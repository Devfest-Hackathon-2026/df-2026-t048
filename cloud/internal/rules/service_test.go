package rules_test

import (
	"context"
	"errors"
	"path/filepath"
	"postcheck/cloud/internal/rules"
	"postcheck/cloud/internal/rulestore"
	"testing"
	"time"
)

var ctx = context.Background()
var owner = rules.Actor{UID: "owner", Org: "org-a"}
var other = rules.Actor{UID: "other", Org: "org-b"}
var operator = rules.Actor{UID: "reviewer", Org: "operations", Operator: true}

func fixture(t *testing.T) (rules.Service, rules.Policy) {
	t.Helper()
	return rules.Service{Store: &rulestore.FileStore{Path: filepath.Join(t.TempDir(), "state.json")}, Now: func() time.Time { return time.Date(2026, 11, 8, 0, 0, 0, 0, time.UTC) }}, rules.Policy{Name: "架空施設", ApplicationName: "架空のルール申請", Address: "架空住所", Website: "https://example.org", Contact: "fiction@example.org", Latitude: 35, Longitude: 139, Photography: "conditional", Publication: "conditional", Commercial: "unknown", Words: []string{"架空ワード"}, SourceURL: "https://example.org/rules", SourceText: "架空の撮影ルール", Visibility: "public"}
}
func change(t *testing.T, s rules.Service, a rules.Actor, v rules.Venue, action string, p *rules.Policy) rules.Venue {
	t.Helper()
	if action == "submit" {
		verifyFacility(t, s, a, v)
	}
	next, e := s.Change(ctx, a, v.ID, v.Version, action, p, "修正してください", true)
	if e != nil {
		t.Fatal(action, e)
	}
	return next
}
func public(t *testing.T, s rules.Service, a rules.Actor) []rules.PublicVenue {
	t.Helper()
	list, e := s.List(ctx, a, false)
	if e != nil {
		t.Fatal(e)
	}
	return list.([]rules.PublicVenue)
}
func TestPublicationLifecycleAndSnapshotIsolation(t *testing.T) {
	s, p := fixture(t)
	v, e := s.Create(ctx, owner, p)
	if e != nil {
		t.Fatal(e)
	}
	if len(public(t, s, rules.Actor{})) != 0 {
		t.Fatal("draft leaked")
	}
	v = change(t, s, owner, v, "submit", nil)
	if _, e = s.Change(ctx, owner, v.ID, v.Version, "save", &p, "", true); !errors.Is(e, rules.ErrConflict) {
		t.Fatal("pending mutable", e)
	}
	if _, e = s.Change(ctx, owner, v.ID, v.Version, "approve", nil, "", true); !errors.Is(e, rules.ErrForbidden) {
		t.Fatal("self approval", e)
	}
	v = change(t, s, operator, v, "approve", nil)
	published := public(t, s, rules.Actor{})
	if len(published) != 1 || published[0].Policy.Contact != "" {
		t.Fatal("public projection leaked")
	}
	p.Name = "変更申請中の名称"
	v = change(t, s, owner, v, "save", &p)
	v = change(t, s, owner, v, "submit", nil)
	if public(t, s, rules.Actor{})[0].Policy.Name == p.Name {
		t.Fatal("draft changed published snapshot")
	}
	if _, e = s.Change(ctx, operator, v.ID, v.Version-1, "approve", nil, "", true); !errors.Is(e, rules.ErrConflict) {
		t.Fatal("stale approval", e)
	}
	v = change(t, s, operator, v, "return", nil)
	v = change(t, s, owner, v, "submit", nil)
	v = change(t, s, operator, v, "approve", nil)
	if public(t, s, rules.Actor{})[0].Policy.Name != p.Name {
		t.Fatal("publication failed")
	}
	change(t, s, operator, v, "suspend", nil)
	if len(public(t, s, rules.Actor{})) != 0 {
		t.Fatal("suspended published")
	}
}
func TestOrganizationIsolationAndAcknowledgement(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	verifyFacility(t, s, owner, v)
	if _, e := s.Change(ctx, other, v.ID, v.Version, "save", &p, "", true); !errors.Is(e, rules.ErrForbidden) {
		t.Fatal(e)
	}
	verifyFacility(t, s, owner, v)
	if _, e := s.Change(ctx, owner, v.ID, v.Version, "submit", nil, "", false); !errors.Is(e, rules.ErrInvalid) {
		t.Fatal("public acknowledgement missing")
	}
	p.Visibility = "organization"
	v = change(t, s, owner, v, "save", &p)
	v = change(t, s, owner, v, "submit", nil)
	v = change(t, s, operator, v, "approve", nil)
	if len(public(t, s, other)) != 0 || len(public(t, s, rules.Actor{})) != 0 || len(public(t, s, owner)) != 1 {
		t.Fatal("organization visibility broken")
	}
	list, e := s.List(ctx, other, true)
	if e != nil || len(list.([]rules.Venue)) != 0 {
		t.Fatal("other organization draft leaked")
	}
}
func TestOperatorListHidesDrafts(t *testing.T) {
	s, p := fixture(t)
	draft, e := s.Create(ctx, owner, p)
	if e != nil {
		t.Fatal(e)
	}
	opList, e := s.List(ctx, operator, true)
	if e != nil {
		t.Fatal(e)
	}
	for _, v := range opList.([]rules.Venue) {
		if v.ID == draft.ID || v.Status == "draft" {
			t.Fatal("operator saw unpublished draft")
		}
	}
	ownerList, e := s.List(ctx, owner, true)
	if e != nil || len(ownerList.([]rules.Venue)) != 1 {
		t.Fatal("owner should still see own draft")
	}
	pending := change(t, s, owner, draft, "submit", nil)
	pending = change(t, s, operator, pending, "approve", nil)
	p.Name = "再編集中の下書き"
	reedit := change(t, s, owner, pending, "save", &p)
	if reedit.Status != "draft" {
		t.Fatal("expected draft after save")
	}
	opList, e = s.List(ctx, operator, true)
	if e != nil {
		t.Fatal(e)
	}
	if len(opList.([]rules.Venue)) != 1 {
		t.Fatal("operator should still see published venue while re-editing")
	}
	seen := opList.([]rules.Venue)[0]
	if seen.Status != "published" || seen.Draft.Name != "架空施設" {
		t.Fatal("operator must see published snapshot, not draft", seen.Status, seen.Draft.Name)
	}
}
func TestExpiryInvalidURLAndStoreCAS(t *testing.T) {
	s, p := fixture(t)
	p.SourceURL = "http://127.0.0.1/private"
	if rules.Validate(p, true) == nil {
		t.Fatal("unsafe source")
	}
	p.SourceURL = "https://example.org/rules"
	until := s.Now().Add(-time.Hour)
	p.ValidUntil = &until
	v, _ := s.Create(ctx, owner, p)
	if _, e := s.Change(ctx, owner, v.ID, v.Version, "submit", nil, "", true); e == nil {
		t.Fatal("expired submitted")
	}
	st, r, e := s.Store.Load(ctx)
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Store.Save(ctx, r, st); e != nil {
		t.Fatal(e)
	}
	if e = s.Store.Save(ctx, r, st); !errors.Is(e, rules.ErrConflict) {
		t.Fatal("lost update")
	}
}
