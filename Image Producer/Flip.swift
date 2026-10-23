//
//  Flip.swift
//  Image Producer
//
//  FLIP — the last unbuilt piece of the Move / Transform umbrella (DeveloperNotes,
//  "MOVE / TRANSFORM … SKEW · DISTORT · FLIP"). Built 2026-10-23 at Michael's word:
//  "build flip and go over with me how to use it", after he wanted to mirror the
//  background of his Lab A wallpaper and found the app could not.
//
//  // REM: NOTHING IS RASTERIZED. His rule (2026-10-03): "no rasterization please unless
//  // specifically asked to by the user." The first cut (build 341) flipped a render of
//  // the layer, which turned text into pixels — he said "yes fix it" the same morning.
//  // Now each element flips in its OWN kind:
//  //   • text / symbol → the transform's mirror flags; drawn mirrored, still typeable;
//  //   • image / pixels → their own pixels are mirrored (they were pixels already);
//  //   • live effects (glow, shadow, gradient…) are untouched and follow the art.
//
//  // REM: Follows the NON-DESTRUCTIVE RULE (GlowTool `apply`). Undo is OFF on purpose
//  // (UndoManager crashed this app), so layering IS the undo — the untouched original
//  // goes directly BELOW, hidden, and the flipped copy sits on top keeping the
//  // original's id, so the selection stays on it.
//
//  // REM: Flipping a ROTATED layer mirrors the whole thing about its centre, which is
//  // the same as flipping the art and turning the angle the other way (θ → −θ).
//
//  // REM: Where the mirror line runs. Text and symbols fill their own box, so the
//  // layer's centre is the art's centre. A picture with rotation 0 mirrors about its
//  // VISIBLE ART — a Remove Background cutout keeps the full canvas size, and mirroring
//  // the whole canvas would throw the subject to the other side. A full-canvas
//  // background's art IS the canvas, so it mirrors about the canvas centre.
//

import SwiftUI
import CoreGraphics
import ImageIO

enum FlipAxis: String {
    case horizontal, vertical

    /// The name Preview and Photos use for the same command.
    var title: String { self == .horizontal ? "Flip Horizontal" : "Flip Vertical" }
}

extension ImageDocument {

    /// Flip the layer at `i` across `axis`. Returns false (and says why on the status
    /// line) when nothing could be flipped; the document is then unchanged.
    @discardableResult
    @MainActor func flipLayer(at i: Int, axis: FlipAxis) -> Bool {
        guard layers.indices.contains(i) else { return false }
        let source = layers[i]
        // A solid background layer has no picture to turn over.
        guard case .content = source.role, !source.elements.isEmpty else {
            say("Flip works on picture, text and symbol layers", kind: .warning)
            return false
        }

        // Build every flipped element first. Fail-safe: if any picture can't be
        // flipped, change nothing at all.
        let keepsArtInPlace = source.transform.rotationDegrees == 0
        var elements: [LayerElement] = []
        var flipsTransform = false
        for element in source.elements {
            var e = element
            switch element.content {
            case .text, .symbol:
                flipsTransform = true
            case .image(var image):
                guard let png = Self.mirroredPNG(image.pngData, across: axis,
                                                 aboutArt: keepsArtInPlace) else {
                    say("Flip failed — the picture could not be read", kind: .warning)
                    return false
                }
                image.pngData = png
                e.content = .image(image)
            case .pixels(var pixels):
                // A pixel layer fills the canvas with no rotation: always about its art.
                guard let png = Self.mirroredPNG(pixels.pngData, across: axis, aboutArt: true) else {
                    say("Flip failed — the picture could not be read", kind: .warning)
                    return false
                }
                pixels.pngData = png
                e.content = .pixels(pixels)
            }
            elements.append(e)
        }

        captureHistoryBaselineIfNeeded()

        // The original, exactly as it was, hidden underneath. Fresh id — it is a second
        // layer now. Unlinked, so it stays where it was.
        var original = source
        original.id = UUID()
        original.isVisible = false
        original.linkGroup = nil

        // Naming follows Apply and Move: strip an earlier "(Flipped)" / "(Flipped n)" so
        // flipping twice numbers instead of compounding. The suffix is a LABEL
        // (`ImageLayer.splitLabel`), so a text layer stays linked to its words.
        var base = source.name
        if let r = base.range(of: #" \(Flipped(?: \d+)?\)$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }
        let taken = Set(layers.map(\.name))
        func candidate(_ k: Int) -> String { k == 1 ? "\(base) (Flipped)" : "\(base) (Flipped \(k))" }
        var n = 1
        while taken.contains(candidate(n)) { n += 1 }

        var t = source.transform
        if flipsTransform {
            switch axis {
            case .horizontal: t.mirrorX = !(t.mirrorX ?? false)
            case .vertical:   t.mirrorY = !(t.mirrorY ?? false)
            }
        }
        if t.rotationDegrees != 0 { t.rotationDegrees = -t.rotationDegrees }
        // A flip is not a move: don't let linked layers follow it (LayerLink).
        if source.linkGroup != nil, t != source.transform { skipLinkFollowOnce = true }

        layers[i].name = candidate(n)
        layers[i].elements = elements
        layers[i].transform = t
        layers[i].isVisible = true

        let flippedID = layers[i].id
        layers.insert(original, at: i)    // directly BELOW the flipped copy

        recordHistory(toolID: Tool.move.rawValue,
                      groupTitle: Tool.move.title,
                      actionLabel: "\(axis.title) — \(candidate(n))",
                      layerID: flippedID)
        say("\(axis.title) — the original is hidden underneath")
        return true
    }

    /// PNG bytes mirrored across `axis`. `aboutArt` puts the mirror line through the
    /// middle of the visible pixels; otherwise through the middle of the picture.
    nonisolated static func mirroredPNG(_ data: Data, across axis: FlipAxis, aboutArt: Bool) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let whole = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        // A fully transparent picture has nothing to move; mirror it whole.
        let box = aboutArt ? (opaquePixelBox(of: cg) ?? whole) : whole
        guard let out = mirrored(cg, across: axis, about: box) else { return nil }
        return pngData(from: out)
    }

    /// The box around every pixel that is at least faintly visible, in pixel
    /// coordinates with a TOP-LEFT origin (row 0 = the picture's top). nil if empty.
    nonisolated static func opaquePixelBox(of cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // REM: the bitmap's memory runs TOP-DOWN (see LayerArtBounds "NO Y FLIP") —
        // row 0 here is the picture's top, so these rows are already top-left.
        let floor: UInt8 = 8   // same alpha floor as LayerArtBounds
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where bytes[row + x * 4 + 3] >= floor {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// `cg` mirrored across `axis`, the mirror line through the middle of `box`
    /// (top-left pixel coordinates). Same pixel size as `cg`, transparent elsewhere.
    nonisolated static func mirrored(_ cg: CGImage, across axis: FlipAxis, about box: CGRect) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        switch axis {
        case .horizontal:
            // x' = (minX + maxX) − x. Left/right is the same in either origin.
            ctx.translateBy(x: box.minX + box.maxX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .vertical:
            // CGContext is bottom-left, the box is top-left: y_cg = h − y_top, so the
            // box's top+bottom in context space is 2h − (minY + maxY).
            ctx.translateBy(x: 0, y: CGFloat(2 * h) - (box.minY + box.maxY))
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
