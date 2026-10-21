import SwiftUI
import AppCore
import Sharing
import Theme

struct ReviewInputSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.reviewInputSettings))
    private var settingsRaw: String = ""

    var body: some View {
        SettingsPage {
            presetSection
            ForEach(inputSections) { section in
                SettingsSectionHeader(title: section.title)
                SettingsGroup {
                    ForEach(Array(section.inputs.enumerated()), id: \.offset) { index, input in
                        ReviewInputMappingRow(
                            input: input,
                            questionAction: actionBinding(for: input, side: .question),
                            answerAction: actionBinding(for: input, side: .answer)
                        )
                        if index < section.inputs.count - 1 { SettingsSeparator() }
                    }
                }
            }
            SettingsFootnote(
                "Sync uses the app's normal sync flow. User Action 1–8 call userJs1–userJs8 "
                    + "on HTML card templates when defined; they do nothing on native cards."
            )
        }
        .navigationTitle("Controller Bindings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var presetSection: some View {
        Group {
            SettingsSectionHeader(title: "Preset")
            SettingsGroup {
                SettingsValueRow(
                    title: "Active assignment",
                    value: presetTitle,
                    systemImage: "slider.horizontal.3",
                    tone: .accent
                )
                SettingsSeparator()
                SettingsButtonRow(
                    title: "Use AnkiMobile-style preset",
                    systemImage: "gamecontroller.fill",
                    tone: .review,
                    action: { store(.ankiMobile) }
                )
                SettingsSeparator()
                SettingsButtonRow(
                    title: "Reset to Amgi defaults",
                    systemImage: "arrow.counterclockwise",
                    tone: .neutral,
                    action: { store(.legacyAmgi) }
                )
            }
            SettingsFootnote(
                "Question and answer assignments are independent. Off disables one side. "
                    + "If imported settings overlap, the last matching assignment is active."
            )
        }
    }

    private var settings: ReviewInputSettings {
        ReviewInputSettingsCodec.decode(settingsRaw)
    }

    private var presetTitle: String {
        if settings.presetID == .legacyAmgi { return "Amgi default" }
        if settings.presetID == .ankiMobile { return "AnkiMobile-style" }
        return "Custom"
    }

    private func actionBinding(
        for input: ReviewInputID,
        side: ReviewCardSide
    ) -> Binding<ReviewActionID> {
        Binding(
            get: { settings.action(for: input, side: side) },
            set: { action in
                var edited = settings
                edited.setAction(action, for: input, side: side)
                store(edited)
            }
        )
    }

    private func store(_ settings: ReviewInputSettings) {
        guard let encoded = try? ReviewInputSettingsCodec.encode(settings) else { return }
        $settingsRaw.withLock { $0 = encoded }
    }
}

private struct ReviewInputMappingRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let input: ReviewInputID
    @Binding var questionAction: ReviewActionID
    @Binding var answerAction: ReviewActionID

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack(spacing: AmgiSpacing.md) {
                SettingsIconTile(systemImage: presentation.systemImage, tone: presentation.tone)
                Text(presentation.title)
                    .amgiFont(.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: AmgiSpacing.sm)
            }
            if horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AmgiSpacing.md) {
                    actionPicker(title: "Question", side: .question, selection: $questionAction)
                    actionPicker(title: "Answer", side: .answer, selection: $answerAction)
                }
            } else {
                HStack(spacing: AmgiSpacing.md) {
                    actionPicker(title: "Question", side: .question, selection: $questionAction)
                    actionPicker(title: "Answer", side: .answer, selection: $answerAction)
                }
                .padding(.leading, 30 + AmgiSpacing.md)
            }
        }
        .padding(.horizontal, AmgiSpacing.lg)
        .padding(.vertical, AmgiSpacing.md)
        .frame(minHeight: 44)
    }

    private func actionPicker(
        title: String,
        side: ReviewCardSide,
        selection: Binding<ReviewActionID>
    ) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            Text(title)
                .amgiFont(.micro)
                .foregroundStyle(palette.textTertiary)
            Picker("\(presentation.title) \(title.lowercased()) action", selection: selection) {
                if ReviewActionCatalog.entry(for: selection.wrappedValue) == nil {
                    Text("Unavailable: \(selection.wrappedValue.rawValue)")
                        .tag(selection.wrappedValue)
                        .disabled(true)
                }
                ForEach(ReviewActionCatalog.entries) { entry in
                    Text(entry.title + (entry.isAvailable ? "" : " (Unavailable)"))
                        .tag(entry.action)
                        .disabled(!entry.isAvailable || !entry.supports(side))
                }
            }
            .pickerStyle(.menu)
            .tint(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(presentation.title), \(title) action")
            .accessibilityValue(actionTitle(selection.wrappedValue))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionTitle(_ action: ReviewActionID) -> String {
        ReviewActionCatalog.entry(for: action)?.title ?? "Unavailable \(action.rawValue)"
    }

    private var presentation: ReviewInputPresentation {
        ReviewInputPresentation(input)
    }
}

private struct ReviewInputSection: Identifiable {
    let title: String
    let inputs: [ReviewInputID]
    var id: String { title }
}

private let inputSections: [ReviewInputSection] = [
    ReviewInputSection(title: "Face Buttons", inputs: [.buttonA, .buttonB, .buttonX, .buttonY]),
    ReviewInputSection(title: "D-Pad", inputs: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
    ReviewInputSection(
        title: "Shoulders & System",
        inputs: [
            .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
            .leftThumbstickButton, .rightThumbstickButton, .menu, .options,
        ]
    ),
    ReviewInputSection(
        title: "Stick Axes",
        inputs: [
            .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
            .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
        ]
    ),
]

private struct ReviewInputPresentation {
    let title: String
    let systemImage: String
    let tone: SettingsTone

    init(_ input: ReviewInputID) {
        let values: [ReviewInputID: (String, String, SettingsTone)] = [
            .buttonA: ("A Button", "a.circle", .review),
            .buttonB: ("B Button", "b.circle", .danger),
            .buttonX: ("X Button", "x.circle", .info),
            .buttonY: ("Y Button", "y.circle", .learning),
            .dpadUp: ("D-Pad Up", "arrow.up.circle", .neutral),
            .dpadDown: ("D-Pad Down", "arrow.down.circle", .neutral),
            .dpadLeft: ("D-Pad Left", "arrow.left.circle", .neutral),
            .dpadRight: ("D-Pad Right", "arrow.right.circle", .neutral),
            .leftShoulder: ("Left Shoulder", "gamecontroller.fill", .link),
            .rightShoulder: ("Right Shoulder", "gamecontroller.fill", .link),
            .leftTrigger: ("Left Trigger", "gamecontroller.fill", .mature),
            .rightTrigger: ("Right Trigger", "gamecontroller.fill", .mature),
            .leftThumbstickButton: ("Left Stick Button", "gamecontroller.fill", .accent),
            .rightThumbstickButton: ("Right Stick Button", "gamecontroller.fill", .accent),
            .menu: ("Menu", "line.3.horizontal.circle", .neutral),
            .options: ("Options", "ellipsis.circle", .neutral),
            .leftStickUp: ("Left Stick Up", "arrow.up", .accent),
            .leftStickDown: ("Left Stick Down", "arrow.down", .accent),
            .leftStickLeft: ("Left Stick Left", "arrow.left", .accent),
            .leftStickRight: ("Left Stick Right", "arrow.right", .accent),
            .rightStickUp: ("Right Stick Up", "arrow.up", .info),
            .rightStickDown: ("Right Stick Down", "arrow.down", .info),
            .rightStickLeft: ("Right Stick Left", "arrow.left", .info),
            .rightStickRight: ("Right Stick Right", "arrow.right", .info),
        ]
        let value = values[input] ?? (input.rawValue, "gamecontroller", .neutral)
        title = value.0
        systemImage = value.1
        tone = value.2
    }
}

#if DEBUG
#Preview {
    NavigationStack { ReviewInputSettingsView() }
}
#endif
