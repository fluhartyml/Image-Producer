//
//  ImagePlaygroundTool.swift
//  Image Producer
//
//  The Image Playground tool (roadmap A1): Apple's on-device AI image generation,
//  wired as ONE tool with TWO modes (Michael 2026-06-11):
//    • MAKER  — a text prompt generates a brand-new image on a NEW layer.
//    • FILTER — a text prompt + the ACTIVE layer's current art are fed in together,
//               and the result REPLACES that layer (restyle what's already there).
//
//  ENGINE = Apple's vetted `.imagePlaygroundSheet` (iOS 18.1+ / macOS 15.1+),
//  chosen over the programmatic `ImageCreator` for a publishable v1: Apple owns the
//  generation UX, style selection, content safety, and candidate picking — we just
//  hand it a concept (+ an optional source image) and place the returned image.
//  The inspector keeps Michael's TWO prompt boxes; the sheet is seeded from them.
//  API verified against the installed Xcode-27 SDK swiftinterface (2026-06-21):
//    func imagePlaygroundSheet(isPresented:concept:sourceImage:onCompletion:) -> View
//    var EnvironmentValues.supportsImagePlayground: Bool   (cross-platform gate)
//
//  AVAILABILITY: gated by @Environment(\.supportsImagePlayground) — true only where
//  Apple Intelligence is present + enabled (iPhone 15 Pro / 16+, Apple-silicon Mac).
//  Where it's false the inspector shows a graceful "not available here" state — no
//  error path. Deployment target is 27.0, so the 18.1+ APIs need no #available guards.
//
//  ⚠️ NOT yet device-verified: AI generation only runs on Apple-Intelligence
//  hardware, so the generate/restyle round-trip needs Michael to confirm on a
//  capable device. Compiles green on iOS + macOS; the wiring is what's verified here.
//

import SwiftUI
import ImagePlayground

/// Tool #11's inspector — the Image Playground Maker/Filter surface.
struct ImagePlaygroundInspector: View {
    @ObservedObject var document: IconDocument
    let activeLayerID: IconLayer.ID?

    /// Cross-platform Apple-Intelligence capability check (no UIKit needed).
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @State private var makerPrompt = ""
    @State private var filterPrompt = ""
    @State private var showMaker = false
    @State private var showFilter = false
    @State private var filterSource: Image?     // the active layer rendered, seeds Filter
    @State private var failed = false

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    /// The active layer iff it's a CONTENT layer that actually has art on it —
    /// Filter needs something to restyle.
    private var activeFilterable: IconLayer? {
        guard let i = activeIndex, case .content = document.layers[i].role,
              !document.layers[i].elements.isEmpty else { return nil }
        return document.layers[i]
    }

    var body: some View {
        Group {
            if supportsImagePlayground {
                supported
            } else {
                PanelPlaceholder(
                    systemImage: "apple.image.playground",
                    title: "Image Playground",
                    subtitle: "Needs Apple Intelligence. Turn it on in Settings on a supported device (iPhone 15 Pro / 16 or later, or an Apple-silicon Mac), then this tool generates art on device.")
            }
        }
        // Maker: prompt only -> generate a fresh image.
        .imagePlaygroundSheet(isPresented: $showMaker, concept: makerPrompt) { url in
            placeNewLayer(from: url)
        }
        // Filter: prompt + the active layer's current art as the source.
        .imagePlaygroundSheet(isPresented: $showFilter, concept: filterPrompt, sourceImage: filterSource) { url in
            replaceActiveLayer(from: url)
        }
    }

    @ViewBuilder private var supported: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MAKER — a new layer from a prompt.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make — new layer").font(.subheadline).bold()
                    TextField("Describe an image to generate…", text: $makerPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        // Kill QuickType/autofill suggestions: the predicted "past
                        // words" were hijacking the field — replacing text mid-sentence
                        // and causing the freeze (Michael 2026-06-21).
                        .autocorrectionDisabled()
                    Button { showMaker = true } label: {
                        Label("Generate New Layer", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Generates from your prompt in Apple's Image Playground, then drops the result on a new layer.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                // FILTER — restyle the active layer's current art.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter — restyle this layer").font(.subheadline).bold()
                    TextField("Describe how to restyle the active layer…", text: $filterPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                    Button { startFilter() } label: {
                        Label("Restyle Active Layer", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeFilterable == nil)
                    Text(activeFilterable == nil
                         ? "Select a content layer that has art on it to restyle."
                         : "Feeds this layer's current art plus your prompt to Image Playground and replaces it with the result.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if failed {
                    Text("Couldn't place the generated image.")
                        .font(.caption).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Actions

    /// Render the active layer's current look into a SwiftUI Image to seed the
    /// Filter sheet's source, then present it.
    @MainActor private func startFilter() {
        guard let layer = activeFilterable else { return }
        let side = CGFloat(document.canvasSize)
        let solo = IconDocument(name: document.name, canvasSize: document.canvasSize,
                                layers: [layer], palette: document.palette, cropRect: nil)
        let renderer = ImageRenderer(content: IconCompositeView(document: solo, side: side))
        renderer.scale = 1
        if let cg = renderer.cgImage, let png = pngData(from: cg),
           let platform = PlatformImage(data: png) {
            filterSource = Image(platformImage: platform)
        } else {
            filterSource = nil
        }
        showFilter = true
    }

    /// Maker result -> a brand-new content layer at the top of the stack.
    private func placeNewLayer(from url: URL) {
        guard let png = loadPNG(from: url) else { failed = true; return }
        failed = false
        var layer = IconLayer(name: layerName(from: makerPrompt), role: .content)
        layer.setImage(png)
        document.layers.append(layer)   // end of array = top of the visual stack
    }

    /// Filter result -> replace the active content layer's art.
    private func replaceActiveLayer(from url: URL) {
        guard let png = loadPNG(from: url), let i = activeIndex,
              case .content = document.layers[i].role else { failed = true; return }
        failed = false
        document.layers[i].setImage(png)
    }

    /// The sheet hands back a file URL to the generated image (not necessarily PNG);
    /// normalize to PNG bytes for the layer model.
    private func loadPNG(from url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return pngData(fromImageData: raw)
    }

    /// Auto-name a new layer from its prompt (content names the layer).
    private func layerName(from prompt: String) -> String {
        let t = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "AI Image" : String(t.prefix(24))
    }
}
