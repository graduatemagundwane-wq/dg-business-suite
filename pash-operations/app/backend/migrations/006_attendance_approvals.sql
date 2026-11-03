-- PASH Auto Operations ERP: additive attendance approvals, safe for existing records.
-- Apply to the dedicated operations database before deploying this backend revision.
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS approval_status VARCHAR(16) NOT NULL DEFAULT 'pending';
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS decision_by INTEGER REFERENCES users(id);
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS decision_at TIMESTAMPTZ;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS decision_note VARCHAR(500) NOT NULL DEFAULT '';
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS unpaid_break_minutes INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS ix_pash_attendance_approval_status ON attendance(organization_id,approval_status);
