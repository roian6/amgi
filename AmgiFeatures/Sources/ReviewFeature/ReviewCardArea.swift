//
//  ReviewCardArea.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 20.08.2026.
//

import SwiftUI
import AmgiCardWeb
import Theme
import UI
import AppCore
import AppShared
import AnkiClients
import AnkiKit
import Dependencies
import BrowseFeature
import TemplatesFeature
import Sharing
import ReviewCore
import SwiftUINavigation

// MARK: - Card Area

/// The card region of the reviewer: render-mode chip, the flip surface, and
/// the reveal/rating controls. Extracted from `ReviewContent` so that session
/// mutations it doesn't read (audio-playing toggles, toast, deck counts) skip
/// its body — otherwise every such change re-runs `CardWebView.updateUIView`
/// and its regex HTML processing. Owns the render-mode sheet flag and the
/// native audio player, which are only relevant here.
struct ReviewCardArea: View {
    let session: ReviewSession
    let openLinksExternally: Bool
    let cardContentAlignment: String
    let tapLookup: Bool
    let showNextReviewTime: Bool
    let tapControlsEnabled: Bool
    let gamepadControlsEnabled: Bool
    let reviewInputSettings: ReviewInputSettings
    let showAnswerButtons: Bool
    let audioAutoplayPolicy: ReviewAutoplayPolicy
    let answerAudioPolicy: ReviewAnswerAudioPolicy
    @Binding var zoomScale: Double
    let answerZoomPolicy: ReviewAnswerZoomPolicy
    let lookupHighlight: LookupHighlight
    let shortcutsEnabled: Bool
    @Binding var lookupQuery: String?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.startSync) private var startSync
    @Shared(.appStorage(ReaderPreferences.Keys.dictionaryScanLength))
    private var dictionaryScanLength: Int = 16
    @State private var showRenderModeSheet = false
    @State private var nativeAudioPlayer = NativeCardAudioPlayer()
    @State private var gamepadMonitor = ReviewGamepadMonitor()
    @State private var isAnswerTransitioning = false
    @State private var isWebEditableFocused = false
    @State private var showSyncUnavailable = false
    @State private var scrollRequestID = 0
    @State private var scrollDirection = ReviewScrollDirection.down
    @State private var continuousScrollDelta: CGFloat?
    @State private var userActionRequestID = 0
    @State private var userActionIndex: Int?
    @State private var userActionCardID: CardID?
    @State private var userActionIsAnswerSide: Bool?

    private var mediaFolder: URL? { session.mediaFolder }
    private var tapControlsAvailable: Bool {
        ReviewTapPolicy.tapControlsAvailable(
            preferenceEnabled: tapControlsEnabled,
            isTypedAnswerCard: session.isTypedAnswerCard,
            isVoiceOverEnabled: isVoiceOverEnabled
        )
    }

    private var reviewShortcutsActive: Bool {
        shortcutsEnabled && !showRenderModeSheet && session.answerError == nil
    }

    private var shouldShowRatingButtons: Bool {
        ReviewTapPolicy.showsRatingButtons(
            isShowingAnswer: session.showAnswer,
            preferenceEnabled: showAnswerButtons,
            tapControlsEnabled: tapControlsEnabled,
            gamepadControlsEnabled: gamepadControlsEnabled,
            isGamepadConnected: gamepadMonitor.hasConnectedController,
            gamepadHasRatingAction: ReviewInputReachability.hasRatingAction(
                in: reviewInputSettings,
                availableInputs: gamepadMonitor.availableInputs
            ),
            isTypedAnswerCard: session.isTypedAnswerCard,
            isVoiceOverEnabled: isVoiceOverEnabled
        )
    }

    var body: some View {
        if session.currentCardId == nil {
            // No card prepared yet — `start()` is still in its backend round
            // trip. Rendering the normal chrome here meant an empty WKWebView
            // under a "HTML · sandboxed" label and a dead Show Answer button,
            // with nothing to say the app was working.
            preparingCard
        } else {
            cardContent
        }
    }

    private var preparingCard: some View {
        VStack(spacing: AmgiSpacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Preparing cards\u{2026}")
                .amgiFont(.body)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            RenderModeChipRow(
                isNative: isNativeMode,
                isAuto: session.resolvedByAuto,
                templateName: session.templateName,
                onTap: { showRenderModeSheet = true }
            )
            .padding(.horizontal)

            cardFlipRegion
            .frame(maxWidth: .infinity)
            .onChange(of: session.stopAudioRequestID) { _, _ in
                nativeAudioPlayer.stop()
            }
            .onChange(of: session.currentCardId) { _, _ in
                isWebEditableFocused = false
                userActionIndex = nil
                userActionCardID = nil
                userActionIsAnswerSide = nil
                nativeAudioPlayer.stop()
                playNativeAudio(automatic: true)
            }
            .onChange(of: session.showAnswer) { _, shown in
                guard shown else { return }
                nativeAudioPlayer.stop()
                if answerZoomPolicy.shouldResetOnAnswer {
                    zoomScale = ReviewZoomPolicy.reset()
                }
                playNativeAudio(automatic: true)
            }
            .onChange(of: session.replayRequestID) { _, _ in
                playNativeAudio(automatic: false)
            }
            .onChange(of: nativeAudioPlayer.isPlaying) { _, playing in
                if isNativeMode { session.updateAudioPlaying(playing) }
            }
            .onDisappear { nativeAudioPlayer.stop() }
            .sheet(isPresented: $showRenderModeSheet) { renderModeSheet }

            if ReviewTapPolicy.needsBottomControlSpacer(
                isShowingAnswer: session.showAnswer,
                showsRatingButtons: shouldShowRatingButtons,
                isTypedAnswerCard: session.isTypedAnswerCard
            ) {
                Spacer()
            }

            if session.isTypedAnswerCard {
                TypedAnswerField(session: session)
            }

            if shouldShowRatingButtons {
                answerButtons
            } else if !session.showAnswer {
                Button {
                    session.revealAnswer()
                } label: {
                    Text("Show Answer")
                        .amgiFont(.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(keyboardActive ? KeyboardShortcut(.space, modifiers: []) : nil)
                .padding()
            }
        }
        .animation(AmgiMotion.quick, value: session.showAnswer)
        .onAppear { updateGamepadMonitoring() }
        .onChange(of: gamepadControlsEnabled) { _, _ in updateGamepadMonitoring() }
        .onChange(of: gamepadMonitor.inputCount) { _, _ in
            for event in gamepadMonitor.drainInputs() {
                handleGamepadInput(event)
            }
        }
        .onChange(of: gamepadMonitor.axisFrameCount) { _, _ in
            handleGamepadAxisFrames(gamepadMonitor.drainAxisFrames())
        }
        .onDisappear { gamepadMonitor.stop() }
        .alert("Sync unavailable", isPresented: $showSyncUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sync isn't available from this review session. Close the reviewer and check your sync setup.")
        }
    }

    private var isNativeMode: Bool {
        if case .native = session.resolvedMode { return true }
        return false
    }

    private var keyboardActive: Bool {
        reviewShortcutsActive && !session.isTypedAnswerCard
    }

    /// The reveal region. Native cards get the 3D flip (pure SwiftUI, crisp);
    /// WebView cards swap sides without rotation, because 3D-rotating a live
    /// `WKWebView` rasterizes to a blurred frame mid-flip.
    @ViewBuilder
    private var cardFlipRegion: some View {
        if isNativeMode {
            FlipContainer(showBack: session.showAnswer) { isBack in
                cardSurface(isBack: isBack)
            }
        } else {
            cardSurface(isBack: session.showAnswer)
        }
    }

    private var renderModeSheet: some View {
        RenderModeSheet(
            explainer: renderModeExplainer,
            template: session.currentTemplateTarget,
            templateName: session.templateName,
            onChanged: { session.reresolveCurrentCard() }
        )
    }

    private var renderModeExplainer: String {
        switch session.resolvedMode {
        case .native:
            return "shown with the built-in renderer."
        case .html:
            let prefs = currentRenderEnginePreferences(
                mid: session.currentNote?.mid,
                ord: Int(session.currentCardOrdinal)
            )
            if (prefs.override ?? prefs.global) == .alwaysHTML {
                return "shown with its own template, because you chose that below."
            }
            return "shown with its own template, because it uses formatting the built-in renderer can't show."
        }
    }

    @ViewBuilder
    private func cardSurface(isBack: Bool) -> some View {
        switch session.resolvedMode {
        case .native(let front, let back):
            nativeCardSurface(content: isBack ? back : front, isBack: isBack)
                .frame(maxWidth: ReviewLayoutPolicy.maximumContentWidth(
                    isRegularWidth: horizontalSizeClass == .regular
                ))
                .frame(maxWidth: .infinity)
        case .html:
            VStack(spacing: 0) {
                CardWebView(
                    html: isBack ? session.backHTML : session.frontHTML,
                    cardID: session.currentCardId,
                    cardCSS: session.cardCSS,
                    autoplayEnabled: audioAutoplayPolicy == .enabled,
                    zoomScale: zoomScale,
                    maximumContentWidth: ReviewLayoutPolicy.maximumContentWidth(
                        isRegularWidth: horizontalSizeClass == .regular
                    ),
                    isAnswerSide: isBack,
                    cardOrdinal: session.currentCardOrdinal,
                    replayRequestID: session.replayRequestID,
                    replayCardID: session.replayCardID,
                    replayIsAnswerSide: session.replayIsAnswerSide,
                    stopAudioRequestID: session.stopAudioRequestID,
                    scrollRequestID: scrollRequestID,
                    scrollDirection: scrollDirection,
                    continuousScrollDelta: continuousScrollDelta,
                    userActionRequestID: userActionRequestID,
                    userActionIndex: userActionIndex,
                    userActionCardID: userActionCardID,
                    userActionIsAnswerSide: userActionIsAnswerSide,
                    replayMode: isBack
                        ? CardWebViewReplayMode.answerPolicy(answerAudioPolicy)
                        : .question,
                    openLinksExternally: openLinksExternally,
                    lookupPopupEnabled: tapLookup && !session.requiresTypedAnswerInput,
                    dictionaryScanLength: dictionaryScanLength,
                    lookupHighlight: lookupHighlight,
                    contentAlignment: CardWebViewContentAlignment(rawValue: cardContentAlignment) ?? .center,
                    tapControlsEnabled: tapControlsAvailable,
                    onAudioStateChange: { playing in session.updateAudioPlaying(playing) },
                    onCardBackgroundColorChange: { color, isDark in
                        session.updateCardChrome(color: color, isDark: isDark)
                    },
                    // No tap-lookup while the typed-answer input is up — the
                    // dictionary would hand over the answer to be typed.
                    onLookupRequested: tapLookup && !session.requiresTypedAnswerInput ? { text, _, _ in
                        if let text, !text.isEmpty { lookupQuery = text }
                    } : nil,
                    onShowAnswerRequested: { session.revealAnswer() },
                    onReviewTapRequested: handleReviewTap,
                    onEditableFocusChange: { isWebEditableFocused = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private func nativeCardSurface(content: NativeCardContent, isBack: Bool) -> some View {
        if tapControlsAvailable {
            GeometryReader { proxy in
                NativeCardView(
                    content: content,
                    isAnswerSide: isBack,
                    mediaFolder: mediaFolder,
                    zoomScale: zoomScale,
                    scrollRequestID: scrollRequestID,
                    scrollDirection: scrollDirection,
                    continuousScrollDelta: continuousScrollDelta
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        handleReviewTap(value.location.x / max(proxy.size.width, 1))
                    }
                )
            }
        } else {
            NativeCardView(
                content: content,
                isAnswerSide: isBack,
                mediaFolder: mediaFolder,
                zoomScale: zoomScale,
                scrollRequestID: scrollRequestID,
                scrollDirection: scrollDirection,
                continuousScrollDelta: continuousScrollDelta
            )
        }
    }

    private func handleReviewTap(_ horizontalFraction: CGFloat) {
        let action = ReviewTapPolicy.action(
            isEnabled: tapControlsAvailable,
            isShowingAnswer: session.showAnswer,
            isAdvancing: session.isAdvancing || isAnswerTransitioning,
            horizontalFraction: horizontalFraction
        )
        performReviewAction(action)
    }

    private func handleGamepadInput(_ event: ReviewGamepadInputEvent) {
        let action = ReviewInputRouter.action(
            for: event.input,
            settings: reviewInputSettings,
            context: reviewInputContext
        )
        if event.source == .axisEdge, case .scroll = action { return }
        performSemanticAction(action)
    }

    private func handleGamepadAxisFrames(_ frames: [ReviewGamepadAxisFrame]) {
        var combinedDelta: CGFloat = 0
        for frame in frames {
            var frameDelta: CGFloat = 0
            for sample in frame.samples {
                guard case .scroll(let direction) = ReviewInputRouter.action(
                    for: sample.input,
                    settings: reviewInputSettings,
                    context: reviewInputContext
                ) else { continue }
                frameDelta += ReviewScrollPolicy.continuousDelta(
                    magnitude: sample.magnitude,
                    elapsed: frame.elapsed,
                    direction: direction
                )
            }
            combinedDelta += ReviewScrollPolicy.clampedCombinedDelta(
                frameDelta,
                elapsed: frame.elapsed
            )
        }
        guard combinedDelta != 0 else { return }
        continuousScrollDelta = combinedDelta
        scrollRequestID &+= 1
    }

    private var reviewInputContext: ReviewInputContext {
        ReviewInputContext(
            preferenceEnabled: gamepadControlsEnabled,
            hasConnectedController: gamepadMonitor.hasConnectedController,
            shortcutsEnabled: shortcutsEnabled,
            requiresTypedAnswerInput: session.requiresTypedAnswerInput,
            side: session.showAnswer ? .answer : .question,
            isAdvancing: session.isAdvancing,
            isAnswerTransitioning: isAnswerTransitioning,
            hasBlockingPresentation: showRenderModeSheet || session.answerError != nil,
            hasEditableWebFocus: isWebEditableFocused,
            canUndo: session.canUndo,
            syncActionInstalled: startSync.isInstalled,
            userActionsAvailable: !isNativeMode
        )
    }

    private func performReviewAction(_ action: ReviewTapAction?) {
        switch action {
        case .revealAnswer:
            isAnswerTransitioning = true
            session.revealAnswer()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                isAnswerTransitioning = false
            }
        case .rate(let rating):
            session.answer(rating: rating)
        case nil:
            break
        }
    }

    private func performSemanticAction(_ action: ReviewSemanticAction?) {
        switch action {
        case .revealAnswer:
            isAnswerTransitioning = true
            session.revealAnswer()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                isAnswerTransitioning = false
            }
        case .rate(let rating):
            session.answer(rating: rating)
        case .undo:
            session.undo()
        case .sync:
            startSync()
        case .syncUnavailable:
            showSyncUnavailable = true
        case .replayOrStopAudio:
            if session.isAudioPlaying {
                session.bumpStopAudioRequest()
            } else {
                session.bumpReplayRequest()
            }
        case .scroll(let direction):
            scrollDirection = direction
            continuousScrollDelta = nil
            scrollRequestID &+= 1
        case .userAction(let index):
            userActionIndex = index
            userActionCardID = session.currentCardId
            userActionIsAnswerSide = session.showAnswer
            userActionRequestID &+= 1
        case nil:
            break
        }
    }

    private func updateGamepadMonitoring() {
        if gamepadControlsEnabled {
            gamepadMonitor.start()
        } else {
            gamepadMonitor.stop()
        }
    }

    private func playNativeAudio(automatic: Bool) {
        guard case .native(let front, let back) = session.resolvedMode else { return }
        guard !automatic || audioAutoplayPolicy == .enabled else { return }
        let files: [String]
        if session.showAnswer {
            switch answerAudioPolicy {
            case .questionAndAnswer:
                files = back.audioFiles
            case .answerOnly:
                let questionFiles = Set(front.audioFiles)
                files = back.audioFiles.filter { !questionFiles.contains($0) }
            }
        } else {
            files = front.audioFiles
        }
        guard !files.isEmpty else { return }
        nativeAudioPlayer.play(files: files, mediaFolder: mediaFolder)
    }

    private var answerButtons: some View {
        RatingBar(
            intervals: session.nextIntervals,
            showIntervals: showNextReviewTime,
            isDisabled: session.isAdvancing,
            shortcutsEnabled: keyboardActive,
            onRate: { rating in session.answer(rating: rating) }
        )
    }
}

/// Native input for typed-answer (`{{type:}}`) cards. Native rather than an
/// in-card HTML input because WKWebView ignores web keyboard attributes and
/// the predictive bar would offer the answer as a suggestion.
struct TypedAnswerField: View {
    @Bindable var session: ReviewSession
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Type the answer", text: text)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit { session.revealAnswer() }
            .focused($focused)
            .padding(.horizontal)
            .onAppear { focused = true }
    }

    private var text: Binding<String> {
        Binding(
            get: { session.typedAnswer },
            set: { if !session.showAnswer { session.typedAnswer = $0 } }
        )
    }
}
