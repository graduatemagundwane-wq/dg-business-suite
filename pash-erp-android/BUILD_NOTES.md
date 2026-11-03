# PASH Auto ERP Android — connected QA build

This isolated branch builds a PASH Auto Administration **Android test launcher**. It is not the public PASH website, chatbot, academy, or a signed production release.

The first launch now loads the verified PASH Auto Operations QA frontend at https://pash-auto-operations-qa.onrender.com automatically. Existing saved server preferences remain respected. To change the address, use Android Back > Change server address.

QA checks on 3 November 2026 confirmed `/api/health` and `/api/ready` responded successfully, and a separately provisioned PASH Auto Operations QA Neon database contains the expected ERP tables. These checks are **not** end-to-end user acceptance tests.

The build workflow produces a DEBUG-signed QA APK. It does not embed passwords, API tokens, client records, or a database connection string. No demo records are created. The standalone React Native Operations app and its backend remain separate from this launcher.

Before production: prove role permissions, attendance approvals, POS and inventory transactions, invoice/PDF delivery, file uploads, backup/restore, and real-device behavior. Ensure durable file storage and backup verification, production signing, monitoring, and an approved deployment target. Do not classify this QA artifact as production-ready.
