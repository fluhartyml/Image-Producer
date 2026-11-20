//
//  AppStoreUniversalImage.swift
//  Image Producer
//
//  The App Store Connect universal image (5244 × 2950), built from the icon in one pass and
//  written BESIDE the icon set on every icon-set export.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  REM 2026-11-20 — HIS ASK, after building CryoTunes' universal image by hand:
//  "do you think we can add the whole workflow we just did to automatically take the users
//  icon make the huge frosted glass and auto skew a sharp icon then export to a supporting
//  folder or ride inside the icon set?" → "yes build it beside the icon set".
//
//  BESIDE, NOT INSIDE: anything inside Assets.xcassets ships in the app. This image is for
//  App Store Connect only, so it gets its own folder next to AppIcon.appiconset.
//
//  THE RECIPE IS EXACTLY THE ONE HE SIGNED OFF ON BY HAND (template layers hidden):
//    1. Backdrop — the icon at 1024, Gaussian Blur 36.8 px ("the blur is fine"), then Fill
//       to the canvas (aspect-fill, centered). Blur is at 1024 because that is where his
//       Filter ▸ Gaussian Blur ran: on the layer's own pixels, before the Fill scaled it.
//    2. Tile — the icon at 940 px, App Icon shape (continuous corners, 22.37 %), centered
//       at x 2622, y 1145 from the top: the middle of Apple's art-safe box as he placed it.
//    3. Tilt -8° (his "askew the icon angle at a shallow angle"). Same sign as the Move
//       tool's Rotation box, so -8 here looks like -8 there. The two corners that cross
//       the safe box are on purpose — his: "the two corners that fall outside the safe
//       zone will be cropped off in an artistic way".
//    4. No alpha channel — App Store Connect art, flattened like the icon set.
//
//  LIGHT AND DARK: both are written, from the same Light/Dark floors the icon set uses,
//  so the image always matches the icon it ships beside. He picks one in ASC.
//  ─────────────────────────────────────────────────────────────────────────────
//

import Foundation
import SwiftUI
import CoreImage
import ImageIO

@MainActor
enum AppStoreUniversalImage {

    static let folderName = "App Store Universal Image"
    static let width = 5244
    static let height = 2950

    static let lightFile = "app-store-universal-light-5244x2950.png"
    static let darkFile  = "app-store-universal-dark-5244x2950.png"

    // His hand-built values, 2026-11-20.
    static let blurRadiusAt1024 = 36.8
    static let tileSide: CGFloat = 940
    static let tileCenterFromTop = CGPoint(x: 2622, y: 1145)
    static let tiltDegrees: CGFloat = -8

    /// Both images, keyed by file name. Empty when the icon could not be rendered.
    static func build(from document: ImageDocument) -> [String: Data] {
        var files: [String: Data] = [:]
        let px = IconSetExport.px
        for (appearance, name) in [(IconAppearance.light, lightFile), (.dark, darkFile)] {
            let square = IconSetExport.widened(IconSetExport.render(appearance, of: document), width: px, height: px)
            guard let iconPNG = ContentView.renderIconPNG(document: square, px: px),
                  let icon = cgImage(from: iconPNG),
                  let out = compose(icon: icon) else { continue }
            files[name] = out
        }
        return files
    }

    /// Backdrop + tilted tile on an opaque 5244 × 2950 canvas, as PNG data with no alpha.
    static func compose(icon: CGImage) -> Data? {
        let W = CGFloat(width), H = CGFloat(height)
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high

        // 1. Backdrop: blur at icon size, then aspect-fill the canvas.
        let blurred = AdjustmentEngine.gaussianBlur(icon, radius: blurRadiusAt1024, mask: nil) ?? icon
        let iw = CGFloat(blurred.width), ih = CGFloat(blurred.height)
        let fill = max(W / iw, H / ih)
        let bw = iw * fill, bh = ih * fill
        ctx.draw(blurred, in: CGRect(x: (W - bw) / 2, y: (H - bh) / 2, width: bw, height: bh))

        // 2–3. Tile: CG is y-up, so the center flips, and a y-down angle of -8° (counter-
        // clockwise on screen, as in the Move tool) is +8° here.
        let center = CGPoint(x: tileCenterFromTop.x, y: H - tileCenterFromTop.y)
        let tile = CGRect(x: -tileSide / 2, y: -tileSide / 2, width: tileSide, height: tileSide)
        let shape = RoundedRectangle(cornerRadius: tileSide * 0.2237, style: .continuous).path(in: tile).cgPath
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -tiltDegrees * .pi / 180)
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(icon, in: tile)
        ctx.restoreGState()

        // 4. Encode — the context has no alpha, so neither does the PNG.
        guard let flat = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, flat, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private static func cgImage(from png: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
