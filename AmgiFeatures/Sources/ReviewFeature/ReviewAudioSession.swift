//
//  ReviewAudioSession.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 04.05.2026.
//

import AVFoundation
import Foundation

@MainActor
enum ReviewAudioSession {
    private static var currentPlayInSilent: Bool?

    static func apply(playInSilent: Bool) {
        currentPlayInSilent = playInSilent
        _ = prepareForPlayback()
    }

    static func prepareForPlayback() -> Bool {
        guard let playInSilent = currentPlayInSilent else { return false }
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = playInSilent ? .playback : .ambient
        do {
            try session.setCategory(category, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            return false
        }
        #endif
        return true
    }

    static func release() {
        currentPlayInSilent = nil
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        #endif
    }
}
