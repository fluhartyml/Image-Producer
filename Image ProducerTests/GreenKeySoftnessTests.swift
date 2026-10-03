//
//  GreenKeySoftnessTests.swift
//  Image ProducerTests
//
//  2026-10-03. Keying a sunflower under a white spotlight on black: the swiss cheese
//  was right, the beam's soft falloff came out as a ragged cut-out. These pin the
//  three promises of Softness — 0 is the old hard key, the band fades instead of
//  cutting, and what is left is unmixed so it recomposites to the original over the
//  key color. Plus: files saved before Softness existed still open.
//

import Testing
import Foundation
import CoreGraphics
@testable import Image_Producer

struct GreenKeySoftnessTests {

    /// A 1-pixel-tall strip of opaque grays.
    private func strip(_ grays: [UInt8]) -> CGImage {
        var bytes: [UInt8] = []
        for g in grays { bytes += [g, g, g, 255] }
        return cgImage(fromRGBA: bytes, w: grays.count, h: 1)!
    }

    private func pixels(_ cg: CGImage) -> [(r: Int, a: Int)] {
        let (b, w, _) = rgbaBytes(from: cg)!
        return (0..<w).map { (Int(b[$0 * 4]), Int(b[$0 * 4 + 3])) }
    }

    private let black: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)

    @Test func softnessZeroIsTheOldHardKey() {
        let src = strip([0, 10, 24, 25, 60, 200])
        let hard = pixels(colorMaskedImage(src, target: black, tolerance: 24, contiguous: false)!)
        let soft0 = pixels(colorKeyedImage(src, target: black, tolerance: 24, softness: 0)!)
        #expect(hard.map(\.a) == soft0.map(\.a))
        #expect(hard.map(\.r) == soft0.map(\.r))
    }

    @Test func theBandFadesInsteadOfCutting() {
        // tolerance 24, softness 100: 24 clears, 124+ untouched, between ramps.
        let out = pixels(colorKeyedImage(strip([24, 49, 74, 99, 124, 200]),
                                         target: black, tolerance: 24, softness: 100)!)
        #expect(out[0].a == 0)
        #expect(out[1].a > 0 && out[1].a < out[2].a && out[2].a < out[3].a && out[3].a < 255)
        #expect(out[4].a == 255 && out[5].a == 255)
    }

    @Test func unmixedPixelsRecompositeOverTheKeyColor() {
        // Over black, a premultiplied pixel composites to its own stored color — so the
        // stored red must be the ORIGINAL gray, within rounding.
        let grays: [UInt8] = [40, 60, 90, 110]
        let out = pixels(colorKeyedImage(strip(grays), target: black, tolerance: 24, softness: 100)!)
        for (g, p) in zip(grays, out) {
            #expect(abs(p.r - Int(g)) <= 2, "gray \(g) came back \(p.r) at alpha \(p.a)")
        }
    }

    @Test func oldFilesWithoutSoftnessStillOpen() throws {
        let json = ##"{"isEnabled":true,"colorHex":"#000000","tolerance":30}"##.data(using: .utf8)!
        let key = try JSONDecoder().decode(LayerGreenKey.self, from: json)
        #expect(key.tolerance == 30 && key.softness == 0 && key.colorHex == "#000000")
    }
}
