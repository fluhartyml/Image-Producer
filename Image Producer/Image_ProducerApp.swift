//
//  Image_ProducerApp.swift
//  Image Producer
//
//  Created by Michael Fluharty on 6/20/26.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Export menu command (macOS)

/// Focused-document Export action, published by the frontmost ContentView so the
/// File menu can invoke it. A closure keyed off the focused scene — `nil` when no
/// document window is frontmost, which disables the menu item.
struct ExportActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var exportAction: (() -> Void)? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
}

#if os(macOS)
/// Adds File > Export… (⌘E) driving the focused document's Export flow.
struct ExportCommands: Commands {
    @FocusedValue(\.exportAction) private var exportAction

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Export…") { exportAction?() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(exportAction == nil)
        }
    }
}
#endif

@main
struct Image_ProducerApp: App {
    var body: some Scene {
        // Document-based (roadmap 2.4.1): each icon is a saved package the user owns
        // in Files / iCloud Drive. New documents open with the default layer stack.
        DocumentGroup(newDocument: { ImageDocument.newDefault() }) { configuration in
            ContentView(document: configuration.document, fileURL: configuration.fileURL)
                // Self-driven autosave — the app has no UndoManager (undo/redo is the
                // future History system's job), so SwiftUI's undo-based autosave never
                // fires. This writes the package directly as edits settle.
                .autosave(document: configuration.document,
                          fileURL: configuration.fileURL,
                          isEditable: configuration.isEditable)
        }
        // Turn off undo/redo. ImageDocument is a ReferenceFileDocument that never registers
        // undo actions — undo/redo belongs to the future linear History system, not the
        // system UndoManager (an app-wide UndoManager is what crashed Shelf-Ready on
        // deletes). Replacing the Undo/Redo command group with nothing drops Cmd+Z and the
        // Edit-menu Undo/Redo items. NOTE: \.undoManager is a read-only Environment value,
        // so it can't be nil'd directly — replacing the command group is the supported way.
        .commands {
            // Undo/Redo replaced with nothing for now (see note above).
            // TODO — once the linear History engine exists, bind ⌘Z / ⇧⌘Z here to step
            // through it instead of leaving them empty:
            //
            //   CommandGroup(replacing: .undoRedo) {
            //       Button("Step Back")    { history.stepBack() }
            //           .keyboardShortcut("z", modifiers: .command)          // ⌘Z = back
            //       Button("Step Forward") { history.stepForward() }
            //           .keyboardShortcut("z", modifiers: [.command, .shift]) // ⇧⌘Z = forward
            //   }
            //
            // Reach the focused document's history via @FocusedValue so ⌘Z hits THAT
            // document's history. The History tab/page already exists as a placeholder
            // (ContentView.historyPage); only the engine is missing ("no engine yet").
            CommandGroup(replacing: .undoRedo) { }

            #if os(macOS)
            // File > Export… (⌘E) — placed after Save, but distinct from it: Save
            // writes the editable project package; Export renders the finished icon
            // out. Drives the focused document's Export action (nil-disabled when no
            // document is frontmost).
            ExportCommands()
            #endif

            #if os(macOS)
            // ⌘N: new project as a REAL file (never "Untitled"). URL resolved OFF the main
            // thread (the iCloud lookup can block); create + open on main, fall back to a
            // default untitled doc on any failure.
            CommandGroup(replacing: .newItem) {
                Button("New Image") {
                    Task {
                        let url = await Task.detached { ImageDocument.nextProjectURL() }.value
                        if let url, ImageDocument.writeNewProject(at: url) {
                            NSDocumentController.shared.openDocument(withContentsOf: url,
                                                                     display: true) { doc, _, err in
                                if doc == nil {
                                    NSLog("ImageProducer ⌘N: open failed for %@ — %@",
                                          url.path, String(describing: err))
                                    NSDocumentController.shared.newDocument(nil)   // always a window
                                }
                            }
                        } else {
                            NSDocumentController.shared.newDocument(nil)
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                // ⇧⌘N: New from Import — the picked PDF IS the template. Seeds an EMPTY
                // document (NOT newDefault), so the Light/Dark floors appear only if the
                // PDF carries them — they never spawn out of nowhere.
                Button("New from Import…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.prompt = "Import"
                    panel.message = "Choose a PDF to open as a new document."
                    guard panel.runModal() == .OK, let pdfURL = panel.url else { return }
                    Task {
                        let url = await Task.detached { ImageDocument.nextProjectURL() }.value
                        if let url, ImageDocument.writeNewProjectFromPDF(at: url, pdf: pdfURL) {
                            NSDocumentController.shared.openDocument(withContentsOf: url,
                                                                     display: true) { doc, _, err in
                                if doc == nil {
                                    NSLog("ImageProducer ⇧⌘N: open failed for %@ — %@",
                                          url.path, String(describing: err))
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            #endif
        }
        // macOS: suppress the default open-panel on launch so the custom Welcome window
        // (below) is the front door instead. .defaultLaunchBehavior is macOS 15+/visionOS
        // only, so gate to macOS — iOS/visionOS keep their DocumentGroupLaunchScene path.
        #if os(macOS)
        // macOS: suppress the default open-panel on launch so the custom Welcome window
        // (below) is the front door instead.
        .defaultLaunchBehavior(.suppressed)
        // New document windows open centered at a consistent size (first launch / no
        // persisted frame); once moved/resized, state restoration owns the frame.
        .defaultSize(width: 1223, height: 680)
        .defaultPosition(.center)
        #endif

        // Branded launch experience (option B) — iPhone / iPad / Vision only.
        // DocumentGroupLaunchScene is NOT available on native macOS (iOS/iPadOS/Mac
        // Catalyst/visionOS only), and this app builds a native Mac target, so the Mac
        // keeps the default open-panel launch. Gated with #if !os(macOS).
        //
        // Replaces the bare document browser with a branded screen: the wordmark/title,
        // a prominent "New Image" button, and the recent-documents browser (free). New
        // docs are created as .imageProject (the first writable content type).
        #if !os(macOS)
        DocumentGroupLaunchScene("Image Producer") {
            NewDocumentButton("New Image", contentType: .imageProject)
        } background: {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.14, blue: 0.22),
                         Color(red: 0.05, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        } overlayAccessoryView: { _ in
            // Hero app icon above the wordmark — mirrors the Mac Welcome window, which
            // shows the app icon over the title. The 1024 icon art (LaunchHeroIcon,
            // light/dark) is clipped to the iOS app-icon superellipse so it reads as the
            // home-screen icon. The version line stays pinned at the bottom — the
            // conventional spot for a build stamp on a launch screen.
            VStack {
                Image("LaunchHeroIcon")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(radius: 8, y: 3)
                    .padding(.top, 44)
                Spacer()
                Text(appVersionLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        #endif

        // macOS branded launch — DocumentGroupLaunchScene isn't available on native macOS,
        // so the Mac gets a custom Welcome window instead. .defaultLaunchBehavior(.presented)
        // makes it the window shown at launch (paired with .suppressed on the DocumentGroup
        // above). WelcomeView has the wordmark, a New Image button, and recent documents.
        #if os(macOS)
        // macOS branded launch — the Welcome window is presented at launch (paired with
        // .suppressed on the DocumentGroup above).
        Window("Welcome to Image Producer", id: "welcome") {
            WelcomeView()
        }
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        #endif
    }
}
