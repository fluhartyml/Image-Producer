//
//  IconModels.swift
//  Icon Producer
//
//  Created by Michael Fluharty on 6/10/26.
//
//  The icon-document domain model — the data shapes from the design.
//  See ImageProducer_DeveloperNotes.swift for the full plan-of-record.
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
    /// Canvas pixel dimensions. Was a single square `canvasSize`; B2 makes it W×H so the
    /// canvas can take non-square print / photo / card shapes. Mutable — the Canvas tool
    /// resizes it (pixels = physical size × ppi). 1024×1024 is the default square master.
    @Published var canvasWidth: Int
    @Published var canvasHeight: Int
    /// Pixel size as a CGSize — the export / render reference.
    var canvasPixelSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }
    /// Bottom-to-top draw order.
    @Published var layers: [IconLayer]
    /// The 8-slot brand palette (hex), saved WITH the document so it travels per-project.
    @Published var palette: [String]

    /// Linear, tool-grouped edit history — the app's undo (a byproduct of stepping
    /// back through this list; there is NO ⌘Z / UndoManager). Saved in the package,
    /// persistent per-project. Empty until the recording hooks land (step 2).
    @Published var history: IconHistory = IconHistory()

    /// Optional crop region — a normalized rectangle (0…1, origin top-left) in canvas
    /// space marking the KEPT area. `nil` = no crop (full square). Non-destructive:
    /// stored here and applied at export/share; the source layers are never trimmed.
    /// A smaller rectangle fits inside the square canvas, so this needs no canvas resize.
    @Published var cropRect: CGRect?

    /// Output resolution in pixels-per-inch. Physical/print size = pixels ÷ ppi. Changing
    /// it is LOSSLESS — it reinterprets the SAME pixels at a new physical size; it never
    /// resamples. Saved with the document (absent in older files → defaults to 72).
    @Published var ppi: Double

    // MARK: Print setup (Canvas hub section C) — feeds the Print PDF. All persisted.
    /// Bleed in inches — artwork extends this far past the trim so trimming leaves no white
    /// sliver. Print standard is 0.125 in (3 mm).
    @Published var bleedInches: Double = 0.125
    /// Safe-margin inset in inches — keep important content this far inside the trim.
    @Published var safeMarginInches: Double = 0
    /// Draw crop / trim marks at the trim corners in the Print PDF.
    @Published var cropMarks: Bool = true
    /// Draw registration marks (for aligning color plates) in the Print PDF.
    @Published var registrationMarks: Bool = false
    /// Output color space for the Print PDF: false = RGB (default), true = CMYK. Switchable
    /// anytime — editing stays RGB on screen; CMYK is an export-time conversion.
    @Published var colorSpaceCMYK: Bool = false

    /// Crayon-box defaults — used for a new doc, or one saved before palettes existed.
    static let defaultPalette = ["#000000", "#FFFFFF", "#FF3B30", "#FF9500",
                                 "#FFCC00", "#34C759", "#007AFF", "#AF52DE"]
    /// Palette = the project's gatekeeper color set. Default 8 (the "school crayon box"),
    /// growable to 24 (Michael 2026-06-22). No color exists outside this palette.
    static let maxPaletteSlots = 24

    /// Add a slot (capped at 24), seeded from the last color. Returns the new index, or nil.
    @discardableResult
    func addPaletteColor() -> Int? {
        guard palette.count < Self.maxPaletteSlots else { return nil }
        palette.append(palette.last ?? "#000000")
        IconDocument.lastUsedPalette = palette
        return palette.count - 1
    }

    /// Remove a slot (never below the 8-color minimum).
    func removePaletteColor(at i: Int) {
        guard palette.count > 8, palette.indices.contains(i) else { return }
        palette.remove(at: i)
        IconDocument.lastUsedPalette = palette
    }

    /// The last palette the user worked with — persists app-wide so a NEW document (or
    /// one saved without a palette) inherits it instead of resetting to the defaults.
    static var lastUsedPalette: [String] {
        get { UserDefaults.standard.stringArray(forKey: "IconProducer.lastUsedPalette") ?? defaultPalette }
        set { UserDefaults.standard.set(newValue, forKey: "IconProducer.lastUsedPalette") }
    }

    init(name: String = "Untitled Image", canvasWidth: Int = 1024, canvasHeight: Int = 1024,
         layers: [IconLayer] = [], palette: [String] = IconDocument.lastUsedPalette,
         cropRect: CGRect? = nil, ppi: Double = 72, history: IconHistory = IconHistory()) {
        self.name = name
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.layers = layers
        self.palette = palette
        self.cropRect = cropRect
        self.ppi = ppi
        self.history = history
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

extension IconDocument {
    /// Non-destructive "Apply": put the result of a destructive edit on a NEW content
    /// layer directly ABOVE the source, and HIDE the source (kept, re-showable) so the
    /// result composites correctly. The original is never overwritten — there's no undo
    /// (Cmd-Z is off until the History engine exists), so every destructive Apply
    /// (Crop / AI Filter / Magic Eraser) preserves the source this way. Returns the new
    /// layer's id (e.g. so the caller can set its transform).
    @discardableResult
    func addResultLayer(_ png: Data, above sourceIndex: Int, nameSuffix: String) -> IconLayer.ID? {
        guard layers.indices.contains(sourceIndex) else { return nil }
        var layer = IconLayer(name: "\(layers[sourceIndex].name) (\(nameSuffix))", role: .content)
        layer.setImage(png)
        layers[sourceIndex].isVisible = false        // keep the original, just hidden
        layers.insert(layer, at: sourceIndex + 1)    // directly above the source
        return layer.id
    }
}

// MARK: - History recording + step-back (steps 2–3)

extension IconDocument {
    /// Encode the current layer stack as a `DocumentSnapshot`.
    private func encodedSnapshot() -> Data? {
        try? JSONEncoder().encode(DocumentSnapshot(layers: layers))
    }

    /// Capture the pre-edit layer stack as the history baseline the FIRST time an edit is
    /// recorded, so step-back can return to the original. No-op once set. MUST be called
    /// BEFORE the edit mutates the layers.
    func captureHistoryBaselineIfNeeded() {
        guard history.baseline == nil, history.entries.isEmpty else { return }
        history.baseline = encodedSnapshot()
    }

    /// Append one edit to the linear history, AFTER it has been applied to `layers` (so the
    /// snapshot captures the post-edit state). Consecutive actions from the SAME tool nest
    /// under one group (a continuous "tool run"); a different tool starts a new group —
    /// matching the "grouped by tool" design. Non-destructive tools (zoom / pan / eyedropper)
    /// never call this. `toolID`/`groupTitle` come from the caller's `Tool` (rawValue / title);
    /// the model stays free of the editor's Tool enum.
    /// `coalesce` (used by continuous edits like typing): if the current tool run's LAST
    /// action already has this label, update ITS snapshot in place instead of appending a
    /// new row — so a whole typing session is one "Text" step, not one per keystroke.
    func recordHistory(toolID: String, groupTitle: String, actionLabel: String,
                       layerID: IconLayer.ID?, coalesce: Bool = false) {
        let snapshot = encodedSnapshot()
        let n = history.entries.count
        if n > 0, history.entries[n - 1].toolID == toolID {
            let m = history.entries[n - 1].actions.count
            if coalesce, m > 0, history.entries[n - 1].actions[m - 1].label == actionLabel {
                history.entries[n - 1].actions[m - 1].snapshot = snapshot   // fold into the current row
                return
            }
            history.entries[n - 1].actions.append(
                HistoryAction(label: actionLabel, layerID: layerID, snapshot: snapshot))
        } else {
            history.entries.append(HistoryEntry(toolID: toolID, title: groupTitle,
                actions: [HistoryAction(label: actionLabel, layerID: layerID, snapshot: snapshot)]))
        }
    }

    /// Restore a snapshot's layer stack onto the live document (leaves non-history state —
    /// name, canvas size, palette, crop, ppi, print setup — untouched).
    private func restore(_ data: Data?) {
        guard let data, let snap = try? JSONDecoder().decode(DocumentSnapshot.self, from: data) else { return }
        layers = snap.layers
    }

    /// Linear step-back to a chosen action: restore its layer-stack snapshot and DROP every
    /// action/entry after it (the picked action's effect is kept — "resume from there").
    /// This IS the app's undo (no ⌘Z / UndoManager). Returns true if it stepped back.
    @discardableResult
    func stepBack(toEntry entryIndex: Int, action actionIndex: Int) -> Bool {
        guard history.entries.indices.contains(entryIndex),
              history.entries[entryIndex].actions.indices.contains(actionIndex) else { return false }
        restore(history.entries[entryIndex].actions[actionIndex].snapshot)
        // Trim the target entry to the picked action, drop all entries after it.
        var entry = history.entries[entryIndex]
        entry.actions = Array(entry.actions.prefix(actionIndex + 1))
        history.entries = Array(history.entries.prefix(entryIndex)) + [entry]
        return true
    }

    /// Step back to the original (pre-first-edit) layer stack — the "Original" row. Restores
    /// the baseline and clears every recorded entry (the baseline itself is kept).
    func stepBackToBaseline() {
        restore(history.baseline)
        history.entries.removeAll()
    }

    /// Purge History (the ONLY thing that clears the trail): keep the CURRENT image, drop the
    /// entire history — entries AND the baseline. The live `layers` are never touched.
    func purgeHistory() {
        history.entries.removeAll()
        history.baseline = nil
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

    /// The text string currently on this layer, if any (for the live Text tool + the
    /// layer-name⇄text two-way link).
    var textString: String? {
        for element in elements {
            if case .text(let t) = element.content { return t.string }
        }
        return nil
    }

    /// Rewrite just the text element's string (keeps font/style/color), for the layer-name
    /// → text link. No-op if the layer has no text element.
    mutating func setTextString(_ string: String) {
        for i in elements.indices {
            if case .text(var t) = elements[i].content {
                t.string = string
                elements[i] = LayerElement(content: .text(t))
                return
            }
        }
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
    /// Scale as a fraction of the canvas edge — the LIMITING (larger) content dimension.
    var scale = 1.0
    var rotationDegrees = 0.0
    /// Intrinsic width÷height of the layer's content (e.g. a cropped image's aspect).
    /// `nil` = treat as square (1:1), the legacy assumption and the default for files
    /// saved before crop set it. Lets the Move box hug a non-square object and lets
    /// Fit/Fill snap it to the canvas with the right geometry.
    var contentAspect: Double? = nil

    /// The content's displayed size as a fraction of the canvas edge (width, height),
    /// honoring `contentAspect`. `scale` drives the limiting (larger) dimension; the
    /// other follows the aspect. Square when `contentAspect` is nil.
    var contentSize: CGSize {
        let a = contentAspect ?? 1
        let width  = a >= 1 ? scale : scale * a
        let height = a >= 1 ? scale / a : scale
        return CGSize(width: width, height: height)
    }
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

    /// Valid `#RRGGBB` slots, 8…24. Keeps the file's colors (dropping malformed ones),
    /// pads up to the 8-color minimum with the crayon-box defaults, and caps at 24 — so a
    /// hand-edited or foreign file can never corrupt the document's palette (the gatekeeper).
    var normalizedColors: [String] {
        let defaults = IconDocument.defaultPalette                 // 8
        var out = colors.compactMap { PaletteFile.normalizeHex($0) }
        if out.count < 8 { out += Array(defaults[out.count..<8]) } // pad to the 8 minimum
        if out.count > IconDocument.maxPaletteSlots {              // cap at 24
            out = Array(out.prefix(IconDocument.maxPaletteSlots))
        }
        return out
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

// MARK: - History (linear, tool-grouped timeline — the app's undo)
//
// Step 1 (2026-07-02): DATA MODEL + PERSISTENCE only. No UI, no recording yet.
// Step 2 (2026-07-02): RECORDING HOOKS. Pen strokes + Paint Bucket fills append to
//   the timeline via IconDocument.recordHistory (below).
// Step 3 (2026-07-02): PANEL UI + LINEAR STEP-BACK. Each action snapshots the whole
//   LAYER STACK (DocumentSnapshot) post-edit; step-back restores it and drops everything
//   forward. Baseline captures the pre-first-edit stack → an "Original" row. Undo is a
//   byproduct of the History panel — NO ⌘Z / UndoManager (spec + Shelf-Ready crash class).
// Design per DeveloperNotes "HISTORY — DECIDED 2026-06-10":
//   • Linear, Photoshop-style. Undo is a BYPRODUCT of this list — no ⌘Z, no
//     app-wide UndoManager (that snapshot-the-whole-store undo is the crash class
//     that killed Shelf-Ready; deliberately avoided).
//   • Grouped by tool (reveal carats); each group holds that run's nested actions.
//     Only destructive/edit tools are parents — never zoom/pan.
//   • Per-stroke granularity lives in a group's `actions` (each pen stroke = one).
//   • Linear step-back: pick an entry → everything forward is dropped.
//   • Persistent from icon creation across close/reopen; cleared ONLY by Purge.

/// One nested action under a tool group — the granular, step-back-able unit
/// (e.g. a single pen stroke, one bucket fill).
struct HistoryAction: Identifiable, Codable {
    var id = UUID()
    /// Row label, e.g. "Stroke", "Fill", "Erase".
    var label: String
    /// The layer this action modified — for display (which layer a row touched). Optional
    /// so document-wide actions can omit it. Not used for restore (the snapshot below is
    /// a full layer-stack capture, which reverses layer add/hide too).
    var layerID: IconLayer.ID? = nil
    /// A `DocumentSnapshot` (encoded JSON) of the whole LAYER STACK AFTER this action —
    /// step-back decodes it and replaces `document.layers` wholesale, so picking any point
    /// restores exactly that state (including fill's added/hidden layers, which a single
    /// layer PNG could not reverse). Stored INLINE, matching how layer pixels are already
    /// persisted; icons are tiny + "storage is a non-issue" (Michael). Sibling-file storage
    /// is the later optimization once layer pixels move out of the JSON too.
    var snapshot: Data? = nil
}

/// A tool group in the timeline (the reveal-carat parent) — one continuous run of a
/// tool's actions. Only destructive/edit tools create groups.
struct HistoryEntry: Identifiable, Codable {
    var id = UUID()
    /// Owning tool's raw id (`Tool.rawValue`, e.g. "pen", "fill", "eraser").
    var toolID: String
    /// Group header, e.g. "Pen (Pixels)", "Paint Bucket".
    var title: String
    /// Nested actions; per-stroke granularity lives here.
    var actions: [HistoryAction] = []
}

/// The document's linear edit history. Persistent per-project (saved in the package),
/// cleared only by Purge History. Undo = stepping back through `entries`, which
/// truncates everything after the chosen point.
struct IconHistory: Codable {
    var entries: [HistoryEntry] = []
    /// The layer stack BEFORE the first recorded edit (encoded `DocumentSnapshot`), so
    /// step-back can return all the way to the original — the "Original" row in the panel.
    /// Captured once, on the first edit; `nil` until then.
    var baseline: Data? = nil
}

/// A restorable capture of just the LAYER STACK at one history point. History governs
/// only the destructive layer edits (pen / fill / eraser…), so a snapshot captures only
/// `layers` — deliberately NOT canvas size, name, palette, crop, ppi or print setup, which
/// aren't history-tracked and must survive a step-back untouched (no silent rename/resize
/// reverts). Reversing an action = replacing `document.layers` with this.
struct DocumentSnapshot: Codable {
    var layers: [IconLayer]
}

/// The serializable shape written into a saved package's `manifest.json`.
/// Binary assets (pixel/image PNGs) become sibling files in the wrapper when those
/// tools land — kept out of JSON to avoid base64 bloat.
struct IconProjectManifest: Codable {
    var name: String
    /// Legacy square size (files saved before non-square existed). Read-only fallback.
    var canvasSize: Int? = nil
    /// Non-square canvas pixel dimensions (B2). Absent in older files → fall back to canvasSize.
    var canvasWidth: Int? = nil
    var canvasHeight: Int? = nil
    var layers: [IconLayer]
    /// Optional for backward-compat with .iconproj files saved before palettes existed.
    var palette: [String]?
    /// Optional crop region (normalized); absent in files saved before crop existed.
    var cropRect: CGRect?
    /// Output resolution (PPI); absent in files saved before it existed → defaults to 72.
    var ppi: Double?
    // Print setup (section C); all optional for back-compat.
    var bleedInches: Double? = nil
    var safeMarginInches: Double? = nil
    var cropMarks: Bool? = nil
    var registrationMarks: Bool? = nil
    var colorSpaceCMYK: Bool? = nil
    /// Linear edit history; optional/absent in files saved before History existed → an
    /// empty history. (Snapshot PNGs referenced by entries live as sibling files.)
    var history: IconHistory? = nil
}

extension IconDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.iconProject] }

    /// Open a saved package: pull `manifest.json` out of the directory wrapper.
    convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.fileWrappers?["manifest.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest = try JSONDecoder().decode(IconProjectManifest.self, from: data)
        let w = manifest.canvasWidth ?? manifest.canvasSize ?? 1024
        let h = manifest.canvasHeight ?? manifest.canvasSize ?? 1024
        self.init(name: manifest.name, canvasWidth: w, canvasHeight: h, layers: manifest.layers,
                  palette: manifest.palette ?? IconDocument.lastUsedPalette, cropRect: manifest.cropRect,
                  ppi: manifest.ppi ?? 72, history: manifest.history ?? IconHistory())
        // Print-setup fields (section C) — apply saved values over the defaults.
        if let v = manifest.bleedInches { bleedInches = v }
        if let v = manifest.safeMarginInches { safeMarginInches = v }
        if let v = manifest.cropMarks { cropMarks = v }
        if let v = manifest.registrationMarks { registrationMarks = v }
        if let v = manifest.colorSpaceCMYK { colorSpaceCMYK = v }
    }

    /// Capture current state for writing (called off the main actor by SwiftUI).
    func snapshot(contentType: UTType) throws -> IconProjectManifest {
        IconProjectManifest(name: name, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                            layers: layers, palette: palette, cropRect: cropRect, ppi: ppi,
                            bleedInches: bleedInches, safeMarginInches: safeMarginInches,
                            cropMarks: cropMarks, registrationMarks: registrationMarks,
                            colorSpaceCMYK: colorSpaceCMYK, history: history)
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
        let manifest = IconProjectManifest(name: name, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                                           layers: layers, palette: palette, cropRect: cropRect, ppi: ppi,
                                           bleedInches: bleedInches, safeMarginInches: safeMarginInches,
                                           cropMarks: cropMarks, registrationMarks: registrationMarks,
                                           colorSpaceCMYK: colorSpaceCMYK, history: history)
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

// MARK: - New project files (never "Untitled")

extension IconDocument {
    /// New documents save as `.picprod` — the already-registered project package that opens
    /// reliably. (`.imgprd` is declared too, but the old "Icon Producer" app still claims the
    /// same type identifier with only the old extensions, so LaunchServices doesn't recognize
    /// a fresh `.imgprd` as our PACKAGE — it sees a plain folder and won't open it. Switching
    /// the app to its own type identifier is the follow-up that lets `.imgprd` work; until
    /// then new files use `.picprod`. Either way old `.picprod`/`.iconproj` files open.)
    static let projectExtension = "picprod"

    /// Where new projects are written immediately so a canvas is never an unnamed
    /// "Untitled": the app's iCloud Documents folder (syncs across devices, shows in
    /// Files), falling back to the local Documents container when iCloud is unavailable.
    nonisolated static func projectsDirectory() -> URL? {
        let fm = FileManager.default
        let dir: URL
        if let icloud = fm.url(forUbiquityContainerIdentifier: "iCloud.com.nightgard.image-producer") {
            dir = icloud.appendingPathComponent("Documents", isDirectory: true)
        } else if let local = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true) {
            dir = local
        } else {
            return nil
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Persisted count of every project ever created in the app's lifetime. The auto-name
    /// `ImageProducerNNNN` uses THIS, not the count of files on disk — so the number is a
    /// running total and a deleted project's number is never reused (Michael 2026-06-23).
    private static let lifetimeCountKey = "ip.lifetimeProjectCount"

    /// Reserve the next lifetime project number and return a fresh, non-colliding URL
    /// `<projects>/ImageProducerNNNN.imgprd` (4-digit zero-padded, no space). Bumps the
    /// persisted counter; if that name somehow already exists, keeps bumping so it's unique.
    nonisolated static func nextProjectURL() -> URL? {
        guard let dir = projectsDirectory() else { return nil }
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        var n = defaults.integer(forKey: lifetimeCountKey) + 1
        func url(_ k: Int) -> URL {
            dir.appendingPathComponent(String(format: "ImageProducer%04d", k))
               .appendingPathExtension(projectExtension)
        }
        var candidate = url(n)
        while fm.fileExists(atPath: candidate.path) { n += 1; candidate = url(n) }
        defaults.set(n, forKey: lifetimeCountKey)
        return candidate
    }

    /// Write a brand-new default project to `url` (which the caller resolved OFF the main
    /// thread via `nextProjectURL` — the slow iCloud-container lookup lives there). This
    /// stays on the main actor because IconDocument is main-actor-isolated; the write is a
    /// quick local package write. Returns true on success; the Canvas name field then
    /// renames the file in place. Split from the old one-shot `createNewProjectFile` so the
    /// blocking lookup no longer runs on the main thread (the suspected New-crash, 2026-06-23).
    @MainActor static func writeNewProject(at url: URL) -> Bool {
        let doc = newDefault()
        doc.name = url.deletingPathExtension().lastPathComponent
        do {
            try doc.writePackage(to: url)
            pendingNewProjectURL = url      // so the editor opens it on the Canvas hub
            return true
        } catch { return false }
    }

    /// The just-created project's URL. New projects are real files now (not "Untitled"),
    /// so the editor can't use "no file" to know it's new — it matches this instead to open
    /// a fresh project on the Canvas hub (name + extents up front). Consumed on first appear.
    static var pendingNewProjectURL: URL?
}
