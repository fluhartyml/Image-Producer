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
        recents = NSDocumentController.shared.recentDocumentURLs
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
                        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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

            // New from Import — the launch surface IS the "no document open" state, so the
            // import-as-new-document path belongs right here next to New Image (not only in
            // the ⇧⌘N File-menu command). The picked PDF becomes the template: an empty doc
            // seeded from the PDF, so the Light/Dark floors appear only if the PDF has them.
            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.pdf]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.prompt = "Import"
                panel.message = "Choose a PDF to open as a new document."
                guard panel.runModal() == .OK, let pdfURL = panel.url else { return }
                Task {
                    let url = await Task.detached { ImageDocument.nextProjectURL() }.value
                    var opened = false
                    if let url, ImageDocument.writeNewProjectFromPDF(at: url, pdf: pdfURL) {
                        NSDocumentController.shared.noteNewRecentDocumentURL(url)
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

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(recents.prefix(6), id: \.self) { url in
                        Button {
                            Task {
                                try? await openDocument(at: url)
                                dismissWindow(id: "welcome")
                            }
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent,
                                  systemImage: "doc")
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
            // Link that pops open the app's File menu at the cursor, so "open other
            // files" is one click instead of a hunt up in the menu bar.
            Button("Open other files from the File menu.") {
                if let fileMenu = NSApplication.shared.mainMenu?.item(withTitle: "File")?.submenu {
                    fileMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
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
