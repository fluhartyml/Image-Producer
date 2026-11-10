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
//  REM: Piece 2 (Transitions.swift): transitions and their filler frames (D-082, D-083,
//  D-090–D-095). A pair of cards with no transition still cuts to the next.
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
    /// REM: D-093 — "A transition's length sets its transition frames." One per pair of
    /// cards that has one; a pair with none cuts. Optional, so files saved by build 391
    /// (no key) open unchanged.
    struct Transition: Codable, Equatable {
        /// The card it leaves and the card it arrives at. Reordering cards drops it (cut).
        var from: UUID
        var to: UUID
        /// The effect's saved name; one this build doesn't know reads as a cut.
        var effectName: String
        var frames: Int
        var effect: TransitionEffect { TransitionEffect(rawValue: effectName) ?? .cut }
        /// REM: D-091 — "motion in-betweens with easing (from the Camera tool)": the Camera
        /// tool's easing, saved by name for a motion in-between. Optional, so files saved by
        /// build 392 (no key) open unchanged; nil reads as the Camera tool's own starting
        /// choice, Slow in + out.
        var easingName: String? = nil
        var easing: CameraEasing { CameraEasing(rawValue: easingName ?? "") ?? .easeBoth }
    }
    var transitions: [Transition]? = nil
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

    // MARK: Transitions (D-090 – D-095)

    /// REM: Claude's call, not from the sheet — each card keeps at least this many frames
    /// of its own (shown whole) after the transitions take theirs.
    static let minimumCardFrames = 1

    /// The transition between card `i` and card `i + 1`, if it has one that isn't a cut.
    func transition(after i: Int, ids: [UUID]) -> Transition? {
        guard i >= 0, i + 1 < ids.count else { return nil }
        return (transitions ?? []).first { $0.from == ids[i] && $0.to == ids[i + 1] && $0.effect != .cut && $0.frames > 0 }
    }

    /// Each gap's transition, in order (count = cards − 1), a cut where there's none.
    func steps(for ids: [UUID]) -> [VideoTransitionStep] {
        guard ids.count > 1 else { return [] }
        // REM: D-093 — "A transition isn't allowed if there aren't enough frames to spend on
        // its effect." Claude's call, not from the sheet: if you shorten the video below what
        // its transitions spend, they're trimmed in order, never below their minimum; one
        // that can't keep its minimum plays as a cut until there's room again (it stays saved).
        var budget = max(0, totalFrames(cards: ids.count) - ids.count * Self.minimumCardFrames)
        return (0..<(ids.count - 1)).map { i in
            guard let t = transition(after: i, ids: ids) else { return VideoTransitionStep(effect: .cut, frames: 0) }
            let frames = min(t.frames, budget)
            guard frames >= t.effect.minimumFrames else { return VideoTransitionStep(effect: .cut, frames: 0) }
            budget -= frames
            return VideoTransitionStep(effect: t.effect, frames: frames)
        }
    }

    /// REM: D-093 — "A transition isn't allowed if there aren't enough frames to spend on
    /// its effect." The video's length stays as you set it (D-088); transitions spend frames
    /// out of it, and the cards share what's left in the proportions their times give them.
    func cardHolds(for ids: [UUID]) -> [Int] {
        let holds = holds(for: ids)
        let spent = steps(for: ids).reduce(0) { $0 + $1.frames }
        guard spent > 0, !holds.isEmpty else { return holds }
        return Self.share(max(ids.count, holds.reduce(0, +) - spent), by: holds)
    }

    /// Frames a transition at gap `i` could spend: the length, less every card's minimum,
    /// less the other transitions.
    func framesAvailable(at i: Int, ids: [UUID]) -> Int {
        let total = totalFrames(cards: ids.count)
        let others = steps(for: ids).enumerated().reduce(0) { $0 + ($1.offset == i ? 0 : $1.element.frames) }
        return max(0, total - ids.count * Self.minimumCardFrames - others)
    }

    /// REM: D-094 — "An effect too long for its gap is grayed out, with a note like: 'Needs
    /// 12 more frames — shorten another transition, or remove a card.'" Nil when it fits.
    func shortfall(_ effect: TransitionEffect, at i: Int, ids: [UUID]) -> Int? {
        let need = effect.minimumFrames - framesAvailable(at: i, ids: ids)
        return need > 0 ? need : nil
    }

    /// REM: D-095 — "Picking an effect sets its default length". Claude's call, not from
    /// the sheet: when the natural length doesn't fit but the minimum does, it gets the
    /// most frames there are.
    mutating func setEffect(_ effect: TransitionEffect, at i: Int, ids: [UUID]) {
        guard i >= 0, i + 1 < ids.count else { return }
        var list = (transitions ?? []).filter { !($0.from == ids[i] && $0.to == ids[i + 1]) }
        if effect != .cut {
            guard shortfall(effect, at: i, ids: ids) == nil else { return }
            let frames = min(effect.naturalFrames, framesAvailable(at: i, ids: ids))
            list.append(Transition(from: ids[i], to: ids[i + 1], effectName: effect.rawValue, frames: frames))
        }
        transitions = list.isEmpty ? nil : list
    }

    /// REM: D-091 — the easing a motion in-between moves with.
    mutating func setEasing(_ easing: CameraEasing, at i: Int, ids: [UUID]) {
        guard let t = transition(after: i, ids: ids), var list = transitions,
              let k = list.firstIndex(of: t) else { return }
        list[k].easingName = easing.rawValue
        transitions = list
    }

    /// REM: D-095 — "you can stretch it on the timeline, but never below its minimum (094)."
    mutating func setTransitionFrames(_ frames: Int, at i: Int, ids: [UUID]) {
        guard let t = transition(after: i, ids: ids), var list = transitions,
              let k = list.firstIndex(of: t) else { return }
        list[k].frames = min(max(t.effect.minimumFrames, frames), framesAvailable(at: i, ids: ids))
        transitions = list
    }
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
/// One block per card, as wide as its time, numbered in order; between each two cards a
/// transition block, as wide as its filler frames (a cut is a narrow block you can still
/// pick, so you can give it an effect — D-091 "Each transition's length is set on the
/// timeline").
struct StoryboardTimeline: View {
    let holds: [Int]
    /// Filler frames between card i and i + 1 (count = cards − 1).
    var gaps: [Int] = []
    var selected: Int?
    var selectedGap: Int? = nil
    var onSelect: (Int) -> Void
    var onSelectGap: (Int) -> Void = { _ in }

    private static let cutWidth: CGFloat = 14
    private var seconds: Double {
        Double(holds.reduce(0, +) + gaps.reduce(0, +)) / Double(Storyboard.fps)
    }
    private var color: Color {
        if seconds < VideoExport.shortest - 0.001 { return .orange }
        if seconds <= VideoExport.longest + 0.001 { return .green }
        return .red
    }

    var body: some View {
        let total = max(1, holds.reduce(0, +) + gaps.reduce(0, +))
        let cuts = gaps.filter { $0 == 0 }.count
        GeometryReader { geo in
            let spacing = CGFloat(holds.count + gaps.count - 1) * 2
            let room = max(1, geo.size.width - spacing - CGFloat(cuts) * Self.cutWidth)
            HStack(spacing: 2) {
                ForEach(Array(holds.enumerated()), id: \.offset) { i, h in
                    let w = max(4, room * CGFloat(h) / CGFloat(total))
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
                    if gaps.indices.contains(i) {
                        let g = gaps[i]
                        let gw = g == 0 ? Self.cutWidth : max(Self.cutWidth, room * CGFloat(g) / CGFloat(total))
                        Button { onSelectGap(i) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(g == 0 ? Color.gray.opacity(0.35) : color.opacity(0.35))
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(selectedGap == i ? Color.primary : color,
                                                  style: StrokeStyle(lineWidth: selectedGap == i ? 3 : 1, dash: [3, 2]))
                            }
                            .frame(width: gw, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Transition \(i + 1)")
                        .accessibilityValue(g == 0 ? "Cut" : VideoExport.seconds(Double(g) / Double(Storyboard.fps)))
                    }
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
    /// The transition being edited: the gap after this card.
    @State private var selectedGap: Int?
    @State private var busy = false
    @State private var failure: String?
    @State private var player: AVPlayer?
    @State private var exporting = false

    private var cards: [ImageLayer] { document.storyboardCards }
    private var ids: [UUID] { cards.map(\.id) }

    var body: some View {
        let cards = self.cards, ids = self.ids
        let board = document.storyboard
        // REM: D-093 — the cards' own frames, after the transitions take theirs.
        let holds = board.cardHolds(for: ids)
        let steps = board.steps(for: ids)
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
                StoryboardTimeline(holds: holds, gaps: steps.map(\.frames), selected: selected,
                                   selectedGap: selectedGap,
                                   onSelect: { selected = $0; selectedGap = nil },
                                   onSelectGap: { selectedGap = $0; selected = nil })
                if let gap = selectedGap, gap + 1 < cards.count {
                    transitionPanel(gap, board: board, ids: ids)
                }
                Text(lengthNote(holds: holds + steps.map(\.frames))).scaledFont(18).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                            cardRow(i, card: card, frames: holds.indices.contains(i) ? holds[i] : 0,
                                    count: cards.count, ids: ids)
                            if steps.indices.contains(i) {
                                transitionRow(i, step: steps[i])
                            }
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
                document.storyboard.setFrames(own(i, ids) - step, forCard: i, ids: ids)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
            .disabled(count < 2 || frames <= 1)
            .accessibilityLabel("Less time")
            Button("More Time") {
                selected = i
                document.storyboard.setFrames(own(i, ids) + step, forCard: i, ids: ids)
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
            .disabled(count < 2 || frames >= document.storyboard.totalFrames(cards: count) - (count - 1))
            .accessibilityLabel("More time")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// A card's share of the length before transitions take theirs (what More / Less Time move).
    private func own(_ i: Int, _ ids: [UUID]) -> Int {
        let h = document.storyboard.holds(for: ids)
        return h.indices.contains(i) ? h[i] : 0
    }

    /// The line between two cards in the list: its effect and length, and a button to change it.
    @ViewBuilder private func transitionRow(_ i: Int, step: VideoTransitionStep) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down").accessibilityHidden(true)
            Text(step.frames == 0 ? "Cut"
                 : "\(step.effect.name), \(VideoExport.seconds(Double(step.frames) / Double(Storyboard.fps))), \(step.frames) frames")
                .scaledFont(18).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(selectedGap == i ? "Close Transition" : "Change Transition") {
                selectedGap = selectedGap == i ? nil : i
                selected = nil
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
            .accessibilityLabel(selectedGap == i ? "Close transition" : "Change transition")
        }
        .padding(.leading, 20)
    }

    /// REM: D-091 — "Each transition's length is set on the timeline." D-094 — "An effect too
    /// long for its gap is grayed out, with a note like: 'Needs 12 more frames — shorten
    /// another transition, or remove a card.'" D-095 — "Picking an effect sets its default
    /// length; you can stretch it on the timeline, but never below its minimum (094)."
    @ViewBuilder private func transitionPanel(_ gap: Int, board: Storyboard, ids: [UUID]) -> some View {
        let step = board.steps(for: ids).indices.contains(gap) ? board.steps(for: ids)[gap]
            : VideoTransitionStep(effect: .cut, frames: 0)
        let effect = step.frames > 0 ? step.effect : .cut
        let frames = step.frames
        // REM: Claude's call, not from the sheet — Shorter / Longer move a transition by
        // 3 frames (1/10 s) a press, buttons rather than a drag, so nothing needs a steady hand.
        let nudge = 3
        VStack(alignment: .leading, spacing: 8) {
            Text("Transition from card \(gap + 1) to card \(gap + 2)").scaledFont(18, weight: .semibold)
            if effect != .cut {
                HStack(spacing: 10) {
                    Text("\(effect.name): \(VideoExport.seconds(Double(frames) / Double(Storyboard.fps))), "
                         + "\(frames) frames")
                        .scaledFont(18, monospacedDigit: true)
                    Spacer(minLength: 8)
                    Button("Shorter") {
                        document.storyboard.setTransitionFrames(frames - nudge, at: gap, ids: ids)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .disabled(frames <= effect.minimumFrames)
                    .accessibilityLabel("Shorter transition")
                    Button("Longer") {
                        document.storyboard.setTransitionFrames(frames + nudge, at: gap, ids: ids)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .disabled(frames >= board.framesAvailable(at: gap, ids: ids))
                    .accessibilityLabel("Longer transition")
                }
                if effect == .motion {
                    // REM: D-091 — "motion in-betweens with easing (from the Camera tool)":
                    // the Camera tool's own easing choices, nothing new.
                    let easing = board.transition(after: gap, ids: ids)?.easing ?? .easeBoth
                    Picker("Easing", selection: Binding(
                        get: { easing },
                        set: { document.storyboard.setEasing($0, at: gap, ids: ids) })) {
                        ForEach(CameraEasing.allCases) { Text($0.title).scaledFont(18).tag($0) }
                    }
                    .scaledFont(18)
                    .accessibilityLabel("Easing")
                    Text("Your Camera frames' layers move, scale and fade from one card's pose to "
                         + "the next. Cards without the Camera's scene cross-fade instead.")
                        .scaledFont(18).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Shortest for this effect: \(effect.minimumFrames) frames.")
                    .scaledFont(18).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TransitionEffect.allCases) { e in
                        let short = board.shortfall(e, at: gap, ids: ids)
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                document.storyboard.setEffect(e, at: gap, ids: ids)
                                document.say("Transition \(gap + 1): \(e.name)", kind: .edit)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: e == effect ? "checkmark.circle.fill" : "circle")
                                        .accessibilityHidden(true)
                                    Text(e.name).scaledFont(18)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(short != nil)
                            .accessibilityLabel(e.name)
                            .accessibilityAddTraits(e == effect ? .isSelected : [])
                            if let short {
                                Text("Needs \(short) more frame\(short == 1 ? "" : "s") — shorten another "
                                     + "transition, or remove a card.")
                                    .scaledFont(18).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 28)
                            }
                        }
                        .foregroundStyle(short == nil ? Color.primary : Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
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
