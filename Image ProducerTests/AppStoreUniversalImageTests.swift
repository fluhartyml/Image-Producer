//
//  AppStoreUniversalImageTests.swift
//  Image ProducerTests
//
//  REM 2026-11-20 — his "yes build it beside the icon set". The universal image must come
//  out 5244 × 2950 with no alpha channel (App Store Connect art), the backdrop must reach
//  every edge (no black bars from a missed Fill), and the tile must sit where he put it.
//

import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import Image_Producer

@MainActor
struct AppStoreUniversalImageTests {

    /// A 1024 test icon: dark blue square with a white bar in the middle.
    private func testIcon() -> CGImage {
        let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.15, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 462, y: 200, width: 100, height: 624))
        return ctx.makeImage()!
    }

    @Test func composesFullSizeOpaqueImage() throws {
        let data = try #require(AppStoreUniversalImage.compose(icon: testIcon()))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let cg = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(cg.width == 5244 && cg.height == 2950)
        let alpha = cg.alphaInfo
        #expect(alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst, "alpha: \(alpha.rawValue)")

        // Corners are backdrop, not black: the blurred icon was filled to every edge.
        let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                            bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func blue(_ x: Int, _ yFromTop: Int) -> UInt8 { px[(yFromTop * cg.width + x) * 4 + 2] }
        for (x, y) in [(2, 2), (5241, 2), (2, 2947), (5241, 2947)] {
            #expect(blue(x, y) > 40, "corner \(x),\(y) is black")
        }
        // The tile's white bar crosses its center.
        #expect(px[(1145 * cg.width + 2622) * 4] > 200, "tile center is not the icon's white bar")

        // Leave a copy where a person can look at it.
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("app-store-universal-test.png")
        try data.write(to: out)
        print("UNIVERSAL_TEST_PNG \(out.path)")
    }
}
