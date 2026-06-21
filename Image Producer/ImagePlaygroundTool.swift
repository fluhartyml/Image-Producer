//
//  ImagePlaygroundTool.swift
//  Image Producer
//
//  The Image Playground tool (roadmap A1): Apple's on-device AI image generation,
//  wired as ONE tool with TWO modes (Michael 2026-06-11):
//    • MAKER  — generate a brand-new image on a NEW layer.
//    • FILTER — feed the ACTIVE layer's current art + a prompt, and REPLACE that
//               layer with the restyled result.
//
//  ENGINE = Apple's vetted `.imagePlaygroundSheet` (iOS 18.1+ / macOS 15.1+). The
//  PROMPT IS TYPED IN APPLE'S SHEET, not in the inspector: our own in-inspector
//  text field was disrupting typing (per-keystroke churn / focus loss that drove
//  Michael up the wall 2026-06-21), and Apple's panel already has a solid prompt
//  input plus styles, content safety, and candidate picking. So the inspector is
//  just two buttons that present the sheet; the user types there. Cleaner AND more
//  publishable. (If a reliable in-inspector field is wanted later, it can be added
//  back once the field-rebuild issue is understood — kept out for now on purpose.)
//
//  API verified vs the installed Xcode-27 SDK swiftinterface (2026-06-21):
//    func imagePlaygroundSheet(isPresented:concept:sourceImage:onCompletion:) -> View
//    var EnvironmentValues.supportsImagePlayground: Bool   (cross-platform gate)
//
//  AVAILABILITY: gated by @Environment(\.supportsImagePlayground); graceful
//  "needs Apple Intelligence" state where unsupported. Deployment target 27.0, so
//  the 18.1+ APIs need no #available guards.
//
//  ⚠️ NOT device-verified: AI generation only runs on Apple-Intelligence hardware,
//  so the generate/restyle round-trip needs Michael's confirmation. Compiles green.
//

import SwiftUI
import ImagePlayground

/// Tool #11's inspector — two buttons that present Apple's Image Playground sheet.
struct ImagePlaygroundInspector: View {
    @ObservedObject var document: IconDocument
    let activeLayerID: IconLayer.ID?

    /// Cross-platform Apple-Intelligence capability check (no UIKit needed).
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

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
        // The user types the prompt inside Apple's sheet (concept seeded empty).
        .imagePlaygroundSheet(isPresented: $showMaker, concept: "") { url in
            placeNewLayer(from: url)
        }
        // Filter seeds the sheet with the active layer's current art as the source.
        .imagePlaygroundSheet(isPresented: $showFilter, concept: "", sourceImage: filterSource) { url in
            replaceActiveLayer(from: url)
        }
    }

    @ViewBuilder private var supported: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MAKER — a new layer from a prompt typed in Apple's sheet.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make — new layer").font(.subheadline).bold()
                    Button { showMaker = true } label: {
                        Label("New Image…", systemImage: "plus.rectangle.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Opens Apple's Image Playground — type your prompt there, generate, and the result drops on a new layer.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                // FILTER — restyle the active layer's current art.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter — restyle this layer").font(.subheadline).bold()
                    Button { startFilter() } label: {
                        Label("Restyle This Layer…", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeFilterable == nil)
                    Text(activeFilterable == nil
                         ? "Select a content layer that has art on it to restyle."
                         : "Opens Image Playground seeded with this layer's art — describe the change there; the result replaces it.")
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
        var layer = IconLayer(name: "AI Image", role: .content)
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
}
