//
//  LevelsAdjustment.swift
//  Image Producer
//
//  LEVELS (⌘L) — input black / gray / white and output black / white, per channel or for
//  all three together, over a live histogram.
//
//  From Kirk's PhotoCraft test (2026-10-11): Levels was test #1, the first thing he does
//  to every photo. PhotoCraft's was "a very basic version" — and he named the two things
//  missing, so both are here:
//    • EYEDROPPERS — pick the black, gray and white points straight off the picture.
//    • ⌥ CLIPPING PREVIEW — hold Option while dragging the black or white slider to see
//      exactly which pixels are being crushed to pure black or blown to pure white.
//  The clipping preview is ALSO a switch in the window, so it never depends on holding a
//  key (iPad without a keyboard; Sticky Keys — feedback_sticky_keys_avoid_modifier_gestures).
//
//  The math is the standard levels curve, per channel:
//      out = outBlack + (outWhite − outBlack) · clamp((in − inBlack) / (inWhite − inBlack))^(1/γ)
//  A single channel's levels run first, then the RGB (all-channel) levels on top.
//

import SwiftUI
import CoreGraphics

// MARK: - Model

nonisolated struct LevelsChannel: Equatable, Sendable {
    var inBlack: Double = 0
    var inWhite: Double = 255
    /// Midtones. 1 = unchanged; above 1 brightens, below darkens (Photoshop's convention).
    var gamma: Double = 1
    var outBlack: Double = 0
    var outWhite: Double = 255

    var isIdentity: Bool { self == LevelsChannel() }

    func map(_ v: Double) -> Double {
        let span = max(1, inWhite - inBlack)
        let x = min(1, max(0, (v - inBlack) / span))
        let y = pow(x, 1 / max(0.01, gamma))
        return outBlack + (outWhite - outBlack) * y
    }
}

nonisolated enum LevelsTarget: String, CaseIterable, Identifiable, Sendable {
    case rgb = "RGB", red = "Red", green = "Green", blue = "Blue"
    var id: String { rawValue }
}

nonisolated struct LevelsSettings: Equatable, Sendable {
    var rgb = LevelsChannel()
    var red = LevelsChannel()
    var green = LevelsChannel()
    var blue = LevelsChannel()

    subscript(_ t: LevelsTarget) -> LevelsChannel {
        get { switch t { case .rgb: rgb; case .red: red; case .green: green; case .blue: blue } }
        set {
            switch t {
            case .rgb: rgb = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }

    var isIdentity: Bool { self == LevelsSettings() }

    /// One 256-entry table per channel: that channel's levels, then the RGB levels.
    func tables() -> (r: [UInt8], g: [UInt8], b: [UInt8]) {
        func table(_ c: LevelsChannel) -> [UInt8] {
            (0..<256).map { v in
                UInt8(max(0, min(255, rgb.map(c.map(Double(v))).rounded())))
            }
        }
        return (table(red), table(green), table(blue))
    }
}

// MARK: - Engine

nonisolated enum LevelsEngine {
    /// 256-bin histograms of the picture: red, green, blue and luminance. Transparent
    /// pixels are skipped — they have no color to count.
    static func histograms(_ cg: CGImage) -> (r: [Int], g: [Int], b: [Int], lum: [Int]) {
        var r = [Int](repeating: 0, count: 256), g = r, b = r, l = r
        guard let px = rgbaUnpremultiplied(cg) else { return (r, g, b, l) }
        let bytes = px.bytes
        var i = 0
        while i < bytes.count {
            if bytes[i + 3] > 0 {
                let rv = Int(bytes[i]), gv = Int(bytes[i + 1]), bv = Int(bytes[i + 2])
                r[rv] += 1; g[gv] += 1; b[bv] += 1
                l[min(255, (rv * 299 + gv * 587 + bv * 114) / 1000)] += 1
            }
            i += 4
        }
        return (r, g, b, l)
    }

    static func apply(_ cg: CGImage, _ s: LevelsSettings) -> CGImage? {
        guard !s.isIdentity else { return cg }
        guard var px = rgbaUnpremultiplied(cg) else { return nil }
        let t = s.tables()
        px.bytes.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                if p[i + 3] > 0 {
                    p[i] = t.r[Int(p[i])]
                    p[i + 1] = t.g[Int(p[i + 1])]
                    p[i + 2] = t.b[Int(p[i + 2])]
                }
                i += 4
            }
        }
        return cgImageUnpremultiplied(px.bytes, w: px.w, h: px.h)
    }

    enum ClipSide: Sendable { case shadows, highlights }

    /// Photoshop's ⌥-drag view. SHADOWS: white where nothing clips, black where every
    /// channel is crushed to the darkest output, colored where only some are.
    /// HIGHLIGHTS: black where nothing clips, white/colored where channels blow out.
    static func clipping(_ cg: CGImage, _ s: LevelsSettings, side: ClipSide) -> CGImage? {
        guard var px = rgbaUnpremultiplied(cg) else { return nil }
        let t = s.tables()
        let lo = (t.r[0], t.g[0], t.b[0]), hi = (t.r[255], t.g[255], t.b[255])
        px.bytes.withUnsafeMutableBufferPointer { p in
            var i = 0
            while i < p.count {
                let r = t.r[Int(p[i])], g = t.g[Int(p[i + 1])], b = t.b[Int(p[i + 2])]
                switch side {
                case .shadows:
                    p[i] = r <= lo.0 ? 0 : 255; p[i + 1] = g <= lo.1 ? 0 : 255; p[i + 2] = b <= lo.2 ? 0 : 255
                case .highlights:
                    p[i] = r >= hi.0 ? 255 : 0; p[i + 1] = g >= hi.1 ? 255 : 0; p[i + 2] = b >= hi.2 ? 255 : 0
                }
                p[i + 3] = 255
                i += 4
            }
        }
        return cgImageUnpremultiplied(px.bytes, w: px.w, h: px.h)
    }

    /// The color under a point (normalized 0…1, top-left origin), averaged over 3×3, as
    /// straight (unpremultiplied) 0…255 values. nil on a transparent spot.
    static func sample(_ cg: CGImage, at n: CGPoint) -> (r: Double, g: Double, b: Double)? {
        guard let px = rgbaUnpremultiplied(cg) else { return nil }
        let cx = Int(n.x * Double(px.w)), cy = Int(n.y * Double(px.h))
        var sr = 0.0, sg = 0.0, sb = 0.0, n9 = 0.0
        for y in (cy - 1)...(cy + 1) where y >= 0 && y < px.h {
            for x in (cx - 1)...(cx + 1) where x >= 0 && x < px.w {
                let i = (y * px.w + x) * 4
                guard px.bytes[i + 3] > 0 else { continue }
                sr += Double(px.bytes[i]); sg += Double(px.bytes[i + 1]); sb += Double(px.bytes[i + 2]); n9 += 1
            }
        }
        guard n9 > 0 else { return nil }
        return (sr / n9, sg / n9, sb / n9)
    }

    // Straight-alpha RGBA, because levels act on COLOR — on premultiplied bytes a
    // half-transparent pixel would be adjusted as if it were darker than it is.
    static func rgbaUnpremultiplied(_ cg: CGImage) -> (bytes: [UInt8], w: Int, h: Int)? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        var out = Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: w * h * 4),
                                            count: w * h * 4))
        var i = 0
        while i < out.count {
            let a = Int(out[i + 3])
            if a > 0 && a < 255 {
                out[i] = UInt8(min(255, Int(out[i]) * 255 / a))
                out[i + 1] = UInt8(min(255, Int(out[i + 1]) * 255 / a))
                out[i + 2] = UInt8(min(255, Int(out[i + 2]) * 255 / a))
            }
            i += 4
        }
        return (out, w, h)
    }

    static func cgImageUnpremultiplied(_ bytes: [UInt8], w: Int, h: Int) -> CGImage? {
        var pre = bytes
        var i = 0
        while i < pre.count {
            let a = Int(pre[i + 3])
            if a < 255 {
                pre[i] = UInt8(Int(pre[i]) * a / 255)
                pre[i + 1] = UInt8(Int(pre[i + 1]) * a / 255)
                pre[i + 2] = UInt8(Int(pre[i + 2]) * a / 255)
            }
            i += 4
        }
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return pre.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}

// MARK: - Window

struct LevelsWindow: View {
    @Bindable var document: ImageDocument
    let source: AdjustmentSource
    let dismiss: () -> Void

    enum Dropper: String { case black, gray, white }
    enum Marker { case inBlack, gamma, inWhite, outBlack, outWhite }

    @State private var settings = LevelsSettings()
    @State private var target: LevelsTarget = .rgb
    @State private var small: CGImage?
    @State private var hist: (r: [Int], g: [Int], b: [Int], lum: [Int])?
    @State private var preview: CGImage?
    @State private var dropper: Dropper?
    @State private var optionHeld = false
    @State private var showClippingSwitch = false
    @State private var dragging: Marker?
    @State private var lastClipSide: LevelsEngine.ClipSide = .shadows
    @State private var working = false
    @State private var problem: String?

    private var channel: Binding<LevelsChannel> {
        Binding(get: { settings[target] }, set: { settings[target] = $0 })
    }

    /// Which clipping view is showing, if any: while Option is held during a black/white
    /// drag, or whenever the switch is on (for the slider touched last).
    private var clipSide: LevelsEngine.ClipSide? {
        if optionHeld, let d = dragging {
            switch d {
            case .inBlack, .outBlack: return .shadows
            case .inWhite, .outWhite: return .highlights
            case .gamma: return nil
            }
        }
        return showClippingSwitch ? lastClipSide : nil
    }

    var body: some View {
        AdjustmentWindow(title: "Levels", working: working, problem: problem,
                         onCancel: dismiss, onApply: apply) {
            previewPane
        } controls: {
            controls
        }
        .onAppear(perform: prepare)
        .task(id: "\(settings.hashKey)-\(String(describing: clipSide))") { await render() }
        #if os(macOS)
        .onModifierKeysChanged(mask: .option, initial: true) { _, new in
            optionHeld = new.contains(.option)
        }
        #endif
    }

    // MARK: Preview (and the eyedroppers' target)

    private var previewPane: some View {
        GeometryReader { geo in
            if let preview {
                let fitted = fittedRect(image: CGSize(width: preview.width, height: preview.height), in: geo.size)
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        guard let dropper else { return }
                        let n = CGPoint(x: (p.x - fitted.minX) / fitted.width, y: (p.y - fitted.minY) / fitted.height)
                        guard n.x >= 0, n.x <= 1, n.y >= 0, n.y <= 1 else { return }
                        pick(dropper, at: n)
                    }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fittedRect(image: CGSize, in box: CGSize) -> CGRect {
        let s = min(box.width / max(1, image.width), box.height / max(1, image.height))
        let w = image.width * s, h = image.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Channel", selection: $target) {
                    ForEach(LevelsTarget.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                dropperButton(.black, "eyedropper.halffull", "Set black point — click the darkest thing that should be pure black")
                dropperButton(.gray, "eyedropper", "Set gray point — click something that should be neutral gray")
                dropperButton(.white, "eyedropper.full", "Set white point — click the brightest thing that should be pure white")
            }
            .font(.system(size: 18))

            Text("Input Levels").font(.system(size: 18)).foregroundStyle(.secondary)
            histogramView.frame(height: 110)
            LevelsMarkerBar(markers: inputMarkers, dragging: $dragging) { marker, x in
                setInput(marker, fraction: x)
            }
            .frame(height: 22)
            HStack {
                numberField("Black", value: channel.inBlack, range: 0...253)
                Spacer()
                numberField("Gray", value: channel.gamma, range: 0.1...9.99, decimals: 2)
                Spacer()
                numberField("White", value: channel.inWhite, range: 2...255)
            }

            Text("Output Levels").font(.system(size: 18)).foregroundStyle(.secondary)
            LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
                .frame(height: 12).clipShape(RoundedRectangle(cornerRadius: 3))
            LevelsMarkerBar(markers: outputMarkers, dragging: $dragging) { marker, x in
                setOutput(marker, fraction: x)
            }
            .frame(height: 22)
            HStack {
                numberField("Black", value: channel.outBlack, range: 0...255)
                Spacer()
                numberField("White", value: channel.outWhite, range: 0...255)
            }

            HStack(spacing: 16) {
                Toggle("Show clipping", isOn: $showClippingSwitch)
                    .help("Hold ⌥ Option while dragging the black or white slider for the same view")
                Text("or hold ⌥ while dragging").foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { settings = LevelsSettings() }
                    .disabled(settings.isIdentity)
            }
            .font(.system(size: 18))
        }
    }

    private func dropperButton(_ d: Dropper, _ icon: String, _ help: String) -> some View {
        Button { dropper = (dropper == d) ? nil : d } label: {
            Image(systemName: icon)
                .foregroundStyle(d == .black ? Color.primary : d == .gray ? Color.gray : Color.secondary)
                .frame(width: 36, height: 30)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(dropper == d ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func numberField(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                             decimals: Int = 0) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 18)).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { value.wrappedValue },
                                            set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }),
                      format: .number.precision(.fractionLength(decimals)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18).monospacedDigit())
                .frame(width: 80)
        }
    }

    private var histogramView: some View {
        Canvas { ctx, size in
            guard let hist else { return }
            let bins: [Int]
            switch target {
            case .rgb: bins = hist.lum
            case .red: bins = hist.r
            case .green: bins = hist.g
            case .blue: bins = hist.b
            }
            // Scale to the 2nd-highest bin so one spike (a flat background) does not
            // flatten everything else into the floor.
            let sorted = bins.sorted(by: >)
            let peak = Double(max(1, sorted.count > 1 ? sorted[1] : sorted.first ?? 1))
            var path = Path()
            let bw = size.width / 256
            for (i, n) in bins.enumerated() {
                let hgt = min(1, Double(n) / peak) * size.height
                path.addRect(CGRect(x: Double(i) * bw, y: size.height - hgt, width: bw + 0.5, height: hgt))
            }
            let color: Color = target == .red ? .red : target == .green ? .green : target == .blue ? .blue : .primary
            ctx.fill(path, with: .color(color.opacity(0.75)))
        }
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Markers

    private var inputMarkers: [LevelsMarkerBar.MarkerSpec] {
        let c = settings[target]
        let mid = c.inBlack + (c.inWhite - c.inBlack) * pow(0.5, c.gamma)
        return [
            .init(id: .inBlack, fraction: c.inBlack / 255, fill: .black),
            .init(id: .gamma, fraction: mid / 255, fill: .gray),
            .init(id: .inWhite, fraction: c.inWhite / 255, fill: .white),
        ]
    }

    private var outputMarkers: [LevelsMarkerBar.MarkerSpec] {
        let c = settings[target]
        return [
            .init(id: .outBlack, fraction: c.outBlack / 255, fill: .black),
            .init(id: .outWhite, fraction: c.outWhite / 255, fill: .white),
        ]
    }

    private func setInput(_ m: Marker, fraction x: Double) {
        var c = settings[target]
        let v = x * 255
        switch m {
        case .inBlack: c.inBlack = min(max(0, v), c.inWhite - 2); lastClipSide = .shadows
        case .inWhite: c.inWhite = max(min(255, v), c.inBlack + 2); lastClipSide = .highlights
        case .gamma:
            // Midtone slider position f within black…white ⇔ γ = log(f) / log(0.5).
            let f = min(0.99, max(0.01, (v - c.inBlack) / max(1, c.inWhite - c.inBlack)))
            c.gamma = min(9.99, max(0.1, log(f) / log(0.5)))
        default: break
        }
        settings[target] = c
    }

    private func setOutput(_ m: Marker, fraction x: Double) {
        var c = settings[target]
        let v = min(255, max(0, x * 255))
        switch m {
        case .outBlack: c.outBlack = v; lastClipSide = .shadows
        case .outWhite: c.outWhite = v; lastClipSide = .highlights
        default: break
        }
        settings[target] = c
    }

    // MARK: Eyedroppers

    /// Black / white point: each channel's input black (or white) moves to that pixel's
    /// value, so the pixel itself becomes pure black (white) — and any color cast in it
    /// goes with it. Gray point: each channel's midtone is bent so that pixel comes out
    /// neutral (its channels equal their average) — the classic cast removal.
    private func pick(_ d: Dropper, at n: CGPoint) {
        guard let small, let c = LevelsEngine.sample(small, at: n) else { return }
        let values: [(LevelsTarget, Double)] = [(.red, c.r), (.green, c.g), (.blue, c.b)]
        switch d {
        case .black:
            for (t, v) in values { settings[t].inBlack = min(v, settings[t].inWhite - 2) }
        case .white:
            for (t, v) in values { settings[t].inWhite = max(v, settings[t].inBlack + 2) }
        case .gray:
            let target = (c.r + c.g + c.b) / 3
            for (t, v) in values {
                let ch = settings[t]
                let span = max(1, ch.inWhite - ch.inBlack)
                let x = (v - ch.inBlack) / span, y = (target - ch.inBlack) / span
                guard x > 0.001, x < 0.999, y > 0.001, y < 0.999 else { continue }
                settings[t].gamma = min(9.99, max(0.1, log(x) / log(y)))
            }
        }
        target = .rgb
        dropper = nil
    }

    // MARK: Render / apply

    private func prepare() {
        let s = previewCopy(of: source.cgImage)
        small = s
        Task.detached(priority: .userInitiated) {
            let h = LevelsEngine.histograms(s)
            await MainActor.run { hist = h }
        }
    }

    private func render() async {
        guard let small = small ?? Optional(previewCopy(of: source.cgImage)) else { return }
        let s = settings, side = clipSide
        let out = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            if let side { return LevelsEngine.clipping(small, s, side: side) }
            return LevelsEngine.apply(small, s)
        }.value
        if !Task.isCancelled { preview = out }
    }

    private func apply() {
        guard !settings.isIdentity else { dismiss(); return }
        working = true
        let cg = source.cgImage, s = settings
        Task {
            let out = await Task.detached(priority: .userInitiated) { LevelsEngine.apply(cg, s) }.value
            working = false
            guard let out, document.applyAdjustment(.levels, source: source, result: out) != nil else {
                problem = "Levels could not be applied to this layer."
                return
            }
            dismiss()
        }
    }
}

private extension LevelsSettings {
    /// A cheap change key for `.task(id:)`.
    var hashKey: String {
        [rgb, red, green, blue].map {
            "\($0.inBlack),\($0.inWhite),\($0.gamma),\($0.outBlack),\($0.outWhite)"
        }.joined(separator: "|")
    }
}

// MARK: - The triangle sliders

/// Photoshop-style triangle markers on a 0…1 track. Each drag reports its marker and the
/// new fraction; the owner clamps and stores. `dragging` names the marker in hand, which
/// is what lets ⌥ show the right clipping view.
struct LevelsMarkerBar: View {
    struct MarkerSpec: Identifiable {
        let id: LevelsWindow.Marker
        let fraction: Double
        let fill: Color
    }
    let markers: [MarkerSpec]
    @Binding var dragging: LevelsWindow.Marker?
    let onDrag: (LevelsWindow.Marker, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(markers) { m in
                    Triangle()
                        .fill(m.fill)
                        .overlay(Triangle().stroke(Color.secondary, lineWidth: 1))
                        .frame(width: 16, height: 16)
                        .position(x: m.fraction * geo.size.width, y: 9)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                dragging = m.id
                                onDrag(m.id, min(1, max(0, v.location.x / max(1, geo.size.width))))
                            }
                            .onEnded { _ in dragging = nil })
                        .accessibilityLabel(String(describing: m.id))
                }
            }
        }
    }

    struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.midX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                p.closeSubpath()
            }
        }
    }
}
