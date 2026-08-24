//
//  MarchingAnts.swift
//  Image Producer
//
//  The animated selection border, 1984 edition.
//
//  WHERE IT COMES FROM. Bill Atkinson needed a way to show a selection on a
//  one-bit screen. Inverting the pixels worked on simple pictures and became
//  unreadable on complex ones. The answer arrived in a pub in Los Gatos, where he
//  looked up at a Hamm's beer sign with an animated waterfall — and realised the
//  water was not moving at all. A ROTATING MASK underneath made a static image
//  read as motion.
//
//  That is exactly what this is. Nothing redraws. A dashed stroke has its
//  dashPhase advanced, and the eye supplies the marching.
//
//  Michael asked for this on 2026-08-24 — "ant go marching on is a bonus if you
//  can do it" — after sending the video that explains where it came from. Notes
//  and reference stills in the apartment:
//    Workshop/MacPaint-design-notes-for-Image-Producer.md
//

import SwiftUI

/// A marching-ants border for any shape.
///
/// Two strokes, offset by half a period: a white one and a black one. That is
/// what makes the border legible over BOTH light and dark artwork without
/// knowing anything about what is underneath it — the same reason MacPaint's
/// worked on a black-and-white screen.
struct MarchingAnts<S: Shape>: View {
    let shape: S

    /// Dash length in points. 4 matches the original's feel at 1x; larger reads
    /// better when the canvas itself is magnified (see `FatBits`).
    var dash: CGFloat = 4

    /// Seconds for the pattern to travel one full period. Lower = faster ants.
    var period: Double = 0.5

    /// Set false to freeze the animation — useful while a drag is in flight, and
    /// required for anything being exported or screenshotted.
    var animated: Bool = true

    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            // The light half of the pattern.
            shape.stroke(style: StrokeStyle(lineWidth: 1, dash: [dash, dash], dashPhase: phase))
                .foregroundStyle(.white)
            // The dark half, offset by one dash so the two interleave.
            shape.stroke(style: StrokeStyle(lineWidth: 1, dash: [dash, dash], dashPhase: phase + dash))
                .foregroundStyle(.black)
        }
        .allowsHitTesting(false)
        .onAppear { start() }
        .onChange(of: animated) { _, _ in start() }
    }

    private func start() {
        phase = 0
        guard animated else { return }
        // One period of travel is two dashes — the light run plus the dark run.
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            phase = dash * 2
        }
    }
}

extension View {
    /// Outline this view's bounds with marching ants.
    ///
    /// ```swift
    /// selectionRect.marchingAnts()
    /// ```
    func marchingAnts(dash: CGFloat = 4, period: Double = 0.5, animated: Bool = true) -> some View {
        overlay(MarchingAnts(shape: Rectangle(), dash: dash, period: period, animated: animated))
    }

    /// Outline this view with marching ants following an arbitrary shape — the
    /// silhouette a lasso or Cookie Cutter produced, for instance.
    func marchingAnts<S: Shape>(_ shape: S,
                                dash: CGFloat = 4,
                                period: Double = 0.5,
                                animated: Bool = true) -> some View {
        overlay(MarchingAnts(shape: shape, dash: dash, period: period, animated: animated))
    }
}
