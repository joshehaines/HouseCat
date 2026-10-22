import XCTest

/// The goal tracker on the room (CLAUDE.md "Goals you always see"), played as a new player meets it: a fresh save in
/// memory (`HOUSECAT_FRESH`, the device's save left alone) with a cat already made (`HOUSECAT_CAT`), the tour skipped.
/// The card shows Moving in and its next goal; Feed meets Breakfast, which ticks; a stroke meets Hello, you, and
/// Make it cosy slides in; a tap on it opens Decorate; All goals opens the Goals page. A debug build. Run on
/// the iPhone 18 Pro Max and the 13-inch iPad: `xcodebuild test … -only-testing:HouseCatUITests/GoalTrackerTests`.
/// Every screen is attached, and written to `SHOTS` when the runner has it (`TEST_RUNNER_SHOTS=<folder>`).
@MainActor
final class GoalTrackerTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // No StoreKit (no sandbox sign-in prompt).
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_FRESH"] = "1"
        app.launchEnvironment["HOUSECAT_CAT"] = "midnight"
        // The game is on its side; a device held upright gives sideways screenshots and taps.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testTheTrackerLeadsANewPlayer() throws {
        app.launch()
        skipTheTour()

        // On the room, top middle: the chapter and its first goal.
        let header = chapterHeader()
        XCTAssertTrue(header.shows(within: 15), "the tracker's Moving in")
        XCTAssertTrue(header.isHittable, "the tracker is on the room, not under something")
        let before = metCount()
        XCTAssertNotNil(before, "the header counts the chapter: \(header.label)")
        XCTAssertTrue(goalRow("Breakfast").shows(within: 5), "Breakfast on the tracker")
        snap("tracker")

        // Feed meets Breakfast: its row goes green and says Done, then the card moves on and counts it.
        let feed = careButton("Feed")
        XCTAssertTrue(feed.shows(within: 10), "Feed")
        feed.tapInFront()
        let ticked = goalRow("Breakfast", containing: "Done")
        let sawTick = ticked.shows(within: 6)
        if sawTick {
            // Into the tick, not its first frame.
            usleep(600_000)
            snap("breakfast ticked")
        }
        let counted = waitUntil(timeout: 10) { self.metCount() == (before ?? 0) + 1 }
        XCTAssertTrue(counted, "Breakfast met: \(chapterHeader().label)")
        XCTAssertTrue(sawTick || !goalRow("Breakfast").exists, "Breakfast ticked, or met and moved on")
        dismissCards()

        // A stroke meets Hello, you; Make it cosy comes onto the card (it shows one goal since 22 Oct).
        XCTAssertTrue(goalRow("Hello, you").shows(within: 5), "Hello, you next on the tracker")
        XCTAssertTrue(strokeTheCat(until: goalRow("Make it cosy")), "a stroke meets Hello, you and Make it cosy slides in")
        dismissCards()
        snap("make it cosy next")

        // A tap on Make it cosy opens Decorate.
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(tap(goalRow("Make it cosy"), until: { done.shows(within: 5) }), "Make it cosy opens Decorate")
        snap("decorate from make it cosy")
        done.tap()

        // All goals opens the Goals page, the two met ticked.
        XCTAssertTrue(chapterHeader().shows(within: 10), "the tracker back on the room")
        let page = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' milestones'")).firstMatch
        XCTAssertTrue(tap(chapterHeader(), until: { page.shows(within: 8) }), "All goals opens the Goals page")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Breakfast:' AND label CONTAINS ', done'")).firstMatch.exists,
            "Breakfast ticked on the Goals page"
        )
        sleep(1)
        snap("goals page")
        closeTop()
    }

    /// The debug screens for what is otherwise rare: a goal on the card ticked (`HOUSECAT_SCREEN=goaldone`) and
    /// Moving in's card (`chapter`).
    func testTheTickAndTheChapterCard() throws {
        app.launchEnvironment["HOUSECAT_SCREEN"] = "goaldone"
        app.launch()
        skipTheTour()
        XCTAssertTrue(goalRow("Breakfast", containing: "Done").shows(within: 10), "the first goal shown met")
        sleep(1)
        snap("goaldone")
        app.terminate()

        app.launchEnvironment["HOUSECAT_SCREEN"] = "chapter"
        app.launch()
        // Not dismissing cards: the chapter's card is closed with Lovely too.
        skipTheTour(dismissingCards: false)
        XCTAssertTrue(app.staticTexts["Moving in: done!"].shows(within: 10), "Moving in's card")
        let lovely = app.buttons["Lovely"]
        XCTAssertTrue(lovely.exists && lovely.isHittable, "the card's Lovely")
        sleep(1)
        snap("chapter")
        lovely.tapInFront()
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.staticTexts["Moving in: done!"].exists }, "Lovely closes the card")
    }

    // MARK: Helpers

    /// Past the launch curtain, the cold open outside (a tap opens the door) and the first visit's tour, and its
    /// welcome Beans. The tour starts a few seconds after the room is up, but only on a device that has not seen it
    /// (it is remembered on the device, not in the save `HOUSECAT_FRESH` replaces). No tap once the room is up: one on
    /// the cat would meet Hello, you before the tracker is checked.
    private func skipTheTour(dismissingCards: Bool = true) {
        let skip = app.buttons["Skip the tour"]
        let decorate = app.buttons["Decorate"]
        let arrival = Date().addingTimeInterval(90)
        while !(decorate.exists && decorate.isHittable), !skip.exists, Date() < arrival {
            XCUIApplication.frontTarget()
            if !decorate.exists {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(2)
        }
        XCTAssertTrue(decorate.exists || skip.exists, "the room")
        guard skip.shows(within: 10) else {
            if dismissingCards {
                dismissCards()
            }
            return
        }
        skip.tapInFront()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if app.buttons["Thank you"].exists {
                app.buttons["Thank you"].tapInFront()
            }
            if app.buttons["Decorate"].exists, app.buttons["Decorate"].isHittable, !app.buttons["Skip the tour"].exists {
                break
            }
            sleep(1)
        }
        if dismissingCards {
            dismissCards()
        }
    }

    /// The tracker's header: "Moving in, 0 of 9 done. All goals."
    private func chapterHeader() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Moving in,'")).firstMatch
    }

    /// How many of the chapter's goals are met, as the header says.
    private func metCount() -> Int? {
        let header = chapterHeader()
        guard header.exists else { return nil }
        // "Moving in, 1 of 9 done. All goals."
        return header.label.split(separator: ",").dropFirst().first?.split(separator: " ").first.flatMap { Int($0) }
    }

    /// A goal's row on the tracker: "Breakfast: Feed Pip.. 15 Beans. 10 XP" ("Done" while it ticks).
    private func goalRow(_ name: String, containing text: String? = nil) -> XCUIElement {
        let named = NSPredicate(format: "label BEGINSWITH %@", name + ":")
        let predicate = text.map { NSCompoundPredicate(andPredicateWithSubpredicates: [named, NSPredicate(format: "label CONTAINS %@", $0)]) } ?? named
        return app.buttons.matching(predicate).firstMatch
    }

    /// A care button, whose label carries its badge ("Feed, done today", "Play, 5 left").
    private func careButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
    }

    /// A tap on the cat's body (SpriteKit lists its nodes by name), else taps round the middle of the room (it follows
    /// the cat), until `shown` appears.
    private func strokeTheCat(until shown: XCUIElement) -> Bool {
        let torso = app.otherElements["Cat"].firstMatch.descendants(matching: .any)["torso"].firstMatch
        for _ in 0 ..< 3 where torso.exists && !torso.frame.isEmpty {
            torso.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapInFront()
            if shown.shows(within: 4) {
                return true
            }
        }
        var spots: [CGVector] = []
        for dy in stride(from: 0.3, through: 0.7, by: 0.08) {
            for dx in stride(from: 0.26, through: 0.74, by: 0.06) {
                spots.append(CGVector(dx: dx, dy: dy))
            }
        }
        spots.sort { hypot($0.dx - 0.5, $0.dy - 0.55) < hypot($1.dx - 0.5, $1.dy - 0.55) }
        for spot in spots {
            app.coordinate(withNormalizedOffset: spot).tapInFront()
            if shown.shows(within: 2.5) {
                return true
            }
            // A closed room tapped by mistake offers itself.
            dismissCards()
        }
        return false
    }

    /// Taps `element` until `opened`: while the cat's line is up under the card, the card lets a tap through to the
    /// line (which it closes).
    private func tap(_ element: XCUIElement, until opened: () -> Bool) -> Bool {
        for _ in 0 ..< 3 {
            element.tapInFront()
            if opened() {
                return true
            }
        }
        return false
    }

    private func gamesOpen() -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Play with' OR label CONTAINS 'plays left today'"))
            .firstMatch.shows(within: 8)
    }

    /// The top screen's Close (the last on screen), or Not now.
    private func closeTop() {
        if let close = app.buttons.matching(identifier: "Close").allElementsBoundByIndex.last(where: \.isHittable) {
            close.tapInFront()
        } else if app.buttons["Not now"].exists {
            app.buttons["Not now"].firstMatch.tapInFront()
        }
        sleep(1)
    }

    /// Cards that come up on their own: reminders after the first feed, a new level.
    private func dismissCards() {
        for _ in 0 ..< 4 {
            sleep(1)
            let card = ["Not now", "Lovely", "Got it"].map { app.buttons[$0].firstMatch }.first { $0.exists && $0.isHittable }
            guard let card else { return }
            card.tapInFront()
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
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(device) goals \(name).png"))
    }
}
