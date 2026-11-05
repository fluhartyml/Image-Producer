//
//  Image_ProducerUITests.swift
//  Image ProducerUITests
//
//  REM: THE SHAKEDOWN, his ask 11-04: "can you do a shake down like you do during the white hat
//  security shakedown / inventory" — the Legend pattern. Drives the Mac app by accessibility
//  name and keyboard (his rule: drive our apps through VoiceOver and keyboard, not screenshots),
//  checks builds 355–359 and 366, inventories each screen (*.txt) and runs Apple's accessibility audit
//  (ACCESSIBILITY.md). Launches with -ImageProducerUITest (UITestDoor.swift): the test's image
//  lives in the app's temporary folder, not his iCloud folder; his recents and lifetime project
//  number are untouched. Results: RESULTS.md in the runner's tmp/ImageProducerUITestResults,
//  copied into the repo by Scripts/run-ui-tests.sh.
//

import XCTest

#if os(macOS)
// REM: Mac only — it drives the menu bar and the mouse. The iPad's own shakedown is
// Image_ProducerUITests_iPad.swift (his ask 11-04: "write the ipad shakedown and run it").
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
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'canvas.element'", label)).firstMatch
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
        press("Canvas Tool"); sleep(1); press("Move"); sleep(1)
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
            target.click(); sleep(1)
            let after = app.buttons.matching(NSPredicate(format: "label MATCHES 'Color [0-9]+, .*'")).allElementsBoundByIndex
            let selected = after.filter { $0.isSelected }.map { $0.label }
            check("356", "Pressing a swatch picks that color", selected == [name],
                  "pressed \(name); selected now: \(selected.joined(separator: " · "))")
        } else {
            check("356", "Pressing a swatch picks that color", false, "no unselected swatch to press")
        }
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

        // 366 — 012 / A4 number fields: type the layer's center, no drag.
        func typeInto(_ spoken: String, _ text: String) -> Bool {
            let f = app.textFields[spoken]
            guard f.waitForExistence(timeout: 3) else { return false }
            // REM 11-05 07:29 run: Rotation sat low in the inspector (y 942) and a click gave it
            // no keyboard focus, which stopped the whole run. Scroll the inspector under the
            // field's column until a click takes, then type; give up cleanly (a FAIL, not a crash).
            func focused() -> Bool { (f.value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
            let win = app.windows.matching(NSPredicate(format: "title CONTAINS '.imgprd'")).firstMatch
            for dy in [0.0, -250, -250, -250, 500, 500] {
                if dy != 0, win.exists {
                    win.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: f.frame.midX - win.frame.minX, dy: win.frame.height * 0.5))
                        .scroll(byDeltaX: 0, deltaY: dy)
                    sleep(1)
                }
                f.click(); usleep(300_000)
                if focused() { break }
            }
            guard focused() else {
                record("| — | ⚠️ NOT TYPED | '\(spoken)' never took keyboard focus (frame \(f.frame)) |")
                return false
            }
            // REM 11-05 07:35 run: "Crop width" read 922 after typing 400 — exactly the clamp a
            // huge number hits (819 box, left edge 102 → 922 of room), so ⌘A had not selected
            // and 400 was appended. Clear for certain: end of field, delete everything, type.
            f.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .command)
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
            f.typeText(text + "\r"); sleep(1)
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

        // REM: 011 / A3 (355), his ask 11-05 07:2x: "yes add the checks and run it" — the 07:14
        // run never tried the Mac letters or the guard. A letter typed INTO a number box stays
        // in the box; it must not switch tools (the key monitor skips an NSText first responder).
        let px = app.textFields["Position X"]
        if px.exists {
            px.click(); px.typeKey("a", modifierFlags: .command); px.typeText("b"); sleep(1)
            check("355", "Typing B in a number box leaves the tool alone (still Move)", button("Move").isSelected)
            px.typeKey("a", modifierFlags: .command); px.typeText("100\r"); sleep(1)
        }

        // REM: 012 / A4 (366) remainder, same ask — the typed Rotation box, and the Crop and Mask
        // boxes, were never typed into. The probe carries no rotation; the Rotation stepper's
        // spoken value ("N degrees") is read from the model, so it proves the typed value landed.
        func fieldNumber(_ spoken: String) -> Double {
            Double((app.textFields[spoken].value as? String ?? "").replacingOccurrences(of: ",", with: "")) ?? -1
        }
        if !typeInto("Rotation degrees", "30") {
            check("366", "Typing Rotation 30 turns the layer to 30 degrees", false, "couldn't type into the box")
        } else {
            let turned = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == 'Rotation' AND value == '30 degrees'")).firstMatch.exists
            check("366", "Typing Rotation 30 turns the layer to 30 degrees", turned,
                  "field reads \(app.textFields["Rotation degrees"].value as? String ?? "?")")
            _ = typeInto("Rotation degrees", "0")
        }

        // Crop: pick Square (a locked 1:1 ratio), then type the box.
        let aspect = app.popUpButtons["Aspect"].exists ? app.popUpButtons["Aspect"] : app.menuButtons["Aspect"]
        if aspect.waitForExistence(timeout: 3) {
            aspect.click(); sleep(1)
            if app.menuItems["Square"].waitForExistence(timeout: 3) { app.menuItems["Square"].click(); sleep(1) }
            let cropNames = ["Crop left", "Crop top", "Crop width", "Crop height"]
            check("366", "Crop left, top, width and height fields are there by name",
                  cropNames.allSatisfy { app.textFields[$0].waitForExistence(timeout: 3) })
            if typeInto("Crop width", "400") {
                let w = fieldNumber("Crop width"), h = fieldNumber("Crop height")
                check("366", "Square crop: typing Width 400 makes Height 400 (ratio held)",
                      w == 400 && h == 400, "width \(w), height \(h)")
            }
            if typeInto("Crop left", "100"), typeInto("Crop top", "50") {
                let l = fieldNumber("Crop left"), t = fieldNumber("Crop top")
                check("366", "Typing Crop left 100, top 50 moves the crop box there", l == 100 && t == 50, "left \(l), top \(t)")
            }
            // Back to Original so the crop can't touch the checks after this one.
            aspect.click(); sleep(1)
            if app.menuItems["Original"].waitForExistence(timeout: 3) { app.menuItems["Original"].click(); sleep(1) }
        } else {
            record("| 366 | ⚠️ NOT CHECKED | Crop fields — the Aspect menu wasn't found by name |")
        }
        snapshot("04b-number-fields")

        // Mask: add one, type its box, remove it.
        press("Mask"); sleep(1)
        if press("Add Mask", 5) {
            sleep(1)
            let maskNames = ["Mask left", "Mask top", "Mask width", "Mask height"]
            check("366", "Mask left, top, width and height fields are there by name",
                  maskNames.allSatisfy { app.textFields[$0].waitForExistence(timeout: 3) })
            if typeInto("Mask left", "100"), typeInto("Mask top", "80") {
                let l = fieldNumber("Mask left"), t = fieldNumber("Mask top")
                check("366", "Typing Mask left 100, top 80 moves the mask there", l == 100 && t == 80, "left \(l), top \(t)")
            }
            if typeInto("Mask width", "300") {
                let w = fieldNumber("Mask width")
                check("366", "Typing Mask width 300 sizes the mask", w == 300, "width \(w), height \(fieldNumber("Mask height"))")
            }
            snapshot("04c-mask-fields")
            press("Remove Mask"); sleep(1)
        } else {
            record("| 366 | ⚠️ NOT CHECKED | Mask fields — Add Mask wasn't found by name |")
        }
        press("Move"); sleep(1)
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
                     "Zoom", "Camera"]
        var missed: [String] = []
        for t in tools {
            let b = button(t)
            guard b.waitForExistence(timeout: 3) else { missed.append("\(t) (not found)"); continue }
            b.click(); sleep(1)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); sleep(1)
            }
            if !button(t).isSelected { missed.append(t) }
        }
        check("015", "Every tool picked by its spoken name shows as selected (\(tools.count) tools)",
              missed.isEmpty, missed.isEmpty ? "all \(tools.count)" : "missed: \(missed.joined(separator: ", "))")
        audit("After the tool walk")

        // REM: 011 / A3 (355), his ask 11-05 07:2x — every tool letter on the Mac, no modifier
        // (Sticky Keys). Same letters as Tool.shortcutLetter, same order as the walk above.
        let letters: [(String, String)] = [
            ("c", "Canvas Tool"), ("k", "Color Palette"), ("m", "Move"), ("s", "Selection"),
            ("q", "Mask"), ("b", "Paint Drop Bucket"), ("p", "Pixel Pen"), ("e", "Eraser"),
            ("i", "Eyedropper"), ("t", "Text"), ("y", "Symbol"), ("g", "Image"),
            ("a", "Image Playground"), ("l", "Layer"), ("r", "Remove Background"), ("w", "Magic Lasso"),
            ("j", "Adjust"), ("z", "Zoom"), ("h", "Camera")]
        var keyMissed: [String] = []
        for (k, t) in letters {
            app.typeKey(k, modifierFlags: []); sleep(1)
            if app.sheets.firstMatch.exists || app.alerts.firstMatch.exists {
                app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); sleep(1)
            }
            if !button(t).isSelected { keyMissed.append("\(k.uppercased())→\(t)") }
        }
        check("355", "Every tool letter picks its tool on the Mac (\(letters.count) keys)",
              keyMissed.isEmpty, keyMissed.isEmpty ? "all \(letters.count)" : "missed: \(keyMissed.joined(separator: ", "))")
    }
}
#endif
