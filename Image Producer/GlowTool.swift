//
//  GlowTool.swift
//  Image Producer
//
//  LAYER GLOW — Michael's spec, 2026-09-06:
//
//    "neon glow is one color that glows"
//    "plasma glow is two colors that blend in the glow transitioning from one
//     color to the other"
//
//  Two named effects, one mechanism. The glow is drawn UNDERNEATH the layer's own
//  artwork as a stack of blurred passes, each pass a flat colour MASKED BY THE
//  LAYER ITSELF. Masking on the layer's alpha is what makes this work identically
//  for a symbol, a line of text, an imported PNG and a painted pixel layer — none
//  of them has to be re-drawn or re-tinted, and nothing needs to know what kind of
//  content it is looking at.
//
//    neon   → every pass is the same colour.
//    plasma → the pass colour is interpolated across the passes, so the halo reads
//             as the inner colour where it leaves the art and the outer colour at
//             its faintest edge. That transition IS the effect.
//
//  ⚠️ WHY NOT IMAGE PLAYGROUND. He asked first whether Playground could "make this
//  layer glow and blend with the layer below." It cannot: Apple's sheet takes ONE
//  source image, and everything it returns is OPAQUE — no alpha — so any result
//  would cover the layers beneath instead of blending with them. A glow is also a
//  thing that has to look the same every time it is rendered, which a generative
//  model does not promise. So it lives here, deterministic and non-destructive.
//
//  COLOUR RULE: the palette is this app's gatekeeper for colour, so the glow's two
//  colours are CHOSEN FROM `document.palette` rather than from a free colour well.
//

import SwiftUI

// MARK: - Model

/// Which of the two named effects a layer is wearing.
enum GlowStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    case neon      // one colour
    case plasma    // two colours, blended across the halo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neon:   "Neon Glow"
        case .plasma: "Plasma Glow"
        }
    }

    /// How many colours the inspector should ask for.
    var colorCount: Int {
        switch self {
        case .neon:   1
        case .plasma: 2
        }
    }
}

/// A layer's glow. Optional on `ImageLayer`, so every document saved before this
/// existed still decodes — a missing key simply means "no glow."
struct LayerGlow: Codable, Equatable {
    var isEnabled = true
    var style: GlowStyle = .neon

    /// The colour where the halo leaves the artwork. Neon uses this one alone.
    var innerHex = "#00A2FF"
    /// Plasma only: the colour at the halo's faint outer edge.
    var outerHex = "#FF2D55"

    /// Halo reach, as a fraction of the canvas's SHORT edge — not pixels — so the
    /// same document renders the same glow at 16pt and at 1024.
    var radiusFraction = 0.05

    /// Overall strength of the halo. 1.0 is the designed weight; above that it
    /// blooms, below it whispers.
    var intensity = 1.0

    /// How many blurred passes make the halo. More is smoother and costs more.
    static let passCount = 7

    /// The colour of pass `i`, where 0 is the OUTERMOST (widest, faintest) pass and
    /// `passCount - 1` is the innermost, tightest one against the art.
    func color(forPass i: Int) -> Color {
        let inner = RGB(hex: innerHex) ?? RGB(r: 0, g: 0.64, b: 1)
        guard style == .plasma else { return inner.color }
        let outer = RGB(hex: outerHex) ?? RGB(r: 1, g: 0.18, b: 0.33)
        // t: 0 at the outer edge → 1 against the artwork.
        let t = Double(i) / Double(max(1, LayerGlow.passCount - 1))
        return outer.mixed(toward: inner, amount: t).color
    }

    /// Blur radius of pass `i`, in points, given the canvas's short edge.
    func blurRadius(forPass i: Int, reference: CGFloat) -> CGFloat {
        let maxRadius = max(0.5, CGFloat(radiusFraction) * reference)
        let t = Double(i) / Double(max(1, LayerGlow.passCount - 1))
        // Outermost pass gets the full radius; the innermost stays tight so the
        // halo has a hot core rather than one flat smear.
        return maxRadius * CGFloat(1.0 - 0.85 * t)
    }

    /// Opacity of pass `i`. The tight inner passes carry more weight, which is what
    /// makes a glow look like it is coming OUT of the art rather than sitting behind it.
    func opacity(forPass i: Int) -> Double {
        let t = Double(i) / Double(max(1, LayerGlow.passCount - 1))
        let base = 0.16 + 0.34 * t
        return min(1.0, base * intensity)
    }
}

/// A tiny sRGB triple, only so two hex strings can be blended. SwiftUI's `Color`
/// cannot be interpolated directly and reading components back out of one is
/// platform-specific, so the arithmetic happens here in plain numbers.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// Straight linear mix. `amount` 0 = self, 1 = `other`.
    func mixed(toward other: RGB, amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t,
                   g: g + (other.g - g) * t,
                   b: b + (other.b - b) * t)
    }
}

// MARK: - The halo

/// The blurred passes that sit UNDER a layer's artwork. `content` is the layer,
/// rendered exactly as the compositor would draw it — it is used only as a MASK,
/// so its own colours never reach the screen from here.
struct GlowHalo<Content: View>: View {
    let glow: LayerGlow
    /// The canvas's short edge, so the halo scales with the document.
    let reference: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            // 0 = outermost/widest, drawn first so the tight hot passes land on top.
            ForEach(0..<LayerGlow.passCount, id: \.self) { i in
                glow.color(forPass: i)
                    .mask(content())
                    .blur(radius: glow.blurRadius(forPass: i, reference: reference))
                    .opacity(glow.opacity(forPass: i))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Inspector

/// The tool strip's panel. Picks the layer (defaults to the active one), the style,
/// and the one or two palette colours the style calls for.
struct GlowInspector: View {
    @ObservedObject var document: ImageDocument
    var activeLayerID: ImageLayer.ID?

    /// Which layer is being given a glow. Starts on the active layer and can be
    /// pointed anywhere — his spec: "user picks the layer and the color or colrs."
    @State private var targetID: ImageLayer.ID?

    private var targetIndex: Int? {
        guard let id = targetID ?? activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    /// Content layers only — a flat background has no alpha to mask against, so a
    /// glow on one would be a full-canvas colour wash rather than a halo.
    private var glowableLayers: [ImageLayer] {
        document.layers.filter { $0.backgroundRole == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Layer Glow")
                    .font(.headline)

                if glowableLayers.isEmpty {
                    Text("No artwork layers yet. A glow needs something to glow around.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    layerPicker
                    if let i = targetIndex, document.layers.indices.contains(i) {
                        editor(for: i)
                    }
                }
            }
            .padding(14)
        }
        .onAppear { if targetID == nil { targetID = activeLayerID } }
        .onChange(of: activeLayerID) { _, new in
            // Following the active layer is the behaviour that surprises least —
            // until the user deliberately points this panel somewhere else.
            if targetID == nil { targetID = new }
        }
    }

    /// Hoisted out of the Picker: inline, this binding pushed the view body past
    /// what the type-checker will solve in reasonable time.
    private var targetSelection: Binding<ImageLayer.ID?> {
        Binding(get: { self.targetID ?? self.activeLayerID ?? self.glowableLayers.first?.id },
                set: { self.targetID = $0 })
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layer").font(.subheadline).foregroundStyle(.secondary)
            Picker("Layer", selection: targetSelection) {
                ForEach(glowableLayers) { layer in
                    Text(layer.name).tag(Optional(layer.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// Written as several small pieces on purpose: as one expression this body was
    /// past what the Swift type-checker will solve in reasonable time.
    @ViewBuilder
    private func editor(for i: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Glow this layer", isOn: enabledBinding(i))
            if document.layers[i].glow?.isEnabled == true {
                stylePicker(i)
                colorSections(i)
                sliders(i)
                applyRow(i)
            }
        }
    }

    private func glowBinding(_ i: Int) -> Binding<LayerGlow> {
        Binding(get: { self.document.layers[i].glow ?? LayerGlow() },
                set: { self.document.layers[i].glow = $0 })
    }

    private func enabledBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: { self.document.layers[i].glow?.isEnabled ?? false },
                set: { on in
                    var g = self.document.layers[i].glow ?? LayerGlow()
                    g.isEnabled = on
                    self.document.layers[i].glow = on ? g : nil
                })
    }

    @ViewBuilder
    private func stylePicker(_ i: Int) -> some View {
        Picker("Style", selection: glowBinding(i).style) {
            ForEach(GlowStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func colorSections(_ i: Int) -> some View {
        let isPlasma = document.layers[i].glow?.style == .plasma
        let innerTitle = isPlasma ? "Inner colour — where it leaves the art" : "Colour"
        swatches(title: innerTitle, selection: glowBinding(i).innerHex)
        if isPlasma {
            swatches(title: "Outer colour — the faint edge",
                     selection: glowBinding(i).outerHex)
        }
    }

    @ViewBuilder
    private func sliders(_ i: Int) -> some View {
        let glow = document.layers[i].glow ?? LayerGlow()
        let reach = String(format: "%.1f%%", glow.radiusFraction * 100)
        let strength = String(format: "%.2f×", glow.intensity)
        labelledSlider("Reach", value: glowBinding(i).radiusFraction,
                       range: 0.005...0.20, readout: reach)
        labelledSlider("Intensity", value: glowBinding(i).intensity,
                       range: 0.1...2.0, readout: strength)
    }

    // MARK: - Apply

    /// ⚖️ THE NON-DESTRUCTIVE RULE — Michael, 2026-09-06: *"yes it is the non
    /// destructive rule."*
    ///
    /// The live glow is a PREVIEW: a setting on the layer, changeable and reversible.
    /// **Apply bakes it.** What you get is TWO layers where there was one:
    ///
    ///   • the untouched original, moved DOWN one and switched OFF — nothing is lost;
    ///   • above it, the flattened result named `{Layer} (Glow)`, with the glow setting
    ///     cleared because it is now pixels rather than a live effect.
    ///
    /// This is the same shape the Move tool's commit already uses, deliberately — a
    /// hidden pristine copy inserted directly BELOW the committed one.
    @ViewBuilder
    private func applyRow(_ i: Int) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
            Button {
                apply(at: i)
            } label: {
                Label("Apply", systemImage: "square.stack.3d.down.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("Bakes the glow into pixels. The original layer is kept directly "
                 + "below, switched off — nothing is overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(at i: Int) {
        guard document.layers.indices.contains(i) else { return }
        let source = document.layers[i]
        guard source.backgroundRole == nil else { return }

        // Render the layer AS IT LOOKS RIGHT NOW — halo included, because the
        // compositor draws the glow. Fail-safe: if the render fails, change nothing.
        guard let cg = renderLayerImage(source, in: document),
              let png = pngData(from: cg) else { return }

        document.captureHistoryBaselineIfNeeded()

        // The pristine copy that goes underneath. A fresh id so it is a separate
        // layer, the glow cleared so it is genuinely the original, and hidden.
        var original = source
        original.id = UUID()
        original.glow = nil
        original.isVisible = false

        // Name the baked layer. Strip any existing "(Glow)" / "(Glow n)" first so
        // repeat applies never compound into "Stars (Glow) (Glow)" — the same rule
        // the Move tool follows.
        var base = source.name
        if let r = base.range(of: #" \(Glow(?: \d+)?\)$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }
        let taken = Set(document.layers.map(\.name))
        func candidate(_ k: Int) -> String { k == 1 ? "\(base) (Glow)" : "\(base) (Glow \(k))" }
        var n = 1
        while taken.contains(candidate(n)) { n += 1 }

        document.layers[i].name = candidate(n)
        document.layers[i].setImage(png)
        document.layers[i].transform = document.coveringTransform(forPNG: png)
        document.layers[i].glow = nil              // it is pixels now, not a live effect
        document.layers[i].isVisible = true
        // A text layer mirrors its name from its typed text; leaving that link intact
        // would let the next keystroke wipe the "(Glow)" suffix off the baked layer.
        document.layers[i].nameLinkedToText = false

        let bakedID = document.layers[i].id
        document.layers.insert(original, at: i)    // directly BELOW the baked copy

        document.recordHistory(toolID: Tool.glow.rawValue,
                               groupTitle: Tool.glow.title,
                               actionLabel: "Apply Glow",
                               layerID: bakedID)

        // Keep the panel pointed at the layer that is now on screen.
        targetID = bakedID
    }

    /// Colour comes from the project palette — the palette is this app's gatekeeper
    /// for every colour, so a glow does not get its own private colour well.
    private func swatches(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            if document.palette.isEmpty {
                Text("The palette is empty — add colours in Color Palette first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                    ForEach(document.palette, id: \.self) { hex in
                        let picked = hex.caseInsensitiveCompare(selection.wrappedValue) == .orderedSame
                        Button { selection.wrappedValue = hex } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(picked ? Color.accentColor : Color.secondary.opacity(0.35),
                                            lineWidth: picked ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
            }
        }
    }

    private func labelledSlider(_ title: String,
                                value: Binding<Double>,
                                range: ClosedRange<Double>,
                                readout: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
