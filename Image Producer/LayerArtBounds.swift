//
//  LayerArtBounds.swift
//  Image Producer
//
//  Where the ART actually is inside a layer — as opposed to how big the layer
//  declares itself to be.
//
//  Michael, 2026-08-21, working on the Lighthouse icon: "the selection was the
//  full layer size and not the lighthouse pixels." That is fix-list items C and
//  D in one sentence. A layer's transform describes a `scale`-sized SQUARE, and
//  the Move box was drawn from that square — so a 1024x1024 cutout holding one
//  small lighthouse put its four corner grabbers exactly on the canvas corners,
//  where half of each grabber is off-canvas and there is nothing left to hit.
//  The art sat in the middle, untouched by any handle.
//
//  So: find the layer's opaque pixels and report their box. Everything the Move
//  overlay draws hangs off that instead.
//
//  Cheap on purpose. The PNG is decoded ONCE into a small square (opaque bounds
//  do not need 1024 of resolution to place a 14pt grabber), the answer is cached
//  by the raster's identity, and every later frame is a dictionary hit. A view
//  body can call this without thinking about it.
//

import Foundation
import CoreGraphics
import ImageIO

enum LayerArtBounds {

    /// Scan resolution. 256 puts the box within ~4/1024 of the true edge, which is
    /// far finer than a finger or a pointer, and costs 65k byte reads instead of 1M.
    private static let probe = 256

    /// A pixel counts as art at alpha >= this. Anti-aliased edges fade to nothing,
    /// and including a 2%-opaque halo would grow the box past what anyone can see.
    private static let alphaFloor: UInt8 = 8

    /// Cached answers, keyed by the raster's byte count + a hash of its bytes.
    /// Rasters are immutable once written (every edit makes a NEW layer), so a hit
    /// can never be stale for a different picture.
    nonisolated(unsafe) private static var cache: [Int: CGRect] = [:]
    private static let lock = NSLock()

    /// The opaque box of `png`, in the coordinate space of the SQUARE the canvas
    /// draws that layer into — 0…1, top-left origin, (0.5, 0.5) at the square's
    /// centre.
    ///
    /// Two things are folded in together, because the caller needs the product of
    /// both and getting one without the other is a bug waiting to happen:
    ///   1. `.scaledToFit()` inside a square — a non-square picture letterboxes,
    ///      so its drawn footprint is already smaller than the square.
    ///   2. the transparent margin inside the picture itself.
    ///
    /// Returns nil when the picture can't be decoded or is fully transparent — the
    /// caller falls back to the whole square, which is today's behaviour.
    static func unitRect(forPNG png: Data) -> CGRect? {
        let key = png.count &* 31 &+ png.hashValue
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              cg.width > 0, cg.height > 0,
              let opaque = opaqueUnitRect(of: cg) else { return nil }

        // Where `.scaledToFit()` lands the picture inside the unit square.
        let aspect = Double(cg.width) / Double(cg.height)
        let fitW = aspect >= 1 ? 1.0 : aspect
        let fitH = aspect >= 1 ? 1.0 / aspect : 1.0
        let fit = CGRect(x: (1 - fitW) / 2, y: (1 - fitH) / 2, width: fitW, height: fitH)

        let result = CGRect(x: fit.minX + opaque.minX * fit.width,
                            y: fit.minY + opaque.minY * fit.height,
                            width: opaque.width * fit.width,
                            height: opaque.height * fit.height)

        lock.lock()
        if cache.count > 64 { cache.removeAll() }   // a project's worth, then start over
        cache[key] = result
        lock.unlock()
        return result
    }

    /// The opaque box WITHIN the picture, 0…1 of the picture's own width/height,
    /// top-left origin. nil if nothing clears `alphaFloor`.
    private static func opaqueUnitRect(of cg: CGImage) -> CGRect? {
        let w = probe, h = probe
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress,
                                      width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where bytes[row + x * 4 + 3] >= alphaFloor {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // The context draws with a bottom-left origin, so flip Y back to the
        // top-left space every caller here uses. +1 on the far edge because the
        // box has to CONTAIN the last lit pixel, not stop at its near corner.
        let x0 = Double(minX) / Double(w)
        let x1 = Double(maxX + 1) / Double(w)
        let y0 = 1 - Double(maxY + 1) / Double(h)
        let y1 = 1 - Double(minY) / Double(h)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

extension ImageLayer {
    /// The layer's art box inside its own transform square (0…1, top-left origin),
    /// or nil when there is nothing raster to measure.
    ///
    /// Raster content only — pixels and imported images. A symbol or a text glyph
    /// also has a true drawn box, but measuring those means rendering them, and a
    /// text layer already has its own resize behaviour in the Move overlay. Those
    /// keep the whole-square box they have today rather than getting a guess.
    var artUnitRect: CGRect? {
        for element in elements {
            switch element.content {
            case .pixels(let p): return LayerArtBounds.unitRect(forPNG: p.pngData)
            case .image(let i):  return LayerArtBounds.unitRect(forPNG: i.pngData)
            default:             continue
            }
        }
        return nil
    }
}
