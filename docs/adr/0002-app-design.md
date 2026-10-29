# ADR 0002: Design of the Go API

- **Status:** proposed
- **Date:** 2026-10-20

## Context
PatientPing lets clinics store patients and appointments, and a worker sends reminders before each appointment. It's the app that the rest of the project builds, ships to AWS and monitors. It starts small: the data is kept in memory, without a database, so it runs and can be tested anywhere at once.

## Options considered

**The web part**
1. **Standard library (`net/http`):** routes by method and path since Go 1.22. No extra dependency to keep updated and scan, but fewer features than a framework.
2. **A framework (Gin or chi):** more features, but one more dependency to keep updated and scan.

**The storage**
1. **In memory, behind a `Store` interface:** runs and can be tested anywhere, with no database. All data is lost on every restart.
2. **SQL Server from the start:** the data survives a restart, but a database has to run before the first test can.

## Decision
We chose the standard library, because it needs no extra dependency.
We chose the in-memory store behind a `Store` interface, because it runs anywhere now, and on Day 17 SQL Server takes its place without changing the handlers.

## Spec

### Entities

**Patient**

| Field | Type | Rules |
|---|---|---|
| id | integer | set by the server |
| name | text | required |
| phone | text | required if email is empty |
| email | text | required if phone is empty |

**Appointment**

| Field | Type | Rules |
|---|---|---|
| id | integer | set by the server |
| patient_id | integer | required |
| starts_at | time (RFC 3339) | required |
| reminded_at | time (RFC 3339) | empty until the worker sends the reminder |

### Endpoints

| Method | Path | What it does | Answers |
|---|---|---|---|
| GET | /healthz | says the process is alive | 200 |
| GET | /readyz | says the API can serve requests now | 200; 503 when not ready (the database check comes on Day 17) |
| GET | /version | says which version is running (`dev` until Day 26) | 200 |
| GET | /api/patients | lists all patients | 200 with a JSON list |
| POST | /api/patients | adds a patient | 201 with the new patient; 400 if the JSON is broken, the name is missing, or both phone and email are empty |
| GET | /api/appointments | lists all appointments | 200 with a JSON list |
| POST | /api/appointments | adds an appointment | 201 with the new appointment; 400 if the JSON is broken, patient_id or starts_at is missing, or the patient doesn't exist |

### Configuration

| Variable | Default | What it sets |
|---|---|---|
| PORT | 8080 | the port the API listens on |

### Logs

One JSON object per line. The line the API writes when it starts:
`{"time":"2026-10-21T00:15:00Z","level":"INFO","msg":"listening","port":"8080","version":"dev"}`

## Consequences
- Easier: the API builds and its tests run on any machine with Go, with no database.
- Harder: all data is lost on every restart until Day 17.
- Follow-up: Day 17 adds SQL Server as a second implementation of the same interface.
- Settings are added when they're needed, not in advance.
