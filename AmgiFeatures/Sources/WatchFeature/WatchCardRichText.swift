import AmgiCardWeb
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
struct WatchCardRichText {
    struct Paragraph {
        let text: AttributedString
        let alignment: TextAlignment
        let spaceBefore: CGFloat
        let spaceAfter: CGFloat

        var frameAlignment: Alignment {
            switch alignment {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
            }
        }
    }

    let document: WatchCardDocument
    let paragraphs: [Paragraph]

    init?(document: WatchCardDocument) {
        #if os(watchOS) || os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let imported = try? NSAttributedString(
            data: Data(document.html.utf8), options: options, documentAttributes: nil
        ), imported.length > 0 else { return nil }

        let string = imported.string as NSString
        var paragraphs: [Paragraph] = []
        var cursor = 0
        while cursor < string.length {
            let range = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            let style = imported.attribute(.paragraphStyle, at: cursor, effectiveRange: nil) as? NSParagraphStyle
            var textRange = range
            while textRange.length > 0,
                  [10, 13, 0x2028, 0x2029].contains(string.character(at: NSMaxRange(textRange) - 1)) {
                textRange.length -= 1
            }
            let substring = textRange.length == 0
                ? NSAttributedString(string: " ", attributes: imported.attributes(at: cursor, effectiveRange: nil))
                : imported.attributedSubstring(from: textRange)
            let text = Self.swiftUIText(from: substring)
            let alignment: TextAlignment = switch style?.alignment {
            case .center: .center
            case .right: .trailing
            default: .leading
            }
            paragraphs.append(Paragraph(
                text: text, alignment: alignment,
                spaceBefore: max(0, style?.paragraphSpacingBefore ?? 0),
                spaceAfter: max(0, style?.paragraphSpacing ?? 0)
            ))
            cursor = NSMaxRange(range)
        }
        self.document = document
        self.paragraphs = paragraphs
        #else
        return nil
        #endif
    }

    private static func swiftUIText(from source: NSAttributedString) -> AttributedString {
        var result = AttributedString(source.string)
        let sourceString = source.string
        source.enumerateAttributes(
            in: NSRange(location: 0, length: source.length),
            options: []
        ) { attributes, range, _ in
            guard let stringRange = Range(range, in: sourceString),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: result),
                  let upper = AttributedString.Index(stringRange.upperBound, within: result)
            else { return }

            var container = AttributeContainer()
            #if canImport(UIKit)
            if let font = attributes[.font] as? UIFont {
                container.font = Font(font)
            }
            if let color = attributes[.foregroundColor] as? UIColor {
                container.foregroundColor = Color(uiColor: color)
            }
            if let color = attributes[.backgroundColor] as? UIColor {
                container.backgroundColor = Color(uiColor: color)
            }
            #elseif canImport(AppKit)
            if let font = attributes[.font] as? NSFont {
                container.font = Font(font)
            }
            if let color = attributes[.foregroundColor] as? NSColor {
                container.foregroundColor = Color(nsColor: color)
            }
            if let color = attributes[.backgroundColor] as? NSColor {
                container.backgroundColor = Color(nsColor: color)
            }
            #endif
            result[lower..<upper].mergeAttributes(container)
        }
        return result
    }
}
