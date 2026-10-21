import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// Execute the production request-observation branch on Linux. This narrow
// syntax translation is not Swift compilation; the WebKit integration test
// exercises updateWebView itself on Apple platforms.
const source = readFileSync("AmgiFeatures/Sources/ReviewFeature/CardWebView.swift", "utf8");
const end = source.indexOf("        if scrollRequestID != coordinator.lastScrollRequestID");
const start = source.lastIndexOf("        if contentChanged {", end);
assert.ok(start >= 0 && end > start);
const branch = source.slice(start, end)
    .replace(/if ([^\n{]+) \{/g, "if ($1) {")
    .replace(/let (\w+) =/g, "const $1 =")
    .replace(/\.replay\(replayMode\)/g, '"replay:" + replayMode')
    .replace(/command: \.stop/g, 'command: "stop"')
    .replace(/coordinator\.observeAudioCommand\(([\s\S]*?)\n\s*\)/g,
        "coordinator.observeAudioCommand({$1\n})");
const script = new vm.Script(branch, { filename: "CardWebView.update-audio-branch.swift-as-js" });

function observe({ contentChanged, targetCard = 42, targetAnswer = true, currentAnswer = true }) {
    const commands = [];
    const coordinator = {
        lastReplayRequestID: 0, lastStopAudioRequestID: 0,
        observeAudioCommand(command) { commands.push(command); },
    };
    const state = vm.createContext({
        coordinator, contentChanged, replayRequestID: 1, stopAudioRequestID: 0,
        replayCardID: targetCard, replayIsAnswerSide: targetAnswer,
        cardID: 42, isAnswerSide: currentAnswer,
        replayMode: "answerOnly", renderIdentity: "card-42-answer-generation-8", webView: {},
    });
    script.runInContext(state);
    state.contentChanged = false;
    script.runInContext(state);
    return commands;
}

const simultaneous = observe({ contentChanged: true });
assert.equal(simultaneous.length, 1,
    "replay targeting the new answer must survive the same update as a generation change, exactly once");
assert.equal(simultaneous[0].command, "replay:answerOnly");
assert.equal(observe({ contentChanged: true, targetAnswer: false }).length, 0,
    "question replay must not leak to the answer");
assert.equal(observe({ contentChanged: true, targetCard: 41 }).length, 0,
    "previous card replay must not leak to the new card");
assert.equal(observe({ contentChanged: false }).length, 1, "ordinary replay still works");
console.log("review-replay-update: PASS (production branch translation; not Swift compilation)");
