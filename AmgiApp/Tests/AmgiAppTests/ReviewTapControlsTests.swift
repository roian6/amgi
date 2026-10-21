import AnkiKit
import Foundation
import SwiftUI
import Testing
import WebKit
import AmgiCardWeb
@testable import ReviewFeature

@MainActor
@Suite struct ReviewTapControlsTests {
    @Test func TTSMarkupRemainsAQueueItemWithoutAnInlineButton() {
        let expanded = CardWebView.expandTTSTags(
            in: "before [anki:tts lang=en_US voices=Samantha speed=1.25]hello[/anki:tts] after",
            isDarkMode: false,
            showReplayButtons: false
        )

        #expect(expanded.contains("class=\"anki-tts-audio\""))
        #expect(expanded.contains("data-tts-text=\"hello\""))
        #expect(!expanded.contains("replay-button"))
    }

    @Test func cardAssetFetchAllowsOnlyTheCardMainDocument() {
        let mediaURL = CardAssetPath.mediaBaseURL.appending(path: "_kanjilist.json")

        var customOrigin = URLRequest(url: mediaURL)
        customOrigin.mainDocumentURL = CardAssetPath.cardBaseURL
        customOrigin.setValue("amgi-asset://card", forHTTPHeaderField: "Origin")
        #expect(CardAssetScheme.accessControlAllowOrigin(for: customOrigin) == "amgi-asset://card")

        var opaqueOrigin = customOrigin
        opaqueOrigin.setValue("null", forHTTPHeaderField: "Origin")
        #expect(CardAssetScheme.accessControlAllowOrigin(for: opaqueOrigin) == "null")

        var externalOrigin = URLRequest(url: mediaURL)
        externalOrigin.mainDocumentURL = URL(string: "https://example.com/card")!
        externalOrigin.setValue("https://example.com", forHTTPHeaderField: "Origin")
        #expect(CardAssetScheme.accessControlAllowOrigin(for: externalOrigin) == nil)

        externalOrigin.setValue("amgi-asset://card", forHTTPHeaderField: "Origin")
        #expect(CardAssetScheme.accessControlAllowOrigin(for: externalOrigin) == nil)
    }

    @Test func cardDocumentFetchesBundledAssetThroughScopedCORS() async throws {
        let card = CardWebView(html: "fixture")
        let coordinator = card.makeCoordinator()
        let webView = card.makeWebView(coordinator: coordinator)
        card.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)

        let result = try await webView.callAsyncJavaScript(
            """
            const response = await fetch(assetURL);
            const body = await response.text();
            return {
                status: response.status,
                hasMathJaxMarker: body.includes('MathJax'),
                bodyLength: body.length
            };
            """,
            arguments: ["assetURL": CardAssetPath.mathJaxConfigScriptURLString],
            contentWorld: .page
        ) as? [String: Any]
        #expect(result?["status"] as? Int == 200)
        #expect(result?["hasMathJaxMarker"] as? Bool == true)
        #expect((result?["bodyLength"] as? Int ?? 0) > 100)
    }

    @Test func audioCommandsWaitForTheirContentGenerationAndStaleCommandsAreDropped() {
        var queue = CardWebViewAudioCommandQueue()
        queue.beginContentUpdate(generation: 1, identity: "card-1-question")
        queue.enqueue(
            requestID: 1,
            command: .replay(.question),
            contentGeneration: 1,
            contentIdentity: "card-1-question"
        )

        queue.markContentReady(generation: 0)
        #expect(queue.takeReadyCommand() == nil)
        queue.markContentReady(generation: 1)
        #expect(queue.takeReadyCommand() == .replay(.question))
        #expect(queue.takeReadyCommand() == nil)

        queue.enqueue(
            requestID: 2,
            command: .replay(.question),
            contentGeneration: 1,
            contentIdentity: "card-1-question"
        )
        queue.beginContentUpdate(generation: 2, identity: "card-1-answer")
        queue.markContentReady(generation: 1)
        #expect(queue.takeReadyCommand() == nil)

        queue.enqueue(
            requestID: 1,
            command: .stop,
            contentGeneration: 2,
            contentIdentity: "card-1-answer"
        )
        queue.markContentReady(generation: 2)
        #expect(queue.takeReadyCommand() == .stop)
    }

    @Test func answerReplayPolicyMapsToTheExpectedBridgeMode() {
        #expect(CardWebViewReplayMode.answerPolicy(rawValue: "questionAndAnswer") == .answerWithQuestion)
        #expect(CardWebViewReplayMode.answerPolicy(rawValue: "answerOnly") == .answerOnly)
    }

    @Test(arguments: [false, true])
    func replayDuringAnswerUpdateWaitsForGenerationAndRejectsOldSide(staleTarget: Bool) async throws {
        // ReviewView owns this lifecycle in production. This focused WebView
        // fixture must install the same policy before the reply-handler can
        // authorize managed playback. Keep it active across parameterized
        // cases because Swift Testing may execute them concurrently.
        ReviewAudioSession.apply(playInSilent: false)

        let initial = CardWebView(html: "question", cardID: CardID(601), autoplayEnabled: false)
        let coordinator = initial.makeCoordinator()
        let webView = initial.makeWebView(coordinator: coordinator)
        initial.updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil(timeout: .seconds(10)) {
            (try? await webView.evaluateJavaScript("window.__amgiContentGeneration") as? Int) == 1
        })
        try await webView.evaluateJavaScript("""
            window.__played = [];
            window.__replays = [];
            const originalReplay = window.amgiReplayAll;
            window.amgiReplayAll = function(mode, generation) {
                window.__replays.push([mode, generation]);
                return originalReplay(mode, generation);
            };
            HTMLMediaElement.prototype.play = function() {
                window.__played.push(this.getAttribute('src'));
                return Promise.resolve();
            };
            const originalSetInnerHTML = amgiSetInnerHTML;
            amgiSetInnerHTML = (element, html) => originalSetInnerHTML(
                element, html.replaceAll('preload="auto"', 'preload="none"')
            );
            amgiPreloadResources = () => new Promise(resolve => { window.__releasePreload = resolve; });
            true;
            """)
        let answer = CardWebView(
            html: "<audio id='template-audio' controls></audio><video controls></video>[sound:answer.mp3]",
            cardID: CardID(601),
            autoplayEnabled: false,
            isAnswerSide: true,
            replayRequestID: 1,
            replayCardID: CardID(601),
            replayIsAnswerSide: !staleTarget,
            replayMode: .answerOnly
        )
        answer.updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("typeof window.__releasePreload === 'function'") as? Bool) == true
        })
        #expect((try await webView.evaluateJavaScript("window.__replays.length") as? Int) == 0)
        try await webView.evaluateJavaScript("window.__releasePreload(); true;")
        #expect(try await waitUntil(timeout: .seconds(10)) {
            (try? await webView.evaluateJavaScript("window.__amgiContentGeneration") as? Int) == 2
        })
        if !staleTarget {
            #expect(try await waitUntil {
                (try? await webView.evaluateJavaScript("window.__played.length") as? Int) == 1
            })
            #expect((try await webView.evaluateJavaScript("window.__played[0].endsWith('/answer.mp3')") as? Bool) == true)
            #expect((try await webView.evaluateJavaScript("window.__replays[0][1]") as? Int) == 2)
        }
        answer.updateWebView(webView, coordinator: coordinator)
        try await Task.sleep(for: .milliseconds(100))
        #expect((try await webView.evaluateJavaScript("window.__replays.length") as? Int) == (staleTarget ? 0 : 1))
    }

    @Test func regularWidthBoundsInnerContentWithoutChangingGenerationOnResize() async throws {
        let card = CardWebView(
            html: "<div id='content'>Readable content</div>",
            cardCSS: ".card { background: rgb(12, 34, 56); text-align: left; }",
            maximumContentWidth: 860
        )
        let coordinator = card.makeCoordinator()
        let webView = card.makeWebView(coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        card.updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil(timeout: .seconds(10)) {
            (try? await webView.evaluateJavaScript("window.__amgiContentGeneration") as? Int) == 1
        })
        #expect((try await webView.evaluateJavaScript("document.body.getBoundingClientRect().width") as? Double) == 1200)
        #expect((try await webView.evaluateJavaScript("document.getElementById('qa').getBoundingClientRect().width") as? Double) == 860)
        #expect((try await webView.evaluateJavaScript("document.getElementById('qa').getBoundingClientRect().x") as? Double) == 170)
        #expect((try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('content')).textAlign") as? String) == "left")
        #expect((try await webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String) == "rgb(12, 34, 56)")
        CardWebView(html: card.html, cardCSS: card.cardCSS).updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("getComputedStyle(document.getElementById('qa')).maxWidth") as? String) == "none"
        })
        #expect(coordinator.contentGeneration == 1)
        #expect((try await webView.evaluateJavaScript("document.getElementById('qa').getBoundingClientRect().width") as? Double) == 1160)
    }

    @Test func WebViewZoomClampsWithoutChangingCardMarkupOrTapBridge() async throws {
        let card = CardWebView(
            html: "<a id=\"link\" href=\"https://example.com\">link</a><input id=\"typed\">",
            cardID: CardID(91),
            zoomScale: 9,
            tapControlsEnabled: true
        )
        let coordinator = card.makeCoordinator()
        let webView = card.makeWebView(coordinator: coordinator)

        card.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)

        #expect(webView.pageZoom == 2.0)
        #expect(try await webView.evaluateJavaScript("document.getElementById('link') !== null") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("document.getElementById('typed') !== null") as? Bool == true)
    }

    @Test func tapPolicyMapsQuestionTapToReveal() {
        #expect(
            ReviewTapPolicy.action(
                isEnabled: true,
                isShowingAnswer: false,
                isAdvancing: false,
                horizontalFraction: 0.25
            ) == .revealAnswer
        )
    }

    @Test func tapPolicyMapsAnswerHalvesToAgainAndGood() {
        #expect(
            ReviewTapPolicy.action(
                isEnabled: true,
                isShowingAnswer: true,
                isAdvancing: false,
                horizontalFraction: 0.49
            ) == .rate(.again)
        )
        #expect(
            ReviewTapPolicy.action(
                isEnabled: true,
                isShowingAnswer: true,
                isAdvancing: false,
                horizontalFraction: 0.5
            ) == .rate(.good)
        )
    }

    @Test func tapPolicyIgnoresDisabledAndAdvancingStates() {
        #expect(
            ReviewTapPolicy.action(
                isEnabled: false,
                isShowingAnswer: false,
                isAdvancing: false,
                horizontalFraction: 0.25
            ) == nil
        )
        #expect(
            ReviewTapPolicy.action(
                isEnabled: true,
                isShowingAnswer: true,
                isAdvancing: true,
                horizontalFraction: 0.75
            ) == nil
        )
    }

    @Test func typedAnswerCardsDisableTapControls() {
        #expect(
            ReviewTapPolicy.tapControlsAvailable(
                preferenceEnabled: true,
                isTypedAnswerCard: false,
                isVoiceOverEnabled: false
            )
        )
        #expect(
            !ReviewTapPolicy.tapControlsAvailable(
                preferenceEnabled: true,
                isTypedAnswerCard: true,
                isVoiceOverEnabled: false
            )
        )
        #expect(
            !ReviewTapPolicy.tapControlsAvailable(
                preferenceEnabled: false,
                isTypedAnswerCard: false,
                isVoiceOverEnabled: false
            )
        )
        #expect(
            !ReviewTapPolicy.tapControlsAvailable(
                preferenceEnabled: true,
                isTypedAnswerCard: false,
                isVoiceOverEnabled: true
            )
        )
    }

    @Test func ratingButtonsHideOnlyWhenImmersiveControlsAreUsable() {
        for preferenceEnabled in [false, true] {
            for tapControlsEnabled in [false, true] {
                for isTypedAnswerCard in [false, true] {
                    for isVoiceOverEnabled in [false, true] {
                        let expected = preferenceEnabled
                            || !tapControlsEnabled
                            || isTypedAnswerCard
                            || isVoiceOverEnabled
                        #expect(
                            ReviewTapPolicy.showsRatingButtons(
                                isShowingAnswer: true,
                                preferenceEnabled: preferenceEnabled,
                                tapControlsEnabled: tapControlsEnabled,
                                isTypedAnswerCard: isTypedAnswerCard,
                                isVoiceOverEnabled: isVoiceOverEnabled
                            ) == expected
                        )
                        #expect(
                            !ReviewTapPolicy.showsRatingButtons(
                                isShowingAnswer: false,
                                preferenceEnabled: preferenceEnabled,
                                tapControlsEnabled: tapControlsEnabled,
                                isTypedAnswerCard: isTypedAnswerCard,
                                isVoiceOverEnabled: isVoiceOverEnabled
                            )
                        )
                    }
                }
            }
        }
    }

    @Test func HTMLBridgeFiltersInteractiveSelectionLookupAndDragTaps() async throws {
        var receivedFractions: [CGFloat] = []
        let cardView = CardWebView(
            html: "",
            tapControlsEnabled: true,
            onReviewTapRequested: { receivedFractions.append($0) }
        )
        let coordinator = cardView.makeCoordinator()
        let webView = cardView.makeWebView(coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.loadHTMLString(frameHTML, baseURL: nil)
        try await waitUntilLoaded(webView)

        let filteredResults = try #require(
            try await webView.evaluateJavaScript(
                """
                (() => {
                    window.__amgiCardState = {
                        tapControlsEnabled: true,
                        lookupPopupEnabled: false,
                        dictionaryScanLength: 16,
                        renderedAt: Date.now() - 1000
                    };
                    const host = document.getElementById('qa');
                    host.innerHTML = `
                        <div id="plain">plain text</div>
                        <a id="link" href="https://example.com">link</a>
                        <button id="button">button</button>
                        <input id="input">
                        <label id="label">label</label>
                        <div id="editable" contenteditable="true">editable</div>
                        <audio id="audio" controls></audio>
                        <video id="video" controls></video>
                    `;
                    const originalElementFromPoint = document.elementFromPoint.bind(document);
                    function payloadFor(id) {
                        document.elementFromPoint = () => document.getElementById(id);
                        return amgiReviewTapPayloadAt(80, 40);
                    }
                    window.__amgiCardState.tapControlsEnabled = false;
                    const result = {
                        disabled: payloadFor('plain') === null
                    };
                    window.__amgiCardState.tapControlsEnabled = true;
                    Object.assign(result, {
                        plain: payloadFor('plain') !== null,
                        link: payloadFor('link') === null,
                        button: payloadFor('button') === null,
                        input: payloadFor('input') === null,
                        label: payloadFor('label') === null,
                        editable: payloadFor('editable') === null,
                        audio: payloadFor('audio') === null,
                        video: payloadFor('video') === null
                    });

                    const selection = window.getSelection();
                    const range = document.createRange();
                    range.selectNodeContents(document.getElementById('plain'));
                    selection.removeAllRanges();
                    selection.addRange(range);
                    result.selection = payloadFor('plain') === null;
                    selection.removeAllRanges();

                    window.__amgiCardState.lookupPopupEnabled = true;
                    window.amgiLookup = { payloadAt: () => ({ text: 'plain' }) };
                    result.lookup = payloadFor('plain') === null;
                    window.__amgiCardState.lookupPopupEnabled = false;
                    window.amgiLookup = null;
                    document.elementFromPoint = originalElementFromPoint;
                    return result;
                })()
                """
            ) as? [String: Bool]
        )
        #expect(filteredResults.values.allSatisfy { $0 })

        try await webView.evaluateJavaScript(
            """
            (() => {
                const plain = document.getElementById('plain');
                document.elementFromPoint = () => plain;
                plain.dispatchEvent(new PointerEvent('pointerdown', {
                    bubbles: true, pointerId: 1, pointerType: 'touch', isPrimary: true,
                    clientX: 40, clientY: 40
                }));
                plain.dispatchEvent(new PointerEvent('pointermove', {
                    bubbles: true, pointerId: 1, pointerType: 'touch', isPrimary: true,
                    clientX: 90, clientY: 40
                }));
                plain.dispatchEvent(new PointerEvent('pointerup', {
                    bubbles: true, pointerId: 1, pointerType: 'touch', isPrimary: true,
                    clientX: 90, clientY: 40
                }));
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(50))
        #expect(receivedFractions.isEmpty)

        try await webView.evaluateJavaScript(
            """
            (() => {
                const plain = document.getElementById('plain');
                plain.dispatchEvent(new PointerEvent('pointerdown', {
                    bubbles: true, pointerId: 2, pointerType: 'touch', isPrimary: true,
                    clientX: 240, clientY: 40
                }));
                plain.dispatchEvent(new PointerEvent('pointerup', {
                    bubbles: true, pointerId: 2, pointerType: 'touch', isPrimary: true,
                    clientX: 240, clientY: 40
                }));
            })()
            """
        )
        #expect(try await waitUntil { receivedFractions.count == 1 })
        #expect(abs(try #require(receivedFractions.first) - 0.75) < 0.001)
    }

    @Test func HTMLBridgeRejectsTapsThatBeginOnInteractiveContent() async throws {
        var receivedFractions: [CGFloat] = []
        let cardView = CardWebView(
            html: "",
            tapControlsEnabled: true,
            onReviewTapRequested: { receivedFractions.append($0) }
        )
        let coordinator = cardView.makeCoordinator()
        let webView = cardView.makeWebView(coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.loadHTMLString(frameHTML, baseURL: nil)
        try await waitUntilLoaded(webView)

        try await webView.evaluateJavaScript(
            """
            (() => {
                window.__amgiCardState = {
                    tapControlsEnabled: true,
                    lookupPopupEnabled: false,
                    dictionaryScanLength: 16,
                    renderedAt: Date.now() - 1000
                };
                const host = document.getElementById('qa');
                host.innerHTML = `
                    <div id="plain">plain text</div>
                    <a id="link" href="https://example.com">link</a>
                    <input id="input">
                    <audio id="audio" controls></audio>
                `;
                const plain = document.getElementById('plain');
                const origins = ['link', 'input', 'audio'];
                origins.forEach((id, index) => {
                    const origin = document.getElementById(id);
                    document.elementFromPoint = x => x < 85 ? origin : plain;
                    origin.dispatchEvent(new PointerEvent('pointerdown', {
                        bubbles: true, pointerId: index + 20, pointerType: 'touch', isPrimary: true,
                        clientX: 80, clientY: 40
                    }));
                    plain.dispatchEvent(new PointerEvent('pointerup', {
                        bubbles: true, pointerId: index + 20, pointerType: 'touch', isPrimary: true,
                        clientX: 89, clientY: 40
                    }));
                });
                document.elementFromPoint = () => plain;
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(100))

        #expect(
            receivedFractions.isEmpty,
            "Interactive pointerdown origins emitted \(receivedFractions.count) review taps"
        )
    }

    @Test func secondTapDuringAnswerTransitionDoesNotBecomeRating() async throws {
        var isShowingAnswer = false
        var isTransitioning = false
        var actions: [ReviewTapAction] = []
        let cardView = CardWebView(
            html: "",
            tapControlsEnabled: true,
            onReviewTapRequested: { horizontalFraction in
                guard let action = ReviewTapPolicy.action(
                    isEnabled: true,
                    isShowingAnswer: isShowingAnswer,
                    isAdvancing: isTransitioning,
                    horizontalFraction: horizontalFraction
                ) else { return }
                actions.append(action)
                if action == .revealAnswer {
                    isShowingAnswer = true
                    isTransitioning = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        isTransitioning = false
                    }
                }
            }
        )
        let coordinator = cardView.makeCoordinator()
        let webView = cardView.makeWebView(coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.loadHTMLString(frameHTML, baseURL: nil)
        try await waitUntilLoaded(webView)

        try await webView.evaluateJavaScript(
            """
            window.__amgiCardState = {
                tapControlsEnabled: true,
                lookupPopupEnabled: false,
                dictionaryScanLength: 16,
                renderedAt: Date.now() - 1000
            };
            document.getElementById('qa').innerHTML = '<div id="plain">plain text</div>';
            document.elementFromPoint = () => document.getElementById('plain');
            true;
            """
        )

        try await dispatchTap(in: webView, pointerID: 10, x: 80)
        try #require(try await waitUntil { actions == [.revealAnswer] })
        try await Task.sleep(for: .milliseconds(20))
        try await dispatchTap(in: webView, pointerID: 11, x: 240)
        try await Task.sleep(for: .milliseconds(350))

        #expect(
            actions == [.revealAnswer],
            "A transition-time question tap must not become a later rating; got \(actions)"
        )
    }

    @Test func HTMLBridgeReportsEditableFocusForExternalInputGating() async throws {
        var focusStates: [Bool] = []
        let cardView = CardWebView(
            html: "",
            onEditableFocusChange: { focusStates.append($0) }
        )
        let coordinator = cardView.makeCoordinator()
        let webView = cardView.makeWebView(coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        webView.loadHTMLString(frameHTML, baseURL: nil)
        try await waitUntilLoaded(webView)

        try await webView.evaluateJavaScript(
            """
            (() => {
                const host = document.getElementById('qa');
                host.innerHTML = '<input id="editable"><div id="plain" tabindex="0">plain</div>';
                document.getElementById('editable').focus();
            })()
            """
        )
        #expect(try await waitUntil { focusStates.last == true })

        try await webView.evaluateJavaScript("document.getElementById('plain').focus();")
        #expect(try await waitUntil { focusStates.last == false })
    }

    @Test func templateUserActionScriptUsesOnlyFixedValidatedFunctionNames() throws {
        for index in 1...8 {
            let script = try #require(CardWebView.userActionScript(index: index))
            #expect(script.contains("window.userJs\(index)"))
            #expect(!script.contains("eval("))
        }
        #expect(CardWebView.userActionScript(index: 0) == nil)
        #expect(CardWebView.userActionScript(index: 9) == nil)
    }

    @Test func templateUserActionRequestsRepeatAndMissingFunctionsNoOp() async throws {
        let initial = CardWebView(
            html: "<script>window.__userActionCount = 0; window.userJs1 = () => { window.__userActionCount += 1; };</script>",
            cardID: CardID(101),
            userActionRequestID: 0,
            userActionIndex: nil
        )
        let coordinator = initial.makeCoordinator()
        let webView = initial.makeWebView(coordinator: coordinator)
        initial.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 0
        })

        CardWebView(
            html: initial.html,
            cardID: CardID(101),
            userActionRequestID: 1,
            userActionIndex: 1,
            userActionCardID: CardID(101),
            userActionIsAnswerSide: false
        ).updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 1
        })

        CardWebView(
            html: initial.html,
            cardID: CardID(101),
            userActionRequestID: 2,
            userActionIndex: 1,
            userActionCardID: CardID(101),
            userActionIsAnswerSide: false
        ).updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 2
        })

        CardWebView(
            html: initial.html,
            cardID: CardID(101),
            userActionRequestID: 3,
            userActionIndex: 8,
            userActionCardID: CardID(101),
            userActionIsAnswerSide: false
        ).updateWebView(webView, coordinator: coordinator)
        try await Task.sleep(for: .milliseconds(50))
        #expect((try await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 2)
    }

    @Test func templateUserActionRequestDoesNotLeakOntoTheNextCard() async throws {
        let first = CardWebView(
            html: "<script>window.__userActionCount = 0; window.userJs1 = () => { window.__userActionCount += 1; };</script>",
            cardID: CardID(201),
            userActionRequestID: 7,
            userActionIndex: 1,
            userActionCardID: CardID(201),
            userActionIsAnswerSide: false
        )
        let coordinator = first.makeCoordinator()
        let webView = first.makeWebView(coordinator: coordinator)
        first.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)

        let next = CardWebView(
            html: first.html,
            cardID: CardID(202),
            userActionRequestID: 7,
            userActionIndex: 1,
            userActionCardID: CardID(201),
            userActionIsAnswerSide: false
        )
        let firstSignature = coordinator.lastContentSignature
        next.updateWebView(webView, coordinator: coordinator)
        #expect(coordinator.lastContentSignature != firstSignature)
        #expect(coordinator.lastUserActionRequestID == 7)
        try await Task.sleep(for: .milliseconds(100))
        #expect((try await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 0)
    }

    @Test func templateUserActionFunctionDoesNotPersistWhenTheNextCardOmitsIt() async throws {
        let first = CardWebView(
            html: "<script>window.__cardMarker = 'first'; window.__userActionCount = 0; window.userJs1 = () => { window.__userActionCount += 1; };</script>",
            cardID: CardID(301)
        )
        let coordinator = first.makeCoordinator()
        let webView = first.makeWebView(coordinator: coordinator)
        first.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__cardMarker") as? String) == "first"
        })

        CardWebView(
            html: "<script>window.__cardMarker = 'next'; window.__userActionCount = 0;</script>",
            cardID: CardID(302)
        ).updateWebView(webView, coordinator: coordinator)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__cardMarker") as? String) == "next"
        })

        CardWebView(
            html: "<script>window.__cardMarker = 'next'; window.__userActionCount = 0;</script>",
            cardID: CardID(302),
            userActionRequestID: 1,
            userActionIndex: 1,
            userActionCardID: CardID(302),
            userActionIsAnswerSide: false
        ).updateWebView(webView, coordinator: coordinator)
        try await Task.sleep(for: .milliseconds(50))
        #expect((try await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 0)
    }

    @Test func templateUserActionBeforeDidFinishRunsExactlyOnceWhenCardIsReady() async throws {
        let card = CardWebView(
            html: "<script>window.__userActionCount = 0; window.userJs1 = () => { window.__userActionCount += 1; };</script>",
            cardID: CardID(401),
            userActionRequestID: 1,
            userActionIndex: 1,
            userActionCardID: CardID(401),
            userActionIsAnswerSide: false
        )
        let coordinator = card.makeCoordinator()
        let webView = card.makeWebView(coordinator: coordinator)

        card.updateWebView(webView, coordinator: coordinator)
        card.updateWebView(webView, coordinator: coordinator)

        #expect(try await waitUntil(timeout: .seconds(10)) {
            (try? await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 1
        })
        try await Task.sleep(for: .milliseconds(100))
        #expect((try await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 1)
    }

    @Test func templateUserActionDuringDelayedCardUpdateWaitsAndRunsExactlyOnce() async throws {
        let initial = CardWebView(
            html: "<script>window.__userActionCount = 0;</script>",
            cardID: CardID(501)
        )
        let coordinator = initial.makeCoordinator()
        let webView = initial.makeWebView(coordinator: coordinator)
        initial.updateWebView(webView, coordinator: coordinator)
        try await waitUntilLoaded(webView)
        #expect(try await waitUntil {
            (try? await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 0
        })

        try await webView.evaluateJavaScript(
            "window.__originalPreload = amgiPreloadResources; "
                + "amgiPreloadResources = () => new Promise(resolve => setTimeout(resolve, 250)); true;"
        )
        let delayedHTML = """
            <script>
            amgiPreloadResources = window.__originalPreload;
            window.__delayedCardInstalled = true;
            window.__userActionCount = 0;
            window.userJs1 = () => { window.__userActionCount += 1; };
            </script>
            """
        CardWebView(
            html: delayedHTML,
            cardID: CardID(502)
        ).updateWebView(webView, coordinator: coordinator)
        CardWebView(
            html: delayedHTML,
            cardID: CardID(502),
            userActionRequestID: 1,
            userActionIndex: 1,
            userActionCardID: CardID(502),
            userActionIsAnswerSide: false
        ).updateWebView(webView, coordinator: coordinator)

        try await Task.sleep(for: .milliseconds(50))
        #expect((try await webView.evaluateJavaScript("window.__delayedCardInstalled") as? Bool) != true)
        #expect(try await waitUntil {
            let isInstalled = try? await webView.evaluateJavaScript(
                "window.__delayedCardInstalled"
            ) as? Bool
            let actionCount = try? await webView.evaluateJavaScript(
                "window.__userActionCount"
            ) as? Int
            return isInstalled == true && actionCount == 1
        })
        try await Task.sleep(for: .milliseconds(100))
        #expect((try await webView.evaluateJavaScript("window.__userActionCount") as? Int) == 1)
    }

    private var frameHTML: String {
        CardWebView.buildFrameHTML(
            htmlClass: "ios iphone mobile",
            isDarkMode: false,
            playIconHTML: "",
            pauseIconHTML: "",
            baseTag: ""
        )
    }

    private func waitUntilLoaded(_ webView: WKWebView) async throws {
        let loaded = try await waitUntil(timeout: .seconds(10)) {
            (try? await webView.evaluateJavaScript("document.getElementById('qa') !== null") as? Bool) == true
        }
        try #require(loaded)
    }

    private func dispatchTap(in webView: WKWebView, pointerID: Int, x: Int) async throws {
        try await webView.evaluateJavaScript(
            """
            (() => {
                const plain = document.getElementById('plain');
                plain.dispatchEvent(new PointerEvent('pointerdown', {
                    bubbles: true, pointerId: \(pointerID), pointerType: 'touch', isPrimary: true,
                    clientX: \(x), clientY: 40
                }));
                plain.dispatchEvent(new PointerEvent('pointerup', {
                    bubbles: true, pointerId: \(pointerID), pointerType: 'touch', isPrimary: true,
                    clientX: \(x), clientY: 40
                }));
            })()
            """
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () async -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}
