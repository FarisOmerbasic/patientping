// The worker sends appointment reminders. Every 30 seconds it marks the
// appointments that start within the next 24 hours and have no reminder yet,
// and logs one "reminder sent" line for each. A real SMS or email comes later.
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
	"github.com/FarisOmerbasic/patientping/app/internal/store"
)

const (
	every  = 30 * time.Second // how often the worker looks
	within = 24 * time.Hour   // how far ahead an appointment gets its reminder
)

func main() {
	healthcheck := flag.Bool("healthcheck", false, "ask the running worker's /healthz, then exit 0 (healthy) or 1")
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

	for _, name := range []string{"DB_ADDR", "DB_NAME", "DB_USER", "DB_PASSWORD"} {
		if os.Getenv(name) == "" {
			log.Error("setup failed", "err", "the worker needs "+name)
			os.Exit(1)
		}
	}
	st, err := store.NewMSSQL(os.Getenv("DB_ADDR"), os.Getenv("DB_NAME"), os.Getenv("DB_USER"), os.Getenv("DB_PASSWORD"))
	if err != nil {
		log.Error("store setup failed", "err", err)
		os.Exit(1)
	}

	// /healthz says the process is alive. It stays 200 while the database is
	// down, because a restart of the worker wouldn't bring the database back.
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintln(w, `{"status":"ok"}`)
	})
	srv := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("health server failed", "err", err)
			os.Exit(1)
		}
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	log.Info("worker started", "every", every.String(), "within", within.String(), "port", port)
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for ctx.Err() == nil {
		remind(ctx, st, log)
		select {
		case <-ctx.Done():
		case <-ticker.C:
		}
	}

	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("shutdown failed", "err", err)
		return
	}
	log.Info("stopped")
}

// remind does one round. If it fails, for example because the database is
// down, it logs the error and gives up on this round. The next round, 30
// seconds later, tries again. The worker never exits because of it.
func remind(ctx context.Context, st *store.MSSQL, log *slog.Logger) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	due, err := st.MarkDueReminders(ctx, within)
	if err != nil {
		log.Error("reminder round failed", "err", err)
		return
	}
	for _, a := range due {
		log.Info("reminder sent", "appointment_id", a.ID, "patient_id", a.PatientID, "starts_at", a.StartsAt)
	}
}
