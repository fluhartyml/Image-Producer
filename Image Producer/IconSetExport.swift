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

    /// What a CLEAR **or MISSING** floor becomes in an icon set.
    ///
    /// ⭐ PER ROLE, and he arrived at this by reversing himself: white for Light, BLACK for
    /// Dark. His first rule was white for both — "if a dark layer is absent its color is
    /// white as in no color only" — and he changed it after the asymmetry was raised:
    /// "you changed my mind on dark being black and not white as in no color."
    ///
    /// **Why black is right for Dark:** a dark icon with a black floor is a PLAUSIBLE icon.
    /// A dark icon with a WHITE floor is a glaring one. Both were defensible, and the
    /// earlier argument here was that loud beats plausible — but that reasoning belongs to
    /// a FAILURE, and this is not a failure. Leaving the Dark floor clear is a legitimate
    /// way to say "black". Punishing it with a white icon would be the app second-guessing
    /// the user, which is exactly what he ruled out: "we ar[e]nt on the app store connect
    /// tea[m] so its not in our lane to have an opinion."
    ///
    /// ⚠️ ICON SET ONLY. Share, Export and PDF keep real transparency — they are not bound
    /// by App Store Connect's rules, and clearing a floor there is a legitimate way to get
    /// a transparent PNG. His split: clear is "alpha clear" on those paths, a real colour
    /// here.
    ///
    /// ⚠️ AND IT IS THE EXPORT COPY ONLY. `render(_:of:)` works on a detached document, so
    /// nothing here reaches his file. His words: "if it replaced a[nd] wrote it to the image
    /// file that would be destructive."
    ///
    /// ⭐ WHAT IT MUST NEVER DO is invent a third answer of its own. The original code
    /// rendered a clear floor transparent and then let `stripAlpha` flatten it to black —
    /// a value nobody chose, arrived at by accident rather than by decision.
    static func defaultFloorHex(for role: BackgroundRole) -> String {
        switch role {
        case .light: "#FFFFFF"
        case .dark:  "#000000"
        }
    }

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
            if fillHex == nil { layers[i].setBackgroundFill(Self.defaultFloorHex(for: role)) }
        }
        // ...AND SO DOES A MISSING FLOOR. Deleting the Dark layer outright is the same
        // authoring gesture as clearing it, so it has to reach the same result. Without
        // this, a document with no Dark floor renders transparent and `stripAlpha` turns
        // it BLACK — a value nobody chose, which looks plausible and ships broken.
        // A white dark-icon is obviously wrong the moment it is seen. Loud beats plausible.
        if !floorIsLit {
            let role: BackgroundRole = appearance == .light ? .light : .dark
            layers.insert(ImageLayer(name: appearance == .light ? "Light" : "Dark",
                                     role: .background(role, fillHex: Self.defaultFloorHex(for: role))),
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

    // MARK: - Apple TV
    //
    // HIS ASK, 2026-10-13: "you need to update apple tv into the icon export". Found the same
    // afternoon when the Mediaworks tvOS archive failed validation — "Missing Info.plist Key …
    // CFBundleIcons.CFBundlePrimaryIcon" and "TVTopShelfImage.TVTopShelfPrimaryImageWide" —
    // because AppIcon.appiconset only ever carried iPhone and Mac art. Apple TV wants a
    // different thing entirely: a WIDE icon built from at least two LAYERS (the TV shifts
    // them apart when the icon is focused), plus Top Shelf banners.
    //
    // The layers fall straight out of the document: the BACK is the floor, stretched to the
    // wide shape (it is a solid fill, so stretching loses nothing); the FRONT is every other
    // visible layer, floors hidden, transparent, centred. Together they are exactly the
    // square icon on its own floor, widened. Top Shelf is the two flattened.
    //
    // Light AND dark, his words: "it does light and dark automatically". actool accepts
    // dark renditions in every tvOS well and stores them (checked the compiled Assets.car);
    // whether the TV swaps them with its own Dark setting is for the TV to show.

    static let tvFolderName = "App Icon & Top Shelf Image.brandassets"

    /// The art is rendered once at the tallest height any TV image needs (Top Shelf @2x)
    /// and drawn down from there.
    static let tvArtPx = 1440

    private enum TVPart { case back, front, flat }

    /// One PNG in the brand assets: where it goes, its pixel size, and which part it shows.
    private struct TVImage {
        let folder: String, stem: String, width: Int, height: Int, scale: Int, part: TVPart
    }

    private static let iconStack = "App Icon.imagestack"
    private static let storeStack = "App Icon - App Store.imagestack"
    private static let topShelf = "Top Shelf Image.imageset"
    private static let topShelfWide = "Top Shelf Image Wide.imageset"

    private static let tvImages: [TVImage] = {
        var list: [TVImage] = []
        for (stack, sizes) in [(iconStack, [(400, 240, 1), (800, 480, 2)]), (storeStack, [(1280, 768, 1)])] {
            for (w, h, s) in sizes {
                list.append(TVImage(folder: "\(stack)/Back.imagestacklayer/Content.imageset", stem: "back",
                                    width: w, height: h, scale: s, part: .back))
                list.append(TVImage(folder: "\(stack)/Front.imagestacklayer/Content.imageset", stem: "front",
                                    width: w, height: h, scale: s, part: .front))
            }
        }
        for (set, w, h) in [(topShelf, 1920, 720), (topShelfWide, 2320, 720)] {
            for s in [1, 2] {
                list.append(TVImage(folder: set, stem: "topshelf", width: w * s, height: h * s, scale: s, part: .flat))
            }
        }
        return list
    }()

    private static func fileName(_ image: TVImage, _ appearance: IconAppearance) -> String {
        image.stem + (image.scale == 2 ? "@2x" : "") + (appearance == .dark ? "-dark" : "") + ".png"
    }

    /// The Apple TV brand assets, light and dark — PNGs plus every Contents.json, keyed by
    /// path inside the `.brandassets` folder. All or nothing: a set that names a dark file
    /// it does not contain would fail in Xcode.
    static func buildTV(from document: ImageDocument) -> [String: Data] {
        var files: [String: Data] = [:]
        for appearance in [IconAppearance.light, .dark] {
            let lit = render(appearance, of: document)
            guard let floor = floorColor(of: lit),
                  let artPNG = ContentView.renderIconPNG(document: hidingFloors(lit), px: tvArtPx),
                  let source = CGImageSourceCreateWithData(artPNG as CFData, nil),
                  let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [:] }
            for image in tvImages {
                guard let png = compose(image, floor: floor, art: art) else { return [:] }
                files["\(image.folder)/\(fileName(image, appearance))"] = png
            }
        }
        files.merge(tvContents()) { $1 }
        return files
    }

    /// The colour of the one floor `render` left lit (it always fills a clear or missing one).
    private static func floorColor(of document: ImageDocument) -> CGColor? {
        for layer in document.layers where layer.isVisible {
            if case .background(_, let hex?) = layer.role, let rgb = RGB(hex: hex) {
                return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            }
        }
        return nil
    }

    /// The same detached copy with its floors hidden — the art alone, on transparency.
    private static func hidingFloors(_ document: ImageDocument) -> ImageDocument {
        var layers = document.layers
        for i in layers.indices {
            if case .background = layers[i].role { layers[i].isVisible = false }
        }
        return ImageDocument(name: document.name,
                             canvasWidth: document.canvasWidth,
                             canvasHeight: document.canvasHeight,
                             layers: layers,
                             palette: document.palette,
                             cropRect: nil,
                             ppi: document.ppi)
    }

    /// Draw one TV image: the floor across the whole width, the square art centred at full
    /// height. Only the FRONT layer keeps an alpha channel — it is the one that must be
    /// see-through; the back and Top Shelf are flattened like the iOS icon.
    private static func compose(_ image: TVImage, floor: CGColor, art: CGImage) -> Data? {
        let w = image.width, h = image.height
        let alpha = image.part == .front ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: alpha.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        if image.part != .front {
            ctx.setFillColor(floor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        if image.part != .back {
            ctx.draw(art, in: CGRect(x: CGFloat(w - h) / 2, y: 0, width: CGFloat(h), height: CGFloat(h)))
        }
        guard let cg = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Every Contents.json in the brand assets, laid out the way Xcode's own tvOS template does.
    private static func tvContents() -> [String: Data] {
        let info: [String: Any] = ["author": "xcode", "version": 1]
        func json(_ root: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        }
        var files: [String: Data] = [:]
        files["Contents.json"] = json(["assets": [
            ["filename": storeStack, "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
            ["filename": iconStack, "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
            ["filename": topShelfWide, "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
            ["filename": topShelf, "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
        ], "info": info])
        for stack in [iconStack, storeStack] {
            files["\(stack)/Contents.json"] = json(["layers": [["filename": "Front.imagestacklayer"],
                                                              ["filename": "Back.imagestacklayer"]],
                                                   "info": info])
            for layer in ["Front", "Back"] {
                files["\(stack)/\(layer).imagestacklayer/Contents.json"] = json(["info": info])
            }
        }
        // One imageset Contents.json per folder, listing each scale in light then dark.
        for folder in Set(tvImages.map(\.folder)) {
            var images: [[String: Any]] = []
            for image in tvImages where image.folder == folder {
                for appearance in [IconAppearance.light, .dark] {
                    var entry: [String: Any] = ["filename": fileName(image, appearance),
                                                "idiom": "tv", "scale": "\(image.scale)x"]
                    if appearance == .dark {
                        entry["appearances"] = [["appearance": "luminosity", "value": "dark"]]
                    }
                    images.append(entry)
                }
            }
            files["\(folder)/Contents.json"] = json(["images": images, "info": info])
        }
        return files
    }

    // MARK: - Writing

    /// Write the set into `directory` as `AppIcon.appiconset` — inside a folder named for
    /// the project when one is given. Replaces an existing set at the same path, so
    /// re-exporting after an edit does the obvious thing.
    ///
    /// ⭐ The project folder is his, 2026-09-16: "i want the icon set folder to be unique
    /// and have the image project name enclosing /phototizer/appicon.iconset". Every set
    /// used to land as a bare `AppIcon.appiconset`, so two projects exported to the same
    /// place replaced each other and nothing said whose icon it was. The inner name stays
    /// `AppIcon.appiconset` because that is what Xcode's asset catalog expects.
    ///
    /// `setName` is the set's own folder — `AppIcon.appiconset`, or the Apple TV
    /// `.brandassets`, whose file names carry subfolders ("App Icon.imagestack/…").
    static func write(_ files: [String: Data], into directory: URL,
                      projectName: String? = nil, setName: String = folderName) throws -> URL {
        var parent = directory
        if let folder = projectName.map(safeFolderName), !folder.isEmpty {
            parent = directory.appendingPathComponent(folder, isDirectory: true)
        }
        let set = parent.appendingPathComponent(setName, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: set.path) { try fm.removeItem(at: set) }
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        for (name, data) in files {
            let url = set.appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return set
    }

    /// A project name made safe as ONE folder name: no path separators, trimmed.
    static func safeFolderName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ask for a destination and write. Returns a sentence to show the user —
    /// success or failure, never silence.
    static func exportInteractively(from document: ImageDocument, projectName: String? = nil) -> String {
        let files = build(from: document)
        guard files.count > 1 else { return "Nothing to export — the canvas rendered empty." }
        do {
            let dir = try chooseDirectory()
            guard let dir else { return "" }               // user cancelled
            let set = try write(files, into: dir, projectName: projectName)
            let tvFiles = buildTV(from: document)
            if !tvFiles.isEmpty {
                _ = try write(tvFiles, into: dir, projectName: projectName, setName: tvFolderName)
            }
            let tvLine = tvFiles.isEmpty
                ? "The Apple TV set could not be rendered, so only the iPhone/Mac set was written."
                : "Beside it, \(tvFolderName) — the Apple TV icon (front and back layers) and Top Shelf "
                  + "images, light and dark. In the app's build settings, set the tvOS App Icon to "
                  + "\"App Icon & Top Shelf Image\"."
            return """
                Wrote \(lightFile) and \(darkFile) to \(set.path).

                The tinted well is declared but left empty — iOS derives it from the \
                light icon.

                \(tvLine)

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
        panel.message = "Choose where to put the icon set. It is written inside a folder named for the project."
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
        #endif
    }
}
