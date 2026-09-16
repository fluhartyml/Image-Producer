//
//  DocumentWindow.swift
//  Image Producer
//
//  State that belongs to the WINDOW, not the document — because the document does not
//  survive. The autosave's coordinated write makes DocumentGroup reload the document about
//  two seconds after every change, and a reload builds a fresh `ImageDocument`, wiping
//  anything held only in memory. (Same lesson `CameraState` paid for.)
//
//  2026-09-16, two things broke on exactly that:
//   • Optimize History finished — 658 MB -> 19 MB — and the status bar read "Ready". The
//     result line had been posted to the instance that the reload threw away.
//   • The cryochamber's frozen points lived on the document, so Revert to Open and Revert
//     to Last Save were forgotten at the first autosave.
//
//  And a third reason, the one that makes the status bar usable at all: a status line kept
//  as a @Published property of the document fires `objectWillChange`, which schedules an
//  autosave. So narrating a save would itself cause a save. Held here, it never does.
//
//  ⭐ Michael, 2026-09-16: "the status bar should tell the user everything that is going on
//  behind the scenes." Posting here is how that stays cheap.
//

import SwiftUI
import Combine

final class DocumentWindow: ObservableObject {
    @Published var status: ImageDocument.StatusNote?
    @Published var hasFrozenOpen = false
    @Published var hasFrozenLastSave = false

    let chamber = Cryochamber()

    /// The document this window is showing NOW. Replaced on every reload.
    weak var document: ImageDocument?

    nonisolated(unsafe) private static var links: [ObjectIdentifier: DocumentWindow] = [:]
    nonisolated private static let lock = NSLock()

    /// Point `doc` at this window. Called when the window appears and again every time the
    /// reload hands it a new document instance.
    func attach(_ doc: ImageDocument) {
        document = doc
        Self.lock.withLock { Self.links[ObjectIdentifier(doc)] = self }
    }

    /// The window a document belongs to — including an instance a reload has already
    /// replaced, so a long job that started on it can still report and find the live one.
    nonisolated static func window(for doc: ImageDocument) -> DocumentWindow? {
        lock.withLock { links[ObjectIdentifier(doc)] }
    }

    func post(_ note: ImageDocument.StatusNote) { status = note }
}
