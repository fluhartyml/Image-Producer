//
//  PSDImport.swift
//  Image Producer
//
//  OPEN A PHOTOSHOP FILE WITH ITS LAYERS — 1.1, 2026-10-05. The twin of PSDExport.swift.
//  Written from Adobe's published Photoshop File Format spec, Apple frameworks only, so it
//  runs on the iPad too (ImageIO there cannot read a PSD at all; on the Mac it can only
//  flatten one).
//
//  What comes in:
//    • Every pixel layer as its own image layer, at its own position and size on the canvas,
//      with its NAME (Unicode), VISIBILITY, OPACITY and BLEND MODE (Normal, Multiply,
//      Screen, Overlay — the four Image Producer has; others come in as Normal).
//    • LAYER MASKS and CLIPPING are applied to the pixels, so each layer looks the way it
//      did in Photoshop. GROUPS are flattened into the list; a hidden group hides its layers.
//    • The flattened composite, for a "replace this layer's picture" import.
//    • 8- and 16-bit RGB, Grayscale and CMYK (CMYK converted simply, not color-managed);
//      raw, RLE and ZIP compression.
//
//  ⚠️ Honest limits:
//    • Adjustment layers (Levels, Curves…) are skipped — there is nothing to apply them to.
//    • Text, smart objects and layer styles come in as the pixels Photoshop saved for them.
//    • Group opacity/blend, vector masks and fill opacity are not applied.
//    • Large-document PSB, 32-bit, Lab, Indexed and Bitmap files are refused (the Mac then
//      falls back to its flattened import).
//

import SwiftUI
import CoreGraphics
import Compression
import UniformTypeIdentifiers

// MARK: - Parsing

enum PSDReader {
    struct Layer {
        var name: String
        /// Position and size on the canvas (may extend past its edges).
        var left: Int, top: Int, width: Int, height: Int
        /// Straight RGBA, width × height × 4, top row first. Empty when width or height is 0.
        var rgba: [UInt8]
        var opacity: UInt8
        var isVisible: Bool
        var blendKey: String
    }

    struct Document {
        var width: Int, height: Int
        /// Bottom to top — the same order as Image Producer's layer list.
        var layers: [Layer]
        /// The flattened image Photoshop saved, straight RGBA, if it could be read.
        var composite: [UInt8]?
        var skippedAdjustments = 0
        var blendsShownAsNormal = 0
    }

    enum Failure: Error { case notPSD, unsupported(String), damaged }

    /// True when the data starts with Photoshop's signature.
    static func isPSD(_ data: Data) -> Bool { data.prefix(4) == Data("8BPS".utf8) }

    static func read(_ data: Data) throws -> Document {
        var c = Cursor(Array(data))
        guard try c.ascii4() == "8BPS" else { throw Failure.notPSD }
        let version = try c.u16()
        guard version == 1 else { throw Failure.unsupported("large-document PSB") }
        try c.skip(6)
        let channelCount = Int(try c.u16())
        let h = Int(try c.u32()), w = Int(try c.u32())
        let depth = Int(try c.u16())
        let mode = Int(try c.u16())
        guard (1...PSDWriter.maxSide).contains(w), (1...PSDWriter.maxSide).contains(h) else { throw Failure.damaged }
        guard depth == 8 || depth == 16 else { throw Failure.unsupported("\(depth)-bit") }
        guard mode == 1 || mode == 3 || mode == 4 else { throw Failure.unsupported("this color mode") }
        let header = Header(width: w, height: h, depth: depth, mode: mode)

        try c.skip(Int(try c.u32()))            // color mode data
        try c.skip(Int(try c.u32()))            // image resources

        var doc = Document(width: w, height: h, layers: [])
        var mergedHasAlpha = false
        let sectionLength = Int(try c.u32())
        let sectionEnd = c.p + sectionLength
        if sectionLength > 0 {
            let infoLength = Int(try c.u32())
            let infoEnd = c.p + infoLength
            if infoLength > 0 {
                let r = try readLayerInfo(&c, header, end: infoEnd)
                doc.layers = r.layers; doc.skippedAdjustments = r.skipped; doc.blendsShownAsNormal = r.odd
                mergedHasAlpha = r.mergedHasAlpha
            }
            c.p = infoEnd
            if c.p + 4 <= sectionEnd {
                try c.skip(Int(try c.u32()))    // global layer mask
            }
            // Some writers (and every 16-bit file) put the layers in a tagged block instead.
            while doc.layers.isEmpty, c.p + 12 <= sectionEnd {
                let sig = try c.ascii4()
                guard sig == "8BIM" || sig == "8B64" else { break }
                let key = try c.ascii4()
                let len = Int(try c.u32())
                let blockEnd = c.p + len
                if key == "Layr" || key == "Lr16" {
                    let r = try readLayerInfo(&c, header, end: blockEnd)
                    doc.layers = r.layers; doc.skippedAdjustments = r.skipped; doc.blendsShownAsNormal = r.odd
                    mergedHasAlpha = r.mergedHasAlpha
                }
                c.p = blockEnd + (len % 2)
            }
        }
        c.p = sectionEnd

        doc.composite = try? readComposite(&c, header, channels: channelCount, hasAlpha: mergedHasAlpha)
        return doc
    }

    // MARK: Layers

    private struct Header { let width: Int, height: Int, depth: Int, mode: Int }

    private struct Record {
        var top = 0, left = 0, bottom = 0, right = 0
        var channels: [(id: Int16, length: Int)] = []
        var blendKey = "norm"
        var opacity: UInt8 = 255
        var clipped = false
        var hidden = false
        var name = ""
        var sectionType = 0                 // 1/2 = group, 3 = end of group
        var isAdjustment = false
        var mask: (top: Int, left: Int, bottom: Int, right: Int, defaultColor: UInt8, disabled: Bool)?
        var width: Int { right - left }
        var height: Int { bottom - top }
    }

    /// Adjustment and fill layers: settings, not pixels.
    private static let adjustmentKeys: Set<String> = [
        "brit", "levl", "curv", "expA", "vibA", "hue ", "hue2", "blnc", "blwh", "phfl",
        "mixr", "clrL", "nvrt", "post", "thrs", "grdm", "selc", "SoCo", "GdFl", "PtFl"]

    private static let supportedBlends: Set<String> = ["norm", "mul ", "scrn", "over"]

    private static func readLayerInfo(_ c: inout Cursor, _ hd: Header, end: Int)
        throws -> (layers: [Layer], skipped: Int, odd: Int, mergedHasAlpha: Bool) {
        let rawCount = Int(try c.i16())
        let count = abs(rawCount)
        var records: [Record] = []
        for _ in 0..<count {
            var r = Record()
            r.top = Int(try c.i32()); r.left = Int(try c.i32())
            r.bottom = Int(try c.i32()); r.right = Int(try c.i32())
            guard r.width >= 0, r.height >= 0, r.width <= PSDWriter.maxSide, r.height <= PSDWriter.maxSide
            else { throw Failure.damaged }
            let n = Int(try c.u16())
            for _ in 0..<n { r.channels.append((try c.i16(), Int(try c.u32()))) }
            _ = try c.ascii4()                                  // "8BIM"
            r.blendKey = try c.ascii4()
            r.opacity = try c.u8()
            r.clipped = try c.u8() != 0
            r.hidden = (try c.u8() & 0x02) != 0
            try c.skip(1)
            let extraLength = Int(try c.u32())
            let extraEnd = c.p + extraLength

            let maskLength = Int(try c.u32())
            let maskEnd = c.p + maskLength
            if maskLength >= 18 {
                let t = Int(try c.i32()), l = Int(try c.i32()), b = Int(try c.i32()), rt = Int(try c.i32())
                let def = try c.u8()
                let flags = try c.u8()
                r.mask = (t, l, b, rt, def, (flags & 0x02) != 0)
            }
            c.p = maskEnd
            try c.skip(Int(try c.u32()))                        // blending ranges
            let nameLength = Int(try c.u8())
            // The legacy name is Mac Roman, not UTF-8 ("Base rød" read as "Base r?d"). The
            // Unicode block below, when present, replaces it.
            let nameBytes = Data(try c.bytes(nameLength))
            r.name = String(data: nameBytes, encoding: .macOSRoman) ?? String(decoding: nameBytes, as: UTF8.self)
            try c.skip((4 - (1 + nameLength) % 4) % 4)

            while c.p + 12 <= extraEnd {
                let sig = try c.ascii4()
                guard sig == "8BIM" || sig == "8B64" else { break }
                let key = try c.ascii4()
                let len = Int(try c.u32())
                let blockEnd = c.p + len
                if key == "luni", len >= 4 {
                    let units = Int(try c.u32())
                    var u16: [UInt16] = []
                    for _ in 0..<min(units, (len - 4) / 2) { u16.append(try c.u16()) }
                    let s = String(decoding: u16, as: UTF16.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    if !s.isEmpty { r.name = s }
                } else if key == "lsct" || key == "lsdk", len >= 4 {
                    r.sectionType = Int(try c.u32())
                } else if adjustmentKeys.contains(key) {
                    r.isAdjustment = true
                }
                c.p = blockEnd
            }
            c.p = extraEnd
            records.append(r)
        }

        // Channel image data, in record order.
        var layers: [Layer?] = []
        for r in records {
            var planes: [Int16: [UInt8]] = [:]
            for ch in r.channels {
                let start = c.p
                defer { c.p = start + ch.length }
                guard ch.length >= 2 else { continue }
                let compression = Int(try c.u16())
                let isMask = ch.id == -2
                guard ch.id >= -2 else { continue }             // -3 real mask: not used
                let pw = isMask ? (r.mask.map { $0.right - $0.left } ?? 0) : r.width
                let ph = isMask ? (r.mask.map { $0.bottom - $0.top } ?? 0) : r.height
                guard pw > 0, ph > 0 else { continue }
                let payload = try c.bytes(ch.length - 2)
                planes[ch.id] = try decodePlane(payload, compression: compression,
                                                width: pw, height: ph, depth: hd.depth)
            }
            layers.append(r.sectionType == 0 && !r.isAdjustment
                          ? assemble(r, planes, hd) : nil)
        }

        // Groups: walk top-down; a hidden group hides everything inside it.
        var hiddenDepth = 0
        var groupStack: [Bool] = []
        var effectiveHidden = [Bool](repeating: false, count: records.count)
        for i in stride(from: records.count - 1, through: 0, by: -1) {
            let r = records[i]
            switch r.sectionType {
            case 1, 2:
                groupStack.append(r.hidden)
                if r.hidden { hiddenDepth += 1 }
            case 3:
                if let wasHidden = groupStack.popLast(), wasHidden { hiddenDepth -= 1 }
            default:
                effectiveHidden[i] = r.hidden || hiddenDepth > 0
            }
        }

        // Clipping: a clipped layer only shows where the layer it clips to has pixels.
        var out: [Layer] = []
        var base: Layer?
        var skipped = 0, odd = 0
        for (i, r) in records.enumerated() {
            if r.isAdjustment { skipped += 1; continue }
            guard var layer = layers[i] else { continue }
            layer.isVisible = !effectiveHidden[i]
            if !supportedBlends.contains(layer.blendKey) { odd += 1; layer.blendKey = "norm" }
            if r.clipped, let b = base {
                clip(&layer, to: b)
            } else {
                base = layer
            }
            out.append(layer)
        }
        return (out, skipped, odd, rawCount < 0)
    }

    /// Build a layer's straight RGBA from its channel planes, mask applied.
    private static func assemble(_ r: Record, _ planes: [Int16: [UInt8]], _ hd: Header) -> Layer {
        let w = r.width, h = r.height
        var layer = Layer(name: r.name, left: r.left, top: r.top, width: w, height: h,
                          rgba: [], opacity: r.opacity, isVisible: !r.hidden, blendKey: r.blendKey)
        guard w > 0, h > 0 else { return layer }
        let n = w * h
        var px = [UInt8](repeating: 0, count: n * 4)
        let a = planes[-1]
        let p0 = planes[0], p1 = planes[1], p2 = planes[2], p3 = planes[3]
        for i in 0..<n {
            let (rr, gg, bb) = color(hd.mode, p0?[i] ?? 0, p1?[i] ?? 0, p2?[i] ?? 0, p3?[i] ?? 255)
            px[i * 4] = rr; px[i * 4 + 1] = gg; px[i * 4 + 2] = bb
            px[i * 4 + 3] = a?[i] ?? 255
        }
        if let m = r.mask, !m.disabled {
            let mask = planes[-2]
            let mw = m.right - m.left
            for y in 0..<h {
                let cy = r.top + y
                for x in 0..<w {
                    let cx = r.left + x
                    var v = m.defaultColor
                    if let mask, cy >= m.top, cy < m.bottom, cx >= m.left, cx < m.right {
                        v = mask[(cy - m.top) * mw + (cx - m.left)]
                    }
                    let k = (y * w + x) * 4 + 3
                    px[k] = UInt8((Int(px[k]) * Int(v) + 127) / 255)
                }
            }
        }
        layer.rgba = px
        return layer
    }

    /// One pixel to RGB. Photoshop stores CMYK inverted (255 = no ink).
    private static func color(_ mode: Int, _ c0: UInt8, _ c1: UInt8, _ c2: UInt8, _ c3: UInt8)
        -> (UInt8, UInt8, UInt8) {
        switch mode {
        case 1: return (c0, c0, c0)
        case 4:
            let k = Int(c3)
            return (UInt8(Int(c0) * k / 255), UInt8(Int(c1) * k / 255), UInt8(Int(c2) * k / 255))
        default: return (c0, c1, c2)
        }
    }

    /// Multiply a clipped layer's alpha by its base layer's alpha at the same canvas spot.
    private static func clip(_ layer: inout Layer, to base: Layer) {
        guard layer.width > 0, layer.height > 0 else { return }
        for y in 0..<layer.height {
            let by = layer.top + y - base.top
            for x in 0..<layer.width {
                let bx = layer.left + x - base.left
                var ba = 0
                if base.width > 0, by >= 0, by < base.height, bx >= 0, bx < base.width {
                    ba = Int(base.rgba[(by * base.width + bx) * 4 + 3])
                }
                let k = (y * layer.width + x) * 4 + 3
                layer.rgba[k] = UInt8((Int(layer.rgba[k]) * ba + 127) / 255)
            }
        }
    }

    // MARK: Composite

    private static func readComposite(_ c: inout Cursor, _ hd: Header, channels: Int, hasAlpha: Bool) throws -> [UInt8] {
        let w = hd.width, h = hd.height
        let compression = Int(try c.u16())
        let colorChannels = hd.mode == 1 ? 1 : (hd.mode == 4 ? 4 : 3)
        let wanted = min(channels, colorChannels + (hasAlpha ? 1 : 0))
        guard wanted >= colorChannels else { throw Failure.damaged }
        let bpr = w * hd.depth / 8
        var planes: [[UInt8]] = []
        switch compression {
        case 0:
            for _ in 0..<wanted { planes.append(narrow(Array(try c.bytes(bpr * h)), depth: hd.depth)) }
        case 1:
            var counts: [Int] = []
            for _ in 0..<(channels * h) { counts.append(Int(try c.u16())) }
            for ch in 0..<wanted {
                var plane: [UInt8] = []
                plane.reserveCapacity(bpr * h)
                for y in 0..<h { plane += try unpackBits(try c.bytes(counts[ch * h + y]), length: bpr) }
                planes.append(narrow(plane, depth: hd.depth))
            }
        default:
            throw Failure.unsupported("compressed composite")
        }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let (r, g, b) = color(hd.mode, planes[0][i],
                                  planes.count > 1 ? planes[min(1, planes.count - 1)][i] : 0,
                                  planes.count > 2 ? planes[2][i] : 0,
                                  planes.count > 3 ? planes[3][i] : 255)
            px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b
            if hasAlpha, planes.count > colorChannels { px[i * 4 + 3] = planes[colorChannels][i] }
        }
        return px
    }

    // MARK: Decoding

    private static func decodePlane(_ payload: ArraySlice<UInt8>, compression: Int,
                                    width w: Int, height h: Int, depth: Int) throws -> [UInt8] {
        let bpr = w * depth / 8
        var plane: [UInt8]
        switch compression {
        case 0:
            guard payload.count >= bpr * h else { throw Failure.damaged }
            plane = Array(payload.prefix(bpr * h))
        case 1:
            var c = Cursor(Array(payload))
            var counts: [Int] = []
            for _ in 0..<h { counts.append(Int(try c.u16())) }
            plane = []
            plane.reserveCapacity(bpr * h)
            for count in counts { plane += try unpackBits(try c.bytes(count), length: bpr) }
        case 2, 3:
            plane = try inflate(payload, size: bpr * h)
            if compression == 3 { undoPrediction(&plane, width: w, height: h, depth: depth) }
        default:
            throw Failure.unsupported("compression \(compression)")
        }
        return narrow(plane, depth: depth)
    }

    /// 16-bit samples down to 8 (the high byte); 8-bit passes through.
    private static func narrow(_ plane: [UInt8], depth: Int) -> [UInt8] {
        guard depth == 16 else { return plane }
        return stride(from: 0, to: plane.count - 1, by: 2).map { plane[$0] }
    }

    /// PackBits, decoded to exactly `length` bytes.
    static func unpackBits(_ src: ArraySlice<UInt8>, length: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(length)
        var i = src.startIndex
        while i < src.endIndex, out.count < length {
            let n = Int(Int8(bitPattern: src[i])); i += 1
            if n >= 0 {
                let end = i + n + 1
                guard end <= src.endIndex else { throw Failure.damaged }
                out += src[i..<end]; i = end
            } else if n != -128 {
                guard i < src.endIndex else { throw Failure.damaged }
                out += repeatElement(src[i], count: 1 - n); i += 1
            }
        }
        guard out.count >= length else { throw Failure.damaged }
        return out.count == length ? out : Array(out.prefix(length))
    }

    /// Photoshop's ZIP is a zlib stream; Apple's decoder wants the raw deflate inside it.
    private static func inflate(_ src: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        guard src.count > 2, size > 0 else { throw Failure.damaged }
        let body = Array(src.dropFirst(2))
        var out = [UInt8](repeating: 0, count: size)
        let written = out.withUnsafeMutableBufferPointer { dst in
            body.withUnsafeBufferPointer { s in
                compression_decode_buffer(dst.baseAddress!, size, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.damaged }
        return out
    }

    /// ZIP-with-prediction stores each row as differences from the sample to its left.
    private static func undoPrediction(_ p: inout [UInt8], width w: Int, height h: Int, depth: Int) {
        for y in 0..<h {
            if depth == 16 {
                let row = y * w * 2
                for x in 1..<max(1, w) {
                    let i = row + x * 2, j = i - 2
                    let v = (UInt16(p[i]) << 8 | UInt16(p[i + 1])) &+ (UInt16(p[j]) << 8 | UInt16(p[j + 1]))
                    p[i] = UInt8(v >> 8); p[i + 1] = UInt8(v & 0xFF)
                }
            } else {
                let row = y * w
                for x in 1..<max(1, w) { p[row + x] = p[row + x] &+ p[row + x - 1] }
            }
        }
    }

    /// Bounds-checked big-endian reader — a damaged file throws instead of crashing.
    private struct Cursor {
        let b: [UInt8]
        var p = 0
        init(_ b: [UInt8]) { self.b = b }
        mutating func bytes(_ n: Int) throws -> ArraySlice<UInt8> {
            guard n >= 0, p + n <= b.count else { throw Failure.damaged }
            defer { p += n }
            return b[p..<(p + n)]
        }
        mutating func skip(_ n: Int) throws { _ = try bytes(n) }
        mutating func u8() throws -> UInt8 { try bytes(1).first! }
        mutating func u16() throws -> UInt16 { let s = try bytes(2); return UInt16(s[s.startIndex]) << 8 | UInt16(s[s.startIndex + 1]) }
        mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
        mutating func u32() throws -> UInt32 { UInt32(try u16()) << 16 | UInt32(try u16()) }
        mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
        mutating func ascii4() throws -> String { String(decoding: try bytes(4), as: UTF8.self) }
    }
}

// MARK: - Into Image Producer

/// Straight RGBA to PNG (CGImage takes non-premultiplied alpha directly).
func pngFromStraightRGBA(_ rgba: [UInt8], width: Int, height: Int) -> Data? {
    guard width > 0, height > 0, rgba.count == width * height * 4,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let provider = CGDataProvider(data: Data(rgba) as CFData),
          let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width * 4, space: space,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false,
                           intent: .defaultIntent)
    else { return nil }
    return pngData(from: cg)
}

extension PSDReader.Document {
    /// The flattened picture: Photoshop's own composite when the file has one, otherwise the
    /// visible layers stacked (Normal blend) — what "Import to Selected Layer" uses.
    func flattenedPNG() -> Data? {
        if let composite { return pngFromStraightRGBA(composite, width: width, height: height) }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for l in layers where l.isVisible && l.width > 0 {
            for y in 0..<l.height {
                let cy = l.top + y
                guard cy >= 0, cy < height else { continue }
                for x in 0..<l.width {
                    let cx = l.left + x
                    guard cx >= 0, cx < width else { continue }
                    let s = (y * l.width + x) * 4, d = (cy * width + cx) * 4
                    let sa = Double(l.rgba[s + 3]) / 255 * Double(l.opacity) / 255
                    let da = Double(px[d + 3]) / 255
                    let oa = sa + da * (1 - sa)
                    guard oa > 0 else { continue }
                    for k in 0..<3 {
                        let v = (Double(l.rgba[s + k]) * sa + Double(px[d + k]) * da * (1 - sa)) / oa
                        px[d + k] = UInt8(min(255, max(0, v.rounded())))
                    }
                    px[d + 3] = UInt8((oa * 255).rounded())
                }
            }
        }
        return pngFromStraightRGBA(px, width: width, height: height)
    }

    /// Image Producer layers, bottom to top, placed on a `canvas` of the given pixel size.
    /// A PSD of a different size is centered on that canvas.
    func imageLayers(canvas: CGSize) -> [ImageLayer] {
        let W = Double(canvas.width), H = Double(canvas.height)
        let ref = min(W, H)
        let dx = (W - Double(width)) / 2, dy = (H - Double(height)) / 2
        return layers.map { l in
            var layer = ImageLayer(name: l.name.isEmpty ? "Layer" : l.name, role: .content)
            layer.nameLinkedToText = false
            layer.isVisible = l.isVisible
            layer.opacity = Double(l.opacity) / 255
            switch l.blendKey {
            case "mul ": layer.blend = .multiply
            case "scrn": layer.blend = .screen
            case "over": layer.blend = .overlay
            default:     break
            }
            if l.width > 0, l.height > 0,
               let png = pngFromStraightRGBA(l.rgba, width: l.width, height: l.height) {
                layer.setImage(png)
                // The image fits a square of (short canvas edge × scale), so the longer
                // side of the layer sets the scale; that keeps it at its own pixel size.
                layer.transform.scale = Double(max(l.width, l.height)) / ref
                layer.transform.contentAspect = Double(l.width) / Double(l.height)
                layer.transform.center = CGPoint(x: (Double(l.left) + Double(l.width) / 2 + dx) / W,
                                                 y: (Double(l.top) + Double(l.height) / 2 + dy) / H)
            }
            return layer
        }
    }

    /// A one-line account of what did not come across, or nil when everything did.
    var importNote: String? {
        var parts: [String] = []
        if skippedAdjustments > 0 {
            parts.append("\(skippedAdjustments) adjustment layer\(skippedAdjustments == 1 ? "" : "s") skipped")
        }
        if blendsShownAsNormal > 0 {
            parts.append("\(blendsShownAsNormal) blend mode\(blendsShownAsNormal == 1 ? "" : "s") shown as Normal")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Seed a NEW document from a PSD: its size becomes the canvas and its layers the stack —
/// the PSD is the template, nothing else is invented. False if the file can't be read
/// with layers (the caller then falls back to the flattened image path).
@MainActor func importPSDAsLayers(_ url: URL, into document: ImageDocument) -> Bool {
    guard let raw = try? Data(contentsOf: url), PSDReader.isPSD(raw),
          let psd = try? PSDReader.read(raw) else { return false }
    document.canvasWidth = psd.width
    document.canvasHeight = psd.height
    var layers = psd.imageLayers(canvas: document.canvasPixelSize)
    if layers.isEmpty {                                    // a flat PSD: one picture
        guard let png = psd.flattenedPNG() else { return false }
        var layer = ImageLayer(name: url.deletingPathExtension().lastPathComponent, role: .content)
        layer.setImage(png)
        layers = [layer]
    }
    document.captureHistoryBaselineIfNeeded()
    document.layers.append(contentsOf: layers)
    document.recordHistory(toolID: Tool.image.rawValue, groupTitle: Tool.image.title,
                           actionLabel: "Open Photoshop file (\(layers.count) layer\(layers.count == 1 ? "" : "s"))",
                           layerID: layers.last!.id)
    if let note = psd.importNote { document.say("Photoshop file opened — \(note)", kind: .info) }
    return true
}

extension ImageDocument {
    /// True when the file is a Photoshop document, by content first, extension as fallback.
    nonisolated static func isPSD(_ url: URL) -> Bool {
        if let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
           t.conforms(to: .photoshopDocument) { return true }
        return url.pathExtension.lowercased() == "psd"
    }
}
