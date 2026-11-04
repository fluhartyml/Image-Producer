//
//  Image_ProducerUITests.swift
//  Image ProducerUITests
//
//  REM: THE SHAKEDOWN, his ask 11-04: "can you do a shake down like you do during the white hat
//  security shakedown / inventory" — the Legend pattern. Drives the Mac app by accessibility
//  name and keyboard (his rule: drive our apps through VoiceOver and keyboard, not screenshots),
//  checks builds 356–359, inventories each screen (*.txt) and runs Apple's accessibility audit
//  (ACCESSIBILITY.md). Launches with -ImageProducerUITest (UITestDoor.swift): the test's image
//  lives in the app's temporary folder, not his iCloud folder; his recents and lifetime project
//  number are untouched. Results: RESULTS.md in the runner's tmp/ImageProducerUITestResults,
//  copied into the repo by Scripts/run-ui-tests.sh.
//

import XCTest

final class Image_ProducerUITests: XCTestCase {
    var app: XCUIApplication!

    static let dir: URL = {
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ImageProducerUITestResults")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-ImageProducerUITest"]   // the app turns window restore off for itself (UITestDoor)
        app.launch()
        app.activate()
    }

    override func tearDown() {
        app.terminate()
    }

    // MARK: Helpers

    func record(_ line: String) {
        let url = Self.dir.appendingPathComponent("RESULTS.md")
        let text = line + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? ("# Image Producer shakedown\n\n| Build | Result | Check |\n|---|---|---|\n" + text)
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func check(_ build: String, _ what: String, _ ok: Bool, _ detail: String = "") {
        record("| \(build) | \(ok ? "✅ PASS" : "❌ FAIL") | \(what)\(detail.isEmpty ? "" : " — \(detail)") |")
        XCTAssertTrue(ok, "\(build): \(what) \(detail)")
    }

    func snapshot(_ name: String) {
        try? app.debugDescription.write(to: Self.dir.appendingPathComponent("\(name).txt"),
                                        atomically: true, encoding: .utf8)
    }

    func audit(_ screen: String) {
        var issues: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let who = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "screen"
                issues.append("\(issue.auditType) · \(who) · \(issue.compactDescription)")
                return true
            }
        } catch {
            issues.append("audit couldn't run: \(error.localizedDescription)")
        }
        let url = Self.dir.appendingPathComponent("ACCESSIBILITY.md")
        var text = "\n### \(screen) — \(issues.count) issue(s)\n"
        for i in issues { text += "- \(i)\n" }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? ("# Accessibility audit\n" + text).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @discardableResult
    func press(_ label: String, _ seconds: TimeInterval = 8) -> Bool {
        let b = button(label)
        guard b.waitForExistence(timeout: seconds) else { return false }
        b.click()
        return true
    }

    // MARK: Probe (UITestDoor.swift)

    struct Probe {
        var w = 0.0, h = 0.0, layers = 0, hidden = 0, active = "", x = 0.0, y = 0.0
    }

    var probeElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'uitest.canvas' AND NOT (label CONTAINS 'active=none')")).firstMatch
    }

    func probe() -> Probe? {
        guard probeElement.waitForExistence(timeout: 5) else { return nil }
        let v = probeElement.label   // the readings ride in the label (a value is not passed through)
        var p = Probe()
        // "w=1920 h=720 layers=2 hidden=0 active=Layer 1 x=0.5000 y=0.5000"
        func num(_ key: String) -> Double? {
            guard let r = v.range(of: "\(key)=") else { return nil }
            return Double(v[r.upperBound...].prefix { "0123456789.-".contains($0) })
        }
        p.w = num("w") ?? 0; p.h = num("h") ?? 0
        p.layers = Int(num("layers") ?? 0); p.hidden = Int(num("hidden") ?? 0)
        p.x = num("x") ?? -1; p.y = num("y") ?? -1
        if let a = v.range(of: "active="), let e = v.range(of: " x=") { p.active = String(v[a.upperBound..<e.lowerBound]) }
        return p
    }

    /// Drag the active layer by (dx, dy) screen points, starting on the layer's center.
    func dragLayer(dx: CGFloat, dy: CGFloat, modifiers: XCUIElement.KeyModifierFlags = []) {
        guard let p = probe() else { return }
        // Bring the editor forward first: a mouse press on a window that isn't in front only
        // activates it, and the drag is lost. REM: the 11-04 runs clicked the title bar's
        // MIDDLE — where the Welcome window sat on top — so every drag re-activated the editor
        // and moved nothing. Welcome is closed after New Image now; this clicks near the
        // title bar's left end, just right of the window buttons, for good measure.
        let win = app.windows.matching(NSPredicate(format: "title CONTAINS '.imgprd'")).firstMatch
        if win.exists { win.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 120, dy: 12)).click(); sleep(1) }
        let start = probeElement.coordinate(withNormalizedOffset: CGVector(dx: p.x, dy: p.y))
        let end = start.withOffset(CGVector(dx: dx, dy: dy))
        start.hover(); usleep(300_000)
        let drag = { start.click(forDuration: 0.3, thenDragTo: end) }
        if modifiers.isEmpty { drag() } else { XCUIElement.perform(withKeyModifiers: modifiers, block: drag) }
        sleep(1)
    }

    /// Commit the Move session by leaving the tool, then come back.
    func commitMove() {
        press("Canvas"); sleep(1); press("Move"); sleep(1)
    }

    // MARK: The shakedown

    func testShakedown() throws {
        record("Run: \(Date())  ·  Mac  ·  -ImageProducerUITest (temporary image; his files untouched)")
        record("")

        // Welcome
        let welcome = app.windows["Welcome to Image Producer"]
        if welcome.waitForExistence(timeout: 10) {
            snapshot("00-welcome"); audit("Welcome")
        }

        // New image in the temporary folder.
        // File ▸ New Image by the menu (a keypress can land in his own copy of the app, in front).
        app.menuBars.menuBarItems["File"].click()
        let newItem = app.menuItems["New Image"]
        if newItem.waitForExistence(timeout: 5) { newItem.click() } else { app.typeKey(.escape, modifierFlags: []) }
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        if press("Create", 10) { sleep(2) }
        // Close the test copy's Welcome window: it overlapped the editor's title bar and took
        // the clicks meant to bring the editor forward before each drag.
        if welcome.exists {
            welcome.buttons["_XCUI:CloseWindow"].click(); sleep(1)
        }
        check("—", "A new image opens (in the test's temporary folder)",
              app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 10))
        snapshot("01-editor"); audit("Editor (Canvas tool)")

        // 356 — swatches are named buttons that answer an accessibility press.
        press("Color Palette"); sleep(1)
        let swatches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Color '"))
        check("356", "Palette swatches are named buttons", swatches.count >= 2, "\(swatches.count) found")
        snapshot("02-color-palette"); audit("Color Palette")

        // A layer to move.
        press("Add a layer"); sleep(1)
        // An empty layer has no art to grab; fill it edge to edge so the Move box is the canvas.
        press("Paint Drop Bucket"); sleep(1); press("Fill Layer"); sleep(1)
        press("Move"); sleep(1)
        snapshot("03-move"); audit("Move / Transform")
        guard let p0 = probe() else { check("—", "Probe readable", false); return }
        check("—", "A layer is active in Move", p0.active.hasPrefix("Layer"), p0.active)

        // 357 — arrow-key nudge: 5 × Down (1 px) + 1 × Shift-Down (10 px) = 15 px down.
        for _ in 0..<5 { app.typeKey(.downArrow, modifierFlags: []) }
        app.typeKey(.downArrow, modifierFlags: .shift)
        sleep(1)
        if let p = probe() {
            let dyPx = (p.y - p0.y) * p.h, dxPx = (p.x - p0.x) * p.w
            check("357", "Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways",
                  abs(dyPx - 15) < 0.6 && abs(dxPx) < 0.6, String(format: "moved %.1f px down, %.1f px sideways", dyPx, dxPx))
        }
        commitMove()
        if let p = probe() {
            check("357", "Leaving Move keeps the nudge as one Move step (hidden original kept)",
                  p.active.contains("(Move)") && p.hidden == p0.hidden + 1, "\(p.active), hidden \(p.hidden)")
        }

        // 358 — lock buttons.
        let upDown = button("Up down only"), leftRight = button("Left right only")
        check("358", "Straight-line buttons are there by their spoken names", upDown.exists && leftRight.exists)
        upDown.click(); sleep(1)
        check("358", "Up down only shows as selected when on", upDown.isSelected)
        if let a = probe() {
            dragLayer(dx: 60, dy: 40)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w, dy = (b.y - a.y) * b.h
                check("358", "Up down only: a diagonal drag moves only up/down",
                      abs(dx) < 0.6 && abs(dy) > 5, String(format: "%.1f px sideways, %.1f px down", dx, dy))
            }
        }
        upDown.click(); sleep(1)
        check("358", "Tapping Up down only again turns it off", !upDown.isSelected)
        leftRight.click(); sleep(1)
        if let a = probe() {
            dragLayer(dx: 60, dy: 40)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w, dy = (b.y - a.y) * b.h
                check("358", "Left right only: a diagonal drag moves only sideways",
                      abs(dy) < 0.6 && abs(dx) > 5, String(format: "%.1f px sideways, %.1f px down", dx, dy))
            }
        }
        leftRight.click(); sleep(1)
        check("358", "Left right only turns off again", !leftRight.isSelected)
        if let a = probe() {
            dragLayer(dx: 80, dy: 25, modifiers: .shift)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w, dy = (b.y - a.y) * b.h
                check("358", "Shift-drag locks to the starting direction (mostly sideways → sideways only)",
                      abs(dy) < 0.6 && abs(dx) > 5, String(format: "%.1f px sideways, %.1f px down", dx, dy))
            }
        }
        commitMove()

        // 359 — Option-drag drags a copy; the original stays.
        if let a = probe() {
            dragLayer(dx: -80, dy: 0, modifiers: .option)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w
                check("359", "Option-drag makes one new layer and selects it as \"(copy)\"",
                      b.layers == a.layers + 1 && b.active.hasSuffix("(copy)"), "\(b.active), layers \(a.layers)→\(b.layers)")
                check("359", "The copy moved", abs(dx) > 5, String(format: "%.1f px", dx))
            }
            commitMove()
            if let c = probe() {
                check("359", "Committing the copy adds no hidden fork", c.hidden == a.hidden, "hidden \(a.hidden)→\(c.hidden)")
            }
            // The original is still where it was: select it in the Layers list and read it.
            // REM: the Layers list shows names as static text whose VALUE is the name (the
            // 11-04 15:28 run found no row by label).
            let rows = app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", a.active, a.active))
            if rows.firstMatch.waitForExistence(timeout: 3) {
                rows.firstMatch.click(); sleep(1)
                if let o = probe(), o.active == a.active {
                    check("359", "The original stayed where it was",
                          abs((o.x - a.x) * o.w) < 0.6 && abs((o.y - a.y) * o.h) < 0.6,
                          String(format: "x %.4f→%.4f", a.x, o.x))
                }
            } else {
                record("| 359 | ⚠️ NOT CHECKED | Original's position — its row wasn't found by name '\(a.active)' |")
            }
        }
        // Option-Shift: a mostly-sideways copy drag stays level.
        if let a = probe() {
            dragLayer(dx: 70, dy: 20, modifiers: [.option, .shift])
            if let b = probe() {
                let dy = (b.y - a.y) * b.h
                check("359", "Option-Shift-drag copy stays in a straight line",
                      b.layers == a.layers + 1 && abs(dy) < 0.6, String(format: "%.1f px down", dy))
            }
            commitMove()
        }
        snapshot("04-after"); audit("Move / Transform after copies")
    }
}
