//
//  CLIRunner.swift
//  Image Producer
//
//  REM: COMMAND MODE — roadmap C (017–020), "Claude drives Image Producer". His rule: when he
//  says API for his app he means a CLI MODE — one CLIRunner.swift, runIfRequested() from the
//  App's init(). 008 (his word, my call as the engineer) set the first steps: new or open
//  project, add image layer, remove background, magic eraser, merge, Image Playground, export
//  PNG. C1 (017) is the basic loop: a job file lists the steps, the app runs them with its OWN
//  tool code (the same functions the panels call), and hands back the picture plus a project
//  file he can open and adjust.
//
//  Run (Mac only):
//    "Image Producer.app/Contents/MacOS/Image Producer" --command job.json
//  The app is sandboxed, so every path in a job is RELATIVE to the job folder:
//    • the JOB FOLDER the person chose once in Image Producer ▸ Settings… (suggested
//      ~/Image Producer Jobs), kept as a security-scoped bookmark — or, until one is chosen,
//    • the app's own Command folder inside its container:
//      ~/Library/Containers/com.nightgard.Image-Producer/Data/Documents/Command/
//  Put input pictures there; results land there. Absolute paths are refused, not guessed.
//
//  REM 2026-11-24 — BOT DRIVING 002 (his lock: "the app stays sandboxed (App Store). Michael
//  picks the job folder once (bookmark, same as Save to Desktop), suggested ~/Image Producer
//  Jobs in the home folder, not under Documents, which macOS privacy guards from shell tools").
//  Why: a shell tool could not even list the container folder ("Operation not permitted").
//  The bookmark is the DesktopAccess.swift pattern; command mode can't show a panel (no
//  window, ever), so the choosing happens in Settings and the CLI only resolves it.
//
//  Job file:
//    { "name": "Two cats", "width": 1024, "height": 1024,
//      "steps": [ { "do": "addImage", "file": "cat.png" },
//                 { "do": "removeBackground" },
//                 { "do": "magicErase", "color": "#FFFFFF", "tolerance": 24 },
//                 { "do": "merge" },
//                 { "do": "exportPNG", "file": "out.png" },
//                 { "do": "saveProject", "file": "out.imgprd" } ] }
//  Each step acts on the TOP visible content layer (the one just added or made).
//  "open" (a project file) may replace the first step to start from saved work.
//
//  ⚠️ IMAGE PLAYGROUND CANNOT RUN HERE, and the step says so instead of pretending.
//  Apple's only hands-off generator (ImageCreator) is deprecated in OS 27 ("Use
//  ImagePlaygroundViewController or imagePlaygroundSheet") and refuses to run with the app in
//  the background (ImageCreator.Error.backgroundCreationForbidden) — which is exactly what a
//  command run is. The sheet needs a person to pick the picture. So "imagePlayground" stops the
//  job after saving what is done so far, and names the project to open for that step.
//
//  Output: one line per step on stdout ("ok 2 removeBackground — …" / "FAIL …"). Exit codes
//  (005): 0 every step ran or --help, 1 at the first failed step (the steps before it are kept
//  and saved), 2 usage error (missing/unreadable job file, bad path, unknown --flag). The same
//  results go into <job name>.status.json in the job folder, written last (003).
//

#if os(macOS)
import Foundation
import AppKit

enum CommandMode {
    static let flag = "--command"

    /// The folder every job path is relative to: the chosen job folder (002), else the app's
    /// Command folder inside its sandbox container. Resolved once per run; the security scope
    /// stays open until the process exits.
    static let folder: URL = {
        if let chosen = JobFolder.resolve(), chosen.startAccessingSecurityScopedResource() {
            return chosen
        }
        return containerFolder
    }()

    /// The app's own Command folder inside its sandbox container (before a job folder is chosen).
    static var containerFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Command", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One line naming where jobs are read from — and, when no folder is chosen, how to choose.
    static var folderLine: String {
        if folder == containerFolder {
            return "job folder: \(folder.path) — to use a folder shell tools can reach, choose one in Image Producer ▸ Settings… ▸ Job Folder (suggested \(JobFolder.suggested.path))"
        }
        return "job folder: \(folder.path)"
    }

    // REM 2026-11-24 — BOT DRIVING 004 + 005 (his locks). 004: "--help" prints usage and exits
    // without a window; "only unknown double-dash flags (--anything) print usage and exit without
    // a window; single-dash arguments from Xcode, macOS and the UI tests (-ImageProducerUITest)
    // still open the app as today." Why: a bot must never open a window by accident with a typo.
    // 005: stable exit codes a bot branches on — 0 every step ran (or --help), 1 a job step
    // failed (work before it saved), 2 usage error (missing job file, bad path, unknown flag).
    // An unreadable job file is also 2: nothing ran, so nothing was kept — it is bad input.
    static let helpFlag = "--help"
    static let exitOK: Int32 = 0, exitStepFailed: Int32 = 1, exitUsage: Int32 = 2

    static var usage: String {
        """
        Image Producer command mode — runs a job with no window.

        usage:
          "Image Producer" --command <job.json>   run a job file from the job folder
          "Image Producer" --help                 print this and exit

        \(folderLine)
        Every path in a job is a plain name inside the job folder (no /, ~ or ..).

        job file: { "name": "…", "width": 1024, "height": 1024, "steps": [ … ] }
        steps (each acts on the top visible picture layer):
          open              file   — an .imgprd project to start from
          addImage          file   — a picture on its own layer (the first sets the canvas)
          removeBackground         — keep the subject, original hidden below
          magicErase        color ("#RRGGBB", default #FFFFFF), tolerance (default 24)
          merge                    — merge every visible picture layer into one
          exportPNG         file   — write the canvas as a PNG
          saveProject       file   — write an .imgprd project to open and adjust
          imagePlayground   prompt — needs a person: saves the project and stops

        output: one "ok" or "FAIL" line per step, then <job name>.status.json in the job
        folder, written last (exit code, each step, every file written).

        exit codes:
          0  every step ran, or --help printed
          1  a job step failed (the steps before it are kept and saved)
          2  usage error: missing job file, bad path, unreadable job, unknown flag
        """
    }

    /// Called first thing from Image_ProducerApp.init(). Returns only when no job was asked for.
    @MainActor static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains(helpFlag) { finish(exitOK, usage) }
        if let i = args.firstIndex(of: flag) {
            guard i + 1 < args.count else {
                finish(exitUsage, "FAIL usage: --command <job.json>\n\(folderLine)\n(--help lists the steps and exit codes)")
            }
            finish(run(jobName: args[i + 1]), nil)
        }
        // Unknown double-dash flag: never fall through to a window (004). Single-dash
        // arguments (Xcode, macOS, UI tests) still open the app.
        if let unknown = args.first(where: { $0.hasPrefix("--") }) {
            finish(exitUsage, "FAIL unknown flag \(unknown)\n\n\(usage)")
        }
    }

    private static func finish(_ code: Int32, _ line: String?) -> Never {
        if let line { print(line) }
        fflush(stdout)
        exit(code)
    }

    // MARK: Job

    struct Job: Decodable {
        var name: String?
        var width: Int?
        var height: Int?
        var steps: [Step]
    }

    struct Step: Decodable {
        var `do`: String
        var file: String?
        var color: String?
        var tolerance: Int?
        var prompt: String?
    }

    enum Problem: Error, CustomStringConvertible {
        case say(String)
        var description: String { if case .say(let s) = self { return s }; return "" }
    }

    /// A path inside the Command folder; absolute paths and ".." are refused.
    static func inside(_ name: String) throws -> URL {
        guard !name.hasPrefix("/"), !name.hasPrefix("~"), !name.split(separator: "/").contains("..") else {
            throw Problem.say("\"\(name)\" must be a plain name inside \(folder.path)")
        }
        return folder.appendingPathComponent(name)
    }

    @MainActor static func run(jobName: String) -> Int32 {
        written = []
        // The status file is named after the job file until the job's own name is known.
        var status = Status(job: (jobName as NSString).deletingPathExtension, jobFile: jobName)
        let doc: ImageDocument
        let job: Job
        do {
            let data = try Data(contentsOf: try inside(jobName))
            job = try JSONDecoder().decode(Job.self, from: data)
            doc = ImageDocument(name: job.name ?? "Command", canvasWidth: job.width ?? 1024,
                                canvasHeight: job.height ?? 1024)
        } catch {
            // Plain words, not a Cocoa error dump: a bot (or a person) reads this line.
            let why: String
            if (error as? CocoaError)?.code == .fileReadNoSuchFile {
                why = "\(jobName) is not in the job folder"
            } else if error is DecodingError {
                why = "\(jobName) is not a readable job file (\(error))"
            } else {
                why = "\(error)"
            }
            print("FAIL job — \(why)")
            print(folderLine)
            status.problem = why
            return finishStatus(&status, code: exitUsage)
        }
        if let name = job.name, !name.isEmpty { status.job = name }
        var saved = false
        for (n, step) in job.steps.enumerated() {
            do {
                let note = try perform(step, on: doc, saved: &saved)
                print("ok \(n + 1) \(step.do) — \(note)")
                status.steps.append(.init(step: n + 1, do: step.do, result: "ok", note: note))
            } catch {
                print("FAIL \(n + 1) \(step.do) — \(error)")
                status.steps.append(.init(step: n + 1, do: step.do, result: "FAIL", note: "\(error)"))
                if !saved, let auto = try? save(doc, as: "\(job.name ?? "Command") (unfinished).imgprd") {
                    print("kept the steps before it in \(auto.lastPathComponent)")
                    status.kept = auto.lastPathComponent
                }
                return finishStatus(&status, code: exitStepFailed)
            }
        }
        return finishStatus(&status, code: exitOK)
    }

    // MARK: Status file (bot driving 003)

    // REM 2026-11-24 — BOT DRIVING 003 (his lock: "the status file is JSON, named after the job
    // (<job name>.status.json) so runs never overwrite each other, and written last in one
    // atomic step so a polling bot never reads half a file"). Why: a bot polls the folder, not
    // the terminal. It mirrors stdout: one entry per step, ok or FAIL, the exit code, every file
    // the job wrote, and the "unfinished" project kept after a failure. Written LAST — so when it
    // appears, everything it names is already on disk.

    /// Every file this run wrote into the job folder, in order (exportPNG, saveProject, …).
    @MainActor static var written: [String] = []

    struct Status: Encodable {
        struct StepResult: Encodable {
            var step: Int
            var `do`: String
            var result: String
            var note: String
        }
        var job: String
        var jobFile: String
        var exitCode: Int32 = 0
        var ok = false
        var steps: [StepResult] = []
        var outputs: [String] = []
        var kept: String?
        var problem: String?
        var finished = ""
    }

    /// Fill in the end of the run, write <job>.status.json atomically, and return the exit code.
    @MainActor static func finishStatus(_ status: inout Status, code: Int32) -> Int32 {
        status.exitCode = code
        status.ok = code == 0
        status.outputs = written
        status.finished = ISO8601DateFormatter().string(from: Date())
        let name = status.job.replacingOccurrences(of: "/", with: "-") + ".status.json"
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try enc.encode(status).write(to: folder.appendingPathComponent(name), options: .atomic)
            print("status \(name)")
        } catch {
            print("FAIL status \(name): \(error)")
        }
        return code
    }

    // MARK: Steps — each calls the app's own tool code

    /// Index of the top visible content layer — the one the last step made.
    @MainActor static func topContent(_ doc: ImageDocument) -> Int? {
        doc.layers.indices.last { doc.layers[$0].isVisible && isContent(doc.layers[$0]) }
    }

    @MainActor static func isContent(_ l: ImageLayer) -> Bool {
        if case .content = l.role { return true }
        return false
    }

    @MainActor static func picture(of layer: ImageLayer) -> Data? {
        for el in layer.elements {
            if case .image(let img) = el.content, !img.pngData.isEmpty { return img.pngData }
        }
        return layer.pixelData
    }

    @MainActor static func perform(_ s: Step, on doc: ImageDocument, saved: inout Bool) throws -> String {
        switch s.do {
        case "open":
            guard let f = s.file else { throw Problem.say("needs \"file\"") }
            let dir = try FileWrapper(url: try inside(f))
            guard let m = dir.fileWrappers?["manifest.json"]?.regularFileContents else {
                throw Problem.say("\(f) is not an Image Producer project")
            }
            doc.load(try JSONDecoder().decode(ImageProjectManifest.self, from: m))
            return "\(doc.layers.count) layers, \(doc.canvasWidth) by \(doc.canvasHeight)"

        case "addImage":
            guard let f = s.file else { throw Problem.say("needs \"file\"") }
            let url = try inside(f)
            let isFirst = !doc.layers.contains { isContent($0) && $0.isVisible && picture(of: $0) != nil }
            if isFirst {
                // The first picture sets the canvas, exactly like Import Image.
                guard importImageAsLayer(url, into: doc) else { throw Problem.say("could not read \(f)") }
            } else {
                guard let raw = try? Data(contentsOf: url),
                      let src = CGImageSourceCreateWithData(raw as CFData, nil),
                      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
                      let png = pngData(from: cg) else { throw Problem.say("could not read \(f)") }
                var layer = ImageLayer(name: url.deletingPathExtension().lastPathComponent, role: .content)
                layer.setImage(png)
                let aspect = Double(cg.width) / Double(cg.height)
                layer.transform.contentAspect = aspect
                layer.transform.scale = canvasFitScale(aspect: aspect, canvasWidth: doc.canvasWidth,
                                                       canvasHeight: doc.canvasHeight)
                doc.captureHistoryBaselineIfNeeded()
                doc.layers.append(layer)
                doc.recordHistory(toolID: Tool.image.rawValue, groupTitle: Tool.image.title,
                                  actionLabel: "Import Image", layerID: layer.id)
            }
            return "\(f) on its own layer, canvas \(doc.canvasWidth) by \(doc.canvasHeight)"

        case "removeBackground":
            guard let i = topContent(doc), let png = picture(of: doc.layers[i]) else {
                throw Problem.say("no picture layer to work on")
            }
            let out = try SubjectCutout.lift(imageData: png)
            doc.captureHistoryBaselineIfNeeded()
            let id = doc.addResultLayer(out, above: i, nameSuffix: "cutout")
            doc.recordHistory(toolID: Tool.cutout.rawValue, groupTitle: Tool.cutout.title,
                              actionLabel: "Remove Background", layerID: id ?? doc.layers[i].id)
            return "subject kept, original hidden below"

        case "magicErase":
            guard let i = topContent(doc), let png = picture(of: doc.layers[i]) else {
                throw Problem.say("no picture layer to work on")
            }
            let hex = s.color ?? "#FFFFFF"
            let tol = s.tolerance ?? 24
            guard let cg = GreenKeyCache.keyed(png, colorHex: hex, tolerance: tol),
                  let out = pngData(from: cg) else { throw Problem.say("could not erase \(hex)") }
            doc.captureHistoryBaselineIfNeeded()
            let id = doc.addResultLayer(out, above: i, nameSuffix: "erased")
            doc.recordHistory(toolID: Tool.magicLasso.rawValue, groupTitle: Tool.magicLasso.title,
                              actionLabel: "Magic Erase", layerID: id ?? doc.layers[i].id)
            return "cleared \(hex) within \(tol)"

        case "merge":
            let ids = Set(doc.layers.filter { isContent($0) && $0.isVisible }.map(\.id))
            if let why = mergeLayers(ids, in: doc) { throw Problem.say(why) }
            return "\(ids.count) visible layers merged into one"

        case "exportPNG":
            guard let f = s.file else { throw Problem.say("needs \"file\"") }
            guard let png = makeCanvasPNG(doc) else { throw Problem.say("could not render the picture") }
            try png.write(to: try inside(f), options: .atomic)
            written.append(f)
            return "\(f), \(ByteCountFormatter.string(fromByteCount: Int64(png.count), countStyle: .file))"

        case "saveProject":
            guard let f = s.file else { throw Problem.say("needs \"file\"") }
            let url = try save(doc, as: f)
            saved = true
            return "\(url.lastPathComponent) — open it in Image Producer to adjust"

        case "imagePlayground":
            let url = try save(doc, as: "\(doc.name) (for Image Playground).imgprd")
            saved = true
            throw Problem.say("Image Playground needs a person: Apple's generator will not run with the app in the background, and is deprecated in OS 27. Saved \(url.lastPathComponent) — open it and use the Image Playground tool (A).")

        default:
            throw Problem.say("unknown step \"\(s.do)\" — steps: open, addImage, removeBackground, magicErase, merge, exportPNG, saveProject, imagePlayground")
        }
    }

    /// Write a project package (manifest + its Finder picture) into the Command folder.
    @MainActor static func save(_ doc: ImageDocument, as name: String) throws -> URL {
        let url = try inside(name.hasSuffix(".imgprd") ? name : name + ".imgprd")
        let data = try doc.encodedManifest()
        try ImageDocument.writeEncodedPackage(data, to: url)
        written.append(url.lastPathComponent)
        return url
    }
}

// MARK: - Job folder (bot driving 002)

/// The job folder the person picks once, kept as a security-scoped bookmark — the same pattern
/// as DesktopAccess. Chosen in Settings (a window); command mode only resolves it.
enum JobFolder {
    private static let bookmarkKey = "ImageProducer.commandJobFolderBookmark"

    /// The real home folder, not the sandbox container's.
    static var home: URL { DesktopAccess.realDesktop.deletingLastPathComponent() }

    /// His suggestion: in the home folder, not under Documents (privacy-guarded from shell tools).
    static var suggested: URL { home.appendingPathComponent("Image Producer Jobs", isDirectory: true) }

    /// The chosen folder, or nil if none was chosen or the grant no longer resolves.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            remember(url)
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    /// Ask once with an open panel. Starts at the suggested folder when it exists, else the
    /// home folder (New Folder is allowed). Returns the chosen folder, or nil on Cancel.
    @MainActor static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let start = FileManager.default.fileExists(atPath: suggested.path) ? suggested : home
        panel.directoryURL = start
        panel.message = "Choose the job folder for command mode. Shell tools put job files and pictures here, and results land here. Suggested: Image Producer Jobs in your home folder."
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        remember(chosen)
        return chosen
    }

    static func forget() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

    private static func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}
#endif
