import XCTest

/// Choosing the home's place as a finger does it (XCUITest; the simulator panel's taps don't reach the globe):
/// `testProbe` taps the turning globe, drags, pinches and searches, as any version of the map takes it (it showed
/// the glitches Josh saw on 19 Oct); `testChoosingAPlace` goes through the new way round. Opens the map straight
/// away (`HOUSECAT_SCREEN=map`, a debug build).
/// Every step is attached as a screenshot, and written to `SHOTS` (a folder on the Mac) when the runner has it:
/// `TEST_RUNNER_SHOTS=<folder> xcodebuild test … -only-testing:HouseCatUITests/MapPickTests`.
/// `TEST_RUNNER_ORIENTATION=portrait` turns an iPad upright first.
@MainActor
final class MapPickTests: XCTestCase {
    private var shots = 0

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_SCREEN"] = "map"
        XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["ORIENTATION"] == "portrait" ? .portrait : .landscapeLeft
        app.launch()
        return app
    }

    func testProbe() throws {
        let app = launch()
        let liveHere = app.buttons["Live here"]
        XCTAssertTrue(liveHere.waitForExistence(timeout: 60), "the map")
        sleep(6)
        snap("spinning")
        // A tap on the turning globe.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        snap("tapped")
        sleep(3)
        snap("tapped 3s")
        // A drag and let go.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
        snap("dragged")
        sleep(2)
        snap("dragged 2s")
        // A pinch in.
        app.pinch(withScale: 2.5, velocity: 2)
        snap("pinched")
        sleep(2)
        snap("pinched 2s")
        // A search.
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("Manch")
        sleep(3)
        snap("typing")
        field.typeText("ester")
        sleep(3)
        snap("typed")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Manchester'")).firstMatch
        if result.waitForExistence(timeout: 5) {
            result.tap()
        }
        snap("chosen")
        sleep(4)
        snap("chosen 4s")
        print("MAPPROBE labels:", app.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label })
    }

    /// The new way round (Josh, 19 Oct): pick a city from the short list, tap the globe and see it snap to a
    /// named place, drag and pinch it, search and choose a suggestion; each time Live here comes on.
    func testChoosingAPlace() throws {
        let app = launch()
        let liveHere = app.buttons["Live here"]
        XCTAssertTrue(liveHere.waitForExistence(timeout: 60), "the map")
        sleep(4)
        snap("map")

        // A city from the short list.
        let paris = app.buttons["Paris"]
        XCTAssertTrue(paris.waitForExistence(timeout: 5), "the cities to pick")
        front(app)
        paris.tap()
        let name = app.staticTexts["placeName"]
        XCTAssertTrue(waitUntil(timeout: 5) { name.exists && name.label == "Paris, France" }, "the card names it")
        XCTAssertTrue(waitUntil(timeout: 15) { liveHere.isEnabled }, "Paris can be confirmed")
        sleep(2)
        snap("picked Paris")

        // A tap on the globe south-east of the pin, in the Alps: it snaps to a named place.
        front(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.5)).tap()
        sleep(1)
        snap("tapped")
        XCTAssertTrue(waitUntil(timeout: 15) { liveHere.isEnabled }, "the tapped place can be confirmed")
        sleep(2)
        snap("tapped and named")
        XCTAssertFalse(name.label.isEmpty || name.label.contains("°"), "named, not left as a coordinate: '\(name.label)'")
        print("MAPPROBE tapped:", name.label)

        // A drag, and a pinch: the pin stays where it was put.
        front(app)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.55)), withVelocity: .fast, thenHoldForDuration: 0)
        sleep(2)
        snap("dragged")
        app.pinch(withScale: 0.6, velocity: -1)
        sleep(2)
        snap("pinched out")

        // A search: suggestions as you type, one chosen.
        let field = app.textFields.firstMatch
        front(app)
        let top = field.frame.minY
        field.tap()
        field.typeText("Manch")
        // The search stays where it was (or moves up) while the keyboard is up: it used to slide down 53 points on a
        // landscape phone.
        XCTAssertLessThanOrEqual(field.frame.minY, top + 1, "the search box keeps its place")
        let manchester = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Manchester, England'")).firstMatch
        XCTAssertTrue(manchester.waitForExistence(timeout: 10), "a suggestion as you type")
        snap("typing")
        front(app)
        manchester.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { name.exists && name.label == "Manchester, England" }, "the card names it")
        XCTAssertTrue(waitUntil(timeout: 15) { liveHere.isEnabled }, "Manchester can be confirmed")
        sleep(3)
        snap("chose Manchester")
    }

    /// Other sessions' builds sometimes open over the app on a shared simulator: back to it first.
    private func front(_ app: XCUIApplication) {
        if app.state != .runningForeground {
            app.activate()
            sleep(2)
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(300_000)
        }
        return condition()
    }

    private func snap(_ name: String) {
        shots += 1
        let picture = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: picture)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let folder = ProcessInfo.processInfo.environment["SHOTS"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(String(format: "%02d %@.png", shots, name))
            try? picture.pngRepresentation.write(to: url)
        }
    }
}
