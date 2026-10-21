//
//  CardWebViewConfig.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 01.05.2026.
//

import AppCore
import Foundation

enum CardWebViewReplayMode: String, Sendable {
    case question
    case answerOnly
    case answerWithQuestion

    static func answerPolicy(_ policy: ReviewAnswerAudioPolicy) -> Self {
        switch policy {
        case .questionAndAnswer: .answerWithQuestion
        case .answerOnly: .answerOnly
        }
    }

    static func answerPolicy(rawValue: String) -> Self {
        answerPolicy(ReviewAnswerAudioPolicy.resolved(rawValue))
    }
}

package enum CardWebViewContentAlignment: String, Sendable {
    case top
    case center
}

enum CardWebViewAudioCommand: Equatable {
    case replay(CardWebViewReplayMode)
    case stop
}

struct CardWebViewAudioCommandQueue {
    private struct PendingCommand {
        let requestID: Int
        let command: CardWebViewAudioCommand
        let contentGeneration: Int
        let contentIdentity: String
    }

    private var contentGeneration = 0
    private var contentIdentity = ""
    private var readyContentGeneration: Int?
    private var pending: PendingCommand?

    mutating func beginContentUpdate(generation: Int, identity: String) {
        contentGeneration = generation
        contentIdentity = identity
        readyContentGeneration = nil
        pending = nil
    }

    mutating func enqueue(
        requestID: Int,
        command: CardWebViewAudioCommand,
        contentGeneration: Int,
        contentIdentity: String
    ) {
        guard contentGeneration == self.contentGeneration,
              contentIdentity == self.contentIdentity else { return }
        pending = PendingCommand(
            requestID: requestID,
            command: command,
            contentGeneration: contentGeneration,
            contentIdentity: contentIdentity
        )
    }

    mutating func markContentReady(generation: Int) {
        guard generation == contentGeneration else { return }
        readyContentGeneration = generation
    }

    mutating func takeReadyCommand() -> CardWebViewAudioCommand? {
        guard readyContentGeneration == contentGeneration,
              let pending,
              pending.contentGeneration == contentGeneration,
              pending.contentIdentity == contentIdentity else { return nil }
        self.pending = nil
        return pending.command
    }
}
