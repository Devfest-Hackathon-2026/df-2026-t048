// Explicit loopback-only demo. Never accepted by cmd/server.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"postcheck/cloud/internal/ruleapi"
	"postcheck/cloud/internal/rules"
	"postcheck/cloud/internal/rulestore"
	"time"
)

type demoIdentity struct{}

func (demoIdentity) VerifyActor(_ context.Context, token string) (rules.Actor, error) {
	switch token {
	case "postcheck-demo-org":
		return rules.Actor{UID: "demo-org", Org: "demo-org"}, nil
	case "postcheck-demo-staff":
		return rules.Actor{UID: "demo-staff", Org: "demo-staff"}, nil
	case "postcheck-demo-operator":
		return rules.Actor{UID: "demo-operator", Org: "operator", Operator: true}, nil
	}
	return rules.Actor{}, errors.New("unauthorized")
}
func main() {
	if os.Getenv("K_SERVICE") != "" || os.Getenv("POSTCHECK_DEMO") != "1" {
		log.Fatal("Demo requires POSTCHECK_DEMO=1 on a local machine")
	}
	path := os.Getenv("POSTCHECK_DEMO_DATA")
	if path == "" {
		base, _ := os.UserCacheDir()
		path = filepath.Join(base, "PostCheckMVP", "rules-demo.json")
	}
	if e := os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		log.Fatal("Storage setup failed")
	}
	h := ruleapi.Handler{Service: rules.Service{Store: &rulestore.FileStore{Path: path}}, Identity: demoIdentity{}}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && origin != "http://localhost:5173" && origin != "http://127.0.0.1:5173" {
			w.WriteHeader(403)
			return
		}
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		h.ServeHTTP(w, r)
	})
	log.Print("PostCheck demo API: http://127.0.0.1:8787 (fictional data only)")
	server := http.Server{Addr: "127.0.0.1:8787", Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 25 * time.Second, WriteTimeout: 25 * time.Second}
	log.Fatal(server.ListenAndServe())
}
