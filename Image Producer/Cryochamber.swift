//
//  Cryochamber.swift
//  Image Producer
//
//  Recovery that lives INSIDE the app. Built 2026-09-16 from his design of 2026-09-15
//  (full reasoning in ImageProducer_DeveloperNotes.swift, "THE CRYOCHAMBER").
//
//  ⛔ WHY IT EXISTS: offered Time Machine to get a document back, he refused it —
//  "not time machine because that is a lazy work around" — and named the principle:
//  ⭐ "remember this mantra, One Stop Shop."
//
//  TWO POINTS, HIS NAMES AND HIS SEMANTICS:
//    • Revert to Open       — the document as it was when this session opened it.
//    • Revert to Last Save  — "revert to last save reverts to the last command s per
//                              opened session." NEVER an autosave. Absent until ⌘S.
//      ⭐ "it is a concious marker for save points the user knows once existed"
//
//  THE SESSION IS THE UNIT. Both points are discarded when the app quits.
//
//  COST: the Open point is an APFS clone (FileManager copies clone on APFS), so it costs
//  nothing when taken and only grows as the live file diverges. The Last Save point is
//  the ⌘S bytes themselves, which the save already had in hand.
//

import Foundation

nonisolated final class Cryochamber: @unchecked Sendable {

    enum Point: String { case open, lastSave }

    /// Where every session's chambers live. Inside the app's own temporary directory, so
    /// nothing here is ever written next to the user's document.
    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Cryochamber", isDirectory: true)

    /// This process's folder. A chamber from a crashed session is swept at next launch.
    static var sessionDirectory: URL {
        root.appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)
    }

    private let directory = Cryochamber.sessionDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    private let lock = NSLock()
    private var frozen: Set<Point> = []

    func has(_ point: Point) -> Bool { lock.withLock { frozen.contains(point) } }

    private func url(_ point: Point) -> URL {
        directory.appendingPathComponent(point.rawValue, isDirectory: true)
    }

    /// Freeze the package as it sits on disk right now. Runs on `PackageWriter`'s queue:
    /// that keeps the coordinated read off the main thread (the 2026-08-21 deadlock) AND
    /// guarantees it lands before any autosave the session enqueues after it.
    func freezeOpen(from fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        PackageWriter.run { [self] in
            let fm = FileManager.default
            let dest = url(.open)
            var ok = false
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordError) { src in
                do {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: src, to: dest)
                    ok = true
                } catch {
                    NSLog("Cryochamber: could not freeze Open — %@", String(describing: error))
                }
            }
            if ok { lock.withLock { _ = frozen.insert(.open) } }
            completion(ok)
        }
    }

    /// Freeze the bytes a ⌘S just produced. Replaces the previous Last Save — it is the
    /// LAST ⌘S, one point, by his definition.
    @discardableResult
    func freezeLastSave(manifest data: Data) -> Bool {
        let fm = FileManager.default
        let dest = url(.lastSave)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try data.write(to: dest.appendingPathComponent("manifest.json"), options: .atomic)
            lock.withLock { _ = frozen.insert(.lastSave) }
            return true
        } catch {
            NSLog("Cryochamber: could not freeze Last Save — %@", String(describing: error))
            return false
        }
    }

    /// The frozen manifest, decoded. `nil` if the point was never taken or cannot be read.
    func thaw(_ point: Point) throws -> ImageProjectManifest? {
        guard has(point) else { return nil }
        let data = try Data(contentsOf: url(point).appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(ImageProjectManifest.self, from: data)
    }

    // MARK: Session lifetime

    /// On quit: this session's points go, as he specified.
    static func discardSession() {
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    /// On launch: remove chambers left by sessions that did not quit cleanly. A folder
    /// named for a process that is still running is left alone.
    static func sweepAbandoned() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for dir in dirs {
            guard let pid = Int32(dir.lastPathComponent), pid != me else { continue }
            if kill(pid, 0) != 0 { try? fm.removeItem(at: dir) }
        }
    }
}

extension ImageDocument {
    /// Replace the live document with a frozen point — layers, history, canvas, palette,
    /// crop, resolution and print setup, exactly as they were frozen. Autosave writes the
    /// result to the file on its own. Returns false and changes nothing if the point
    /// cannot be read.
    func revert(to point: Cryochamber.Point) -> Bool {
        let manifest: ImageProjectManifest
        do {
            guard let m = try cryochamber.thaw(point) else { return false }
            manifest = m
        } catch {
            say("Could not read the frozen copy — nothing was changed", kind: .warning)
            return false
        }
        name = manifest.name
        canvasWidth = manifest.canvasWidth ?? manifest.canvasSize ?? canvasWidth
        canvasHeight = manifest.canvasHeight ?? manifest.canvasSize ?? canvasHeight
        layers = manifest.layers
        if let p = manifest.palette { palette = p }
        cropMask = manifest.cropMask ?? manifest.cropRect.map { CropMask(rect: $0) }
        ppi = manifest.ppi ?? 72
        if let v = manifest.bleedInches { bleedInches = v }
        if let v = manifest.safeMarginInches { safeMarginInches = v }
        if let v = manifest.cropMarks { cropMarks = v }
        if let v = manifest.registrationMarks { registrationMarks = v }
        if let v = manifest.colorSpaceCMYK { colorSpaceCMYK = v }
        history = manifest.history ?? ImageHistory()
        historyCursor = .latest
        say(point == .open ? "Reverted to Open" : "Reverted to Last Save", kind: .info)
        return true
    }
}
