package backup

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"testing"
)

type MemoryStore struct{ Records map[string]Record }

func (m MemoryStore) Get(_ context.Context, uid string) (Record, error) {
	r, ok := m.Records[uid]
	if !ok {
		return Record{}, ErrNotFound
	}
	return r, nil
}
func (m MemoryStore) Put(_ context.Context, uid, expected string, r Record) error {
	old, ok := m.Records[uid]
	if (!ok && expected != "") || (ok && (expected == "" || old.Revision != expected)) {
		return ErrConflict
	}
	m.Records[uid] = r
	return nil
}
func (m MemoryStore) Delete(_ context.Context, uid, expected string) error {
	old, ok := m.Records[uid]
	if !ok {
		return ErrNotFound
	}
	if old.Revision != expected {
		return ErrConflict
	}
	delete(m.Records, uid)
	return nil
}

type testWrapper struct{}

func (testWrapper) Wrap(_ context.Context, key, aad []byte) ([]byte, error) {
	a, _ := gcm(bytes.Repeat([]byte{7}, 32))
	n := make([]byte, a.NonceSize())
	rand.Read(n)
	return append(n, a.Seal(nil, n, key, aad)...), nil
}
func (testWrapper) Unwrap(_ context.Context, wrapped, aad []byte) ([]byte, error) {
	a, _ := gcm(bytes.Repeat([]byte{7}, 32))
	return a.Open(nil, wrapped[:a.NonceSize()], wrapped[a.NonceSize():], aad)
}

const valid = `{"schema":1,"aiEnabled":true,"privateWords":["架空企画Sakura"],"review":{"mode":"enterprise","requiredKinds":["privateWord"],"learningEnabled":true,"choices":{"personal:contact:caption":{"hide":3,"keep":0}}}}`

func TestEncryptionRoundTripIsolationAndConflict(t *testing.T) {
	ctx := context.Background()
	store := MemoryStore{map[string]Record{}}
	s := Service{store, testWrapper{}}
	first, e := s.Put(ctx, "user-a", "", []byte(valid))
	if e != nil {
		t.Fatal(e)
	}
	r := store.Records["user-a"]
	if bytes.Contains(r.Ciphertext, []byte("Sakura")) || bytes.Contains(r.WrappedKey, []byte("Sakura")) {
		t.Fatal("plaintext stored")
	}
	restored, e := s.Get(ctx, "user-a")
	if e != nil || string(restored.Payload) != valid {
		t.Fatal("restore failed", e)
	}
	if _, e = s.Get(ctx, "user-b"); e != ErrNotFound {
		t.Fatal("cross-user read")
	}
	store.Records["user-b"] = r
	if _, e = s.Get(ctx, "user-b"); e == nil {
		t.Fatal("AAD did not bind ciphertext to identity")
	}
	if _, e = s.Put(ctx, "user-a", "", []byte(valid)); e != ErrConflict {
		t.Fatal("blind overwrite allowed")
	}
	second, e := s.Put(ctx, "user-a", first.Revision, []byte(valid))
	if e != nil {
		t.Fatal(e)
	}
	if first.Revision == second.Revision || bytes.Equal(r.Ciphertext, store.Records["user-a"].Ciphertext) {
		t.Fatal("revision/key/nonce reused")
	}
	if e = s.Delete(ctx, "user-a", first.Revision); e != ErrConflict {
		t.Fatal("stale delete allowed")
	}
	if e = s.Delete(ctx, "user-a", second.Revision); e != nil {
		t.Fatal(e)
	}
}
func TestRejectTamperingAndForbiddenInput(t *testing.T) {
	ctx := context.Background()
	store := MemoryStore{map[string]Record{}}
	s := Service{store, testWrapper{}}
	s.Put(ctx, "u", "", []byte(valid))
	r := store.Records["u"]
	r.Ciphertext[0] ^= 1
	store.Records["u"] = r
	if _, e := s.Get(ctx, "u"); e == nil {
		t.Fatal("tampered ciphertext accepted")
	}
	var data map[string]any
	json.Unmarshal([]byte(valid), &data)
	data["photo"] = "private-photo"
	extra, _ := json.Marshal(data)
	for _, input := range [][]byte{extra, []byte(valid + "{}"), bytes.Repeat([]byte("x"), MaxPayload+1), []byte(`{"schema":2}`)} {
		if Validate(input) == nil {
			t.Fatal("invalid/forbidden payload accepted")
		}
	}
}
