//
//  UITestDoor.swift
//  Image Producer
//
//  REM: THE SHAKEDOWN'S DOOR, his ask 11-04: "can you do a shake down like you do during the
//  white hat security shakedown / inventory" — the Legend pattern (an XCUITest that drives the
//  app by accessibility name, inventories each screen and runs Apple's accessibility audit).
//  The test launches the app with -ImageProducerUITest. DEBUG builds only; a Release or
//  TestFlight build never has it, whatever arguments it is given.
//
//  While the door is open the test must leave NO trace in his things:
//  - new projects go to the app's temporary folder, never his iCloud Image Producer folder;
//  - the lifetime project number (ImageProducerNNNN) is not advanced;
//  - Welcome's recents (capped at 8) are not touched, so no real entry is pushed out.
//  And the canvas gets an invisible probe element (identifier "uitest.canvas") whose frame is
//  the canvas and whose value reports the active layer — the canvas itself is not visible to
//  accessibility yet (roadmap 013), and the test needs to aim drags and check positions.
//

import Foundation

enum UITestDoor {
    #if DEBUG
    nonisolated static let isOpen = ProcessInfo.processInfo.arguments.contains("-ImageProducerUITest")
    #else
    nonisolated static let isOpen = false
    #endif

    /// Where the test's projects go: the sandbox's own temporary folder.
    nonisolated static var projectsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ImageProducerUITest", isDirectory: true)
    }
}
