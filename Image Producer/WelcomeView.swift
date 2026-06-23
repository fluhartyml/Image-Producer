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

    /// Recent .iconproj documents, newest first (AppKit's recents list).
    private var recents: [URL] { NSDocumentController.shared.recentDocumentURLs }

    var body: some View {
        VStack(spacing: 28) {
            // Wordmark — mirrors the in-app About sheet (serif, "GRAPHIC ARTS" subtitle).
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
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
                    let url = await Task.detached { IconDocument.nextProjectURL() }.value
                    var opened = false
                    if let url, IconDocument.writeNewProject(at: url) {
                        do { try await openDocument(at: url); opened = true }
                        catch {
                            NSLog("ImageProducer New: openDocument failed for %@ — %@",
                                  url.path, String(describing: error))
                        }
                    } else {
                        NSLog("ImageProducer New: could not create project file (url=%@)",
                              String(describing: url))
                    }
                    if !opened { newDocument(contentType: .iconProject) }
                    dismissWindow(id: "welcome")
                }
            } label: {
                Label("New Image", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

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
            Text("Open other files from the File menu.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(width: 440, height: 520)
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.14, blue: 0.22),
                         Color(red: 0.05, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
#endif
