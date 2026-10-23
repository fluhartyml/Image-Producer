//
//  Flip.swift
//  Image Producer
//
//  FLIP — the last unbuilt piece of the Move / Transform umbrella (DeveloperNotes,
//  "MOVE / TRANSFORM … SKEW · DISTORT · FLIP"). Built 2026-10-23 at Michael's word:
//  "build flip and go over with me how to use it", after he wanted to mirror the
//  background of his Lab A wallpaper and found the app could not.
//
//  // REM: Flip follows the NON-DESTRUCTIVE RULE (GlowTool `apply`): it never mutates a
//  // layer in place. Undo is OFF on purpose (UndoManager crashed this app), so layering
//  // IS the undo — the untouched original goes directly BELOW, hidden, and the flipped
//  // copy sits on top with the original's id, so the selection stays on it.
//
//  // REM: It flips the layer AS IT LOOKS — the same render Apply uses, so a glow, shadow
//  // or text all flip with it. The catch is the same as Apply's: the result is pixels,
//  // so a flipped text layer is no longer typeable. The hidden original still is.
//
//  // REM: The mirror line runs through the middle of the layer's VISIBLE ART, not the
//  // middle of the canvas — so the art flips where it stands instead of jumping to the
//  // other side. A full-canvas layer (a background) has its art box = the canvas, so it
//  // mirrors about the canvas centre, which is what he asked for.
//

import SwiftUI
import CoreGraphics

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
        guard case .content = source.role else {
            say("Flip works on picture and text layers, not a solid background", kind: .warning)
            return false
        }
        // Fail-safe: if the render or the art box fails, change nothing.
        guard let cg = renderLayerImage(source, in: self) else {
            say("Flip failed — the layer could not be rendered", kind: .warning)
            return false
        }
        guard let box = Self.opaquePixelBox(of: cg) else {
            say("This layer is empty — nothing to flip", kind: .warning)
            return false
        }
        guard let flipped = Self.mirrored(cg, across: axis, about: box),
              let png = pngData(from: flipped) else {
            say("Flip failed — the layer could not be rendered", kind: .warning)
            return false
        }

        captureHistoryBaselineIfNeeded()

        // The original, exactly as it was (live effects and all), hidden underneath.
        // Fresh id — it is a second layer now. Unlinked, so it stays where it was.
        var original = source
        original.id = UUID()
        original.isVisible = false
        original.linkGroup = nil

        // Naming follows Apply and Move: strip an earlier "(Flipped)" / "(Flipped n)" so
        // flipping twice numbers instead of compounding.
        var base = source.name
        if let r = base.range(of: #" \(Flipped(?: \d+)?\)$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }
        let taken = Set(layers.map(\.name))
        func candidate(_ k: Int) -> String { k == 1 ? "\(base) (Flipped)" : "\(base) (Flipped \(k))" }
        var n = 1
        while taken.contains(candidate(n)) { n += 1 }

        layers[i].name = candidate(n)
        layers[i].setImage(png)
        layers[i].transform = coveringTransform(forPNG: png)
        // Baked into the pixels, exactly as Apply clears them.
        layers[i].glow = nil
        layers[i].shadow = nil
        layers[i].opacity = 1.0
        layers[i].greenKey = nil
        layers[i].gradient = nil
        layers[i].isVisible = true
        // A text layer names itself from its words; left linked, the next keystroke
        // would wipe the "(Flipped)" label off a layer that is pixels now.
        layers[i].nameLinkedToText = false

        let flippedID = layers[i].id
        layers.insert(original, at: i)    // directly BELOW the flipped copy

        recordHistory(toolID: Tool.move.rawValue,
                      groupTitle: Tool.move.title,
                      actionLabel: "\(axis.title) — \(candidate(n))",
                      layerID: flippedID)
        say("\(axis.title) — the original is hidden underneath")
        return true
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
