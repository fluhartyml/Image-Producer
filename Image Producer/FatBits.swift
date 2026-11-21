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
    @Bindable var document: ImageDocument

    /// The SHORT edge in points — fixed. Not a zoom factor — a real size.
    var side: CGFloat = 128

    /// THE PREVIEW TAKES THE CANVAS'S SHAPE, AND ONLY EVER GROWS. Michael, 2026-10-03,
    /// on a 1500 × 500 banner: "the preview should mirror the canvas shape and not get
    /// letterbox" → "the height should remain the same where the width increases" →
    /// "the width should never decrease … if the canvas turns out to be higher than
    /// wider." So the SHORT edge is always `side` and the long edge grows: a 3:1 banner
    /// is three times as wide, a 1:3 poster three times as tall, a square unchanged.
    static func fitted(_ canvas: CGSize, side: CGFloat) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return CGSize(width: side, height: side) }
        return canvas.width >= canvas.height
            ? CGSize(width: (side * canvas.width / canvas.height).rounded(), height: side)
            : CGSize(width: side, height: (side * canvas.height / canvas.width).rounded())
    }

    private var size: CGSize { Self.fitted(document.canvasPixelSize, side: side) }

    var body: some View {
        ZStack {
            // The app's existing transparency checkerboard. An icon's alpha is
            // not a detail, it is most of the design.
            Checkerboard(squareSize: max(3, side / 16))
            ImageCompositeView(document: document, size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Production icon preview at \(Int(side)) points")
    }
}

// MARK: - The Zoom inspector — REMOVED 2026-11-21

// REM: His word on the 16e, 2026-11-21: "this tool inspector is useless as is tell me why it is
// there" → "go with option 2". It had held only the Floating preview switch and two tips since the
// 10-04 removal of the Icon Producer leftovers. The switch now lives in the Canvas inspector.

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
    func point(in bounds: CGSize, panel: CGSize, margin: CGFloat = 16) -> CGPoint {
        let hx = panel.width / 2 + margin, hy = panel.height / 2 + margin
        switch self {
        case .topLeading:     return CGPoint(x: hx, y: hy)
        case .topTrailing:    return CGPoint(x: bounds.width - hx, y: hy)
        case .bottomLeading:  return CGPoint(x: hx, y: bounds.height - hy)
        case .bottomTrailing: return CGPoint(x: bounds.width - hx, y: bounds.height - hy)
        }
    }

    /// The corner nearest an arbitrary point — where a drag should land.
    static func nearest(to p: CGPoint, in bounds: CGSize, panel: CGSize) -> PiPCorner {
        allCases.min(by: { a, b in
            let pa = a.point(in: bounds, panel: panel), pb = b.point(in: bounds, panel: panel)
            return hypot(pa.x - p.x, pa.y - p.y) < hypot(pb.x - p.x, pb.y - p.y)
        }) ?? .bottomLeading
    }
}

struct ProductionPiP: View {
    @Bindable var document: ImageDocument

    /// The canvas display rect's size — corners are the CANVAS's, not the window's.
    let bounds: CGSize

    /// ZOOMED IN, THE PiP IS A NAVIGATOR. Michael, 2026-10-19: "the PiP the pointer when
    /// clicked centers to that exact point and click drag pans". `viewport` = the part
    /// of the canvas in view (0…1 units), drawn as a box; nil at 1×, where there is
    /// nothing to navigate and a drag moves the panel to a corner as before.
    var viewport: CGRect? = nil
    /// Called with a point on the canvas (0…1) to centre the view there.
    var onNavigate: ((CGPoint) -> Void)? = nil

    /// Persisted: which corner. Defaults to bottom-LEADING because the canvas zoom
    /// controls already live bottom-trailing.
    @AppStorage("ip.pip.corner") private var cornerRaw: Int = PiPCorner.bottomLeading.rawValue

    /// ONE size. Not stored, not adjustable — see the caption note in `body`.
    private let storedSide: Double = 96

    @State private var drag: CGSize = .zero
    @State private var dragging = false

    private var side: CGFloat { CGFloat(storedSide) }
    private var corner: PiPCorner { PiPCorner(rawValue: cornerRaw) ?? .bottomLeading }
    /// The panel as drawn: the canvas-shaped thumbnail plus its 8-pt padding.
    private var panel: CGSize {
        let t = ProductionThumbnail.fitted(document.canvasPixelSize, side: side)
        return CGSize(width: t.width + 16, height: t.height + 16 + Self.gripHeight)
    }

    /// REM 2026-11-21 — A HANDLE TO MOVE IT BY. His 16e note on 433: "You cant move the PiP if you
    /// touch it it zooms and pans". Zoomed in, the thumbnail is a navigator (his 10-19 rule: "click
    /// drag pans"), so a drag on it can never also move the panel. The strip across the top is the
    /// panel's own: drag it to another corner at any zoom (his 11-05 "movable like the PiP
    /// everywhere"). It is a button too — a tap sends it to the next corner — so a switch, Voice
    /// Control or Sticky Keys user never needs the drag (his rules).
    static let gripHeight: CGFloat = 18

    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                dragging = true
                drag = v.translation
            }
            .onEnded { v in drop(v.translation) }
    }

    /// REM 2026-11-21 — LONG PRESS TO MOVE IT. His word: "yes long press to move the pip" (his 433 note:
    /// "You cant move the PiP if you touch it it zooms and pans"). Hold anywhere on the preview, it
    /// lifts, then drag it to a corner — at any zoom. A quick touch still navigates, as his 10-19
    /// rule says ("click drag pans"). While it is lifted the navigator stands down.
    private var holdDrag: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let d) = value else { return }
                if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                drag = d?.translation ?? .zero
            }
            .onEnded { value in
                guard case .second(true, let d) = value else { return }
                drop(d?.translation ?? .zero)
            }
    }

    /// Snap to the corner nearest where it was let go: zero the offset and change corner in one
    /// animation, so it flies to the corner rather than jumping.
    private func drop(_ translation: CGSize) {
        let dropped = CGPoint(x: home.x + translation.width, y: home.y + translation.height)
        let target = PiPCorner.nearest(to: dropped, in: bounds, panel: panel)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            cornerRaw = target.rawValue
            drag = .zero
            dragging = false
        }
    }

    private var grip: some View {
        Button {
            let all = PiPCorner.allCases
            let next = all[(all.firstIndex(of: corner)! + 1) % all.count]
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { cornerRaw = next.rawValue }
        } label: {
            Capsule()
                .fill(.secondary)
                .frame(width: 32, height: 5)
                .frame(maxWidth: .infinity, minHeight: Self.gripHeight + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(moveDrag)
        .padding(.top, -8)
        .accessibilityLabel("Move preview")
        .accessibilityHint("Moves the floating preview to the next corner")
        .help("Drag to move the preview to another corner, or click to send it to the next one")
    }
    private var home: CGPoint { corner.point(in: bounds, panel: panel) }

    var body: some View {
        // NO CAPTION, and his reasoning is the point — Michael, 2026-08-24:
        //   "i figured it already stays one size and instead of changing the PiP
        //    size we remove the caption so the user doesnt think its a bug"
        // The panel was always going to be one size. Printing "96 pt" on it implies
        // the number is a property you can change, so when it does not, the app
        // looks BROKEN. He diagnosed a PERCEIVED bug, not a real one.
        // RULE: do not display a value the user cannot change and does not need.
        // It reads as a control that is failing.
        let thumb = ProductionThumbnail.fitted(document.canvasPixelSize, side: side)
        VStack(spacing: 0) {
            // REM 2026-11-21 — the handle is exactly as wide as the thumbnail. Left to stretch, it widened
            // the whole panel past the size `panel` assumes, and the 16e sim showed it hanging off the
            // left edge of the canvas.
            grip.frame(width: thumb.width)
            ProductionThumbnail(document: document, side: side)
                .frame(width: thumb.width, height: thumb.height)
                .overlay {
                    if let v = viewport?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)), !v.isNull {
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: max(4, v.width * thumb.width), height: max(4, v.height * thumb.height))
                            .position(x: v.midX * thumb.width, y: v.midY * thumb.height)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                // Click = centre there; drag = keep centring under the pointer, i.e. pan.
                .gesture(viewport == nil ? nil : DragGesture(minimumDistance: 0).onChanged { v in
                    guard !dragging else { return }   // lifted by a long press: moving, not navigating
                    onNavigate?(CGPoint(x: min(max(v.location.x / thumb.width, 0), 1),
                                        y: min(max(v.location.y / thumb.height, 0), 1)))
                })
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
        .shadow(radius: dragging ? 12 : 6, y: 2)
        .scaleEffect(dragging ? 1.04 : 1)          // it lifts while held
        .position(x: home.x + drag.width, y: home.y + drag.height)
        // At 1× a drag anywhere on it moves the panel; zoomed in, the thumbnail navigates and the
        // handle on top moves it.
        .gesture(viewport != nil ? nil : moveDrag)
        .simultaneousGesture(holdDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pip.panel")
        .help(viewport == nil ? "Production preview — drag it to any corner. Never follows the canvas zoom."
                              : "Navigator — click to center the view there, drag to pan; hold it, or drag the handle, to move it")
    }
}
