//
//  FatBits.swift
//  Image Producer
//
//  The live production thumbnail that rides alongside magnified pixel editing.
//
//  THIS IS R2, NOT A NEW IDEA. Michael resolved it on 2026-06-10 and wrote it
//  into the DeveloperNotes:
//
//    "(R2) ZOOM-IN/ZOOM-OUT CANVAS + FIXED-RESOLUTION THUMBNAIL (RESOLVED).
//     THE PREVIEW THUMBNAIL stays at ACTUAL SCREEN RESOLUTION (1:1 device
//     pixels, true final size) and does NOT follow the canvas zoom — it updates
//     LIVE as each pixel is drawn so you always see the real, shipping-size icon
//     take shape while the canvas is zoomed in. It renders the full layer
//     composite, not just the pixel layer."
//
//    In his own words: "a zoom in / zoom out canvas while the preview thumbnail
//    remains actual screen resolution."
//
//  WHERE THE IDEA CAME FROM, which he found again on 2026-08-24. MacPaint hid
//  this in the Goodies menu and called it FAT BITS: blow the pixels up to paint
//  them one at a time, and — the half that modern apps drop — keep a panel of
//  the picture at ACTUAL SIZE on screen at the same time. Andy Hertzfeld saw it
//  and built Susan Kare her first icon editor; until then she was designing the
//  Macintosh's icons on GRAPH PAPER. Notes and reference stills:
//    Workshop/MacPaint-design-notes-for-Image-Producer.md
//    Workshop/MacPaint-reference/
//
//  WHY IT MATTERS MORE HERE THAN ANYWHERE ELSE. This is an icon app. Editing an
//  icon means being zoomed in, while the only question that counts — does it
//  read at shipping size? — can only be answered zoomed out. MacPaint refused to
//  choose between the two views. So does this.
//
//  IT IS LIVE FOR FREE. `ImageCompositeView` is a SwiftUI view, not a raster, so
//  handing it a smaller `size` re-renders the whole composite at that size and
//  SwiftUI keeps it current as the document changes. Nothing to invalidate,
//  nothing to snapshot.
//
//  PLACEMENT. `zoom` was already in the LOCKED tool vocabulary and was withheld
//  from `Tool.shipping` only because its inspector was a placeholder. This is
//  that inspector. No tool was added; one was finished.
//

import SwiftUI

// MARK: - The live production thumbnail

/// The finished icon at shipping size, updating as you draw.
///
/// Deliberately does NOT follow the canvas zoom — that is the entire point of
/// R2. Interpolation is off: smoothing an icon preview would show the user
/// something the Finder never will.
struct ProductionThumbnail: View {
    @ObservedObject var document: ImageDocument

    /// Side length in points. Not a zoom factor — a real size.
    var side: CGFloat = 128

    var body: some View {
        ZStack {
            // The app's existing transparency checkerboard. An icon's alpha is
            // not a detail, it is most of the design.
            Checkerboard(squareSize: max(3, side / 16))
            ImageCompositeView(document: document,
                               size: CGSize(width: side, height: side))
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Production icon preview, \(Int(side)) points")
    }
}

// MARK: - The Zoom inspector

/// Zoom's inspector: the live production thumbnail, plus the sizes that decide
/// whether an icon works.
///
/// R2 specifies ONE thumbnail at true final size. The extra sizes below it are
/// offered because an icon that reads at 128 can still be mud at 16, and 16 is a
/// Finder list row. They are a row of previews, not a mode — nothing here
/// changes what the canvas is doing.
struct ZoomInspector: View {
    @ObservedObject var document: ImageDocument

    /// Shipping sizes worth checking at a glance. NOT the resolution ladder —
    /// R1's ladder (128/256/512/1024) is the ART-CELL grid density and lives in
    /// the Pen inspector. These are display sizes, a different axis entirely.
    private let checkSizes: [CGFloat] = [16, 32, 64]

    /// The main preview's size. Defaults to 128 — roughly a Dock icon.
    @State private var side: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Actual Size")
                .font(.headline)

            ProductionThumbnail(document: document, side: side)

            // Not a zoom control. This is which shipping size you are judging.
            Picker("Preview at", selection: $side) {
                Text("64").tag(CGFloat(64))
                Text("128").tag(CGFloat(128))
                Text("256").tag(CGFloat(256))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Divider()

            Text("Small sizes")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(checkSizes, id: \.self) { s in
                    VStack(spacing: 4) {
                        ProductionThumbnail(document: document, side: s)
                        Text("\(Int(s))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("The preview never follows the canvas zoom — that is the point. "
                 + "Work up close, judge at size.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        // Inspector convention (see PaintBucketInspector): pad here, and never
        // add a ScrollView — ToolInspector already wraps content in one.
        .padding()
    }
}
