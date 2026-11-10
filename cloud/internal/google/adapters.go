package google

import (
	"cloud.google.com/go/firestore"
	kms "cloud.google.com/go/kms/apiv1"
	"cloud.google.com/go/kms/apiv1/kmspb"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"postcheck/cloud/internal/backup"
)

type Identity struct {
	Client  *auth.Client
	RulesDB *firestore.Client
}

func (a Identity) Verify(ctx context.Context, token string) (string, error) {
	t, e := a.Client.VerifyIDTokenAndCheckRevoked(ctx, token)
	if e != nil {
		return "", e
	}
	p := t.Firebase.SignInProvider
	if p != "google.com" && p != "apple.com" {
		return "", errors.New("unsupported provider")
	}
	return t.UID, nil
}

type Keys struct {
	Client *kms.KeyManagementClient
	Name   string
}

func (k Keys) Wrap(ctx context.Context, key, aad []byte) ([]byte, error) {
	r, e := k.Client.Encrypt(ctx, &kmspb.EncryptRequest{Name: k.Name, Plaintext: key, AdditionalAuthenticatedData: aad})
	if e != nil {
		return nil, e
	}
	return r.Ciphertext, nil
}
func (k Keys) Unwrap(ctx context.Context, key, aad []byte) ([]byte, error) {
	r, e := k.Client.Decrypt(ctx, &kmspb.DecryptRequest{Name: k.Name, Ciphertext: key, AdditionalAuthenticatedData: aad})
	if e != nil {
		return nil, e
	}
	return r.Plaintext, nil
}

type Store struct{ Client *firestore.Client }

func (s Store) ref(uid string) *firestore.DocumentRef {
	sum := sha256.Sum256([]byte(uid))
	return s.Client.Collection("settingsBackups").Doc(hex.EncodeToString(sum[:]))
}
func (s Store) Get(ctx context.Context, uid string) (backup.Record, error) {
	snap, e := s.ref(uid).Get(ctx)
	if status.Code(e) == codes.NotFound {
		return backup.Record{}, backup.ErrNotFound
	}
	if e != nil {
		return backup.Record{}, e
	}
	var r backup.Record
	e = snap.DataTo(&r)
	return r, e
}
func (s Store) Put(ctx context.Context, uid, expected string, r backup.Record) error {
	return s.Client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		ref := s.ref(uid)
		snap, e := tx.Get(ref)
		if status.Code(e) == codes.NotFound {
			if expected != "" {
				return backup.ErrConflict
			}
			return tx.Create(ref, r)
		}
		if e != nil {
			return e
		}
		var old backup.Record
		if e = snap.DataTo(&old); e != nil {
			return e
		}
		if expected == "" || old.Revision != expected {
			return backup.ErrConflict
		}
		return tx.Set(ref, r)
	})
}
func (s Store) Delete(ctx context.Context, uid, expected string) error {
	return s.Client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		ref := s.ref(uid)
		snap, e := tx.Get(ref)
		if status.Code(e) == codes.NotFound {
			return backup.ErrNotFound
		}
		if e != nil {
			return e
		}
		var old backup.Record
		if e = snap.DataTo(&old); e != nil {
			return e
		}
		if old.Revision != expected {
			return backup.ErrConflict
		}
		return tx.Delete(ref)
	})
}
