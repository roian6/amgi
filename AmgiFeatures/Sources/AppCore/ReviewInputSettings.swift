import Foundation

public struct ReviewInputPresetID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let legacyAmgi = Self(rawValue: "amgi.legacy")
    public static let ankiMobile = Self(rawValue: "anki_mobile")
    public static let custom = Self(rawValue: "custom")
}

public struct ReviewInputSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var presetID: ReviewInputPresetID
    public var bindings: [ReviewInputBinding]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        presetID: ReviewInputPresetID,
        bindings: [ReviewInputBinding]
    ) {
        self.schemaVersion = schemaVersion
        self.presetID = presetID
        self.bindings = bindings
    }

    public func action(for input: ReviewInputID, side: ReviewCardSide) -> ReviewActionID {
        bindings.last { binding in
            binding.input == input && binding.applicability.applies(to: side)
        }?.action ?? .off
    }

    public mutating func setAction(
        _ action: ReviewActionID,
        for input: ReviewInputID,
        side: ReviewCardSide
    ) {
        let otherSide: ReviewCardSide = side == .question ? .answer : .question
        let otherAction = self.action(for: input, side: otherSide)
        bindings.removeAll { $0.input == input }

        if action == otherAction {
            append(action, for: input, applicability: .both)
        } else {
            let questionAction = side == .question ? action : otherAction
            let answerAction = side == .answer ? action : otherAction
            append(questionAction, for: input, applicability: .question)
            append(answerAction, for: input, applicability: .answer)
        }
        presetID = .custom
    }

    public static let legacyAmgi = ReviewInputSettings(
        presetID: .legacyAmgi,
        bindings: legacyBindings
    )

    public static let ankiMobile = ReviewInputSettings(
        presetID: .ankiMobile,
        bindings: [
            ReviewInputBinding(input: .buttonA, action: .showAnswerOrGood, applicability: .both),
            ReviewInputBinding(input: .buttonB, action: .again, applicability: .answer),
            ReviewInputBinding(input: .buttonX, action: .easy, applicability: .answer),
            ReviewInputBinding(input: .buttonY, action: .hard, applicability: .answer),
        ] + scrollBindings
    )

    private mutating func append(
        _ action: ReviewActionID,
        for input: ReviewInputID,
        applicability: ReviewInputApplicability
    ) {
        guard action != .off else { return }
        bindings.append(ReviewInputBinding(input: input, action: action, applicability: applicability))
    }

    private static let legacyBindings: [ReviewInputBinding] = {
        var result = ReviewInputID.legacyButtons.map {
            ReviewInputBinding(input: $0, action: .showAnswer, applicability: .question)
        }
        let answerActions: [(ReviewInputID, ReviewActionID)] = [
            (.buttonX, .again), (.dpadLeft, .again),
            (.buttonY, .hard), (.dpadUp, .hard),
            (.buttonA, .good), (.dpadDown, .good),
            (.buttonB, .easy), (.dpadRight, .easy),
        ]
        result += answerActions.map {
            ReviewInputBinding(input: $0.0, action: $0.1, applicability: .answer)
        }
        result += scrollBindings
        return result
    }()

    private static let scrollBindings: [ReviewInputBinding] = [
        ReviewInputBinding(input: .leftStickUp, action: .scrollUp, applicability: .both),
        ReviewInputBinding(input: .leftStickDown, action: .scrollDown, applicability: .both),
        ReviewInputBinding(input: .rightStickUp, action: .scrollUp, applicability: .both),
        ReviewInputBinding(input: .rightStickDown, action: .scrollDown, applicability: .both),
    ]
}

public enum ReviewInputSettingsCodec {
    public static func decode(_ rawValue: String) -> ReviewInputSettings {
        guard let data = rawValue.data(using: .utf8),
              let settings = try? JSONDecoder().decode(ReviewInputSettings.self, from: data) else {
            return .legacyAmgi
        }
        return settings
    }

    public static func encode(_ settings: ReviewInputSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        guard let rawValue = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                settings,
                EncodingError.Context(codingPath: [], debugDescription: "UTF-8 encoding failed")
            )
        }
        return rawValue
    }
}

public struct ReviewActionCatalogEntry: Identifiable, Sendable {
    public let action: ReviewActionID
    public let title: String
    public let unavailableReason: String?
    public let questionSupported: Bool
    public let answerSupported: Bool

    public var id: ReviewActionID { action }
    public var isAvailable: Bool { unavailableReason == nil }

    public func supports(_ side: ReviewCardSide) -> Bool {
        side == .question ? questionSupported : answerSupported
    }
}

public enum ReviewActionCatalog {
    public static let entries: [ReviewActionCatalogEntry] = [
        entry(.off, "Off"),
        entry(.showAnswer, "Show Answer", question: true, answer: false),
        entry(.showAnswerOrGood, "Show Answer / Good"),
        entry(.again, "Again", question: false, answer: true),
        entry(.hard, "Hard", question: false, answer: true),
        entry(.good, "Good", question: false, answer: true),
        entry(.easy, "Easy", question: false, answer: true),
        entry(.undo, "Undo"),
        entry(.sync, "Sync"),
        entry(.replayOrStopAudio, "Replay / Stop Audio"),
        entry(.scrollUp, "Scroll Up"),
        entry(.scrollDown, "Scroll Down"),
        entry(.userAction1, "User Action 1"),
        entry(.userAction2, "User Action 2"),
        entry(.userAction3, "User Action 3"),
        entry(.userAction4, "User Action 4"),
        entry(.userAction5, "User Action 5"),
        entry(.userAction6, "User Action 6"),
        entry(.userAction7, "User Action 7"),
        entry(.userAction8, "User Action 8"),
    ]

    public static func entry(for action: ReviewActionID) -> ReviewActionCatalogEntry? {
        entries.first { $0.action == action }
    }

    private static func entry(
        _ action: ReviewActionID,
        _ title: String,
        question: Bool = true,
        answer: Bool = true,
        unavailableReason: String? = nil
    ) -> ReviewActionCatalogEntry {
        ReviewActionCatalogEntry(
            action: action,
            title: title,
            unavailableReason: unavailableReason,
            questionSupported: question,
            answerSupported: answer
        )
    }
}
