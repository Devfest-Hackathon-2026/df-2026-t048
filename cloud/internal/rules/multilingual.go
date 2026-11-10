package rules

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
)

type RuleTranslation struct {
	Text           string `json:"text"`
	Area           string `json:"area"`
	ReviewedDigest string `json:"reviewedDigest"`
}

var conditionAspects = map[string]string{
	"noFlash": "photography", "noTripod": "photography",
	"photosOnly": "photography", "designatedAreasOnly": "photography",
	"noLiveStreaming": "publication", "creditRequired": "publication",
	"subjectsConsentRequired": "publication", "personalUseOnly": "commercial",
}

func ruleLanguage(p Policy) string {
	if p.SourceLanguage == "" {
		return "ja"
	}
	return p.SourceLanguage
}
func areaKind(p Policy) string {
	if p.AreaKind == "" {
		return "custom"
	}
	return p.AreaKind
}
func ruleMillis(t *time.Time) string {
	if t == nil {
		return ""
	}
	return strconv.FormatInt(t.UnixMilli(), 10)
}

// RulesDigest is shared with Dart's VenuePolicy.rulesDigest. Length-prefixes
// make arbitrary Unicode/newlines unambiguous without JSON escaping differences.
func (p Policy) RulesDigest() string {
	codes := append([]string(nil), p.Conditions...)
	sort.Strings(codes)
	words := append([]string(nil), p.Words...)
	sort.Strings(words)
	coordinate := func(value float64) string {
		var raw [8]byte
		binary.BigEndian.PutUint64(raw[:], math.Float64bits(value))
		return base64.StdEncoding.EncodeToString(raw[:])
	}
	fields := []string{p.Name, p.Event, p.Area, areaKind(p), ruleLanguage(p),
		p.SourceText, p.SourceURL, p.Photography, p.Publication, p.Commercial,
		p.Address, p.Website, p.Visibility, coordinate(p.Latitude), coordinate(p.Longitude),
		ruleMillis(p.ReleaseAt), ruleMillis(p.ValidUntil), strconv.Itoa(len(codes))}
	fields = append(fields, codes...)
	fields = append(fields, strconv.Itoa(len(words)))
	fields = append(fields, words...)
	// Appended only when set, so venues without check items keep their earlier
	// digest (and their reviewed translations).
	if len(p.CheckTargets) > 0 {
		targets := append([]string(nil), p.CheckTargets...)
		sort.Strings(targets)
		fields = append(fields, "checkTargets", strconv.Itoa(len(targets)))
		fields = append(fields, targets...)
	}
	var b strings.Builder
	for _, field := range fields {
		b.WriteString(strconv.Itoa(len(field)))
		b.WriteByte(':')
		b.WriteString(field)
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}

func (p Policy) TranslationDigest(language string, t RuleTranslation) string {
	var b strings.Builder
	for _, field := range []string{p.RulesDigest(), language, t.Text, t.Area} {
		b.WriteString(strconv.Itoa(len(field)))
		b.WriteByte(':')
		b.WriteString(field)
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}

func validRuleLanguage(code string) bool {
	return code == "ja" || code == "en" || code == "zh" || code == "ko"
}
func validateMultilingual(p Policy, submit bool) error {
	if !validRuleLanguage(ruleLanguage(p)) {
		return ErrInvalid
	}
	switch areaKind(p) {
	case "custom", "entireVenue", "lobby", "exhibitionRooms", "outdoors", "designatedOnly":
	default:
		return ErrInvalid
	}
	if len(p.Conditions) > len(conditionAspects) || len(p.Translations) > 4 {
		return ErrInvalid
	}
	seen := map[string]bool{}
	permissions := map[string]string{"photography": p.Photography, "publication": p.Publication, "commercial": p.Commercial}
	for _, code := range p.Conditions {
		aspect, ok := conditionAspects[code]
		if !ok || seen[code] || (submit && permissions[aspect] != "conditional") {
			return ErrInvalid
		}
		seen[code] = true
	}
	for code, t := range p.Translations {
		if !validRuleLanguage(code) || code == ruleLanguage(p) || len(t.Text) > 6000 || len(t.Area) > 500 {
			return ErrInvalid
		}
		if t.ReviewedDigest != "" {
			raw, err := hex.DecodeString(t.ReviewedDigest)
			if err != nil || len(raw) != 32 {
				return ErrInvalid
			}
		}
	}
	return nil
}

// Only a facility-confirmed translation for this exact rules revision is public.
// Drafts and outdated translations remain editable in the private admin API.
func publicTranslations(p Policy) map[string]RuleTranslation {
	out := map[string]RuleTranslation{}
	for code, t := range p.Translations {
		if validRuleLanguage(code) && code != ruleLanguage(p) && t.ReviewedDigest == p.TranslationDigest(code, t) &&
			strings.TrimSpace(t.Text) != "" && (strings.TrimSpace(p.Area) == "" || strings.TrimSpace(t.Area) != "") {
			out[code] = t
		}
	}
	return out
}
