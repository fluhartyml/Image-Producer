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
    /// 015a: the palette footer's height at the default text size, read by testTextSizeIPad.
    nonisolated(unsafe) static var footerHeightAtDefault: CGFloat = 0
    var app: XCUIApplication!

    static let dir: URL = {
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ImageProducerUITestResults")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override func setUp() {
        continueAfterFailure = true
        // testDuoLook runs in whatever shape Claude set in Device Hub — don't turn the device for it.
        // So does the shakedown (testShakedownLayout): every shape is set by hand in Device Hub first.
        if !name.contains("testDuoLook") && !name.contains("testShakedownLayout") && !name.contains("testShapeChange") && !name.contains("testElementsA") && !name.contains("testKeyProbe") && !name.contains("testNameFieldIdle") { XCUIDevice.shared.orientation = .landscapeLeft }
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
        // 022 — a picture of each screen too, so a run on the iPhone Duo leaves screenshots.
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: Self.dir.appendingPathComponent("\(name).png"))
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
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'canvas.element'", label)).firstMatch
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
        press("Canvas Tool"); sleep(1); press("Move"); sleep(1)
    }

    /// Hardware-keyboard key, sent to the app (the A3 key-catcher), not to a text field.
    func key(_ k: String, _ flags: XCUIElement.KeyModifierFlags = []) {
        app.typeKey(k, modifierFlags: flags)
    }

    /// Launch screen → New Image → the editor (shared by the shakedown and the text-size check).
    func openNewImage(named name: String? = nil) {
        // Launch screen → New Image (the launch scene's own button; the system makes the file).
        // REM 16:3x (his "make the tests run faster without ruining quality"): wait for the launch screen, not a fixed 5 s.
        _ = button("New Image").waitForExistence(timeout: 15); snapshot("00-start")
        // REM: the launch scene and the document browser under it BOTH carry a "New Image"
        // button; the 18:24 run's firstMatch tapped the browser's and opened its Shared tab.
        // Take the launch scene's: the hittable one nearest the top.
        _ = button("New Image").waitForExistence(timeout: 15)
        snapshot("00-launch"); audit("Launch")
        // REM: a fresh simulator has no iCloud and its browser opened on Shared, so New Image
        // said "No location available to save" (18:38 run). Pick On My iPad first.
        if press("Browse", 5) {
            sleep(1)
            let onMyIPad = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPad' OR label == 'On My iPhone'")).firstMatch
            if onMyIPad.waitForExistence(timeout: 5) { onMyIPad.tap(); sleep(1) }
        }
        let candidates = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex
            .filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }
        if let launchButton = candidates.first { launchButton.tap() }
        else {
            // REM 2026-11-21 13:3x run (16e, after his Mac restart): the browser's On My iPhone page
            // covered the launch scene, so no "New Image" was hittable and nothing was tapped. Use the
            // browser's own Create Document cell, the same thing a person would tap there.
            let create = app.cells["Create Document"].firstMatch
            if create.waitForExistence(timeout: 3), create.isHittable {
                record("| — | ↻ FALLBACK | New Image covered; tapped Create Document |"); create.tap()
            }
        }
        // REM 16:3x — was sleep(3): wait for the name sheet (or the editor) instead.
        _ = app.buttons["Create"].waitForExistence(timeout: 3)
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
        // REM 2026-11-21 — shakedown rule 000.7 (his word): one project file per subsection, named for it.
        if let name, app.buttons["Create"].waitForExistence(timeout: 10) {
            let field = app.textFields["File name"].firstMatch
            // REM 2026-11-22 09:3x — 1 run in 2 the first Create tap missed on the open Duo: the sheet is still
            // sliding up for the keyboard when the test taps. Give it a beat (a finger sees where the button is).
            if field.exists { field.tap(); field.typeText(name); sleep(1) }
            else { record("| — | ℹ️ INFO | New Image sheet has no Name field; file keeps its automatic name |") }
        }
        if press("Create", 10) { sleep(2) }
        // REM 2026-11-22 A3 (open Duo) — the sheet stayed up with the name typed and the keyboard showing; the tap on
        // Create didn't take. Close the keyboard, then tap Create again, and say so in the results.
        if app.buttons["Create"].exists {
            if app.keyboards.firstMatch.exists { app.typeText("\n"); sleep(1) }
            if app.buttons["Create"].exists {
                record("| — | ↻ RETRY | Create tapped again after closing the keyboard |")
                app.buttons["Create"].firstMatch.tap(); sleep(2)
            }
        }
    }

    // MARK: The shakedown

    func testShakedownIPad() throws {
        record("Run: \(Date())  ·  iPad simulator  ·  -ImageProducerUITest (simulator only; his iPad untouched)")
        record("")

        openNewImage()
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
        let footer = app.staticTexts["Active color"].firstMatch
        Self.footerHeightAtDefault = footer.waitForExistence(timeout: 3) ? footer.frame.height : 0

        // A3 (364) — tool letters from a hardware keyboard pick tools.
        // Tap the canvas first so the key-catcher (not a field) has the keyboard.
        press("Canvas Tool"); sleep(1)
        for (letter, tool) in [("m", "Move"), ("b", "Paint Drop Bucket"), ("c", "Canvas Tool")] {
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

        // 013 — A5: the canvas is one VoiceOver element named "Canvas" (an image, not a button —
        // the "Canvas Tool" tile is the button).
        let canvasEl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'canvas.element' AND label == 'Canvas'")).firstMatch
        check("013", "The canvas is one element named Canvas", canvasEl.waitForExistence(timeout: 5))
        snapshot("05-canvas-element")

        // 014 — A6: pixel cursor. Pen, three Rights, Space twice → after the pause, ONE new
        // "(Pixel n)" layer (two presses close together are one stroke, one History step).
        press("Pixel Pen"); sleep(1)
        let before = probe()
        for _ in 0..<3 { app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: []) }
        app.typeKey(" ", modifierFlags: []); app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        sleep(3)
        if let b = before, let a = probe() {
            check("014", "Arrows + Space paint by keyboard: one stroke, one new pixel layer",
                  a.layers == b.layers + 1 && a.active.contains("(Pixel"),
                  "layers \(b.layers) → \(a.layers), active \(a.active)")
        } else {
            check("014", "Arrows + Space paint by keyboard: one stroke, one new pixel layer", false, "probe unreadable")
        }
        snapshot("06-pixel-cursor"); audit("Pixel Pen with cursor")

        // 015 — A7: walk every tool by its spoken name; each must become the selected tool.
        let tools = ["Canvas Tool", "Color Palette", "Move", "Selection", "Mask", "Paint Drop Bucket",
                     "Pixel Pen", "Eraser", "Eyedropper", "Text", "Symbol", "Image",
                     "Image Playground", "Layer", "Remove Background", "Magic Lasso", "Adjust",
                     "Camera"]  // no Zoom tool on iOS (his word 11-21)
        var missed: [String] = []
        for t in tools {
            let b = button(t)
            guard b.waitForExistence(timeout: 3) else { missed.append("\(t) (not found)"); continue }
            b.tap(); sleep(1)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); sleep(1)
            }
            if !button(t).isSelected { missed.append(t) }
        }
        check("015", "Every tool picked by its spoken name shows as selected (\(tools.count) tools)",
              missed.isEmpty, missed.isEmpty ? "all \(tools.count)" : "missed: \(missed.joined(separator: ", "))")
        audit("After the tool walk")

        // REM: 022, his word 11-05 08:1x: "yes iPad too" — the movable tool box on the iPad
        // (and the opened Duo, which runs these layouts). Float, drag, pick, dock.
        if press("Float tools", 5) {
            sleep(1)
            let grip = button("Dock tools")
            check("022", "Float tools turns the tool box into a floating palette",
                  grip.waitForExistence(timeout: 3) && button("Move").exists)
            let f0 = grip.frame
            let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 160, dy: 120)))
            sleep(1)
            let f1 = grip.frame
            check("022", "Dragging the grip moves the palette",
                  hypot(f1.minX - f0.minX, f1.minY - f0.minY) > 40,
                  String(format: "moved %.0f right, %.0f down", f1.minX - f0.minX, f1.minY - f0.minY))
            press("Eraser"); sleep(1)
            check("022", "A tool in the floating palette picks", button("Eraser").isSelected)
            snapshot("07-floating-tools")
            press("Dock tools"); sleep(1)
            check("022", "Dock tools puts it back under the canvas", button("Float tools").waitForExistence(timeout: 3))
        } else {
            check("022", "Float tools button is there by name", false)
        }
    }

    // 015a — A8: text follows the system text size. Runs after testShakedownIPad (alphabetical),
    // which measured the Color Palette's "Active color" line (18 pt) at the default size.
    /// Scale arrows (his 2026-11-05 "SOOOOOoooooo Slow"): one tap = 1 px; holding speeds up.
    func testScaleArrowHold() throws {
        openNewImage()
        press("Add a layer"); sleep(1)
        press("Paint Drop Bucket"); sleep(1); press("Fill Layer"); sleep(1)
        press("Move"); sleep(1)
        let field = app.textFields["Size in pixels"]
        guard field.waitForExistence(timeout: 5) else { check("383", "Size in pixels field found", false); return }
        func px() -> Int { Int((field.value as? String ?? "").filter(\.isNumber)) ?? -1 }
        let stepper = app.steppers["Scale"]
        let inc = stepper.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Increment'")).firstMatch
        guard inc.waitForExistence(timeout: 5) else {
            check("383", "Scale arrow found", false, app.steppers.allElementsBoundByIndex.map(\.label).joined(separator: ", ")); return
        }
        let start = px()
        inc.tap(); sleep(1)
        let afterTap = px()
        check("383", "One tap on the up arrow adds 1 px", afterTap - start == 1, "\(start) → \(afterTap)")
        inc.press(forDuration: 5); sleep(1)
        let afterHold = px()
        check("383", "Holding the up arrow 5 s speeds up past 1 px a step", afterHold - afterTap > 100,
              "\(afterTap) → \(afterHold) (+\(afterHold - afterTap))")
        snapshot("scale-hold")
    }

    func testTextSizeIPad() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        openNewImage()
        press("Color Palette"); sleep(1)
        let big = app.staticTexts["Active color"].firstMatch
        let h0 = Self.footerHeightAtDefault
        let h1 = big.waitForExistence(timeout: 5) ? big.frame.height : 0
        check("015a", "Text grows with the system text size (Accessibility Large)",
              h0 > 0 && h1 > h0 * 1.3, String(format: "\"Active color\" %.1f pt tall → %.1f pt", h0, h1))
        snapshot("07-larger-text"); audit("Color Palette at Accessibility Large")
    }

    // 022 — iPhone Duo, phone layout: on the Duo's narrow screen the system toolbar runs down
    // the right edge (iOS 27.1). Every tool in the one-line strip must still be reachable:
    // tap each in turn (the strip scrolls) and it must become the selected tool. A tool the
    // toolbar covered would take the tap on the toolbar instead, and fail here.
    func testPhoneLayout() throws {
        openNewImage()
        snapshot("p0-editor")
        let tools = ["Canvas Tool", "Color Palette", "Move", "Selection", "Mask", "Paint Drop Bucket",
                     "Pixel Pen", "Eraser", "Eyedropper", "Text", "Symbol", "Image",
                     "Image Playground", "Layer", "Remove Background", "Magic Lasso", "Adjust",
                     "Camera"]  // no Zoom tool on iOS (his word 11-21)
        var missed: [String] = []
        // The system toolbar's left edge (its Back button); without one, the window's right edge.
        let back = app.buttons["BackButton"].firstMatch
        let limit = back.exists ? back.frame.minX : app.windows.firstMatch.frame.maxX
        record("| — | ℹ️ INFO | Toolbar's left edge at x \(Int(limit)) of \(Int(app.windows.firstMatch.frame.width)) |")
        let strip = app.scrollViews.element(boundBy: 0)
        for t in tools {
            let b = button(t)
            guard b.waitForExistence(timeout: 3) else { missed.append("\(t) (not found)"); continue }
            // Swipe the strip the way a person would until the tool sits fully clear of the
            // toolbar. (isHittable throws for a tool not yet laid out, 21:18 run.)
            var tries = 0
            func clear() -> Bool { let f = b.frame; return f.width > 0 && f.minX >= 0 && f.maxX <= limit }
            // Short drags, either way — a full swipe flung tools past the left edge (21:42 run).
            func nudge(_ dx: CGFloat) {
                let from = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: 0)))
                sleep(1)
            }
            while !clear() && tries < 12 {
                let f = b.frame
                nudge(f.width > 0 && f.minX < 0 ? 120 : -120); tries += 1
            }
            if !clear() { missed.append("\(t) (stays under the toolbar, x \(Int(b.frame.minX))–\(Int(b.frame.maxX)))"); continue }
            b.tap(); sleep(1)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); sleep(1)
            }
            if !button(t).isSelected { missed.append(t) }
        }
        snapshot("p1-strip-end")
        // 022 — the detachable palette: float it (the grip is a button too), look, dock it.
        if press("Float tools", 3) {
            sleep(1); snapshot("p2-floating")
            check("022", "Tools float as a glass palette and stay pickable",
                  button("Camera").exists && button("Dock tools").exists)
            press("Dock tools", 3); sleep(1)
        } else {
            check("022", "Tools float as a glass palette and stay pickable", false, "no Float tools button")
        }
        check("022", "Phone layout: every tool in the strip can be tapped and selected (\(tools.count))",
              missed.isEmpty, missed.isEmpty ? "all \(tools.count)" : "missed: \(missed.joined(separator: ", "))")
    }

    // REM 2026-11-21 — 433 FEEDBACK INSPECTION on the iPhone 16e simulator, portrait (his 13
    // TestFlight notes were all on his 16e). His word: "go ahead code please and inspect the
    // product". A picture of every tool's inspector, plus the two bugs: the keyboard that never
    // rose in the Image Playground / Text boxes, and the floating preview that couldn't be moved.
    func testPhoneInspectors() throws {
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        openNewImage()
        let tools = ["Canvas Tool", "Color Palette", "Move", "Selection", "Mask", "Paint Drop Bucket",
                     "Pixel Pen", "Eraser", "Eyedropper", "Text", "Symbol", "Image",
                     "Image Playground", "Layer", "Remove Background", "Magic Lasso", "Adjust",
                     "Camera"]  // no Zoom tool on iOS (his word 11-21)
        let strip = app.scrollViews.element(boundBy: 0)
        let limit = app.windows.firstMatch.frame.maxX
        for (i, t) in tools.enumerated() {
            let b = button(t)
            guard b.waitForExistence(timeout: 3) else { record("| — | ❌ FAIL | \(t): tool not found |"); continue }
            var tries = 0
            func clear() -> Bool { let f = b.frame; return f.width > 0 && f.minX >= 0 && f.maxX <= limit }
            while !clear() && tries < 12 {
                let f = b.frame
                let from = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: f.width > 0 && f.minX < 0 ? 120 : -120, dy: 0)))
                sleep(1); tries += 1
            }
            b.tap(); sleep(2)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                snapshot(String(format: "i%02d-%@-alert", i, t.replacingOccurrences(of: " ", with: "-")))
                app.alerts.firstMatch.buttons.firstMatch.tap(); sleep(1)
            }
            snapshot(String(format: "i%02d-%@", i, t.replacingOccurrences(of: " ", with: "-")))
            // Name once: the tool's name should not also appear as a title inside its inspector.
            let named = app.staticTexts.matching(NSPredicate(format: "label == %@", t)).count
            record("| — | ℹ️ INFO | \(t): \(named) text label(s) reading \"\(t)\" on screen |")

            if t == "Text" || t == "Image Playground" {
                let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
                if field.waitForExistence(timeout: 3) {
                    field.tap(); sleep(2)
                    snapshot(String(format: "i%02d-%@-typing", i, t.replacingOccurrences(of: " ", with: "-")))
                    // His word 11-21: "fix the preview covering the back button" — it steps aside while typing.
                    check("11-21", "\(t): the preview is out of the way while the keyboard is up",
                          !app.descendants(matching: .any)["pip.panel"].firstMatch.exists)
                    check("433#2", "\(t): tapping the text box brings up the keyboard",
                          app.keyboards.firstMatch.exists, "keyboards on screen: \(app.keyboards.count)")
                    app.typeText("x"); sleep(1)
                    let v = (field.value as? String) ?? ""
                    check("433#2", "\(t): typing reaches the box", v.contains("x"), "box reads \"\(v)\"")
                    if app.keyboards.firstMatch.exists { app.keyboards.buttons["Return"].firstMatch.tap(); sleep(1) }
                } else {
                    record("| — | ℹ️ INFO | \(t): no text box on screen (needs a layer or Apple Intelligence) |")
                }
            }
        }

        // His word 11-21: "ios devices dont need a zoom toolbox tool if the pinch zoom pan is native".
        check("11-21", "No Zoom tool in the iOS toolbox", !button("Zoom").exists)

        // 433 #2 — the floating preview moves. His word 11-21: "yes long press to move the pip".
        // Hold anywhere on it, then drag: at 1× and again zoomed in (his note: zoomed in, a touch on
        // it only panned the canvas). Then the handle tap still sends it to the next corner.
        let pip = app.descendants(matching: .any)["pip.panel"].firstMatch
        let window = app.windows.firstMatch
        func longPressMove(_ label: String) {
            guard pip.waitForExistence(timeout: 3) else { check("433#2", "\(label): preview found", false); return }
            let f0 = pip.frame
            // Drag toward the corner diagonally opposite where it sits.
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: f0.midX < window.frame.midX ? 0.85 : 0.15,
                                                                       dy: f0.midY < window.frame.midY ? 0.45 : 0.1))
            pip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.8, thenDragTo: to)
            sleep(1)
            let f1 = pip.frame
            check("433#2", "\(label): long press + drag moves the preview",
                  hypot(f1.midX - f0.midX, f1.midY - f0.midY) > 80,
                  String(format: "moved %.0f across, %.0f down", f1.midX - f0.midX, f1.midY - f0.midY))
            check("433#2", "\(label): the preview stays fully on screen",
                  f1.minX >= 0 && f1.maxX <= window.frame.maxX && f1.minY >= 0,
                  String(format: "x %.0f–%.0f, y %.0f", f1.minX, f1.maxX, f1.minY))
        }
        press("Canvas Tool"); sleep(1)
        snapshot("i98-preview-before")
        longPressMove("At 1×")
        snapshot("i98-preview-moved-1x")
        let canvasEl = app.descendants(matching: .any)["uitest.canvas"].firstMatch
        if canvasEl.waitForExistence(timeout: 3) { canvasEl.pinch(withScale: 3, velocity: 2); sleep(1) }
        snapshot("i98-zoomed")
        longPressMove("Zoomed in")
        snapshot("i99-preview-moved-zoomed")
        // His word 11-21: "fix the preview covering the back button" — park it top-left, check it
        // sits below the toolbar.
        if pip.waitForExistence(timeout: 3) {
            pip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.8, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.02)))
            sleep(1)
            snapshot("i99-preview-top-left")
            let back = app.buttons["BackButton"].firstMatch
            let backBottom = back.exists ? back.frame.maxY : 0
            check("11-21", "Top-left, the preview sits below the Back button",
                  back.exists && pip.frame.minY >= backBottom,
                  String(format: "preview top %.0f, Back bottom %.0f%@", pip.frame.minY, backBottom, back.exists ? "" : " (Back not found)"))
        }
        let grip = app.buttons["Move preview"].firstMatch
        if grip.waitForExistence(timeout: 3) {
            let f0 = grip.frame
            grip.tap(); sleep(1)
            let f1 = grip.frame
            check("433#2", "Tapping the handle sends it to the next corner",
                  hypot(f1.midX - f0.midX, f1.midY - f0.midY) > 40,
                  String(format: "moved %.0f across, %.0f down", f1.midX - f0.midX, f1.midY - f0.midY))
        } else {
            check("433#2", "The floating preview's Move preview handle is there", false)
        }
    }

    // REM 2026-11-21 — 438: the Floating Preview switch left the Canvas page for Settings. His word:
    // "move the PiP toggle to settings", then "test 438 in the 16e simulator". Checks the Canvas page
    // has no switch, the Settings app has it, and turning it off there hides the preview.
    // REM 2026-11-21 — his word: "fix the plasma glow intensity bug". Seen 11-20 on the Mac (build 430):
    // switching Neon → Plasma dropped Intensity 1.00× → 0.13× unasked. Reproduce before touching code.
    func testGlowStyleKeepsIntensity() throws {
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        openNewImage()
        // A new image has no layer selected ("Select a layer to use these effects") — add one first.
        app.buttons["Layers"].firstMatch.tap(); sleep(1)
        check("glow", "Add a layer button is there", press("Add a layer")); sleep(1)
        app.buttons["Tool"].firstMatch.tap(); sleep(1)
        press("Layer"); sleep(2)
        func find(_ e: XCUIElement) -> Bool {
            var n = 0
            // REM 16:0x run: app.swipeUp() landed on the canvas and panned it; scroll the inspector panel itself.
            while !(e.exists && e.isHittable) && n < 8 {
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.92))
                from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.72)))
                sleep(1); n += 1
            }
            return e.exists && e.isHittable
        }
        let glowRow = app.staticTexts["Glow"].firstMatch
        check("glow", "Glow section is on the Layer page", find(glowRow))
        glowRow.tap(); sleep(1)
        let toggle = app.switches["Glow this layer"].firstMatch
        check("glow", "Glow switch is there", find(toggle))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); sleep(1)
        let slider = app.sliders["Intensity"].firstMatch
        // REM 16:1x run: scrolling down to the slider pushed the style buttons off the top. Its value reads without scrolling.
        check("glow", "Intensity slider is there", slider.waitForExistence(timeout: 3))
        let before = (slider.value as? String) ?? "nil"
        snapshot("g01-neon")
        let plasma = app.buttons["Plasma Glow"].firstMatch
        check("glow", "Plasma Glow button is there", find(plasma))
        plasma.tap(); sleep(1)
        let after = (slider.value as? String) ?? "nil"
        snapshot("g02-plasma")
        app.screenshot().attach(self, "g02-plasma")
        check("glow", "Neon → Plasma keeps Intensity", before == after, "before \(before), after \(after)")
        app.buttons["Neon Glow"].firstMatch.tap(); sleep(1)
        let back = (slider.value as? String) ?? "nil"
        check("glow", "Plasma → Neon keeps Intensity", back == before, "before \(before), back \(back)")
    }

    // REM 2026-11-21 18:3x — his Duo feedback on 439: "What the fuck dude the tool box is scrolling and the layers
    // tool inspector and history are no where to be found" (landscape, "because portrait is worse"). His rulings:
    // two rows of tools, never scrolling (Oct 04, build 249), then Tool | Layers | History (Nov 19). He watches
    // this run in Device Hub: it opens an image on its side, picks the Layer tool, and holds so the layout shows.
    // REM 18:5x his word: "reuse this test for every duo orientation as a proof of concept". The test no longer
    // turns the device: Claude sets each shape in Device Hub (Closed / Open, Rotate Right) and runs it once per shape.
    func testDuoLook() throws {
        openNewImage()
        press("Layer"); sleep(2)
        let shape = (ProcessInfo.processInfo.environment["DUO_SHAPE"] ?? "")
        let w = app.windows.firstMatch.frame.size
        record("| duo | — | Shape \(shape): window \(Int(w.width)) × \(Int(w.height)) |")
        app.screenshot().attach(self, "duo-\(shape)")
        // The three must sit together as ONE switch: the Layers and History buttons in the top bar
        // don't count (the 18:3x before-run passed Layers/History on those alone).
        let tool = app.buttons["Tool"].firstMatch
        check("duo", "Tool | Layers | History switch shows", tool.exists && {
            let row = tool.frame.midY
            let inRow = { (n: String) in self.app.buttons.matching(identifier: n).allElementsBoundByIndex.contains { abs($0.frame.midY - row) < 8 } }
            return inRow("Layers") && inRow("History")
        }())
        check("duo", "Every tool is on screen (no scrolling)", button("Camera").exists && button("Camera").isHittable)
        sleep(15)   // hold so he can look
    }

    // REM 2026-11-21 — THE SHAKEDOWN (Workshop/Image-Producer-Shakedown-Amber-Sheet.html in the apartment).
    // His word: "lets start the amber roadmap of your shake down for image producer". This is the layout pass,
    // L1–L7, run once per device shape. Claude sets the shape in Device Hub; SHAPE_CODE (e.g. "A1") names the
    // subsection and its project file (rule 000.7). His rules it checks: 000.8 a real photo, never clear pixels ·
    // 000.11 every control at least 44 × 44 points, never covered · 000.12 every tab · his Oct 4 ruling, two rows
    // of tools, no scrolling · "the lable of eacj tool inspector should be listed only once" (11-21).
    /// L2's photo step (000.8), shared by the shape checks and A6: Image tool → Import → "Shakedown Photo 1".
    func placeShakedownPhoto(_ code: String) -> Bool {
        press("Image")
        // REM 16:3x — was sleep(2): wait for the Image page's Import button.
        _ = app.buttons["Import Image to New Layer…"].firstMatch.waitForExistence(timeout: 3)
        // REM 2026-11-22 A3 — the open Duo's new image came up on the Layers tab, so Import was never on screen.
        // Open the Tool tab first, the way a person would.
        if !app.buttons["Import Image to New Layer…"].firstMatch.exists {
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
        }
        var placed = false
        if press("Import Image to New Layer…", 5) {
            // REM 16:3x — was sleep(3): wait for the Files picker itself.
            _ = app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.waitForExistence(timeout: 4)
            snapshot("\(code)-L2-picker")
            let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Shakedown Photo 1'")).firstMatch
            if !photo.waitForExistence(timeout: 5) {
                // The picker may open on Recents: Browse → On My iPhone → Image Producer.
                if press("Browse", 3) { sleep(1) }
                let onMy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPhone'")).firstMatch
                if onMy.waitForExistence(timeout: 3) { onMy.tap(); sleep(1) }
                let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Image Producer'")).firstMatch
                if folder.waitForExistence(timeout: 3) { folder.tap(); sleep(1) }
            }
            snapshot("\(code)-L2-picker-folder")
            // REM 13:0x idle probe: the folder filled up with shakedown project files, so the photo sat
            // below the screen and was never found. Scroll the picker until it shows.
            var swipes = 0
            while !(photo.exists && photo.isHittable) && swipes < 6 {
                app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.swipeUp(); sleep(1); swipes += 1
            }
            // REM 16:3x — was sleep(4): wait until the canvas reports an active layer (the photo landed), 8 s at most.
            if photo.waitForExistence(timeout: 5) { photo.tap(); _ = probeElement.waitForExistence(timeout: 8); sleep(1); placed = true }
            // REM 20:3x A1 run: the picker never found the photo and stayed open over the editor, so every
            // later check read nothing. If the photo wasn't picked, close the picker before going on.
            if !placed {
                for n in ["Cancel", "Close"] where app.buttons[n].firstMatch.exists { app.buttons[n].firstMatch.tap(); sleep(1); break }
            }
        }
        return placed
    }

    func testShakedownLayout() throws {
        let env = ProcessInfo.processInfo.environment
        let code = env["SHAPE_CODE"] ?? "X"
        let shapeName = env["SHAPE_NAME"] ?? "unnamed shape"
        let win = app.windows.firstMatch
        record("| \(code) | — | \(shapeName): window \(Int(win.frame.width)) × \(Int(win.frame.height)) |")

        // Buttons smaller than Apple's 44 × 44 touch minimum, on whatever is on screen now (000.11).
        let tools: [(String, String)] = [("Canvas Tool", "Canvas"), ("Color Palette", "Color Palette"), ("Move", "Move / Transform"),
            ("Selection", "Selection"), ("Mask", "Mask"), ("Paint Drop Bucket", "Paint Drop / Bucket"), ("Pixel Pen", "Pen (Pixels)"),
            ("Eraser", "Eraser"), ("Eyedropper", "Eyedropper"), ("Text", "Text"), ("Symbol", "Symbol"), ("Image", "Image"),
            ("Image Playground", "Image Playground"), ("Layer", "Layer"), ("Remove Background", "Remove Background"),
            ("Magic Lasso", "Magic Lasso"), ("Adjust", "Adjust"), ("Camera", "Camera")]
        func small(_ where_: String) -> [String] {
            // REM 2026-11-21 21:5x — Apple's own controls (the system toolbar, the segmented switch, List's reorder
            // grip) are Apple's components, sized by Apple: not counted here. The toolbox's tool buttons have their
            // own check (L3), so they're not repeated on every page.
            // REM 2026-11-22 — Apple's Stepper (its − / + halves) joins the exempt Apple components.
            let system = (app.toolbars.buttons.allElementsBoundByIndex + app.segmentedControls.buttons.allElementsBoundByIndex
                          + app.steppers.buttons.allElementsBoundByIndex
                          // Apple's document title menu in the navigation bar ("Untitled 15 ⌄").
                          + app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.frame.minY < 90 })
                .map(\.frame)
            let toolLabels = Set(tools.map(\.0))
            let browse = app.otherElements["Browse View"].firstMatch
            return app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.compactMap { b in
                let f = b.frame
                // REM 2026-11-22 A5 — Apple's document browser ("Browse View": Icons, More, Search, 40 × 40) is Apple's
                // component, sized by Apple — exempt like the toolbar and Stepper above.
                guard !system.contains(f), !b.label.hasPrefix("Reorder"), !toolLabels.contains(b.label),
                      !(browse.exists && browse.frame.contains(f)) else { return nil }
                // REM 2026-11-22 — measured to the nearest point: a 44-pt target lands at 43.7 after pixel rounding
                // on a 3× screen, and that is still Apple's 44.
                guard f.width > 0, f.height > 0, f.width.rounded() < 44 || f.height.rounded() < 44 else { return nil }
                let n = b.label.isEmpty ? b.identifier : b.label
                return "\(n.isEmpty ? "?" : n) \(Int(f.width))×\(Int(f.height))"
            }
        }
        // Text cut off at the window's edge.
        func offEdge() -> [String] {
            let w = win.frame
            return app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.compactMap { t in
                let f = t.frame
                guard f.width > 0, f.minX < w.minX - 1 || f.maxX > w.maxX + 1 else { return nil }
                return "\"\(t.label.prefix(30))\""
            }
        }

        // A3–A5 "nothing important sits across the fold" (sheet). SHAPE_FOLD = "x" (a vertical hinge at the window's
        // middle) or "y" (horizontal). A button, field or line of text straddling the fold by more than 6 pt on each
        // side fails; the canvas and whole-width containers are not "important" single things.
        let fold = env["SHAPE_FOLD"] ?? ""
        func acrossFold() -> [String] {
            guard fold == "x" || fold == "y" else { return [] }
            let w = win.frame, line = fold == "x" ? w.midX : w.midY
            let els = app.buttons.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex
                + app.staticTexts.allElementsBoundByIndex + app.sliders.allElementsBoundByIndex
            // Only what a person can see and touch: the launch scene's buttons stay in the tree behind the editor.
            return els.filter { $0.exists && $0.isHittable && $0.frame.width > 0 && $0.identifier != "canvas.element" }.compactMap { e in
                let f = e.frame
                let (lo, hi, span) = fold == "x" ? (f.minX, f.maxX, w.width) : (f.minY, f.maxY, w.height)
                guard lo < line - 6, hi > line + 6, hi - lo < span * 0.9 else { return nil }
                // His ruling 11-22: "how about the spine lables fall inside the fold" — the spine belongs there.
                if e.elementType == .staticText, f.height > f.width * 1.5 { return nil }
                return "\(e.label.isEmpty ? e.identifier : String(e.label.prefix(30)))"
            }
        }
        func checkFold(_ where_: String) {
            guard !fold.isEmpty else { return }
            let x = acrossFold()
            check(code, "Fold \(where_): nothing sits across the fold", x.isEmpty, x.joined(separator: ", "))
        }

        // L1 — the launch screen.
        sleep(5)
        // REM 2026-11-22 A2 — held sideways, Apple's own document browser covers the launch title page and its
        // "Create Document" tile is the way in (Apple's component, HIG). Either path counts as "New Image".
        let launchNew = app.descendants(matching: .any).matching(NSPredicate(format: "(elementType == %d AND label == 'New Image') OR (elementType == %d AND label == 'Create Document')",
                XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue)).allElementsBoundByIndex
            // REM 2026-11-22 A2 — the Create Document cell reports not-hittable while it is plainly on screen (and L2
            // taps through it fine); count it when it exists inside the window.
            .filter { $0.isHittable || ($0.exists && win.frame.contains($0.frame)) }.sorted { $0.frame.minY < $1.frame.minY }.first
        snapshot("\(code)-L1-launch")
        check(code, "L1 Launch: New Image is on screen and tappable", launchNew != nil)
        let l1small = small("launch")
        check(code, "L1 Launch: every button is at least 44 × 44", l1small.isEmpty, l1small.joined(separator: ", "))
        let l1cut = offEdge()
        check(code, "L1 Launch: no text cut off at the edge", l1cut.isEmpty, l1cut.joined(separator: ", "))
        checkFold("launch")

        // L2 — a new image in its own named project, with a real photo on a layer.
        openNewImage(named: "\(code) \(shapeName)")
        snapshot("\(code)-L2-new")
        // REM 2026-11-22 — HIS REPORT on 451, real Duo: the title stayed "Untitled" until he tapped the canvas, then
        // became the name he typed; and the image did not open on the Canvas tool's page. Both read with NO touch.
        let typed = "\(code) \(shapeName)"
        let titled = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", typed)).firstMatch
        let titleShown = titled.waitForExistence(timeout: 6)
        let untitled = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Untitled'")).firstMatch
        check(code, "L2 The title shows the typed name without a tap", titleShown && !untitled.exists,
              titleShown ? (untitled.exists ? "\"\(untitled.label)\" still on screen" : "") : "no \"\(typed)\" on screen")
        let toolTab = app.buttons["Tool"].firstMatch
        check(code, "L2 A new image opens on the Canvas tool's page", !toolTab.exists || toolTab.isSelected,
              "panel shows \(["Layers", "History"].first { app.buttons[$0].firstMatch.isSelected } ?? "?")")
        // Short run for a single bug: SHAPE_STOP_AFTER_NEW=1 stops here.
        if !(env["SHAPE_STOP_AFTER_NEW"] ?? "").isEmpty { snapshot("\(code)-L2-stop"); return }
        check(code, "L2 The editor opened", app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 10))
        let placed = placeShakedownPhoto(code)
        let afterPhoto = probe()
        snapshot("\(code)-L2-photo")
        check(code, "L2 A real photo is placed on a layer (000.8)", placed && (afterPhoto?.layers ?? 0) >= 1,
              "layers \(afterPhoto?.layers ?? -1), active \(afterPhoto?.active ?? "?")")
        let pip = app.descendants(matching: .any)["pip.panel"].firstMatch
        let back = app.buttons["BackButton"].firstMatch
        if pip.exists, back.exists {
            check(code, "L2 The floating preview stays clear of the Back button", !pip.frame.intersects(back.frame),
                  String(format: "preview %.0f,%.0f %.0f×%.0f · Back %.0f,%.0f", pip.frame.minX, pip.frame.minY, pip.frame.width, pip.frame.height, back.frame.minX, back.frame.minY))
        }

        // L3 — the toolbox: two rows, no scrolling, every tool on screen.
        var offScreen: [String] = [], rows = Set<Int>(), toolSizes = Set<String>()
        for (t, _) in tools {
            let b = button(t)
            guard b.waitForExistence(timeout: 3), b.isHittable, win.frame.contains(b.frame) else { offScreen.append(t); continue }
            rows.insert(Int(b.frame.midY.rounded()))
            toolSizes.insert("\(Int(b.frame.width.rounded()))×\(Int(b.frame.height.rounded()))")
        }
        snapshot("\(code)-L3-toolbox")
        check(code, "L3 Every tool is on screen without scrolling", offScreen.isEmpty, offScreen.joined(separator: ", "))
        check(code, "L3 Tools sit in two rows", rows.count == 2, "\(rows.count) row(s)")
        // REM 2026-11-22 09:1x — HIS RULING on the 37–38 pt wide tools: "it cant afford to get shorter why three
        // rows? ... two rows on the screen right now loks good". Two rows win over Apple's 44 pt WIDTH (9 tools in
        // ~340 pt can't be 44 wide), so width only has to stay at today's 37 pt or more; height still must be 44.
        check(code, "L3 Tool buttons are 44 tall, ≥ 37 wide (two rows, his ruling 11-22)", toolSizes.allSatisfy { s in
                  let p = s.split(separator: "×").map { Int($0) ?? 0 }; return p.count == 2 && p[0] >= 37 && p[1] >= 44 },
              toolSizes.sorted().joined(separator: ", "))

        // L4 — the Tool | Layers | History switch, every tab (000.12).
        let tabTool = app.buttons["Tool"].firstMatch
        let row = tabTool.frame.midY
        let tabsTogether = tabTool.exists && ["Layers", "History"].allSatisfy { n in
            app.buttons.matching(identifier: n).allElementsBoundByIndex.contains { abs($0.frame.midY - row) < 8 } }
        check(code, "L4 Tool | Layers | History sit together as one switch", tabsTogether)
        for tab in ["Layers", "History", "Tool"] {
            let b = app.buttons.matching(identifier: tab).allElementsBoundByIndex.first { abs($0.frame.midY - row) < 8 }
            b?.tap(); sleep(1)
            snapshot("\(code)-L4-\(tab)")
            check(code, "L4 \(tab) tab opens", b?.isSelected ?? false)
            let s = small(tab), cut = offEdge()
            check(code, "L4 \(tab) tab: every button at least 44 × 44", s.isEmpty, s.joined(separator: ", "))
            check(code, "L4 \(tab) tab: no text cut off", cut.isEmpty, cut.joined(separator: ", "))
            checkFold("\(tab) tab")
        }

        // L5 + L6 — every tool's page: opens, nothing cut off, name once, controls a finger can use.
        for (i, (t, title)) in tools.enumerated() {
            guard press(t, 3) else { check(code, "L5 \(title): tool button found", false); continue }
            sleep(2)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                snapshot(String(format: "%@-L5-%02d-%@-alert", code, i, t.replacingOccurrences(of: " ", with: "-")))
                app.alerts.firstMatch.buttons.firstMatch.tap(); sleep(1)
            }
            snapshot(String(format: "%@-L5-%02d-%@", code, i, t.replacingOccurrences(of: " ", with: "-")))
            // A button that DOES the tool's job ("Remove Background") is an action, not a second title:
            // count only text that isn't a button's own caption.
            let buttonFrames = app.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.map(\.frame)
            let named = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
                .filter { t in !buttonFrames.contains { $0.intersects(t.frame) } }.count
            check(code, "L5 \(title): name shown once", named <= 1, "\(named) times")
            let cut = offEdge(), s = small(title)
            check(code, "L5 \(title): no text cut off", cut.isEmpty, cut.joined(separator: ", "))
            check(code, "L5 \(title): every button at least 44 × 44", s.isEmpty, s.joined(separator: ", "))
            checkFold(title)
            // L6 — "The tool inspector is too narrow to work in" (his 439 feedback): sliders and fields need room.
            let narrow = (app.sliders.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex)
                // REM 2026-11-22 — a number field (Canvas W/H) hugs its number by his 10-11 design; the 120 bar
                // is for sliders and text you type words into.
                .filter { $0.exists && $0.isHittable && $0.frame.width < 120
                          && !(($0.value as? String).map { !$0.isEmpty && $0.filter { $0 != "," }.allSatisfy(\.isNumber) } ?? false) }
                .map { "\($0.label.isEmpty ? $0.identifier : $0.label) \(Int($0.frame.width)) wide" }
            check(code, "L6 \(title): sliders and fields at least 120 wide", narrow.isEmpty, narrow.joined(separator: ", "))
            // REM 2026-11-21 21:2x — his word on the Duo: "that lable 'immage' is supposed to be a spine from bottom
            // of the frame to the top" · "that horizontal lable takes up too much realestate". The name must run
            // vertically (taller than wide), and no horizontal copy of it may sit on the page.
            let nameEls = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType != %d", title,
                                                                              XCUIElement.ElementType.button.rawValue))
                .allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 0 && !buttonFrames.contains($0.frame) }
            let spine = nameEls.contains { $0.frame.height > $0.frame.width }
            let flat = nameEls.filter { $0.frame.width > $0.frame.height && $0.elementType == .staticText }
            check(code, "L6 \(title): name is a vertical spine on the left", spine,
                  nameEls.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" }.joined(separator: ", "))
            check(code, "L6 \(title): no horizontal title", flat.isEmpty, "\(flat.count) horizontal")
            // REM 2026-11-22 — his word on A2: "canvas spine bleads off the frame". The spine stays in its own page.
            let canvasFrame = app.descendants(matching: .any)["canvas.element"].firstMatch.frame
            let bleed = nameEls.filter { $0.frame.height > $0.frame.width && $0.frame.intersection(canvasFrame).width > 1 }
            check(code, "L6 \(title): spine stays off the canvas", bleed.isEmpty,
                  bleed.map { String(format: "spine x %.0f–%.0f, canvas ends %.0f", $0.frame.minX, $0.frame.maxX, canvasFrame.maxX) }.joined())
            // His word: "that scroll area is TOO SMALL" — the tool page's scroll area needs real room.
            let panelBottom = app.segmentedControls["Panel"].firstMatch.exists ? app.segmentedControls["Panel"].firstMatch.frame.maxY : 0
            let pageHeight = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.frame.minY >= panelBottom - 1 }
                .map(\.frame.height).max() ?? 0
            check(code, "L6 \(title): tool page at least 120 tall", pageHeight >= 120, "\(Int(pageHeight)) tall")
            audit("\(code) \(title)")
        }

        // L7 — draw, leave the project, reopen it: the work is all there.
        let before = probe()
        press("Pixel Pen", 3); sleep(1)
        let canvasEl = app.descendants(matching: .any)["uitest.canvas"].firstMatch
        if canvasEl.exists { canvasEl.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap(); sleep(2) }
        let drawn = probe()
        check(code, "L7 Drawing adds to the project", (drawn?.layers ?? 0) > (before?.layers ?? 0),
              "layers \(before?.layers ?? -1) → \(drawn?.layers ?? -1)")
        sleep(3)   // autosave runs 1.5 s after the last edit
        if back.exists { back.tap(); sleep(3) }
        snapshot("\(code)-L7-browser")
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(code) ")).firstMatch
        // REM 2026-11-21 21:5x — the browser lists many files; the project can sit below the fold. Scroll for it.
        let fileView = app.collectionViews["File View"].firstMatch
        // REM 2026-11-22 — the 07:00 run: the file WAS saved, but the browser opened scrolled down and "A1 …" sorts
        // to the top; swiping up only went further away. Look toward the top first, then down.
        for _ in 0..<4 where !(file.exists && file.isHittable) && fileView.exists { fileView.swipeDown(); sleep(1) }
        for _ in 0..<4 where !(file.exists && file.isHittable) && fileView.exists { fileView.swipeUp(); sleep(1) }
        if file.waitForExistence(timeout: 4) { file.tap(); sleep(4) }
        // REM 20:5x A1 run: a reopened project has no layer selected, and probe() only reads with one
        // selected — read the layer count straight off the canvas probe instead.
        var reopened: Probe? = nil
        let anyProbe = app.descendants(matching: .any)["uitest.canvas"].firstMatch
        if anyProbe.waitForExistence(timeout: 8), let r = anyProbe.label.range(of: "layers=") {
            var p = Probe(); p.layers = Int(anyProbe.label[r.upperBound...].prefix { $0.isNumber }) ?? -1; reopened = p
        }
        snapshot("\(code)-L7-reopened")
        check(code, "L7 Reopened project has the same layers", reopened != nil && reopened?.layers == drawn?.layers,
              "before \(drawn?.layers ?? -1), after \(reopened?.layers ?? -1)")
    }

    // MARK: A6 — changing shape with a picture open
    // REM 2026-11-22 09:5x — his word: "keep going with A6". Sheet line A-006: "Fold, unfold and turn with a picture
    // open: same picture, same tool, same layer, nothing lost." XCUITest can turn the phone but can't fold it, so the
    // runner (Workshop/shakedown/a6.sh) presses Device Hub's Closed / Open / Rotate Right, one per "READY n" line
    // written here; the test waits for the window to change, then checks nothing was lost.
    func testShapeChange() throws {
        let code = "A6"
        let win = app.windows.firstMatch
        record("| \(code) | — | Changing shape: starts \(Int(win.frame.width)) × \(Int(win.frame.height)) |")
        openNewImage(named: "A6 Duo changing shape")
        check(code, "The editor opened", app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 10))
        let placed = placeShakedownPhoto(code)
        check(code, "A real photo is placed on a layer (000.8)", placed)
        press("Pixel Pen"); sleep(1)
        let tool = app.buttons["Pixel Pen"].firstMatch
        guard let before = probe() else { check(code, "Canvas state readable", false); return }
        check(code, "Pixel Pen is the active tool before the change", tool.isSelected)
        for (n, what) in ["folded closed", "opened again", "turned"].enumerated() {
            let size0 = win.frame.size
            record("| \(code) | — | READY \(n + 1) \(what) |")
            var changed = false
            for _ in 0..<60 { sleep(1); if win.frame.size != size0 { changed = true; break } }
            sleep(3)
            snapshot("\(code)-\(n + 1)-\(what.replacingOccurrences(of: " ", with: "-"))")
            check(code, "The window changed shape when \(what)", changed,
                  "\(Int(size0.width))×\(Int(size0.height)) → \(Int(win.frame.width))×\(Int(win.frame.height))")
            let after = probe()
            check(code, "\(what): same picture (canvas \(Int(before.w))×\(Int(before.h)))", after?.w == before.w && after?.h == before.h,
                  "\(Int(after?.w ?? -1))×\(Int(after?.h ?? -1))")
            check(code, "\(what): same layers (\(before.layers))", after?.layers == before.layers, "\(after?.layers ?? -1)")
            check(code, "\(what): same active layer (\(before.active))", after?.active == before.active, after?.active ?? "?")
            let t = app.buttons["Pixel Pen"].firstMatch
            check(code, "\(what): Pixel Pen is still the active tool", t.waitForExistence(timeout: 3) && t.isSelected)
        }
        record("| \(code) | — | DONE |")
    }

    // MARK: A7 — every element, in section A's element shape (Duo closed, upright). Sheet rule 000.14 (his yes 11-21):
    // each section's element list runs once per device, in that section's element shape. ELEMENTS picks the lines
    // to run ("101,102,103"); empty runs all that are written. Claude presses Device Hub's Closed button first.

    /// Clear a text field and type a value; Tab moves on so a number field commits (a person would do the same).
    func setField(_ f: XCUIElement, _ value: String) {
        // A tap right after a menu closes can be swallowed: tap until the field has the keyboard (A-102, 11-22).
        for _ in 0..<3 {
            f.tap(); sleep(1)
            if (f.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
        }
        let old = (f.value as? String) ?? ""
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(old.count, 8)) + value)
        sleep(1)
    }

    /// The canvas size in pixels from the probe, blank images included (probe() skips a canvas with no layer).
    func canvasSize() -> (w: Int, h: Int) {
        let e = app.descendants(matching: .any)["uitest.canvas"].firstMatch
        guard e.waitForExistence(timeout: 5) else { return (-1, -1) }
        func num(_ k: String) -> Int {
            guard let r = e.label.range(of: "\(k)=") else { return -1 }
            return Int(Double(e.label[r.upperBound...].prefix { "0123456789.".contains($0) }) ?? -1)
        }
        return (num("w"), num("h"))
    }

    func testElementsA() throws {
        let env = ProcessInfo.processInfo.environment
        let want = Set((env["ELEMENTS"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        func runs(_ n: String) -> Bool { want.isEmpty || want.contains(n) }
        // His 11:07 screen: A6's turns left the Duo upside down. Section A's element shape is closed UPRIGHT.
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        let win = app.windows.firstMatch
        record("| A7 | — | Element shape (Duo closed upright): window \(Int(win.frame.width)) × \(Int(win.frame.height)) |")
        // REM 16:3x — was sleep(5): wait for the launch screen.
        _ = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).firstMatch.waitForExistence(timeout: 10)

        // A-101 — launch screen: New Image, New from Import… (Files picker; Cancel makes nothing), icon, version line.
        if runs("101") {
            let new = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex.filter(\.isHittable)
            check("A-101", "New Image is on the launch screen", !new.isEmpty)
            // The launch scene and a hidden copy lower in the tree both carry it: take the one a finger can reach.
            let imp = app.buttons.matching(NSPredicate(format: "label == 'New from Import…'")).allElementsBoundByIndex
                .filter(\.isHittable).sorted { $0.frame.minY < $1.frame.minY }.first ?? button("New from Import…")
            check("A-101", "New from Import… is on the launch screen", imp.exists && imp.isHittable)
            let version = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Build' OR label CONTAINS 'build' OR label CONTAINS '(4'")).firstMatch
            check("A-101", "The version line shows", version.exists, version.exists ? version.label : "not found")
            // The hero icon is drawn only in regular width (LaunchHeroOverlay); the closed Duo is compact.
            let icon = app.images["LaunchHeroIcon"].firstMatch
            record("| A-101 | ℹ️ INFO | Hero icon \(icon.exists ? "shown" : "not shown") — by design it shows only in regular width |")
            snapshot("A101-launch")
            if imp.exists {
                imp.tap(); sleep(3)
                snapshot("A101-import-picker")
                let cancel = app.buttons["Cancel"].firstMatch
                check("A-101", "New from Import… opens the Files picker", cancel.waitForExistence(timeout: 8))
                if cancel.exists { cancel.tap(); sleep(3) }
                snapshot("A101-after-cancel")
                let editor = app.descendants(matching: .any)["uitest.canvas"].firstMatch
                check("A-101", "Cancel makes nothing (no editor opens)", !editor.exists && button("New from Import…").exists)
            }
        }

        // A-102 — New Image sheet: Name, W and H, Sizes menu, Cancel (Esc), Create (Return); 0, 1 and a huge size.
        if runs("102") {
            func openSheet() -> Bool {
                let new = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex
                    .filter(\.isHittable).sorted { $0.frame.minY < $1.frame.minY }
                new.first?.tap()
                return app.buttons["Create"].waitForExistence(timeout: 10)
            }
            func backToLaunch() {
                let back = app.buttons["BackButton"].firstMatch
                if back.waitForExistence(timeout: 5) { back.tap(); sleep(3) }
            }
            // Sheet 1 — every field, then Esc.
            check("A-102", "New Image opens the sheet", openSheet())
            let name = app.textFields["File name"].firstMatch, w = app.textFields["Width"].firstMatch, h = app.textFields["Height"].firstMatch
            check("A-102", "Name field shows for an automatic name", name.exists)
            check("A-102", "W and H fields show", w.exists && h.exists, "W \(w.value ?? "?") H \(h.value ?? "?")")
            snapshot("A102-sheet")
            // Sizes menu: a quick size sets W and H.
            let sizes = button("Sizes")
            if sizes.exists {
                let before = app.buttons.allElementsBoundByIndex.map(\.label)
                sizes.tap(); sleep(2)
                snapshot("A102-sizes-menu")
                // The menu is taller than the closed Duo: read it, scroll it, read it again.
                var items = app.buttons.allElementsBoundByIndex.map(\.label).filter { !before.contains($0) && !$0.isEmpty }
                if let last = app.buttons.matching(NSPredicate(format: "label == 'Paper'")).allElementsBoundByIndex.first(where: \.isHittable) {
                    last.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
                    sleep(1)
                    items += app.buttons.allElementsBoundByIndex.map(\.label).filter { !before.contains($0) && !$0.isEmpty && !items.contains($0) }
                }
                let groups = ["App Store Connect", "Wallpapers", "Social", "Apple TV", "Web ads", "Paper", "Posters",
                              "Signs & flyers", "Event & stationery", "Cards & envelopes", "Photo"]
                let quick = items.filter { !groups.contains($0) }
                check("A-102", "Sizes menu: 4 quick sizes", quick.count >= 4, quick.joined(separator: " · "))
                check("A-102", "Sizes menu: the full catalog groups", groups.allSatisfy(items.contains),
                      "missing: \(groups.filter { !items.contains($0) }.joined(separator: ", "))")
                // Scrolling moved the quick sizes away: close the menu and open it fresh to pick one.
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1)
                sizes.tap(); sleep(2)
                if let pick = quick.first(where: { $0.hasPrefix("Web banner") }) ?? quick.first, let b = app.buttons.matching(NSPredicate(format: "label == %@", pick)).allElementsBoundByIndex.first(where: \.isHittable) {
                    b.tap(); sleep(1)
                    check("A-102", "A quick size sets W and H (\(pick))", (w.value as? String) == "1,500" && (h.value as? String) == "500",
                          "W \(w.value ?? "?") H \(h.value ?? "?")")
                } else { app.tap(); sleep(1) }
            } else { check("A-102", "Sizes menu shows", false) }
            // 0 → Create is off; 1 → Create is on.
            setField(w, "0"); h.tap(); sleep(1)
            check("A-102", "W = 0: Create is off", !app.buttons["Create"].firstMatch.isEnabled)
            setField(w, "1"); setField(h, "1"); name.tap(); sleep(1)
            check("A-102", "1 × 1: Create is on", app.buttons["Create"].firstMatch.isEnabled)
            // A huge size: over 16,384 a side Create is off and the sheet says why; 16,384 itself is allowed.
            setField(w, "30000"); setField(h, "30000"); name.tap(); sleep(1)
            snapshot("A102-huge-typed")
            check("A-102", "30000 × 30000: Create is off", !app.buttons["Create"].firstMatch.isEnabled)
            check("A-102", "30000 × 30000: the sheet says the limit", app.staticTexts["Up to 16,384 pixels a side."].exists)
            setField(w, "16384"); setField(h, "16384"); name.tap(); sleep(1)
            check("A-102", "16384 × 16384: Create is on", app.buttons["Create"].firstMatch.isEnabled)
            // Esc with the cursor in the Name field (hardware keyboard).
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: []); sleep(2)
            // REM 2026-11-22 testKeyProbe: this iPhone simulator delivers no simulated hardware keys (a tool letter
            // didn't land either), so Esc is recorded, not judged here; judged on the iPad pass / a real keyboard.
            record("| A-102 | ℹ️ INFO | Esc (hardware key): sheet \(app.buttons["Create"].exists ? "stayed — keys don't reach the app on this iPhone simulator" : "closed") |")
            if app.buttons["Create"].exists { app.buttons["Cancel"].firstMatch.tap(); sleep(2) }
            let afterEsc = canvasSize()
            check("A-102", "Cancel keeps the size it opened with, not 16384", afterEsc.w > 0 && afterEsc.w < 16384,
                  "\(afterEsc.w)×\(afterEsc.h)")
            backToLaunch()
            // Sheet 2 — the subsection's project file (000.7): name, 1024 × 1024, Return on the keyboard creates.
            if openSheet() {
                setField(app.textFields["File name"].firstMatch, "A7 Duo closed upright")
                setField(app.textFields["Width"].firstMatch, "1024"); setField(app.textFields["Height"].firstMatch, "1024")
                app.textFields["File name"].firstMatch.tap(); sleep(1)
                app.textFields["File name"].firstMatch.typeText("\n"); sleep(3)
                check("A-102", "Return in the Name field creates", !app.buttons["Create"].exists)
                if app.buttons["Create"].exists { app.buttons["Create"].firstMatch.tap(); sleep(3) }
                let made = canvasSize()
                check("A-102", "Create makes the image at 1024 × 1024", made.w == 1024 && made.h == 1024, "\(made.w)×\(made.h)")
                snapshot("A102-created")
                backToLaunch()
            }
        }

        // A-103 — Canvas presets: apply one from every group, on the subsection's file with a real photo (000.8).
        if runs("103") {
            openNewImage(named: "A7 presets")
            _ = placeShakedownPhoto("A103")
            press("Canvas Tool"); sleep(2)
            let groups = ["App Store Connect", "Wallpapers", "Social", "Apple TV", "Web ads", "Paper", "Posters",
                          "Signs & flyers", "Event & stationery", "Cards & envelopes", "Photo"]
            var last = canvasSize()
            for g in groups {
                let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Canvas size presets'")).firstMatch
                guard menu.waitForExistence(timeout: 5) else { check("A-103", "\(g): presets menu found", false); continue }
                if !menu.isHittable { app.swipeUp(); sleep(1) }
                menu.tap(); sleep(2)
                let gb = app.buttons.matching(NSPredicate(format: "label == %@", g)).firstMatch
                guard gb.waitForExistence(timeout: 4) else {
                    snapshot("A103-\(g)-missing"); check("A-103", "\(g): group in the menu", false)
                    app.tap(); sleep(1); continue
                }
                let before = Set(app.buttons.allElementsBoundByIndex.map(\.label))
                gb.tap(); sleep(2)
                let item = app.buttons.allElementsBoundByIndex.first { !before.contains($0.label) && !$0.label.isEmpty && $0.isHittable }
                guard let item else { snapshot("A103-\(g)-empty"); check("A-103", "\(g): a preset to pick", false); app.tap(); sleep(1); continue }
                let label = item.label
                item.tap(); sleep(2)
                let now = canvasSize()
                check("A-103", "\(g): \"\(label.prefix(40))\" applies", now.w > 0 && app.state == .runningForeground,
                      "\(last.w)×\(last.h) → \(now.w)×\(now.h)")
                last = now
            }
            snapshot("A103-done")
        }

        // A-104 to A-110 — layout & navigation, in one project file for the group (000.7), with a real photo (000.8).
        let layoutLines = ["104", "105", "106", "107", "109", "110"]
        if layoutLines.contains(where: runs) {
            openNewImage(named: "A7 layout")
            _ = placeShakedownPhoto("A104")
        }
        let tools: [(String, String)] = [("Canvas Tool", "c"), ("Color Palette", "k"), ("Move", "m"), ("Selection", "s"),
            ("Mask", "q"), ("Paint Drop Bucket", "b"), ("Pixel Pen", "p"), ("Eraser", "e"), ("Eyedropper", "i"), ("Text", "t"),
            ("Symbol", "y"), ("Image", "g"), ("Image Playground", "a"), ("Layer", "l"), ("Remove Background", "r"),
            ("Magic Lasso", "w"), ("Adjust", "j"), ("Camera", "h")]
        // A-104 — every tool button selects its tool; selected state shows; its letter key picks it (hardware keyboard).
        if runs("104") {
            var notSel: [String] = [], keyMiss: [String] = []
            for (t, _) in tools {
                guard press(t, 3) else { notSel.append("\(t) (not found)"); continue }
                sleep(1)
                if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap(); sleep(1) }
                if !button(t).isSelected { notSel.append(t) }
            }
            check("A-104", "Every tool button selects its tool (18)", notSel.isEmpty, notSel.joined(separator: ", "))
            press("Canvas Tool"); sleep(1)
            for (t, k) in tools where t != "Canvas Tool" {
                app.typeKey(k, modifierFlags: []); sleep(1)
                if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap(); sleep(1) }
                if !button(t).isSelected { keyMiss.append("\(k.uppercased()) → \(t)") }
                press("Canvas Tool"); sleep(1)
            }
            if keyMiss.count == tools.count - 1 {
                record("| A-104 | ℹ️ INFO | Letter keys: none landed — this iPhone simulator delivers no hardware keys (testKeyProbe); judged on the iPad pass |")
            } else {
                check("A-104", "Each tool's letter key picks it (hardware keyboard)", keyMiss.isEmpty, keyMiss.joined(separator: ", "))
            }
            record("| A-104 | ℹ️ INFO | The letter in each tool's help text is pointer hover (iPad/Mac); checked on the Mac pass |")
        }
        // A-105 — tool palette grip: float and dock; drag the floating palette; its spot is remembered.
        if runs("105") {
            let float = button("Float tools")
            check("A-105", "Float tools grip shows", float.waitForExistence(timeout: 3))
            float.tap(); sleep(2)
            let dock = button("Dock tools")
            check("A-105", "Float tools floats the palette (grip now says Dock tools)", dock.waitForExistence(timeout: 3))
            snapshot("A105-floating")
            let f0 = dock.frame
            dock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.4, thenDragTo: dock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 60, dy: -120)))
            sleep(2)
            let f1 = button("Dock tools").frame
            check("A-105", "Dragging the grip moves the palette", abs(f1.minX - f0.minX) > 20 || abs(f1.minY - f0.minY) > 20,
                  "\(Int(f0.minX)),\(Int(f0.minY)) → \(Int(f1.minX)),\(Int(f1.minY))")
            // Remembered: quit, relaunch, reopen the same file.
            app.terminate()
            app.launchArguments.append("-ImageProducerUITestKeep")   // keep the settings across this one relaunch
            app.launch(); sleep(5)
            app.launchArguments.removeAll { $0 == "-ImageProducerUITestKeep" }
            snapshot("A105-relaunch-start")
            // Reopen the same file the way a person would: it may be open already, else Browse → On My iPhone → folder → file.
            if !app.descendants(matching: .any)["uitest.canvas"].firstMatch.exists {
                // The browser's cells carry the file name as their IDENTIFIER; Recents lists the newest first.
                let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'A7 layout' OR label BEGINSWITH 'A7 layout'")).firstMatch
                if press("Recents", 4) { sleep(2) }
                for _ in 0..<4 where !(file.exists && file.isHittable) { app.swipeUp(); sleep(1) }
                if file.waitForExistence(timeout: 4) { file.tap(); sleep(4) }
            }
            // The spot is an app-wide setting: if the file didn't reopen, any image shows it.
            if !app.descendants(matching: .any)["uitest.canvas"].firstMatch.exists { openNewImage(named: "A7 layout 2"); _ = placeShakedownPhoto("A105b") }
            snapshot("A105-relaunched")
            let dockAgain = button("Dock tools")
            _ = dockAgain.waitForExistence(timeout: 8)
            let f2 = dockAgain.exists ? dockAgain.frame : .zero
            check("A-105", "The palette's spot is remembered after a relaunch", dockAgain.exists && abs(f2.minX - f1.minX) < 6 && abs(f2.minY - f1.minY) < 6,
                  dockAgain.exists ? "\(Int(f1.minX)),\(Int(f1.minY)) → \(Int(f2.minX)),\(Int(f2.minY))" : "palette not found after relaunch (file reopened: \(app.descendants(matching: .any)["uitest.canvas"].firstMatch.exists))")
            if button("Dock tools").exists { button("Dock tools").tap(); sleep(2) }
            check("A-105", "Dock tools puts the palette back under the canvas", button("Float tools").waitForExistence(timeout: 3))
        }
        // A-106 — split handle (upright): drag 15%–85%, double-tap resets; it is an adjustable control for VoiceOver.
        if runs("106") {
            let handle = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Canvas size'")).firstMatch
            check("A-106", "The split handle is on screen (Canvas size)", handle.waitForExistence(timeout: 3))
            if handle.exists {
                let pct = { () -> Int in Int(((handle.value as? String) ?? "").prefix { $0.isNumber }) ?? -1 }
                let start = pct()
                handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
                sleep(1); let hi = pct()
                for _ in 0..<3 {   // three strokes: one long fast drag can end early
                    handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)), withVelocity: 300, thenHoldForDuration: 0.3)
                    sleep(1)
                }
                let lo = pct()
                snapshot("A106-dragged-up")
                check("A-106", "Dragging down stops at 85%", hi == 85, "\(start)% → \(hi)%")
                check("A-106", "Dragging up stops at 15%", lo == 15, "\(lo)%")
                handle.doubleTap(); sleep(2)
                let reset = pct()
                check("A-106", "Double-tap resets the split", reset != lo && reset > 15 && reset < 85, "\(lo)% → \(reset)%")
                let adjustable = handle.debugDescription.contains("Adjustable") || handle.elementType == .slider || handle.elementType == .other
                record("| A-106 | ℹ️ INFO | VoiceOver: an adjustable control, value \"\(handle.value ?? "")\", steps of 5% in code; swipe check is VoiceOver-only (\(adjustable ? "element present" : "?")) |")
            }
        }
        // A-107 — Tool | Layers | History: each page opens; swipe between pages where offered.
        if runs("107"), app.buttons["Tool"].firstMatch.waitForExistence(timeout: 5) {
            let row = app.buttons["Tool"].firstMatch.frame.midY
            for tab in ["Layers", "History", "Tool"] {
                let b = app.buttons.matching(identifier: tab).allElementsBoundByIndex.first { abs($0.frame.midY - row) < 8 }
                b?.tap(); sleep(1)
                check("A-107", "\(tab) page opens", b?.isSelected ?? false)
            }
            // Swipe left on the panel below the switch.
            let panelPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: row + 120))
            panelPoint.press(forDuration: 0.05, thenDragTo: panelPoint.withOffset(CGVector(dx: -200, dy: 0)))
            sleep(1)
            let swiped = app.buttons.matching(identifier: "Layers").allElementsBoundByIndex.first { abs($0.frame.midY - row) < 8 }?.isSelected ?? false
            record("| A-107 | ℹ️ INFO | Swipe left on the Tool page \(swiped ? "goes to Layers" : "is not offered (no change)") |")
        }
        // A-109 — Zoom in, Zoom out, Fit screen (shows the zoom level); A-110 — pinch zoom 1× to 8×.
        if runs("109") || runs("110") {
            let fit = button("Fit screen")
            // The zoom level from the probe (zoom=1.00 → 100); the closed Duo has no on-canvas readout.
            let zoom = { () -> Int in
                let e = self.app.descendants(matching: .any)["uitest.canvas"].firstMatch
                guard e.exists, let r = e.label.range(of: "zoom=") else { return -1 }
                return Int(((Double(e.label[r.upperBound...].prefix { "0123456789.".contains($0) }) ?? -0.01) * 100).rounded())
            }
            func toFit() { while zoom() > 100, button("Zoom out").isEnabled { button("Zoom out").tap(); sleep(1) } }
            if runs("109") {
                check("A-109", "Zoom in and Zoom out show", button("Zoom in").exists && button("Zoom out").exists)
                record("| A-109 | ℹ️ INFO | Fit screen (the % button) \(fit.exists ? "shows" : "is not on this shape — zoom is the toolbar's + and −") |")
                toFit(); let z0 = zoom()
                press("Zoom in"); sleep(1); let z1 = zoom()
                press("Zoom out"); sleep(1); let z2 = zoom()
                check("A-109", "Zoom in raises the zoom; Zoom out lowers it", z1 > z0 && z2 < z1, "\(z0)% → \(z1)% → \(z2)%")
                check("A-109", "Zoom out stops at 100%", z2 == 100 && !button("Zoom out").isEnabled, "\(z2)%")
                let lh = app.buttons.matching(NSPredicate(format: "(label == 'Layers' OR label == 'History') AND identifier != 'Layers' AND identifier != 'History'")).count
                record("| A-109 | ℹ️ INFO | Toolbar Layers/History buttons on this shape: \(lh) (the Tool | Layers | History switch holds them here) |")
            }
            if runs("110") {
                toFit()
                let canvasEl = app.descendants(matching: .any)["uitest.canvas"].firstMatch
                canvasEl.pinch(withScale: 12, velocity: 6); sleep(2)
                let zMax = zoom()
                check("A-110", "Pinch out zooms to 800% and stops", zMax == 800, "\(zMax)%")
                canvasEl.pinch(withScale: 0.05, velocity: -6); sleep(2)
                if zoom() > 100 { canvasEl.pinch(withScale: 0.1, velocity: -2); sleep(2) }   // a slower second pinch
                let zMin = zoom()
                snapshot("A110-pinched-in")
                // REM 2026-11-22 — at 800% the canvas element is ~2,300 pt wide, so XCUITest's pinch-in starts its
                // fingers off screen and the app never feels them. Recorded here; judged on his Duo.
                if zMin == 100 { check("A-110", "Pinch in comes back to 100% and stops", true, "100%") }
                else { record("| A-110 | ℹ️ INFO | Pinch in from 800%: the simulated fingers start off screen (canvas \(Int(canvasEl.frame.width)) pt wide) — zoom stayed \(zMin)%; needs your Duo |") }
                toFit()   // leave it at 100% for the next lines, whatever the pinch did
                record("| A-111 | ℹ️ INFO | Two-finger pan: XCUITest has no two-finger drag on iPhone — needs your Duo |")
            }
        }
        /// Close whatever sheet or screen a toolbar button opened: its own Done / Cancel / Close, else swipe it down.
        func dismissTop() {
            for n in ["Done", "Cancel", "Close", "OK"] {
                let b = app.buttons.matching(NSPredicate(format: "label == %@", n)).allElementsBoundByIndex.first(where: \.isHittable)
                if let b { b.tap(); sleep(2); return }
            }
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            sleep(2)
        }
        // A-108 — toolbar: Export, Storyboard, Share (flat PNG), About. Each opens, then closes back to the editor.
        if runs("108") {
            if !app.descendants(matching: .any)["uitest.canvas"].firstMatch.exists {
                openNewImage(named: "A7 layout"); _ = placeShakedownPhoto("A108")
            }
            for (label, opened) in [("Export", "Export"), ("Storyboard", "Storyboard"), ("Share", "share sheet"), ("About Image Producer", "About")] {
                let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first(where: \.isHittable)
                guard let b else { check("A-108", "\(label) is on the toolbar", false); continue }
                let before = app.buttons.count
                b.tap(); sleep(3)
                snapshot("A108-\(label.replacingOccurrences(of: " ", with: "-"))")
                let shareUp = XCUIApplication(bundleIdentifier: "com.apple.springboard").otherElements["ActivityListView"].exists
                    || app.otherElements["ActivityListView"].exists || app.navigationBars["UIActivityContentView"].exists
                let changed = app.sheets.count > 0 || app.buttons.count != before || shareUp
                    || app.buttons["Done"].exists || app.buttons["Close"].exists
                check("A-108", "\(label) opens the \(opened)", changed, "buttons \(before) → \(app.buttons.count)")
                dismissTop()
                check("A-108", "\(label): back to the editor afterward", app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 5)
                      && button("Canvas Tool").isHittable)
            }
        }
        // A-112 — floating preview: tap the handle → next corner; drag snaps to a corner; long-press lifts it;
        // zoomed in it is a navigator; it stays clear of Back and the zoom controls.
        if runs("112") {
            if !app.descendants(matching: .any)["uitest.canvas"].firstMatch.exists {
                openNewImage(named: "A7 layout"); _ = placeShakedownPhoto("A112")
            }
            while button("Zoom out").exists && button("Zoom out").isEnabled { button("Zoom out").tap(); sleep(1) }   // start at 100%
            let pip = app.descendants(matching: .any)["pip.panel"].firstMatch
            let grip = button("Move preview")
            check("A-112", "The floating preview shows", pip.waitForExistence(timeout: 5))
            if pip.exists, grip.exists {
                let c0 = pip.frame
                grip.tap(); sleep(2)
                let c1 = pip.frame
                check("A-112", "Tapping the handle sends it to the next corner", c1.midX != c0.midX || c1.midY != c0.midY,
                      "\(Int(c0.midX)),\(Int(c0.midY)) → \(Int(c1.midX)),\(Int(c1.midY))")
                // Drag toward the middle of the canvas and let go: it must land in a corner, not mid-canvas.
                let canvas = app.descendants(matching: .any)["uitest.canvas"].firstMatch.frame
                grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.6, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: canvas.midX - 20, dy: canvas.midY - 20)))
                sleep(2)
                let c2 = pip.frame
                let inCorner = (abs(c2.minX - canvas.minX) < 40 || abs(c2.maxX - canvas.maxX) < 40)
                    && (abs(c2.minY - canvas.minY) < 80 || abs(c2.maxY - canvas.maxY) < 40)
                check("A-112", "A long-press drag lifts it and it snaps to a corner", inCorner,
                      "panel \(Int(c2.minX)),\(Int(c2.minY)) \(Int(c2.width))×\(Int(c2.height)) · canvas \(Int(canvas.minX)),\(Int(canvas.minY)) \(Int(canvas.width))×\(Int(canvas.height))")
                // Clear of Back and the zoom controls, in every corner.
                var hits: [String] = []
                for _ in 0..<4 {
                    let f = pip.frame
                    for n in ["BackButton", "Zoom in", "Zoom out", "Fit screen", "Fit width"] {
                        let e = n == "BackButton" ? app.buttons["BackButton"].firstMatch : button(n)
                        if e.exists, e.isHittable, f.intersects(e.frame) { hits.append("\(n) at \(Int(f.midX)),\(Int(f.midY))") }
                    }
                    grip.tap(); sleep(2)
                }
                check("A-112", "In every corner it stays clear of Back and the zoom controls", hits.isEmpty, hits.joined(separator: ", "))
                // Navigator: zoomed in, a tap on the thumbnail's corner moves the view.
                button("Zoom in").tap(); sleep(1); button("Zoom in").tap(); sleep(1)
                // Panning moves the canvas itself: compare where it sits (no layer needs to be selected).
                let cv = app.descendants(matching: .any)["uitest.canvas"].firstMatch
                let before = cv.frame
                pip.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap(); sleep(2)
                let after = cv.frame
                check("A-112", "Zoomed in, tapping the preview moves the view (navigator)",
                      abs(after.minX - before.minX) > 10 || abs(after.minY - before.minY) > 10,
                      "canvas at \(Int(before.minX)),\(Int(before.minY)) → \(Int(after.minX)),\(Int(after.minY))")
                while button("Zoom out").exists && button("Zoom out").isEnabled { button("Zoom out").tap(); sleep(1) }
            }
            record("| A-113 | ℹ️ INFO | Drag a picture in from another app: not possible on the iPhone simulator — needs your Duo |")
        }

        // A-114 to A-121 — the Canvas tool's page, one project file for the group (000.7), a real photo (000.8).
        let canvasLines = ["114", "115", "116", "117", "118", "119", "120", "121"]
        /// Scroll the tool page until the element can be tapped (the closed Duo shows a few rows at a time).
        func reveal(_ e: XCUIElement) -> Bool {
            for _ in 0..<14 {
                if e.exists && e.isHittable { return true }
                // REM 14:5x — drag inside the settings list itself (the lowest scroll view on screen, 175 pt tall on the
                // closed Duo), toward the control: up when it sits above the list, down otherwise. Guessing from the Tool
                // tab put drags outside the list, so the page never moved (A-117–A-121 "not found" with the control on screen).
                // REM 14:5x (2) — a coordinate drag landed on fields/switches, which ate it (the list moved 8 pt in two runs).
                // XCUITest's own slow swipe on the list element scrolls it like a finger on the list.
                let lists = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 60 }
                guard let list = lists.max(by: { $0.frame.minY < $1.frame.minY }) else { sleep(1); continue }
                // REM 15:1x — the slow swipe overshot (Bleed found, Units 100 pt below lost; A-116 passed before it). Now a
                // MEASURED drag on the list's left margin (6 pt in: controls start 16 pt in, so nothing eats it), moving the
                // control toward the list's middle, at most 120 pt per step, held at the end so it cannot coast.
                let f = list.frame
                let delta: CGFloat = e.exists ? max(-120, min(120, e.frame.midY - f.midY)) : 120
                let x = (f.minX + 6) / app.windows.firstMatch.frame.width
                let win = app.windows.firstMatch.frame.height
                let y0 = (f.midY + delta / 2) / win, y1 = (f.midY - delta / 2) / win
                let a = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y0))
                let b = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y1))
                a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.4)
                usleep(300_000)   // REM 16:3x — was sleep(1); the 0.4 s hold already stops the list coasting
            }
            return e.exists && e.isHittable
        }
        func toTop() { for _ in 0..<6 { let s = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)); s.press(forDuration: 0.05, thenDragTo: s.withOffset(CGVector(dx: 0, dy: 160))) } ; sleep(1) }
        func pickMenu(_ menuLabel: String, _ item: String) -> Bool {
            let m = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", menuLabel)).firstMatch
            guard reveal(m) else { return false }
            m.tap(); sleep(2)
            let i = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item)).allElementsBoundByIndex.first(where: \.isHittable)
            guard let i else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1); return false }
            i.tap(); sleep(2); return true
        }
        if canvasLines.contains(where: runs) {
            openNewImage(named: "A7 canvas page")
            _ = placeShakedownPhoto("A114")
            press("Canvas Tool"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
        }
        // A-114 — Project name: rename it; a name that is already taken.
        if runs("114") {
            let field = app.textFields["Project name"].firstMatch
            // REM 13:3x — a unique name each run: earlier runs and the A-114 probe left "A7 canvas renamed" on disk.
            let newName = "A7 renamed \(Int(Date().timeIntervalSince1970) % 100000)"
            if reveal(field) {
                setField(field, newName); field.typeText("\n"); sleep(4)
                snapshot("A114-renamed")
                // REM 13:3x — the closed Duo shows no navigation bar; reading a missing one failed the whole run.
                let nav = app.navigationBars.firstMatch
                let title = nav.exists ? nav.identifier : ""
                check("A-114", "Renaming the project changes its name", (field.value as? String) == newName || title.contains(newName),
                      "field \"\(field.value ?? "")\" · title \"\(title)\"")
                setField(field, "A1 Duo closed upright"); field.typeText("\n"); sleep(4)
                snapshot("A114-taken")
                let err = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH \"Couldn't rename\"")).firstMatch
                check("A-114", "A name already taken is refused, and says so", err.exists || (field.value as? String) != "A1 Duo closed upright",
                      err.exists ? err.label : "field now \"\(field.value ?? "")\"")
                if (field.value as? String) != newName { setField(field, newName); field.typeText("\n"); sleep(3) }
            } else { check("A-114", "Project name field found", false) }
        }
        // A-115 — Pixels W × H, Size rule (Exact, Fixed ratio, Fluid width, Fluid height), Landscape switch.
        if runs("115") {
            toTop()
            let w = app.textFields["Width"].firstMatch, h = app.textFields["Height"].firstMatch
            if reveal(w) {
                // REM 13:5x — Return commits each field and drops the keyboard; without it the keyboard covered every later control.
                setField(w, "800"); w.typeText("\n"); sleep(1); setField(h, "600"); h.typeText("\n"); sleep(2)
                let s1 = canvasSize()
                check("A-115", "Pixels W × H set the canvas (800 × 600)", s1.w == 800 && s1.h == 600, "\(s1.w)×\(s1.h)")
                for rule in ["Fixed ratio", "Fluid width", "Fluid height", "Exact"] {
                    let ok = pickMenu("Size rule", rule)
                    check("A-115", "Size rule: \(rule) can be picked", ok)
                    if rule == "Fixed ratio", ok {
                        setField(w, "1600"); w.typeText("\n"); sleep(2)
                        let s2 = canvasSize()
                        check("A-115", "Fixed ratio: W 1600 keeps 4:3 (H 1200)", s2.w == 1600 && s2.h == 1200, "\(s2.w)×\(s2.h)")
                    }
                }
                let land = app.switches["Landscape"].firstMatch
                if reveal(land) {
                    let before = canvasSize()
                    land.tap(); sleep(2)
                    let after = canvasSize()
                    check("A-115", "Landscape switch swaps W and H", after.w == before.h && after.h == before.w, "\(before.w)×\(before.h) → \(after.w)×\(after.h)")
                } else { check("A-115", "Landscape switch found", false) }
            } else { check("A-115", "Pixels fields found", false) }
        }
        // A-116 — Units, Resolution and the 5 common resolutions, Print size readout.
        if runs("116") {
            snapshot("A116-start")
            // REM 14:1x — Units is a segmented picker (labelsHidden), not a menu: its four segments are buttons named in/mm/pt/px; there is no "Units" button.
            for u in ["in", "mm", "pt", "px"] {
                let seg = app.buttons[u].firstMatch
                var ok = false
                if reveal(seg) { seg.tap(); sleep(1); ok = seg.isSelected }
                check("A-116", "Units: \(u) can be picked", ok, seg.exists ? "selected=\(seg.isSelected)" : "segment not found")
            }
            if !app.textFields["Resolution"].firstMatch.exists { snapshot("A116-no-resolution") }
            let res = app.textFields["Resolution"].firstMatch
            if reveal(res) {
                for (label, v) in [("72 —", "72"), ("150 —", "150"), ("300 —", "300"), ("360 —", "360"), ("600 —", "600")] {
                    let ok = pickMenu("Common resolutions", label)
                    check("A-116", "Common resolution \(v) sets Resolution", ok && (res.value as? String)?.replacingOccurrences(of: ",", with: "") == v, "\(res.value ?? "")")
                }
                // REM 15:0x — the readout is attrRow("Print size", "W … × H … <unit>"); in px it reads pixels, so pick inches first. 600 PPI was set last.
                let inSeg = app.buttons["in"].firstMatch
                if reveal(inSeg) { inSeg.tap(); sleep(1) }
                let readout = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'W ' AND label CONTAINS ' × H ' AND label ENDSWITH ' in'")).firstMatch
                let w = Double(res.value as? String ?? "") ?? 0
                _ = reveal(readout)
                check("A-116", "Print size readout shows inches", readout.exists, readout.exists ? readout.label : "no 'W … × H … in' text (PPI \(w))")
            } else { check("A-116", "Resolution field found", false) }
        }
        // A-117 — Canvas size presets menu (A-103 applied all 11 groups); the ratio warning.
        if runs("117") {
            // REM 14:2x — A-103's proven path: wait for the group, then wait for the item; a screenshot when either is missing.
            // REM 15:3x — the warning half: on the 1024 × 1024 canvas, Social → "X header" (3:1, 1500 px minimum long edge)
            // must keep the shape and say the resolution is too low (applyAspectPreset: "say it, don't fix it").
            let orange = NSPredicate(format: "label BEGINSWITH 'Canvas is W' AND label CONTAINS 'minimum long edge'")
            var warned = false
            if pickMenu("Canvas size presets", "Social") {
                let x = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'X header'")).firstMatch
                if x.waitForExistence(timeout: 5) && x.isHittable { x.tap(); sleep(2)
                    let w = app.staticTexts.matching(orange).firstMatch
                    warned = reveal(w)
                    let s0 = canvasSize()
                    check("A-117", "Ratio preset below its minimum shows the orange warning (X header on 1024 → 1024 × 341)", warned && s0.w == 1024 && s0.h == 341, warned ? "\(s0.w)×\(s0.h) · \(w.label.prefix(60))" : "no warning · \(s0.w)×\(s0.h)")
                } else { snapshot("A117-no-xheader"); app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1)
                    check("A-117", "X header preset found", false) }
            } else { check("A-117", "Social group found", false) }
            let ok = pickMenu("Canvas size presets", "App Store Connect")
            if ok {
                let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'iPhone 6.9'")).firstMatch
                if item.waitForExistence(timeout: 5) && item.isHittable { item.tap(); sleep(2) }
                else { snapshot("A117-no-item"); app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1) }
            } else { snapshot("A117-no-group") }
            let s = canvasSize()
            check("A-117", "Canvas size presets menu applies (iPhone 6.9″ → 1260 × 2736)", s.w == 1260 && s.h == 2736, "\(s.w)×\(s.h)")
            if warned { check("A-117", "Orange warning clears once a full-size preset applies", !app.staticTexts.matching(orange).firstMatch.exists) }
        }
        // A-118 — Print setup: Bleed + presets, Safe margin, Crop / trim marks, Registration marks, Color RGB / CMYK.
        if runs("118") {
            let bleed = app.textFields["Bleed"].firstMatch
            if reveal(bleed) {
                check("A-118", "Bleed preset 0.125 in", pickMenu("Bleed presets", "0.125") && (bleed.value as? String) == "0.125", "\(bleed.value ?? "")")
                check("A-118", "Bleed preset None", pickMenu("Bleed presets", "None") && (bleed.value as? String) == "0", "\(bleed.value ?? "")")
                let safe = app.textFields["Safe margin"].firstMatch
                if reveal(safe) { setField(safe, "0.25"); safe.typeText("\n"); sleep(1)   // REM 15:3x — Return, not a tap on Bleed: that raised a keyboard over the switches
                    check("A-118", "Safe margin takes a value", (safe.value as? String) == "0.25", "\(safe.value ?? "")") }
                for t in ["Crop / trim marks", "Registration marks"] {
                    let sw = app.switches[t].firstMatch
                    // REM 15:4x — tap the toggle knob at the row's right end, not the row's middle (Registration marks sat at the
                    // list's clipped bottom edge and its centre tap did nothing: 0 → 0). Screenshot when it still doesn't flip.
                    if reveal(sw) { let v0 = sw.value as? String
                        let knob = sw.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)); knob.tap(); sleep(1)
                        let flipped = (sw.value as? String) != v0
                        if !flipped { snapshot("A118-\(t.prefix(4))-no-flip") }
                        check("A-118", "\(t) switches", flipped, "\(v0 ?? "?") → \(sw.value ?? "?") · y \(Int(sw.frame.midY))"); if flipped { knob.tap(); sleep(1) }
                    } else { check("A-118", "\(t) found", false) }
                }
                let cmyk = app.buttons["CMYK"].firstMatch, rgb = app.buttons["RGB"].firstMatch
                if reveal(cmyk) { cmyk.tap(); sleep(1); check("A-118", "Color: CMYK can be picked", cmyk.isSelected); rgb.tap(); sleep(1)
                    check("A-118", "Color: back to RGB", rgb.isSelected) }
                else if pickMenu("Color", "CMYK") { check("A-118", "Color: CMYK can be picked", true); _ = pickMenu("Color", "RGB") }
                else { check("A-118", "Color RGB / CMYK found", false) }
            } else { check("A-118", "Bleed field found", false) }
        }
        // A-119 — Export buttons; A-120 — Layer PDF. Each opens its save panel; Cancel saves nothing.
        func opensSaver(_ line: String, _ label: String) {
            let b = app.buttons[label].firstMatch
            guard reveal(b) else { check(line, "\(label) found", false); return }
            b.tap(); sleep(4)
            snapshot("\(line)-\(label.replacingOccurrences(of: " ", with: "-"))")
            let cancel = app.buttons["Cancel"].firstMatch
            check(line, "\(label) opens a save or pick panel", cancel.waitForExistence(timeout: 6))
            if cancel.exists { cancel.tap(); sleep(3) }
            check(line, "\(label): Cancel goes back to the editor", app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 5))
        }
        if runs("119") { for l in ["Print PDF", "Web folder", "Icon sizes", "Single image"] { opensSaver("A-119", l) } }
        if runs("120") {
            opensSaver("A-120", "Export layer PDF")
            let flat = app.switches["Flatten transparency onto a matte"].firstMatch
            // REM 15:5x — the Matte color well exists only while Flatten is ON (ContentView: if flattenLayerPDF); the old test
            // switched Flatten back off before looking for it. Now: on → well shows → off → well gone.
            let matte = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Matte color'")).firstMatch
            if reveal(flat) { let v0 = flat.value as? String
                let knob = flat.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                if v0 == "1" { knob.tap(); sleep(1) }   // start from off
                knob.tap(); sleep(1)
                check("A-120", "Flatten onto a matte switches on", (flat.value as? String) == "1", "\(v0 ?? "?") → \(flat.value ?? "?")")
                check("A-120", "Matte color well shows while Flatten is on", reveal(matte))
                if reveal(flat) { knob.tap(); sleep(1) }
                check("A-120", "Matte color well hides when Flatten is off", (flat.value as? String) == "0" && !matte.exists, "flatten=\(flat.value ?? "?")")
            } else { check("A-120", "Flatten switch found", false) }
            opensSaver("A-120", "Import layer PDF")
        }
        // A-121 — File rows.
        if runs("121") {
            var missing: [String] = []
            for r in ["Location", "Type", "Last saved", "Size", "State"] {
                if !reveal(app.staticTexts[r].firstMatch) { missing.append(r) }
            }
            check("A-121", "File rows: Location, Type, Last saved, Size, State", missing.isEmpty, missing.joined(separator: ", "))
            snapshot("A121-file-rows")
        }
        // A-122 / A-123 — Tool: Color Palette. Its own project file (000.7), a real photo (000.8).
        if runs("122") || runs("123") {
            openNewImage(named: "A7 color palette")
            _ = placeShakedownPhoto("A122")
            press("Color Palette"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
            snapshot("A122-start")
        }
        /// "Palette — N colors" → N (‑1 when the heading isn't there).
        func paletteCount() -> Int {
            let h = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Palette — '")).firstMatch
            guard h.exists else { return -1 }
            return Int(h.label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? -1
        }
        // A-122 — Edit the selected swatch; Add color up to 24; Remove down to 8; long-press Remove.
        if runs("122") {
            // Edit: tap the well, pick a grid color, close; the Active color hex must change.
            // REM 16:4x — the system color sheet runs outside the app, so its Grid/Sliders/hex controls are not in our
            // accessibility tree (A122-color-sheet). Pick a grid cell by position (the bright orange-red row, closed Duo)
            // and close with the sheet's X, the way a finger would.
            let activeHex = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch
            let hex0 = activeHex.exists ? activeHex.label : "?"
            let well = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Edit selected swatch'")).firstMatch
            var edited = false
            if reveal(well) {
                // REM 16:2x — a center tap lands on the label text and opens nothing; the well is the circle at the right end.
                well.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap(); sleep(2)
                snapshot("A122-color-sheet")
                let w = app.windows.firstMatch
                w.coordinate(withNormalizedOffset: CGVector(dx: 180.0 / 466, dy: 390.0 / 678)).tap(); sleep(1)
                w.coordinate(withNormalizedOffset: CGVector(dx: 418.0 / 466, dy: 186.0 / 678)).tap(); sleep(2)
                edited = activeHex.exists && activeHex.label != hex0 && activeHex.label.hasPrefix("#")
            }
            check("A-122", "Edit selected swatch changes the Active color", edited, "\(hex0) → \(activeHex.exists ? activeHex.label : "?")")

            // Add color up to 24, then Add is disabled.
            let add = app.buttons["Add color"].firstMatch
            let remove = app.buttons.matching(NSPredicate(format: "label == 'Remove'")).firstMatch
            let n0 = paletteCount()
            if reveal(add) {
                var guardN = 0
                while add.isEnabled && paletteCount() < 24 && guardN < 20 { add.tap(); usleep(400_000); guardN += 1 }
            }
            let nMax = paletteCount()
            check("A-122", "Add color grows the palette to 24, then stops", nMax == 24 && !add.isEnabled, "\(n0) → \(nMax), Add enabled=\(add.isEnabled)")

            // Remove down to 8, then Remove is disabled (the 8 base colors stay).
            if reveal(remove) {
                var guardN = 0
                while remove.isEnabled && paletteCount() > 8 && guardN < 20 { remove.tap(); usleep(400_000); guardN += 1 }
            }
            let nMin = paletteCount()
            check("A-122", "Remove shrinks the palette to 8, then stops", nMin == 8 && !remove.isEnabled, "\(nMax) → \(nMin), Remove enabled=\(remove.isEnabled)")

            // Long-press Remove: at 8 the menu has no Remove; add one (9), long-press swatch 9, Remove → 8.
            if reveal(add) { add.tap(); sleep(1) }
            // REM 16:4x — the swatches sit in a LazyVGrid: iOS builds only rows on screen, so a swatch below or above the
            // list's window does not exist yet and reveal() cannot aim at it. Bring the "Palette —" heading (a plain view,
            // always in the tree) to the list's middle first; the rows under it get built.
            let paletteHeading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Palette — '")).firstMatch
            _ = reveal(paletteHeading); usleep(500_000)
            let s9 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Color 9,'")).firstMatch
            var lpOK = false
            if paletteCount() == 9 && reveal(s9) {
                s9.press(forDuration: 1.2); sleep(1)
                let menuRemove = app.buttons.matching(NSPredicate(format: "label == 'Remove'")).allElementsBoundByIndex.first { $0.isHittable && $0.frame != remove.frame }
                if let menuRemove { menuRemove.tap(); sleep(1); lpOK = paletteCount() == 8 }
                else { snapshot("A122-no-context-remove"); app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1) }
            }
            check("A-122", "Long-press a swatch → Remove takes it out (9 → 8)", lpOK, "count now \(paletteCount())")
            let s1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Color 1,'")).firstMatch
            _ = reveal(paletteHeading); usleep(500_000)
            if reveal(s1) {
                s1.press(forDuration: 1.2); sleep(1)
                let shown = app.buttons.matching(NSPredicate(format: "label == 'Remove'")).count
                // Only the bottom Remove button (disabled) may exist; the menu must offer no Remove at 8.
                check("A-122", "At 8 colors the long-press menu offers no Remove", shown <= 1, "Remove buttons on screen: \(shown)")
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1)
            }
            snapshot("A122-end")
        }
        // REM 16:5x — HIS PACE RULINGS (11-22 16:4x): "you must be being too strict in your testing rules" and
        // "small medium large ... that removes 357 steps" (000.15). From here: visit each control, try 3 sample values,
        // snapshot. A line passes on what the screenshot shows; checks below are evidence, not gates to perfect.
        func cancelPanel() {
            for n in ["Cancel", "Close", "Done"] where app.buttons[n].firstMatch.exists { app.buttons[n].firstMatch.tap(); sleep(1); return }
            app.windows.firstMatch.swipeDown(velocity: .fast); sleep(1)
        }
        func slide(_ label: String, _ code: String) {
            let s = app.sliders[label].firstMatch
            guard reveal(s) else { record("| \(code) | ❓ | \(label) slider not found |"); return }
            var seen: [String] = []
            // REM 16:5x — his "i am talking random samples": one random value in each third (small / middle / large),
            // fresh each run. A slider that slips off screen mid-way is re-revealed, never allowed to stop the batch
            // (16:48 run: a lost slider ended the whole test at A-124).
            for band in [0.0, 0.34, 0.67] as [CGFloat] {
                let v = band + CGFloat.random(in: 0.02...0.31)
                guard s.exists || reveal(s) else { seen.append("lost"); break }
                if !s.isHittable { _ = reveal(s) }
                guard s.exists, s.isHittable else { seen.append("lost"); break }
                s.adjust(toNormalizedSliderPosition: v); usleep(400_000)
                seen.append("\(Int(v * 100))%→\(s.exists ? ((s.value as? String) ?? "?") : "lost")")
            }
            record("| \(code) | 👁 | \(label) random small/middle/large → \(seen.joined(separator: " · ")) |")
        }
        // A-123 — Save Palette / Load Palette (same Color Palette project, 000.7), plus a file that is not a palette.
        if runs("123") {
            if !runs("122") { openNewImage(named: "A7 color palette"); _ = placeShakedownPhoto("A123"); press("Color Palette"); sleep(2) }
            if reveal(app.buttons["Save Palette"].firstMatch) {
                app.buttons["Save Palette"].firstMatch.tap(); sleep(3); snapshot("A123-save-panel")
                check("A-123", "Save Palette opens a save panel", app.otherElements["Browse View (Picker)"].exists || app.navigationBars.count > 0 || app.buttons["Save"].exists || app.buttons["Move"].exists)
                cancelPanel()
            }
            if reveal(app.buttons["Load Palette"].firstMatch) {
                app.buttons["Load Palette"].firstMatch.tap(); sleep(3); snapshot("A123-load-panel")
                let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Shakedown Photo 1'")).firstMatch
                if photo.waitForExistence(timeout: 4) {
                    photo.tap(); sleep(2); snapshot("A123-not-a-palette")
                    record("| A-123 | 👁 | Picked a photo as a palette: alert=\(app.alerts.firstMatch.exists) · text: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'palette'")).allElementsBoundByIndex.map(\.label).prefix(3).joined(separator: " | ")) |")
                    if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap(); sleep(1) }
                } else { cancelPanel() }
            }
        }
        // A-124 to A-129 — the Move page: Crop, Straight line, Snap to Canvas, Scale, Position/Rotation, Apply/Flip/Center/Reset.
        let moveLines = ["124", "125", "126", "127", "128", "129"]
        if moveLines.contains(where: runs) {
            openNewImage(named: "A7 move page")
            _ = placeShakedownPhoto("A124")
            press("Move"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
            snapshot("A124-move-page")
        }
        if runs("124") {
            let aspects = ["Original", "Freeform", "Custom"]
            for a in aspects { if pickMenu("Aspect", a) { snapshot("A124-aspect-\(a)"); if a == "Freeform" { slide("Width", "A-124"); slide("Height", "A-124") } } }
            slide("Crop size", "A-124")
            let w = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'W '")).firstMatch
            if reveal(w) { w.buttons.element(boundBy: 1).tap(); w.buttons.element(boundBy: 1).tap(); record("| A-124 | 👁 | Custom W stepper → \(w.label) |") }
            let apply = app.buttons["Apply Crop"].firstMatch
            let before = canvasSize()
            if reveal(apply) { apply.tap(); sleep(2) }
            let after = canvasSize()
            check("A-124", "Apply Crop changes the canvas", before != after, "\(before.w)×\(before.h) → \(after.w)×\(after.h)")
            snapshot("A124-cropped"); app.typeKey("z", modifierFlags: .command)
        }
        if runs("125") {
            for n in ["Up down only", "Left right only"] {
                let b = app.buttons[n].firstMatch
                if reveal(b) { b.tap(); usleep(500_000); record("| A-125 | 👁 | \(n) on: selected=\(b.isSelected) · value=\(b.value ?? "") |") }
            }
            snapshot("A125-straight-line")
            // REM 16:5x — the in-test relaunch could not find the project again and stopped the batch; reopen is L7's job.
        }
        // A-124 recheck (16:5x): Height read 80% on three adjust() tries. Drag the thumb by hand, end to end.
        if runs("124h") {
            if !moveLines.contains(where: runs) { openNewImage(named: "A7 move page"); _ = placeShakedownPhoto("A124h"); press("Move"); sleep(2) }
            _ = pickMenu("Aspect", "Freeform")
            let h = app.sliders["Height"].firstMatch
            if reveal(h) {
                let v0 = (h.value as? String) ?? "?"
                h.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(forDuration: 0.2, thenDragTo: h.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
                sleep(1); let v1 = (h.value as? String) ?? "?"
                check("A-124", "Height slider moves when dragged", v0 != v1, "\(v0) → \(v1)"); snapshot("A124h-height")
            } else { record("| A-124 | ❓ | Height slider not found |") }
        }
        if runs("126") {
            for n in ["Fit", "Fill"] { if reveal(app.buttons[n].firstMatch) { app.buttons[n].firstMatch.tap(); sleep(1); snapshot("A126-\(n)") } }
        }
        if runs("127") {
            let pct = app.textFields["Scale percent"].firstMatch
            for v in ["25", "100", "400"] where reveal(pct) { setField(pct, v); pct.typeText("\n"); usleep(600_000); record("| A-127 | 👁 | Scale % \(v) → px \(app.textFields["Size in pixels"].firstMatch.value ?? "?") |") }
            let st = app.steppers["Scale"].firstMatch
            if reveal(st) { st.buttons.element(boundBy: 1).press(forDuration: 1.5); record("| A-127 | 👁 | Scale stepper held → \(pct.value ?? "?") % |") }
            slide("Scale", "A-127"); snapshot("A127-scale")
        }
        if runs("128") {
            for (f, v) in [("Position X", "100"), ("Position Y", "200")] {
                let t = app.textFields[f].firstMatch
                if reveal(t) { setField(t, v); t.typeText("\n"); usleep(500_000); record("| A-128 | 👁 | \(f) \(v) → \(t.value ?? "?") |") }
            }
            let rot = app.textFields["Rotation degrees"].firstMatch
            for v in ["90", "180", "-90"] where reveal(rot) { setField(rot, v); rot.typeText("\n"); usleep(500_000); record("| A-128 | 👁 | Rotation \(v) → \(rot.value ?? "?") |") }
            slide("Rotation", "A-128"); snapshot("A128-position-rotation")
        }
        if runs("129") {
            for n in ["Apply", "Flip Horizontal", "Flip Vertical", "Center", "Reset"] {
                let b = app.buttons[n].firstMatch
                if reveal(b) { b.tap(); usleep(700_000); snapshot("A129-\(n.replacingOccurrences(of: " ", with: "-"))") }
                else { record("| A-129 | ❓ | \(n) not found |") }
            }
        }
        // A-130 — on the canvas: drag the box and a corner (picture layer). Before/after shots + probe position.
        if runs("130") {
            if !moveLines.contains(where: runs) { openNewImage(named: "A7 move page"); _ = placeShakedownPhoto("A130"); press("Move"); sleep(2) }
            let p0 = probe()
            dragLayer(dx: CGFloat.random(in: 20...60), dy: CGFloat.random(in: 10...40)); snapshot("A130-dragged")
            let p1 = probe()
            record("| A-130 | 👁 | Drag the box: center \(p0.map { "\($0.x),\($0.y)" } ?? "?") → \(p1.map { "\($0.x),\($0.y)" } ?? "?") |")
        }
        // A-131 — arrow-key nudge: the iPhone simulator passes no hardware keys (testKeyProbe 11-22) → iPad pass.
        if runs("131") { record("| A-131 | ℹ️ | Hardware keys don't reach the iPhone simulator (testKeyProbe); checked in the iPad section |") }
        // A-132 to A-134 — Selection: shapes, Clear Inside/Outside, Copy, Deselect, double-tap.
        let selLines = ["132", "133", "134"]
        if selLines.contains(where: runs) {
            openNewImage(named: "A7 selection")
            _ = placeShakedownPhoto("A132")
            press("Selection"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
            snapshot("A132-selection-page")
        }
        func dragOnCanvas() {
            let c = app.descendants(matching: .any)["uitest.canvas"].firstMatch
            guard c.exists else { return }
            let a = c.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.2...0.35), dy: CGFloat.random(in: 0.3...0.4)))
            let b = c.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.6...0.8), dy: CGFloat.random(in: 0.6...0.7)))
            a.press(forDuration: 0.2, thenDragTo: b); sleep(1)
        }
        if runs("132") {
            for s in ["Rectangle", "Oval", "App Icon", "Freehand"] {
                if pickMenu("Shape", s) { dragOnCanvas(); snapshot("A132-\(s.replacingOccurrences(of: " ", with: "-"))") }
                else { record("| A-132 | ❓ | Shape \(s) not found in the menu |") }
            }
            if pickMenu("Shape", "Path") {
                let c = app.descendants(matching: .any)["uitest.canvas"].firstMatch
                for (x, y) in [(0.3, 0.3), (0.7, 0.35), (0.5, 0.7)] { c.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap(); usleep(400_000) }
                snapshot("A132-path-points")
                record("| A-132 | 👁 | Path: Close Path=\(app.buttons["Close Path"].exists) · Cancel Path=\(app.buttons["Cancel Path"].exists) |")
                if reveal(app.buttons["Close Path"].firstMatch) { app.buttons["Close Path"].firstMatch.tap(); sleep(1); snapshot("A132-path-closed") }
            }
        }
        if runs("133") {
            _ = pickMenu("Shape", "Rectangle")
            for (n, code) in [("Clear inside", "inside"), ("Clear outside", "outside")] {
                dragOnCanvas()
                if reveal(app.buttons[n].firstMatch) { app.buttons[n].firstMatch.tap(); sleep(1); snapshot("A133-\(code)"); app.typeKey("z", modifierFlags: .command); sleep(1) }
                else { record("| A-133 | ❓ | \(n) not found |") }
            }
            dragOnCanvas()
            for n in ["Copy", "Deselect"] {
                let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", n)).firstMatch
                if reveal(b) { b.tap(); sleep(1); snapshot("A133-\(n)") } else { record("| A-133 | ❓ | \(n) not found |") }
            }
        }
        if runs("134") {
            let c = app.descendants(matching: .any)["uitest.canvas"].firstMatch
            if c.exists { c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap(); sleep(1); snapshot("A134-double-tap") }
        }
        // A-135 to A-138 — Mask: Add, shapes, sides/points samples, character, SF Symbol, corners, Remove.
        let maskLines = ["135", "136", "137", "138"]
        if maskLines.contains(where: runs) {
            openNewImage(named: "A7 mask")
            _ = placeShakedownPhoto("A135")
            press("Mask"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
            if reveal(app.buttons["Add Mask"].firstMatch) { app.buttons["Add Mask"].firstMatch.tap(); sleep(1) }
            snapshot("A135-mask-added")
        }
        if runs("135") {
            for s in ["Square", "Circle", "App Icon", "Polygon", "Star", "Character"] {
                if pickMenu("Shape", s) {
                    if s == "Polygon" || s == "Star" {
                        let st = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Sides' OR label BEGINSWITH 'Points'")).firstMatch
                        if reveal(st) { for _ in 0..<Int.random(in: 1...4) { st.buttons.element(boundBy: 1).tap() }; record("| A-135 | 👁 | \(s) → \(st.label) |") }
                    }
                    snapshot("A135-\(s.replacingOccurrences(of: " ", with: "-"))")
                } else { record("| A-135 | ❓ | Mask shape \(s) not found |") }
            }
        }
        if runs("136") {
            let f = app.textFields["Symbol name"].firstMatch
            for name in ["heart.fill", "not.a.symbol.xyz"] where reveal(f) {
                setField(f, name); if reveal(app.buttons["Use"].firstMatch) { app.buttons["Use"].firstMatch.tap(); sleep(1) }
                snapshot("A136-\(name)")
            }
        }
        if runs("137") {
            if pickMenu("Corner ratio", "") { snapshot("A137-ratio-menu") }
            let t = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Free corners'")).firstMatch
            if reveal(t) { t.tap(); sleep(1); record("| A-137 | 👁 | Free corners → \(t.value ?? "?") |"); snapshot("A137-free-corners") }
            if reveal(app.buttons["Remove Mask"].firstMatch) { app.buttons["Remove Mask"].firstMatch.tap(); sleep(1); snapshot("A137-removed"); record("| A-137 | 👁 | Remove Mask → Add Mask back=\(app.buttons["Add Mask"].exists) |") }
        }
        if runs("138") { dragOnCanvas(); snapshot("A138-mask-dragged") }
        // A-139 / A-140 — Paint Drop Bucket: swatches, Fill Layer, Tolerance (random samples), tap inside / outside.
        if runs("139") || runs("140") {
            openNewImage(named: "A7 paint bucket")
            _ = placeShakedownPhoto("A139")
            press("Paint Drop Bucket"); sleep(2)
            app.buttons.matching(identifier: "Tool").allElementsBoundByIndex.first { $0.isHittable }?.tap(); sleep(1)
            snapshot("A139-bucket-page")
        }
        if runs("139") {
            let fill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fill'")).firstMatch
            if reveal(fill) { fill.tap(); sleep(1); snapshot("A139-filled"); app.typeKey("z", modifierFlags: .command); sleep(1) }
            else { record("| A-139 | ❓ | Fill Layer not found |") }
        }
        if runs("140") {
            slide("Tolerance", "A-140")
            let c = app.descendants(matching: .any)["uitest.canvas"].firstMatch
            if c.exists { c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1); snapshot("A140-tap-inside")
                          c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); sleep(1); snapshot("A140-tap-clear") }
        }
        record("| A7 | — | DONE |")
    }

    /// Do simulated hardware keys reach the app on this simulator? (A-102 Esc, 11-22.) A letter key in the editor,
    /// then Esc in the New Image sheet with no field focused, then Esc with the Name field focused.
    func testKeyProbe() throws {
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        openNewImage(named: "A7 key probe")
        press("Canvas Tool"); sleep(1)
        app.typeKey("k", modifierFlags: []); sleep(2)
        record("| KEY | — | Letter K in the editor → Color Palette selected: \(button("Color Palette").isSelected) |")
        app.buttons["BackButton"].firstMatch.tap(); sleep(3)
        let new = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex.filter(\.isHittable).sorted { $0.frame.minY < $1.frame.minY }
        new.first?.tap(); _ = app.buttons["Create"].waitForExistence(timeout: 10); sleep(2)
        record("| KEY | — | Sheet up; keyboard focus anywhere: \(app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == 1")).count) |")
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: []); sleep(2)
        record("| KEY | — | Esc, nothing focused → sheet closed: \(!app.buttons["Create"].exists) |")
        if app.buttons["Create"].exists {
            app.textFields["File name"].firstMatch.tap(); sleep(1)
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: []); sleep(2)
            record("| KEY | — | Esc, Name focused → sheet closed: \(!app.buttons["Create"].exists) |")
        }
    }

    /// A-114 stall (11-22): tap Project name on the Canvas page and hold 40 s, so the Mac can measure the app's CPU.
    func testNameFieldIdle() throws {
        XCUIDevice.shared.orientation = .portrait; sleep(2)
        openNewImage(named: "A7 idle \(Int(Date().timeIntervalSince1970) % 100000)")
        // REM 13:0x — the blank-image probe did not stall; the stalled A-114 run had a photo placed first.
        if ProcessInfo.processInfo.environment["IDLE_PHOTO"] == "1" {
            record("| IDLE | — | photo placed: \(placeShakedownPhoto("IDLE")) |")
        }
        press("Canvas Tool"); sleep(2)
        let f = app.textFields["Project name"].firstMatch
        record("| IDLE | — | READY tapping Project name |")
        if f.waitForExistence(timeout: 5) { f.tap() }
        record("| IDLE | — | TAPPED |")
        sleep(5)
        // The A-114 stall came while typing, so type it the same way A-114 does and time each step.
        let t0 = Date()
        record("| IDLE | — | field hittable: \(f.isHittable) in \(Int(Date().timeIntervalSince(t0))) s |")
        let t1 = Date()
        snapshot("IDLE-before-type")
        setField(f, "A7 canvas renamed")
        snapshot("IDLE-after-type")
        record("| IDLE | — | setField in \(Int(Date().timeIntervalSince(t1))) s |")
        let t2 = Date()
        f.typeText("\n")
        record("| IDLE | — | Return in \(Int(Date().timeIntervalSince(t2))) s |")
        sleep(10)
        snapshot("IDLE-after")
    }

    func testPhoneFloatingPreviewSetting() throws {
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        openNewImage()
        press("Canvas Tool"); sleep(2)
        snapshot("s01-canvas-page")
        let pip = app.descendants(matching: .any)["pip.panel"].firstMatch
        check("438", "The preview shows by default", pip.waitForExistence(timeout: 3))
        check("438", "No Floating preview switch on the Canvas page",
              !app.switches["Floating preview"].exists && !app.staticTexts["Floating preview"].exists)

        // The Settings app ▸ Apps ▸ Image Producer.
        let prefs = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        prefs.launch(); sleep(2)
        func scrollFind(_ e: XCUIElement) -> Bool {
            var n = 0
            // REM 13:3x run: the row "existed" off screen, the tap missed, and the search ran on.
            // Scroll until it can really be tapped.
            while !(e.exists && e.isHittable) && n < 15 { prefs.swipeUp(); sleep(1); n += 1 }
            return e.exists && e.isHittable
        }
        let apps = prefs.staticTexts["Apps"].firstMatch
        if scrollFind(apps) { apps.tap(); sleep(2) }
        // REM 13:4x run: staticTexts["Image Producer"].firstMatch was the "◀ Image Producer" back-to-app link in
        // the status bar, not the list row. Search the list, then take a match below the nav bar.
        // REM 14:3x runs: the result row sat at y≈110, so the old "minY > 150" filter threw it away. And on a freshly
        // erased simulator, Settings search says "No Results" (its index isn't built yet) even though the app is listed.
        // So scroll the Apps list itself; the status-bar link is never a cell — take the cell that holds the label.
        let row = prefs.cells.containing(NSPredicate(format: "label == 'Image Producer'")).firstMatch
        guard scrollFind(row) else {
            snapshot("s02-settings-no-row")
            check("438", "Image Producer appears in the Settings app", false); return
        }
        row.tap(); sleep(2)
        let sw = prefs.switches["Floating Preview"].firstMatch
        let found = scrollFind(sw)
        prefs.screenshot().attach(self, "s03-settings-page")
        check("438", "Settings app shows the Floating Preview switch", found)
        guard found else { return }
        check("438", "It reads on by default", (sw.value as? String) == "1", "value \(sw.value ?? "nil")")
        sw.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); sleep(1)
        prefs.screenshot().attach(self, "s04-settings-off")
        check("438", "Switch turns off", (sw.value as? String) == "0", "value \(sw.value ?? "nil")")

        // REM 15:0x run: the video never showed the app between "off" and "on" — the check may have read a
        // background app. Wait until it is really in front, then give the preview time to go.
        app.activate()
        check("438", "Image Producer comes back to the front", app.wait(for: .runningForeground, timeout: 10))
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pip)
        let goneOK = XCTWaiter().wait(for: [gone], timeout: 5) == .completed
        snapshot("s05-canvas-preview-off")
        check("438", "Back in the app, the preview is gone", goneOK)

        // Put it back on so the simulator is left as found.
        prefs.activate(); sleep(2)
        sw.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); sleep(1)
        check("438", "Switch turns back on", (sw.value as? String) == "1", "value \(sw.value ?? "nil")")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        snapshot("s06-canvas-preview-on")
        check("438", "Back in the app, the preview returns", pip.waitForExistence(timeout: 3))
    }
}

private extension XCUIScreenshot {
    func attach(_ test: XCTestCase, _ name: String) {
        let a = XCTAttachment(screenshot: self); a.name = name; a.lifetime = .keepAlways; test.add(a)
    }
}
#endif
