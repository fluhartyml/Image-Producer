//
//  CanvasExport.swift
//  Image Producer
//
//  Canvas-hub exports (sections C + D, 2026-06-22). Three deliverables:
//    • PRINT  → a single PDF at the trim size + bleed, with crop / registration marks.
//    • WEB    → a packaged FOLDER of PNG assets (@1x / @2x / @3x), sRGB.
//    • (ICON  → the existing PNG-folder export elsewhere.)
//
//  Non-square aware: everything renders at the document's canvasPixelSize (W×H).
//
//  ⚠️ Honest limits (v1): the PDF is RGB. CMYK is stored on the document and the user can
//  pick it, but a true ICC RGB→CMYK conversion in the PDF is a later step — flagged, not
//  faked. Bleed is done by scaling the art to FILL the full page (art bleeds to the edge;
//  crop marks show the trim). Compile-verified; the actual PDF/PNG output is a device test.
//

import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A concrete CGColor for the SwiftUI Color, cross-platform (ColorPicker gives a
/// resolvable colour, so this is safe for the matte fill).
extension Color {
    var cgColorResolved: CGColor {
        #if canImport(AppKit)
        return NSColor(self).cgColor
        #elseif canImport(UIKit)
        return UIColor(self).cgColor
        #else
        return cgColor ?? CGColor(gray: 1, alpha: 1)
        #endif
    }
}

/// Render the document's visible layers to a CGImage at canvasPixelSize × `scale`.
@MainActor func renderCanvasImage(_ document: IconDocument, scale: CGFloat = 1) -> CGImage? {
    let renderer = ImageRenderer(content: IconCompositeView(document: document, size: document.canvasPixelSize))
    renderer.scale = scale
    return renderer.cgImage
}

/// A press-ready PDF: page = trim + bleed (points, 72/in). The art fills the full page so it
/// bleeds to the edge; crop marks mark the trim; registration marks optional.
@MainActor func makePrintPDF(_ document: IconDocument) -> Data? {
    guard let art = renderCanvasImage(document) else { return nil }
    let ppi = max(1, document.ppi)
    let trimW = Double(document.canvasWidth) / ppi * 72.0
    let trimH = Double(document.canvasHeight) / ppi * 72.0
    let bleed = max(0, document.bleedInches) * 72.0
    let pageW = trimW + 2 * bleed
    let pageH = trimH + 2 * bleed
    guard pageW > 0, pageH > 0 else { return nil }

    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

    ctx.beginPDFPage(nil)

    // Art fills the full page (aspect-fill), centered → bleeds to the edge.
    let imgAR = Double(art.width) / Double(max(1, art.height))
    let pageAR = pageW / pageH
    let drawRect: CGRect
    if imgAR > pageAR {
        let h = pageH, w = h * imgAR
        drawRect = CGRect(x: (pageW - w) / 2, y: 0, width: w, height: h)
    } else {
        let w = pageW, h = w / imgAR
        drawRect = CGRect(x: 0, y: (pageH - h) / 2, width: w, height: h)
    }
    ctx.draw(art, in: drawRect)

    // The trim rectangle (inset from the page by the bleed on every edge).
    let trim = CGRect(x: bleed, y: bleed, width: trimW, height: trimH)

    // Crop / trim marks: short black lines just outside each trim corner.
    if document.cropMarks {
        let len: CGFloat = min(18, max(8, bleed))
        let gap: CGFloat = min(6, bleed / 2)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(0.5)
        func mark(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
            // horizontal arm
            ctx.move(to: CGPoint(x: x + dx * gap, y: y))
            ctx.addLine(to: CGPoint(x: x + dx * (gap + len), y: y))
            // vertical arm
            ctx.move(to: CGPoint(x: x, y: y + dy * gap))
            ctx.addLine(to: CGPoint(x: x, y: y + dy * (gap + len)))
        }
        mark(trim.minX, trim.minY, -1, -1)
        mark(trim.maxX, trim.minY,  1, -1)
        mark(trim.minX, trim.maxY, -1,  1)
        mark(trim.maxX, trim.maxY,  1,  1)
        ctx.strokePath()
    }

    // Registration marks: a small crosshair-in-circle at each edge midpoint, in the bleed.
    if document.registrationMarks, bleed > 6 {
        let r = min(6, bleed / 2)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(0.5)
        func reg(_ cx: CGFloat, _ cy: CGFloat) {
            ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.move(to: CGPoint(x: cx - r * 1.6, y: cy)); ctx.addLine(to: CGPoint(x: cx + r * 1.6, y: cy))
            ctx.move(to: CGPoint(x: cx, y: cy - r * 1.6)); ctx.addLine(to: CGPoint(x: cx, y: cy + r * 1.6))
            ctx.strokePath()
        }
        reg(pageW / 2, bleed / 2)            // bottom
        reg(pageW / 2, pageH - bleed / 2)    // top
        reg(bleed / 2, pageH / 2)            // left
        reg(pageW - bleed / 2, pageH / 2)    // right
    }

    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

/// A web-ready packaged folder: PNG @1x/@2x/@3x (sRGB), named from the project.
@MainActor func makeWebFolder(_ document: IconDocument, baseName: String) -> [String: Data] {
    var files: [String: Data] = [:]
    for scale in [1, 2, 3] {
        if let cg = renderCanvasImage(document, scale: CGFloat(scale)), let png = pngData(from: cg) {
            let suffix = scale == 1 ? "" : "@\(scale)x"
            files["\(baseName)\(suffix).png"] = png
        }
    }
    return files
}

/// A single non-square PNG of the whole canvas at its pixel size.
@MainActor func makeCanvasPNG(_ document: IconDocument) -> Data? {
    guard let cg = renderCanvasImage(document) else { return nil }
    return pngData(from: cg)
}

/// The app-icon PNG set as a packaged folder (icon_16.png … icon_1024.png) — the same
/// output as the toolbar Export, surfaced in the Canvas hub so export is one-stop.
@MainActor func makeIconFolder(_ document: IconDocument) -> [String: Data] {
    var files: [String: Data] = [:]
    for px in ContentView.exportPixelSizes {
        if let data = ContentView.renderIconPNG(document: document, px: px) {
            files["icon_\(px).png"] = data
        }
    }
    return files
}

// MARK: - Layer PDF (one page per layer) + inverse import

/// Tag written into (and read from) the PDF's Subject metadata so Image Producer
/// recognizes its OWN layer PDFs and can round-trip pure-text layers back to editable
/// text layers. Foreign PDFs (no tag) import every page as a picture.
private let layerPDFTag = "IMGPRD-LAYERS-v1:"

/// Per-page record in the manifest. For a "verbatim" page (a lightweight, non-bitmap
/// layer) `layer` holds the whole layer so it round-trips to its exact editable kind; a
/// "raster" page (bitmap-heavy layer) stores just a name and is rasterized on import.
private struct LayerPDFPage: Codable {
    var kind: String            // "cover" | "verbatim" | "raster"
    var name: String
    var layer: IconLayer?
}

private struct LayerPDFManifest: Codable {
    var version = 1
    var pages: [LayerPDFPage]
}

extension IconLayer {
    /// True when the layer carries NO raster bitmap — a background (a fill colour) or a
    /// content layer whose elements are all text/symbol (or empty). These are tiny, so
    /// Image Producer stores them verbatim in its own layer PDFs and restores them to
    /// their exact editable kind ("home court advantage"). Image/pixel layers are
    /// bitmap-heavy and come back as pictures instead — their page already IS the data,
    /// and embedding the bitmap would just duplicate the project inside the PDF.
    var isLightweightForPDFTag: Bool {
        switch role {
        case .background:
            return true
        case .content:
            for el in elements {
                switch el.content {
                case .image, .pixels: return false
                case .text, .symbol:  continue
                }
            }
            return true            // empty, or all text/symbol
        }
    }
}

/// Decode Image Producer's layer manifest from a PDF's Subject, or nil for a foreign PDF.
private func layerPDFManifest(from pdf: PDFDocument) -> LayerPDFManifest? {
    guard let subject = pdf.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String,
          subject.hasPrefix(layerPDFTag),
          let data = Data(base64Encoded: String(subject.dropFirst(layerPDFTag.count))),
          let manifest = try? JSONDecoder().decode(LayerPDFManifest.self, from: data)
    else { return nil }
    return manifest
}

/// Render a single layer alone (over transparency) at the canvas pixel size, using the
/// same compositor as the full render. `forceVisible` shows even a hidden layer so the
/// breakdown is complete. Returns a CGImage that carries alpha for transparent layers.
@MainActor private func renderLayerImage(_ layer: IconLayer, in document: IconDocument) -> CGImage? {
    var solo = layer
    solo.isVisible = true
    let soloDoc = IconDocument(name: document.name,
                               canvasWidth: document.canvasWidth,
                               canvasHeight: document.canvasHeight,
                               layers: [solo], palette: document.palette,
                               cropRect: nil)
    let renderer = ImageRenderer(content: IconCompositeView(document: soloDoc, size: document.canvasPixelSize))
    renderer.scale = 1
    return renderer.cgImage
}

/// A multi-page PDF: page 1 = the composited icon as seen, then ONE PAGE PER LAYER
/// (bottom-to-top), each rendered on its own. Transparency is PRESERVED by default —
/// PDF has a native alpha model, so transparent layers stay transparent and re-import
/// cleanly (no white-matte halo). Pass a `matte` CGColor to FLATTEN each page onto that
/// colour instead — for print/CMYK handoff where live transparency is unwanted.
@MainActor func makeLayerPDF(_ document: IconDocument, matte: CGColor? = nil) -> Data? {
    let size = document.canvasPixelSize
    guard size.width > 0, size.height > 0 else { return nil }

    // Home-court manifest: page 0 = the cover composite, then one entry per layer in order.
    // Lightweight layers (text/symbol/background) are stored verbatim so a re-import restores
    // them to their exact editable kind; bitmap layers are marked "raster" (rasterized back).
    var pages: [LayerPDFPage] = [LayerPDFPage(kind: "cover", name: "Composite", layer: nil)]
    for layer in document.layers {
        if layer.isLightweightForPDFTag {
            pages.append(LayerPDFPage(kind: "verbatim", name: layer.name, layer: layer))
        } else {
            pages.append(LayerPDFPage(kind: "raster", name: layer.name, layer: nil))
        }
    }
    var auxInfo: [CFString: Any] = [kCGPDFContextCreator: "Image Producer"]
    if let manifestData = try? JSONEncoder().encode(LayerPDFManifest(pages: pages)) {
        auxInfo[kCGPDFContextSubject] = layerPDFTag + manifestData.base64EncodedString()
    }

    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = CGRect(origin: .zero, size: size)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, auxInfo as CFDictionary) else { return nil }

    func drawPage(_ cg: CGImage?) {
        ctx.beginPDFPage(nil)
        if let matte {                       // flatten: paint the matte, then the art over it
            ctx.setFillColor(matte)
            ctx.fill(mediaBox)
        }
        if let cg { ctx.draw(cg, in: mediaBox) }   // alpha preserved when matte == nil
        ctx.endPDFPage()
    }

    drawPage(renderCanvasImage(document))                        // cover: the composite
    for layer in document.layers {                               // one page per layer
        drawPage(renderLayerImage(layer, in: document))
    }

    ctx.closePDF()
    return data as Data
}

/// Rasterize one PDF page to a CGImage at `pixelSize`, PRESERVING transparency (the
/// bitmap starts clear, so a page with alpha keeps it — no forced white background).
private func rasterizePDFPage(_ page: PDFPage, pixelSize: CGSize) -> CGImage? {
    let box = PDFDisplayBox.mediaBox
    let bounds = page.bounds(for: box)
    guard bounds.width > 0, bounds.height > 0,
          Int(pixelSize.width) > 0, Int(pixelSize.height) > 0,
          let ctx = CGContext(data: nil,
                              width: Int(pixelSize.width),
                              height: Int(pixelSize.height),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Fill the page to the pixel bounds (aspect is normalized to the square canvas on
    // import; the layer transform can be adjusted afterward like any imported image).
    ctx.saveGState()
    ctx.scaleBy(x: pixelSize.width / bounds.width, y: pixelSize.height / bounds.height)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: box, to: ctx)
    ctx.restoreGState()
    return ctx.makeImage()
}

/// Import a PDF's pages as layers (appended top-of-stack, in page order).
///
/// HOME COURT: a PDF that Image Producer exported carries a manifest, so this restores
/// lightweight layers (text/symbol/background) to their EXACT editable kind, skips the
/// composite cover page, and rasterizes only the bitmap-heavy pages. A FOREIGN PDF (no
/// manifest) imports every page as a picture (image layer) — a flattened page is just
/// artwork, so "editable" there means move/scale/opacity, not native-kind reconstruction.
/// Returns layers added.
@MainActor func importPDFAsLayers(_ url: URL, into document: IconDocument) -> Int {
    guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { return 0 }
    let size = document.canvasPixelSize
    let baseName = url.deletingPathExtension().lastPathComponent
    let multi = pdf.pageCount > 1
    let manifest = layerPDFManifest(from: pdf)   // non-nil only for our own tagged PDFs

    document.captureHistoryBaselineIfNeeded()
    var added = 0
    var lastID: IconLayer.ID?
    for i in 0..<pdf.pageCount {
        let mpage: LayerPDFPage? = (manifest != nil && i < manifest!.pages.count) ? manifest!.pages[i] : nil
        if let mpage {
            if mpage.kind == "cover" { continue }                 // drop the composite
            if mpage.kind == "verbatim", var layer = mpage.layer {
                layer.id = UUID()                                 // fresh id, avoid collisions
                document.layers.append(layer)                     // restored to its exact kind
                lastID = layer.id
                added += 1
                continue
            }
            // "raster" falls through to the picture path below.
        }
        guard let pdfPage = pdf.page(at: i),
              let cg = rasterizePDFPage(pdfPage, pixelSize: size),
              let png = pngData(from: cg) else { continue }
        let name = mpage?.name ?? (multi ? "\(baseName) — Page \(i + 1)" : baseName)
        var layer = IconLayer(name: name, role: .content)
        layer.setImage(png)
        document.layers.append(layer)      // append = top of the visual stack
        lastID = layer.id
        added += 1
    }
    if added > 0, let lastID {
        document.recordHistory(toolID: Tool.image.rawValue, groupTitle: Tool.image.title,
                               actionLabel: multi ? "Import PDF (\(added) pages)" : "Import PDF",
                               layerID: lastID)
    }
    return added
}

// MARK: - Unified export (format dropdown)

/// Encode a CGImage to any ImageIO-writable format (PNG/JPEG/TIFF/HEIC/GIF/BMP).
func encodedImageData(_ cg: CGImage, as type: UTType) -> Data? {
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

/// A single-page PDF of the flattened composite — the plain "flat PDF" (no bleed/marks;
/// that's the separate Print PDF). Transparency preserved.
@MainActor func makeFlatPDF(_ document: IconDocument) -> Data? {
    guard let cg = renderCanvasImage(document) else { return nil }
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var box = CGRect(origin: .zero, size: document.canvasPixelSize)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
    ctx.beginPDFPage(nil); ctx.draw(cg, in: box); ctx.endPDFPage(); ctx.closePDF()
    return data as Data
}

/// Formats the unified Export sheet (⌘E) offers — the project rendered out to a file.
/// No legacy multi-size app-icon PNG set (deprecated: modern Xcode takes a single 1024
/// PNG or an Icon Composer .icon, both covered by "PNG" / the layer PDF here).
enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"
    case heic = "HEIC"
    case gif = "GIF"
    case bmp = "BMP"
    case pdfFlat = "PDF (flat)"
    case pdfLayers = "PDF (one page per layer)"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .heic: return UTType("public.heic") ?? .png
        case .gif:  return .gif
        case .bmp:  return .bmp
        case .pdfFlat, .pdfLayers: return .pdf
        }
    }

    /// Render the project to this format. `matte` only applies to the layer PDF (flatten).
    @MainActor func data(from document: IconDocument, matte: CGColor? = nil) -> Data? {
        switch self {
        case .pdfFlat:   return makeFlatPDF(document)
        case .pdfLayers: return makeLayerPDF(document, matte: matte)
        default:
            guard let cg = renderCanvasImage(document) else { return nil }
            return encodedImageData(cg, as: utType)
        }
    }
}

/// A plain data file for SwiftUI's `.fileExporter` — any format the Export sheet writes.
struct CanvasDataDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.png, .jpeg, .tiff, .gif, .bmp, .pdf, UTType("public.heic") ?? .png]
    }
    static var writableContentTypes: [UTType] { readableContentTypes }
    var data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
