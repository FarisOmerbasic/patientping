// Package httpapi turns HTTP requests into calls on the store, and the
// results into JSON answers.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/FarisOmerbasic/patientping/app/internal/store"
)

// API holds what the handlers need.
type API struct {
	store   store.Store
	version string
	log     *slog.Logger
}

// New returns an API that keeps its data in s.
func New(s store.Store, version string, log *slog.Logger) *API {
	return &API{store: s, version: version, log: log}
}

// Routes connects every endpoint of the spec to its handler. A request with
// the wrong method gets 405, and an unknown path gets 404.
func (a *API) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", a.healthz)
	mux.HandleFunc("GET /readyz", a.readyz)
	mux.HandleFunc("GET /version", a.showVersion)
	mux.HandleFunc("GET /api/patients", a.listPatients)
	mux.HandleFunc("POST /api/patients", a.addPatient)
	mux.HandleFunc("GET /api/appointments", a.listAppointments)
	mux.HandleFunc("POST /api/appointments", a.addAppointment)
	return mux
}

func (a *API) healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// readyz answers 200 when the store answers within 2 seconds, and 503 when
// it doesn't, so a load balancer stops sending requests here while the
// database is down. healthz stays 200: the process itself is fine.
func (a *API) readyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.Ping(ctx); err != nil {
		a.log.Warn("not ready", "err", err)
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *API) showVersion(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": a.version})
}

func (a *API) listPatients(w http.ResponseWriter, r *http.Request) {
	patients, err := a.store.ListPatients(r.Context())
	if err != nil {
		a.serverError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, patients)
}

// patientInput is what a client may send. It has no id: the server sets it,
// and an id in the request body is ignored.
type patientInput struct {
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Email string `json:"email"`
}

func (a *API) addPatient(w http.ResponseWriter, r *http.Request) {
	var in patientInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "the JSON is broken")
		return
	}
	if in.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if in.Phone == "" && in.Email == "" {
		writeError(w, http.StatusBadRequest, "phone or email is required")
		return
	}

	p, err := a.store.AddPatient(r.Context(), store.Patient{Name: in.Name, Phone: in.Phone, Email: in.Email})
	if err != nil {
		a.serverError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (a *API) listAppointments(w http.ResponseWriter, r *http.Request) {
	appointments, err := a.store.ListAppointments(r.Context())
	if err != nil {
		a.serverError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, appointments)
}

// appointmentInput is what a client may send. id and reminded_at are left
// out, so they are ignored when a client sends them.
type appointmentInput struct {
	PatientID int64     `json:"patient_id"`
	StartsAt  time.Time `json:"starts_at"`
}

func (a *API) addAppointment(w http.ResponseWriter, r *http.Request) {
	var in appointmentInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "the JSON is broken")
		return
	}
	if in.PatientID == 0 {
		writeError(w, http.StatusBadRequest, "patient_id is required")
		return
	}
	if in.StartsAt.IsZero() {
		writeError(w, http.StatusBadRequest, "starts_at is required")
		return
	}

	appt, err := a.store.AddAppointment(r.Context(), store.Appointment{PatientID: in.PatientID, StartsAt: in.StartsAt})
	if errors.Is(err, store.ErrPatientNotFound) {
		writeError(w, http.StatusBadRequest, "the patient doesn't exist")
		return
	}
	if err != nil {
		a.serverError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, appt)
}

// serverError logs what went wrong and answers 500 without the details,
// which can hold things a client shouldn't see.
func (a *API) serverError(w http.ResponseWriter, r *http.Request, err error) {
	a.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "internal error")
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// writeJSON sends v as JSON with the given status code. An error from Encode
// is ignored: the status line is already sent, so nothing better can be done.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
