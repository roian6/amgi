import AppCore
import Testing
@testable import ReviewFeature

@MainActor
@Suite struct ReviewGamepadControlsTests {
    @Test func pressGateEmitsOneDownEdgePerPress() {
        var gate = ReviewGamepadPressGate()

        #expect(gate.update(.buttonA, isPressed: true) == .buttonA)
        #expect(gate.update(.buttonA, isPressed: true) == nil)
        #expect(gate.update(.buttonA, isPressed: false) == nil)
        #expect(gate.update(.buttonA, isPressed: false) == nil)
        #expect(gate.update(.buttonA, isPressed: true) == .buttonA)
    }

    @Test func everyRequestedControllerInputHasAStableIdentifier() {
        let expected: Set<ReviewInputID> = [
            .buttonA, .buttonB, .buttonX, .buttonY,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
            .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
            .leftThumbstickButton, .rightThumbstickButton, .menu, .options,
            .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
            .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
        ]

        #expect(Set(ReviewInputID.allControllerInputs) == expected)
        #expect(ReviewInputID.allControllerInputs.allSatisfy { $0.rawValue.hasPrefix("controller.") })
    }

    @Test func analogAxesApplyDeadZoneAndPreserveBoundedMagnitude() throws {
        var tracker = ReviewGamepadAxisTracker(deadZone: 0.35)

        #expect(tracker.update(.leftY, value: 0.34) == nil)
        #expect(tracker.update(.leftY, value: 0.36) == .leftStickUp)
        let low = try #require(tracker.samples().first)
        #expect(low.magnitude > 0 && low.magnitude < 0.1)

        #expect(tracker.update(.leftY, value: 0.8) == nil)
        let high = try #require(tracker.samples().first)
        #expect(high.magnitude > low.magnitude)
        #expect(high.magnitude <= 1)

        #expect(tracker.update(.leftY, value: 0) == nil)
        #expect(tracker.samples().isEmpty)
    }

    @Test func analogDirectionChangesEmitImmediately() {
        var tracker = ReviewGamepadAxisTracker()

        #expect(tracker.update(.rightX, value: 0.7) == .rightStickRight)
        #expect(tracker.update(.rightX, value: 0.9) == nil)
        #expect(tracker.update(.rightX, value: -0.7) == .rightStickLeft)
        #expect(tracker.update(.rightY, value: -0.7) == .rightStickDown)
    }

    @Test func separateControllersEachEmitTheSameButtonDownEdge() {
        let first = ReviewGamepadControllerToken()
        let second = ReviewGamepadControllerToken()
        var state = ReviewGamepadInputState()

        #expect(state.updateButton(
            controllerID: ObjectIdentifier(first),
            input: .buttonA,
            isPressed: true
        ) == .buttonA)
        #expect(state.updateButton(
            controllerID: ObjectIdentifier(second),
            input: .buttonA,
            isPressed: true
        ) == .buttonA)
        #expect(state.updateButton(
            controllerID: ObjectIdentifier(first),
            input: .buttonA,
            isPressed: true
        ) == nil)
    }

    @Test func removingOneControllerStopsOnlyItsContinuousAxisSamples() {
        let first = ReviewGamepadControllerToken()
        let second = ReviewGamepadControllerToken()
        let firstID = ObjectIdentifier(first)
        let secondID = ObjectIdentifier(second)
        var state = ReviewGamepadInputState()

        #expect(state.updateAxis(
            controllerID: firstID,
            axis: .leftY,
            value: 0.8,
            at: 0
        ) == .leftStickUp)
        #expect(state.updateAxis(
            controllerID: secondID,
            axis: .rightY,
            value: -0.8,
            at: 0
        ) == .rightStickDown)

        state.removeController(secondID)

        #expect(state.axisSamples().map(\.input) == [.leftStickUp])
    }

    @Test func clearingControllerStateResetsEveryPressAndHeldAxis() {
        let controller = ReviewGamepadControllerToken()
        let controllerID = ObjectIdentifier(controller)
        var state = ReviewGamepadInputState()

        #expect(state.updateButton(
            controllerID: controllerID,
            input: .buttonA,
            isPressed: true
        ) == .buttonA)
        #expect(state.updateAxis(
            controllerID: controllerID,
            axis: .leftY,
            value: 0.8,
            at: 0
        ) == .leftStickUp)

        state.removeAllControllers()

        #expect(state.axisSamples().isEmpty)
        #expect(state.updateButton(
            controllerID: controllerID,
            input: .buttonA,
            isPressed: true
        ) == .buttonA)
    }

    @Test func heldAxisEmitsOneSemanticEdgeButKeepsContinuousSamples() {
        let controller = ReviewGamepadControllerToken()
        let controllerID = ObjectIdentifier(controller)
        var state = ReviewGamepadInputState()

        #expect(state.updateAxis(
            controllerID: controllerID,
            axis: .leftY,
            value: 0.75,
            at: 0
        ) == .leftStickUp)
        #expect(state.updateAxis(
            controllerID: controllerID,
            axis: .leftY,
            value: 0.9,
            at: 1
        ) == nil)
        #expect(state.axisSamples().count == 1)
    }

    @Test func hiddenRatingButtonsReturnWhenGamepadDisconnects() {
        #expect(!showsRatingButtons(
            isGamepadConnected: true,
            hasRatingAction: true,
            isVoiceOverEnabled: false
        ))
        #expect(showsRatingButtons(
            isGamepadConnected: false,
            hasRatingAction: true,
            isVoiceOverEnabled: false
        ))
        #expect(showsRatingButtons(
            isGamepadConnected: true,
            hasRatingAction: true,
            isVoiceOverEnabled: true
        ))
        #expect(showsRatingButtons(
            isGamepadConnected: true,
            hasRatingAction: false,
            isVoiceOverEnabled: false
        ))
    }

    @Test func bottomSpacerIsRemovedOnlyWhenEveryBottomControlIsHidden() {
        #expect(
            !ReviewTapPolicy.needsBottomControlSpacer(
                isShowingAnswer: true,
                showsRatingButtons: false,
                isTypedAnswerCard: false
            )
        )
        #expect(
            ReviewTapPolicy.needsBottomControlSpacer(
                isShowingAnswer: false,
                showsRatingButtons: false,
                isTypedAnswerCard: false
            )
        )
        #expect(
            ReviewTapPolicy.needsBottomControlSpacer(
                isShowingAnswer: true,
                showsRatingButtons: true,
                isTypedAnswerCard: false
            )
        )
        #expect(
            ReviewTapPolicy.needsBottomControlSpacer(
                isShowingAnswer: true,
                showsRatingButtons: false,
                isTypedAnswerCard: true
            )
        )
    }

    private func showsRatingButtons(
        isGamepadConnected: Bool,
        hasRatingAction: Bool,
        isVoiceOverEnabled: Bool
    ) -> Bool {
        ReviewTapPolicy.showsRatingButtons(
            isShowingAnswer: true,
            preferenceEnabled: false,
            tapControlsEnabled: false,
            gamepadControlsEnabled: true,
            isGamepadConnected: isGamepadConnected,
            gamepadHasRatingAction: hasRatingAction,
            isTypedAnswerCard: false,
            isVoiceOverEnabled: isVoiceOverEnabled
        )
    }
}

private final class ReviewGamepadControllerToken {}
