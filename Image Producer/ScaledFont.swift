//
//  ScaledFont.swift
//  Image Producer
//
//  REM: 015a A8 SYSTEM TEXT SIZE, his ruling 004d (11-04): "18 pt is my personal setting" —
//  so the system's text size wins. Every fixed `.font(.system(size: N))` in the app now goes
//  through `.scaledFont(N)`: N points at the DEFAULT text size, growing or shrinking with
//  what each person picks in Settings (Dynamic Type), relative to Body. One modifier, so no
//  screen can drift back to a fixed size.
//  Mac note: macOS has no system-wide Dynamic Type for apps, so on the Mac the sizes stay at
//  their default (the same N points as before). The iPad follows Settings ▸ Display & Brightness
//  ▸ Text Size and Settings ▸ Accessibility ▸ Larger Text.
//

import SwiftUI

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    let monospacedDigit: Bool
    let monospaced: Bool

    init(size: CGFloat, weight: Font.Weight?, design: Font.Design?, monospacedDigit: Bool, monospaced: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight; self.design = design
        self.monospacedDigit = monospacedDigit; self.monospaced = monospaced
    }

    func body(content: Content) -> some View {
        var f = Font.system(size: size, weight: weight ?? .regular, design: design ?? .default)
        if monospacedDigit { f = f.monospacedDigit() }
        if monospaced { f = f.monospaced() }
        return content.font(f)
    }
}

extension View {
    /// A system font that is `size` points at the default text size and follows Dynamic Type.
    func scaledFont(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil,
                    monospacedDigit: Bool = false, monospaced: Bool = false) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design,
                                  monospacedDigit: monospacedDigit, monospaced: monospaced))
    }
}
