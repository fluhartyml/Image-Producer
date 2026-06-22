//
//  EditorTools.swift
//  Icon Producer
//
//  Created by Michael Fluharty on 6/11/26.
//
//  The toolbox lineup. These are the SELECTABLE tools that populate the tool
//  strip. The set is locked in ImageProducer_DeveloperNotes.swift ("TOOL
//  VOCABULARY"); the BEHAVIOUR of each tool is built later, one at a time. For
//  now a tool just selects (highlights) and shows its placeholder inspector.
//
//  NOTE on names: "Pen" = the PIXEL painter; "Path" = the VECTOR Bezier tool
//  (Photoshop/Illustrator's "pen") — kept distinct so the two never blur.
//

import SwiftUI

/// A tool in the toolbox. Order here = left-to-right order in the strip (which
/// scrolls horizontally when there are more tools than fit — see DeveloperNotes).
enum Tool: String, CaseIterable, Identifiable {
    case canvas        // central hub for the open project (name/dimensions/print/export)
    case move
    case fill          // paint bucket
    case pen           // pixel painter
    case eraser
    case eyedropper
    case shape         // line / rectangle / oval / polygon
    case path          // vector Bezier
    case text          // type characters + browse a font's full repertoire (Wingdings etc.)
    case symbol        // SF Symbols
    case image         // import: File / Photo / paste / AI
    case imagePlayground   // Apple Image Playground — Maker (new layer) / Filter (restyle active layer)
    case zoom          // navigation only (not history)

    var id: String { rawValue }

    /// Label shown in the tool's (placeholder) inspector.
    var title: String {
        switch self {
        case .canvas:     "Canvas"
        case .move:       "Move / Transform"
        case .fill:       "Paint Bucket"
        case .pen:        "Pen (Pixels)"
        case .eraser:     "Eraser"
        case .eyedropper: "Eyedropper"
        case .shape:      "Shape"
        case .path:       "Path (Vector)"
        case .text:       "Text"
        case .symbol:     "Symbol (SF Symbols)"
        case .image:      "Image"
        case .imagePlayground: "Image Playground"
        case .zoom:       "Zoom"
        }
    }

    /// SF Symbol used for the tool's button in the strip.
    var systemImage: String {
        switch self {
        case .canvas:     "photo.artframe"
        case .move:       "arrow.up.and.down.and.arrow.left.and.right"
        case .fill:       "drop.fill"
        case .pen:        "pencil.tip"
        case .eraser:     "eraser.fill"
        case .eyedropper: "eyedropper"
        case .shape:      "square.on.circle"
        case .path:       "scribble.variable"
        case .text:       "textformat"
        case .symbol:     "star.fill"
        case .image:      "photo"
        case .imagePlayground: "apple.image.playground"
        case .zoom:       "magnifyingglass"
        }
    }
}

// MARK: - Paint Bucket glyph (style B — solid bucket, colored pour)

/// Vector paint bucket drawn with Canvas — used for the Fill tool's strip glyph
/// (static colour) and the Fill cursor (live fill colour). Style "B" from the
/// 2026-06-15 concept mockup: solid body, a colored pour, a small puddle.
/// `pourTip` is where the paint lands (unit space, origin top-left) → the cursor
/// hotspot must sit there so the cursor aims where the fill goes.
struct PaintBucketGlyph: View {
    /// The pouring paint colour. Static amber for the toolbar glyph; the cursor
    /// passes the user's live fill colour (the easter egg).
    var pourColor: Color = Color(red: 1.0, green: 0.69, blue: 0.0)
    var bodyColor: Color = Color(white: 0.85)
    var outline: Color = Color(white: 0.42)

    /// Where the pour lands, as a fraction of the glyph box (origin top-left).
    /// Kept in sync with the drawing below so the cursor hotspot matches.
    static let pourTip = CGPoint(x: 0.30, y: 0.92)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 100 * s, y: y / 100 * s) }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x / 100 * s, y: y / 100 * s, width: w / 100 * s, height: h / 100 * s)
            }
            let lw = max(1, s * 0.035)

            // Bucket body (tilted trapezoid, opening up-right).
            var bodyPath = Path()
            bodyPath.move(to: p(34, 22))
            bodyPath.addLine(to: p(80, 14))
            bodyPath.addLine(to: p(72, 60))
            bodyPath.addLine(to: p(46, 66))
            bodyPath.closeSubpath()
            ctx.fill(bodyPath, with: .color(bodyColor))
            ctx.stroke(bodyPath, with: .color(outline), lineWidth: lw)

            // Handle arc over the opening.
            var handle = Path()
            handle.move(to: p(37, 18))
            handle.addQuadCurve(to: p(79, 11), control: p(58, -16))
            ctx.stroke(handle, with: .color(outline), lineWidth: lw)

            // Rim (open top) drawn over the body's top edge.
            let rim = Path(ellipseIn: r(33, 8, 48, 16))
            ctx.fill(rim, with: .color(bodyColor))
            ctx.stroke(rim, with: .color(outline), lineWidth: lw)
            ctx.fill(Path(ellipseIn: r(37, 11, 40, 10)), with: .color(outline.opacity(0.45)))

            // Pour stream from the lower-left lip down to the pour tip.
            var pour = Path()
            pour.move(to: p(47, 56))
            pour.addCurve(to: p(30, 90), control1: p(40, 72), control2: p(31, 80))
            ctx.stroke(pour, with: .color(pourColor),
                       style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))

            // Puddle where it lands (the hotspot point).
            ctx.fill(Path(ellipseIn: r(22, 88, 16, 7)), with: .color(pourColor))
        }
    }
}

/// The glyph shown for a tool in the strip/rail. Every tool with custom art in
/// Assets (Michael's 96×96 @300dpi tool renders, imported 2026-06-18) uses that
/// image; a tool without one falls back to its SF Symbol. Custom art renders a
/// touch larger (28pt) than the 18pt SF Symbols so the detail stays legible.
struct ToolGlyph: View {
    let tool: Tool

    /// Asset-catalog image name for this tool, or nil to use the SF Symbol.
    /// Every tool now has custom art (the Font tool was folded into Text, and the
    /// Image tool uses the PhotoTool render). The Optional/SF-Symbol fallback stays
    /// in place for any future tool added without art.
    private var assetName: String? {
        switch tool {
        case .canvas:     "CanvasTool"
        case .move:       "MoveTool"
        case .fill:       "BucketTool"
        case .pen:        "PixelArtPenTool"
        case .eraser:     "PinkEraser"
        case .eyedropper: "ColorSampleEyeDropper"
        case .shape:      "ShapeTool"
        case .path:       "PathTool"
        case .text:       "FontBook"
        case .symbol:     "SFPickerTool"
        case .image:      "PhotoTool"
        case .imagePlayground: "ImagePlayground"
        case .zoom:       "MagnefyingGlass"
        }
    }

    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: tool.systemImage)
                .font(.system(size: 18))
        }
    }
}
