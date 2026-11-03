# PASH Operations crash fix, v0.5.4 QA
Root cause: LABELS in mobile/App.tsx omitted the Customers display label, while the authorized workspace categories included customers. Following successful sign-in, the app tried to call toLowerCase on the missing label and could crash while rendering the CEO/Manager navigation.
Fix: restored Customers label; added tests/menu_contract.test.js enforcing display labels for every workspace, including all category references.
Earlier native cold-start smoke passed on Android API 35. The emulator screenshot confirmed the login UI renders.
This new QA APK also contains the error boundary and secure-session recovery safeguards from v0.5.3.
No customer records, live website, chatbot, or academy logic changed.
Real-device login validation is still required before production release.
POWERED BY DOUBLE GEE TECH
