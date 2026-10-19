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

    private func launch(_ screen: String = "map") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_SCREEN"] = screen
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

    /// The world map as the menu opens it (`HOUSECAT_SCREEN=world`): the home with Move house, the other cats'
    /// homes (a visit if they are open at this save's level), and moving as far as the "Move to …?" card, which is
    /// left with Stay so the save keeps its home.
    func testTheWorldMap() throws {
        let app = launch("world")
        let move = app.buttons["Move house"]
        XCTAssertTrue(move.waitForExistence(timeout: 60), "the world map")
        sleep(3)
        snap("world")
        let locked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Other cats'")).firstMatch
        let homes = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "'s home"))
        XCTAssertTrue(waitUntil(timeout: 10) { homes.count > 0 }, "the other cats' homes are on the globe")
        if locked.exists {
            snap("locked")
        } else if let home = homes.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            front(app)
            home.tap()
            let visit = app.buttons["Visit"]
            XCTAssertTrue(visit.waitForExistence(timeout: 5), "a home's card")
            sleep(2)
            snap("a home")
            visit.tap()
            let back = app.buttons["Back to the map"]
            XCTAssertTrue(back.waitForExistence(timeout: 10), "the visit")
            sleep(3)
            snap("visit")
            back.tap()
            XCTAssertTrue(move.waitForExistence(timeout: 10), "back on the world map")
        }

        // Move house: the place picker, then the card that asks.
        front(app)
        move.tap()
        let paris = app.buttons["Paris"]
        XCTAssertTrue(paris.waitForExistence(timeout: 5), "choosing a new place")
        paris.tap()
        let moveHere = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Move here'")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 15) { moveHere.exists && moveHere.isEnabled }, "Paris can be moved to")
        sleep(2)
        snap("moving to Paris")
        moveHere.tap()
        let moveTo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Move to Paris'")).firstMatch
        XCTAssertTrue(moveTo.waitForExistence(timeout: 5), "the card that asks before moving")
        sleep(1)
        snap("move to Paris?")
        let stay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Stay in' OR label == 'Not yet'")).firstMatch
        XCTAssertTrue(stay.exists, "a way to stay")
        stay.tap()
        app.buttons["Back"].tap()
        XCTAssertTrue(move.waitForExistence(timeout: 5), "back on the world map, the home where it was")
    }

    /// The house step's warning that the home changes with the seasons and the time of day
    /// (`HOUSECAT_SCREEN=homes`): under the homes on an iPad; on a phone, a card when Make it home is tapped, left with
    /// Back.
    func testTheHomeWarning() throws {
        let app = launch("homes")
        let makeItHome = app.buttons["Make it home"]
        XCTAssertTrue(makeItHome.waitForExistence(timeout: 60), "the house step")
        sleep(3)
        snap("homes")
        if app.descendants(matching: .any)["homeWarning"].exists {
            // An iPad: the warning is under the homes, and Make it home would choose (and change the save).
            return
        }
        front(app)
        makeItHome.tap()
        XCTAssertTrue(app.buttons["confirmHome"].waitForExistence(timeout: 5), "the card on a phone")
        sleep(1)
        snap("before you move in")
        app.buttons["Back"].firstMatch.tap()
        let confirm = app.buttons["confirmHome"]
        XCTAssertTrue(waitUntil(timeout: 3) { !confirm.exists }, "Back closes the card")
    }

    /// Move house from the cat's profile (Josh couldn't find it): the room, the profile's home row, then the map
    /// choosing a new place, closed again. Needs a save with a cat.
    func testMoveHouseFromTheProfile() throws {
        let app = launch("")
        let cat = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", your cat")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 60), "the room")
        sleep(3)
        front(app)
        cat.tap()
        let move = app.buttons["Move house"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "the profile's home row")
        sleep(1)
        snap("profile")
        move.tap()
        XCTAssertTrue(app.buttons["Paris"].waitForExistence(timeout: 15), "the map, choosing a new place")
        sleep(2)
        snap("move house")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(cat.waitForExistence(timeout: 10), "back in the room")
    }

    /// Puts a shared iPad back on its side after an upright run (the orientation stays after a test ends).
    func testTurnBack() {
        XCUIDevice.shared.orientation = .landscapeLeft
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
