// Package backup contains the application logic; it has no Google SDK dependencies.
package backup

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"time"
)

var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("version conflict")
var ErrInvalid = errors.New("invalid settings")

const MaxPayload = 128 * 1024

type Record struct {
	Ciphertext []byte    `firestore:"ciphertext"`
	Nonce      []byte    `firestore:"nonce"`
	WrappedKey []byte    `firestore:"wrappedKey"`
	Revision   string    `firestore:"revision"`
	UpdatedAt  time.Time `firestore:"updatedAt"`
	Schema     int       `firestore:"schema"`
}
type Store interface {
	Get(context.Context, string) (Record, error)
	Put(context.Context, string, string, Record) error
	Delete(context.Context, string, string) error
}
type KeyWrapper interface {
	Wrap(context.Context, []byte, []byte) ([]byte, error)
	Unwrap(context.Context, []byte, []byte) ([]byte, error)
}
type Service struct {
	Store Store
	Keys  KeyWrapper
}
type Snapshot struct {
	Payload   json.RawMessage `json:"payload"`
	Revision  string          `json:"revision"`
	UpdatedAt time.Time       `json:"updatedAt"`
}

func aad(uid string) []byte { return []byte("postcheck:settings:v1:" + uid) }
func gcm(key []byte) (cipher.AEAD, error) {
	b, e := aes.NewCipher(key)
	if e != nil {
		return nil, e
	}
	return cipher.NewGCM(b)
}
func (s Service) Get(ctx context.Context, uid string) (Snapshot, error) {
	r, e := s.Store.Get(ctx, uid)
	if e != nil {
		return Snapshot{}, e
	}
	if r.Schema != 1 {
		return Snapshot{}, ErrInvalid
	}
	key, e := s.Keys.Unwrap(ctx, r.WrappedKey, aad(uid))
	if e != nil {
		return Snapshot{}, e
	}
	defer clear(key)
	a, e := gcm(key)
	if e != nil {
		return Snapshot{}, e
	}
	if len(r.Nonce) != a.NonceSize() {
		return Snapshot{}, ErrInvalid
	}
	plain, e := a.Open(nil, r.Nonce, r.Ciphertext, aad(uid))
	if e != nil {
		return Snapshot{}, e
	}
	if e = Validate(plain); e != nil {
		return Snapshot{}, e
	}
	return Snapshot{plain, r.Revision, r.UpdatedAt}, nil
}
func (s Service) Put(ctx context.Context, uid, expected string, payload []byte) (Snapshot, error) {
	if e := Validate(payload); e != nil {
		return Snapshot{}, e
	}
	key := make([]byte, 32)
	if _, e := rand.Read(key); e != nil {
		return Snapshot{}, e
	}
	defer clear(key)
	a, e := gcm(key)
	if e != nil {
		return Snapshot{}, e
	}
	nonce := make([]byte, a.NonceSize())
	if _, e = rand.Read(nonce); e != nil {
		return Snapshot{}, e
	}
	wrapped, e := s.Keys.Wrap(ctx, key, aad(uid))
	if e != nil {
		return Snapshot{}, e
	}
	version := make([]byte, 16)
	if _, e = rand.Read(version); e != nil {
		return Snapshot{}, e
	}
	r := Record{Ciphertext: a.Seal(nil, nonce, payload, aad(uid)), Nonce: nonce, WrappedKey: wrapped, Revision: hex.EncodeToString(version), UpdatedAt: time.Now().UTC(), Schema: 1}
	if e = s.Store.Put(ctx, uid, expected, r); e != nil {
		return Snapshot{}, e
	}
	return Snapshot{Revision: r.Revision, UpdatedAt: r.UpdatedAt}, nil
}
func (s Service) Delete(ctx context.Context, uid, expected string) error {
	return s.Store.Delete(ctx, uid, expected)
}

type Count struct {
	Hide int `json:"hide"`
	Keep int `json:"keep"`
}
type Review struct {
	Mode            string           `json:"mode"`
	RequiredKinds   []string         `json:"requiredKinds"`
	LearningEnabled *bool            `json:"learningEnabled"`
	Choices         map[string]Count `json:"choices"`
}
type Settings struct {
	Schema       int      `json:"schema"`
	AIEnabled    *bool    `json:"aiEnabled"`
	PrivateWords []string `json:"privateWords"`
	Review       Review   `json:"review"`
}

func Validate(payload []byte) error {
	if len(payload) > MaxPayload {
		return ErrInvalid
	}
	var data Settings
	d := json.NewDecoder(bytes.NewReader(payload))
	d.DisallowUnknownFields()
	if d.Decode(&data) != nil {
		return ErrInvalid
	}
	if d.Decode(new(any)) != io.EOF {
		return ErrInvalid
	}
	if data.Schema != 1 || data.AIEnabled == nil || data.PrivateWords == nil || len(data.PrivateWords) > 500 || data.Review.LearningEnabled == nil || data.Review.RequiredKinds == nil || data.Review.Choices == nil {
		return ErrInvalid
	}
	if data.Review.Mode != "personal" && data.Review.Mode != "enterprise" {
		return ErrInvalid
	}
	kinds := map[string]bool{"contact": true, "imageText": true, "face": true, "announcement": true, "privateWord": true, "context": true}
	for _, w := range data.PrivateWords {
		if strings.TrimSpace(w) == "" || len([]rune(w)) > 200 {
			return ErrInvalid
		}
	}
	if len(data.Review.RequiredKinds) > 6 || len(data.Review.Choices) > 100 {
		return ErrInvalid
	}
	for _, k := range data.Review.RequiredKinds {
		if !kinds[k] {
			return ErrInvalid
		}
	}
	for key, c := range data.Review.Choices {
		parts := strings.Split(key, ":")
		if len(parts) != 3 || !(parts[0] == "personal" || parts[0] == "enterprise") || !kinds[parts[1]] || !(parts[2] == "photo" || parts[2] == "caption" || parts[2] == "whole") || c.Hide < 0 || c.Keep < 0 || c.Hide > 1000000 || c.Keep > 1000000 || c.Hide+c.Keep > 1000000 {
			return ErrInvalid
		}
	}
	return nil
}
