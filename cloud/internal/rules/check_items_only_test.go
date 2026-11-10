package rules_test

import (
	"postcheck/cloud/internal/rules"
	"testing"
)

func TestCheckItemsOnlyPublicationWithoutLegacyInputs(t *testing.T) {
	for _, targets := range [][]string{{"whiteboard", "poster"}, {}} {
		s, _ := fixture(t)
		p := rules.Policy{
			Name: "Fictional check-item venue", Address: "Fictional address",
			Photography: "unknown", Publication: "unknown", Commercial: "unknown",
			Visibility: "public", CheckTargets: targets,
		}
		if p.HasLegacyRuleDetails() {
			t.Fatal("check items treated as legacy rule details")
		}
		if err := rules.Validate(p, true); err != nil {
			t.Fatal("check items require removed inputs", err)
		}
		v, err := s.Create(ctx, owner, p)
		if err != nil {
			t.Fatal(err)
		}
		v = change(t, s, owner, v, "submit", nil)
		change(t, s, operator, v, "approve", nil)
		out := public(t, s, rules.Actor{})
		if len(out) != 1 || len(out[0].Policy.CheckTargets) != len(targets) {
			t.Fatal("published check items lost")
		}
		if out[0].Policy.SourceText != "" || out[0].Policy.SourceURL != "" {
			t.Fatal("invented evidence was added")
		}
		p.Address = ""
		if rules.Validate(p, true) == nil {
			t.Fatal("missing facility address accepted")
		}
	}
}
