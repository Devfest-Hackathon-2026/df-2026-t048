package ruleapi_test

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"postcheck/cloud/internal/ruleapi"
	"postcheck/cloud/internal/rules"
	"postcheck/cloud/internal/rulestore"
	"strings"
	"testing"
)

func TestAccessHTTPBoundaries(t *testing.T) {
	s := rules.Service{Store: &rulestore.FileStore{Path: filepath.Join(t.TempDir(), "state")}}
	h := ruleapi.Handler{Service: s, Identity: identity{}}
	ctx := context.Background()
	a := rules.Actor{UID: "u", Org: "u"}
	v, e := s.Create(ctx, a, rules.Policy{Name: "Synthetic venue", Photography: "unknown", Publication: "unknown", Commercial: "unknown", Visibility: "public"})
	if e != nil {
		t.Fatal(e)
	}
	req, e := s.RequestVerification(ctx, a, v.ID)
	if e != nil {
		t.Fatal(e)
	}
	link, e := s.IssueVerification(ctx, rules.Actor{UID: "op", Operator: true}, req.ID, "https://example.invalid", true)
	if e != nil {
		t.Fatal(e)
	}
	call := func(path, token, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("POST", path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("Referrer-Policy") != "no-referrer" {
			t.Fatal("missing privacy headers")
		}
		return w
	}
	for _, c := range []struct {
		path, token, body string
		code              int
	}{
		{"/v1/access/requests", "", "{}", 401},
		{"/v1/access/requests/" + req.ID + "/issue", "valid", `{"confirmed":true,"officialSourceUrl":"https://example.invalid"}`, 403},
		{"/v1/access/requests", "valid", `{"venueId":"` + v.ID + `","email":"not-collected@example.invalid"}`, 400},
		{"/v1/access/consume", "", `{"token":"` + link.Token + `","confirmed":true,"targetUid":"attacker"}`, 400},
		{"/v1/access/consume", "", `{"token":"` + link.Token + `","confirmed":false}`, 400},
		{"/v1/access/preview", "", `{"token":"invalid"}`, 404},
		{"/v1/access/preview", "", `{} {}`, 400},
	} {
		if w := call(c.path, c.token, c.body); w.Code != c.code {
			t.Fatalf("%s: got %d want %d", c.path, w.Code, c.code)
		}
	}
	body := `{"token":"` + link.Token + `","confirmed":true}`
	if w := call("/v1/access/preview", "", body); w.Code != 200 {
		t.Fatalf("preview %d", w.Code)
	}
	w := call("/v1/access/consume", "", body)
	if w.Code != 200 {
		t.Fatalf("consume %d", w.Code)
	}
	var access rules.AccessView
	if json.Unmarshal(w.Body.Bytes(), &access) != nil || access.UID != "u" || access.Role != "manager" {
		t.Fatal("target binding")
	}
	if w := call("/v1/access/consume", "", body); w.Code != 404 {
		t.Fatal("replay accepted")
	}
	invite, e := s.Invite(ctx, a, v.ID, "editor")
	if e != nil {
		t.Fatal(e)
	}
	if w := call("/v1/access/consume", "", `{"token":"`+invite.Token+`","confirmed":true}`); w.Code != 403 {
		t.Fatalf("anonymous invite %d", w.Code)
	}
	r := httptest.NewRequest("GET", "/v1/access/requests", nil)
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 401 {
		t.Fatal("anonymous requests exposed")
	}
}
