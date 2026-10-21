import Foundation

public struct ReviewInputID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let buttonA = Self(rawValue: "controller.button.a")
    public static let buttonB = Self(rawValue: "controller.button.b")
    public static let buttonX = Self(rawValue: "controller.button.x")
    public static let buttonY = Self(rawValue: "controller.button.y")
    public static let dpadUp = Self(rawValue: "controller.dpad.up")
    public static let dpadDown = Self(rawValue: "controller.dpad.down")
    public static let dpadLeft = Self(rawValue: "controller.dpad.left")
    public static let dpadRight = Self(rawValue: "controller.dpad.right")
    public static let leftShoulder = Self(rawValue: "controller.shoulder.left")
    public static let rightShoulder = Self(rawValue: "controller.shoulder.right")
    public static let leftTrigger = Self(rawValue: "controller.trigger.left")
    public static let rightTrigger = Self(rawValue: "controller.trigger.right")
    public static let leftThumbstickButton = Self(rawValue: "controller.thumbstick.left.button")
    public static let rightThumbstickButton = Self(rawValue: "controller.thumbstick.right.button")
    public static let menu = Self(rawValue: "controller.button.menu")
    public static let options = Self(rawValue: "controller.button.options")
    public static let leftStickUp = Self(rawValue: "controller.stick.left.up")
    public static let leftStickDown = Self(rawValue: "controller.stick.left.down")
    public static let leftStickLeft = Self(rawValue: "controller.stick.left.left")
    public static let leftStickRight = Self(rawValue: "controller.stick.left.right")
    public static let rightStickUp = Self(rawValue: "controller.stick.right.up")
    public static let rightStickDown = Self(rawValue: "controller.stick.right.down")
    public static let rightStickLeft = Self(rawValue: "controller.stick.right.left")
    public static let rightStickRight = Self(rawValue: "controller.stick.right.right")

    public static let legacyButtons: [Self] = [
        .buttonA, .buttonB, .buttonX, .buttonY,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
    ]

    public static let allControllerInputs: [Self] = legacyButtons + [
        .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
        .leftThumbstickButton, .rightThumbstickButton, .menu, .options,
        .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
        .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
    ]
}

public struct ReviewActionID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let off = Self(rawValue: "review.off")
    public static let showAnswer = Self(rawValue: "review.show_answer")
    public static let showAnswerOrGood = Self(rawValue: "review.show_answer_or_good")
    public static let again = Self(rawValue: "review.answer.again")
    public static let hard = Self(rawValue: "review.answer.hard")
    public static let good = Self(rawValue: "review.answer.good")
    public static let easy = Self(rawValue: "review.answer.easy")
    public static let undo = Self(rawValue: "review.undo")
    public static let sync = Self(rawValue: "review.sync")
    public static let replayOrStopAudio = Self(rawValue: "review.audio.replay_or_stop")
    public static let scrollUp = Self(rawValue: "review.scroll.up")
    public static let scrollDown = Self(rawValue: "review.scroll.down")
    public static let userAction1 = Self(rawValue: "review.user_action.1")
    public static let userAction2 = Self(rawValue: "review.user_action.2")
    public static let userAction3 = Self(rawValue: "review.user_action.3")
    public static let userAction4 = Self(rawValue: "review.user_action.4")
    public static let userAction5 = Self(rawValue: "review.user_action.5")
    public static let userAction6 = Self(rawValue: "review.user_action.6")
    public static let userAction7 = Self(rawValue: "review.user_action.7")
    public static let userAction8 = Self(rawValue: "review.user_action.8")

    public static let userActions: [Self] = [
        .userAction1, .userAction2, .userAction3, .userAction4,
        .userAction5, .userAction6, .userAction7, .userAction8,
    ]

    public var userActionNumber: Int? {
        Self.userActions.firstIndex(of: self).map { $0 + 1 }
    }
}

public enum ReviewCardSide: String, Codable, CaseIterable, Sendable {
    case question
    case answer
}

public struct ReviewInputApplicability: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let question = Self(rawValue: "question")
    public static let answer = Self(rawValue: "answer")
    public static let both = Self(rawValue: "both")

    public func applies(to side: ReviewCardSide) -> Bool {
        self == .both || rawValue == side.rawValue
    }
}

public struct ReviewInputBinding: Codable, Equatable, Sendable {
    public var input: ReviewInputID
    public var action: ReviewActionID
    public var applicability: ReviewInputApplicability

    public init(
        input: ReviewInputID,
        action: ReviewActionID,
        applicability: ReviewInputApplicability
    ) {
        self.input = input
        self.action = action
        self.applicability = applicability
    }
}
