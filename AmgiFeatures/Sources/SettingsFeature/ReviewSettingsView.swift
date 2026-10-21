//
//  ReviewSettingsView.swift
//  SettingsFeature
//
//  Created by Vladimir Gusev on 02.05.2026.
//

import SwiftUI
import AppCore
import Theme
import Sharing
import ReviewCore
import ReviewFeature

struct ReviewSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.openLinksExternally))
    private var openLinksExternally: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.cardContentAlignment))
    private var cardContentAlignment: String = CardWebViewContentAlignment.center.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.autoMatchCardBackground))
    private var autoMatchCardBackground: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showRemainingDays))
    private var showRemainingDays: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showNextReviewTime))
    private var showNextReviewTime: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Shared(.appStorage(ReviewPreferences.Keys.audioAutoplay))
    private var audioAutoplay: String = ReviewAutoplayPolicy.defaultValue.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.answerAudio))
    private var answerAudio: String = ReviewAnswerAudioPolicy.defaultValue.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.answerZoom))
    private var answerZoom: String = ReviewAnswerZoomPolicy.defaultValue.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.tapControls))
    private var tapControls: Bool = false

    @Shared(.appStorage(ReviewPreferences.Keys.gamepadControls))
    private var gamepadControls: Bool = false

    @Shared(.appStorage(ReviewPreferences.Keys.reviewInputSettings))
    private var reviewInputSettingsRaw: String = ""

    @Shared(.appStorage(ReviewPreferences.Keys.showAnswerButtons))
    private var showAnswerButtons: Bool = true

    var body: some View {
        SettingsPage {
            cardDisplaySection
            answerButtonsSection
            audioSection
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardDisplaySection: some View {
        Group {
            SettingsSectionHeader(title: "Card Display")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Match toolbar to card background",
                    systemImage: "paintbrush",
                    tone: .mature,
                    isOn: Binding($autoMatchCardBackground)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Open links externally",
                    systemImage: "arrow.up.right.square",
                    tone: .accent,
                    isOn: Binding($openLinksExternally)
                )
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Vertical content placement",
                    systemImage: "arrow.up.and.down.text.horizontal",
                    tone: .link,
                    selection: Binding($cardContentAlignment)
                ) {
                    Text("Center").tag(CardWebViewContentAlignment.center.rawValue)
                    Text("Top").tag(CardWebViewContentAlignment.top.rawValue)
                }
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Zoom after showing answer",
                    systemImage: "textformat.size",
                    tone: .link,
                    selection: Binding($answerZoom)
                ) {
                    Text("Keep zoom").tag(ReviewAnswerZoomPolicy.keep.rawValue)
                    Text("Reset zoom").tag(ReviewAnswerZoomPolicy.reset.rawValue)
                }
            }
        }
    }

    private var answerButtonsSection: some View {
        Group {
            SettingsSectionHeader(title: "Answer Buttons")
            SettingsGroup {
                SettingsPickerRow(
                    title: "Automatic card audio",
                    systemImage: "play.circle",
                    tone: .learning,
                    selection: Binding($audioAutoplay)
                ) {
                    Text("On").tag(ReviewAutoplayPolicy.enabled.rawValue)
                    Text("Off").tag(ReviewAutoplayPolicy.disabled.rawValue)
                }
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Replay on answer",
                    systemImage: "repeat",
                    tone: .learning,
                    selection: Binding($answerAudio)
                ) {
                    Text("Question and answer").tag(ReviewAnswerAudioPolicy.questionAndAnswer.rawValue)
                    Text("Answer only").tag(ReviewAnswerAudioPolicy.answerOnly.rawValue)
                }
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Tap controls",
                    systemImage: "hand.tap",
                    tone: .accent,
                    isOn: Binding($tapControls)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Gamepad controls",
                    systemImage: "gamecontroller",
                    tone: .accent,
                    isOn: Binding($gamepadControls)
                )
                SettingsSeparator()
                SettingsRowLink(
                    title: "Controller bindings",
                    systemImage: "slider.horizontal.3",
                    tone: .link,
                    detail: controllerPresetTitle
                ) {
                    ReviewInputSettingsView()
                }
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Show answer buttons",
                    systemImage: "rectangle.bottomthird.inset.filled",
                    tone: .review,
                    isOn: Binding($showAnswerButtons)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Show remaining counts",
                    systemImage: "number",
                    tone: .review,
                    isOn: Binding($showRemainingDays)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Show next review time",
                    systemImage: "clock",
                    tone: .info,
                    isOn: Binding($showNextReviewTime)
                )
            }
        }
    }

    private var controllerPresetTitle: String {
        let preset = ReviewInputSettingsCodec.decode(reviewInputSettingsRaw).presetID
        if preset == .legacyAmgi { return "Amgi default" }
        if preset == .ankiMobile { return "AnkiMobile-style" }
        return "Custom"
    }

    private var audioSection: some View {
        Group {
            SettingsSectionHeader(title: "Audio")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Play audio in silent mode",
                    systemImage: "speaker.wave.2",
                    tone: .learning,
                    isOn: Binding($playAudioInSilentMode)
                )
            }
        }
    }
}

#if DEBUG

#Preview {
    NavigationStack {
        ReviewSettingsView()
    }
}
#endif
