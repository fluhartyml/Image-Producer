//
//  MaskTool.swift
//  Image Producer
//
//  THE MASK — a selection you can actually grab.
//
//  WHY IT EXISTS. The crop could not be lined up with the artwork by hand, and the
//  reason was arithmetic rather than a knack Michael hadn't found. Two separate
//  center-bindings were fighting him:
//
//    1. Every crop rect was built by `centeredRect()` — the crop had a SIZE but no
//       POSITION, so it could never sit over an off-center subject.
//    2. The Move box's corner drag scaled "aspect-locked, around the center" — three
//       degrees of freedom (move X, move Y, one uniform scale) where matching a
//       rectangle needs four.
//
//  His own words, 2026-08-24, with the crop at 80% and the layer scaled to 302%:
//  "i can only get two sides and one grabber in place because the square selector is
//  center bound." Exactly right — with three degrees of freedom you can pin one corner
//  and the two edges running off it, and the fourth is unreachable.
//
//  THE BEHAVIOUR HE SPECIFIED (verbatim, and it is the whole spec):
//
//    "aspect ratio square move one grabber then the opposite grabber stays locked and
//     the square gets larger or smaller depending on the distance between the selected
//     grabber and its adjacent counterpart … the 16:9 and others function one grabber
//     moves the opposite side grabber is locked … you have to grab the center of the
//     square or rectangle to reposition the mask"
//
//    "the freeform has two freeforms theres the one that each corner maintains a 90
//     degree angle and the one you found that all four corners are accute or obtuce"
//
//    "a modifyer key option turns the any angle any grabber position but no modifyer
//     key all four corners are free to move as long as they are 90 degrees"
//
//  So: ⌘ is the switch. Without it a corner drag keeps the shape a rectangle; with it
//  that one corner goes anywhere and the mask becomes a quadrilateral. The frequent
//  case needs no key at all, which is what Sticky Keys asks of a design — see
//  `feedback_sticky_keys_avoid_modifier_gestures` in the apartment. Both freeforms are
//  ALSO listed in the picker, so the modifier is an accelerator and never the only route.
//
//  AND IT IS ITS OWN TOOL, not part of Move/Transform — Michael, 2026-08-24: "we need a
//  mask tool in addition to the move transform." That separation is what finally stops
//  the mask's handles and the layer's handles from being confused for each other: these
//  grabbers move the MASK and never touch the artwork.
//
//  Full spec: apartment `Workshop/ImageProducer-Mask-Grabber-Spec-2026-08-24.md`.
//

import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#endif

// MARK: - The shapes a mask can cut

/// The silhouette vocabulary, per Michael 2026-08-24: *"use star square/rectangle
/// circle/elipse and some random sf and unicode shapes."*
///
/// Every case here resolves to a real vector `Path`, which is what lets the marching ants
/// trace the actual silhouette instead of a bounding box. `.glyph` covers "random unicode
/// shapes" and is the deep well — every dingbat, arrow, star and ornament in every font
/// on the machine, exact, via CoreText.
///
/// **SF Symbols are deliberately absent for now.** They are not reachable as vector paths
/// the way a font glyph is; masking with one means rendering it and tracing its alpha.
/// That is the next step, not a dropped requirement.
///
/// Written to be adopted by the Shape tool when it ships — its locked vocabulary
/// ("line / rectangle / oval / polygon", `EditorTools.swift:28`) is a subset of this.
enum MaskForm: Equatable, Hashable, Codable {
    case rectangle
    case oval
    case polygon
    case star
    /// Any Unicode character, drawn from `fontName` (nil = system font).
    case glyph(String, fontName: String?)

    var label: String {
        switch self {
        case .rectangle: "Square / Rectangle"
        case .oval:      "Circle / Oval"
        case .polygon:   "Polygon"
        case .star:      "Star"
        case .glyph(let c, _): "Character \(c)"
        }
    }

    /// The forms offered as plain picker rows. `.glyph` is reached through its own
    /// character field, so it isn't listed here.
    static let pickable: [MaskForm] = [.rectangle, .oval, .polygon, .star]
}

// MARK: - The mask itself

/// A four-cornered mask in normalized canvas space (0…1, origin top-left).
///
/// Four points rather than a `CGRect` because Michael's Freeform-with-⌘ lets every
/// corner go acute or obtuse — at which point the shape is a quadrilateral and a rect
/// can no longer describe it. Every rectangular case is just a quad whose corners
/// happen to sit at right angles, so one type covers all the modes.
///
/// Corner order is fixed and every operation depends on it:
/// `0 = top-left · 1 = top-right · 2 = bottom-right · 3 = bottom-left`.
/// The corner OPPOSITE index `i` — the one that stays nailed down during a resize —
/// is always `(i + 2) % 4`.
struct CropMask: Equatable, Codable {
    var corners: [CGPoint]

    /// What silhouette is cut inside the frame. Michael, 2026-08-24: "the mask needs to
    /// be able to use a randomly drawn path or a shape. i think we should just offer a
    /// shape untill we get the path tool." So a shape now, `.path` when the Path tool
    /// ships — the frame and its grabbers are identical either way.
    var form: MaskForm = .rectangle

    /// Side count for `.polygon`. Ignored by the other forms.
    var polygonSides: Int = 6

    /// Smallest edge a mask may be squeezed to, normalized. Keeps a mask from being
    /// collapsed to nothing and becoming impossible to grab again.
    static let minSide: CGFloat = 0.02

    init(corners: [CGPoint], form: MaskForm = .rectangle, polygonSides: Int = 6) {
        self.corners = corners.count == 4 ? corners : CropMask(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)).corners
        self.form = form
        self.polygonSides = max(3, min(polygonSides, 12))
    }

    init(rect: CGRect, form: MaskForm = .rectangle, polygonSides: Int = 6) {
        corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        self.form = form
        self.polygonSides = max(3, min(polygonSides, 12))
    }

    /// Axis-aligned bounding box. This is what export trims to, and what older files
    /// (which stored a plain `cropRect`) round-trip through.
    var bounds: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True when the four corners still form an axis-aligned rectangle — i.e. no ⌘ drag
    /// has bent it. Export can take the cheap `cropping(to:)` path when this holds.
    var isRectangular: Bool {
        let e: CGFloat = 0.0005
        return abs(corners[0].y - corners[1].y) < e && abs(corners[3].y - corners[2].y) < e
            && abs(corners[0].x - corners[3].x) < e && abs(corners[1].x - corners[2].x) < e
    }

    /// The corners in a view's coordinate space.
    func points(in size: CGSize) -> [CGPoint] {
        corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// The FRAME — the four-cornered outline you grab. Always a quad, whatever the form.
    func framePath(in size: CGSize) -> Path {
        var p = Path()
        let pts = points(in: size)
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    /// The SILHOUETTE — what is actually kept. This is what the ants trace, what the dim
    /// cuts around, and what export clips to.
    ///
    /// `.rectangle` uses the quad ITSELF, so a ⌘-distorted mask keeps its bent corners.
    /// `.oval` and `.polygon` are inscribed in the frame's bounding box: distorting the
    /// frame moves and sizes them, but does not shear them — a sheared ellipse is a
    /// projective map, which is a bigger idea than this needs and would arrive with the
    /// Path tool anyway.
    func silhouette(in size: CGSize) -> Path {
        switch form {
        case .rectangle:
            return framePath(in: size)
        case .oval:
            let b = bounds
            return Path(ellipseIn: CGRect(x: b.minX * size.width, y: b.minY * size.height,
                                          width: b.width * size.width, height: b.height * size.height))
        case .polygon:
            return Self.radialPath(in: boundsRect(in: size), points: max(3, min(polygonSides, 12)), innerRatio: 1)
        case .star:
            // Five points unless he says otherwise; 0.42 is the inner radius that reads as
            // "a star" rather than a spiky asterisk or a fat pinwheel.
            return Self.radialPath(in: boundsRect(in: size), points: max(3, min(polygonSides, 12)), innerRatio: 0.42)
        case .glyph(let text, let fontName):
            return Self.glyphPath(text, fontName: fontName, fitting: boundsRect(in: size))
                ?? Path(ellipseIn: boundsRect(in: size))
        }
    }

    /// The frame's bounding box in a view's coordinate space.
    private func boundsRect(in size: CGSize) -> CGRect {
        let b = bounds
        return CGRect(x: b.minX * size.width, y: b.minY * size.height,
                      width: b.width * size.width, height: b.height * size.height)
    }

    /// Polygon and star share one generator — a star IS a polygon whose alternate vertices
    /// are pulled toward the middle. `innerRatio: 1` gives the plain polygon.
    /// Starts at 12 o'clock so a triangle points up and a star stands on two feet.
    static func radialPath(in r: CGRect, points n: Int, innerRatio: CGFloat) -> Path {
        var p = Path()
        let steps = innerRatio < 1 ? n * 2 : n
        for k in 0..<steps {
            let a = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / CGFloat(steps)
            let f = (innerRatio < 1 && k % 2 == 1) ? innerRatio : 1
            let pt = CGPoint(x: r.midX + cos(a) * r.width / 2 * f,
                             y: r.midY + sin(a) * r.height / 2 * f)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// A Unicode character as an exact outline, scaled to fill `rect`.
    ///
    /// CoreText hands back the real glyph outline — the same curves the type designer
    /// drew — so the ants trace the actual shape of a ★ or a ❄, not a box around it.
    /// Any font on the machine works, which makes every dingbat and ornament available
    /// as a mask without shipping a single asset.
    ///
    /// Returns nil for an empty string or a character the font has no glyph for; the
    /// caller falls back rather than showing an empty mask.
    static func glyphPath(_ text: String, fontName: String?, fitting rect: CGRect) -> Path? {
        guard let scalar = text.unicodeScalars.first, rect.width > 0, rect.height > 0 else { return nil }
        let font: CTFont = {
            if let fontName, !fontName.isEmpty {
                return CTFontCreateWithName(fontName as CFString, 100, nil)
            }
            return CTFontCreateUIFontForLanguage(.system, 100, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 100, nil)
        }()
        var utf16 = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count),
              let glyph = glyphs.first, glyph != 0,
              let cg = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }

        // Glyph space is y-up with an arbitrary origin; flip it and fit it to the frame.
        let g = cg.boundingBox
        guard g.width > 0, g.height > 0 else { return nil }
        let sx = rect.width / g.width, sy = rect.height / g.height
        var t = CGAffineTransform.identity
            .translatedBy(x: rect.minX, y: rect.minY + rect.height)
            .scaledBy(x: sx, y: -sy)
            .translatedBy(x: -g.minX, y: -g.minY)
        guard let fitted = cg.copy(using: &t) else { return nil }
        return Path(fitted)
    }

    // MARK: Editing

    /// Slide the whole mask, clamped so it can never be dragged off the canvas.
    /// This is the "grab the center to reposition" gesture.
    func moved(by delta: CGSize) -> CropMask {
        let b = bounds
        let dx = min(max(delta.width, -b.minX), 1 - b.maxX)
        let dy = min(max(delta.height, -b.minY), 1 - b.maxY)
        return CropMask(corners: corners.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    }

    /// ⌘ drag: move ONE corner and leave the other three where they are. The mask stops
    /// being a rectangle — corners go acute or obtuse — which is the distort Michael
    /// described as "the one you found."
    func movingCornerFreely(_ i: Int, to p: CGPoint) -> CropMask {
        var c = corners
        c[i] = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        return CropMask(corners: c)
    }

    /// Plain drag: the opposite corner stays locked and the shape stays a rectangle, so
    /// the two neighbours slide along their shared edges. Four degrees of freedom —
    /// every edge reachable, which is what the centered crop could never do.
    func resizingRectangle(_ i: Int, to p: CGPoint) -> CropMask {
        let anchor = corners[(i + 2) % 4]
        let px = min(max(p.x, 0), 1), py = min(max(p.y, 0), 1)
        var minX = min(anchor.x, px), maxX = max(anchor.x, px)
        var minY = min(anchor.y, py), maxY = max(anchor.y, py)
        if maxX - minX < Self.minSide { maxX = minX + Self.minSide }
        if maxY - minY < Self.minSide { maxY = minY + Self.minSide }
        (minX, maxX) = (min(minX, 1 - Self.minSide), min(maxX, 1))
        (minY, maxY) = (min(minY, 1 - Self.minSide), min(maxY, 1))
        return CropMask(rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    /// Locked-ratio drag: opposite corner still anchors, but the rectangle is forced back
    /// to `aspect` (width ÷ height, measured in PIXELS so a non-square canvas doesn't
    /// quietly skew a "Square" crop). The box grows to cover the drag rather than
    /// shrinking to fit inside it, which is what "gets larger or smaller depending on the
    /// distance between the selected grabber and its adjacent counterpart" describes.
    func resizingRatio(_ i: Int, to p: CGPoint, aspect: CGFloat, canvas: CGSize) -> CropMask {
        guard aspect > 0, canvas.width > 0, canvas.height > 0 else { return resizingRectangle(i, to: p) }
        let anchor = corners[(i + 2) % 4]
        let px = min(max(p.x, 0), 1), py = min(max(p.y, 0), 1)
        // Work in pixels so the ratio is a real ratio.
        let dxPx = abs(px - anchor.x) * canvas.width
        let dyPx = abs(py - anchor.y) * canvas.height
        var wPx = max(dxPx, dyPx * aspect)
        var hPx = wPx / aspect
        // Don't let the forced ratio push the mask off the canvas: shrink to the room
        // available in the drag's direction, keeping the ratio exact.
        let roomXPx = (px >= anchor.x ? 1 - anchor.x : anchor.x) * canvas.width
        let roomYPx = (py >= anchor.y ? 1 - anchor.y : anchor.y) * canvas.height
        let fit = min(1, min(roomXPx / max(wPx, 0.0001), roomYPx / max(hPx, 0.0001)))
        wPx *= fit; hPx *= fit
        var w = wPx / canvas.width, h = hPx / canvas.height
        w = max(w, Self.minSide); h = max(h, Self.minSide)
        let x = px >= anchor.x ? anchor.x : anchor.x - w
        let y = py >= anchor.y ? anchor.y : anchor.y - h
        return CropMask(rect: CGRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h))
    }
}

/// How a corner drag behaves — set by the mask's mode, overridden to `.free` by ⌘.
enum MaskCornerMode: Equatable {
    case free                 // every corner independent → quadrilateral
    case rectangle            // 90° corners, width and height independent
    case ratio(CGFloat)       // 90° corners, aspect locked (w ÷ h, in pixels)
}

/// A `Shape` wrapper so the mask can be handed to `MarchingAnts`, which is already
/// generic over any shape — it was written for exactly this ("the silhouette a lasso or
/// Cookie Cutter produced"). Nothing about the ants had to change to trace a quad.
struct CropMaskShape: Shape {
    let mask: CropMask
    func path(in rect: CGRect) -> Path {
        mask.silhouette(in: rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The four-cornered FRAME, as a `Shape` — the grab area for repositioning. Separate from
/// `CropMaskShape` because the thing you grab is the frame even when the thing you keep
/// is a star: hit-testing a star's actual points would leave most of the box dead.
struct CropMaskFrameShape: Shape {
    let mask: CropMask
    func path(in rect: CGRect) -> Path {
        mask.framePath(in: rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: - What you see

/// Dims everything outside the mask and traces its outline with marching ants.
///
/// The dim is one even-odd fill — canvas rect plus mask path — rather than the four
/// bands the rectangle-only version used, because a quadrilateral has no bands.
struct MaskOverlay: View {
    let mask: CropMask
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addPath(mask.silhouette(in: size))
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

            // The frame, faint, whenever the silhouette isn't the frame — otherwise a star
            // mask leaves its grabbers floating in space with nothing connecting them.
            if mask.form != .rectangle {
                CropMaskFrameShape(mask: mask)
                    .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: size.width, height: size.height)
            }

            MarchingAnts(shape: CropMaskShape(mask: mask))
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - What you grab

/// The mask's own grabbers. Deliberately the same 14pt visual / 30pt hit target the
/// Move box uses — Michael could not reliably grab a 14pt square sitting on a corner,
/// and the invisible 30pt target was the fix. Same problem here, same answer.
///
/// These handles move the MASK ONLY. The artwork is never touched, which is the whole
/// reason the mask became its own tool.
struct MaskBox: View {
    @Binding var mask: CropMask
    let size: CGSize
    /// Canvas pixel dimensions — needed so a locked ratio is honest on a non-square canvas.
    let canvasPixels: CGSize
    let mode: MaskCornerMode

    @State private var dragStart: CropMask?
    /// ⌘ is sampled ONCE at the start of a drag and held for its duration. Sampling every
    /// frame would let a Sticky-Keys release mid-drag flip the behaviour halfway through.
    @State private var freeOverride = false

    private let grabVisual: CGFloat = 14
    private let grabTarget: CGFloat = 30

    var body: some View {
        let pts = mask.points(in: size)
        ZStack(alignment: .topLeading) {
            // Interior — "you have to grab the center of the square or rectangle to
            // reposition the mask." Corners resize; only the inside moves.
            CropMaskFrameShape(mask: mask)
                .fill(Color.white.opacity(0.001))   // hit area, invisible
                .frame(width: size.width, height: size.height)
                .contentShape(CropMaskFrameShape(mask: mask))
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            let start = dragStart ?? mask
                            if dragStart == nil { dragStart = start }
                            mask = start.moved(by: CGSize(width: value.translation.width / size.width,
                                                          height: value.translation.height / size.height))
                        }
                        .onEnded { _ in dragStart = nil }
                )

            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: grabVisual, height: grabVisual)
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
                    .contentShape(Rectangle().size(width: grabTarget, height: grabTarget)
                        .offset(x: -(grabTarget - grabVisual) / 2, y: -(grabTarget - grabVisual) / 2))
                    .position(pts[i])
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = mask
                                    freeOverride = Self.commandHeld()
                                }
                                let p = CGPoint(x: value.location.x / size.width,
                                                y: value.location.y / size.height)
                                let effective: MaskCornerMode = freeOverride ? .free : mode
                                let base = dragStart ?? mask
                                switch effective {
                                case .free:
                                    mask = base.movingCornerFreely(i, to: p)
                                case .rectangle:
                                    mask = base.resizingRectangle(i, to: p)
                                case .ratio(let a):
                                    mask = base.resizingRatio(i, to: p, aspect: a, canvas: canvasPixels)
                                }
                            }
                            .onEnded { _ in dragStart = nil; freeOverride = false }
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Is ⌘ down right now? Sticky Keys LOCKS a double-pressed modifier, so this global
    /// read stays true across the whole drag — which is exactly why the flag is sampled
    /// at drag start and not continuously.
    static func commandHeld() -> Bool {
        #if os(macOS)
        return NSEvent.modifierFlags.contains(.command)
        #else
        return false
        #endif
    }
}

// MARK: - The Mask tool's inspector

/// Controls for the Mask tool. Deliberately mirrors the Crop section's vocabulary — the
/// same ratio presets, the same "Apply" language — because it is the same idea grown up.
/// The Move tool's Crop section is left in place and untouched; nothing was removed.
struct MaskInspector: View {
    @ObservedObject var document: ImageDocument

    /// Ratio presets, in Photos' order. `nil` = freeform.
    private static let ratios: [(String, CGFloat?)] = [
        ("Freeform", nil), ("Square", 1), ("16:9", 16.0 / 9), ("4:5", 4.0 / 5),
        ("5:7", 5.0 / 7), ("4:3", 4.0 / 3), ("3:5", 3.0 / 5), ("3:2", 3.0 / 2),
    ]

    /// A few characters worth having one tap away. Everything else is typable — any
    /// glyph in any installed font is a legal mask.
    private static let quickGlyphs = ["★", "♥", "●", "▲", "✚", "❄", "♠", "♣", "◆", "☾"]

    @State private var glyphText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mask").font(.system(size: 18)).bold()

            if document.cropMask == nil {
                Text("No mask. The mask marks what is KEPT — everything outside it dims, and Export trims to it.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                Button { addMask() } label: {
                    Label("Add Mask", systemImage: "square.dashed").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                shapeControls
                Divider()
                cornerControls
                Divider()
                Button(role: .destructive) { document.cropMask = nil } label: {
                    Label("Remove Mask", systemImage: "xmark.square.dashed").frame(maxWidth: .infinity)
                }
                Text("Drag a corner to resize. Hold ⌘ while dragging a corner to move that corner on its own. Drag inside the frame to reposition.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Shape

    @ViewBuilder private var shapeControls: some View {
        Text("Shape").font(.system(size: 18)).foregroundStyle(.secondary)
        Picker("Shape", selection: formBinding) {
            ForEach(MaskForm.pickable, id: \.self) { f in Text(f.label).tag(f) }
            Text("Character").tag(MaskForm.glyph(currentGlyph, fontName: nil))
        }
        .pickerStyle(.menu)
        .labelsHidden()

        if case .polygon = document.cropMask?.form {
            sidesStepper(label: "Sides")
        }
        if case .star = document.cropMask?.form {
            sidesStepper(label: "Points")
        }
        if case .glyph = document.cropMask?.form {
            HStack {
                TextField("Character", text: $glyphText)
                    .font(.system(size: 18))
                    .frame(width: 90)
                    .onChange(of: glyphText) { _, new in
                        guard let c = new.first else { return }
                        document.cropMask?.form = .glyph(String(c), fontName: nil)
                    }
            }
            // A row of ready-made glyphs, because typing ❄ is harder than tapping it.
            HStack(spacing: 6) {
                ForEach(Self.quickGlyphs, id: \.self) { g in
                    Button(g) {
                        glyphText = g
                        document.cropMask?.form = .glyph(g, fontName: nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Any character from any installed font works — the mask uses the real glyph outline, so the marching ants trace its exact shape.")
                .font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func sidesStepper(label: String) -> some View {
        Stepper("\(label)  \(document.cropMask?.polygonSides ?? 6)",
                value: Binding(get: { document.cropMask?.polygonSides ?? 6 },
                               set: { document.cropMask?.polygonSides = max(3, min($0, 12)) }),
                in: 3...12)
            .font(.system(size: 18))
    }

    // MARK: Corners

    @ViewBuilder private var cornerControls: some View {
        Text("Corners").font(.system(size: 18)).foregroundStyle(.secondary)
        Picker("Aspect", selection: Binding(get: { document.maskRatio }, set: { document.maskRatio = $0 })) {
            ForEach(Self.ratios, id: \.0) { name, value in Text(name).tag(value) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .disabled(document.maskFreeCorners)

        Toggle("Free corners (any angle)", isOn: Binding(get: { document.maskFreeCorners },
                                                        set: { document.maskFreeCorners = $0 }))
            .font(.system(size: 18))
        Text(document.maskFreeCorners
             ? "Every corner moves on its own — the mask can be any four-sided shape."
             : "Corners stay square. The opposite corner stays locked while you drag.")
            .font(.system(size: 18)).foregroundStyle(.secondary)
    }

    // MARK: Plumbing

    private var currentGlyph: String {
        if case .glyph(let c, _) = document.cropMask?.form { return c }
        return glyphText.isEmpty ? "★" : String(glyphText.prefix(1))
    }

    private var formBinding: Binding<MaskForm> {
        Binding(get: { document.cropMask?.form ?? .rectangle },
                set: { newValue in
                    if case .glyph = newValue, glyphText.isEmpty { glyphText = "★" }
                    document.cropMask?.form = newValue
                })
    }

    /// A new mask starts at 80% of the canvas, centred — the same place the old Crop
    /// section started, so nothing about the first moment feels different. Everything
    /// after that first moment is what changed.
    private func addMask() {
        document.cropMask = CropMask(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
    }
}
