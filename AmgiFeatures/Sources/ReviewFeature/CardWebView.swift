//
//  CardWebView.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 27.03.2026.
//

import AppCore
import AppShared
import AnkiKit
import OSLog
import Reader
import SwiftUI
import WebKit
import UIKit
import AVFoundation
import AmgiCardWeb


@MainActor
struct CardWebView {
    @Environment(\.colorScheme) private var colorScheme

    let html: String
    let cardID: CardID?
    let cardCSS: String
    let autoplayEnabled: Bool
    let zoomScale: Double
    let maximumContentWidth: CGFloat?
    let isAnswerSide: Bool
    let cardOrdinal: UInt32
    let replayRequestID: Int
    let replayCardID: CardID?
    let replayIsAnswerSide: Bool?
    let stopAudioRequestID: Int
    let scrollRequestID: Int
    let scrollDirection: ReviewScrollDirection
    let continuousScrollDelta: CGFloat?
    let userActionRequestID: Int
    let userActionIndex: Int?
    let userActionCardID: CardID?
    let userActionIsAnswerSide: Bool?
    let replayMode: CardWebViewReplayMode
    let showInlineAudioReplayButtons: Bool
    let openLinksExternally: Bool
    let lookupPopupEnabled: Bool
    let dictionaryScanLength: Int
    let lookupHighlight: LookupHighlight
    let prefetchHTML: String?
    let contentAlignment: CardWebViewContentAlignment
    let bottomContentInset: CGFloat
    let tapControlsEnabled: Bool
    let onAudioStateChange: ((Bool) -> Void)?
    let onCardBackgroundColorChange: ((Color, Bool) -> Void)?
    let onLookupRequested: ((String?, String?, CGPoint) -> Void)?
    let onShowAnswerRequested: (() -> Void)?
    let onReviewTapRequested: ((CGFloat) -> Void)?
    let onEditableFocusChange: ((Bool) -> Void)?

    init(
        html: String,
        cardID: CardID? = nil,
        cardCSS: String = "",
        autoplayEnabled: Bool = true,
        zoomScale: Double = 1,
        maximumContentWidth: CGFloat? = nil,
        isAnswerSide: Bool = false,
        cardOrdinal: UInt32 = 0,
        replayRequestID: Int = 0,
        replayCardID: CardID? = nil,
        replayIsAnswerSide: Bool? = nil,
        stopAudioRequestID: Int = 0,
        scrollRequestID: Int = 0,
        scrollDirection: ReviewScrollDirection = .down,
        continuousScrollDelta: CGFloat? = nil,
        userActionRequestID: Int = 0,
        userActionIndex: Int? = nil,
        userActionCardID: CardID? = nil,
        userActionIsAnswerSide: Bool? = nil,
        replayMode: CardWebViewReplayMode = .question,
        showInlineAudioReplayButtons: Bool = true,
        openLinksExternally: Bool = true,
        lookupPopupEnabled: Bool = false,
        dictionaryScanLength: Int = 16,
        lookupHighlight: LookupHighlight = LookupHighlight(),
        prefetchHTML: String? = nil,
        contentAlignment: CardWebViewContentAlignment = .center,
        bottomContentInset: CGFloat = 0,
        tapControlsEnabled: Bool = false,
        onAudioStateChange: ((Bool) -> Void)? = nil,
        onCardBackgroundColorChange: ((Color, Bool) -> Void)? = nil,
        onLookupRequested: ((String?, String?, CGPoint) -> Void)? = nil,
        onShowAnswerRequested: (() -> Void)? = nil,
        onReviewTapRequested: ((CGFloat) -> Void)? = nil,
        onEditableFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.html = html
        self.cardID = cardID
        self.cardCSS = cardCSS
        self.autoplayEnabled = autoplayEnabled
        self.zoomScale = zoomScale
        self.maximumContentWidth = maximumContentWidth
        self.isAnswerSide = isAnswerSide
        self.cardOrdinal = cardOrdinal
        self.replayRequestID = replayRequestID
        self.replayCardID = replayCardID
        self.replayIsAnswerSide = replayIsAnswerSide
        self.stopAudioRequestID = stopAudioRequestID
        self.scrollRequestID = scrollRequestID
        self.scrollDirection = scrollDirection
        self.continuousScrollDelta = continuousScrollDelta
        self.userActionRequestID = userActionRequestID
        self.userActionIndex = userActionIndex
        self.userActionCardID = userActionCardID
        self.userActionIsAnswerSide = userActionIsAnswerSide
        self.replayMode = replayMode
        self.showInlineAudioReplayButtons = showInlineAudioReplayButtons
        self.openLinksExternally = openLinksExternally
        self.lookupPopupEnabled = lookupPopupEnabled
        self.dictionaryScanLength = dictionaryScanLength
        self.lookupHighlight = lookupHighlight
        self.prefetchHTML = prefetchHTML
        self.contentAlignment = contentAlignment
        self.bottomContentInset = bottomContentInset
        self.tapControlsEnabled = tapControlsEnabled
        self.onAudioStateChange = onAudioStateChange
        self.onCardBackgroundColorChange = onCardBackgroundColorChange
        self.onLookupRequested = onLookupRequested
        self.onShowAnswerRequested = onShowAnswerRequested
        self.onReviewTapRequested = onReviewTapRequested
        self.onEditableFocusChange = onEditableFocusChange
    }

    func makeCoordinator() -> CardWebViewCoordinator {
        CardWebViewCoordinator(
            onAudioStateChange: onAudioStateChange,
            onCardBackgroundColorChange: onCardBackgroundColorChange,
            onLookupRequested: onLookupRequested,
            onShowAnswerRequested: onShowAnswerRequested,
            onReviewTapRequested: onReviewTapRequested,
            onEditableFocusChange: onEditableFocusChange
        )
    }

    func makeWebView(coordinator: CardWebViewCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        config.userContentController.addScriptMessageHandler(coordinator, contentWorld: .page, name: "amgiPrepareAudio")
        config.userContentController.add(coordinator, name: "amgiAudioState")
        config.userContentController.add(coordinator, name: "amgiOpenLink")
        config.userContentController.add(coordinator, name: "amgiSpeakTts")
        config.userContentController.add(coordinator, name: "amgiStopTts")
        config.userContentController.add(coordinator, name: "amgiCardTheme")
        config.userContentController.add(coordinator, name: "amgiLookupText")
        config.userContentController.add(coordinator, name: "amgiShowAnswer")
        config.userContentController.add(coordinator, name: "amgiReviewTap")
        config.userContentController.add(coordinator, name: "amgiEditableFocus")
        config.userContentController.add(coordinator, name: "amgiCardReady")
        config.userContentController.add(coordinator, name: "amgiUserActionComplete")

        config.userContentController.addUserScript(WKUserScript(
            source: LookupExtractionScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // Enable media playback without user interaction
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = coordinator
        return webView
    }

    static func dismantleWebView(_ webView: WKWebView, coordinator: CardWebViewCoordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiPrepareAudio", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiAudioState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiOpenLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiSpeakTts")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiStopTts")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiCardTheme")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiLookupText")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiShowAnswer")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiReviewTap")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiEditableFocus")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiCardReady")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiUserActionComplete")
        coordinator.stopTTS()
        coordinator.currentWebView = nil
    }

    func updateWebView(_ webView: WKWebView, coordinator: CardWebViewCoordinator) {
        let isDarkMode = colorScheme == .dark
        let alignTop = contentAlignment == .top

        // Both signatures are derived from the *inputs*, never from the
        // processed output. `processedHTML` costs three whole-document regex
        // passes, so hashing it to decide whether anything changed meant
        // paying that cost on every render and usually throwing it away.
        // `ReviewContent` reads a dozen `session.*` properties, so an
        // audio-state flip, an undo, or a flag tap each used to run all three.
        // `html`, `isDarkMode`, and `showInlineAudioReplayButtons` are its only
        // inputs, so they discriminate exactly as well.
        let pageSignature = "\(isDarkMode)"
        // `bottomContentInset` joins the signature because it is now carried as
        // body padding in the show-card script rather than as a scroll inset.
        let contentSignature = "\(cardID?.rawValue ?? 0)|\(autoplayEnabled)|\(isAnswerSide)|\(lookupPopupEnabled)|\(dictionaryScanLength)|\(tapControlsEnabled)|\(replayMode.rawValue)|\(cardOrdinal)|\(alignTop)|\(showInlineAudioReplayButtons)|\(Int(bottomContentInset))|\(cardCSS.hashValue)|\(html.hashValue)|\(prefetchHTML?.hashValue ?? 0)"

        // Bookkeeping that has to track every render, expensive or not.
        coordinator.openLinksExternally = openLinksExternally
        coordinator.currentWebView = webView
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        webView.pageZoom = CGFloat(ReviewZoomPolicy.clamped(zoomScale))
        let width = maximumContentWidth.map { "\($0)px" } ?? "none"
        let layoutScript = """
            document.documentElement.style.setProperty('--amgi-content-max-width', '\(width)');
            document.documentElement.classList.toggle('amgi-regular-width', \(maximumContentWidth != nil));
            """
        if coordinator.contentLayoutScript != layoutScript {
            coordinator.contentLayoutScript = layoutScript
            if coordinator.isPageLoaded {
                webView.evaluateJavaScript(layoutScript) { _, error in
                    if let error { Log.review.error("card layout script failed: \(error)") }
                }
            }
        }

        let pageChanged = coordinator.lastPageSignature != pageSignature
        let contentChanged = coordinator.lastContentSignature != contentSignature
        let renderIdentity = "\(pageSignature)|\(contentSignature)"

        if pageChanged || contentChanged {
            coordinator.beginContentUpdate(identity: renderIdentity)
        }

        if pageChanged || contentChanged {
            // Convert Anki [sound:filename.mp3] tags to <audio> HTML elements.
            // The Rust renderer keeps these tags literal; the client must expand them.
            let processedHTML = Self.userActionResetHTML + Self.deferCardScripts(in:
                Self.expandTTSTags(
                    in: Self.expandSoundTags(
                        html,
                        isDarkMode: isDarkMode,
                        showReplayButtons: showInlineAudioReplayButtons
                    ),
                    isDarkMode: isDarkMode,
                    showReplayButtons: showInlineAudioReplayButtons
                )
            )
            let bodyPaddingBottom = 16 + Int(bottomContentInset)
            let cardPaddingBottom = 0
            let bodyClass = Self.bodyClasses(cardOrdinal: cardOrdinal, isDarkMode: isDarkMode)

            // Build the JS call that shows the card – passed via evaluateJavaScript so
            // HTML content never lives inside a <script> literal in the page source.
            let showCardScript = Self.showCardScript(
                processedHTML: processedHTML,
                prefetchHTML: prefetchHTML,
                cardCSS: cardCSS,
                isAnswerSide: isAnswerSide,
                lookupPopupEnabled: lookupPopupEnabled,
                dictionaryScanLength: dictionaryScanLength,
                tapControlsEnabled: tapControlsEnabled,
                bodyClass: bodyClass,
                autoplayEnabled: autoplayEnabled,
                replayMode: replayMode.rawValue,
                alignTop: alignTop,
                bodyPaddingBottom: bodyPaddingBottom,
                cardPaddingBottom: cardPaddingBottom,
                contentGeneration: coordinator.contentGeneration
            )
            // Only when the card content actually changes. Unconditionally,
            // any unrelated re-render — including the audio callback writing
            // `isAudioPlaying` back onto the session — cut off speech that was
            // still playing.
            coordinator.stopTTS()

            if pageChanged {
                coordinator.lastPageSignature = pageSignature
                coordinator.lastContentSignature = contentSignature
                coordinator.isPageLoaded = false
                let htmlClass = Self.htmlClasses(isDarkMode: isDarkMode)
                let playIconHTML = Self.audioButtonIconHTML(systemName: "play.circle", alt: "Play", isDarkMode: isDarkMode)
                let pauseIconHTML = Self.audioButtonIconHTML(systemName: "pause.circle", alt: "Pause", isDarkMode: isDarkMode)
                let baseTag = CardAssetPath.mediaBaseTag()
                // Stash the show-card call so we can run it once the page finishes loading.
                coordinator.pendingUpdateScript = showCardScript

                let styledHTML = Self.buildFrameHTML(
                    htmlClass: htmlClass,
                    isDarkMode: isDarkMode,
                    playIconHTML: playIconHTML,
                    pauseIconHTML: pauseIconHTML,
                    baseTag: baseTag
                )

                // Use cardBaseURL so that MathJax, fonts, and other resources load correctly.
                // The CardAssetScheme handler processes amgi-asset:// URLs.
                webView.loadHTMLString(styledHTML, baseURL: CardAssetPath.cardBaseURL)
            } else {
                coordinator.lastContentSignature = contentSignature
                if coordinator.isPageLoaded {
                    webView.evaluateJavaScript(showCardScript) { _, error in
                        // A JS exception in _showQuestion/_showAnswer renders
                        // a blank card; dropping the error left no diagnostic.
                        if let error { Log.review.error("showCard script failed: \(error)") }
                    }
                } else {
                    coordinator.pendingUpdateScript = showCardScript
                }
            }
        }
        if contentChanged {
            coordinator.lastStopAudioRequestID = stopAudioRequestID
        }
        if replayRequestID != coordinator.lastReplayRequestID {
            coordinator.lastReplayRequestID = replayRequestID
            if replayCardID == cardID && replayIsAnswerSide == isAnswerSide {
                coordinator.observeAudioCommand(
                    requestID: replayRequestID,
                    command: .replay(replayMode),
                    contentIdentity: renderIdentity,
                    webView: webView
                )
            }
        }

        if !contentChanged && stopAudioRequestID != coordinator.lastStopAudioRequestID {
            coordinator.lastStopAudioRequestID = stopAudioRequestID
            coordinator.observeAudioCommand(
                requestID: stopAudioRequestID,
                command: .stop,
                contentIdentity: renderIdentity,
                webView: webView
            )
        }

        if scrollRequestID != coordinator.lastScrollRequestID {
            coordinator.lastScrollRequestID = scrollRequestID
            let scrollView = webView.scrollView
            let minimumOffset = -scrollView.adjustedContentInset.top
            let maximumOffset = max(
                minimumOffset,
                scrollView.contentSize.height - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            let target: CGFloat
            let animated: Bool
            if let continuousScrollDelta {
                target = ReviewScrollPolicy.targetOffset(
                    currentOffset: scrollView.contentOffset.y,
                    minimumOffset: minimumOffset,
                    maximumOffset: maximumOffset,
                    delta: continuousScrollDelta
                )
                animated = false
            } else {
                target = ReviewScrollPolicy.targetOffset(
                    currentOffset: scrollView.contentOffset.y,
                    minimumOffset: minimumOffset,
                    maximumOffset: maximumOffset,
                    direction: scrollDirection
                )
                animated = true
            }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: target),
                animated: animated
            )
        }

        coordinator.observeUserAction(
            requestID: userActionRequestID,
            index: userActionIndex,
            targetsCurrentContent: userActionCardID == cardID
                && userActionIsAnswerSide == isAnswerSide,
            contentIdentity: renderIdentity,
            webView: webView
        )

        if lookupHighlight.generation != coordinator.lastLookupHighlightGeneration {
            coordinator.lastLookupHighlightGeneration = lookupHighlight.generation
            let call = lookupHighlight.utf16Length > 0 ? "highlightMatched(\(lookupHighlight.utf16Length))" : "clearHighlight()"
            webView.evaluateJavaScript("window.amgiLookup && window.amgiLookup.\(call);") { _, error in
                if let error { Log.review.error("lookup highlight script failed: \(error)") }
            }
        }

    }

    // MARK: - Helpers

    private static let userActionResetHTML = """
        <script type="application/x-amgi-card-script" data-amgi-card-script="1">
        window.userJs1 = undefined;
        window.userJs2 = undefined;
        window.userJs3 = undefined;
        window.userJs4 = undefined;
        window.userJs5 = undefined;
        window.userJs6 = undefined;
        window.userJs7 = undefined;
        window.userJs8 = undefined;
        </script>
        """

    static func userActionScript(
        index: Int,
        contentGeneration: Int = 0,
        requestID: Int = 0
    ) -> String? {
        let functionName: String
        switch index {
        case 1: functionName = "userJs1"
        case 2: functionName = "userJs2"
        case 3: functionName = "userJs3"
        case 4: functionName = "userJs4"
        case 5: functionName = "userJs5"
        case 6: functionName = "userJs6"
        case 7: functionName = "userJs7"
        case 8: functionName = "userJs8"
        default: return nil
        }
        return """
            void amgiQueueAction(function() {
                try {
                    if (window.__amgiContentGeneration === \(contentGeneration)
                        && typeof window.\(functionName) === 'function') {
                        window.\(functionName)();
                    }
                } catch (error) {
                    console.error('userJs\(index) failed', error);
                } finally {
                    window.webkit.messageHandlers.amgiUserActionComplete.postMessage({
                        contentGeneration: \(contentGeneration),
                        requestID: \(requestID)
                    });
                }
            });
            """
    }

    /// Loads the frame HTML template from the bundled CardWebViewBridge.js resource.
    /// Despite the .js extension, this file is the complete HTML frame document
    /// (including <style> and <script> blocks) with runtime placeholder tokens.
    /// It is named .js because the resource was extracted under that name in Task 8.
    // Internal rather than private: the HTML builder lives in
    // CardHTMLBuilder.swift now, and `private` is file-scoped.
    static let bridgeFrameTemplate: String = {
        guard let url = Bundle.main.url(forResource: "CardWebViewBridge", withExtension: "js", subdirectory: "Review"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            assertionFailure("CardWebViewBridge.js missing from bundle — regenerate xcodeproj")
            return ""
        }
        return str
    }()
}

// MARK: - Representable conformance

extension CardWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: CardWebViewCoordinator) {
        dismantleWebView(webView, coordinator: coordinator)
    }
}
