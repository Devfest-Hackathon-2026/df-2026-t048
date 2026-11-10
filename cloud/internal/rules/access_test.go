package rules_test

import (
	"encoding/json"
	"errors"
	"postcheck/cloud/internal/rules"
	"strings"
	"sync"
	"testing"
	"time"
)

func verifyFacility(t *testing.T, s rules.Service, a rules.Actor, v rules.Venue) {
	t.Helper()
	view, err := s.Access(ctx, a, v.ID)
	if err == nil && view.Role != "unverified" {
		return
	}
	r, err := s.RequestVerification(ctx, a, v.ID)
	if err != nil {
		t.Fatal(err)
	}
	link, err := s.IssueVerification(ctx, operator, r.ID, "https://example.invalid/official", true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.ConsumeLink(ctx, rules.Actor{}, link.Token, true); err != nil {
		t.Fatal(err)
	}
}
func TestUnverifiedFacilityCannotBeSubmitted(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	if _, err := s.Change(ctx, owner, v.ID, v.Version, "submit", nil, "", true); !errors.Is(err, rules.ErrVerificationRequired) {
		t.Fatal(err)
	}
	sameOrg := rules.Actor{UID: "not-owner", Org: owner.Org}
	if _, err := s.Change(ctx, sameOrg, v.ID, v.Version, "save", &p, "", true); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("org alone authorized edit", err)
	}
	r, _ := s.RequestVerification(ctx, owner, v.ID)
	if _, err := s.IssueVerification(ctx, owner, r.ID, "https://example.invalid", true); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("applicant issued proof", err)
	}
	if _, err := s.IssueVerification(ctx, operator, r.ID, "https://example.invalid", false); !errors.Is(err, rules.ErrInvalid) {
		t.Fatal("unchecked official channel", err)
	}
}
func TestVerificationIsBoundSingleUseAndHashOnly(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	r, _ := s.RequestVerification(ctx, owner, v.ID)
	old, _ := s.IssueVerification(ctx, operator, r.ID, "https://example.invalid/official", true)
	link, _ := s.IssueVerification(ctx, operator, r.ID, "https://example.invalid/official", true)
	if _, err := s.PreviewLink(ctx, old.Token); !errors.Is(err, rules.ErrNotFound) {
		t.Fatal("reissued link still works", err)
	}
	st, _, _ := s.Store.Load(ctx)
	b, _ := json.Marshal(st)
	if strings.Contains(string(b), link.Token) {
		t.Fatal("raw token persisted")
	}
	if _, err := s.ConsumeLink(ctx, rules.Actor{}, link.Token, false); !errors.Is(err, rules.ErrInvalid) {
		t.Fatal(err)
	}
	view, err := s.ConsumeLink(ctx, other, link.Token, true)
	if err != nil || view.UID != owner.UID || view.Role != "manager" {
		t.Fatal("proof changed its target", err)
	}
	if _, err = s.ConsumeLink(ctx, rules.Actor{}, link.Token, true); !errors.Is(err, rules.ErrNotFound) {
		t.Fatal("replay", err)
	}
	if _, err = s.Access(ctx, other, v.ID); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("recipient gained target's role", err)
	}
}
func TestScopedInviteRevocationAndNoCreatorBackdoor(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	verifyFacility(t, s, owner, v)
	staff := rules.Actor{UID: "staff", Org: "unrelated"}
	link, _ := s.Invite(ctx, owner, v.ID, "editor")
	if _, err := s.ConsumeLink(ctx, rules.Actor{}, link.Token, true); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("invite accepted without login", err)
	}
	if _, err := s.ConsumeLink(ctx, staff, link.Token, true); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Invite(ctx, staff, v.ID, "manager"); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("editor can invite", err)
	}
	second, _ := s.Create(ctx, owner, p)
	if _, err := s.Change(ctx, staff, second.ID, second.Version, "save", &p, "", false); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("invite applied to another facility", err)
	}
	pendingInvite, _ := s.Invite(ctx, owner, v.ID, "editor")
	promotion, _ := s.Invite(ctx, owner, v.ID, "manager")
	s.ConsumeLink(ctx, staff, promotion.Token, true)
	if _, err := s.Revoke(ctx, staff, v.ID, owner.UID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Change(ctx, owner, v.ID, v.Version, "save", &p, "", false); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("creator bypasses revocation", err)
	}
	if _, err := s.PreviewLink(ctx, pendingInvite.Token); !errors.Is(err, rules.ErrNotFound) {
		t.Fatal("revoked issuer's invite works", err)
	}
	if _, err := s.Revoke(ctx, staff, v.ID, staff.UID); !errors.Is(err, rules.ErrConflict) {
		t.Fatal("last manager removed", err)
	}
}
func TestAccessExpiryAndApprovalRechecksSubmitter(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	verifyFacility(t, s, owner, v)
	staff := rules.Actor{UID: "staff", Org: "staff"}
	invite, _ := s.Invite(ctx, owner, v.ID, "editor")
	s.ConsumeLink(ctx, staff, invite.Token, true)
	pending, err := s.Change(ctx, staff, v.ID, v.Version, "submit", nil, "", true)
	if err != nil {
		t.Fatal(err)
	}
	s.Revoke(ctx, owner, v.ID, staff.UID)
	if _, err = s.Change(ctx, operator, v.ID, pending.Version, "approve", nil, "", false); !errors.Is(err, rules.ErrVerificationRequired) {
		t.Fatal("approved revoked submitter", err)
	}
	invite, _ = s.Invite(ctx, owner, v.ID, "editor")
	base := s.Now()
	s.Now = func() time.Time { return base.Add(24 * time.Hour) }
	if _, err = s.PreviewLink(ctx, invite.Token); !errors.Is(err, rules.ErrNotFound) {
		t.Fatal("link valid at expiry", err)
	}
	s.Now = func() time.Time { return base.Add(90 * 24 * time.Hour) }
	if _, err = s.Change(ctx, owner, v.ID, pending.Version, "withdraw", nil, "", true); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("expired creator edited", err)
	}
}
func TestConcurrentInvitationOnlyOneRedemption(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	verifyFacility(t, s, owner, v)
	link, _ := s.Invite(ctx, owner, v.ID, "editor")
	var wg sync.WaitGroup
	var mu sync.Mutex
	success := 0
	for i := range 8 {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			_, err := s.ConsumeLink(ctx, rules.Actor{UID: strings.Repeat("x", n+1)}, link.Token, true)
			if err == nil {
				mu.Lock()
				success++
				mu.Unlock()
			}
		}(i)
	}
	wg.Wait()
	if success != 1 {
		t.Fatal("non-atomic redemption", success)
	}
}
func TestLegacyContactPurgePreservesRules(t *testing.T) {
	s, p := fixture(t)
	v, _ := s.Create(ctx, owner, p)
	st, rev, _ := s.Store.Load(ctx)
	st.Venues[0].Draft.Contact = "legacy-person@example.invalid"
	published := p
	st.Venues[0].Published = &published
	s.Store.Save(ctx, rev, st)
	if err := s.PurgeLegacyContacts(ctx); err != nil {
		t.Fatal(err)
	}
	st, rev, _ = s.Store.Load(ctx)
	if st.Venues[0].Draft.Contact != "" || st.Venues[0].Published.Contact != "" || st.Venues[0].Draft.Name != v.Draft.Name {
		t.Fatal("cleanup changed rules or retained contacts")
	}
	s.PurgeLegacyContacts(ctx)
	_, next, _ := s.Store.Load(ctx)
	if next != rev {
		t.Fatal("cleanup is not idempotent")
	}
}
