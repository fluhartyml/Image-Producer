//
//  SubjectCutout.swift
//  Image Producer
//
//  Remove Background — lift the subject out of a layer and throw the scene away.
//
//  Why this exists (Michael, 2026-08-20): Image Playground returns whole SCENES. Ask it
//  for a lighthouse and you get a lighthouse plus sky, ocean, cliff and grass, opaque edge
//  to edge. To composite that onto another layer you have to cut the subject out, and the
//  only tool for it was the eraser — which at 1024px is not a real option.
//
//  Apple's Vision does this on-device (the same subject lift Photos and Preview use), so
//  there is no third-party dependency and nothing leaves the Mac. Verified against real
//  artwork before this file was written: one instance, clean alpha, and it kept a 3px
//  antenna line.
//
//  Honest limit: Vision decides what the SUBJECT is. On a lighthouse standing on a cliff it
//  will often return the lighthouse AND the rock as one instance, because to the model they
//  are one connected object. When it finds more than one instance the user picks which to
//  keep — the app never silently chooses for them.
//

import Foundation
import Vision
import CoreImage
import CoreGraphics

enum SubjectCutout {

    enum Failure: LocalizedError {
        case unreadable
        case noSubjectFound
        case maskingFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "That layer's picture couldn't be read."
            case .noSubjectFound:
                "No subject was found to lift. This works on a picture with a clear subject sitting on a background — a flat colour field or a pattern has nothing to separate."
            case .maskingFailed(let why):
                "The cutout failed: \(why)"
            }
        }
    }

    /// How many separate subjects Vision can see in this picture. Called first so the UI
    /// knows whether to ask the user anything — 1 means just do it.
    static func instanceCount(in imageData: Data) throws -> Int {
        let (cg, _) = try decode(imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) }
        catch { throw Failure.maskingFailed(error.localizedDescription) }
        guard let obs = request.results?.first else { throw Failure.noSubjectFound }
        return obs.allInstances.count
    }

    /// Lift `instances` out of the picture and return PNG bytes with everything else
    /// transparent. Pass nil to take every subject Vision found.
    ///
    /// `croppedToInstancesExtent: false` is deliberate — the cutout keeps the layer's
    /// original dimensions so it stays registered with the canvas. Cropping to the subject
    /// would silently move the art.
    static func lift(imageData: Data, instances: IndexSet? = nil) throws -> Data {
        let (cg, _) = try decode(imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) }
        catch { throw Failure.maskingFailed(error.localizedDescription) }
        guard let obs = request.results?.first else { throw Failure.noSubjectFound }

        let wanted = instances ?? obs.allInstances
        guard !wanted.isEmpty else { throw Failure.noSubjectFound }

        do {
            let buffer = try obs.generateMaskedImage(ofInstances: wanted,
                                                     from: handler,
                                                     croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buffer)
            let ctx = CIContext()
            guard let out = ctx.createCGImage(ci, from: ci.extent),
                  let png = pngData(from: out) else {
                throw Failure.maskingFailed("the lifted image could not be encoded")
            }
            return png
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.maskingFailed(error.localizedDescription)
        }
    }

    /// A small preview of one instance on its own, so the chooser can show what each
    /// candidate actually is rather than making the user guess from a number.
    static func preview(imageData: Data, instance: Int) -> Data? {
        guard let (cg, _) = try? decode(imageData) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first,
              obs.allInstances.contains(instance),
              let buffer = try? obs.generateMaskedImage(ofInstances: IndexSet(integer: instance),
                                                        from: handler,
                                                        croppedToInstancesExtent: true)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return pngData(from: out)
    }

    private static func decode(_ data: Data) throws -> (CGImage, CGSize) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.unreadable
        }
        return (cg, CGSize(width: cg.width, height: cg.height))
    }
}

// MARK: - Remove Background inspector

import SwiftUI

/// **Remove Background** — select the background of the active layer's picture and clear it,
/// so the layer BELOW shows through. Michael's framing (2026-08-20): *"it would be useful to
/// blend layers by selecting a layer above erasing the background so you can see the layer
/// below."* That is the point of the tool — compositing, not cropping.
///
/// Sits beside the Eraser's Magic Eraser rather than replacing it. The Magic Eraser matches a
/// COLOUR, which wants a flat background; this matches a SUBJECT, so it copes with the soft
/// gradient skies and clouds that Image Playground produces and colour-matching cannot touch.
///
/// Non-destructive, exactly like the Magic Eraser: the cutout arrives on a NEW layer above and
/// the original is hidden, never overwritten.
struct RemoveBackgroundInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

    @State private var instanceCount: Int?
    @State private var chosen: Set<Int> = []
    @State private var previews: [Int: Data] = [:]
    @State private var working = false
    @State private var problem: String?

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }
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
                Text("Keeps the subject, clears everything behind it — so the layer underneath shows through.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)

                Button { scan() } label: {
                    Label(working ? "Finding the subject…" : "Remove Background",
                          systemImage: "person.and.background.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)

                if let n = instanceCount, n > 1 {
                    Divider()
                    Text("Found \(n) separate subjects. Pick the ones to keep.")
                        .font(.system(size: 18))
                    Text("A lighthouse standing on a cliff often comes back as one piece — the model sees them as a single connected object. Where it splits them, this is where you drop the half you don't want.")
                        .font(.system(size: 18)).foregroundStyle(.secondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(previews.keys.sorted()), id: \.self) { i in
                                instanceChip(i)
                            }
                        }
                    }

                    Button { apply(instances: IndexSet(chosen)) } label: {
                        Label("Keep \(chosen.count) selected", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty || working)
                }

                if let problem {
                    Text(problem).font(.system(size: 18)).foregroundStyle(.red)
                }

                Text("The cutout lands on a new layer above this one. The original is hidden, not replaced.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            PanelPlaceholder(systemImage: "person.and.background.dotted",
                             title: "Remove Background",
                             subtitle: "Select a content layer that has a picture on it")
        }
    }

    @ViewBuilder
    private func instanceChip(_ i: Int) -> some View {
        let isOn = chosen.contains(i)
        Button {
            if isOn { chosen.remove(i) } else { chosen.insert(i) }
        } label: {
            VStack(spacing: 4) {
                if let d = previews[i], let pi = PlatformImage(data: d) {
                    Image(platformImage: pi).resizable().scaledToFit().frame(width: 84, height: 84)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 32))
                        .frame(width: 84, height: 84)
                }
                Text("\(i + 1)").font(.system(size: 18))
            }
            .padding(6)
            .background(isOn ? Color.accentColor.opacity(0.25) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Count first, and only ask the user something when there is genuinely a choice.
    /// One subject is the common case and it should be one press, not a dialog.
    private func scan() {
        guard let (_, png) = activeImage else { return }
        problem = nil; working = true; previews = [:]; chosen = []
        Task {
            do {
                let n = try SubjectCutout.instanceCount(in: png)
                if n <= 1 {
                    await MainActor.run { instanceCount = n }
                    apply(instances: nil)
                    return
                }
                var shots: [Int: Data] = [:]
                for i in 0..<n {
                    if let p = SubjectCutout.preview(imageData: png, instance: i) { shots[i] = p }
                }
                await MainActor.run {
                    instanceCount = n
                    previews = shots
                    chosen = Set(0..<n)          // default to everything; deselect to drop a piece
                    working = false
                }
            } catch {
                await MainActor.run {
                    problem = (error as? SubjectCutout.Failure)?.errorDescription ?? error.localizedDescription
                    working = false
                }
            }
        }
    }

    private func apply(instances: IndexSet?) {
        guard let (idx, png) = activeImage else { return }
        problem = nil; working = true
        Task {
            do {
                let out = try SubjectCutout.lift(imageData: png, instances: instances)
                await MainActor.run {
                    document.captureHistoryBaselineIfNeeded()
                    let newID = document.addResultLayer(out, above: idx, nameSuffix: "cutout")
                    document.recordHistory(toolID: Tool.cutout.rawValue,
                                           groupTitle: Tool.cutout.title,
                                           actionLabel: "Remove Background",
                                           layerID: newID ?? document.layers[idx].id)
                    instanceCount = nil; previews = [:]; chosen = []
                    working = false
                }
            } catch {
                await MainActor.run {
                    problem = (error as? SubjectCutout.Failure)?.errorDescription ?? error.localizedDescription
                    working = false
                }
            }
        }
    }
}

// MARK: - Magic Lasso inspector

/// **Magic Lasso** — click a region on the canvas and the matching contiguous area is cleared.
///
/// The third tool in the cut-out family, and the three do different jobs:
///   • **Magic Eraser** (in Eraser) matches a COLOUR anywhere, or floods in from the border.
///   • **Remove Background** matches a SUBJECT — it copes with soft gradient skies.
///   • **Magic Lasso** matches a REGION you point at — the surgical one, for the piece the
///     other two leave behind (the cliff under a lifted lighthouse, one cloud, one shadow).
struct MagicLassoInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?
    @EnvironmentObject var pen: PixelPen   // same idiom as the other inspectors

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }
    private var hasImage: Bool {
        guard let idx = activeIndex else { return false }
        for el in document.layers[idx].elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { return true }
        }
        return false
    }

    var body: some View {
        if hasImage {
            VStack(alignment: .leading, spacing: 14) {
                Text("Click a region on the canvas and it clears, so the layer below shows through. Hover first — the area that will go is highlighted in red.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tolerance  \(Int(pen.lassoTolerance))").font(.system(size: 18))
                    Slider(value: $pen.lassoTolerance, in: 0...160, step: 1)
                    Text("How different a pixel can be from the one you clicked and still go. Low stops at the faintest line. High walks through a soft sky or a gradient.")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                }

                Text("Click as many times as you need — sky, then ocean, then the rock. They all go on one layer rather than stacking a new one each click, and History steps back through them one at a time.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)

                Text("Your original layer is kept and hidden, never overwritten.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            PanelPlaceholder(systemImage: "lasso.badge.sparkles",
                             title: "Magic Lasso",
                             subtitle: "Select a content layer that has a picture on it")
        }
    }
}
