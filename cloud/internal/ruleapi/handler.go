package ruleapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"postcheck/cloud/internal/rules"
	"strings"
	"time"
)

type Identity interface {
	VerifyActor(context.Context, string) (rules.Actor, error)
}
type Handler struct {
	Service  rules.Service
	Identity Identity
}
type request struct {
	Version            int           `json:"version"`
	Policy             *rules.Policy `json:"policy,omitempty"`
	Reason             string        `json:"reason"`
	PublicAcknowledged bool          `json:"publicAcknowledged"`
}

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	a := rules.Actor{}
	header := r.Header.Get("Authorization")
	if header != "" {
		if !strings.HasPrefix(header, "Bearer ") {
			w.WriteHeader(401)
			return
		}
		var e error
		a, e = h.Identity.VerifyActor(ctx, strings.TrimPrefix(header, "Bearer "))
		if e != nil || a.UID == "" {
			w.WriteHeader(401)
			return
		}
	}
	var result any
	var e error
	switch {
	case strings.HasPrefix(r.URL.Path, "/v1/access/"):
		result, e = h.access(ctx, w, r, a)
		if result == nil && e == nil {
			return
		}
	case r.URL.Path == "/v1/session" && r.Method == "GET":
		if a.UID == "" {
			w.WriteHeader(401)
			return
		}
		result = a
	case r.URL.Path == "/v1/venues" && r.Method == "GET":
		result, e = h.Service.List(ctx, a, false)
	case r.URL.Path == "/v1/admin/venues" && r.Method == "GET":
		result, e = h.Service.List(ctx, a, true)
	case strings.HasPrefix(r.URL.Path, "/v1/admin/venues"):
		if a.UID == "" {
			w.WriteHeader(401)
			return
		}
		if r.Method != "POST" && r.Method != "PUT" {
			w.WriteHeader(405)
			return
		}
		if r.Header.Get("Content-Type") != "application/json" {
			w.WriteHeader(415)
			return
		}
		var body request
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024))
		dec.DisallowUnknownFields()
		if dec.Decode(&body) != nil {
			w.WriteHeader(400)
			return
		}
		var rest any
		if dec.Decode(&rest) != io.EOF {
			w.WriteHeader(400)
			return
		}
		if r.URL.Path == "/v1/admin/venues" && r.Method == "POST" {
			if body.Policy == nil {
				w.WriteHeader(400)
				return
			}
			result, e = h.Service.Create(ctx, a, *body.Policy)
		} else {
			path := strings.Split(strings.TrimPrefix(r.URL.Path, "/v1/admin/venues/"), "/")
			if len(path) < 1 || len(path) > 2 {
				w.WriteHeader(404)
				return
			}
			action := "save"
			if len(path) == 2 && r.Method == "POST" {
				action = path[1]
			} else if len(path) != 1 || r.Method != "PUT" {
				w.WriteHeader(405)
				return
			}
			result, e = h.Service.Change(ctx, a, path[0], body.Version, action, body.Policy, body.Reason, body.PublicAcknowledged)
		}
	default:
		http.NotFound(w, r)
		return
	}
	if e != nil {
		switch {
		case errors.Is(e, rules.ErrVerificationRequired):
			w.WriteHeader(412)
		case errors.Is(e, rules.ErrInvalid):
			w.WriteHeader(400)
		case errors.Is(e, rules.ErrForbidden):
			w.WriteHeader(403)
		case errors.Is(e, rules.ErrConflict):
			w.WriteHeader(409)
		case errors.Is(e, rules.ErrNotFound):
			w.WriteHeader(404)
		default:
			w.WriteHeader(503)
		}
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
