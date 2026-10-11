//
//  Text3D.swift
//  Image Producer
//
//  3D TEXT — any installed font, extruded into a solid, posed or animated.
//  His words, 2026-10-11: "can we turn a font into a 3D object that can be animated?"
//  · "like if it says new can you make it spin or wiggle back and forth?"
//  · "yes code the 3d text".
//
//  It is a SETTING on a text element, not a new kind of layer: the text stays live text
//  (his "no rasterization please unless specifically asked to"), and switching 3D off
//  gives back the flat letters exactly as they were.
//
//  Drawn by SceneKit's OFFSCREEN renderer into a picture, so every path that draws text —
//  the canvas, the floating preview, every export, the Camera — gets the same 3D letters
//  through `TextElementView`. SceneKit, not RealityKit: SCNText extrudes and bevels a
//  font directly and SCNRenderer snapshots to an image on Mac and iPad; neither is
//  deprecated in the OS 27 SDKs (headers checked 2026-10-11).
//

import SwiftUI
import SceneKit
#if os(macOS)
import AppKit
private typealias P3Font = NSFont
private typealias P3Color = NSColor
#else
import UIKit
private typealias P3Font = UIFont
private typealias P3Color = UIColor
#endif

// MARK: - Model

/// A text element's 3D look. Optional on `TextContent`; nil = flat text.
struct Text3D: Codable, Equatable {
    enum Motion: String, Codable, CaseIterable, Identifiable {
        case still, spin, wiggle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .still:  "Still"
            case .spin:   "Spin"
            case .wiggle: "Wiggle"
            }
        }
    }

    var isEnabled = true
    /// How thick the letters are, as a fraction of the font size.
    var depth = 0.30
    /// The rounded-off edge on the front and back faces, as a fraction of the font size.
    var bevel = 0.03
    var motion: Motion = .spin
    /// One full spin, or one swing there and back.
    var secondsPerCycle = 3.0
    /// How far a wiggle swings each way, in degrees.
    var swingDegrees = 30.0
    /// Turn left/right (the still pose, and the middle of a wiggle), degrees.
    var turnDegrees = 20.0
    /// Tilt toward / away from the viewer, degrees.
    var tiltDegrees = 10.0
    /// The sides of the letters. nil = the face color, darker.
    var sideColorHex: String?

    init() {}

    /// Tolerant load, like `TextContent`: a field added later opens with its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Text3D()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        depth = try c.decodeIfPresent(Double.self, forKey: .depth) ?? d.depth
        bevel = try c.decodeIfPresent(Double.self, forKey: .bevel) ?? d.bevel
        motion = try c.decodeIfPresent(Motion.self, forKey: .motion) ?? d.motion
        secondsPerCycle = try c.decodeIfPresent(Double.self, forKey: .secondsPerCycle) ?? d.secondsPerCycle
        swingDegrees = try c.decodeIfPresent(Double.self, forKey: .swingDegrees) ?? d.swingDegrees
        turnDegrees = try c.decodeIfPresent(Double.self, forKey: .turnDegrees) ?? d.turnDegrees
        tiltDegrees = try c.decodeIfPresent(Double.self, forKey: .tiltDegrees) ?? d.tiltDegrees
        sideColorHex = try c.decodeIfPresent(String.self, forKey: .sideColorHex)
    }

    /// The left/right turn at `time` seconds. A spin is one whole turn per cycle; a
    /// wiggle is a smooth swing either side of `turnDegrees`.
    func yawDegrees(at time: Double) -> Double {
        let period = max(0.2, secondsPerCycle)
        let phase = (time / period).truncatingRemainder(dividingBy: 1)
        switch motion {
        case .still:  return turnDegrees
        case .spin:   return turnDegrees + 360 * phase
        case .wiggle: return turnDegrees + swingDegrees * sin(2 * .pi * phase)
        }
    }
}

extension EnvironmentValues {
    /// Set by the 3D-text GIF export to draw every 3D text at one exact moment of its
    /// loop. nil (everywhere else) = the live clock.
    @Entry var text3DTime: Double? = nil
}

// MARK: - Renderer

/// Builds the extruded letters and photographs them. One shared SCNRenderer; the
/// geometry is rebuilt only when the letters or their look change, and finished
/// pictures are cached by pose so a running spin mostly redraws from memory.
@MainActor enum Text3DRenderer {
    private static let renderer: SCNRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.autoenablesDefaultLighting = false
        return r
    }()

    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }
    private static let pictures: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>(); c.countLimit = 160; return c
    }()

    /// One built scene per distinct set of letters + look, so two 3D layers on the
    /// canvas do not rebuild each other's geometry every frame.
    private final class Built {
        let scene: SCNScene, pivot: SCNNode, camera: SCNNode
        /// Half the width and height the letters can ever cover, at any turn or tilt —
        /// so a spin never changes the picture's size or crops a letter.
        let halfExtent: CGSize
        init(scene: SCNScene, pivot: SCNNode, camera: SCNNode, halfExtent: CGSize) {
            self.scene = scene; self.pivot = pivot; self.camera = camera; self.halfExtent = halfExtent
        }
    }
    private static let built: NSCache<NSString, Built> = {
        let c = NSCache<NSString, Built>(); c.countLimit = 12; return c
    }()

    /// Font size the geometry is built at. Only proportions matter; the picture is
    /// rendered to whatever pixel size it is shown at.
    private static let fontSize: CGFloat = 100

    /// The aspect (width ÷ height) of the picture for these letters, so the view can
    /// size itself before the first render.
    static func aspect(string: String, fontName: String, bold: Bool, italic: Bool,
                       style: Text3D) -> CGFloat {
        let b = load(string: string, fontName: fontName, bold: bold, italic: italic,
                     colorHex: "#000000", style: style)
        return b.halfExtent.width / max(0.001, b.halfExtent.height)
    }

    /// The letters at this turn, as a picture about `pixelSize` big (aspect kept).
    static func image(string: String, fontName: String, bold: Bool, italic: Bool,
                      colorHex: String, style: Text3D, yawDegrees: Double,
                      pixelSize: CGSize) -> CGImage? {
        guard let renderer, !string.isEmpty else { return nil }
        let yaw = (yawDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360).rounded()   // 1° steps: plenty smooth, cacheable
        let key = geometryKey(string, fontName, bold, italic, colorHex, style)
        // Fit the letters' fixed aspect inside the requested size; cap for speed.
        let b = load(string: string, fontName: fontName, bold: bold, italic: italic,
                     colorHex: colorHex, style: style)
        let halfExtent = b.halfExtent
        let aspect = halfExtent.width / max(0.001, halfExtent.height)
        var w = max(8, pixelSize.width), h = w / aspect
        if h > pixelSize.height { h = max(8, pixelSize.height); w = h * aspect }
        let cap: CGFloat = 1400
        if max(w, h) > cap { let k = cap / max(w, h); w *= k; h *= k }
        let px = CGSize(width: w.rounded(), height: h.rounded())

        let pictureKey = "\(key)|\(yaw)|\(Int(px.width))x\(Int(px.height))" as NSString
        if let hit = pictures.object(forKey: pictureKey) { return hit.image }

        let pivot = b.pivot, camera = b.camera
        pivot.eulerAngles = SCNVector3(
            Float(style.tiltDegrees * .pi / 180),
            Float(yaw * .pi / 180),
            0)
        // Frame: the camera sees exactly the letters' largest possible extent.
        if let cam = camera.camera {
            cam.projectionDirection = .vertical
            let distance = Double(camera.position.z)
            cam.fieldOfView = 2 * atan(Double(halfExtent.height) / distance) * 180 / .pi
        }
        renderer.scene = b.scene
        renderer.pointOfView = camera
        let shot = renderer.snapshot(atTime: 0, with: px, antialiasingMode: .multisampling4X)
        #if os(macOS)
        guard let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let cg = shot.cgImage else { return nil }
        #endif
        pictures.setObject(Box(cg), forKey: pictureKey)
        return cg
    }

    private static func geometryKey(_ s: String, _ f: String, _ b: Bool, _ i: Bool,
                                    _ c: String, _ st: Text3D) -> String {
        "\(s)|\(f)|\(b)|\(i)|\(c)|\(st.depth)|\(st.bevel)|\(st.sideColorHex ?? "-")"
    }

    /// Build (or reuse) the scene for these letters.
    @discardableResult
    private static func load(string: String, fontName: String, bold: Bool, italic: Bool,
                             colorHex: String, style: Text3D) -> Built {
        let key = geometryKey(string, fontName, bold, italic, colorHex, style) as NSString
        if let hit = built.object(forKey: key) { return hit }

        let depth = CGFloat(max(0.01, style.depth)) * fontSize
        let text = SCNText(string: string.isEmpty ? " " : string, extrusionDepth: depth)
        text.font = font(fontName, bold: bold, italic: italic)
        text.flatness = 0.15                         // smooth curves at this size
        // A bevel deeper than half the letter's thickness folds the faces into each other.
        text.chamferRadius = min(CGFloat(max(0, style.bevel)) * fontSize, depth * 0.45)

        let face = P3Color(Color(hex: colorHex) ?? .black)
        let side = style.sideColorHex.flatMap { Color(hex: $0) }.map { P3Color($0) }
            ?? darker(face)
        // SCNText's material order: front, back, sides, front bevel, back bevel.
        text.materials = [face, face, side, face, face].map { color in
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.specular.contents = P3Color(white: 0.35, alpha: 1)
            m.shininess = 0.4
            m.lightingModel = .blinn
            return m
        }

        let node = SCNNode(geometry: text)
        let (lo, hi) = node.boundingBox
        let w = CGFloat(hi.x - lo.x), h = CGFloat(hi.y - lo.y), d = CGFloat(hi.z - lo.z)
        // Turn and tilt about the letters' own middle.
        node.position = SCNVector3(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -(lo.z + hi.z) / 2)
        let pivotNode = SCNNode()
        pivotNode.addChildNode(node)

        // Largest extent at ANY turn: the corner-to-corner of the top view across, and
        // of the side view up and down — plus a margin for perspective and the bevel.
        let margin: CGFloat = 1.12
        let halfExtent = CGSize(width: max(1, (w * w + d * d).squareRoot() / 2 * margin),
                            height: max(1, (h * h + d * d).squareRoot() / 2 * margin))

        let scene = SCNScene()
        scene.background.contents = P3Color.clear
        scene.rootNode.addChildNode(pivotNode)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        let distance = Float(max(halfExtent.width, halfExtent.height) * 5)
        cam.position = SCNVector3(0, 0, distance)
        cam.camera?.zNear = Double(distance) * 0.1
        cam.camera?.zFar = Double(distance) * 4
        scene.rootNode.addChildNode(cam)

        // Key light from the upper left and in front; a soft fill; ambient so the
        // shadowed sides never go black.
        let keyLight = SCNNode(); keyLight.light = SCNLight(); keyLight.light?.type = .directional
        keyLight.light?.intensity = 900
        keyLight.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .directional
        fill.light?.intensity = 350
        fill.eulerAngles = SCNVector3(0.2, 0.7, 0)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        [keyLight, fill, ambient].forEach(scene.rootNode.addChildNode)

        let b = Built(scene: scene, pivot: pivotNode, camera: cam, halfExtent: halfExtent)
        built.setObject(b, forKey: key)
        return b
    }

    private static func font(_ name: String, bold: Bool, italic: Bool) -> P3Font {
        let base = P3Font(name: name, size: fontSize) ?? P3Font.systemFont(ofSize: fontSize)
        #if os(macOS)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard !traits.isEmpty else { return base }
        let d = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: d, size: fontSize) ?? base
        #else
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let d = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(traits))
        else { return base }
        return UIFont(descriptor: d, size: fontSize)
        #endif
    }

    private static func darker(_ c: P3Color) -> P3Color {
        #if os(macOS)
        let s = c.usingColorSpace(.deviceRGB) ?? c
        return NSColor(red: s.redComponent * 0.55, green: s.greenComponent * 0.55,
                       blue: s.blueComponent * 0.55, alpha: s.alphaComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.55, green: g * 0.55, blue: b * 0.55, alpha: a)
        #endif
    }
}

// MARK: - The view

/// 3D letters filling the text element's box. Animates on the live clock unless the
/// export has fixed a moment (`text3DTime`).
struct Text3DElementView: View {
    let text: TextContent
    let style: Text3D
    /// The element's box, in the points this view is drawn in.
    let box: CGSize
    @Environment(\.text3DTime) private var fixedTime
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let fixedTime {
                frame(at: fixedTime)
            } else if style.motion == .still {
                frame(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    frame(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: max(1, box.width), height: max(1, box.height))
    }

    @ViewBuilder
    private func frame(at time: Double) -> some View {
        let scale = max(1, displayScale)
        if let cg = Text3DRenderer.image(
            string: text.string, fontName: text.fontName, bold: text.bold, italic: text.italic,
            colorHex: text.colorHex, style: style, yawDegrees: style.yawDegrees(at: time),
            pixelSize: CGSize(width: box.width * scale, height: box.height * scale)) {
            Image(decorative: cg, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

// MARK: - Inspector section (Text tool)

/// The 3D controls for the selected text layer. Reads and writes the layer directly,
/// one coalesced History step per run of adjustments — like the rest of the Text tool.
struct Text3DSection: View {
    @Bindable var document: ImageDocument
    let layerID: UUID

    private var index: Int? { document.layers.firstIndex(where: { $0.id == layerID }) }
    private var current: Text3D? { index.flatMap { document.layers[$0].textContent?.threeD } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("3D letters", isOn: Binding(
                get: { current?.isEnabled ?? false },
                set: { on in edit("3D text") { $0 = on ? ($0 ?? Text3D()) : nil } }))
                .font(.system(size: 18))
            if let s = current, s.isEnabled {
                Picker("Motion", selection: binding(\.motion, "3D motion")) {
                    ForEach(Text3D.Motion.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if s.motion != .still {
                    slider("Speed — seconds per \(s.motion == .spin ? "turn" : "swing")",
                           binding(\.secondsPerCycle, "3D speed"), 0.5...10,
                           String(format: "%.1f s", s.secondsPerCycle))
                }
                if s.motion == .wiggle {
                    slider("Swing", binding(\.swingDegrees, "3D swing"), 5...90,
                           "\(Int(s.swingDegrees))°")
                }
                slider(s.motion == .spin ? "Starting turn" : "Turn",
                       binding(\.turnDegrees, "3D turn"), -90...90, "\(Int(s.turnDegrees))°")
                slider("Tilt", binding(\.tiltDegrees, "3D tilt"), -45...45, "\(Int(s.tiltDegrees))°")
                slider("Depth", binding(\.depth, "3D depth"), 0.05...1.0,
                       "\(Int((s.depth * 100).rounded()))%")
                slider("Bevel", binding(\.bevel, "3D bevel"), 0...0.12,
                       "\(Int((s.bevel * 100).rounded()))%")
                PaletteSwatchRow(document: document, color: Binding(
                    get: { s.sideColorHex.flatMap { Color(hex: $0) } ?? .gray },
                    set: { c in edit("3D side color") { $0?.sideColorHex = c.hexString() } }),
                    label: "Side color")
                if s.sideColorHex != nil {
                    Button("Sides follow the letter color") {
                        edit("3D side color") { $0?.sideColorHex = nil }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 18))
                }
                InfoTip("More about this",
                        "Export → Animated GIF (3D text loop) saves one full turn or swing.")
            }
        }
    }

    private func binding<V>(_ path: WritableKeyPath<Text3D, V>, _ label: String) -> Binding<V> {
        Binding(get: { (current ?? Text3D())[keyPath: path] },
                set: { v in edit(label) { $0?[keyPath: path] = v } })
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ readout: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 18)).foregroundStyle(.secondary)
                Spacer()
                Text(readout).font(.system(size: 18).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func edit(_ label: String, _ change: (inout Text3D?) -> Void) {
        guard let i = index else { return }
        document.captureHistoryBaselineIfNeeded()
        document.layers[i].updateText3D(change)
        document.recordHistory(toolID: Tool.text.rawValue, groupTitle: Tool.text.title,
                               actionLabel: label, layerID: layerID, coalesce: true)
    }
}

extension ImageLayer {
    /// Change the text element's 3D setting in place, keeping its string and style.
    mutating func updateText3D(_ change: (inout Text3D?) -> Void) {
        for i in elements.indices {
            if case .text(var t) = elements[i].content {
                change(&t.threeD)
                elements[i].content = .text(t)
                return
            }
        }
    }
}
