//
//  DuoLaunchUITests.swift
//  Image ProducerUITests
//
//  REM: Mockup line 026 (2026-11-05) — the closed-Duo launch page: title, one row of buttons,
//  the card right under them, the three bar buttons and no "…", then open, save and rename a
//  file and open it again from our own list. Runs only on an iPhone Duo simulator (skips
//  elsewhere). Under -ImageProducerUITest every file goes to the test's temporary folder.
//

import XCTest

final class DuoLaunchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // REM: NO test door here. Under the door, files go to the app's temporary folder, and Apple's
        // browser makes the document there but never opens the editor (19:12 / 19:14 runs). This
        // test runs only on a Duo simulator, whose Documents folder is the simulator's own.
        // (Checked 13:2x: the run below decides whether that holds.)
        app.launch()
    }

    override func tearDown() { app.terminate() }

    private func shot(_ name: String) {
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DuoLaunchUITest")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: d.appendingPathComponent(name + ".png"))
        try? app.debugDescription.write(to: d.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        print("DUOUI shot \(d.path)/\(name)")
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testClosedDuoLaunchPage() throws {
        let title = el("duo.title")
        guard title.waitForExistence(timeout: 20) else {
            throw XCTSkip("No Duo launch page — not an iPhone Duo simulator")
        }
        sleep(2); shot("duo-01-page")
        let newImage = el("duo.newImage"), importButton = el("duo.newFromImport"), card = el("duo.card")
        XCTAssertTrue(newImage.exists && importButton.exists && card.exists, "buttons and card on screen")

        // 010–012: the relationships, not the sizes.
        print("DUOUI title=\(title.frame) new=\(newImage.frame) import=\(importButton.frame) card=\(card.frame) window=\(app.windows.firstMatch.frame)")
        XCTAssertLessThan(title.frame.minY, 120, "title near the top")
        XCTAssertLessThan(abs(newImage.frame.midY - importButton.frame.midY), 4, "both buttons on one row")
        XCTAssertGreaterThanOrEqual(card.frame.minY, newImage.frame.maxY - 1, "card starts below the buttons")
        XCTAssertLessThan(card.frame.minY - newImage.frame.maxY, 30, "card starts right under the buttons")
        XCTAssertGreaterThan(card.frame.maxY, app.windows.firstMatch.frame.maxY - 2, "card reaches the bottom")

        // 013: the three bar buttons, and no "…" anywhere on the page.
        for id in ["duo.list", "duo.select", "duo.connect"] { XCTAssertTrue(el(id).isHittable, "\(id) hittable") }
        let more = app.buttons.matching(NSPredicate(format: "label CONTAINS '…' OR label ==[c] 'More'"))
        XCTAssertEqual(more.count, 0, "no … button")
        for tab in ["Recents", "Shared", "Browse"] { XCTAssertTrue(el("duo.tab.\(tab)").exists, "\(tab) tab") }

        // Open: New Image → the editor.
        newImage.tap(); sleep(3); shot("duo-02-after-new")
        if app.buttons["Create"].waitForExistence(timeout: 10) { app.buttons["Create"].tap() }
        // REM: "uitest.canvas" exists only behind the test door; the editor's Back button marks it here.
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 25), "New Image opened the editor")
        sleep(10); shot("duo-03-editor")

        // Rename (and so save) through the Canvas inspector's name field.
        let name = app.textFields["Project name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "name field")
        name.tap()
        name.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText(XCUIKeyboardKey.delete.rawValue)
        name.typeText("Duo Rename Test\n")
        sleep(4)

        // Close the image → our page comes back and lists the renamed file.
        XCTAssertTrue(back.waitForExistence(timeout: 10), "back button")
        back.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15), "our page is back after closing")
        let renamed = el("duo.file.Duo Rename Test")
        XCTAssertTrue(renamed.waitForExistence(timeout: 15), "renamed file listed")

        // Open it again from our own list.
        renamed.tap()
        XCTAssertTrue(app.buttons["BackButton"].firstMatch.waitForExistence(timeout: 25), "opened from our list")
        XCTAssertFalse(title.exists, "our page is not over the editor")
    }
}
