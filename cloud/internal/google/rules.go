package google

import (
	"cloud.google.com/go/firestore"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"postcheck/cloud/internal/backup"
	"postcheck/cloud/internal/rules"
	"time"
)

// Membership documents can only be provisioned by server administrators.
// A new applicant owns a personal organization namespace but no existing venues.
func (a Identity) VerifyActor(ctx context.Context, token string) (rules.Actor, error) {
	uid, e := a.Verify(ctx, token)
	if e != nil {
		return rules.Actor{}, e
	}
	actor := rules.Actor{UID: uid, Org: uid}
	if a.RulesDB == nil {
		return rules.Actor{}, errors.New("missing membership store")
	}
	doc, e := a.RulesDB.Collection("ruleMembers").Doc(uid).Get(ctx)
	if status.Code(e) == codes.NotFound {
		return actor, nil
	}
	if e != nil {
		return rules.Actor{}, e
	}
	var m struct {
		Org      string `firestore:"org"`
		Operator bool   `firestore:"operator"`
	}
	if e = doc.DataTo(&m); e != nil {
		return rules.Actor{}, e
	}
	if m.Org != "" {
		actor.Org = m.Org
	}
	actor.Operator = m.Operator
	return actor, nil
}

type RuleStore struct {
	Client *firestore.Client
	Keys   backup.KeyWrapper
}

var ruleAAD = []byte("postcheck:rules:registry:v1")

func (s RuleStore) ref() *firestore.DocumentRef { return s.Client.Collection("ruleRegistry").Doc("v1") }
func (s RuleStore) Load(ctx context.Context) (rules.State, string, error) {
	doc, e := s.ref().Get(ctx)
	if status.Code(e) == codes.NotFound {
		return rules.State{}, "", nil
	}
	if e != nil {
		return rules.State{}, "", e
	}
	var r backup.Record
	if e = doc.DataTo(&r); e != nil {
		return rules.State{}, "", e
	}
	if r.Schema != 1 {
		return rules.State{}, "", rules.ErrInvalid
	}
	key, e := s.Keys.Unwrap(ctx, r.WrappedKey, ruleAAD)
	if e != nil {
		return rules.State{}, "", e
	}
	defer clear(key)
	block, e := aes.NewCipher(key)
	if e != nil {
		return rules.State{}, "", e
	}
	a, e := cipher.NewGCM(block)
	if e != nil || len(r.Nonce) != a.NonceSize() {
		return rules.State{}, "", rules.ErrInvalid
	}
	plain, e := a.Open(nil, r.Nonce, r.Ciphertext, ruleAAD)
	if e != nil {
		return rules.State{}, "", e
	}
	defer clear(plain)
	var st rules.State
	e = json.Unmarshal(plain, &st)
	return st, r.Revision, e
}
func (s RuleStore) Save(ctx context.Context, expected string, st rules.State) error {
	plain, e := json.Marshal(st)
	if e != nil {
		return e
	}
	defer clear(plain)
	if len(plain) > 700000 {
		return rules.ErrInvalid
	}
	key := make([]byte, 32)
	if _, e = rand.Read(key); e != nil {
		return e
	}
	defer clear(key)
	block, e := aes.NewCipher(key)
	if e != nil {
		return e
	}
	a, e := cipher.NewGCM(block)
	if e != nil {
		return e
	}
	nonce := make([]byte, a.NonceSize())
	if _, e = rand.Read(nonce); e != nil {
		return e
	}
	wrapped, e := s.Keys.Wrap(ctx, key, ruleAAD)
	if e != nil {
		return e
	}
	version := make([]byte, 16)
	if _, e = rand.Read(version); e != nil {
		return e
	}
	record := backup.Record{Ciphertext: a.Seal(nil, nonce, plain, ruleAAD), Nonce: nonce, WrappedKey: wrapped, Revision: hex.EncodeToString(version), UpdatedAt: time.Now().UTC(), Schema: 1}
	return s.Client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, e := tx.Get(s.ref())
		if status.Code(e) == codes.NotFound {
			if expected != "" {
				return rules.ErrConflict
			}
			return tx.Create(s.ref(), record)
		}
		if e != nil {
			return e
		}
		var previous backup.Record
		if e = doc.DataTo(&previous); e != nil {
			return e
		}
		if previous.Revision != expected {
			return rules.ErrConflict
		}
		return tx.Set(s.ref(), record)
	})
}
