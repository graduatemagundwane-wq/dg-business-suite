-- PASH Auto v0.4.0: revocable app sessions. Apply to dedicated PASH Operations staging first.
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;
