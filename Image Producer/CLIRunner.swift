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
//  The app is sandboxed, so every path in a job is RELATIVE to the app's own Command folder:
//    ~/Library/Containers/com.nightgard.Image-Producer/Data/Documents/Command/
//  Put input pictures there; results land there. Absolute paths are refused, not guessed.
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
//  Output: one line per step on stdout ("ok 2 removeBackground — …" / "FAIL …"), exit 0 when
//  every step ran, 1 at the first failure (the steps before it are kept and saved).
//

#if os(macOS)
import Foundation
import AppKit

enum CommandMode {
    static let flag = "--command"

    /// The app's Command folder inside its sandbox container.
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Command", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Called first thing from Image_ProducerApp.init(). Returns only when no job was asked for.
    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag) else { return }
        guard i + 1 < args.count else { finish(1, "FAIL usage: --command <job.json> (in \(folder.path))") }
        let code = run(jobName: args[i + 1])
        finish(code, nil)
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
        let doc: ImageDocument
        let job: Job
        do {
            let data = try Data(contentsOf: try inside(jobName))
            job = try JSONDecoder().decode(Job.self, from: data)
            doc = ImageDocument(name: job.name ?? "Command", canvasWidth: job.width ?? 1024,
                                canvasHeight: job.height ?? 1024)
        } catch {
            print("FAIL job \(jobName): \(error)")
            return 1
        }
        var saved = false
        for (n, step) in job.steps.enumerated() {
            do {
                let note = try perform(step, on: doc, saved: &saved)
                print("ok \(n + 1) \(step.do) — \(note)")
            } catch {
                print("FAIL \(n + 1) \(step.do) — \(error)")
                if !saved, let auto = try? save(doc, as: "\(job.name ?? "Command") (unfinished).imgprd") {
                    print("kept the steps before it in \(auto.lastPathComponent)")
                }
                return 1
            }
        }
        return 0
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
        return url
    }
}
#endif
