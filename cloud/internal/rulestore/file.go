// FileStore is for loopback-only demos. It never backs the production server.
package rulestore

import (
	"context"
	"encoding/json"
	"os"
	"postcheck/cloud/internal/rules"
	"strconv"
	"sync"
)

type FileStore struct {
	Path string
	mu   sync.Mutex
}
type snapshot struct {
	Revision int         `json:"revision"`
	State    rules.State `json:"state"`
}

func (s *FileStore) read() (snapshot, error) {
	var v snapshot
	b, e := os.ReadFile(s.Path)
	if os.IsNotExist(e) {
		return v, nil
	}
	if e != nil {
		return v, e
	}
	e = json.Unmarshal(b, &v)
	return v, e
}
func (s *FileStore) Load(_ context.Context) (rules.State, string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	v, e := s.read()
	return v.State, strconv.Itoa(v.Revision), e
}
func (s *FileStore) Save(_ context.Context, expected string, st rules.State) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	v, e := s.read()
	if e != nil {
		return e
	}
	if strconv.Itoa(v.Revision) != expected {
		return rules.ErrConflict
	}
	b, e := json.Marshal(snapshot{v.Revision + 1, st})
	if e != nil {
		return e
	}
	if e = os.WriteFile(s.Path+".tmp", b, 0600); e != nil {
		return e
	}
	return os.Rename(s.Path+".tmp", s.Path)
}
