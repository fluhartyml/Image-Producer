//
//  Image_ProducerApp.swift
//  Image Producer
//
//  Created by Michael Fluharty on 6/20/26.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct Image_ProducerApp: App {
    var body: some Scene {
        // Document-based (roadmap 2.4.1): each icon is a saved package the user owns
        // in Files / iCloud Drive. New documents open with the default layer stack.
        DocumentGroup(newDocument: { IconDocument.newDefault() }) { configuration in
            ContentView(document: configuration.document)
                // Self-driven autosave — the app has no UndoManager (undo/redo is the
                // future History system's job), so SwiftUI's undo-based autosave never
                // fires. This writes the package directly as edits settle.
                .autosave(document: configuration.document,
                          fileURL: configuration.fileURL,
                          isEditable: configuration.isEditable)
        }
        // Turn off undo/redo. IconDocument is a ReferenceFileDocument that never registers
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
        }
        // macOS: suppress the default open-panel on launch so the custom Welcome window
        // (below) is the front door instead. .defaultLaunchBehavior is macOS 15+/visionOS
        // only, so gate to macOS — iOS/visionOS keep their DocumentGroupLaunchScene path.
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        // Branded launch experience (option B) — iPhone / iPad / Vision only.
        // DocumentGroupLaunchScene is NOT available on native macOS (iOS/iPadOS/Mac
        // Catalyst/visionOS only), and this app builds a native Mac target, so the Mac
        // keeps the default open-panel launch. Gated with #if !os(macOS).
        //
        // Replaces the bare document browser with a branded screen: the wordmark/title,
        // a prominent "New Image" button, and the recent-documents browser (free). New
        // docs are created as .iconProject (the first writable content type).
        #if !os(macOS)
        DocumentGroupLaunchScene("Image Producer") {
            NewDocumentButton("New Image", contentType: .iconProject)
        } background: {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.14, blue: 0.22),
                         Color(red: 0.05, green: 0.06, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        #endif

        // macOS branded launch — DocumentGroupLaunchScene isn't available on native macOS,
        // so the Mac gets a custom Welcome window instead. .defaultLaunchBehavior(.presented)
        // makes it the window shown at launch (paired with .suppressed on the DocumentGroup
        // above). WelcomeView has the wordmark, a New Image button, and recent documents.
        #if os(macOS)
        Window("Welcome to Image Producer", id: "welcome") {
            WelcomeView()
        }
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        #endif
    }
}
