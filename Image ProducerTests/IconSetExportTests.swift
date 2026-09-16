//
//  IconSetExportTests.swift
//  Image ProducerTests
//
//  Drives the REAL export path. `IconSetExport.exportInteractively` is
//  `build(from:)` plus a save panel, so `build(from:)` is production, not a stand-in.
//
//  Written 2026-09-15 to check his rule on an actual PNG rather than by inspection:
//  clear resolves to WHITE in an icon set, an absent floor resolves the same way, and
//  neither file carries an alpha channel — "app store connect rejects a photo that has
//  an alpha layer even with no clear pixels."
//

import Testing
import AppKit
@testable import Image_Producer

@MainActor
struct IconSetExportTests {

    // MARK: Helpers

    /// Decode a PNG and report what actually came out — channel presence and one pixel.
    private func inspect(_ data: Data) -> (hasAlpha: Bool, rgba: (Int, Int, Int, Int))? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let alphaInfo = cg.alphaInfo
        let hasAlpha = !(alphaInfo == .none || alphaInfo == .noneSkipLast || alphaInfo == .noneSkipFirst)

        // Sample the top-left corner, which is floor and nothing else.
        var px: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (hasAlpha, (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3])))
    }

    private func documentWithDefaultFloors() -> ImageDocument {
        ImageDocument.newDefault()
    }

    // MARK: The rule

    @Test("A CLEAR floor exports as opaque white, with no alpha channel")
    func clearFloorBecomesWhite() throws {
        // newDefault() ships Light and Dark with fillHex == nil — i.e. both clear.
        let doc = documentWithDefaultFloors()
        let files = IconSetExport.build(from: doc)

        let light = try #require(files[IconSetExport.lightFile], "no light icon produced")
        let dark  = try #require(files[IconSetExport.darkFile],  "no dark icon produced")

        for (name, data) in [("light", light), ("dark", dark)] {
            let out = try #require(inspect(data), "\(name): could not decode PNG")
            #expect(out.hasAlpha == false, "\(name): carries an alpha channel — ASC rejects this")
            #expect(out.rgba.0 == 255 && out.rgba.1 == 255 && out.rgba.2 == 255,
                    "\(name): floor is \(out.rgba), expected white — this is the old black bug")
        }
    }

    @Test("An ABSENT dark floor exports the same as a cleared one")
    func missingFloorBecomesWhite() throws {
        let doc = documentWithDefaultFloors()
        // Delete the Dark layer outright — the other half of the same gesture.
        doc.layers.removeAll {
            if case .background(.dark, _) = $0.role { return true }
            return false
        }
        #expect(!doc.layers.contains {
            if case .background(.dark, _) = $0.role { return true }
            return false
        }, "precondition: the dark floor should be gone")

        let files = IconSetExport.build(from: doc)
        let dark = try #require(files[IconSetExport.darkFile], "no dark icon produced")
        let out  = try #require(inspect(dark), "could not decode PNG")

        #expect(out.hasAlpha == false, "carries an alpha channel — ASC rejects this")
        #expect(out.rgba.0 == 255 && out.rgba.1 == 255 && out.rgba.2 == 255,
                "absent floor gave \(out.rgba), expected white")
    }

    @Test("A FILLED floor is untouched — the change must not break what worked")
    func filledFloorsAreUnchanged() throws {
        let doc = documentWithDefaultFloors()
        for i in doc.layers.indices {
            if case .background(.light, _) = doc.layers[i].role {
                doc.layers[i].setBackgroundFill("#FF0000")     // red
            }
            if case .background(.dark, _) = doc.layers[i].role {
                doc.layers[i].setBackgroundFill("#0000FF")     // blue
            }
        }
        let files = IconSetExport.build(from: doc)
        // Split rather than nested: #require inside #require is a recursive macro expansion
        // and does not compile.
        let lightData = try #require(files[IconSetExport.lightFile])
        let darkData  = try #require(files[IconSetExport.darkFile])
        let light = try #require(inspect(lightData))
        let dark  = try #require(inspect(darkData))

        #expect(light.rgba.0 > 200 && light.rgba.1 < 60 && light.rgba.2 < 60,
                "light floor should still be red, got \(light.rgba)")
        #expect(dark.rgba.2 > 200 && dark.rgba.0 < 60 && dark.rgba.1 < 60,
                "dark floor should still be blue, got \(dark.rgba)")
        #expect(light.hasAlpha == false && dark.hasAlpha == false)
    }
}
