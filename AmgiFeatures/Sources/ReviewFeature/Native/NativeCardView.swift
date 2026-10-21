//
//  NativeCardView.swift
//  ReviewFeature
//
//  Created by Vladimir Gusev on 20.07.2026.
//

import SwiftUI
import AppCore
import UI
import Theme
import AmgiCardWeb
#if canImport(UIKit)
import UIKit
#endif

/// Native SwiftUI renderer for allowlist-simple cards (R11). Renders the
/// side's parsed blocks on a radius-24 `AmgiCard` surface: the first text
/// block is the serif headword (large on the front, reduced on the back —
/// Anki back HTML already contains `{{FrontSide}}` plus an `<hr>` divider),
/// remaining text blocks are body copy, `<hr>` becomes a hairline.
struct NativeCardView: View {
    let content: NativeCardContent
    let isAnswerSide: Bool
    let mediaFolder: URL?
    var zoomScale: Double = ReviewZoomPolicy.defaultScale
    var scrollRequestID: Int = 0
    var scrollDirection: ReviewScrollDirection = .down
    var continuousScrollDelta: CGFloat? = nil

    @Environment(\.palette) private var palette

    @ScaledMetric(relativeTo: .largeTitle) private var headwordFront: CGFloat = 48
    @ScaledMetric(relativeTo: .title) private var headwordBack: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 20

    private var clampedZoomScale: CGFloat {
        CGFloat(ReviewZoomPolicy.clamped(zoomScale))
    }

    var body: some View {
        ScrollView {
            AmgiCard(
                background: .surface,
                cornerRadius: AmgiRadius.card,
                contentInsets: EdgeInsets(top: 40, leading: 24, bottom: 40, trailing: 24)
            ) {
                VStack(spacing: AmgiSpacing.lg) {
                    ForEach(Array(content.blocks.enumerated()), id: \.offset) { index, block in
                        blockView(block, isFirst: index == firstTextIndex)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            #if canImport(UIKit)
            .background(
                NativeCardScrollDriver(
                    requestID: scrollRequestID,
                    direction: scrollDirection,
                    continuousScrollDelta: continuousScrollDelta
                )
                .frame(width: 0, height: 0)
            )
            #endif
        }
    }

    private var firstTextIndex: Int? {
        content.blocks.firstIndex {
            if case .text = $0 { return true }
            return false
        }
    }

    @ViewBuilder
    private func blockView(_ block: NativeCardContent.Block, isFirst: Bool) -> some View {
        switch block {
        case .text(let attributed):
            // One `Text` with ternary modifier arguments rather than an
            // if/else over two `Text`s: the branches differed only in font and
            // scale factor, and `_ConditionalContent` would give the same
            // block two structural identities.
            Text(attributed)
                .font(.system(
                    size: (isFirst ? (isAnswerSide ? headwordBack : headwordFront) : bodySize)
                        * clampedZoomScale,
                    weight: isFirst ? .semibold : .regular,
                    design: .serif
                ))
                .minimumScaleFactor(isFirst ? 0.5 : 1)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
        case .image(let filename):
            // Decoded and downsampled off the main thread — a full-resolution
            // decode here lands squarely in the answer-reveal frame.
            DownsampledImage(
                url: mediaFolder?.appendingPathComponent(filename),
                maxPixelSize: AmgiImagePixelSize.card
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AmgiRadius.small, style: .continuous))
            } placeholder: {
                EmptyView()
            }
        case .divider:
            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
    }
}

#if canImport(UIKit)
private struct NativeCardScrollDriver: UIViewRepresentable {
    let requestID: Int
    let direction: ReviewScrollDirection
    let continuousScrollDelta: CGFloat?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }

    func updateUIView(_ view: UIView, context: Context) {
        guard requestID != context.coordinator.lastRequestID else { return }
        context.coordinator.lastRequestID = requestID
        DispatchQueue.main.async {
            guard let scrollView = enclosingScrollView(from: view) else { return }
            let minimumOffset = -scrollView.adjustedContentInset.top
            let maximumOffset = max(
                minimumOffset,
                scrollView.contentSize.height - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            let target: CGFloat
            let animated: Bool
            if let continuousScrollDelta {
                target = ReviewScrollPolicy.targetOffset(
                    currentOffset: scrollView.contentOffset.y,
                    minimumOffset: minimumOffset,
                    maximumOffset: maximumOffset,
                    delta: continuousScrollDelta
                )
                animated = false
            } else {
                target = ReviewScrollPolicy.targetOffset(
                    currentOffset: scrollView.contentOffset.y,
                    minimumOffset: minimumOffset,
                    maximumOffset: maximumOffset,
                    direction: direction
                )
                animated = true
            }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: target),
                animated: animated
            )
        }
    }

    final class Coordinator {
        var lastRequestID = 0
    }

    private func enclosingScrollView(from view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView { return scrollView }
            ancestor = current.superview
        }
        return nil
    }
}
#endif

#if DEBUG
#Preview("Front") {
    NativeCardView(
        content: .parse(html: "猫"),
        isAnswerSide: false,
        mediaFolder: nil
    )
}

#Preview("Back") {
    NativeCardView(
        content: .parse(html: "猫<hr>cat<br><i>The cat sat on the mat.</i>"),
        isAnswerSide: true,
        mediaFolder: nil
    )
}
#endif
