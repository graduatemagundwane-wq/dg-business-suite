"""Browser layout regression for Yola's *actual* shared HTML/CSS/JS.

This exercises the same original frontend at phone and landscape-tablet widths
with mocked API responses. It does NOT certify an Android WebView, native
hardware, offline sales, or pixel-perfect physical-device appearance.
"""
import json
import re
import tempfile
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

STATIC = Path(__file__).resolve().parents[1] / "offline" / "desktop" / "static"


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def serve():
    server = ThreadingHTTPServer(
        ("127.0.0.1", 0),
        partial(QuietHandler, directory=str(STATIC)),
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


USER = {
    "authenticated": True,
    "user": {
        "id": "layout-test-user",
        "role": "owner",
        "name": "Yola QA",
        "business": "Yola QA",
        "license": {"active": True},
    },
}
SUMMARY = {
    "summary": {
        "sales_total": 12500,
        "sales_count": 7,
        "products": 1,
        "low_stock": 0,
    },
}
PRODUCTS = {
    "products": [
        {
            "id": "test-001",
            "name": "Layout Test Product",
            "sku": "QA-001",
            "barcode": "123456789",
            "category": "General",
            "stock_qty": 12,
            "min_stock": 2,
            "price_cents": 500,
            "tax_bps": 0,
        }
    ]
}


def mock_api(route):
    path = urlparse(route.request.url).path
    response = {
        "/api/me": USER,
        "/api/pos/summary": SUMMARY,
        "/api/pos/products": PRODUCTS,
    }.get(path)
    if response is None:
        route.fulfill(
            status=404, content_type="application/json",
            body=json.dumps({"error": "Not mocked in visual smoke test"}),
        )
    else:
        route.fulfill(
            status=200, content_type="application/json", body=json.dumps(response),
        )


def exercise(browser, url, label, viewport, mobile, screenshot_dir):
    context = browser.new_context(
        viewport=viewport, device_scale_factor=1,
        is_mobile=mobile, has_touch=mobile,
    )
    page = context.new_page()
    page.route("**/api/**", mock_api)
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    page.locator("#sidebar-nav button").first.wait_for(timeout=15000)
    page.wait_for_function(
        "() => document.querySelector('#business-name')?.textContent === 'Yola QA'"
    )
    assert page.locator("#screen-title").inner_text() == "Overview"
    assert page.locator("#sidebar-nav button").count() >= 8

    metrics = page.evaluate("""() => {
      const shell = document.querySelector('#shell');
      const sidebar = document.querySelector('.sidebar');
      return {
        width: window.innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        shellDisplay: getComputedStyle(shell).display,
        sidebarPosition: getComputedStyle(sidebar).position,
        sidebarWidth: Math.round(sidebar.getBoundingClientRect().width)
      };
    }""")
    assert metrics["width"] == viewport["width"], (label, metrics)
    assert metrics["scrollWidth"] <= metrics["width"] + 2, (label, metrics)
    if mobile:
        assert metrics["shellDisplay"] == "block", (label, metrics)
        assert metrics["sidebarPosition"] == "relative", (label, metrics)
    else:
        assert metrics["shellDisplay"] == "grid", (label, metrics)
        assert 240 <= metrics["sidebarWidth"] <= 280, (label, metrics)

    page.screenshot(path=str(screenshot_dir / f"{label}-overview.png"), full_page=True)
    page.locator('[data-page="sell"]').click()
    page.locator('#results [data-add="test-001"]').wait_for(timeout=15000)
    page.locator('[data-add="test-001"]').click()
    assert "Layout Test Product" in page.locator("#cart-items").inner_text()
    page.screenshot(path=str(screenshot_dir / f"{label}-sale.png"), full_page=True)
    print(f"PASS {label}: {metrics}; overview, product list, cart add, screenshots")
    context.close()


def main():
    screenshots = Path("yola-android-browser-layout-evidence")
    screenshots.mkdir(exist_ok=True)
    server = serve()
    try:
        url = f"http://127.0.0.1:{server.server_port}/workspace.html"
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            try:
                exercise(browser, url, "phone-390x844",
                         {"width": 390, "height": 844}, True, screenshots)
                exercise(browser, url, "tablet-landscape-1280x800",
                         {"width": 1280, "height": 800}, False, screenshots)
            finally:
                browser.close()
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
