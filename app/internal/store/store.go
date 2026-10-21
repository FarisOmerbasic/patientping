// Package store holds the types the API stores, and the Store interface the
// handlers use to reach them.
package store

import (
	"context"
	"errors"
	"time"
)

// ErrPatientNotFound means an appointment points to a patient that doesn't exist.
var ErrPatientNotFound = errors.New("patient not found")

// Patient is a person who gets reminders. The server sets ID.
type Patient struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	Email string `json:"email"`
}

// Appointment is a visit by one patient at one time. RemindedAt stays nil
// (null in JSON) until the worker sends the reminder.
type Appointment struct {
	ID         int64      `json:"id"`
	PatientID  int64      `json:"patient_id"`
	StartsAt   time.Time  `json:"starts_at"`
	RemindedAt *time.Time `json:"reminded_at"`
}

// Store is everything the handlers need from storage. Memory implements it
// now, and SQL Server will implement the same methods on Day 17.
type Store interface {
	ListPatients(ctx context.Context) ([]Patient, error)
	AddPatient(ctx context.Context, p Patient) (Patient, error)
	ListAppointments(ctx context.Context) ([]Appointment, error)
	AddAppointment(ctx context.Context, a Appointment) (Appointment, error)
}
