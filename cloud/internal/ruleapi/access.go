package ruleapi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"postcheck/cloud/internal/rules"
	"strings"
)

type accessRequest struct {
	VenueID           string `json:"venueId"`
	Token             string `json:"token"`
	OfficialSourceURL string `json:"officialSourceUrl"`
	Confirmed         bool   `json:"confirmed"`
	Role              string `json:"role"`
	UID               string `json:"uid"`
}

func (h Handler) access(ctx context.Context, w http.ResponseWriter, r *http.Request, a rules.Actor) (any, error) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/access/")
	anonymous := path == "preview" || path == "consume"
	if a.UID == "" && !anonymous {
		w.WriteHeader(401)
		return nil, nil
	}
	if path == "requests" && r.Method == "GET" {
		return h.Service.Requests(ctx, a)
	}
	parts := strings.Split(path, "/")
	if len(parts) == 2 && parts[0] == "venues" && r.Method == "GET" {
		return h.Service.Access(ctx, a, parts[1])
	}
	if r.Method != "POST" {
		w.WriteHeader(405)
		return nil, nil
	}
	if r.Header.Get("Content-Type") != "application/json" {
		w.WriteHeader(415)
		return nil, nil
	}
	var body accessRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
	dec.DisallowUnknownFields()
	if dec.Decode(&body) != nil {
		return nil, rules.ErrInvalid
	}
	var rest any
	if dec.Decode(&rest) != io.EOF {
		return nil, rules.ErrInvalid
	}
	switch {
	case path == "requests":
		return h.Service.RequestVerification(ctx, a, body.VenueID)
	case path == "preview":
		return h.Service.PreviewLink(ctx, body.Token)
	case path == "consume":
		return h.Service.ConsumeLink(ctx, a, body.Token, body.Confirmed)
	case len(parts) == 3 && parts[0] == "requests" && parts[2] == "issue":
		return h.Service.IssueVerification(ctx, a, parts[1], body.OfficialSourceURL, body.Confirmed)
	case len(parts) == 3 && parts[0] == "venues" && parts[2] == "invite":
		return h.Service.Invite(ctx, a, parts[1], body.Role)
	case len(parts) == 3 && parts[0] == "venues" && parts[2] == "revoke":
		return h.Service.Revoke(ctx, a, parts[1], body.UID)
	default:
		return nil, rules.ErrNotFound
	}
}
