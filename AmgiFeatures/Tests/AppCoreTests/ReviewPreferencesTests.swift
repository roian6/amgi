import Testing
@testable import AppCore

@Suite struct ReviewPreferencesTests {
    @Test func audioPoliciesUseCurrentAnkiStyleDefaults() {
        #expect(ReviewAutoplayPolicy.defaultValue == .enabled)
        #expect(ReviewAnswerAudioPolicy.defaultValue == .questionAndAnswer)
        #expect(ReviewAutoplayPolicy.resolved("future") == .enabled)
        #expect(ReviewAnswerAudioPolicy.resolved("future") == .questionAndAnswer)
    }

    @Test func zoomPolicyClampsAndStepsPersistableValues() {
        #expect(ReviewZoomPolicy.clamped(0.1) == ReviewZoomPolicy.minimumScale)
        #expect(ReviewZoomPolicy.clamped(9) == ReviewZoomPolicy.maximumScale)
        #expect(ReviewZoomPolicy.increased(from: 1) == 1.1)
        #expect(ReviewZoomPolicy.decreased(from: 1) == 0.9)
        #expect(ReviewZoomPolicy.reset() == ReviewZoomPolicy.defaultScale)
    }

    @Test func answerZoomDefaultsToKeepingTheQuestionZoom() {
        #expect(ReviewAnswerZoomPolicy.defaultValue == .keep)
        #expect(ReviewAnswerZoomPolicy.resolved("future") == .keep)
        #expect(ReviewAnswerZoomPolicy.reset.shouldResetOnAnswer)
        #expect(!ReviewAnswerZoomPolicy.keep.shouldResetOnAnswer)
    }

    @Test func newReviewPreferenceKeysAreStableAndIndependentFromSilentMode() {
        #expect(ReviewPreferences.Keys.audioAutoplay == "review_pref_audio_autoplay")
        #expect(ReviewPreferences.Keys.answerAudio == "review_pref_answer_audio")
        #expect(ReviewPreferences.Keys.zoomScale == "review_pref_zoom_scale")
        #expect(ReviewPreferences.Keys.answerZoom == "review_pref_answer_zoom")
        #expect(ReviewPreferences.Keys.audioAutoplay != ReviewPreferences.Keys.playAudioInSilentMode)
    }
}
