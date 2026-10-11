//
//  DropShadow.swift
//  Image Producer
//
//  DROP SHADOW — a child of the Layer… tool, beside Glow. A live effect: drawn under the
//  layer's artwork from the artwork's own shape, never written into pixels until Apply.
//
//  From Kirk's PhotoCraft test (2026-10-11), test #5: text layer, FX, drop shadow,
//  distance up, black, opacity 100. PhotoCraft's worked, but "I don't have the same like
//  circle to decide the angle here — you have to sort of decide the angle more of a manual
//  kind of know what degree you want." So the angle here is a DIAL you turn, with the
//  number beside it for when you do know the degree.
//
//  ANGLE uses Photoshop's convention, since that is where a Photoshop user's sense of it
//  comes from: the direction the LIGHT comes from, in degrees counter-clockwise from the
//  right (east). 120° = light from the upper left, shadow falling down and to the right.
//

import SwiftUI

// MARK: - Model

/// A layer's drop shadow. Optional on `ImageLayer` — documents saved before it existed
/// decode with no shadow.
struct LayerShadow: Codable, Equatable {
    var isEnabled = true
    var colorHex = "#000000"
    /// 0…1.
    var opacity = 0.75
    /// Where the light comes FROM, degrees counter-clockwise from east (Photoshop's way).
    var angleDegrees = 120.0
    /// How far the shadow falls, as a fraction of the canvas's SHORT edge — like the
    /// glow's reach, so the same document looks the same at every export size.
    var distanceFraction = 0.02
    /// Softness (blur), same units.
    var sizeFraction = 0.01

    /// The shadow's offset in points for a canvas whose short edge is `reference`.
    /// Light from angle a → shadow cast the opposite way; screen y grows downward.
    func offset(reference: CGFloat) -> CGSize {
        let a = angleDegrees * .pi / 180
        let d = distanceFraction * reference
        return CGSize(width: -cos(a) * d, height: sin(a) * d)
    }
}

// MARK: - The shadow itself

/// The shadow under a layer: the layer, as the compositor draws it, used as a MASK over a
/// flat color, then softened and pushed away from the light. Built from the same view as
/// the artwork, so it can never drift out of register with it.
struct DropShadowCast<Content: View>: View {
    let shadow: LayerShadow
    /// The canvas's short edge, so the shadow scales with the document.
    let reference: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        (Color(hex: shadow.colorHex) ?? .black)
            .mask(content())
            .blur(radius: max(0, shadow.sizeFraction * reference))
            .offset(shadow.offset(reference: reference))
            .opacity(shadow.opacity)
            .allowsHitTesting(false)
    }
}

// MARK: - The angle dial

/// Turn to set where the light comes from. The dot is the LIGHT; the shadow falls
/// opposite it. Drag anywhere on the dial; the number field beside it takes exact degrees.
struct AngleDial: View {
    @Binding var degrees: Double

    var body: some View {
        HStack(spacing: 14) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let r = side / 2
                let a = degrees * .pi / 180
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                    // The line from the centre toward the light.
                    Path { p in
                        p.move(to: CGPoint(x: r, y: r))
                        p.addLine(to: CGPoint(x: r + cos(a) * (r - 6), y: r - sin(a) * (r - 6)))
                    }
                    .stroke(Color.accentColor, lineWidth: 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .position(x: r + cos(a) * (r - 6), y: r - sin(a) * (r - 6))
                }
                .frame(width: side, height: side)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let dx = v.location.x - r, dy = r - v.location.y
                    guard dx != 0 || dy != 0 else { return }
                    var deg = atan2(dy, dx) * 180 / .pi
                    if deg < 0 { deg += 360 }
                    degrees = deg.rounded()
                })
                .accessibilityElement()
                .accessibilityLabel("Light angle")
                .accessibilityValue("\(Int(degrees)) degrees")
                .accessibilityAdjustableAction { dir in
                    switch dir {
                    case .increment: degrees = (degrees + 5).truncatingRemainder(dividingBy: 360)
                    case .decrement: degrees = (degrees + 355).truncatingRemainder(dividingBy: 360)
                    @unknown default: break
                    }
                }
            }
            .frame(width: 64, height: 64)

            HStack(spacing: 4) {
                TextField("Angle", value: Binding(get: { degrees.rounded() },
                                                  set: { degrees = (($0.truncatingRemainder(dividingBy: 360)) + 360)
                                                            .truncatingRemainder(dividingBy: 360) }),
                          format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18).monospacedDigit())
                    .frame(width: 70)
                Text("°").font(.system(size: 18))
            }
        }
    }
}
