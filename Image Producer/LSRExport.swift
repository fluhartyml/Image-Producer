//
//  LSRExport.swift
//  Image Producer
//
//  APPLE TV PARALLAX IMAGE (.lsr) — 2026-10-21.
//  Michael: "can we make parallax images in image producer" · "both, lsr export and tilt preview"
//
//  Written from Apple's published Asset Catalog Format reference (the LSR pages in the
//  Documentation Archive), Apple frameworks only — no third-party zip or LSR library.
//
//  What an .lsr is: a ZIP of the same tree as an Xcode .imagestack, with no wrapping folder:
//      Contents.json                          ← layers listed FRONT to BACK, canvas size
//      <name>.imagestacklayer/Contents.json
//      <name>.imagestacklayer/Content.imageset/Contents.json
//      <name>.imagestacklayer/Content.imageset/Content.png
//
//  Which layers: every VISIBLE layer that has something to show, bottom layer = back.
//  Hidden layers stay out — the parallax is what is on screen. Each layer is rendered at
//  full canvas size with its opacity baked in: LSR has no opacity or blend setting.
//
//  ⚠️ Honest limits:
//    • Apple's rule is 2 to 5 layers with an opaque back layer. The sheet WARNS when the
//      project is outside that; it never refuses the export.
//    • Blend modes are drawn as Normal (no LSR equivalent).
//

import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

extension UTType {
    /// Apple's layered source image. Falls back to a plain extension type so the exporter
    /// still writes ".lsr" where the system does not declare one.
    static var layeredSourceImage: UTType {
        UTType(filenameExtension: "lsr", conformingTo: .data) ?? .data
    }
}

/// The layers that go into the parallax image, bottom (back) to top (front).
@MainActor func parallaxLayers(_ document: ImageDocument) -> [ImageLayer] {
    document.layers.filter { layer in
        guard layer.isVisible else { return false }
        switch layer.role {
        case .content: return !layer.elements.isEmpty
        case .background(_, let fillHex): return fillHex != nil
        }
    }
}

/// The project as an Apple TV .lsr, or nil if it can't be written.
@MainActor func makeLSR(_ document: ImageDocument) -> Data? {
    let w = Int(document.canvasPixelSize.width)
    let h = Int(document.canvasPixelSize.height)
    let layers = parallaxLayers(document)
    guard w > 0, h > 0, !layers.isEmpty else { return nil }

    var files: [(path: String, data: Data)] = []
    var folders: [String] = []
    var used = Set<String>()
    // Front to back is the order Contents.json lists them in.
    for (index, layer) in layers.reversed().enumerated() {
        guard let cg = renderLayerImage(layer, in: document),
              let png = encodedImageData(cg, as: .png) else { return nil }
        var name = lsrSafeName(layer.name, fallback: "Layer \(index + 1)")
        if used.contains(name) { name += " \(index + 1)" }
        used.insert(name)
        let folder = "\(name).imagestacklayer"
        folders.append(folder)
        files.append(("\(folder)/Contents.json", lsrJSON(["info": lsrInfo])))
        files.append(("\(folder)/Content.imageset/Contents.json",
                      lsrJSON(["images": [["filename": "Content.png", "idiom": "universal", "scale": "1x"]],
                               "info": lsrInfo])))
        files.append(("\(folder)/Content.imageset/Content.png", png))
    }
    files.insert(("Contents.json",
                  lsrJSON(["info": lsrInfo,
                           "layers": folders.map { ["filename": $0] },
                           "properties": ["canvasSize": ["width": w, "height": h]]])), at: 0)
    return ZipWriter.stored(files)
}

private let lsrInfo: [String: Any] = ["author": "com.nightgard.Image-Producer", "version": 1]

private func lsrJSON(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
}

/// A layer name that is safe as a folder name inside the zip.
private func lsrSafeName(_ name: String, fallback: String) -> String {
    let cleaned = name.map { "/\\:".contains($0) ? "-" : $0 }
    let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

// MARK: - ZIP, stored (no compression — the PNGs are already compressed)

/// A minimal ZIP writer from PKWARE's published APPNOTE: local headers, central
/// directory, end record. Stored entries only, UTF-8 names, no directory entries.
enum ZipWriter {
    static func stored(_ files: [(path: String, data: Data)], date: Date = Date()) -> Data? {
        let (time, day) = dosDateTime(date)
        var out = Data()
        var central = Data()
        for file in files {
            let name = Data(file.path.utf8)
            guard file.data.count < Int(UInt32.max), out.count < Int(UInt32.max) else { return nil }
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)
            let offset = UInt32(out.count)

            out.le32(0x04034b50)
            out.le16(20); out.le16(0x0800); out.le16(0)      // version · UTF-8 names · stored
            out.le16(time); out.le16(day)
            out.le32(crc); out.le32(size); out.le32(size)
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(file.data)

            central.le32(0x02014b50)
            central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(time); central.le16(day)
            central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0)
            central.le32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50)
        out.le16(0); out.le16(0)
        out.le16(UInt16(files.count)); out.le16(UInt16(files.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset)
        out.le16(0)
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    /// MS-DOS time and date, which is what ZIP stores.
    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = (c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2
        let day = max((c.year ?? 1980) - 1980, 0) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1)
        return (UInt16(time), UInt16(day))
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
}

// MARK: - Tilt preview

/// A live preview of the parallax: the layers stacked, the front ones moving further as the
/// picture tilts, with a soft moving shine. Apple does not publish its own tilt math, so
/// this is a close approximation, not the Apple TV's exact effect.
/// Hover or drag over it to tilt; Animate sweeps it in a slow circle.
struct ParallaxTiltPreview: View {
    let document: ImageDocument
    @State private var images: [CGImage] = []      // back to front
    @State private var tilt = CGPoint.zero          // -1…1 on each axis
    @State private var animate = false

    var body: some View {
        let size = document.canvasPixelSize
        let aspect = size.height > 0 ? size.width / size.height : 1
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if animate {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate * 0.8
                        stack(tilt: CGPoint(x: cos(t), y: sin(t)), aspect: aspect)
                    }
                } else {
                    stack(tilt: tilt, aspect: aspect)
                }
            }
            .frame(maxWidth: .infinity)
            Toggle("Animate", isOn: $animate).font(.system(size: 18))
        }
        .onAppear { images = parallaxLayers(document).compactMap { renderLayerImage($0, in: document) } }
    }

    private func stack(tilt: CGPoint, aspect: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shift = w * 0.04
            let n = images.count
            ZStack {
                ForEach(images.indices, id: \.self) { i in
                    // Back layer barely moves; the front layer moves the most.
                    let depth = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
                    Image(decorative: images[i], scale: 1)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.06 + 0.04 * depth)
                        .offset(x: tilt.x * shift * depth, y: tilt.y * shift * depth)
                }
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: .center,
                               startRadius: 0, endRadius: w * 0.6)
                    .offset(x: -tilt.x * w * 0.35, y: -tilt.y * w * 0.35 / aspect)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: w / aspect)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.035, style: .continuous))
            .rotation3DEffect(.degrees(-tilt.y * 8), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt.x * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): self.tilt = normalized(p, in: CGSize(width: w, height: w / aspect))
                case .ended: withAnimation(.easeOut(duration: 0.3)) { self.tilt = .zero }
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { self.tilt = normalized($0.location, in: CGSize(width: w, height: w / aspect)) }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.3)) { self.tilt = .zero } })
        }
        .aspectRatio(aspect, contentMode: .fit)
        .padding(16)        // room for the tilt and shadow
    }

    private func normalized(_ p: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: min(max(p.x / size.width * 2 - 1, -1), 1),
                       y: min(max(p.y / size.height * 2 - 1, -1), 1))
    }
}
