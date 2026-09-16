//
//  HistoryOptimizeTests.swift
//  Image ProducerTests
//
//  2026-09-16. Phototizer.picprod reached 628 MB: 654 MB of history holding 12 MB of
//  distinct images. These pin the three promises of the fix — duplicates collapse, old
//  inline files still restore, and Optimize keeps every step exactly.
//

import Testing
import Foundation
@testable import Image_Producer

@MainActor
struct HistoryOptimizeTests {

    private func png(_ seed: UInt8, bytes: Int = 50_000) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: Int($0) &+ Int(seed)) })
    }

    private func document(steps: Int) -> ImageDocument {
        var layer = ImageLayer(name: "Photo", role: .content)
        layer.setImage(png(1))
        let doc = ImageDocument(layers: [layer])
        doc.captureHistoryBaselineIfNeeded()
        for i in 0..<steps {
            doc.layers[0].name = "Photo \(i)"                 // a change that is not pixels
            doc.recordHistory(toolID: "move", groupTitle: "Move", actionLabel: "Nudge \(i)", layerID: nil)
        }
        return doc
    }

    @Test func repeatedPixelsAreStoredOnce() {
        let doc = document(steps: 20)
        #expect(doc.history.blobs?.count == 1)
        // 21 snapshots of a 50 KB image would be over 1 MB inline.
        #expect(doc.historyByteCount < 200_000)
    }

    @Test func legacyInlineSnapshotsStillRestore() throws {
        var layer = ImageLayer(name: "Old", role: .content)
        layer.setImage(png(7))
        let inline = try JSONEncoder().encode(DocumentSnapshot(layers: [layer]))   // pre-2026-09-16 shape
        let doc = ImageDocument(layers: [])
        doc.history.entries = [HistoryEntry(toolID: "fill", title: "Fill",
                                            actions: [HistoryAction(label: "Fill", snapshot: inline)])]
        doc.jump(toEntry: 0, action: 0)
        #expect(doc.layers.first?.name == "Old")
        guard case .image(let restored)? = doc.layers.first?.elements.first?.content else {
            Issue.record("restored layer has no image"); return
        }
        #expect(restored.pngData == png(7))
    }

    @Test func optimizeIsLosslessAndShrinks() async throws {
        // Build a legacy-shaped history: every step carries its own inline copy.
        var layer = ImageLayer(name: "Photo", role: .content)
        layer.setImage(png(3))
        let doc = ImageDocument(layers: [layer])
        var actions: [HistoryAction] = []
        for i in 0..<15 {
            layer.name = "Photo \(i)"
            actions.append(HistoryAction(label: "Step \(i)",
                                         snapshot: try JSONEncoder().encode(DocumentSnapshot(layers: [layer]))))
        }
        doc.history.entries = [HistoryEntry(toolID: "move", title: "Move", actions: actions)]
        let sortedPlain = JSONEncoder(); sortedPlain.outputFormatting = [.sortedKeys]
        let expected = try actions.map {
            try sortedPlain.encode(JSONDecoder().decode(DocumentSnapshot.self, from: $0.snapshot!))
        }

        let result = try #require(await doc.optimizeHistory())
        #expect(result.steps == 15)
        #expect(result.after < result.before / 5)
        #expect(doc.history.blobs?.count == 1)

        for (i, action) in doc.history.entries[0].actions.enumerated() {
            let snap = try BlobCoding.decoder(BlobStore(doc.history.blobs ?? [:]))
                .decode(DocumentSnapshot.self, from: action.snapshot!)
            #expect(try sortedPlain.encode(snap) == expected[i])
        }
    }

    @Test func purgeDropsTheBlobs() {
        let doc = document(steps: 3)
        doc.purgeHistory()
        #expect(doc.history.blobs == nil)
    }
}
