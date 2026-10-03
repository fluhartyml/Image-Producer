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
import ImageIO
import os

/// Tool #11's inspector — a prompt box + Make/Restyle buttons that seed Apple's sheet.
struct ImagePlaygroundInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

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
    private var activeFilterable: ImageLayer? {
        guard let i = activeIndex, case .content = document.layers[i].role,
              !document.layers[i].elements.isEmpty else { return nil }
        return document.layers[i]
    }

    /// Why Filter is unavailable, said in terms of THIS document's layers.
    ///
    /// Michael, 2026-09-02: the old copy read "Restyle needs a content layer with art
    /// selected," which is accurate and still left him stuck — he had filled a layer,
    /// so as far as he was concerned there WAS art. His verdict on the experience was
    /// one word: "Intuitive."
    ///
    /// THE TRAP THIS NAMES. A document has a CONTENT layer called "Background" AND a
    /// pair of `.background`-role floor layers called Light and Dark. Filling Light or
    /// Dark with the paint bucket puts color on the floor, not art on a content layer —
    /// so the canvas goes black and Filter stays greyed out, with nothing on screen
    /// explaining the difference. A generic message cannot resolve that; only naming the
    /// selected layer and its actual role can.
    private var filterAvailabilityMessage: String {
        if activeFilterable != nil {
            return "New Layer = fresh layer · Restyle = redo the selected layer's art with your prompt."
        }
        guard let i = activeIndex else {
            return "New Layer drops the result on a fresh layer. Select a layer to use Restyle."
        }
        let layer = document.layers[i]
        switch layer.role {
        case .background(let role, _):
            let which = role == .light ? "Light" : "Dark"
            return """
            New Layer drops the result on a fresh layer. \
            “\(layer.name)” is the \(which) floor — a solid fill, not artwork — so there is \
            nothing for Restyle to redo. Select a content layer instead: Foreground, \
            Midground or Background.
            """
        case .content:
            return """
            New Layer drops the result on a fresh layer. \
            “\(layer.name)” is a content layer but has nothing on it yet. Filling the Light \
            or Dark floor does not count — Restyle needs art on THIS layer. Import an image \
            or draw something first, or use New Layer.
            """
        }
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
            VStack(alignment: .leading, spacing: 14) {
                Text("Describe what Image Playground should make:")
                    .font(.system(size: 18))

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

                Text(filterAvailabilityMessage)
                    .font(.system(size: 18)).foregroundStyle(.secondary)

                if failed {
                    Text("Couldn't place the generated image.")
                        .font(.system(size: 18)).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        let solo = ImageDocument(name: document.name, canvasWidth: document.canvasWidth,
                                canvasHeight: document.canvasHeight,
                                layers: [layer], palette: document.palette, cropRect: nil)
        let renderer = ImageRenderer(content: ImageCompositeView(document: solo, size: document.canvasPixelSize))
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
        guard let png = loadPNG(from: url) else {
            failed = true
            document.say("Image Playground result could not be placed", kind: .warning)
            return
        }
        failed = false
        // NAME THE LAYER FOR WHAT IT WAS TASKED WITH DRAWING. Michael, 2026-10-03: the
        // sheet said "illuminated B" and the layer came out "AI Image", because our own
        // prompt box was empty — he had typed in Apple's sheet instead. The sheet returns
        // only a file URL, never its text, so the file's own metadata is the one place
        // the sheet's prompt could survive. Read it first; our box is the fallback.
        let drawn = promptFromSheetFile(url) ?? prompt
        document.say("Image Playground — placed a new layer", kind: .edit)

        // SELECTING AN EMPTY LAYER IS AN INSTRUCTION. Michael, 2026-08-22, while
        // building the Shell Citadel icon: he selected "Background", asked Image
        // Playground for art, and got a fourth layer on top of his
        // Foreground/Midground/Background stack instead. Choosing an empty slot means
        // "put it HERE", and the app should read it that way.
        //
        // It still creates a NEW layer rather than writing into the selected one —
        // his call, and the right one: the empty layer survives untouched, so this
        // stays non-destructive and undo has something to fall back to. The name
        // carries the slot so it is obvious which one it fills.
        if let i = activeIndex,
           case .content = document.layers[i].role,
           document.layers[i].elements.isEmpty {
            var layer = ImageLayer(name: slotLayerName(slot: document.layers[i].name, drawn: drawn), role: .content)
            layer.setImage(png)
            layer.transform = document.coveringTransform(forPNG: png)
            document.layers.insert(layer, at: i + 1)   // directly above the empty slot
            return
        }

        var layer = ImageLayer(name: layerName(from: drawn), role: .content)
        layer.setImage(png)
        layer.transform = document.coveringTransform(forPNG: png)
        document.layers.append(layer)   // end of array = top of the visual stack
    }

    /// "Background · a teal safe" — the slot it fills, then what made it.
    private func slotLayerName(slot: String, drawn: String) -> String {
        let t = drawn.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "\(slot) · SI" : "\(slot) · \(String(t.prefix(18)))"
    }

    /// Filter result -> NON-DESTRUCTIVE: the AI edit lands on a new layer above the
    /// source, and the original is hidden (kept), not overwritten — there's no undo.
    private func replaceActiveLayer(from url: URL) {
        guard let png = loadPNG(from: url), let i = activeIndex,
              case .content = document.layers[i].role else {
            failed = true
            document.say("Image Playground result could not be placed", kind: .warning)
            return
        }
        document.say("Image Playground — restyled \(document.layers[i].name) onto a new layer", kind: .edit)
        failed = false

        // A RESTYLE MUST NOT MOVE THE ART. The result inherits the source layer's
        // placement — scale, centre, rotation — so the only thing that changes is how
        // the art looks. Only `contentAspect` is re-read, from the returned pixels,
        // because Image Playground does not promise to hand back the source's shape.
        //
        // Michael, 2026-08-23: "i used filter-> edit current layer and it didnt fill the
        // whole canvas with the filter." Without this the result took the DEFAULT
        // transform — scale 1.0, which means the canvas's SHORT edge — so on his
        // 1024×512 banner it drew at half the width no matter where the source sat.
        // THE ONE EXCEPTION: a layer still sitting at the untouched default is not a
        // placement decision, it is the ABSENCE of one — and on a non-square canvas that
        // default is the half-size bug itself. Restyling such a layer would inherit the
        // fault and reproduce exactly what he reported. So an unplaced source gets the
        // covering transform; a source he has actually moved or scaled is left alone.
        var t = document.layers[i].transform
        if t.isUntouchedDefault {
            t = document.coveringTransform(forPNG: png)
        } else {
            t.contentAspect = ImageDocument.pixelAspect(ofPNG: png) ?? t.contentAspect
        }
        document.addResultLayer(png, above: i, nameSuffix: "SI edit", transform: t)
    }

    /// The sheet hands back a file URL to the generated image (not necessarily PNG);
    /// normalize to PNG bytes for the layer model.
    private func loadPNG(from url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return pngData(fromImageData: raw)
    }

    /// Auto-name a new layer from its prompt (content names the layer).
    /// "SI", not "AI" — Michael, 2026-10-03: "it has officially been renmed super
    /// intellegence and is no longer called artificial intellegence."
    private func layerName(from prompt: String) -> String {
        let t = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "SI Image" : String(t.prefix(24))
    }

    // MARK: - Diagnostic: does the sheet's file carry its prompt?

    private static let diagLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ImageProducer",
                                        category: "PlaygroundDiag")

    /// DIAGNOSTIC (2026-10-03). Dumps every string in the returned file's metadata to
    /// the system log (category `PlaygroundDiag`) and reports the verdict on the status
    /// bar, then returns the prompt if one of the caption/description/title fields
    /// holds it. Remove the dump once the answer is known; keep the lookup if it works.
    private func promptFromSheetFile(_ url: URL) -> String? {
        let log = Self.diagLog
        log.notice("file name: \(url.lastPathComponent, privacy: .public)")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            log.notice("could not open the file as an image")
            document.say("Diagnostic: could not read the file's metadata", kind: .warning)
            return nil
        }
        log.notice("type: \((CGImageSourceGetType(src) as String?) ?? "?", privacy: .public)")

        var found: [(String, String)] = []
        func walk(_ value: Any, _ path: String) {
            if let d = value as? [String: Any] {
                for (k, v) in d { walk(v, path.isEmpty ? k : "\(path).\(k)") }
            } else if let a = value as? [Any] {
                for (n, v) in a.enumerated() { walk(v, "\(path)[\(n)]") }
            } else if let str = value as? String {
                found.append((path, str))
            }
        }
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            walk(props, "")
        }
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
           let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] {
            for tag in tags {
                let name = (CGImageMetadataTagCopyName(tag) as String?) ?? "?"
                let prefix = (CGImageMetadataTagCopyPrefix(tag) as String?) ?? "?"
                if let v = CGImageMetadataTagCopyValue(tag) { walk(v, "XMP \(prefix):\(name)") }
            }
        }
        for (path, value) in found {
            log.notice("\(path, privacy: .public) = \(value, privacy: .public)")
        }

        // Fields a prompt would plausibly live in, best first.
        let wanted = ["caption", "description", "title", "objectname", "usercomment", "comment", "subject"]
        let hit = wanted.lazy.compactMap { key in
            found.first { $0.0.lowercased().contains(key) && !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
        }.first

        if let hit {
            document.say("Diagnostic: prompt found in \(hit.0) — \"\(hit.1)\"", kind: .edit)
            return hit.1
        }
        document.say("Diagnostic: no prompt in the file (\(found.count) text fields) — name is \(url.lastPathComponent)", kind: .warning)
        return nil
    }
}
