# Yola Windows — exact live UI + local offline POS (candidate)

**Do not give to a paying client yet.**

This project embeds the very same HTML, JavaScript, CSS and Yola artwork from the current live Yola web workspace. The local Windows executable hosts them from 127.0.0.1 with SQLite-backed checkout, stock, refunds, basic double-entry accounting, expenses, receipts, documents and owner settings.

**Activation:** No local administrator key or demo licence exists. The app uses the existing original Yola desktop engine's device-bound Ed25519-signed licence and expiry checks. The Vercel Yola onboarding backend currently does **not** implement the desktop signer. Device activation will return a service error until DG Tech configures and deploys the existing desktop bridge with a secure signing key. Do not disable or replace the licence gate to make it look activated.

**Offline:** After a signed licence and first online sign-in on that computer, cached account verifiers allow local sales while the time-limited licence is valid. Once expired, reconnect to renew. Master Control cannot revoke a device that stays disconnected indefinitely; revocation takes effect on reconnection or lease expiration.

**Data:** Local data are separated from web POS data. The offline outbox retains events but does not yet reconcile them to the hosted Yola stock and ledger, and existing web inventory isn't automatically transferred to this EXE. Resolving that is required before the final production customer release.

**Windows:** Windows runner builds branded `.exe` and runs a packaged self-test. Physical printer, serial, POS terminal and scanner integrations must still be verified with actual supported hardware.

**Tests:** `python test_offline_web.py`. Test uses fake lease in the test process only; production code never accepts a fake licence.