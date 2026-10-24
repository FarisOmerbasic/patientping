package store

import (
	"context"
	"database/sql"
	"errors"
	"net/url"

	mssql "github.com/microsoft/go-mssqldb"
)

// MSSQL keeps everything in SQL Server. The tables come from the files in
// migrations/, not from this code.
type MSSQL struct {
	db *sql.DB
}

// NewMSSQL prepares a connection to the database name on the server at addr
// (host:port). It doesn't connect yet: the first query or Ping does.
func NewMSSQL(addr, name, user, password string) (*MSSQL, error) {
	u := url.URL{
		Scheme:   "sqlserver",
		User:     url.UserPassword(user, password),
		Host:     addr,
		RawQuery: url.Values{"database": {name}}.Encode(),
	}
	db, err := sql.Open("sqlserver", u.String())
	if err != nil {
		return nil, err
	}
	return &MSSQL{db: db}, nil
}

// Ping reports whether SQL Server answers.
func (s *MSSQL) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

// ListPatients returns all patients, oldest first.
func (s *MSSQL) ListPatients(ctx context.Context) ([]Patient, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT id, name, phone, email FROM patients ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	patients := []Patient{}
	for rows.Next() {
		var p Patient
		if err := rows.Scan(&p.ID, &p.Name, &p.Phone, &p.Email); err != nil {
			return nil, err
		}
		patients = append(patients, p)
	}
	return patients, rows.Err()
}

// AddPatient stores p and returns it with the ID SQL Server gave it.
func (s *MSSQL) AddPatient(ctx context.Context, p Patient) (Patient, error) {
	err := s.db.QueryRowContext(ctx,
		"INSERT INTO patients (name, phone, email) OUTPUT INSERTED.id VALUES (@p1, @p2, @p3)",
		p.Name, p.Phone, p.Email,
	).Scan(&p.ID)
	return p, err
}

// ListAppointments returns all appointments, oldest first.
func (s *MSSQL) ListAppointments(ctx context.Context) ([]Appointment, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT id, patient_id, starts_at, reminded_at FROM appointments ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	appointments := []Appointment{}
	for rows.Next() {
		var a Appointment
		if err := rows.Scan(&a.ID, &a.PatientID, &a.StartsAt, &a.RemindedAt); err != nil {
			return nil, err
		}
		appointments = append(appointments, a)
	}
	return appointments, rows.Err()
}

// AddAppointment stores a, or returns ErrPatientNotFound if its patient
// doesn't exist. starts_at has no time zone, so it's stored in UTC.
func (s *MSSQL) AddAppointment(ctx context.Context, a Appointment) (Appointment, error) {
	a.StartsAt = a.StartsAt.UTC()
	err := s.db.QueryRowContext(ctx,
		"INSERT INTO appointments (patient_id, starts_at) OUTPUT INSERTED.id VALUES (@p1, @p2)",
		a.PatientID, a.StartsAt,
	).Scan(&a.ID)
	if isForeignKeyError(err) {
		return Appointment{}, ErrPatientNotFound
	}
	return a, err
}

// isForeignKeyError reports whether err is SQL Server's error 547: the row
// points to a row in another table that doesn't exist.
func isForeignKeyError(err error) bool {
	var e mssql.Error
	return errors.As(err, &e) && e.Number == 547
}
