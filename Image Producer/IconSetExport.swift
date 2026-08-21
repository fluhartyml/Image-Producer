//
//  IconSetExport.swift
//  Image Producer
//
//  Export a drop-in `AppIcon.appiconset` — the PNGs AND a valid Contents.json —
//  so the whole thing drags straight into Assets.xcassets and is done. A folder of
//  loose PNGs still leaves you dragging files into wells, and the wells were always
//  the actual work.
//
//  THE SIZES ARE NOT GUESSED. They were read on 2026-08-21 out of Image Producer's
//  own `Assets.xcassets/AppIcon.appiconset/Contents.json` — written by Michael's own
//  Xcode — because Apple's requirements move and this app's old 19-size ladder
//  (16…1024) is left over from Icon Producer. What Xcode actually declares:
//
//    iOS   — exactly TWO images: 1024×1024, and a second 1024×1024 tagged
//            `appearances: luminosity = dark`. iOS downsamples the rest itself.
//    macOS — 6 unique files (16 · 32 · 64 · 128 · 256 · 512) wired into 10 slots,
//            each point size at 1x and 2x, files shared: 16@2x IS the 32px file,
//            and 512@2x is the 1024.
//
//  ⚠️ And the finding that would have burned us: the macOS entries carry NO dark
//  variant. Only the iOS 1024 has an appearance. So "light and dark of every size"
//  is really light+dark of the iOS 1024 plus a light-only Mac ladder. We emit
//  exactly what Xcode generates — anything extra risks an import warning.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Which background floor is showing for this render.
enum IconAppearance { case light, dark }

@MainActor
enum IconSetExport {

    /// The UNIQUE macOS pixel sizes. Verified, not recalled — see the file header.
    static let macPixelSizes = [16, 32, 64, 128, 256, 512]

    static let folderName = "AppIcon.appiconset"

    // MARK: - Rendering

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
        for i in layers.indices {
            guard case .background(let role, _) = layers[i].role else { continue }
            layers[i].isVisible = (role == .light) == (appearance == .light)
        }
        return ImageDocument(name: document.name,
                             canvasWidth: document.canvasWidth,
                             canvasHeight: document.canvasHeight,
                             layers: layers,
                             palette: document.palette,
                             cropRect: nil,
                             ppi: document.ppi)
    }

    /// Every file the set contains, keyed by filename. Light and dark come from the
    /// document's own Light and Dark floors — you never export twice or name a file
    /// by hand, which is the whole point of doing this inside a layer app.
    static func build(from document: ImageDocument) -> [String: Data] {
        var files: [String: Data] = [:]
        let light = render(.light, of: document)
        let dark  = render(.dark,  of: document)

        if let d = ContentView.renderIconPNG(document: light, px: 1024) { files["icon-light-1024.png"] = d }
        if let d = ContentView.renderIconPNG(document: dark,  px: 1024) { files["icon-dark-1024.png"]  = d }
        for px in macPixelSizes {
            if let d = ContentView.renderIconPNG(document: light, px: px) { files["icon-mac-\(px).png"] = d }
        }
        files["Contents.json"] = contentsJSON()
        return files
    }

    // MARK: - Contents.json

    /// Mirrors Xcode's own output exactly — same keys, same order, same shared files.
    static func contentsJSON() -> Data {
        var images: [[String: Any]] = [
            ["filename": "icon-light-1024.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"],
            ["appearances": [["appearance": "luminosity", "value": "dark"]],
             "filename": "icon-dark-1024.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"],
        ]
        // (point size, scale, the pixel file it resolves to)
        let macSlots: [(pt: Int, scale: Int, px: Int)] = [
            (16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128),
            (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024),
        ]
        for s in macSlots {
            // 512@2x is the 1024 — the same file the iOS light slot uses, exactly as
            // Xcode wires it. No duplicate megabyte on disk.
            let file = s.px == 1024 ? "icon-light-1024.png" : "icon-mac-\(s.px).png"
            images.append(["filename": file, "idiom": "mac",
                           "scale": "\(s.scale)x", "size": "\(s.pt)x\(s.pt)"])
        }
        let root: [String: Any] = ["images": images,
                                   "info": ["author": "xcode", "version": 1]]
        return (try? JSONSerialization.data(withJSONObject: root,
                                            options: [.prettyPrinted])) ?? Data()
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
            return "Wrote \(files.count) files to \(set.path).\n\nDrag \(folderName) into Assets.xcassets."
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
