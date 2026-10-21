import AnkiKit
import CoreGraphics

enum ReviewTapAction: Equatable {
    case revealAnswer
    case rate(Rating)
}

enum ReviewTapPolicy {
    static func tapControlsAvailable(
        preferenceEnabled: Bool,
        isTypedAnswerCard: Bool,
        isVoiceOverEnabled: Bool
    ) -> Bool {
        preferenceEnabled && !isTypedAnswerCard && !isVoiceOverEnabled
    }

    static func action(
        isEnabled: Bool,
        isShowingAnswer: Bool,
        isAdvancing: Bool,
        horizontalFraction: CGFloat
    ) -> ReviewTapAction? {
        guard isEnabled, !isAdvancing else { return nil }
        guard isShowingAnswer else { return .revealAnswer }
        return horizontalFraction < 0.5 ? .rate(.again) : .rate(.good)
    }

    static func showsRatingButtons(
        isShowingAnswer: Bool,
        preferenceEnabled: Bool,
        tapControlsEnabled: Bool,
        gamepadControlsEnabled: Bool = false,
        isGamepadConnected: Bool = false,
        gamepadHasRatingAction: Bool = true,
        isTypedAnswerCard: Bool,
        isVoiceOverEnabled: Bool
    ) -> Bool {
        guard isShowingAnswer else { return false }
        let tapControlsUsable = tapControlsAvailable(
            preferenceEnabled: tapControlsEnabled,
            isTypedAnswerCard: isTypedAnswerCard,
            isVoiceOverEnabled: isVoiceOverEnabled
        )
        let gamepadControlsUsable = gamepadControlsEnabled
            && isGamepadConnected
            && gamepadHasRatingAction
        let canHide = (tapControlsUsable || gamepadControlsUsable) && !isVoiceOverEnabled
        return preferenceEnabled || !canHide
    }

    static func needsBottomControlSpacer(
        isShowingAnswer: Bool,
        showsRatingButtons: Bool,
        isTypedAnswerCard: Bool
    ) -> Bool {
        !isShowingAnswer || showsRatingButtons || isTypedAnswerCard
    }
}
