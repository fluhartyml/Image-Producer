//
//  Adjustments.swift
//  Image Producer
//
//  ADJUST — Levels, Gaussian Blur and Liquify. Each opens as its own window with a live
//  preview, the way Photoshop and PhotoCraft both do it, and touches nothing until OK.
//
//  Where they came from (2026-10-11): two videos Michael watched — Kirk's "This Free
//  Photoshop Clone Shouldn't Exist - Let's TEST It" (PhotoCraft 0.5.0 vs Photoshop) and
//  Jeff Fagan's "Someone Just Recreated Adobe With AI… FOR FREE!" — and his instruction
//  "code everything from the amber sheet". Ideas only; no code was taken from ArtCraft or
//  anyone else. Built on Apple's Core Image / Core Graphics and plain pixel arithmetic.
//  Amber page: apartment `Workshop/Image-Producer-PhotoCraft-Findings-DRAFT-2026-10-11.html`.
//
//  NON-DESTRUCTIVE, like every other pixel tool in the app: the result lands on a NEW layer
//  directly above, a full copy of the source (placement, glow, blend…) with only its
//  picture replaced, and the original is hidden — never overwritten. One History step.
//

import SwiftUI
import CoreImage
import CoreGraphics

// MARK: - The three adjustments

enum Adjustment: String, Identifiable, CaseIterable {
    case levels
    case gaussianBlur
    case liquify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .levels:       "Levels"
        case .gaussianBlur: "Gaussian Blur"
        case .liquify:      "Liquify"
        }
    }

    var systemImage: String {
        switch self {
        case .levels:       "chart.bar.xaxis"
        case .gaussianBlur: "drop.circle"
        case .liquify:      "hand.point.up.left"
        }
    }

    /// What a layer made by this adjustment is called — "Photo (Levels)".
    var suffix: String { title }
}

// MARK: - The picture an adjustment works on

/// A layer's raster: the picture (`.image`) or painted pixels (`.pixels`).
/// Text and symbol layers are not rasters and are never rasterized behind his back —
/// "no rasterization please unless specifically asked to by the user" (2026-10-03).
struct AdjustmentSource {
    enum Kind { case image, pixels }
    let layerIndex: Int
    let layerID: ImageLayer.ID
    let kind: Kind
    let png: Data
    let cgImage: CGImage
}

extension ImageDocument {
    /// The active layer's picture, if it has one.
    func adjustmentSource(layerID: ImageLayer.ID?) -> AdjustmentSource? {
        guard let id = layerID, let idx = layers.firstIndex(where: { $0.id == id }) else { return nil }
        for el in layers[idx].elements {
            switch el.content {
            case .image(let c) where !c.pngData.isEmpty:
                if let cg = decodeCGImage(c.pngData) {
                    return AdjustmentSource(layerIndex: idx, layerID: id, kind: .image, png: c.pngData, cgImage: cg)
                }
            case .pixels(let p) where !p.pngData.isEmpty:
                if let cg = decodeCGImage(p.pngData) {
                    return AdjustmentSource(layerIndex: idx, layerID: id, kind: .pixels, png: p.pngData, cgImage: cg)
                }
            default:
                continue
            }
        }
        return nil
    }

    /// Put an adjusted picture on a NEW layer directly above the source and hide the
    /// source. The new layer is a full copy — same placement, glow, blend, link group — so
    /// nothing jumps; only the picture changes. Records one History step.
    @discardableResult
    func applyAdjustment(_ adjustment: Adjustment, source: AdjustmentSource, result: CGImage) -> ImageLayer.ID? {
        guard layers.indices.contains(source.layerIndex),
              layers[source.layerIndex].id == source.layerID,
              let png = pngData(from: result) else { return nil }
        captureHistoryBaselineIfNeeded()
        var copy = layers[source.layerIndex]
        copy.id = UUID()
        copy.isVisible = true
        let (words, _) = ImageLayer.splitLabel(copy.name)
        copy.name = "\(words.isEmpty ? copy.name : words) (\(adjustment.suffix))"
        copy.nameLinkedToText = false
        var replaced = false
        copy.elements = copy.elements.map { el in
            guard !replaced else { return el }
            switch (el.content, source.kind) {
            case (.image, .image):
                replaced = true
                return LayerElement(content: .image(ImageContent(pngData: png)))
            case (.pixels, .pixels):
                replaced = true
                return LayerElement(content: .pixels(PixelContent(pngData: png)))
            default:
                return el
            }
        }
        guard replaced else { return nil }
        layers[source.layerIndex].isVisible = false          // kept, re-showable
        layers.insert(copy, at: source.layerIndex + 1)       // directly above
        recordHistory(toolID: Tool.adjust.rawValue, groupTitle: Tool.adjust.title,
                      actionLabel: adjustment.title, layerID: copy.id)
        return copy.id
    }

    /// The Mask tool's selection, projected onto THIS layer's own pixels: white inside the
    /// mask, clear outside, at the picture's resolution. nil when there is no mask.
    ///
    /// A picture layer sits on the canvas by its transform (center, scale, rotation,
    /// fitted inside a square of the canvas's short edge); painted pixels always fill the
    /// canvas. So the canvas-space silhouette is carried into picture space by the inverse
    /// of exactly what ImageCompositeView does to draw it — the same math as
    /// `imagePixel(forCanvasPoint:…)`, run as one affine transform over the whole path.
    func selectionMask(for source: AdjustmentSource) -> CGImage? {
        guard let mask = cropMask, layers.indices.contains(source.layerIndex) else { return nil }
        let w = source.cgImage.width, h = source.cgImage.height
        let canvas = CGSize(width: max(1, canvasWidth), height: max(1, canvasHeight))
        let path = mask.silhouette(in: canvas).cgPath

        let toPicture: CGAffineTransform
        switch source.kind {
        case .pixels:
            toPicture = CGAffineTransform(scaleX: CGFloat(w) / canvas.width, y: CGFloat(h) / canvas.height)
        case .image:
            let t = layers[source.layerIndex].transform
            let frame = min(canvas.width, canvas.height) * t.scale
            let a = CGFloat(w) / CGFloat(h)
            let dispW = a >= 1 ? frame : frame * a
            let dispH = a >= 1 ? frame / a : frame
            guard dispW > 0, dispH > 0 else { return nil }
            let rad = -t.rotationDegrees * .pi / 180
            toPicture = CGAffineTransform(translationX: -t.center.x * canvas.width, y: -t.center.y * canvas.height)
                .concatenating(CGAffineTransform(rotationAngle: rad))
                .concatenating(CGAffineTransform(translationX: dispW / 2, y: dispH / 2))
                .concatenating(CGAffineTransform(scaleX: CGFloat(w) / dispW, y: CGFloat(h) / dispH))
        }
        var tf = toPicture
        guard let inPicture = path.copy(using: &tf) else { return nil }

        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // The path is top-left origin; the context is bottom-left.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.addPath(inPicture)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        return ctx.makeImage()
    }
}

/// Decode PNG bytes to a CGImage.
func decodeCGImage(_ data: Data) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// A smaller copy for live preview — big pictures stay interactive while dragging; the
/// full-resolution picture is processed once, on OK.
func previewCopy(of cg: CGImage, maxDimension: Int = 1024) -> CGImage {
    downscaledCGImage(cg, maxDimension: maxDimension) ?? cg
}

// MARK: - Core Image plumbing

/// Off the main actor — the work runs in a background task so the window never stalls.
nonisolated enum AdjustmentEngine {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Gaussian blur of `radius` pixels. Edges are clamped first so the border does not
    /// fade to transparent, then cropped back to the picture. With a selection mask the
    /// blur only shows inside it — his test in the video blurred a lasso around a face.
    static func gaussianBlur(_ cg: CGImage, radius: Double, mask: CGImage?) -> CGImage? {
        let input = CIImage(cgImage: cg)
        let extent = input.extent
        guard radius > 0 else { return cg }
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: extent)
        let out: CIImage
        if let mask {
            let m = CIImage(cgImage: mask)
                .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(mask.width),
                                                   y: extent.height / CGFloat(mask.height)))
            out = blurred.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: input,
                kCIInputMaskImageKey: m,
            ])
        } else {
            out = blurred
        }
        return context.createCGImage(out, from: extent)
    }
}

// MARK: - The Adjust tool's inspector

/// The strip tool. Three buttons, each opening its window; the same three live in the
/// Mac's Image and Filter menus (⌘L, ⇧⌘X).
struct AdjustInspector: View {
    @Bindable var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

    private var hasPicture: Bool { document.adjustmentSource(layerID: activeLayerID) != nil }

    var body: some View {
        if hasPicture {
            VStack(alignment: .leading, spacing: 14) {
                InfoTip("More about this", "Each opens its own window with a live preview. Nothing changes until you press OK.")
                ForEach(Adjustment.allCases) { a in
                    Button { document.adjustmentRequested = a } label: {
                        Label("\(a.title)…", systemImage: a.systemImage)
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                if document.cropMask != nil {
                    Text("Gaussian Blur stays inside the Mask.")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Text("The result goes on a new layer above. Your original is hidden, never overwritten.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            PanelPlaceholder(systemImage: "slider.horizontal.3",
                             title: "Adjust",
                             subtitle: "Select a layer that has a picture or painted pixels on it")
        }
    }
}

// MARK: - Window chrome shared by the three

/// Title, the live preview, the controls, and Cancel / OK.
struct AdjustmentWindow<Preview: View, Controls: View>: View {
    let title: String
    var working: Bool = false
    var problem: String? = nil
    let onCancel: () -> Void
    let onApply: () -> Void
    @ViewBuilder var preview: Preview
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .semibold))
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Checkerboard())
                .clipShape(RoundedRectangle(cornerRadius: 8))
            controls
            if let problem {
                Text(problem).font(.system(size: 18)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Working…" : "OK", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
            }
            .font(.system(size: 18))
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 640, idealHeight: 760)
        #endif
    }
}

/// Which window is open — set by the inspector or a menu, read by the editor.
struct AdjustmentSheetHost: View {
    @Bindable var document: ImageDocument
    let adjustment: Adjustment
    let activeLayerID: ImageLayer.ID?
    let dismiss: () -> Void

    var body: some View {
        if let source = document.adjustmentSource(layerID: activeLayerID) {
            switch adjustment {
            case .gaussianBlur:
                GaussianBlurWindow(document: document, source: source, dismiss: dismiss)
            case .levels:
                LevelsWindow(document: document, source: source, dismiss: dismiss)
            case .liquify:
                LiquifyWindow(document: document, source: source, dismiss: dismiss)
            }
        } else {
            VStack(spacing: 14) {
                Text("Select a layer that has a picture or painted pixels on it.")
                    .font(.system(size: 18))
                Button("Close", action: dismiss).keyboardShortcut(.defaultAction)
            }
            .padding(30)
        }
    }
}

// MARK: - Gaussian Blur

struct GaussianBlurWindow: View {
    @Bindable var document: ImageDocument
    let source: AdjustmentSource
    let dismiss: () -> Void

    @State private var radius: Double = 6       // his test in the video used 6
    @State private var onlyInMask = true
    @State private var preview: CGImage?
    @State private var working = false
    @State private var problem: String?

    private var small: CGImage { previewCopy(of: source.cgImage) }
    private var hasMask: Bool { document.cropMask != nil }

    var body: some View {
        AdjustmentWindow(title: "Gaussian Blur", working: working, problem: problem,
                         onCancel: dismiss, onApply: apply) {
            if let preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Radius").font(.system(size: 18))
                    Spacer()
                    Text(String(format: "%.1f px", radius)).font(.system(size: 18).monospacedDigit())
                    Stepper("", value: $radius, in: 0...250, step: 0.5).labelsHidden()
                }
                Slider(value: $radius, in: 0...250)
                if hasMask {
                    Toggle("Only inside the Mask", isOn: $onlyInMask).font(.system(size: 18))
                }
            }
        }
        .task(id: "\(radius)-\(onlyInMask)") { await render() }
    }

    /// Preview radius is scaled with the preview, so the preview looks like the result.
    private func render() async {
        let small = self.small
        let scale = Double(small.width) / Double(source.cgImage.width)
        let mask = (hasMask && onlyInMask) ? document.selectionMask(for: source) : nil
        let r = radius * scale
        let out = await Task.detached(priority: .userInitiated) {
            AdjustmentEngine.gaussianBlur(small, radius: r, mask: mask)
        }.value
        if !Task.isCancelled { preview = out }
    }

    private func apply() {
        working = true
        let cg = source.cgImage
        let mask = (hasMask && onlyInMask) ? document.selectionMask(for: source) : nil
        let r = radius
        Task {
            let out = await Task.detached(priority: .userInitiated) {
                AdjustmentEngine.gaussianBlur(cg, radius: r, mask: mask)
            }.value
            working = false
            guard let out, document.applyAdjustment(.gaussianBlur, source: source, result: out) != nil else {
                problem = "The blur could not be applied to this layer."
                return
            }
            dismiss()
        }
    }
}
