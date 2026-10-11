//
//  LiquifyAdjustment.swift
//  Image Producer
//
//  LIQUIFY — brush the picture to PUCKER (pull in toward the brush) or BLOAT (push out
//  from it). Its own window, like Photoshop's and PhotoCraft's.
//
//  From Kirk's PhotoCraft test (2026-10-11), test #4: he puckered his nose and pulled in
//  his hairline, and it was the tool he was most impressed by — "a more advanced tool and
//  the results and the features were almost identical." Brush size and density, as in his
//  test (size 150, density 50).
//
//  HOW IT WORKS. The window keeps a WARP FIELD: for every preview pixel, where in the
//  original picture it should be read from. A brush dab rewrites the field inside the
//  brush; the picture is then re-read through the field. Holding still keeps working,
//  as it does in Photoshop. On OK the field is scaled up to the full-resolution picture
//  and the original is read through it once — so the warp is applied to the original,
//  never to an already-warped, already-resampled copy.
//

import SwiftUI
import CoreGraphics

// MARK: - Warp field

nonisolated struct WarpField: Sendable {
    let w: Int, h: Int
    /// Source x and y for each pixel, in preview pixel units.
    var sx: [Float]
    var sy: [Float]

    init(w: Int, h: Int) {
        self.w = w; self.h = h
        sx = [Float](repeating: 0, count: w * h)
        sy = sx
        reset()
    }

    mutating func reset() {
        for y in 0..<h { for x in 0..<w { sx[y * w + x] = Float(x); sy[y * w + x] = Float(y) } }
    }

    var isIdentity: Bool {
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if abs(sx[i] - Float(x)) > 0.01 || abs(sy[i] - Float(y)) > 0.01 { return false }
        } }
        return true
    }

    /// One dab. Each pixel inside the brush now reads from a point further OUT along its
    /// line from the brush center (pucker — the picture shrinks toward the center) or
    /// further IN (bloat — it swells). Falloff is smooth to zero at the brush edge so no
    /// seam is ever drawn. Returns the rectangle that changed.
    mutating func dab(at c: CGPoint, radius r: Double, strength s: Double, pucker: Bool) -> CGRect {
        let x0 = max(0, Int(c.x - r)), x1 = min(w - 1, Int(c.x + r))
        let y0 = max(0, Int(c.y - r)), y1 = min(h - 1, Int(c.y + r))
        guard x0 <= x1, y0 <= y1, r > 0 else { return .null }
        let old = (sx, sy)
        let r2 = r * r
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) - c.x, dy = Double(y) - c.y
                let d2 = dx * dx + dy * dy
                guard d2 < r2 else { continue }
                let fall = (1 - d2 / r2)
                let k = fall * fall * s * 0.12            // per-dab step; density scales it
                let f = pucker ? 1 + k : 1 - k            // read from further out / further in
                let qx = c.x + dx * f, qy = c.y + dy * f
                let (nx, ny) = Self.sample(old, w: w, h: h, x: qx, y: qy)
                sx[y * w + x] = nx; sy[y * w + x] = ny
            }
        }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }

    /// Bilinear read of the previous field — composing warps rather than stacking them.
    private static func sample(_ f: ([Float], [Float]), w: Int, h: Int, x: Double, y: Double) -> (Float, Float) {
        let cx = min(max(0, x), Double(w - 1)), cy = min(max(0, y), Double(h - 1))
        let ix = Int(cx), iy = Int(cy)
        let jx = min(ix + 1, w - 1), jy = min(iy + 1, h - 1)
        let tx = Float(cx - Double(ix)), ty = Float(cy - Double(iy))
        func lerp(_ a: [Float]) -> Float {
            let a00 = a[iy * w + ix], a10 = a[iy * w + jx], a01 = a[jy * w + ix], a11 = a[jy * w + jx]
            return (a00 * (1 - tx) + a10 * tx) * (1 - ty) + (a01 * (1 - tx) + a11 * tx) * ty
        }
        return (lerp(f.0), lerp(f.1))
    }
}

nonisolated enum LiquifyEngine {
    /// Read `src` (premultiplied RGBA bytes) through the field into `dst`, inside `rect`.
    /// `scale` maps field units to source pixels (1 for the preview; full/preview on OK).
    static func render(field: WarpField, src: [UInt8], sw: Int, sh: Int,
                       into dst: inout [UInt8], dw: Int, dh: Int, rect: CGRect? = nil) {
        let fx = Double(field.w) / Double(dw), fy = Double(field.h) / Double(dh)
        let scaleX = Double(sw) / Double(field.w), scaleY = Double(sh) / Double(field.h)
        let r = rect ?? CGRect(x: 0, y: 0, width: dw, height: dh)
        let x0 = max(0, Int(r.minX)), x1 = min(dw - 1, Int(r.maxX))
        let y0 = max(0, Int(r.minY)), y1 = min(dh - 1, Int(r.maxY))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                // Where this output pixel reads from, via the (bilinear) field.
                let gx = min(Double(field.w - 1), (Double(x) + 0.5) * fx - 0.5)
                let gy = min(Double(field.h - 1), (Double(y) + 0.5) * fy - 0.5)
                let ix = max(0, Int(gx)), iy = max(0, Int(gy))
                let jx = min(ix + 1, field.w - 1), jy = min(iy + 1, field.h - 1)
                let tx = max(0, gx - Double(ix)), ty = max(0, gy - Double(iy))
                func lerp(_ a: [Float]) -> Double {
                    let a00 = Double(a[iy * field.w + ix]), a10 = Double(a[iy * field.w + jx])
                    let a01 = Double(a[jy * field.w + ix]), a11 = Double(a[jy * field.w + jx])
                    return (a00 * (1 - tx) + a10 * tx) * (1 - ty) + (a01 * (1 - tx) + a11 * tx) * ty
                }
                let px = (lerp(field.sx) + 0.5) * scaleX - 0.5
                let py = (lerp(field.sy) + 0.5) * scaleY - 0.5
                bilinearPixel(src, sw, sh, px, py, into: &dst, at: (y * dw + x) * 4)
            }
        }
    }

    @inline(__always)
    private static func bilinearPixel(_ s: [UInt8], _ w: Int, _ h: Int, _ x: Double, _ y: Double,
                                      into d: inout [UInt8], at o: Int) {
        let cx = min(max(0, x), Double(w - 1)), cy = min(max(0, y), Double(h - 1))
        let ix = Int(cx), iy = Int(cy)
        let jx = min(ix + 1, w - 1), jy = min(iy + 1, h - 1)
        let tx = cx - Double(ix), ty = cy - Double(iy)
        let i00 = (iy * w + ix) * 4, i10 = (iy * w + jx) * 4, i01 = (jy * w + ix) * 4, i11 = (jy * w + jx) * 4
        for c in 0..<4 {
            let v = (Double(s[i00 + c]) * (1 - tx) + Double(s[i10 + c]) * tx) * (1 - ty)
                  + (Double(s[i01 + c]) * (1 - tx) + Double(s[i11 + c]) * tx) * ty
            d[o + c] = UInt8(max(0, min(255, v.rounded())))
        }
    }

    /// Full-resolution result: the original read once through the field.
    static func apply(field: WarpField, to cg: CGImage) -> CGImage? {
        guard let src = rgbaBytes(from: cg) else { return nil }
        var dst = [UInt8](repeating: 0, count: src.w * src.h * 4)
        render(field: field, src: src.bytes, sw: src.w, sh: src.h, into: &dst, dw: src.w, dh: src.h)
        return cgImage(fromRGBA: dst, w: src.w, h: src.h)
    }
}

// MARK: - Window

struct LiquifyWindow: View {
    @Bindable var document: ImageDocument
    let source: AdjustmentSource
    let dismiss: () -> Void

    enum Mode: String, CaseIterable, Identifiable { case pucker = "Pucker", bloat = "Bloat"; var id: String { rawValue } }

    @State private var mode: Mode = .pucker
    /// Brush size in FULL-picture pixels (his test: 150) and density 0…100 (his test: 50).
    @State private var brushSize: Double = 150
    @State private var density: Double = 50

    @State private var field: WarpField?
    @State private var srcBytes: [UInt8] = []
    @State private var outBytes: [UInt8] = []
    @State private var pw = 0
    @State private var ph = 0
    @State private var preview: CGImage?
    @State private var hover: CGPoint?
    @State private var pressing: CGPoint?
    @State private var holdTimer: Timer?
    @State private var lastDab: CGPoint?
    @State private var working = false
    @State private var problem: String?

    /// Full-picture pixels per preview pixel.
    private var ratio: Double { Double(source.cgImage.width) / Double(max(1, pw)) }

    var body: some View {
        AdjustmentWindow(title: "Liquify", working: working, problem: problem,
                         onCancel: { stopHold(); dismiss() }, onApply: apply) {
            canvas
        } controls: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Picker("Tool", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Label(m.rawValue, systemImage: m == .pucker
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    Spacer()
                    Button("Restore All") { resetField() }
                        .disabled(field?.isIdentity ?? true)
                }
                labeled("Brush size", "\(Int(brushSize)) px") {
                    Slider(value: $brushSize, in: 5...1500)
                }
                labeled("Density", "\(Int(density))") {
                    Slider(value: $density, in: 1...100)
                }
                Text("Drag to \(mode == .pucker ? "pull the picture in" : "push the picture out"). Hold still to keep going.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 18))
        }
        .onAppear(perform: prepare)
        .onDisappear(perform: stopHold)
    }

    private func labeled<C: View>(_ label: String, _ value: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            c()
            Text(value).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            if let preview {
                let fit = fittedRect(CGSize(width: pw, height: ph), in: geo.size)
                let viewPerPreviewPx = fit.width / CGFloat(max(1, pw))
                ZStack(alignment: .topLeading) {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                    if let h = hover ?? pressing {
                        let d = brushSize / ratio * viewPerPreviewPx
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 0.5).padding(1.5))
                            .frame(width: d, height: d)
                            .position(h)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        pressing = v.location
                        hover = v.location
                        stroke(to: v.location, fit: fit)
                        startHold(fit: fit)
                    }
                    .onEnded { _ in pressing = nil; lastDab = nil; stopHold() })
                #if os(macOS)
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hover = p } else { hover = nil }
                }
                #endif
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fittedRect(_ image: CGSize, in box: CGSize) -> CGRect {
        let s = min(box.width / max(1, image.width), box.height / max(1, image.height))
        let w = image.width * s, h = image.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    // MARK: Brushing

    /// Dabs spaced along the drag (a quarter of the brush apart), so a fast stroke is as
    /// even as a slow one.
    private func stroke(to viewPoint: CGPoint, fit: CGRect) {
        let p = toPreview(viewPoint, fit: fit)
        let r = brushSize / ratio / 2
        let spacing = max(1, r / 4)
        if let last = lastDab {
            let dist = hypot(p.x - last.x, p.y - last.y)
            guard dist >= spacing else { return }
            let n = Int(dist / spacing)
            for i in 1...n {
                let t = Double(i) / Double(n)
                dab(at: CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t))
            }
        } else {
            dab(at: p)
        }
        lastDab = p
    }

    private func toPreview(_ v: CGPoint, fit: CGRect) -> CGPoint {
        CGPoint(x: (v.x - fit.minX) / fit.width * CGFloat(pw), y: (v.y - fit.minY) / fit.height * CGFloat(ph))
    }

    private func dab(at p: CGPoint) {
        guard var f = field else { return }
        let r = brushSize / ratio / 2
        let changed = f.dab(at: p, radius: r, strength: density / 50, pucker: mode == .pucker)
        field = f
        guard !changed.isNull else { return }
        LiquifyEngine.render(field: f, src: srcBytes, sw: pw, sh: ph, into: &outBytes, dw: pw, dh: ph, rect: changed)
        preview = cgImage(fromRGBA: outBytes, w: pw, h: ph)
    }

    /// Holding the brush still keeps puckering / bloating, as Photoshop's does.
    private func startHold(fit: CGRect) {
        guard holdTimer == nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let p = pressing else { return }
                dab(at: toPreview(p, fit: fit))
            }
        }
    }

    private func stopHold() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    // MARK: Setup / apply

    private func prepare() {
        let small = previewCopy(of: source.cgImage, maxDimension: 900)
        guard let px = rgbaBytes(from: small) else { problem = "This picture could not be read."; return }
        pw = px.w; ph = px.h
        srcBytes = px.bytes
        outBytes = px.bytes
        field = WarpField(w: pw, h: ph)
        preview = small
    }

    private func resetField() {
        field = WarpField(w: pw, h: ph)
        outBytes = srcBytes
        preview = cgImage(fromRGBA: outBytes, w: pw, h: ph)
    }

    private func apply() {
        stopHold()
        guard let f = field, !f.isIdentity else { dismiss(); return }
        working = true
        let cg = source.cgImage
        Task {
            let out = await Task.detached(priority: .userInitiated) { LiquifyEngine.apply(field: f, to: cg) }.value
            working = false
            guard let out, document.applyAdjustment(.liquify, source: source, result: out) != nil else {
                problem = "Liquify could not be applied to this layer."
                return
            }
            dismiss()
        }
    }
}
