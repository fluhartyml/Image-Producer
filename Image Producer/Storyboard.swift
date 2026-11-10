//
//  Storyboard.swift
//  Image Producer
//
//  STORYBOARD, PIECE 1 (Amber Sheet D-080, D-081, D-084, D-088, D-089, D-092, D-070a).
//
//  REM: D-080 — "30 s × 30 fps = 900 frames, too many to be layers, so frames are grouped
//  into scenes on a storyboard." D-092 — "HyperCard is our inspiration: each card is a key
//  frame, and a stack of cards is a storyboard."
//  REM: D-081 — "Each storyboard card is a key frame, and each key frame gets a layer." The
//  cards are the same flipbook layers the videos already use (each layer with artwork, or
//  the Camera's frames when there are any), in layer order. Nothing new is saved per frame:
//  only the video's length and each card's share of it.
//  REM: D-088 — "Length first, then key frames. You set the video's length (30 s max); key
//  frames split it evenly by default (15 s with 5 cards = 3 s, 90 frames each). Adding or
//  removing a card re-divides the time."
//  REM: D-089 — "A timeline where you can give one card more time and the others shrink to
//  keep the total."
//  REM: D-086 — "Render saves a working video file. When you want it out, Export saves it
//  anywhere you pick with the file picker (Desktop, iCloud Drive, and so on)."
//  REM: D-087 — "One working video, overwritten at each Play or Render. It's kept inside
//  the .imgprd document, so it travels with the file." It's saved in the document the way
//  the wells' videos are (D-074), so older builds and older files are unaffected.
//  REM: Not in this piece (sheet order, next pieces): transitions and their filler frames
//  (D-082, D-083, D-090–D-095) — until then every card cuts to the next.
//

import AVKit
import SwiftUI

/// What the document saves about its storyboard. Optional in the manifest, so files saved
/// before it open unchanged (no storyboard: videos keep the flipbook speed).
struct Storyboard: Codable, Equatable {
    /// One card's time, in 1/30 s frames, tied to its layer.
    struct CardTime: Codable, Equatable {
        var id: UUID
        var frames: Int
    }

    /// The video's length in seconds. 0 = no length set: the storyboard is off and videos
    /// time their cards by the flipbook speed, as before.
    var lengthSeconds: Double = 0
    /// Each card's time, when you've changed it from the even split. Used only while it
    /// matches the cards exactly; otherwise the time is split evenly again (D-088).
    var times: [CardTime] = []
    /// REM: D-087 — the one working video, made by Play or Render, overwritten each time.
    /// Claude's call, not from the sheet: H.264 (.mp4), the smaller of D-073's two formats,
    /// since it's carried inside the document.
    var workingVideo: Data? = nil
    var workingSeconds: Double = 0
    /// Worth saving: a length is set or a working video is kept.
    var isWorthSaving: Bool { isOn || workingVideo != nil }

    static let fps = Int(VideoExport.fps)
    /// REM: D-088 — "You set the video's length (30 s max)". Claude's call, not from the
    /// sheet: the shortest length you can set is 1 second, in whole seconds. D-070a's red
    /// ("You're still allowed past 30") still applies to the flipbook-speed export, which
    /// has no storyboard length.
    static let shortest: Double = 1
    static let longest: Double = 30
    /// REM: D-084 — "A card holds for 5 seconds by default, and that varies with the number
    /// of cards against the video's length (088's even split)."
    static let defaultCardSeconds: Double = 5

    var isOn: Bool { lengthSeconds > 0 }

    /// The total in frames for these many cards (never less than one frame a card).
    func totalFrames(cards n: Int) -> Int {
        max(n, Int((lengthSeconds * Double(Self.fps)).rounded()))
    }

    /// Each card's hold in frames, in card order.
    func holds(for ids: [UUID]) -> [Int] {
        let n = ids.count
        guard n > 0 else { return [] }
        let total = totalFrames(cards: n)
        if times.map(\.id) == ids, times.reduce(0, { $0 + $1.frames }) == total,
           times.allSatisfy({ $0.frames >= 1 }) {
            return times.map(\.frames)
        }
        return Self.evenSplit(total, n)
    }

    /// REM: D-088 — "key frames split it evenly by default". Frames that don't divide
    /// evenly go one each to the first cards.
    static func evenSplit(_ total: Int, _ n: Int) -> [Int] {
        let base = total / n, extra = total % n
        return (0..<n).map { base + ($0 < extra ? 1 : 0) }
    }

    /// Share `total` frames out in proportion to `weights`, each at least one frame, the
    /// leftover frames going to the largest remainders.
    static func share(_ total: Int, by weights: [Int]) -> [Int] {
        let n = weights.count
        guard n > 0 else { return [] }
        guard total > n else { return Array(repeating: max(1, total / n), count: n) }
        let spare = total - n            // one frame each is set aside first
        let sum = max(1, weights.reduce(0, +))
        let exact = weights.map { Double(spare) * Double($0) / Double(sum) }
        var out = exact.map { Int($0) }
        var left = spare - out.reduce(0, +)
        let order = exact.indices.sorted { (exact[$0] - Double(out[$0])) > (exact[$1] - Double(out[$1])) }
        for i in order where left > 0 { out[i] += 1; left -= 1 }
        return out.map { $0 + 1 }
    }

    /// Set the length first (D-088). The cards keep their shares of it.
    /// REM: Claude's call, not from the sheet — changing the length scales every card's
    /// time in proportion, so a card you gave more time keeps more; an even split stays even.
    mutating func setLength(_ seconds: Double, ids: [UUID]) {
        let current = holds(for: ids)
        let custom = !ids.isEmpty && times.map(\.id) == ids
        lengthSeconds = min(Self.longest, max(Self.shortest, seconds.rounded()))
        if custom {
            let fresh = Self.share(totalFrames(cards: ids.count), by: current)
            times = zip(ids, fresh).map { CardTime(id: $0, frames: $1) }
        } else {
            times = []
        }
    }

    /// REM: D-089 — "give one card more time and the others shrink to keep the total." The
    /// others shrink in proportion to the time they had; each keeps at least one frame.
    mutating func setFrames(_ frames: Int, forCard index: Int, ids: [UUID]) {
        let n = ids.count
        guard ids.indices.contains(index), n > 1 else { return }
        let total = totalFrames(cards: n)
        var current = holds(for: ids)
        let mine = min(max(1, frames), total - (n - 1))
        var others = current
        others.remove(at: index)
        var shared = Self.share(total - mine, by: others)
        shared.insert(mine, at: index)
        current = shared
        times = zip(ids, current).map { CardTime(id: $0, frames: $1) }
    }

    /// Back to the even split (D-088's default).
    mutating func splitEvenly() { times = [] }
}

extension ImageDocument {
    /// The storyboard's cards: the flipbook layers the wells' videos use (D-081).
    var storyboardCards: [ImageLayer] {
        flipbookFrameLayers(self, cameraOnly: !cameraFrames.isEmpty)
    }
}

/// REM: D-070a — "on the storyboard timeline it comes with D-080 on. The timeline fills
/// with cards and transitions, and its bar is colored by length: amber under 15 seconds
/// (still exports, padded — 070c), green from 15 to 30 seconds, red after 30 seconds."
/// One block per card, as wide as its time, numbered in order.
struct StoryboardTimeline: View {
    let holds: [Int]
    var selected: Int?
    var onSelect: (Int) -> Void

    private var seconds: Double { Double(holds.reduce(0, +)) / Double(Storyboard.fps) }
    private var color: Color {
        if seconds < VideoExport.shortest - 0.001 { return .orange }
        if seconds <= VideoExport.longest + 0.001 { return .green }
        return .red
    }

    var body: some View {
        let total = max(1, holds.reduce(0, +))
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(holds.enumerated()), id: \.offset) { i, h in
                    let w = max(4, (geo.size.width - CGFloat(holds.count - 1) * 2) * CGFloat(h) / CGFloat(total))
                    Button { onSelect(i) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(selected == i ? 1 : 0.7))
                            if selected == i {
                                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary, lineWidth: 3)
                            }
                            if w > 24 {
                                Text("\(i + 1)").scaledFont(18, weight: .semibold)
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: w, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Card \(i + 1)")
                    .accessibilityValue(VideoExport.seconds(Double(h) / Double(Storyboard.fps)))
                }
            }
        }
        .frame(height: 44)
    }
}

/// The storyboard: set the video's length, then see and change each card's time.
struct StoryboardSheet: View {
    @Bindable var document: ImageDocument
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int?
    @State private var busy = false
    @State private var failure: String?
    @State private var player: AVPlayer?
    @State private var exporting = false

    private var cards: [ImageLayer] { document.storyboardCards }
    private var ids: [UUID] { cards.map(\.id) }

    var body: some View {
        let cards = self.cards, ids = self.ids
        let board = document.storyboard
        let holds = board.holds(for: ids)
        VStack(alignment: .leading, spacing: 14) {
            Text("Storyboard").scaledFont(24, weight: .semibold)
            Text("Each card is a key frame: one layer with artwork, in layer order. Set your video's "
                 + "length first, and your cards share it evenly.")
                .scaledFont(18).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if cards.isEmpty {
                Text("No cards yet. Each layer with artwork is one card.")
                    .scaledFont(18).foregroundStyle(.secondary)
            } else if !board.isOn {
                Text("Your videos now time each card by the flipbook speed in the Export sheet.")
                    .scaledFont(18).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set Video Length") {
                    // REM: D-084 — 5 seconds a card by default, within D-088's 30 s maximum.
                    let start = min(Storyboard.longest,
                                    max(Storyboard.shortest, Storyboard.defaultCardSeconds * Double(cards.count)))
                    document.storyboard.setLength(start, ids: ids)
                    document.say("Storyboard on: \(VideoExport.seconds(document.storyboard.lengthSeconds)) video",
                                 kind: .edit)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).scaledFont(18)
                .accessibilityLabel("Set video length")
            } else {
                lengthRow(board: board, ids: ids)
                StoryboardTimeline(holds: holds, selected: selected) { selected = $0 }
                Text(lengthNote(holds: holds)).scaledFont(18).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                            cardRow(i, card: card, frames: holds.indices.contains(i) ? holds[i] : 0,
                                    count: cards.count, ids: ids)
                        }
                    }
                }
                .frame(maxHeight: 320)
                workingVideoRow
                HStack(spacing: 10) {
                    Button("Split Evenly") { document.storyboard.splitEvenly() }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                        .disabled(board.times.isEmpty)
                        .accessibilityLabel("Split evenly")
                    Button("Use Flipbook Speed") {
                        // Your working video is kept (D-087); only the timing goes.
                        let kept = document.storyboard
                        document.storyboard = Storyboard(workingVideo: kept.workingVideo,
                                                         workingSeconds: kept.workingSeconds)
                        document.say("Storyboard off: videos use the flipbook speed", kind: .edit)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Use flipbook speed")
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Close storyboard")
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 560)
        .fileExporter(isPresented: $exporting,
                      document: CanvasDataDocument(document.storyboard.workingVideo ?? Data()),
                      contentType: .mpeg4Movie,
                      defaultFilename: "\(document.name) Video") { result in
            document.reportExport(result, what: "\(document.name) Video")
        }
        .alert("Storyboard", isPresented: Binding(get: { failure != nil },
                                                  set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "").scaledFont(18)
        }
        .onDisappear { player?.pause() }
    }

    /// Play, Render, and the working video they make (D-083, D-086, D-087).
    @ViewBuilder private var workingVideoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .accessibilityLabel("Working video")
            }
            HStack(spacing: 10) {
                // REM: D-083 — "Filler frames are made only when you ask: at export, or when
                // you intentionally Play or Render. They are never saved as layers."
                Button("Play") { make(thenPlay: true) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Make and play")
                Button("Render") { make(thenPlay: false) }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Make working video")
                if document.storyboard.workingVideo != nil {
                    Button("Export Video") { exporting = true }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                        .accessibilityLabel("Export video")
                }
                if busy { ProgressView() }
            }
            .disabled(busy)
            Text(workingNote).scaledFont(18).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workingNote: String {
        if busy { return "Making your working video." }
        guard document.storyboard.workingVideo != nil else {
            return "Play or Render makes your working video. It's kept in this document, "
                + "and each Play or Render replaces it."
        }
        return "Your working video: \(VideoExport.seconds(document.storyboard.workingSeconds)), kept in this "
            + "document. Play or Render replaces it; Export Video saves a copy where you pick."
    }

    /// Make the working video from the storyboard, padded under 15 s like every export (D-070c).
    private func make(thenPlay: Bool) {
        let plan = VideoExport.plan(document, sourceFPS: WellVideoMaker.sourceFPS,
                                    cameraOnly: !document.cameraFrames.isEmpty)
        guard !plan.cards.isEmpty else { failure = "No cards yet. Each layer with artwork is one card."; return }
        busy = true
        player?.pause(); player = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let url = try await VideoExport.make(plan, document: document, codec: .h264)
                defer { try? FileManager.default.removeItem(at: url) }
                let data = try Data(contentsOf: url)
                document.storyboard.workingVideo = data
                document.storyboard.workingSeconds = plan.seconds
                document.say("Working video made: \(VideoExport.seconds(plan.seconds))", kind: .save)
                if thenPlay { play(data) }
            } catch {
                failure = "Your working video could not be made: \(error.localizedDescription)"
            }
        }
    }

    /// AVPlayer reads from a file, so the working video is played from a temporary copy.
    private func play(_ data: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageProducer-working-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        do {
            try data.write(to: url)
            let p = AVPlayer(url: url)
            player = p
            p.play()
        } catch {
            failure = "Your working video could not be played: \(error.localizedDescription)"
        }
    }

    @ViewBuilder private func lengthRow(board: Storyboard, ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Video length: \(VideoExport.seconds(board.lengthSeconds))").scaledFont(18)
            Slider(value: Binding(get: { document.storyboard.lengthSeconds },
                                  set: { document.storyboard.setLength($0, ids: ids) }),
                   in: Storyboard.shortest...Storyboard.longest, step: 1)
                .accessibilityLabel("Video length")
                .accessibilityValue(VideoExport.seconds(board.lengthSeconds))
        }
    }

    @ViewBuilder private func cardRow(_ i: Int, card: ImageLayer, frames: Int, count: Int, ids: [UUID]) -> some View {
        // REM: D-089 — more time for one card, the others shrink. Claude's call, not from
        // the sheet: half a second (15 frames) a press, with buttons rather than a drag, so
        // nothing needs a modifier key or a steady hand.
        let step = Storyboard.fps / 2
        HStack(spacing: 10) {
            Text("\(i + 1). \(card.name)").scaledFont(18, weight: selected == i ? .semibold : nil)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(VideoExport.seconds(Double(frames) / Double(Storyboard.fps))), \(frames) frames")
                .scaledFont(18, monospacedDigit: true).foregroundStyle(.secondary)
            Button("Less Time") {
                selected = i
                document.storyboard.setFrames(frames - step, forCard: i, ids: ids)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
            .disabled(count < 2 || frames <= 1)
            .accessibilityLabel("Less time")
            Button("More Time") {
                selected = i
                document.storyboard.setFrames(frames + step, forCard: i, ids: ids)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
            .disabled(count < 2 || frames >= document.storyboard.totalFrames(cards: count) - (count - 1))
            .accessibilityLabel("More time")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func lengthNote(holds: [Int]) -> String {
        let n = holds.count
        let s = Double(holds.reduce(0, +)) / Double(Storyboard.fps)
        let cards = "\(n) card\(n == 1 ? "" : "s") in \(VideoExport.seconds(s))"
        if s < VideoExport.shortest - 0.001 {
            return "\(cards). Under 15 seconds: when you make a video, each card is held longer "
                + "until it reaches 15 seconds."
        }
        return "\(cards). Ready for the App Store: 15 to 30 seconds."
    }
}
