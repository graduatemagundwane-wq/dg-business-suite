-- Yola Desktop bridge: tenant-scoped device enrolment and idempotent event inbox.
-- This extends the existing DG Tech Master Control Neon database without
-- changing the existing installations, products, staff or licences schema.
CREATE TABLE IF NOT EXISTS yola_desktop_enrollments (
 installation_id UUID NOT NULL REFERENCES installations(id),
 device_uid TEXT PRIMARY KEY,
 claim_hash TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS yola_desktop_enrollments_tenant
 ON yola_desktop_enrollments (installation_id);
CREATE TABLE IF NOT EXISTS yola_desktop_sync_events (
 installation_id UUID NOT NULL REFERENCES installations(id),
 device_uid TEXT NOT NULL,
 event_key TEXT NOT NULL,
 event_type TEXT NOT NULL,
 payload JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (installation_id,device_uid,event_key)
);
CREATE INDEX IF NOT EXISTS yola_desktop_sync_events_tenant_date
 ON yola_desktop_sync_events (installation_id,created_at DESC);