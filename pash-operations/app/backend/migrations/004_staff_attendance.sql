-- Attendance: new staff clock-in/out records, PASH Operations database only.
CREATE TABLE IF NOT EXISTS attendance (
 id SERIAL PRIMARY KEY,
 organization_id INTEGER NOT NULL REFERENCES organizations(id),
 user_id INTEGER NOT NULL REFERENCES users(id),
 clock_in TIMESTAMPTZ NOT NULL DEFAULT now(),
 clock_out TIMESTAMPTZ NULL,
 CONSTRAINT chk_attendance_time CHECK (clock_out IS NULL OR clock_out >= clock_in)
);
CREATE INDEX IF NOT EXISTS ix_attendance_organization_id ON attendance(organization_id);
CREATE INDEX IF NOT EXISTS ix_attendance_user_id ON attendance(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS ix_attendance_open_shift ON attendance(organization_id,user_id) WHERE clock_out IS NULL;
