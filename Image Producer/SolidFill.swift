//
//  SolidFill.swift
//  Image Producer
//
//  Whole-layer fill for CONTENT layers.
//
//  Michael, 2026-08-22, filling a banner's Background layer with white:
//    "should not be constrained to light or dark layer only"
//    "i cant tap the paint drip choose a color and then tap a (blank) area on the canvas"
//
//  The Paint Bucket had two behaviours — a solid fill for Light/Dark background layers,
//  and a flood fill bounded by lines for a content layer WITH art. An empty content
//  layer matched neither, so both the button and the canvas tap did nothing. Tapping a
//  blank canvas with a bucket and getting nothing is not a rule anyone would guess;
//  it is the tool failing to behave the way it looks.
//
//  A background layer stores a colour. A content layer holds a raster, so the fill has
//  to be rendered — and, critically, the layer's transform has to be told the raster's
//  ASPECT. `contentAspect` defaults to nil, meaning "square", so a 2:1 fill dropped
//  into a 2:1 canvas was laid out as if it were square and came out at half size.
//  That is what Michael saw: a white rectangle floating in the middle of his banner.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension ImageDocument {

    /// Fills the layer at `index` edge to edge with one colour.
    ///
    /// Works for a background layer (stores the hex) or a content layer (renders a
    /// raster at canvas size and sets the transform so it covers the canvas exactly).
    /// Returns false only if the raster could not be made.
    @discardableResult
    func fillLayerSolid(at index: Int, cgColor: CGColor) -> Bool {
        guard layers.indices.contains(index) else { return false }

        if layers[index].backgroundRole != nil {
            layers[index].setBackgroundFill(cgColor.hexString8 ?? "#FFFFFF")
            return true
        }

        guard case .content = layers[index].role else { return false }
        guard let png = Self.solidPNG(cgColor: cgColor, size: canvasPixelSize) else { return false }

        layers[index].setImage(png)

        var t = layers[index].transform
        t.contentAspect = canvasAspect
        t.scale = coverScale
        t.center = CGPoint(x: 0.5, y: 0.5)
        t.rotationDegrees = 0
        layers[index].transform = t
        return true
    }

    /// Width ÷ height of the canvas.
    var canvasAspect: Double {
        canvasHeight == 0 ? 1 : Double(canvasWidth) / Double(canvasHeight)
    }

    /// The `transform.scale` that makes canvas-shaped content cover the canvas exactly.
    ///
    /// WHY THIS IS NOT SIMPLY 1.0, which is the assumption that produced the half-size
    /// fill Michael found: layer geometry measures everything as a fraction of
    /// `min(canvasWidth, canvasHeight)` — the SHORT edge. On a square canvas the short
    /// edge IS the canvas, so `scale = 1.0` covers it and the assumption survives. On his
    /// 1024×512 banner the unit is 512, so 1.0 covers only half the width, and the fill
    /// rendered at half size in the middle of the canvas.
    ///
    /// Working it through: content is drawn `contentSize × ref` points, and for a
    /// landscape aspect `a`, `contentSize.width == scale`. To draw the full width,
    /// `scale × ref == canvasWidth`, so `scale == canvasWidth / ref == a`. Portrait is
    /// the mirror image, giving `1/a`. Both collapse to the long-to-short ratio.
    ///
    /// This uses the model's real unit rather than resizing anything after the fact —
    /// Michael's objection to the quick fix was exactly that, and he was right.
    ///
    /// The deeper item is still open: `scale` READING as "fraction of the canvas" when it
    /// means "fraction of the short edge" is a trap, and correcting it means migrating
    /// every saved document so existing art does not move. Not today's job.
    var coverScale: Double {
        let a = canvasAspect
        return max(a, 1 / max(a, 0.000_001))
    }

    /// A flat rectangle of one colour, as PNG data.
    static func solidPNG(cgColor: CGColor, size: CGSize) -> Data? {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cg = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

extension CGColor {
    /// "#RRGGBB" in sRGB, for the background layer's stored fill.
    var hexString8: String? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = converted(to: space, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
