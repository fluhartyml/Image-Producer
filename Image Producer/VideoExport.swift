//
//  VideoExport.swift
//  Image Producer
//
//  VIDEO, PIECE 1 — Export ▸ Format ▸ Video (Amber Sheet D-077, D-073, D-078, D-070,
//  D-070a, D-070b, D-070c, D-072). The flipbook frames the Animated GIF already uses
//  (each layer with artwork, or the Camera's frames) become the cards of a video.
//
//  REM: D-026 — "image producer technically can make animations for app store connect"
//  (his word). This is that animation, written as a real video file. The wells taking
//  video (D-026, D-074–076), your own sound (D-071) and the storyboard (D-080 on) come
//  in later pieces.
//
//  REM: D-071 — "Sound: you bring your own. You can add your own sound effects; Image
//  Producer offers none, not even the Mac's built-in system sounds, to stay clear of
//  copyright." There is no sound list here and none ships with the app: the only sound a
//  video gets is a file you pick. "Videos with no sound stay silent" — no sound picked, no
//  audio track written.
//

import AVFoundation
import CoreVideo
import SwiftUI
import UniformTypeIdentifiers

enum VideoExport {
    /// REM: D-078 — "30 frames per second for every video (your yes, 2026-11-05)".
    nonisolated static let fps: Int32 = 30
    /// REM: D-070 — "App Store videos run 15 to 30 seconds."
    static let shortest: Double = 15
    static let longest: Double = 30
    /// REM: D-072 — "preset to 5 seconds (App Store Connect's default)".
    static let posterDefault: Double = 5

    /// REM: D-073 — "Both formats, as per App Store Connect: ProRes 422 HQ (.mov, highest
    /// quality) and H.264 (.mp4, small files)."
    nonisolated enum Codec: String, CaseIterable, Identifiable {
        case proRes = "ProRes 422 HQ (.mov)"
        case h264 = "H.264 (.mp4)"
        var id: String { rawValue }
        var codec: AVVideoCodecType { self == .proRes ? .proRes422HQ : .h264 }
        var fileType: AVFileType { self == .proRes ? .mov : .mp4 }
        var utType: UTType { self == .proRes ? .quickTimeMovie : .mpeg4Movie }
        var fileExtension: String { self == .proRes ? "mov" : "mp4" }
    }

    /// The video's plan: one entry per card, how many 1/30 s frames it holds.
    struct Plan {
        var cards: [ImageLayer]
        /// Frames each card holds before any padding (its time in the flipbook).
        var baseHolds: [Int]
        /// How many times each card's hold was doubled to reach 15 seconds (D-070c).
        var doublings: Int
        var holds: [Int] { baseHolds.map { $0 << doublings } }
        var baseFrames: Int { baseHolds.reduce(0, +) }
        var frames: Int { holds.reduce(0, +) }
        var baseSeconds: Double { Double(baseFrames) / Double(VideoExport.fps) }
        var seconds: Double { Double(frames) / Double(VideoExport.fps) }
        /// Start of each card, in seconds, for the dividers on the bar.
        var cardStarts: [Double] {
            var t = 0, out: [Double] = []
            for h in holds { out.append(Double(t) / Double(VideoExport.fps)); t += h }
            return out
        }
    }

    /// The cards and their holds. A card lasts as long as it does in the Animated GIF:
    /// its exposures (1 for an ordinary layer) at the flipbook's frames a second.
    /// REM: D-070c — "Under 15 seconds is padded by doubling each card in succession, not
    /// by repeating the stack, until 15 seconds is reached. Cards 1 2 3 become 1111 2222
    /// 3333 (yes), never 123 123 123 123 (no)." Doubling every hold together keeps the
    /// cards in order and in proportion; anything under 15 s doubles to under 30 s, so the
    /// padded video always lands in the green.
    /// REM: Claude's call, not from the sheet — until the storyboard's length-first timing
    /// (D-084, D-088) is built, a card's time comes from the flipbook's frames a second,
    /// the same slider the Animated GIF uses.
    static func plan(_ document: ImageDocument, sourceFPS: Double, cameraOnly: Bool) -> Plan {
        let cards = flipbookFrameLayers(document, cameraOnly: cameraOnly)
        let rate = max(1, sourceFPS)
        let base = cards.map { layer -> Int in
            let exposures = Double(max(1, layer.cameraFrame?.exposures ?? 1))
            return max(1, Int((exposures * Double(fps) / rate).rounded()))
        }
        var plan = Plan(cards: cards, baseHolds: base, doublings: 0)
        let target = Int(shortest) * Int(fps)
        while !cards.isEmpty && plan.frames < target { plan.doublings += 1 }
        return plan
    }

    /// Whole and half seconds read plainly: "5 s", "12.5 s".
    static func seconds(_ s: Double) -> String {
        let r = (s * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r)) s" : String(format: "%.1f s", r)
    }

    /// Render the cards and write the video to a temporary file. Returns its URL.
    @MainActor static func make(_ plan: Plan, document: ImageDocument, codec: Codec,
                                sound: URL? = nil) async throws -> URL {
        var images: [CGImage] = []
        for card in plan.cards {
            guard let cg = renderLayerImage(card, in: document) else { throw Failure.render }
            images.append(cg)
        }
        // REM: Claude's call, not from the sheet — H.264 needs an even width and height
        // (AVVideoSettings.h: "always use even number values … when encoding to
        // AVVideoCodecTypeH264"). An odd canvas gets one black row or column added; the
        // picture is never stretched (D-041's rule).
        let cw = document.canvasWidth, ch = document.canvasHeight
        let w = cw + cw % 2, h = ch + ch % 2
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageProducer-\(UUID().uuidString)")
            .appendingPathExtension(codec.fileExtension)
        try await write(images: images, holds: plan.holds, width: w, height: h,
                        canvas: CGSize(width: cw, height: ch), codec: codec, sound: sound, to: url)
        return url
    }

    nonisolated enum Failure: LocalizedError {
        case render, writer(String)
        var errorDescription: String? {
            switch self {
            case .render: return "A frame could not be drawn."
            case .writer(let why): return why
            }
        }
    }

    /// The AVAssetWriter loop, off the main thread. Each card is drawn once into a pixel
    /// buffer, then appended for every 1/30 s frame it holds.
    @concurrent nonisolated static func write(images: [CGImage], holds: [Int], width: Int, height: Int,
                                              canvas: CGSize, codec: Codec, sound: URL?, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: codec.fileType)
        // Your sound, read as plain stereo samples and written in App Store Connect's form.
        var soundReader: AVAssetReader?
        var soundOutput: AVAssetReaderTrackOutput?
        var soundInput: AVAssetWriterInput?
        if let sound {
            let asset = AVURLAsset(url: sound)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw Failure.writer("The sound file has no sound in it.")
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false])
            guard reader.canAdd(output) else { throw Failure.writer("The sound file can't be read.") }
            reader.add(output)
            // REM: D-071 — "App Store Connect's preview audio rule: stereo, AAC 256 kbps (or
            // PCM for ProRes), 44.1 or 48 kHz." Claude's call: the ProRes .mov gets PCM, the
            // H.264 .mp4 gets AAC 256 kbps; both stereo at 48 kHz.
            let settings: [String: Any] = codec == .proRes
                ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                   AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                   AVEncoderBitRateKey: 256_000]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw Failure.writer("Sound can't be added to this video format.") }
            writer.add(input)
            guard reader.startReading() else {
                throw Failure.writer(reader.error?.localizedDescription ?? "The sound file can't be read.")
            }
            soundReader = reader; soundOutput = output; soundInput = input
        }
        var pending: CMSampleBuffer?
        var soundDone = soundInput == nil
        let videoEnd = CMTime(value: Int64(holds.reduce(0, +)), timescale: fps)
        /// Feed sound up to `limit` while the writer will take it. Returns true if any went in.
        /// The sound plays from the start and is cut off where the video ends.
        func pumpSound(upTo limit: CMTime) -> Bool {
            guard let soundInput, let soundOutput, !soundDone else { return false }
            var fed = false
            while soundInput.isReadyForMoreMediaData {
                if pending == nil { pending = soundOutput.copyNextSampleBuffer() }
                guard let buffer = pending else {
                    soundInput.markAsFinished(); soundDone = true; return fed
                }
                let at = CMSampleBufferGetPresentationTimeStamp(buffer)
                if at >= videoEnd {
                    soundInput.markAsFinished(); soundDone = true
                    soundReader?.cancelReading(); pending = nil; return fed
                }
                if at > limit { return fed }
                guard soundInput.append(buffer) else { soundDone = true; return fed }
                pending = nil; fed = true
            }
            return fed
        }
        let settings: [String: Any] = [AVVideoCodecKey: codec.codec,
                                       AVVideoWidthKey: width,
                                       AVVideoHeightKey: height]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: width,
                                         kCVPixelBufferHeightKey as String: height]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw Failure.writer("This video format can't be written here.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw Failure.writer(writer.error?.localizedDescription ?? "The video could not be started.")
        }
        writer.startSession(atSourceTime: .zero)
        var frame: Int64 = 0
        for (image, hold) in zip(images, holds) {
            var made: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                attributes as CFDictionary, &made)
            guard let buffer = made else { throw Failure.writer("Out of memory for the video frames.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                       | CGBitmapInfo.byteOrder32Little.rawValue) {
                // Video has no transparency: clear parts of a card show black.
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.draw(image, in: CGRect(x: 0, y: CGFloat(height) - canvas.height,
                                           width: canvas.width, height: canvas.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            for _ in 0..<hold {
                while !input.isReadyForMoreMediaData {
                    // The writer interleaves picture and sound; give it sound while it waits.
                    if !pumpSound(upTo: CMTime(value: frame + Int64(fps), timescale: fps)) {
                        try await Task.sleep(for: .milliseconds(2))
                    }
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps)) else {
                    throw Failure.writer(writer.error?.localizedDescription ?? "A video frame could not be written.")
                }
                frame += 1
                _ = pumpSound(upTo: CMTime(value: frame + Int64(fps), timescale: fps))
            }
        }
        input.markAsFinished()
        while !soundDone {
            if !pumpSound(upTo: videoEnd) { try await Task.sleep(for: .milliseconds(2)) }
        }
        writer.endSession(atSourceTime: CMTime(value: frame, timescale: fps))
        await writer.finishWriting()
        if writer.status != .completed {
            throw Failure.writer(writer.error?.localizedDescription ?? "The video could not be finished.")
        }
    }
}

/// REM: D-070a — "its bar is colored by length: amber under 15 seconds (still exports,
/// padded — 070c), green from 15 to 30 seconds, red after 30 seconds. You're still allowed
/// past 30." The bar is colored by the cards' own length, before padding, so you can see
/// when padding will happen; dividers mark where each card starts in the video.
/// REM: D-072 — "a marker on the timeline labeled "Poster Frame", preset to 5 seconds
/// (App Store Connect's default), draggable to any moment."
struct VideoLengthBar: View {
    let plan: VideoExport.Plan
    @Binding var poster: Double

    private var color: Color {
        let s = plan.baseSeconds
        if s < VideoExport.shortest { return .orange }
        if s <= VideoExport.longest { return .green }
        return .red
    }

    var body: some View {
        let length = max(plan.seconds, 0.1)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.85))
                        .frame(height: 28).offset(y: 26)
                    ForEach(Array(plan.cardStarts.enumerated()), id: \.offset) { i, start in
                        if i > 0 {
                            Rectangle().fill(Color.black.opacity(0.5))
                                .frame(width: 1, height: 28)
                                .offset(x: w * start / length, y: 26)
                        }
                    }
                    let x = w * min(poster, length) / length
                    // The marker itself: a line at the moment, its label above.
                    Rectangle().fill(Color.primary).frame(width: 3, height: 34).offset(x: x - 1.5, y: 23)
                    Text("Poster Frame").scaledFont(18).fixedSize()
                        .offset(x: min(max(0, x - 55), max(0, w - 110)), y: -2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let t = Double(min(max(0, g.location.x), w) / max(w, 1)) * length
                    poster = (t * Double(VideoExport.fps)).rounded() / Double(VideoExport.fps)
                })
                .accessibilityElement()
                .accessibilityLabel("Poster Frame")
                .accessibilityValue(VideoExport.seconds(poster))
                .accessibilityAdjustableAction { dir in
                    switch dir {
                    case .increment: poster = min(length, poster + 1)
                    case .decrement: poster = max(0, poster - 1)
                    default: break
                    }
                }
            }
            .frame(height: 56)
        }
    }
}

/// The Video choice's part of the Export sheet: the codec, the length bar with its
/// Poster Frame marker, and what the length means.
struct VideoExportOptions: View {
    let plan: VideoExport.Plan
    @Binding var codec: VideoExport.Codec
    @Binding var poster: Double
    /// The sound file you picked (a private copy), or nil for a silent video.
    @Binding var sound: URL?
    @State private var pickingSound = false
    @State private var soundProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Video format").scaledFont(18).foregroundStyle(.secondary)
                Picker("Video format", selection: $codec) {
                    ForEach(VideoExport.Codec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .scaledFont(18)
                .fixedSize()
                .accessibilityLabel("Video format")
            }
            if plan.cards.isEmpty {
                Text("No frames yet. Each layer with artwork is one card of the video.")
                    .scaledFont(18).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VideoLengthBar(plan: plan, poster: $poster)
                Text(lengthNote).scaledFont(18)
                    .foregroundStyle(plan.baseSeconds > VideoExport.longest ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Poster Frame at \(VideoExport.seconds(poster)). Drag the marker to move it; "
                     + "set the same moment in App Store Connect.")
                    .scaledFont(18).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                soundRow
            }
        }
        .fileImporter(isPresented: $pickingSound, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // A private copy, so the export can read it after the picker's access ends.
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("ImageProducer-sound-\(UUID().uuidString)")
                .appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: copy)
                sound = copy
            } catch {
                soundProblem = "That sound file can't be opened: \(error.localizedDescription)"
            }
        }
        .alert("Sound", isPresented: Binding(get: { soundProblem != nil },
                                             set: { if !$0 { soundProblem = nil } })) {
            Button("OK", role: .cancel) { soundProblem = nil }
        } message: {
            Text(soundProblem ?? "").scaledFont(18)
        }
    }

    /// REM: D-071 — "you bring your own". Claude's call, not from the sheet: one sound
    /// file, playing from the start and cut off where the video ends.
    @ViewBuilder private var soundRow: some View {
        if let sound {
            HStack(spacing: 10) {
                Text("Sound: \(sound.lastPathComponent)").scaledFont(18)
                    .lineLimit(1).truncationMode(.middle)
                Button("Remove Sound") { self.sound = nil }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Remove sound")
            }
            Text("Your sound plays from the start and stops when the video ends.")
                .scaledFont(18).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 10) {
                Text("No sound: your video is silent.").scaledFont(18).foregroundStyle(.secondary)
                Button("Add Sound") { pickingSound = true }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).scaledFont(18)
                    .accessibilityLabel("Add sound")
            }
        }
    }

    private var lengthNote: String {
        let n = plan.cards.count
        let cards = "\(n) card\(n == 1 ? "" : "s"), 30 frames a second"
        let base = plan.baseSeconds
        if base < VideoExport.shortest {
            // REM: D-070c — padded by doubling each card, never by repeating the stack.
            return "\(cards). Your cards run \(VideoExport.seconds(base)), under 15 seconds, so each card "
                + "is held longer until the video reaches \(VideoExport.seconds(plan.seconds))."
        }
        if base <= VideoExport.longest {
            return "\(cards), \(VideoExport.seconds(base)). Ready for the App Store: 15 to 30 seconds."
        }
        // REM: D-070b — "A longer-than-30 video can be saved, and exported as an ordinary
        // video to anywhere in Finder. Only the green part (15–30 s) can go into the App
        // Store wells and the Project Bundle."
        return "\(cards), \(VideoExport.seconds(base)). Longer than 30 seconds: you can still save it "
            + "as an ordinary video, but the App Store takes 15 to 30 seconds."
    }
}
