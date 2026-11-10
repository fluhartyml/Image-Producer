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
/// in-betweens with easing (from the Camera tool)." Every effect in the list but the last
/// is here; motion in-betweens with easing come with a later piece.
nonisolated enum TransitionEffect: String, CaseIterable, Identifiable, Sendable {
    case cut, dissolve, fadeBlack, fadeWhite
    case barnDoorOpen, barnDoorClose, venetianBlinds
    case wipeLeft, wipeRight, wipeUp, wipeDown
    case irisOpen, irisClose, zoomOpen, zoomClose, checkerboard
    case scrollLeft, scrollRight, scrollUp, scrollDown

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
        case .venetianBlinds, .irisOpen, .irisClose, .zoomOpen, .zoomClose, .checkerboard: return 20
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
        case .dissolve:
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
}
