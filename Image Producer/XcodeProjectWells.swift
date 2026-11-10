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
//  REM: Export to Project Bundle (D-050–051) and D-042's "resized" report are in
//  ProjectBundleExport.swift; the export calls `wellResized` below.
//  REM: WHAT IS DELIBERATELY NOT HERE. The Apple TV icon and Top Shelf wells (D-021/027), the creative
//  asset wells (D-024/025/028) and video (D-070+) are later pieces. His rule: no placeholders,
//  dead buttons or "coming soon" — so they are absent, not stubbed.
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

/// One set — a whole App Store page's worth of screenshots, one well per device.
/// REM: D-023 — "your original page plus up to 3 Product Page Optimization test versions".
struct XcodeWellSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// Keyed by `XcodeWellDevice.rawValue`, NOT by the enum. A String key means a file written
    /// by a later build with a device this build doesn't know still OPENS here — the unknown
    /// well is simply not shown — instead of the whole document failing to decode.
    var wells: [String: [XcodeScreenshot]] = [:]

    func screenshots(for device: XcodeWellDevice) -> [XcodeScreenshot] { wells[device.rawValue] ?? [] }
}

/// Every set for this project. REM: D-023 — modeled as an ARRAY of sets from day one so the
/// Product Page Optimization versions can be added later without changing the file format.
/// Only "Original" has UI in this piece.
struct XcodeProjectWells: Codable, Equatable {
    /// REM: D-022 — "Up to 10 screenshots per device, as per App Store Connect."
    static let maxPerDevice = 10
    /// REM: D-023 — "Up to 4 sets per device". Original + 3 test versions.
    static let maxSets = 4
    static let originalName = "Original"

    /// REM: D-023 — the "Original" set first. Always present.
    var sets: [XcodeWellSet] = [XcodeWellSet(name: XcodeProjectWells.originalName)]

    init() {}

    /// Older builds' files have no wells, and a file could in theory carry an empty list:
    /// either way the Original set is guaranteed to exist and to come first.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sets = try c.decodeIfPresent([XcodeWellSet].self, forKey: .sets) ?? []
        if !sets.contains(where: { $0.name == Self.originalName }) {
            sets.insert(XcodeWellSet(name: Self.originalName), at: 0)
        }
    }

    /// Nothing in any well — the manifest leaves the key out entirely.
    var isEmpty: Bool { sets.allSatisfy { $0.wells.values.allSatisfy(\.isEmpty) } }

    var originalIndex: Int { sets.firstIndex { $0.name == Self.originalName } ?? 0 }
}

extension ImageDocument {
    /// Add screenshots to one well of one set, in the order given, up to the ten-per-device
    /// limit. Returns how many were left out because the well was full.
    @discardableResult
    func addScreenshots(_ images: [Data], to device: XcodeWellDevice, inSet setIndex: Int) -> Int {
        guard xcodeProject.sets.indices.contains(setIndex) else { return images.count }
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

    var body: some View {
        let setIndex = document.xcodeProject.originalIndex
        Section {
            ForEach(XcodeWellDevice.allCases) { device in
                XcodeWellRow(document: document, device: device, setIndex: setIndex)
            }
        } header: {
            // REM: D-023 — the set's name shows, so later sets read as siblings of this one.
            Text("Xcode Project · \(document.xcodeProject.sets[setIndex].name)")
                .scaledFont(18, weight: .semibold)
                .accessibilityLabel("Xcode wells")
        }
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

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 84
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
            .accessibilityLabel(mismatch == nil ? "Screenshot \(position)" : "Screenshot \(position), wrong size")
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
                Text("\(position)")
                    .scaledFont(18, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill").scaledFont(18)
                }
                .buttonStyle(.borderless)
                .help("Remove this screenshot from the well")
                .accessibilityLabel("Remove screenshot")
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
