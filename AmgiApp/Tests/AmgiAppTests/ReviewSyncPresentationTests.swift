import Foundation
import Testing

@Suite struct ReviewSyncPresentationTests {
    @Test func fullScreenReviewerHostsTheExistingSyncFlowAboveTheCover() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("AmgiFeatures/Sources/RootFeature/RootView.swift"),
            encoding: .utf8
        )
        let reviewStart = try #require(source.range(of: "ReviewView(deckId: deckId)"))
        let outerFlowComment = try #require(
            source.range(of: "// still drives the tabs", range: reviewStart.upperBound..<source.endIndex)
        )
        let presentedReview = source[reviewStart.lowerBound..<outerFlowComment.lowerBound]

        #expect(presentedReview.contains(".syncFlow"))
    }
}
