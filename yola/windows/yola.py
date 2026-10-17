"""Yola Windows desktop client — live Master Control connected web workspace.

This app deliberately does not contain database credentials or licensing secrets.
Business registration and activation are enforced by the hosted Yola API, backed
by the existing DG Tech Master Control. Offline transactions are NOT enabled.
"""
import argparse
import json
import os
import sys
import threading
import time
from urllib.request import Request, urlopen
from urllib.error import URLError

APP_NAME = "Yola — Powered by Double Gee Tech"
BASE_URL = "https://yola-onboarding.vercel.app"
HEALTH_URL = BASE_URL + "/api/health"
WINDOW = None

def live_health(timeout=8):
    request = Request(HEALTH_URL, headers={"User-Agent": "Yola-Windows/1.0", "Cache-Control": "no-cache"})
    with urlopen(request, timeout=timeout) as res:
        if res.status != 200:
            raise RuntimeError(f"Yola cloud returned HTTP {res.status}")
        payload = json.loads(res.read(4096))
        if not (payload.get("ok") and payload.get("licensingAuthority") == "DG Tech Master Control" and payload.get("productIntegration") == "connected"):
            raise RuntimeError("The Yola server has not verified its Master Control integration.")
        return payload

def offline_html(reason="Cannot reach Yola"):
    # Static, self-contained recovery screen; don't interpolate network messages.
    return """<!doctype html><html><head><meta charset='utf-8'>
    <meta name='viewport' content='width=device-width,initial-scale=1'>
    <style>body{margin:0;background:#f5f7fb;color:#0f2740;font:16px 'Segoe UI',sans-serif;display:grid;place-items:center;min-height:100vh}
    article{max-width:490px;text-align:center;background:white;padding:46px;border-radius:24px;box-shadow:0 16px 55px #102a4b20}
    .logo{font-size:60px;color:#b88232}.gold{background:linear-gradient(135deg,#ffdc8c,#be883c);padding:12px 23px;border-radius:17px;color:#122b45;font-weight:900}
    h1{font-size:25px}p{color:#566b80;line-height:1.7}button{background:#b78b49;color:#0a1e32;padding:14px 25px;border:0;border-radius:12px;font-weight:700;cursor:pointer}
    small{display:block;margin-top:24px;color:#768ba0}</style></head>
    <body><article><div class='logo'><span class='gold'>Y</span></div><h1>Yola cannot connect right now</h1>
    <p>Check your internet connection, then select Retry. No new sale has been recorded on this screen.</p>
    <button onclick='window.pywebview.api.retry_connection()'>Retry connection</button>
    <small>Yola · Powered by Double Gee Tech<br>Activated through DG Tech Master Control</small></article></body></html>"""

class NativeBridge:
    """Read-only device discovery. Never makes privileged changes to hardware."""
    def list_devices(self):
        if sys.platform != "win32":
            return {"supported": False, "printers": [], "devices": [], "reason": "Windows device enumeration is unavailable."}
        import subprocess
        printers = []
        try:
            import win32print
            printers = [p[2] for p in win32print.EnumPrinters(win32print.PRINTER_ENUM_LOCAL | win32print.PRINTER_ENUM_CONNECTIONS)]
        except Exception:
            pass
        devices = []
        try:
            ps = "Get-PnpDevice -PresentOnly | Where-Object {$_.Class -in @('HIDClass','USB','Ports','Printer','Keyboard','Mouse','Bluetooth')} | Select-Object Class,FriendlyName,Status | ConvertTo-Json -Compress"
            p = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=12,
                               check=False, creationflags=subprocess.CREATE_NO_WINDOW)
            if p.returncode == 0 and p.stdout:
                obj = json.loads(p.stdout.decode("utf-8-sig", errors="replace"))
                devices = obj if isinstance(obj, list) else [obj]
        except Exception:
            pass
        return {"supported": True, "printers": printers[:128], "devices": devices[:256],
                "notice": "Discovery does not guarantee a driver, protocol or payment-terminal integration."}

    def retry_connection(self):
        def do_retry():
            try:
                live_health()
                if WINDOW: WINDOW.load_url(BASE_URL)
            except Exception:
                if WINDOW: WINDOW.load_html(offline_html())
        threading.Thread(target=do_retry, daemon=True).start()
        return {"checking": True}

def run_selftest(live=False):
    assert BASE_URL.startswith("https://")
    assert "/api/health" in HEALTH_URL
    assert "DG Tech Master Control" in APP_NAME or APP_NAME.endswith("Double Gee Tech")
    html=offline_html()
    assert "Retry connection" in html
    if live: live_health()
    print("PASS YOLA WINDOWS SELF-TEST" + (" + LIVE MASTER CONTROL HEALTH" if live else ""))
    return 0

def start_window():
    import webview
    global WINDOW
    WINDOW = webview.create_window(APP_NAME, html="""<html><head><meta charset='utf-8'></head><body style='font:19px Segoe UI;background:#f8fafc;color:#18324f;display:grid;place-items:center;height:100vh;margin:0'><div style='text-align:center'><h1>Yola</h1><p>Connecting securely to your business...</p></div></body></html>""",
        js_api=NativeBridge(), width=1440, height=900, min_size=(930, 620), background_color="#f6f8fb",
        confirm_close=False, text_select=False)
    def initialize():
        try:
            live_health(timeout=12)
            WINDOW.load_url(BASE_URL)
        except (Exception,):
            WINDOW.load_html(offline_html())
    # Edge WebView2 on Windows provides the Chromium controls and print dialog.
    try:
        webview.start(initialize, gui="edgechromium", debug=False, private_mode=False)
    except Exception as exc:
        # Exit with error rather than trapping users in an invisible window.
        print(f"Yola desktop cannot start: {exc}", file=sys.stderr)
        return 1
    return 0

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--self-test",action="store_true")
    parser.add_argument("--check-live",action="store_true")
    args=parser.parse_args()
    if args.self_test: return run_selftest(live=args.check_live)
    if args.check_live: return run_selftest(live=True)
    return start_window()

if __name__ == "__main__":
    try: sys.exit(main())
    except Exception as e:
        print(f"Yola: {e}", file=sys.stderr)
        sys.exit(1)
