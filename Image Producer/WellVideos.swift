//
//  WellVideos.swift
//  Image Producer
//
//  VIDEO, PIECE 2 — video in the wells (Amber Sheet D-074, D-075, D-076; finishes D-070b
//  and D-026). All LOCKED. His words, from the sheet:
//    D-026 "The wells take video too, made from Image Producer's own frame animations
//          ("image producer technically can make animations for app store connect")."
//    D-074 "App preview rules (App Store Connect app preview specifications, read
//          2026-11-05): up to 3 per device size and language; 15–30 s; up to 500 MB; .mov,
//          .m4v or .mp4. Sizes: iPhone, including iPhone Duo: 886 × 1920 (or 1920 × 886).
//          iPad: 1200 × 1600 (or 1600 × 1200). Mac and Apple TV: 1920 × 1080, landscape
//          only. Apple Watch isn't listed."
//    D-075 "Creative asset video rules: header 21:9 at 3840 × 1646; search results 3:2,
//          1920 × 1280 up to 3840 × 2560 — both 5–30 s at 30 or 60 fps. Event card 16:9 and
//          details page 9:16 — 15–30 s. All loop and play muted at first."
//    D-076 "A wrong-size animation follows the same rule as pictures (040–042): a warning
//          in the well, Fill ( ) Fit with Fit as default, and the export says what it
//          resized."
//    D-070b "Only the green part (15–30 s) can go into the App Store wells and the Project
//          Bundle."
//
//  REM: HOW IT WORKS. "Make Video" in a well turns the flipbook (the same cards the Export ▸
//  Video uses, VideoExport.plan) into a video at your canvas's size. When that size isn't one
//  the well takes, the Fit and Fill versions at the well's size are made at the same moment
//  from the same cards, with the same `wellResized` the pictures use (never stretched), so
//  flipping Fill / Fit later is instant and the export writes exactly what was made, even if
//  the layers have changed since. The video is saved in the project with its wells.
//
//  REM: Claude's calls, not from the sheet —
//    • H.264 (.mp4) for the wells: D-074 caps a preview at 500 MB, and a 30 s ProRes 422 HQ
//      video at these sizes runs past that. .mp4 is on D-074's list.
//    • Silent: the wells' videos carry no sound. Your own sound (D-071) is on Export ▸ Video.
//    • The flipbook timing: 8 frames a second, the Export sheet's and the Camera's starting
//      value; Camera frames only when you have Camera frames, as the Export sheet starts.
//    • Video sizes for the event card and details page: D-075 gives their shapes but no
//      sizes, so they use D-025's picture ranges at those shapes (the conservative reading).
//      The header takes only 21:9 at 3840 × 1646 for video: D-075 doesn't list the 16:9
//      5244 × 2950 picture size for video.
//    • A ranged size is always even on both sides (H.264 needs even sizes).
//

import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

/// One video in a well. `videoData` is the video at your canvas's size; `fitData` and
/// `fillData` are the same video at the well's size, made only when the canvas size isn't
/// one the well takes (D-076).
struct XcodeVideo: Identifiable, Codable, Equatable {
    var id = UUID()
    var videoData: Data
    var width: Int
    var height: Int
    var seconds: Double
    /// A still of the video (the card at the 5 s Poster Frame), for the well's thumbnail.
    var still: Data
    var fitData: Data?
    var fillData: Data?
    /// REM: D-076 — "Fill ( ) Fit with Fit as default".
    var fitMode: XcodeFitMode = .fit

    var size: WellPixelSize { WellPixelSize(width: width, height: height) }
    /// The thumbnail goes through the same strip as the screenshots.
    var asShot: XcodeScreenshot { XcodeScreenshot(id: id, imageData: still, fitMode: fitMode) }
}

extension XcodeWellSet {
    /// Videos in a well, keyed the way the pictures are (a device's or creative well's raw
    /// value).
    func videos(for key: String) -> [XcodeVideo] { videos[key] ?? [] }
    var videoCount: Int { videos.values.reduce(0) { $0 + $1.count } }
}

/// Which well a video goes in, and that well's video rules.
enum VideoWell: Equatable {
    case device(XcodeWellDevice)
    case creative(XcodeCreativeWell)

    var key: String {
        switch self {
        case .device(let d): d.rawValue
        case .creative(let w): w.rawValue
        }
    }

    var title: String {
        switch self {
        case .device(let d): d.title
        case .creative(let w): w.title
        }
    }

    /// REM: D-074 — "up to 3 per device size and language". A creative well holds one, like
    /// its picture.
    var maxCount: Int {
        switch self {
        case .device: 3
        case .creative: 1
        }
    }

    /// REM: D-074 "Apple Watch isn't listed" — no video there.
    var takesVideo: Bool {
        if case .device(.appleWatch) = self { return false }
        return true
    }

    /// REM: D-075 — header and search results "5–30 s"; everything else "15–30 s" (D-070,
    /// D-074). D-070 "Maximum length 30 seconds".
    var shortest: Double {
        switch self {
        case .creative(.header), .creative(.searchResults): 5
        default: VideoExport.shortest
        }
    }
    var longest: Double { VideoExport.longest }

    func lengthFits(_ s: Double) -> Bool { s >= shortest - 0.001 && s <= longest + 0.001 }

    private enum Option {
        case exact(WellPixelSize)
        case range(rw: Int, rh: Int, from: WellPixelSize, to: WellPixelSize)
    }

    /// REM: D-074 and D-075, exactly as the sheet lists them (see the file header).
    private var options: [Option] {
        func s(_ w: Int, _ h: Int) -> WellPixelSize { WellPixelSize(width: w, height: h) }
        switch self {
        case .device(.iPhone), .device(.iPhoneDuo):
            return [.exact(s(886, 1920)), .exact(s(1920, 886))]
        case .device(.iPad):
            return [.exact(s(1200, 1600)), .exact(s(1600, 1200))]
        case .device(.mac), .device(.appleTV):
            return [.exact(s(1920, 1080))]
        case .device(.appleWatch):
            return []
        case .creative(.header):
            return [.exact(s(3840, 1646))]
        case .creative(.searchResults):
            return [.range(rw: 3, rh: 2, from: s(1920, 1280), to: s(3840, 2560))]
        case .creative(.eventCard):
            return [.range(rw: 16, rh: 9, from: s(1920, 1080), to: s(3840, 2160))]
        case .creative(.eventDetails):
            return [.range(rw: 9, rh: 16, from: s(1080, 1920), to: s(2160, 3840))]
        }
    }

    func accepts(_ size: WellPixelSize) -> Bool {
        options.contains { option in
            switch option {
            case .exact(let s):
                return s == size
            case .range(let rw, let rh, let from, let to):
                guard (from.width...to.width).contains(size.width) else { return false }
                return abs(Double(size.height) - Double(size.width) * Double(rh) / Double(rw)) < 1
            }
        }
    }

    /// REM: D-076 / D-042 — the size that changes the video least: the closest shape, then
    /// within a range the size nearest its own pixel count. Ranged sizes step by an even
    /// multiple, so both sides stay even for H.264.
    func exportSize(for size: WellPixelSize) -> WellPixelSize {
        let area = Double(size.width) * Double(size.height)
        let candidates: [WellPixelSize] = options.map { option in
            switch option {
            case .exact(let s):
                return s
            case .range(let rw, let rh, let from, let to):
                let unit = (area / Double(rw * rh)).squareRoot()
                let lo = Double(from.width / rw), hi = Double(to.width / rw)
                var k = Int(min(max(unit, lo), hi).rounded())
                if k % 2 == 1 { k += (Double(k + 1) <= hi ? 1 : -1) }
                return WellPixelSize(width: rw * k, height: rh * k)
            }
        }
        func shapeGap(_ t: WellPixelSize) -> Double { abs(log(t.aspect / size.aspect)) }
        return candidates.min { shapeGap($0) < shapeGap($1) } ?? size
    }

    var acceptedSizesText: String {
        switch self {
        case .device(.iPhone), .device(.iPhoneDuo): "886 × 1920 or 1920 × 886"
        case .device(.iPad): "1200 × 1600 or 1600 × 1200"
        case .device: "1920 × 1080, landscape only"
        case .creative(.header): "21:9 at 3840 × 1646"
        case .creative(.searchResults): "3:2 from 1920 × 1280 up to 3840 × 2560"
        case .creative(.eventCard): "16:9 from 1920 × 1080 up to 3840 × 2160"
        case .creative(.eventDetails): "9:16 from 1080 × 1920 up to 2160 × 3840"
        }
    }

    var lengthText: String { "\(Int(shortest)) to \(Int(longest)) seconds" }

    /// Plural noun for the well's videos, in the status line and the report.
    var videoName: String {
        switch self {
        case .device: "app preview"
        case .creative: "video"
        }
    }
}

extension ImageDocument {
    /// Put a video in a well. A device well takes up to three, in order; a creative well
    /// holds one, and a new one replaces the old. Returns false when the well is full.
    @discardableResult
    func addVideo(_ video: XcodeVideo, to well: VideoWell, inSet setIndex: Int) -> Bool {
        guard xcodeProject.sets.indices.contains(setIndex) else { return false }
        var list = xcodeProject.sets[setIndex].videos(for: well.key)
        if case .creative = well { list = [] }
        guard list.count < well.maxCount else { return false }
        list.append(video)
        xcodeProject.sets[setIndex].videos[well.key] = list
        return true
    }

    func removeVideo(_ id: XcodeVideo.ID, from well: VideoWell, inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex) else { return }
        xcodeProject.sets[setIndex].videos[well.key]?.removeAll { $0.id == id }
    }

    func setVideoFitMode(_ mode: XcodeFitMode, for id: XcodeVideo.ID, in well: VideoWell, inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex),
              var list = xcodeProject.sets[setIndex].videos[well.key],
              let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].fitMode = mode
        xcodeProject.sets[setIndex].videos[well.key] = list
    }

    /// One step earlier — the well's order is the upload order, as for screenshots.
    func moveVideoEarlier(_ id: XcodeVideo.ID, in well: VideoWell, inSet setIndex: Int) {
        guard xcodeProject.sets.indices.contains(setIndex),
              var list = xcodeProject.sets[setIndex].videos[well.key],
              let i = list.firstIndex(where: { $0.id == id }), i > 0 else { return }
        list.swapAt(i, i - 1)
        xcodeProject.sets[setIndex].videos[well.key] = list
    }
}

// MARK: - Making a well's video

enum WellVideoMaker {
    /// REM: Claude's call — see the file header: the Export sheet's starting timing.
    static let sourceFPS: Double = 8

    enum Problem: LocalizedError {
        case noCards, tooLong(Double), render, tooShort(Double)
        var errorDescription: String? {
            switch self {
            case .noCards:
                return "No frames yet. Each layer with artwork is one card of the video."
            case .tooLong(let s):
                // REM: D-070b — "Only the green part (15–30 s) can go into the App Store wells
                // and the Project Bundle." A longer one still saves from Export ▸ Video.
                return "Your cards run \(VideoExport.seconds(s)), longer than 30 seconds, so the video "
                    + "can't go in a well. Make it 30 seconds or shorter, or save it as an ordinary "
                    + "video with Export ▸ Video."
            case .tooShort(let s):
                return "The video runs \(VideoExport.seconds(s)), shorter than this well takes."
            case .render:
                return "A frame could not be drawn."
            }
        }
    }

    /// The plan the wells use: the flipbook, padded under 15 s (D-070c).
    @MainActor static func plan(_ document: ImageDocument) -> VideoExport.Plan {
        VideoExport.plan(document, sourceFPS: sourceFPS, cameraOnly: !document.cameraFrames.isEmpty)
    }

    /// Make the video for a well: at the canvas's size, and when that's not a size the well
    /// takes, its Fit and Fill versions at the well's size too (D-076).
    @MainActor static func make(_ document: ImageDocument, for well: VideoWell) async throws -> XcodeVideo {
        let plan = plan(document)
        guard !plan.cards.isEmpty else { throw Problem.noCards }
        guard plan.baseSeconds <= VideoExport.longest + 0.001 else { throw Problem.tooLong(plan.baseSeconds) }
        guard well.lengthFits(plan.seconds) else { throw Problem.tooShort(plan.seconds) }
        var images: [CGImage] = []
        for card in plan.cards {
            guard let cg = renderLayerImage(card, in: document) else { throw Problem.render }
            images.append(cg)
        }
        let cw = document.canvasWidth, ch = document.canvasHeight
        let size = WellPixelSize(width: cw + cw % 2, height: ch + ch % 2)
        let holds = plan.holds
        // The card at the 5 s Poster Frame (D-072's preset) is the well's still.
        let posterCard = plan.cardStarts.lastIndex { $0 <= VideoExport.posterDefault } ?? 0
        let stillImage = images[min(posterCard, images.count - 1)]
        let still = pngData(stillImage) ?? Data()

        let original = try await encode(images, holds: holds, size: size,
                                        canvas: CGSize(width: cw, height: ch), steps: plan.steps)
        var fit: Data?, fill: Data?
        if !well.accepts(size) {
            let target = well.exportSize(for: size)
            let full = CGSize(width: target.width, height: target.height)
            fit = try await encode(images.compactMap { wellResized($0, to: target, mode: .fit) },
                                   holds: holds, size: target, canvas: full, steps: plan.steps)
            fill = try await encode(images.compactMap { wellResized($0, to: target, mode: .fill) },
                                    holds: holds, size: target, canvas: full, steps: plan.steps)
        }
        return XcodeVideo(videoData: original, width: size.width, height: size.height,
                          seconds: plan.seconds, still: still, fitData: fit, fillData: fill)
    }

    /// One silent H.264 video through Export ▸ Video's own writer, read back as bytes.
    @MainActor private static func encode(_ images: [CGImage], holds: [Int], size: WellPixelSize,
                                          canvas: CGSize, steps: [VideoTransitionStep] = []) async throws -> Data {
        guard images.count == holds.count else { throw Problem.render }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageProducer-well-\(UUID().uuidString)")
            .appendingPathExtension(VideoExport.Codec.h264.fileExtension)
        defer { try? FileManager.default.removeItem(at: url) }
        try await VideoExport.write(images: images, holds: holds, width: size.width, height: size.height,
                                    canvas: canvas, codec: .h264, sound: nil, to: url,
                                    steps: steps)
        return try Data(contentsOf: url)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

// MARK: - The video part of a well

/// REM: D-026 / D-074 / D-075 — the videos in one well, under its pictures: a count, a Make
/// Video button, the thumbnails (with D-076's warning and Fill / Fit), and what the length
/// rule is.
struct WellVideoStrip: View {
    @Bindable var document: ImageDocument
    let well: VideoWell
    let setIndex: Int

    @State private var making = false

    private var videos: [XcodeVideo] {
        document.xcodeProject.sets.indices.contains(setIndex)
            ? document.xcodeProject.sets[setIndex].videos(for: well.key) : []
    }
    private var isFull: Bool {
        if case .creative = well { return false }   // a new one replaces the old
        return videos.count >= well.maxCount
    }

    private func mismatch(_ v: XcodeVideo) -> WellMismatch? {
        well.accepts(v.size) ? nil : WellMismatch(size: v.size, exportSize: well.exportSize(for: v.size))
    }

    var body: some View {
        if well.takesVideo {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "film")
                        .scaledFont(18)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text(countText)
                        .scaledFont(18)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if making {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Making video")
                    }
                    Button("Make Video") { make() }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .disabled(isFull || making)
                    .help("Make a video of your flipbook for the \(well.title) well")
                    .accessibilityLabel("Make video")
                }
                if !videos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(videos.enumerated()), id: \.element.id) { i, v in
                                XcodeWellThumbnail(
                                    shot: v.asShot, position: i + 1, mismatch: mismatch(v),
                                    onSetFitMode: { mode in
                                        document.setVideoFitMode(mode, for: v.id, in: well, inSet: setIndex)
                                    },
                                    onRemove: { document.removeVideo(v.id, from: well, inSet: setIndex) },
                                    onMoveEarlier: (i == 0 || well.maxCount == 1) ? nil : {
                                        document.moveVideoEarlier(v.id, in: well, inSet: setIndex)
                                    },
                                    artName: "Video \(i + 1), \(VideoExport.seconds(v.seconds))",
                                    isVideo: true)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                ForEach(Array(videos.enumerated()), id: \.element.id) { i, v in
                    if let m = mismatch(v) {
                        Label {
                            Text(wrongSizeText(position: i + 1, mismatch: m, mode: v.fitMode))
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
                Text(ruleText)
                    .scaledFont(18)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(well.title) videos")
        }
    }

    private var countText: String {
        switch well {
        case .device: "App Previews · \(videos.count) of \(well.maxCount)"
        case .creative: "Video · \(videos.count) of 1"
        }
    }

    /// REM: D-070b, D-074, D-075 — what this well takes, in one line. "All loop and play muted
    /// at first" (D-075) is how the App Store plays creative asset videos.
    private var ruleText: String {
        var text = "Make Video turns your flipbook into a silent video. This well takes "
            + "\(well.lengthText) at \(well.acceptedSizesText); under 15 seconds, each card is held longer."
        if case .creative = well { text += " The App Store loops it and plays it muted at first." }
        // REM: D-088 — once the storyboard has a length, it times the cards here too.
        if document.storyboard.isOn {
            text += " Your cards are timed by your storyboard: \(VideoExport.seconds(document.storyboard.lengthSeconds))."
        }
        return text
    }

    private func wrongSizeText(position: Int, mismatch m: WellMismatch, mode: XcodeFitMode) -> String {
        let how = mode == .fit
            ? "fit inside it, all of it showing, with black bars where it doesn't reach"
            : "filled to its edges, with what spills over trimmed"
        return "Video \(position) is \(m.size.text). This well takes \(well.acceptedSizesText). "
            + "At export it's \(m.exportSize.text), \(how). Nothing is stretched."
    }

    private func make() {
        making = true
        Task {
            defer { making = false }
            do {
                let video = try await WellVideoMaker.make(document, for: well)
                let replacing = !videos.isEmpty && well.maxCount == 1
                guard document.addVideo(video, to: well, inSet: setIndex) else {
                    document.say("The \(well.title) well holds \(well.maxCount) \(well.videoName)s", kind: .warning)
                    return
                }
                let length = VideoExport.seconds(video.seconds)
                if mismatch(video) != nil {
                    document.say("Added a \(length) \(well.videoName) to the \(well.title) well — it isn't a "
                                 + "size the well takes; see the note in the well", kind: .warning)
                } else {
                    document.say((replacing ? "Replaced the \(well.title) video with a \(length) one"
                                            : "Added a \(length) \(well.videoName) to the \(well.title) well"),
                                 kind: .edit)
                }
            } catch {
                document.say(error.localizedDescription, kind: .warning)
            }
        }
    }
}
