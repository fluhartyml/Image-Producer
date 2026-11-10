//
//  XcodeProjectWells.swift
//  Image Producer
//
//  REM: AMBER SHEET D, PIECE 1 — Xcode Project Support (D-010, D-011, D-012, D-020, D-022,
//  D-023, plus the Mac well from D-001). All LOCKED 2026-11-05. His words, from the sheet:
//    D-010 "Hidden unless you ask for it. The feature is called Xcode Project Support and is
//          off by default."
//    D-011 "Two ways to turn it on: View menu and Settings." — "View and settings because the
//          ipad has a menubar but iphones dont."
//    D-012 "Once on, the wells show in the Layers list as drop slots, each showing what's in it."
//    D-020 "Screenshot wells for iPhone, iPad, iPhone Duo, Apple Watch and Apple TV."
//    D-001 "A Mac well: yes, up to 10 screenshots"
//    D-022 "Up to 10 screenshots per device, as per App Store Connect."
//    D-023 "Up to 4 sets per device: your original page plus up to 3 Product Page
//          Optimization test versions"
//
//  REM: PIECE 2 (D-040, D-041, D-042, LOCKED) — wrong-size images. His words:
//    D-040 "A wrong-size image dropped in a well gets a warning: an exclamation popup, or a
//          text note on the wells page."
//    D-041 "Once a mismatch is found, the image shows a toggle: Fill ( ) Fit. Fit is the
//          default."
//    D-042 "At export, every wrong-size image is resized to its well, and the export says so
//          plainly, so you can look in each folder and check nothing was skewed."
//  Sizes are D-001 and D-030–D-034 (App Store Connect screenshot specifications, read
//  2026-11-05). See "Sizes" below.
//
//  REM: THE OTHER SETS (build 386, D-023 and D-003, LOCKED). His words:
//    D-023 "Up to 4 sets per device: your original page plus up to 3 Product Page
//          Optimization test versions, as per App Store Connect."
//    D-003 "Custom product pages: yes, up to 70, as per App Store Connect. Each is its own set
//          with iPhone and iPad screenshot wells (up to 10 each), no icon well."
//  The wells section shows "Showing [set]" (a Picker), Add Test Version, Add Custom Page, and
//  for any set but the Original, Rename and Delete. Deleting a set with screenshots asks first.
//
//  REM: Export to Project Bundle (D-050–051) and D-042's "resized" report are in
//  ProjectBundleExport.swift; the export calls `wellResized` below.
//  REM: THE APPLE TV ICON AND TOP SHELF WELLS (D-021, D-027, D-002, LOCKED). His words:
//    D-021 "Apple TV wells: the rounded-rectangle icon, Top Shelf and wide Top Shelf, plus the
//          TV screenshots."
//    D-027 "Top Shelf is a banner, made the way we made Mediaworks' on Nov 4 … its own wide
//          picture with the app's name in big type across it … light and dark. Sizes: Top
//          Shelf 1920 × 720 (@2x 3840 × 1440), wide 2320 × 720 (@2x 4640 × 1440)."
//    D-002 "No icon wells for the page versions. Each version varies its screenshots only;
//          the app keeps one icon." — so these wells are on the Original page only.
//  They sit right under the Apple TV screenshot well. Each holds one picture, with the same
//  wrong-size check and Fill / Fit as the screenshots. Export to Project Bundle puts them into
//  "App Icon & Top Shelf Image.brandassets" in place of the pictures made from the canvas; an
//  empty well leaves the canvas's picture there, as the Icon Set export makes it.
//
//  REM: WHAT IS DELIBERATELY NOT HERE. The creative asset wells (D-024/025/028) and video
//  (D-070+) are later pieces. His rule: no placeholders, dead buttons or "coming soon" — so
//  they are absent, not stubbed.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreTransferable

// MARK: - The switch

enum XcodeProjectSupport {
    /// REM: D-011 — ONE stored value behind both switches. The View menu toggle, the Mac's
    /// Settings window and the iPhone/iPad Settings app (Settings.bundle, same key) all read
    /// and write this, so turning it on in one place turns it on everywhere. Standard
    /// UserDefaults on purpose: that is the domain the iOS Settings app writes to.
    static let storageKey = "ip.xcodeProjectSupport"
    /// REM: D-010 — "off by default."
    static let defaultValue = false
}

// MARK: - Model (saved in the .imgprd document)

/// The devices that get a screenshot well. REM: D-020 lists iPhone, iPad, iPhone Duo, Apple
/// Watch and Apple TV, in that order; D-001 adds the Mac. The Mac goes after the iPad so the
/// three big-screen pages sit together — the sheet doesn't set an order beyond D-020's list.
enum XcodeWellDevice: String, CaseIterable, Identifiable {
    case iPhone, iPad, iPhoneDuo, mac, appleWatch, appleTV
    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhone:     "iPhone"
        case .iPad:       "iPad"
        case .iPhoneDuo:  "iPhone Duo"
        case .mac:        "Mac"
        case .appleWatch: "Apple Watch"
        case .appleTV:    "Apple TV"
        }
    }

    /// Verified against the app's own SFSymbolNames.json. The Duo has no symbol of its own;
    /// two panels side by side reads as the folding phone.
    var systemImage: String {
        switch self {
        case .iPhone:     "iphone"
        case .iPad:       "ipad"
        case .iPhoneDuo:  "rectangle.split.2x1"
        case .mac:        "macbook"
        case .appleWatch: "applewatch"
        case .appleTV:    "appletv"
        }
    }
}

/// One screenshot in a well. The file's own bytes, kept as dropped — REM: D-035 "Files: JPEG
/// or PNG". A JPEG or PNG is stored untouched; anything else (HEIC, TIFF…) is turned into a
/// PNG on the way in, so a well only ever holds what App Store Connect accepts.
struct XcodeScreenshot: Identifiable, Codable, Equatable {
    var id = UUID()
    var imageData: Data
    /// REM: D-041 — "the image shows a toggle: Fill ( ) Fit. Fit is the default." Kept per
    /// screenshot and saved with the project; it only matters while the image is the wrong
    /// size for its well.
    var fitMode: XcodeFitMode = .fit
}

extension XcodeScreenshot {
    /// Build 383 wrote screenshots with no `fitMode`; they open as Fit — D-041 "Fit is the
    /// default." (In an extension so the memberwise init stays.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        imageData = try c.decode(Data.self, forKey: .imageData)
        fitMode = try c.decodeIfPresent(XcodeFitMode.self, forKey: .fitMode) ?? .fit
    }
}

/// REM: D-041 — "Fill ( ) Fit". Neither one stretches: D-042 wants "nothing was skewed", so
/// both keep the picture's own proportions. Fit shows all of it inside the well's size, with
/// bars where it doesn't reach; Fill covers the whole size and trims what spills over.
enum XcodeFitMode: String, Codable {
    case fill, fit
}

/// REM: What kind of App Store page a set is. His words, LOCKED 2026-11-05:
///   D-023 "Up to 4 sets per device: your original page plus up to 3 Product Page
///         Optimization test versions, as per App Store Connect."
///   D-003 "Custom product pages: yes, up to 70, as per App Store Connect. Each is its own set
///         with iPhone and iPad screenshot wells (up to 10 each), no icon well. Apple offers
///         custom pages for iPhone and iPad only, not Mac, Apple TV or Apple Watch."
///   D-002 "No icon wells for the page versions." — no set has an icon well; the app keeps
///         one icon (the Icon Set export).
enum XcodeSetKind: String, Codable {
    case original, testVersion, customPage

    /// The wells this kind of set shows, in the Layers list and in the export.
    /// REM: D-023 says "per device", so the original page and its test versions get every
    /// well. D-003 names "iPhone and iPad" only for custom pages, so they get exactly those
    /// two. REM (Claude's call, conservative): the sheet doesn't say whether a custom page
    /// takes iPhone Duo screenshots; D-003 names only "iPhone and iPad", so no Duo well.
    var devices: [XcodeWellDevice] {
        switch self {
        case .original, .testVersion: XcodeWellDevice.allCases
        case .customPage:             [.iPhone, .iPad]
        }
    }
}

/// One set — a whole App Store page's worth of screenshots, one well per device.
/// REM: D-023 — "your original page plus up to 3 Product Page Optimization test versions";
/// D-003 — custom product pages, each "its own set".
struct XcodeWellSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// Keyed by `XcodeWellDevice.rawValue`, NOT by the enum. A String key means a file written
    /// by a later build with a device this build doesn't know still OPENS here — the unknown
    /// well is simply not shown — instead of the whole document failing to decode.
    var wells: [String: [XcodeScreenshot]] = [:]
    /// Added in build 386. Builds 383–385 only ever wrote the Original set, with no `kind`.
    var kind: XcodeSetKind = .original

    func screenshots(for device: XcodeWellDevice) -> [XcodeScreenshot] { wells[device.rawValue] ?? [] }

    /// Screenshots in the wells this set shows.
    var screenshotCount: Int { kind.devices.reduce(0) { $0 + screenshots(for: $1).count } }
}

extension XcodeWellSet {
    /// Builds 383–385 wrote no `kind`: their only set was "Original", so a set without one
    /// opens as the original page if it's named that, otherwise as a test version.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        wells = try c.decodeIfPresent([String: [XcodeScreenshot]].self, forKey: .wells) ?? [:]
        kind = try c.decodeIfPresent(XcodeSetKind.self, forKey: .kind)
            ?? (name == XcodeProjectWells.originalName ? .original : .testVersion)
    }
}

/// Every set for this project: the Original first, then the test versions, then the custom
/// pages. REM: D-023 — modeled as an ARRAY of sets from day one (build 383), so adding the
/// other sets didn't change the file format, only added each set's `kind`.
struct XcodeProjectWells: Codable, Equatable {
    /// REM: D-022 — "Up to 10 screenshots per device, as per App Store Connect."
    static let maxPerDevice = 10
    /// REM: D-023 — "Up to 4 sets per device": the original page + "up to 3 Product Page
    /// Optimization test versions".
    static let maxSets = 4
    static let maxTestVersions = maxSets - 1
    /// REM: D-003 — "Custom product pages: yes, up to 70".
    static let maxCustomPages = 70
    static let originalName = "Original"

    /// REM: D-023 — the "Original" set first. Always present.
    var sets: [XcodeWellSet] = [XcodeWellSet(name: XcodeProjectWells.originalName)]

    init() {}

    /// Older builds' files have no wells, and a file could in theory carry an empty list:
    /// either way exactly one Original set exists and comes first, then test versions, then
    /// custom pages (each group in its saved order).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try c.decodeIfPresent([XcodeWellSet].self, forKey: .sets) ?? []
        var original = saved.first { $0.kind == .original } ?? XcodeWellSet(name: Self.originalName)
        original.name = Self.originalName
        // A second "original" can only come from a hand-edited file; keep its screenshots
        // as a test version rather than drop them.
        let extraOriginals = saved.filter { $0.kind == .original && $0.id != original.id }
            .map { s -> XcodeWellSet in var s = s; s.kind = .testVersion; return s }
        sets = [original]
            + (saved.filter { $0.kind == .testVersion } + extraOriginals)
            + saved.filter { $0.kind == .customPage }
    }

    /// Only the Original, with nothing in its wells — the manifest leaves the key out
    /// entirely, so a project that never used the wells saves the same bytes it always did.
    /// A test version or custom page you added is saved even while its wells are empty, so
    /// its name is still there when you reopen the project.
    var isEmpty: Bool {
        sets.count == 1 && sets.allSatisfy { $0.wells.values.allSatisfy(\.isEmpty) }
    }

    var originalIndex: Int { sets.firstIndex { $0.kind == .original } ?? 0 }

    func count(of kind: XcodeSetKind) -> Int { sets.filter { $0.kind == kind }.count }

    var canAddTestVersion: Bool { count(of: .testVersion) < Self.maxTestVersions }
    var canAddCustomPage: Bool { count(of: .customPage) < Self.maxCustomPages }

    /// The folder this name would get in the export, compared the way the Mac's disk compares
    /// names (case doesn't count), so two sets can never write into one folder.
    private static func folderKey(_ name: String) -> String {
        IconSetExport.safeFolderName(name).lowercased()
    }

    /// nil when the name can be used for the set `id`; otherwise the sentence saying why not.
    /// REM: D-051 names each set's folder "<project>-<set name>", so names must be unique and
    /// not empty, and none but the Original may be called "Original".
    func problem(withName name: String, for id: XcodeWellSet.ID?) -> String? {
        let key = Self.folderKey(name)
        if key.isEmpty { return "A set needs a name." }
        if key == Self.folderKey(Self.originalName) {
            return "“\(Self.originalName)” is your original page's name. Choose another."
        }
        if sets.contains(where: { $0.id != id && Self.folderKey($0.name) == key }) {
            return "Another set is already named “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”. Choose another."
        }
        return nil
    }

    /// The first free default name: "Version A", "Version B", "Version C" for test versions —
    /// REM: D-051's own example folder is "HomeLAB Playground-Version A" — and "Custom Page 1",
    /// "Custom Page 2"… for custom pages (Claude's wording; the sheet writes these folders
    /// "<custom page name>" and leaves the default open).
    func defaultName(for kind: XcodeSetKind) -> String {
        let candidates: [String]
        switch kind {
        case .original:    return Self.originalName
        case .testVersion: candidates = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { "Version \($0)" }
        case .customPage:  candidates = (1...(Self.maxCustomPages + sets.count)).map { "Custom Page \($0)" }
        }
        return candidates.first { problem(withName: $0, for: nil) == nil } ?? candidates[0]
    }
}

extension ImageDocument {
    /// Add an empty test version or custom page under its default name, after the others of
    /// its kind (test versions stay ahead of custom pages). Returns its id, or nil at the cap
    /// — REM: D-023 "up to 3 Product Page Optimization test versions", D-003 "up to 70".
    @discardableResult
    func addWellSet(_ kind: XcodeSetKind) -> XcodeWellSet.ID? {
        switch kind {
        case .original:    return nil   // there's only ever one, and it's always there
        case .testVersion: guard xcodeProject.canAddTestVersion else { return nil }
        case .customPage:  guard xcodeProject.canAddCustomPage else { return nil }
        }
        let set = XcodeWellSet(name: xcodeProject.defaultName(for: kind), kind: kind)
        let order: [XcodeSetKind] = [.original, .testVersion, .customPage]
        let rank = order.firstIndex(of: kind) ?? order.count
        let at = xcodeProject.sets.lastIndex { (order.firstIndex(of: $0.kind) ?? 0) <= rank }
            .map { $0 + 1 } ?? xcodeProject.sets.count
        xcodeProject.sets.insert(set, at: at)
        return set.id
    }

    /// Rename a test version or custom page. Returns nil when done, or the sentence saying why
    /// not. REM: the Original keeps its name — D-051's folder is "<project>-Original".
    func renameWellSet(_ id: XcodeWellSet.ID, to name: String) -> String? {
        guard let i = xcodeProject.sets.firstIndex(where: { $0.id == id }),
              xcodeProject.sets[i].kind != .original else { return nil }
        if let problem = xcodeProject.problem(withName: name, for: id) { return problem }
        xcodeProject.sets[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return nil
    }

    /// Delete a test version or custom page and everything in its wells. The Original can't
    /// be deleted. (The view asks first when the set holds screenshots.)
    func removeWellSet(_ id: XcodeWellSet.ID) {
        xcodeProject.sets.removeAll { $0.id == id && $0.kind != .original }
    }

    /// Add screenshots to one well of one set, in the order given, up to the ten-per-device
    /// limit. Returns how many were left out because the well was full.
    @discardableResult
    func addScreenshots(_ images: [Data], to device: XcodeWellDevice, inSet setIndex: Int) -> Int {
        guard xcodeProject.sets.indices.contains(setIndex),
              xcodeProject.sets[setIndex].kind.devices.contains(device) else { return images.count }
        var list = xcodeProject.sets[setIndex].screenshots(for: device)
        let room = max(0, XcodeProjectWells.maxPerDevice - list.count)
        let taken = images.prefix(room)
        list.append(contentsOf: taken.map { XcodeScreenshot(imageData: $0) })
        xcodeProject.sets[setIndex].wells[device.rawValue] = list
        return images.count - taken.count
    }

    func removeScreenshot(_ id: XcodeScreenshot.ID, from device: XcodeWellDevice, inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex) else { return }
        xcodeProject.sets[setIndex].wells[device.rawValue]?.removeAll { $0.id == id }
    }

    /// REM: D-041 — flip one wrong-size screenshot between Fill and Fit.
    func setFitMode(_ mode: XcodeFitMode, for id: XcodeScreenshot.ID, in device: XcodeWellDevice,
                    inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex),
              var list = xcodeProject.sets[setIndex].wells[device.rawValue],
              let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].fitMode = mode
        xcodeProject.sets[setIndex].wells[device.rawValue] = list
    }

    /// One step earlier in upload order. REM: order matters — D-051 numbers the exported files
    /// "in upload order", so the well's order IS the App Store order.
    func moveScreenshotEarlier(_ id: XcodeScreenshot.ID, in device: XcodeWellDevice, inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex),
              var list = xcodeProject.sets[setIndex].wells[device.rawValue],
              let i = list.firstIndex(where: { $0.id == id }), i > 0 else { return }
        list.swapAt(i, i - 1)
        xcodeProject.sets[setIndex].wells[device.rawValue] = list
    }
}

// MARK: - Sizes (D-001, D-030–D-034) and the wrong-size check (D-040)

/// A picture's size in pixels, the way it shows on screen (EXIF rotation applied).
struct WellPixelSize: Hashable, Sendable {
    let width: Int
    let height: Int
    var aspect: Double { Double(width) / Double(height) }
    var sideways: WellPixelSize { WellPixelSize(width: height, height: width) }
    /// "1206 × 2622" — the way App Store Connect writes it.
    var text: String { "\(width) × \(height)" }
}

extension XcodeWellDevice {
    /// REM: The accepted screenshot sizes, exactly as the sheet lists them (App Store Connect
    /// screenshot specifications, read 2026-11-05). "App Store Connect is our source of truth."
    ///   D-031 iPhone "1206 × 2622 or 1179 × 2556"
    ///   D-032 iPad "13-inch, 2064 × 2752 or 2048 × 2732"
    ///   D-030 iPhone Duo "outer 1398 × 2034, inner 2007 × 2853 (landscape flipped)"
    ///   D-001 Mac "16:10 at 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800"
    ///   D-034 Apple Watch "one size per model, for example 422 × 514 (Ultra 4, Ultra 3) or
    ///         416 × 496 (Series 10–12)" — only the two the sheet names; a later sheet line
    ///         can add the other models.
    ///   D-033 Apple TV "1920 × 1080 or 3840 × 2160"
    var acceptedSizes: [WellPixelSize] {
        func s(_ w: Int, _ h: Int) -> WellPixelSize { WellPixelSize(width: w, height: h) }
        switch self {
        case .iPhone:     return [s(1206, 2622), s(1179, 2556)]
        case .iPad:       return [s(2064, 2752), s(2048, 2732)]
        case .iPhoneDuo:  return [s(1398, 2034), s(2007, 2853)]
        case .mac:        return [s(1280, 800), s(1440, 900), s(2560, 1600), s(2880, 1800)]
        case .appleWatch: return [s(422, 514), s(416, 496)]
        case .appleTV:    return [s(1920, 1080), s(3840, 2160)]
        }
    }

    /// REM: D-030 says the Duo's sizes come "landscape flipped" too. App Store Connect takes
    /// iPhone and iPad screenshots either way up as well, so those three wells accept the
    /// sideways size. Mac and Apple TV are landscape only, the Watch upright only.
    var turnsSideways: Bool {
        switch self {
        case .iPhone, .iPad, .iPhoneDuo: true
        case .mac, .appleWatch, .appleTV: false
        }
    }

    /// Every size this well takes, upright first.
    var allAcceptedSizes: [WellPixelSize] {
        turnsSideways ? acceptedSizes + acceptedSizes.map(\.sideways) : acceptedSizes
    }

    func accepts(_ size: WellPixelSize) -> Bool { allAcceptedSizes.contains(size) }

    /// "1206 × 2622 or 1179 × 2556, upright or sideways" — for the note in the well.
    var acceptedSizesText: String {
        let list = acceptedSizes.map(\.text)
        let joined = list.count <= 2
            ? list.joined(separator: " or ")
            : list.dropLast().joined(separator: ", ") + " or " + list.last!
        return turnsSideways ? joined + ", upright or sideways" : joined
    }

    /// REM: D-042 — "every wrong-size image is resized to its well." The well takes more than
    /// one size, so pick the one that changes the picture least: same way up first, then the
    /// closest shape, then (shapes alike within 2 %) the closest pixel count, so a slightly
    /// small iPhone shot goes to 1179 × 2556 rather than being scaled up to 1206 × 2622.
    func exportSize(for size: WellPixelSize) -> WellPixelSize {
        let all = allAcceptedSizes
        let sameWay = all.filter { size.width == size.height || ($0.width > $0.height) == (size.width > size.height) }
        let pool = sameWay.isEmpty ? all : sameWay
        func shapeGap(_ t: WellPixelSize) -> Double { abs(log(t.aspect / size.aspect)) }
        let best = pool.map(shapeGap).min() ?? 0
        let area = Double(size.width * size.height)
        return pool.filter { shapeGap($0) <= best + 0.02 }
            .min { abs(Double($0.width * $0.height) - area) < abs(Double($1.width * $1.height) - area) }
            ?? pool[0]
    }
}

/// The picture's pixel size, read from the file's header without decoding it. Rotation from
/// the camera (EXIF orientations 5–8) swaps width and height, the same way the thumbnail
/// shows it, so the check matches what you see.
nonisolated func wellPixelSize(_ data: Data) -> WellPixelSize? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
    let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
    return (5...8).contains(orientation) ? WellPixelSize(width: h, height: w)
                                         : WellPixelSize(width: w, height: h)
}

/// REM: D-042 — the resize itself. Fill or Fit (D-041), centered, never stretched ("check
/// nothing was skewed"). Drawn onto an opaque canvas — D-035 "no transparency" — so Fit's
/// bars are solid black. The thumbnails in the wells run THIS function at thumbnail size, so
/// what you see in the well is the shape the export gets.
nonisolated func wellResized(_ image: CGImage, to size: WellPixelSize, mode: XcodeFitMode) -> CGImage? {
    let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil)
        ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size.width, height: size.height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    let sx = Double(size.width) / Double(image.width)
    let sy = Double(size.height) / Double(image.height)
    let k = mode == .fill ? max(sx, sy) : min(sx, sy)
    let w = Double(image.width) * k, h = Double(image.height) * k
    ctx.draw(image, in: CGRect(x: (Double(size.width) - w) / 2, y: (Double(size.height) - h) / 2,
                               width: w, height: h))
    return ctx.makeImage()
}

/// A screenshot whose size isn't one its well takes, and what the export does about it.
struct WellMismatch: Equatable {
    let size: WellPixelSize
    let exportSize: WellPixelSize
}

// MARK: - The Apple TV icon and Top Shelf wells (D-021, D-027)

/// REM: D-021 "the rounded-rectangle icon, Top Shelf and wide Top Shelf"; D-027 "light and
/// dark" for the Top Shelf banner. One picture per well. The raw values are the keys in the
/// Original set's `wells`, beside the device keys, so the file format doesn't change and a
/// build that doesn't know these wells still opens (and keeps) them.
enum XcodeTVArtWell: String, CaseIterable, Identifiable {
    case icon = "appleTVIcon"
    case topShelf = "appleTVTopShelf"
    case topShelfDark = "appleTVTopShelfDark"
    case wideTopShelf = "appleTVTopShelfWide"
    case wideTopShelfDark = "appleTVTopShelfWideDark"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon:             "Apple TV Icon"
        case .topShelf:         "Top Shelf, Light"
        case .topShelfDark:     "Top Shelf, Dark"
        case .wideTopShelf:     "Wide Top Shelf, Light"
        case .wideTopShelfDark: "Wide Top Shelf, Dark"
        }
    }

    /// Verified against the app's own SFSymbolNames.json.
    var systemImage: String {
        switch self {
        case .icon:                          "appletv"
        case .topShelf, .wideTopShelf:       "sun.max"
        case .topShelfDark, .wideTopShelfDark: "moon"
        }
    }

    var slot: IconSetExport.TVSlot {
        switch self {
        case .icon:                           .icon
        case .topShelf, .topShelfDark:        .topShelf
        case .wideTopShelf, .wideTopShelfDark: .topShelfWide
        }
    }

    var appearance: IconAppearance {
        switch self {
        case .topShelfDark, .wideTopShelfDark: .dark
        default:                               .light
        }
    }

    /// REM: The sizes, biggest first. Top Shelf from D-027: "Top Shelf 1920 × 720 (@2x 3840 ×
    /// 1440), wide 2320 × 720 (@2x 4640 × 1440)". The icon's are the ones the Icon Set export
    /// already writes into the brand assets (IconSetExport `tvImages`): App Store 1280 × 768,
    /// home screen 400 × 240 (@2x 800 × 480). The sheet gives no icon size of its own.
    var acceptedSizes: [WellPixelSize] {
        func s(_ w: Int, _ h: Int) -> WellPixelSize { WellPixelSize(width: w, height: h) }
        switch self {
        case .icon:                          return [s(1280, 768), s(800, 480), s(400, 240)]
        case .topShelf, .topShelfDark:       return [s(3840, 1440), s(1920, 720)]
        case .wideTopShelf, .wideTopShelfDark: return [s(4640, 1440), s(2320, 720)]
        }
    }

    func accepts(_ size: WellPixelSize) -> Bool { acceptedSizes.contains(size) }

    /// "3840 × 1440 or 1920 × 720" — for the note in the well.
    var acceptedSizesText: String {
        let list = acceptedSizes.map(\.text)
        return list.count <= 2 ? list.joined(separator: " or ")
            : list.dropLast().joined(separator: ", ") + " or " + list.last!
    }

    /// REM: D-042 — a wrong-size picture is resized to its well. Every size in a well is the
    /// same shape, and the export makes all of them from the picture, so the note names the
    /// biggest.
    var exportSize: WellPixelSize { acceptedSizes[0] }

    /// What the empty well says. REM: D-027 — the Top Shelf "is a banner … with the app's
    /// name in big type across it".
    var dropHint: String {
        switch self {
        case .icon: "Drop your Apple TV icon here"
        case .topShelf, .wideTopShelf: "Drop your light Top Shelf banner here"
        case .topShelfDark, .wideTopShelfDark: "Drop your dark Top Shelf banner here"
        }
    }

    /// What the export does when this well is empty, in the well, so an empty well isn't a
    /// surprise. REM: an empty well keeps the Icon Set export's picture from the canvas.
    var emptyNote: String {
        switch self {
        case .icon, .topShelf, .wideTopShelf:
            "While it's empty, the export makes this one from your canvas."
        case .topShelfDark, .wideTopShelfDark:
            "While it's empty, the export makes this one from your canvas, unless the light well "
                + "above has a picture: then your light banner shows in dark mode too."
        }
    }
}

extension XcodeWellSet {
    /// The picture in one Apple TV well, if any. REM: D-002 — only the Original set has them.
    func tvArt(_ well: XcodeTVArtWell) -> XcodeScreenshot? {
        kind == .original ? wells[well.rawValue]?.first : nil
    }
}

extension ImageDocument {
    /// Put a picture in an Apple TV well, replacing the one there — each well holds one.
    /// Always the Original set (D-002).
    func setTVArt(_ data: Data, for well: XcodeTVArtWell) {
        xcodeProject.sets[xcodeProject.originalIndex].wells[well.rawValue] = [XcodeScreenshot(imageData: data)]
    }

    func removeTVArt(_ well: XcodeTVArtWell) {
        xcodeProject.sets[xcodeProject.originalIndex].wells[well.rawValue] = nil
    }

    /// REM: D-041 — Fill or Fit for a wrong-size picture in an Apple TV well.
    func setTVArtFitMode(_ mode: XcodeFitMode, for well: XcodeTVArtWell) {
        let i = xcodeProject.originalIndex
        guard var list = xcodeProject.sets[i].wells[well.rawValue], !list.isEmpty else { return }
        list[0].fitMode = mode
        xcodeProject.sets[i].wells[well.rawValue] = list
    }
}

// MARK: - Bringing an image in

/// What a well accepts from a drop: a picture file from the Finder or Files, a photo dragged
/// from Photos, or any app's image. JPEG and PNG keep their own bytes; anything else becomes
/// a PNG (see `XcodeScreenshot`).
struct WellDropImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .png) { WellDropImage(data: $0) }
        DataRepresentation(importedContentType: .jpeg) { WellDropImage(data: $0) }
        DataRepresentation(importedContentType: .image) { data in
            guard let png = wellPNG(fromImageData: data) else { throw CocoaError(.fileReadCorruptFile) }
            return WellDropImage(data: png)
        }
    }
}

/// A file picked with the Add File button: same rule as a drop.
private func wellImageData(fromFile url: URL) -> Data? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return nil }
    let type = UTType(filenameExtension: url.pathExtension)
    if let type, type.conforms(to: .png) || type.conforms(to: .jpeg) { return data }
    return wellPNG(fromImageData: data)
}

/// Any decodable picture → PNG bytes. Its own `nonisolated` copy of ContentView's
/// `pngData(fromImageData:)`: this target defaults to the main actor, and a drop's data
/// arrives off it, so the main-actor helper can't be called from the import closure.
nonisolated private func wellPNG(fromImageData data: Data) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, cg, nil)
    return CGImageDestinationFinalize(dest) ? out as Data : nil
}

/// A small picture for the well, decoded once per screenshot — never the full-size image.
nonisolated private func wellThumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

// MARK: - The wells in the Layers list

/// REM: D-012 — "the wells show in the Layers list as drop slots, each showing what's in it."
/// A Section placed in the Layers panel's own List, under the layers, shown only while Xcode
/// Project Support is on. It never touches the layer stack: the layer rows' move and delete
/// work on their own ForEach and are unchanged.
struct XcodeWellsSection: View {
    @Bindable var document: ImageDocument

    /// Which set's wells you're looking at. nil (or a set that's gone) means the Original.
    @State private var selectedSetID: XcodeWellSet.ID?
    @State private var renamingID: XcodeWellSet.ID?
    @State private var draftName = ""
    @State private var pendingDelete: XcodeWellSet?

    private var setIndex: Int {
        selectedSetID.flatMap { id in document.xcodeProject.sets.firstIndex { $0.id == id } }
            ?? document.xcodeProject.originalIndex
    }

    var body: some View {
        let wells = document.xcodeProject
        let index = setIndex
        let set = wells.sets[index]
        Section {
            setControls(set: set, wells: wells)
            ForEach(set.kind.devices) { device in
                XcodeWellRow(document: document, device: device, setIndex: index)
                // REM: D-021 — the icon and Top Shelf wells go with "the TV screenshots";
                // D-002 — on the Original page only, never a test version.
                if device == .appleTV && set.kind == .original {
                    ForEach(XcodeTVArtWell.allCases) { well in
                        XcodeTVArtRow(document: document, well: well)
                    }
                }
            }
        } header: {
            // REM: D-023 — the set's name shows, so the sets read as siblings of one another.
            Text("Xcode Project · \(set.name)")
                .scaledFont(18, weight: .semibold)
                .accessibilityLabel("Xcode wells")
        }
    }

    /// REM: D-023 and D-003 — choosing, adding, renaming and deleting sets. A Picker to choose
    /// which set's wells you see (his rule allows a Picker for choosing); every action is a
    /// visible button with words on it — no "…" menu.
    @ViewBuilder
    private func setControls(set: XcodeWellSet, wells: XcodeProjectWells) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Showing").scaledFont(18).foregroundStyle(.secondary)
                Picker("Set", selection: Binding(get: { set.id }, set: { selectedSetID = $0 })) {
                    ForEach(wells.sets) { s in
                        Text(pickerTitle(s)).tag(s.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .scaledFont(18)
                .accessibilityLabel("Choose set")
                .help("Choose which page's wells you see")
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Button { add(.testVersion) } label: {
                    Label("Add Test Version", systemImage: "plus.square.on.square").scaledFont(18)
                }
                .disabled(!wells.canAddTestVersion)
                .help(wells.canAddTestVersion
                      ? "Add a Product Page Optimization test version with its own wells"
                      : "You have \(XcodeProjectWells.maxTestVersions) test versions, the most App Store Connect allows")
                .accessibilityLabel("Add test version")
                Button { add(.customPage) } label: {
                    Label("Add Custom Page", systemImage: "doc.badge.plus").scaledFont(18)
                }
                .disabled(!wells.canAddCustomPage)
                .help(wells.canAddCustomPage
                      ? "Add a custom product page with its own iPhone and iPad wells"
                      : "You have \(XcodeProjectWells.maxCustomPages) custom pages, the most App Store Connect allows")
                .accessibilityLabel("Add custom page")
            }
            .buttonStyle(.borderless)
            // REM: the Original "can't be removed" (and keeps its name — D-051's folder is
            // "<project>-Original"), so it shows no Rename or Delete at all rather than dead ones.
            if set.kind != .original {
                HStack(spacing: 12) {
                    Button { startRename(set) } label: {
                        Label("Rename", systemImage: "pencil").scaledFont(18)
                    }
                    .help("Rename “\(set.name)”; its export folder takes the new name")
                    .accessibilityLabel("Rename set")
                    Button(role: .destructive) { askDelete(set) } label: {
                        Label("Delete", systemImage: "trash").scaledFont(18)
                    }
                    .help("Delete “\(set.name)” and its wells")
                    .accessibilityLabel("Delete set")
                }
                .buttonStyle(.borderless)
            }
            Text(kindNote(set, wells: wells))
                .scaledFont(18)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sets")
        .alert("Rename Set", isPresented: Binding(get: { renamingID != nil },
                                                  set: { if !$0 { renamingID = nil } })) {
            TextField("Name", text: $draftName)
                .accessibilityLabel("Set name")
            Button("Cancel", role: .cancel) { renamingID = nil }
            Button("Rename") { commitRename() }
        } message: {
            Text("This name is also the set's folder name when you export the project bundle.")
        }
        // REM: his rule — deleting a set that has screenshots asks first; it destroys work.
        .confirmationDialog(pendingDelete.map { "Delete “\($0.name)”?" } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Set and Screenshots", role: .destructive) {
                if let doomed = pendingDelete { delete(doomed) }
                pendingDelete = nil
            }
            .accessibilityLabel("Delete set")
            Button("Keep Set", role: .cancel) { pendingDelete = nil }
                .accessibilityLabel("Keep set")
        } message: {
            if let doomed = pendingDelete {
                let n = doomed.screenshotCount
                Text("Its \(n) screenshot\(n == 1 ? "" : "s") will be deleted with it.")
            }
        }
    }

    private func pickerTitle(_ s: XcodeWellSet) -> String {
        switch s.kind {
        case .original:    "Original page"
        case .testVersion: "Test version: \(s.name)"
        case .customPage:  "Custom page: \(s.name)"
        }
    }

    /// One line under the buttons saying what this set is, in App Store Connect's terms.
    private func kindNote(_ s: XcodeWellSet, wells: XcodeProjectWells) -> String {
        switch s.kind {
        case .original:
            return "Your original App Store page. You can add up to \(XcodeProjectWells.maxTestVersions) "
                + "test versions and up to \(XcodeProjectWells.maxCustomPages) custom pages."
        case .testVersion:
            return "A Product Page Optimization test version, \(wells.count(of: .testVersion)) of "
                + "\(XcodeProjectWells.maxTestVersions). It varies the screenshots; your app keeps one icon."
        case .customPage:
            return "A custom product page, \(wells.count(of: .customPage)) of \(XcodeProjectWells.maxCustomPages). "
                + "App Store Connect offers custom pages for iPhone and iPad only."
        }
    }

    private func add(_ kind: XcodeSetKind) {
        guard let id = document.addWellSet(kind),
              let added = document.xcodeProject.sets.first(where: { $0.id == id }) else { return }
        selectedSetID = id
        document.say("Added \(added.name). Its wells are showing; Rename changes its name.", kind: .edit)
    }

    private func startRename(_ s: XcodeWellSet) {
        draftName = s.name
        renamingID = s.id
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        renamingID = nil
        // A name that can't be used leaves the old one and says why in the status line.
        if let problem = document.renameWellSet(id, to: draftName) {
            document.say(problem, kind: .warning)
        }
    }

    private func askDelete(_ s: XcodeWellSet) {
        if s.screenshotCount > 0 { pendingDelete = s } else { delete(s) }
    }

    private func delete(_ s: XcodeWellSet) {
        document.removeWellSet(s.id)
        if selectedSetID == s.id { selectedSetID = nil }
        document.say("Deleted \(s.name). Showing your original page.", kind: .edit)
    }
}

/// One drop slot: the device, how full it is, the screenshots in upload order, and two
/// buttons for when dragging isn't handy (an iPhone, mostly).
struct XcodeWellRow: View {
    @Bindable var document: ImageDocument
    let device: XcodeWellDevice
    let setIndex: Int

    @State private var isTargeted = false
    @State private var importing = false
    /// Each screenshot's pixel size, read once from its header (D-040's check needs it).
    @State private var sizes: [XcodeScreenshot.ID: WellPixelSize] = [:]

    private var shots: [XcodeScreenshot] {
        document.xcodeProject.sets.indices.contains(setIndex)
            ? document.xcodeProject.sets[setIndex].screenshots(for: device) : []
    }
    private var isFull: Bool { shots.count >= XcodeProjectWells.maxPerDevice }

    /// REM: D-040 — "A wrong-size image dropped in a well gets a warning". nil while the size
    /// is still being read, or when it's a size this well takes.
    private func mismatch(_ shot: XcodeScreenshot) -> WellMismatch? {
        guard let size = sizes[shot.id], !device.accepts(size) else { return nil }
        return WellMismatch(size: size, exportSize: device.exportSize(for: size))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: device.systemImage)
                    .scaledFont(18)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                // REM: the count is the "showing what's in it" half of D-012, in words:
                // "iPhone · 3 of 10".
                Text("\(device.title) · \(shots.count) of \(XcodeProjectWells.maxPerDevice)")
                    .scaledFont(18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                // No "…" menu — his rule: actions show as buttons.
                Button { addCanvas() } label: {
                    Image(systemName: "photo.badge.plus").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .disabled(isFull)
                .help("Add the canvas as it looks now to the \(device.title) well")
                .accessibilityLabel("Add canvas")
                Button { importing = true } label: {
                    Image(systemName: "doc.badge.plus").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .disabled(isFull)
                .help("Add pictures from a file to the \(device.title) well")
                .accessibilityLabel("Add file")
            }
            strip
            wrongSizeNotes
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1,
                                                 dash: shots.isEmpty ? [6, 4] : []))
        )
        .contentShape(Rectangle())
        .dropDestination(for: WellDropImage.self, isEnabled: !isFull) { items, _ in
            add(items.map(\.data))
        }
        .onDropSessionUpdated { session in
            // Highlight while something is held over the well.
            switch session.phase {
            case .entering, .active: isTargeted = true
            default: isTargeted = false
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .image],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            add(urls.compactMap(wellImageData(fromFile:)))
        }
        .task(id: shots.map(\.id)) {
            // Read sizes only for screenshots not yet measured; keep the rest.
            let missing = shots.filter { sizes[$0.id] == nil }.map { ($0.id, $0.imageData) }
            guard !missing.isEmpty else { return }
            let found = await Task.detached(priority: .utility) {
                missing.compactMap { id, data in wellPixelSize(data).map { (id, $0) } }
            }.value
            for (id, size) in found { sizes[id] = size }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.title) well")
    }

    /// REM: D-040 — of "an exclamation popup, or a text note on the wells page", the text
    /// note: it stays in the well beside the picture it's about, needs no tap to dismiss, and
    /// a popup over the Layers list would stop you mid-drop. Each thumbnail also carries an
    /// exclamation mark. The note says what D-042 will do at export — "says so plainly".
    @ViewBuilder private var wrongSizeNotes: some View {
        let wrong = shots.enumerated().compactMap { i, shot in
            mismatch(shot).map { (position: i + 1, shot: shot, mismatch: $0) }
        }
        if !wrong.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(wrong, id: \.shot.id) { item in
                    Label {
                        Text(wrongSizeText(position: item.position, mismatch: item.mismatch,
                                           mode: item.shot.fitMode))
                            .scaledFont(18)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .scaledFont(18)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func wrongSizeText(position: Int, mismatch m: WellMismatch, mode: XcodeFitMode) -> String {
        let how = mode == .fit
            ? "fit inside it, all of it showing, with black bars where it doesn't reach"
            : "filled to its edges, with what spills over trimmed"
        return "Screenshot \(position) is \(m.size.text). The \(device.title) well takes "
            + "\(device.acceptedSizesText). At export it's resized to \(m.exportSize.text), "
            + "\(how). Nothing is stretched."
    }

    @ViewBuilder private var strip: some View {
        if shots.isEmpty {
            Text("Drop \(device.title) screenshots here")
                .scaledFont(18)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { i, shot in
                        XcodeWellThumbnail(
                            shot: shot, position: i + 1, mismatch: mismatch(shot),
                            onSetFitMode: { mode in
                                document.setFitMode(mode, for: shot.id, in: device, inSet: setIndex)
                            },
                            onRemove: { document.removeScreenshot(shot.id, from: device, inSet: setIndex) },
                            onMoveEarlier: i == 0 ? nil : {
                                document.moveScreenshotEarlier(shot.id, in: device, inSet: setIndex)
                            })
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func addCanvas() {
        guard let png = ContentView.renderCanvasPNG(document: document) else {
            document.say("Could not render the canvas for the \(device.title) well", kind: .warning)
            return
        }
        add([png])
    }

    private func add(_ images: [Data]) {
        guard !images.isEmpty else { return }
        let before = shots.count
        let leftOut = document.addScreenshots(images, to: device, inSet: setIndex)
        let added = shots.count - before
        // REM: D-040 — measure the new arrivals right away (a header read, no decode) so the
        // warning is there the moment the drop lands, not a beat later.
        let newShots = shots.suffix(added)
        for shot in newShots where sizes[shot.id] == nil {
            sizes[shot.id] = wellPixelSize(shot.imageData)
        }
        let wrong = newShots.filter { mismatch($0) != nil }.count
        if leftOut > 0 {
            document.say("\(device.title) holds \(XcodeProjectWells.maxPerDevice) screenshots — "
                         + "\(leftOut) not added", kind: .warning)
        } else if wrong > 0 {
            document.say("Added \(added) to the \(device.title) well — \(wrong) "
                         + (wrong == 1 ? "isn't" : "aren't") + " a size it takes; see the note in the well",
                         kind: .warning)
        } else if added > 0 {
            document.say("Added \(added) to the \(device.title) well", kind: .edit)
        }
    }
}

/// REM: D-021/D-027 — one Apple TV well: the icon, or a Top Shelf banner in light or dark.
/// Built like `XcodeWellRow` (drop, Add Canvas, Add File, the D-040 note and D-041's Fill /
/// Fit), but it holds one picture: a new one replaces the old, and the status line says so.
struct XcodeTVArtRow: View {
    @Bindable var document: ImageDocument
    let well: XcodeTVArtWell

    @State private var isTargeted = false
    @State private var importing = false
    @State private var size: WellPixelSize?
    @State private var measuredID: XcodeScreenshot.ID?

    private var art: XcodeScreenshot? {
        document.xcodeProject.sets[document.xcodeProject.originalIndex].tvArt(well)
    }

    /// REM: D-040 — the wrong-size check, against this well's sizes.
    private var mismatch: WellMismatch? {
        guard let art, measuredID == art.id, let size, !well.accepts(size) else { return nil }
        return WellMismatch(size: size, exportSize: well.exportSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: well.systemImage)
                    .scaledFont(18)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                // REM: D-012 "each showing what's in it" — "1 of 1" like the screenshot wells.
                Text("\(well.title) · \(art == nil ? 0 : 1) of 1")
                    .scaledFont(18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { addCanvas() } label: {
                    Image(systemName: "photo.badge.plus").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .help(art == nil ? "Put the canvas as it looks now in the \(well.title) well"
                                 : "Replace the \(well.title) picture with the canvas as it looks now")
                .accessibilityLabel("Add canvas")
                Button { importing = true } label: {
                    Image(systemName: "doc.badge.plus").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .help(art == nil ? "Put a picture from a file in the \(well.title) well"
                                 : "Replace the \(well.title) picture with one from a file")
                .accessibilityLabel("Add file")
            }
            content
            if let mismatch, let art {
                Label {
                    Text(wrongSizeText(mismatch, mode: art.fitMode))
                        .scaledFont(18)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(18)
                        .foregroundStyle(.yellow)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1,
                                                 dash: art == nil ? [6, 4] : []))
        )
        .contentShape(Rectangle())
        .dropDestination(for: WellDropImage.self) { items, _ in
            guard let first = items.first else { return false }
            put(first.data)
            return true
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active: isTargeted = true
            default: isTargeted = false
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .image],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard let data = wellImageData(fromFile: url) else {
                document.say("Could not read that picture for the \(well.title) well", kind: .warning)
                return
            }
            put(data)
        }
        .task(id: art?.id) {
            guard let art, measuredID != art.id else { return }
            let data = art.imageData, id = art.id
            size = await Task.detached(priority: .utility) { wellPixelSize(data) }.value
            measuredID = id
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(well.title) well")
    }

    @ViewBuilder private var content: some View {
        if let art {
            ScrollView(.horizontal, showsIndicators: false) {
                XcodeWellThumbnail(
                    shot: art, position: 1, mismatch: mismatch,
                    onSetFitMode: { document.setTVArtFitMode($0, for: well) },
                    onRemove: {
                        document.removeTVArt(well)
                        document.say("Removed the \(well.title) picture", kind: .edit)
                    },
                    onMoveEarlier: nil,
                    artName: well.title)
                    .padding(.vertical, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(well.dropHint)
                    .scaledFont(18)
                    .foregroundStyle(.secondary)
                Text("Size: \(well.acceptedSizesText). \(well.emptyNote)")
                    .scaledFont(18)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
    }

    private func wrongSizeText(_ m: WellMismatch, mode: XcodeFitMode) -> String {
        let how = mode == .fit
            ? "fit inside it, all of it showing, with black bars where it doesn't reach"
            : "filled to its edges, with what spills over trimmed"
        let made = well.acceptedSizes.map(\.text).joined(separator: " and ")
        return "This picture is \(m.size.text). The \(well.title) well takes \(well.acceptedSizesText). "
            + "At export it's resized to \(made), \(how). Nothing is stretched."
    }

    private func addCanvas() {
        guard let png = ContentView.renderCanvasPNG(document: document) else {
            document.say("Could not render the canvas for the \(well.title) well", kind: .warning)
            return
        }
        put(png)
    }

    private func put(_ data: Data) {
        let replacing = art != nil
        document.setTVArt(data, for: well)
        // REM: D-040 — measured right away so the warning is there the moment the drop lands.
        let measured = wellPixelSize(data)
        size = measured
        measuredID = art?.id
        let wrong = measured.map { !well.accepts($0) } ?? false
        if wrong {
            document.say("\(replacing ? "Replaced" : "Added") the \(well.title) picture — it isn't a "
                         + "size the well takes; see the note in the well", kind: .warning)
        } else {
            document.say("\(replacing ? "Replaced" : "Added") the \(well.title) picture", kind: .edit)
        }
    }
}

/// One screenshot in a well: the picture, its place in upload order, Remove, and Move Earlier.
struct XcodeWellThumbnail: View {
    let shot: XcodeScreenshot
    let position: Int
    /// REM: D-041 — "Once a mismatch is found, the image shows a toggle". nil = right size,
    /// no toggle.
    let mismatch: WellMismatch?
    let onSetFitMode: (XcodeFitMode) -> Void
    let onRemove: () -> Void
    let onMoveEarlier: (() -> Void)?
    /// Set for a picture in an Apple TV well: what VoiceOver calls it, and no upload number
    /// (a well that holds one picture has no order).
    var artName: String? = nil

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 84

    private var spokenName: String { artName ?? "Screenshot \(position)" }
    @State private var thumb: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumb {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.secondary.opacity(0.15)
                        .aspectRatio(0.5, contentMode: .fit)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // REM: D-040 — the exclamation mark on the picture itself.
                if mismatch != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(18)
                        .symbolRenderingMode(.multicolor)
                        .padding(2)
                        .accessibilityLabel("Wrong size")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(mismatch == nil ? spokenName : "\(spokenName), wrong size")
            if mismatch != nil { fillFitToggle }
            HStack(spacing: 6) {
                if let onMoveEarlier {
                    Button(action: onMoveEarlier) {
                        Image(systemName: "chevron.left").scaledFont(18)
                    }
                    .buttonStyle(.borderless)
                    .help("Move this screenshot one place earlier")
                    .accessibilityLabel("Move earlier")
                }
                if artName == nil {
                    Text("\(position)")
                        .scaledFont(18, monospacedDigit: true)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .help(artName == nil ? "Remove this screenshot from the well" : "Remove this picture from the well")
                .accessibilityLabel(artName == nil ? "Remove screenshot" : "Remove picture")
            }
        }
        .task(id: PreviewKey(id: shot.id, mode: shot.fitMode, mismatch: mismatch)) {
            // REM: D-042 — a wrong-size screenshot shows as the export will make it: the same
            // `wellResized` Fill or Fit, run at thumbnail size, so you can see before export
            // that nothing is skewed.
            let data = shot.imageData, mode = shot.fitMode, target = mismatch?.exportSize
            thumb = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let small = wellThumbnail(data, maxPixels: 256) else { return nil }
                guard let target else { return small }
                let k = 256 / Double(max(target.width, target.height))
                let size = WellPixelSize(width: max(1, Int((Double(target.width) * k).rounded())),
                                         height: max(1, Int((Double(target.height) * k).rounded())))
                return wellResized(small, to: size, mode: mode) ?? small
            }.value
        }
    }

    private struct PreviewKey: Equatable {
        let id: XcodeScreenshot.ID
        let mode: XcodeFitMode
        let mismatch: WellMismatch?
    }

    /// REM: D-041 — "Fill ( ) Fit", in that order, as two visible buttons (no menu — his
    /// rule). Built from plain buttons rather than a segmented Picker so the words keep the
    /// 18 pt Dynamic Type font on iPhone and iPad too.
    private var fillFitToggle: some View {
        HStack(spacing: 0) {
            fillFitButton("Fill", mode: .fill, help: "Fill the well's size, trimming the edges that spill over")
            fillFitButton("Fit", mode: .fit, help: "Fit the whole picture inside the well's size, with bars where it doesn't reach")
        }
        .background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }

    private func fillFitButton(_ title: String, mode: XcodeFitMode, help: String) -> some View {
        let on = shot.fitMode == mode
        return Button { onSetFitMode(mode) } label: {
            Text(title)
                .scaledFont(18, weight: on ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(Capsule().fill(on ? Color.accentColor : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The two switches (D-011)

/// REM: D-011, the View-menu half — "the ipad has a menubar". Not inside `#if os(macOS)`: the
/// same command shows in the iPad's menu bar. ⌥⌘X ("X" for Xcode) is free in this app — the
/// shortcuts in use are ⌘A C E L N S V X Z, ⇧⌘N S X Z.
struct XcodeProjectCommands: Commands {
    @AppStorage(XcodeProjectSupport.storageKey) private var isOn = XcodeProjectSupport.defaultValue

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Xcode Project Support", isOn: $isOn)
                .keyboardShortcut("x", modifiers: [.command, .option])
        }
    }
}

#if os(macOS)
/// REM: D-011, the Settings half, on the Mac: Image Producer ▸ Settings… (⌘,). The iPhone and
/// iPad get the same switch in the Settings app through Settings.bundle — "iphones dont"
/// have a menu bar, and the iOS Settings scene doesn't exist (SwiftUI `Settings` is
/// macOS-only, checked in the iOS SDK).
struct XcodeProjectSettingsView: View {
    @AppStorage(XcodeProjectSupport.storageKey) private var isOn = XcodeProjectSupport.defaultValue

    var body: some View {
        Form {
            Toggle("Xcode Project Support", isOn: $isOn)
                .scaledFont(18)
                .accessibilityLabel("Xcode Project Support")
            Text("Shows screenshot wells for your App Store pages in the Layers list. "
                 + "Drop screenshots for each device into its well; they save with your project.")
                .scaledFont(18)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520)
    }
}
#endif
