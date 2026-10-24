package store

import (
	"context"
	"sync"
)

// Memory keeps everything in two lists in memory. All data is lost when the
// process stops.
type Memory struct {
	mu           sync.Mutex
	patients     []Patient
	appointments []Appointment
}

// NewMemory returns an empty in-memory store.
func NewMemory() *Memory {
	return &Memory{}
}

// ListPatients returns a copy of all patients, so a caller can't change the
// store's own list.
func (m *Memory) ListPatients(ctx context.Context) ([]Patient, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Patient{}, m.patients...), nil
}

// AddPatient gives p the next ID and stores it.
func (m *Memory) AddPatient(ctx context.Context, p Patient) (Patient, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	p.ID = int64(len(m.patients) + 1)
	m.patients = append(m.patients, p)
	return p, nil
}

// ListAppointments returns a copy of all appointments.
func (m *Memory) ListAppointments(ctx context.Context) ([]Appointment, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Appointment{}, m.appointments...), nil
}

// AddAppointment stores a, or returns ErrPatientNotFound if its patient
// doesn't exist.
func (m *Memory) AddAppointment(ctx context.Context, a Appointment) (Appointment, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.hasPatient(a.PatientID) {
		return Appointment{}, ErrPatientNotFound
	}
	a.ID = int64(len(m.appointments) + 1)
	m.appointments = append(m.appointments, a)
	return a, nil
}

// hasPatient reports whether a patient with this ID exists. The caller must
// hold m.mu.
func (m *Memory) hasPatient(id int64) bool {
	for _, p := range m.patients {
		if p.ID == id {
			return true
		}
	}
	return false
}

// Ping always succeeds: memory is always there.
func (m *Memory) Ping(ctx context.Context) error {
	return nil
}
