CREATE TABLE patients (
    id    BIGINT IDENTITY(1,1) PRIMARY KEY,
    name  NVARCHAR(200) NOT NULL,
    phone NVARCHAR(50)  NOT NULL,
    email NVARCHAR(254) NOT NULL
);

CREATE TABLE appointments (
    id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    patient_id  BIGINT NOT NULL REFERENCES patients(id),
    starts_at   DATETIME2 NOT NULL,
    reminded_at DATETIME2 NULL
);

CREATE INDEX ix_appointments_starts_at ON appointments (starts_at);
