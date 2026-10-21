import AnkiKit
import AppCore
import CoreGraphics
import Foundation

enum ReviewScrollDirection: Equatable, Sendable {
    case up
    case down
}

enum ReviewSemanticAction: Equatable {
    case revealAnswer
    case rate(Rating)
    case undo
    case sync
    case syncUnavailable
    case replayOrStopAudio
    case scroll(ReviewScrollDirection)
    case userAction(Int)
}

struct ReviewInputContext {
    var preferenceEnabled: Bool = true
    var hasConnectedController: Bool = true
    var shortcutsEnabled: Bool = true
    var requiresTypedAnswerInput: Bool = false
    var side: ReviewCardSide = .question
    var isAdvancing: Bool = false
    var isAnswerTransitioning: Bool = false
    var hasBlockingPresentation: Bool = false
    var hasEditableWebFocus: Bool = false
    var canUndo: Bool = true
    var syncActionInstalled: Bool = false
    var userActionsAvailable: Bool = false
}

enum ReviewInputRouter {
    static func action(
        for input: ReviewInputID,
        settings: ReviewInputSettings,
        context: ReviewInputContext
    ) -> ReviewSemanticAction? {
        guard context.preferenceEnabled,
              context.hasConnectedController,
              context.shortcutsEnabled,
              !context.requiresTypedAnswerInput,
              !context.isAdvancing,
              !context.isAnswerTransitioning,
              !context.hasBlockingPresentation,
              !context.hasEditableWebFocus else { return nil }

        let action = settings.action(for: input, side: context.side)
        guard let entry = ReviewActionCatalog.entry(for: action),
              entry.isAvailable,
              entry.supports(context.side) else { return nil }

        if action == .showAnswer { return .revealAnswer }
        if action == .showAnswerOrGood {
            return context.side == .question ? .revealAnswer : .rate(.good)
        }
        if action == .again { return .rate(.again) }
        if action == .hard { return .rate(.hard) }
        if action == .good { return .rate(.good) }
        if action == .easy { return .rate(.easy) }
        if action == .undo { return context.canUndo ? .undo : nil }
        if action == .sync { return context.syncActionInstalled ? .sync : .syncUnavailable }
        if action == .replayOrStopAudio { return .replayOrStopAudio }
        if action == .scrollUp { return .scroll(.up) }
        if action == .scrollDown { return .scroll(.down) }
        if let number = action.userActionNumber {
            return context.userActionsAvailable ? .userAction(number) : nil
        }
        return nil
    }
}

enum ReviewScrollPolicy {
    static let step: CGFloat = 160
    static let maximumVelocity: CGFloat = 900
    static let maximumFrameDuration: TimeInterval = 1.0 / 15.0

    static func targetOffset(
        currentOffset: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat,
        direction: ReviewScrollDirection
    ) -> CGFloat {
        let delta = direction == .down ? step : -step
        return min(max(currentOffset + delta, minimumOffset), maximumOffset)
    }

    static func continuousDelta(
        magnitude: Float,
        elapsed: TimeInterval,
        direction: ReviewScrollDirection
    ) -> CGFloat {
        let boundedMagnitude = min(max(CGFloat(magnitude), 0), 1)
        let boundedElapsed = min(max(elapsed, 0), maximumFrameDuration)
        let velocity = maximumVelocity * pow(boundedMagnitude, 1.6)
        let delta = velocity * boundedElapsed
        return direction == .down ? delta : -delta
    }

    static func clampedCombinedDelta(_ delta: CGFloat, elapsed: TimeInterval) -> CGFloat {
        let limit = maximumVelocity * min(max(elapsed, 0), maximumFrameDuration)
        return min(max(delta, -limit), limit)
    }

    static func targetOffset(
        currentOffset: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat,
        delta: CGFloat
    ) -> CGFloat {
        min(max(currentOffset + delta, minimumOffset), maximumOffset)
    }
}

enum ReviewLayoutPolicy {
    static let regularWidthMaximum: CGFloat = 860

    static func maximumContentWidth(isRegularWidth: Bool) -> CGFloat? {
        isRegularWidth ? regularWidthMaximum : nil
    }
}

enum ReviewInputReachability {
    static func hasRevealAction(in settings: ReviewInputSettings) -> Bool {
        ReviewInputID.allControllerInputs.contains { input in
            let action = settings.action(for: input, side: .question)
            return action == .showAnswer || action == .showAnswerOrGood
        }
    }

    static func hasRatingAction(
        in settings: ReviewInputSettings,
        availableInputs: Set<ReviewInputID> = Set(ReviewInputID.allControllerInputs)
    ) -> Bool {
        availableInputs.contains { input in
            let action = settings.action(for: input, side: .answer)
            return action == .showAnswerOrGood
                || action == .again
                || action == .hard
                || action == .good
                || action == .easy
        }
    }
}
