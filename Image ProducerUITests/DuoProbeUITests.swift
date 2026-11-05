import XCTest
// TEMP (13:5x): pick "On My iPhone" in Apple's browser (page off), then try our page's New Image.
final class DuoProbeUITests: XCTestCase {
    func testPickLocationThenOurNewImage() {
        var app = XCUIApplication(); app.launchArguments += ["-DuoNoPage"]; app.launch()
        sleep(5)
        let browse = app.buttons.matching(NSPredicate(format: "label == 'Browse'")).allElementsBoundByIndex.filter(\.isHittable).first
        browse?.tap(); sleep(2)
        let onMy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPhone'")).firstMatch
        print("DUOPROBE onMy=\(onMy.waitForExistence(timeout: 5))"); if onMy.exists { onMy.tap(); sleep(2) }
        app.terminate()
        app = XCUIApplication(); app.launch(); sleep(5)
        let ours = app.descendants(matching: .any)["duo.newImage"].firstMatch
        print("DUOPROBE page=\(ours.exists)"); ours.tap(); sleep(12)
        if app.buttons["Create"].exists { app.buttons["Create"].tap(); sleep(3) }
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DuoLaunchUITest")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: d.appendingPathComponent("ours-new.png"))
        print("DUOPROBE back=\(app.buttons["BackButton"].exists)")
    }
}
