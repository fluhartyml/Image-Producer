//
//  ProjectBundleExport.swift
//  Image Producer
//
//  REM: AMBER SHEET D, PIECE 3 — Export to Project Bundle (D-050, D-051) and the export's
//  "resized" report (D-042). All LOCKED 2026-11-05. His words, from the sheet:
//    D-050 "Export to Project Bundle sits next to the Icon Set export and writes every filled
//          well into one folder."
//    D-051 "Folder layout, as per App Store Connect, built like the Icon Set export (your 09-16
//          rule: the project name encloses everything)."
//            HomeLAB Playground/
//              AppIcon.appiconset/ (the Icon Set export, unchanged)
//              HomeLAB Playground-Original/iPhone/01.png … 10.png
//              HomeLAB Playground-Version A/iPad/01.png …
//          "One folder per set, one folder per device size inside it, files numbered in upload
//          order."
//    D-042 "At export, every wrong-size image is resized to its well, and the export says so
//          plainly, so you can look in each folder and check nothing was skewed."
//    D-035 "Files: JPEG or PNG, no transparency."
//
//  REM: THE APPLE TV WELLS (D-021, D-027, LOCKED). The icon and Top Shelf pictures you drop
//  go into "App Icon & Top Shelf Image.brandassets" in the files the canvas would otherwise
//  fill (same folders, same names, same Contents.json layout as the Icon Set export). An
//  empty well keeps the canvas's picture. The report lists what came from the wells and
//  names anything resized or enlarged (D-042).
//
//  REM: WHAT IS DELIBERATELY NOT HERE. The creative asset wells (D-024/025/028) and video
//  (D-070+, incl. 070b's "Only the green part … can go into … the Project Bundle") are later
//  pieces — absent, not stubbed.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum ProjectBundleExport {

    /// The name in the Export sheet's Format list, beside "Icon Set" (D-050).
    static let title = "Project Bundle"

    /// One screenshot the export changed to fit its well — a line in the D-042 report.
    struct Resize {
        let path: String
        let from: WellPixelSize
        let to: WellPixelSize
        let mode: XcodeFitMode
    }

    /// Everything the export writes, before it's written, plus what the report needs.
    struct Built {
        /// The project folder's own name — D-051 "the project name encloses everything".
        var project: String
        /// Each top-level folder inside the project folder, with its files by relative path.
        var groups: [(name: String, files: [String: Data])] = []
        /// Set folders whose wells are all empty now: an earlier export of them is removed,
        /// so the folder never shows screenshots that aren't in the wells any more.
        var emptySetFolders: [String] = []
        /// Per filled set: its folder and how many screenshots each device got.
        var filled: [(folder: String, counts: [(device: String, count: Int)])] = []
        var resized: [Resize] = []
        var seeThrough: [String] = []
        var unreadable: [String] = []
        var iconSetWritten = false
        var tvSetWritten = false
        /// The Apple TV wells that went into the brand assets (D-021, D-027), by title.
        var tvArtUsed: [String] = []
        /// Brand-asset files made bigger than the picture they came from (a 1920 × 720 banner
        /// becomes the 3840 × 1440 @2x file). Same shape, so nothing is skewed, but softer.
        var enlarged: [Resize] = []

        /// Every file, keyed by its path inside the project folder.
        var allFiles: [String: Data] {
            var all: [String: Data] = [:]
            for g in groups { for (path, data) in g.files { all["\(g.name)/\(path)"] = data } }
            return all
        }
    }

    // MARK: - Building

    static func projectFolderName(_ projectName: String) -> String {
        let safe = IconSetExport.safeFolderName(projectName)
        return safe.isEmpty ? "Untitled" : safe
    }

    static func build(from document: ImageDocument, projectName: String) -> Built {
        let project = projectFolderName(projectName)
        var built = Built(project: project)

        // REM: D-051 "AppIcon.appiconset/ (the Icon Set export, unchanged)" — the same
        // `IconSetExport.build`, and beside it the Apple TV `.brandassets` the Icon Set
        // export also writes into the project folder, so the bundle holds exactly what Icon
        // Set would have put there.
        let icon = IconSetExport.build(from: document)
        if icon.count > 1 {
            built.groups.append((IconSetExport.folderName, icon))
            built.iconSetWritten = true
        }
        // REM: D-021/D-027 — the Apple TV wells replace the canvas's pictures in the brand
        // assets; an empty well keeps them.
        let tv = IconSetExport.buildTV(from: document, art: tvArt(from: document, into: &built))
        if !tv.isEmpty {
            built.groups.append((IconSetExport.tvFolderName, tv))
            built.tvSetWritten = true
        }

        // REM: D-051 "One folder per set, one folder per device size inside it, files numbered
        // in upload order." Folder "<project>-<set name>", device folder named as the well is,
        // files 01, 02 … in the well's own order. D-050 "every filled well": an empty well
        // writes no folder.
        // REM: D-051's names, checked against build 386's sets: the original page is
        // "<project>-Original", a test version "<project>-Version A" (its default name; you can
        // rename it), a custom page "<project>-<custom page name>". Set names are kept unique
        // (case doesn't count), so no two sets share a folder.
        for set in document.xcodeProject.sets {
            let folder = IconSetExport.safeFolderName("\(project)-\(set.name)")
            var files: [String: Data] = [:]
            var counts: [(device: String, count: Int)] = []
            // REM: D-003 — a custom page has "iPhone and iPad screenshot wells" only, so only
            // the wells its kind shows are written.
            for device in set.kind.devices {
                let shots = set.screenshots(for: device)
                guard !shots.isEmpty else { continue }
                let deviceFolder = IconSetExport.safeFolderName(device.title)
                var written = 0
                for (i, shot) in shots.enumerated() {
                    // The number is the screenshot's place in the well, so "Screenshot 3" in
                    // the well is 03 in the folder.
                    let number = String(format: "%02d", i + 1)
                    guard let out = exportImage(shot, for: device) else {
                        built.unreadable.append("\(folder)/\(deviceFolder), screenshot \(i + 1)")
                        continue
                    }
                    let name = "\(deviceFolder)/\(number).\(out.ext)"
                    files[name] = out.data
                    written += 1
                    if let r = out.resized {
                        built.resized.append(Resize(path: "\(folder)/\(name)", from: r.from, to: r.to,
                                                    mode: shot.fitMode))
                    }
                    if out.seeThrough { built.seeThrough.append("\(folder)/\(name)") }
                }
                if written > 0 { counts.append((device.title, written)) }
            }
            if files.isEmpty {
                built.emptySetFolders.append(folder)
            } else {
                built.groups.append((folder, files))
                built.filled.append((folder, counts))
            }
        }
        return built
    }

    /// REM: D-021/D-027 — the Apple TV wells as the brand assets' pictures. Each picture is
    /// read upright once; every size the brand assets need is made from it with the same
    /// `wellResized` (Fill or Fit, never stretched) the well's thumbnail shows. Opaque, as
    /// D-035 asks ("no transparency"). A picture that can't be read is left out and named in
    /// the report, and that file keeps the canvas's picture.
    private static func tvArt(from document: ImageDocument, into built: inout Built) -> IconSetExport.TVArt {
        let original = document.xcodeProject.sets[document.xcodeProject.originalIndex]
        var art: IconSetExport.TVArt = [:]
        for well in XcodeTVArtWell.allCases {
            guard let shot = original.tvArt(well) else { continue }
            guard let (image, size) = uprightImage(shot.imageData) else {
                built.unreadable.append("The \(well.title) well")
                continue
            }
            let mode = shot.fitMode
            art[well.slot, default: [:]][well.appearance] = { target in
                wellResized(image, to: target, mode: mode).flatMap(pngData(from:))
            }
            built.tvArtUsed.append(well.title)
            let wrongSize = !well.accepts(size)
            for file in IconSetExport.tvArtFiles(well.slot, well.appearance) where file.size != size {
                let path = "\(IconSetExport.tvFolderName)/\(file.path)"
                if wrongSize {
                    built.resized.append(Resize(path: path, from: size, to: file.size, mode: mode))
                } else if file.size.width > size.width {
                    built.enlarged.append(Resize(path: path, from: size, to: file.size, mode: mode))
                }
            }
            if hasAlpha(image), hasSeeThroughPixels(image) {
                built.seeThrough.append("The \(well.title) well")
            }
        }
        return art
    }

    /// The picture upright (EXIF rotation applied, as the well shows it) and its size.
    private static func uprightImage(_ data: Data) -> (CGImage, WellPixelSize)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let size = wellPixelSize(data) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1 {
            return CGImageSourceCreateImageAtIndex(src, 0, nil).map { ($0, size) }
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { ($0, size) }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// One screenshot as it goes into the bundle.
    private struct Output {
        let data: Data
        let ext: String
        let resized: (from: WellPixelSize, to: WellPixelSize)?
        let seeThrough: Bool
    }

    /// REM: D-042 — "every wrong-size image is resized to its well", through the same
    /// `wellResized` (Fill or Fit, D-041; never stretched) that draws the well's thumbnails, so
    /// the file is the shape the well showed. A screenshot that's already a size its well takes
    /// is written byte for byte as it was dropped — a JPEG stays a JPEG (01.jpg), a PNG a PNG.
    /// REM: D-035 "no transparency": a picture with an alpha channel is redrawn onto the same
    /// opaque black canvas the Fit bars use, and the report names it if anything was see-through.
    /// A camera-rotated file is redrawn upright, the way the well shows it and measured it.
    private static func exportImage(_ shot: XcodeScreenshot, for device: XcodeWellDevice) -> Output? {
        let data = shot.imageData
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let size = wellPixelSize(data) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
        let type = CGImageSourceGetType(src).flatMap { UTType($0 as String) }
        let isJPEG = type?.conforms(to: .jpeg) ?? false
        let isPNG = type?.conforms(to: .png) ?? false
        let target: WellPixelSize? = device.accepts(size) ? nil : device.exportSize(for: size)

        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        } else {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
            ]
            image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
        guard let image else { return nil }
        let hasAlphaChannel: Bool = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        if target == nil, orientation == 1, !hasAlphaChannel, isPNG || isJPEG {
            return Output(data: data, ext: isJPEG ? "jpg" : "png", resized: nil, seeThrough: false)
        }
        let seeThrough = hasAlphaChannel && hasSeeThroughPixels(image)
        guard let flat = wellResized(image, to: target ?? size, mode: shot.fitMode),
              let png = pngData(from: flat) else { return nil }
        return Output(data: png, ext: "png", resized: target.map { (from: size, to: $0) },
                      seeThrough: seeThrough)
    }

    /// True when any pixel is less than fully opaque. A PNG often carries an alpha channel
    /// with every pixel solid (the canvas renders that way); that's dropped without a word.
    private static func hasSeeThroughPixels(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clear(rect)
        ctx.draw(image, in: rect)
        guard let raw = ctx.data else { return true }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 3, to: w * h * 4, by: 4) where bytes[i] < 255 { return true }
        return false
    }

    // MARK: - The report (D-042)

    /// What was written and, plainly, what was resized. `header` is the first line (where it
    /// went), which differs between the Mac's folder panel and the iPhone/iPad file picker.
    static func report(_ built: Built, header: String) -> String {
        var parts: [String] = [header]

        var inside: [String] = []
        if built.iconSetWritten { inside.append(IconSetExport.folderName) }
        if built.tvSetWritten { inside.append(IconSetExport.tvFolderName) }
        for f in built.filled {
            let counts = f.counts.map { "\($0.device) \($0.count)" }.joined(separator: ", ")
            inside.append("\(f.folder) (\(counts))")
        }
        parts.append("Inside it: " + inside.joined(separator: "; ") + ".")
        if built.filled.isEmpty {
            parts.append("No well has a screenshot yet, so only the icon set was written.")
        } else {
            parts.append("Screenshots are numbered in upload order.")
        }
        if !built.iconSetWritten {
            parts.append("The icon set could not be rendered, so \(IconSetExport.folderName) was not written.")
        }
        if !built.tvSetWritten {
            parts.append("The Apple TV icon set could not be rendered, so it was not written.")
        } else if !built.tvArtUsed.isEmpty {
            // REM: D-021/D-027 — say which Apple TV pictures came from the wells.
            parts.append("From your Apple TV wells, in \(IconSetExport.tvFolderName): "
                         + built.tvArtUsed.joined(separator: ", ")
                         + ". The rest of it is made from your canvas, as the Icon Set export makes it.")
        }

        // REM: D-042 — "the export says so plainly, so you can look in each folder and check
        // nothing was skewed." Every resized file by its path, its old size and its new one.
        if built.resized.isEmpty {
            if !built.filled.isEmpty {
                parts.append("Nothing was resized: every screenshot is already a size its well takes.")
            }
        } else {
            var lines = ["Resized to fit their wells. Open each folder and check nothing was skewed:"]
            for r in built.resized {
                let how = r.mode == .fit
                    ? "fit inside, all of it showing, with black bars where it doesn't reach"
                    : "filled to the edges, with what spilled over trimmed"
                lines.append("• \(r.path) was \(r.from.text), now \(r.to.text), \(how).")
            }
            lines.append("Nothing was stretched.")
            parts.append(lines.joined(separator: "\n"))
        }
        if !built.enlarged.isEmpty {
            // REM: D-042 "says so plainly" — an enlarged file isn't skewed, but it is softer.
            parts.append("Enlarged from a smaller picture in its well, same shape, so nothing is skewed, but it may look soft:\n"
                         + built.enlarged.map { "• \($0.path) was \($0.from.text), now \($0.to.text)." }
                             .joined(separator: "\n"))
        }
        if !built.seeThrough.isEmpty {
            // REM: D-035 "no transparency".
            parts.append("App Store Connect takes no transparency, so the see-through parts of these are solid black now:\n"
                         + built.seeThrough.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !built.unreadable.isEmpty {
            parts.append("These couldn't be read, so they were left out:\n"
                         + built.unreadable.map { "• \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Writing on the Mac (built like the Icon Set export)

    #if os(macOS)
    /// REM: D-051 "built like the Icon Set export" — the same folder panel and the same
    /// `IconSetExport.write`, into a folder named for the project. Each set folder and the
    /// icon set are replaced whole, so re-exporting after an edit leaves no old screenshots
    /// behind. Returns the sentence to show — "" means you cancelled.
    static func exportInteractively(from document: ImageDocument, projectName: String) -> String {
        let built = build(from: document, projectName: projectName)
        guard !built.groups.isEmpty else {
            return "Nothing to export: the icon set could not be rendered and no well has a screenshot."
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put the project bundle. It's written inside a folder named \(built.project)."
        guard panel.runModal() == .OK, let dir = panel.url else { return "" }
        do {
            for g in built.groups {
                _ = try IconSetExport.write(g.files, into: dir, projectName: built.project, setName: g.name)
            }
            let root = dir.appendingPathComponent(built.project, isDirectory: true)
            let fm = FileManager.default
            for f in built.emptySetFolders {
                let stale = root.appendingPathComponent(f, isDirectory: true)
                if fm.fileExists(atPath: stale.path) { try fm.removeItem(at: stale) }
            }
            return report(built, header: "Wrote the project bundle to \(root.path).")
        } catch {
            return "Could not write the project bundle: \(error.localizedDescription)"
        }
    }
    #endif
}

// MARK: - Writing on iPhone and iPad (the system file picker)

/// The whole project folder as one document for SwiftUI's `fileExporter`, so iPhone and iPad
/// save through the system picker (the sandbox gives no other way out). Files are keyed by
/// path inside the project folder; the subfolders are built from those paths.
struct ProjectBundleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    var files: [String: Data]

    init(files: [String: Data]) { self.files = files }

    init(configuration: ReadConfiguration) throws { files = [:] } // export-only

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            let parts = path.split(separator: "/").map(String.init)
            guard let fileName = parts.last else { continue }
            var dir = root
            for name in parts.dropLast() {
                if let existing = dir.fileWrappers?[name], existing.isDirectory {
                    dir = existing
                } else {
                    let sub = FileWrapper(directoryWithFileWrappers: [:])
                    sub.preferredFilename = name
                    _ = dir.addFileWrapper(sub)
                    dir = sub
                }
            }
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = fileName
            _ = dir.addFileWrapper(file)
        }
        return root
    }
}

// MARK: - In the Export sheet

/// What Project Bundle will write, shown in the Export sheet while it's the chosen format.
struct ProjectBundleSummary: View {
    let document: ImageDocument
    let project: String

    var body: some View {
        let wells = document.xcodeProject
        let filled = wells.sets.compactMap { set -> String? in
            let counts = set.kind.devices.compactMap { d -> String? in
                let n = set.screenshots(for: d).count
                return n > 0 ? "\(d.title) \(n)" : nil
            }
            return counts.isEmpty ? nil : "\(project)-\(set.name): " + counts.joined(separator: ", ")
        }
        let wrong = wells.sets.reduce(0) { total, set in
            total + set.kind.devices.reduce(0) { sub, d in
                sub + set.screenshots(for: d).filter { shot in
                    wellPixelSize(shot.imageData).map { !d.accepts($0) } ?? false
                }.count
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("One folder named \(project), holding the icon set and a folder for each set of wells, "
                 + "with each device's screenshots numbered in upload order.")
            if filled.isEmpty {
                Text("Your wells are empty, so only the icon set goes in.")
            } else {
                ForEach(filled, id: \.self) { Text($0) }
            }
            // REM: D-021/D-027 — the Apple TV wells that will replace the canvas's pictures.
            let tvArt = XcodeTVArtWell.allCases.filter { wells.sets[wells.originalIndex].tvArt($0) != nil }
            if !tvArt.isEmpty {
                Text("Apple TV pictures from your wells: " + tvArt.map(\.title).joined(separator: ", ") + ".")
            }
            if wrong > 0 {
                Text("\(wrong) screenshot\(wrong == 1 ? " isn't a size its well takes; it's" : "s aren't a size their well takes; they're") "
                     + "resized, and the report after export names each one.")
            }
        }
        .scaledFont(18)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
