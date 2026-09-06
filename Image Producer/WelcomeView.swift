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
        // De-duplicate by the URL each bookmark resolves to, not by the bookmark
        // bytes — the same file bookmarked twice does not produce identical data.
        stored.removeAll { resolve($0)?.standardizedFileURL == url.standardizedFileURL }
        stored.insert(bookmark, at: 0)
        UserDefaults.standard.set(Array(stored.prefix(limit)), forKey: key)

        // Keep feeding AppKit too — it costs nothing and it is what File ▸ Open Recent
        // uses. It has never persisted anything here (no NSRecentDocumentRecords key
        // existed after 22 lifetime projects), which is the bug that started this.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// Newest first, with anything unresolvable dropped — a recents row that opens
    /// nothing is worse than no row.
    static func list() -> [URL] {
        let stored = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        var alive: [Data] = []
        var urls: [URL] = []
        for bookmark in stored {
            if let url = resolve(bookmark), FileManager.default.fileExists(atPath: url.path) {
                alive.append(bookmark)
                urls.append(url)
            }
        }
        if alive.count != stored.count { UserDefaults.standard.set(alive, forKey: key) }
        return urls
    }

    /// Forget everything. Backs File ▸ Open Recent ▸ Clear Menu's counterpart here.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
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

    private func refreshRecents() {
        recents = RecentProjects.list()
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

            Button {
                Task {
                    // Resolve the new file's URL OFF the main thread (the iCloud lookup can
                    // block). Create + open on the main actor. ALWAYS end with a visible
                    // window: if open fails, log why and fall back to an untitled doc — so we
                    // can never land in "welcome gone, no document window, app still running."
                    let url = await Task.detached { ImageDocument.nextProjectURL() }.value
                    var opened = false
                    if let url, ImageDocument.writeNewProject(at: url) {
                        // Register in the recent-documents list (SwiftUI's openDocument
                        // doesn't always record it), then open.
                        RecentProjects.note(url)
                        do { try await openDocument(at: url); opened = true }
                        catch {
                            NSLog("ImageProducer New: openDocument failed for %@ — %@",
                                  url.path, String(describing: error))
                        }
                    } else {
                        NSLog("ImageProducer New: could not create project file (url=%@)",
                              String(describing: url))
                    }
                    if !opened { newDocument(contentType: .imageProject) }
                    dismissWindow(id: "welcome")
                }
            } label: {
                Label("New Image", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

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
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.imageProject]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.prompt = "Open"
                panel.message = "Choose an Image Producer project to open."
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
                let panel = NSOpenPanel()
                panel.allowedContentTypes = ImageDocument.newFromImportContentTypes
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.prompt = "Import"
                panel.message = "Choose an image or PDF to open as a new document."
                guard panel.runModal() == .OK, let pdfURL = panel.url else { return }
                Task {
                    let url = await Task.detached { ImageDocument.nextProjectURL() }.value
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
                Text("Recent")
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
                            Button {
                                Task {
                                    // Sandboxed: the grant only exists inside this scope,
                                    // so the document has to be opened while it is held.
                                    await RecentProjects.withAccess(url) {
                                        RecentProjects.note(url)
                                        try? await openDocument(at: url)
                                    }
                                    dismissWindow(id: "welcome")
                                }
                            } label: {
                                Label(url.deletingPathExtension().lastPathComponent,
                                      systemImage: "doc")
                            }
                            .buttonStyle(.link)
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
        .frame(width: 440, height: 520)
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
