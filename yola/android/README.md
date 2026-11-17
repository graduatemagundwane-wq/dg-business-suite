# Yola Android — hosted UI + licence-gated offline POS (QA candidate)

**Source of visual truth:** the original Yola web app at https://yola-onboarding.vercel.app/ is still shown unmodified inside Android WebView, including its phone and tablet/landscape responsive workspace.

**Android QA implementation:** `lib/yola_android/` is a separate offline cashier/receipt area reached from the small Offline button or connection-error screen. It does not replace the hosted layout with a fake offline copy.

## What has been implemented in source

- **Offline checkout:** independent business-scoped SQLite tables for products, sales, sale items and durable outbox. Every sale uses a single database transaction: re-check stock, calculate integer-cent totals and tax, deduct stock, write receipt and queue a uniquely identified event. Failure rolls the transaction back; a repeated idempotency key returns the existing sale.
- **Cash only while offline.** The app never falsely marks an unverified card, EcoCash or bank payment as paid.
- **Signed offline licence:** DG Tech Master Control must approve the Android device. The app checks the same pinned Ed25519 public key and signed business/device-bound licence and short-lived offline lease as the Windows candidate. It rejects expiry and obvious clock rollback. No client-only activation flag or self-generated licence is accepted.
- **Owner PIN:** PBKDF2-protected 6–12 digit PIN saved in Android secure storage after an approved activation, with a short lockout after repeated bad attempts. Each offline session must be unlocked.
- **Inventory import:** the signed-in original Yola web UI fetches `/api/me` and `/api/pos/products`. Android compares the authenticated online business identifier and owner/manager role with its signed licence before caching. Import is blocked while any local events remain unreconciled.
- **Barcode:** camera scanning via `mobile_scanner`, product barcode matching, manual SKU/barcode search for external keyboard/HID scanners.
- **Printing:** persistent receipts can be printed/reprinted with Android's Print Framework via the `printing` plugin and PDF layouts for 58 mm, 80 mm and A4. Bluetooth, USB and network printers require compatible Android print drivers/services. Direct ESC/POS, cash-drawer triggering and exact printer model compatibility are **not** certified.
- **Sync safety:** queued `sale.completed` events retain stable IDs and are sent to `/api/sync/event` in order. The event is marked complete **only** when the server explicitly responds `reconciled: true`. Network errors, 404 and mere inbox acknowledgements leave the event pending.

## Critical outstanding integrations

1. **Hosted Master Control activation** is not yet verified. The Windows release status (18 October 2026) reported that the live `/api/activation/request` and `/api/activation/status` routes were not available. Provision/verify those endpoints and the official signing private key server-side before this device can activate. **Never bundle the signing private key in Android.**
2. **Cloud accounting and stock reconciliation** still needs a server-side `/api/sync/event` implementation that merges events idempotently and returns `reconciled: true` only after a committed transaction. Existing online sales/stock must not be claimed to include pending Android sales.
3. **Online inventory business ID compatibility** must be checked against actual `/api/me` responses. If the hosted API does not disclose an authenticated stable business identifier, catalog caching is intentionally blocked.
4. **Device acceptance:** test camera scanning, USB/Bluetooth/network printing, background/rotation and power-loss recovery on a physical Android phone and tablet.
5. **Production release:** configure secure signing (not the debug Gradle key), persistence/backup and upgrades; validate owner/staff authorization, Android device integrity and permission flows.

## Build / QA

```bash
flutter pub get
flutter analyze lib/main_yola_android.dart lib/yola_android/ lib/screens/barcode_scan.dart
flutter build apk --release -t lib/main_yola_android.dart --build-name 0.2.0 --build-number 2
```

GitHub Actions: `.github/workflows/build-yola-android-same-ui.yml` (named **Yola Android Offline Integration APK QA**).

## Operator flow (after Master Control endpoints work)

1. Open hosted Yola to sign in on Android.
2. Open **Offline** → enter the existing business registration ID and authorised owner credentials, select an offline PIN, and submit for **DG Tech approval**.
3. After actual Master Control approval, press **Check approved licence**. Enter the owner PIN to unlock the offline area.
4. While online, choose **Cache products from signed-in online Yola**; only a matching business owner's or manager's inventory can be imported.
5. Disconnect internet, scan items, take real cash, complete a local sale. Print or reprint the saved receipt.
6. Reconnect and select **Retry cloud reconciliation**. Confirm pending count is zero before importing fresh inventory. If the cloud has not reconciled the sale, keep the device data; **do not uninstall, clear storage, reset or re-import stock**.

**Release classification: QA source / Android build candidate, NOT a ready-to-sell production offline POS.** No physical hardware tests or end-to-end server reconciliation have been reported as complete.
