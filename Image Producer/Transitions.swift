//
//  Transitions.swift
//  Image Producer
//
//  STORYBOARD, PIECE 2 — transitions between cards (Amber Sheet D-090, D-091, D-093,
//  D-094, D-095; finishes D-082, D-083 and D-070a's "cards and transitions").
//
//  REM: D-090 — "Transition fillers like HyperCard's visual effects: barn doors, blinds,
//  fades." D-082 — "The storyboard decides the filler frames that carry one key frame into
//  the next." D-083 — "Filler frames are made only when you ask: at export, or when you
//  intentionally Play or Render. They are never saved as layers." Only each transition's
//  effect and length are saved; its frames are drawn while a video is being written.
//  REM: Drawn with Core Graphics only (CGContext clipping, alpha and image drawing), the
//  same context the video writer already draws each card into.
//

import CoreGraphics
import Foundation

/// REM: D-091 — "The transition list, as per HyperCard: cut · dissolve · fade to/from black
/// or white · barn door open/close · venetian blinds · wipe (left/right/up/down) · iris
/// open/close · zoom open/close · checkerboard · scroll (left/right/up/down) · plus motion
/// in-betweens with easing (from the Camera tool)." Every effect in the list is here; the
/// last, `.motion`, is drawn from frames made ahead of time (see `motionInBetweens`).
nonisolated enum TransitionEffect: String, CaseIterable, Identifiable, Sendable {
    case cut, dissolve, fadeBlack, fadeWhite
    case barnDoorOpen, barnDoorClose, venetianBlinds
    case wipeLeft, wipeRight, wipeUp, wipeDown
    case irisOpen, irisClose, zoomOpen, zoomClose, checkerboard
    case scrollLeft, scrollRight, scrollUp, scrollDown
    case motion

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cut: return "Cut"
        case .dissolve: return "Dissolve"
        case .fadeBlack: return "Fade Through Black"
        case .fadeWhite: return "Fade Through White"
        case .barnDoorOpen: return "Barn Door Open"
        case .barnDoorClose: return "Barn Door Close"
        case .venetianBlinds: return "Venetian Blinds"
        case .wipeLeft: return "Wipe Left"
        case .wipeRight: return "Wipe Right"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        case .irisOpen: return "Iris Open"
        case .irisClose: return "Iris Close"
        case .zoomOpen: return "Zoom Open"
        case .zoomClose: return "Zoom Close"
        case .checkerboard: return "Checkerboard"
        case .scrollLeft: return "Scroll Left"
        case .scrollRight: return "Scroll Right"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .motion: return "Motion In-Between"
        }
    }

    /// REM: D-094 — "Each effect has a minimum frame count (a cut needs none)."
    /// REM: Claude's call, not from the sheet — the sheet gives no numbers, and D-095 says
    /// "Starting lengths get tuned by eye before they're locked." These are starting
    /// values in 1/30 s frames, waiting for that tuning.
    var minimumFrames: Int {
        switch self {
        case .cut: return 0
        case .dissolve, .wipeLeft, .wipeRight, .wipeUp, .wipeDown,
             .scrollLeft, .scrollRight, .scrollUp, .scrollDown: return 6
        case .venetianBlinds, .irisOpen, .irisClose, .zoomOpen, .zoomClose, .checkerboard: return 8
        // The Camera tool's own in-betweens go down to 1 frame; 4 is the fewest that reads
        // as motion rather than a jump at 30 frames a second.
        case .motion: return 4
        case .fadeBlack, .fadeWhite, .barnDoorOpen, .barnDoorClose: return 10
        }
    }

    /// REM: D-095 — "Each effect has its own natural length — a barn door swinging takes
    /// longer than a crossfade." Picking an effect sets this length. Claude's starting
    /// values (see minimumFrames), to be tuned by eye.
    var naturalFrames: Int {
        switch self {
        case .cut: return 0
        case .dissolve, .wipeLeft, .wipeRight, .wipeUp, .wipeDown: return 15
        case .scrollLeft, .scrollRight, .scrollUp, .scrollDown: return 18
        case .venetianBlinds, .irisOpen, .irisClose, .zoomOpen, .zoomClose, .checkerboard, .motion: return 20
        case .barnDoorOpen, .barnDoorClose: return 24
        case .fadeBlack, .fadeWhite: return 30
        }
    }

    /// Draw one filler frame: `from` turning into `to`, `p` of the way (0 < p < 1), into
    /// `r` (the canvas's place in the frame). The context is already filled black.
    func draw(_ ctx: CGContext, from a: CGImage, to b: CGImage, progress p: CGFloat, in r: CGRect) {
        let p = min(max(p, 0), 1)
        func clipped(_ image: CGImage, _ rects: [CGRect]) {
            ctx.saveGState()
            ctx.clip(to: rects)
            ctx.draw(image, in: r)
            ctx.restoreGState()
        }
        func ellipse(_ image: CGImage, radius: CGFloat) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: r.midX - radius, y: r.midY - radius, width: radius * 2, height: radius * 2))
            ctx.clip()
            ctx.draw(image, in: r)
            ctx.restoreGState()
        }
        let w = r.width, h = r.height
        // Half the diagonal: the iris's radius when fully open.
        let reach = (w * w + h * h).squareRoot() / 2
        switch self {
        case .cut:
            ctx.draw(p < 0.5 ? a : b, in: r)
        case .dissolve, .motion:
            // `.motion` lands here only when its frames couldn't be made (see
            // `motionInBetweens`): the cards are then cross-faded, eased.
            ctx.draw(a, in: r)
            ctx.saveGState(); ctx.setAlpha(p); ctx.draw(b, in: r); ctx.restoreGState()
        case .fadeBlack, .fadeWhite:
            // First half: the old card fades out to the color; second half: the new card
            // fades in from it.
            let shade: CGFloat = self == .fadeWhite ? 1 : 0
            ctx.setFillColor(CGColor(red: shade, green: shade, blue: shade, alpha: 1))
            ctx.fill(r)
            ctx.saveGState()
            if p < 0.5 { ctx.setAlpha(1 - p * 2); ctx.draw(a, in: r) } else { ctx.setAlpha(p * 2 - 1); ctx.draw(b, in: r) }
            ctx.restoreGState()
        case .barnDoorOpen:
            // The doors part from the middle, showing the new card.
            ctx.draw(a, in: r)
            let open = w * p
            clipped(b, [CGRect(x: r.midX - open / 2, y: r.minY, width: open, height: h)])
        case .barnDoorClose:
            // The doors swing shut from both sides, carrying the new card.
            ctx.draw(a, in: r)
            let door = w * p / 2
            clipped(b, [CGRect(x: r.minX, y: r.minY, width: door, height: h),
                        CGRect(x: r.maxX - door, y: r.minY, width: door, height: h)])
        case .venetianBlinds:
            ctx.draw(a, in: r)
            let slats = 10, slat = h / CGFloat(slats)
            clipped(b, (0..<slats).map {
                CGRect(x: r.minX, y: r.minY + CGFloat($0) * slat, width: w, height: slat * p)
            })
        case .wipeLeft:
            ctx.draw(a, in: r)
            clipped(b, [CGRect(x: r.maxX - w * p, y: r.minY, width: w * p, height: h)])
        case .wipeRight:
            ctx.draw(a, in: r)
            clipped(b, [CGRect(x: r.minX, y: r.minY, width: w * p, height: h)])
        case .wipeUp:
            // Core Graphics counts up from the bottom: up starts at the bottom edge.
            ctx.draw(a, in: r)
            clipped(b, [CGRect(x: r.minX, y: r.minY, width: w, height: h * p)])
        case .wipeDown:
            ctx.draw(a, in: r)
            clipped(b, [CGRect(x: r.minX, y: r.maxY - h * p, width: w, height: h * p)])
        case .irisOpen:
            ctx.draw(a, in: r)
            ellipse(b, radius: reach * p)
        case .irisClose:
            ctx.draw(b, in: r)
            ellipse(a, radius: reach * (1 - p))
        case .zoomOpen:
            // The new card grows out of the middle.
            ctx.draw(a, in: r)
            ctx.draw(b, in: CGRect(x: r.midX - w * p / 2, y: r.midY - h * p / 2, width: w * p, height: h * p))
        case .zoomClose:
            // The old card shrinks into the middle.
            ctx.draw(b, in: r)
            let q = 1 - p
            ctx.draw(a, in: CGRect(x: r.midX - w * q / 2, y: r.midY - h * q / 2, width: w * q, height: h * q))
        case .checkerboard:
            // Two passes, like HyperCard: the even squares fill in, then the odd ones.
            ctx.draw(a, in: r)
            let cols = 8, rows = 8
            let cw = w / CGFloat(cols), ch = h / CGFloat(rows)
            var rects: [CGRect] = []
            for row in 0..<rows {
                for col in 0..<cols {
                    let even = (row + col) % 2 == 0
                    let fill = even ? min(1, p * 2) : max(0, p * 2 - 1)
                    guard fill > 0 else { continue }
                    rects.append(CGRect(x: r.minX + CGFloat(col) * cw, y: r.maxY - CGFloat(row + 1) * ch + ch * (1 - fill),
                                        width: cw, height: ch * fill))
                }
            }
            if !rects.isEmpty { clipped(b, rects) }
        case .scrollLeft, .scrollRight, .scrollUp, .scrollDown:
            // The new card pushes the old one out of the frame.
            let dx: CGFloat = self == .scrollLeft ? -1 : self == .scrollRight ? 1 : 0
            let dy: CGFloat = self == .scrollUp ? 1 : self == .scrollDown ? -1 : 0
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.draw(a, in: r.offsetBy(dx: dx * w * p, dy: dy * h * p))
            ctx.draw(b, in: r.offsetBy(dx: -dx * w * (1 - p), dy: -dy * h * (1 - p)))
            ctx.restoreGState()
        }
    }
}

/// One transition in a video: the effect and how many filler frames it spends, between
/// card `index` and the next card.
nonisolated struct VideoTransitionStep: Sendable {
    var effect: TransitionEffect
    var frames: Int
    /// For a motion in-between: each filler frame, made ahead of time on the main actor
    /// (count = frames). Empty for every other effect.
    var motionFrames: [CGImage] = []
    /// For a motion in-between: each filler frame's progress, already eased. Empty means
    /// even steps.
    var progress: [CGFloat] = []
}

// MARK: - Motion in-betweens (D-091)

extension VideoTransitionStep {
    /// The effect and length only, before a motion in-between's frames are made.
    var bare: VideoTransitionStep { VideoTransitionStep(effect: effect, frames: frames) }
}

/// REM: D-091 — "plus motion in-betweens with easing (from the Camera tool)." The Camera
/// tool's own rule (CameraTool.swift): "A frame carries its NEGATIVE … Two flattened
/// pictures can only be cross-faded — the motion is not in the pixels. Two snapshots give
/// start and end for every layer's center, scale and rotation, so an in-between is
/// arithmetic and a re-render." So when both cards are Camera frames with negatives, each
/// layer moves, scales and turns from its pose in one card to its pose in the next (the
/// Camera tool's `blend`), shaped by the Camera tool's easing (`CameraEasing.shape`), and
/// fades in or out where it is only in one of the two.
/// REM: Claude's call, not from the sheet — with no negatives to read (flipbook layers,
/// Camera in-betweens, a frame trimmed to its art, or two frames shot with different
/// background or scale settings), there is no sound basis for what moved, so it returns
/// nothing and the cards cross-fade with the same easing — what the Camera tool says a
/// flattened pair can only do.
@MainActor
func motionInBetweens(from a: ImageLayer, to b: ImageLayer, in document: ImageDocument,
                      count: Int, easing: CameraEasing) -> [CGImage] {
    guard count > 0,
          let fa = a.cameraFrame, let fb = b.cameraFrame,
          !fa.isTween, !fb.isTween, !fa.trimmedToArt, !fb.trimmedToArt,
          fa.includedBackground == fb.includedBackground, fa.scale == fb.scale,
          let da = fa.snapshot, let db = fb.snapshot,
          let sa = try? JSONDecoder().decode(DocumentSnapshot.self, from: da),
          let sb = try? JSONDecoder().decode(DocumentSnapshot.self, from: db)
    else { return [] }
    let width = sa.canvasWidth ?? document.canvasWidth
    let height = sa.canvasHeight ?? document.canvasHeight
    // A hidden layer counts as fully faded, so showing or hiding one between shots fades it.
    func shown(_ l: ImageLayer) -> Double { l.isVisible ? l.opacity : 0 }
    var frames: [CGImage] = []
    for k in 1...count {
        let t = easing.shape(Double(k) / Double(count + 1))
        var mid: [ImageLayer] = []
        for var layer in sa.layers {
            let start = shown(layer)
            if let to = sb.layers.first(where: { $0.id == layer.id }) {
                layer.transform = cameraBlend(layer.transform, to.transform, t)
                layer.opacity = start + (shown(to) - start) * t
            } else {
                layer.opacity = start * (1 - t)
            }
            layer.isVisible = layer.opacity > 0
            mid.append(layer)
        }
        // Layers only in the next card fade in at their place in its stack.
        for (j, var layer) in sb.layers.enumerated() where !sa.layers.contains(where: { $0.id == layer.id }) {
            layer.opacity = shown(layer) * t
            layer.isVisible = layer.opacity > 0
            mid.insert(layer, at: min(j, mid.count))
        }
        let temp = ImageDocument(name: document.name, canvasWidth: width, canvasHeight: height,
                                 layers: mid, palette: document.palette, cropRect: nil)
        guard let cg = renderCanvasImage(temp, scale: CGFloat(fa.scale),
                                         includeBackgrounds: fa.includedBackground)
        else { return [] }
        frames.append(cg)
    }
    return frames
}

extension VideoExport {
    /// REM: D-091 — fill in each motion in-between's frames (or its eased cross-fade) for
    /// the steps as they'll be written, after D-070c's padding has set their lengths.
    @MainActor static func withMotion(_ steps: [VideoTransitionStep], cards: [ImageLayer],
                                      document: ImageDocument) -> [VideoTransitionStep] {
        steps.enumerated().map { i, step in
            guard step.effect == .motion, step.frames > 0, cards.indices.contains(i + 1) else { return step }
            let easing = document.storyboard.transition(after: i, ids: cards.map(\.id))?.easing ?? .easeBoth
            var out = step
            out.motionFrames = motionInBetweens(from: cards[i], to: cards[i + 1], in: document,
                                                count: step.frames, easing: easing)
            out.progress = (1...step.frames).map {
                CGFloat(easing.shape(Double($0) / Double(step.frames + 1)))
            }
            return out
        }
    }
}
