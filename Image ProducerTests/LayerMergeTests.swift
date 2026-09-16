//
//  LayerMergeTests.swift
//  Image ProducerTests
//
//  The non-destructive rule is the whole feature, so it is asserted rather than trusted.
//  "it has to be non destructive so the originals stay below but the merged lay[e]rs are
//  consolidated in a new layer above" — 2026-09-15.
//
//  It matters more here than in most places: undo is OFF because UndoManager crashed this
//  app, so a destructive merge would be unrecoverable.
//

import Testing
@testable import Image_Producer

@MainActor
struct LayerMergeTests {

    /// Light + Dark floors and three content layers, bottom-first as the document stores them.
    private func makeDocument() -> ImageDocument {
        ImageDocument(layers: [
            ImageLayer(name: "Light", role: .background(.light, fillHex: "#FFFFFF")),
            ImageLayer(name: "Dark",  role: .background(.dark,  fillHex: "#000000")),
            ImageLayer(name: "Back",  role: .content),
            ImageLayer(name: "Mid",   role: .content),
            ImageLayer(name: "Front", role: .content),
        ])
    }

    private func layer(_ doc: ImageDocument, _ name: String) -> ImageLayer? {
        doc.layers.first { $0.name == name }
    }

    @Test("Merge keeps every original, switched off, and puts the result above the topmost")
    func mergeIsNonDestructive() throws {
        let doc = makeDocument()
        let before = doc.layers.count
        let backID  = try #require(layer(doc, "Back")).id
        let frontID = try #require(layer(doc, "Front")).id

        let error = mergeLayers([backID, frontID], in: doc)
        #expect(error == nil, "merge reported: \(error ?? "")")

        // Nothing was removed — one layer was ADDED.
        #expect(doc.layers.count == before + 1)

        // Both originals survive, by id, and are switched off.
        let back  = try #require(doc.layers.first { $0.id == backID },  "the Back original was destroyed")
        let front = try #require(doc.layers.first { $0.id == frontID }, "the Front original was destroyed")
        #expect(back.isVisible == false,  "Back should be switched off, not deleted")
        #expect(front.isVisible == false, "Front should be switched off, not deleted")

        // The merged layer sits directly ABOVE the topmost source.
        let merged = try #require(doc.layers.first { $0.name.contains("(Merged") }, "no merged layer")
        let mergedIdx = try #require(doc.layers.firstIndex { $0.id == merged.id })
        let frontIdx  = try #require(doc.layers.firstIndex { $0.id == frontID })
        #expect(mergedIdx == frontIdx + 1, "merged layer is at \(mergedIdx), expected \(frontIdx + 1)")
        #expect(merged.isVisible)
        #expect(merged.name == "Front (Merged)", "named after the topmost source, got \(merged.name)")

        // The untouched layer is untouched.
        #expect(try #require(layer(doc, "Mid")).isVisible, "Mid was not part of the merge")
    }

    @Test("Merge refuses the Light and Dark floors")
    func mergeRefusesFloors() throws {
        let doc = makeDocument()
        let before = doc.layers.map(\.id)
        let lightID = try #require(layer(doc, "Light")).id
        let frontID = try #require(layer(doc, "Front")).id

        let error = mergeLayers([lightID, frontID], in: doc)
        #expect(error != nil, "merging a floor should be refused")
        #expect(doc.layers.map(\.id) == before, "a refused merge must change nothing")
        #expect(try #require(layer(doc, "Front")).isVisible, "a refused merge must not hide anything")
    }

    @Test("Merge needs two layers")
    func mergeNeedsTwo() throws {
        let doc = makeDocument()
        let before = doc.layers.count
        let frontID = try #require(layer(doc, "Front")).id

        #expect(mergeLayers([frontID], in: doc) != nil)
        #expect(mergeLayers([], in: doc) != nil)
        #expect(doc.layers.count == before)
    }

    @Test("A second merge numbers rather than compounds the suffix")
    func mergeSuffixNumbers() throws {
        let doc = makeDocument()
        let backID  = try #require(layer(doc, "Back")).id
        let frontID = try #require(layer(doc, "Front")).id

        #expect(mergeLayers([backID, frontID], in: doc) == nil)
        let firstMerged = try #require(doc.layers.first { $0.name.contains("(Merged") })
        let midID = try #require(layer(doc, "Mid")).id

        #expect(mergeLayers([midID, firstMerged.id], in: doc) == nil)
        let names = doc.layers.map(\.name).filter { $0.contains("(Merged") }
        #expect(names.contains("Front (Merged)"))
        #expect(names.contains("Front (Merged 2)"),
                "expected a numbered suffix, got \(names)")
        #expect(!names.contains { $0.contains("(Merged) (Merged)") }, "suffix compounded: \(names)")
    }
}
