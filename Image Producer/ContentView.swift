//
//  ContentView.swift
//  Icon Producer
//
//  Created by Michael Fluharty on 6/9/26.
//
//  Editor SHELL + tools coming live ONE AT A TIME (toolbox order). A brand-new
//  icon opens with three BLANK layers (Light Background, Dark Background, Icon),
//  so the canvas shows the transparency checkerboard until the user fills/draws.
//
//  LAYOUT (Michael 2026-06-11): adapts by geometry, not size class.
//   • PORTRAIT (taller than wide — iPhone AND iPad portrait):
//        canvas (top half) · TOOL STRIP · ACTIVE-TOOL NAME · SWIPE PANEL
//        (Tool inspector / Layers / History).
//   • LANDSCAPE / WIDE (Mac, iPad/iPhone landscape): the original side-by-side.
//
//  TOOL #1 — MOVE / TRANSFORM (live 2026-06-11): tap a layer row -> ACTIVE layer
//  (highlighted). With Move active, a bounding box shows on the canvas; drag to
//  move; the inspector has scale / rotation / center / reset. Acts on the WHOLE
//  layer's transform. (Scale/rotate handles + flip + per-element = follow-ups;
//  layers are still blank so you manipulate the frame, content follows later.)
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import ImageIO
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @ObservedObject var document: ImageDocument
    /// The open document's file on disk (from the DocumentGroup) — shown in the Canvas
    /// hub's Project/File section. nil while the document is untitled / not yet saved.
    var fileURL: URL? = nil
    @State private var activeTool: Tool = .move
    @State private var activeLayerID: ImageLayer.ID?
    @State private var bottomPanel: BottomPanel = .layers
    /// Paint Bucket's current colour (roadmap 2.1) — the user's own light/dark choice.
    @State private var fillColor: Color = .white
    /// Export (⌘E): the unified export sheet with a format dropdown.
    @State private var showExportSheet = false
    /// Result of an "Export ▸ Icon Set…" run. Always says what happened — a silent
    /// export is the same failure shape as the Done button that reported nothing.
    @State private var iconSetResult: String?
    /// Share (roadmap 2.5): a flat 1024 PNG of the visible layers, snapshot at tap.
    /// About / wordmark sheet — shows the "Image Producer / Graphic Arts" brand inside the app
    /// (the home-screen + App Store name can't carry the subheading).
    @State private var showAbout = false
    /// Shared pixel-pen state — the canvas draws into it; the Pen inspector configures it.
    @StateObject private var pen = PixelPen()
    /// Canvas zoom (×1…×8), driven by the on-canvas +/− buttons. scaleEffect-based
    /// (NOT a scroll view) so it can't refight the Auto Layout battle that parked
    /// pinch-zoom on 2026-06-11. Center-anchored; the named "canvas" coordinate
    /// space is defined INSIDE CanvasView, so pen/move hit-testing stays correct
    /// under the scale. Pan is a later step.
    @State private var canvasZoom: CGFloat = 1
    /// Focus mode: hide the tool strip + panel so the canvas fills the whole editor.
    @State private var canvasFocused = false
    /// Fit Width: fill the working area's WIDTH and scroll vertically for any overflow,
    /// re-fitting as the window resizes — without entering full-screen focus. Sticky
    /// toggle; turns itself off on manual zoom or on an incompatible tool (Michael
    /// 2026-06-23). Works for any canvas aspect (portrait scrolls, landscape just fills).
    @State private var fitWidth = false

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 8
    private let zoomStep: CGFloat = 1

    /// Production preview PiP visible? Shared with the Zoom inspector's toggle via
    /// AppStorage, so either surface can turn it on or off.
    @AppStorage("ip.pip.visible") private var showProductionPiP: Bool = true

    /// Zoom at the moment a pinch began, so the gesture scales from where you were
    /// rather than snapping to 1× on the first delta.
    @State private var zoomAtPinchStart: CGFloat?

    /// How far the zoomed canvas has been panned. Only meaningful above 1× — a canvas
    /// that fits its area has nowhere to go, so this resets whenever zoom returns to 1.
    @State private var canvasPan: CGSize = .zero
    @State private var panAtDragStart: CGSize = .zero

    /// What one double-click is worth. Michael, 2026-08-24: "you double click the canvas
    /// to zoom in +1.5x per double click".
    private let doubleClickZoomFactor: CGFloat = 1.5

    /// The ZOOM TOOL's own gestures — double-click to zoom in, drag to pan.
    ///
    /// Michael, 2026-08-24: "so maybe the pointer changes to a magnefying glass and you
    /// double click the canvas to zoom in +1.5x per double click and click and drag to
    /// pan". The magnifying-glass pointer already existed (ToolPointer); these did not.
    ///
    /// Only active while `.zoom` is the selected tool, so it can never steal a drag from
    /// the Pen or the Bucket. Navigation by GESTURE stays always-on and untouched — this
    /// is the tool-specific behaviour on top of it.
    ///
    /// At exactly 1× the pan resets: a canvas that fits its area has nowhere to be
    /// dragged to, and leaving a stale offset there would park the artwork off-centre
    /// with no way to tell why.
    private var zoomToolGestures: some Gesture {
        // ORDER MATTERS. A plain TapGesture still fires while modifiers are held, so the
        // most specific combination has to get first refusal — hence .exclusively(before:)
        // running shift+option, then option, then bare.
        let reset = TapGesture(count: 2).modifiers([.option, .shift])
            .onEnded { applyZoom(1) }
        let out = TapGesture(count: 2).modifiers(.option)
            .onEnded { applyZoom(canvasZoom / doubleClickZoomFactor) }
        let inward = TapGesture(count: 2)
            .onEnded { applyZoom(canvasZoom * doubleClickZoomFactor) }

        let pan = DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard canvasZoom > 1 else { return }          // nothing to pan at fit size
                canvasPan = CGSize(width: panAtDragStart.width + v.translation.width,
                                   height: panAtDragStart.height + v.translation.height)
            }
            .onEnded { _ in panAtDragStart = canvasPan }

        return SimultaneousGesture(pan, reset.exclusively(before: out).exclusively(before: inward))
    }

    /// Where the zoom was before the last "all the way out", so the toggle can put it
    /// back. Pan travels with it — returning to 3× with the artwork re-centred would
    /// lose your place, which is the whole thing the toggle exists to preserve.
    @State private var zoomBeforeToggle: CGFloat?
    @State private var panBeforeToggle: CGSize = .zero

    /// Double-tap the magnifying glass in the tool strip: zoom all the way out, or back
    /// to where you were.
    ///
    /// Michael, 2026-08-24: "how about double click or tap the magnefying tool it zooms
    /// all the way out or back in to the previous zoom".
    ///
    /// Better than Photoshop's equivalent, which jumps to 100% and FORGETS where you
    /// were. This remembers, which is what you actually want while working magnified:
    /// pop out to check the whole picture, pop back in and carry on at the same spot.
    ///
    /// Modifier-free by design — see feedback_sticky_keys_avoid_modifier_gestures.
    private func toggleZoomAllTheWayOut() {
        if canvasZoom > minZoom {
            zoomBeforeToggle = canvasZoom
            panBeforeToggle = canvasPan
            applyZoom(minZoom)
        } else if let z = zoomBeforeToggle {
            applyZoom(z)
            withAnimation(.easeOut(duration: 0.18)) {
                canvasPan = panBeforeToggle
                panAtDragStart = panBeforeToggle
            }
        }
    }

    /// Land on a zoom level from the Zoom tool's double-clicks.
    ///
    /// Michael, 2026-08-24: "yes add option click to zoom out by -1.5x per double clich
    /// or shift option click zooms to 1x".
    ///
    ///   double-click                -> × 1.5
    ///   option + double-click       -> ÷ 1.5
    ///   shift + option + double-click -> straight back to 1×
    ///
    /// Animated, unlike the pinch: a click is a discrete act and should be seen to
    /// happen, where a continuous gesture must not lag behind the fingers.
    private func applyZoom(_ z: CGFloat) {
        fitWidth = false
        withAnimation(.easeOut(duration: 0.18)) {
            canvasZoom = min(max(z, minZoom), maxZoom)
            if canvasZoom == 1 { canvasPan = .zero; panAtDragStart = .zero }
        }
    }

    /// Trackpad pinch — Michael, 2026-08-24: "the canvas doesnt pinch zoom on a mac".
    ///
    /// The +/− buttons worked, so zoom itself was fine; there was simply no gesture.
    /// `ZoomableCanvas` wraps the content in a UIScrollView on iOS and is a PASSTHROUGH
    /// on macOS — and macOS is PRIMARY for this app. So the Mac had buttons and nothing
    /// else, on a machine whose trackpad pinch every other graphics app understands.
    ///
    /// Deliberately NOT animated: setZoom() animates, which is right for a button press
    /// and wrong for a continuous gesture — it would lag behind the fingers.
    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomAtPinchStart ?? canvasZoom
                if zoomAtPinchStart == nil { zoomAtPinchStart = base }
                fitWidth = false                       // pinching leaves Fit Width, as +/− does
                canvasZoom = min(max(base * value.magnification, minZoom), maxZoom)
            }
            .onEnded { _ in zoomAtPinchStart = nil }
    }

    private func setZoom(_ z: CGFloat) {
        fitWidth = false                       // manual zoom leaves Fit Width
        withAnimation(.easeOut(duration: 0.15)) {
            canvasZoom = min(max(z, minZoom), maxZoom)
            if canvasZoom == 1 { canvasPan = .zero; panAtDragStart = .zero }
        }
    }

    /// True on iPhone (any orientation) — gates the phone-only layout so it never
    /// touches the iPad/Mac views. Size class can't decide this: an iPhone Pro Max in
    /// landscape reports `.regular` width, same as an iPad — so use the device idiom.
    #if os(iOS)
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    #else
    private var isPhone: Bool { false }
    #endif

    /// iPhone-only layout, isolated from iPad. Canvas gets the room; the tool box is a
    /// single scrollable line; Tool/Layers/History stay in the existing swipe panel.
    /// Portrait stacks it; landscape puts the canvas on the left, tools+panel on the right.
    @ViewBuilder
    private func phoneLayout(geo: GeometryProxy) -> some View {
        if geo.size.height > geo.size.width {
            VStack(spacing: 0) {
                // Canvas ~42% (was half): the inspector was starved for height. No
                // ActiveToolLabel here — the tool strip highlights the active tool and
                // the inspector names it, so a third label was redundant. Panel is
                // `compact` (no pills, swipe + dots) and takes the freed room.
                canvasArea
                    .frame(height: geo.size.height * 0.42)
                Divider()
                ToolStrip(activeTool: $activeTool, onDoubleTap: { if $0 == .zoom { toggleZoomAllTheWayOut() } }, lines: 1)
                Divider()
                BottomPanel.PanelView(document: document, activeTool: activeTool,
                                      activeLayerID: $activeLayerID, selection: $bottomPanel,
                                      fillColor: $fillColor, fileURL: fileURL, compact: true)
                    .frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 0) {
                canvasArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(spacing: 0) {
                    ToolStrip(activeTool: $activeTool, onDoubleTap: { if $0 == .zoom { toggleZoomAllTheWayOut() } }, lines: 1)
                    Divider()
                    BottomPanel.PanelView(document: document, activeTool: activeTool,
                                          activeLayerID: $activeLayerID, selection: $bottomPanel,
                                          fillColor: $fillColor, fileURL: fileURL, compact: true)
                }
                .frame(width: 300)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            if canvasFocused {
                // Full-screen focus: canvas only, tools/panel hidden. The on-canvas
                // control cluster carries the toggle back out + the zoom buttons.
                canvasArea
            } else if isPhone {
                phoneLayout(geo: geo)
            } else if geo.size.height > geo.size.width {
                // Portrait: canvas top half, then tool strip + swipe panel.
                VStack(spacing: 0) {
                    canvasArea
                        .frame(height: geo.size.height / 2)
                    Divider()
                    ToolStrip(activeTool: $activeTool, onDoubleTap: { if $0 == .zoom { toggleZoomAllTheWayOut() } })
                    ActiveToolLabel(tool: activeTool)
                    Divider()
                    BottomPanel.PanelView(document: document,
                                          activeTool: activeTool,
                                          activeLayerID: $activeLayerID,
                                          selection: $bottomPanel,
                                          fillColor: $fillColor,
                                          fileURL: fileURL)
                }
            } else {
                // Landscape / wide: canvas | tool rail | inspector | layers — all
                // visible at once, using the gap the square canvas leaves to the
                // right (Michael 2026-06-11: iPad is landscape-locked in a Magic
                // Keyboard, so landscape needs full tooling, not the bare layout).
                HStack(spacing: 0) {
                    canvasArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ToolRail(activeTool: $activeTool, onDoubleTap: { if $0 == .zoom { toggleZoomAllTheWayOut() } })
                    Divider()
                    ToolInspector(document: document,
                                  activeTool: activeTool,
                                  activeLayerID: activeLayerID,
                                  fillColor: $fillColor,
                                  fileURL: fileURL)
                        .frame(width: 300)
                    Divider()
                    // Right column: Layers with History "behind" it (spec: undo is the History
                    // panel sitting behind the layer list). The wide/Mac layout used to hardcode
                    // only LayerPanel, so History was unreachable on Mac — this restores it.
                    LayersHistoryColumn(document: document, activeLayerID: $activeLayerID)
                        .frame(width: 320)
                }
            }
        }
        // A NEW project lands on the Canvas hub so the user immediately sees where to name
        // the project and set the canvas size; opened EXISTING files keep the Move tool.
        // New projects are real files now, so match the just-created URL (by name) too.
        .onAppear {
            if fileURL == nil
                || fileURL?.lastPathComponent == ImageDocument.pendingNewProjectURL?.lastPathComponent {
                activeTool = .canvas
                ImageDocument.pendingNewProjectURL = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showExportSheet = true } label: {
                    Label("Export", systemImage: "arrow.up.doc")
                }
                .help("Export the project to a file (⌘E) — pick the format")
            }
            ToolbarItem(placement: .secondaryAction) {
                // Native ShareLink (replaces the old render→custom-sheet path that came
                // up empty). Shares a flat PNG of the visible layers (crop-trimmed).
                ShareLink(item: shareItem, preview: SharePreview(exportFilename)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share a flat PNG of the visible layers")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showAbout = true } label: {
                    Label("About Image Producer", systemImage: "info.circle")
                }
                .help("About Image Producer — Graphic Arts")
            }
        }
        .sheet(isPresented: $showExportSheet) { ExportSheet(document: document) }
        .alert("Icon Set", isPresented: Binding(get: { iconSetResult != nil },
                                                set: { if !$0 { iconSetResult = nil } })) {
            Button("OK", role: .cancel) { iconSetResult = nil }
        } message: {
            Text(iconSetResult ?? "").font(.system(size: 18))
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .environmentObject(pen)
        #if os(macOS)
        // File > Export… (⌘E) opens the SAME unified export sheet as the toolbar button,
        // targeting the focused document.
        .focusedSceneValue(\.exportAction, { showExportSheet = true })
        // The top-level Export menu's "Icon Set…" item, targeting this document.
        .focusedSceneValue(\.iconSetAction, { exportIconSet() })
        #endif
    }

    /// Export ▸ Icon Set… — renders the light and dark 1024s from this document's own
    /// Light and Dark floors plus the Mac ladder, and writes a drop-in
    /// `AppIcon.appiconset`. An empty result string means the user cancelled the
    /// panel, which is not worth an alert.
    private func exportIconSet() {
        let message = IconSetExport.exportInteractively(from: document)
        if !message.isEmpty { iconSetResult = message }
    }

    private var exportFilename: String {
        let base = document.name.trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Untitled" : base
    }

    /// On-demand flat PNG of the visible layers (crop-trimmed) for the native ShareLink.
    private var shareItem: ImageShare {
        ImageShare(pngData: ContentView.renderIconPNG(document: document, px: 1024) ?? Data(),
                  filename: exportFilename)
    }

    /// Pixel sizes still used by the Canvas hub's Web-folder export.
    static let exportPixelSizes: [Int] =
        [16, 20, 29, 32, 40, 58, 60, 64, 76, 80, 87, 120, 128, 152, 167, 180, 256, 512, 1024]

    /// Flatten the visible layers to a px×px PNG (1024 master; PNG per 2.5.1).
    @MainActor static func renderIconPNG(document: ImageDocument, px: Int) -> Data? {
        let renderer = ImageRenderer(content: ImageCompositeView(document: document, size: CGSize(width: px, height: px)))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        // Non-destructive crop: render the full square, then trim the CGImage to the
        // normalized crop rect (origin top-left, matching the canvas convention). A
        // non-square crop yields a rectangular PNG; nil = full square as before.
        // Trim to the mask. `clip` crops to the mask's bounding box AND makes everything
        // outside the silhouette transparent — so a star mask exports a star, not the
        // rectangle around one. A plain rectangular mask comes out exactly as before.
        if let mask = document.cropMask, let cut = mask.clip(cg) {
            return pngData(from: cut)
        }
        return pngData(from: cg)
    }

    private var canvasArea: some View {
        // Zoom REVIVED 2026-06-18 as a scaleEffect driven by the on-canvas +/−
        // buttons (the ZoomableCanvas/UIScrollView pinch approach stays parked —
        // it fought Auto Layout). scaleEffect is a render transform: layout size
        // is unchanged, so it doesn't refight that battle, and the "canvas" named
        // coordinate space lives inside CanvasView so pen/move math is unaffected.
        // Pan is the next step (center-anchored for now).
        Group {
            if fitWidth {
                // Fit Width: frame the canvas to the area's WIDTH at its true aspect (any
                // shape — B2 removed the square constraint), inside a vertical ScrollView so
                // a taller-than-area canvas (portrait) scrolls; a landscape one just fills
                // the width. Re-fits automatically as the window/area is resized.
                GeometryReader { geo in
                    let aspect = CGFloat(document.canvasWidth) / CGFloat(max(1, document.canvasHeight))
                    let fittedHeight = geo.size.width / max(aspect, 0.0001)
                    ScrollView(.vertical) {
                        CanvasView(document: document,
                                   activeLayerID: $activeLayerID,
                                   showTransformBox: activeTool == .move,
                                   activeTool: activeTool,
                                   fillColor: $fillColor,
                                   fillFrame: true)
                            .frame(width: geo.size.width, height: fittedHeight)
                    }
                }
            } else {
                CanvasView(document: document,
                           activeLayerID: $activeLayerID,
                           showTransformBox: activeTool == .move,
                           activeTool: activeTool,
                           fillColor: $fillColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(canvasZoom)
                    .offset(canvasPan)
                    .gesture(pinchZoom)
                    .gesture(activeTool == .zoom ? zoomToolGestures : nil)
            }
        }
        .padding()
        .background(Color(white: 0.5).opacity(0.12))
        .clipped()                                   // zoomed canvas stays inside its area
        // The production preview floats over the canvas AREA — deliberately OUTSIDE the
        // .scaleEffect / .offset applied above.
        //
        // BUG THIS FIXES, found by Michael 2026-08-24: "one bug the PiP moves with the
        // pan". It had been placed inside the canvas ZStack, so it was scaled AND panned
        // with the artwork and ended up hanging half off the bottom edge — which also
        // made the panel's own caption a lie ("The preview never follows the canvas
        // zoom"). It was following both.
        //
        // It belongs to the WINDOW, not to the picture. Same reason it snaps to the
        // corners of the canvas area rather than to the artwork.
        .overlay {
            if showProductionPiP {
                GeometryReader { g in ProductionPiP(document: document, bounds: g.size) }
            }
        }
        .overlay(alignment: .bottomTrailing) { canvasControls }
        // Safeguard: if a tool is marked incompatible with Fit Width, picking it drops
        // back to the normal fitted view so the tool can't break (Michael 2026-06-23).
        .onChange(of: activeTool) { _, newTool in
            if fitWidth && !newTool.fitWidthCompatible { fitWidth = false }
        }
    }

    /// Floating control cluster on the canvas: full-screen toggle + zoom +/−.
    /// Always reachable — including in focus mode, which is the only way back out.
    private var canvasControls: some View {
        VStack(spacing: 6) {
            Button { canvasFocused.toggle() } label: {
                Image(systemName: canvasFocused
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .help(canvasFocused ? "Exit full screen" : "Full-screen canvas")
            .accessibilityLabel(canvasFocused ? "Exit full screen" : "Full-screen canvas")

            Divider().frame(width: 26)

            // Fit Width: fill the area width + scroll vertically, within the resizable
            // window (NOT full-screen). Sticky toggle; tinted when on.
            Button { fitWidth.toggle() } label: { Image(systemName: "arrow.left.and.right") }
                .help(fitWidth ? "Fit width: on (tap to turn off)"
                               : "Fit width — fill the width, scroll vertically")
                .accessibilityLabel("Fit width")
                .foregroundStyle(fitWidth ? Color.accentColor : Color.primary)

            Divider().frame(width: 26)

            Button { setZoom(canvasZoom + zoomStep) } label: { Image(systemName: "plus") }
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
                .disabled(canvasZoom >= maxZoom)
            Button { setZoom(1) } label: {
                Text("\(Int(canvasZoom * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .help("Reset zoom to 100%")
            .accessibilityLabel("Reset zoom to 100 percent")
            Button { setZoom(canvasZoom - zoomStep) } label: { Image(systemName: "minus") }
                .help("Zoom out")
                .accessibilityLabel("Zoom out")
                .disabled(canvasZoom <= minZoom)
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .frame(width: 30)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
        .padding(12)
    }
}

// MARK: - Tool strip

/// The always-visible toolbox: a horizontal row of tool icons that scrolls when
/// there are more tools than fit. Tapping a tool makes it the active tool.
struct ToolStrip: View {
    @Binding var activeTool: Tool
    /// Double-tap on a tool's own button. Zoom uses it to toggle all-the-way-out and
    /// back — Michael 2026-08-24. Optional so callers that do not care can omit it.
    var onDoubleTap: ((Tool) -> Void)? = nil
    /// Rows of tools: 2 on iPad (the default), 1 on iPhone (a single scrollable line).
    var lines: Int = 2

    private var rows: [GridItem] {
        Array(repeating: GridItem(.fixed(44), spacing: 4), count: lines)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 4) {
                ForEach(Tool.shipping) { tool in
                    Button { activeTool = tool } label: {
                        ToolGlyph(tool: tool)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(activeTool == tool ? Color.accentColor.opacity(0.2)
                                                             : Color.clear)
                            )
                            .foregroundStyle(activeTool == tool ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    // simultaneous, not .onTapGesture — a Button already owns the tap,
                    // and replacing it would stop single-click tool selection working.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap?(tool) })
                    .help(tool.title)                 // tooltip on Mac / iPad pointer
                    .accessibilityLabel(tool.title)   // VoiceOver everywhere
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

/// Shows the ACTIVE tool's name on screen — the touch/iPhone substitute for a
/// hover tooltip. Updates the instant a tool is tapped, on every platform, so
/// the less-obvious glyphs are never a guess.
struct ActiveToolLabel: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tool.systemImage)
            Text(tool.title).fontWeight(.medium)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color(white: 0.5).opacity(0.10))
    }
}

// MARK: - Tool rail (landscape)

/// Vertical version of the tool strip for the wide/landscape layout — sits in the
/// gap the square canvas leaves, hugging the canvas's right edge. Scrolls
/// vertically when there are more tools than fit.
struct ToolRail: View {
    @Binding var activeTool: Tool
    /// Double-tap on a tool's own button. Zoom uses it to toggle all-the-way-out and
    /// back — Michael 2026-08-24. Optional so callers that do not care can omit it.
    var onDoubleTap: ((Tool) -> Void)? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.fixed(44), spacing: 4), GridItem(.fixed(44), spacing: 4)], spacing: 4) {
                ForEach(Tool.shipping) { tool in
                    Button { activeTool = tool } label: {
                        ToolGlyph(tool: tool)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(activeTool == tool ? Color.accentColor.opacity(0.2)
                                                             : Color.clear)
                            )
                            .foregroundStyle(activeTool == tool ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    // simultaneous, not .onTapGesture — a Button already owns the tap,
                    // and replacing it would stop single-click tool selection working.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap?(tool) })
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .frame(width: 104)
    }
}

// MARK: - Tool inspector (shared)

/// The active tool's inspector — Move's controls, or a placeholder for tools not
/// built yet. Reused by BOTH the portrait swipe panel and the landscape column.
struct ToolInspector: View {
    @ObservedObject var document: ImageDocument
    let activeTool: Tool
    let activeLayerID: ImageLayer.ID?
    @Binding var fillColor: Color
    /// Open document's file on disk — for the Canvas hub's Project/File section.
    var fileURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool-name header: the inspector names the active tool, so you never
            // need hover to know which tool you're on (Michael 2026-06-11).
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: activeTool.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeTool.title).font(.system(size: 20, weight: .semibold))
                    // "Duplicate with a purpose" (Michael 2026-06-11): the active
                    // layer is also highlighted in the list, but spelling it out
                    // here CONFIRMS which layer you're about to act on.
                    if let name = activeLayerName {
                        Text("Layer: \(name)")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            // Every tool inspector scrolls if its content is taller than the panel
            // (Michael 2026-06-22). Individual inspectors must NOT add their own ScrollView.
            ScrollView { content }
        }
    }

    private var activeLayerName: String? {
        guard let id = activeLayerID else { return nil }
        return document.layers.first(where: { $0.id == id })?.name
    }

    @ViewBuilder
    private var content: some View {
        switch activeTool {
        case .canvas:
            CanvasInspector(document: document, fileURL: fileURL)
        case .colorPalette:
            ColorPaletteInspector(document: document, fillColor: $fillColor)
        case .move:
            MoveTransformInspector(document: document, activeLayerID: activeLayerID)
        case .mask:
            MaskInspector(document: document)
        case .fill:
            PaintBucketInspector(document: document,
                                 activeLayerID: activeLayerID,
                                 fillColor: $fillColor)
        case .symbol:
            SymbolPickerInspector(document: document, activeLayerID: activeLayerID)
        case .text:
            FontPickerInspector(document: document, activeLayerID: activeLayerID)
        case .image:
            ImageImportInspector(document: document, activeLayerID: activeLayerID)
        case .imagePlayground:
            ImagePlaygroundInspector(document: document, activeLayerID: activeLayerID)
        case .cutout:
            RemoveBackgroundInspector(document: document, activeLayerID: activeLayerID)
        case .magicLasso:
            MagicLassoInspector(document: document, activeLayerID: activeLayerID)
        case .eyedropper:
            EyedropperInspector(fillColor: $fillColor)
        case .eraser:
            EraserInspector(document: document, activeLayerID: activeLayerID, fillColor: $fillColor)
        case .pen:
            PenInspector(document: document, activeLayerID: activeLayerID)
        case .zoom:
            // R2 (resolved 2026-06-10): the live production thumbnail that does
            // NOT follow the canvas zoom. See FatBits.swift.
            ZoomInspector(document: document)
        default:
            ToolInspectorPlaceholder(tool: activeTool)
        }
    }
}

// MARK: - Paint Bucket inspector (Tool #2)

/// Paint Bucket v1 (roadmap 2.1): pick a colour, then tap a BACKGROUND layer's
/// canvas to fill it — the user makes their own Light and Dark backgrounds. The
/// "Fill" button applies without a canvas tap (and works on Mac / for VoiceOver).
struct PaintBucketInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?
    @Binding var fillColor: Color
    /// Flood tolerance lives on the pen so the canvas can draw the live region preview.
    @EnvironmentObject var pen: PixelPen

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    private var activeIsBackground: Bool {
        guard let i = activeIndex else { return false }
        return document.layers[i].backgroundRole != nil
    }

    private var activeHasImage: Bool {
        guard let i = activeIndex else { return false }
        for el in document.layers[i].elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { return true }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaletteSwatchRow(document: document, color: $fillColor, label: "Fill color (from palette)")

            // Fill Layer is ALWAYS available. It used to vanish the moment a layer had
            // any art, which trapped Michael: he filled a blank layer, the panel flipped
            // to flood-fill only, and the button he had just used was gone.
            Button {
                fillActiveLayer()
            } label: {
                Label("Fill Layer", systemImage: "drop.fill")
            }
            .buttonStyle(.borderedProminent)
            Text("Fills the whole layer, edge to edge.")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            if activeHasImage {
                Divider()
                Text("Flood fill — pour color up to the lines").font(.system(size: 18)).bold()
                Text("Hover to preview the region (shown in the fill color), then tap inside an outlined area to flood it up to the surrounding lines. Tolerance sets how strict those \"walls\" are. Fills onto a new layer — your original is kept.")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tolerance  \(Int(pen.bucketTolerance))").font(.system(size: 18))
                    Slider(value: $pen.bucketTolerance, in: 0...160, step: 1)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// A CONTENT layer with nothing on it. It could take a whole-layer fill all along;
    /// there was simply no branch for it.
    private var activeIsEmptyContent: Bool {
        guard let i = activeIndex else { return false }
        guard case .content = document.layers[i].role else { return false }
        return document.layers[i].elements.isEmpty
    }

    /// Whole-layer fill for EITHER a background layer or an empty content layer.
    ///
    /// Michael, 2026-08-22: "should not be constrained to light or dark layer only."
    /// The Paint Bucket had two branches — whole-fill for Light/Dark, flood-fill for a
    /// content layer with art — and an empty content layer fell between them, showing
    /// a message and no button. Filling a blank layer with a flat colour is an ordinary
    /// thing to want, and the constraint was arbitrary.
    private func fillActiveLayer() {
        guard let i = activeIndex else { return }
        document.captureHistoryBaselineIfNeeded()

        guard document.fillLayerSolid(at: i, cgColor: fillColor.cgColorResolved) else { return }
        document.recordHistory(toolID: Tool.fill.rawValue, groupTitle: Tool.fill.title,
                               actionLabel: activeIsBackground ? "Fill Background" : "Fill Layer",
                               layerID: document.layers[i].id)
    }

}

/// Units for the Canvas hub's dimensions / print-size readouts.
enum CanvasUnit: String, CaseIterable, Identifiable {
    case px, inch, mm, pt
    var id: String { rawValue }
    var label: String {
        switch self {
        case .px:   "px"
        case .inch: "in"
        case .mm:   "mm"
        case .pt:   "pt"
        }
    }
    /// A length given in INCHES, expressed in this unit. (px path is read-only elsewhere.)
    func fromInches(_ inches: Double) -> Double {
        switch self {
        case .px, .inch: inches
        case .mm:        inches * 25.4
        case .pt:        inches * 72
        }
    }
    /// A length given in THIS unit, expressed in inches.
    func toInches(_ value: Double) -> Double {
        switch self {
        case .px, .inch: value
        case .mm:        value / 25.4
        case .pt:        value / 72
        }
    }
}

/// A standard canvas size preset (stored short × long inches; orientation applied on use).
struct CanvasSizePreset: Identifiable {
    var id: String { label }
    let label: String
    let shortIn: Double
    let longIn: Double
    /// The conventional orientation when this preset is applied (business cards / envelopes
    /// are landscape by convention; most else portrait). The live Landscape toggle flips it.
    var defaultLandscape = false
}

/// A canvas preset defined by ASPECT RATIO, keeping the resolution already set.
///
/// **Michael, 2026-08-25, correcting the first version of this:** *"i think for the
/// youtube thumbnail the important is the aspect ratio over the pixel density because
/// youtube will reformat after upload, it just needs the aspect so it has minimum
/// cutoff."* He is right — YouTube re-encodes and generates its own sizes, so the pixel
/// count is not what survives. **The aspect is what stops it letterboxing or cropping
/// him**, and the pixel count only matters at the boundaries: their 640 × 360 minimum
/// and the 2 MB file cap.
///
/// So this keeps the canvas's LONG EDGE and sets the other side to match the ratio.
/// Whatever resolution he has chosen is respected; only the shape changes.
struct CanvasAspectPreset: Identifiable {
    var id: String { label }
    let label: String
    let ratioW: Int
    let ratioH: Int
    /// Smallest long edge the target will accept, if it has one — used to warn, never to
    /// silently resize. 0 = no stated minimum.
    var minLongEdge: Int = 0
}

/// A canvas preset defined in PIXELS rather than inches.
///
/// ⚠️ SEPARATE FROM `CanvasSizePreset` ON PURPOSE, and the distinction is not cosmetic.
/// An inch preset computes `pixels = physical × PPI`, which is right for anything that
/// gets printed. A screen target is specified in pixels and has no physical size at all —
/// a YouTube thumbnail is 1280 × 720 whatever the PPI happens to be. Run it through the
/// inch path at the 300 PPI the inspector recommends for print and you would get
/// 5333 × 3000, which is not a thumbnail.
///
/// So these set the pixel count directly and leave PPI untouched.
struct CanvasPixelPreset: Identifiable {
    var id: String { label }
    let label: String
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - Canvas inspector (Tool: Canvas — the open project's central hub)

/// The Canvas tool is the CENTRAL HUB for the open project. SLICE A (2026-06-22):
/// Project / File — rename, disk location, type, last saved, size, save state. Later
/// slices add B Dimensions/Resolution, C Print setup, D Export (see DeveloperNotes).
struct CanvasInspector: View {
    @ObservedObject var document: ImageDocument
    var fileURL: URL?

    @State private var draftName = ""
    @State private var renameError = false
    /// Set when an aspect preset leaves the canvas below a target's stated minimum.
    @State private var aspectWarning: String?
    // Export (sections C/D)
    @State private var exportData = Data()
    @State private var exportType: UTType = .pdf
    @State private var exportFilename = "Export"
    @State private var showDataExporter = false
    @State private var webBundle = ImageExportBundle(files: [:])
    @State private var showWebExporter = false
    @State private var folderFilename = "Export"
    // Layer PDF (one page per layer) + inverse import
    @State private var flattenLayerPDF = false
    @State private var layerMatte: Color = .white
    @State private var importingPDF = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // --- Project name ---
            VStack(alignment: .leading, spacing: 6) {
                Text("Project name").font(.system(size: 18)).foregroundStyle(.secondary)
                if fileURL == nil {
                    // Untitled: editable working name (becomes the manifest name on first save).
                    TextField("Project name", text: $draftName)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18))
                        .onSubmit { commitName() }
                    Text("Working name for this untitled project.")
                        .font(.system(size: 18)).foregroundStyle(.primary)
                } else {
                    // Saved: editing here renames the FILE on disk (one-stop — no trip to Finder).
                    TextField("Project name", text: $draftName)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18))
                        .onSubmit { renameFile() }
                    Text("Renames the file on disk. Press Return to apply.")
                        .font(.system(size: 18)).foregroundStyle(.primary)
                    if renameError {
                        Text("Couldn't rename — a file with that name may already exist.")
                            .font(.system(size: 18)).foregroundStyle(.red)
                    }
                }
            }

            Divider()

            // --- B · Dimensions & Resolution ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Dimensions & Resolution").font(.system(size: 20, weight: .semibold))

                // Pixels — editable W × H. This is the explicit pixel-count change; existing
                // art scales-to-fit the new shape, letterboxed on the background.
                HStack(spacing: 6) {
                    Text("Pixels").font(.system(size: 18)).frame(width: 92, alignment: .leading)
                    TextField("W", value: $document.canvasWidth, format: .number)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 64)
                    Text("×").font(.system(size: 18))
                    TextField("H", value: $document.canvasHeight, format: .number)
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 64)
                    Text("px").font(.system(size: 18)).foregroundStyle(.secondary)
                }

                Picker("Units", selection: $unitRaw) {
                    ForEach(CanvasUnit.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Resolution: manual field + a preset menu for when you don't know the number.
                HStack(spacing: 8) {
                    Text("Resolution").font(.system(size: 18)).frame(width: 92, alignment: .leading)
                    TextField("PPI", value: $document.ppi, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 76)
                        .onSubmit { if document.ppi < 1 { document.ppi = 1 } }
                    Text("PPI").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Menu("Common resolutions") {
                    Button("72 — Screen / web")                  { document.ppi = 72 }
                    Button("150 — Draft print")                  { document.ppi = 150 }
                    Button("300 — Standard print / photo labs")  { document.ppi = 300 }
                    Button("360 — Epson photo inkjet")           { document.ppi = 360 }
                    Button("600 — Fine art / line art")          { document.ppi = 600 }
                }
                .font(.system(size: 18)).fixedSize()

                // Print size — derived readout (W × H) from pixels ÷ PPI.
                attrRow("Print size", printSizeText)

                // Standard non-square shapes. A preset sets pixels = physical × current PPI.
                Toggle("Landscape", isOn: landscapeBinding).font(.system(size: 18)).fixedSize()
                Menu("Canvas size presets") {
                    Section("Photo")          { presetButtons(Self.photoPresets) }
                    Section("Paper")          { presetButtons(Self.paperPresets) }
                    Section("Index card")     { presetButtons(Self.indexPresets) }
                    Section("Business card")  { presetButtons(Self.businessPresets) }
                    Section("Envelope")       { presetButtons(Self.envelopePresets) }
                    Section("Screen") {
                        aspectPresetButtons(Self.screenAspectPresets)
                        pixelPresetButtons(Self.screenPresets)
                    }
                }
                .font(.system(size: 18)).fixedSize()

                if let aspectWarning {
                    Text(aspectWarning)
                        .font(.system(size: 18)).foregroundStyle(.orange)
                }

                Text("Resolution (PPI) changes the print size losslessly — pixels stay. Editing Pixels or applying a size preset changes the pixel count; existing art scales to fit, letterboxed on the background. Set Resolution first (300 for print), then pick a size.")
                    .font(.system(size: 18)).foregroundStyle(.primary)
            }

            Divider()

            // --- File attributes ---
            VStack(alignment: .leading, spacing: 8) {
                Text("File").font(.system(size: 20, weight: .semibold))
                attrRow("Location", locationText)
                #if os(macOS)
                if let url = fileURL {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Label("Reveal in Finder", systemImage: "folder").font(.system(size: 18))
                    }
                    .buttonStyle(.bordered)
                }
                #endif
                attrRow("Type", typeText)
                attrRow("Last saved", savedText)
                attrRow("Size", sizeText)
                attrRow("State", stateText)
            }

            Divider()

            // --- C · Print setup ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Print setup").font(.system(size: 20, weight: .semibold))
                HStack(spacing: 8) {
                    Text("Bleed").font(.system(size: 18)).frame(width: 92, alignment: .leading)
                    TextField("in", value: $document.bleedInches, format: .number.precision(.fractionLength(0...3)))
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 64)
                    Text("in").font(.system(size: 18)).foregroundStyle(.secondary)
                    Menu {
                        Button("None") { document.bleedInches = 0 }
                        Button("0.125 in (1/8\")") { document.bleedInches = 0.125 }
                        Button("3 mm") { document.bleedInches = 3.0 / 25.4 }
                    } label: { Image(systemName: "chevron.down.circle").font(.system(size: 18)) }
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    Text("Safe margin").font(.system(size: 18)).frame(width: 92, alignment: .leading)
                    TextField("in", value: $document.safeMarginInches, format: .number.precision(.fractionLength(0...3)))
                        .textFieldStyle(.roundedBorder).font(.system(size: 18)).frame(width: 64)
                    Text("in").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Toggle("Crop / trim marks", isOn: $document.cropMarks).font(.system(size: 18))
                Toggle("Registration marks", isOn: $document.registrationMarks).font(.system(size: 18))
                HStack(spacing: 8) {
                    Text("Color").font(.system(size: 18)).frame(width: 92, alignment: .leading)
                    Picker("Color", selection: $document.colorSpaceCMYK) {
                        Text("RGB").tag(false); Text("CMYK").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if document.colorSpaceCMYK {
                    Text("CMYK is saved on the project; the PDF currently exports RGB (a true ICC RGB→CMYK conversion is a later step).")
                        .font(.system(size: 18)).foregroundStyle(.primary)
                }
            }

            Divider()

            // --- D · Export ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Export").font(.system(size: 20, weight: .semibold))
                Button {
                    if let data = makePrintPDF(document) {
                        exportData = data; exportType = .pdf
                        exportFilename = displayName; showDataExporter = true
                    }
                } label: { Label("Print PDF (bleed + marks)", systemImage: "doc.richtext").font(.system(size: 18)).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                Button {
                    webBundle = ImageExportBundle(files: makeWebFolder(document, baseName: displayName))
                    folderFilename = "\(displayName) Web"; showWebExporter = true
                } label: { Label("Web folder (PNG @1x/2x/3x)", systemImage: "globe").font(.system(size: 18)).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                Button {
                    webBundle = ImageExportBundle(files: makeIconFolder(document))
                    folderFilename = "\(displayName) Icons"; showWebExporter = true
                } label: { Label("Icon — all sizes (PNG folder)", systemImage: "square.and.arrow.up.on.square").font(.system(size: 18)).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                Text("Print PDF = trim + bleed. Web = PNGs @1x/2x/3x. Icon — all sizes = every app-icon size (16→1024) as a PNG folder. For a single PNG/JPEG/TIFF/PDF, use Export (⌘E) and pick the format.")
                    .font(.system(size: 18)).foregroundStyle(.primary)
            }

            Divider()

            // --- E · Layer PDF (round-trips with the importer below) ---
            VStack(alignment: .leading, spacing: 10) {
                Text("Layer PDF").font(.system(size: 20, weight: .semibold))
                Button {
                    let matte = flattenLayerPDF ? layerMatte.cgColorResolved : nil
                    if let data = makeLayerPDF(document, matte: matte) {
                        exportData = data; exportType = .pdf
                        exportFilename = "\(displayName) Layers"; showDataExporter = true
                    }
                } label: { Label("Export layers → PDF (one page each)", systemImage: "square.stack.3d.up").font(.system(size: 18)).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                Toggle(isOn: $flattenLayerPDF) {
                    Text("Flatten transparency onto a matte").font(.system(size: 18))
                }
                if flattenLayerPDF {
                    ColorPicker(selection: $layerMatte, supportsOpacity: false) {
                        Text("Matte colour").font(.system(size: 18))
                    }
                }
                Text("Export writes page 1 = the composite, then one page per layer — transparency preserved (flatten only for print).")
                    .font(.system(size: 18)).foregroundStyle(.primary)
                Button {
                    importingPDF = true
                } label: { Label("Import PDF as layers…", systemImage: "square.and.arrow.down.on.square").font(.system(size: 18)).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                Text("Import brings each page in as its own editable image layer.")
                    .font(.system(size: 18)).foregroundStyle(.primary)
            }

        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fileExporter(isPresented: $showDataExporter,
                      document: CanvasDataDocument(exportData),
                      contentType: exportType,
                      defaultFilename: exportFilename) { _ in }
        .fileExporter(isPresented: $showWebExporter,
                      document: webBundle,
                      contentType: .folder,
                      defaultFilename: folderFilename) { _ in }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            _ = importPDFAsLayers(url, into: document)
        }
        .onAppear { draftName = displayName }
        .onChange(of: document.name) { draftName = displayName }
        .onChange(of: fileURL) { draftName = displayName; renameError = false }
    }

    @ViewBuilder private func attrRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 18)).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value).font(.system(size: 18)).foregroundStyle(.primary).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { draftName = displayName; return }
        document.name = trimmed
    }

    /// Rename the .picprod file on disk IN PLACE (one-stop — no trip to Finder). Uses a
    /// coordinated move + presenter notification so the open document follows the new URL
    /// (so autosave keeps writing to the right file).
    private func renameFile() {
        renameError = false
        guard let url = fileURL else { return }
        // Sanitize: a file name can't contain "/" or ":".
        let clean = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let current = url.deletingPathExtension().lastPathComponent
        guard !clean.isEmpty, clean != current else { draftName = displayName; return }
        let newURL = url.deletingLastPathComponent()
            .appendingPathComponent(clean)
            .appendingPathExtension(url.pathExtension)
        guard !FileManager.default.fileExists(atPath: newURL.path) else { renameError = true; return }

        let coordinator = NSFileCoordinator()
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forMoving,
                               writingItemAt: newURL, options: .forReplacing, error: &coordErr) { src, dst in
            do {
                try FileManager.default.moveItem(at: src, to: dst)
                coordinator.item(at: src, didMoveTo: dst)   // notify the open document to follow
            } catch {
                DispatchQueue.main.async { renameError = true; draftName = displayName }
            }
        }
        if coordErr != nil { renameError = true; draftName = displayName }
    }

    /// The name to show: the FILE name when the project is saved (authoritative), else
    /// the working/internal name. Fixes "shows Untitled when I opened erasertime.picprod."
    private var displayName: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        return document.name
    }

    // MARK: B · Dimensions & Resolution
    @AppStorage("ip.canvasUnit") private var unitRaw = CanvasUnit.inch.rawValue
    private var unit: CanvasUnit { CanvasUnit(rawValue: unitRaw) ?? .inch }

    /// Live orientation of the CURRENT canvas. Toggling swaps width/height immediately, so
    /// you can flip any canvas between landscape and portrait (Michael 2026-06-22).
    private var isLandscape: Bool { document.canvasWidth > document.canvasHeight }
    private var landscapeBinding: Binding<Bool> {
        Binding(get: { isLandscape }, set: { want in
            guard want != isLandscape else { return }
            let w = document.canvasWidth
            document.canvasWidth = document.canvasHeight
            document.canvasHeight = w
        })
    }

    /// Derived print size readout (W × H) in the chosen unit, from pixels ÷ PPI.
    private var printSizeText: String {
        if unit == .px { return "\(document.canvasWidth) × \(document.canvasHeight) px" }
        let w = unit.fromInches(Double(document.canvasWidth) / max(1, document.ppi))
        let h = unit.fromInches(Double(document.canvasHeight) / max(1, document.ppi))
        return String(format: "%.2f × %.2f %@", w, h, unit.label)
    }

    @ViewBuilder private func presetButtons(_ list: [CanvasSizePreset]) -> some View {
        ForEach(list) { p in Button(p.label) { applyPreset(p) } }
    }

    @ViewBuilder private func aspectPresetButtons(_ list: [CanvasAspectPreset]) -> some View {
        ForEach(list) { p in Button(p.label) { applyAspectPreset(p) } }
    }

    /// Reshape the canvas to a ratio WITHOUT changing how big it is: the long edge is
    /// kept and the short edge is recomputed. PPI is untouched.
    private func applyAspectPreset(_ p: CanvasAspectPreset) {
        guard p.ratioW > 0, p.ratioH > 0 else { return }
        let long = max(document.canvasWidth, document.canvasHeight)
        let wide = p.ratioW >= p.ratioH
        let shortSide = Int((Double(long) * Double(min(p.ratioW, p.ratioH))
                             / Double(max(p.ratioW, p.ratioH))).rounded())
        document.canvasWidth  = wide ? long : max(1, shortSide)
        document.canvasHeight = wide ? max(1, shortSide) : long

        // SAY IT, DON'T FIX IT. Silently enlarging his canvas to clear a platform's floor
        // would contradict the whole point of this preset — that it keeps the resolution
        // he chose. So the shape changes and the shortfall is reported.
        if p.minLongEdge > 0 && long < p.minLongEdge {
            aspectWarning = "Canvas is \(document.canvasWidth) × \(document.canvasHeight). "
                          + "That is below the \(p.minLongEdge)px minimum long edge for this target — "
                          + "the shape is right, the resolution is too low. Raise Pixels, then re-apply."
        } else {
            aspectWarning = nil
        }
    }

    @ViewBuilder private func pixelPresetButtons(_ list: [CanvasPixelPreset]) -> some View {
        ForEach(list) { p in Button(p.label) { applyPixelPreset(p) } }
    }

    /// Apply a pixel preset: set the pixel count outright. **PPI is deliberately left
    /// alone** — it describes print size, and a screen target has none. The Landscape
    /// toggle is not consulted either: 1280 × 720 is 1280 × 720, and rotating it would
    /// produce something no platform accepts.
    private func applyPixelPreset(_ p: CanvasPixelPreset) {
        document.canvasWidth = max(1, p.pixelWidth)
        document.canvasHeight = max(1, p.pixelHeight)
    }

    /// Apply a size preset: pixels = physical × current PPI, respecting the orientation.
    private func applyPreset(_ p: CanvasSizePreset) {
        let land = p.defaultLandscape                   // each preset's conventional orientation
        let pw = land ? p.longIn : p.shortIn
        let ph = land ? p.shortIn : p.longIn
        document.canvasWidth = max(1, Int((pw * document.ppi).rounded()))
        document.canvasHeight = max(1, Int((ph * document.ppi).rounded()))
    }

    // Standard sizes (stored short × long inches; orientation applied on use).
    static let photoPresets = [
        CanvasSizePreset(label: "Wallet 2.5 × 3.5", shortIn: 2.5, longIn: 3.5),
        CanvasSizePreset(label: "4 × 6",  shortIn: 4,  longIn: 6),
        CanvasSizePreset(label: "5 × 7",  shortIn: 5,  longIn: 7),
        CanvasSizePreset(label: "8 × 10", shortIn: 8,  longIn: 10),
        CanvasSizePreset(label: "8 × 12", shortIn: 8,  longIn: 12),
        CanvasSizePreset(label: "11 × 14", shortIn: 11, longIn: 14),
        CanvasSizePreset(label: "16 × 20", shortIn: 16, longIn: 20),
        CanvasSizePreset(label: "20 × 30", shortIn: 20, longIn: 30),
        CanvasSizePreset(label: "24 × 36", shortIn: 24, longIn: 36),
    ]
    static let paperPresets = [
        CanvasSizePreset(label: "A — Letter 8.5 × 11", shortIn: 8.5, longIn: 11),
        CanvasSizePreset(label: "B — Tabloid 11 × 17", shortIn: 11, longIn: 17),
        CanvasSizePreset(label: "C — 17 × 22", shortIn: 17, longIn: 22),
        CanvasSizePreset(label: "D — 22 × 34", shortIn: 22, longIn: 34),
        CanvasSizePreset(label: "E — 34 × 44", shortIn: 34, longIn: 44),
    ]
    static let indexPresets = [
        CanvasSizePreset(label: "3 × 5", shortIn: 3, longIn: 5),
        CanvasSizePreset(label: "4 × 6", shortIn: 4, longIn: 6),
        CanvasSizePreset(label: "5 × 8", shortIn: 5, longIn: 8),
    ]
    static let businessPresets = [
        CanvasSizePreset(label: "Business card 3.5 × 2", shortIn: 2, longIn: 3.5, defaultLandscape: true),
    ]
    /// Ratio-defined targets — **the ones that actually matter for upload**, because the
    /// platform re-encodes anyway and only the shape survives.
    static let screenAspectPresets = [
        // ⭐ THE TITLE IS THE FEATURE. Michael, 2026-08-25: "the important thing is the
        // title youtube thumbnail over the pixel density." He looks for the JOB, not the
        // numbers — the numbers are what the preset exists to spare him. So the label is
        // the plain name of the thing and nothing else, and it is the ONLY entry carrying
        // that name so there is never a choice to make between two of them.
        CanvasAspectPreset(label: "YouTube thumbnail", ratioW: 16, ratioH: 9, minLongEdge: 640),

        // 3:1. From knowledge, NOT from a local source — X has moved this before, so if a
        // banner ever looks wrong, check their current spec before blaming the preset.
        CanvasAspectPreset(label: "X banner", ratioW: 3, ratioH: 1, minLongEdge: 1500),

        // 820 × 312, which reduces to 205:78 — an ugly ratio because Facebook's number is
        // an arbitrary pixel size rather than a clean shape. Expressed as the exact ratio
        // so the preset still keeps whatever resolution he is working at.
        //
        // ⚠️ FROM KNOWLEDGE, NOT FROM A LOCAL SOURCE, and Facebook has moved this before
        // (851 × 315 was the spec for years). It also crops differently on phone and
        // desktop, so the safe area is smaller than the canvas. If a banner ever looks
        // wrong, check their current spec before blaming the preset.
        CanvasAspectPreset(label: "Facebook banner", ratioW: 205, ratioH: 78, minLongEdge: 820),

        // ⭐ THESE TWO WERE MEASURED, NOT RECALLED. Read straight off Michael's own shipped
        // tvOS app — Tally Matrix Clock's `App Icon & Top Shelf Image.brandassets`:
        //   Top Shelf Image        1920 × 720   (@2x 3840 × 1440)  → exactly 8:3
        //   Top Shelf Image Wide   2320 × 720   (@2x 4640 × 1440)  → exactly 29:9
        // Apple ships BOTH slots, which is why there are two entries here rather than the
        // one he asked for. 2320/720 reduces to 29/9 exactly; it is not an odd rounding.
        CanvasAspectPreset(label: "Apple TV top shelf", ratioW: 8, ratioH: 3, minLongEdge: 1920),
        CanvasAspectPreset(label: "Apple TV top shelf (wide)", ratioW: 29, ratioH: 9, minLongEdge: 2320),

        // 2:3, and the ratio is Apple's own word — TVTopShelfSectionedItem.h in the tvOS
        // SDK says "/// A 2:3 poster image." for TVTopShelfSectionedItemImageShapePoster.
        //
        // ⚠️ THIS IS A DIFFERENT THING FROM THE TWO ABOVE, which is easy to miss. Those are
        // the STATIC top shelf image every tvOS app ships in its brand asset. This one is
        // for DYNAMIC top shelf content, drawn by a TV Services extension, where sectioned
        // items come in three shapes: square 1:1, poster 2:3, HDTV 16:9. An app can use
        // both — the static image when nothing else applies, the dynamic items when the
        // extension supplies them.
        //
        // No minimum long edge: Apple states the shape, not a floor.
        CanvasAspectPreset(label: "Apple TV poster", ratioW: 2, ratioH: 3),
    ]

    /// Pixel-defined targets. Michael asked for the YouTube thumbnail on 2026-08-25;
    /// **1280 × 720 is YouTube's own recommendation** (640 × 360 is their stated minimum,
    /// and 16:9 is what the player expects, so anything else is letterboxed or cropped by
    /// YouTube rather than by him).
    ///
    /// The section is deliberately open-ended — other screen targets drop straight in as
    /// one line each, and none of them need a physical size.
    static let screenPresets = [
        // Kept, but renamed off the "YouTube thumbnail" name — this one is for when he
        // wants that exact canvas, and it should read as a size, not as a second answer
        // to the same question.
        CanvasPixelPreset(label: "1280 × 720 exact", pixelWidth: 1280, pixelHeight: 720),
        CanvasPixelPreset(label: "1500 × 500 exact", pixelWidth: 1500, pixelHeight: 500),
        CanvasPixelPreset(label: "820 × 312 exact", pixelWidth: 820, pixelHeight: 312),
        CanvasPixelPreset(label: "1920 × 720 exact", pixelWidth: 1920, pixelHeight: 720),
        CanvasPixelPreset(label: "2320 × 720 exact", pixelWidth: 2320, pixelHeight: 720),
    ]

    static let envelopePresets = [
        CanvasSizePreset(label: "Letter #6¾ 3.625 × 6.5", shortIn: 3.625, longIn: 6.5, defaultLandscape: true),
        CanvasSizePreset(label: "Business #10 4.125 × 9.5", shortIn: 4.125, longIn: 9.5, defaultLandscape: true),
    ]

    // MARK: file attribute readouts (from the on-disk file)
    private var locationText: String {
        guard let url = fileURL else { return "Not saved yet (untitled)" }
        return url.deletingLastPathComponent().path(percentEncoded: false)
    }
    private var typeText: String {
        guard let ext = fileURL?.pathExtension, !ext.isEmpty else { return "—" }
        return ".\(ext)"
    }
    private var savedText: String {
        guard let url = fileURL,
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return "—" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    private var sizeText: String {
        guard let url = fileURL else { return "—" }
        let bytes = packageSize(url)
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    private var stateText: String {
        fileURL == nil ? "Untitled — not yet saved" : "Saved"
    }

    /// Sum bytes in the `.picprod` package (a directory); falls back to a single file.
    private func packageSize(_ url: URL) -> Int {
        let fm = FileManager.default
        var total = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
        }
        if total == 0 { total = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 }
        return total
    }
}

/// A palette swatch grid that sets a tool's color FROM the palette (the gatekeeper) — no
/// free color picking in the tools. Tap a swatch → `color` becomes that palette color.
/// Custom colors are added in the Color Palette tool.
struct PaletteSwatchRow: View {
    @ObservedObject var document: ImageDocument
    @Binding var color: Color
    var label = "Color (from palette)"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 18))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(document.palette.indices, id: \.self) { i in
                    let c = Color(hex: document.palette[i]) ?? .black
                    let isSel = c.hexString() == color.hexString()
                    RoundedRectangle(cornerRadius: 6).fill(c).frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(isSel ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: isSel ? 3 : 1))
                        .onTapGesture { color = c }
                }
            }
            Text("Colors come from the Color Palette tool.")
                .font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color Palette inspector (Tool: Color Palette — the gatekeeper)

/// The palette is the project's ENTIRE color set and the ONLY place colors are created or
/// edited (Michael 2026-06-22). Every other tool picks FROM these swatches — there are no
/// free color pickers elsewhere. Tap a swatch → it's the active color (pen/bucket/eraser/
/// eyedropper); the picker here edits the selected swatch; Add/Remove grow the box (8 default
/// → 24 max; the 8 base can't be removed). Save/Load reuses the .iconpalette brand file.
struct ColorPaletteInspector: View {
    @EnvironmentObject var pen: PixelPen
    @ObservedObject var document: ImageDocument
    @Binding var fillColor: Color

    @State private var savingPalette = false
    @State private var loadingPalette = false
    @State private var paletteDoc: PaletteFileDocument?
    @State private var loadFailed = false

    private var selected: Int { min(max(pen.selectedSlot, 0), max(0, document.palette.count - 1)) }

    /// Edit the SELECTED swatch — the only place a custom color is created.
    private var selectedColorBinding: Binding<Color> {
        Binding(get: { Color(hex: document.palette[selected]) ?? .black },
                set: { c in
                    guard document.palette.indices.contains(selected) else { return }
                    document.palette[selected] = c.hexString() ?? "#000000"
                    ImageDocument.lastUsedPalette = document.palette
                    applyActive()
                })
    }

    /// Push the selected swatch out as the shared active color (pen + fill tools).
    private func applyActive() {
        let c = Color(hex: document.palette[selected]) ?? .black
        pen.color = c
        fillColor = c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(fillColor)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active color").font(.system(size: 18))
                    Text(document.palette[selected]).font(.system(size: 18))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            ColorPicker("Edit selected swatch", selection: selectedColorBinding, supportsOpacity: false)
                .font(.system(size: 18))

            Divider()

            Text("Palette — \(document.palette.count) colors").font(.system(size: 20, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(document.palette.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: document.palette[i]) ?? .black)
                        .frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(i == selected ? Color.accentColor : Color.gray.opacity(0.4),
                                    lineWidth: i == selected ? 3 : 1))
                        .onTapGesture { pen.selectedSlot = i; applyActive() }
                        .contextMenu {
                            if document.palette.count > 8 {
                                Button(role: .destructive) { document.removePaletteColor(at: i) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            VStack(spacing: 8) {
                Button { if let n = document.addPaletteColor() { pen.selectedSlot = n; applyActive() } } label: {
                    Label("Add color", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .disabled(document.palette.count >= ImageDocument.maxPaletteSlots)
                Button(role: .destructive) { document.removePaletteColor(at: selected) } label: {
                    Label("Remove", systemImage: "minus").frame(maxWidth: .infinity)
                }
                .disabled(document.palette.count <= 8)
            }
            .font(.system(size: 18)).buttonStyle(.bordered)

            Text("Tap a swatch to make it the active color; edit it above. Add grows the box (8–24); the 8 base colors can't be removed. This palette is the only place colors are defined — every tool picks from it.")
                .font(.system(size: 18)).foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 6) {
                Button {
                    paletteDoc = PaletteFileDocument(palette: PaletteFile(name: document.name, colors: document.palette))
                    savingPalette = true
                } label: { Label("Save Palette", systemImage: "plus.rectangle.on.folder").frame(maxWidth: .infinity) }
                Button { loadFailed = false; loadingPalette = true } label: {
                    Label("Load Palette", systemImage: "paintpalette").frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 18)).buttonStyle(.bordered)
            if loadFailed {
                Text("Couldn't read that palette file.").font(.system(size: 18)).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fileExporter(isPresented: $savingPalette, document: paletteDoc,
                      contentType: .iconPalette, defaultFilename: "\(document.name) Palette") { _ in }
        .fileImporter(isPresented: $loadingPalette, allowedContentTypes: [.iconPalette]) { result in
            loadFailed = false
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(PaletteFile.self, from: data) else { loadFailed = true; return }
            document.palette = file.normalizedColors
            ImageDocument.lastUsedPalette = document.palette
            if !document.palette.indices.contains(pen.selectedSlot) { pen.selectedSlot = 0 }
            applyActive()
        }
    }
}

// MARK: - Symbol picker inspector (Tool: Symbol — v1 content path, roadmap 2.2)

/// Pick an SF Symbol and place it on the active CONTENT layer (single-glyph icon is
/// the primary case). Tint is user-chosen; picking replaces the layer's symbol so
/// the user can change their mind. Scale/position via the Move tool.
struct SymbolPickerInspector: View {
    @EnvironmentObject var pen: PixelPen
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?
    @State private var search = ""
    @State private var tint: Color = .black

    /// One searchable Unicode character: the glyph plus its lowercased Unicode name.
    struct UnicodeGlyph: Identifiable, Hashable {
        let char: String
        let name: String
        var id: String { char }
    }

    /// One entry in the blended result grid — an SF Symbol or a Unicode character. The
    /// search covers BOTH repertoires at once (no segment toggle); each tile keeps its own
    /// placement behavior (SF → editable symbol, Unicode → single-glyph text).
    enum GlyphResult: Identifiable, Hashable {
        case sf(String)
        case unicode(UnicodeGlyph)
        var id: String {
            switch self {
            case .sf(let name):   return "sf:" + name
            case .unicode(let g): return "u:" + g.char
            }
        }
    }

    /// A curated starter set of long-standing SF Symbols (safe across OS versions).
    static let symbols: [String] = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "drop.fill",
        "moon.fill", "sun.max.fill", "cloud.fill", "sparkles", "wand.and.stars", "crown.fill",
        "camera.fill", "photo.fill", "video.fill", "music.note", "mic.fill", "headphones",
        "paintbrush.fill", "pencil", "hammer.fill", "wrench.and.screwdriver.fill", "lightbulb.fill", "key.fill",
        "house.fill", "cart.fill", "bag.fill", "gift.fill", "bell.fill", "flag.fill",
        "tag.fill", "paperplane.fill", "envelope.fill", "phone.fill", "message.fill", "globe",
        "map.fill", "location.fill", "clock.fill", "calendar", "folder.fill", "doc.fill",
        "gamecontroller.fill", "gearshape.fill", "lock.fill", "wifi", "airplane", "car.fill",
        "bicycle", "figure.walk", "pawprint.fill", "fish.fill", "bird.fill", "hand.thumbsup.fill",
    ]

    /// The COMPLETE SF Symbols name catalog, bundled as SFSymbolNames.json (generated
    /// from the system CoreGlyphs name_availability.plist, ~9,476 names). Search covers
    /// ALL of these; the curated `symbols` above is only the starting view shown when the
    /// search box is empty. Falls back to the curated set if the resource is missing.
    static let allSymbols: [String] = {
        guard let url = Bundle.main.url(forResource: "SFSymbolNames", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data),
              !names.isEmpty
        else { return symbols }
        return names
    }()

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    private var activeIsContent: Bool {
        guard let i = activeIndex else { return false }
        if case .content = document.layers[i].role { return true }
        return false
    }

    private var currentSymbol: String? {
        guard let i = activeIndex else { return nil }
        return document.layers[i].symbolElementName
    }

    /// The blended result list — SF Symbols first, then Unicode. Empty search shows the
    /// curated SF starter set as a browse default; typing searches BOTH full catalogs.
    private var combinedResults: [GlyphResult] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Self.symbols.map { .sf($0) } }
        let sf = Self.allSymbols.filter { $0.contains(q) }.map { GlyphResult.sf($0) }
        let uni = Self.unicodeGlyphs.filter { $0.name.contains(q) || $0.char == q }
            .map { GlyphResult.unicode($0) }
        return sf + uni
    }

    /// The currently-placed Unicode character on the active layer (for the highlight).
    private var currentText: String? {
        guard let i = activeIndex else { return nil }
        return document.layers[i].textString
    }

    /// The full Unicode symbol/emoji repertoire, built ONCE from the OS's own Unicode name
    /// database (`Unicode.Scalar.Properties.name`) over the symbol-bearing blocks — chess,
    /// cards, arrows, math, dingbats, geometric shapes, misc symbols, and the emoji blocks.
    /// No bundled file, and it stays current with the installed OS's Unicode version.
    static let unicodeGlyphs: [UnicodeGlyph] = {
        let ranges: [ClosedRange<Int>] = [
            0x2190...0x21FF, 0x2200...0x22FF, 0x2300...0x23FF, 0x2460...0x24FF,
            0x2500...0x257F, 0x2580...0x259F, 0x25A0...0x25FF, 0x2600...0x26FF,
            0x2700...0x27BF, 0x2B00...0x2BFF, 0x1F0A0...0x1F0FF, 0x1F300...0x1F5FF,
            0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
        ]
        var out: [UnicodeGlyph] = []
        for r in ranges {
            for cp in r {
                guard let scalar = Unicode.Scalar(cp),
                      let name = scalar.properties.name else { continue }
                out.append(UnicodeGlyph(char: String(scalar), name: name.lowercased()))
            }
        }
        return out
    }()

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        if activeIsContent {
            VStack(alignment: .leading, spacing: 12) {
                PaletteSwatchRow(document: document, color: $tint, label: "Color")
                TextField("Search SF & Unicode", text: $search)
                    .textFieldStyle(.roundedBorder)
                if combinedResults.isEmpty {
                    Text("Can't find an SF or Unicode symbol matching “\(search.trimmingCharacters(in: .whitespaces))”.")
                        .font(.system(size: 16)).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(combinedResults) { resultTile($0) }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 240)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onAppear { tint = pen.color }   // default the tint to the active palette color
        } else {
            PanelPlaceholder(systemImage: "star",
                             title: "Symbol",
                             subtitle: "Select the Icon layer (a content layer) to place a symbol")
        }
    }

    /// One tile in the blended grid — an SF Symbol (Image) or a Unicode character (Text),
    /// each with its own place action and current-selection highlight.
    @ViewBuilder private func resultTile(_ result: GlyphResult) -> some View {
        switch result {
        case .sf(let name):
            Button { place(name) } label: {
                Image(systemName: name)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(name == currentSymbol ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
            }
            .buttonStyle(.plain).accessibilityLabel(name)
        case .unicode(let g):
            Button { placeUnicode(g.char) } label: {
                Text(g.char)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(g.char == currentText ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
            }
            .buttonStyle(.plain).accessibilityLabel(g.name)
        }
    }

    private func place(_ name: String) {
        guard let i = activeIndex else { return }
        document.captureHistoryBaselineIfNeeded()
        document.layers[i].setSymbol(name, tintHex: tint.hexString() ?? "#000000")
        document.recordHistory(toolID: Tool.symbol.rawValue, groupTitle: Tool.symbol.title,
                               actionLabel: "Place Symbol", layerID: document.layers[i].id)
    }

    /// Place a Unicode character as a single-glyph text element on the active layer. Uses
    /// "Apple Symbols" (broad symbol coverage) and relies on Core Text glyph fallback for
    /// anything it lacks (e.g. emoji → Apple Color Emoji). Monochrome symbols take the
    /// chosen tint; color emoji keep their own colors.
    private func placeUnicode(_ char: String) {
        guard let i = activeIndex else { return }
        document.captureHistoryBaselineIfNeeded()
        document.layers[i].setText(char, fontName: "Apple Symbols",
                                   tintHex: tint.hexString() ?? "#000000")
        document.recordHistory(toolID: Tool.symbol.rawValue, groupTitle: Tool.symbol.title,
                               actionLabel: "Place Glyph", layerID: document.layers[i].id)
    }
}

// MARK: - Font picker inspector (Tool: "F" — font glyphs, e.g. Wingdings)

/// Browse an installed font's glyph repertoire and place a character on the active
/// CONTENT layer as a styled text element. Distinct from "SF" (SF Symbols). The font
/// LIST renders each name in its own font, reflecting the live style toggles. Outline
/// is stored but its rendering is a follow-up (no stock SwiftUI text-outline).
struct FontPickerInspector: View {
    @EnvironmentObject var pen: PixelPen
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

    @State private var family: String = FontPickerInspector.families.first ?? "Helvetica"
    @State private var tint: Color = .black
    @State private var bold = false
    @State private var italic = false
    @State private var underline = false
    @State private var outline = false
    @State private var textInput: String = ""
    @State private var glyphs: [String] = []
    /// The live text layer this inspector is creating/editing (its name == its text).
    @State private var currentTextLayerID: ImageLayer.ID?
    /// Center of the line just finished with Enter, so the next line spawns offset below it.
    @State private var lastLineCenter: CGPoint?

    /// Installed font family names (Core Text — cross-platform), sorted.
    static let families: [String] =
        ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).sorted()

    private func styled(_ text: Text) -> Text {
        text.bold(bold).italic(italic).underline(underline)
    }

    /// User-edit binding: typing in the field updates the live text layer. (Programmatic
    /// sets — adopt/new — assign `textInput` directly, NOT through this, so they don't
    /// re-style an adopted layer.)
    private var textBinding: Binding<String> {
        Binding(get: { textInput }, set: { v in
            if v.contains("\n") {
                // Enter finishes this line and ARMS a new layer — it does NOT insert a
                // newline (each line is its own independent layer). Lazy: the armed layer is
                // created only when the next character is typed; double-Enter / stop = done,
                // nothing empty left behind. Remember the current line's center so the next
                // line spawns offset below it.
                if let id = currentTextLayerID,
                   let i = document.layers.firstIndex(where: { $0.id == id }) {
                    lastLineCenter = document.layers[i].transform.center
                }
                textInput = ""
                currentTextLayerID = nil
                return
            }
            textInput = v
            syncText()
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Starting text is unusual, so the initiator is line #1 and prominent (Michael
            // 2026-06-22). Primary way: tap the canvas to start text there; this button is the
            // explicit alternative and always creates a fresh layer.
            Button { newText() } label: {
                Label("New Text Layer", systemImage: "plus.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Tap the canvas to start text there — or tap this. Then type below.")
                .font(.system(size: 18)).foregroundStyle(.secondary)

            Text("Text").font(.system(size: 18)).foregroundStyle(.secondary)
            TextField("Type your text…", text: textBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 18))
                .lineLimit(1...4)
                .autocorrectionDisabled()

            HStack(spacing: 8) {
                styleToggle("bold", "Bold", $bold)
                styleToggle("italic", "Italic", $italic)
                styleToggle("underline", "Underline", $underline)
                styleToggle("character.textbox", "Outline", $outline)
            }

            Text("Font").font(.system(size: 18)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.families, id: \.self) { fam in
                        Button { family = fam; recomputeGlyphs() } label: {
                            styled(Text(fam).font(.custom(fam, size: 16)))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(fam == family ? Color.accentColor.opacity(0.2) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)

            // Glyph browser (a real FontBook for the chosen font) — tapping a glyph APPENDS
            // it to the text, building a string from the keyboard AND the font's repertoire.
            Text("Insert glyph — tap to add to your text").font(.system(size: 18)).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 6)], spacing: 6) {
                    ForEach(glyphs, id: \.self) { g in
                        Button { textInput += g; syncText() } label: {
                            styled(Text(g).font(.custom(family, size: 20)))
                                .frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Glyph \(g)")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)

            PaletteSwatchRow(document: document, color: $tint, label: "Tint (from palette)")

            Text("The text layer updates live, named after the text. Reposition with the Move tool; rename the layer (Layers panel) to edit it later.")
                .font(.system(size: 18)).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { tint = pen.color; if glyphs.isEmpty { recomputeGlyphs() }; adoptActiveLayer() }
        .onChange(of: activeLayerID) { adoptActiveLayer() }
    }

    @ViewBuilder
    private func styleToggle(_ icon: String, _ label: String, _ flag: Binding<Bool>) -> some View {
        Button { flag.wrappedValue.toggle() } label: {
            Image(systemName: icon)
                .frame(width: 36, height: 30)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(flag.wrappedValue ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// The chosen family's supported characters (its repertoire), bounded for speed.
    private func recomputeGlyphs() {
        let font = CTFontCreateWithName(family as CFString, 24, nil)
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        var out: [String] = []
        for value in 0x21...0x33FF {
            guard let scalar = Unicode.Scalar(value), set.contains(scalar) else { continue }
            out.append(String(scalar))
            if out.count >= 1000 { break }
        }
        glyphs = out
    }

    /// Create the live text layer on the first character, then keep it + its NAME in sync
    /// with the typed text. Centered (default transform) — reposition with Move afterward.
    private func syncText() {
        if let id = currentTextLayerID, let i = document.layers.firstIndex(where: { $0.id == id }) {
            document.captureHistoryBaselineIfNeeded()
            document.layers[i].setText(textInput, fontName: family, tintHex: tint.hexString() ?? "#000000",
                                       bold: bold, italic: italic, underline: underline, outline: outline)
            // Canvas → name mirror, ONE-WAY and only while the link is intact. A manual
            // rename severs it (see commitRename), after which typed text no longer
            // renames the layer.
            if document.layers[i].isNameLinkedToText {
                document.layers[i].name = textInput.isEmpty ? "Text" : textInput
            }
            // Coalesce a typing session into one "Text" step (not one per keystroke).
            document.recordHistory(toolID: Tool.text.rawValue, groupTitle: Tool.text.title,
                                   actionLabel: "Text", layerID: id, coalesce: true)
        } else if !textInput.isEmpty {
            document.captureHistoryBaselineIfNeeded()
            var layer = ImageLayer(name: textInput, role: .content)
            layer.setText(textInput, fontName: family, tintHex: tint.hexString() ?? "#000000",
                          bold: bold, italic: italic, underline: underline, outline: outline)
            // A new Enter-made line spawns slightly BELOW the previous one so stacked lines
            // are visible/separable instead of piling up dead-center.
            if let prev = lastLineCenter {
                layer.transform.center = CGPoint(x: prev.x, y: min(prev.y + 0.18, 0.95))
                lastLineCenter = nil
            }
            document.layers.append(layer)
            currentTextLayerID = layer.id
            document.recordHistory(toolID: Tool.text.rawValue, groupTitle: Tool.text.title,
                                   actionLabel: "Text", layerID: layer.id, coalesce: true)
        }
    }

    /// Selecting a text layer (in the Layers panel) loads it here for editing; selecting a
    /// non-text layer starts fresh. Assigns `textInput` directly so it doesn't re-style it.
    private func adoptActiveLayer() {
        if let id = activeLayerID, let i = document.layers.firstIndex(where: { $0.id == id }),
           let s = document.layers[i].textString {
            currentTextLayerID = id
            textInput = s
        } else {
            currentTextLayerID = nil
            textInput = ""
        }
    }

    /// Start a fresh text layer NOW — eagerly create an empty, centered text layer and adopt
    /// it, so the button always produces a visible new layer (it was a dead button before).
    private func newText() {
        var layer = ImageLayer(name: "Text", role: .content)
        layer.setText("", fontName: family, tintHex: tint.hexString() ?? "#000000")
        document.layers.append(layer)
        currentTextLayerID = layer.id
        textInput = ""
    }
}

// MARK: - Image import inspector (Tool: Image — manual import)

/// Import an image file onto the active CONTENT layer. Re-encoded to PNG and kept at
/// native resolution; the canvas scales it to fit the icon (Move tool re-sizes it).
/// v1 stores the bytes in the manifest; sibling-file storage in the package is a
/// follow-up. (Seatrial: the resolution/scaling behaviour is the part to shake down.)
struct ImageImportInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?
    @State private var importing = false
    @State private var failed = false

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }
    private var activeIsContent: Bool {
        guard let i = activeIndex else { return false }
        if case .content = document.layers[i].role { return true }
        return false
    }

    var body: some View {
        if activeIsContent {
            VStack(alignment: .leading, spacing: 12) {
                Button { importing = true } label: {
                    Label("Import Image…", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                Text("Drops an image onto this layer at native resolution, scaled to fit the icon. Use Move to resize/position it.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                Text("Opens PNG, JPEG, HEIC, TIFF, GIF, BMP — and PSD on Mac (imported flattened).")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                if failed {
                    Text("Couldn't read that image.").font(.system(size: 18)).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fileImporter(isPresented: $importing, allowedContentTypes: importableImageTypes) { result in
                failed = false
                guard case .success(let url) = result else { return }
                load(url)
            }
        } else {
            PanelPlaceholder(systemImage: "photo",
                             title: "Image",
                             subtitle: "Select the Icon layer (a content layer) to import an image")
        }
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url),
              let png = pngData(fromImageData: raw),
              let i = activeIndex else { failed = true; return }
        document.captureHistoryBaselineIfNeeded()
        document.layers[i].setImage(png)
        document.recordHistory(toolID: Tool.image.rawValue, groupTitle: Tool.image.title,
                               actionLabel: "Import Image", layerID: document.layers[i].id)
    }
}

// MARK: - Pixel grid overlay

/// Faint grid at the active pixel layer's resolution — shows the cells you paint into
/// while the (higher-res) image on the layer below shows through, for tracing.
struct PixelGrid: View {
    let resolution: Int

    var body: some View {
        Canvas { ctx, size in
            // Draw EVERY line for the resolution (no thinning) — one cell = one pixel.
            let cw = size.width / CGFloat(resolution)
            let ch = size.height / CGFloat(resolution)
            var path = Path()
            for i in 0...resolution {
                let x = CGFloat(i) * cw
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                let y = CGFloat(i) * ch
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(path, with: .color(.gray.opacity(0.7)), lineWidth: 1)
        }
    }
}

// MARK: - Pen inspector (Tool #3 — pixel art)

/// The Pixel Pen's controls: colour, the active layer's resolution (per-layer), a grid
/// toggle, and brush size. Drawing happens on the canvas; this configures the pen.
struct PenInspector: View {
    @EnvironmentObject var pen: PixelPen
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

    /// Resolution rungs for the graduated slider — 2 is the control.
    private let resolutionRungs = [2, 4, 6, 8, 16, 32, 64, 128, 256, 512, 1024]

    /// Which palette slot is open for recoloring (popover).
    private struct EditSlot: Identifiable { let id: Int }
    @State private var editing: EditSlot?

    /// Standalone palette file Save/Load (brand-asset palettes — loadable into any icon).
    @State private var savingPalette = false
    @State private var loadingPalette = false
    @State private var paletteDoc: PaletteFileDocument?
    @State private var paletteLoadFailed = false

    private var activeIsContent: Bool {
        guard let id = activeLayerID,
              let i = document.layers.firstIndex(where: { $0.id == id }) else { return false }
        if case .content = document.layers[i].role { return true }
        return false
    }

    /// Bridge a palette slot (hex in the document) to a Color binding for the picker.
    /// Recoloring writes back to the document, updates the active color if it's the
    /// selected slot, and persists the palette as "last used" so new docs inherit it.
    private func slotColorBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { Color(hex: document.palette[i]) ?? .black },
                set: { c in
                    document.palette[i] = c.hexString() ?? "#000000"
                    if i == pen.selectedSlot { pen.color = c }
                    ImageDocument.lastUsedPalette = document.palette
                })
    }

    var body: some View {
        if activeIsContent {
            VStack(alignment: .leading, spacing: 14) {
                Text("Colors").font(.system(size: 18))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(document.palette.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: document.palette[i]) ?? .black)
                            .frame(height: 26)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(i == pen.selectedSlot ? Color.accentColor : Color.gray.opacity(0.4),
                                        lineWidth: i == pen.selectedSlot ? 2.5 : 1))
                            .onTapGesture {
                                pen.selectedSlot = i
                                pen.color = Color(hex: document.palette[i]) ?? .black
                            }
                            .contextMenu { Button("Change color…") { editing = EditSlot(id: i) } }
                    }
                }
                .popover(item: $editing) { slot in
                    ColorPicker("Slot color", selection: slotColorBinding(slot.id), supportsOpacity: false)
                        .padding().frame(minWidth: 220)
                }
                Text("Tap to use · right-click (long-press) to change. Saved with the file; new docs inherit it.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Button {
                        paletteDoc = PaletteFileDocument(
                            palette: PaletteFile(name: document.name, colors: document.palette))
                        savingPalette = true
                    } label: {
                        Label("Save Palette", systemImage: "plus.rectangle.on.folder")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        paletteLoadFailed = false
                        loadingPalette = true
                    } label: {
                        Label("Load Palette", systemImage: "paintpalette")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 18))
                .buttonStyle(.bordered)
                Text("Save these 8 colors as a reusable brand palette, or load one into this icon.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                if paletteLoadFailed {
                    Text("Couldn't read that palette file.").font(.system(size: 18)).foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("This layer's resolution — \(pen.resolution)\(pen.resolution == 2 ? " (control)" : "") px")
                        .font(.system(size: 18))
                    Slider(value: Binding(
                        get: { Double(resolutionRungs.firstIndex(of: pen.resolution) ?? 4) },
                        set: { pen.resolution = resolutionRungs[min(max(Int($0.rounded()), 0), resolutionRungs.count - 1)] }
                    ), in: 0...Double(resolutionRungs.count - 1), step: 1)
                    // Ruler graduations: first / middle / last detent (indices 0, 5, 10 of 11
                    // rungs). Deliberately below the usual min font size — these are reference
                    // ticks, not body text. Start minimal (3 labels); add more if it reads sparse.
                    HStack {
                        Text("2"); Spacer(); Text("32"); Spacer(); Text("1024")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, -2)
                    Text("Per-layer resolution; the grid matches. Lower = blockier.")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Show grid", isOn: $pen.showGrid)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brush  \(pen.brush) cell\(pen.brush == 1 ? "" : "s")").font(.system(size: 18))
                    Slider(value: Binding(get: { Double(pen.brush) },
                                          set: { pen.brush = Int($0) }), in: 1...8, step: 1)
                }

                Text("Drag on the canvas to drop pixels into the grid cells.")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fileExporter(isPresented: $savingPalette, document: paletteDoc,
                          contentType: .iconPalette, defaultFilename: paletteFilename) { _ in }
            .fileImporter(isPresented: $loadingPalette, allowedContentTypes: [.iconPalette]) { result in
                paletteLoadFailed = false
                guard case .success(let url) = result else { return }
                loadPalette(url)
            }
        } else {
            PanelPlaceholder(systemImage: "pencil.tip", title: "Pen (Pixels)",
                             subtitle: "Select the Icon layer (a content layer) to draw")
        }
    }

    /// Default name for a saved palette — the icon's name plus "Palette".
    private var paletteFilename: String {
        let base = document.name.trimmingCharacters(in: .whitespaces)
        return (base.isEmpty ? "Untitled Icon" : base) + " Palette"
    }

    /// Read a `.iconpalette` file, normalize it to 8 valid slots, and adopt it into the
    /// document + last-used store (so new docs inherit it too). Sets the current pen
    /// color to the selected slot's new value. Fail-safe: a bad file leaves the palette
    /// untouched and surfaces an inline note.
    private func loadPalette(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PaletteFile.self, from: data) else {
            paletteLoadFailed = true
            return
        }
        document.palette = file.normalizedColors
        ImageDocument.lastUsedPalette = document.palette
        if document.palette.indices.contains(pen.selectedSlot) {
            pen.color = Color(hex: document.palette[pen.selectedSlot]) ?? pen.color
        }
    }
}

// MARK: - Bottom swipe panel

/// The three lower-frequency surfaces under the tool strip. A segmented control
/// picks one; on iOS you can also swipe between them.
enum BottomPanel: String, CaseIterable, Identifiable {
    case tool = "Tool"
    case layers = "Layers"
    case history = "History"

    var id: String { rawValue }

    struct PanelView: View {
        @ObservedObject var document: ImageDocument
        let activeTool: Tool
        // (PanelView is the bottom swipe panel; it observes the document too.)
        @Binding var activeLayerID: ImageLayer.ID?
        @Binding var selection: BottomPanel
        @Binding var fillColor: Color
        /// The open document's file on disk — forwarded to the Canvas hub inspector.
        var fileURL: URL? = nil
        /// iPhone passes true: hide the segmented pills and rely on swipe + page dots,
        /// reclaiming vertical room for the cramped inspector. iPad/Mac keep the pills
        /// (default false), so their layout is unchanged.
        var compact: Bool = false

        var body: some View {
            VStack(spacing: 0) {
                if !compact {
                    Picker("", selection: $selection) {
                        ForEach(BottomPanel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)
                }

                #if os(iOS)
                TabView(selection: $selection) {
                    toolPage.tag(BottomPanel.tool)
                    layersPage.tag(BottomPanel.layers)
                    historyPage.tag(BottomPanel.history)
                }
                .tabViewStyle(.page(indexDisplayMode: compact ? .always : .never))
                #else
                // macOS has no page style; portrait branch is unused on Mac, but
                // it still must compile — switch on the selection.
                Group {
                    switch selection {
                    case .tool:    toolPage
                    case .layers:  layersPage
                    case .history: historyPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            }
        }

        private var toolPage: some View {
            ToolInspector(document: document,
                          activeTool: activeTool,
                          activeLayerID: activeLayerID,
                          fillColor: $fillColor,
                          fileURL: fileURL)
        }

        private var layersPage: some View {
            // Compact (iPhone, no pills): show the "Layers" header so the swiped-to page
            // is labeled. With pills (iPad portrait) the pills already label it.
            LayerPanel(document: document, showsHeader: compact, activeLayerID: $activeLayerID)
        }

        private var historyPage: some View {
            HistoryPanel(document: document, activeLayerID: $activeLayerID, showsHeader: compact)
        }
    }
}

/// Placeholder shown on the Tool page until each tool's real inspector is built.
struct ToolInspectorPlaceholder: View {
    let tool: Tool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Inspector — coming soon")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Generic empty-state placeholder for a panel page.
struct PanelPlaceholder: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 18)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Layers + History column (wide / Mac layout)

/// The right-hand column in the landscape/Mac layout: a segmented Layers / History switch,
/// so History (the app's undo) is reachable there — it "sits behind the layer list" per the
/// spec. Portrait / iPhone reach the same two via the bottom swipe panel's picker instead.
struct LayersHistoryColumn: View {
    @ObservedObject var document: ImageDocument
    @Binding var activeLayerID: ImageLayer.ID?

    private enum Tab: String, CaseIterable, Identifiable {
        case layers = "Layers", history = "History"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .layers

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch tab {
            case .layers:  LayerPanel(document: document, activeLayerID: $activeLayerID)
            case .history: HistoryPanel(document: document, activeLayerID: $activeLayerID)
            }
        }
    }
}

// MARK: - History panel (step 3)

/// The linear, tool-grouped edit timeline — the app's undo (there is NO ⌘Z / UndoManager;
/// undo is a byproduct of picking a point here). Newest at the bottom; the last row is the
/// current state. Tap any tool group (its whole run) or a nested action to STEP BACK to that
/// point — everything after it is dropped. The "Original" row returns to the pre-edit state.
/// Purge History (behind the ⋯ menu, confirmed) clears the trail but keeps the current image.
struct HistoryPanel: View {
    @ObservedObject var document: ImageDocument
    @Binding var activeLayerID: ImageLayer.ID?
    /// iPhone (no pills) shows a "History" header so the swiped-to page is labeled.
    var showsHeader: Bool = false

    @State private var expanded: Set<UUID> = []
    @State private var confirmingPurge = false

    /// A history edit awaiting confirmation.
    ///
    /// HISTORY EDITS ARE FINITE — Michael's decision, 2026-08-24: "finite because that
    /// settles the incongruity and has a well i warned ya before it executed."
    ///
    /// The incongruity he was sensing: Restore and Delete are both DESTRUCTIVE, and the
    /// History panel IS this app's undo — ⌘Z/UndoManager was removed because it crashed.
    /// So these two controls destroy the only recovery mechanism there is, and autosave
    /// commits the result within about a second (the cursor returns to .latest, which
    /// un-suppresses the write). There is nothing underneath to catch a misfire, and a
    /// right-click on a small list row is exactly the gesture people misfire.
    ///
    /// The rule this satisfies: a confirmation is the FALLBACK FOR WHEN YOU CANNOT OFFER
    /// UNDO. Undo would be better and is not available here. And the dialog names the
    /// CONSEQUENCE rather than asking "are you sure?" — the user should be agreeing to
    /// something specific, not being asked how confident they feel.
    private enum PendingHistoryEdit: Identifiable {
        case restore(entry: Int, action: Int, dropping: Int, label: String)
        case deleteStep(entry: Int, action: Int, label: String)
        case deleteGroup(entry: Int, count: Int, label: String)
        case restoreOriginal(dropping: Int)

        var id: String {
            switch self {
            case .restore(let e, let a, _, _):   "r\(e).\(a)"
            case .deleteStep(let e, let a, _):   "d\(e).\(a)"
            case .deleteGroup(let e, _, _):      "g\(e)"
            case .restoreOriginal:               "orig"
            }
        }

        var title: String {
            switch self {
            case .restore(_, _, _, let l):       "Restore from “\(l)”?"
            case .deleteStep(_, _, let l):       "Delete “\(l)”?"
            case .deleteGroup(_, _, let l):      "Delete “\(l)”?"
            case .restoreOriginal:               "Restore to Original?"
            }
        }

        var message: String {
            switch self {
            case .restore(_, _, let n, _):
                n == 0 ? "This step is already the newest. Nothing will be deleted."
                       : "\(n) newer step\(n == 1 ? "" : "s") will be permanently deleted. This can’t be undone."
            case .deleteStep:
                "This step will be permanently removed from the history. Your picture won’t change. This can’t be undone."
            case .deleteGroup(_, let n, _):
                "\(n) step\(n == 1 ? "" : "s") will be permanently removed from the history. Your picture won’t change. This can’t be undone."
            case .restoreOriginal(let n):
                "Every recorded step (\(n)) will be permanently deleted and the picture returns to how it started. This can’t be undone."
            }
        }

        var buttonTitle: String {
            switch self {
            case .restore:          "Restore"
            case .deleteStep,
                 .deleteGroup:      "Delete"
            case .restoreOriginal:  "Restore to Original"
            }
        }
    }

    @State private var pending: PendingHistoryEdit?

    /// How many recorded actions sit AFTER the given point — what a Restore would drop.
    private func actionsAfter(entry e: Int, action a: Int) -> Int {
        var n = 0
        for (i, entry) in document.history.entries.enumerated() {
            if i < e { continue }
            n += i == e ? max(0, entry.actions.count - (a + 1)) : entry.actions.count
        }
        return n
    }

    /// Carry out a confirmed edit.
    private func perform(_ edit: PendingHistoryEdit) {
        switch edit {
        case .restore(let e, let a, _, _):
            document.restoreHistory(toEntry: e, action: a)
        case .deleteStep(let e, let a, _):
            document.deleteHistoryStep(entry: e, action: a)
        case .deleteGroup(let e, let count, _):
            for a in stride(from: count - 1, through: 0, by: -1) {
                document.deleteHistoryStep(entry: e, action: a)
            }
        case .restoreOriginal:
            document.deleteHistoryFromBaseline()
        }
        clampActiveLayer()
    }

    /// After viewing/deleting a history point the active layer may no longer exist (e.g. a
    /// fill result layer); fall back to the top layer so the editor keeps a valid selection.
    private func clampActiveLayer() {
        if !document.layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = document.layers.last?.id
        }
    }

    /// Total recorded actions across all groups (baseline excluded).
    private var totalActions: Int {
        document.history.entries.reduce(0) { $0 + $1.actions.count }
    }

    /// Flat ordinal of the currently-viewed point: baseline = -1, otherwise the count of
    /// actions before it. Used to highlight the current row and dim the steps "ahead."
    private var cursorOrdinal: Int {
        switch document.historyCursor {
        case .baseline: return -1
        case .latest:   return totalActions - 1
        case .at(let e, let a):
            return document.history.entries.prefix(e).reduce(0) { $0 + $1.actions.count } + a
        }
    }

    /// Actions before entry `e` — the ordinal of that entry's first action.
    private func baseOrdinal(_ e: Int) -> Int {
        document.history.entries.prefix(e).reduce(0) { $0 + $1.actions.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsHeader {
                    Text("History").font(.system(size: 20, weight: .semibold))
                }
                Spacer()
                Menu {
                    Button(role: .destructive) { confirmingPurge = true } label: {
                        Label("Purge History…", systemImage: "trash")
                    }
                    .disabled(document.history.entries.isEmpty && document.history.baseline == nil)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if document.history.entries.isEmpty && document.history.baseline == nil {
                PanelPlaceholder(systemImage: "clock.arrow.circlepath",
                                 title: "History",
                                 subtitle: "Your edits appear here. Tap a step to view it — nothing is removed. Right-click (or long-press) a step to restore from it, or to delete it.")
            } else {
                List {
                    if document.history.baseline != nil {
                        let isCurrent = cursorOrdinal < 0
                        Button {
                            document.jumpToBaseline(); clampActiveLayer()
                        } label: {
                            Label("Original", systemImage: "photo")
                                .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contextMenu {
                            Button(role: .destructive) {
                                pending = .restoreOriginal(dropping: totalActions)
                            } label: { Label("Restore to Original", systemImage: "arrow.uturn.backward") }
                        }
                    }
                    ForEach(Array(document.history.entries.enumerated()), id: \.element.id) { eIdx, entry in
                        HistoryEntryRow(entry: entry,
                                        baseOrdinal: baseOrdinal(eIdx),
                                        cursorOrdinal: cursorOrdinal,
                                        expanded: expanded.contains(entry.id),
                                        toggle: { toggle(entry.id) },
                                        viewEntry: {
                                            document.jump(toEntry: eIdx, action: entry.actions.count - 1)
                                            clampActiveLayer()
                                        },
                                        viewAction: { aIdx in
                                            document.jump(toEntry: eIdx, action: aIdx)
                                            clampActiveLayer()
                                        },
                                        // Every destructive item ASKS FIRST. History edits
                                        // are finite (Michael 2026-08-24) and this panel is
                                        // the app's only undo, so nothing here executes on
                                        // the click itself.
                                        deleteEntry: {
                                            pending = .deleteGroup(entry: eIdx,
                                                                   count: entry.actions.count,
                                                                   label: entry.title)
                                        },
                                        deleteAction: { aIdx in
                                            pending = .deleteStep(entry: eIdx, action: aIdx,
                                                                  label: entry.actions[aIdx].label)
                                        },
                                        restoreEntry: {
                                            let a = entry.actions.count - 1
                                            pending = .restore(entry: eIdx, action: a,
                                                               dropping: actionsAfter(entry: eIdx, action: a),
                                                               label: entry.title)
                                        },
                                        restoreAction: { aIdx in
                                            pending = .restore(entry: eIdx, action: aIdx,
                                                               dropping: actionsAfter(entry: eIdx, action: aIdx),
                                                               label: entry.actions[aIdx].label)
                                        })
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.plain)
                #endif
            }
        }
        .confirmationDialog("Purge all history?",
                            isPresented: $confirmingPurge, titleVisibility: .visible) {
            Button("Purge History", role: .destructive) { document.purgeHistory() }
            Button("Cancel", role: .cancel) { }
        .confirmationDialog(pending?.title ?? "",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            presenting: pending) { edit in
            Button(edit.buttonTitle, role: .destructive) { perform(edit); pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { edit in
            Text(edit.message)
        }
        } message: {
            Text("Keeps the current image and clears the entire edit trail. This can't be undone.")
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// One tool-group row in the History panel: a chevron to reveal the nested actions, the
/// group title + action count, and (when expanded) each nested action. TAP a group or an
/// action to VIEW that state (non-destructive). RIGHT-CLICK / LONG-PRESS to delete it and
/// everything after. The current point is highlighted; steps "ahead" of it are dimmed.
private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let baseOrdinal: Int          // ordinal of this entry's first action
    let cursorOrdinal: Int        // currently-viewed ordinal (baseline = -1)
    let expanded: Bool
    let toggle: () -> Void
    let viewEntry: () -> Void
    let viewAction: (Int) -> Void
    let deleteEntry: () -> Void
    let deleteAction: (Int) -> Void
    let restoreEntry: () -> Void
    let restoreAction: (Int) -> Void

    private var toolSymbol: String { Tool(rawValue: entry.toolID)?.systemImage ?? "square.dashed" }
    private var lastOrdinal: Int { baseOrdinal + entry.actions.count - 1 }
    /// The viewed point falls inside this group.
    private var groupHoldsCursor: Bool { cursorOrdinal >= baseOrdinal && cursorOrdinal <= lastOrdinal }
    /// The whole group is ahead of the viewed point (dimmed — dropped if you edit/delete).
    private var groupAhead: Bool { baseOrdinal > cursorOrdinal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                Button(action: viewEntry) {
                    HStack {
                        // Step number, 1 = OLDEST (Michael 2026-08-24: "it should also
                        // number the history rows in order 1, 2, 3, etc" … "one being
                        // oldest"). A group spanning several actions shows its range,
                        // so the numbers line up with the children when expanded.
                        Text(baseOrdinal == lastOrdinal
                             ? "\(baseOrdinal + 1)."
                             : "\(baseOrdinal + 1)–\(lastOrdinal + 1).")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: toolSymbol)
                        Text(entry.title)
                        Spacer()
                        Text("\(entry.actions.count)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 16, weight: groupHoldsCursor ? .semibold : .regular))
            .opacity(groupAhead ? 0.4 : 1)
            .contextMenu {
                // Two choices that do genuinely different jobs — Michael 2026-08-24:
                // "restore does keep this step and deletes newer and the other option in
                // the right click is delete this history line only". RESTORE changes the
                // picture; DELETE only tidies the list and leaves the canvas alone.
                Button(action: restoreEntry) {
                    Label("Restore from This Step", systemImage: "clock.arrow.circlepath")
                }
                Divider()
                Button(role: .destructive, action: deleteEntry) {
                    Label("Delete This Step", systemImage: "trash")
                }
            }

            if expanded {
                ForEach(Array(entry.actions.enumerated()), id: \.element.id) { aIdx, action in
                    let ord = baseOrdinal + aIdx
                    let isCurrent = ord == cursorOrdinal
                    Button { viewAction(aIdx) } label: {
                        HStack {
                            Text("\(ord + 1).")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(action.label)
                            Spacer()
                            if isCurrent {
                                Image(systemName: "eye.fill").font(.system(size: 11))
                            }
                        }
                        .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                        .padding(.leading, 30)
                        .padding(.vertical, 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(ord > cursorOrdinal ? 0.4 : 1)
                    .contextMenu {
                        Button { restoreAction(aIdx) } label: {
                            Label("Restore from This Step", systemImage: "clock.arrow.circlepath")
                        }
                        Divider()
                        Button(role: .destructive) { deleteAction(aIdx) } label: {
                            Label("Delete This Step", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Move / Transform inspector

/// Tool #1's inspector: a document-level CROP section (aspect + size, non-destructive,
/// shrink-only — v1) plus scale / rotation / center / reset on the ACTIVE layer.
struct MoveTransformInspector: View {
    @ObservedObject var document: ImageDocument
    let activeLayerID: ImageLayer.ID?

    @State private var cropAspect: CropAspect = .original
    @State private var cropSize: Double = 0.8       // limiting-dimension fraction for a locked ratio
    @State private var freeWidth: Double = 0.8      // Freeform width fraction
    @State private var freeHeight: Double = 0.8     // Freeform height fraction
    @State private var customW: Int = 4             // Custom ratio width
    @State private var customH: Int = 3             // Custom ratio height

    private var index: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                cropSection
                Divider()
                if let idx = index {
                    layerControls(idx)
                } else {
                    PanelPlaceholder(systemImage: "hand.tap",
                                     title: "Move / Transform",
                                     subtitle: "Tap a layer to select it, then drag it on the canvas")
                        .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onAppear(perform: syncCropStateFromDocument)
    }

    // MARK: Crop (document-level, non-destructive, centered — Photos-style presets)
    @ViewBuilder private var cropSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crop").font(.system(size: 18)).bold()
            Text("Aspect ratio").font(.system(size: 18)).foregroundStyle(.secondary)
            Picker("Aspect", selection: $cropAspect) {
                Text("Original").tag(CropAspect.original)
                Text("Freeform").tag(CropAspect.freeform)
                ForEach(CropAspect.presets, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
                Text("Custom").tag(CropAspect.custom)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            if cropAspect != .original {
                // Apply (destructive) sits a short space below the aspect picker.
                // Non-destructive now (makes a new cropped layer), so no "can't be undone"
                // confirmation needed.
                Button { commitCrop() } label: {
                    Label("Apply Crop", systemImage: "crop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)

                cropSizeControls

                Text("Live preview is non-destructive (Export/Share trim to it). Apply Crop makes a new cropped layer and hides the original (kept).")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
            }
        }
        // ⚠️ ALSO ON APPEAR, NOT ONLY ON CHANGE. Every call to applyCrop() used to come
        // from an .onChange, which means a selection that is ALREADY set when the panel
        // opens — restored, or left in @State — never computes a rect. The picker then
        // reads "Square" while `document.cropRect` is nil and the overlay draws nothing,
        // so re-choosing the value that is already chosen does nothing at all. Found
        // while diagnosing the square-crop report, 2026-08-27.
        .onAppear { if cropAspect != .original { applyCrop() } }
        .onChange(of: cropAspect) { applyCrop() }
        .onChange(of: cropSize) { applyCrop() }
        .onChange(of: freeWidth) { applyCrop() }
        .onChange(of: freeHeight) { applyCrop() }
        .onChange(of: customW) { applyCrop() }
        .onChange(of: customH) { applyCrop() }
    }

    /// Size controls vary by mode: one Size slider for a locked ratio, two sliders for
    /// Freeform (independent W + H), and a W:H entry plus Size for Custom.
    @ViewBuilder private var cropSizeControls: some View {
        switch cropAspect {
        case .freeform:
            Text("Width  \(Int(freeWidth * 100))%").font(.system(size: 18))
            Slider(value: $freeWidth, in: 0.1...1.0)
            Text("Height  \(Int(freeHeight * 100))%").font(.system(size: 18))
            Slider(value: $freeHeight, in: 0.1...1.0)
        case .custom:
            HStack {
                Stepper("W \(customW)", value: $customW, in: 1...32)
                Stepper("H \(customH)", value: $customH, in: 1...32)
            }
            .font(.system(size: 18))
            Text("Crop size  \(Int(cropSize * 100))%").font(.system(size: 18))
            Slider(value: $cropSize, in: 0.1...1.0)
        default:
            Text("Crop size  \(Int(cropSize * 100))%").font(.system(size: 18))
            Slider(value: $cropSize, in: 0.1...1.0)
        }
    }

    /// Destructive commit (v1.1): crop ONLY the active layer to the crop rect, keeping
    /// every other layer and the project's layer structure intact (NO flatten). The
    /// active layer's content is baked into a TIGHTLY-CROPPED PNG (just the kept region,
    /// at the crop rect's pixel size), then placed back with a transform that is
    /// centered on the canvas, scaled to the crop's limiting dimension, and tagged with
    /// the crop's aspect. So the cropped image lands as a normal selectable object — the
    /// Move box hugs it (no orphaned full-canvas handles, no dead checkerboard frame) —
    /// and the Fit/Fill control can snap it to the canvas. Other layers + the document
    /// are left alone; Share/Export still flattens a throwaway copy, so the project is
    /// never destroyed. No undo (no UndoManager — hence the confirmation).
    /// Cropping MULTIPLE selected layers at once = v1.2 (needs multi-layer selection).
    private func commitCrop() {
        guard let crop = document.cropRect, let idx = index,
              document.layers.indices.contains(idx),
              case .content = document.layers[idx].role else {
            // No active content layer (e.g. a background is active): nothing to bake,
            // just clear the crop so the overlay goes away.
            DispatchQueue.main.async { document.cropRect = nil; cropAspect = .original }
            return
        }
        let w = CGFloat(document.canvasWidth), h = CGFloat(document.canvasHeight)
        let layerID = document.layers[idx].id
        // Render JUST the active layer (with its current transform), then crop the
        // resulting bitmap to the kept region — yielding a tight crop-sized PNG.
        let solo = ImageDocument(name: document.name, canvasWidth: document.canvasWidth,
                                canvasHeight: document.canvasHeight,
                                layers: [document.layers[idx]], palette: document.palette,
                                cropRect: nil)
        let renderer = ImageRenderer(content: ImageCompositeView(document: solo, size: document.canvasPixelSize))
        renderer.scale = 1
        let px = CGRect(x: crop.minX * w, y: crop.minY * h,
                        width: crop.width * w, height: crop.height * h).integral
        // Bake through the same mask the canvas previewed, so Apply and Export agree.
        let cutMask = document.cropMask ?? CropMask(rect: crop)
        guard px.width >= 1, px.height >= 1,
              let full = renderer.cgImage,
              let cropped = cutMask.clip(full),
              let png = pngData(from: cropped) else { return }
        // Defer the mutation so the confirmation dialog fully dismisses and any in-flight
        // slider bindings settle before the layer's content changes.
        DispatchQueue.main.async {
            guard let i = document.layers.firstIndex(where: { $0.id == layerID }) else { return }
            // Non-destructive: the cropped image becomes a NEW layer above; the original
            // is hidden (kept), not overwritten — there's no undo. Then give the new layer
            // the centered/scaled/aspect transform so the Move box hugs it (ready for Fit/Fill).
            document.captureHistoryBaselineIfNeeded()
            if let newID = document.addResultLayer(png, above: i, nameSuffix: "cropped"),
               let ni = document.layers.firstIndex(where: { $0.id == newID }) {
                document.layers[ni].transform = LayerTransform(
                    center: CGPoint(x: 0.5, y: 0.5),
                    scale: max(crop.width, crop.height),
                    rotationDegrees: 0,
                    contentAspect: crop.height > 0 ? crop.width / crop.height : 1)
                // Crop is a destructive Apply (new layer, source hidden) → one history step.
                document.recordHistory(toolID: Tool.move.rawValue, groupTitle: "Crop",
                                       actionLabel: "Crop", layerID: newID)
            }
            document.cropRect = nil
            cropAspect = .original
        }
    }

    /// Build a centered, normalized crop rect from the chosen aspect + size. Original
    /// clears the crop; a locked ratio scales to fit by its limiting dimension;
    /// Freeform uses independent W/H; Custom uses the W:H entry.
    private func applyCrop() {
        switch cropAspect {
        case .original:
            document.cropRect = nil
        case .freeform:
            document.cropRect = centeredRect(width: freeWidth, height: freeHeight)
        case .custom:
            document.cropRect = ratioRect(Double(customW), Double(customH), size: cropSize)
        case .ratio(let w, let h):
            document.cropRect = ratioRect(Double(w), Double(h), size: cropSize)
        }
    }

    /// A centered rect for a w:h ratio whose LIMITING dimension fills `size` of the
    /// canvas.
    ///
    /// ⚠️ THE CANVAS ASPECT MUST BE DIVIDED OUT. `cropRect` is stored in NORMALISED
    /// canvas coordinates (0...1), not pixels — so "0.8 wide by 0.8 tall" is only a
    /// SQUARE ON SCREEN when the canvas itself is square. On any other canvas it comes
    /// out wearing the canvas's shape.
    ///
    /// Michael found this from real use, 2026-08-27: *"i chose square aspect ratio and it
    /// stayed rectangle and didnt automatically snap to square with the shaded ask
    /// previewing a square crop."* Measured off his screen: canvas 2.0:1, crop drawn
    /// 1.97:1 at Square/80% — exactly 80% of width by 80% of height. The old comment here
    /// said it "always fits inside the square", which quietly assumed a square canvas and
    /// was the whole bug.
    ///
    /// So: convert the requested VISUAL ratio into a normalised-space ratio first.
    private func ratioRect(_ w: Double, _ h: Double, size: Double) -> CGRect {
        guard w > 0, h > 0 else { return centeredRect(width: size, height: size) }
        let cw = Double(document.canvasWidth), ch = Double(document.canvasHeight)
        // A degenerate canvas would divide by zero; fall back to the old behaviour
        // rather than producing NaN, which propagates into an invisible rect.
        let canvasAspect = (cw > 0 && ch > 0) ? cw / ch : 1
        let aspect = (w / h) / canvasAspect
        let width  = aspect >= 1 ? size : size * aspect
        let height = aspect >= 1 ? size / aspect : size
        return centeredRect(width: width, height: height)
    }

    private func centeredRect(width: Double, height: Double) -> CGRect {
        CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// Reflect an existing saved crop back into the picker on open (best-effort): match
    /// a known preset by aspect if one fits, else fall back to Freeform (which can
    /// represent any rect exactly).
    private func syncCropStateFromDocument() {
        guard let r = document.cropRect, r.width > 0, r.height > 0 else { cropAspect = .original; return }
        let aspect = r.width / r.height
        if let preset = CropAspect.presets.first(where: { p in
            guard case .ratio(let w, let h) = p else { return false }
            return abs(Double(w) / Double(h) - aspect) < 0.02
        }) {
            cropAspect = preset
            cropSize = max(0.1, min(1.0, max(r.width, r.height)))
        } else {
            cropAspect = .freeform
            freeWidth = max(0.1, min(1.0, r.width))
            freeHeight = max(0.1, min(1.0, r.height))
        }
    }

    // MARK: Active-layer transform
    @ViewBuilder private func layerControls(_ idx: Int) -> some View {
        // Bounds-guard the whole section: the active layer can be removed (e.g. Apply
        // Crop collapses the stack) while a stale `idx` is still in flight.
        if document.layers.indices.contains(idx) {
            VStack(alignment: .leading, spacing: 18) {
                // Fit / Fill — snap the active object to the canvas. Live and explicit:
                // each tap re-snaps so what you see is exactly the result (no inferred
                // position). Only meaningful for a content layer that has something on it
                // — e.g. the object you just cropped. Fit honors the object's aspect (so
                // a non-square crop letterboxes); Fill covers the canvas and clips.
                if case .content = document.layers[idx].role,
                   !document.layers[idx].elements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Snap to Canvas").font(.system(size: 18))
                        HStack {
                            Button("Fit")  { applyFitFill(.fit,  idx) }
                            Button("Fill") { applyFitFill(.fill, idx) }
                        }
                        .buttonStyle(.bordered)
                        Text("Fit insets the object inside the canvas (letterbox if it isn't square). Fill covers the canvas and clips the overflow.")
                            .font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scale  \(Int(document.layers[idx].transform.scale * 100))%")
                        .font(.system(size: 18))
                    // 100% SITS AT THE CENTRE. Michael, 2026-09-02, after saying Rotation
                    // reads correctly and Scale does not: "i want 100% to be center then i
                    // want gradiens but NO snap. i want gradians 1.5 2 2.5 3."
                    //
                    // The old slider ran 0.1...4.0 straight, which put 1.0 about a QUARTER
                    // of the way along — so the resting value was nearly hard left, three
                    // quarters of the track enlarged, and shrinking was crushed into a
                    // sliver. Rotation only felt right because -180...180 is symmetric and
                    // zero therefore lands dead centre; this gives Scale the same property.
                    //
                    // The track is now a POSITION from -1 to 1 with 1.0 at 0, mapped
                    // piecewise: right half 1.0 -> 4.0, left half 1.0 -> 0.1. Both ends of
                    // the original range are kept.
                    //
                    // NO `step:` ANYWHERE — he asked for that explicitly. The marks below
                    // are drawn, not enforced; the slider passes straight through them.
                    Slider(value: scaleSliderBinding(idx), in: -1...1)
                    ScaleTicks()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rotation  \(Int(document.layers[idx].transform.rotationDegrees))°")
                        .font(.system(size: 18))
                    Slider(value: transformBinding(\.rotationDegrees, idx), in: -180...180)
                }
                HStack {
                    Button("Center") {
                        guard document.layers.indices.contains(idx) else { return }
                        document.layers[idx].transform.center = CGPoint(x: 0.5, y: 0.5)
                    }
                    Button("Reset") {
                        guard document.layers.indices.contains(idx) else { return }
                        document.layers[idx].transform = LayerTransform()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Bounds-safe so a slider that fires after its layer was removed can't crash.
    private func transformBinding<V>(_ keyPath: WritableKeyPath<LayerTransform, V>,
                                     _ idx: Int) -> Binding<V> {
        Binding(get: { document.layers.indices.contains(idx)
                        ? document.layers[idx].transform[keyPath: keyPath]
                        : LayerTransform()[keyPath: keyPath] },
                set: { if document.layers.indices.contains(idx) {
                        document.layers[idx].transform[keyPath: keyPath] = $0 } })
    }

    /// Slider position <-> layer scale, with 1.0 (100%) pinned to the centre of the track.
    ///
    /// Position runs -1...1. The right half grows 1x -> 4x; the left half is its exact
    /// MIRROR, dividing by the same numbers — so a mark at -2 is half size and -3 is a
    /// third. Michael, 2026-09-02: "i want the gradians on the left to have a minus."
    ///
    /// TRADE-OFF, STATED RATHER THAN HIDDEN: true symmetry puts the left end at 1/4x
    /// (0.25) instead of the old 0.1. The corner drag handles still reach 0.1, so nothing
    /// is unreachable — only the slider's own travel is symmetric now.
    ///
    /// `ScaleTicks` uses the same mapping, so every drawn mark lands under the value it
    /// names, on both sides.
    private func scaleSliderBinding(_ idx: Int) -> Binding<Double> {
        Binding(
            get: {
                let scale = document.layers.indices.contains(idx)
                    ? document.layers[idx].transform.scale
                    : 1.0
                return ScaleTicks.position(for: scale)
            },
            set: { position in
                guard document.layers.indices.contains(idx) else { return }
                let scale = position >= 0
                    ? 1 + position * 3                  // 1x  -> 4x,  even steps up
                    : 1 + position * 0.75               // 1x  -> 1/4x, even steps down
                document.layers[idx].transform.scale = min(max(scale, 0.1), 4.0)
            }
        )
    }

    /// Snap the active object to the canvas, centered. Fit = the limiting (larger)
    /// dimension fills the canvas, the other letterboxes (scale 1.0). Fill = the
    /// smaller dimension fills the canvas, the larger overflows and is clipped
    /// (scale = max(aspect, 1/aspect), capped to the slider's 4× ceiling). Uses the
    /// content's recorded aspect; a square object behaves identically either way.
    private func applyFitFill(_ mode: FitFillMode, _ idx: Int) {
        guard document.layers.indices.contains(idx) else { return }
        let aspect = document.layers[idx].transform.contentAspect ?? 1
        let scale: Double = (mode == .fit) ? 1.0 : min(max(aspect, 1 / aspect), 4.0)
        document.layers[idx].transform.scale = scale
        document.layers[idx].transform.center = CGPoint(x: 0.5, y: 0.5)
    }
}

/// The two ways to snap a placed/cropped object to the canvas (Move inspector).
enum FitFillMode { case fit, fill }

/// Crop aspect choices in the Move/Transform inspector (Photos-style presets).
/// `ratio(w:h:)` covers Square (1:1) and every fixed preset; Freeform = independent
/// W/H; Custom = a user-entered W:H; Original = no crop.
enum CropAspect: Hashable {
    case original, freeform, custom
    case ratio(w: Int, h: Int)

    /// Fixed presets in Photos' order (Square first), shown between Freeform and Custom.
    static let presets: [CropAspect] = [
        .ratio(w: 1, h: 1), .ratio(w: 16, h: 9), .ratio(w: 4, h: 5), .ratio(w: 5, h: 7),
        .ratio(w: 4, h: 3), .ratio(w: 3, h: 5), .ratio(w: 3, h: 2),
    ]

    var label: String {
        switch self {
        case .original: "Original"
        case .freeform: "Freeform"
        case .custom:   "Custom"
        case .ratio(let w, let h): w == h ? "Square" : "\(w):\(h)"
        }
    }
}

/// A flat PNG of the icon, shareable via the native `ShareLink`. Holds already-rendered
/// `Data` (Sendable); the render happens on the main actor before this is constructed.
struct ImageShare: Transferable {
    let pngData: Data
    let filename: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.pngData }
            .suggestedFileName { $0.filename + ".png" }
    }
}

// MARK: - Canvas

/// The square artboard. Composites the visible layers bottom-to-top over a
/// transparency checkerboard. (Blank layers render nothing -> checkerboard shows.)
/// When Move is active and a layer is selected, draws a draggable transform box.
#if os(macOS)
/// macOS-only: captures right-mouse (secondary) clicks/drags on the canvas and reports the
/// normalized point (0…1, top-left origin) so right-click ERASES a pixel without flipping the
/// Draw/Erase mode. Left-clicks pass through to the SwiftUI draw gesture underneath.
struct RightClickEraser: NSViewRepresentable {
    var onErase: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let v = RightClickView(); v.onErase = onErase; v.onEnded = onEnded; return v
    }
    func updateNSView(_ v: RightClickView, context: Context) {
        v.onErase = onErase; v.onEnded = onEnded
    }

    final class RightClickView: NSView {
        var onErase: ((CGPoint) -> Void)?
        var onEnded: (() -> Void)?

        private func report(_ event: NSEvent) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            let nx = max(0, min(1, p.x / bounds.width))
            let ny = max(0, min(1, 1 - p.y / bounds.height))   // AppKit bottom-left → top-left
            onErase?(CGPoint(x: nx, y: ny))
        }
        override func rightMouseDown(with event: NSEvent) { report(event) }
        override func rightMouseDragged(with event: NSEvent) { report(event) }
        override func rightMouseUp(with event: NSEvent) { onEnded?() }

        /// Claim ONLY right-mouse events; return nil otherwise so the SwiftUI left-drag
        /// gesture beneath still receives normal clicks.
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}
#endif

/// The brush eraser's footprint ring, shown at the cursor BEFORE you commit so you can
/// see exactly which pixels a stroke will clear (there's no undo). Double-stroked (dark
/// under, light over) so it reads on any background. Circle or square to match the brush.
struct BrushCursor: View {
    let diameter: CGFloat
    let square: Bool
    private var shape: AnyShape { square ? AnyShape(Rectangle()) : AnyShape(Circle()) }
    var body: some View {
        ZStack {
            shape.stroke(Color.black.opacity(0.7), lineWidth: 3)
            shape.stroke(Color.white, lineWidth: 1.5)
        }
        .frame(width: max(2, diameter), height: max(2, diameter))
    }
}

/// Makes the mouse pointer reflect the active tool while it's over the canvas — a paint
/// bucket for Fill, a pencil tip for Pen, etc. (macOS 15+ `.pointerStyle`; a no-op on iOS,
/// which has no pointer). Tools with no drawing action (Move / Zoom / Symbol / Image) fall
/// back to the system arrow (nil). Hot spots put the "business end" of each glyph on the
/// actual click point (the drip of the drop, the tip of the pencil/dropper).
private struct ToolPointer: ViewModifier {
    let tool: Tool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.pointerStyle(Self.style(for: tool))
        #else
        content
        #endif
    }

    #if os(macOS)
    /// EVERY tool gets its own pointer. Michael, 2026-08-22: "all of the tools should
    /// change the arrow pointer to the respective tool pointer."
    ///
    /// The old version covered five tools and left the rest on the system arrow, on the
    /// reasoning that panel-only tools never click the canvas. But the cursor is how you
    /// know which tool you are holding — leaving it an arrow makes the app look like
    /// nothing is selected, whichever tool it is. Each pointer uses that tool's own
    /// toolbar symbol, so the cursor and the button always match.
    static func style(for tool: Tool) -> PointerStyle? {
        switch tool {
        // Tools you click the canvas with — hot spot placed at the working tip.
        // The drop's POINT is at the top of the glyph, not the bottom — that is the tip
        // you aim with. Michael: "the hot point should be the top pointy part of the drip".
        case .fill:       .image(Image(systemName: "drop.fill"),   hotSpot: UnitPoint(x: 0.5, y: 0.0))
        case .pen:        .image(Image(systemName: "pencil.tip"),  hotSpot: UnitPoint(x: 0.2, y: 0.9))
        case .eraser:     .image(Image(systemName: "eraser.fill"), hotSpot: UnitPoint(x: 0.5, y: 0.6))
        case .eyedropper: .image(Image(systemName: "eyedropper"),  hotSpot: UnitPoint(x: 0.15, y: 0.9))
        case .magicLasso: .image(Image(systemName: "lasso.badge.sparkles"),
                                 hotSpot: UnitPoint(x: 0.5, y: 0.55))
        case .shape:      .image(Image(systemName: "square.on.circle"), hotSpot: UnitPoint(x: 0.5, y: 0.5))
        case .path:       .image(Image(systemName: "point.topleft.down.to.point.bottomright.curvepath"),
                                 hotSpot: UnitPoint(x: 0.2, y: 0.2))
        case .move:       .image(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right"),
                                 hotSpot: UnitPoint(x: 0.5, y: 0.5))
        // The mask is dragged by its corners and its middle, so the pointer is the frame
        // itself, centred — same reasoning as Move.
        case .mask:       .image(Image(systemName: "square.dashed"), hotSpot: UnitPoint(x: 0.5, y: 0.5))
        case .zoom:       .image(Image(systemName: "magnifyingglass"), hotSpot: UnitPoint(x: 0.45, y: 0.45))
        case .symbol:     .image(Image(systemName: "star"),        hotSpot: UnitPoint(x: 0.5, y: 0.5))

        // ARROW, deliberately. Michael listed these as exceptions: they are driven from
        // the inspector and you never click the canvas with them, so a tool cursor over
        // the canvas would promise something the tool does not do.
        // Text places characters ON the canvas, so the I-beam is right — Michael put it
        // back after the first pass moved it to the arrow.
        case .text:       .horizontalText

        case .imagePlayground, .canvas, .colorPalette, .image, .cutout:
            nil
        }
    }
    #endif
}

struct CanvasView: View {

    /// The floating production preview, factored OUT of `body` deliberately: the
    /// canvas expression is already at the Swift type-checker's limit, and inlining
    /// even this much broke the build with "unable to type-check in reasonable
    /// time". Anything further added to the canvas should come out here too.
    /// Commit a pen stroke — as a NEW LAYER, every time.
    ///
    /// THE BUG THIS STARTED FROM, found by Michael 2026-08-24: he placed a star on
    /// Foreground, switched to the Pen, drew one stroke, and the star was GONE.
    /// `ImageLayer.setPixels` REPLACES the elements array, so the first stroke
    /// silently destroyed the symbol — with no warning and no undo, in an app where
    /// every other destructive op keeps the original.
    ///
    /// HIS RULE, and he had to give it to me twice because I argued the second half
    /// down as "a layer per stroke — wrong":
    ///   1. "the first pixel should have created a copy new layer foreground (pixels)"
    ///   2. "and every time you start a new pixel stroke it should make a new copy and
    ///      (layer x) to keep it non distructive and reversable"
    ///
    /// So EVERY stroke forks. Foreground → "Foreground (pixels)" → "(pixels 2)" →
    /// "(pixels 3)". The previous PIXEL layer is hidden as each new one lands, so the
    /// stack does not double-draw; unhide any earlier one to step back to it. The
    /// ORIGINAL ART layer is never hidden — the pixel-grid note in this file says the
    /// layer below "shows through, for tracing", and tracing needs it visible.
    ///
    /// Yes, this makes a lot of layers. That is the cost of being reversible, and it
    /// is the same mantra as the other Applies ("original kept + hidden — there's no
    /// undo"). His call, twice.
    @MainActor private func commitPenPixels(_ data: Data, actionLabel: String) {
        guard let i = activeIndex, document.layers.indices.contains(i) else { return }
        document.captureHistoryBaselineIfNeeded()   // before the edit

        let source = document.layers[i]
        let sourceHoldsPixels = source.pixelData != nil

        // Naming is HIS — "(Pixel X)", capital, SINGULAR, always numbered
        // (Michael 2026-08-24: "or not layerx but (Pixel X)" … "i think your singular
        // (pixel) should be good"). So: Foreground (Pixel 1), (Pixel 2), (Pixel 3).
        //
        // Strip any existing "(Pixel n)" first so forks never compound into
        // "Foreground (Pixel 1) (Pixel 2)".
        var base = source.name
        if let r = base.range(of: #" \(Pixel \d+\)$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }

        // Next free number in this family.
        var n = 1
        let taken = Set(document.layers.map(\.name))
        func name(_ k: Int) -> String { "\(base) (Pixel \(k))" }
        while taken.contains(name(n)) { n += 1 }

        var fork = ImageLayer(name: name(n), role: .content)
        fork.setPixels(data)
        fork.transform = source.transform          // sit exactly over what it came from

        // Hide the layer we forked FROM only when it was itself a pixel layer — two
        // rasters of the same drawing stacked would double-draw. An art layer (symbol,
        // text, image) stays visible so it can be traced.
        if sourceHoldsPixels { document.layers[i].isVisible = false }

        document.layers.insert(fork, at: i + 1)    // directly above
        activeLayerID = fork.id                    // the pen follows the newest layer
        document.recordHistory(toolID: Tool.pen.rawValue,
                               groupTitle: Tool.pen.title,
                               actionLabel: actionLabel,
                               layerID: fork.id)
    }

    /// The canvas's preview overlays, factored OUT of `body`. That ZStack had
    /// reached the Swift type-checker's limit — adding even ONE more branch
    /// failed the build with "unable to type-check this expression in reasonable
    /// time". Anything new that draws over the canvas belongs in here, not inline.
    @ViewBuilder
    private func canvasOverlays(disp: CGSize, ref: CGFloat) -> some View {
            // Magic Eraser LIVE PREVIEW: magenta over exactly the pixels an Erase would
            // clear, over the active (visible) layer at its transform — tune by eye.
            if activeTool == .eraser, let idx = activeIndex,
               document.layers[idx].isVisible, let hi = pen.erasePreview {
                let t = document.layers[idx].transform
                Image(decorative: hi, scale: 1)
                    .interpolation(.low)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ref * t.scale, height: ref * t.scale)
                    .rotationEffect(.degrees(t.rotationDegrees))
                    .position(x: t.center.x * disp.width, y: t.center.y * disp.height)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
            // LIVE PREVIEW: the region a tap would flood (bucket, in the fill colour) or
            // clear (Magic Lasso, in red).
            if activeTool == .fill || activeTool == .magicLasso, let idx = activeIndex,
               document.layers[idx].isVisible, let hi = pen.bucketPreview {
                let t = document.layers[idx].transform
                Image(decorative: hi, scale: 1)
                    .interpolation(.low)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ref * t.scale, height: ref * t.scale)
                    .rotationEffect(.degrees(t.rotationDegrees))
                    .position(x: t.center.x * disp.width, y: t.center.y * disp.height)
                    .opacity(0.55)
                    .allowsHitTesting(false)
            }
            // ⚠️ ORDER MATTERS: THE DIMMING GOES UNDER THE BOX, NOT OVER IT.
            //
            // These two used to be the other way round, and the grab handles were being
            // painted over by the crop scrim. They still WORKED — CropOverlay is inert —
            // but they were washed out and looked absent. Michael, 2026-08-27, opening a
            // document straight after the crop fixes: "No grabbers".
            //
            // It was always the wrong z-order; it only became visible once the crop
            // started computing on appear, because before that `cropRect` was nil on open
            // and no scrim was ever drawn over a freshly opened document.
            //
            // A selection box belongs ABOVE a dimming layer. Always.
            if activeTool == .move, let crop = document.cropRect {
                CropOverlay(crop: crop, size: disp)
                    .allowsHitTesting(false)
            }
            if showTransformBox, let idx = activeIndex {
                TransformBox(document: document, index: idx, size: disp)
            }
            // MASK TOOL: the same dimming, but around a four-cornered mask you can grab.
            // The overlay is inert; the box on top of it owns every gesture. Its handles
            // move the MASK ONLY — the artwork is never touched, which is the whole reason
            // this is a separate tool from Move/Transform.
            if activeTool == .mask, document.cropMask != nil {
                let maskBinding = Binding<CropMask>(
                    get: { document.cropMask ?? CropMask(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)) },
                    set: { document.cropMask = $0 })
                MaskOverlay(mask: maskBinding.wrappedValue, size: disp)
                MaskBox(mask: maskBinding,
                        size: disp,
                        canvasPixels: CGSize(width: document.canvasWidth, height: document.canvasHeight),
                        mode: document.maskFreeCorners
                              ? .free
                              : (document.maskRatio.map { MaskCornerMode.ratio($0) } ?? .rectangle))
            }
            // Brush eraser footprint ring — follows the cursor so you see WHICH pixels
            // a stroke will clear before committing (no undo). Circle ring / square box.
            if activeTool == .eraser, pen.eraserMode == .brush, let hp = brushHover {
                BrushCursor(diameter: pen.eraserBrushFraction * ref, square: pen.eraserSquare)
                    .position(hp)
                    .allowsHitTesting(false)
            }
    }

    @ObservedObject var document: ImageDocument
    @Binding var activeLayerID: ImageLayer.ID?
    var showTransformBox: Bool = false
    var activeTool: Tool = .move
    @Binding var fillColor: Color
    /// Fit Width view: fill the given frame exactly (the frame is already shaped to the
    /// canvas aspect) instead of letterboxing the canvas inside a square area. The host
    /// frame supplies the aspect; here we just fill it so it can run taller than the
    /// viewport and scroll vertically.
    var fillFrame: Bool = false
    @EnvironmentObject var pen: PixelPen
    /// Live cursor position (in canvas space) for the brush-eraser footprint ring.
    @State private var brushHover: CGPoint?
    /// Live cursor position (canvas space) for the paint-bucket fill-region preview.
    @State private var bucketHover: CGPoint?
    /// The layer the Magic Lasso made on its first click, so later clicks keep editing it
    /// instead of stacking a new hidden layer per click.
    @State private var lassoLayerID: ImageLayer.ID?

    private var activeIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return document.layers.firstIndex(where: { $0.id == id })
    }

    /// The active content layer's current pixel raster (to seed the pen), if any.
    private var activePixelData: Data? {
        guard let idx = activeIndex else { return nil }
        return document.layers[idx].pixelData
    }

    /// Paint Bucket tap. BACKGROUND layer → solid fill (existing). CONTENT image layer →
    /// seeded FLOOD fill bounded by the lines, onto a NEW layer (non-destructive; original
    /// kept + hidden, same mantra as the other Applies — there's no undo).
    @MainActor private func bucketFill(atNormalized n: CGPoint, canvas: CGSize) {
        guard activeTool == .fill, let idx = activeIndex else { return }
        if document.layers[idx].backgroundRole != nil {
            document.captureHistoryBaselineIfNeeded()   // before the edit
            document.layers[idx].setBackgroundFill(fillColor.hexString())
            // History: solid background fill (the snapshot captures the layer's new fillHex).
            document.recordHistory(toolID: Tool.fill.rawValue,
                                   groupTitle: Tool.fill.title,
                                   actionLabel: "Fill Background",
                                   layerID: document.layers[idx].id)
            return
        }
        // A blank content layer: tapping a bucket on empty canvas should pour, not do
        // nothing. Michael: "i cant tap the paint drip choose a color and then tap a
        // (blank) area on the canvas".
        guard let png = activeImagePNG,
              let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            document.captureHistoryBaselineIfNeeded()
            if document.fillLayerSolid(at: idx, cgColor: fillColor.cgColorResolved) {
                document.recordHistory(toolID: Tool.fill.rawValue, groupTitle: Tool.fill.title,
                                       actionLabel: "Fill Layer", layerID: document.layers[idx].id)
            }
            return
        }
        let t = document.layers[idx].transform
        let canvasPt = CGPoint(x: n.x * canvas.width, y: n.y * canvas.height)
        guard let seed = imagePixel(forCanvasPoint: canvasPt, canvas: canvas, transform: t,
                                    imageW: cg.width, imageH: cg.height) else { return }
        let fc = fillColor.rgb8
        guard let filled = floodFilledImage(cg, seed: seed, tolerance: Int(pen.bucketTolerance),
                                            fill: (fc.r, fc.g, fc.b, 255)),
              let out = pngData(from: filled) else { return }
        document.captureHistoryBaselineIfNeeded()   // before the edit
        if let newID = document.addResultLayer(out, above: idx, nameSuffix: "filled"),
           let nIdx = document.layers.firstIndex(where: { $0.id == newID }) {
            document.layers[nIdx].transform = t
            activeLayerID = newID
            // History: flood fill adds a result layer + hides the source. The layer-stack
            // snapshot captures both, so step-back removes the result and re-shows the source.
            document.recordHistory(toolID: Tool.fill.rawValue,
                                   groupTitle: Tool.fill.title,
                                   actionLabel: "Fill",
                                   layerID: newID)
        }
        pen.clearBucketPreview()
    }

    /// **Magic Lasso** — click a region and the matching contiguous area is CLEARED, so the
    /// layer below shows through. Same seeded flood as the Paint Bucket, bounded by the same
    /// colour edges; it writes transparent instead of paint.
    ///
    /// Michael, 2026-08-20: this is the tool that finishes what Remove Background starts.
    /// Vision hands back the lighthouse *and the cliff it stands on* as one subject, because
    /// to the model they are one connected object. The lasso is how the cliff comes off.
    ///
    /// **Repeat clicks edit the SAME cutout layer.** Knocking out a sky, then an ocean, then a
    /// rock is three clicks, and the bucket's one-new-layer-per-tap idiom would leave three
    /// hidden layers behind for one job. The FIRST click makes the result layer (original kept
    /// and hidden, so it is still non-destructive); every click after that edits that layer in
    /// place. History records each click, so step-back still walks them one at a time.
    @MainActor private func lassoClear(atNormalized n: CGPoint, canvas: CGSize) {
        guard activeTool == .magicLasso, let idx = activeIndex else { return }
        guard document.layers[idx].backgroundRole == nil else { return }   // a solid background has nothing to lasso
        guard let png = activeImagePNG,
              let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let t = document.layers[idx].transform
        let canvasPt = CGPoint(x: n.x * canvas.width, y: n.y * canvas.height)
        guard let seed = imagePixel(forCanvasPoint: canvasPt, canvas: canvas, transform: t,
                                    imageW: cg.width, imageH: cg.height) else { return }
        // Clearing = flooding with premultiplied transparent.
        guard let cleared = floodFilledImage(cg, seed: seed, tolerance: Int(pen.lassoTolerance),
                                             fill: (0, 0, 0, 0)),
              let out = pngData(from: cleared) else { return }

        document.captureHistoryBaselineIfNeeded()   // before the edit

        if let lassoID = lassoLayerID, lassoID == activeLayerID,
           let li = document.layers.firstIndex(where: { $0.id == lassoID }) {
            document.layers[li].setImage(out)       // keep working on the layer we already made
            document.recordHistory(toolID: Tool.magicLasso.rawValue,
                                   groupTitle: Tool.magicLasso.title,
                                   actionLabel: "Lasso Clear",
                                   layerID: lassoID)
        } else if let newID = document.addResultLayer(out, above: idx, nameSuffix: "lassoed"),
                  let nIdx = document.layers.firstIndex(where: { $0.id == newID }) {
            document.layers[nIdx].transform = t     // the cutout stays exactly where the art was
            activeLayerID = newID
            lassoLayerID = newID
            document.recordHistory(toolID: Tool.magicLasso.rawValue,
                                   groupTitle: Tool.magicLasso.title,
                                   actionLabel: "Lasso Clear",
                                   layerID: newID)
        }
        pen.clearBucketPreview()
    }

    /// Recompute the bucket's fill-region highlight for the hovered seed (downscaled), or
    /// clear it. Region shown in the fill color. `force` recomputes when tolerance/color change.
    @MainActor private func refreshBucketPreview(canvas: CGSize, force: Bool = false) {
        let lassoing = activeTool == .magicLasso
        let c = fillColor.rgb8
        // The lasso highlights in red because it is showing what will be REMOVED. Painting
        // that region in the fill colour, the way the bucket does, would say the opposite.
        let hi: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) = lassoing ? (255, 59, 48, 255) : (c.r, c.g, c.b, 255)
        guard activeTool == .fill || lassoing, let hp = bucketHover, let idx = activeIndex,
              document.layers[idx].isVisible, document.layers[idx].backgroundRole == nil,
              let id = activeLayerID, let png = activeImagePNG else {
            pen.refreshBucketPreview(seed: nil, highlight: hi); return
        }
        pen.ensureBucketSource(png: png, layerKey: "\(id)-\(png.count)")
        let t = document.layers[idx].transform
        let seed = imagePixel(forCanvasPoint: hp, canvas: canvas, transform: t,
                              imageW: pen.bucketSourceW, imageH: pen.bucketSourceH)
        pen.refreshBucketPreview(seed: seed, highlight: hi, force: force,
                                 tolerance: lassoing ? pen.lassoTolerance : nil)
    }

    /// Eyedropper: render the active layer and sample its color (averaged over the
    /// sample circle) at a normalized canvas point into fillColor.
    @MainActor private func sampleEyedropper(at n: CGPoint) {
        guard activeTool == .eyedropper, let idx = activeIndex else { return }
        let solo = ImageDocument(name: document.name, canvasWidth: document.canvasWidth,
                                canvasHeight: document.canvasHeight,
                                layers: [document.layers[idx]], palette: document.palette, cropRect: nil)
        let renderer = ImageRenderer(content: ImageCompositeView(document: solo, size: document.canvasPixelSize))
        renderer.scale = 1
        if let cg = renderer.cgImage,
           let color = averagedColor(in: cg, atNormalized: n, radiusPixels: pen.eyedropperRadius) {
            // Gatekeeper: a sampled color must live in the palette — write it into the active
            // slot, which becomes the active color everywhere.
            fillColor = color
            pen.color = color
            if document.palette.indices.contains(pen.selectedSlot) {
                document.palette[pen.selectedSlot] = color.hexString() ?? document.palette[pen.selectedSlot]
                ImageDocument.lastUsedPalette = document.palette
            }
        }
    }

    /// The active content layer's image-element PNG (the Magic Eraser's source), if any.
    private var activeImagePNG: Data? {
        guard let idx = activeIndex else { return nil }
        for el in document.layers[idx].elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { return img.pngData }
        }
        return nil
    }

    /// Refresh the Magic Eraser's live highlight for the current tolerance/color/layer
    /// (or clear it when the Eraser isn't active on an image layer in MAGIC mode).
    @MainActor private func refreshEraserPreview() {
        guard activeTool == .eraser, pen.eraserMode == .magic,
              let id = activeLayerID, let png = activeImagePNG else {
            pen.clearErasePreview(); return
        }
        pen.refreshErasePreview(png: png, layerKey: "\(id)-\(png.count)", target: fillColor.rgb8)
    }

    /// Brush eraser (option b): the first stroke on a layer auto-duplicates it (original
    /// kept + hidden) and erases the COPY — with Cmd-Z off, the copy IS the undo. Maps the
    /// canvas point through the layer transform to the right image pixel, then clears a dab.
    @MainActor private func eraseAt(_ n: CGPoint, canvas: CGSize) {
        guard activeTool == .eraser, pen.eraserMode == .brush else { return }
        // Start a new erase session (a fresh copy) if we aren't already erasing the active layer.
        if pen.eraserWorkingLayerID != activeLayerID || !pen.hasEraseSession {
            guard let idx = activeIndex, let png = activeImagePNG else { return }
            document.captureHistoryBaselineIfNeeded()   // before the layer copy is made
            let srcTransform = document.layers[idx].transform
            guard let newID = document.addResultLayer(png, above: idx, nameSuffix: "erased"),
                  let nIdx = document.layers.firstIndex(where: { $0.id == newID }) else { return }
            document.layers[nIdx].transform = srcTransform   // copy sits exactly over the original
            activeLayerID = newID
            pen.startEraseSession(workingID: newID, png: png)
        }
        guard let wid = pen.eraserWorkingLayerID,
              let widx = document.layers.firstIndex(where: { $0.id == wid }) else { return }
        pen.eraserLiveLayerID = wid
        let t = document.layers[widx].transform
        let canvasPt = CGPoint(x: n.x * canvas.width, y: n.y * canvas.height)
        guard let px = imagePixel(forCanvasPoint: canvasPt, canvas: canvas, transform: t,
                                  imageW: pen.eraserImageW, imageH: pen.eraserImageH) else { return }
        let a = pen.eraserImageH > 0 ? Double(pen.eraserImageW) / Double(pen.eraserImageH) : 1.0
        let widthFactor = a >= 1 ? 1.0 : a   // scaledToFit limits on width for portrait images
        let radius = (pen.eraserBrushFraction * Double(pen.eraserImageW)) / (2 * max(0.01, t.scale) * widthFactor)
        pen.eraseBrush(atImagePixel: px, radius: radius, square: pen.eraserSquare)
    }

    /// Commit the live brush stroke back to the working copy's image element.
    @MainActor private func endEraseStroke() {
        guard pen.eraserMode == .brush, let wid = pen.eraserWorkingLayerID,
              let widx = document.layers.firstIndex(where: { $0.id == wid }),
              let png = pen.endEraseStroke() else { pen.eraserLiveLayerID = nil; return }
        document.layers[widx].setImage(png)
        // History: each committed brush-erase stroke = one "Erase" step under the Eraser group.
        document.recordHistory(toolID: Tool.eraser.rawValue, groupTitle: Tool.eraser.title,
                               actionLabel: "Erase", layerID: document.layers[widx].id)
        pen.eraserLiveLayerID = nil
    }

    /// Text tool: tap the canvas to start a new text layer AT that spot (approximate is fine).
    /// Creates an empty text layer there and selects it; the Text inspector adopts it so what
    /// you type fills it. (Michael 2026-06-22: tap gives the natural starting point.)
    @MainActor private func startTextAt(_ n: CGPoint) {
        guard activeTool == .text else { return }
        var layer = ImageLayer(name: "Text", role: .content)
        layer.setText("", fontName: "Helvetica", tintHex: pen.color.hexString() ?? "#000000")
        layer.transform.center = CGPoint(x: min(max(n.x, 0), 1), y: min(max(n.y, 0), 1))
        document.layers.append(layer)
        activeLayerID = layer.id
    }

    var body: some View {
        GeometryReader { geo in
            // The canvas can be non-square (B2). Fit its aspect inside the available square
            // area → the on-screen display rect `disp`. `ref` = the shorter display edge, used
            // for element sizing so a square canvas reduces to exactly the old `side` math.
            let disp = displayRect(in: geo.size)
            let ref = min(disp.width, disp.height)
            ZStack {
                Checkerboard()
                // Non-destructive canvas mask: content past the canvas is GHOSTED (dimmed,
                // unclipped) so you can still see + position it; then drawn CRISP clipped to
                // the canvas rect. What shows inside the rect = what exports.
                layerStack(size: disp)
                    .opacity(0.25)
                layerStack(size: disp)
                    .frame(width: disp.width, height: disp.height)
                    .clipped()
                // Live pen stroke (the active layer's in-progress raster), kept crisp.
                if activeTool == .pen, let img = pen.image {
                    Image(decorative: img, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: disp.width, height: disp.height)
                        .allowsHitTesting(false)
                }
                // Pixel grid overlay for the active layer's resolution.
                if activeTool == .pen, pen.showGrid {
                    PixelGrid(resolution: pen.resolution)
                        .frame(width: disp.width, height: disp.height)
                        .allowsHitTesting(false)
                }
                canvasOverlays(disp: disp, ref: ref)
            }
            .frame(width: disp.width, height: disp.height)
            .coordinateSpace(name: "canvas")
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
            .overlay {
                // macOS: right-click erases a pixel without flipping the Draw/Erase mode;
                // left-clicks fall through to the SwiftUI draw gesture below.
                #if os(macOS)
                if activeTool == .pen, activeIndex != nil {
                    RightClickEraser(
                        onErase: { n in pen.erase(toNormalized: n) },
                        onEnded: {
                            pen.endStroke()
                            if let data = pen.currentPNG() {
                                // History: right-click erase is a Pen-group Erase action.
                                commitPenPixels(data, actionLabel: "Erase")
                            }
                        }
                    )
                }
                #endif
            }
            .contentShape(Rectangle())
            .gesture(
                // One gesture for both Pen (draw) and Fill (pour). minimumDistance 0 so a
                // TAP fires onChanged → a single pixel; a drag paints a trail.
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        let n = CGPoint(x: value.location.x / disp.width, y: value.location.y / disp.height)
                        if activeTool == .eraser, pen.eraserMode == .brush {
                            brushHover = value.location   // ring follows the finger/cursor mid-stroke too
                            eraseAt(n, canvas: disp); return
                        }
                        guard activeTool == .pen, activeIndex != nil else { return }
                        if pen.erasing { pen.erase(toNormalized: n) } else { pen.stroke(toNormalized: n) }
                    }
                    .onEnded { value in
                        switch activeTool {
                        case .pen:
                            pen.endStroke()
                            if let data = pen.currentPNG() {
                                // History: one stroke = one action under the Pen group.
                                commitPenPixels(data, actionLabel: pen.erasing ? "Erase" : "Stroke")
                            }
                        case .fill:
                            bucketFill(atNormalized: CGPoint(x: value.location.x / disp.width, y: value.location.y / disp.height), canvas: disp)
                        case .magicLasso:
                            lassoClear(atNormalized: CGPoint(x: value.location.x / disp.width, y: value.location.y / disp.height), canvas: disp)
                        case .eyedropper:
                            sampleEyedropper(at: CGPoint(x: value.location.x / disp.width, y: value.location.y / disp.height))
                        case .eraser:
                            if pen.eraserMode == .brush { endEraseStroke() }
                        case .text:
                            startTextAt(CGPoint(x: value.location.x / disp.width, y: value.location.y / disp.height))
                        default:
                            break
                        }
                    },
                including: (activeTool == .pen || activeTool == .fill || activeTool == .eyedropper
                            || activeTool == .magicLasso
                            || activeTool == .text
                            || (activeTool == .eraser && pen.eraserMode == .brush)) ? .all : .subviews
            )
            .modifier(ToolPointer(tool: activeTool))   // cursor reflects the active tool (macOS)
            // The production preview, floating over the canvas and visible with ANY
            // tool active — which is the whole point (R2: it updates as each pixel
            // is drawn, so hiding it inside the Zoom inspector made it invisible
            // exactly when it was needed). Overlaid AFTER the canvas gestures so its
            // own drag-to-corner wins. See FatBits.swift.
            .onContinuousHover(coordinateSpace: .named("canvas")) { phase in
                // Trackpad/pointer hover (no press) → position the footprint ring so you can
                // aim before committing. Touch has no hover; the mid-stroke update covers that.
                switch phase {
                case .active(let loc):
                    if activeTool == .eraser, pen.eraserMode == .brush { brushHover = loc }
                    if activeTool == .fill { bucketHover = loc; refreshBucketPreview(canvas: disp) }
                case .ended:
                    brushHover = nil
                    if activeTool == .fill { bucketHover = nil; refreshBucketPreview(canvas: disp) }
                }
            }
            .onAppear {
                if activeTool == .pen { pen.load(activePixelData) }
                refreshEraserPreview()
            }
            .onChange(of: activeTool) {
                if activeTool == .pen { pen.load(activePixelData) }
                if activeTool != .eraser { pen.endEraseSession() }   // leaving the tool drops the copy session
                if activeTool != .fill && activeTool != .magicLasso { bucketHover = nil; pen.clearBucketPreview() }
                refreshEraserPreview()
            }
            .onChange(of: activeLayerID) {
                // NB: don't end the brush session here — eraseAt() sets activeLayerID itself when it
                // makes the copy, which would wipe the session we just started. A manual layer switch
                // is handled by eraseAt's "working != active → new copy" check on the next stroke.
                if activeTool == .pen { pen.load(activePixelData) }
                refreshEraserPreview()
                refreshBucketPreview(canvas: disp)
            }
            .onChange(of: pen.eraserMode) {
                if pen.eraserMode != .brush { pen.endEraseSession() }
                refreshEraserPreview()
            }
            .onChange(of: pen.eraseTolerance) { refreshEraserPreview() }
            .onChange(of: pen.eraseContiguous) { refreshEraserPreview() }
            .onChange(of: pen.bucketTolerance) { refreshBucketPreview(canvas: disp, force: true) }
            .onChange(of: pen.lassoTolerance) { refreshBucketPreview(canvas: disp, force: true) }
            .onChange(of: fillColor) {
                if activeTool == .eraser { refreshEraserPreview() }
                if activeTool == .fill { refreshBucketPreview(canvas: disp, force: true) }
            }
            .onChange(of: pen.resolution) {
                guard activeTool == .pen else { return }
                // Resolution locks once a layer has pixels — changing it starts a NEW
                // pixel layer at the chosen resolution rather than altering the old art.
                if let i = activeIndex, document.layers[i].pixelData != nil {
                    let layer = ImageLayer(name: "Pixels @\(pen.resolution)", role: .content)
                    document.layers.append(layer)
                    activeLayerID = layer.id
                }
                pen.load(nil)   // fresh blank bitmap at the new resolution
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // center in the area
        }
    }

    /// The on-screen canvas rect for the available area. Fit Width (`fillFrame`) fills the
    /// frame, which the host already shaped to the canvas aspect; otherwise the canvas is
    /// letterboxed to fit inside the square area (a square canvas reduces to the old math).
    private func displayRect(in size: CGSize) -> CGSize {
        if fillFrame { return size }
        let aspect = CGFloat(document.canvasWidth) / CGFloat(max(1, document.canvasHeight))
        let avail = min(size.width, size.height)
        return aspect >= 1
            ? CGSize(width: avail, height: avail / aspect)
            : CGSize(width: avail * aspect, height: avail)
    }

    /// What a layer draws on the canvas. A filled background renders its colour;
    /// a content layer renders its elements at the layer's transform. (Most
    /// element kinds wait for their tools; `symbol` renders now so the TEST-ONLY
    /// shakedown star is visible for the Move/Transform tool.)
    /// All visible layers composited — used twice (ghosted bleed + clipped crisp icon).
    @ViewBuilder
    private func layerStack(size: CGSize) -> some View {
        ZStack {
            ForEach(document.layers) { layer in
                if layer.isVisible { layerContent(layer, size: size) }
            }
        }
    }

    @ViewBuilder
    private func layerContent(_ layer: ImageLayer, size: CGSize) -> some View {
        switch layer.role {
        case .background(_, let fillHex):
            // A filled background fills the whole canvas rect — also the letterbox margin
            // when the canvas is non-square and content scales-to-fit inside it.
            if let hex = fillHex, let color = Color(hex: hex) {
                color
            }
        case .content:
            // While a brush stroke is live on this layer, render its working bitmap (with the
            // erased holes) instead of the stored element, so transparency shows immediately.
            if layer.id == pen.eraserLiveLayerID, let live = pen.eraserImage {
                liveImageView(live, transform: layer.transform, size: size)
            } else {
                ForEach(layer.elements) { element in
                    elementView(element, transform: layer.transform, size: size)
                }
            }
        }
    }

    /// The live brush-eraser bitmap drawn exactly like an image element (same frame /
    /// scaledToFit / rotation / position), so it sits over the layer pixel-aligned.
    @ViewBuilder
    private func liveImageView(_ cg: CGImage, transform t: LayerTransform, size: CGSize) -> some View {
        let ref = min(size.width, size.height)
        Image(decorative: cg, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(width: ref * t.scale, height: ref * t.scale)
            .rotationEffect(.degrees(t.rotationDegrees))
            .position(x: t.center.x * size.width, y: t.center.y * size.height)
    }

    @ViewBuilder
    private func elementView(_ element: LayerElement,
                             transform t: LayerTransform,
                             size: CGSize) -> some View {
        // Element sizing uses the shorter canvas edge (`ref`) so content scales-to-fit and
        // letterboxes on a non-square canvas; positioning uses the full width/height.
        let ref = min(size.width, size.height)
        switch element.content {
        case .symbol(let symbol):
            Image(systemName: symbol.systemName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: symbol.tintHex) ?? .primary)
                .frame(width: ref * t.scale, height: ref * t.scale)
                .rotationEffect(.degrees(t.rotationDegrees))
                .position(x: t.center.x * size.width, y: t.center.y * size.height)
        case .text(let text):
            Text(text.string)
                // Model B: text FILLS its box (the Move transform box = center + contentSize).
                // Font starts at the box height; the text wraps to the box WIDTH and scales
                // down (minimumScaleFactor) so the whole string fits the rectangle. Reshape
                // the box → text re-wraps AND re-sizes. Box defaults to the full canvas.
                .font(.custom(text.fontName, size: max(1, t.contentSize.height * ref)))
                .bold(text.bold)
                .italic(text.italic)
                .underline(text.underline)
                .foregroundStyle(Color(hex: text.colorHex) ?? .primary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .minimumScaleFactor(0.01)
                .frame(width: max(1, t.contentSize.width * ref),
                       height: max(1, t.contentSize.height * ref))
                .rotationEffect(.degrees(t.rotationDegrees))
                .position(x: t.center.x * size.width, y: t.center.y * size.height)
        case .image(let imageContent):
            if let platformImage = PlatformImage(data: imageContent.pngData) {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ref * t.scale, height: ref * t.scale)
                    .rotationEffect(.degrees(t.rotationDegrees))
                    .position(x: t.center.x * size.width, y: t.center.y * size.height)
            }
        case .pixels(let pixels):
            if let platformImage = PlatformImage(data: pixels.pngData) {
                Image(platformImage: platformImage)
                    .interpolation(.none)   // crisp blocks when a low-res layer scales up
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }
        }
    }

}

/// The draggable transform box for the active layer (Move tool). Reflects the
/// layer's transform (center / scale / rotation). Drag GRABS and moves RELATIVE
/// to the start, so a tap doesn't jump the layer — only a real drag moves it
/// (Michael 2026-06-11: "it moves when touched").
struct TransformBox: View {
    @ObservedObject var document: ImageDocument
    let index: Int
    let size: CGSize
    @State private var startCenter: CGPoint?
    @State private var startAnchor: CGPoint?

    /// Unit offsets of the four corners from the box center.
    private let corners: [CGSize] = [
        CGSize(width: -1, height: -1), CGSize(width: 1, height: -1),
        CGSize(width: -1, height: 1),  CGSize(width: 1, height: 1),
    ]

    /// The grabber you SEE, and the target you can actually hit. Michael could not
    /// grab a corner (fix-list C) partly because a 14pt square sitting exactly on the
    /// canvas corner offers ~7pt of reachable area. The visual stays 14; the touch
    /// target is 30 and invisible, so the handle looks the same and catches far more.
    private let grabVisual: CGFloat = 14
    private let grabTarget: CGFloat = 30

    var body: some View {
        // Guard: the active layer can be deleted while this box is still mounted,
        // leaving `index` pointing past the end of the array for one update pass.
        if index >= 0, index < document.layers.count {
            let layer = document.layers[index]
            let t = layer.transform
            let isText = layer.textString != nil
            let ref = min(size.width, size.height)
            // The square the canvas draws this layer into.
            let side = ref * t.scale
            let squareCenter = CGPoint(x: t.center.x * size.width, y: t.center.y * size.height)

            // WHERE THE ART IS. A layer's transform describes a square; the picture
            // inside it may be a small object floating in transparency — a Remove
            // Background cutout keeps the layer's full size on purpose, so the square
            // is the whole canvas while the subject is a lighthouse in the middle.
            // Michael, 2026-08-21: "the selection was the full layer size and not the
            // lighthouse pixels." Hug the opaque pixels, and the grabbers land ON the
            // object instead of orphaned at the canvas corners (fix-list C and D).
            //
            // Fallback when there is nothing raster to measure (symbol, text, an empty
            // layer): the whole square honouring contentAspect — exactly the old box.
            let art = layer.artUnitRect ?? {
                let cs = t.contentSize                       // fractions of `ref`
                let w = t.scale > 0 ? cs.width / t.scale : 1  // → fractions of the square
                let h = t.scale > 0 ? cs.height / t.scale : 1
                return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
            }()

            let boxW = max(24, art.width * side)
            let boxH = max(24, art.height * side)
            let radians = t.rotationDegrees * .pi / 180
            // The art's centre is offset from the square's centre whenever the picture
            // does not sit dead centre in its layer — and that offset rotates with it.
            let center = squareCenter.offsetBy(
                rotate(CGSize(width: (art.midX - 0.5) * side,
                              height: (art.midY - 0.5) * side), by: radians))

            // The movable box.
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(Color.accentColor.opacity(0.06))
                .frame(width: boxW, height: boxH)
                .rotationEffect(.degrees(t.rotationDegrees))
                .position(center)
                .contentShape(Rectangle())
                // minimumDistance:6 (was 0) so a touch that lands on a corner grabber
                // isn't stolen by this move gesture on touch-down — the frontmost handle
                // gets first claim, fixing the top-left corner that used to move instead
                // of resize.
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            guard index < document.layers.count else { return }
                            let start = startCenter ?? document.layers[index].transform.center
                            if startCenter == nil { startCenter = start }
                            let nx = min(max(start.x + value.translation.width / size.width, 0), 1)
                            let ny = min(max(start.y + value.translation.height / size.height, 0), 1)
                            document.layers[index].transform.center = CGPoint(x: nx, y: ny)
                        }
                        .onEnded { _ in startCenter = nil }
                )

            // Corner grabbers — drag to scale (aspect-locked, around the center).
            ForEach(Array(corners.enumerated()), id: \.offset) { _, off in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: grabVisual, height: grabVisual)
                    .frame(width: grabTarget, height: grabTarget)   // invisible margin
                    .contentShape(Rectangle())
                    .position(center.offsetBy(
                        rotate(CGSize(width: off.width * boxW / 2,
                                      height: off.height * boxH / 2), by: radians)))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                guard index < document.layers.count else { return }
                                if isText {
                                    // Text = RECT-RESIZE: the OPPOSITE corner is the anchor,
                                    // the dragged corner follows the finger. Sets the box's
                                    // center + width + height (via scale + contentAspect) — so
                                    // width drives wrap and height drives the fit area.
                                    let anchor = startAnchor ?? CGPoint(x: center.x - off.width * boxW / 2,
                                                                        y: center.y - off.height * boxH / 2)
                                    if startAnchor == nil { startAnchor = anchor }
                                    let dx = min(max(value.location.x, 0), size.width)
                                    let dy = min(max(value.location.y, 0), size.height)
                                    let wPts = max(abs(dx - anchor.x), 12)
                                    let hPts = max(abs(dy - anchor.y), 12)
                                    let nW = Double(wPts / ref)
                                    let nH = Double(hPts / ref)
                                    document.layers[index].transform.center = CGPoint(
                                        x: min(max((anchor.x + dx) / 2 / size.width, 0), 1),
                                        y: min(max((anchor.y + dy) / 2 / size.height, 0), 1))
                                    document.layers[index].transform.scale = min(max(max(nW, nH), 0.05), 4.0)
                                    document.layers[index].transform.contentAspect = min(max(nW / nH, 0.05), 20)
                                } else {
                                    // Non-text = uniform aspect-locked scale, about the layer's
                                    // own centre (which is what `scale` means).
                                    //
                                    // The grabbed corner sits at  squareCenter + scale * v,
                                    // where v is fixed by which corner it is and where the art
                                    // sits in the layer. So the scale that puts that corner
                                    // nearest the pointer is the projection of the drag onto v.
                                    // Solving it this way keeps the corner under the pointer
                                    // even when the art is off-centre in its layer — the old
                                    // max(|dx|,|dy|) assumed the box was the whole square.
                                    let v = rotate(CGSize(
                                        width: (art.midX - 0.5 + off.width * art.width / 2) * ref,
                                        height: (art.midY - 0.5 + off.height * art.height / 2) * ref),
                                                   by: radians)
                                    let vv = v.width * v.width + v.height * v.height
                                    let newScale: Double
                                    if vv > 0.0001 {
                                        let dx = value.location.x - squareCenter.x
                                        let dy = value.location.y - squareCenter.y
                                        newScale = (dx * v.width + dy * v.height) / vv
                                    } else {
                                        // Degenerate (no measurable art): the old behaviour.
                                        let half = max(abs(value.location.x - squareCenter.x),
                                                       abs(value.location.y - squareCenter.y))
                                        newScale = (half * 2) / ref
                                    }
                                    document.layers[index].transform.scale = min(max(newScale, 0.1), 4.0)
                                }
                            }
                            .onEnded { _ in startAnchor = nil }
                    )
            }
        }
    }

    /// Rotate an offset by `radians` (screen space: y grows downward).
    private func rotate(_ s: CGSize, by radians: Double) -> CGSize {
        guard radians != 0 else { return s }
        let c = cos(radians), sn = sin(radians)
        return CGSize(width: s.width * c - s.height * sn,
                      height: s.width * sn + s.height * c)
    }
}

private extension CGPoint {
    func offsetBy(_ s: CGSize) -> CGPoint { CGPoint(x: x + s.width, y: y + s.height) }
}

/// Dims the canvas outside the crop rectangle (Photos-style) so you can see what
/// export/share will keep. Visual only in v1 — the crop is sized from the inspector's
/// aspect picker + size slider (draggable handles for Freeform = later).
struct CropOverlay: View {
    let crop: CGRect    // normalized (0…1, top-left origin)
    let size: CGSize

    var body: some View {
        let r = CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                       width: crop.width * size.width, height: crop.height * size.height)
        let dim = Color.black.opacity(0.45)
        ZStack(alignment: .topLeading) {
            dim.frame(width: size.width, height: max(0, r.minY))                       // top band
            dim.frame(width: size.width, height: max(0, size.height - r.maxY))         // bottom band
                .offset(y: r.maxY)
            dim.frame(width: max(0, r.minX), height: r.height)                         // left band
                .offset(y: r.minY)
            dim.frame(width: max(0, size.width - r.maxX), height: r.height)            // right band
                .offset(x: r.maxX, y: r.minY)
            // Crop border = MARCHING ANTS. A crop rect IS a selection, and this is
            // the one place in the app that already had a plain outline waiting for
            // them. The white/black double stroke reads over any artwork underneath
            // without knowing what it is — see MarchingAnts.swift for where the
            // trick comes from (a Hamm's beer sign, via Bill Atkinson).
            MarchingAnts(shape: Rectangle())
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Standard image-editor transparency checkerboard.
struct Checkerboard: View {
    var squareSize: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<max(rows, 1) {
                for col in 0..<max(cols, 1) where (row + col) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(col) * squareSize,
                                      y: CGFloat(row) * squareSize,
                                      width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.28)))
                }
            }
        }
        .background(Color(white: 0.97))
    }
}

// MARK: - Layer panel

/// The layer list. Shown TOP-of-stack first (the array is bottom-to-top, so the
/// display is reversed). Tap a row to make that layer ACTIVE (highlighted). Each
/// row: kind badge + editable name + eyeball; reorder is always-on (edit mode);
/// rename is via the row's context menu. `showsHeader` is false inside the
/// portrait swipe panel (the segmented control already labels it "Layers").
struct LayerPanel: View {
    @ObservedObject var document: ImageDocument
    var showsHeader: Bool = true
    @Binding var activeLayerID: ImageLayer.ID?
    @State private var renamingID: ImageLayer.ID?
    /// Which groups are folded shut, keyed by base name. VIEW STATE ONLY — never
    /// saved, never sent to the document; closing a group changes nothing about the art.
    @State private var collapsedGroups: Set<String> = []
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: title (when shown) + the always-present "+" to add a layer
            // (L3 — top-right add). In the portrait swipe panel the segmented control
            // already says "Layers", so the title is hidden but the "+" stays.
            HStack {
                if showsHeader { Text("Layers").font(.headline) }
                Spacer()
                Button { addLayer() } label: {
                    Image(systemName: "plus").font(.headline)
                }
                .buttonStyle(.plain)
                .help("Add a layer")
                .accessibilityLabel("Add a layer")
            }
            .padding(.horizontal)
            .padding(.vertical, showsHeader ? 10 : 6)
            Divider()
            #if os(macOS)
            // macOS: List selection = click-to-activate; .onMove = drag-to-reorder.
            // You just drag a row (no edit-mode handles on macOS). The row must NOT be a
            // Button, or it would swallow the drag before .onMove sees it.
            List(selection: $activeLayerID) {
                layerRows().onMove(perform: move).onDelete(perform: deleteAt)
            }
            .listStyle(.plain)
            #else
            // iOS: always-on edit mode gives explicit drag handles; the row Button activates.
            List {
                layerRows().onMove(perform: move).onDelete(perform: deleteAt)
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            #endif
        }
        .alert("Rename Layer", isPresented: isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { renamingID = nil }
            Button("Rename") { commitRename() }
        }
    }

    /// The layer rows (reversed = top-of-stack first). Returns DynamicViewContent so
    /// `.onMove`/`.onDelete` attach; `.tag` wires each row to List selection on macOS.
    ///
    /// Iterates `visibleRows`, NOT `document.layers` — a collapsed group contributes only
    /// its topmost member. Every index handed to `.onMove`/`.onDelete` is therefore an
    /// index into `visibleRows`, and both functions translate through ids rather than
    /// positions because of it.
    private func layerRows() -> some DynamicViewContent {
        let groups = rowGroups
        return ForEach(visibleRows) { layer in
            LayerRow(
                layer: layer,
                isActive: layer.id == activeLayerID,
                groupBase: collapsibleBase(for: layer, in: groups),
                isCollapsed: collapsibleBase(for: layer, in: groups).map { collapsedGroups.contains($0) } ?? false,
                hiddenCount: hiddenCount(for: layer, in: groups),
                onToggleGroup: {
                    guard let base = collapsibleBase(for: layer, in: groups) else { return }
                    if collapsedGroups.contains(base) { collapsedGroups.remove(base) }
                    else { collapsedGroups.insert(base) }
                },
                onActivate: { activeLayerID = layer.id },
                onToggleVisibility: { toggleVisibility(layer.id) },
                onRename: { beginRename(layer) },
                onDuplicate: { duplicate(layer.id) },
                onDelete: { delete(layer.id) }
            )
            .tag(layer.id)
            .listRowBackground(layer.id == activeLayerID
                               ? Color.accentColor.opacity(0.15) : nil)
        }
    }

    // MARK: - Reveal caret (display only)
    //
    // Michael, 2026-08-25: "can layers have a reveal carrot? … i make a pixel per layer
    // instead of having 100 new layers the parentesis are hidden behind the reveal
    // carrot with the top most layer only showing" — then generalised it: "that logic
    // can be for all tools that make new layers."
    //
    // ⭐ THE APP ALREADY ENCODED PARENTAGE IN THE NAMES. Every derived layer is
    // `base (suffix)`: addResultLayer builds "\(name) (\(suffix))" and the pen's fork
    // builds "\(base) (Pixel \(k))". Live suffixes: Pixel N, cropped, filled, lassoed,
    // erased. So grouping needs NO new data model and NO change to the saved file.
    //
    // ⚠️ THIS IS A VIEW OF THE ARRAY, NOT A STRUCTURE IN IT. Nothing is stored, the
    // stacking order is never rewritten, and compositing never sees any of it. A group is
    // recomputed from scratch every render.
    //
    // ⚠️ CONTIGUOUS RUNS ONLY. Two layers sharing a base name but separated by an
    // unrelated layer are NOT grouped — folding them together would draw a stack order
    // that isn't the real one, and the list must never lie about z-order.

    /// A run of adjacent rows sharing a base name. `base` is nil for a row that belongs
    /// to no group, which is most of them.
    struct LayerRowGroup {
        let base: String?
        let members: [ImageLayer]   // top-first, same order as the list
    }

    /// `"Foreground (Pixel 7)"` → `"Foreground"`. Nil when the name has no parenthetical
    /// suffix, i.e. the layer was not produced from another layer.
    static func derivedBase(of name: String) -> String? {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return nil }
        let base = name[name.startIndex..<open].trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? nil : base
    }

    /// The stack, top-first, cut into contiguous runs. A run is one or more derived
    /// children sharing a base, plus the parent of that same name when it sits directly
    /// below them — which is where `addResultLayer` puts it.
    var rowGroups: [LayerRowGroup] {
        let topFirst = Array(document.layers.reversed())
        var groups: [LayerRowGroup] = []
        var i = 0
        while i < topFirst.count {
            guard let base = Self.derivedBase(of: topFirst[i].name) else {
                groups.append(LayerRowGroup(base: nil, members: [topFirst[i]]))
                i += 1
                continue
            }
            var run = [topFirst[i]]
            var j = i + 1
            while j < topFirst.count, Self.derivedBase(of: topFirst[j].name) == base {
                run.append(topFirst[j]); j += 1
            }
            // The source layer itself, sitting immediately under its children.
            if j < topFirst.count, topFirst[j].name == base {
                run.append(topFirst[j]); j += 1
            }
            // A lone child with no siblings and no parent present is not worth a caret.
            groups.append(LayerRowGroup(base: run.count > 1 ? base : nil, members: run))
            i = j
        }
        return groups
    }

    /// What the list actually shows: a collapsed group folds down to its topmost member.
    var visibleRows: [ImageLayer] {
        rowGroups.flatMap { group -> [ImageLayer] in
            guard let base = group.base, collapsedGroups.contains(base),
                  let first = group.members.first else { return group.members }
            return [first]
        }
    }

    /// The group base for a row that can carry a caret — only the group's TOP row does.
    private func collapsibleBase(for layer: ImageLayer, in groups: [LayerRowGroup]) -> String? {
        for g in groups where g.base != nil && g.members.first?.id == layer.id { return g.base }
        return nil
    }

    /// How many rows are folded away behind this row's caret.
    private func hiddenCount(for layer: ImageLayer, in groups: [LayerRowGroup]) -> Int {
        for g in groups where g.members.first?.id == layer.id { return max(0, g.members.count - 1) }
        return 0
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renamingID != nil },
                set: { if !$0 { renamingID = nil } })
    }

    private func beginRename(_ layer: ImageLayer) {
        draftName = layer.name
        renamingID = layer.id
    }

    private func commitRename() {
        defer { renamingID = nil }
        guard let id = renamingID,
              let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // ONE-WAY (Michael 2026-07-12, supersedes the 2026-06-22 two-way link): a
            // manual rename only sets the label and NEVER writes back to the canvas text.
            // It also SEVERS the text→name auto-mirror, so from now on this layer's name is
            // frozen and independent — typing new text won't rename it. (This is why
            // renaming an emoji/text layer can no longer corrupt its glyph.)
            document.layers[index].name = trimmed
            document.layers[index].nameLinkedToText = false
        }
    }

    private func toggleVisibility(_ id: ImageLayer.ID) {
        if let index = document.layers.firstIndex(where: { $0.id == id }) {
            document.layers[index].isVisible.toggle()
        }
    }

    /// L3 — add a new blank content layer on TOP of the stack, and select it.
    private func addLayer() {
        let layer = ImageLayer(name: "Layer \(document.layers.count + 1)", role: .content)
        document.layers.append(layer)          // end of array = top of the visual stack
        activeLayerID = layer.id
    }

    /// L4.1 — exact copy (fill/elements, transform, opacity, visibility), named
    /// "<name> copy," new UUID, inserted directly ABOVE the original, selected.
    private func duplicate(_ id: ImageLayer.ID) {
        guard let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        var copy = document.layers[i]
        copy.id = UUID()
        copy.name = document.layers[i].name + " copy"
        document.layers.insert(copy, at: i + 1)   // i+1 = one step toward the top
        activeLayerID = copy.id
    }

    /// L4/L5 — delete a layer (context menu).
    private func delete(_ id: ImageLayer.ID) {
        document.layers.removeAll { $0.id == id }
        if activeLayerID == id { activeLayerID = nil }
    }

    /// L5 — swipe-to-delete. Offsets index into the reversed (top-first) display,
    /// so map them back to layer ids before removing.
    /// Offsets index `visibleRows`, so a collapsed group's row deletes only the member
    /// being shown — the next one down simply becomes the new representative. Nothing
    /// hidden is deleted by a gesture aimed at something visible.
    private func deleteAt(_ offsets: IndexSet) {
        let rows = visibleRows
        let ids = offsets.compactMap { $0 < rows.count ? rows[$0].id : nil }
        document.layers.removeAll { ids.contains($0.id) }
        if let active = activeLayerID, ids.contains(active) { activeLayerID = nil }
    }

    /// The list shows the stack reversed (top-first), so reorder in that reversed space
    /// and write the un-reversed result back to the bottom-to-top array.
    ///
    /// Offsets index `visibleRows`, which may be shorter than the stack, so the move is
    /// resolved by IDENTITY rather than position: find what the drop should land above,
    /// pull the dragged layers out of the full array, and put them back in front of it.
    /// Dragging a collapsed group's row moves just that layer — the run stops being
    /// contiguous and the grouping simply recomputes, because the grouping was never
    /// stored in the first place.
    private func move(from source: IndexSet, to destination: Int) {
        let rows = visibleRows
        let movingIDs = Set(source.compactMap { $0 < rows.count ? rows[$0].id : nil })
        guard !movingIDs.isEmpty else { return }
        let anchorID = destination < rows.count ? rows[destination].id : nil

        var topFirst = Array(document.layers.reversed())
        let moving = topFirst.filter { movingIDs.contains($0.id) }
        topFirst.removeAll { movingIDs.contains($0.id) }
        let insertAt = anchorID.flatMap { id in topFirst.firstIndex { $0.id == id } } ?? topFirst.count
        topFirst.insert(contentsOf: moving, at: insertAt)
        document.layers = topFirst.reversed()
    }
}

struct LayerRow: View {
    let layer: ImageLayer
    let isActive: Bool
    /// Non-nil only on the TOP row of a collapsible run — that row owns the caret.
    var groupBase: String? = nil
    var isCollapsed: Bool = false
    /// How many rows are folded away behind the caret.
    var hiddenCount: Int = 0
    var onToggleGroup: () -> Void = {}
    let onActivate: () -> Void
    let onToggleVisibility: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // THE REVEAL CARET. Only a run's top row gets one. It is a Button, not a tap
            // gesture on the row, so it cannot be swallowed by List selection on macOS or
            // by .onMove's drag — the same reason the row itself must not be a Button.
            if groupBase != nil {
                Button(action: onToggleGroup) {
                    Image(systemName: isCollapsed ? "chevron.forward" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)      // a real target, not a 13pt glyph
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                // Keep ungrouped rows aligned with grouped ones.
                Color.clear.frame(width: 22, height: 1)
            }
            #if os(macOS)
            // macOS: plain label — List selection handles click-to-activate and .onMove
            // handles drag-to-reorder. A row-wide Button would eat the drag.
            HStack(spacing: 10) {
                Image(systemName: layer.displaySymbolName)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(layer.name)
                    .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .contentShape(Rectangle())
            #else
            // iOS: tapping the badge/name area selects (activates) the layer.
            Button(action: onActivate) {
                HStack(spacing: 10) {
                    Image(systemName: layer.displaySymbolName)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(layer.name)
                        .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #endif

            // How many rows are folded away. Shown only while shut — the point of the
            // count is to say what you cannot see, so it would be noise when open.
            if isCollapsed, hiddenCount > 0 {
                Text("\(hiddenCount)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }

            // VISIBILITY EYE. Michael, 2026-09-02: "the show hide layer eyes are too
            // faint and hard to distinguish. can you bold them and use color to
            // indecate visable or hidden with a slash?"
            //
            // The old pair was an outline `eye` in `.primary` vs an outline `eye.slash`
            // in `.secondary` — two thin glyphs separated mainly by OPACITY, which is
            // the one difference that disappears first at a glance or at distance.
            //
            // Three signals now, so none of them has to carry it alone: the SHAPE
            // (slash or no slash), the WEIGHT (filled and bold, not hairline), and the
            // COLOUR (green on, red off). Colour is reinforcement rather than the
            // meaning — the slash still says it on its own for anyone who cannot
            // separate red from green.
            Button(action: onToggleVisibility) {
                Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(layer.isVisible ? Color.green : Color.red)
                    .frame(width: 32, height: 26)   // a target worth aiming at
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Visible — click to hide" : "Hidden — click to show")
            .accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Scale slider graduations

/// The marks under the Scale slider. DRAWN ONLY — they are guides, never stops.
///
/// Michael, 2026-09-02: "i want gradiens but NO snap. i want gradians 1.5 2 2.5 3" and
/// then "i want the gradians on the left to have a minus." So the track shows where the
/// round numbers are and the thumb slides straight through them; there is no `step:` on
/// the Slider and there is no snapping anywhere in this file.
///
/// A minus mark means DIVISION, mirroring the plus side: -2 is half size, -3 a third.
/// That is why the left and right marks sit at mirrored distances from the centre.
struct ScaleTicks: View {

    /// Slider position (-1...1) for a given scale. The single source of truth for the
    /// mapping — `scaleSliderBinding` reads it too, so marks cannot drift from behaviour.
    static func position(for scale: Double) -> Double {
        scale >= 1 ? (scale - 1) / 3 : (scale - 1) / 0.75
    }

    private struct Mark: Identifiable {
        let id: String
        let scale: Double
        let label: String
    }

    private var marks: [Mark] {
        var out: [Mark] = [Mark(id: "center", scale: 1, label: "100%")]

        // GROW SIDE — his list, verbatim: "i want gradians 1.5 2 2.5 3."
        for n in [1.5, 2.0, 2.5, 3.0] {
            let text = n == 2 || n == 3 ? String(Int(n)) : String(n)
            out.append(Mark(id: "+\(n)", scale: n, label: text))
        }

        // SHRINK SIDE — three even quarters down. See `fractionLabel` for why these are
        // not the reciprocals of the grow side's numbers.
        for (fraction, glyph) in Self.fractionLabel.sorted(by: { $0.key < $1.key }) {
            out.append(Mark(id: "-\(fraction)", scale: fraction, label: glyph))
        }
        return out
    }

    /// The divisor -> the fraction of full size it produces, as a single glyph.
    /// Keyed by the SAME numbers the grow side uses, so the two halves stay mirrored.
    /// The divisor -> the fraction of full size it produces, as a single glyph.
    ///
    /// EVERY ONE IS A UNIT FRACTION — one over something. That is the rule, and Michael
    /// arrived at it in two steps on 2026-09-02: "i dont like 2/5", then "2/3 isnt
    /// normalized." Both rejects were the same shape — the only two labels in the set
    /// with a numerator other than 1. A run of 1/4, 1/3, 1/2 is read as a series; drop a
    /// 2/3 into it and the eye has to stop and work that one out, which defeats the
    /// reason fractions were chosen over decimals in the first place.
    ///
    /// So the shrink side marks the divisors 4, 3 and 2. It no longer mirrors the grow
    /// side's list exactly — that is the price of every label being legible on sight, and
    /// it is the right trade. Each mark still sits at its true mirrored POSITION, and 1/4
    /// falls at the left end of the track, which is where the travel stops anyway.
    /// The shrink side's marks, as a fraction of full size.
    ///
    /// EVENLY SPACED, NOT RECIPROCAL. Michael, 2026-09-02, asked what it would look like
    /// to "devide the shrink by the same gradians" and then corrected the reading: "i
    /// dont mean literal." Taken literally, mirroring 1.5/2/2.5/3 produces 2/3, 1/2, 2/5,
    /// 1/3 — which is where 2/5 and 2/3 came from, and he had already rejected both.
    ///
    /// What he meant was the same RHYTHM: four even steps out from the centre in each
    /// direction. So the shrink half is linear from 1x down to 1/4x and gets three evenly
    /// spaced quarters. Grow steps up by even amounts, shrink steps down by even amounts,
    /// and every label is a half or a quarter.
    private static let fractionLabel: [Double: String] = [
        0.75: "\u{00BE}",   // three quarters
        0.5:  "\u{00BD}",   // one half
        0.25: "\u{00BC}",   // one quarter
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(marks) { mark in
                VStack(spacing: 2) {
                    Rectangle()
                        .frame(width: 1, height: 5)
                    Text(mark.label)
                        .font(.system(size: 11, weight: mark.scale == 1 ? .semibold : .regular))
                        .fixedSize()
                }
                .foregroundStyle(mark.scale == 1 ? Color.primary : Color.secondary)
                // The thumb is inset by roughly half its width at each end, so the usable
                // track is narrower than the view. Insetting by the same amount keeps a
                // mark under the thumb that is sitting on that value.
                .position(x: 9 + (geo.size.width - 18) * (ScaleTicks.position(for: mark.scale) + 1) / 2,
                          y: 11)
            }
        }
        .frame(height: 24)
    }
}

// MARK: - Zoom / pan (Procreate-style: 1 finger = tool, 2 = pan, pinch = zoom)

/// Wraps the canvas so pinch zooms and two-finger drag pans, while a single
/// finger still reaches the active tool. iOS uses a UIScrollView (pan set to a
/// 2-finger minimum); other platforms just show the content for now.
struct ZoomableCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(iOS)
        ZoomableScrollView { content }
        #else
        content
        #endif
    }
}

#if os(iOS)
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    @ViewBuilder var content: Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delaysContentTouches = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2 // 1 finger -> tool

        let hosted = context.coordinator.hosting.view!
        hosted.backgroundColor = .clear
        hosted.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            hosted.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            hosted.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hosting.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hosting: UIHostingController(rootView: content))
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hosting: UIHostingController<Content>
        init(hosting: UIHostingController<Content>) {
            self.hosting = hosting
            hosting.view.backgroundColor = .clear
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hosting.view }
    }
}
#endif

// MARK: - Helpers

extension Color {
    /// "#RRGGBB" (or "RRGGBB") -> Color. Returns nil on a malformed string.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self = Color(.sRGB,
                     red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    /// sRGB "#RRGGBB" for persisting a chosen colour (alpha dropped — backgrounds
    /// are opaque). Returns nil if the platform colour can't be resolved.
    func hexString() -> String? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #elseif canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        #endif
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Resolve to a CGColor for Core Graphics drawing (the Pixel Pen).
    var platformCGColor: CGColor {
        #if canImport(UIKit)
        return UIColor(self).cgColor
        #else
        return NSColor(self).cgColor
        #endif
    }
}

// MARK: - Pixel Pen (Tool #3) — raster drawing into a 1024 master bitmap

/// Owns the pen's mutable raster (a 1024×1024 bitmap) plus colour + size. The canvas
/// strokes into it on drag and commits the PNG to the active layer on release; it is
/// seeded from the layer's existing pixels so drawing accumulates rather than wipes.
@MainActor
/// The Eraser tool's two modes: a manual BRUSH (drag to erase to transparent) and the
/// MAGIC color-mask (sample a color → clear matching pixels).
enum EraserMode: Hashable { case brush, magic }

final class PixelPen: ObservableObject {
    /// The active paint color (the chosen palette slot). The palette itself lives in the
    /// document (saved per-project); the pen just holds the current color + which slot.
    @Published var color: Color = .black
    @Published var selectedSlot = 0
    /// The active pixel layer's resolution — per-layer (128/256/512/1024…). The pen's
    /// bitmap IS this many pixels square; nearest-neighbor upscaling keeps it blocky.
    @Published var resolution: Int = 128
    /// Brush size in CELLS (1 = one pixel/cell, 2 = a 2×2 block, …) — same unit as the grid.
    @Published var brush: Int = 1
    /// Draw vs Erase mode — driven by the on-screen Draw/Erase toggle (all platforms).
    /// Mac right-click erases momentarily without flipping this.
    @Published var erasing = false
    @Published var showGrid = true
    /// Eyedropper sample radius in pixels (0 = single pixel; >0 = averaged circle).
    @Published var eyedropperRadius: Int = 2
    @Published private(set) var image: CGImage?

    // MARK: Magic Eraser live preview (color mask)
    /// Tolerance + contiguity for the Magic Eraser live HERE (not in the inspector's local
    /// @State) so the canvas can render a live highlight of what an Erase would remove as
    /// the slider drags. (Michael 2026-06-21: "the slider is not wired to a visual element".)
    @Published var eraseTolerance: Double = 24
    @Published var eraseContiguous = true
    /// Highlight overlay the canvas draws over the active layer (downscaled; matched pixels
    /// painted magenta, rest clear). nil when not previewing.
    @Published private(set) var erasePreview: CGImage?
    /// Cached downscaled source, so dragging the slider re-runs only the cheap match — not a
    /// full-res PNG decode every tick. Keyed by "layerID-byteCount" to rebuild on layer change.
    private var erasePreviewSource: CGImage?
    private var erasePreviewKey: String?

    /// Stop previewing (tool/layer left the Magic Eraser).
    func clearErasePreview() { erasePreview = nil; erasePreviewSource = nil; erasePreviewKey = nil }

    /// Recompute the highlight from the active layer's image. Decodes + downscales the source
    /// only when the layer/image changes (keyed); the per-change match runs on the small copy.
    func refreshErasePreview(png: Data?, layerKey: String?, target: (r: UInt8, g: UInt8, b: UInt8)) {
        guard let png, let layerKey else { clearErasePreview(); return }
        if erasePreviewKey != layerKey || erasePreviewSource == nil {
            erasePreviewKey = layerKey
            if let src = CGImageSourceCreateWithData(png as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                erasePreviewSource = downscaledCGImage(cg, maxDimension: 320)
            } else {
                erasePreviewSource = nil
            }
        }
        guard let cg = erasePreviewSource else { erasePreview = nil; return }
        erasePreview = matchHighlightImage(cg, target: target,
                                           tolerance: Int(eraseTolerance), contiguous: eraseContiguous,
                                           highlight: (255, 0, 255, 255))
    }

    // MARK: Manual brush eraser (Eraser tool, Brush mode)
    /// Which eraser mode the inspector is showing. Brush = drag on the canvas to erase.
    @Published var eraserMode: EraserMode = .magic
    /// Brush footprint: false = circle, true = square.
    @Published var eraserSquare = false
    /// Brush diameter as a fraction of the canvas edge (resolution-independent).
    @Published var eraserBrushFraction: Double = 0.06
    /// The auto-made working COPY we erase into (option b — original kept + hidden). A new
    /// session (new copy) starts when the active layer isn't this one. nil = no session yet.
    @Published var eraserWorkingLayerID: UUID?
    /// While a stroke is live, the canvas renders THIS layer from `eraserImage` instead of its
    /// stored element (so erased holes show transparent, not the un-erased pixels underneath).
    @Published var eraserLiveLayerID: UUID?
    @Published private(set) var eraserImage: CGImage?
    private(set) var eraserImageW = 0
    private(set) var eraserImageH = 0
    private var eraserCtx: CGContext?

    /// True once a working bitmap is seeded for the current copy.
    var hasEraseSession: Bool { eraserCtx != nil }

    /// Begin erasing a copy: seed a working bitmap at the image's native resolution.
    func startEraseSession(workingID: UUID, png: Data) {
        eraserWorkingLayerID = workingID
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            eraserCtx = nil; eraserImage = nil; eraserImageW = 0; eraserImageH = 0; return
        }
        let w = cg.width, h = cg.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        eraserCtx = ctx; eraserImageW = w; eraserImageH = h
        eraserImage = ctx?.makeImage()
    }

    /// Clear a brush dab (circle or square) at an image-pixel point. CG is y-up → flip.
    func eraseBrush(atImagePixel p: CGPoint, radius: Double, square: Bool) {
        guard let ctx = eraserCtx else { return }
        let r = max(0.5, radius)
        let cx = p.x, cy = Double(ctx.height) - p.y
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        if square {
            ctx.clear(rect)                 // hard square
        } else {
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: rect)       // soft-edged circle
            ctx.setBlendMode(.normal)
        }
        eraserImage = ctx.makeImage()
    }

    /// PNG of the erased bitmap to write back to the layer at stroke end.
    func endEraseStroke() -> Data? {
        guard let cg = eraserCtx?.makeImage() else { return nil }
        return pngData(from: cg)
    }

    /// Drop the session (tool/layer left the brush eraser) so a fresh copy is made next time.
    func endEraseSession() {
        eraserCtx = nil; eraserImage = nil; eraserWorkingLayerID = nil
        eraserLiveLayerID = nil; eraserImageW = 0; eraserImageH = 0
    }

    // MARK: Paint Bucket flood fill (live region preview)
    /// How loose the fill match is — how different a pixel can be from the tapped color and
    /// still flood. Higher = jumps softer edges; lower = stops at the faintest line ("wall").
    @Published var bucketTolerance: Double = 16
    /// Magic Lasso's own looseness. Kept SEPARATE from the bucket's: filling inside a line
    /// drawing wants a tight tolerance, while knocking a soft AI sky out wants a loose one,
    /// and sharing one slider would make each tool fight the other's setting.
    @Published var lassoTolerance: Double = 40
    /// Highlight of the region a tap would fill, over the active layer (downscaled). nil = none.
    @Published private(set) var bucketPreview: CGImage?
    private var bucketSource: CGImage?           // cached downscaled source
    private var bucketKey: String?
    private(set) var bucketSourceW = 0
    private(set) var bucketSourceH = 0
    private var bucketLastSeed: CGPoint?         // skip recompute when the seed pixel is unchanged

    func clearBucketPreview() {
        bucketPreview = nil; bucketSource = nil; bucketKey = nil
        bucketSourceW = 0; bucketSourceH = 0; bucketLastSeed = nil
    }

    /// Decode + downscale the layer image once (keyed), so hover only re-runs the cheap flood.
    func ensureBucketSource(png: Data, layerKey: String) {
        if bucketKey == layerKey, bucketSource != nil { return }
        bucketKey = layerKey; bucketLastSeed = nil
        if let src = CGImageSourceCreateWithData(png as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
           let ds = downscaledCGImage(cg, maxDimension: 320) {
            bucketSource = ds; bucketSourceW = ds.width; bucketSourceH = ds.height
        } else { bucketSource = nil; bucketSourceW = 0; bucketSourceH = 0 }
    }

    /// Recompute the fill-region highlight for a downscaled seed (or clear it). `seed` is in
    /// the DOWNSCALED source's pixel space. `force` recomputes even if the seed pixel is the
    /// same (used when tolerance changes).
    /// `tolerance` nil = the bucket's own setting; the Magic Lasso passes its own.
    func refreshBucketPreview(seed: CGPoint?, highlight: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
                              force: Bool = false, tolerance: Double? = nil) {
        guard let cg = bucketSource, let seed else { bucketPreview = nil; bucketLastSeed = nil; return }
        if !force, let last = bucketLastSeed, Int(last.x) == Int(seed.x), Int(last.y) == Int(seed.y) { return }
        bucketLastSeed = seed
        bucketPreview = floodHighlightImage(cg, seed: seed, tolerance: Int(tolerance ?? bucketTolerance),
                                            highlight: highlight)
    }

    private var ctx: CGContext?
    private var lastPoint: CGPoint?

    private func makeContext(_ dim: Int) -> CGContext? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: dim, height: dim, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        c?.setShouldAntialias(false)   // hard pixel edges (blocky)
        c?.setLineCap(.round)
        c?.setLineJoin(.round)
        return c
    }

    /// Seed from a layer's existing raster (adopting ITS resolution — per-layer), or
    /// start a fresh blank buffer at the picker's `resolution`.
    func load(_ data: Data?) {
        if let data,
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            resolution = cg.width                       // layer keeps its own resolution
            ctx = makeContext(cg.width)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.width))
        } else {
            ctx = makeContext(resolution)
        }
        lastPoint = nil
        image = ctx?.makeImage()
    }

    /// Fill the grid cell(s) under a normalized canvas point (0…1, top-left) — whole
    /// pixels at the layer's resolution; a brush of N fills an N×N cell block. Snapped
    /// to the grid, so the brush and grid share the same unit. CG is bottom-left → flip y.
    func stroke(toNormalized n: CGPoint) { paint(n, erase: false) }

    /// Erase the grid cell(s) under a normalized point — the counterpart of `stroke`,
    /// clearing each cell back to transparent. Driven by the Draw/Erase toggle (all
    /// platforms) and by Mac right-click.
    func erase(toNormalized n: CGPoint) { paint(n, erase: true) }

    private func paint(_ n: CGPoint, erase: Bool) {
        if ctx == nil { ctx = makeContext(resolution) }
        guard let ctx else { return }
        let dim = resolution
        let col = min(max(Int(n.x * CGFloat(dim)), 0), dim - 1)
        let row = min(max(Int(n.y * CGFloat(dim)), 0), dim - 1)
        let half = brush / 2
        if !erase { ctx.setFillColor(color.platformCGColor) }
        for dc in -half..<(brush - half) {
            for dr in -half..<(brush - half) {
                let c = col + dc, r = row + dr
                guard c >= 0, c < dim, r >= 0, r < dim else { continue }
                let cell = CGRect(x: c, y: dim - 1 - r, width: 1, height: 1)   // one cell = one pixel
                if erase { ctx.clear(cell) } else { ctx.fill(cell) }
            }
        }
        image = ctx.makeImage()
    }

    func endStroke() { lastPoint = nil }

    func currentPNG() -> Data? {
        guard let cg = ctx?.makeImage() else { return nil }
        return pngData(from: cg)
    }
}

// MARK: - Flattened render + export (roadmap 2.3)

/// The visible layers composited with NO editor chrome (no checkerboard / box) —
/// what Export and Share rasterize. Transparent where no opaque background shows.
// MARK: - Unified Export sheet (⌘E)

/// One export window: pick a format from the dropdown and save. The primary export path
/// (⌘E / the toolbar Export button). The all-sizes icon PNG folder lives on separately in
/// the Canvas hub; this sheet covers single-file formats.
struct ExportSheet: View {
    @ObservedObject var document: ImageDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .png
    @State private var flattenMatte = false
    @State private var matte: Color = .white
    @State private var payload = Data()
    @State private var exporting = false

    private var baseName: String {
        let n = document.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Untitled" : n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.system(size: 22, weight: .semibold))
            HStack(spacing: 10) {
                Text("Format").font(.system(size: 18)).foregroundStyle(.secondary)
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
            }
            if format == .pdfLayers {
                Toggle("Flatten transparency onto a matte", isOn: $flattenMatte)
                if flattenMatte {
                    ColorPicker("Matte colour", selection: $matte, supportsOpacity: false)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                Button("Export…") {
                    let m = (format == .pdfLayers && flattenMatte) ? matte.cgColorResolved : nil
                    if let d = format.data(from: document, matte: m) {
                        payload = d
                        exporting = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(20)
        #if os(iOS)
        // iPad: size the sheet to its content so it doesn't float in an empty box.
        .presentationSizing(.fitted)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 380)
        #endif
        .fileExporter(isPresented: $exporting,
                      document: CanvasDataDocument(payload),
                      contentType: format.utType,
                      defaultFilename: baseName) { _ in dismiss() }
    }
}

struct ImageCompositeView: View {
    let document: ImageDocument
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(document.layers) { layer in
                if layer.isVisible { composited(layer) }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func composited(_ layer: ImageLayer) -> some View {
        switch layer.role {
        case .background(_, let fillHex):
            if let hex = fillHex, let color = Color(hex: hex) { color }
        case .content:
            ForEach(layer.elements) { element in
                elementView(element, transform: layer.transform)
            }
        }
    }

    @ViewBuilder
    private func elementView(_ element: LayerElement, transform t: LayerTransform) -> some View {
        let ref = min(size.width, size.height)
        switch element.content {
        case .symbol(let symbol):
            Image(systemName: symbol.systemName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: symbol.tintHex) ?? .primary)
                .frame(width: ref * t.scale, height: ref * t.scale)
                .rotationEffect(.degrees(t.rotationDegrees))
                .position(x: t.center.x * size.width, y: t.center.y * size.height)
        case .text(let text):
            Text(text.string)
                // Model B: text FILLS its box (the Move transform box = center + contentSize).
                // Font starts at the box height; the text wraps to the box WIDTH and scales
                // down (minimumScaleFactor) so the whole string fits the rectangle. Reshape
                // the box → text re-wraps AND re-sizes. Box defaults to the full canvas.
                .font(.custom(text.fontName, size: max(1, t.contentSize.height * ref)))
                .bold(text.bold)
                .italic(text.italic)
                .underline(text.underline)
                .foregroundStyle(Color(hex: text.colorHex) ?? .primary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .minimumScaleFactor(0.01)
                .frame(width: max(1, t.contentSize.width * ref),
                       height: max(1, t.contentSize.height * ref))
                .rotationEffect(.degrees(t.rotationDegrees))
                .position(x: t.center.x * size.width, y: t.center.y * size.height)
        case .image(let imageContent):
            if let platformImage = PlatformImage(data: imageContent.pngData) {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ref * t.scale, height: ref * t.scale)
                    .rotationEffect(.degrees(t.rotationDegrees))
                    .position(x: t.center.x * size.width, y: t.center.y * size.height)
            }
        case .pixels(let pixels):
            if let platformImage = PlatformImage(data: pixels.pngData) {
                Image(platformImage: platformImage)
                    .interpolation(.none)   // crisp blocks when a low-res layer scales up
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }
        }
    }
}

/// CGImage -> PNG bytes, cross-platform via ImageIO (no UIKit/AppKit needed).
func pngData(from cgImage: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

/// Re-encode any imported image data (PNG/JPEG/HEIC/…) to PNG bytes (model rule:
/// PNG only — alpha + lossless, never JPG).
func pngData(fromImageData data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return pngData(from: cg)
}

/// Every image UTType the RUNNING platform can actually decode (queried from ImageIO), so
/// the import picker only ever offers formats we can truly open. On macOS this includes
/// PSD (imported flattened) and BMP; the list auto-narrows on iOS where the system decoder
/// is smaller (e.g. PSD isn't offered there). Falls back to the abstract image type.
var importableImageTypes: [UTType] {
    let ids = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
    let types = ids.compactMap { UTType($0) }
    return types.isEmpty ? [.image] : types
}

/// Cross-platform image type + a SwiftUI Image bridge, for rendering imported PNGs.
#if canImport(UIKit)
typealias PlatformImage = UIImage
extension Image { init(platformImage: UIImage) { self.init(uiImage: platformImage) } }
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
extension Image { init(platformImage: NSImage) { self.init(nsImage: platformImage) } }
#endif

/// Export deliverable (roadmap 2.3): a FOLDER of named PNG sizes, no Contents.json.
/// Write-only; the user drags the PNGs into Xcode's AppIcon wells themselves.
struct ImageExportBundle: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    var files: [String: Data]

    init(files: [String: Data]) { self.files = files }

    init(configuration: ReadConfiguration) throws { files = [:] } // export-only

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var wrappers: [String: FileWrapper] = [:]
        for (name, data) in files {
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = name
            wrappers[name] = wrapper
        }
        return FileWrapper(directoryWithFileWrappers: wrappers)
    }
}

#if canImport(UIKit)
/// Hosts the system share sheet (roadmap 2.5) for the rendered PNG file URL.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Autosave (self-driven, no UndoManager)

/// Debounced autosave for the document editor. Watches the model for ANY change and
/// writes the package ~1.5s after edits settle, plus a flush when the app leaves the
/// foreground. Deliberately independent of SwiftUI's undo-based autosave: this app has no
/// UndoManager (undo/redo belongs to the future History system, and we don't want them to
/// compete), so without this the document is never marked dirty and edits are lost on close.
struct AutosaveModifier: ViewModifier {
    @ObservedObject var document: ImageDocument
    let fileURL: URL?
    let isEditable: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var debounce: Task<Void, Never>?
    /// Where an UNTITLED document is auto-materialized so an unnamed canvas can never
    /// be lost before its first manual Save. Cleared once the user names/saves it.
    @State private var recoveryURL: URL?

    func body(content: Content) -> some View {
        content
            .onReceive(document.objectWillChange) { _ in schedule() }
            .onChange(of: scenePhase) { _, phase in
                // Flush on background. The write is now ENQUEUED rather than completed
                // inline — the serial queue picks it up immediately, and on macOS the
                // process isn't suspended on resign-active, so it lands. Blocking here to
                // "make sure" is exactly the deadlock this change removes.
                if phase != .active { debounce?.cancel(); save() }
            }
            .onChange(of: fileURL) { _, newURL in
                // The user just named/saved it → drop the auto-recovery copy.
                if newURL != nil, let r = recoveryURL {
                    try? FileManager.default.removeItem(at: r)
                    recoveryURL = nil
                }
            }
    }

    /// Coalesce a burst of edits into a single write 1.5s after the last change.
    private func schedule() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { save() }
        }
    }

    /// Snapshot on the main actor, then hand the BYTES to the background writer.
    ///
    /// The coordinated write must never happen here. On 2026-08-21 this method called
    /// `writePackage(to:)` directly, which runs `NSFileCoordinator` synchronously — and
    /// because the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, "directly"
    /// meant "on the main thread." Waiting for a file-access claim on an iCloud-backed
    /// document from the main thread deadlocks permanently: beachball, 0% CPU, no recovery,
    /// and the only way out was force-quitting the app mid-edit.
    ///
    /// Only the encode stays here, because it reads the model. Everything that can block
    /// is on `PackageWriter`'s serial queue.
    private func save() {
        guard isEditable else { return }                      // read-only → nothing to do
        // Viewing a past history point is non-destructive: writing the previewed state (or
        // letting the coordinated write reload the doc) would snap the canvas back. Skip the
        // save entirely while viewing — every state is preserved in the history snapshots, and
        // the newest committed state is already on disk from its own edit.
        guard !document.isViewingHistory else { return }

        let url: URL
        if let fileURL {
            url = fileURL                                     // saved doc: write in place
        } else {
            // UNTITLED → auto-materialize a recovery copy so the canvas is never lost,
            // even on a crash before the first Save. One stable file per window,
            // overwritten each autosave; removed when the user finally names/saves it.
            if recoveryURL == nil { recoveryURL = makeRecoveryURL() }
            guard let r = recoveryURL else { return }
            url = r
        }

        guard let data = try? document.encodedManifest() else { return }
        PackageWriter.enqueue(data, to: url)
    }

    /// A crash-safety recovery file for a genuinely UNTITLED document (rare now that new
    /// docs are materialized as real files): the next free "Recovered Image N.imgprd" in
    /// the shared projects folder. Distinct name from the ImageProducerNNNN lifetime files
    /// so it never consumes a lifetime number or collides with a real project.
    private func makeRecoveryURL() -> URL? {
        guard let dir = ImageDocument.projectsDirectory() else { return nil }
        let fm = FileManager.default
        let ext = ImageDocument.projectExtension
        var n = 1
        var url = dir.appendingPathComponent("Recovered Image \(n)").appendingPathExtension(ext)
        while fm.fileExists(atPath: url.path) {
            n += 1
            url = dir.appendingPathComponent("Recovered Image \(n)").appendingPathExtension(ext)
        }
        return url
    }
}

extension View {
    func autosave(document: ImageDocument, fileURL: URL?, isEditable: Bool) -> some View {
        modifier(AutosaveModifier(document: document, fileURL: fileURL, isEditable: isEditable))
    }
}

// MARK: - About / in-app wordmark

/// The brand wordmark shown inside the open app: "Image Producer" with the "Graphic Arts"
/// subheading the home-screen / App Store name can't display. Reached from the
/// toolbar's info button.
/// "Version 1.0 · Build 1" — read live from the bundle so it tracks
/// MARKETING_VERSION / CURRENT_PROJECT_VERSION without manual edits. Shared by
/// the About sheet, the macOS Welcome window, and the iOS launch scene so the
/// version reads identically on every platform.
var appVersionLine: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = info?["CFBundleVersion"] as? String ?? "1"
    return "Version \(short) · Build \(build)"
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Image Producer")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
            Text("GRAPHIC ARTS")
                .font(.subheadline)
                .tracking(4)
                .foregroundStyle(.secondary)
            Text(appVersionLine)
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .padding()
        }
    }
}

#Preview {
    ContentView(document: .newDefault())
}
