//
//  SelectionTool.swift
//  Image Producer
//
//  THE SELECTION TOOL — marching ants around pixels you can clear or copy.
//
//  REM: His spec, 2026-10-31, in his words:
//    "what i would normally do at this point in photoshop is use the square select and
//     rectangle over the red black and a sliver of purple and the boundaries would be set
//     with a dashed rectangle and handles then i would press delete key to clear the pixels"
//    "the dash would be a selection tool not a mask tool"
//    "the selection is supposed to also be random shapes like with the path tool"
//    "not one at a time" — so all four shapes ship together: Rectangle, Oval, Freehand, Path.
//
//  REM: WHAT IT IS NOT. The Mask marks what is KEPT at export; it never touches pixels.
//  The selection marks pixels to ACT ON: Delete clears them on the selected layer, ⌘C
//  copies what you see inside the ants. It reuses `CropMask` (same frame, same handles,
//  same silhouettes) because a selection is the same shape problem with a different verb.
//
//  REM: NON-DESTRUCTIVE, like every other pixel edit here (there is no undo): the first
//  Delete puts the result on a new "(cleared)" layer and hides the original; further
//  Deletes on that layer edit it in place, the way the Magic Lasso does.
//

import SwiftUI
import CoreGraphics
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The four ways to draw a selection.
enum SelectionShape: String, CaseIterable, Identifiable {
    case rectangle, oval, freehand, path

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .oval:      "Oval"
        case .freehand:  "Freehand"
        case .path:      "Path"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: "rectangle.dashed"
        case .oval:      "circle.dashed"
        case .freehand:  "scribble"
        case .path:      "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// One line of how-to, shown in the inspector.
    var howTo: String {
        switch self {
        case .rectangle: "Drag on the canvas to draw a rectangle."
        case .oval:      "Drag on the canvas to draw an oval."
        case .freehand:  "Drag on the canvas to draw any shape. Letting go closes it."
        case .path:      "Click to place points. Click the first point (or Close Path) to finish."
        }
    }
}

// MARK: - Geometry (pure — unit tested)

enum SelectionGeometry {
    /// Clamp a normalized point onto the canvas.
    static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// The rectangle/oval selection spanned by a drag, in normalized canvas space.
    static func dragged(from a: CGPoint, to b: CGPoint, shape: SelectionShape) -> CropMask {
        let p = clamp(a), q = clamp(b)
        let r = CGRect(x: min(p.x, q.x), y: min(p.y, q.y),
                       width: max(abs(q.x - p.x), CropMask.minSide),
                       height: max(abs(q.y - p.y), CropMask.minSide))
        return CropMask(rect: r, form: shape == .oval ? .oval : .rectangle)
    }

    /// A closed outline (freehand stroke or clicked path) as a selection: the frame is the
    /// outline's bounding box and the silhouette is the outline itself, stored 0…1 inside
    /// that box — exactly the `.path` form the Mask already draws. Nil for fewer than 3
    /// points or a degenerate outline.
    static func outline(_ points: [CGPoint], label: String) -> CropMask? {
        let pts = points.map(clamp)
        guard pts.count >= 3 else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let w = maxX - minX, h = maxY - minY
        guard w > 0.002, h > 0.002 else { return nil }
        let loop = pts.map { CGPoint(x: ($0.x - minX) / w, y: ($0.y - minY) / h) }
        return CropMask(rect: CGRect(x: minX, y: minY, width: w, height: h),
                        form: .path(loops: [loop], label: label))
    }

    /// The affine map from canvas pixel space (top-left origin) into a layer's image
    /// pixel space. Same math as `imagePixel(forCanvasPoint:…)`, as a transform so a whole
    /// silhouette (curves included) can be carried across at once.
    static func canvasToImage(canvas: CGSize, transform t: LayerTransform,
                              imageW: Int, imageH: Int) -> CGAffineTransform? {
        guard imageW > 0, imageH > 0, canvas.width > 0, canvas.height > 0 else { return nil }
        let frame = min(canvas.width, canvas.height) * t.scale
        let a = Double(imageW) / Double(imageH)
        let dispW = a >= 1 ? frame : frame * a
        let dispH = a >= 1 ? frame / a : frame
        guard dispW > 0, dispH > 0 else { return nil }
        let rad = -t.rotationDegrees * .pi / 180
        return CGAffineTransform(translationX: -t.center.x * canvas.width, y: -t.center.y * canvas.height)
            .concatenating(CGAffineTransform(rotationAngle: rad))
            .concatenating(CGAffineTransform(translationX: dispW / 2, y: dispH / 2))
            .concatenating(CGAffineTransform(scaleX: Double(imageW) / dispW, y: Double(imageH) / dispH))
    }

    /// `image` with every pixel inside `selection` made fully transparent. The selection is
    /// in normalized canvas space; `canvas` is the canvas in pixels; `transform` places the
    /// image on the canvas. Pixels outside the selection are untouched, byte for byte.
    static func clearing(_ image: CGImage, inside selection: CropMask, canvas: CGSize,
                         transform: LayerTransform) -> CGImage? {
        let w = image.width, h = image.height
        guard let toImage = canvasToImage(canvas: canvas, transform: transform, imageW: w, imageH: h) else { return nil }
        let silhouette = selection.silhouette(in: canvas).cgPath
        // Top-left image space → the context's bottom-left space.
        var m = toImage.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h)))
        guard let path = silhouette.copy(using: &m) else { return nil }
        let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil)
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.addPath(path)
        ctx.setBlendMode(.clear)
        ctx.fillPath()
        return ctx.makeImage()
    }
}

// MARK: - What you see

/// Marching ants around the selection (no dimming — that is the Mask's language for
/// "kept"), plus the in-progress Path points or Freehand stroke while you draw.
struct SelectionOverlay: View {
    let selection: CropMask?
    let pathPoints: [CGPoint]
    let freehand: [CGPoint]
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let selection {
                if selection.form != .rectangle {
                    CropMaskFrameShape(mask: selection)
                        .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: size.width, height: size.height)
                }
                MarchingAnts(shape: CropMaskShape(mask: selection))
                    .frame(width: size.width, height: size.height)
            }
            if pathPoints.count > 0 {
                Path { p in
                    p.addLines(pathPoints.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                ForEach(Array(pathPoints.enumerated()), id: \.offset) { i, pt in
                    Circle()
                        .fill(i == 0 ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: i == 0 ? 14 : 9, height: i == 0 ? 14 : 9)
                        .position(x: pt.x * size.width, y: pt.y * size.height)
                }
            }
            if freehand.count > 1 {
                Path { p in
                    p.addLines(freehand.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Inspector

struct SelectionInspector: View {
    @Bindable var document: ImageDocument
    let onClear: () -> Void
    let onCopy: () -> Void
    let onClosePath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selection").font(.system(size: 18)).bold()

            Text("Shape").font(.system(size: 18)).foregroundStyle(.secondary)
            Picker("Shape", selection: $document.selectionShape) {
                ForEach(SelectionShape.allCases) { s in
                    Label(s.label, systemImage: s.systemImage).tag(s)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.system(size: 18))
            .controlSize(.large)

            Text(document.selectionShape.howTo)
                .font(.system(size: 18)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if document.selectionShape == .path, !document.selectionPathPoints.isEmpty {
                HStack {
                    Button { onClosePath() } label: { Text("Close Path").font(.system(size: 18)) }
                        .disabled(document.selectionPathPoints.count < 3)
                    Button(role: .destructive) { document.selectionPathPoints = [] } label: {
                        Text("Cancel Path").font(.system(size: 18))
                    }
                }
                .controlSize(.large)
            }

            Divider()

            Button { onClear() } label: {
                Label("Clear Inside  (Delete)", systemImage: "eraser").font(.system(size: 18)).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(document.selection == nil)
            Button { onCopy() } label: {
                Label("Copy  (⌘C)", systemImage: "doc.on.doc").font(.system(size: 18)).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(document.selection == nil)
            Button { document.selection = nil; document.selectionPathPoints = [] } label: {
                Label("Deselect  (Esc)", systemImage: "xmark.square").font(.system(size: 18)).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(document.selection == nil && document.selectionPathPoints.isEmpty)

            InfoTip("More about this", label: "About Clear Inside and Copy", "Clear Inside works on the selected layer: the first clear makes a new layer and hides the original (kept). Copy takes everything you see inside the ants. Drag inside the ants to move them; drag a corner to resize.")
        }
        .font(.system(size: 18))
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Delete / Escape keys (macOS)

#if os(macOS)
/// Listens for Delete and Escape in THIS window only, and only while `enabled`. A text box
/// with the keyboard always keeps its own Delete — the monitor stands aside whenever the
/// first responder is text.
struct SelectionKeyMonitor: NSViewRepresentable {
    var enabled: Bool
    var onDelete: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled
        view.onDelete = onDelete
        view.onEscape = onEscape
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var enabled = false
        var onDelete: () -> Void = {}
        var onEscape: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, let win = self.window, event.window === win,
                      !(win.firstResponder is NSText),
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
                switch event.keyCode {
                case 51, 117:  // Delete (backspace), Forward Delete
                    self.onDelete(); return nil
                case 53:       // Escape
                    self.onEscape(); return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}
#endif

// MARK: - Actions

extension ImageDocument {
    /// The Path shape's points become the selection (needs 3 or more).
    func closeSelectionPath() {
        guard selectionPathPoints.count >= 3 else { return }
        selection = SelectionGeometry.outline(selectionPathPoints, label: "Path")
        selectionPathPoints = []
    }

    /// DELETE — clear the pixels inside the ants on the selected layer. Returns the layer
    /// that now holds the result (select it), or nil when nothing was cleared.
    @MainActor @discardableResult
    func clearInsideSelection(activeLayerID: ImageLayer.ID?) -> ImageLayer.ID? {
        guard let sel = selection else { say("Nothing selected", kind: .info); return nil }
        guard let id = activeLayerID, let idx = layers.firstIndex(where: { $0.id == id }) else {
            say("Pick a layer to clear", kind: .info); return nil
        }
        guard layers[idx].backgroundRole == nil else {
            say("Light and Dark are solid colors — pick a picture layer", kind: .info); return nil
        }
        var png: Data?
        for el in layers[idx].elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { png = img.pngData; break }
        }
        guard let png else { say("Clear Inside works on picture layers", kind: .info); return nil }
        let t = layers[idx].transform
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let cleared = SelectionGeometry.clearing(cg, inside: sel, canvas: canvasPixelSize, transform: t),
              let out = pngData(from: cleared) else {
            say("Clear failed", kind: .info); return nil
        }

        captureHistoryBaselineIfNeeded()   // before the edit
        // Repeat Deletes keep working on the layer the first one made (Magic Lasso's idiom),
        // so clearing three areas does not leave three hidden copies behind.
        if selectionClearLayerID == id {
            layers[idx].setImage(out)
            recordHistory(toolID: Tool.select.rawValue, groupTitle: Tool.select.title,
                          actionLabel: "Clear Selection", layerID: id)
            return id
        }
        guard let newID = addResultLayer(out, above: idx, nameSuffix: "cleared"),
              let ni = layers.firstIndex(where: { $0.id == newID }) else { return nil }
        layers[ni].transform = t            // the result sits exactly where the art was
        selectionClearLayerID = newID
        recordHistory(toolID: Tool.select.rawValue, groupTitle: Tool.select.title,
                      actionLabel: "Clear Selection", layerID: newID)
        return newID
    }

    /// ⌘C — everything you SEE inside the ants (all visible layers), clipped to the
    /// selection's shape and trimmed to its box, onto the clipboard as PNG (+ TIFF on Mac).
    @MainActor
    func copySelectionPixels() {
        guard let sel = selection else { say("Nothing selected", kind: .info); return }
        let flat = ImageDocument(name: name, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                                 layers: layers, palette: palette, cropRect: nil)
        let renderer = ImageRenderer(content: ImageCompositeView(document: flat, size: canvasPixelSize))
        renderer.scale = 1
        guard let full = renderer.cgImage, let image = sel.clip(full), let png = pngData(from: image) else {
            say("Copy failed", kind: .info); return
        }
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
        #else
        UIPasteboard.general.setData(png, forPasteboardType: "public.png")
        #endif
        say("Copied \(image.width) × \(image.height)", kind: .info)
    }
}
