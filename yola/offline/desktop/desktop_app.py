"""Yola Windows shell.

Starts the local-only Yola API and hosts the premium desktop interface in a
native WebView2 window. The customer EXE never exposes the Double Gee Tech admin
secret; commercial activation is handled by the public Yola Control Center API.
"""
import json
import os
import socket
import sys
import threading
import time
import urllib.request
import webbrowser
import tempfile
import traceback
from pathlib import Path

import uvicorn
from local_server import app, STATIC_DIR, VERSION


def free_port(default=8787):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", default))
            return default
        except OSError:
            s.bind(("127.0.0.1", 0))
            return s.getsockname()[1]


def run_server(port):
    # A windowed PyInstaller executable has no stdout/stderr streams. Avoid
    # Uvicorn's console logging configuration and use explicit pure-Python
    # protocols so the packaged server starts reliably on client PCs.
    try:
        config = uvicorn.Config(
            app,
            host="127.0.0.1",
            port=port,
            log_level="warning",
            access_log=False,
            log_config=None,
            loop="asyncio",
            http="h11",
            ws="none",
        )
        uvicorn.Server(config).run()
    except Exception:
        try:
            (Path(tempfile.gettempdir()) / "dg_pos_server_error.log").write_text(
                traceback.format_exc(), encoding="utf-8"
            )
        except Exception:
            pass


def wait_for_server(url: str, timeout: float = 12.0) -> None:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url + "/api/health", timeout=1.0) as res:
                data = json.loads(res.read().decode("utf-8"))
                if data.get("ok"):
                    return
        except Exception as exc:
            last = exc
        time.sleep(0.15)
    raise RuntimeError(f"Yola local service did not start: {last}")


def self_test() -> int:
    """Windows build smoke-test used by CI before a client build is released."""
    if not (STATIC_DIR / "index.html").exists():
        raise RuntimeError(f"Missing packaged UI: {STATIC_DIR / 'index.html'}")
    port = free_port(18787)
    threading.Thread(target=run_server, args=(port,), daemon=True).start()
    url = f"http://127.0.0.1:{port}"
    try:
        wait_for_server(url)
    except Exception as exc:
        err = Path(tempfile.gettempdir()) / "dg_pos_server_error.log"
        detail = err.read_text(encoding="utf-8", errors="replace") if err.exists() else "No server exception was captured."
        raise RuntimeError(f"{exc}\nServer diagnostic:\n{detail}") from exc
    with urllib.request.urlopen(url + "/", timeout=3) as res:
        html = res.read().decode("utf-8", errors="replace")
    required = ["Yola", "Sell", "Products", "Stock Take", "Request activation"]
    missing = [x for x in required if x not in html]
    if missing:
        raise RuntimeError("Packaged UI is incomplete: " + ", ".join(missing))
    return 0


def main():
    if "--self-test" in sys.argv:
        try:
            code = self_test()
            log_path = Path(tempfile.gettempdir()) / "dg_pos_self_test.log"
            log_path.write_text("PASS\n", encoding="utf-8")
            raise SystemExit(code)
        except SystemExit:
            raise
        except Exception:
            log_path = Path(tempfile.gettempdir()) / "dg_pos_self_test.log"
            log_path.write_text(traceback.format_exc(), encoding="utf-8")
            raise SystemExit(1)

    port = free_port(int(os.getenv("DG_POS_PORT", "8787")))
    threading.Thread(target=run_server, args=(port,), daemon=True).start()
    url = f"http://127.0.0.1:{port}"
    try:
        wait_for_server(url)
    except Exception as exc:
        # If the native shell cannot start, surface a clear Windows message rather
        # than leaving the user on a blank/stuck page.
        try:
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, str(exc), "Yola could not start", 0x10)
        except Exception:
            pass
        raise

    try:
        import webview
        webview.create_window(
            "Yola — Powered by Double Gee Tech",
            url,
            width=1440,
            height=920,
            min_size=(1024, 700),
            background_color="#F3F5F8",
            confirm_close=True,
        )
        webview.start(debug=False)
    except Exception:
        # Last-resort fallback still leaves the POS usable through the installed
        # Windows browser instead of presenting a dead window.
        webbrowser.open(url)
        while True:
            time.sleep(3600)


if __name__ == "__main__":
    main()