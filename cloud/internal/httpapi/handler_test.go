package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"postcheck/cloud/internal/backup"
	"strings"
	"testing"
)

type identity struct{}

func (identity) Verify(_ context.Context, t string) (string, error) {
	if t == "valid-token" {
		return "owner", nil
	}
	return "", errors.New("rejected")
}

type store struct {
	called bool
	uid    string
}

func (s *store) Get(_ context.Context, u string) (backup.Record, error) {
	s.called = true
	s.uid = u
	return backup.Record{}, backup.ErrNotFound
}
func (s *store) Put(context.Context, string, string, backup.Record) error { return nil }
func (s *store) Delete(_ context.Context, u, v string) error {
	s.called = true
	s.uid = u
	return backup.ErrConflict
}
func TestAuthOwnerAndHTTPPreconditions(t *testing.T) {
	for _, test := range []struct {
		method, path, token, version string
		status                       int
	}{
		{"GET", "/v1/backup", "", "", 401}, {"GET", "/v1/backup", "invalid", "", 401},
		{"GET", "/v1/backup", "valid-token", "", 404},
		{"PUT", "/v1/backup", "valid-token", "", 428},
		{"DELETE", "/v1/backup", "valid-token", "", 428},
		{"DELETE", "/v1/backup", "valid-token", "old", 409},
		{"GET", "/v1/backup/other-user", "valid-token", "", 404},
	} {
		t.Run(test.method+test.path+test.token+test.version, func(t *testing.T) {
			st := &store{}
			h := Handler{Service: backup.Service{Store: st}, Identity: identity{}}
			req := httptest.NewRequest(test.method, test.path, strings.NewReader(`{}`))
			req.Header.Set("Content-Type", "application/json")
			if test.token != "" {
				req.Header.Set("Authorization", "Bearer "+test.token)
			}
			if test.version != "" {
				req.Header.Set("If-Match", test.version)
			}
			out := httptest.NewRecorder()
			h.ServeHTTP(out, req)
			if out.Code != test.status {
				t.Fatalf("got %d want %d", out.Code, test.status)
			}
			if st.called && st.uid != "owner" {
				t.Fatal("caller controlled user id")
			}
			if test.status == http.StatusUnauthorized && st.called {
				t.Fatal("unauthenticated access reached storage")
			}
			if out.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("response cache enabled")
			}
		})
	}
}
