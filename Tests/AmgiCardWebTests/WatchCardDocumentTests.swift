import Foundation
import Testing
@testable import AmgiCardWeb

@Suite("Watch rich card document")
struct WatchCardDocumentTests {
    @Test func preservesCardStylesAndContentWithoutExecutableControls() {
        let css = ".card { font-family: Georgia; font-size: 23px; text-align: right; } .night_mode .answer { color: #ff8800; }"
        let document = WatchCardDocument(
            html: """
            <script>throw new Error('hidden script')</script>
            <button onclick="reveal()">hidden button</button><input value="hidden input">
            <div class="answer" onclick="run()"><b>答え</b><ol><li>First</li><li>Second</li></ol></div>
            [Sound:answer.mp3]
            """,
            css: css
        )

        #expect(document.html.contains("<body class=\"card night_mode\">"))
        #expect(document.html.contains(css))
        #expect(document.html.contains("<b>答え</b><ol><li>First</li><li>Second</li></ol>"))
        #expect(!document.html.contains("hidden"))
        #expect(!document.html.contains("onclick"))
        #expect(!document.html.contains("[Sound:"))
    }

    @Test func fallbackKeepsEmphasisDividersAndImagesWithoutStyleOrControlText() {
        let folder = URL(fileURLWithPath: "/tmp/collection.media", isDirectory: true)
        let document = WatchCardDocument(
            html: """
            <style>.term { color: red; }</style><b>Front</b><hr><img src="cat.jpg">
            <textarea>hidden editor</textarea><select><option>hidden option</option></select>
            <audio controls src="voice.mp3">hidden player</audio>[Sound:voice.mp3]
            """,
            css: "",
            mediaFolder: folder
        )

        #expect(document.mediaFolder == folder)
        #expect(document.fallbackHTML.contains("<b>Front</b><hr><img src=\"cat.jpg\">"))
        #expect(!document.fallbackHTML.contains("hidden"))
        #expect(!document.fallbackHTML.contains(".term"))
        #expect(!document.fallbackHTML.contains("[Sound:"))
        #expect(document.html.contains("Image: cat.jpg"))
        #expect(!document.html.contains("<img"))
        #expect(!document.html.contains("hidden"))
        #expect(document.html.contains(".term { color: red; }"))
    }

    @Test func removesResourceLoadsAndDocumentOverridesButKeepsInlineStyles() {
        let document = WatchCardDocument(
            html: """
            <html><head><base href="https://example.com"><link rel="stylesheet" href="remote.css"></head>
            <body class="other"><!-- hidden comment -->
            <iframe src="remote">hidden frame</iframe><object>hidden object</object><embed src="remote">
            <p style="color: red; text-align: right" title="a > b" onmouseover='run()'>Visible</p>
            <a href="javascript:run()">Link text</a></body></html>
            """,
            css: "@import 'remote.css'; .card { color: white; background-image: url(https://example.com/a); }"
        )

        #expect(document.html.contains("style=\"color: red; text-align: right\""))
        #expect(document.html.contains("Link text"))
        #expect(!document.html.contains("hidden"))
        #expect(!document.html.contains("remote"))
        #expect(!document.html.contains("javascript:"))
        #expect(!document.html.contains("onmouseover"))
        #expect(!document.html.contains("url("))
        #expect(!document.html.contains("class=\"other\""))
    }

    @Test func cssCannotEscapeStyleElementAndUnclosedScriptDoesNotBecomeText() {
        let document = WatchCardDocument(
            html: "<p>Visible</p><SCRIPT>hidden unfinished script",
            css: ".card::after { content: '</style><script>hidden</script>'; }"
        )

        #expect(!document.html.contains("<script>"))
        #expect(!document.html.contains("hidden unfinished"))
        #expect(document.fallbackHTML == "<p>Visible</p>")
    }

    @Test func encodedCSSCannotLoadRemoteResources() {
        let document = WatchCardDocument(
            html: "<p style=\"background-image: ur&#108;(https://example.test/inline); color: red\">Visible</p>",
            css: """
            @\\69mport "https://example.test/imported.css";
            .card { background-image: u\\72l(https://example.test/card); color: white; }
            """
        )

        #expect(!document.html.contains("example.test"))
        #expect(!document.html.localizedCaseInsensitiveContains("@import"))
        #expect(!document.html.localizedCaseInsensitiveContains("url("))
        #expect(document.html.contains("color: red"))
        #expect(document.html.contains("color: white"))
    }

    @Test func watchCompatibilityHidesTTSAndNormalizesScreeningLayout() {
        let document = WatchCardDocument(
            html: """
            <div class="front">
              <div class="headword">Term</div>
              <div class="speak"><span class="tts-anki">[anki:tts lang=en_US voices=Apple_Samantha]</span></div>
            </div>
            <div class="back"><div class="header"><span class="hw">Term</span></div></div>
            """,
            css: """
            .front { display: flex; }
            .headword { font-size: clamp(36px, 10vw, 64px); }
            .tags-inline { display: inline-flex; }
            .deep-context-content { display: none; }
            """
        )

        #expect(!document.html.localizedCaseInsensitiveContains("[anki:tts"))
        #expect(document.html.contains("font-size: 36px"))
        #expect(document.html.contains("display: block"))
        #expect(document.html.contains("display: inline"))
        #expect(document.html.contains("font-size: 28px !important"))
        #expect(document.html.contains(".deep-context-content"))
        #expect(document.fallbackHTML.contains("Term"))
        #expect(!document.fallbackHTML.localizedCaseInsensitiveContains("[anki:tts"))
    }

    @Test func adjacentTagChipsGetNonbreakingSpacing() {
        let document = WatchCardDocument(
            html: """
            <div class="tags-inline"><span class="tag tag-syn">First</span><span class="tag tag-syn">Second</span><span class="tag tag-syn">Third</span></div>
            """,
            css: ""
        )

        #expect(document.html.contains("First</span>&nbsp;&nbsp;<span class=\"tag tag-syn\">Second"))
        #expect(document.html.contains("Second</span>&nbsp;&nbsp;<span class=\"tag tag-syn\">Third"))
        #expect(document.fallbackHTML.contains("First</span>&nbsp;&nbsp;<span class=\"tag tag-syn\">Second"))
    }

    @Test func watchCompatibilityStylesTagChipsWithoutFlex() {
        let document = WatchCardDocument(
            html: "<div class=\"tags-inline\"><span class=\"tag tag-syn\">First</span></div>",
            css: ""
        )

        #expect(document.html.contains(".tags-inline .tag-syn"))
        #expect(document.html.contains("background-color: #14532d !important"))
        #expect(document.html.contains("border: 1px solid #86efac !important"))
    }

    @Test func emptyCardHasNoFallbackContent() {
        let document = WatchCardDocument(html: "", css: "")
        #expect(document.fallbackHTML.isEmpty)
        #expect(document.mediaFolder == nil)
    }
}
