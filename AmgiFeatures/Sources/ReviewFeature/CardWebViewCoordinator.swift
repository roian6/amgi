//
//  CardWebViewCoordinator.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 01.05.2026.
//

import OSLog
import AppCore
import Foundation
import WebKit
import SwiftUI
import AVFoundation
import UIKit
import SafariServices
import AmgiCardWeb

// MARK: - CardWebViewCoordinator

/// WKNavigationDelegate + WKScriptMessageHandler + AVSpeechSynthesizerDelegate
/// for CardWebView.  Lifted from the DreamAfar fork (AnkiApp/Sources/Review/CardWebView.swift
/// — nested `Coordinator` class, lines ~1757-2053) and promoted to a top-level type.
///
/// The coordinator is responsible for:
///  - Receiving the 7 JS bridge messages (amgi* names)
///  - Calling back to the SwiftUI layer via stored closures
///  - AVSpeechSynthesizer integration for TTS
///  - Frame-load lifecycle so per-card evaluateJavaScript runs at the right moment
@MainActor
final class CardWebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, AVSpeechSynthesizerDelegate {

    private struct PendingUserAction {
        let requestID: Int
        let index: Int
        let contentIdentity: String
        let contentGeneration: Int
        var isExecuting = false
    }

    private struct ActiveTTS {
        let contentGeneration: Int
        let requestID: Int
        let utterance: AVSpeechUtterance
    }

    // MARK: State tracked across updates

    var lastPageSignature: String?
    var lastContentSignature: String?
    var lastReplayRequestID: Int = 0
    var contentLayoutScript = ""
    var lastStopAudioRequestID: Int = 0
    var lastScrollRequestID: Int = 0
    private(set) var lastUserActionRequestID: Int = 0
    private(set) var contentGeneration: Int = 0
    var lastLookupHighlightGeneration: Int = 0
    var isPageLoaded = false
    var pendingUpdateScript: String?
    var openLinksExternally: Bool = true
    weak var currentWebView: WKWebView?
    private var currentContentIdentity: String?
    private var readyContentGeneration: Int?
    private var lastObservedUserActionRequestID = 0
    private var pendingUserActions: [PendingUserAction] = []
    private var audioCommandQueue = CardWebViewAudioCommandQueue()

    // MARK: Callbacks (injected by makeCoordinator)

    private let onAudioStateChange: ((Bool) -> Void)?
    private let onCardBackgroundColorChange: ((Color, Bool) -> Void)?
    private let onLookupRequested: ((String?, String?, CGPoint) -> Void)?
    private let onShowAnswerRequested: (() -> Void)?
    private let onReviewTapRequested: ((CGFloat) -> Void)?
    private let onEditableFocusChange: ((Bool) -> Void)?

    // MARK: Private state

    private var lastThemePayload: String?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var activeTTS: ActiveTTS?

    // MARK: Init

    init(
        onAudioStateChange: ((Bool) -> Void)? = nil,
        onCardBackgroundColorChange: ((Color, Bool) -> Void)? = nil,
        onLookupRequested: ((String?, String?, CGPoint) -> Void)? = nil,
        onShowAnswerRequested: (() -> Void)? = nil,
        onReviewTapRequested: ((CGFloat) -> Void)? = nil,
        onEditableFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.onAudioStateChange = onAudioStateChange
        self.onCardBackgroundColorChange = onCardBackgroundColorChange
        self.onLookupRequested = onLookupRequested
        self.onShowAnswerRequested = onShowAnswerRequested
        self.onReviewTapRequested = onReviewTapRequested
        self.onEditableFocusChange = onEditableFocusChange
        super.init()
        speechSynthesizer.delegate = self
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "amgiCardReady" {
            guard let generation = (message.body as? NSNumber)?.intValue,
                  let webView = message.webView else { return }
            markContentReady(generation: generation, webView: webView)
            return
        }

        if message.name == "amgiUserActionComplete" {
            guard let body = message.body as? [String: Any],
                  let generation = (body["contentGeneration"] as? NSNumber)?.intValue,
                  let requestID = (body["requestID"] as? NSNumber)?.intValue,
                  let webView = message.webView else { return }
            completeUserAction(
                requestID: requestID,
                contentGeneration: generation,
                webView: webView
            )
            return
        }

        if message.name == "amgiEditableFocus" {
            if let isFocused = message.body as? Bool {
                onEditableFocusChange?(isFocused)
            } else if let number = message.body as? NSNumber {
                onEditableFocusChange?(number.boolValue)
            }
            return
        }

        if message.name == "amgiShowAnswer" {
            onShowAnswerRequested?()
            return
        }

        if message.name == "amgiReviewTap" {
            guard let body = message.body as? [String: Any],
                  let x = body["x"] as? NSNumber,
                  let width = body["width"] as? NSNumber,
                  width.doubleValue > 0 else { return }
            let fraction = min(max(x.doubleValue / width.doubleValue, 0), 1)
            onReviewTapRequested?(CGFloat(fraction))
            return
        }

        if message.name == "amgiAudioState" {
            if let isPlaying = message.body as? Bool {
                onAudioStateChange?(isPlaying)
            } else if let number = message.body as? NSNumber {
                onAudioStateChange?(number.boolValue)
            }
            return
        }

        if message.name == "amgiStopTts" {
            stopTTS(from: message.body)
            return
        }

        if message.name == "amgiSpeakTts" {
            speakTTS(from: message.body)
            return
        }


        if message.name == "amgiCardTheme" {
            guard let body = message.body as? [String: Any] else { return }
            let colorString = body["backgroundColor"] as? String ?? ""
            let isDark = (body["isDark"] as? Bool) ?? false
            let payload = colorString + "|" + String(isDark)
            guard payload != lastThemePayload else { return }
            lastThemePayload = payload
            guard let color = Self.parseCSSColor(colorString) else { return }
            onCardBackgroundColorChange?(color, isDark)
            return
        }

        if message.name == "amgiLookupText" {
            // Silently drop when no lookup callback is wired (inert behavior per Q1 resolution).
            guard let body = message.body as? [String: Any] else { return }
            let text = body["text"] as? String
            let sentence = body["sentence"] as? String
            let x = (body["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
            let y = (body["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
            onLookupRequested?(text, sentence, CGPoint(x: x, y: y))
            return
        }

        guard message.name == "amgiOpenLink" else { return }
        let href: String?
        if let string = message.body as? String {
            href = string
        } else {
            href = nil
        }

        guard let href, !href.isEmpty else { return }
        openLink(href)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard message.name == "amgiPrepareAudio",
              message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let generation = (body["contentGeneration"] as? NSNumber)?.intValue,
              generation == contentGeneration,
              message.webView != nil,
              message.webView === currentWebView else {
            replyHandler(false, nil)
            return
        }
        replyHandler(ReviewAudioSession.prepareForPlayback(), nil)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self,
                  let activeTTS = self.activeTTS,
                  ObjectIdentifier(activeTTS.utterance) == utteranceID,
                  activeTTS.contentGeneration == self.contentGeneration else { return }
            self.onAudioStateChange?(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishTTS(utteranceID)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishTTS(utteranceID)
        }
    }

    // MARK: - TTS

    func stopTTS() {
        let hadActiveTTS = activeTTS != nil
        activeTTS = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        guard hadActiveTTS else { return }
        onAudioStateChange?(false)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Cards render untrusted, shared-deck-authored HTML and JS, so the
        // only navigations allowed are the app's own asset scheme and the
        // about: document itself. `file:` and `javascript:` were whitelisted
        // here, which removed the app's own guard against a card navigating
        // the frame to a local file or injecting script through a URL.
        let scheme = url.scheme?.lowercased()
        if scheme == "about" || scheme == CardAssetPath.scheme {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL || scheme == "javascript" {
            Log.review.error("Blocked \(scheme ?? "unknown", privacy: .public) navigation from card content")
            decisionHandler(.cancel)
            return
        }

        // Custom app links should always go to the system.
        let isWebLink = scheme == "http" || scheme == "https"
        if !isWebLink || openLinksExternally {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.openExternally(url) }
        } else {
            // Keep http/https inside WKWebView when external opening is disabled.
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true

        guard let pendingUpdateScript else { return }
        self.pendingUpdateScript = nil
        webView.evaluateJavaScript(contentLayoutScript + "\n" + pendingUpdateScript) { _, error in
            if let error {
                Log.review.error("evaluateJavaScript error: \(error)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        Log.review.error("Navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        Log.review.error("Provisional navigation failed: \(error)")
    }

    func beginContentUpdate(identity: String) {
        contentGeneration &+= 1
        currentContentIdentity = identity
        readyContentGeneration = nil
        audioCommandQueue.beginContentUpdate(
            generation: contentGeneration,
            identity: identity
        )
        if let lastPending = pendingUserActions.last {
            lastUserActionRequestID = lastPending.requestID
        }
        pendingUserActions.removeAll()
    }

    func observeUserAction(
        requestID: Int,
        index: Int?,
        targetsCurrentContent: Bool,
        contentIdentity: String,
        webView: WKWebView
    ) {
        guard requestID != lastObservedUserActionRequestID else { return }
        lastObservedUserActionRequestID = requestID
        guard targetsCurrentContent,
              let index,
              (1...8).contains(index),
              contentIdentity == currentContentIdentity else {
            lastUserActionRequestID = requestID
            return
        }
        pendingUserActions.append(PendingUserAction(
            requestID: requestID,
            index: index,
            contentIdentity: contentIdentity,
            contentGeneration: contentGeneration
        ))
        executeNextUserActionIfReady(in: webView)
    }

    private func markContentReady(generation: Int, webView: WKWebView) {
        guard generation == contentGeneration else { return }
        readyContentGeneration = generation
        audioCommandQueue.markContentReady(generation: generation)
        executeAudioCommandIfReady(in: webView)
        executeNextUserActionIfReady(in: webView)
    }

    func observeAudioCommand(
        requestID: Int,
        command: CardWebViewAudioCommand,
        contentIdentity: String,
        webView: WKWebView
    ) {
        audioCommandQueue.enqueue(
            requestID: requestID,
            command: command,
            contentGeneration: contentGeneration,
            contentIdentity: contentIdentity
        )
        executeAudioCommandIfReady(in: webView)
    }

    private func executeAudioCommandIfReady(in webView: WKWebView) {
        guard let command = audioCommandQueue.takeReadyCommand() else { return }
        let script: String
        switch command {
        case .replay(let mode):
            script = "window.amgiReplayAll && window.amgiReplayAll('\(mode.rawValue)', \(contentGeneration));"
        case .stop:
            script = "window.amgiStopAllAudio && window.amgiStopAllAudio(\(contentGeneration));"
        }
        webView.evaluateJavaScript(script) { _, error in
            if let error { Log.review.error("audio command failed: \(error)") }
        }
    }

    private func executeNextUserActionIfReady(in webView: WKWebView) {
        guard readyContentGeneration == contentGeneration,
              !pendingUserActions.isEmpty,
              !pendingUserActions[0].isExecuting else { return }
        let pending = pendingUserActions[0]
        guard pending.contentGeneration == contentGeneration,
              pending.contentIdentity == currentContentIdentity,
              let script = CardWebView.userActionScript(
                index: pending.index,
                contentGeneration: pending.contentGeneration,
                requestID: pending.requestID
              ) else { return }
        pendingUserActions[0].isExecuting = true
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let error else { return }
            Log.review.error("userJs\(pending.index) failed: \(error)")
            self?.completeUserAction(
                requestID: pending.requestID,
                contentGeneration: pending.contentGeneration,
                webView: webView
            )
        }
    }

    private func completeUserAction(
        requestID: Int,
        contentGeneration: Int,
        webView: WKWebView
    ) {
        guard let pending = pendingUserActions.first,
              pending.requestID == requestID,
              pending.contentGeneration == contentGeneration else { return }
        lastUserActionRequestID = requestID
        pendingUserActions.removeFirst()
        executeNextUserActionIfReady(in: webView)
    }

}

private extension CardWebViewCoordinator {
    func speakTTS(from body: Any) {
        guard let payload = body as? [String: Any],
              let generation = (payload["contentGeneration"] as? NSNumber)?.intValue,
              let requestID = (payload["requestID"] as? NSNumber)?.intValue,
              generation == contentGeneration else { return }
        let text = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        stopTTS()

        let utterance = AVSpeechUtterance(string: text)
        let lang = ((payload["lang"] as? String) ?? "").replacingOccurrences(of: "_", with: "-")
        let preferredVoices = ((payload["voices"] as? String) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let voice = preferredVoice(lang: lang, preferredNames: preferredVoices) {
            utterance.voice = voice
        } else if !lang.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: lang)
        }

        let speedMultiplier = Float((payload["speed"] as? String) ?? "") ?? 1
        let mappedRate = AVSpeechUtteranceDefaultSpeechRate * max(0.25, min(speedMultiplier, 2.0))
        utterance.rate = min(max(mappedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        activeTTS = ActiveTTS(
            contentGeneration: generation,
            requestID: requestID,
            utterance: utterance
        )
        guard ReviewAudioSession.prepareForPlayback() else {
            finishTTS(ObjectIdentifier(utterance))
            return
        }
        speechSynthesizer.speak(utterance)
    }

    func stopTTS(from body: Any) {
        guard let payload = body as? [String: Any],
              let generation = (payload["contentGeneration"] as? NSNumber)?.intValue,
              let requestID = (payload["requestID"] as? NSNumber)?.intValue,
              let activeTTS,
              activeTTS.contentGeneration == generation,
              activeTTS.requestID == requestID else { return }
        stopTTS()
    }

    func finishTTS(_ utteranceID: ObjectIdentifier) {
        guard let activeTTS,
              ObjectIdentifier(activeTTS.utterance) == utteranceID else { return }
        self.activeTTS = nil
        guard activeTTS.contentGeneration == contentGeneration else { return }
        onAudioStateChange?(false)
        currentWebView?.evaluateJavaScript(
            "window.amgiTtsDidFinish && window.amgiTtsDidFinish(\(activeTTS.contentGeneration), \(activeTTS.requestID));"
        ) { _, error in
            if let error { Log.review.error("TTS completion failed: \(error)") }
        }
    }

    func preferredVoice(lang: String, preferredNames: [String]) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        for preferredName in preferredNames {
            if let voice = voices.first(where: { $0.identifier.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                return voice
            }
            if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                return voice
            }
        }

        guard !lang.isEmpty else { return nil }
        return voices.first(where: { $0.language.caseInsensitiveCompare(lang) == .orderedSame })
            ?? voices.first(where: { $0.language.lowercased().hasPrefix(lang.lowercased()) })
    }

    // MARK: - Link handling

    func openLink(_ href: String) {
        let resolvedURL = URL(string: href, relativeTo: currentWebView?.url)?.absoluteURL
            ?? URL(string: href)

        guard let url = resolvedURL else { return }

        let scheme = url.scheme?.lowercased()
        let isWebLink = scheme == "http" || scheme == "https"

        if isWebLink, !openLinksExternally {
            currentWebView?.load(URLRequest(url: url))
            return
        }

        DispatchQueue.main.async { self.openExternally(url) }
    }

    func openExternally(_ url: URL) {
        if url.scheme == "http" || url.scheme == "https" {
            presentSafariView(url: url)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    func presentSafariView(url: URL) {
        // `.first` could pick a background scene and `windows.first` is not
        // necessarily the key window, so under multi-window or Stage Manager
        // a tapped card link could present on the wrong window — or nowhere.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else {
            UIApplication.shared.open(url)
            return
        }
        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let safari = SFSafariViewController(url: url)
        topVC.present(safari, animated: true)
    }

    // MARK: - CSS color parsing

    static func parseCSSColor(_ cssColor: String) -> Color? {
        let trimmed = cssColor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            return parseHexColor(trimmed)
        }

        if trimmed.hasPrefix("rgb(") || trimmed.hasPrefix("rgba(") {
            let pattern = #"rgba?\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

            func component(_ idx: Int) -> Double {
                guard let r = Range(match.range(at: idx), in: trimmed) else { return 0 }
                let value = Double(trimmed[r]) ?? 0
                return max(0, min(255, value)) / 255.0
            }

            var alpha: Double = 1
            if match.range(at: 4).location != NSNotFound,
               let r = Range(match.range(at: 4), in: trimmed) {
                let value = Double(trimmed[r]) ?? 1
                alpha = max(0, min(1, value))
            }

            return Color(red: component(1), green: component(2), blue: component(3), opacity: alpha)
        }

        if trimmed == "transparent" {
            return .clear
        }

        return nil
    }

    static func parseHexColor(_ hex: String) -> Color? {
        let value = String(hex.dropFirst())
        let chars = Array(value)
        func hexByte(_ a: Character, _ b: Character) -> UInt8 {
            UInt8(String([a, b]), radix: 16) ?? 0
        }

        switch chars.count {
        case 3:
            let r = hexByte(chars[0], chars[0])
            let g = hexByte(chars[1], chars[1])
            let b = hexByte(chars[2], chars[2])
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case 6:
            let r = hexByte(chars[0], chars[1])
            let g = hexByte(chars[2], chars[3])
            let b = hexByte(chars[4], chars[5])
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case 8:
            let r = hexByte(chars[0], chars[1])
            let g = hexByte(chars[2], chars[3])
            let b = hexByte(chars[4], chars[5])
            let a = hexByte(chars[6], chars[7])
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
        default:
            return nil
        }
    }
}
