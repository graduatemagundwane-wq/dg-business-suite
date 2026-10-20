"""Static contract tests for the Yola same-source Android UI candidate.

These tests verify source wiring only, not device visual parity or offline POS.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
STATIC = ROOT / "yola" / "offline" / "desktop" / "static"


class YolaAndroidContract(unittest.TestCase):
    def test_android_uses_hosted_yola_workspace(self):
        dart = (ROOT / "lib" / "main_yola_android.dart").read_text()
        self.assertIn("https://yola-onboarding.vercel.app/", dart)
        self.assertIn("WebViewWidget(controller: _web)", dart)
        self.assertIn("JavaScriptMode.unrestricted", dart)
        self.assertNotIn("DeviceOrientation.portraitUp", dart)
        self.assertNotIn("DeviceOrientation.landscapeLeft", dart)

    def test_original_workspace_has_mobile_viewport(self):
        html = (STATIC / "workspace.html").read_text()
        self.assertIn('name="viewport"', html)
        self.assertIn('width=device-width', html)
        self.assertIn('href="/pos.css"', html)
        self.assertIn('href="/premium.css"', html)
        self.assertIn('src="/pos.js"', html)

    def test_phone_and_landscape_tablet_breakpoints(self):
        premium = (STATIC / "premium.css").read_text()
        self.assertIn("grid-template-columns:266px", premium)
        self.assertIn("@media(max-width:780px)", premium)
        self.assertIn("#shell{display:block}", premium)
        self.assertIn("@media screen and (min-width:781px)", premium)

    def test_android_permissions_and_app_identity(self):
        manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text()
        gradle = (ROOT / "android/app/build.gradle.kts").read_text()
        self.assertIn('android.permission.INTERNET', manifest)
        self.assertIn('android:label="Yola"', manifest)
        self.assertIn('android:allowBackup="false"', manifest)
        self.assertIn('android:usesCleartextTraffic="false"', manifest)
        self.assertIn('com.doublegeetech.yola.android', gradle)


if __name__ == "__main__":
    unittest.main()
