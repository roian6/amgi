import os
from pathlib import Path
import re
import tempfile

from playwright.sync_api import sync_playwright


root = Path(__file__).resolve().parents[1]
evidence = root / ".review-qa"
evidence.mkdir(exist_ok=True)
os.environ["TMPDIR"] = str(evidence)
os.environ["XDG_CACHE_HOME"] = str(evidence / "cache")
os.environ["XDG_CONFIG_HOME"] = str(evidence / "config")
tempfile.tempdir = str(evidence)

source = (root / "AmgiApp/Resources/Review/CardWebViewBridge.js").read_text()
web = (root / "AmgiFeatures/Sources/ReviewFeature/CardWebView.swift").read_text()
layout = re.search(r'let layoutScript = """(.*?)"""', web, re.S)
assert layout is not None
source = re.sub(r"__AMGI_(PLAY_ICON_LITERAL|PAUSE_ICON_LITERAL|MATHJAX_CONFIG_URL|MATHJAX_CORE_URL)__", '""', source)
source = source.replace("__AMGI_COLOR_SCHEME__", "light")
source = re.sub(r"__AMGI_[A-Z_]+__", "", source)
chromium_paths = sorted((Path.home() / ".cache/ms-playwright").glob("chromium-*/chrome-linux/chrome"))
assert chromium_paths, "Requires an already installed Chromium; this script does not install browsers"

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        executable_path=str(chromium_paths[-1]),
        headless=True,
        args=["--disable-dev-shm-usage", "--disable-breakpad", "--disable-crash-reporter"],
    )
    try:
        page = browser.new_page()
        errors: list[str] = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.route("**/*", lambda route: route.abort())
        for width, regular in [(1200, True), (768, True), (390, False)]:
            for top in [False, True]:
                page.set_viewport_size({"width": width, "height": 800})
                page.set_content(source)
                script = layout[1].replace(r"\(width)", "860.0px" if regular else "none")
                script = script.replace(r"\(maximumContentWidth != nil)", "true" if regular else "false")
                page.evaluate(script)
                page.evaluate("""top => {
                    window.webkit = {messageHandlers: {amgiCardReady: {postMessage() {}}}};
                    amgiSetCardCSS('.card { background: rgb(12, 34, 56); color: white; text-align: left; }');
                    _showQuestion('<div id="text">Readable template content</div><input id="typeans" aria-label="Answer">',
                        '', 'card', false, 'question', top, 16, 0, false, 16, true, 1);
                    return window.__amgiUpdateQueue;
                }""", top)
                page.locator("#typeans").blur()
                metrics = page.evaluate("""() => {
                    const qa = document.getElementById('qa');
                    const rect = qa.getBoundingClientRect();
                    const body = document.body.getBoundingClientRect();
                    return {width: rect.width, x: rect.x, y: rect.y, height: rect.height,
                        bodyWidth: body.width, background: getComputedStyle(document.body).backgroundColor,
                        align: getComputedStyle(document.getElementById('text')).textAlign,
                        overflow: document.documentElement.scrollWidth > innerWidth};
                }""")
                expected_width = min(width - 40, 860) if regular else width - 40
                assert metrics["width"] == expected_width, metrics
                assert metrics["x"] == (width - expected_width) / 2, metrics
                assert metrics["bodyWidth"] == (width if regular else width - 40), metrics
                assert metrics["background"] == "rgb(12, 34, 56)", metrics
                assert metrics["align"] == "left" and not metrics["overflow"], metrics
                assert metrics["y"] == 20 if top else metrics["y"] > 200, metrics
                page.screenshot(path=str(evidence / f"layout-{width}-{'top' if top else 'center'}.png"))
                print(f"layout width={width} regular={regular} top={top}: PASS {metrics}")
        assert not errors, errors
    finally:
        browser.close()
print("review-web-layout: PASS (Chromium bridge fixture; not iPad/WKWebView)")
