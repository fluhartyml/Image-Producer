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
//  REM: WHAT IS DELIBERATELY NOT HERE. Wrong-size warnings and Fill/Fit (D-040–042), Export to
//  Project Bundle (D-050–051), the Apple TV icon and Top Shelf wells (D-021/027), the creative
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

    private var shots: [XcodeScreenshot] {
        document.xcodeProject.sets.indices.contains(setIndex)
            ? document.xcodeProject.sets[setIndex].screenshots(for: device) : []
    }
    private var isFull: Bool { shots.count >= XcodeProjectWells.maxPerDevice }

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.title) well")
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
                            shot: shot, position: i + 1,
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
        if leftOut > 0 {
            document.say("\(device.title) holds \(XcodeProjectWells.maxPerDevice) screenshots — "
                         + "\(leftOut) not added", kind: .warning)
        } else if added > 0 {
            document.say("Added \(added) to the \(device.title) well", kind: .edit)
        }
    }
}

/// One screenshot in a well: the picture, its place in upload order, Remove, and Move Earlier.
struct XcodeWellThumbnail: View {
    let shot: XcodeScreenshot
    let position: Int
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
            .accessibilityLabel("Screenshot \(position)")
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
        .task(id: shot.id) {
            let data = shot.imageData
            thumb = await Task.detached(priority: .utility) { wellThumbnail(data, maxPixels: 256) }.value
        }
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
