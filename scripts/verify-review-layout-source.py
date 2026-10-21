from pathlib import Path
import re

area = Path("AmgiFeatures/Sources/ReviewFeature/ReviewCardArea.swift").read_text()
web = Path("AmgiFeatures/Sources/ReviewFeature/CardWebView.swift").read_text()
native = Path("AmgiFeatures/Sources/ReviewFeature/Native/NativeCardView.swift").read_text()
settings = Path("AmgiFeatures/Sources/SettingsFeature/ReviewSettingsView.swift").read_text()
bridge = Path("AmgiApp/Resources/Review/CardWebViewBridge.js").read_text()
native_branch = area.split("case .native(let front, let back):", 1)[1].split("case .html:", 1)[0]
qa_css = re.search(r"#qa\s*\{([^}]+)\}", bridge)

checks = {
    "full-width flip region": not re.search(r"cardFlipRegion\s*\.frame\(maxWidth: ReviewLayoutPolicy", area),
    "native renderer retains bounded column": "ReviewLayoutPolicy.maximumContentWidth" in native_branch,
    "regular-width limit passed into WebView": "maximumContentWidth:" in area and "horizontalSizeClass == .regular" in area,
    "only inner content bounded and centered": qa_css is not None and all(
        token in qa_css[1] for token in ["max-width:", "--amgi-content-max-width", "margin-inline: auto"]
    ),
    "width limit not applied to body/card background": not re.search(r"(?:body|\.card)\s*\{[^}]*max-width", bridge),
    "WebKit page zoom": "webView.pageZoom" in web,
    "native zoom": "zoomScale" in native,
    "clarified vertical label": 'title: "Vertical content placement"' in settings,
}
failed = [label for label, passed in checks.items() if not passed]
if failed:
    raise SystemExit("review-layout-source: FAIL: " + ", ".join(failed))
print("review-layout-source: PASS")
