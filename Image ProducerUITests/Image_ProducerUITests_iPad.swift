//
//  Image_ProducerUITests_iPad.swift
//  Image ProducerUITests
//
//  REM: THE iPAD SHAKEDOWN, his ask 11-04: "can you use the ipad simulator to do a shakedown?"
//  → "yes write the ipad shakedown and run it". Same pattern as the Mac's (Legend's white-hat
//  shakedown): drive by accessibility name, touch and a hardware keyboard — never screenshots.
//  Runs in the iPad SIMULATOR only (Scripts/run-ipad-ui-tests.sh); his real iPad is never touched.
//  Checks: 356 named swatches · A3 (364) tool letters + arrow nudge from a hardware keyboard ·
//  358 straight-line locks with a touch drag · 012/A4 (366) Position X/Y fields.
//  REM: Option-drag copies (359) are a Mac pointer gesture — not checked here.
//

import XCTest

#if os(iOS)
final class Image_ProducerUITests_iPad: XCTestCase {
    var app: XCUIApplication!

    static let dir: URL = {
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ImageProducerUITestResults")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments += ["-ImageProducerUITest"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    // MARK: Helpers (same record format as the Mac's, so run-ipad-ui-tests.sh counts the same way)

    func record(_ line: String) {
        let url = Self.dir.appendingPathComponent("RESULTS.md")
        let text = line + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? ("# Image Producer iPad shakedown\n\n| Build | Result | Check |\n|---|---|---|\n" + text)
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
            try? ("# Accessibility audit (iPad)\n" + text).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @discardableResult
    func press(_ label: String, _ seconds: TimeInterval = 8) -> Bool {
        let b = button(label)
        guard b.waitForExistence(timeout: seconds) else { return false }
        b.tap()
        return true
    }

    // MARK: Probe (UITestDoor.swift) — same label format as the Mac

    struct Probe {
        var w = 0.0, h = 0.0, layers = 0, hidden = 0, active = "", x = 0.0, y = 0.0
    }

    var probeElement: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'uitest.canvas' AND NOT (label CONTAINS 'active=none')")).firstMatch
    }

    func probe() -> Probe? {
        guard probeElement.waitForExistence(timeout: 5) else { return nil }
        let v = probeElement.label
        var p = Probe()
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

    /// Touch-drag the active layer by (dx, dy) points, starting on the layer's center.
    func dragLayer(dx: CGFloat, dy: CGFloat) {
        guard let p = probe() else { return }
        let start = probeElement.coordinate(withNormalizedOffset: CGVector(dx: p.x, dy: p.y))
        let end = start.withOffset(CGVector(dx: dx, dy: dy))
        start.press(forDuration: 0.3, thenDragTo: end)
        sleep(1)
    }

    func commitMove() {
        press("Canvas"); sleep(1); press("Move"); sleep(1)
    }

    /// Hardware-keyboard key, sent to the app (the A3 key-catcher), not to a text field.
    func key(_ k: String, _ flags: XCUIElement.KeyModifierFlags = []) {
        app.typeKey(k, modifierFlags: flags)
    }

    // MARK: The shakedown

    func testShakedownIPad() throws {
        record("Run: \(Date())  ·  iPad simulator  ·  -ImageProducerUITest (simulator only; his iPad untouched)")
        record("")

        // Launch screen → New Image (the launch scene's own button; the system makes the file).
        sleep(5); snapshot("00-start")
        // REM: the launch scene and the document browser under it BOTH carry a "New Image"
        // button; the 18:24 run's firstMatch tapped the browser's and opened its Shared tab.
        // Take the launch scene's: the hittable one nearest the top.
        _ = button("New Image").waitForExistence(timeout: 15)
        snapshot("00-launch"); audit("Launch")
        // REM: a fresh simulator has no iCloud and its browser opened on Shared, so New Image
        // said "No location available to save" (18:38 run). Pick On My iPad first.
        if press("Browse", 5) {
            sleep(1)
            let onMyIPad = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPad'")).firstMatch
            if onMyIPad.waitForExistence(timeout: 5) { onMyIPad.tap(); sleep(1) }
        }
        let candidates = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex
            .filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }
        if let launchButton = candidates.first { launchButton.tap() }
        sleep(3)
        // REM: the 19:14 run's tap left the launch screen up (a file from the 18:44 run sat in
        // On My iPad; the tap may have landed mid-refresh). One retry, then go on and report.
        if !app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 5),
           !app.buttons["Create"].exists, !app.alerts.firstMatch.exists {
            let again = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex
                .filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }
            if let b = again.first { record("| — | ↻ RETRY | New Image tapped a second time |"); b.tap(); sleep(3) }
        }
        snapshot("00b-after-new-image")
        let alert = app.alerts.firstMatch
        if alert.exists {
            record("| — | ⚠️ ALERT | \(alert.label): \(alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")) |")
            alert.buttons.firstMatch.tap(); sleep(1)
        }
        if press("Create", 10) { sleep(2) }
        check("—", "A new image opens",
              app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 15))
        snapshot("01-editor"); audit("Editor (Canvas tool)")

        // 356 — swatches are named buttons.
        press("Color Palette"); sleep(1)
        let swatches = app.buttons.matching(NSPredicate(format: "label MATCHES 'Color [0-9]+, .*'"))
        check("356", "Palette swatches are named buttons", swatches.count >= 2, "\(swatches.count) found")

        // REM: 009a, his yes 11-04 19:2x: "add the swatch press test". A NAME IS NOT A PRESS —
        // press a swatch that is NOT the active color and check it becomes the selected one
        // (the .isSelected trait rides on the same isSel the accent ring draws from), and that
        // it is the only one selected. ("Color N, #hex" only — the 19:19 run's BEGINSWITH 'Color '
        // also caught the selected "Color Palette" tool tile.) The robot's press is a pointer press; the accessibility
        // action runs the SAME closure (paletteSwatchAccessibility), so they cannot drift apart.
        if let target = swatches.allElementsBoundByIndex.first(where: { !$0.isSelected }) {
            let name = target.label
            target.tap(); sleep(1)
            let after = app.buttons.matching(NSPredicate(format: "label MATCHES 'Color [0-9]+, .*'")).allElementsBoundByIndex
            let selected = after.filter { $0.isSelected }.map { $0.label }
            check("356", "Pressing a swatch picks that color", selected == [name],
                  "pressed \(name); selected now: \(selected.joined(separator: " · "))")
        } else {
            check("356", "Pressing a swatch picks that color", false, "no unselected swatch to press")
        }
        snapshot("02-color-palette"); audit("Color Palette")

        // A3 (364) — tool letters from a hardware keyboard pick tools.
        // Tap the canvas first so the key-catcher (not a field) has the keyboard.
        press("Canvas"); sleep(1)
        for (letter, tool) in [("m", "Move"), ("b", "Paint Drop Bucket"), ("c", "Canvas")] {
            key(letter); sleep(1)
            check("364", "Key \(letter.uppercased()) picks \(tool)", button(tool).isSelected)
        }

        // A layer to move, filled edge to edge so the Move box is the canvas.
        press("Add a layer"); sleep(1)
        press("Paint Drop Bucket"); sleep(1); press("Fill Layer"); sleep(1)
        press("Move"); sleep(1)
        snapshot("03-move"); audit("Move / Transform")
        guard let p0 = probe() else { check("—", "Probe readable", false); return }
        check("—", "A layer is active in Move", p0.active.hasPrefix("Layer"), p0.active)

        // A3 (364) — arrow nudge: 5 × Down (1 px) + 1 × Shift-Down (10 px) = 15 px down.
        for _ in 0..<5 { key(XCUIKeyboardKey.downArrow.rawValue) }
        key(XCUIKeyboardKey.downArrow.rawValue, .shift)
        sleep(1)
        if let p = probe() {
            let dyPx = (p.y - p0.y) * p.h, dxPx = (p.x - p0.x) * p.w
            check("364", "Arrow keys: Down ×5 + Shift-Down = 15 px down, none sideways",
                  abs(dyPx - 15) < 0.6 && abs(dxPx) < 0.6, String(format: "moved %.1f px down, %.1f px sideways", dyPx, dxPx))
        }
        commitMove()

        // 358 — straight-line locks with a touch drag.
        let upDown = button("Up down only"), leftRight = button("Left right only")
        check("358", "Straight-line buttons are there by their spoken names", upDown.exists && leftRight.exists)
        upDown.tap(); sleep(1)
        check("358", "Up down only shows as selected when on", upDown.isSelected)
        if let a = probe() {
            dragLayer(dx: 60, dy: 40)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w, dy = (b.y - a.y) * b.h
                check("358", "Up down only: a diagonal drag moves only up/down",
                      abs(dx) < 0.6 && abs(dy) > 5, String(format: "%.1f px sideways, %.1f px down", dx, dy))
            }
        }
        upDown.tap(); sleep(1)
        check("358", "Tapping Up down only again turns it off", !upDown.isSelected)
        leftRight.tap(); sleep(1)
        if let a = probe() {
            dragLayer(dx: 60, dy: 40)
            if let b = probe() {
                let dx = (b.x - a.x) * b.w, dy = (b.y - a.y) * b.h
                check("358", "Left right only: a diagonal drag moves only sideways",
                      abs(dy) < 0.6 && abs(dx) > 5, String(format: "%.1f px sideways, %.1f px down", dx, dy))
            }
        }
        leftRight.tap(); sleep(1)
        check("358", "Left right only turns off again", !leftRight.isSelected)
        commitMove()
        snapshot("04-after"); audit("Move / Transform after drags")

        // 366 — 012 / A4 number fields: type the layer's center, no drag.
        func typeInto(_ spoken: String, _ text: String) -> Bool {
            let f = app.textFields[spoken]
            guard f.waitForExistence(timeout: 3) else { return false }
            f.tap()
            f.typeKey("a", modifierFlags: .command)
            f.typeText(text + "\n"); sleep(1)
            return true
        }
        check("366", "Position X, Position Y and Rotation degrees fields are there by name",
              app.textFields["Position X"].exists && app.textFields["Position Y"].exists
                && app.textFields["Rotation degrees"].exists)
        if typeInto("Position X", "100"), typeInto("Position Y", "200"), let p = probe() {
            check("366", "Typing X 100, Y 200 puts the layer's center there",
                  abs(p.x * p.w - 100) < 0.6 && abs(p.y * p.h - 200) < 0.6,
                  String(format: "center %.1f, %.1f px", p.x * p.w, p.y * p.h))
        }
        commitMove()
    }
}
#endif
