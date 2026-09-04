//
//  CameraTool.swift
//  Image Producer
//
//  The Camera stamps the canvas's VISIBLE layers onto a new topmost layer. That is the
//  whole tool — and Michael spotted the consequence before it was built: "animation and
//  stop motion". Shoot a frame, nudge the puppet, shoot again, and the layer stack is a
//  timeline. Three pieces of the animation rig already existed by accident: the
//  collision-avoidance numbering is a frame index, layer opacity is onion skinning, and
//  the per-layer PDF export is a flipbook. Only playback was actually missing.
//
//  Two rules hold the design together:
//
//  1. A frame carries its NEGATIVE. The PNG is the photograph; `CameraFrame.snapshot` is
//     the scene that made it. Two flattened pictures can only be cross-faded — the motion
//     is not in the pixels. Two snapshots give start and end for every layer's center,
//     scale and rotation, so an in-between is arithmetic and a re-render, not image
//     analysis. It also makes a frame re-enterable rather than a print.
//
//  2. The lightbox never touches the film. Onion skin and playback are DISPLAY ONLY. If
//     onion skin worked by turning down a layer's real opacity, that ghost would be a
//     visible layer and the next press would bake it in, compounding down the stack.
//

import SwiftUI
import Combine
import CoreGraphics

// MARK: - Capture

/// The layer name for the next frame: "{file name} (Camera n)", falling back to plain
/// "Camera n" for a document that has never been saved and has no file name to borrow.
@MainActor
private func cameraLayerName(_ document: ImageDocument, fileURL: URL?, index: Int) -> String {
    var base = fileURL?.deletingPathExtension().lastPathComponent ?? ""
    if base.isEmpty {
        let n = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.lowercased() != "untitled image" { base = n }
    }
    let taken = Set(document.layers.map(\.name))
    func candidate(_ k: Int) -> String {
        if base.isEmpty { return k == 1 ? "Camera" : "Camera \(k)" }
        return k == 1 ? "\(base) (Camera)" : "\(base) (Camera \(k))"
    }
    var k = max(1, index)
    while taken.contains(candidate(k)) { k += 1 }
    return candidate(k)
}

/// Press the shutter. Renders the visible layers at the configured scale, optionally
/// without the background and trimmed to the art, and puts the result on a new topmost
/// layer that carries its own negative.
@MainActor
func captureCameraFrame(_ document: ImageDocument, fileURL: URL?) {
    let s = document.camera
    guard let cg = renderCanvasImage(document, scale: CGFloat(s.scale),
                                     includeBackgrounds: s.includeBackground),
          var png = pngData(from: cg) else {
        document.camera.lastResult = "Nothing to capture — no visible layers rendered."
        return
    }
    var w = cg.width, h = cg.height

    // Trim to the art's own bounding box, measured off the rendered PNG rather than
    // guessed from the layers.
    if s.trimToArt, let unit = LayerArtBounds.unitRect(forPNG: png) {
        let r = CGRect(x: unit.minX * CGFloat(w), y: unit.minY * CGFloat(h),
                       width: unit.width * CGFloat(w), height: unit.height * CGFloat(h)).integral
        if r.width >= 1, r.height >= 1,
           let crop = cg.cropping(to: r), let cropped = pngData(from: crop) {
            png = cropped; w = crop.width; h = crop.height
        }
    }

    let index = document.nextCameraFrameIndex
    document.captureHistoryBaselineIfNeeded()

    var layer = ImageLayer(name: cameraLayerName(document, fileURL: fileURL, index: index),
                           role: .content)
    layer.setImage(png)
    layer.cameraFrame = CameraFrame(index: index,
                                    snapshot: document.cameraNegative(),
                                    includedBackground: s.includeBackground,
                                    scale: s.scale,
                                    trimmedToArt: s.trimToArt,
                                    exposures: max(1, s.exposures))
    // ⚠️ In Animation mode a frame is a RECORD, not part of the scene. Left visible it
    // would sit on top of everything and the NEXT press would photograph this photograph.
    // As a plain stamp (Animation off) visible is exactly what you want.
    layer.isVisible = !s.animationMode
    document.layers.append(layer)          // end of array = top of the visual stack

    document.recordHistory(toolID: Tool.camera.rawValue,
                           groupTitle: Tool.camera.title,
                           actionLabel: "Capture",
                           layerID: layer.id)

    var bits = ["Frame \(index)", "\(w)×\(h)"]
    if !s.includeBackground { bits.append("transparent") }
    if s.scale != 1 { bits.append("\(Int(s.scale))×") }
    if s.trimToArt { bits.append("trimmed") }
    if s.exposures > 1 { bits.append("on \(s.exposures)s") }
    if s.animationMode { bits.append("hidden (Animation)") }
    document.camera.lastResult = bits.joined(separator: " · ")
}

// MARK: - In-betweening

/// Linear blend of two placements. Easing shapes `t` before it gets here, so this stays
/// the straight-line case — the seam a motion PATH would replace when the Path tool ships
/// (real movement follows arcs, and a straight tween is wrong the same way linear timing
/// is). Kept as one function precisely so that swap is one function later.
private func blend(_ a: LayerTransform, _ b: LayerTransform, _ t: Double) -> LayerTransform {
    var out = a
    out.center = CGPoint(x: a.center.x + (b.center.x - a.center.x) * t,
                         y: a.center.y + (b.center.y - a.center.y) * t)
    out.scale = a.scale + (b.scale - a.scale) * t
    out.rotationDegrees = a.rotationDegrees + (b.rotationDegrees - a.rotationDegrees) * t
    if let ca = a.contentAspect, let cb = b.contentAspect {
        out.contentAspect = ca + (cb - ca) * t
    }
    return out
}

/// 3-tap smoothing of the shot path: pull each frame toward the average of its
/// neighbours. `amount` blends between the shot positions (0) and fully smoothed (1),
/// because full smoothing damps intentional motion too — a sharp direction change gets
/// rounded into a curve. Endpoints are left alone; they have only one neighbour and
/// moving them drags the whole sequence.
private func smoothed(_ scenes: [[ImageLayer]], amount: Double) -> [[ImageLayer]] {
    guard amount > 0, scenes.count >= 3 else { return scenes }
    var out = scenes
    for i in 1..<(scenes.count - 1) {
        for (j, layer) in scenes[i].enumerated() {
            guard let prev = scenes[i - 1].first(where: { $0.id == layer.id })?.transform,
                  let next = scenes[i + 1].first(where: { $0.id == layer.id })?.transform
            else { continue }
            let cur = layer.transform
            var avg = cur
            avg.center = CGPoint(x: (prev.center.x + 2 * cur.center.x + next.center.x) / 4,
                                 y: (prev.center.y + 2 * cur.center.y + next.center.y) / 4)
            avg.scale = (prev.scale + 2 * cur.scale + next.scale) / 4
            avg.rotationDegrees = (prev.rotationDegrees + 2 * cur.rotationDegrees
                                   + next.rotationDegrees) / 4
            out[i][j].transform = blend(cur, avg, amount)
        }
    }
    return out
}

/// Build the transition frames between every pair of shot frames. Replaces any previously
/// generated tweens — they are derived, so regenerating is always safe — and never touches
/// a real exposure.
@MainActor
func generateCameraInBetweens(_ document: ImageDocument) {
    let s = document.camera
    let shot = document.cameraFrames.filter { $0.cameraFrame?.isTween == false }
    guard shot.count >= 2 else {
        document.camera.lastResult = "Need at least two shot frames to tween."
        return
    }
    guard s.tweenSteps >= 1 else { return }

    var scenes: [[ImageLayer]] = []
    for frame in shot {
        guard let data = frame.cameraFrame?.snapshot,
              let snap = try? JSONDecoder().decode(DocumentSnapshot.self, from: data) else {
            document.camera.lastResult =
                "Frame \(frame.cameraFrame?.index ?? 0) has no negative — it can only be cross-faded."
            return
        }
        scenes.append(snap.layers)
    }
    scenes = smoothed(scenes, amount: s.smoothing)

    document.captureHistoryBaselineIfNeeded()
    document.layers.removeAll { $0.cameraFrame?.isTween == true }

    var made = 0
    var ordered: [ImageLayer] = []
    for i in 0..<shot.count {
        ordered.append(shot[i])
        guard i < shot.count - 1 else { continue }
        for step in 1...s.tweenSteps {
            let raw = Double(step) / Double(s.tweenSteps + 1)
            let t = s.easing.shape(raw)
            var mid = scenes[i]
            for (j, layer) in mid.enumerated() {
                guard let to = scenes[i + 1].first(where: { $0.id == layer.id })?.transform
                else { continue }
                mid[j].transform = blend(layer.transform, to, t)
            }
            let temp = ImageDocument(name: document.name,
                                     canvasWidth: document.canvasWidth,
                                     canvasHeight: document.canvasHeight,
                                     layers: mid, palette: document.palette, cropRect: nil)
            guard let cg = renderCanvasImage(temp, scale: CGFloat(s.scale),
                                             includeBackgrounds: s.includeBackground),
                  let png = pngData(from: cg) else { continue }
            var tween = ImageLayer(name: "\(shot[i].name) → \(step)", role: .content)
            tween.setImage(png)
            // An in-between takes ONE beat regardless of the shot's hold — the hold is
            // what you are smoothing between, so repeating it here would undo the point.
            tween.cameraFrame = CameraFrame(index: 0, snapshot: nil,
                                            includedBackground: s.includeBackground,
                                            scale: s.scale, trimmedToArt: false,
                                            isTween: true, exposures: 1)
            tween.isVisible = false
            ordered.append(tween)
            made += 1
        }
    }

    // Renumber the whole timeline so shot frames and in-betweens share one running order.
    let ids = Set(ordered.map(\.id))
    document.layers.removeAll { ids.contains($0.id) }
    for (n, var layer) in ordered.enumerated() {
        layer.cameraFrame?.index = n + 1
        document.layers.append(layer)
    }

    document.recordHistory(toolID: Tool.camera.rawValue,
                           groupTitle: Tool.camera.title,
                           actionLabel: "In-betweens",
                           layerID: nil)
    document.camera.lastResult =
        "\(made) in-between\(made == 1 ? "" : "s") · \(s.easing.title)"
        + (s.smoothing > 0 ? " · smoothing \(Int(s.smoothing * 100))%" : "")
}

// MARK: - Inspector

struct CameraInspector: View {
    @ObservedObject var document: ImageDocument
    var fileURL: URL?

    private var shotCount: Int {
        document.cameraFrames.filter { $0.cameraFrame?.isTween == false }.count
    }
    private var frameCount: Int { document.cameraFrames.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Always says what happened. Landing on an inspector that does not confirm
            // the capture is the same failure shape as a Done button reporting nothing.
            Text(document.camera.lastResult ?? "No frames captured yet.")
                .font(.system(size: 17))
                .foregroundStyle(document.camera.lastResult == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                captureCameraFrame(document, fileURL: fileURL)
            } label: {
                Label("Capture", systemImage: "camera").font(.system(size: 18))
            }
            .buttonStyle(.borderedProminent)

            Divider()

            // ── What a press captures
            Group {
                Text("Capture").font(.system(size: 17, weight: .semibold))
                Toggle("Include background", isOn: $document.camera.includeBackground)
                Text(document.camera.includeBackground
                     ? "Bakes in whichever of Light/Dark is showing."
                     : "Transparent stamp of just the art.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)

                Picker("Scale", selection: $document.camera.scale) {
                    Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0)
                }
                .pickerStyle(.segmented)

                Toggle("Trim to art bounds", isOn: $document.camera.trimToArt)

                Stepper("Hold each capture: \(document.camera.exposures) beat\(document.camera.exposures == 1 ? "" : "s")",
                        value: $document.camera.exposures, in: 1...8)
                Text(document.camera.exposures == 1
                     ? "On 1s — a new drawing every beat."
                     : "On \(document.camera.exposures)s — limited animation. Anime runs about 8 drawings a second by holding each for three.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }

            Divider()

            // ── Stop motion
            Group {
                Text("Stop Motion").font(.system(size: 17, weight: .semibold))
                Toggle("Animation mode", isOn: $document.camera.animationMode)
                Text(document.camera.animationMode
                     ? "Move stops forking — the shutter is the commit. A nudge you did not photograph is gone."
                     : "Move keeps its own hidden copy of each placement.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Text("\(shotCount) shot · \(frameCount) frame\(frameCount == 1 ? "" : "s") total")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }

            Divider()

            // ── Lightbox — display only, never captured
            Group {
                Text("Lightbox").font(.system(size: 17, weight: .semibold))
                Toggle("Onion skin", isOn: $document.camera.onionSkin)
                if document.camera.onionSkin {
                    Stepper("Frames back: \(document.camera.onionFrames)",
                            value: $document.camera.onionFrames, in: 1...5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strength  \(Int(document.camera.onionStrength * 100))%")
                            .font(.system(size: 15))
                        Slider(value: $document.camera.onionStrength, in: 0.05...0.6)
                    }
                }
            }

            Divider()

            // ── Playback — display only
            Group {
                Text("Playback").font(.system(size: 17, weight: .semibold))
                HStack {
                    Button {
                        document.camera.isPlaying.toggle()
                        if document.camera.isPlaying, document.camera.playPos == nil {
                            document.camera.playPos = -1
                        }
                    } label: {
                        Label(document.camera.isPlaying ? "Stop" : "Play",
                              systemImage: document.camera.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .disabled(frameCount == 0)
                    Button("Exit preview") {
                        document.camera.isPlaying = false
                        document.camera.soloFrameIndex = nil
                        document.camera.playPos = nil
                    }
                    .disabled(document.camera.soloFrameIndex == nil)
                }
                Toggle("Loop", isOn: $document.camera.loop)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(document.camera.fps)) fps").font(.system(size: 15))
                    Slider(value: $document.camera.fps, in: 1...24)
                }
                if frameCount > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frame \(document.camera.soloFrameIndex ?? 0) of \(frameCount)"
                             + "  ·  \(document.playbackTimeline.count) beats")
                            .font(.system(size: 15))
                        Slider(value: Binding(
                            get: { Double(document.camera.soloFrameIndex ?? 1) },
                            set: {
                                let f = Int($0.rounded())
                                document.camera.soloFrameIndex = f
                                document.camera.playPos =
                                    document.playbackTimeline.firstIndex(of: f)
                            }),
                               in: 1...Double(frameCount))
                    }
                }
                // Retime the frame you are looking at — the cutout animator's real control.
                if let solo = document.camera.soloFrameIndex,
                   let i = document.layers.firstIndex(where: { $0.cameraFrame?.index == solo }) {
                    Stepper("Hold frame \(solo): \(document.layers[i].cameraFrame?.exposures ?? 1)",
                            value: Binding(
                                get: { document.layers[i].cameraFrame?.exposures ?? 1 },
                                set: { document.layers[i].cameraFrame?.exposures = max(1, $0) }),
                            in: 1...8)
                }
            }

            Divider()

            // ── In-betweens
            Group {
                Text("In-Betweens").font(.system(size: 17, weight: .semibold))
                Stepper("Frames between: \(document.camera.tweenSteps)",
                        value: $document.camera.tweenSteps, in: 1...7)
                Picker("Easing", selection: $document.camera.easing) {
                    ForEach(CameraEasing.allCases) { Text($0.title).tag($0) }
                }
                Text("Linear reads as mechanical — real motion starts slow and settles.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Path smoothing  \(Int(document.camera.smoothing * 100))%")
                        .font(.system(size: 15))
                    Slider(value: $document.camera.smoothing, in: 0...1)
                }
                Text("Pulls each shot toward its neighbours. Full smoothing flattens intentional motion too.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                HStack {
                    Button("Generate") { generateCameraInBetweens(document) }
                        .disabled(shotCount < 2)
                    Button("Clear") {
                        document.layers.removeAll { $0.cameraFrame?.isTween == true }
                        document.camera.lastResult = "In-betweens cleared."
                    }
                }
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 1.0 / max(1, document.camera.fps),
                                 on: .main, in: .common).autoconnect()) { _ in
            advancePlayback()
        }
    }

    /// Steps through the EXPANDED timeline, so a frame held on 3s occupies three beats.
    private func advancePlayback() {
        guard document.camera.isPlaying else { return }
        let timeline = document.playbackTimeline
        guard !timeline.isEmpty else { return }
        var next = (document.camera.playPos ?? -1) + 1
        if next >= timeline.count {
            guard document.camera.loop else {
                document.camera.isPlaying = false
                return
            }
            next = 0
        }
        document.camera.playPos = next
        document.camera.soloFrameIndex = timeline[next]
    }
}
