package rules_test

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"image"
	"image/png"
	"postcheck/cloud/internal/rules"
	"strings"
	"testing"
)

func proofImage(t *testing.T) string {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(b.Bytes())
}

func TestOperatorCannotActAsApplicant(t *testing.T) {
	s, p := fixture(t)
	if _, err := s.Create(ctx, operator, p); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("operator created application", err)
	}
	v, err := s.Create(ctx, owner, p)
	if err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"save", "submit"} {
		if _, err = s.Change(ctx, operator, v.ID, v.Version, action, &p, "", true); !errors.Is(err, rules.ErrForbidden) {
			t.Fatal(action, err)
		}
	}
	v = change(t, s, owner, v, "submit", nil)
	if _, err = s.Change(ctx, operator, v.ID, v.Version, "withdraw", nil, "", true); !errors.Is(err, rules.ErrForbidden) {
		t.Fatal("operator withdrew application", err)
	}
	// The same operator can still perform its intended review operation.
	change(t, s, operator, v, "approve", nil)
}

func TestPrivateProofImageNeverReachesPublicAPI(t *testing.T) {
	s, p := fixture(t)
	p.SourceImage = proofImage(t)
	p.SourceURL = ""
	v, err := s.Create(ctx, owner, p)
	if err != nil {
		t.Fatal(err)
	}
	v = change(t, s, owner, v, "submit", nil)
	managed, err := s.List(ctx, operator, true)
	if err != nil {
		t.Fatal(err)
	}
	if managed.([]rules.Venue)[0].Draft.SourceImage != p.SourceImage {
		t.Fatal("operator lost evidence")
	}
	change(t, s, operator, v, "approve", nil)
	out := public(t, s, rules.Actor{})
	data, err := json.Marshal(out)
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"sourceImage", "contact", "applicationName"} {
		if strings.Contains(string(data), `"`+field+`"`) {
			t.Fatal("private field exposed:", field)
		}
	}
	if out[0].Policy.SourceText != p.SourceText {
		t.Fatal("public evidence text missing")
	}
	// Redacting the public response must not mutate the saved private snapshot.
	managed, err = s.List(ctx, operator, true)
	if err != nil {
		t.Fatal(err)
	}
	if managed.([]rules.Venue)[0].Published.SourceImage != p.SourceImage {
		t.Fatal("stored proof was erased")
	}
}

func TestProofImageValidationAndReferenceRequirement(t *testing.T) {
	_, p := fixture(t)
	p.SourceURL = ""
	p.SourceImage = proofImage(t)
	if err := rules.Validate(p, true); err != nil {
		t.Fatal(err)
	}
	for _, raw := range []string{"", "data:image/png;base64,invalid", "data:image/svg+xml;base64,PHN2Zz4=", "data:image/jpeg;base64," + strings.TrimPrefix(p.SourceImage, "data:image/png;base64,")} {
		bad := p
		bad.SourceImage = raw
		if rules.Validate(bad, true) == nil {
			t.Fatal("accepted missing or invalid proof")
		}
	}
	// A legacy application without a separate title remains reviewable.
	p.SourceURL = "https://example.invalid/rules"
	p.SourceImage = ""
	p.ApplicationName = ""
	if err := rules.Validate(p, true); err != nil {
		t.Fatal("legacy policy rejected", err)
	}
}
