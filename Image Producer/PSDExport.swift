//
//  PSDExport.swift
//  Image Producer
//
//  SAVE AS PHOTOSHOP (.psd), LAYERS KEPT — 1.1, 2026-10-05.
//  Michael: "photoshop support is probably a necesity for a graphics art application."
//
//  Written from Adobe's published Photoshop File Format spec, Apple frameworks only — no
//  third-party PSD library (the "no kits other than Apple kits" rule), and it runs the same
//  on iPad and Mac. ImageIO can READ a PSD on the Mac but cannot WRITE one anywhere.
//
//  What goes in the file:
//    • One Photoshop layer per Image Producer layer, bottom to top, each the full canvas
//      size, 8-bit RGB + transparency, RLE (PackBits) compressed.
//    • The layer's NAME, VISIBILITY (hidden stays hidden), OPACITY and BLEND MODE as
//      Photoshop's own layer settings — so they stay adjustable in Photoshop instead of
//      being baked into the pixels.
//    • Light and Dark go in as ordinary layers with their own visibility.
//    • The flattened composite, which is what Preview, Quick Look and Finder show.
//
//  ⚠️ Honest limits:
//    • Text, symbols, glow and gradients arrive as PIXELS — Photoshop's live text and layer
//      styles are not written. Same trade-off as the layer PDF.
//    • Blend STRENGTH has no Photoshop equivalent. A blend at 50% or more is written as that
//      mode; under 50% as Normal.
//    • Photoshop's PSD limit is 30,000 px on a side; larger canvases return nil (PSB would
//      be the format for those).
//

import SwiftUI
import CoreGraphics

// MARK: - Rendering the document into PSD layers

/// The whole project as a layered Photoshop file, or nil if it can't be written.
@MainActor func makeLayeredPSD(_ document: ImageDocument) -> Data? {
    let w = Int(document.canvasPixelSize.width)
    let h = Int(document.canvasPixelSize.height)
    guard w > 0, h > 0, w <= PSDWriter.maxSide, h <= PSDWriter.maxSide,
          let compositeCG = renderCanvasImage(document),
          let composite = straightRGBA(compositeCG, width: w, height: h) else { return nil }

    var layers: [PSDWriter.Layer] = []
    for layer in document.layers {                 // model order = bottom to top = PSD order
        // Render at full strength and Normal blend; Photoshop applies the layer's opacity
        // and blend itself, so they stay live settings rather than being baked in twice.
        var plain = layer
        plain.opacity = 1
        plain.blend = nil
        guard let cg = renderLayerImage(plain, in: document),
              let rgba = straightRGBA(cg, width: w, height: h) else { return nil }
        layers.append(PSDWriter.Layer(name: layer.name,
                                      rgba: rgba,
                                      opacity: UInt8((min(max(layer.opacity, 0), 1) * 255).rounded()),
                                      isHidden: !layer.isVisible,
                                      blendKey: psdBlendKey(layer)))
    }
    return PSDWriter.data(width: w, height: h, layers: layers, composite: composite)
}

/// Photoshop's four-letter blend key for the layer's blend mode.
private func psdBlendKey(_ layer: ImageLayer) -> String {
    let mode = layer.blend ?? .normal
    if layer.blendAmount < 0.5 { return "norm" }   // a weak blend reads closer to Normal
    switch mode {
    case .normal:   return "norm"
    case .multiply: return "mul "
    case .screen:   return "scrn"
    case .overlay:  return "over"
    }
}

/// The image as straight (un-premultiplied) 8-bit RGBA in sRGB, top row first — what a
/// PSD stores. Core Graphics only draws premultiplied, so the alpha is divided back out.
func straightRGBA(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    var px = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = px.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }
    var i = 0
    while i < px.count {
        let a = Int(px[i + 3])
        if a > 0 && a < 255 {
            for c in 0..<3 { px[i + c] = UInt8(min(255, (Int(px[i + c]) * 255 + a / 2) / a)) }
        }
        i += 4
    }
    return px
}

// MARK: - The file format

/// Writes an 8-bit RGB Photoshop document. Pure byte work, no UI — kept separate so the
/// output can be checked against an independent PSD reader.
enum PSDWriter {
    static let maxSide = 30_000

    struct Layer {
        var name: String
        /// Straight RGBA, width × height × 4, top row first.
        var rgba: [UInt8]
        var opacity: UInt8
        var isHidden: Bool
        var blendKey: String
    }

    /// The finished file. `composite` is the flattened image (straight RGBA).
    static func data(width w: Int, height h: Int, layers: [Layer], composite: [UInt8]) -> Data? {
        let count = w * h * 4
        guard w > 0, h > 0, w <= maxSide, h <= maxSide, composite.count == count,
              layers.allSatisfy({ $0.rgba.count == count }), layers.count <= Int(Int16.max)
        else { return nil }

        var out = Data()
        // File header
        out.append(ascii: "8BPS")
        out.append(u16: 1)                       // version 1 = PSD
        out.append(Data(count: 6))               // reserved
        out.append(u16: 4)                       // channels: R, G, B + transparency
        out.append(u32: UInt32(h))
        out.append(u32: UInt32(w))
        out.append(u16: 8)                       // bits per channel
        out.append(u16: 3)                       // color mode: RGB
        // Color mode data, image resources: none
        out.append(u32: 0)
        out.append(u32: 0)

        // Layer and mask information
        var info = Data()
        // Negative count = the composite's alpha channel is the merged transparency.
        info.append(i16: -Int16(layers.count))
        var channelData = Data()
        for layer in layers {
            // Channel order: transparency (-1), then R, G, B — records and data match.
            let channels: [(id: Int16, offset: Int)] = [(-1, 3), (0, 0), (1, 1), (2, 2)]
            var lengths: [UInt32] = []
            for ch in channels {
                let encoded = rleChannel(layer.rgba, width: w, height: h, offset: ch.offset)
                channelData.append(u16: 1)       // compression: RLE
                channelData.append(encoded)
                lengths.append(UInt32(2 + encoded.count))
            }
            // Layer record — every layer covers the full canvas.
            info.append(i32: 0); info.append(i32: 0)                       // top, left
            info.append(i32: Int32(h)); info.append(i32: Int32(w))         // bottom, right
            info.append(u16: UInt16(channels.count))
            for (ch, len) in zip(channels, lengths) {
                info.append(i16: ch.id)
                info.append(u32: len)
            }
            info.append(ascii: "8BIM")
            info.append(ascii: layer.blendKey)
            info.append(layer.opacity)
            info.append(UInt8(0))                                          // clipping: base
            info.append(UInt8(layer.isHidden ? 0x02 : 0x00))               // flags: bit 1 = hidden
            info.append(UInt8(0))                                          // filler

            var extra = Data()
            extra.append(u32: 0)                                           // no layer mask
            extra.append(u32: 0)                                           // no blending ranges
            extra.append(pascalName(layer.name))
            extra.append(unicodeNameBlock(layer.name))
            info.append(u32: UInt32(extra.count))
            info.append(extra)
        }
        info.append(channelData)
        if info.count % 2 == 1 { info.append(UInt8(0)) }                   // even length

        var layerAndMask = Data()
        layerAndMask.append(u32: UInt32(info.count))
        layerAndMask.append(info)
        layerAndMask.append(u32: 0)                                        // no global mask
        out.append(u32: UInt32(layerAndMask.count))
        out.append(layerAndMask)

        // Image data: the composite, RLE. All row byte-counts for every channel come
        // first, then every channel's rows, in R, G, B, A order.
        out.append(u16: 1)
        var counts = Data()
        var rows = Data()
        for offset in 0..<4 {
            for y in 0..<h {
                let start = y * w * 4
                let packed = packBits(stride(from: start + offset, to: start + w * 4, by: 4).map { composite[$0] })
                counts.append(u16: UInt16(packed.count))
                rows.append(contentsOf: packed)
            }
        }
        out.append(counts)
        out.append(rows)
        return out
    }

    /// One layer channel as PSD stores it: a byte count per row, then the packed rows.
    private static func rleChannel(_ rgba: [UInt8], width w: Int, height h: Int, offset: Int) -> Data {
        var counts = Data()
        var rows = Data()
        for y in 0..<h {
            let start = y * w * 4
            let packed = packBits(stride(from: start + offset, to: start + w * 4, by: 4).map { rgba[$0] })
            counts.append(u16: UInt16(packed.count))
            rows.append(contentsOf: packed)
        }
        return counts + rows
    }

    /// PackBits (Apple's own run-length scheme, which Photoshop uses): runs of one
    /// repeated byte become two bytes; everything else is copied in literal stretches.
    static func packBits(_ row: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(row.count + row.count / 128 + 1)
        let n = row.count
        var i = 0
        while i < n {
            var run = 1
            while i + run < n, run < 128, row[i + run] == row[i] { run += 1 }
            if run >= 2 {
                out.append(UInt8(bitPattern: Int8(1 - run)))
                out.append(row[i])
                i += run
                continue
            }
            // Literal stretch: stop where a run of three begins, or at 128 bytes.
            var j = i + 1
            while j < n, j - i < 128 {
                if j + 2 < n, row[j] == row[j + 1], row[j] == row[j + 2] { break }
                j += 1
            }
            out.append(UInt8(j - i - 1))
            out.append(contentsOf: row[i..<j])
            i = j
        }
        return out
    }

    /// The legacy layer name: a length-prefixed byte string, padded to a multiple of 4.
    /// Non-ASCII characters become "?" here; the Unicode block carries the real name.
    private static func pascalName(_ name: String) -> Data {
        let bytes = Array(name.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : UInt8(ascii: "?") }.prefix(255))
        var d = Data([UInt8(bytes.count)])
        d.append(contentsOf: bytes)
        while d.count % 4 != 0 { d.append(0) }
        return d
    }

    /// Additional layer info "luni": the layer name in UTF-16, so names keep every character.
    private static func unicodeNameBlock(_ name: String) -> Data {
        var body = Data()
        let units = Array(name.utf16)
        body.append(u32: UInt32(units.count))
        for u in units { body.append(u16: u) }
        while body.count % 4 != 0 { body.append(0) }
        var d = Data()
        d.append(ascii: "8BIM")
        d.append(ascii: "luni")
        d.append(u32: UInt32(body.count))
        d.append(body)
        return d
    }
}

// MARK: - Big-endian writing

private extension Data {
    mutating func append(ascii s: String) { append(contentsOf: Array(s.utf8)) }
    mutating func append(u16 v: UInt16) { append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)]) }
    mutating func append(i16 v: Int16) { append(u16: UInt16(bitPattern: v)) }
    mutating func append(u32 v: UInt32) {
        append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
    mutating func append(i32 v: Int32) { append(u32: UInt32(bitPattern: v)) }
}
