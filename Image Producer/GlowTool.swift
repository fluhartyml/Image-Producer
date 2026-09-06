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
//  artwork as a stack of blurred passes, each pass a flat color MASKED BY THE
//  LAYER ITSELF. Masking on the layer's alpha is what makes this work identically
//  for a symbol, a line of text, an imported PNG and a painted pixel layer — none
//  of them has to be re-drawn or re-tinted, and nothing needs to know what kind of
//  content it is looking at.
//
//    neon   → every pass is the same color.
//    plasma → the pass color is interpolated across the passes, so the halo reads
//             as the inner color where it leaves the art and the outer color at
//             its faintest edge. That transition IS the effect.
//
//  ⚠️ WHY NOT IMAGE PLAYGROUND. He asked first whether Playground could "make this
//  layer glow and blend with the layer below." It cannot: Apple's sheet takes ONE
//  source image, and everything it returns is OPAQUE — no alpha — so any result
//  would cover the layers beneath instead of blending with them. A glow is also a
//  thing that has to look the same every time it is rendered, which a generative
//  model does not promise. So it lives here, deterministic and non-destructive.
//
//  COLOR RULE: the palette is this app's gatekeeper for color, so the glow's two
//  colors are CHOSEN FROM `document.palette` rather than from a free color well.
//

import SwiftUI

// MARK: - Model

/// Which of the two named effects a layer is wearing.
enum GlowStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    case neon      // one color
    case plasma    // two colors, blended across the halo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neon:   "Neon Glow"
        case .plasma: "Plasma Glow"
        }
    }

    /// How many colors the inspector should ask for.
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

    /// The color where the halo leaves the artwork. Neon uses this one alone.
    var innerHex = "#00A2FF"
    /// Plasma only: the color at the halo's faint outer edge.
    var outerHex = "#FF2D55"

    /// Halo reach, as a fraction of the canvas's SHORT edge — not pixels — so the
    /// same document renders the same glow at 16pt and at 1024.
    var radiusFraction = 0.05

    /// Overall strength of the halo. 1.0 is the designed weight; above that it
    /// blooms, below it whispers.
    var intensity = 1.0

    /// How many blurred passes make the halo. More is smoother and costs more.
    static let passCount = 7

    /// The color of pass `i`, where 0 is the OUTERMOST (widest, faintest) pass and
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


// MARK: - Green Key  (child 050)

/// GREEN KEY — his name for it, 2026-09-06, and the differentiator he set:
///
///   *"magic lasso NO 'swiss cheese' effect · layer green key tool 'swiss cheese'
///    effect is acceptable"*
///
/// ⚖️ THAT IS THE WHOLE DESIGN. Magic Lasso is CONTIGUOUS — it floods from the pixel
/// you click and never touches a matching color elsewhere. Green Key is **GLOBAL**:
/// every pixel in the layer matching this color goes clear, holes and all.
///
/// **THE HOLES ARE THE POINT.** A real chroma key has to reach the gaps between
/// fingers, through hair, inside a handle. Swiss cheese is the correct result here
/// and the wrong result there, which is why both tools exist and neither replaces
/// the other — his words: *"i want the layer and the magic lasso both not one or
/// the other."*
///
/// Unlike Magic Lasso, which writes pixels on every click, this is held as a
/// SETTING: color + tolerance stored on the layer, keyed live, reversible, and
/// baked only when Apply is pressed.
struct LayerGreenKey: Codable, Equatable {
    var isEnabled = true
    /// The color being removed, sampled from the layer or picked from the palette.
    var colorHex = "#00B140"          // broadcast chroma green, as a starting point
    /// How far from that color still counts as a match, per channel (0…128).
    var tolerance: Int = 24
}

// MARK: - The halo

/// The blurred passes that sit UNDER a layer's artwork. `content` is the layer,
/// rendered exactly as the compositor would draw it — it is used only as a MASK,
/// so its own colors never reach the screen from here.
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

/// THE LAYER TOOL — one entry in the strip, several children revealed inside it.
///
/// His spec, 2026-09-06: *"i want one tool in the tools pane… renaming it 'Layer...'
/// dot dot dot because there is more children in the tool. then in the tool inspector
/// the child layer tools will be listed as reveals… at the top to the far right of
/// 'layer. . .' will be (apply)… the child tools will be similar to >Translucent
/// >Glow >gradient and whatever we determine is needed."*
///
/// Layout, in his order:
///   • header row — "Layer…" on the left, **Apply** hard right
///   • the layer picker — which layer am I dressing?
///   • one reveal per child, each independently switchable
///
/// WHY APPLY LIVES ON THE PARENT AND NOT IN EACH CHILD. Apply bakes the layer AS IT
/// IS CURRENTLY DRAWN — every enabled child at once — into a single flattened layer.
/// A per-child Apply would have to invent an order and would bake twice; one Apply on
/// the parent matches what the canvas is already showing you.
///
/// ⚠️ NO PLACEHOLDER REVEALS. Gradient is agreed but unbuilt, so it is NOT listed —
/// the app deliberately withholds Shape and Path for exactly this reason (App Store
/// Guideline 2.1 rejects visible "coming soon" controls). It joins the list the day
/// it works.
struct LayerInspector: View {
    @ObservedObject var document: ImageDocument
    var activeLayerID: ImageLayer.ID?

    /// Which layer is being dressed. Starts on the active layer and can be pointed
    /// anywhere — his spec: "user picks the layer and the color or colrs."
    @State private var targetID: ImageLayer.ID?
    @State private var showTranslucent = false
    @State private var showGlow = false
    @State private var showGreenKey = false

    private var targetIndex: Int? {
        guard let id = targetID ?? activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    /// 028 — EVERY LAYER, no exclusion. His ruling, 2026-09-06: *"the background
    /// layers are just named light and dark for automation purposes… its a generic
    /// label just pre named."* The filter here was my assumption and it was wrong —
    /// fading the Light floor so Dark shows through is a real icon move.
    ///
    /// Glow on a layer whose whole area is one solid fill gives a full-canvas wash
    /// rather than a halo. That is what it looks like, not a reason to forbid it.
    private var dressableLayers: [ImageLayer] { document.layers }

    private var targetSelection: Binding<ImageLayer.ID?> {
        Binding(get: { self.targetID ?? self.activeLayerID ?? self.dressableLayers.first?.id },
                set: { self.targetID = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if dressableLayers.isEmpty {
                    Text("No artwork layers yet. These effects need something to dress.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    layerPicker
                    if let i = targetIndex, document.layers.indices.contains(i) {
                        Divider()
                        translucentReveal(i)
                        glowReveal(i)
                        greenKeyReveal(i)
                    }
                }
            }
            .padding(14)
        }
        .onAppear { if targetID == nil { targetID = activeLayerID } }
        .onChange(of: activeLayerID) { _, new in
            if targetID == nil { targetID = new }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Layer…")
                .font(.headline)
            Spacer()
            Button("Apply") {
                if let i = targetIndex { apply(at: i) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasSomethingToApply)
            .help("Bake the effects into pixels. The original layer is kept directly below, switched off.")
        }
    }

    /// Apply is meaningless with nothing switched on — a bake that changes nothing
    /// would still cost a layer and a history entry.
    private var hasSomethingToApply: Bool {
        guard let i = targetIndex, document.layers.indices.contains(i) else { return false }
        let layer = document.layers[i]
        return (layer.glow?.isEnabled ?? false)
            || layer.opacity < 1.0
            || (layer.greenKey?.isEnabled ?? false)
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Layer").font(.subheadline).foregroundStyle(.secondary)
            Picker("Layer", selection: targetSelection) {
                ForEach(dressableLayers) { layer in
                    Text(layer.name).tag(Optional(layer.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: Child — Translucent

    /// ⭐ The model field was already there and unread. `ImageLayer.opacity` has
    /// existed, defaulted to 1.0 and been saved into every document he has ever made,
    /// and no renderer looked at it. This child is mostly the wiring it never got.
    @ViewBuilder
    private func translucentReveal(_ i: Int) -> some View {
        let opacity = Binding<Double>(
            get: { self.document.layers[i].opacity },
            set: { self.document.layers[i].opacity = $0 }
        )
        DisclosureGroup(isExpanded: $showTranslucent) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", opacity.wrappedValue * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: opacity, in: 0...1)
                Text("The whole layer, artwork and glow together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } label: {
            revealLabel("Translucent",
                        on: document.layers[i].opacity < 1.0,
                        detail: document.layers[i].opacity < 1.0
                            ? String(format: "%.0f%%", document.layers[i].opacity * 100)
                            : nil)
        }
    }

    // MARK: Child — Glow

    @ViewBuilder
    private func glowReveal(_ i: Int) -> some View {
        DisclosureGroup(isExpanded: $showGlow) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Glow this layer", isOn: enabledBinding(i))
                if document.layers[i].glow?.isEnabled == true {
                    stylePicker(i)
                    colorSections(i)
                    sliders(i)
                }
            }
            .padding(.top, 4)
        } label: {
            let g = document.layers[i].glow
            revealLabel("Glow",
                        on: g?.isEnabled ?? false,
                        detail: (g?.isEnabled ?? false) ? g?.style.title : nil)
        }
    }

    /// A reveal's own row: name, a dot when the child is doing something, and a short
    /// readout so the state is legible with every reveal shut.
    private func revealLabel(_ name: String, on: Bool, detail: String?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(name)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Glow controls

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
        let innerTitle = isPlasma ? "Inner color — where it leaves the art" : "Color"
        swatches(title: innerTitle, selection: glowBinding(i).innerHex)
        if isPlasma {
            swatches(title: "Outer color — the faint edge",
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

    /// Color comes from the project palette — the palette is this app's gatekeeper
    /// for every color, so a glow does not get its own private color well.
    private func swatches(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            if document.palette.isEmpty {
                Text("The palette is empty — add colors in Color Palette first.")
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


    // MARK: Child — Green Key

    /// GREEN KEY — global color removal, held as a setting.
    ///
    /// His differentiator, 2026-09-06: *"magic lasso NO 'swiss cheese' effect · layer
    /// green key tool 'swiss cheese' effect is acceptable."* Magic Lasso floods from
    /// one click and stays connected; this clears EVERY matching pixel in the layer.
    ///
    /// Naming is his too: **Green Key** labels the reveal, **Color Key** is the heading
    /// above the palette and the eyedropper — *"green key is the child label color key
    /// is above the pallete and eyedropper."*
    @ViewBuilder
    private func greenKeyReveal(_ i: Int) -> some View {
        DisclosureGroup(isExpanded: $showGreenKey) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Key this layer", isOn: greenKeyEnabled(i))
                if document.layers[i].greenKey?.isEnabled == true {
                    Text("Color Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    greenKeySwatch(i)
                    swatches(title: "", selection: greenKeyBinding(i).colorHex)
                    eyedropperRow(i)
                    greenKeyTolerance(i)
                }
            }
            .padding(.top, 4)
        } label: {
            let k = document.layers[i].greenKey
            revealLabel("Green Key",
                        on: k?.isEnabled ?? false,
                        detail: (k?.isEnabled ?? false) ? k?.colorHex : nil)
        }
    }

    private func greenKeyBinding(_ i: Int) -> Binding<LayerGreenKey> {
        Binding(get: { self.document.layers[i].greenKey ?? LayerGreenKey() },
                set: { self.document.layers[i].greenKey = $0 })
    }

    private func greenKeyEnabled(_ i: Int) -> Binding<Bool> {
        Binding(get: { self.document.layers[i].greenKey?.isEnabled ?? false },
                set: { on in
                    var k = self.document.layers[i].greenKey ?? LayerGreenKey()
                    k.isEnabled = on
                    self.document.layers[i].greenKey = on ? k : nil
                })
    }

    /// The color currently being removed, shown big enough to judge.
    @ViewBuilder
    private func greenKeySwatch(_ i: Int) -> some View {
        let hex = document.layers[i].greenKey?.colorHex ?? "#00B140"
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: hex) ?? .green)
                .frame(width: 44, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
            Text(hex).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// ⚠️ THE EYEDROPPER IS THE PRIMARY WAY IN, and the palette is the shortcut.
    /// The palette governs color you PUT IN; a key matches color that is already THERE,
    /// and a photographed green screen is a thousand greens, none of them in a palette.
    @ViewBuilder
    private func eyedropperRow(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                sampleFromLayer(i)
            } label: {
                Label("Sample from layer", systemImage: "eyedropper")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        Text("Samples the most common opaque color in this layer. For a specific spot, "
             + "pick it with the Eyedropper tool first.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Take the layer's dominant opaque color as the key. A whole-layer sample is the
    /// right default for a chroma key: the background IS the most common color, and it
    /// saves aiming at a canvas the inspector cannot see.
    private func sampleFromLayer(_ i: Int) {
        guard let cg = renderLayerImage(document.layers[i], in: document),
              let hex = dominantOpaqueColorHex(cg) else {
            document.say("Nothing to sample on this layer", kind: .warning)
            return
        }
        greenKeyBinding(i).wrappedValue.colorHex = hex
        document.say("Color Key sampled \(hex)", kind: .info)
    }

    @ViewBuilder
    private func greenKeyTolerance(_ i: Int) -> some View {
        let tol = Binding<Double>(
            get: { Double(self.document.layers[i].greenKey?.tolerance ?? 24) },
            set: { self.greenKeyBinding(i).wrappedValue.tolerance = Int($0) }
        )
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Tolerance").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(tol.wrappedValue))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: tol, in: 0...128)
            Text("How far from that color still counts as a match. Higher reaches more "
                 + "shades — and more of the subject.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Apply

    /// ⚖️ THE NON-DESTRUCTIVE RULE — his words, 2026-09-06: *"yes it is the non
    /// destructive rule."* And the reason it is not optional, from the same day:
    /// **undo is OFF ON PURPOSE because UndoManager crashed this app.** Layering IS
    /// the undo, so nothing here may mutate a layer in place.
    ///
    /// Apply leaves TWO layers where there was one:
    ///   • the untouched original, moved DOWN one and switched OFF;
    ///   • above it, the flattened result named `{Layer} (Glow)`, with the live
    ///     effects cleared because they are pixels now.
    ///
    /// Same shape the Move tool's commit already uses — a pristine copy inserted
    /// directly BELOW the committed one.
    private func apply(at i: Int) {
        guard document.layers.indices.contains(i) else { return }
        let source = document.layers[i]

        // Render the layer AS IT LOOKS RIGHT NOW — halo and opacity included, because
        // the compositor draws both. Fail-safe: if the render fails, change nothing.
        guard let cg = renderLayerImage(source, in: document),
              let png = pngData(from: cg) else {
            document.say("Apply failed — the layer could not be rendered", kind: .warning)
            return
        }

        document.captureHistoryBaselineIfNeeded()

        // The pristine copy that goes underneath: a fresh id, the live effects cleared
        // so it is genuinely the original, and hidden.
        var original = source
        original.id = UUID()
        original.glow = nil
        original.opacity = 1.0
        original.greenKey = nil
        original.isVisible = false

        // 016 — THE NAME LISTS WHAT ACTUALLY BAKED. Agreed 2026-09-06. It used to say
        // "(Glow)" whichever child fired, so applying Translucent alone produced
        // "Stars (Glow)", which is a lie on the layer's own label.
        //
        // Several at once are joined with " + ". Repeats NUMBER rather than compound:
        // "(Glow)" then "(Glow 2)", never "(Glow) (Glow)" — the rule the Move tool
        // follows, and the reason the existing suffix is stripped first.
        var applied: [String] = []
        if source.glow?.isEnabled == true { applied.append("Glow") }
        if source.opacity < 1.0 { applied.append("Translucent") }
        if source.greenKey?.isEnabled == true { applied.append("Green Key") }
        let suffix = applied.isEmpty ? "Applied" : applied.joined(separator: " + ")

        var base = source.name
        if let r = base.range(of: #" \((?:Glow|Translucent|Applied)(?: \+ [A-Za-z]+)*(?: \d+)?\)$"#,
                              options: .regularExpression) {
            base.removeSubrange(r)
        }
        let taken = Set(document.layers.map(\.name))
        func candidate(_ k: Int) -> String {
            k == 1 ? "\(base) (\(suffix))" : "\(base) (\(suffix) \(k))"
        }
        var n = 1
        while taken.contains(candidate(n)) { n += 1 }

        document.layers[i].name = candidate(n)
        document.layers[i].setImage(png)
        document.layers[i].transform = document.coveringTransform(forPNG: png)
        document.layers[i].glow = nil          // pixels now, not a live effect
        document.layers[i].opacity = 1.0       // baked in
        document.layers[i].greenKey = nil      // baked in
        document.layers[i].isVisible = true
        // A text layer mirrors its name from its typed text; leaving that link intact
        // would let the next keystroke wipe the suffix off the baked layer.
        document.layers[i].nameLinkedToText = false

        let bakedID = document.layers[i].id
        document.layers.insert(original, at: i)    // directly BELOW the baked copy

        document.recordHistory(toolID: Tool.layer.rawValue,
                               groupTitle: Tool.layer.title,
                               actionLabel: "Apply \(suffix) — \(candidate(n))",
                               layerID: bakedID)

        targetID = bakedID
    }
}
