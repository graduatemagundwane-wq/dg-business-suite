# Yola Desktop licensing and syncing bridge — review required

This code is **not deployed**. Existing Master Control remains the sole source of business activation and device limits.

When `YOLA_DESKTOP_PKCS8_B64` is correctly provisioned on the existing Yola Vercel service, `desktop.js` verifies the owner's existing Yola email/password against `yola_web_users`, requires that business installation and product account to be active in Master Control, ensures devices belong to the right business, and issues Ed25519-signed leases that expire after the Master-configured offline grace period (capped at 72 hours).

The bridge implements `/api/public-key`, `/api/activation/request`, `/api/activation/status`, `/api/license/verify`, and `/api/sync/event`. Integrate it into the existing `api/index.js` router **without replacing the other Yola registration, staff or POS routes**.

The public key embedded into Windows EXE must match the deployed server key exactly. **Never store the private key in the EXE, GitHub, or client document.** The production signing environment cannot be set up via the available connection in this turn, so any binary using this public key will remain unactivated until this issue is resolved. Do not generate new per-deployment signers that would invalidate offline customer licences.

The event endpoint records customer events durably with an idempotency key, but responds `reconciled:false`: cloud inventory/accounting balances are **not yet reconciled**. The Windows agent retains these events as pending rather than marking them fully synchronized. Completing reconciliation requires an audited importer with product SKU matching, cash/bank journal balancing, returns, client/branch isolation and conflict resolution before commercial release.

Compatibility tests with disposable signing keys and simulated business status pass. **Production enrollment/renewal/revocation/expiry must still be tested with a real administrator-approved Yola test installation.**