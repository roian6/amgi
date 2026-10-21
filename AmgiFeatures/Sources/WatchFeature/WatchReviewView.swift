//
//  WatchReviewView.swift
//  WatchFeature
//
//  Created by Leaf Eriksen on 17.07.2026.
//

import AVFoundation
import AnkiBackend
import AnkiKit
import Dependencies
import AmgiCardWeb
import Foundation
import SwiftUI
import ReviewCore

struct WatchReviewView: View {
    let deckId: DeckID
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReviewSession
    @State private var audioPlayer = AVQueuePlayer()

    private var currentHTML: String {
        session.showAnswer ? session.backHTML : session.frontHTML
    }
    init(deckId: DeckID, onFinish: @escaping () -> Void) {
        self.deckId = deckId
        self.onFinish = onFinish
        self._session = State(initialValue: ReviewSession(deckId: deckId))
    }
    var body: some View {
        VStack {
            if session.isFinished {
                finishedView
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        CardTextView(html: currentHTML, css: session.cardCSS, mediaFolder: session.mediaFolder)
                    }
                    if session.showAnswer {
                        HStack(spacing: 0) {
                            ratingButton(.again, label: "Again", color: .red)
                            ratingButton(.good, label: "Good", color: .green)
                        }
                    } else {
                        reviewButton("Show Answer", color: .blue) { session.revealAnswer() }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Color.black)
        ._statusBarHidden()
        .onTapGesture { playAudio(from: currentHTML) }
        .accessibilityAction(named: "Replay Audio") { playAudio(from: currentHTML) }
        .task {
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback,
                    mode: .default,
                    policy: .longFormAudio
                )
                // watchOS-only API. Unguarded, it makes WatchFeature fail to
                // compile for an iOS destination, which is what the
                // AmgiFeatures-Package scheme builds — so no package test
                // target could run at all. Guarding changes nothing on watchOS.
                #if os(watchOS)
                try await AVAudioSession.sharedInstance().activate(options: [])
                #endif
            } catch {
                // Audio may fail silently on watchOS if session setup errors.
            }
            session.start()
        }
        .onChange(of: session.frontHTML) { _, new in playAudio(from: new) }
        .onChange(of: session.showAnswer) { _, show in if show { playAudio(from: session.backHTML) } }
    }
    private var finishedView: some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("Finished!").font(.headline)
            Text("\(session.sessionStats.reviewed) cards").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                dismiss()
                onFinish()
            }
            .buttonStyle(.borderedProminent)
        }.padding()
    }
    private func reviewButton(_ title: String, color: Color, font: Font = .headline, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .frame(maxWidth: .infinity)
                .padding(12)
        }
        .buttonStyle(.plain)
        .background(color)
    }
    private func ratingButton(_ rating: Rating, label: LocalizedStringKey, color: Color) -> some View {
        let interval = session.nextIntervals[rating] ?? ""
        return reviewButton(interval, color: color, font: .caption) {
            session.answer(rating: rating)
        }
        .accessibilityLabel(label)
        .accessibilityValue(interval)
    }
    private func playAudio(from html: String) {
        @Dependency(\.ankiBackend) var backend
        guard let mediaDir = backend.currentMediaFolderPath else { return }
        let items = CardText.soundFilenames(in: html).map { filename in
            AVPlayerItem(url: URL(fileURLWithPath: mediaDir).appendingPathComponent(filename))
        }
        audioPlayer.removeAllItems()
        items.forEach { if audioPlayer.canInsert($0, after: nil) { audioPlayer.insert($0, after: nil) } }
        audioPlayer.play()
    }
}

struct CardTextView: View {
    let document: WatchCardDocument
    let content: NativeCardContent
    @State private var richText: WatchCardRichText?

    init(html: String, css: String = "", mediaFolder: URL? = nil) {
        document = WatchCardDocument(html: html, css: css, mediaFolder: mediaFolder)
        content = NativeCardContent.parse(html: document.fallbackHTML)
    }

    var body: some View {
        Group {
            if let richText, richText.document == document {
                VStack(spacing: 0) {
                    ForEach(Array(richText.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph.text)
                            .multilineTextAlignment(paragraph.alignment)
                            .frame(maxWidth: .infinity, alignment: paragraph.frameAlignment)
                            .padding(.top, paragraph.spaceBefore)
                            .padding(.bottom, paragraph.spaceAfter)
                    }
                }
            } else {
                fallback
            }
        }
        .task(id: document) {
            richText = WatchCardRichText(document: document)
        }
    }

    private var fallback: some View {
        VStack(spacing: 8) {
            ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let attributed):
                    Text(attributed)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                case .divider:
                    Divider()
                case .image(let filename):
                    Image(systemName: "photo")
                        .accessibilityLabel("Image: \(filename)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
