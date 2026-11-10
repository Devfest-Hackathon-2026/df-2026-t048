package main

import (
	"cloud.google.com/go/firestore"
	kms "cloud.google.com/go/kms/apiv1"
	"context"
	firebase "firebase.google.com/go/v4"
	"log"
	"net/http"
	"os"
	"postcheck/cloud/internal/backup"
	adapter "postcheck/cloud/internal/google"
	"postcheck/cloud/internal/httpapi"
	"postcheck/cloud/internal/ruleapi"
	"postcheck/cloud/internal/rules"
	"time"
)

func main() {
	ctx := context.Background()
	project := os.Getenv("GOOGLE_CLOUD_PROJECT")
	key := os.Getenv("KMS_KEY_NAME")
	if project == "" || key == "" {
		log.Fatal("Missing service configuration")
	}
	app, e := firebase.NewApp(ctx, &firebase.Config{ProjectID: project})
	if e != nil {
		log.Fatal("Authentication setup failed")
	}
	auth, e := app.Auth(ctx)
	if e != nil {
		log.Fatal("Authentication setup failed")
	}
	db, e := firestore.NewClient(ctx, project)
	if e != nil {
		log.Fatal("Storage setup failed")
	}
	defer db.Close()
	keys, e := kms.NewKeyManagementClient(ctx)
	if e != nil {
		log.Fatal("Encryption setup failed")
	}
	defer keys.Close()
	service := backup.Service{Store: adapter.Store{Client: db}, Keys: adapter.Keys{Client: keys, Name: key}}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	identity := adapter.Identity{Client: auth, RulesDB: db}
	mux := http.NewServeMux()
	// Settings backup remains deferred; deploying venue rules must not activate it.
	if os.Getenv("ENABLE_SETTINGS_BACKUP") == "true" {
		mux.Handle("/v1/backup", httpapi.Handler{Service: service, Identity: identity})
	}
	mux.Handle("/healthz", httpapi.Handler{Service: service, Identity: identity})
	ruleService := rules.Service{Store: adapter.RuleStore{Client: db, Keys: service.Keys}}
	// The user requested removal of dedicated personal contact fields; no rule is deleted.
	if e = ruleService.PurgeLegacyContacts(ctx); e != nil {
		log.Fatal("Legacy contact cleanup failed")
	}
	mux.Handle("/v1/", ruleapi.Handler{Service: ruleService, Identity: identity})
	server := http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 25 * time.Second, WriteTimeout: 25 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 * 1024}
	log.Print("PostCheck settings service started")
	if e = server.ListenAndServe(); e != nil && e != http.ErrServerClosed {
		log.Fatal("Server stopped")
	}
}
