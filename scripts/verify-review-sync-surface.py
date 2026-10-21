from pathlib import Path

source = Path("AmgiFeatures/Sources/RootFeature/RootView.swift").read_text()
start = source.index("ReviewView(deckId: deckId)")
end = source.index("// still drives the tabs", start)
presentation = source[start:end]
if ".syncFlow" not in presentation:
    raise SystemExit("review-sync-surface: FAIL: full-screen reviewer does not host SyncFlow")
outer = source[end:]
if "presentsFeedback: pendingReviewDeckId == nil" not in outer:
    raise SystemExit("review-sync-surface: FAIL: covered root still competes to present sync feedback")
router = Path("AmgiFeatures/Sources/ReviewFeature/ReviewInputRouter.swift").read_text()
area = Path("AmgiFeatures/Sources/ReviewFeature/ReviewCardArea.swift").read_text()
if "case syncUnavailable" not in router or "case .syncUnavailable" not in area:
    raise SystemExit("review-sync-surface: FAIL: unavailable mapped sync has no active-review feedback path")
print("review-sync-surface: PASS")
