"""Browser viewport smoke test of Yola's ORIGINAL HTML/CSS/JS.

Uses a disposable local HTTP server and mocked read-only API responses.
It does not validate Android WebView rendering, live auth, sales, or offline use.
"""
import functools
import json
import os
from pathlib import Path
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

STATIC = Path(__file__).resolve().parents[1] / "offline" / "desktop" / "static"
SHOTS = Path(__file__).resolve().parent / "qa-screenshots"
USER = {
    "authenticated": True,
    "user": {
        "name": "QA Owner",
        "role": "owner",
        "business": "Yola Responsive QA",
        "license": {"active": True},
    },
}
SUMMARY = {"summary": {
    "sales_total": 7500,
    "sales_count": 3,
    "products": 2,
    "low_stock": 0,
}}
PRODUCTS = {"products": [
    {"id": "p1", "name": "QA Tea", "sku": "QA-001", "barcode": "10001",
     "category": "Beverages", "price_cents": 250, "stock_qty": 10, "min_stock": 2},
    {"id": "p2", "name": "QA Water", "sku": "QA-002", "barcode": "10002",
     "category": "Beverages", "price_cents": 100, "stock_qty": 20, "min_stock": 3},
]}


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def mock_api(route):
    path = urlsplit(route.request.url).path
    data = {
        "/api/me": USER,
        "/api/pos/summary": SUMMARY,
        "/api/pos/products": PRODUCTS,
    }.get(path)
    if data is None:
        route.fulfill(status=501, content_type="application/json",
                      body=json.dumps({"error": "Not mocked: " + path}))
    else:
        route.fulfill(status=200, content_type="application/json",
                      body=json.dumps(data))


def main():
    SHOTS.mkdir(parents=True, exist_ok=True)
    handler = functools.partial(QuietHandler, directory=str(STATIC))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    base = "http://127.0.0.1:" + str(server.server_port)
    sizes = [
        ("phone-portrait", 390, 844, False),
        ("phone-landscape", 844, 390, True),
        ("tablet-portrait", 768, 1024, False),
        ("tablet-landscape", 1024, 768, True),
        ("desktop", 1280, 800, True),
    ]
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                headless=True, executable_path=os.environ.get("DG_BROWSER_PATH") or None,
                args=["--no-sandbox", "--disable-dev-shm-usage"],
            )
            try:
                for name, width, height, wide in sizes:
                    page = browser.new_page(viewport={"width": width, "height": height},
                                            device_scale_factor=1)
                    errors = []
                    page.on("pageerror", lambda error: errors.append(str(error)))
                    page.route("**/api/**", mock_api)
                    page.goto(base + "/workspace.html", wait_until="domcontentloaded")
                    page.locator("#body .cards .card").first.wait_for(timeout=12000)
                    page.locator('[data-page="sell"]').click()
                    page.locator("#results .product").first.wait_for(timeout=12000)
                    assert page.locator("#screen-title").inner_text() == "Sell", name
                    assert page.locator("#complete").is_visible(), name
                    layout = page.evaluate("""() => ({
                        shell: getComputedStyle(document.querySelector('#shell')).display,
                        sidebarWidth: document.querySelector('.sidebar').getBoundingClientRect().width,
                        viewport: window.innerWidth,
                        scrollWidth: document.documentElement.scrollWidth
                    })""")
                    assert layout["scrollWidth"] <= width + 3, (
                        name, "unexpected horizontal page overflow", layout)
                    if wide:
                        assert layout["shell"] == "grid", (name, layout)
                        assert 260 <= layout["sidebarWidth"] <= 270, (name, layout)
                    else:
                        assert layout["shell"] == "block", (name, layout)
                    assert not errors, (name, errors)
                    page.screenshot(path=str(SHOTS / (name + ".png")), full_page=True)
                    print("PASS", name, json.dumps(layout))
                    page.close()
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=5)
    print("PASS: Original Yola HTML/CSS/JS responsive browser smoke (mock data).")
    print("NOT TESTED: Android WebView, physical device, live API, offline POS.")


if __name__ == "__main__":
    main()
