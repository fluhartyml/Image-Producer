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
    /// The size asked for, before Dynamic Type — picks the Apple text style on iOS.
    private let wantedSize: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    let monospacedDigit: Bool
    let monospaced: Bool

    init(size: CGFloat, weight: Font.Weight?, design: Font.Design?, monospacedDigit: Bool, monospaced: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.wantedSize = size
        self.weight = weight; self.design = design
        self.monospacedDigit = monospacedDigit; self.monospaced = monospaced
    }

    func body(content: Content) -> some View {
        var f: Font
        #if os(iOS)
        // REM 2026-11-21 — APPLE'S TEXT STYLES ON iPHONE AND iPAD. His word: "why dont we use apples?"
        // → "apple is the source of truth". Each size the app asks for is read as the Apple text style
        // it stands for (18 → Body, 20 → Title 3, 15 → Subheadline …), so Apple decides the point size
        // and its Dynamic Type steps on each device. Decorative glyphs (32 pt and up) keep their size.
        if let style = Self.appleStyle(for: wantedSize) {
            f = Font.system(style, design: design ?? .default, weight: weight ?? .regular)
        } else {
            f = Font.system(size: size, weight: weight ?? .regular, design: design ?? .default)
        }
        #else
        // The Mac keeps its point sizes: macOS has no Dynamic Type, and its Body style is 13 pt — far
        // under his 18-pt reading size (his 11-04: "18 pt is my personal setting"). Mac text size is
        // his call, so it is unchanged until he rules on it.
        f = Font.system(size: size, weight: weight ?? .regular, design: design ?? .default)
        #endif
        if monospacedDigit { f = f.monospacedDigit() }
        if monospaced { f = f.monospaced() }
        return content.font(f)
    }

    /// Which Apple text style a requested size stands for, at the default text size.
    static func appleStyle(for size: CGFloat) -> Font.TextStyle? {
        switch size {
        case 32...:     nil            // a glyph, not text
        case 28..<32:   .title
        case 22..<28:   .title2
        case 20..<22:   .title3
        case 17..<20:   .body
        case 16..<17:   .callout
        case 15..<16:   .subheadline
        case 13..<15:   .footnote
        case 12..<13:   .caption
        default:        .caption2
        }
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
