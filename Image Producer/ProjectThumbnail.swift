//
//  ProjectThumbnail.swift
//  Image Producer
//
//  REM: 016 B1 PREVIEW ICON (his choice 10-05; 007 Mac + iPad). Every save tucks the project's
//  own flattened picture into the package at QuickLook/Thumbnail.png, and the Image Producer
//  Thumbnail extension hands it to Finder and Files. The picture is drawn HERE, by the same
//  renderer Export uses (renderCanvasImage), so the icon always matches the app.
//
//  Why a hand-off table: the package writers are nonisolated and see only the manifest BYTES
//  (the 08-21 autosave hang is why — see writeEncodedPackage). Rendering needs the document,
//  on the main actor. So the main actor renders at save time and files the PNG under the
//  hash of the bytes it just encoded; the writer picks it up by that same hash. Two windows
//  saving at once cannot swap pictures.
//

import Foundation
import CoreGraphics
import Synchronization

nonisolated enum ProjectThumbnail {
    static let folder = "QuickLook"
    static let file = "Thumbnail.png"
    /// Longest side of the stored picture, in pixels. Finder and Files scale it down.
    static let maxSide: CGFloat = 512

    private static let pending = Mutex<[Int: Data]>([:])

    static func stash(_ png: Data, forManifestHash h: Int) {
        pending.withLock { $0[h] = png; if $0.count > 8 { $0.removeAll() } }
    }

    static func take(forManifestHash h: Int) -> Data? {
        pending.withLock { $0.removeValue(forKey: h) }
    }

    /// The QuickLook folder wrapper, or nil when no picture was stashed for these bytes.
    static func wrapper(forManifest data: Data) -> FileWrapper? {
        guard let png = take(forManifestHash: data.hashValue) else { return nil }
        let pic = FileWrapper(regularFileWithContents: png)
        pic.preferredFilename = file
        let dir = FileWrapper(directoryWithFileWrappers: [file: pic])
        dir.preferredFilename = folder
        return dir
    }
}

extension ImageDocument {
    /// Render the small picture for the bytes about to be written (main actor).
    func stashThumbnail(forManifest data: Data) {
        let side = CGFloat(max(canvasWidth, canvasHeight, 1))
        guard let cg = renderCanvasImage(self, scale: min(1, ProjectThumbnail.maxSide / side)),
              let png = pngData(from: cg) else { return }
        ProjectThumbnail.stash(png, forManifestHash: data.hashValue)
    }
}
