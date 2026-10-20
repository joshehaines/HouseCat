import XCTest

/// The Home Screen widget as a player adds and uses it (it needs the App Group, which a free-signed build on a
/// device does not have, so this runs in the simulator): the app is opened once so the App Group has the save and
/// the widget's pictures, the medium widget is added from the Home Screen's edit mode, its Feed and Pet are pressed
/// (the widget redraws: fed, and the streak), and its Visit and a tap on it open the app in the room. The widget is
/// taken off the Home Screen again at the end. Screenshots as in `ButtonSweepTests`.
@MainActor
final class WidgetTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var shots = 0

    func testTheMediumWidget() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_CAT"] = "ginger_tabby"
        app.launch()
        XCTAssertTrue(app.buttons["Decorate"].waitForExistence(timeout: 90), "the room")
        // The widget's pictures are made a moment after the room is up (behind the launch film).
        sleep(15)
        let name = app.label
        let wasFed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Feed, done today'")).firstMatch.exists
        XCUIDevice.shared.press(.home)
        sleep(2)

        removeTheWidgets(appName: name)
        try addTheWidget(appName: name)
        defer { removeTheWidgets(appName: name) }
        snap("widget added")

        let feed = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Feed '")).firstMatch
        let pet = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pet '")).firstMatch
        let visit = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Visit '")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 20), "the widget's Feed (the widget has the save)")
        XCTAssertTrue(pet.exists, "the widget's Pet")
        XCTAssertTrue(visit.exists, "the widget's Visit")
        // The widget's picture before and after Feed: an unfed cat's widget redraws (the bowl, the pose).
        let widget = theWidget(appName: name)
        let before = widget?.screenshot().pngRepresentation
        feed.tap()
        sleep(4)
        snap("widget fed")
        let after = widget?.screenshot().pngRepresentation
        if wasFed {
            XCTContext.runActivity(named: "Already fed today: Feed has nothing new to draw") { _ in }
        } else {
            XCTAssertNotEqual(before, after, "the widget redrew after Feed")
        }
        pet.tap()
        sleep(3)
        snap("widget petted")

        // Visit opens the app in the room.
        visit.tap()
        if !app.wait(for: .runningForeground, timeout: 15) {
            // On a simulator with another HouseCat build installed, both answer housecat://, and iOS picks one.
            let other = XCUIApplication(bundleIdentifier: "com.housecatgame.housecat")
            XCTAssertEqual(other.state, .runningForeground, "Visit opened a HouseCat")
            XCTContext.runActivity(named: "Visit opened the other HouseCat build on this simulator") { _ in }
            app.activate()
        }
        XCTAssertTrue(app.buttons["Decorate"].waitForExistence(timeout: 60), "Visit opened the room")
        sleep(2)
        snap("visit opened the app")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Feed, done today'")).firstMatch.waitForExistence(timeout: 10),
            "the widget's feed reached the app"
        )

        // A tap on the widget itself (not its buttons) opens the app too.
        XCUIDevice.shared.press(.home)
        sleep(2)
        if let widget = theWidget(appName: name) {
            widget.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            let other = XCUIApplication(bundleIdentifier: "com.housecatgame.housecat")
            let opened = app.wait(for: .runningForeground, timeout: 15) || other.state == .runningForeground
            XCTAssertTrue(opened, "a tap on the widget opened a HouseCat")
            snap("tap opened the app")
            XCUIDevice.shared.press(.home)
            sleep(1)
        }
    }

    // MARK: The Home Screen

    private func addTheWidget(appName: String) throws {
        // Hold an empty spot: the icons jiggle, with Edit (or +) at the top.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 2)
        sleep(1)
        snap("home edit")
        dumpSpringboard("edit mode")
        if springboard.buttons["Edit"].waitForExistence(timeout: 3) {
            springboard.buttons["Edit"].tap()
            sleep(1)
            let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'widget'")).firstMatch
            if add.waitForExistence(timeout: 3) {
                add.tap()
            }
        } else if springboard.buttons["Add Widget"].exists {
            springboard.buttons["Add Widget"].tap()
        } else {
            springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add'")).firstMatch.tap()
        }
        sleep(2)
        snap("widget gallery")
        dumpSpringboard("gallery")
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(appName)
            sleep(2)
        }
        // This build's own entry (a test build may sit beside another HouseCat).
        let exact = NSPredicate(format: "label == %@", appName)
        let loose = NSPredicate(format: "label BEGINSWITH %@", appName)
        let found = [
            springboard.cells.matching(exact).firstMatch, springboard.buttons.matching(exact).firstMatch,
            springboard.cells.matching(loose).firstMatch, springboard.buttons.matching(loose).firstMatch,
        ].first { $0.waitForExistence(timeout: 2) } ?? springboard.cells.matching(loose).firstMatch
        guard found.exists else {
            dumpSpringboard("no HouseCat")
            throw XCTSkip("HouseCat is not in the widget gallery")
        }
        found.tap()
        sleep(2)
        snap("housecat widgets")
        dumpSpringboard("housecat widgets")
        // The sizes page: the small first; one swipe left is the medium.
        springboard.swipeLeft()
        sleep(1)
        let addWidget = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), "Add Widget")
        addWidget.tap()
        sleep(2)
        let done = springboard.buttons["Done"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }
        sleep(2)
    }

    /// This app's widget on the Home Screen (an icon whose value says Widget).
    private func theWidget(appName: String) -> XCUIElement? {
        let widget = springboard.icons.matching(NSPredicate(format: "identifier == %@ AND value BEGINSWITH 'Widget'", appName)).firstMatch
        return widget.exists ? widget : nil
    }

    /// Every widget of this app taken off the Home Screen (a test run leaves none behind).
    private func removeTheWidgets(appName: String) {
        XCUIDevice.shared.press(.home)
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(1)
        for _ in 0 ..< 4 {
            guard let widget = theWidget(appName: appName) else { break }
            widget.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
            let remove = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Remove Widget'")).firstMatch
            guard remove.waitForExistence(timeout: 3) else {
                dumpSpringboard("no Remove Widget")
                break
            }
            remove.tap()
            let confirm = springboard.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Remove'")).firstMatch
            if confirm.waitForExistence(timeout: 3) {
                confirm.tap()
            }
            sleep(2)
        }
        XCUIDevice.shared.press(.home)
    }

    private func dumpSpringboard(_ name: String) {
        let text = XCTAttachment(string: springboard.debugDescription)
        text.name = "springboard \(name)"
        text.lifetime = .deleteOnSuccess
        add(text)
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        shots += 1
        let file = String(format: "widget %02d %@.png", shots, name)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(file))
    }
}
