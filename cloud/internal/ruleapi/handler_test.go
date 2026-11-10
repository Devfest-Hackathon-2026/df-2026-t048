package ruleapi_test

import (
	"context"
	"errors"
	"net/http/httptest"
	"path/filepath"
	"postcheck/cloud/internal/ruleapi"
	"postcheck/cloud/internal/rules"
	"postcheck/cloud/internal/rulestore"
	"strings"
	"testing"
)

type identity struct{}

func (identity) VerifyActor(_ context.Context, s string) (rules.Actor, error) {
	if s == "valid" {
		return rules.Actor{UID: "u", Org: "u"}, nil
	}
	return rules.Actor{}, errors.New("invalid")
}
func TestHTTPRejectsUnauthenticatedAndExtraPayload(t *testing.T) {
	h := ruleapi.Handler{Service: rules.Service{Store: &rulestore.FileStore{Path: filepath.Join(t.TempDir(), "state")}}, Identity: identity{}}
	cases := []struct {
		method, path, token, body string
		code                      int
	}{{"GET", "/v1/venues", "", "", 200}, {"GET", "/v1/admin/venues", "", "", 403}, {"POST", "/v1/admin/venues", "", "{}", 401}, {"GET", "/v1/venues", "bad", "", 401}, {"POST", "/v1/admin/venues", "valid", `{"photo":"private"}`, 400}, {"POST", "/v1/admin/venues", "valid", `{} {}`, 400}}
	for _, c := range cases {
		r := httptest.NewRequest(c.method, c.path, strings.NewReader(c.body))
		r.Header.Set("Content-Type", "application/json")
		if c.token != "" {
			r.Header.Set("Authorization", "Bearer "+c.token)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != c.code {
			t.Fatalf("%s %s: %d want %d", c.method, c.path, w.Code, c.code)
		}
	}
}
