//
//  IconModels.swift
//  Icon Producer
//
//  Created by Michael Fluharty on 6/10/26.
//
//  The icon-document domain model — the data shapes from the design.
//  See IconProducer_DeveloperNotes.swift for the full plan-of-record.
//
//  KEY MODEL DECISION (Michael 2026-06-10): layers are NOT pre-typed. There is
//  one kind of content layer — a BLANK, TRANSPARENT canvas — and "pixels / image
//  / text / symbol" are ELEMENTS you add to ANY content layer (mixed + composited).
//  A blank layer can become anything. Only the two background layers have a
//  special role (a fillable solid colour, the icon's opacity floor).
//
//  Other deliberate choices:
//   • PERSISTENCE-AGNOSTIC + Codable-friendly. The "icon package" save format is
//     decided later; nothing here ties to SwiftData or a document type yet.
//   • NO whole-store UndoManager anywhere — that is what crashed Shelf-Ready on
//     deletes. Undo will be a byproduct of a custom tool-history structure later.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Document

/// An icon project: a square canvas (the 1024 "master") holding an ordered,
/// nondestructive stack of layers. Index 0 = bottom (drawn first), last = top.
/// Reordering a layer = reindexing this array; layers are never flattened until
/// export.
///
/// Reference type + `ObservableObject` because it is the app's `ReferenceFileDocument`
/// (see the conformance below) — DocumentGroup owns it and saves it as a package.
final class IconDocument: ObservableObject {
    @Published var name: String
    /// Square master resolution. 1024 = the design's "draw small, render master big".
    let canvasSize: Int
    /// Bottom-to-top draw order.
    @Published var layers: [IconLayer]
    /// The 8-slot brand palette (hex), saved WITH the document so it travels per-project.
    @Published var palette: [String]

    /// Optional crop region — a normalized rectangle (0…1, origin top-left) in canvas
    /// space marking the KEPT area. `nil` = no crop (full square). Non-destructive:
    /// stored here and applied at export/share; the source layers are never trimmed.
    /// A smaller rectangle fits inside the square canvas, so this needs no canvas resize.
    @Published var cropRect: CGRect?

    /// Crayon-box defaults — used for a new doc, or one saved before palettes existed.
    static let defaultPalette = ["#000000", "#FFFFFF", "#FF3B30", "#FF9500",
                                 "#FFCC00", "#34C759", "#007AFF", "#AF52DE"]

    /// The last palette the user worked with — persists app-wide so a NEW document (or
    /// one saved without a palette) inherits it instead of resetting to the defaults.
    static var lastUsedPalette: [String] {
        get { UserDefaults.standard.stringArray(forKey: "IconProducer.lastUsedPalette") ?? defaultPalette }
        set { UserDefaults.standard.set(newValue, forKey: "IconProducer.lastUsedPalette") }
    }

    init(name: String = "Untitled Icon", canvasSize: Int = 1024, layers: [IconLayer] = [],
         palette: [String] = IconDocument.lastUsedPalette, cropRect: CGRect? = nil) {
        self.name = name
        self.canvasSize = canvasSize
        self.layers = layers
        self.palette = palette
        self.cropRect = cropRect
    }

    /// A brand-new icon's default stack (bottom → top): two background floors —
    /// Light, Dark — then three blank content layers — Background, Midground,
    /// Foreground. ALL START BLANK (roadmap 0.4: no example icon, no test content).
    /// The user fills the floors with the paint bucket and composes art across the
    /// three content layers (e.g. an imported/AI subject on Midground, a backdrop on
    /// Background). The named content layers give a depth scaffold AND keep an
    /// AI-generated icon's baked-in backdrop off the Light/Dark mode floors (no
    /// "background within a background"). Light vs dark is previewed by toggling a
    /// floor's `isVisible` (the eyeball); there are no light/dark mode buttons. More
    /// layers can be added/deleted freely.
    static func newDefault() -> IconDocument {
        IconDocument(layers: [
            IconLayer(name: "Light",      role: .background(.light, fillHex: nil)),
            IconLayer(name: "Dark",       role: .background(.dark,  fillHex: nil)),
            IconLayer(name: "Background", role: .content),
            IconLayer(name: "Midground",  role: .content),
            IconLayer(name: "Foreground", role: .content),
        ])
    }
}

// MARK: - Layer

/// One layer in the stack.
/// CONTENT layers are blank transparent canvases — real alpha, see-through to the
/// layers below — that hold a MIX of content `elements`. BACKGROUND layers are a
/// fillable solid colour (the floor that removes any clear background from the
/// final icon); they start blank (no fill) until the user paints them.
struct IconLayer: Identifiable, Codable {
    var id = UUID()
    /// User-editable; auto-named from its content ("content names the layer").
    var name: String
    /// The eyeball toggle. For the two background layers this also serves as the
    /// light/dark preview control (hide Dark Background to preview the light look).
    var isVisible = true
    /// 0...1.
    var opacity = 1.0
    var transform = LayerTransform()
    var role: LayerRole
    /// Content elements on a CONTENT layer, composited bottom-to-top. Mixed types
    /// allowed (pixels + image + text + symbol on one layer). Empty = blank.
    /// (Backgrounds ignore this; their look is the fill.)
    var elements: [LayerElement]

    init(name: String, role: LayerRole, elements: [LayerElement] = []) {
        self.name = name
        self.role = role
        self.elements = elements
    }

    /// True while a layer is still blank (nothing filled / nothing placed).
    var isBlank: Bool {
        switch role {
        case .background(_, let fillHex): fillHex == nil
        case .content:                    elements.isEmpty
        }
    }

    /// This layer's background sub-role (light/dark), or nil if it's a content layer.
    var backgroundRole: BackgroundRole? {
        if case .background(let r, _) = role { return r }
        return nil
    }

    /// Paint Bucket v1 (roadmap 2.1): set a BACKGROUND layer's solid fill. Pass nil
    /// to clear it back to blank. No-op on content layers.
    mutating func setBackgroundFill(_ hex: String?) {
        if case .background(let r, _) = role { role = .background(r, fillHex: hex) }
    }

    /// Symbol tool v1 (roadmap 2.2): set this CONTENT layer to a single SF Symbol
    /// element (single-glyph-as-icon is the primary case). Replaces existing content.
    /// No-op on background layers.
    mutating func setSymbol(_ systemName: String, tintHex: String) {
        guard case .content = role else { return }
        elements = [LayerElement(content: .symbol(SymbolContent(systemName: systemName, tintHex: tintHex)))]
    }

    /// Font tool "F" v1: place a single font glyph (a character in a chosen font)
    /// as a text element on this CONTENT layer. Replaces existing content. No-op on
    /// a background layer. SF Symbols are the separate "SF" tool; this is fonts only.
    mutating func setText(_ string: String, fontName: String, tintHex: String,
                          bold: Bool = false, italic: Bool = false,
                          underline: Bool = false, outline: Bool = false) {
        guard case .content = role else { return }
        elements = [LayerElement(content: .text(TextContent(
            string: string, fontName: fontName, sizeFraction: 0.8, colorHex: tintHex,
            bold: bold, italic: italic, underline: underline, outline: outline)))]
    }

    /// Image tool v1: place imported PNG bytes as an image element on this CONTENT
    /// layer, kept at native resolution (the canvas scales it for display). No-op on bg.
    mutating func setImage(_ pngData: Data) {
        guard case .content = role else { return }
        elements = [LayerElement(content: .image(ImageContent(pngData: pngData)))]
    }

    /// Pixel Pen v1: set this CONTENT layer's raster to `pngData` (the full 1024
    /// master bitmap the pen draws into). No-op on a background layer.
    mutating func setPixels(_ pngData: Data) {
        guard case .content = role else { return }
        elements = [LayerElement(content: .pixels(PixelContent(pngData: pngData)))]
    }

    /// This layer's current pixel raster (for seeding the pen), if any.
    var pixelData: Data? {
        for element in elements {
            if case .pixels(let p) = element.content { return p.pngData }
        }
        return nil
    }

    /// The SF Symbol currently on this layer, if any (for picker highlighting).
    var symbolElementName: String? {
        for element in elements {
            if case .symbol(let symbol) = element.content { return symbol.systemName }
        }
        return nil
    }

    /// SF Symbol name used to badge this layer in the layer list.
    var displaySymbolName: String {
        switch role {
        case .background(let bg, _): bg == .light ? "sun.max" : "moon"
        case .content:               elements.isEmpty ? "square.dashed" : "square.stack.3d.up"
        }
    }
}

/// Placement of a layer within the square canvas.
struct LayerTransform: Codable {
    /// Normalized center in canvas space (0...1, origin top-left).
    var center = CGPoint(x: 0.5, y: 0.5)
    /// Scale as a fraction of the canvas edge.
    var scale = 1.0
    var rotationDegrees = 0.0
}

// MARK: - Layer role

/// What a layer IS at the structural level (NOT a content type).
enum LayerRole: Codable {
    /// A fillable solid-colour background — the icon's floor. STARTS BLANK
    /// (`fillHex == nil`); the user fills it with the paint bucket. Once filled it
    /// is opaque, which removes any clear background from the final icon. Light =
    /// typically white, Dark = typically black, but the colour is user-chosen.
    case background(_ role: BackgroundRole, fillHex: String?)
    /// A blank, transparent canvas that can hold any mix of content elements.
    case content
}

enum BackgroundRole: String, Codable {
    case light, dark
}

// MARK: - Content elements

/// One piece of content on a content layer. A layer can hold a MIX of these,
/// composited. Tools (pixel pen, image import, text tool, symbol picker) add
/// elements; nothing pre-types the layer.
struct LayerElement: Identifiable, Codable {
    var id = UUID()
    var content: ElementContent
}

enum ElementContent: Codable {
    /// In-place pixel painting on the master (pen size = stamp size; densities
    /// 128/256/512/1024 are a view concern — strokes of different sizes mix here).
    case pixels(PixelContent)
    /// Imported / pasted / drag / AI-generated raster artwork. PNG only (never JPG).
    case image(ImageContent)
    /// A click-to-add text element (font glyphs; single-letter-as-icon is primary).
    case text(TextContent)
    /// An SF Symbol — picked from Apple's library, not typed.
    case symbol(SymbolContent)
}

struct PixelContent: Codable {
    /// PNG bytes of the pixel raster at the master resolution.
    var pngData = Data()
}

struct ImageContent: Codable {
    /// PNG bytes at the master resolution. Empty = not yet populated.
    var pngData = Data()
}

struct TextContent: Codable {
    var string = "A"
    var fontName = "SF Pro"
    /// Point size as a fraction of the master edge (can reach 1.0 = canvas-filling).
    var sizeFraction = 0.8
    var colorHex = "#000000"
    /// Style toggles (F tool). `outline` is stored now; its rendering is a follow-up
    /// (no stock SwiftUI text-outline — needs custom glyph stroking).
    var bold = false
    var italic = false
    var underline = false
    var outline = false
}

struct SymbolContent: Codable {
    var systemName = "star.fill"
    var tintHex = "#000000"
}

// MARK: - Saved package format (roadmap 2.4)

extension UTType {
    /// Icon Producer's editable project package — a file wrapper (directory) the
    /// user saves to iCloud Drive / Files. Holds a `manifest.json` (layers +, later,
    /// edit history) alongside binary assets. Declared in Info.plist to match.
    static let iconProject = UTType(exportedAs: "com.nightgard.Icon-Producer.project")

    /// A standalone brand palette (`.iconpalette`) — plain JSON, saved/loaded
    /// independent of any project so one color set can seed many icons. Declared in
    /// Info.plist as an exported type (identity only; the app opens it via its own
    /// in-app importer, NOT the DocumentGroup, so it is not a CFBundleDocumentTypes entry).
    static let iconPalette = UTType(exportedAs: "com.nightgard.Icon-Producer.palette")
}

// MARK: - Standalone palette file (roadmap: brand-asset palettes)

/// A portable 8-color brand palette saved on its own, outside any project. The same
/// file can be loaded into any icon so a brand's colors stay consistent across icons.
struct PaletteFile: Codable {
    var schemaVersion = 1
    /// The originating document's name when saved — metadata only (loading a palette
    /// changes colors, never the icon's name).
    var name: String
    var colors: [String]

    /// Exactly 8 valid `#RRGGBB` slots. Pads a short file with the crayon-box defaults,
    /// drops extras past 8, and replaces any malformed hex — so a hand-edited or
    /// foreign file can never corrupt the document's fixed 8-slot palette.
    var normalizedColors: [String] {
        let defaults = IconDocument.defaultPalette
        return (0..<8).map { i in
            if i < colors.count, let hex = PaletteFile.normalizeHex(colors[i]) { return hex }
            return defaults[i]
        }
    }

    /// Validate + canonicalize one hex string to "#RRGGBB" (uppercase). nil if malformed.
    /// Pure string work — no platform color round-trip, so it's actor-free.
    static func normalizeHex(_ string: String) -> String? {
        var t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, UInt32(t, radix: 16) != nil else { return nil }
        return "#" + t.uppercased()
    }
}

/// SwiftUI `fileExporter` wrapper for a `PaletteFile` — pretty-printed JSON so the
/// saved brand asset is human-readable and hand-editable.
struct PaletteFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.iconPalette] }
    static var writableContentTypes: [UTType] { [.iconPalette] }

    var palette: PaletteFile

    init(palette: PaletteFile) { self.palette = palette }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        palette = try JSONDecoder().decode(PaletteFile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(palette))
    }
}

/// The serializable shape written into a saved package's `manifest.json`.
/// Binary assets (pixel/image PNGs) become sibling files in the wrapper when those
/// tools land — kept out of JSON to avoid base64 bloat.
struct IconProjectManifest: Codable {
    var name: String
    var canvasSize: Int
    var layers: [IconLayer]
    /// Optional for backward-compat with .iconproj files saved before palettes existed.
    var palette: [String]?
    /// Optional crop region (normalized); absent in files saved before crop existed.
    var cropRect: CGRect?
}

extension IconDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.iconProject] }

    /// Open a saved package: pull `manifest.json` out of the directory wrapper.
    convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.fileWrappers?["manifest.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest = try JSONDecoder().decode(IconProjectManifest.self, from: data)
        self.init(name: manifest.name, canvasSize: manifest.canvasSize, layers: manifest.layers,
                  palette: manifest.palette ?? IconDocument.lastUsedPalette, cropRect: manifest.cropRect)
    }

    /// Capture current state for writing (called off the main actor by SwiftUI).
    func snapshot(contentType: UTType) throws -> IconProjectManifest {
        IconProjectManifest(name: name, canvasSize: canvasSize, layers: layers, palette: palette,
                            cropRect: cropRect)
    }

    /// Write the package: a directory wrapper holding `manifest.json`.
    func fileWrapper(snapshot: IconProjectManifest,
                     configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(snapshot)
        let manifest = FileWrapper(regularFileWithContents: data)
        manifest.preferredFilename = "manifest.json"
        return FileWrapper(directoryWithFileWrappers: ["manifest.json": manifest])
    }
}

// MARK: - Self-driven autosave

extension IconDocument {
    /// Write the `.picprod` package straight to `url` (older `.iconproj` files still
    /// open — same type identifier), file-coordinated for iCloud
    /// safety. This is the app's autosave path — it does NOT go through SwiftUI's
    /// undo-based autosave (the app has no UndoManager; undo/redo is the future History
    /// system's job, and we don't want the two to compete). Same `manifest.json` format
    /// as the official `fileWrapper(snapshot:)` writer, so the file stays interchangeable.
    func writePackage(to url: URL) throws {
        let manifest = IconProjectManifest(name: name, canvasSize: canvasSize,
                                           layers: layers, palette: palette, cropRect: cropRect)
        let data = try JSONEncoder().encode(manifest)
        let mf = FileWrapper(regularFileWithContents: data)
        mf.preferredFilename = "manifest.json"
        let dir = FileWrapper(directoryWithFileWrappers: ["manifest.json": mf])

        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordError) { coordURL in
            do { try dir.write(to: coordURL, options: .atomic, originalContentsURL: nil) }
            catch { writeError = error }
        }
        if let writeError { throw writeError }
        if let coordError { throw coordError }
    }
}
