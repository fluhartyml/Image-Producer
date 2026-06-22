//
//  ColorMask.swift
//  Image Producer
//
//  The selection-subsystem keystone, first slice (Michael 2026-06-21):
//    • EYEDROPPER with an averaged CIRCLE sampler (sample-size slider) — picks a
//      representative color instead of one noisy pixel. Feeds `fillColor`, shared
//      with the Paint Bucket and the Magic Eraser. (His "humans see different
//      shades" point: sample the real background shade, averaged.)
//    • MAGIC ERASER (the "color mask") in the Eraser tool — takes the eyedropper's
//      color + a tolerance and clears matching pixels to transparent. Two modes:
//        GLOBAL     — every matching pixel anywhere goes clear.
//        CONTIGUOUS — flood from the image BORDER inward, so only background that
//                     touches an edge clears; matching pixels fully enclosed by the
//                     subject (interior whites) survive. Best for "knock out the bg."
//
//  Operates on the active layer's stored image raster (the AI/imported image), then
//  setImage() puts the masked result back — the layer's transform is preserved.
//
//  ⚠️ Honest limits (v1): pixels are read premultiplied, so the color compare is
//  exact only for OPAQUE pixels (fine for an opaque AI background) — soft/anti-
//  aliased edges can leave a faint fringe. Targets image-element layers (the AI
//  case); pixel-only layers come later. Compile-verified; pixel results need a
//  device run. See memory project_image_producer_playground_paste_workaround.
//

import SwiftUI
import CoreGraphics
import ImageIO

// MARK: - Pixel buffer helpers

/// RGBA8 bytes (sRGB, premultiplied-last) for a CGImage, plus its dimensions.
func rgbaBytes(from cg: CGImage) -> (bytes: [UInt8], w: Int, h: Int)? {
    let w = cg.width, h = cg.height
    guard w > 0, h > 0 else { return nil }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let count = w * h * 4
    let buf = data.bindMemory(to: UInt8.self, capacity: count)
    return (Array(UnsafeBufferPointer(start: buf, count: count)), w, h)
}

/// Build a CGImage back from RGBA8 bytes.
func cgImage(fromRGBA bytes: [UInt8], w: Int, h: Int) -> CGImage? {
    guard bytes.count == w * h * 4 else { return nil }
    var mutable = bytes
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return mutable.withUnsafeMutableBytes { ptr -> CGImage? in
        guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return ctx.makeImage()
    }
}

/// Average the opaque pixels inside a circle (radius in pixels) around a normalized
/// point — the eyedropper's sample. radius 0 = a single pixel (point sample).
func averagedColor(in cg: CGImage, atNormalized p: CGPoint, radiusPixels: Int) -> Color? {
    guard let (bytes, w, h) = rgbaBytes(from: cg) else { return nil }
    let cx = Int(p.x * CGFloat(w)), cy = Int(p.y * CGFloat(h))
    let rad = max(0, radiusPixels)
    var rs = 0, gs = 0, bs = 0, n = 0
    for dy in -rad...rad {
        for dx in -rad...rad where dx * dx + dy * dy <= rad * rad {
            let x = cx + dx, y = cy + dy
            guard x >= 0, x < w, y >= 0, y < h else { continue }
            let i = (y * w + x) * 4
            guard bytes[i + 3] > 0 else { continue }        // skip transparent
            rs += Int(bytes[i]); gs += Int(bytes[i + 1]); bs += Int(bytes[i + 2]); n += 1
        }
    }
    guard n > 0 else { return nil }
    return Color(.sRGB, red: Double(rs / n) / 255, green: Double(gs / n) / 255, blue: Double(bs / n) / 255)
}

/// Clear pixels matching `target` (± tolerance per channel) to transparent.
/// contiguous = flood from the image border inward (keeps enclosed interior matches);
/// otherwise every matching pixel goes clear.
func colorMaskedImage(_ cg: CGImage, target: (r: UInt8, g: UInt8, b: UInt8),
                      tolerance: Int, contiguous: Bool) -> CGImage? {
    guard let (src, w, h) = rgbaBytes(from: cg) else { return nil }
    var bytes = src
    @inline(__always) func matches(_ i: Int) -> Bool {
        bytes[i + 3] > 0 &&
        abs(Int(bytes[i])     - Int(target.r)) <= tolerance &&
        abs(Int(bytes[i + 1]) - Int(target.g)) <= tolerance &&
        abs(Int(bytes[i + 2]) - Int(target.b)) <= tolerance
    }
    @inline(__always) func clear(_ i: Int) { bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0 }

    if contiguous {
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        @inline(__always) func seed(_ x: Int, _ y: Int) {
            let p = y * w + x
            if !visited[p] { visited[p] = true; stack.append(p) }
        }
        for x in 0..<w { seed(x, 0); seed(x, h - 1) }
        for y in 0..<h { seed(0, y); seed(w - 1, y) }
        while let p = stack.popLast() {
            let i = p * 4
            guard matches(i) else { continue }
            clear(i)
            let x = p % w, y = p / w
            if x > 0 { seed(x - 1, y) }
            if x < w - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < h - 1 { seed(x, y + 1) }
        }
    } else {
        var i = 0
        while i < bytes.count { if matches(i) { clear(i) }; i += 4 }
    }
    return cgImage(fromRGBA: bytes, w: w, h: h)
}

/// Downscale a CGImage so its longest side ≤ `maxDimension` (aspect preserved) — used
/// to make the live preview cheap. Returns the original if it's already small enough.
func downscaledCGImage(_ cg: CGImage, maxDimension: Int) -> CGImage? {
    let w = cg.width, h = cg.height
    let longSide = max(w, h)
    guard longSide > maxDimension, longSide > 0 else { return cg }
    let f = Double(maxDimension) / Double(longSide)
    let nw = max(1, Int((Double(w) * f).rounded()))
    let nh = max(1, Int((Double(h) * f).rounded()))
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                              bytesPerRow: nw * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .low
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
    return ctx.makeImage()
}

/// LIVE-PREVIEW twin of `colorMaskedImage`: instead of clearing matched pixels, it
/// paints them with `highlight` and leaves everything else transparent — so the canvas
/// can overlay exactly what an Erase would remove. SAME match + contiguous semantics as
/// the real mask, so what lights up is what gets cleared. (Michael 2026-06-21: the
/// tolerance slider must be "wired to a visual element" — tune by eye, not blind.)
func matchHighlightImage(_ cg: CGImage, target: (r: UInt8, g: UInt8, b: UInt8),
                         tolerance: Int, contiguous: Bool,
                         highlight: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> CGImage? {
    guard let (src, w, h) = rgbaBytes(from: cg) else { return nil }
    var out = [UInt8](repeating: 0, count: w * h * 4)        // all transparent
    @inline(__always) func matches(_ i: Int) -> Bool {
        src[i + 3] > 0 &&
        abs(Int(src[i])     - Int(target.r)) <= tolerance &&
        abs(Int(src[i + 1]) - Int(target.g)) <= tolerance &&
        abs(Int(src[i + 2]) - Int(target.b)) <= tolerance
    }
    @inline(__always) func mark(_ i: Int) {
        out[i] = highlight.r; out[i + 1] = highlight.g; out[i + 2] = highlight.b; out[i + 3] = highlight.a
    }
    if contiguous {
        var visited = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        @inline(__always) func seed(_ x: Int, _ y: Int) {
            let p = y * w + x
            if !visited[p] { visited[p] = true; stack.append(p) }
        }
        for x in 0..<w { seed(x, 0); seed(x, h - 1) }
        for y in 0..<h { seed(0, y); seed(w - 1, y) }
        while let p = stack.popLast() {
            let i = p * 4
            guard matches(i) else { continue }
            mark(i)
            let x = p % w, y = p / w
            if x > 0 { seed(x - 1, y) }
            if x < w - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < h - 1 { seed(x, y + 1) }
        }
    } else {
        var i = 0
        while i < out.count { if matches(i) { mark(i) }; i += 4 }
    }
    return cgImage(fromRGBA: out, w: w, h: h)
}

/// Seeded FLOOD FILL (Paint Bucket): from `seed` (image pixels), replace the contiguous
/// region of pixels matching the seed's color (± tolerance) with `fill`. Confined by color
/// edges — lines/walls of a different color stop the flood (the "dam/dyke walls"). Shares
/// the contiguous core with the Magic Eraser, but seeded from the tap and painting a color
/// instead of clearing. nil on bad input / seed out of bounds.
func floodFilledImage(_ cg: CGImage, seed: CGPoint, tolerance: Int,
                      fill: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> CGImage? {
    guard let (src, w, h) = rgbaBytes(from: cg) else { return nil }
    var bytes = src
    let sx = Int(seed.x), sy = Int(seed.y)
    guard sx >= 0, sx < w, sy >= 0, sy < h else { return nil }
    let si = (sy * w + sx) * 4
    let t = (r: src[si], g: src[si + 1], b: src[si + 2], a: src[si + 3])   // seed color (from original)
    @inline(__always) func matches(_ i: Int) -> Bool {
        abs(Int(src[i])     - Int(t.r)) <= tolerance &&
        abs(Int(src[i + 1]) - Int(t.g)) <= tolerance &&
        abs(Int(src[i + 2]) - Int(t.b)) <= tolerance &&
        abs(Int(src[i + 3]) - Int(t.a)) <= tolerance
    }
    var visited = [Bool](repeating: false, count: w * h)
    var stack = [sy * w + sx]; visited[sy * w + sx] = true
    while let p = stack.popLast() {
        let i = p * 4
        guard matches(i) else { continue }
        bytes[i] = fill.r; bytes[i + 1] = fill.g; bytes[i + 2] = fill.b; bytes[i + 3] = fill.a
        let x = p % w, y = p / w
        if x > 0,     !visited[p - 1] { visited[p - 1] = true; stack.append(p - 1) }
        if x < w - 1, !visited[p + 1] { visited[p + 1] = true; stack.append(p + 1) }
        if y > 0,     !visited[p - w] { visited[p - w] = true; stack.append(p - w) }
        if y < h - 1, !visited[p + w] { visited[p + w] = true; stack.append(p + w) }
    }
    return cgImage(fromRGBA: bytes, w: w, h: h)
}

/// LIVE-PREVIEW twin of `floodFilledImage`: mark the region a tap would fill (seed +
/// tolerance) with `highlight`, rest transparent — so the bucket's fill area is visible
/// before you commit, exactly like the Magic Eraser's highlight.
func floodHighlightImage(_ cg: CGImage, seed: CGPoint, tolerance: Int,
                         highlight: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> CGImage? {
    guard let (src, w, h) = rgbaBytes(from: cg) else { return nil }
    let sx = Int(seed.x), sy = Int(seed.y)
    guard sx >= 0, sx < w, sy >= 0, sy < h else { return nil }
    let si = (sy * w + sx) * 4
    let t = (r: src[si], g: src[si + 1], b: src[si + 2], a: src[si + 3])
    var out = [UInt8](repeating: 0, count: w * h * 4)
    @inline(__always) func matches(_ i: Int) -> Bool {
        abs(Int(src[i])     - Int(t.r)) <= tolerance &&
        abs(Int(src[i + 1]) - Int(t.g)) <= tolerance &&
        abs(Int(src[i + 2]) - Int(t.b)) <= tolerance &&
        abs(Int(src[i + 3]) - Int(t.a)) <= tolerance
    }
    var visited = [Bool](repeating: false, count: w * h)
    var stack = [sy * w + sx]; visited[sy * w + sx] = true
    while let p = stack.popLast() {
        let i = p * 4
        guard matches(i) else { continue }
        out[i] = highlight.r; out[i + 1] = highlight.g; out[i + 2] = highlight.b; out[i + 3] = highlight.a
        let x = p % w, y = p / w
        if x > 0,     !visited[p - 1] { visited[p - 1] = true; stack.append(p - 1) }
        if x < w - 1, !visited[p + 1] { visited[p + 1] = true; stack.append(p + 1) }
        if y > 0,     !visited[p - w] { visited[p - w] = true; stack.append(p - w) }
        if y < h - 1, !visited[p + w] { visited[p + w] = true; stack.append(p + w) }
    }
    return cgImage(fromRGBA: out, w: w, h: h)
}

/// Map a canvas point (in canvas points, 0…side) to a pixel in a layer's image element,
/// inverting the layer transform (center / rotation / scale) and the `scaledToFit` letterbox.
/// Returns nil if the point falls outside the displayed image. Used by the manual brush
/// eraser so a drag clears the right pixels even on a moved/rotated/scaled layer.
func imagePixel(forCanvasPoint p: CGPoint, side: CGFloat, transform t: LayerTransform,
                imageW: Int, imageH: Int) -> CGPoint? {
    guard imageW > 0, imageH > 0 else { return nil }
    // 1. relative to the layer's center
    let dx = p.x - t.center.x * side
    let dy = p.y - t.center.y * side
    // 2. un-rotate (inverse of the view's rotationEffect)
    let rad = -t.rotationDegrees * .pi / 180
    let cosA = cos(rad), sinA = sin(rad)
    let rx = dx * cosA - dy * sinA
    let ry = dx * sinA + dy * cosA
    // 3. the image's displayed rect (scaledToFit inside a side*scale square)
    let frame = side * t.scale
    let a = Double(imageW) / Double(imageH)
    let dispW = a >= 1 ? frame : frame * a
    let dispH = a >= 1 ? frame / a : frame
    guard dispW > 0, dispH > 0 else { return nil }
    // 4. local (origin at center) → normalized 0…1 → image pixels
    let u = (Double(rx) + dispW / 2) / dispW
    let v = (Double(ry) + dispH / 2) / dispH
    guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }
    return CGPoint(x: u * Double(imageW), y: v * Double(imageH))
}

extension Color {
    /// 0–255 RGB for pixel comparison (best-effort via the platform CGColor).
    var rgb8: (r: UInt8, g: UInt8, b: UInt8) {
        let cg = self.platformCGColor
        guard let comps = cg.components, comps.count >= 3 else { return (255, 255, 255) }
        func c(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
        return (c(comps[0]), c(comps[1]), c(comps[2]))
    }
}

// MARK: - Eyedropper inspector (Tool #5)

/// The eyedropper's controls: a SAMPLE-SIZE slider (point → averaged circle) and a
/// swatch of the currently-picked color. Sampling itself happens on the canvas
/// (tap with the eyedropper active) — see CanvasView. The picked color is `fillColor`,
/// shared with the Paint Bucket and the Magic Eraser.
struct EyedropperInspector: View {
    @EnvironmentObject var pen: PixelPen
    @Binding var fillColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap the canvas to sample a color. The circle averages the pixels under it — grow it for a steadier read of a soft background.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sample size  \(pen.eyedropperRadius == 0 ? "point" : "\(pen.eyedropperRadius * 2 + 1) px")")
                    .font(.subheadline)
                Slider(value: Binding(get: { Double(pen.eyedropperRadius) },
                                      set: { pen.eyedropperRadius = Int($0.rounded()) }),
                       in: 0...24, step: 1)
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                Text("Picked color").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Eraser inspector (Tool #4) — Magic Eraser (color mask)

/// Magic Eraser: clears pixels matching the picked color (the eyedropper's `fillColor`)
/// to transparent on the active image layer. Tolerance widens the match; Contiguous
/// keeps interior matches by flooding only from the border. (Manual pixel-erase +
/// Magic Select are later slices off the same core.)
struct EraserInspector: View {
    @ObservedObject var document: IconDocument
    let activeLayerID: IconLayer.ID?
    @Binding var fillColor: Color
    /// Tolerance + contiguity live on the pen so the canvas can draw the live highlight.
    @EnvironmentObject var pen: PixelPen

    @State private var failed = false

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    /// (index, image PNG) of the active content layer's image element, if any.
    private var activeImage: (idx: Int, png: Data)? {
        guard let idx = activeIndex else { return nil }
        for el in document.layers[idx].elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { return (idx, img.pngData) }
        }
        return nil
    }

    var body: some View {
        if activeImage != nil {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Eraser mode", selection: $pen.eraserMode) {
                    Text("Brush").tag(EraserMode.brush)
                    Text("Magic").tag(EraserMode.magic)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if pen.eraserMode == .brush { brushControls } else { magicControls }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            PanelPlaceholder(systemImage: "eraser",
                             title: "Eraser",
                             subtitle: "Select a layer that holds an image, then erase it — Brush wipes pixels by hand, Magic knocks a background color out to transparent.")
        }
    }

    /// Manual brush eraser — drag on the canvas; the first stroke auto-copies the layer.
    @ViewBuilder private var brushControls: some View {
        Text("Manual eraser — wipe pixels to transparent").font(.subheadline).bold()
        Text("Drag on the canvas to erase. The first stroke automatically copies the layer and erases the copy — your original is kept (hidden), since there's no undo yet.")
            .font(.caption).foregroundStyle(.secondary)

        Picker("Shape", selection: $pen.eraserSquare) {
            Text("Circle").tag(false)
            Text("Square").tag(true)
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading, spacing: 4) {
            Text("Brush size  \(Int(pen.eraserBrushFraction * 1024)) px").font(.subheadline)
            Slider(value: $pen.eraserBrushFraction, in: 0.004...0.4)
        }
    }

    /// Magic Eraser — color mask, with the live magenta highlight on the canvas.
    @ViewBuilder private var magicControls: some View {
        Text("Magic Eraser — color mask").font(.subheadline).bold()
        Text("Pick the background color with the Eyedropper first. Matching pixels light up magenta on the canvas — raise Tolerance until the whole background lights up, then erase.")
            .font(.caption).foregroundStyle(.secondary)

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(fillColor)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
            Text("Color to erase").font(.caption).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Tolerance  \(Int(pen.eraseTolerance))").font(.subheadline)
            Slider(value: $pen.eraseTolerance, in: 0...160, step: 1)
        }

        Toggle("Contiguous (keep interior matches)", isOn: $pen.eraseContiguous)
            .font(.caption)

        Button(role: .destructive) { apply() } label: {
            Label("Erase Color → Transparent", systemImage: "wand.and.stars.inverse")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)

        if failed {
            Text("Couldn't read this layer's image.").font(.caption).foregroundStyle(.red)
        }
    }

    private func apply() {
        failed = false
        guard let (idx, png) = activeImage,
              let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let masked = colorMaskedImage(cg, target: fillColor.rgb8,
                                            tolerance: Int(pen.eraseTolerance), contiguous: pen.eraseContiguous),
              let out = pngData(from: masked) else { failed = true; return }
        // Non-destructive: the masked result goes on a new layer above; the original
        // (with its background) is hidden, not overwritten — there's no undo.
        document.addResultLayer(out, above: idx, nameSuffix: "erased")
    }
}
