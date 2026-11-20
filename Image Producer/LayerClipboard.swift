//
//  LayerClipboard.swift
//  Image Producer
//
//  REM: COPY A LAYER IN ONE TAB, PASTE IT IN ANOTHER. Michael, 2026-11-20, building the
//  CryoTunes App Store universal asset: "take this layer select and make it active, press
//  command c and switch to the other tab select 'the coast' and press command V to paste it
//  above 'the coast' layer".
//
//  REM: WHY A PRIVATE CLIPBOARD TYPE, NOT JUST THE PNG. The PNG is pixels. Pasting it would
//  turn a text or symbol layer into a picture, and his rule is "no rasterization please
//  unless specifically asked to by the user" (2026-10-03). So ⌘C also puts the layer itself
//  on the clipboard under our own type; ⌘V in any Image Producer tab reads that first and
//  gets the live layer back. Other apps never see this type and keep taking the PNG.
//
//  REM: THE CANVAS SIZE TRAVELS WITH IT. A layer's scale is a fraction of its canvas's short
//  edge, so the same number means a different pixel size on a different canvas. Carrying the
//  source canvas size lets paste keep the layer's PIXEL size, as Photoshop does.
//

#if os(macOS)
import AppKit

enum LayerClipboard {
    static let type = NSPasteboard.PasteboardType("com.nightgard.Image-Producer.layer")

    struct Clip: Codable {
        var layer: ImageLayer
        var canvasWidth: Int
        var canvasHeight: Int
    }

    static func encode(_ layer: ImageLayer, canvasWidth: Int, canvasHeight: Int) -> Data? {
        try? JSONEncoder().encode(Clip(layer: layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight))
    }

    static func decode(_ data: Data) -> Clip? {
        try? JSONDecoder().decode(Clip.self, from: data)
    }
}
#endif
