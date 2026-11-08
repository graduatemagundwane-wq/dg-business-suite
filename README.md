# IrvinAero Aviation — E-learning Staging

This branch holds the IrvinAero 64-screen development platform for a separate Railway staging service. It is intentionally isolated from dg-business-suite main.

- Backend: Python ThreadingHTTPServer, SQLite, PDF and QR-code libraries.
- Frontend: vanilla JS/CSS responsive academy portal.
- Operational dependencies: persistent Railway volume mounted at /data; IRVINAERO_DB=/data/irvinaero.sqlite3; IRVINAERO_UPLOADS=/data/uploads.
- Demo accounts must NOT be enabled on public staging. IRVINAERO_DEMO=0; configure a unique IRVINAERO_ADMIN_PASSWORD and IRVINAERO_ADMIN_EMAIL in Railway variables.
- Integrations (EcoCash/WhatsApp/SMS/Zoom/aviation licensing) are not connected. Do not accept real payments, personal student documents, or official flying hours in public staging.

The initial data and content is illustrative and subject to academic and regulatory approval.
