import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync("AmgiApp/Resources/Review/CardWebViewBridge.js", "utf8");
const audioStart = source.indexOf("function setAudioButtonState");
const audioEnd = source.indexOf("// ── pycmd", audioStart);
const updateStart = source.indexOf("async function amgiUpdateQA");
assert.ok(audioStart >= 0 && audioEnd > audioStart && updateStart > audioEnd);

function sound(src) {
    return {
        className: "anki-sound-audio", src, paused: true, currentTime: 0,
        nextElementSibling: { innerHTML: "" },
        getAttribute: name => name === "src" ? src : null,
        pause() { this.paused = true; },
    };
}
function tts(text) {
    return {
        className: "anki-tts-audio", innerHTML: "",
        dataset: { ttsText: text, ttsLang: "en_US", ttsVoices: "Samantha", ttsSpeed: "1.25" },
    };
}
function harness(media = []) {
    const events = [];
    const preparations = [];
    let deferPreparation = false;
    let items = [];
    let preload = Promise.resolve();
    const qa = { style: {} };
    const window = {
        __amgiAudioQueueToken: 0, __amgiNextTtsRequestID: 0,
        __amgiCardState: { contentGeneration: 0 }, __amgiContentGeneration: 0,
        scrollTo() {}, webkit: { messageHandlers: {} },
    };
    function record(type, value) {
        events.push({ type, value, generation: window.__amgiContentGeneration, opacity: qa.style.opacity });
    }
    for (const [name, type] of Object.entries({
        amgiAudioState: "audio", amgiSpeakTts: "tts", amgiStopTts: "stop", amgiCardReady: "ready",
    })) window.webkit.messageHandlers[name] = { postMessage: value => record(type, value) };
    window.webkit.messageHandlers.amgiPrepareAudio = {
        postMessage(value) {
            record("prepare", value);
            if (!deferPreparation) return Promise.resolve(true);
            return new Promise((resolve, reject) => preparations.push({ resolve, reject }));
        },
    };
    const player = {
        paused: true, currentTime: 0,
        removeAttribute() { this.src = ""; }, load() {},
        pause() { this.paused = true; },
        play() { this.paused = false; record("sound", this.src); return Promise.resolve(); },
    };
    const document = {
        getElementById: id => ({ qa, "amgi-audio-queue-player": player })[id] ?? null,
        querySelector: selector => document.querySelectorAll(selector)[0] ?? null,
        querySelectorAll(selector) {
            if (selector === ".anki-sound-audio, .anki-tts-audio") return items;
            if (selector === ".anki-sound-audio") return items.filter(item => item.className === "anki-sound-audio");
            if (selector.includes("audio:not(")) return media;
            return [];
        },
    };
    const context = vm.createContext({
        window, document, Array, Set, console,
        Node: { DOCUMENT_POSITION_FOLLOWING: 4 },
        PAUSE_ICON_HTML: "pause", PLAY_ICON_HTML: "play",
        amgiContentGenerationValue: () => window.__amgiCardState.contentGeneration,
        amgiReplayModeValue: () => window.__amgiCardState.replayMode,
        amgiAutoplayEnabled: () => window.__amgiCardState.autoplayEnabled,
        amgiPrefetchHTMLValue: () => "",
        amgiNormalizeMathJaxMarkup: html => html,
        amgiContainsMathJaxMarkup: () => false,
        amgiPreloadResources: () => preload,
        amgiApplyCardState: state => { window.__amgiCardState = state; },
        amgiSetInnerHTML: async (_, html) => {
            items = html;
            for (const item of items.filter(item => item.className === "anki-sound-audio")) {
                item.nextElementSibling.previousElementSibling = item;
                item.play = function() { this.paused = false; record("sound", this.src); return Promise.resolve(); };
            }
        },
        amgiRunHooks: async hooks => { for (const hook of hooks) await hook(); },
        amgiAllImagesLoaded: () => Promise.resolve(),
        amgiSetupImageOcclusion() {}, amgiScheduleCardThemeReport() {},
    });
    vm.runInContext(source.slice(audioStart, audioEnd), context);
    vm.runInContext(source.slice(audioEnd, source.indexOf("// ===== Link interceptor", audioEnd)), context);
    vm.runInContext(source.slice(updateStart, source.indexOf("</script>", updateStart)), context);
    return {
        context, window, player, events, preparations,
        deferPreparation() { deferPreparation = true; },
        settle: () => new Promise(resolve => setImmediate(resolve)),
        async show(answer, content, generation, mode, autoplay = true) {
            if (answer) context._showAnswer(content, "card", autoplay, mode, false, 16, 0, false, 16, false, generation);
            else context._showQuestion(content, "", "card", autoplay, mode, false, 16, 0, false, 16, false, generation);
            await window.__amgiUpdateQueue;
            await Promise.resolve();
        },
        delay() {
            let release;
            preload = new Promise(resolve => { release = resolve; });
            return release;
        },
        async drain() {
            for (let count = 0; window.__amgiAudioPlaying && count < 20; count++) {
                await this.settle();
                const pending = window.__amgiPendingTts;
                if (pending) context.amgiTtsDidFinish(pending.contentGeneration, pending.requestID);
                else player.onended();
            }
            assert.equal(window.__amgiAudioPlaying, false, "queue drains");
        },
    };
}
function templateMedia(tag, state = {}) {
    return Object.freeze({ tagName: tag.toUpperCase(), paused: true, ended: false, autoplay: false,
        currentTime: 19, ...state,
        pause() { assert.fail("must not pause template media"); },
        load() { assert.fail("must not reload template media"); },
        removeAttribute() { assert.fail("must not mutate template media"); },
    });
}
const playback = h => h.events.filter(event => event.type === "sound" || event.type === "tts");
const labels = h => playback(h).map(event => event.type === "sound" ? event.value : event.value.text);

for (const tag of ["audio", "video"]) {
    for (const state of [{}, { paused: false, ended: true }]) {
        test(`question autoplay with nonplaying ${tag}: ${JSON.stringify(state)}`, async () => {
            const h = harness([templateMedia(tag, state)]);
            await h.show(false, [sound("q.mp3"), tts("question")], 1, "question");
            await h.drain();
            assert.deepEqual(labels(h), ["q.mp3", "question"]);
        });
    }
    for (const mode of ["answerWithQuestion", "answerOnly"]) {
        test(`answer transition with passive ${tag}: ${mode}, delayed generation`, async () => {
            const media = [];
            const h = harness(media);
            const question = [sound("question.mp3"), tts("question")];
            await h.show(false, question, 7, "question");
            await h.drain();
            assert.deepEqual(labels(h), ["question.mp3", "question"]);
            h.events.length = 0;
            media.push(templateMedia(tag));
            const release = h.delay();
            const shown = h.show(true, [...question, sound("answer.mp3"), tts("answer")], 8, mode);
            await Promise.resolve();
            assert.equal(playback(h).length, 0, "no playback while content is loading");
            assert.equal(h.events.some(event => event.type === "ready"), false);
            release();
            await shown;
            await h.drain();
            assert.deepEqual(labels(h), mode === "answerOnly"
                ? ["answer.mp3", "answer"] : ["question.mp3", "question", "answer.mp3", "answer"]);
            assert.ok(playback(h).every(event => event.generation === 8 && event.opacity === "1"),
                "automatic playback starts only after the new generation is installed and shown");
            assert.deepEqual(h.events.filter(event => event.type === "ready").map(event => event.value), [8]);
        });
    }
    for (const state of [{}, { paused: false }, { autoplay: true }]) {
        test(`mapped replay/stop owns only Amgi media: ${tag} ${JSON.stringify(state)}`, async () => {
            const media = templateMedia(tag, state);
            const h = harness([media]);
            await h.show(false, [sound("front.mp3"), tts("hello")], 7, "question", false);
            assert.equal(playback(h).length, 0, "autoplay preference is respected");
            h.context.amgiReplayAll("question", 7);
            await h.settle();
            assert.deepEqual(labels(h), ["front.mp3"], "mapped replay enqueues managed sound despite template media");
            h.player.onended();
            assert.deepEqual(labels(h), ["front.mp3", "hello"], "mapped replay continues into managed TTS");
            const pending = h.window.__amgiPendingTts;
            assert.deepEqual({ ...playback(h).at(-1).value }, {
                text: "hello", lang: "en_US", voices: "Samantha", speed: "1.25",
                contentGeneration: 7, requestID: pending.requestID,
            }, "TTS retains voice, language, speed and request identity");
            h.context.amgiTtsDidFinish(6, pending.requestID);
            h.context.amgiTtsDidFinish(7, pending.requestID + 1);
            assert.equal(h.window.__amgiAudioPlaying, true);
            h.window.amgiStopAllAudio(6);
            assert.equal(h.window.__amgiAudioPlaying, true, "stale stop rejected");
            h.window.amgiStopAllAudio(7);
            assert.equal(h.window.__amgiAudioPlaying, false);
            assert.deepEqual({ ...h.events.find(event => event.type === "stop").value },
                { contentGeneration: 7, requestID: pending.requestID });
            h.context.amgiTtsDidFinish(7, pending.requestID);
            h.context.amgiReplayAll("question", 6);
            assert.equal(playback(h).length, 2, "stale replay and stopped completion cannot restart playback");
            assert.equal(media.currentTime, 19);
        });
    }
    for (const state of [{ paused: false }, { autoplay: true }]) {
        test(`automatic collision suppression: ${tag} ${JSON.stringify(state)}`, async () => {
            const h = harness([templateMedia(tag, state)]);
            await h.show(false, [sound("q.mp3"), tts("question")], 1, "question");
            await h.show(true, [sound("a.mp3"), tts("answer")], 2, "answerOnly");
            assert.equal(playback(h).length, 0);
        });
    }
}
test("old sound callbacks and TTS completions cannot advance a new generation", async () => {
    const h = harness();
    await h.show(false, [sound("q.mp3"), tts("old")], 1, "question");
    const oldEnded = h.player.onended;
    await h.show(true, [tts("new"), sound("a.mp3")], 2, "answerOnly");
    const count = playback(h).length;
    oldEnded();
    h.context.amgiTtsDidFinish(1, 1);
    assert.equal(playback(h).length, count);
    assert.equal(h.window.__amgiAudioPlaying, true);
    await h.drain();
    assert.deepEqual(labels(h), ["q.mp3", "new", "a.mp3"]);
});

test("managed MP3 waits for native preparation before each item, then continues to TTS", async () => {
    const h = harness([templateMedia("audio")]);
    h.deferPreparation();
    await h.show(true, [sound("one.mp3"), sound("two.mp3"), tts("answer")], 8, "answerOnly");
    assert.deepEqual(labels(h), [], "managed sound must wait for the native preparation reply");
    assert.deepEqual(h.events.filter(e => e.type === "prepare").map(e => ({ ...e.value })),
        [{ contentGeneration: 8 }]);
    h.preparations[0].resolve(true);
    await h.settle();
    assert.deepEqual(labels(h), ["one.mp3"]);
    h.player.onended();
    await h.settle();
    assert.deepEqual(labels(h), ["one.mp3"], "each MP3 needs a fresh preparation");
    assert.equal(h.preparations.length, 2);
    h.preparations[1].resolve(true);
    await h.settle();
    assert.deepEqual(labels(h), ["one.mp3", "two.mp3"]);
    h.player.onended();
    assert.deepEqual(labels(h), ["one.mp3", "two.mp3", "answer"]);
    await h.drain();
});

for (const entry of ["mapped", "inline", "pycmd"]) {
    function replay(h, clip) {
        if (entry === "mapped") h.context.amgiReplayAll("question", 7);
        else if (entry === "inline") assert.equal(h.context.playSound(clip.nextElementSibling), false);
        else assert.equal(h.context.pycmd("play:q:0"), false);
    }
    test(`${entry} replay waits for preparation; Stop cancels a pending start`, async () => {
        const h = harness([templateMedia("video", { paused: false })]);
        const clip = sound("explicit.mp3");
        h.deferPreparation();
        await h.show(false, [clip], 7, "question", false);
        assert.equal(h.preparations.length, 0, "autoplay disabled does not prepare audio");
        replay(h, clip);
        assert.deepEqual(labels(h), [], "explicit playback waits for preparation too");
        assert.equal(h.preparations.length, 1);
        h.window.amgiStopAllAudio(7);
        h.preparations[0].resolve(true);
        await h.settle();
        assert.deepEqual(labels(h), [], "Stop must invalidate the pending reply");
        assert.equal(h.window.__amgiAudioPlaying, false);
        replay(h, clip);
        h.preparations[1].resolve(true);
        await h.settle();
        assert.deepEqual(labels(h), ["explicit.mp3"], "explicit replay still bypasses template collision");
    });

    for (const reply of ["denied", "rejected", "missing"]) {
        test(`${entry} replay fails closed on ${reply} preparation`, async () => {
            const h = harness();
            const clip = sound("blocked.mp3");
            h.deferPreparation();
            await h.show(false, [clip], 7, "question", false);
            if (reply === "missing") delete h.window.webkit.messageHandlers.amgiPrepareAudio;
            replay(h, clip);
            assert.deepEqual(labels(h), [], "no unprepared playback fallback");
            if (reply === "denied") h.preparations[0].resolve(false);
            if (reply === "rejected") h.preparations[0].reject(new Error("native preparation failed"));
            await h.settle();
            assert.deepEqual(labels(h), []);
            assert.equal(h.window.__amgiAudioPlaying, false);
            assert.equal(clip.nextElementSibling.innerHTML, "play");
        });
    }

    for (const change of ["card", "replay"]) {
        test(`${entry} stale preparation cannot start or clear ${change} playback`, async () => {
            const h = harness();
            const clip = sound("old.mp3");
            h.deferPreparation();
            await h.show(false, [clip], 7, "question", false);
            replay(h, clip);
            assert.deepEqual(labels(h), [], "old playback is still awaiting preparation");
            if (change === "card") await h.show(true, [sound("new.mp3")], 8, "answerOnly");
            else h.context.amgiReplayAll("question", 7);
            h.preparations[1].resolve(true);
            await h.settle();
            const expected = change === "card" ? ["new.mp3"] : ["old.mp3"];
            assert.deepEqual(labels(h), expected);
            h.preparations[0].resolve(true);
            await h.settle();
            assert.deepEqual(labels(h), expected, "late reply cannot play the superseded item");
            assert.equal(h.window.__amgiAudioPlaying, true);
        });
    }
}

test("inline replay toggles off while native preparation is pending", async () => {
    const h = harness();
    const clip = sound("toggle.mp3");
    h.deferPreparation();
    await h.show(false, [clip], 7, "question", false);
    h.context.playSound(clip.nextElementSibling);
    assert.deepEqual(labels(h), [], "first tap must wait");
    h.context.playSound(clip.nextElementSibling);
    h.preparations[0].resolve(true);
    await h.settle();
    assert.deepEqual(labels(h), [], "second tap cancels pending playback");
    assert.equal(h.window.__amgiAudioPlaying, false);
    assert.equal(h.preparations.length, 1);
});

test("native preparation contract: reply lifecycle, current mixed policy and immediate TTS preparation", () => {
    const web = readFileSync("AmgiFeatures/Sources/ReviewFeature/CardWebView.swift", "utf8");
    const coordinator = readFileSync("AmgiFeatures/Sources/ReviewFeature/CardWebViewCoordinator.swift", "utf8");
    const session = readFileSync("AmgiFeatures/Sources/ReviewFeature/ReviewAudioSession.swift", "utf8");
    assert.match(web, /addScriptMessageHandler\(coordinator, contentWorld: \.page, name: "amgiPrepareAudio"\)/);
    assert.match(web, /removeScriptMessageHandler\(forName: "amgiPrepareAudio", contentWorld: \.page\)/);
    assert.match(coordinator, /WKScriptMessageHandlerWithReply/);
    const reply = coordinator.slice(coordinator.indexOf("replyHandler:"), coordinator.indexOf("// MARK: - AVSpeechSynthesizerDelegate"));
    assert.match(reply, /generation == contentGeneration/);
    assert.match(reply, /message\.webView === currentWebView/);
    assert.match(reply, /message\.frameInfo\.isMainFrame/);
    assert.match(reply, /replyHandler\(ReviewAudioSession\.prepareForPlayback\(\), nil\)/);
    assert.match(coordinator, /guard ReviewAudioSession\.prepareForPlayback\(\) else \{\s*finishTTS\(ObjectIdentifier\(utterance\)\)\s*return\s*\}\s*speechSynthesizer\.speak\(utterance\)/);
    assert.match(session, /currentPlayInSilent = playInSilent/);
    assert.match(session, /guard let playInSilent = currentPlayInSilent else \{ return false \}/);
    assert.match(session, /playInSilent \? \.playback : \.ambient/);
    assert.match(session, /options: \[\.mixWithOthers\]/);
    assert.match(session, /func release\(\) \{\s*currentPlayInSilent = nil/);
});
