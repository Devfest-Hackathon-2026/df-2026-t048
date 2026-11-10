// Package rules owns venue publication. It does not depend on HTTP or Google SDKs.
package rules

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"math"
	"net/url"
	"strings"
	"time"
)

var ErrInvalid = errors.New("invalid input")
var ErrForbidden = errors.New("forbidden")
var ErrConflict = errors.New("revision conflict")
var ErrNotFound = errors.New("not found")
var ErrVerificationRequired = errors.New("facility verification required")

type Actor struct {
	UID      string `json:"uid"`
	Org      string `json:"org"`
	Operator bool   `json:"operator"`
}
type Policy struct {
	Name            string                     `json:"name"`
	ApplicationName string                     `json:"applicationName,omitempty"`
	Address         string                     `json:"address"`
	Latitude        float64                    `json:"latitude"`
	Longitude       float64                    `json:"longitude"`
	Website         string                     `json:"website"`
	Contact         string                     `json:"contact,omitempty"`
	Event           string                     `json:"event"`
	Area            string                     `json:"area"`
	AreaKind        string                     `json:"areaKind,omitempty"`
	Conditions      []string                   `json:"conditions,omitempty"`
	SourceLanguage  string                     `json:"sourceLanguage,omitempty"`
	Translations    map[string]RuleTranslation `json:"translations,omitempty"`
	Photography     string                     `json:"photography"`
	Publication     string                     `json:"publication"`
	Commercial      string                     `json:"commercial"`
	Words           []string                   `json:"words"`
	CheckTargets    []string                   `json:"checkTargets,omitempty"`
	ReleaseAt       *time.Time                 `json:"releaseAt,omitempty"`
	ValidUntil      *time.Time                 `json:"validUntil,omitempty"`
	SourceURL       string                     `json:"sourceUrl"`
	SourceImage     string                     `json:"sourceImage,omitempty"`
	SourceText      string                     `json:"sourceText"`
	Visibility      string                     `json:"visibility"`
}
type Venue struct {
	CreatedByUID     string     `json:"createdByUid,omitempty"`
	SubmittedByUID   string     `json:"submittedByUid,omitempty"`
	AccessVerifiedAt *time.Time `json:"accessVerifiedAt,omitempty"`
	ID               string     `json:"id"`
	Org              string     `json:"org"`
	Version          int        `json:"version"`
	Status           string     `json:"status"`
	Draft            Policy     `json:"draft"`
	Published        *Policy    `json:"published,omitempty"`
	PublishedVersion int        `json:"publishedVersion"`
	Suspended        bool       `json:"suspended"`
	Reason           string     `json:"reason"`
	UpdatedAt        time.Time  `json:"updatedAt"`
	PublishedAt      *time.Time `json:"publishedAt,omitempty"`
}
type PublicVenue struct {
	ID        string    `json:"id"`
	Version   int       `json:"version"`
	Policy    Policy    `json:"policy"`
	UpdatedAt time.Time `json:"updatedAt"`
}
type Audit struct {
	VenueID string    `json:"venueId"`
	Actor   string    `json:"actor"`
	Action  string    `json:"action"`
	Version int       `json:"version"`
	At      time.Time `json:"at"`
}
type State struct {
	Members       []FacilityMember      `json:"members,omitempty"`
	Verifications []VerificationRequest `json:"verifications,omitempty"`
	Tokens        []AccessToken         `json:"tokens,omitempty"`
	Venues        []Venue               `json:"venues"`
	Audit         []Audit               `json:"audit"`
}
type Store interface {
	Load(context.Context) (State, string, error)
	Save(context.Context, string, State) error
}
type Service struct {
	Store Store
	Now   func() time.Time
}

func (s Service) now() time.Time {
	if s.Now != nil {
		return s.Now().UTC()
	}
	return time.Now().UTC()
}

// VenueCheckTargets are the check items a venue can switch on so its visitors
// are always told about them (OR with the visitor's own settings). Shared with
// Dart's venueCheckTargets and the app's CheckTarget names. Default: none.
var VenueCheckTargets = []string{"contact", "privateWord", "imageText", "face", "announcement", "context",
	"screenDevice", "whiteboard", "wineGlass", "book", "pictureFrame", "poster"}

func validCheckTarget(name string) bool {
	for _, t := range VenueCheckTargets {
		if t == name {
			return true
		}
	}
	return false
}

// Existing detailed rules keep their evidence requirements. New policies may
// consist solely of the app-compatible checkTargets (including none).
func (p Policy) HasLegacyRuleDetails() bool {
	return p.Photography != "unknown" || p.Publication != "unknown" || p.Commercial != "unknown" ||
		p.Event != "" || p.Area != "" || (p.AreaKind != "" && p.AreaKind != "custom") ||
		len(p.Conditions) > 0 || len(p.Translations) > 0 || len(p.Words) > 0 ||
		p.ReleaseAt != nil || p.ValidUntil != nil || strings.TrimSpace(p.SourceText) != "" ||
		p.SourceURL != "" || p.SourceImage != ""
}
func validURL(s string) bool {
	u, e := url.Parse(s)
	return e == nil && u.Scheme == "https" && u.Hostname() != "" && u.User == nil && len(s) < 2000
}

// Proof images are private, bounded raster uploads, never public rule payloads.
func validSourceImage(raw string) bool {
	header, encoded, ok := strings.Cut(raw, ",")
	formats := map[string]string{"data:image/png;base64": "png", "data:image/jpeg;base64": "jpeg", "data:image/gif;base64": "gif"}
	expected, supported := formats[header]
	if !ok || !supported {
		return false
	}
	data, err := base64.StdEncoding.Strict().DecodeString(encoded)
	if err != nil || len(data) > 18*1024 {
		return false
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	return err == nil && format == expected && cfg.Width > 0 && cfg.Height > 0 && cfg.Width <= 4096 && cfg.Height <= 4096 && int64(cfg.Width)*int64(cfg.Height) <= 4_000_000
}
func Validate(p Policy, submit bool) error {
	if err := validateMultilingual(p, submit); err != nil {
		return err
	}
	if strings.TrimSpace(p.Name) == "" || len(p.Name) > 240 || math.IsNaN(p.Latitude) || math.IsNaN(p.Longitude) || p.Latitude < -90 || p.Latitude > 90 || p.Longitude < -180 || p.Longitude > 180 {
		return ErrInvalid
	}
	if p.Visibility != "public" && p.Visibility != "organization" {
		return ErrInvalid
	}
	for _, v := range []string{p.Photography, p.Publication, p.Commercial} {
		if v != "allowed" && v != "forbidden" && v != "conditional" && v != "unknown" {
			return ErrInvalid
		}
	}
	if len(p.Words) > 100 || len(p.SourceText) > 12000 || len(p.Address) > 1000 || len(p.Contact) > 500 || len(p.Area) > 500 || len(p.Event) > 500 || len(p.ApplicationName) > 240 || len(p.SourceImage) > 40000 {
		return ErrInvalid
	}
	if p.SourceImage != "" && !validSourceImage(p.SourceImage) {
		return ErrInvalid
	}
	for _, w := range p.Words {
		if strings.TrimSpace(w) == "" || len(w) > 300 {
			return ErrInvalid
		}
	}
	if len(p.CheckTargets) > len(VenueCheckTargets) {
		return ErrInvalid
	}
	seenTargets := map[string]bool{}
	for _, t := range p.CheckTargets {
		if !validCheckTarget(t) || seenTargets[t] {
			return ErrInvalid
		}
		seenTargets[t] = true
	}
	if submit && strings.TrimSpace(p.Address) == "" {
		return ErrInvalid
	}
	if submit && p.HasLegacyRuleDetails() &&
		(strings.TrimSpace(p.SourceText) == "" || (p.SourceURL == "" && p.SourceImage == "")) {
		return ErrInvalid
	}
	if p.SourceURL != "" && !validURL(p.SourceURL) {
		return ErrInvalid
	}
	if p.Website != "" && !validURL(p.Website) {
		return ErrInvalid
	}
	if p.ReleaseAt != nil && p.ValidUntil != nil && !p.ReleaseAt.Before(*p.ValidUntil) {
		return ErrInvalid
	}
	return nil
}
func (s Service) List(ctx context.Context, a Actor, admin bool) (any, error) {
	st, _, e := s.Store.Load(ctx)
	if e != nil {
		return nil, e
	}
	RedactContacts(&st)
	if admin {
		if a.UID == "" {
			return nil, ErrForbidden
		}
		out := []Venue{}
		for _, v := range st.Venues {
			if !s.canRead(st, a, v) {
				continue
			}
			// 運営には下書きを渡さない。公開済みの再編集中は公開スナップショットのみ。
			if a.Operator && v.Status == "draft" {
				if v.Published == nil {
					continue
				}
				shown := v
				shown.Status = "published"
				shown.Draft = *v.Published
				shown.Reason = ""
				out = append(out, shown)
				continue
			}
			out = append(out, v)
		}
		return out, nil
	}
	out := []PublicVenue{}
	for _, v := range st.Venues {
		if v.Published == nil || v.Suspended {
			continue
		}
		p := *v.Published
		if p.Visibility != "public" && !s.canRead(st, a, v) {
			continue
		}
		if p.ValidUntil != nil && !s.now().Before(*p.ValidUntil) {
			continue
		}
		p.Contact = ""
		p.SourceImage = ""
		p.ApplicationName = ""
		p.Translations = publicTranslations(p)
		out = append(out, PublicVenue{v.ID, v.PublishedVersion, p, *v.PublishedAt})
	}
	return out, nil
}
func (s Service) Create(ctx context.Context, a Actor, p Policy) (Venue, error) {
	if a.UID == "" || a.Org == "" || a.Operator {
		return Venue{}, ErrForbidden
	}
	p = cleanPolicy(p)
	if e := Validate(p, false); e != nil {
		return Venue{}, e
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return Venue{}, e
	}
	if len(st.Venues) >= 100 {
		return Venue{}, ErrInvalid
	}
	b := make([]byte, 12)
	if _, e = rand.Read(b); e != nil {
		return Venue{}, e
	}
	v := Venue{CreatedByUID: a.UID, ID: hex.EncodeToString(b), Org: a.Org, Version: 1, Status: "draft", Draft: p, UpdatedAt: s.now()}
	st.Venues = append(st.Venues, v)
	RedactContacts(&st)
	e = s.save(ctx, rev, st)
	return v, e
}
func (s Service) Change(ctx context.Context, a Actor, id string, version int, action string, p *Policy, reason string, publicAcknowledged bool) (Venue, error) {
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return Venue{}, e
	}
	for i := range st.Venues {
		v := &st.Venues[i]
		if v.ID != id {
			continue
		}
		if !s.canRead(st, a, *v) {
			return Venue{}, ErrForbidden
		}
		// Reading for review does not grant authority to edit or submit for owners.
		if action == "save" || action == "submit" || action == "withdraw" {
			if !s.canEdit(st, a, *v) {
				return Venue{}, ErrForbidden
			}
		}
		if v.Version != version {
			return Venue{}, ErrConflict
		}
		switch action {
		case "save":
			if v.Status == "pending" || p == nil {
				return Venue{}, ErrConflict
			}
			*p = cleanPolicy(*p)
			if e = Validate(*p, false); e != nil {
				return Venue{}, e
			}
			v.Draft = *p
			v.Status = "draft"
			v.Reason = ""
		case "submit":
			if member(st, a.UID, v.ID, s.now()) == nil {
				return Venue{}, ErrVerificationRequired
			}
			if v.Status != "draft" && v.Status != "returned" {
				return Venue{}, ErrConflict
			}
			if e = Validate(v.Draft, true); e != nil {
				return Venue{}, e
			}
			if v.Draft.ValidUntil != nil && !s.now().Before(*v.Draft.ValidUntil) {
				return Venue{}, ErrInvalid
			}
			if v.Draft.Visibility == "public" && !publicAcknowledged {
				return Venue{}, ErrInvalid
			}
			v.Status = "pending"
			v.SubmittedByUID = a.UID
			v.Reason = ""
		case "withdraw":
			if v.Status != "pending" {
				return Venue{}, ErrConflict
			}
			v.Status = "draft"
		case "approve":
			if member(st, v.SubmittedByUID, v.ID, s.now()) == nil {
				return Venue{}, ErrVerificationRequired
			}
			if !a.Operator || creator(a, *v) || member(st, a.UID, v.ID, s.now()) != nil {
				return Venue{}, ErrForbidden
			}
			if v.Status != "pending" {
				return Venue{}, ErrConflict
			}
			if e = Validate(v.Draft, true); e != nil {
				return Venue{}, e
			}
			if v.Draft.ValidUntil != nil && !s.now().Before(*v.Draft.ValidUntil) {
				return Venue{}, ErrInvalid
			}
			copy := v.Draft
			v.Published = &copy
			v.PublishedVersion = v.Version + 1
			t := s.now()
			v.PublishedAt = &t
			v.Suspended = false
			v.Status = "published"
			v.Reason = ""
		case "return":
			if !a.Operator || creator(a, *v) || member(st, a.UID, v.ID, s.now()) != nil {
				return Venue{}, ErrForbidden
			}
			if v.Status != "pending" {
				return Venue{}, ErrConflict
			}
			if strings.TrimSpace(reason) == "" || len(reason) > 2000 {
				return Venue{}, ErrInvalid
			}
			v.Status = "returned"
			v.Reason = reason
		case "suspend":
			if !a.Operator {
				return Venue{}, ErrForbidden
			}
			if v.Published == nil {
				return Venue{}, ErrConflict
			}
			if strings.TrimSpace(reason) == "" || len(reason) > 2000 {
				return Venue{}, ErrInvalid
			}
			v.Suspended = true
			v.Reason = reason
		default:
			return Venue{}, ErrInvalid
		}
		v.Version++
		v.UpdatedAt = s.now()
		st.Audit = append(st.Audit, Audit{id, a.UID, action, v.Version, s.now()})
		if len(st.Audit) > 500 {
			st.Audit = st.Audit[len(st.Audit)-500:]
		}
		RedactContacts(&st)
		e = s.save(ctx, rev, st)
		return *v, e
	}
	return Venue{}, ErrNotFound
}
