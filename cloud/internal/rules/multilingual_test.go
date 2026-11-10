package rules_test

import (
	"encoding/json"
	"errors"
	"os"
	"postcheck/cloud/internal/rules"
	"strings"
	"testing"
)

func TestMultilingualDigestContract(t *testing.T) {
	raw, err := os.ReadFile("../../../packages/postcheck_rules/testdata/multilingual_policy.json")
	if err != nil {
		t.Fatal(err)
	}
	var vector struct {
		Policy            rules.Policy `json:"policy"`
		RulesDigest       string       `json:"rulesDigest"`
		TranslationDigest string       `json:"translationDigest"`
	}
	if err = json.Unmarshal(raw, &vector); err != nil {
		t.Fatal(err)
	}
	if vector.Policy.RulesDigest() != vector.RulesDigest ||
		vector.Policy.TranslationDigest("en", vector.Policy.Translations["en"]) != vector.TranslationDigest {
		t.Fatal("Dart/Go translation review contract differs")
	}
}

func TestOnlyReviewedCurrentTranslationsArePublished(t *testing.T) {
	s, p := fixture(t)
	p.AreaKind = "lobby"
	p.Area = "1階"
	p.Conditions = []string{"noFlash"}
	en := rules.RuleTranslation{Text: "First-floor lobby. No flash.", Area: "First floor"}
	en.ReviewedDigest = p.TranslationDigest("en", en)
	p.Translations = map[string]rules.RuleTranslation{"en": en, "ko": {Text: "검토 전 초안"}}
	v, err := s.Create(ctx, owner, p)
	if err != nil {
		t.Fatal(err)
	}
	v = change(t, s, owner, v, "submit", nil)
	v = change(t, s, operator, v, "approve", nil)
	out := public(t, s, rules.Actor{})[0].Policy
	if len(out.Translations) != 1 || out.Translations["en"].Text != en.Text {
		t.Fatal("reviewed translation lost or draft leaked")
	}
	p.SourceText = "新しい条件。再確認が必要。"
	v = change(t, s, owner, v, "save", &p)
	if public(t, s, rules.Actor{})[0].Policy.Translations["en"].Text != en.Text {
		t.Fatal("draft changed live translation")
	}
	v = change(t, s, owner, v, "submit", nil)
	v = change(t, s, operator, v, "approve", nil)
	if len(public(t, s, rules.Actor{})[0].Policy.Translations) != 0 {
		t.Fatal("outdated translation remained reviewed")
	}
	en.Text = "Updated rule, no flash."
	en.ReviewedDigest = p.TranslationDigest("en", en)
	p.Translations["en"] = en
	v = change(t, s, owner, v, "save", &p)
	v = change(t, s, owner, v, "submit", nil)
	v = change(t, s, operator, v, "approve", nil)
	if len(public(t, s, rules.Actor{})[0].Policy.Translations) != 1 {
		t.Fatal("review did not restore translation")
	}
	en.Text = "Edited without review"
	p.Translations["en"] = en
	v = change(t, s, owner, v, "save", &p)
	v = change(t, s, owner, v, "submit", nil)
	change(t, s, operator, v, "approve", nil)
	if len(public(t, s, rules.Actor{})[0].Policy.Translations) != 0 {
		t.Fatal("changed translation reused an old review")
	}
}

func TestMultilingualValidation(t *testing.T) {
	_, p := fixture(t)
	bads := []func(*rules.Policy){
		func(p *rules.Policy) { p.Conditions = []string{"inventedPermission"} },
		func(p *rules.Policy) { p.Conditions = []string{"noFlash", "noFlash"} },
		func(p *rules.Policy) { p.Conditions = []string{"noFlash"}; p.Photography = "allowed" },
		func(p *rules.Policy) { p.AreaKind = "inventedArea" },
		func(p *rules.Policy) { p.SourceLanguage = "xx" },
		func(p *rules.Policy) { p.Translations = map[string]rules.RuleTranslation{"xx": {Text: "x"}} },
		func(p *rules.Policy) { p.Translations = map[string]rules.RuleTranslation{"ja": {Text: "x"}} },
		func(p *rules.Policy) {
			p.Translations = map[string]rules.RuleTranslation{"en": {Text: "x", ReviewedDigest: "invalid"}}
		},
	}
	for i, mutate := range bads {
		copy := p
		mutate(&copy)
		if rules.Validate(copy, true) == nil {
			t.Fatal("invalid multilingual policy accepted", i)
		}
	}
}

func digestVector(t *testing.T) (rules.Policy, string) {
	t.Helper()
	raw, err := os.ReadFile("../../../packages/postcheck_rules/testdata/multilingual_policy.json")
	if err != nil {
		t.Fatal(err)
	}
	var vector struct {
		Policy      rules.Policy `json:"policy"`
		RulesDigest string       `json:"rulesDigest"`
	}
	if err = json.Unmarshal(raw, &vector); err != nil {
		t.Fatal(err)
	}
	return vector.Policy, vector.RulesDigest
}

// Venues without check items must keep their digest so reviewed translations stay valid.
func TestCheckTargetsDigestUnchangedWhenEmpty(t *testing.T) {
	p, want := digestVector(t)
	p.CheckTargets = []string{}
	if p.RulesDigest() != want {
		t.Fatal("empty checkTargets changed the rules digest")
	}
}

// Expected value is shared with Dart's VenuePolicy.rulesDigest for the same vector.
const checkTargetsVectorDigest = "db398a5f59da57f66ddc3fb3c818236de1e0d0151ab0ed86e5277a53d3f5ad78"

func TestCheckTargetsDigestContract(t *testing.T) {
	p, base := digestVector(t)
	p.CheckTargets = []string{"whiteboard", "face", "contact"}
	got := p.RulesDigest()
	if got == base {
		t.Fatal("checkTargets did not change the rules digest")
	}
	if got != checkTargetsVectorDigest {
		t.Fatal("checkTargets digest differs from the Dart contract:", got)
	}
	p.CheckTargets = []string{"contact", "whiteboard", "face"}
	if p.RulesDigest() != got {
		t.Fatal("checkTargets order changed the rules digest")
	}
	p.CheckTargets = []string{"contact", "face"}
	if p.RulesDigest() == got {
		t.Fatal("removing a check item kept the rules digest")
	}
}

func TestCheckTargetsValidation(t *testing.T) {
	_, p := fixture(t)
	p.CheckTargets = append([]string(nil), rules.VenueCheckTargets...)
	if err := rules.Validate(p, true); err != nil {
		t.Fatal("all check items rejected", err)
	}
	p.CheckTargets = []string{"face", "poster"}
	if err := rules.Validate(p, true); err != nil {
		t.Fatal("valid check items rejected", err)
	}
	bads := [][]string{
		{"inventedTarget"},
		{"face", "face"},
		{"Face"},
		{""},
		append(append([]string(nil), rules.VenueCheckTargets...), "face"),
	}
	for i, targets := range bads {
		copy := p
		copy.CheckTargets = targets
		if !errors.Is(rules.Validate(copy, false), rules.ErrInvalid) {
			t.Fatal("invalid checkTargets accepted", i)
		}
	}
}

// Venue staff set check items through the normal draft -> submit -> approval flow,
// and the published venue serves them to the app.
func TestCheckTargetsArePublished(t *testing.T) {
	s, p := fixture(t)
	v, err := s.Create(ctx, owner, p)
	if err != nil {
		t.Fatal(err)
	}
	p.CheckTargets = []string{"whiteboard", "face"}
	v = change(t, s, owner, v, "save", &p)
	if got := public(t, s, rules.Actor{}); len(got) != 0 {
		t.Fatal("draft check items were public")
	}
	v = change(t, s, owner, v, "submit", nil)
	change(t, s, operator, v, "approve", nil)
	out := public(t, s, rules.Actor{})
	if len(out) != 1 || len(out[0].Policy.CheckTargets) != 2 || out[0].Policy.CheckTargets[0] != "whiteboard" || out[0].Policy.CheckTargets[1] != "face" {
		t.Fatal("published check items lost", out)
	}
	raw, err := json.Marshal(out[0].Policy)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"checkTargets":["whiteboard","face"]`) {
		t.Fatal("checkTargets missing from public JSON")
	}
	_, empty := fixture(t)
	raw, _ = json.Marshal(empty)
	if strings.Contains(string(raw), "checkTargets") {
		t.Fatal("empty checkTargets serialized")
	}
}
