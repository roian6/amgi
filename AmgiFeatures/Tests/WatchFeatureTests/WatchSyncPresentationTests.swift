import AmgiCardWeb
import AnkiKit
import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import WatchFeature

@Suite("Watch sync presentation")
struct WatchSyncPresentationTests {
    @Test func successProducesVisibleCompletionMessage() {
        let presentation = WatchSyncPresentation.success

        #expect(presentation.title == "Sync Complete")
        #expect(presentation.message == "Your collection is up to date.")
    }

    @Test func errorProducesVisibleFailureMessage() {
        let presentation = WatchSyncPresentation.failure(SyncError.authFailed)

        #expect(presentation.title == "Sync Failed")
        #expect(presentation.message == SyncError.authFailed.localizedDescription)
    }
}

@Suite("Watch card content")
struct WatchCardContentTests {
    @Test @MainActor func htmlUsesStructuredNativeBlocks() throws {
        let view = CardTextView(html: "<b>Bold</b><br><i>Italic</i>")

        #expect(view.content.blocks.count == 2)
        let first = try #require(view.content.blocks.first)
        guard case .text(let attributed) = first else {
            Issue.record("Expected a text block")
            return
        }
        #expect(String(attributed.characters) == "Bold")
        #expect(attributed.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
    }

    @Test @MainActor func cardCSSImportsIntoSwiftUIRichText() throws {
        let view = CardTextView(
            html: "<div class=\"answer\"><b>Styled</b><ol><li>First</li><li>Second</li></ol></div>",
            css: ".card { font-family: Georgia; } .answer { color: #ff0000; font-size: 24px; text-align: right; }"
        )

        let richText = try #require(WatchCardRichText(document: view.document))
        let rendered = richText.paragraphs.map { String($0.text.characters) }.joined(separator: "\n")
        let runs = richText.paragraphs.flatMap { Array($0.text.runs) }

        #expect(rendered.contains("Styled"))
        #expect(rendered.contains("First"))
        #expect(rendered.contains("Second"))
        #expect(richText.paragraphs.contains { $0.alignment == .trailing })
        #expect(runs.contains { $0.font != nil })
        #expect(runs.contains { $0.foregroundColor != nil })
    }

    #if canImport(UIKit)
    @Test @MainActor func synonymChipFallbackImportsGreenBackground() throws {
        let document = WatchCardDocument(
            html: "<div class=\"tags-inline\"><span class=\"tag tag-syn\">First</span><span class=\"tag tag-syn\">Second</span></div>",
            css: ""
        )
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        let imported = try NSAttributedString(
            data: Data(document.html.utf8), options: options, documentAttributes: nil
        )
        let firstRange = (imported.string as NSString).range(of: "First")
        let color = try #require(
            imported.attribute(.backgroundColor, at: firstRange.location, effectiveRange: nil) as? UIColor
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(green > red)
        #expect(green > blue)
        #expect(imported.string.contains("First\u{00a0}\u{00a0}Second"))
    }
    #endif
}