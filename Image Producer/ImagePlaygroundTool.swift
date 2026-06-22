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
//  DESIGN (Michael 2026-06-21): the user TYPES their prompt in a text box IN THIS
//  INSPECTOR (one-stop, intuitive — no pasting required), then presses one of two
//  buttons. The typed prompt is handed to Apple's `.imagePlaygroundSheet` as the
//  `concept:` SEED only when a button is pressed — so the sheet opens already
//  filled in and the user never types into Apple's own field.
//
//  WHY type here and not in Apple's sheet: on the OS/Xcode 27 beta Apple's sheet
//  field ignores the controls that should disable name-detection/autocomplete
//  (personalization=.disabled + every system text setting off) and resets typing
//  per keystroke. Our box is a PLAIN text field (no people-detection), and the
//  prompt is decoupled from the sheet (passed only on button press — a LIVE
//  concept binding was what reset our field in an earlier attempt). See memory
//  project_image_producer_playground_paste_workaround.
//
//  ENGINE = Apple's vetted `.imagePlaygroundSheet` (iOS 18.1+/macOS 15.1+);
//  ImageCreator is deprecated in iOS 27. API verified vs the installed Xcode-27
//  SDK swiftinterface (2026-06-21). AVAILABILITY gated by
//  @Environment(\.supportsImagePlayground); graceful "needs Apple Intelligence"
//  state where unsupported. Deployment target 27.0 → no #available guards.
//
//  ⚠️ NOT device-verified: AI generation needs Apple-Intelligence hardware, and
//  whether typing in our box is clean on the 27 beta is Michael's to confirm.
//

import SwiftUI
import ImagePlayground

/// Tool #11's inspector — a prompt box + Make/Restyle buttons that seed Apple's sheet.
struct ImagePlaygroundInspector: View {
    @ObservedObject var document: IconDocument
    let activeLayerID: IconLayer.ID?

    /// Cross-platform Apple-Intelligence capability check (no UIKit needed).
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    @State private var prompt = ""            // what the user types (touched only by typing)
    @State private var sheetConcept = ""      // seeded into the sheet ONLY on a button press
    @State private var showMaker = false
    @State private var showFilter = false
    @State private var filterSource: Image?   // the active layer rendered, seeds Filter
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

    /// Image Playground options with Apple's "Personalization" (people-from-library)
    /// turned OFF. ImagePlaygroundOptions.Personalization = automatic/enabled/disabled
    /// (SDK-verified). NOTE: the 27 beta currently ignores this — kept anyway since
    /// it's the documented control.
    private var personalizationDisabled: ImagePlaygroundOptions {
        var options = ImagePlaygroundOptions()
        options.personalization = .disabled
        return options
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
        // concept = sheetConcept (set on button press), NOT the live `prompt`, so typing
        // in the box never re-configures the sheet.
        .imagePlaygroundSheet(isPresented: $showMaker, concept: sheetConcept) { url in
            placeNewLayer(from: url)
        }
        .imagePlaygroundSheet(isPresented: $showFilter, concept: sheetConcept, sourceImage: filterSource) { url in
            replaceActiveLayer(from: url)
        }
        .imagePlaygroundOptions(personalizationDisabled)
    }

    @ViewBuilder private var supported: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Describe what Image Playground should make:")
                    .font(.subheadline)

                // Plain text box on a LIGHTER fill so it stands out against the dark
                // inspector (Michael 2026-06-21). Autocomplete off.
                TextField("e.g. a vase of sunflowers, no background…",
                          text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.18))
                    )

                Button { startMaker() } label: {
                    Label("Image Playground: New Layer", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { startFilter() } label: {
                    Label("Filter → Edit Current Layer", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(activeFilterable == nil)

                Text(activeFilterable == nil
                     ? "New Layer drops the result on a fresh layer. Restyle needs a content layer with art selected."
                     : "New Layer = fresh layer · Restyle = redo the selected layer's art with your prompt.")
                    .font(.caption2).foregroundStyle(.secondary)

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

    /// Maker — seed the sheet with the typed prompt and present it.
    private func startMaker() {
        sheetConcept = prompt
        showMaker = true
    }

    /// Filter — render the active layer to seed the source image, set the prompt, present.
    @MainActor private func startFilter() {
        guard let layer = activeFilterable else { return }
        let solo = IconDocument(name: document.name, canvasWidth: document.canvasWidth,
                                canvasHeight: document.canvasHeight,
                                layers: [layer], palette: document.palette, cropRect: nil)
        let renderer = ImageRenderer(content: IconCompositeView(document: solo, size: document.canvasPixelSize))
        renderer.scale = 1
        if let cg = renderer.cgImage, let png = pngData(from: cg),
           let platform = PlatformImage(data: png) {
            filterSource = Image(platformImage: platform)
        } else {
            filterSource = nil
        }
        sheetConcept = prompt
        showFilter = true
    }

    /// Maker result -> a brand-new content layer at the top of the stack, named from the prompt.
    private func placeNewLayer(from url: URL) {
        guard let png = loadPNG(from: url) else { failed = true; return }
        failed = false
        var layer = IconLayer(name: layerName(from: prompt), role: .content)
        layer.setImage(png)
        document.layers.append(layer)   // end of array = top of the visual stack
    }

    /// Filter result -> NON-DESTRUCTIVE: the AI edit lands on a new layer above the
    /// source, and the original is hidden (kept), not overwritten — there's no undo.
    private func replaceActiveLayer(from url: URL) {
        guard let png = loadPNG(from: url), let i = activeIndex,
              case .content = document.layers[i].role else { failed = true; return }
        failed = false
        document.addResultLayer(png, above: i, nameSuffix: "AI edit")
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
