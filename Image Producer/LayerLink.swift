//
//  LayerLink.swift
//  Image Producer
//
//  Link checked layers so they move, scale and rotate as ONE object.
//
//  His ask, 2026-10-03: "lock the two layers together so you move one and they both move
//  simultaniously as if one object" — a white headline over bolder dark copies of itself.
//  And the rule that shaped it: "no rasterization please unless specifically asked to by
//  the user." So linking is a RELATIONSHIP, never a bake. Every member stays a live layer:
//  text stays text, and each one keeps its own font, color and effects.
//
//  ONE RULE, NOT ONE PATCH PER CONTROL. A layer's placement is changed from many places —
//  the canvas drag and corner grabbers, Scale / Rotation sliders and their arrows, Text
//  Size, Fit / Fill, Center / Reset. Rather than teach each of them about links, the
//  editor watches every layer's transform and, when exactly ONE member of a group
//  changed, carries the same change to its partners around it. A control written next
//  year gets linking for free.
//

import Foundation
import CoreGraphics

/// Everything the link rule watches: who exists, where each sits, and who is linked.
struct LinkSnapshot: Equatable {
    struct Entry: Equatable {
        var transform: LayerTransform
        var group: UUID?
    }
    var entries: [UUID: Entry]

    @MainActor init(_ document: ImageDocument) {
        var e: [UUID: Entry] = [:]
        for layer in document.layers {
            e[layer.id] = Entry(transform: layer.transform, group: layer.linkGroup)
        }
        entries = e
    }
}

/// Carry a change on one linked layer to its partners. Returns true if anything moved.
///
/// `before` is the state the editor last saw. A group is followed only when EXACTLY ONE of
/// its members changed since then, and that member was already in the same group. Any
/// other shape of change — a History step restoring the whole stack, a revert, this
/// function's own writes — is a whole-document replacement, not a gesture, and following
/// it would move the partners twice.
@MainActor @discardableResult
func followLinkedLayers(from before: LinkSnapshot, in document: ImageDocument) -> Bool {
    // Members that changed placement and were linked in the same group before and after.
    var changedByGroup: [UUID: [UUID]] = [:]
    for layer in document.layers {
        guard let g = layer.linkGroup,
              let old = before.entries[layer.id], old.group == g,
              old.transform != layer.transform else { continue }
        changedByGroup[g, default: []].append(layer.id)
    }

    let W = Double(document.canvasWidth), H = Double(document.canvasHeight)
    guard W > 0, H > 0 else { return false }
    var moved = false

    for (group, changed) in changedByGroup where changed.count == 1 {
        let leaderID = changed[0]
        guard let leader = document.layers.first(where: { $0.id == leaderID }),
              let was = before.entries[leaderID]?.transform else { continue }
        let now = leader.transform

        // How the leader's box changed, per axis, in its own (unrotated) frame.
        let oldSize = was.contentSize, newSize = now.contentSize
        guard oldSize.width > 0, oldSize.height > 0 else { continue }
        let fx = newSize.width / oldSize.width
        let fy = newSize.height / oldSize.height
        let dTheta = now.rotationDegrees - was.rotationDegrees

        // Rigid follow, in canvas PIXELS so a 3:1 banner does not skew the offsets:
        // take each partner's offset from the leader, undo the leader's old rotation,
        // scale it as the leader scaled, apply the new rotation, and re-anchor on the
        // leader's new center. (Positive degrees = clockwise in this y-down canvas,
        // matching `.rotationEffect`.)
        let oldC = CGPoint(x: was.center.x * W, y: was.center.y * H)
        let newC = CGPoint(x: now.center.x * W, y: now.center.y * H)
        let a0 = -was.rotationDegrees * .pi / 180
        let a1 = now.rotationDegrees * .pi / 180

        for i in document.layers.indices {
            let p = document.layers[i]
            guard p.id != leaderID, p.linkGroup == group,
                  before.entries[p.id]?.group == group else { continue }
            var t = p.transform

            var dx = t.center.x * W - oldC.x
            var dy = t.center.y * H - oldC.y
            (dx, dy) = (dx * cos(a0) - dy * sin(a0), dx * sin(a0) + dy * cos(a0))
            dx *= fx; dy *= fy
            (dx, dy) = (dx * cos(a1) - dy * sin(a1), dx * sin(a1) + dy * cos(a1))
            t.center = CGPoint(x: (newC.x + dx) / W, y: (newC.y + dy) / H)

            // The partner's own box scales the same way the leader's did.
            let s = t.contentSize
            let w = max(s.width * fx, 0.005), h = max(s.height * fy, 0.005)
            t.scale = max(w, h)
            if t.contentAspect != nil || abs(fx - fy) > 0.000_001 {
                t.contentAspect = w / h
            }

            var r = t.rotationDegrees + dTheta
            if r > 180 { r -= 360 } else if r < -180 { r += 360 }
            t.rotationDegrees = r

            if t != p.transform {
                document.layers[i].transform = t
                moved = true
            }
        }
    }
    return moved
}

/// Link the given layers. Any group one of them already belongs to is absorbed whole, so
/// linking a new layer to one member of an existing object joins the whole object.
@MainActor func linkLayers(_ ids: Set<ImageLayer.ID>, in document: ImageDocument) {
    let picked = document.layers.filter { ids.contains($0.id) && !$0.isBackgroundFloor }
    guard picked.count >= 2 else { return }
    let absorbed = Set(picked.compactMap(\.linkGroup))
    let group = UUID()
    document.captureHistoryBaselineIfNeeded()
    for i in document.layers.indices {
        let l = document.layers[i]
        if ids.contains(l.id) && !l.isBackgroundFloor { document.layers[i].linkGroup = group }
        else if let g = l.linkGroup, absorbed.contains(g) { document.layers[i].linkGroup = group }
    }
    let count = document.layers.filter { $0.linkGroup == group }.count
    document.recordHistory(toolID: "layers", groupTitle: "Layers",
                           actionLabel: "Link \(count) layers", layerID: picked.last?.id)
}

/// Unlink the given layers. A group left with a single member is dissolved, because a
/// link to nothing is just a stale flag.
@MainActor func unlinkLayers(_ ids: Set<ImageLayer.ID>, in document: ImageDocument) {
    guard document.layers.contains(where: { ids.contains($0.id) && $0.linkGroup != nil }) else { return }
    document.captureHistoryBaselineIfNeeded()
    for i in document.layers.indices where ids.contains(document.layers[i].id) {
        document.layers[i].linkGroup = nil
    }
    var counts: [UUID: Int] = [:]
    for l in document.layers { if let g = l.linkGroup { counts[g, default: 0] += 1 } }
    for i in document.layers.indices {
        if let g = document.layers[i].linkGroup, counts[g] == 1 { document.layers[i].linkGroup = nil }
    }
    document.recordHistory(toolID: "layers", groupTitle: "Layers",
                           actionLabel: "Unlink", layerID: nil)
}
