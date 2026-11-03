-- PASH workshop image evidence; small, authenticated files in same tenant-scoped database.
CREATE TABLE IF NOT EXISTS job_photos (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id),
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    uploaded_by INTEGER NOT NULL REFERENCES users(id),
    kind VARCHAR(25) NOT NULL,
    content_type VARCHAR(30) NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    byte_size INTEGER NOT NULL,
    content BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_job_photo_size CHECK (byte_size BETWEEN 1 AND 3000000),
    CONSTRAINT ck_job_photo_type CHECK (content_type IN ('image/jpeg','image/png')),
    CONSTRAINT ck_job_photo_kind CHECK (kind IN ('intake','diagnostic','repair','quality','handover'))
);
CREATE INDEX IF NOT EXISTS ix_job_photos_organization_id ON job_photos (organization_id);
CREATE INDEX IF NOT EXISTS ix_job_photos_job_id ON job_photos (job_id);
