//
//  SelectionToolTests.swift
//  Image ProducerTests
//
//  The Selection tool's shakedown, asserted pixel by pixel (2026-10-31). Michael asked for
//  all four shapes at once and a shakedown before he tests: "can you do a shake down?"
//  Each shape must clear EXACTLY the pixels inside the ants and leave every other pixel
//  as it was, on a plain layer and on a moved/scaled one.
//

import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import Image_Producer

@MainActor
struct SelectionToolTests {

    // MARK: Helpers

    /// A solid opaque red w×h picture.
    private func redImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// RGBA of pixel (x, y), y measured from the TOP.
    private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return (buf[i], buf[i + 1], buf[i + 2], buf[i + 3])
    }

    private func isCleared(_ img: CGImage, _ x: Int, _ y: Int) -> Bool { pixel(img, x, y).a == 0 }
    private func isUntouchedRed(_ img: CGImage, _ x: Int, _ y: Int) -> Bool {
        let p = pixel(img, x, y); return p.a == 255 && p.r == 255 && p.g == 0 && p.b == 0
    }

    private let fill = LayerTransform()            // full-canvas placement
    private let canvas100 = CGSize(width: 100, height: 100)

    // MARK: Rectangle

    @Test func rectangleClearsInsideOnly() throws {
        let sel = SelectionGeometry.dragged(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.5, y: 0.5), shape: .rectangle)
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas100, transform: fill))
        #expect(isCleared(out, 30, 30))
        #expect(isCleared(out, 21, 21))
        #expect(isCleared(out, 48, 48))
        #expect(isUntouchedRed(out, 10, 10))
        #expect(isUntouchedRed(out, 60, 60))
        #expect(isUntouchedRed(out, 30, 80))   // below, same column: y is not flipped
        #expect(isUntouchedRed(out, 80, 30))
    }

    /// A drag that runs up and to the left selects the same box as one that runs down-right.
    @Test func rectangleDragDirectionDoesNotMatter() {
        let a = SelectionGeometry.dragged(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.2, y: 0.2), shape: .rectangle)
        let b = SelectionGeometry.dragged(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.5, y: 0.5), shape: .rectangle)
        #expect(a.bounds == b.bounds)
    }

    /// Dragging off the canvas stops at the edge.
    @Test func rectangleClampsToCanvas() {
        let s = SelectionGeometry.dragged(from: CGPoint(x: 0.8, y: 0.8), to: CGPoint(x: 1.4, y: -0.3), shape: .rectangle)
        #expect(s.bounds.minX >= 0 && s.bounds.maxX <= 1 && s.bounds.minY >= 0 && s.bounds.maxY <= 1)
    }

    // MARK: Oval

    @Test func ovalClearsTheEllipseNotItsCorners() throws {
        let sel = SelectionGeometry.dragged(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.9, y: 0.9), shape: .oval)
        #expect(sel.form == .oval)
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas100, transform: fill))
        #expect(isCleared(out, 50, 50))     // center
        #expect(isCleared(out, 50, 15))     // near the top of the ellipse
        #expect(isUntouchedRed(out, 13, 13))  // inside the box, outside the ellipse
        #expect(isUntouchedRed(out, 87, 87))
        #expect(isUntouchedRed(out, 5, 50))   // outside the box
    }

    // MARK: Freehand / Path (both become an outline)

    @Test func outlineClearsATriangle() throws {
        let tri = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.1, y: 0.9)]
        let sel = try #require(SelectionGeometry.outline(tri, label: "Path"))
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas100, transform: fill))
        #expect(isCleared(out, 20, 20))
        #expect(isCleared(out, 15, 70))
        #expect(isUntouchedRed(out, 80, 80))   // the other half of the box
        #expect(isUntouchedRed(out, 60, 60))
    }

    @Test func freehandStrokeWithManyPointsClearsItsInside() throws {
        // A rough circle of 40 points, like a hand-drawn loop.
        let pts = (0..<40).map { k -> CGPoint in
            let a = Double(k) / 40 * 2 * .pi
            return CGPoint(x: 0.5 + 0.3 * cos(a), y: 0.5 + 0.3 * sin(a))
        }
        let sel = try #require(SelectionGeometry.outline(pts, label: "Freehand"))
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas100, transform: fill))
        #expect(isCleared(out, 50, 50))
        #expect(isCleared(out, 70, 50))
        #expect(isUntouchedRed(out, 50, 90))
        #expect(isUntouchedRed(out, 22, 22))
    }

    @Test func tooFewPointsMakeNoSelection() {
        #expect(SelectionGeometry.outline([], label: "Path") == nil)
        #expect(SelectionGeometry.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)], label: "Path") == nil)
        // three points on one spot (a click, not a drag)
        #expect(SelectionGeometry.outline(Array(repeating: CGPoint(x: 0.3, y: 0.3), count: 5), label: "Freehand") == nil)
    }

    // MARK: A moved / scaled layer

    /// Picture 100×100 drawn at half size in the top-left quarter of a 200×200 canvas. A
    /// selection over canvas pixels 0…50 must clear picture pixels 0…50 (its top-left half).
    @Test func clearFollowsTheLayersPlacement() throws {
        var t = LayerTransform()
        t.center = CGPoint(x: 0.25, y: 0.25)
        t.scale = 0.5
        let canvas = CGSize(width: 200, height: 200)
        let sel = SelectionGeometry.dragged(from: .zero, to: CGPoint(x: 0.25, y: 0.25), shape: .rectangle)
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas, transform: t))
        #expect(isCleared(out, 20, 20))
        #expect(isCleared(out, 45, 45))
        #expect(isUntouchedRed(out, 75, 75))
        #expect(isUntouchedRed(out, 75, 20))
        #expect(isUntouchedRed(out, 20, 75))
    }

    /// Rotated 90°: canvas-left becomes picture-bottom. Guards the rotation sign.
    @Test func clearFollowsRotation() throws {
        var t = LayerTransform()
        t.rotationDegrees = 90
        let sel = SelectionGeometry.dragged(from: .zero, to: CGPoint(x: 0.3, y: 1), shape: .rectangle)  // left 30% of canvas
        let out = try #require(SelectionGeometry.clearing(redImage(100, 100), inside: sel, canvas: canvas100, transform: t))
        // Clockwise 90°: the picture's BOTTOM edge ends up on the canvas's LEFT.
        #expect(isCleared(out, 50, 90))
        #expect(isUntouchedRed(out, 50, 10))
    }

    // MARK: Editing the selection keeps its shape

    @Test func movingAndResizingKeepTheShape() throws {
        let oval = SelectionGeometry.dragged(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.4, y: 0.4), shape: .oval)
        #expect(oval.moved(by: CGSize(width: 0.1, height: 0.1)).form == .oval)
        #expect(oval.resizingRectangle(2, to: CGPoint(x: 0.7, y: 0.6)).form == .oval)
        #expect(oval.movingCornerFreely(1, to: CGPoint(x: 0.5, y: 0.1)).form == .oval)
        let path = try #require(SelectionGeometry.outline([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.3, y: 0.4)], label: "Path"))
        if case .path = path.moved(by: CGSize(width: 0.2, height: 0)).form {} else { Issue.record("Path selection lost its shape when moved") }
    }

    // MARK: End to end on a document

    private func pngData(_ img: CGImage) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func image(of layer: ImageLayer) -> CGImage? {
        for el in layer.elements {
            if case .image(let img) = el.content,
               let src = CGImageSourceCreateWithData(img.pngData as CFData, nil) {
                return CGImageSourceCreateImageAtIndex(src, 0, nil)
            }
        }
        return nil
    }

    @Test func deleteIsNonDestructiveAndRepeatsEditTheSameLayer() throws {
        var art = ImageLayer(name: "Art", role: .content)
        art.setImage(pngData(redImage(100, 100)))
        let doc = ImageDocument(layers: [
            ImageLayer(name: "Light", role: .background(.light, fillHex: "#FFFFFF")),
            art,
        ])
        doc.canvasWidth = 100
        doc.canvasHeight = 100
        let artID = try #require(doc.layers.last?.id)

        doc.selection = SelectionGeometry.dragged(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.3, y: 0.3), shape: .rectangle)
        let first = try #require(doc.clearInsideSelection(activeLayerID: artID))
        #expect(first != artID)
        #expect(doc.layers.count == 3)
        let original = try #require(doc.layers.first(where: { $0.id == artID }))
        #expect(original.isVisible == false)                       // kept, hidden
        let origImg = try #require(image(of: original))
        #expect(isUntouchedRed(origImg, 20, 20))                   // original pixels untouched
        let cleared = try #require(doc.layers.first(where: { $0.id == first }))
        #expect(cleared.name.contains("cleared"))
        let c1 = try #require(image(of: cleared))
        #expect(isCleared(c1, 20, 20))
        #expect(isUntouchedRed(c1, 50, 50))

        // A second Delete, elsewhere, edits the same "(cleared)" layer.
        doc.selection = SelectionGeometry.dragged(from: CGPoint(x: 0.6, y: 0.6), to: CGPoint(x: 0.8, y: 0.8), shape: .oval)
        let second = try #require(doc.clearInsideSelection(activeLayerID: first))
        #expect(second == first)
        #expect(doc.layers.count == 3)
        let clearedAgain = try #require(doc.layers.first(where: { $0.id == first }))
        let c2 = try #require(image(of: clearedAgain))
        #expect(isCleared(c2, 20, 20))
        #expect(isCleared(c2, 70, 70))
        #expect(isUntouchedRed(c2, 50, 50))
    }

    @Test func deleteRefusesBackgroundsAndNoSelection() throws {
        let doc = ImageDocument(layers: [ImageLayer(name: "Light", role: .background(.light, fillHex: "#FFFFFF"))])
        let light = try #require(doc.layers.first?.id)
        #expect(doc.clearInsideSelection(activeLayerID: light) == nil)   // nothing selected
        doc.selection = SelectionGeometry.dragged(from: .zero, to: CGPoint(x: 0.5, y: 0.5), shape: .rectangle)
        #expect(doc.clearInsideSelection(activeLayerID: light) == nil)   // a solid floor
        #expect(doc.layers.count == 1)
    }

    @Test func closingAPathNeedsThreePoints() {
        let doc = ImageDocument(layers: [])
        doc.selectionPathPoints = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.1)]
        doc.closeSelectionPath()
        #expect(doc.selection == nil)
        doc.selectionPathPoints.append(CGPoint(x: 0.2, y: 0.5))
        doc.closeSelectionPath()
        #expect(doc.selection != nil)
        #expect(doc.selectionPathPoints.isEmpty)
    }

    // MARK: Copy

    /// What ⌘C puts on the clipboard is the selection's box, clipped to its shape.
    @Test func copyIsTheSelectionsBoxClippedToItsShape() throws {
        let sel = SelectionGeometry.dragged(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.6, y: 0.6), shape: .oval)
        let cut = try #require(sel.clip(redImage(100, 100)))
        #expect(cut.width == 40 && cut.height == 40)
        #expect(pixel(cut, 20, 20).a == 255)   // center of the oval: copied
        #expect(pixel(cut, 1, 1).a == 0)       // corner of the box: outside the oval, empty
    }
}
