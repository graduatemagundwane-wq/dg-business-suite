# Yola Android — original UI / APK candidate

**Reference product:** Yola — Powered by Double Gee Tech.

**User requirement:** Android phone APK must render the *actual Yola* mobile workspace, not a visually similar Flutter recreation. When an Android tablet is rotated into landscape, it must render the same desktop-sidebar Yola workspace as the Windows app.

## Single source of visual truth

- Windows (same-design offline candidate) uses `yola/offline/desktop/static/workspace.html` + `pos.css` + `premium.css` + `pos.js`.
- The live Yola app uses that original workspace implementation and is the source opened inside this Android APK by `lib/main_yola_android.dart`.
- The APK does not substitute any Flutter-drawn dashboard, POS, forms, colours, or navigation.
- Android rotation is not locked. The Yola frontend's CSS breakpoints determine mobile and wide-screen modes.

## Current acceptance status

- [x] Android native WebView entrypoint, same live Yola UI URL, normal device rotation.
- [x] Dedicated Android package ID and Yola label.
- [x] CI recipe to apply the official Yola logo and build downloadable test APK.
- [x] CI compilation passed on 20 October 2026 (GitHub Actions run 39489411849; APK artifact 12294464679).\n- [ ] Physical installation on a phone and tablet accepted.
- [ ] Side-by-side screenshots matching original Yola on Android phone / portrait tablet / landscape tablet / Windows PC.
- [ ] Offline signed licence and activation works for Android as it does on Windows.
- [ ] Real offline sales and stock updates integrated with local SQLite.
- [ ] Reconciliation of transactions with hosted Yola stock and ledger.
- [ ] Barcode scanner, printing (USB/Bluetooth/network), cash drawer and receipts verified on real devices.
- [ ] Release signing, upgrade persistence, backups and recovery tests.

**Warning:** The UI test APK currently requires the Yola hosted server. It is **not** a fully offline POS product, nor production client delivery. The original desktop offline backend is Python/FastAPI/SQLite and must be securely ported, adapted or embedded for Android without bypassing existing Master Control licensing.

## Build

```bash
flutter pub get
flutter build apk --release -t lib/main_yola_android.dart --build-name 0.1.0 --build-number 1
```

Until production signing is configured, the Android Gradle release type uses a debug signing key and is suitable **only for testing**. Use GitHub Actions workflow `build-yola-android-same-ui.yml` to produce a branded test artifact.

## Device comparison matrix

| Device | Target Yola workspace | Visual acceptance |
|---|---|---|
| Android phone portrait (360–430 CSS px) | Exact existing Yola phone layout | Same logos, typography, colours, navigation, POS |
| Android phone landscape | Responsive existing Yola layout; no overflow | Every control usable |
| Tablet portrait | Existing tablet/responsive Yola layout | No clipping or hidden sale actions |
| Tablet landscape (800–1280+ CSS px) | Exact desktop Yola sidebar and workspace | Side-by-side reference screenshot |
| Windows PC | Existing premium Yola desktop | Unmodified original baseline |

Only mark the device parity acceptance complete after real device screenshots are compared and all actions pass, not merely because an APK compiled.
