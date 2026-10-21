//
//  WatchApp.swift
//  AmgiWatchApp
//
//  Created by Leaf Eriksen on 17.07.2026.
//

import AnkiBackend
import AnkiSync
import Compression
import CryptoKit
import Dependencies
import Foundation
import Sharing
import SwiftUI
import Theme
import WatchFeature

@main
struct WatchApp: App {
    @State private var isLoggedIn = KeychainHelper.loadHostKey() != nil
    private let startupError: (any Error)?

    // Bootstrap belongs in init, not .onAppear. From .onAppear it ran *after*
    // the content views were constructed — and their `.task` may already have
    // resolved @Dependency(\.ankiBackend), which swift-dependencies then
    // caches, silently binding the unimplemented test client. .onAppear also
    // fires again on reappearance, constructing a second AnkiBackend over the
    // same SQLite file. The iOS scheme doesn't build this target, so nothing
    // caught it.
    init() {
        var failure: (any Error)?
        do {
            try Self.setUpBackend()
        } catch {
            failure = error
        }
        startupError = failure
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = startupError {
                    VStack(spacing: 20) {
                        Text("Startup Error")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .multilineTextAlignment(.center)
                        Button("Sign Out") {
                            isLoggedIn = false
                        }
                    }
                    .padding()
                    .themedRoot()
                } else if isLoggedIn {
                    WatchContentView()
                } else {
                    WatchLoginView {
                        isLoggedIn = true
                    }
                }
            }
            .themedRoot()
        }
    }

    private static func setUpBackend() throws {
        try prepareDependencies {
            let backend = try AnkiBackend(preferredLangs: ["en"])
            // Unprofiled path on purpose: the watch is a separate device
            // container with no profile registry, so it always resolves to
            // the "default" scope (see AnkiKit.ProfileScope). It is not the
            // phone's legacy pre-migration directory.
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? URL.applicationSupportDirectory
            let ankiDir = appSupport.appendingPathComponent("AnkiCollection", isDirectory: true)
            try FileManager.default.createDirectory(at: ankiDir, withIntermediateDirectories: true)
            try installStagedCollectionIfPresent(appSupport: appSupport, ankiDir: ankiDir)
            let collectionPath = ankiDir.appendingPathComponent("collection.anki2").path
            let mediaPath = ankiDir.appendingPathComponent("media").path
            let mediaDbPath = ankiDir.appendingPathComponent("media.db").path
            try FileManager.default.createDirectory(
                atPath: mediaPath, withIntermediateDirectories: true
            )
            try backend.openCollection(
                collectionPath: collectionPath,
                mediaFolderPath: mediaPath,
                mediaDbPath: mediaDbPath
            )
            $0.ankiBackend = backend
        }
    }

    private struct SeedManifest: Decodable {
        let version: Int
        let byteCount: Int
        let sha256: String
        let parts: [String]
        let compression: String?
    }

    private static func installStagedCollectionIfPresent(
        appSupport: URL,
        ankiDir: URL
    ) throws {
        let fileManager = FileManager.default
        let stagingDir = appSupport.appendingPathComponent("AnkiSeedStaging", isDirectory: true)
        let manifestURL = stagingDir.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }

        let manifest = try JSONDecoder().decode(
            SeedManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.version == 1, manifest.byteCount > 0, !manifest.parts.isEmpty else {
            throw NSError(
                domain: "AmgiWatchSeed",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid staged collection manifest."]
            )
        }

        let temporaryURL = ankiDir.appendingPathComponent("collection.anki2.seed")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw NSError(
                domain: "AmgiWatchSeed",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create staged collection file."]
            )
        }

        for partName in manifest.parts {
            guard (partName as NSString).lastPathComponent == partName else {
                throw NSError(
                    domain: "AmgiWatchSeed",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid staged collection part name."]
                )
            }
        }

        let output = try FileHandle(forWritingTo: temporaryURL)
        var hasher = SHA256()
        var written = 0
        do {
            if manifest.compression == "zlib" {
                var partIndex = 0
                var currentInput: FileHandle?
                let filter = try InputFilter<Data>(
                    .decompress,
                    using: .zlib,
                    readingFrom: { requestedCount in
                        while true {
                            if currentInput == nil {
                                guard partIndex < manifest.parts.count else { return nil }
                                currentInput = try FileHandle(
                                    forReadingFrom: stagingDir.appendingPathComponent(
                                        manifest.parts[partIndex]
                                    )
                                )
                                partIndex += 1
                            }
                            if let data = try currentInput?.read(upToCount: requestedCount),
                               !data.isEmpty {
                                return data
                            }
                            try currentInput?.close()
                            currentInput = nil
                        }
                    }
                )
                defer { try? currentInput?.close() }
                while let data = try filter.readData(ofLength: 1_048_576) {
                    hasher.update(data: data)
                    try output.write(contentsOf: data)
                    written += data.count
                }
            } else if manifest.compression == nil {
                for partName in manifest.parts {
                    let input = try FileHandle(
                        forReadingFrom: stagingDir.appendingPathComponent(partName)
                    )
                    while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                        hasher.update(data: data)
                        try output.write(contentsOf: data)
                        written += data.count
                    }
                    try input.close()
                }
            } else {
                throw NSError(
                    domain: "AmgiWatchSeed",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported staged collection compression."]
                )
            }
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard written == manifest.byteCount, digest == manifest.sha256.lowercased() else {
            try? fileManager.removeItem(at: temporaryURL)
            throw NSError(
                domain: "AmgiWatchSeed",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Staged collection verification failed."]
            )
        }

        let collectionURL = ankiDir.appendingPathComponent("collection.anki2")
        for url in [
            collectionURL,
            ankiDir.appendingPathComponent("collection.anki2-wal"),
            ankiDir.appendingPathComponent("collection.anki2-shm"),
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporaryURL, to: collectionURL)
        try fileManager.removeItem(at: stagingDir)
    }
}
