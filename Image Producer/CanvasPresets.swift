//
//  CanvasPresets.swift
//  Image Producer
//
//  THE PRESET CATALOG — defined with Michael, 2026-10-04, by talking it through before any
//  code ("now we need to define presets available befor coding"). Organized by JOB, in
//  subsets, because he looks for the job, not the numbers (2026-08-25: "the important
//  thing is the title youtube thumbnail over the pixel density").
//
//  Every preset carries two labels, his yes 2026-10-04:
//    • SHAPE — Horizontal / Vertical / Square (computed from the size, never typed).
//    • SIZE RULE — Exact / Fixed ratio / Fluid width / Fluid height.
//      "Fixed ratio" is the ad industry's "flexible ad size" (IAB New Ad Portfolio, 2017):
//      the shape is locked, the size can grow above a minimum. "Fluid width/height" — one
//      side fixed, the other free — is web layout's term; he chose it: "fluid height
//      width sounds nice". A fluid resize EXTENDS the canvas; it never letterboxes.
//
//  Sources, checked 2026-10-04: App Store Connect screenshot specifications (Apple);
//  IAB standard ad sizes; US movie poster sizes; ARCH paper sizes; A2/A6/A7 card sizes.
//  ⚠️ Not yet verified against a primary source: LinkedIn banner, desktop wallpaper
//  resolutions, the 18 × 24 yard sign. No business is named anywhere in this file's
//  user-facing text that the app is not associated with (his rule, 2026-10-04).
//

import Foundation

enum CanvasSizeRule: String, CaseIterable, Identifiable {
    case exact = "Exact"
    case ratio = "Fixed ratio"
    case fluidWidth = "Fluid width"
    case fluidHeight = "Fluid height"
    var id: String { rawValue }
}

enum CanvasShape: String {
    case horizontal = "Horizontal", vertical = "Vertical", square = "Square"
    static func of(_ w: Double, _ h: Double) -> CanvasShape {
        abs(w - h) < 0.000_1 ? .square : (w > h ? .horizontal : .vertical)
    }
}

struct CanvasPreset: Identifiable {
    enum Size {
        /// Printed: pixels = inches × the current PPI.
        case inches(Double, Double)
        /// Screen: an exact pixel count; PPI is left alone (a screen has no print size).
        case pixels(Int, Int)
        /// Shape only: keeps the canvas's long edge, sets the other side to the ratio.
        /// `minLongEdge` WARNS when the canvas is too small — it never silently resizes.
        case ratio(Int, Int, minLongEdge: Int)
    }

    let label: String
    let size: Size
    var id: String { label + detail }

    var rule: CanvasSizeRule {
        if case .ratio = size { return .ratio }
        return .exact
    }

    var shape: CanvasShape {
        switch size {
        case .inches(let w, let h):    .of(w, h)
        case .pixels(let w, let h):    .of(Double(w), Double(h))
        case .ratio(let w, let h, _):  .of(Double(w), Double(h))
        }
    }

    /// The numbers, for the second line of the menu item.
    var detail: String {
        switch size {
        case .inches(let w, let h): "\(Self.num(w)) × \(Self.num(h)) in"
        case .pixels(let w, let h): "\(w) × \(h) px"
        case .ratio(let w, let h, let min): min > 0 ? "\(w):\(h), at least \(min) px long" : "\(w):\(h)"
        }
    }

    /// The full second line: numbers · shape · size rule.
    var subtitle: String { "\(detail) · \(shape.rawValue) · \(rule.rawValue)" }

    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    static func inches(_ label: String, _ w: Double, _ h: Double) -> CanvasPreset { .init(label: label, size: .inches(w, h)) }
    static func pixels(_ label: String, _ w: Int, _ h: Int) -> CanvasPreset { .init(label: label, size: .pixels(w, h)) }
    static func ratio(_ label: String, _ w: Int, _ h: Int, min: Int = 0) -> CanvasPreset { .init(label: label, size: .ratio(w, h, minLongEdge: min)) }
}

struct CanvasPresetSubset: Identifiable {
    let title: String
    let presets: [CanvasPreset]
    var id: String { title }
}

struct CanvasPresetGroup: Identifiable {
    let title: String
    let subsets: [CanvasPresetSubset]
    var id: String { title }
}

extension CanvasPreset {
    static let catalog: [CanvasPresetGroup] = [
        CanvasPresetGroup(title: "App Store Connect", subsets: [
            CanvasPresetSubset(title: "iPhone screenshots", presets: [
                .pixels("iPhone 6.9″", 1260, 2736),
                .pixels("iPhone 6.5″", 1284, 2778),
                .pixels("iPhone 6.3″", 1179, 2556),
                .pixels("iPhone Duo — outer", 1398, 2034),
                .pixels("iPhone Duo — inner", 2007, 2853),
            ]),
            CanvasPresetSubset(title: "iPad screenshots", presets: [
                .pixels("iPad 13″", 2064, 2752),
            ]),
            CanvasPresetSubset(title: "Mac, Apple TV, Vision Pro", presets: [
                .pixels("Mac", 2880, 1800),
                .pixels("Apple TV", 3840, 2160),
                .pixels("Apple Vision Pro", 3840, 2160),
            ]),
            CanvasPresetSubset(title: "Icon", presets: [
                .pixels("App icon", 1024, 1024),
            ]),
        ]),
        CanvasPresetGroup(title: "Wallpapers", subsets: [
            CanvasPresetSubset(title: "iPhone & iPad", presets: [
                .pixels("iPhone 6.9″", 1260, 2736),
                .pixels("iPhone 6.3″", 1179, 2556),
                .pixels("iPhone Duo — inner", 2007, 2853),
                .pixels("iPad 13″", 2064, 2752),
            ]),
            CanvasPresetSubset(title: "Desktop", presets: [
                .pixels("HD", 1920, 1080),
                .pixels("QHD", 2560, 1440),
                .pixels("4K", 3840, 2160),
                .pixels("5K", 5120, 2880),
            ]),
        ]),
        CanvasPresetGroup(title: "Social", subsets: [
            // Shape first, exact size second: these platforms re-encode, so the shape is
            // what survives (his ruling on the YouTube thumbnail, 2026-08-25).
            CanvasPresetSubset(title: "Banners & headers", presets: [
                .ratio("X header", 3, 1, min: 1500),
                .pixels("X header", 1500, 500),
                .ratio("Facebook cover", 205, 78, min: 820),
                .pixels("Facebook cover", 820, 312),
                .pixels("LinkedIn banner", 1584, 396),
            ]),
            CanvasPresetSubset(title: "Posts & stories", presets: [
                .pixels("Instagram square", 1080, 1080),
                .pixels("Instagram portrait", 1080, 1350),
                .pixels("Instagram story", 1080, 1920),
            ]),
            CanvasPresetSubset(title: "Video", presets: [
                .ratio("YouTube thumbnail", 16, 9, min: 640),
                .pixels("YouTube thumbnail", 1280, 720),
            ]),
        ]),
        CanvasPresetGroup(title: "Apple TV", subsets: [
            // Measured off his own shipped tvOS app (Tally Matrix Clock's brand assets),
            // and the poster ratio is Apple's word in the tvOS SDK — see git history.
            CanvasPresetSubset(title: "Top shelf & poster", presets: [
                .ratio("Top shelf", 8, 3, min: 1920),
                .pixels("Top shelf", 1920, 720),
                .ratio("Top shelf (wide)", 29, 9, min: 2320),
                .pixels("Top shelf (wide)", 2320, 720),
                .ratio("Poster", 2, 3),
            ]),
        ]),
        CanvasPresetGroup(title: "Web ads", subsets: [
            CanvasPresetSubset(title: "Horizontal", presets: [
                .pixels("Leaderboard", 728, 90),
                .pixels("Billboard", 970, 250),
            ]),
            CanvasPresetSubset(title: "Vertical", presets: [
                .pixels("Skyscraper", 160, 600),
                .pixels("Half page", 300, 600),
            ]),
            CanvasPresetSubset(title: "Tile", presets: [
                .pixels("Medium rectangle", 300, 250),
            ]),
        ]),
        CanvasPresetGroup(title: "Paper", subsets: [
            CanvasPresetSubset(title: "ANSI", presets: [
                .inches("A — Letter", 8.5, 11),
                .inches("B — Tabloid", 11, 17),
                .inches("C", 17, 22),
                .inches("D", 22, 34),
                .inches("E", 34, 44),
            ]),
            CanvasPresetSubset(title: "Architectural (ARCH)", presets: [
                .inches("ARCH A", 9, 12),
                .inches("ARCH B", 12, 18),
                .inches("ARCH C", 18, 24),
                .inches("ARCH D", 24, 36),
                .inches("ARCH E1", 30, 42),
                .inches("ARCH E", 36, 48),
            ]),
        ]),
        CanvasPresetGroup(title: "Posters", subsets: [
            CanvasPresetSubset(title: "Movie posters", presets: [
                .inches("One Sheet", 27, 40),
                .inches("Half Sheet", 22, 28),
                .inches("Insert", 14, 36),
            ]),
        ]),
        CanvasPresetGroup(title: "Signs & flyers", subsets: [
            CanvasPresetSubset(title: "Flyers", presets: [
                .inches("Bulletin-board post", 8.5, 11),
                .inches("Letterhead", 8.5, 11),
            ]),
            CanvasPresetSubset(title: "Garage sale signs", presets: [
                .inches("Letter", 8.5, 11),
                .inches("Tabloid", 11, 17),
                .inches("Yard sign", 24, 18),
            ]),
        ]),
        CanvasPresetGroup(title: "Event & stationery", subsets: [
            CanvasPresetSubset(title: "Take-aways & postcards", presets: [
                .inches("Club take-away", 3, 5),
                .inches("Postcard", 6, 4),
            ]),
            CanvasPresetSubset(title: "Invitations", presets: [
                .inches("A7 invitation", 5, 7),
                .inches("A6 card", 4.5, 6.25),
                .inches("A2 card", 4.25, 5.5),
            ]),
            CanvasPresetSubset(title: "Greeting cards — flat sheet", presets: [
                .inches("A2, folds to 4.25 × 5.5", 8.5, 5.5),
                .inches("A6, folds to 4.5 × 6.25", 9, 6.25),
                .inches("A7, folds to 5 × 7", 10, 7),
            ]),
        ]),
        CanvasPresetGroup(title: "Cards & envelopes", subsets: [
            CanvasPresetSubset(title: "Business cards", presets: [
                .inches("Business card", 3.5, 2),
                .inches("Business card", 2, 3.5),
            ]),
            CanvasPresetSubset(title: "Index cards", presets: [
                .inches("3 × 5", 3, 5),
                .inches("4 × 6", 4, 6),
                .inches("5 × 8", 5, 8),
            ]),
            CanvasPresetSubset(title: "Envelopes", presets: [
                .inches("Letter #6¾", 6.5, 3.625),
                .inches("Business #10", 9.5, 4.125),
            ]),
        ]),
        CanvasPresetGroup(title: "Photo", subsets: [
            CanvasPresetSubset(title: "Prints", presets: [
                .inches("Wallet", 2.5, 3.5),
                .inches("4 × 6", 4, 6),
                .inches("5 × 7", 5, 7),
                .inches("8 × 10", 8, 10),
                .inches("8 × 12", 8, 12),
                .inches("11 × 14", 11, 14),
                .inches("16 × 20", 16, 20),
                .inches("20 × 30", 20, 30),
                .inches("24 × 36", 24, 36),
            ]),
        ]),
    ]
}
