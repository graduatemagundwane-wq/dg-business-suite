# PASH Auto Administration ERP — integration branch
This branch expands the existing v0.5.0 isolated source archive into individual, reviewable source files to enable controlled development. The original QA branch and deployed Render service are unchanged.

Tests are run on GitHub Actions for Python API, the barcode utility, and TypeScript. **Do not** infer production readiness from passing unit tests. The currently live QA service at https://pash-auto-operations-qa.onrender.com reports health and schema readiness.

Production blockers remain: production hosting/configuration and persistent media storage review; least-privilege Worker/Manager/CEO testing; attendance-to-payroll and POS/inventory end-to-end transactions; PDF/WhatsApp/email report deliveries; Google Drive backup & restore implementation and tests; device signing and offline behavior; iOS distribution and Windows client acceptance. Separate PASH website/chatbot/academy remain out of scope.

POWERED BY DOUBLE GEE TECH
