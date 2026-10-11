//
//  FontCatalog.swift
//  Image Producer
//
//  The installed-font list behind the Text tool's Font picker: every family, whether its
//  name can preview itself, and a few of its own characters when it cannot.
//
//  His asks, 2026-10-11: "how can the user press f and it jumps to fonts begimming with f
//  and what if they typed fut it would get closer" · "can the font name be written in the
//  font type of the name listed, as a preview of each font? glyph fonts like wingdimgs
//  would need something different".
//
//  MEASURED on his MacBook, 2026-10-11, before this was written: 203 families, 54 of which
//  cannot show their own name as a preview —
//    • SYMBOL fonts (Core Text class "symbolic"): Wingdings 1–3, Webdings, Zapf Dingbats,
//      Symbol, Bodoni Ornaments, Apple Braille, Apple Color Emoji.
//    • fonts with NO a–z at all: Arabic, Hebrew, Devanagari… and Symbols Nerd Font, which
//      is not flagged symbolic. Bodoni Ornaments is the reverse trap — it HAS a–z, but its
//      letters are ornaments. So the rule needs both halves: hasLatin && !symbolic.
//  ⚠️ Wingdings and Webdings keep ALL 223 of their glyphs in the Private Use Area
//    (U+F020…F0FF). A scan of ordinary Unicode finds nothing in them — which is why the
//    glyph browser used to come up empty for Wingdings. `repertoire` scans the PUA too.
//

import Foundation
import CoreText
import Observation

struct FontFamilyInfo: Identifiable, Hashable {
    let name: String
    /// The name drawn in its own font IS a preview (it has real a–z, and is not a
    /// symbol font). When false, show the name in the system font plus `sample`.
    let previewsItself: Bool
    /// A few of the font's own characters, for fonts that cannot preview their name.
    let sample: String
    var id: String { name }
}

@Observable
final class FontCatalog {
    static let shared = FontCatalog()

    private(set) var families: [FontFamilyInfo] = []

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        reload()
        // A font installed while the app is open used to appear only after a relaunch
        // (the list was a `static let`). Core Text posts this when the registered fonts
        // change; re-read on it.
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String),
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
    }

    func reload() {
        let names = ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).sorted()
        families = names.map(Self.info(for:))
    }

    /// Families matching what was typed into Find Font. Names that BEGIN with it come
    /// first — "fut" puts Futura at the top — then names that merely contain it.
    func matching(_ query: String) -> [FontFamilyInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return families }
        let starts = families.filter { $0.name.range(of: q, options: [.caseInsensitive, .anchored]) != nil }
        let contains = families.filter {
            $0.name.range(of: q, options: .caseInsensitive) != nil
                && $0.name.range(of: q, options: [.caseInsensitive, .anchored]) == nil
        }
        return starts + contains
    }

    /// The first family whose name begins with `prefix` — the type-to-jump target.
    func firstFamily(withPrefix prefix: String) -> String? {
        families.first { $0.name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil }?.name
    }

    // MARK: - Classification

    private static func info(for name: String) -> FontFamilyInfo {
        let font = CTFontCreateWithName(name as CFString, 18, nil)
        let traits = CTFontGetSymbolicTraits(font).rawValue
        let isSymbolic = (traits & CTFontSymbolicTraits.traitClassMask.rawValue)
            == CTFontStylisticClass.classSymbolic.rawValue
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        let hasLatin = "abcxyzABC".unicodeScalars.allSatisfy { set.contains($0) }
        let previews = hasLatin && !isSymbolic
        let sampleText: String
        if previews {
            sampleText = ""
        } else if isSymbolic && hasLatin {
            // Bodoni Ornaments: its ornaments ARE its a–z, so typing letters shows them.
            sampleText = "abcdef"
        } else if isSymbolic {
            sampleText = sample(from: set, in: font, symbolsFirst: true)
        } else {
            sampleText = sample(from: set, in: font, symbolsFirst: false)   // Arabic, Hebrew… letters first
        }
        return FontFamilyInfo(name: name, previewsItself: previews, sample: sampleText)
    }

    /// Up to six characters that show what the font IS — never the ASCII punctuation and
    /// digits nearly every font carries. A script font leads with its LETTERS (Al Bayan
    /// otherwise opened with × and ÷); a symbol font leads with its symbols.
    private static func sample(from set: CharacterSet, in font: CTFont, symbolsFirst: Bool) -> String {
        func pass(_ wanted: (Unicode.GeneralCategory) -> Bool, into out: inout [Character]) {
            for range in sampleRanges {
                for v in range {
                    guard out.count < 6 else { return }
                    guard let s = Unicode.Scalar(v), set.contains(s), v > 0x7F,
                          wanted(s.properties.generalCategory),
                          drawsInk(s, in: font) else { continue }
                    out.append(Character(s))
                }
            }
        }
        let isLetter: (Unicode.GeneralCategory) -> Bool = {
            [.uppercaseLetter, .lowercaseLetter, .otherLetter].contains($0)
        }
        let isSymbol: (Unicode.GeneralCategory) -> Bool = {
            [.otherSymbol, .mathSymbol, .privateUse].contains($0)
        }
        var out: [Character] = []
        pass(symbolsFirst ? isSymbol : isLetter, into: &out)
        pass(symbolsFirst ? isLetter : isSymbol, into: &out)
        return String(out)
    }

    /// True when the character puts something on the page. Wingdings and Webdings map
    /// their SPACE to U+F020, so without this their sample came out blank.
    private static func drawsInk(_ s: Unicode.Scalar, in font: CTFont) -> Bool {
        let utf16 = Array(String(s).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count) else { return false }
        let box = CTFontGetBoundingRectsForGlyphs(font, .default, glyphs, nil, glyphs.count)
        return box.width > 0 && box.height > 0
    }

    /// Where to look for a sample, in order. Emoji are searched before the old symbol
    /// block so Apple Color Emoji shows faces rather than © and ®.
    private static let sampleRanges: [ClosedRange<UInt32>] = [
        0x1F300...0x1FAFF,   // emoji
        0x0080...0x33FF,     // the world's scripts + dingbats + braille + math
        0xE000...0xF8FF,     // Private Use Area — Wingdings, Webdings, Nerd Font icons
    ]

    /// Every character a family can draw, for the glyph browser — bounded for speed.
    /// Includes the Private Use Area, where Wingdings and Webdings keep all their glyphs.
    static func repertoire(of family: String, limit: Int = 1000) -> [String] {
        let font = CTFontCreateWithName(family as CFString, 24, nil)
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        var out: [String] = []
        let ranges: [ClosedRange<UInt32>] = [0x21...0x33FF, 0xE000...0xF8FF]
        for range in ranges {
            for v in range {
                guard let scalar = Unicode.Scalar(v), set.contains(scalar) else { continue }
                out.append(String(scalar))
                if out.count >= limit { return out }
            }
        }
        return out
    }
}
