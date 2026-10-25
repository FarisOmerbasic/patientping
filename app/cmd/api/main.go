package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/FarisOmerbasic/patientping/app/internal/health"
	"github.com/FarisOmerbasic/patientping/app/internal/httpapi"
	"github.com/FarisOmerbasic/patientping/app/internal/store"
)

var version = "dev"

func main() {
	healthcheck := flag.Bool("healthcheck", false, "ask the running API's /healthz, then exit 0 (healthy) or 1")
	flag.Parse()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	if *healthcheck {
		if err := health.Check(port); err != nil {
			fmt.Fprintln(os.Stderr, "unhealthy:", err)
			os.Exit(1)
		}
		os.Exit(0)
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	st, err := newStore()
	if err != nil {
		log.Error("store setup failed", "err", err)
		os.Exit(1)
	}

	api := httpapi.New(st, version, log)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Info("listening", "port", port, "version", version)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	log.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("shutdown failed", "err", err)
		return
	}
	log.Info("stopped")
}

// newStore picks the store named in STORE: memory (the default) or mssql.
// The mssql store needs DB_ADDR (host:port), DB_NAME, DB_USER and DB_PASSWORD.
func newStore() (store.Store, error) {
	switch os.Getenv("STORE") {
	case "", "memory":
		return store.NewMemory(), nil
	case "mssql":
		for _, name := range []string{"DB_ADDR", "DB_NAME", "DB_USER", "DB_PASSWORD"} {
			if os.Getenv(name) == "" {
				return nil, fmt.Errorf("STORE=mssql needs %s", name)
			}
		}
		return store.NewMSSQL(os.Getenv("DB_ADDR"), os.Getenv("DB_NAME"), os.Getenv("DB_USER"), os.Getenv("DB_PASSWORD"))
	default:
		return nil, fmt.Errorf("STORE must be memory or mssql, not %q", os.Getenv("STORE"))
	}
}
