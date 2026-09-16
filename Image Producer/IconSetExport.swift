//
//  IconSetExport.swift
//  Image Producer
//
//  Export a drop-in `AppIcon.appiconset` — the PNGs AND a valid Contents.json —
//  so the whole thing drags straight into Assets.xcassets and is done. A folder of
//  loose PNGs still leaves you dragging files into wells, and the wells were always
//  the actual work.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  2026-09-13 — TWO FILES. LIGHT AND DARK, 1024x1024, AND NOTHING ELSE.
//
//  This briefly grew a well-matrix exporter that read the destination catalog and
//  rendered a PNG per declared well. It was dropped the same morning, on measurement
//  rather than taste: switching the phone between Light and Dark changed NOTHING on
//  the home screen — 1,434 differing pixels across two 2.96-megapixel screenshots,
//  and every one of them the clock. Apple's own icons did not shift either.
//
//  The reason is that iOS 18 moved icon appearance OFF system Dark Mode and onto the
//  Home Screen's own control (long-press -> Edit -> Customize -> Automatic / Dark /
//  Light / Tinted). Pinned to Light or Dark, the system never asks for the other
//  variant at all. So the dark icon is already a minority path, and the rest of the
//  ladder — direction, gamut, per-size Mac art — was effort spent on wells almost
//  nothing would ever read.
//
//  WHAT THE REMAINING WELLS ARE:
//    light (untagged)   the icon. Always needed.
//    dark               shown only when the user's Home Screen is Dark or Automatic.
//    tinted             NOT Liquid Glass — the iOS 18 grayscale-plus-user-colour wash.
//                       LEFT EMPTY ON PURPOSE: iOS derives it from the light art, and
//                       a supplied one is only worth it to override that derivation.
//
//  ⚠️ ALPHA: an iOS icon is rejected for merely CONTAINING an alpha channel, so both
//  files are flattened. This is safe only because the Light and Dark floors are solid
//  fills — there is no real transparency to lose.
//  ─────────────────────────────────────────────────────────────────────────────
//

import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Which background floor is showing for this render.
enum IconAppearance { case light, dark }

@MainActor
enum IconSetExport {

    static let folderName = "AppIcon.appiconset"

    /// The only pixel size an app icon needs. iOS downsamples everything else itself.
    static let px = 1024

    static let lightFile = "icon-light-1024.png"
    static let darkFile  = "icon-dark-1024.png"

    // MARK: - Rendering

    /// What a CLEAR floor becomes in an icon set — opaque white.
    ///
    /// ⚠️ ICON SET ONLY. Share, Export and PDF keep real transparency; they are not
    /// bound by App Store Connect's rules and clearing a floor there is a legitimate way
    /// to get a transparent PNG. Michael, 2026-09-15: clear is "alpha clear" on those
    /// paths and white here.
    ///
    /// ⭐ AND THIS APP DOES NOT POLICE THE USER. Whether a white dark-icon is a good idea
    /// is Apple's question and his — "we ar[e]nt on the app store connect tea[m] so its not
    /// in our lane to have an opinion about a user deleting a dark layer and exporting an
    /// icon set." The exporter's job is to be faithful and PREDICTABLE, not correct on the
    /// user's behalf. What it must never do is invent a third answer of its own, which is
    /// exactly what the old black was.
    static let clearAsWhite = "#FFFFFF"

    /// A DETACHED copy of the document with exactly one background floor visible.
    ///
    /// Deliberately a copy rather than toggling the user's own layers: an export must
    /// never mutate the thing on screen, not even for a moment. A momentary toggle
    /// would also fire `objectWillChange` and hand autosave a half-lit document.
    ///
    /// `cropRect` is dropped on purpose — an app icon is the full square, and a crop
    /// would otherwise hand Xcode a rectangular PNG it will reject.
    static func render(_ appearance: IconAppearance, of document: ImageDocument) -> ImageDocument {
        var layers = document.layers
        var floorIsLit = false
        for i in layers.indices {
            guard case .background(let role, let fillHex) = layers[i].role else { continue }
            let visible = (role == .light) == (appearance == .light)
            layers[i].isVisible = visible
            guard visible else { continue }
            floorIsLit = true
            // CLEAR MEANS WHITE IN AN ICON SET. His ruling, 2026-09-15: "if a dark layer
            // is absent its color is white as in no color only so there are no alpha clear
            // layers because app store connect rejects a photo that has an alpha layer
            // even with no clear pixels."
            if fillHex == nil { layers[i].setBackgroundFill(Self.clearAsWhite) }
        }
        // ...AND SO DOES A MISSING FLOOR. Deleting the Dark layer outright is the same
        // authoring gesture as clearing it, so it has to reach the same result. Without
        // this, a document with no Dark floor renders transparent and `stripAlpha` turns
        // it BLACK — a value nobody chose, which looks plausible and ships broken.
        // A white dark-icon is obviously wrong the moment it is seen. Loud beats plausible.
        if !floorIsLit {
            layers.insert(ImageLayer(name: appearance == .light ? "Light" : "Dark",
                                     role: .background(appearance == .light ? .light : .dark,
                                                       fillHex: Self.clearAsWhite)),
                          at: 0)      // index 0 is the BOTTOM of the stack
        }
        return ImageDocument(name: document.name,
                             canvasWidth: document.canvasWidth,
                             canvasHeight: document.canvasHeight,
                             layers: layers,
                             palette: document.palette,
                             cropRect: nil,
                             ppi: document.ppi)
    }

    /// Re-encode a PNG **without an alpha channel.**
    ///
    /// Found 2026-08-21 by checking the first real export instead of trusting it:
    /// every file came out `hasAlpha: yes`. They were fully opaque — sampled minimum
    /// alpha 255 everywhere — so nothing was see-through, but the CHANNEL was still
    /// there, and Apple rejects an iOS app icon that merely *contains* one
    /// ("can't be transparent nor contain an alpha channel"). Michael's already-shipped
    /// icons are 1024², no alpha; matching what has passed review costs nothing.
    ///
    /// Safe precisely because the Light/Dark floors are solid fills — there is no real
    /// transparency to lose. If someone exports with both floors hidden they get a
    /// black-backed icon rather than a broken one, which is the better failure.
    static func stripAlpha(_ data: Data) -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return data }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return data }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flat = ctx.makeImage() else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)
        else { return data }
        CGImageDestinationAddImage(dest, flat, nil)
        guard CGImageDestinationFinalize(dest) else { return data }
        return out as Data
    }

    // MARK: - Building the set

    /// The two PNGs and the Contents.json that wires them.
    ///
    /// Light and dark come from the document's own Light and Dark floors — you never
    /// export twice or name a file by hand, which is the whole point of doing this
    /// inside a layer app.
    static func build(from document: ImageDocument) -> [String: Data] {
        var files: [String: Data] = [:]
        if let d = ContentView.renderIconPNG(document: render(.light, of: document), px: px) {
            files[lightFile] = stripAlpha(d)
        }
        if let d = ContentView.renderIconPNG(document: render(.dark, of: document), px: px) {
            files[darkFile] = stripAlpha(d)
        }
        guard !files.isEmpty else { return [:] }
        files["Contents.json"] = contentsJSON()
        return files
    }

    // MARK: - Contents.json

    /// Two filled wells plus the empty tinted one.
    ///
    /// The tinted entry is declared WITHOUT a filename on purpose. Declaring it keeps
    /// the slot visible in Xcode so it can be filled later; leaving it empty is what
    /// lets iOS derive the tint from the light art. `.sortedKeys` matches Xcode's own
    /// alphabetical ordering so the file does not churn in a diff.
    static func contentsJSON() -> Data {
        let images: [[String: Any]] = [
            ["filename": lightFile, "idiom": "universal",
             "platform": "ios", "size": "1024x1024"],
            ["appearances": [["appearance": "luminosity", "value": "dark"]],
             "filename": darkFile, "idiom": "universal",
             "platform": "ios", "size": "1024x1024"],
            ["appearances": [["appearance": "luminosity", "value": "tinted"]],
             "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ]
        let root: [String: Any] = ["images": images,
                                   "info": ["author": "xcode", "version": 1]]
        return (try? JSONSerialization.data(withJSONObject: root,
                                            options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - Writing

    /// Write the set into `directory` as `AppIcon.appiconset`. Replaces an existing
    /// one at the same path, so re-exporting after an edit does the obvious thing.
    static func write(_ files: [String: Data], into directory: URL) throws -> URL {
        let set = directory.appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: set.path) { try fm.removeItem(at: set) }
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: set.appendingPathComponent(name), options: .atomic)
        }
        return set
    }

    /// Ask for a destination and write. Returns a sentence to show the user —
    /// success or failure, never silence.
    static func exportInteractively(from document: ImageDocument) -> String {
        let files = build(from: document)
        guard files.count > 1 else { return "Nothing to export — the canvas rendered empty." }
        do {
            let dir = try chooseDirectory()
            guard let dir else { return "" }               // user cancelled
            let set = try write(files, into: dir)
            return """
                Wrote \(lightFile) and \(darkFile) to \(set.path).

                The tinted well is declared but left empty — iOS derives it from the \
                light icon.

                Drag \(folderName) into Assets.xcassets.
                """
        } catch {
            return "Could not write the icon set: \(error.localizedDescription)"
        }
    }

    /// Where the set goes. Platform work lives behind a METHOD, never inline in shared
    /// view code — the `#if os(iOS)` trap we have paid for four times in two days.
    private static func chooseDirectory() throws -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put \(folderName)."
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
        #endif
    }
}
