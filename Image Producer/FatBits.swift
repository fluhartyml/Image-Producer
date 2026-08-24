//
//  FatBits.swift
//  Image Producer
//
//  Magnified pixel editing with a live actual-size preview.
//
//  WHERE IT COMES FROM. MacPaint hid this in the Goodies menu and called it FAT
//  BITS: blow the pixels up so you can paint them one at a time, and — the part
//  most apps forget — show a small panel of the picture at ACTUAL SIZE at the
//  same time. Andy Hertzfeld saw it and built Susan Kare her first icon editor,
//  because until then she was designing the Macintosh's icons on GRAPH PAPER.
//
//  WHY IT MATTERS HERE MORE THAN ANYWHERE. Image Producer is an icon app. When
//  you edit an icon you are always zoomed in, but the only question that counts —
//  "does it read at 16pt?" — can only be answered zoomed out. Fat Bits answered
//  that in 1984 by refusing to choose: both views, at once, always.
//
//  Michael, 2026-08-24, asked for "the actual icon thing they were tlking about
//  for that lady" — Susan Kare. Notes and reference stills:
//    Workshop/MacPaint-design-notes-for-Image-Producer.md
//    Workshop/MacPaint-reference/
//
//  NOTE ON PLACEMENT. `zoom` is already in the LOCKED tool vocabulary
//  (DeveloperNotes, "TOOL VOCABULARY") and was withheld from `Tool.shipping`
//  only because its inspector was a placeholder. This is that inspector. No tool
//  was added; one was finished.
//

import SwiftUI

// MARK: - Actual-size preview

/// The small panel that shows the artwork at 1:1 while you work magnified.
///
/// Deliberately dumb: it renders whatever image it is handed at a fixed pixel
/// size with NO interpolation, so what you see is exactly what a user will see
/// at that size. Smoothing here would be a lie.
struct ActualSizePreview: View {
    /// The composited artwork. Nil renders the empty frame, which is correct on
    /// a new document rather than an error.
    let image: CGImage?

    /// The size to show it at, in points. 32 is the classic icon grid; the
    /// picker below offers the sizes that actually matter on Apple platforms.
    let size: CGFloat

    var body: some View {
        ZStack {
            // The app's existing transparency checkerboard (ContentView) — an
            // icon's alpha is not a detail, it is most of the design. Small
            // squares here because the previews themselves are small.
            Checkerboard(squareSize: max(3, size / 8))
                .frame(width: size, height: size)
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)          // never smooth an icon preview
                    .antialiased(false)
                    .resizable()
                    .frame(width: size, height: size)
            }
        }
        .overlay(Rectangle().stroke(.secondary.opacity(0.4), lineWidth: 1))
        .accessibilityLabel("Actual size preview, \(Int(size)) points")
    }
}

// MARK: - The Fat Bits panel

/// Fat Bits: the actual-size previews that ride alongside magnified editing.
///
/// The magnification itself belongs to the canvas (see `ZoomableCanvas`); this
/// is the half MacPaint got right that modern apps drop — the constant,
/// unmagnified truth sitting next to the work.
struct FatBitsPanel: View {
    /// Composited artwork to preview. The caller supplies it; this view never
    /// reaches into the document.
    let image: CGImage?

    /// Sizes worth checking. 16 is a Finder list row and the cruellest test;
    /// 1024 is the App Store. Michael's rule is that the small ones decide it.
    static let sizes: [CGFloat] = [16, 32, 64, 128]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actual Size")
                .font(.headline)

            // All four at once, largest first, so the eye can compare them in a
            // single glance rather than by flipping a control.
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Self.sizes.reversed(), id: \.self) { s in
                    VStack(spacing: 4) {
                        ActualSizePreview(image: image, size: s)
                        Text("\(Int(s))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("If it does not read at 16, it does not read.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
