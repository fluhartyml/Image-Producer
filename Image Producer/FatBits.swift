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

    /// Shared with the canvas overlay — either surface can turn the PiP on or off.
    @AppStorage("ip.pip.visible") private var showProductionPiP: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Toggle("Floating preview", isOn: $showProductionPiP)
                .toggleStyle(.switch)
            Text("Keeps the production preview on the canvas with ANY tool active — "
                 + "drag it to any corner, double-click to resize.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

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

// MARK: - The floating PiP

/// The production preview as a floating panel over the canvas, on at all times.
///
/// WHY THIS EXISTS AND THE INSPECTOR VERSION IS NOT ENOUGH. Michael, 2026-08-24:
/// "can that preview be a togglable PiP?" — and he was correcting a real mistake.
/// R2 says the thumbnail updates "LIVE as each pixel is drawn". Putting it in the
/// ZOOM inspector means it is only visible while Zoom is the active tool, which is
/// exactly when nobody is drawing. MacPaint's Fat Bits panel was ON SCREEN while
/// you worked; it was not hidden behind a mode. This is that.
///
/// IT SNAPS TO A CORNER — his call, and the right one: "maybe drag and snaps to
/// one of the canvas 4 corners?". Free positioning means it can be left half off
/// the edge, or parked over the thing you are drawing. Four corners is a decision
/// the user makes once, and the panel is always somewhere sensible.

/// Which corner of the canvas the preview is parked in.
enum PiPCorner: Int, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// Centre point for a panel of `size` inside `bounds`, with a margin.
    func point(in bounds: CGSize, panel: CGFloat, margin: CGFloat = 16) -> CGPoint {
        let half = panel / 2 + margin
        switch self {
        case .topLeading:     return CGPoint(x: half, y: half)
        case .topTrailing:    return CGPoint(x: bounds.width - half, y: half)
        case .bottomLeading:  return CGPoint(x: half, y: bounds.height - half)
        case .bottomTrailing: return CGPoint(x: bounds.width - half, y: bounds.height - half)
        }
    }

    /// The corner nearest an arbitrary point — where a drag should land.
    static func nearest(to p: CGPoint, in bounds: CGSize, panel: CGFloat) -> PiPCorner {
        allCases.min(by: { a, b in
            let pa = a.point(in: bounds, panel: panel), pb = b.point(in: bounds, panel: panel)
            return hypot(pa.x - p.x, pa.y - p.y) < hypot(pb.x - p.x, pb.y - p.y)
        }) ?? .bottomLeading
    }
}

struct ProductionPiP: View {
    @ObservedObject var document: ImageDocument

    /// The canvas display rect's size — corners are the CANVAS's, not the window's.
    let bounds: CGSize

    /// Persisted: which corner, and how big. Defaults to bottom-LEADING because the
    /// canvas zoom controls already live bottom-trailing.
    @AppStorage("ip.pip.corner") private var cornerRaw: Int = PiPCorner.bottomLeading.rawValue
    @AppStorage("ip.pip.side") private var storedSide: Double = 96

    @State private var drag: CGSize = .zero
    @State private var dragging = false

    private var side: CGFloat { CGFloat(storedSide) }
    private var corner: PiPCorner { PiPCorner(rawValue: cornerRaw) ?? .bottomLeading }
    private var home: CGPoint { corner.point(in: bounds, panel: side) }

    var body: some View {
        VStack(spacing: 4) {
            ProductionThumbnail(document: document, side: side)
            Text("\(Int(side)) pt")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
        .shadow(radius: dragging ? 12 : 6, y: 2)
        .scaleEffect(dragging ? 1.04 : 1)          // it lifts while held
        .position(x: home.x + drag.width, y: home.y + drag.height)
        .gesture(
            DragGesture()
                .onChanged { v in
                    dragging = true
                    drag = v.translation
                }
                .onEnded { v in
                    let dropped = CGPoint(x: home.x + v.translation.width,
                                          y: home.y + v.translation.height)
                    let target = PiPCorner.nearest(to: dropped, in: bounds, panel: side)
                    // Snap: zero the offset and change corner in one animation, so it
                    // flies to the corner rather than jumping.
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        cornerRaw = target.rawValue
                        drag = .zero
                        dragging = false
                    }
                }
        )
        // Size cycles on double-click. No chrome — a control panel on a floating
        // reference would be more UI than the thing it is referencing.
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.15)) {
                storedSide = storedSide >= 160 ? 64 : storedSide + 32
            }
        }
        .help("Production preview — drag to any corner, double-click to resize. Never follows the canvas zoom.")
    }
}
