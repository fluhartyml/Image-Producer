//
//  NumberFields.swift
//  Image Producer
//
//  012 / A4 — NUMBER FIELDS, SO NOTHING NEEDS A DRAG.
//
//  REM: Roadmap line 012 (Image-Producer-Roadmap-DRAFT-2026-11-04): "Number fields for
//  position, size, rotation of every layer, mask and crop, so nothing needs a drag."
//  It sits in the accessibility block because a drag is the one move that Voice
//  Control, Switch Control and a keyboard cannot make precisely. A typed number can.
//
//  REM: ONE MODULE, THREE SLOTS (his "thinks in modules"). `PixelNumberField` is the
//  single field; `BoxNumberFields` is Left / Top / Width / Height for any box kept in
//  normalized canvas space — the Move tool's Crop and the Mask tool both use it. The
//  layer's own Position and Rotation fields live beside Scale in the Move inspector.
//
//  REM: EVERY NUMBER IS IN PIXELS (degrees for rotation), never the 0...1 the model
//  stores. "A control must be reported in its own unit" — the Scale readout lesson,
//  2026-09-15. Return commits a typed value, like the Scale fields.
//
//  REM: Spoken names are three words max (his rule 11-04): "Crop left", "Mask width".
//

import SwiftUI

/// One labeled number field at 18 pt. The caption sits above the box so the 18-pt label
/// and the number both fit the inspector's width (the build-334 lesson: in one row the
/// labels were squeezed to nothing).
struct PixelNumberField: View {
    let title: String
    let spoken: String
    let help: String
    @Binding var value: Double
    var fractionDigits: ClosedRange<Int> = 0...0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .scaledFont(18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // the field carries the spoken name
            TextField("", value: $value,
                      format: .number.grouping(.never).precision(.fractionLength(fractionDigits)))
                .scaledFont(18)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
                .help(help)
                .accessibilityLabel(spoken)
                #if os(iOS)
                .keyboardType(fractionDigits.upperBound > 0 ? .numbersAndPunctuation : .numberPad)
                #endif
        }
    }
}

/// Left / Top / Width / Height, in canvas pixels, for a box stored in normalized canvas
/// space (0...1, origin top-left).
///
/// - `minSide` is the smallest normalized edge allowed (the box can never be squeezed to
///   nothing and become impossible to grab again).
/// - `lockedRatio` is width ÷ height IN PIXELS. When set, typing Width moves Height to
///   match and typing Height moves Width — the same rule a corner drag follows.
/// - The box is always kept inside the canvas: a size is clamped to the room left, and
///   a position to where the whole box still fits.
struct BoxNumberFields: View {
    /// "Crop" or "Mask" — the start of every spoken name.
    let noun: String
    let box: CGRect
    let canvasWidth: Int
    let canvasHeight: Int
    var minSide: CGFloat = CropMask.minSide
    var lockedRatio: CGFloat? = nil
    let onChange: (CGRect) -> Void

    private var cw: CGFloat { CGFloat(max(1, canvasWidth)) }
    private var ch: CGFloat { CGFloat(max(1, canvasHeight)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PixelNumberField(title: "Left", spoken: "\(noun) left",
                                 help: "Pixels from the canvas's left edge to the \(noun.lowercased())'s left edge — type a value and press Return",
                                 value: binding(.minX))
                PixelNumberField(title: "Top", spoken: "\(noun) top",
                                 help: "Pixels from the canvas's top edge to the \(noun.lowercased())'s top edge — type a value and press Return",
                                 value: binding(.minY))
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                PixelNumberField(title: "Width", spoken: "\(noun) width",
                                 help: "The \(noun.lowercased())'s width in pixels — type a value and press Return",
                                 value: binding(.width))
                PixelNumberField(title: "Height", spoken: "\(noun) height",
                                 help: "The \(noun.lowercased())'s height in pixels — type a value and press Return",
                                 value: binding(.height))
                Spacer(minLength: 0)
            }
        }
    }

    private enum Edge { case minX, minY, width, height }

    private func binding(_ edge: Edge) -> Binding<Double> {
        Binding(
            get: {
                switch edge {
                case .minX:   return Double((box.minX * cw).rounded())
                case .minY:   return Double((box.minY * ch).rounded())
                case .width:  return Double((box.width * cw).rounded())
                case .height: return Double((box.height * ch).rounded())
                }
            },
            set: { px in onChange(Self.apply(px, to: edge, box: box, cw: cw, ch: ch,
                                             minSide: minSide, ratio: lockedRatio)) })
    }

    /// Pure: the new normalized box after one typed pixel value. Kept static so the rule
    /// is testable on its own and cannot reach into view state.
    private static func apply(_ px: Double, to edge: Edge, box: CGRect, cw: CGFloat, ch: CGFloat,
                              minSide: CGFloat, ratio: CGFloat?) -> CGRect {
        var r = box
        let v = CGFloat(px.isFinite ? px.rounded() : 0)
        switch edge {
        case .minX:
            r.origin.x = min(max(v / cw, 0), 1 - r.width)
        case .minY:
            r.origin.y = min(max(v / ch, 0), 1 - r.height)
        case .width:
            // REM: grow from the left edge; never past the right side of the canvas.
            var w = min(max(v / cw, minSide), 1 - r.minX)
            if let ratio, ratio > 0 {
                // Height follows in PIXELS (ratio is pixel w÷h); if that runs off the
                // bottom, shrink both to the room there is.
                var h = (w * cw / ratio) / ch
                let roomH = 1 - r.minY
                if h > roomH { h = roomH; w = (h * ch * ratio) / cw }
                r.size.height = max(h, minSide)
            }
            r.size.width = w
        case .height:
            var h = min(max(v / ch, minSide), 1 - r.minY)
            if let ratio, ratio > 0 {
                var w = (h * ch * ratio) / cw
                let roomW = 1 - r.minX
                if w > roomW { w = roomW; h = (w * cw / ratio) / ch }
                r.size.width = max(w, minSide)
            }
            r.size.height = h
        }
        return r
    }
}

extension CropMask {
    /// The same mask moved and stretched so its bounding box becomes `newBounds`.
    ///
    /// REM: Every corner is mapped from the old box to the new one, so a ⌘-bent quad
    /// keeps its bend and a star keeps its points — a typed number never flattens the
    /// shape back to a rectangle (unlike the `cropRect` setter, which does).
    func fitted(to newBounds: CGRect) -> CropMask {
        let b = bounds
        guard b.width > 0, b.height > 0 else {
            return CropMask(rect: newBounds, form: form, polygonSides: polygonSides)
        }
        var m = self
        m.corners = corners.map { p in
            CGPoint(x: newBounds.minX + (p.x - b.minX) / b.width * newBounds.width,
                    y: newBounds.minY + (p.y - b.minY) / b.height * newBounds.height)
        }
        return m
    }
}
