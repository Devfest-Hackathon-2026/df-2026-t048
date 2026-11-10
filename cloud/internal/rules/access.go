package rules

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"time"
)

const accessDuration = 90 * 24 * time.Hour
const linkDuration = 24 * time.Hour

type FacilityMember struct {
	VenueID    string    `json:"venueId"`
	UID        string    `json:"uid"`
	Role       string    `json:"role"`
	VerifiedAt time.Time `json:"verifiedAt"`
	ExpiresAt  time.Time `json:"expiresAt"`
	Revoked    bool      `json:"revoked,omitempty"`
}
type VerificationRequest struct {
	ID                string    `json:"id"`
	VenueID           string    `json:"venueId"`
	UID               string    `json:"uid"`
	Status            string    `json:"status"`
	RequestedAt       time.Time `json:"requestedAt"`
	OfficialSourceURL string    `json:"officialSourceUrl,omitempty"`
}
type AccessToken struct {
	Hash      string    `json:"hash"`
	Kind      string    `json:"kind"`
	VenueID   string    `json:"venueId"`
	TargetUID string    `json:"targetUid,omitempty"`
	IssuerUID string    `json:"issuerUid"`
	RequestID string    `json:"requestId,omitempty"`
	Role      string    `json:"role"`
	ExpiresAt time.Time `json:"expiresAt"`
}
type IssuedLink struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expiresAt"`
}
type AccessView struct {
	VenueID   string           `json:"venueId"`
	Name      string           `json:"name"`
	UID       string           `json:"uid"`
	Role      string           `json:"role"`
	ExpiresAt *time.Time       `json:"expiresAt,omitempty"`
	Members   []FacilityMember `json:"members"`
}
type RequestView struct {
	VerificationRequest
	Name    string `json:"name"`
	Website string `json:"website"`
}
type LinkPreview struct {
	Kind          string    `json:"kind"`
	Name          string    `json:"name"`
	Role          string    `json:"role"`
	AccountSuffix string    `json:"accountSuffix,omitempty"`
	ExpiresAt     time.Time `json:"expiresAt"`
}

func member(st State, uid, venueID string, now time.Time) *FacilityMember {
	for i := range st.Members {
		m := &st.Members[i]
		if m.UID == uid && m.VenueID == venueID && !m.Revoked && now.Before(m.ExpiresAt) {
			return m
		}
	}
	return nil
}
func creator(a Actor, v Venue) bool {
	return a.UID != "" && (v.CreatedByUID == a.UID || (v.CreatedByUID == "" && v.Org == a.UID))
}
func (s Service) canEdit(st State, a Actor, v Venue) bool {
	return !a.Operator && a.UID != "" && (member(st, a.UID, v.ID, s.now()) != nil || (v.AccessVerifiedAt == nil && creator(a, v)))
}
func (s Service) canRead(st State, a Actor, v Venue) bool {
	return a.UID != "" && (a.Operator || s.canEdit(st, a, v))
}
func venueByID(st *State, id string) *Venue {
	for i := range st.Venues {
		if st.Venues[i].ID == id {
			return &st.Venues[i]
		}
	}
	return nil
}
func (s Service) Access(ctx context.Context, a Actor, id string) (AccessView, error) {
	if a.UID == "" || a.Operator {
		return AccessView{}, ErrForbidden
	}
	st, _, e := s.Store.Load(ctx)
	if e != nil {
		return AccessView{}, e
	}
	v := venueByID(&st, id)
	if v == nil || !s.canEdit(st, a, *v) {
		return AccessView{}, ErrForbidden
	}
	view := AccessView{VenueID: id, Name: v.Draft.Name, UID: a.UID, Role: "unverified", Members: []FacilityMember{}}
	if m := member(st, a.UID, id, s.now()); m != nil {
		view.Role = m.Role
		view.ExpiresAt = &m.ExpiresAt
		if m.Role == "manager" {
			for _, x := range st.Members {
				if x.VenueID == id && !x.Revoked && s.now().Before(x.ExpiresAt) {
					view.Members = append(view.Members, x)
				}
			}
		}
	}
	return view, nil
}
func (s Service) Requests(ctx context.Context, a Actor) ([]RequestView, error) {
	if a.UID == "" {
		return nil, ErrForbidden
	}
	st, _, e := s.Store.Load(ctx)
	if e != nil {
		return nil, e
	}
	out := []RequestView{}
	for _, r := range st.Verifications {
		if !a.Operator && r.UID != a.UID {
			continue
		}
		v := venueByID(&st, r.VenueID)
		if v == nil {
			continue
		}
		p := v.Draft
		if !s.canRead(st, a, *v) {
			if v.Published == nil || v.Published.Visibility != "public" {
				continue
			}
			p = *v.Published
		}
		out = append(out, RequestView{r, p.Name, p.Website})
	}
	return out, nil
}
func (s Service) RequestVerification(ctx context.Context, a Actor, id string) (VerificationRequest, error) {
	if a.UID == "" || a.Operator {
		return VerificationRequest{}, ErrForbidden
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return VerificationRequest{}, e
	}
	v := venueByID(&st, id)
	if v == nil || (!s.canEdit(st, a, *v) && !creator(a, *v) && (v.Published == nil || v.Published.Visibility != "public")) {
		return VerificationRequest{}, ErrForbidden
	}
	pending := 0
	for _, r := range st.Verifications {
		if r.UID == a.UID && r.Status != "confirmed" {
			pending++
		}
		if r.UID == a.UID && r.VenueID == id && r.Status != "confirmed" {
			return r, nil
		}
	}
	if pending >= 5 || len(st.Verifications) >= 500 {
		return VerificationRequest{}, ErrInvalid
	}
	b := make([]byte, 16)
	if _, e = rand.Read(b); e != nil {
		return VerificationRequest{}, e
	}
	r := VerificationRequest{ID: hex.EncodeToString(b), VenueID: id, UID: a.UID, Status: "requested", RequestedAt: s.now()}
	st.Verifications = append(st.Verifications, r)
	e = s.save(ctx, rev, st)
	return r, e
}
func mintToken() (string, string, error) {
	b := make([]byte, 32)
	if _, e := rand.Read(b); e != nil {
		return "", "", e
	}
	raw := hex.EncodeToString(b)
	h := sha256.Sum256([]byte(raw))
	return raw, hex.EncodeToString(h[:]), nil
}
func (s Service) pruneTokens(st *State) {
	out := st.Tokens[:0]
	for _, t := range st.Tokens {
		if s.now().Before(t.ExpiresAt) {
			out = append(out, t)
		}
	}
	st.Tokens = out
}
func (s Service) IssueVerification(ctx context.Context, a Actor, id, officialURL string, checked bool) (IssuedLink, error) {
	if !a.Operator || a.UID == "" {
		return IssuedLink{}, ErrForbidden
	}
	if !checked || !validURL(officialURL) {
		return IssuedLink{}, ErrInvalid
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return IssuedLink{}, e
	}
	for i := range st.Verifications {
		r := &st.Verifications[i]
		if r.ID != id {
			continue
		}
		if r.UID == a.UID || r.Status == "confirmed" {
			return IssuedLink{}, ErrForbidden
		}
		s.pruneTokens(&st)
		if len(st.Tokens) >= 500 {
			return IssuedLink{}, ErrInvalid
		}
		raw, hash, e := mintToken()
		if e != nil {
			return IssuedLink{}, e
		}
		// Reissuing a link invalidates every older link for this request.
		out := st.Tokens[:0]
		for _, t := range st.Tokens {
			if t.RequestID != id {
				out = append(out, t)
			}
		}
		st.Tokens = out
		st.Tokens = append(st.Tokens, AccessToken{Hash: hash, Kind: "verification", VenueID: r.VenueID, TargetUID: r.UID, IssuerUID: a.UID, RequestID: r.ID, Role: "manager", ExpiresAt: s.now().Add(linkDuration)})
		r.Status = "issued"
		r.OfficialSourceURL = officialURL
		s.accessAudit(&st, r.VenueID, a.UID, "verification_issue")
		e = s.save(ctx, rev, st)
		return IssuedLink{raw, s.now().Add(linkDuration)}, e
	}
	return IssuedLink{}, ErrNotFound
}
func (s Service) Invite(ctx context.Context, a Actor, id, role string) (IssuedLink, error) {
	if a.UID == "" || a.Operator {
		return IssuedLink{}, ErrForbidden
	}
	if role != "manager" && role != "editor" {
		return IssuedLink{}, ErrInvalid
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return IssuedLink{}, e
	}
	m := member(st, a.UID, id, s.now())
	if m == nil || m.Role != "manager" {
		return IssuedLink{}, ErrForbidden
	}
	s.pruneTokens(&st)
	if len(st.Tokens) >= 500 {
		return IssuedLink{}, ErrInvalid
	}
	raw, hash, e := mintToken()
	if e != nil {
		return IssuedLink{}, e
	}
	until := s.now().Add(linkDuration)
	if m.ExpiresAt.Before(until) {
		until = m.ExpiresAt
	}
	st.Tokens = append(st.Tokens, AccessToken{Hash: hash, Kind: "invitation", VenueID: id, IssuerUID: a.UID, Role: role, ExpiresAt: until})
	s.accessAudit(&st, id, a.UID, "invitation_issue")
	e = s.save(ctx, rev, st)
	return IssuedLink{raw, until}, e
}
func tokenIndex(st State, raw string, now time.Time) int {
	if len(raw) != 64 {
		return -1
	}
	if _, e := hex.DecodeString(raw); e != nil {
		return -1
	}
	hash := sha256.Sum256([]byte(raw))
	h := hex.EncodeToString(hash[:])
	for i, t := range st.Tokens {
		if t.Hash == h && now.Before(t.ExpiresAt) {
			return i
		}
	}
	return -1
}
func (s Service) PreviewLink(ctx context.Context, raw string) (LinkPreview, error) {
	st, _, e := s.Store.Load(ctx)
	if e != nil {
		return LinkPreview{}, e
	}
	i := tokenIndex(st, raw, s.now())
	if i < 0 {
		return LinkPreview{}, ErrNotFound
	}
	t := st.Tokens[i]
	v := venueByID(&st, t.VenueID)
	if v == nil {
		return LinkPreview{}, ErrNotFound
	}
	if t.Kind == "invitation" {
		m := member(st, t.IssuerUID, t.VenueID, s.now())
		if m == nil || m.Role != "manager" {
			return LinkPreview{}, ErrNotFound
		}
	}
	suffix := t.TargetUID
	if len(suffix) > 8 {
		suffix = suffix[len(suffix)-8:]
	}
	return LinkPreview{t.Kind, v.Draft.Name, t.Role, suffix, t.ExpiresAt}, nil
}
func (s Service) ConsumeLink(ctx context.Context, a Actor, raw string, confirmed bool) (AccessView, error) {
	if !confirmed {
		return AccessView{}, ErrInvalid
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return AccessView{}, e
	}
	i := tokenIndex(st, raw, s.now())
	if i < 0 {
		return AccessView{}, ErrNotFound
	}
	t := st.Tokens[i]
	v := venueByID(&st, t.VenueID)
	if v == nil {
		return AccessView{}, ErrNotFound
	}
	uid := t.TargetUID
	until := s.now().Add(accessDuration)
	if t.Kind == "invitation" {
		if a.UID == "" || a.Operator {
			return AccessView{}, ErrForbidden
		}
		issuer := member(st, t.IssuerUID, t.VenueID, s.now())
		if issuer == nil || issuer.Role != "manager" {
			return AccessView{}, ErrForbidden
		}
		if issuer.ExpiresAt.Before(until) {
			until = issuer.ExpiresAt
		}
		uid = a.UID
	} else if t.Kind != "verification" || uid == "" {
		return AccessView{}, ErrInvalid
	}
	// Keep the stronger existing membership when accepting an editor invitation.
	role := t.Role
	if previous := member(st, uid, t.VenueID, s.now()); previous != nil && previous.Role == "manager" && role == "editor" {
		role = "manager"
		until = previous.ExpiresAt
	}
	out := st.Members[:0]
	for _, m := range st.Members {
		if m.UID != uid || m.VenueID != t.VenueID {
			out = append(out, m)
		}
	}
	st.Members = out
	if len(st.Members) >= 1000 {
		return AccessView{}, ErrInvalid
	}
	st.Members = append(st.Members, FacilityMember{VenueID: t.VenueID, UID: uid, Role: role, VerifiedAt: s.now(), ExpiresAt: until})
	now := s.now()
	v.AccessVerifiedAt = &now
	if t.Kind == "verification" {
		for j := range st.Verifications {
			if st.Verifications[j].ID == t.RequestID {
				st.Verifications[j].Status = "confirmed"
			}
		}
	}
	// Consume and grant in the same CAS write. A concurrent redemption cannot win twice.
	st.Tokens = append(st.Tokens[:i], st.Tokens[i+1:]...)
	s.accessAudit(&st, t.VenueID, uid, "access_accept")
	e = s.save(ctx, rev, st)
	return AccessView{VenueID: v.ID, Name: v.Draft.Name, UID: uid, Role: role, ExpiresAt: &until, Members: []FacilityMember{}}, e
}
func (s Service) Revoke(ctx context.Context, a Actor, id, uid string) (AccessView, error) {
	if a.UID == "" || a.Operator {
		return AccessView{}, ErrForbidden
	}
	st, rev, e := s.Store.Load(ctx)
	if e != nil {
		return AccessView{}, e
	}
	actor := member(st, a.UID, id, s.now())
	if actor == nil || actor.Role != "manager" {
		return AccessView{}, ErrForbidden
	}
	found := false
	managers := 0
	for _, m := range st.Members {
		if m.VenueID == id && !m.Revoked && s.now().Before(m.ExpiresAt) && m.Role == "manager" {
			managers++
		}
	}
	for i := range st.Members {
		m := &st.Members[i]
		if m.VenueID != id || m.UID != uid || m.Revoked {
			continue
		}
		if m.Role == "manager" && s.now().Before(m.ExpiresAt) && managers <= 1 {
			return AccessView{}, ErrConflict
		}
		m.Revoked = true
		found = true
	}
	if !found {
		return AccessView{}, ErrNotFound
	}
	out := st.Members[:0]
	for _, m := range st.Members {
		if !m.Revoked {
			out = append(out, m)
		}
	}
	st.Members = out
	tokens := st.Tokens[:0]
	for _, t := range st.Tokens {
		if t.VenueID != id || t.IssuerUID != uid {
			tokens = append(tokens, t)
		}
	}
	st.Tokens = tokens
	s.accessAudit(&st, id, a.UID, "access_revoke")
	if e = s.save(ctx, rev, st); e != nil {
		return AccessView{}, e
	}
	if uid == a.UID {
		return AccessView{VenueID: id, UID: uid, Role: "none", Members: []FacilityMember{}}, nil
	}
	return s.Access(ctx, a, id)
}
func (s Service) accessAudit(st *State, id, uid, action string) {
	st.Audit = append(st.Audit, Audit{VenueID: id, Actor: uid, Action: action, At: s.now()})
	if len(st.Audit) > 500 {
		st.Audit = st.Audit[len(st.Audit)-500:]
	}
}

// RedactContacts removes the legacy dedicated personal-contact field. Rule content is kept.
func RedactContacts(st *State) bool {
	changed := false
	for i := range st.Venues {
		v := &st.Venues[i]
		if v.Draft.Contact != "" {
			v.Draft.Contact = ""
			changed = true
		}
		if v.Published != nil && v.Published.Contact != "" {
			v.Published.Contact = ""
			changed = true
		}
	}
	return changed
}
func (s Service) PurgeLegacyContacts(ctx context.Context) error {
	for range 3 {
		st, rev, e := s.Store.Load(ctx)
		if e != nil {
			return e
		}
		if !RedactContacts(&st) {
			return nil
		}
		if e = s.save(ctx, rev, st); e == ErrConflict {
			continue
		} else {
			return e
		}
	}
	return ErrConflict
}

// All dedicated contact values received from legacy clients are discarded.
func cleanPolicy(p Policy) Policy { p.Contact = ""; return p }

func (s Service) save(ctx context.Context, rev string, st State) error {
	RedactContacts(&st)
	s.pruneTokens(&st)
	members := st.Members[:0]
	for _, m := range st.Members {
		if !m.Revoked && s.now().Before(m.ExpiresAt) {
			members = append(members, m)
		}
	}
	st.Members = members
	return s.Store.Save(ctx, rev, st)
}
