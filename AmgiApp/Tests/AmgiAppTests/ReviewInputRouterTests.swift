import AppCore
import AnkiKit
import Testing
@testable import ReviewFeature

@MainActor
@Suite struct ReviewInputRouterTests {
    @Test func routerMapsStableActionsThroughCurrentCardSide() {
        let mappings: [(ReviewActionID, ReviewCardSide, ReviewSemanticAction?)] = [
            (.off, .question, nil),
            (.showAnswer, .question, .revealAnswer),
            (.showAnswer, .answer, nil),
            (.showAnswerOrGood, .question, .revealAnswer),
            (.showAnswerOrGood, .answer, .rate(.good)),
            (.again, .answer, .rate(.again)),
            (.hard, .answer, .rate(.hard)),
            (.good, .answer, .rate(.good)),
            (.easy, .answer, .rate(.easy)),
            (.undo, .question, .undo),
            (.replayOrStopAudio, .answer, .replayOrStopAudio),
            (.scrollUp, .question, .scroll(.up)),
            (.scrollDown, .answer, .scroll(.down)),
            (.sync, .question, .sync),
            (.userAction1, .answer, .userAction(1)),
        ]

        for (action, side, expected) in mappings {
            let settings = settings(with: action, side: side)
            #expect(
                ReviewInputRouter.action(
                    for: .buttonA,
                    settings: settings,
                    context: availableContext(side: side)
                ) == expected
            )
        }
    }

    @Test func syncRequiresTheInstalledAppEnvironmentSurface() {
        let settings = settings(with: .sync, side: .question)

        #expect(ReviewInputRouter.action(
            for: .buttonA,
            settings: settings,
            context: availableContext(side: .question, syncActionInstalled: false)
        ) == .syncUnavailable)
        #expect(ReviewInputRouter.action(
            for: .buttonA,
            settings: settings,
            context: availableContext(side: .question, syncActionInstalled: true)
        ) == .sync)
    }

    @Test func allTemplateUserActionsRouteOnlyForHTMLCards() {
        for (offset, action) in ReviewActionID.userActions.enumerated() {
            let settings = settings(with: action, side: .answer)
            #expect(ReviewInputRouter.action(
                for: .buttonA,
                settings: settings,
                context: availableContext(side: .answer, userActionsAvailable: true)
            ) == .userAction(offset + 1))
            #expect(ReviewInputRouter.action(
                for: .buttonA,
                settings: settings,
                context: availableContext(side: .answer, userActionsAvailable: false)
            ) == nil)
        }
    }

    @Test func syncAndTemplateActionsPreserveEveryBlockingReviewGate() {
        for action in [ReviewActionID.sync, .userAction1] {
            let settings = settings(with: action, side: .question)
            let unsafeContexts = [
                ReviewInputContext(
                    requiresTypedAnswerInput: true,
                    syncActionInstalled: true,
                    userActionsAvailable: true
                ),
                ReviewInputContext(
                    isAdvancing: true,
                    syncActionInstalled: true,
                    userActionsAvailable: true
                ),
                ReviewInputContext(
                    isAnswerTransitioning: true,
                    syncActionInstalled: true,
                    userActionsAvailable: true
                ),
                ReviewInputContext(
                    hasBlockingPresentation: true,
                    syncActionInstalled: true,
                    userActionsAvailable: true
                ),
                ReviewInputContext(
                    hasEditableWebFocus: true,
                    syncActionInstalled: true,
                    userActionsAvailable: true
                ),
            ]

            for context in unsafeContexts {
                #expect(ReviewInputRouter.action(
                    for: .buttonA,
                    settings: settings,
                    context: context
                ) == nil)
            }
        }
    }

    @Test func routerRejectsEveryUnsafeReviewState() {
        let settings = settings(with: .showAnswerOrGood, side: .question)
        let unsafeContexts = [
            ReviewInputContext(preferenceEnabled: false),
            ReviewInputContext(hasConnectedController: false),
            ReviewInputContext(shortcutsEnabled: false),
            ReviewInputContext(requiresTypedAnswerInput: true),
            ReviewInputContext(isAdvancing: true),
            ReviewInputContext(isAnswerTransitioning: true),
            ReviewInputContext(hasBlockingPresentation: true),
            ReviewInputContext(hasEditableWebFocus: true),
        ]

        for context in unsafeContexts {
            #expect(
                ReviewInputRouter.action(
                    for: .buttonA,
                    settings: settings,
                    context: context
                ) == nil
            )
        }
    }

    @Test func undoRequiresExistingUndoSurface() {
        let settings = settings(with: .undo, side: .question)

        #expect(
            ReviewInputRouter.action(
                for: .buttonA,
                settings: settings,
                context: availableContext(side: .question, canUndo: false)
            ) == nil
        )
        #expect(
            ReviewInputRouter.action(
                for: .buttonA,
                settings: settings,
                context: availableContext(side: .question, canUndo: true)
            ) == .undo
        )
    }

    @Test func reachabilityOnlyCountsUsableRevealAndRatingMappings() {
        var settings = ReviewInputSettings(
            presetID: .custom,
            bindings: [
                ReviewInputBinding(input: .buttonA, action: .sync, applicability: .question),
                ReviewInputBinding(input: .buttonB, action: .userAction1, applicability: .answer),
            ]
        )
        #expect(!ReviewInputReachability.hasRevealAction(in: settings))
        #expect(!ReviewInputReachability.hasRatingAction(in: settings))

        settings.setAction(.showAnswerOrGood, for: .buttonA, side: .question)
        settings.setAction(.easy, for: .buttonB, side: .answer)
        #expect(ReviewInputReachability.hasRevealAction(in: settings))
        #expect(ReviewInputReachability.hasRatingAction(in: settings))
    }

    @Test func reachabilityRequiresTheConnectedControllerToExposeTheAssignedInput() {
        let settings = ReviewInputSettings(
            presetID: .custom,
            bindings: [
                ReviewInputBinding(
                    input: .rightThumbstickButton,
                    action: .easy,
                    applicability: .answer
                ),
            ]
        )

        #expect(!ReviewInputReachability.hasRatingAction(
            in: settings,
            availableInputs: [.buttonA, .buttonB]
        ))
        #expect(ReviewInputReachability.hasRatingAction(
            in: settings,
            availableInputs: [.rightThumbstickButton]
        ))
    }

    @Test func scrollTargetsAreIncrementalAndClamped() {
        #expect(
            ReviewScrollPolicy.targetOffset(
                currentOffset: 200,
                minimumOffset: 0,
                maximumOffset: 600,
                direction: .down
            ) == 360
        )
        #expect(
            ReviewScrollPolicy.targetOffset(
                currentOffset: 40,
                minimumOffset: 0,
                maximumOffset: 600,
                direction: .up
            ) == 0
        )
        #expect(
            ReviewScrollPolicy.targetOffset(
                currentOffset: 560,
                minimumOffset: 0,
                maximumOffset: 600,
                direction: .down
            ) == 600
        )
    }

    @Test func continuousScrollUsesMagnitudeCurveBoundedVelocityAndFrameTime() {
        let low = ReviewScrollPolicy.continuousDelta(
            magnitude: 0.25,
            elapsed: 1.0 / 60.0,
            direction: .down
        )
        let high = ReviewScrollPolicy.continuousDelta(
            magnitude: 1,
            elapsed: 1.0 / 60.0,
            direction: .down
        )
        let stalled = ReviewScrollPolicy.continuousDelta(
            magnitude: 1,
            elapsed: 1,
            direction: .up
        )

        #expect(low > 0)
        #expect(high > low)
        #expect(high <= ReviewScrollPolicy.maximumVelocity / 60)
        #expect(
            abs(stalled + (ReviewScrollPolicy.maximumVelocity * ReviewScrollPolicy.maximumFrameDuration))
                < 0.001
        )
        #expect(ReviewScrollPolicy.clampedCombinedDelta(high * 2, elapsed: 1.0 / 60.0) == high)
    }

    @Test func continuousScrollTargetsClampWithoutChangingDiscreteStep() {
        #expect(ReviewScrollPolicy.targetOffset(
            currentOffset: 590,
            minimumOffset: 0,
            maximumOffset: 600,
            delta: 20
        ) == 600)
        #expect(ReviewScrollPolicy.targetOffset(
            currentOffset: 10,
            minimumOffset: 0,
            maximumOffset: 600,
            delta: -20
        ) == 0)
        #expect(ReviewScrollPolicy.step == 160)
    }

    @Test func regularWidthUsesABoundedCenteredReviewColumn() {
        #expect(ReviewLayoutPolicy.maximumContentWidth(isRegularWidth: false) == nil)
        #expect(ReviewLayoutPolicy.maximumContentWidth(isRegularWidth: true) == 860)
    }

    private func settings(
        with action: ReviewActionID,
        side: ReviewCardSide
    ) -> ReviewInputSettings {
        ReviewInputSettings(
            presetID: .custom,
            bindings: [
                ReviewInputBinding(
                    input: .buttonA,
                    action: action,
                    applicability: side == .question ? .question : .answer
                ),
            ]
        )
    }

    private func availableContext(
        side: ReviewCardSide,
        canUndo: Bool = true,
        syncActionInstalled: Bool = true,
        userActionsAvailable: Bool = true
    ) -> ReviewInputContext {
        ReviewInputContext(
            side: side,
            canUndo: canUndo,
            syncActionInstalled: syncActionInstalled,
            userActionsAvailable: userActionsAvailable
        )
    }
}
