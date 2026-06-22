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

/// A plain data file (PDF or PNG) for SwiftUI's `.fileExporter`.
struct CanvasDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf, .png] }
    static var writableContentTypes: [UTType] { [.pdf, .png] }
    var data: Data
    init(_ data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
