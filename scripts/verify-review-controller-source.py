from pathlib import Path

gamepad = Path("AmgiFeatures/Sources/ReviewFeature/ReviewGamepad.swift").read_text()
area = Path("AmgiFeatures/Sources/ReviewFeature/ReviewCardArea.swift").read_text()
web = Path("AmgiFeatures/Sources/ReviewFeature/CardWebView.swift").read_text()
native = Path("AmgiFeatures/Sources/ReviewFeature/Native/NativeCardView.swift").read_text()

required = {
    "magnitude tracker": "ReviewGamepadAxisTracker",
    "continuous frame queue": "axisFrameCount",
    "axis-edge source": "axisEdge",
}
for label, needle in required.items():
    if needle not in gamepad:
        raise SystemExit(f"review-controller-source: FAIL: missing {label}")
if "continuousScrollDelta" not in area:
    raise SystemExit("review-controller-source: FAIL: review surface does not route continuous scroll")
if "animated = false" not in web or "animated = false" not in native:
    raise SystemExit("review-controller-source: FAIL: continuous scroll is still animated/discrete")
if "repeatInterval: TimeInterval = 0.12" in gamepad:
    raise SystemExit("review-controller-source: FAIL: fixed 120ms axis repeat remains")
print("review-controller-source: PASS")
