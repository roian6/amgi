public import Foundation

/// Prepares Anki fragments for native HTML text import, not browser rendering.
public struct WatchCardDocument: Sendable, Hashable {
    public let html: String
    public let fallbackHTML: String
    public let mediaFolder: URL?

    public init(html: String, css: String, mediaFolder: URL? = nil) {
        self.mediaFolder = mediaFolder
        let sanitized = Self.sanitize(html)
        let embeddedCSS = Self.styleContents(in: sanitized).joined(separator: "\n")
        let unstyledBody = Self.replace(Self.style, in: sanitized) { _ in "" }
        let body = Self.separateAdjacentTagChips(in: unstyledBody)
        fallbackHTML = body
        let textBody = Self.replace(Self.image, in: body) { tag in
            let source = Self.attributes(in: tag)["src"] ?? ""
            return "<span>Image: \(source)</span>"
        }
        self.html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body { color: white; background-color: black; }
        \(Self.sanitizeCSS(css))
        \(embeddedCSS)
        \(Self.watchCompatibilityCSS)</style></head>
        <body class="card night_mode">\(textBody)</body></html>
        """
    }

    private static let tag = try! NSRegularExpression(
        pattern: #"</?([a-z][a-z0-9]*)\b(?:[^>"']|"[^"]*"|'[^']*')*>"#,
        options: [.caseInsensitive]
    )
    private static let attribute = try! NSRegularExpression(
        pattern: #"([a-z][a-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: [.caseInsensitive]
    )
    private static let noncontent = try! NSRegularExpression(
        pattern: #"<(script|button|select|textarea|iframe|object|audio|video|svg|template|title)\b(?:[^>"']|"[^"]*"|'[^']*')*>.*?(?:</\1\s*>|$)"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let comment = try! NSRegularExpression(pattern: #"(?s)<!--.*?(?:-->|$)"#)
    private static let style = try! NSRegularExpression(
        pattern: #"<style\b[^>]*>(.*?)</style\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let image = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive])
    private static let sound = try! NSRegularExpression(pattern: CardText.soundMarkerPattern)
    private static let ttsMarker = try! NSRegularExpression(
        pattern: #"\[/?anki:tts(?:\s+[^\]]*)?\]"#,
        options: [.caseInsensitive]
    )
    private static let cssComment = try! NSRegularExpression(pattern: #"(?s)/\*.*?\*/"#)
    private static let cssResource = try! NSRegularExpression(
        pattern: #"@import\b[^;]*(?:;|$)|url\s*\((?:[^)"']|"[^"]*"|'[^']*')*\)"#,
        options: [.caseInsensitive]
    )
    private static let cssClamp = try! NSRegularExpression(
        pattern: #"clamp\(\s*([0-9]*\.?[0-9]+(?:px|pt))\s*,\s*[^,()]+\s*,\s*[0-9]*\.?[0-9]+(?:px|pt)\s*\)"#,
        options: [.caseInsensitive]
    )
    private static let cssLayoutDisplay = try! NSRegularExpression(
        pattern: #"display\s*:\s*(inline-)?(?:flex|grid)"#,
        options: [.caseInsensitive]
    )
    private static let adjacentTagChip = try! NSRegularExpression(
        pattern: #"</span>\s*(?=<span\b[^>]*\bclass=\"[^\"]*\btag\b[^\"]*\"[^>]*>)"#,
        options: [.caseInsensitive]
    )
    private static let contentTags: Set<String> = [
        "a", "b", "blockquote", "br", "center", "code", "dd", "del", "div", "dl", "dt", "em",
        "font", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img", "li", "ol", "p", "pre",
        "rp", "rt", "ruby", "s", "small", "span", "strike", "strong", "style", "sub", "sup",
        "table", "tbody", "td", "th", "thead", "tr", "u", "ul",
    ]
    private static let contentAttributes: Set<String> = [
        "class", "id", "style", "dir", "lang", "title", "align", "color", "face", "size", "start", "type",
    ]

    private static func sanitize(_ html: String) -> String {
        var result = replace(comment, in: html) { _ in "" }
        result = replace(noncontent, in: result) { _ in "" }
        result = replace(sound, in: result) { _ in "" }
        result = replace(ttsMarker, in: result) { _ in "" }
        result = replace(style, in: result) { element in
            let ns = element as NSString
            let match = style.firstMatch(in: element, range: NSRange(location: 0, length: ns.length))!
            return "<style>\(sanitizeCSS(ns.substring(with: match.range(at: 1))))</style>"
        }
        return replace(tag, in: result) { element in
            let ns = element as NSString
            let match = tag.firstMatch(in: element, range: NSRange(location: 0, length: ns.length))!
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            guard contentTags.contains(name) else { return "" }
            if element.hasPrefix("</") { return "</\(name)>" }
            let keptAttributes = attributes(in: element).sorted { $0.key < $1.key }.compactMap { key, value in
                guard contentAttributes.contains(key) || (name == "img" && key == "src") else { return nil as String? }
                let cleaned = key == "style" ? sanitizeCSS(value) : value
                let escaped = key == "style" ? escapeStyleAttribute(cleaned) : escapeAttribute(cleaned)
                return " \(key)=\"\(escaped)\""
            }.joined()
            return "<\(name)\(keptAttributes)>"
        }
    }

    private static func sanitizeCSS(_ css: String) -> String {
        let decoded = decodeCSSEscapes(decodeCSSHTMLEntities(css))
        let uncommented = replace(cssComment, in: decoded) { _ in "" }
        let withoutResources = replace(cssResource, in: uncommented) { value in
            value.lowercased().hasPrefix("@import") ? "" : "none"
        }
        let fixedSizes = replaceCSSClamps(in: withoutResources)
        return replace(cssLayoutDisplay, in: fixedSizes) { value in
            value.lowercased().contains("inline-") ? "display: inline" : "display: block"
        }.replacingOccurrences(of: "<", with: "\\3C ")
    }

    private static func styleContents(in html: String) -> [String] {
        let ns = html as NSString
        return style.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.range(at: 1).location != NSNotFound else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func replaceCSSClamps(in css: String) -> String {
        let ns = css as NSString
        let result = NSMutableString(string: css)
        for match in cssClamp.matches(in: css, range: NSRange(location: 0, length: ns.length)).reversed() {
            result.replaceCharacters(in: match.range, with: ns.substring(with: match.range(at: 1)))
        }
        return result as String
    }

    private static func separateAdjacentTagChips(in html: String) -> String {
        replace(adjacentTagChip, in: html) { _ in "</span>&nbsp;&nbsp;" }
    }

    private static let watchCompatibilityCSS = """
    html, body, .card {
      width: auto !important;
      max-width: 100% !important;
      min-height: 0 !important;
      margin: 0 !important;
      padding: 0 !important;
    }
    .front, .back, .reverse-front, .reverse-back, .confusable-front, .confusable-back {
      width: auto !important;
      max-width: 100% !important;
      min-height: 0 !important;
      padding: 6px 2px !important;
    }
    .front { display: block !important; text-align: center !important; }
    .front .headword, .headword {
      display: block !important;
      font-size: 28px !important;
      line-height: 1.15 !important;
      margin: 4px 0 10px !important;
      text-align: center !important;
    }
    .back .header, .reverse-back .header {
      display: block !important;
      text-align: center !important;
      padding-bottom: 8px !important;
      margin-bottom: 10px !important;
    }
    .back .header .hw, .reverse-back .header .hw {
      display: block !important;
      font-size: 24px !important;
      line-height: 1.2 !important;
      text-align: center !important;
    }
    .header .chip, .header .source-tag, .tags-inline .tag {
      display: inline !important;
    }
    .tags-inline, .deep-context-toggle {
      display: block !important;
      text-align: center !important;
    }
    .tags-inline { line-height: 1.9 !important; }
    .tags-inline .tag {
      padding: 2px 6px !important;
      border-radius: 8px !important;
      font-size: 13px !important;
      font-weight: 600 !important;
    }
    .tags-inline .tag-syn {
      color: #86efac !important;
      background-color: #14532d !important;
      border: 1px solid #86efac !important;
    }
    .tags-inline .tag-ant {
      color: #fca5a5 !important;
      background-color: #450a0a !important;
      border: 1px solid #fca5a5 !important;
    }
    .deep-context-content {
      display: block !important;
      max-width: 100% !important;
    }
    .section, .sense-list, .examples, .dc-item, .dc-text {
      max-width: 100% !important;
    }
    .speak, .tts-anki, .tts-web, .replay-button {
      display: none !important;
      font-size: 0 !important;
    }
    .base-screening-progress {
      display: block !important;
      font-size: 11px !important;
      text-align: center !important;
    }
    """

    private static func decodeCSSHTMLEntities(_ value: String) -> String {
        var result = value
        let named: [(String, String)] = [
            ("&lpar;", "("), ("&rpar;", ")"), ("&commat;", "@"), ("&colon;", ":"),
            ("&bsol;", "\\"), ("&sol;", "/"), ("&period;", "."), ("&semi;", ";"),
            ("&quot;", "\""), ("&apos;", "'"), ("&tab;", " "), ("&newline;", " "),
            ("&amp;", "&"),
        ]
        for _ in 0..<3 {
            result = decodeNumericHTMLEntities(result)
            for (entity, replacement) in named {
                result = result.replacingOccurrences(
                    of: entity,
                    with: replacement,
                    options: [.caseInsensitive]
                )
            }
        }
        return result
    }

    private static func decodeNumericHTMLEntities(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "&", index + 2 < scalars.count, scalars[index + 1] == "#" else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            var cursor = index + 2
            let isHex = cursor < scalars.count && (scalars[cursor] == "x" || scalars[cursor] == "X")
            if isHex { cursor += 1 }
            let digitStart = cursor
            while cursor < scalars.count,
                  isHex ? isASCIIHexDigit(scalars[cursor]) : isASCIIDecimalDigit(scalars[cursor]) {
                cursor += 1
            }
            guard cursor > digitStart else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            let digits = String(String.UnicodeScalarView(scalars[digitStart..<cursor]))
            guard let number = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = UnicodeScalar(number),
                  !(0xD800...0xDFFF).contains(number)
            else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            result.unicodeScalars.append(scalar)
            if cursor < scalars.count, scalars[cursor] == ";" { cursor += 1 }
            index = cursor
        }
        return result
    }

    private static func decodeCSSEscapes(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "\\", index + 1 < scalars.count else {
                result.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            var cursor = index + 1
            if isASCIIHexDigit(scalars[cursor]) {
                let digitStart = cursor
                while cursor < scalars.count,
                      cursor - digitStart < 6,
                      isASCIIHexDigit(scalars[cursor]) {
                    cursor += 1
                }
                let digits = String(String.UnicodeScalarView(scalars[digitStart..<cursor]))
                if let number = UInt32(digits, radix: 16),
                   let scalar = UnicodeScalar(number),
                   !(0xD800...0xDFFF).contains(number) {
                    result.unicodeScalars.append(scalar)
                }
                if cursor < scalars.count, isCSSWhitespace(scalars[cursor]) { cursor += 1 }
                index = cursor
                continue
            }
            if scalars[cursor] == "\r" {
                cursor += 1
                if cursor < scalars.count, scalars[cursor] == "\n" { cursor += 1 }
                index = cursor
                continue
            }
            if scalars[cursor] == "\n" || scalars[cursor] == "\u{000C}" {
                index = cursor + 1
                continue
            }
            result.unicodeScalars.append(scalars[cursor])
            index = cursor + 1
        }
        return result
    }

    private static func isASCIIHexDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value) || (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
    }

    private static func isASCIIDecimalDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
    }

    private static func isCSSWhitespace(_ scalar: UnicodeScalar) -> Bool {
        [9, 10, 12, 13, 32].contains(scalar.value)
    }

    private static func attributes(in element: String) -> [String: String] {
        let ns = element as NSString
        var result: [String: String] = [:]
        for match in attribute.matches(in: element, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            for index in 2...4 where match.range(at: index).location != NSNotFound {
                result[name] = ns.substring(with: match.range(at: index))
            }
        }
        return result
    }

    private static func escapeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeStyleAttribute(_ value: String) -> String {
        escapeAttribute(value.replacingOccurrences(of: "&", with: "&amp;"))
    }

    private static func replace(_ regex: NSRegularExpression, in value: String, with transform: (String) -> String) -> String {
        let ns = value as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(ns.substring(with: match.range))
            cursor = NSMaxRange(match.range)
        }
        return result + ns.substring(from: cursor)
    }
}
