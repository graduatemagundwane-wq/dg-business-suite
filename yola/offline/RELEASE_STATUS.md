# Yola — exact-premium-UI offline desktop release candidate

Last inspected: 18 October 2026

## Verified in the source test runtime
- Preserved Yola premium workspace HTML, CSS, navigation, logo and checkout JS from the currently deployed web project; local change only in the account setup status page.
- Local SQLite schema with business-bound products, stock, sales, receipts, quotations, unposted invoices, refunds, expenses and double-entry accounting.
- Checkout is transactional, no overselling within a local database, idempotent by checkout key, posts balanced accounting entries and queues events for later sync.
- Owner vs worker API restrictions, signed licence gate, expiry denial, cross-business separation, password hash verifiers and offline re-login tested using *simulation in QA only*.
- FastAPI local startup self-test passed.

## Not yet verified / blockers
1. Production desktop device signing service: the Yola hosted service does not expose compatible `/api/activation/request`, `/api/activation/status` and `/api/license/verify` endpoints from the proposed bridge; the secure Ed25519 signing key is not provisioned. This candidate cannot activate a new device until that live service is deployed and tested. Client does NOT self-activate.
2. Existing online stock/sales/accounting and new offline transactions are not reconciled between hosted Yola and local SQLite. Events are durable locally but `synced=0`; do not imply web accounts display them.
3. Windows full GUI end-to-end, receipt printer, scanner, cash drawer and payment hardware tests on the actual customer machine remain.
4. Offline licence expiration means the client periodically must reconnect, in order for Master Control suspension/expiry to be enforced. No remote service can revoke a completely disconnected device immediately.
5. WhatsApp owner low-stock messages queue while offline; they cannot be delivered without internet and provider credentials/template.

Do not hand over this candidate to a paying customer as finished software.