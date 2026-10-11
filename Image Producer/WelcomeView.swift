//
//  WelcomeView.swift
//  Image Producer
//
//  Mac-only branded launch window. iPhone/iPad/Vision get DocumentGroupLaunchScene
//  instead — that scene isn't available on native macOS, so the Mac uses a custom
//  Window + .defaultLaunchBehavior (see Image_ProducerApp) to get an equivalent
//  branded launch: wordmark, a New Image action, and recent documents.
//

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// OUR OWN recent-projects list.
///
/// ⛔ WHY THIS EXISTS. The Welcome window read `NSDocumentController.shared
/// .recentDocumentURLs`, and both the New and the Import paths dutifully called
/// `noteNewRecentDocumentURL`. It never persisted: on 2026-09-06, with
/// `ip.lifetimeProjectCount` at 22, the app's preferences held **no
/// `NSRecentDocumentRecords` key at all** — so the list was empty for every project
/// Michael had ever made, and the Welcome window has been showing a bare pair of
/// "start something new" buttons with no way back to his work.
///
/// A SwiftUI `DocumentGroup` does not own an AppKit document controller in the way
/// that API expects, so rather than keep guessing at it, the app keeps its own list
/// in its own preferences — next to the other `ip.*` keys it already writes.
///
/// ⚠️ SECURITY-SCOPED BOOKMARKS, NOT PATHS — **this app IS sandboxed.**
///
/// The first version of this stored plain paths, on the strength of the
/// `Image Producer.entitlements` file, which carries only iCloud keys and no
/// `com.apple.security.app-sandbox`. That was the wrong file to read. The build
/// settings say `ENABLE_APP_SANDBOX = YES`, Xcode synthesizes the entitlement at
/// sign time, and the signed app has both `app-sandbox` and
/// `files.user-selected.read-write`.
///
/// A sandboxed app gets access to a user-chosen file for that launch only. A stored
/// PATH would therefore list projects it cannot open after a relaunch — rows that do
/// nothing, which is worse than an empty list. A security-scoped BOOKMARK is the
/// thing that survives, and it has to be resolved and opened inside
/// `startAccessingSecurityScopedResource()`.
enum RecentProjects {
    private static let key = "ip.recentDocumentBookmarks"
    private static let limit = 8

    /// Put `url` at the top, de-duplicated, capped. Called from every path that opens
    /// or creates a project.
    static func note(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else {
            NSLog("ImageProducer recents: could not bookmark %@", url.path)
            return
        }
        var stored = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        // De-duplicate by the PATH recorded inside each bookmark, read without resolving
        // it. Resolving can fail (see list()), and an entry that cannot resolve must still
        // be recognised as this file, or every reopen would add another copy of it.
        let target = url.standardizedFileURL.path
        stored.removeAll { recordedPath(of: $0) == target || resolve($0)?.standardizedFileURL.path == target }
        stored.insert(bookmark, at: 0)
        UserDefaults.standard.set(Array(stored.prefix(limit)), forKey: key)

        // Keep feeding AppKit too — it costs nothing and it is what File ▸ Open Recent
        // uses. It has never persisted anything here (no NSRecentDocumentRecords key
        // existed after 22 lifetime projects), which is the bug that started this.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// Newest first — the entries that open right now.
    ///
    /// ⛔ THIS NO LONGER DELETES ANYTHING. It used to rewrite the stored list with only the
    /// entries that resolved, so ONE bad launch erased the lot, permanently. That is what
    /// happened on 2026-09-16 at 06:56: the Time Machine snapshot from 06:10 still held
    /// Phototizer, LayerKeytest and Layerlayertest; the preferences written at 06:56 held
    /// nothing. Michael: "it used to remember, it just recently forgot them."
    ///
    /// An entry that does not open now is kept and simply not shown; it is tried again on
    /// the next launch. Only Clear, or falling off the end of the 8-entry cap, removes one.
    ///
    /// ⚠️ And the existence check runs INSIDE the security scope. The sandbox can answer
    /// "no such file" for a file this app has not been granted yet, which would have
    /// looked exactly like a deleted project.
    static func list() -> [URL] {
        let stored = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        var urls: [URL] = []
        for bookmark in stored {
            guard let url = resolve(bookmark) else {
                NSLog("ImageProducer recents: kept but not shown — could not resolve %@",
                      recordedPath(of: bookmark) ?? "(unknown path)")
                continue
            }
            let granted = url.startAccessingSecurityScopedResource()
            let exists = FileManager.default.fileExists(atPath: url.path)
            if granted { url.stopAccessingSecurityScopedResource() }
            if exists {
                urls.append(url)
            } else {
                NSLog("ImageProducer recents: kept but not shown — not found at %@", url.path)
            }
        }
        return urls
    }

    /// Forget everything. Backs File ▸ Open Recent ▸ Clear Menu's counterpart here.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        do {
            return try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            NSLog("ImageProducer recents: resolve failed — %@", String(describing: error))
            return nil
        }
    }

    /// The path a bookmark was made for, read from the bookmark itself — no resolving, no
    /// sandbox grant needed.
    private static func recordedPath(of bookmark: Data) -> String? {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    /// Open a recents entry. The sandbox only hands over access inside this scope, so
    /// the document must be opened WHILE it is held.
    static func withAccess<T>(_ url: URL, _ body: () async throws -> T) async rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}

struct WelcomeView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.colorScheme) private var colorScheme

    /// Neutral background gradient that follows the system appearance: a light gray
    /// in Light Mode, a dark charcoal in Dark Mode. The text uses semantic inks, so
    /// it stays legible against either. (Kept lighter than the icon tile.)
    private var backgroundColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.20, green: 0.20, blue: 0.21),
               Color(red: 0.13, green: 0.13, blue: 0.14)]
            : [Color(red: 0.97, green: 0.97, blue: 0.98),
               Color(red: 0.90, green: 0.90, blue: 0.92)]
    }

    /// Recent documents, newest first (AppKit's recents list). Held in @State and
    /// refreshed on appear / when the app reactivates, so newly-created or -opened
    /// projects appear without the view needing to be rebuilt.
    @State private var recents: [URL] = []

    /// NAME BEFORE NEW — his ask, 2026-10-11: "can the user type the proposed new file name
    /// in the welcome sheet before clicking on create new file?" Empty = the usual
    /// ImageProducerNNNN.
    @State private var newName = ""
    /// Set when the typed name is already a project. Never suffixed into "Name 2" (Skills
    /// Lab: compare on collision, never suffix) — he decides: open it, or type another.
    @State private var nameTaken: URL?
    /// Why the last open failed, shown in this window. ⛔ No silent fallback: until
    /// 2026-10-11 a failed open quietly made a blank ImageProducerNNNN instead, which hid
    /// the failure and looked like the app ignoring the name he typed.
    @State private var openError: String?
    /// THE NAME BOX IS A STAGING AREA — his design, 2026-10-11: "you tap a recent name and
    /// its text automatically populates the name optional text box then you tap new image
    /// open psd open or new from import". One click on a Recent STAGES it (no more opening
    /// by accident); the buttons act on what is staged. Double-click still opens at once.
    /// Cleared the moment the name is edited to something else.
    @State private var stagedURL: URL?

    private func refreshRecents() {
        recents = RecentProjects.list()
    }

    /// The typed name, made safe as a file name: trimmed, no path separators.
    private var cleanedName: String {
        var n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        return String(n.prefix(200))
    }

    /// OPEN .psd — his design, 2026-10-11: "if it cant find photoshop.psd then it opens a
    /// new file named photoshop.psd". The typed name is looked up as <name>.psd in the
    /// Image Producer folder: there → it opens; not there → a new one is made and opened.
    /// "Open", not "New": opening a .psd is the plain, legal description (his word).
    /// Empty name: a file picker for any .psd.
    private func openPSD() {
        if let staged = stagedURL, ImageDocument.isPSD(staged) { Task { await openRecent(staged) }; return }
        let typed = cleanedName
        if typed.isEmpty {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.photoshopDocument]
            panel.allowsMultipleSelection = false
            panel.prompt = "Open"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task { await open(url) }
            return
        }
        Task {
            let found = await Task.detached { () -> (psd: URL?, project: URL?) in
                (ImageDocument.namedProjectURL(typed, ext: "psd"), ImageDocument.namedProjectURL(typed))
            }.value
            guard let url = found.psd else {
                openError = "Could not find the Image Producer folder."
                return
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                // An existing project by this name (staged, or found) comes in AS a .psd —
                // its own content, no size question. Only a name with no file at all makes
                // a blank new one.
                let fm = FileManager.default
                let project = stagedURL ?? found.project.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                if let project {
                    var ok = false
                    await RecentProjects.withAccess(project) {
                        ok = ImageDocument.writePSD(fromProject: project, to: url)
                    }
                    guard ok else {
                        openError = "Could not make \(url.lastPathComponent) from “\(project.deletingPathExtension().lastPathComponent)”."
                        return
                    }
                } else {
                    guard ImageDocument.writeNewPSD(at: url) else {
                        openError = "Could not create \(url.lastPathComponent)."
                        return
                    }
                }
            }
            await open(url)
        }
    }

    /// New Image / New from Import on a file that already exists: a NEW PROJECT made from
    /// it, named "<name> N" (first free number from 2), in the Image Producer folder, then
    /// opened. ALWAYS a project (.prd) — a staged .psd is brought in as a project too (his
    /// screen, 2026-10-11: he pressed New Image on the .psd and got another .psd). Only
    /// Open .psd stays in .psd. The source is never touched. The Image Producer folder,
    /// not the source's own: a Recent can live anywhere and the sandbox only lets the app
    /// write its own folder.
    private func newFromCopy(of source: URL) async {
        let folder = await Task.detached { ImageDocument.projectsDirectory() }.value
        guard let dir = folder else {
            openError = "Could not find the Image Producer folder."
            return
        }
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = ImageDocument.projectExtension
        var n = 2
        var copy = dir.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
        while FileManager.default.fileExists(atPath: copy.path) {
            n += 1
            copy = dir.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
        }
        var failure: String?
        await RecentProjects.withAccess(source) {
            if ImageDocument.isPSD(source) {
                // The .psd's content, as a project.
                guard let data = try? Data(contentsOf: source),
                      let project = projectFromPSD(data, name: copy.deletingPathExtension().lastPathComponent)
                else { failure = "it could not be read"; return }
                let doc = ImageDocument(layers: [])
                doc.load(project.manifest)
                do { try doc.writePackage(to: copy) } catch { failure = error.localizedDescription }
            } else {
                do { try FileManager.default.copyItem(at: source, to: copy) }
                catch { failure = error.localizedDescription }
            }
        }
        if let failure {
            openError = "Could not make a new project from “\(source.lastPathComponent)”: \(failure)"
            return
        }
        stagedURL = nil
        await open(copy)
    }

    /// Open a Recent: sandboxed, so the grant is held while the document opens. A failed
    /// open stays here and says why — never a blank new document in its place.
    private func openRecent(_ url: URL) async {
        var failure: String?
        await RecentProjects.withAccess(url) {
            RecentProjects.note(url)
            do { try await openDocument(at: url) }
            catch { failure = "\(error.localizedDescription) (\(String(describing: error)))" }
        }
        if let failure {
            openError = "“\(url.deletingPathExtension().lastPathComponent)” would not open: \(failure)"
        } else {
            dismissWindow(id: "welcome")
        }
    }

    /// Open a file and close Welcome — or stay and say why it would not open.
    private func open(_ url: URL) async {
        RecentProjects.note(url)
        do {
            try await openDocument(at: url)
            dismissWindow(id: "welcome")
        } catch {
            openError = "“\(url.lastPathComponent)” would not open: \(error.localizedDescription) (\(String(describing: error)))"
        }
    }

    /// New Image: always a new Image Producer project.
    private func createNew() {
        let typed = cleanedName
        Task {
            // Resolve the new file's URL OFF the main thread (the iCloud lookup can
            // block). Create + open on the main actor. ALWAYS end with a visible
            // window: if open fails, log why and fall back to an untitled doc — so we
            // can never land in "welcome gone, no document window, app still running."
            let url = await Task.detached {
                typed.isEmpty ? ImageDocument.nextProjectURL() : ImageDocument.namedProjectURL(typed)
            }.value
            // NAME ALREADY USED (or a Recent staged): New Image makes a COPY of that file
            // with the next number after the name, and opens the copy — his rule,
            // 2026-10-11: "if the user tapped new image it acts like new from copy and
            // appends a number after the name". The original is never touched.
            let existing = stagedURL ?? url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            if let source = existing, !typed.isEmpty {
                await newFromCopy(of: source)
                return
            }
            guard let url, ImageDocument.writeNewProject(at: url) else {
                openError = "Could not create the project file."
                return
            }
            // Register in the recent-documents list (SwiftUI's openDocument
            // doesn't always record it), then open.
            RecentProjects.note(url)
            do {
                try await openDocument(at: url)
                dismissWindow(id: "welcome")
            } catch {
                // The file exists; say why it would not open and stay here.
                openError = "“\(url.deletingPathExtension().lastPathComponent)” was created but would not open: \(error.localizedDescription) (\(String(describing: error)))"
            }
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            // Wordmark — mirrors the in-app About sheet (serif, "GRAPHIC ARTS" subtitle).
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .padding(18)
                    .background(
                        // Soft light-gray tile behind the icon (white 0.89, tuned live).
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color(white: 0.89))
                    )
                Text("Image Producer")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                Text("GRAPHIC ARTS")
                    .font(.subheadline)
                    .tracking(4)
                    .foregroundStyle(.secondary)
                Text(appVersionLine)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Name (optional)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18))
                    .onSubmit { createNew() }
                    .onChange(of: newName) {
                        nameTaken = nil; openError = nil
                        if let staged = stagedURL,
                           staged.deletingPathExtension().lastPathComponent != newName { stagedURL = nil }
                    }
                if let taken = nameTaken {
                    HStack {
                        Text("“\(taken.deletingPathExtension().lastPathComponent)” already exists.")
                            .font(.system(size: 18)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open It") {
                            Task {
                                RecentProjects.note(taken)
                                if (try? await openDocument(at: taken)) != nil { dismissWindow(id: "welcome") }
                            }
                        }
                        .font(.system(size: 18))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    createNew()
                } label: {
                    Label("New Image", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // OPEN .psd — his word, 2026-10-11: "not new psd 'open .psd'".
                Button {
                    openPSD()
                } label: {
                    Label("Open .psd", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            if let openError {
                Text(openError)
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // OPEN — Michael spotted the gap, 2026-09-06: "i just noticed a missng
            // element… what about an open?"
            //
            // The window offered two ways to START something and no way to RETURN to
            // something, which is why "New from Import" was reading as the open button
            // and why he asked whether it should just be called "Open Image."
            //
            // ⛔ It must NOT be called that, and Import must not be renamed to it. They
            // are different verbs: Open reopens an .imgprd PROJECT; New from Import
            // creates a NEW project seeded from a foreign file and never writes back to
            // it. "Open Image" would promise editing that PNG in place — so the first
            // time someone opened one, edited, and saved, they would expect their PNG to
            // have changed. It has not.
            Button {
                // Staged: open that exact file. A typed name that is a project in the
                // Image Producer folder opens too. Otherwise, the file picker.
                if let staged = stagedURL { Task { await openRecent(staged) }; return }
                let typed = cleanedName
                if !typed.isEmpty, let url = ImageDocument.namedProjectURL(typed),
                   FileManager.default.fileExists(atPath: url.path) {
                    Task { await open(url) }; return
                }
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.imageProject]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.prompt = "Open"
                panel.message = "Choose an Image Producer project to open."
                // Start in the app's own iCloud folder. Without this, macOS reopens whatever
                // folder any panel in this app used last — the Desktop, on 2026-09-16, and he
                // expected "the image producer icloud folder."
                panel.directoryURL = ImageDocument.projectsDirectory()
                guard panel.runModal() == .OK, let url = panel.url else { return }
                Task {
                    RecentProjects.note(url)
                    do {
                        try await openDocument(at: url)
                        dismissWindow(id: "welcome")
                    } catch {
                        NSLog("ImageProducer Open: openDocument failed for %@ — %@",
                              url.path, String(describing: error))
                    }
                }
            } label: {
                Label("Open…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)

            // New from Import — the launch surface IS the "no document open" state, so the
            // import-as-new-document path belongs right here next to New Image (not only in
            // the ⇧⌘N File-menu command). The picked file becomes the template: an empty doc
            // seeded from it, so the Light/Dark floors appear only if the source has them.
            // Takes an IMAGE as readily as a PDF — the panel used to be locked to PDF, which
            // made an ordinary PNG unopenable even though the layer importer reads one fine.
            Button {
                // STAGED (or a name already in use): no picker — a copy with the next
                // number, exactly like New Image. His word, 2026-10-11: "new from import
                // would act the same as open as a copy with a number appended because
                // theres no file navigation just a list of recents".
                let typed = cleanedName
                if let staged = stagedURL { Task { await newFromCopy(of: staged) }; return }
                if !typed.isEmpty, let url = ImageDocument.namedProjectURL(typed),
                   FileManager.default.fileExists(atPath: url.path) {
                    Task { await newFromCopy(of: url) }; return
                }
                let panel = NSOpenPanel()
                panel.allowedContentTypes = ImageDocument.newFromImportContentTypes
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.prompt = "Import"
                panel.message = "Choose an image or PDF to open as a new document."
                guard panel.runModal() == .OK, let pdfURL = panel.url else { return }
                Task {
                    // The name box names the new project; a name in use is never overwritten.
                    let url = await Task.detached {
                        typed.isEmpty ? ImageDocument.nextProjectURL() : ImageDocument.namedProjectURL(typed)
                    }.value
                    if let url, !typed.isEmpty, FileManager.default.fileExists(atPath: url.path) {
                        nameTaken = url
                        return
                    }
                    var opened = false
                    if let url, ImageDocument.writeNewProject(at: url, from: pdfURL) {
                        RecentProjects.note(url)
                        do { try await openDocument(at: url); opened = true }
                        catch {
                            NSLog("ImageProducer New from Import: openDocument failed for %@ — %@",
                                  url.path, String(describing: error))
                        }
                    } else {
                        NSLog("ImageProducer New from Import: could not create project from the chosen PDF")
                    }
                    if opened { dismissWindow(id: "welcome") }
                }
            } label: {
                Label("New from Import…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)

            // RECENT — ALWAYS DRAWN, EMPTY OR NOT. Michael, 2026-09-06: "can an empty
            // recents list be a box with no files listed as a place holder below the
            // 'new from import...'"
            //
            // It used to vanish when empty, which cost two things: the window changed
            // shape the moment a first project existed, and — worse — an empty list was
            // indistinguishable from a missing feature. He asked me twice today whether
            // I had removed it. A box that says it is empty answers that on sight.
            VStack(alignment: .leading, spacing: 6) {
                Text("Recents")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if recents.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.tertiary)
                        Text("No recent projects yet.")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(.horizontal, 10)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(recents.prefix(6), id: \.self) { url in
                            let staged = stagedURL == url
                            // Full file name, extension and all — his word, 2026-10-11, so a
                            // project and its .psd twin can be told apart.
                            Label(url.lastPathComponent, systemImage: "doc")
                                .font(.system(size: 18))
                                .foregroundStyle(staged ? Color.white : Color.accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(staged ? Color.accentColor : Color.clear))
                                .contentShape(Rectangle())
                                // Double-click opens; a single click stages (count 2 first,
                                // so a double-click is not also read as two stagings).
                                .onTapGesture(count: 2) { Task { await openRecent(url) } }
                                .onTapGesture {
                                    stagedURL = url
                                    newName = url.deletingPathExtension().lastPathComponent
                                    nameTaken = nil; openError = nil
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.12))
            )

            Spacer(minLength: 0)
            // The faint "Open other files from the File menu." link lived here. It only
            // ever existed to cover the missing Open button — it popped the File menu at
            // the cursor so the user could find Open themselves. With a real Open button
            // above, it has no job, and a launch window is the wrong place to send
            // someone hunting through a menu. Removed 2026-09-06 with his word.
        }
        .padding(40)
        // WIDTH FIXED, HEIGHT INTRINSIC. It was a hard 440×520, which was right until
        // the Recent box arrived — the content grew past 520 and the window clipped it
        // at BOTH ends: the icon at the top and the Recent box at the bottom.
        // Michael caught it on sight, 2026-09-06.
        //
        // The scene is already `.windowResizability(.contentSize)`, so the window sizes
        // itself to whatever this view wants — a fixed height was the only thing
        // stopping it. Letting the height be intrinsic means the window grows as
        // recents accumulate and never has to clip anything.
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            LinearGradient(
                colors: backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { refreshRecents() }
        // Refresh when the app reactivates (e.g. returning to the Welcome window after
        // closing a document) so the recents list reflects the latest projects.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshRecents()
        }
    }
}
#endif
