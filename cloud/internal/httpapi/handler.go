package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"postcheck/cloud/internal/backup"
	"strings"
	"time"
)

type Identity interface {
	Verify(context.Context, string) (string, error)
}
type Handler struct {
	Service  backup.Service
	Identity Identity
}

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.URL.Path == "/healthz" && r.Method == http.MethodGet {
		w.WriteHeader(204)
		return
	}
	if r.URL.Path != "/v1/backup" {
		http.NotFound(w, r)
		return
	}
	if r.Method != "GET" && r.Method != "PUT" && r.Method != "DELETE" {
		w.WriteHeader(405)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		w.WriteHeader(401)
		return
	}
	uid, e := h.Identity.Verify(ctx, strings.TrimPrefix(auth, "Bearer "))
	if e != nil || uid == "" {
		w.WriteHeader(401)
		return
	}
	var snapshot backup.Snapshot
	switch r.Method {
	case "GET":
		snapshot, e = h.Service.Get(ctx, uid)
	case "PUT":
		if r.Header.Get("Content-Type") != "application/json" {
			w.WriteHeader(415)
			return
		}
		expected := r.Header.Get("If-Match")
		if expected == "" && r.Header.Get("If-None-Match") != "*" {
			w.WriteHeader(428)
			return
		}
		if expected != "" && r.Header.Get("If-None-Match") != "" {
			w.WriteHeader(400)
			return
		}
		data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, backup.MaxPayload))
		if err != nil {
			w.WriteHeader(413)
			return
		}
		snapshot, e = h.Service.Put(ctx, uid, expected, data)
	case "DELETE":
		expected := r.Header.Get("If-Match")
		if expected == "" {
			w.WriteHeader(428)
			return
		}
		e = h.Service.Delete(ctx, uid, expected)
	}
	if e != nil {
		switch {
		case errors.Is(e, backup.ErrNotFound):
			w.WriteHeader(404)
		case errors.Is(e, backup.ErrConflict):
			w.WriteHeader(409)
		case errors.Is(e, backup.ErrInvalid):
			w.WriteHeader(400)
		default:
			w.WriteHeader(503)
		}
		return // Never log payloads, tokens, SDK errors, or decrypted settings.
	}
	if r.Method == "DELETE" {
		w.WriteHeader(204)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(snapshot)
}
