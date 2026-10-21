import Foundation
import Testing
@testable import AppCore

@Suite struct ReviewInputSettingsTests {
    @Test func stableIdentifiersRoundTripUnknownFutureValues() throws {
        let input = ReviewInputID(rawValue: "controller.future.paddle")
        let action = ReviewActionID(rawValue: "review.future.custom")

        let encodedInput = try JSONEncoder().encode(input)
        let encodedAction = try JSONEncoder().encode(action)

        #expect(try JSONDecoder().decode(ReviewInputID.self, from: encodedInput) == input)
        #expect(try JSONDecoder().decode(ReviewActionID.self, from: encodedAction) == action)
        #expect(ReviewInputID.buttonA.rawValue == "controller.button.a")
        #expect(ReviewActionID.showAnswerOrGood.rawValue == "review.show_answer_or_good")
        #expect(ReviewActionID.userAction1.rawValue == "review.user_action.1")
        #expect(ReviewActionID.userAction8.rawValue == "review.user_action.8")
    }

    @Test func settingsRoundTripPreservesFutureBindingsAndVersion() throws {
        let json = """
        {
          "schemaVersion": 7,
          "presetID": "future.preset",
          "futureTopLevel": true,
          "bindings": [
            {
              "input": "controller.future.paddle",
              "action": "review.future.custom",
              "applicability": "both"
            }
          ]
        }
        """

        let decoded = ReviewInputSettingsCodec.decode(json)
        #expect(decoded.schemaVersion == 7)
        #expect(decoded.presetID == ReviewInputPresetID(rawValue: "future.preset"))
        #expect(
            decoded.action(
                for: ReviewInputID(rawValue: "controller.future.paddle"),
                side: .question
            ) == ReviewActionID(rawValue: "review.future.custom")
        )

        let roundTripped = ReviewInputSettingsCodec.decode(try ReviewInputSettingsCodec.encode(decoded))
        #expect(roundTripped == decoded)
    }

    @Test func missingAndMalformedSettingsRetainLegacyAmgiMapping() {
        for rawValue in ["", "not json"] {
            let settings = ReviewInputSettingsCodec.decode(rawValue)

            for input in ReviewInputID.legacyButtons {
                #expect(settings.action(for: input, side: .question) == .showAnswer)
            }
            #expect(settings.action(for: .buttonX, side: .answer) == .again)
            #expect(settings.action(for: .dpadLeft, side: .answer) == .again)
            #expect(settings.action(for: .buttonY, side: .answer) == .hard)
            #expect(settings.action(for: .dpadUp, side: .answer) == .hard)
            #expect(settings.action(for: .buttonA, side: .answer) == .good)
            #expect(settings.action(for: .dpadDown, side: .answer) == .good)
            #expect(settings.action(for: .buttonB, side: .answer) == .easy)
            #expect(settings.action(for: .dpadRight, side: .answer) == .easy)
            #expect(settings.action(for: .leftStickUp, side: .question) == .scrollUp)
            #expect(settings.action(for: .rightStickDown, side: .answer) == .scrollDown)
            #expect(settings.action(for: .leftShoulder, side: .answer) == .off)
        }
    }

    @Test func ankiMobilePresetIsExplicitAndUsesDocumentedFaceButtons() {
        let legacy = ReviewInputSettings.legacyAmgi
        let preset = ReviewInputSettings.ankiMobile

        #expect(legacy.presetID == .legacyAmgi)
        #expect(preset.presetID == .ankiMobile)
        #expect(legacy.action(for: .buttonA, side: .question) == .showAnswer)
        #expect(preset.action(for: .buttonA, side: .question) == .showAnswerOrGood)
        #expect(preset.action(for: .buttonA, side: .answer) == .showAnswerOrGood)
        #expect(preset.action(for: .buttonB, side: .answer) == .again)
        #expect(preset.action(for: .buttonX, side: .answer) == .easy)
        #expect(preset.action(for: .buttonY, side: .answer) == .hard)
        #expect(preset.action(for: .buttonB, side: .question) == .off)
        #expect(preset.action(for: .dpadLeft, side: .answer) == .off)
    }

    @Test func lastApplicableAssignmentWinsAndEditingCanonicalizesSides() {
        var settings = ReviewInputSettings(
            schemaVersion: 1,
            presetID: .custom,
            bindings: [
                ReviewInputBinding(input: .buttonA, action: .showAnswer, applicability: .both),
                ReviewInputBinding(input: .buttonA, action: .again, applicability: .answer),
                ReviewInputBinding(input: .buttonA, action: .easy, applicability: .answer),
            ]
        )

        #expect(settings.action(for: .buttonA, side: .question) == .showAnswer)
        #expect(settings.action(for: .buttonA, side: .answer) == .easy)

        settings.setAction(.hard, for: .buttonA, side: .question)

        #expect(settings.presetID == .custom)
        #expect(settings.action(for: .buttonA, side: .question) == .hard)
        #expect(settings.action(for: .buttonA, side: .answer) == .easy)
        #expect(settings.bindings.filter { $0.input == .buttonA }.count <= 2)
    }

    @Test func catalogExposesSyncAndAllOfficialTemplateUserActions() throws {
        let undo = try #require(ReviewActionCatalog.entry(for: .undo))
        let audio = try #require(ReviewActionCatalog.entry(for: .replayOrStopAudio))
        let sync = try #require(ReviewActionCatalog.entry(for: .sync))

        #expect(undo.isAvailable)
        #expect(audio.isAvailable)
        #expect(sync.isAvailable)
        for (index, action) in ReviewActionID.userActions.enumerated() {
            let entry = try #require(ReviewActionCatalog.entry(for: action))
            #expect(entry.isAvailable)
            #expect(entry.title == "User Action \(index + 1)")
            #expect(entry.supports(.question))
            #expect(entry.supports(.answer))
        }
        #expect(ReviewActionCatalog.entry(for: ReviewActionID(rawValue: "future")) == nil)
    }

    @Test func presetsDoNotImplicitlyAssignSyncOrTemplateUserActions() {
        let actions: [ReviewActionID] = [.sync] + ReviewActionID.userActions

        for preset in [ReviewInputSettings.legacyAmgi, .ankiMobile] {
            for input in ReviewInputID.allControllerInputs {
                for side in ReviewCardSide.allCases {
                    #expect(!actions.contains(preset.action(for: input, side: side)))
                }
            }
        }
    }
}
