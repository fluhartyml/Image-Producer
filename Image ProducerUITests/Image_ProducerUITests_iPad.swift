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
        if !name.contains("testDuoLook") && !name.contains("testShakedownLayout") { XCUIDevice.shared.orientation = .landscapeLeft }
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
        // REM 2026-11-21 — shakedown rule 000.7 (his word): one project file per subsection, named for it.
        if let name, app.buttons["Create"].waitForExistence(timeout: 10) {
            let field = app.textFields["File name"].firstMatch
            if field.exists { field.tap(); field.typeText(name) }
            else { record("| — | ℹ️ INFO | New Image sheet has no Name field; file keeps its automatic name |") }
        }
        if press("Create", 10) { sleep(2) }
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
            let system = (app.toolbars.buttons.allElementsBoundByIndex + app.segmentedControls.buttons.allElementsBoundByIndex)
                .map(\.frame)
            let toolLabels = Set(tools.map(\.0))
            return app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }.compactMap { b in
                let f = b.frame
                guard !system.contains(f), !b.label.hasPrefix("Reorder"), !toolLabels.contains(b.label) else { return nil }
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

        // L1 — the launch screen.
        sleep(5)
        let launchNew = app.buttons.matching(NSPredicate(format: "label == 'New Image'")).allElementsBoundByIndex
            .filter { $0.isHittable }.sorted { $0.frame.minY < $1.frame.minY }.first
        snapshot("\(code)-L1-launch")
        check(code, "L1 Launch: New Image is on screen and tappable", launchNew != nil)
        let l1small = small("launch")
        check(code, "L1 Launch: every button is at least 44 × 44", l1small.isEmpty, l1small.joined(separator: ", "))
        let l1cut = offEdge()
        check(code, "L1 Launch: no text cut off at the edge", l1cut.isEmpty, l1cut.joined(separator: ", "))

        // L2 — a new image in its own named project, with a real photo on a layer.
        openNewImage(named: "\(code) \(shapeName)")
        snapshot("\(code)-L2-new")
        check(code, "L2 The editor opened", app.descendants(matching: .any)["uitest.canvas"].firstMatch.waitForExistence(timeout: 10))
        press("Image"); sleep(2)
        var placed = false
        if press("Import Image to New Layer…", 5) {
            sleep(3)
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
            if photo.waitForExistence(timeout: 5) { photo.tap(); sleep(4); placed = true }
            // REM 20:3x A1 run: the picker never found the photo and stayed open over the editor, so every
            // later check read nothing. If the photo wasn't picked, close the picker before going on.
            if !placed {
                for n in ["Cancel", "Close"] where app.buttons[n].firstMatch.exists { app.buttons[n].firstMatch.tap(); sleep(1); break }
            }
        }
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
            toolSizes.insert("\(Int(b.frame.width))×\(Int(b.frame.height))")
        }
        snapshot("\(code)-L3-toolbox")
        check(code, "L3 Every tool is on screen without scrolling", offScreen.isEmpty, offScreen.joined(separator: ", "))
        check(code, "L3 Tools sit in two rows", rows.count == 2, "\(rows.count) row(s)")
        check(code, "L3 Tool buttons are at least 44 × 44", toolSizes.allSatisfy { s in s.split(separator: "×").allSatisfy { Int($0) ?? 0 >= 44 } },
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
            // L6 — "The tool inspector is too narrow to work in" (his 439 feedback): sliders and fields need room.
            let narrow = (app.sliders.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex)
                // REM 2026-11-22 — a number field (Canvas W/H) hugs its number by his 10-11 design; the 120 bar
                // is for sliders and text you type words into.
                .filter { $0.exists && $0.isHittable && $0.frame.width < 120
                          && !(($0.value as? String).map { !$0.isEmpty && $0.allSatisfy(\.isNumber) } ?? false) }
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
