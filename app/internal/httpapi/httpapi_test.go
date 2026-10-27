package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/FarisOmerbasic/patientping/app/internal/store"
)

// newTestAPI returns an API on a fresh memory store that already holds one
// patient, Ana, with id 1.
func newTestAPI(t *testing.T) http.Handler {
	t.Helper()
	s := store.NewMemory()
	if _, err := s.AddPatient(context.Background(), store.Patient{Name: "Ana", Phone: "+38761000000"}); err != nil {
		t.Fatal(err)
	}
	return New(s, "test", slog.New(slog.DiscardHandler)).Routes()
}

func TestAPI(t *testing.T) {
	tests := []struct {
		name     string
		method   string
		path     string
		body     string
		wantCode int
		wantBody string
	}{
		{"healthz", "GET", "/healthz", "", 200, `{"status":"bad"}`},
		{"readyz", "GET", "/readyz", "", 200, `{"status":"ready"}`},
		{"version", "GET", "/version", "", 200, `{"version":"test"}`},
		{"unknown path", "GET", "/nope", "", 404, "404 page not found"},
		{"wrong method", "DELETE", "/api/patients", "", 405, "Method Not Allowed"},

		{"list patients", "GET", "/api/patients", "", 200,
			`[{"id":1,"name":"Ana","phone":"+38761000000","email":""}]`},
		{"add patient", "POST", "/api/patients", `{"name":"Ben","email":"ben@example.com"}`, 201,
			`{"id":2,"name":"Ben","phone":"","email":"ben@example.com"}`},
		{"add patient, id from the client is ignored", "POST", "/api/patients", `{"id":99,"name":"Ben","phone":"+1"}`, 201,
			`{"id":2,"name":"Ben","phone":"+1","email":""}`},
		{"add patient, broken JSON", "POST", "/api/patients", `{"name":`, 400, `{"error":"the JSON is broken"}`},
		{"add patient, no name", "POST", "/api/patients", `{"phone":"+1"}`, 400, `{"error":"name is required"}`},
		{"add patient, no phone or email", "POST", "/api/patients", `{"name":"Ben"}`, 400,
			`{"error":"phone or email is required"}`},

		{"list appointments, none yet", "GET", "/api/appointments", "", 200, `[]`},
		{"add appointment", "POST", "/api/appointments", `{"patient_id":1,"starts_at":"2026-11-03T09:30:00Z"}`, 201,
			`{"id":1,"patient_id":1,"starts_at":"2026-11-03T09:30:00Z","reminded_at":null}`},
		{"add appointment, reminded_at from the client is ignored", "POST", "/api/appointments",
			`{"patient_id":1,"starts_at":"2026-11-03T09:30:00Z","reminded_at":"2026-11-01T08:00:00Z"}`, 201,
			`{"id":1,"patient_id":1,"starts_at":"2026-11-03T09:30:00Z","reminded_at":null}`},
		{"add appointment, broken JSON", "POST", "/api/appointments", `not json`, 400, `{"error":"the JSON is broken"}`},
		{"add appointment, time not RFC 3339", "POST", "/api/appointments", `{"patient_id":1,"starts_at":"tomorrow"}`, 400,
			`{"error":"the JSON is broken"}`},
		{"add appointment, no patient_id", "POST", "/api/appointments", `{"starts_at":"2026-11-03T09:30:00Z"}`, 400,
			`{"error":"patient_id is required"}`},
		{"add appointment, no starts_at", "POST", "/api/appointments", `{"patient_id":1}`, 400,
			`{"error":"starts_at is required"}`},
		{"add appointment, patient doesn't exist", "POST", "/api/appointments", `{"patient_id":99,"starts_at":"2026-11-03T09:30:00Z"}`, 400,
			`{"error":"the patient doesn't exist"}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, strings.NewReader(tt.body))
			rec := httptest.NewRecorder()

			newTestAPI(t).ServeHTTP(rec, req)

			if rec.Code != tt.wantCode {
				t.Errorf("code = %d, want %d", rec.Code, tt.wantCode)
			}
			if got := strings.TrimSpace(rec.Body.String()); got != tt.wantBody {
				t.Errorf("body = %s, want %s", got, tt.wantBody)
			}
		})
	}
}

// brokenStore is a Store whose every call fails. It stands in for a database
// that has gone away, which the memory store can't show.
type brokenStore struct{}

var errBroken = errors.New("store is down")

func (brokenStore) Ping(context.Context) error                            { return errBroken }
func (brokenStore) ListPatients(context.Context) ([]store.Patient, error) { return nil, errBroken }
func (brokenStore) AddPatient(context.Context, store.Patient) (store.Patient, error) {
	return store.Patient{}, errBroken
}
func (brokenStore) ListAppointments(context.Context) ([]store.Appointment, error) {
	return nil, errBroken
}
func (brokenStore) AddAppointment(context.Context, store.Appointment) (store.Appointment, error) {
	return store.Appointment{}, errBroken
}

func TestStoreFails(t *testing.T) {
	tests := []struct {
		name   string
		method string
		path   string
		body   string
	}{
		{"list patients", "GET", "/api/patients", ""},
		{"add patient", "POST", "/api/patients", `{"name":"Ben","phone":"+1"}`},
		{"list appointments", "GET", "/api/appointments", ""},
		{"add appointment", "POST", "/api/appointments", `{"patient_id":1,"starts_at":"2026-11-03T09:30:00Z"}`},
	}

	api := New(brokenStore{}, "test", slog.New(slog.DiscardHandler)).Routes()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, strings.NewReader(tt.body))
			rec := httptest.NewRecorder()

			api.ServeHTTP(rec, req)

			if rec.Code != http.StatusInternalServerError {
				t.Errorf("code = %d, want 500", rec.Code)
			}
			if got, want := strings.TrimSpace(rec.Body.String()), `{"error":"internal error"}`; got != want {
				t.Errorf("body = %s, want %s", got, want)
			}
		})
	}
}

func TestReadyzStoreDown(t *testing.T) {
	api := New(brokenStore{}, "test", slog.New(slog.DiscardHandler)).Routes()
	req := httptest.NewRequest("GET", "/readyz", nil)
	rec := httptest.NewRecorder()

	api.ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("code = %d, want 503", rec.Code)
	}
	if got, want := strings.TrimSpace(rec.Body.String()), `{"status":"not ready"}`; got != want {
		t.Errorf("body = %s, want %s", got, want)
	}
}
