# DG POS Business — three independent Android APKs

Three Android APKs, each with a unique package ID and isolated WebView data:

* `DG Control` — `zw.co.doublegeetech.dgpos.admin`: Double Gee Tech administrator login.
* `DG Owner POS` — `zw.co.doublegeetech.dgpos.owner`: business owner and managers.
* `DG Worker POS` — `zw.co.doublegeetech.dgpos.worker`: workers / cashiers.

These are **native-installable Android APKs with secure WebView interfaces** to the existing DG POS Business online application. Their APK packages do not embed passwords, database credentials, or privileged SQL keys; server enforces permissions. They are not native offline databases. The worker offline queue still needs device acceptance testing. Each app initially requires Internet to sign in.

Build with Android SDK 35, Java 17, Gradle 8.10.2:
`gradle :app:assembleDebug`

The debug-signed APKs install directly on Android but are not Play Store release-signed; for paid distribution, sign stable release APKs with a securely stored release signing key outside the repository.
