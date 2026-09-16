//
//  LayerMerge.swift
//  Image Producer
//
//  Merge several checked layers into one, NON-DESTRUCTIVELY.
//
//  ⚖️ THE NON-DESTRUCTIVE RULE — his, 2026-09-06 ("yes it is the non destructive rule")
//  and restated for merge on 2026-09-15: "it has to be non destructive so the originals
//  stay below but the merged lay[e]rs are consolidated in a new layer above."
//
//  It is not a preference. UNDO IS OFF ON PURPOSE because UndoManager crashed this app,
//  so LAYERING IS THE UNDO. Nothing here may destroy a source layer — the merged result
//  is an ADDITION, and every original stays exactly where it was, switched off.
//  Same shape as GlowTool.apply and the Move tool's commit.
//

import SwiftUI

/// Render several layers together, in stack order, over transparency at canvas size.
///
/// Uses the SAME compositor as the real render, so a merge looks like what was on screen
/// rather than an approximation of it. Sources are forced visible in the throwaway copy —
/// merging a layer you had hidden is a legitimate thing to want, and the alternative is a
/// silently empty result.
@MainActor func renderLayersImage(_ layers: [ImageLayer], in document: ImageDocument) -> CGImage? {
    guard !layers.isEmpty else { return nil }
    let shown = layers.map { layer -> ImageLayer in
        var copy = layer
        copy.isVisible = true
        return copy
    }
    let soloDoc = ImageDocument(name: document.name,
                               canvasWidth: document.canvasWidth,
                               canvasHeight: document.canvasHeight,
                               layers: shown, palette: document.palette,
                               cropRect: nil)
    let renderer = ImageRenderer(content: ImageCompositeView(document: soloDoc,
                                                            size: document.canvasPixelSize))
    renderer.scale = 1
    return renderer.cgImage
}

/// Merge the checked layers. Returns nil on success, or a message to show the user.
///
/// ⛔ BACKGROUND FLOORS ARE REFUSED, not merged. Light and Dark are ALTERNATE RENDITIONS,
/// not a stack — `IconSetExport.render` picks exactly one by role — so combining them
/// would destroy the app's whole reason for existing. His rule, 2026-09-15: keep them
/// "un checkmarkable and exempt." This is the second gate on the same thing: the UI does
/// not offer a checkbox, and this refuses one anyway if it ever arrives.
@MainActor func mergeLayers(_ ids: Set<ImageLayer.ID>, in document: ImageDocument) -> String? {
    let picked = document.layers.enumerated().filter { ids.contains($0.element.id) }
    guard picked.count >= 2 else { return "Check two or more layers to merge." }

    if picked.contains(where: { if case .background = $0.element.role { return true }; return false }) {
        return "Light and Dark are separate renditions and can't be merged."
    }

    // Stack order matters: `picked` is bottom-first because `document.layers` is, so the
    // compositor draws them in the same order it draws them on the canvas.
    guard let cg = renderLayersImage(picked.map(\.element), in: document),
          let png = pngData(from: cg) else {
        return "Those layers could not be rendered."
    }

    document.captureHistoryBaselineIfNeeded()

    // NAMED AFTER THE TOPMOST SOURCE, following the "(Glow)" convention: the existing
    // suffix is stripped first so repeats number rather than compound — "(Merged)" then
    // "(Merged 2)", never "(Merged) (Merged)".
    let topmost = picked.last!
    var base = topmost.element.name
    if let r = base.range(of: #" \(Merged(?: \d+)?\)$"#, options: .regularExpression) {
        base.removeSubrange(r)
    }
    let taken = Set(document.layers.map(\.name))
    func candidate(_ k: Int) -> String { k == 1 ? "\(base) (Merged)" : "\(base) (Merged \(k))" }
    var n = 1
    while taken.contains(candidate(n)) { n += 1 }

    var merged = ImageLayer(name: candidate(n), role: .content)
    merged.setImage(png)
    merged.transform = document.coveringTransform(forPNG: png)
    merged.isVisible = true
    // The name is now a fact about a merge, not a mirror of any text content.
    merged.nameLinkedToText = false

    // The originals: left in place, switched OFF. They are the undo.
    for (i, _) in picked { document.layers[i].isVisible = false }

    // Directly ABOVE the topmost source, so the merged pixels sit where the user was
    // already looking. Indices below it are untouched, so this insert cannot shift any
    // of the layers being hidden.
    document.layers.insert(merged, at: topmost.offset + 1)

    document.recordHistory(toolID: Tool.layer.rawValue,
                           groupTitle: Tool.layer.title,
                           actionLabel: "Merge \(picked.count) layers",
                           layerID: merged.id)
    return nil
}
