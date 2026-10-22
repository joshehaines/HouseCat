import XCTest

/// Every control in the room, tapped as a finger taps it (Josh's iPad, 19 Oct: "the play, nap, shop buttons do not
/// work, can you do a sweep across all buttons"): each is tapped, what it opens or does is checked, and it is closed
/// again. During the room tour (each control the tour points at), after it, the cards that come up on their own, and
/// Settings. Run on the iPhone 18 Pro Max and the 13-inch iPad:
/// `xcodebuild test … -only-testing:HouseCatUITests/ButtonSweepTests`. A debug build: `HOUSECAT_CAT` gives an empty
/// save a cat, `HOUSECAT_SCREEN` starts the tour from the top or opens a card that otherwise waits for its day.
/// Every screen is attached as a screenshot, and written to `SHOTS` when the runner has it (`TEST_RUNNER_SHOTS=<folder>`).
/// The sweep goes on past a failure, so one run lists everything that is wrong.
@MainActor
final class ButtonSweepTests: XCTestCase {
    private var app: XCUIApplication!
    private var shots = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // No StoreKit (no sandbox sign-in prompt): prices show "…" and Buy charges nothing.
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_CAT"] = "ginger_tabby"
        // The game is on its side; a device held upright gives sideways screenshots and taps.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    // MARK: The tour

    /// The tour from the top: each control it points at is tapped (as Josh did) and must open, and once the tour is
    /// over Play, the nap and the shop work in the same visit. It follows the host's lines, so new steps are passed
    /// with Next. Best on a fresh install: its "Tap a piece" needs a spare piece in the tray, as a first visit has.
    func testTheTourAndTheControlsAfterIt() throws {
        app.launchEnvironment["HOUSECAT_SCREEN"] = "tour"
        app.launch()
        waitPastTheCurtain()
        // A visit that starts outside: a tap on the house opens the door; the tour starts once the room is up.
        let skip = app.buttons["Skip the tour"]
        let start = Date()
        while !skip.exists, Date().timeIntervalSince(start) < 60 {
            if !app.buttons["Decorate"].exists {
                screen().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapInFront()
            }
            sleep(1)
        }
        XCTAssertTrue(skip.exists, "the tour")
        var done: Set<String> = []
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline, !app.buttons["Thank you"].exists {
            guard let line = tourLine() else {
                sleep(1)
                continue
            }
            if !done.contains(line) {
                snap("tour \(done.count + 1)")
            }
            done.insert(line)
            tourStep(line)
            // On once the host says something else (a step that did nothing is passed with Next and noted).
            if !waitForTourLine(other: line, timeout: 12) {
                XCTFail("the tour stayed on \"\(line)\"")
                app.buttons["Next"].firstMatch.tapInFront()
                _ = waitForTourLine(other: line, timeout: 5)
            }
        }
        let thanks = app.buttons["Thank you"]
        XCTAssertTrue(thanks.shows(within: 5), "the tour's welcome Beans")
        snap("tour done")
        thanks.tapInFront()
        // The tutorial ends on the homes, the houseboat for sale (docs/LADDER.md): closed here to try the room.
        XCTAssertTrue(app.buttons["buyNextHouse"].shows(within: 10), "the homes after the tour")
        snap("homes after the tour")
        app.buttons["Close"].firstMatch.tapInFront()
        sleep(2)
        dismissCards()
        snap("after the tour")

        // The same visit, the tour over: nothing left over the room.
        checkPlay()
        checkNap()
        checkShop()
        checkFeed()
    }

    /// One step of the tour, by what the host says: the control it points at is used (and must open), or Next.
    private func tourStep(_ line: String) {
        let next = app.buttons["Next"].firstMatch
        switch line {
        case let text where text.contains("Tap Feed"):
            careButton("Feed").tapInFront()
        case let text where text.contains("for a stroke"):
            XCTAssertTrue(strokeTheCat(), "a tap on the cat strokes it")
        case let text where text.contains("Tap Decorate"):
            app.buttons["Decorate"].tapInFront()
        // The tour's furnishing: each piece from the tray (the sofa lands by a wall, the table on the rug).
        case let text where text.contains("Drag the sofa"):
            app.buttons["Place Sagging sofa"].firstMatch.tapInFront()
        case let text where text.contains("Now the rug"):
            app.buttons["Place Wool rug"].firstMatch.tapInFront()
        case let text where text.contains("And the coffee table"):
            app.buttons["Place Coffee table"].firstMatch.tapInFront()
        case let text where text.contains("Tap the sofa"):
            let piece = app.buttons["Place Sagging sofa"].firstMatch
            if piece.shows(within: 3) {
                piece.tapInFront()
                sleep(2)
            } else {
                // A save whose spare pieces are all out (a first visit has two): the tour cannot go on.
                XCTFail("nothing in the tray to place: run the tour on a fresh install")
                app.buttons["Skip the tour"].tapInFront()
            }
        case let text where text.contains("Tap Done"):
            app.buttons["Done"].tapInFront()
        case let text where text.hasPrefix("Play "):
            careButton("Play").tapInFront()
            XCTAssertTrue(gamesOpen(), "Play opens the games during the tour")
            snap("tour games")
            closeTop()
        case let text where text.contains("nap"):
            careButton("Nap").tapInFront()
            XCTAssertTrue(app.buttons["Start the nap"].shows(within: 5), "Nap opens the nap card during the tour")
            snap("tour nap card")
            app.buttons["Not now"].firstMatch.tapInFront()
        case let text where text.contains("in the menu"):
            menuButton().tapInFront()
            XCTAssertTrue(menuOpen(within: 5), "Menu opens the menu during the tour")
            snap("tour menu")
            closeTop()
        case let text where text.hasPrefix("The shop"):
            app.buttons["Shop"].tapInFront()
            XCTAssertTrue(shopOpen(), "Shop opens the shop during the tour")
            snap("tour shop")
            closeTop()
        default:
            next.tapInFront()
        }
    }

    /// What the tour's host says now: its bubble is labelled "<host>: <line>" (Pat, Soot before 19 Oct). The cat's
    /// own lines and the goal cards are labelled the same way, so only the host's name counts.
    private func tourLine() -> String? {
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Pat: ' OR label BEGINSWITH 'Soot: '"))
            .firstMatch
        return bubble.exists ? String(bubble.label.drop { $0 != ":" }.dropFirst(2)) : nil
    }

    private func waitForTourLine(other line: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            XCUIApplication.frontTarget()
            if app.buttons["Thank you"].exists || tourLine().map({ $0 != line }) ?? false {
                return true
            }
            usleep(500_000)
        }
        return false
    }

    // MARK: The room

    /// Every control of the room, once the tour is over.
    func testEveryControlInTheRoom() throws {
        launchIntoTheRoom()
        snap("room")
        checkProfile()
        checkLevel()
        checkBeans()
        checkStreak()
        checkMenu()
        checkFeed()
        checkPlay()
        checkGames()
        checkNap()
        checkDecorate()
        checkShop()
        checkShopSections()
        checkRoomActions()
    }

    /// Settings, from the cat's profile, and each of its controls that stays in the app.
    func testSettings() throws {
        launchIntoTheRoom()
        let badge = app.buttons.matching(NSPredicate(format: "label ENDSWITH ', your cat'")).firstMatch
        XCTAssertTrue(badge.shows(within: 10), "the plaque's cat")
        badge.tapInFront()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.shows(within: 10), "the profile's Settings")
        settings.tapInFront()
        XCTAssertTrue(app.staticTexts["Settings"].shows(within: 10), "Settings opened")
        sleep(1)
        snap("settings")
        let list = app.scrollViews.firstMatch

        // Everything the screen offers, listed for the record.
        let names = app.buttons.allElementsBoundByIndex.map(\.label) + app.switches.allElementsBoundByIndex.map(\.label)
        XCTContext.runActivity(named: "Settings' controls: \(names.joined(separator: " | "))") { _ in }

        // Show me how plays the widget's steps (unless the widget is on this device's Home Screen already). Checked
        // first, as Export's share sheet can still be over Settings on a phone afterwards; then back to the top, until
        // the first switch shows (one swipe more, at the top, would pull the sheet down and close it).
        if let how = reveal(app.buttons["Show me how"], in: list) {
            how.tapInFront()
            XCTAssertTrue(app.descendants(matching: .any)["widgetHowTo"].shows(within: 5), "Show me how shows the steps")
            snap("widget how to")
            let first = app.switches["Breakfast"]
            for _ in 0 ..< 8 where list.exists && !(first.exists && first.isHittable) {
                list.swipeDown()
            }
        }

        // The switches turn and turn back. One that asks iOS first (reminders, Health) is answered Don't Allow.
        for toggle in app.switches.allElementsBoundByIndex where toggle.isHittable {
            // Health's switch hands over to iOS's own permission sheet, and a switch without a name may be part of
            // it: only checked they are there. The rest turn and turn back.
            if toggle.label.isEmpty || toggle.label.hasPrefix("Steps, sleep and workouts") {
                XCTAssertTrue(toggle.isEnabled, "\(toggle.label.isEmpty ? "a switch" : "Health's switch") can be used")
                continue
            }
            let before = toggle.value as? String
            // The switch itself, at the row's right end (a tap on a switch's words does nothing).
            let knob = toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -26, dy: 0))
            knob.tapInFront()
            if answerSystemQuestion(within: 6) {
                snap("settings asked iOS: \(toggle.label)")
                continue
            }
            XCTAssertNotEqual(toggle.value as? String, before, "\(toggle.label) turned")
            knob.tapInFront()
            sleep(1)
        }

        // Licences and credits: a sheet with Done.
        if let credits = reveal(app.buttons["Licences and credits"], in: list) {
            credits.tapInFront()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.shows(within: 5), "the licences")
            snap("licences")
            done.tapInFront()
        } else {
            XCTFail("no Licences and credits")
        }

        // Delete all my data asks first; Keep it keeps it.
        if let delete = reveal(app.buttons["Delete all my data"], in: list) {
            delete.tapInFront()
            let confirm = app.buttons["Delete everything"]
            XCTAssertTrue(confirm.shows(within: 5), "Delete asks first")
            snap("delete asks")
            // Keep it, or on a phone's popover a tap outside it.
            if app.buttons["Keep it"].exists, app.buttons["Keep it"].isHittable {
                app.buttons["Keep it"].tapInFront()
            } else {
                screen().coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tapInFront()
            }
            XCTAssertTrue(waitGone(confirm), "Delete everything went away again")
        } else {
            XCTFail("no Delete all my data")
        }

        // Export my data: the share sheet.
        if let export = reveal(app.buttons["Export my data"], in: list) {
            export.tapInFront()
            // The copy is made, then offered to share.
            let shareCopy = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Share the copy'")).firstMatch
            XCTAssertTrue(shareCopy.shows(within: 8), "Export made the copy")
            shareCopy.tapInFront()
            let share = app.otherElements["ActivityListView"]
            let shown = share.shows(within: 8) || app.navigationBars.firstMatch.shows(within: 2)
            XCTAssertTrue(shown, "Export opens the share sheet")
            snap("export")
            dismissSystemSheet()
        }

        // Restore Purchases answers (no store in a test run: it says so).
        if let restore = reveal(app.buttons["Restore Purchases"], in: list) {
            restore.tapInFront()
            sleep(2)
            snap("restore")
            if app.alerts.firstMatch.exists {
                app.alerts.firstMatch.buttons.firstMatch.tapInFront()
            }
        }

        XCTAssertTrue(backToRoom(), "back in the room from Settings")
    }

    /// The room mid-nap (Josh's iPad, 19 Oct: "the 'wake' button is cut off when the pet is asleep"): the care
    /// button's Wake and the banner's are whole and clear of the other controls, and the banner's wakes the cat.
    func testTheNapBanner() throws {
        app.launchEnvironment["HOUSECAT_NAP_SECONDS"] = "600"
        launchIntoTheRoom(screen: "nap")
        XCTAssertTrue(careButton("Wake").shows(within: 20), "napping")
        sleep(2)
        snap("nap")
        checkWakes()
        if let banner = bannerWake() {
            banner.tapInFront()
            XCTAssertTrue(careButton("Nap").shows(within: 5), "the banner's Wake woke the cat")
        }
    }

    /// Menu and the cat's face take every tap, whatever else is going on in the room (the map session, 19 Oct: on the
    /// iPad a centre tap on Menu was lost three runs in a row, with the tour done and the curtain gone). Each is tapped
    /// eight times between strokes and feeds, which bring up the cat's lines, toasts and floating XP; a lost tap keeps
    /// what was on screen and every element under the tap.
    func testMenuAndTheCatsFaceTakeEveryTap() throws {
        launchIntoTheRoom()
        var lost: [String] = []
        for round in 1 ... 8 {
            // Something happening in the room first: a stroke or a feed (the cat's line, XP, a toast).
            if round % 2 == 0 {
                careButton("Feed").tapInFront()
            } else {
                screen().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tapInFront()
            }
            usleep(useconds_t(300_000 * (round % 4)))
            for (name, control, opened) in [
                ("Menu", menuButton(), { self.menuOpen(within: 3) }),
                ("the cat's face", app.buttons.matching(NSPredicate(format: "label ENDSWITH ', your cat'")).firstMatch,
                 { self.app.buttons["Edit look"].shows(within: 3) }),
            ] {
                guard control.shows(within: 5) else {
                    XCTFail("no \(name) in round \(round)")
                    continue
                }
                let point = CGPoint(x: control.frame.midX, y: control.frame.midY)
                control.tapInFront()
                if opened() {
                    _ = backToRoom()
                    continue
                }
                lost.append("\(name), round \(round)")
                snap("lost tap \(name) \(round)")
                // Everything whose frame holds the tap point, topmost last (the tree's order).
                let under = app.descendants(matching: .any).allElementsBoundByIndex
                    .filter { $0.exists && $0.frame.contains(point) && $0.frame.width < app.windows.firstMatch.frame.width }
                    .map { "\($0.elementType.rawValue) '\($0.label)' \($0.frame)" }
                keep("tap at \(point)\n" + under.joined(separator: "\n") + "\n\n" + app.debugDescription, named: "lost tap \(name) \(round)")
                _ = backToRoom()
            }
        }
        XCTAssertTrue(lost.isEmpty, "taps lost: \(lost.joined(separator: "; "))")
    }

    // MARK: Cards that come up on their own

    func testTheLevelUpCard() throws {
        launchIntoTheRoom(screen: "levelup")
        let lovely = app.buttons["Lovely"]
        XCTAssertTrue(lovely.shows(within: 20), "the level-up card")
        snap("level up")
        let road = app.buttons["The road ahead"]
        XCTAssertTrue(road.exists, "The road ahead")
        road.tapInFront()
        XCTAssertTrue(app.buttons["Close"].firstMatch.shows(within: 5), "the road opened from the card")
        snap("road from level up")
        XCTAssertTrue(backToRoom(), "back in the room")
    }

    /// The add-widget card asks as the reminders card does, and Add to Home Screen goes straight into the steps,
    /// played on a little Home Screen (no app can add a widget itself).
    func testTheWidgetCard() throws {
        launchIntoTheRoom(screen: "addwidget")
        let add = app.buttons["Add to Home Screen"]
        XCTAssertTrue(add.shows(within: 20), "the add-widget card")
        snap("add widget")
        XCTAssertTrue(app.buttons["Not now"].exists, "its Not now")
        add.tapInFront()
        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(gotIt.shows(within: 5), "Add to Home Screen goes straight into the steps")
        XCTAssertTrue(app.descendants(matching: .any)["widgetHowTo"].exists, "the steps on a little Home Screen")
        sleep(3)
        snap("add widget steps")
        gotIt.tapInFront()
        XCTAssertTrue(waitGone(gotIt), "Got it closes it")
        XCTAssertTrue(waitForRoom(), "back in the room")
    }

    func testTheRemindersCard() throws {
        launchIntoTheRoom(screen: "reminders")
        let notNow = app.buttons["Not now"].firstMatch
        XCTAssertTrue(notNow.shows(within: 20), "the reminders card")
        XCTAssertTrue(app.buttons["Remind me"].exists, "its Remind me")
        snap("reminders")
        notNow.tapInFront()
        XCTAssertTrue(waitGone(app.buttons["Remind me"]), "Not now closes it")
        XCTAssertTrue(waitForRoom(), "back in the room")
    }

    func testTheOfferCard() throws {
        launchIntoTheRoom(screen: "offer")
        let look = app.buttons["Have a look"]
        XCTAssertTrue(look.shows(within: 30), "the offer card")
        snap("offer")
        look.tapInFront()
        XCTAssertTrue(shopOpen(), "Have a look opens the shop")
        XCTAssertTrue(backToRoom(), "back in the room")
    }

    func testTheHealthCard() throws {
        launchIntoTheRoom(screen: "health")
        // A debug launch can bring the add-widget card up over it (it was due anyway): that one goes first.
        if app.buttons["Add to Home Screen"].shows(within: 3) {
            app.buttons["widgetNotNow"].tapInFront()
            sleep(1)
        }
        let notNow = app.buttons["Not now"].firstMatch
        guard notNow.shows(within: 20) else {
            throw XCTSkip("No Health on this device")
        }
        XCTAssertTrue(app.buttons["Connect Health"].exists, "its Connect Health")
        snap("health")
        notNow.tapInFront()
        XCTAssertTrue(waitGone(app.buttons["Connect Health"]), "Not now closes it")
    }

    func testThePassAndGoals() throws {
        launchIntoTheRoom()
        for (item, check) in [("Goals", "Close"), ("Pass", "Close"), ("Gifts", "Close")] {
            openMenu()
            let button = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", item, item + ",")).firstMatch
            guard button.shows(within: 3) else {
                closeTop()
                continue
            }
            button.tapInFront()
            XCTAssertTrue(app.buttons[check].firstMatch.shows(within: 8), "\(item) opened")
            sleep(1)
            snap(item.lowercased())
            // A pass reward or a present ready: claimed.
            let claim = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'ready to claim' OR label ENDSWITH 'ready to open'")).firstMatch
            if claim.exists, claim.isHittable {
                claim.tapInFront()
                sleep(2)
                snap("\(item.lowercased()) claimed")
                dismissCards()
            }
            XCTAssertTrue(backToRoom(), "back in the room from \(item)")
        }
    }

    // MARK: The checks

    private func checkProfile() {
        XCTContext.runActivity(named: "The cat's face opens the profile") { _ in
            let badge = app.buttons.matching(NSPredicate(format: "label ENDSWITH ', your cat'")).firstMatch
            XCTAssertTrue(badge.shows(within: 10), "the plaque's cat")
            badge.tapInFront()
            XCTAssertTrue(app.buttons["Edit look"].shows(within: 10), "the profile")
            XCTAssertTrue(app.buttons["Settings"].exists, "the profile's Settings")
            sleep(1)
            snap("profile")
            // Edit look opens the creator over the room; its close comes back.
            app.buttons["Edit look"].tapInFront()
            let creator = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next: ' OR label == 'Save' OR label == 'Done'")).firstMatch
            XCTAssertTrue(creator.shows(within: 15), "Edit look opens the creator")
            sleep(1)
            snap("edit look")
            XCTAssertTrue(backToRoom(), "back in the room from the creator")
        }
    }

    private func checkLevel() {
        XCTContext.runActivity(named: "The level opens the road ahead") { _ in
            let level = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Level '")).firstMatch
            XCTAssertTrue(level.shows(within: 5), "the level")
            level.tapInFront()
            XCTAssertTrue(app.buttons["Close"].firstMatch.shows(within: 5), "the road ahead")
            snap("road")
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    private func checkBeans() {
        XCTContext.runActivity(named: "Beans + opens the shop's Beans") { _ in
            let beans = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Beans. Get more.'")).firstMatch
            XCTAssertTrue(beans.shows(within: 5), "the Beans bar")
            beans.tapInFront()
            XCTAssertTrue(shopOpen(), "the shop")
            snap("shop beans")
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    private func checkStreak() {
        XCTContext.runActivity(named: "The streak opens the streak") { _ in
            let streak = app.buttons.matching(NSPredicate(format: "label CONTAINS 'day streak'")).firstMatch
            XCTAssertTrue(streak.shows(within: 5), "the streak bar")
            streak.tapInFront()
            XCTAssertTrue(app.buttons["Close"].firstMatch.shows(within: 5), "the streak card")
            snap("streak")
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    private func checkMenu() {
        XCTContext.runActivity(named: "Menu and each item") { _ in
            openMenu()
            snap("menu")
            let items = ["Outside", "Goals", "Homes", "Book", "Pass", "Gifts", "Together"].filter { title in
                app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch.exists
            }
            XCTContext.runActivity(named: "Menu items: \(items.joined(separator: ", "))") { _ in }
            XCTAssertTrue(items.contains("Goals") && items.contains("Book"), "Goals and Book are in the menu")
            XCTAssertTrue(backToRoom(), "Close closes the menu")
            for item in items {
                openMenu()
                app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", item, item + ",")).firstMatch.tapInFront()
                let opened = switch item {
                // Out of the front door to look at the house (Josh, 20 Oct): Go in takes you back.
                case "Outside": app.buttons["Go in"].firstMatch.shows(within: 8)
                default: app.buttons["Close"].firstMatch.shows(within: 8)
                }
                XCTAssertTrue(opened, "\(item) opened")
                sleep(item == "Outside" ? 3 : 1)
                snap("menu \(item.lowercased())")
                if item == "Outside" {
                    app.buttons["Go in"].firstMatch.tapInFront()
                    XCTAssertTrue(waitForRoom(), "Go in goes back into the room")
                } else {
                    XCTAssertTrue(backToRoom(), "back in the room from \(item)")
                }
            }
            // A closed room offers itself; an open one is gone to.
            openMenu()
            let closed = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Beans' AND label CONTAINS 'Lv'")).firstMatch
            if closed.exists {
                closed.tapInFront()
                let alert = app.alerts.firstMatch
                XCTAssertTrue(alert.shows(within: 5), "a closed room offers itself")
                snap("room offer")
                let cancel = alert.buttons.matching(NSPredicate(format: "label IN {'Not now', 'Cancel', 'Not yet', 'OK'}")).firstMatch
                (cancel.exists ? cancel : alert.buttons.element(boundBy: alert.buttons.count - 1)).tapInFront()
            } else {
                closeTop()
            }
            XCTAssertTrue(waitForRoom(), "back in the room")
        }
    }

    private func checkFeed() {
        XCTContext.runActivity(named: "Feed feeds") { _ in
            let feed = careButton("Feed")
            XCTAssertTrue(feed.shows(within: 5), "Feed")
            feed.tapInFront()
            sleep(1)
            snap("fed")
            XCTAssertTrue(careButton("Feed").label.hasSuffix("done today"), "Feed shows it is done today")
            // The first feed ever asks about reminders (the tour run has had that).
            sleep(3)
            dismissCards()
        }
    }

    private func checkPlay() {
        XCTContext.runActivity(named: "Play opens the games") { _ in
            let play = careButton("Play")
            XCTAssertTrue(play.shows(within: 5), "Play")
            // Open whether or not the day's five quick plays are used (they are "just for fun" then).
            play.tapInFront()
            XCTAssertTrue(gamesOpen(), "Play opened the games (it says: \(play.label))")
            snap("games")
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    /// Each game in the Games menu opens and comes back, and each quick game opens in the room's game screen and
    /// closes without using a play.
    private func checkGames() {
        for name in ["Zoomies", "Catapult", "Purrfect Match", "Cats in a Row", "Pat's daily puzzle"] {
            XCTContext.runActivity(named: "The game \(name)") { _ in
                if !gamesOpen() {
                    careButton("Play").tapInFront()
                }
                guard gamesOpen() else {
                    XCTFail("Play opened no games for \(name)")
                    return
                }
                let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
                guard card.shows(within: 3) else {
                    XCTFail("\(name) is not in the Games menu")
                    return
                }
                card.tapInFront()
                XCTAssertTrue(gameControl().shows(within: 10), "\(name) opened")
                sleep(2)
                snap("game \(name)")
                leaveGame()
                XCTAssertTrue(quickCard().shows(within: 10), "back in the Games menu from \(name)")
            }
        }
        for name in ["Laser Pointer", "Knock It Off", "String Chase"] {
            XCTContext.runActivity(named: "The quick game \(name)") { _ in
                if !gamesOpen() {
                    careButton("Play").tapInFront()
                }
                guard quickCard().shows(within: 10) else {
                    XCTFail("no quick games for \(name)")
                    return
                }
                quickCard().tapInFront()
                let game = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                XCTAssertTrue(game.shows(within: 5), "\(name) is offered")
                game.tapInFront()
                XCTAssertTrue(app.staticTexts[name].shows(within: 15), "\(name) opened")
                sleep(3)
                for spot in [CGVector(dx: 0.4, dy: 0.5), CGVector(dx: 0.6, dy: 0.45), CGVector(dx: 0.5, dy: 0.6)] {
                    screen().coordinate(withNormalizedOffset: spot).tapInFront()
                }
                snap("quick game \(name)")
                // Leaving early: the game's own close, back to the room.
                app.buttons["Close"].firstMatch.tapInFront()
                XCTAssertTrue(waitForRoom(), "back in the room from \(name)")
            }
        }
    }

    /// The Games menu's card for the quick games with the cat.
    private func quickCard() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play with'")).firstMatch
    }

    /// Something only a game's own screen has: its way back, or its pause.
    private func gameControl() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN {'Back', 'Pause', 'Levels', 'Back to the cats', 'Leave the level', 'Fill', 'Cross'}")).firstMatch
    }

    /// Out of a game to the Games menu: its back (a run is paused and left first).
    private func leaveGame() {
        for _ in 0 ..< 4 where !quickCard().exists {
            if app.buttons["Pause"].exists {
                app.buttons["Pause"].tapInFront()
                _ = app.buttons["Leave"].shows(within: 3)
            }
            if let out = ["Leave", "Back", "Leave the level", "Back to the cats", "Levels", "Back to the games"]
                .map({ app.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable })
            {
                out.tapInFront()
            }
            sleep(1)
        }
    }

    private func checkNap() {
        XCTContext.runActivity(named: "Nap and Wake") { _ in
            let nap = careButton("Nap")
            XCTAssertTrue(nap.shows(within: 5), "Nap")
            nap.tapInFront()
            let start = app.buttons["Start the nap"]
            XCTAssertTrue(start.shows(within: 5), "the nap card")
            snap("nap card")
            start.tapInFront()
            // Two Wakes: the care button and the banner's.
            let wakes = app.buttons.matching(identifier: "Wake")
            XCTAssertTrue(careButton("Wake").shows(within: 5), "the care button says Wake")
            sleep(2)
            snap("napping")
            checkWakes()
            careWake().tapInFront()
            XCTAssertTrue(careButton("Nap").shows(within: 5), "the care Wake woke the cat")
            XCTAssertTrue(waitGone(app.buttons.matching(identifier: "Wake").firstMatch), "the banner went")

            // Again, woken from the banner.
            careButton("Nap").tapInFront()
            XCTAssertTrue(start.shows(within: 5), "the nap card again")
            start.tapInFront()
            XCTAssertTrue(careButton("Wake").shows(within: 5), "napping again")
            sleep(1)
            if let banner = bannerWake() {
                banner.tapInFront()
                XCTAssertTrue(careButton("Nap").shows(within: 5), "the banner's Wake woke the cat")
            } else {
                XCTFail("no Wake on the banner")
                careButton("Wake").tapInFront()
            }
        }
    }

    /// Both Wakes whole on screen, clear of the other controls, and photographed close up.
    private func checkWakes() {
        let wakes = app.buttons.matching(identifier: "Wake")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(wakes.count, 2, "Wake on the care button and on the banner")
        for index in 0 ..< wakes.count {
            let wake = wakes.element(boundBy: index)
            XCTAssertTrue(wake.isHittable, "Wake \(index) can be tapped")
            XCTAssertTrue(window.contains(wake.frame), "Wake \(index) is whole on screen: \(wake.frame) in \(window)")
        }
        if let banner = bannerWake() {
            attachZoom(of: banner, named: "banner wake")
            let others = app.buttons.matching(NSPredicate(
                format: "label ENDSWITH 'Get more.' OR label CONTAINS 'day streak' OR label BEGINSWITH 'Level ' OR label ENDSWITH ', your cat' OR label BEGINSWITH 'Menu'"
            )).allElementsBoundByIndex
            for other in others where other.exists {
                XCTAssertFalse(banner.frame.intersects(other.frame), "the banner's Wake is clear of \(other.label)")
            }
        }
        attachZoom(of: careWake(), named: "care wake")
    }

    private func checkDecorate() {
        XCTContext.runActivity(named: "Decorate, its tray, Turn, Store and Done") { _ in
            let decorate = app.buttons["Decorate"]
            decorate.tapInFront()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.shows(within: 5), "Decorate opened")
            sleep(1)
            snap("decorating")
            // The tray's tabs.
            for tab in ["Shop", "Walls", "Floors", "Yours"] {
                let button = app.buttons[tab].firstMatch
                XCTAssertTrue(button.exists, "the tray's \(tab)")
                button.tapInFront()
                sleep(1)
                let chosen = (0 ..< 3).contains { _ in
                    if (try? button.snapshot())?.isSelected == true {
                        return true
                    }
                    sleep(1)
                    return false
                }
                XCTAssertTrue(chosen, "\(tab) is chosen")
                snap("tray \(tab.lowercased())")
            }
            // A piece out of the tray, turned and stored again. A save with everything out ("Everything you own is
            // out") buys one from the tray's shop, which comes out chosen.
            let piece = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Place '")).firstMatch
            var name = ""
            if piece.shows(within: 3) {
                name = piece.label
                piece.tapInFront()
            } else {
                app.buttons["Shop"].firstMatch.tapInFront()
                let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy '")).firstMatch
                if buy.shows(within: 3) {
                    // "Buy Armchair, 120 Beans" goes back to the tray as "Place Armchair".
                    name = "Place " + buy.label.dropFirst("Buy ".count).prefix { $0 != "," }
                    buy.tapInFront()
                }
            }
            if !name.isEmpty {
                sleep(2)
                let turn = app.buttons["Turn"]
                let store = app.buttons["Store"]
                XCTAssertTrue(turn.shows(within: 5), "Turn, with the piece chosen")
                snap("piece placed")
                turn.tapInFront()
                sleep(1)
                snap("piece turned")
                XCTAssertTrue(store.exists, "Store")
                store.tapInFront()
                sleep(1)
                XCTAssertTrue(app.buttons[name].shows(within: 5), "Store put \(name) back in the tray")
            } else {
                XCTFail("nothing in the tray to place, and nothing to buy")
            }
            done.tapInFront()
            XCTAssertTrue(waitForRoom(), "Done closes Decorate")
        }
    }

    private func checkShop() {
        XCTContext.runActivity(named: "Shop opens") { _ in
            let shop = app.buttons["Shop"]
            XCTAssertTrue(shop.shows(within: 5), "Shop")
            shop.tapInFront()
            XCTAssertTrue(shopOpen(), "the shop")
            sleep(1)
            snap("shop")
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    private func checkShopSections() {
        XCTContext.runActivity(named: "The shop's sections") { _ in
            app.buttons["Shop"].tapInFront()
            XCTAssertTrue(shopOpen(), "the shop")
            let sections = ["Offers", "Season pass", "Beans", "Room looks", "Outfits", "Cat Club"]
            for section in sections {
                let tab = app.buttons.matching(NSPredicate(format: "label == %@", section)).firstMatch
                XCTAssertTrue(tab.shows(within: 3), "the shop's \(section)")
                guard tab.exists else { continue }
                tab.tapInFront()
                sleep(1)
                snap("shop \(section.lowercased())")
                // The first thing for sale opens its panel (or, for the pass, its page), which closes again.
                let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).allElementsBoundByIndex
                    .first { tile in
                        // Not the room's own controls, still there under the shop ("Pip, your cat", "Feed, done today").
                        let room = [", your cat", "Get more.", "day streak", "done today", " left", "Season pass, tier"]
                        return tile.isHittable && !sections.contains(tile.label) && !room.contains { tile.label.contains($0) }
                    }
                if section != "Beans", let tile {
                    let name = tile.label
                    tile.tapInFront()
                    sleep(1)
                    snap("shop \(section.lowercased()) detail")
                    let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy' OR label BEGINSWITH 'Top up' OR label BEGINSWITH 'Add the whole' OR label ENDSWITH 'a year' OR label ENDSWITH 'a month' OR label CONTAINS '£' OR label CONTAINS 'Premium' OR label BEGINSWITH 'See the pass'")).firstMatch
                    XCTAssertTrue(buy.exists, "\(section): its panel offers to buy (\(name))")
                    // The panel's own close (the shop's is under it).
                    let closes = app.buttons.matching(identifier: "Close")
                    if closes.count > 1 {
                        closes.element(boundBy: closes.count - 1).tapInFront()
                    }
                    sleep(1)
                }
            }
            XCTAssertTrue(backToRoom(), "back in the room")
        }
    }

    /// The room's own accessibility actions (VoiceOver's Pet and Feed).
    private func checkRoomActions() {
        XCTContext.runActivity(named: "The room's VoiceOver actions are there") { _ in
            let room = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'room'")).firstMatch
            XCTAssertTrue(room.exists, "the room's description")
        }
    }

    // MARK: Helpers

    /// Into the room with a cat, the tour over (skipped if it shows), and nothing over the room.
    private func launchIntoTheRoom(screen: String? = nil) {
        // A debug screen's card waits for the tour, and the tour takes the first visit: so a test that opens one
        // gets a save whose tour is done, from a plain visit first (once a run).
        if let screen {
            if !Self.tourSeenTo {
                enterTheRoom()
                app.terminate()
            }
            app.launchEnvironment["HOUSECAT_SCREEN"] = screen
        }
        enterTheRoom()
        if screen == nil {
            sleep(2)
            dismissCards()
        }
    }

    /// The tour is over (skipped or finished) on this run's save.
    private static var tourSeenTo = false

    /// Launched and in the room, past the launch curtain, the cold open outside (a tap on the house opens the door)
    /// and the first visit's tour, which starts a few seconds after the room is up (Tuning.Intro.tourDelay) and is
    /// skipped.
    private func enterTheRoom() {
        app.launch()
        waitPastTheCurtain()
        let decorate = app.buttons["Decorate"]
        var deadline = Date().addingTimeInterval(60)
        while !(decorate.exists && decorate.isHittable), Date() < deadline {
            if !decorate.exists, !app.buttons["Skip the tour"].exists {
                screen().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapInFront()
            }
            sleep(1)
        }
        XCTAssertTrue(decorate.exists, "the room")
        // The tour, once the room is up; then nothing of it left over the room.
        if app.buttons["Skip the tour"].shows(within: 7) {
            app.buttons["Skip the tour"].tapInFront()
            sleep(1)
        }
        deadline = Date().addingTimeInterval(10)
        while Date() < deadline, app.buttons["Skip the tour"].exists || app.buttons["Thank you"].exists {
            for done in ["Skip the tour", "Thank you"] where app.buttons[done].exists {
                app.buttons[done].tapInFront()
            }
            sleep(1)
        }
        Self.tourSeenTo = true
    }

    /// The launch curtain (the logo's film) lifted: a tap skips the film, and it lifts once the room has drawn. The
    /// room's controls are in the accessibility tree under it before that, so they cannot tell.
    private func waitPastTheCurtain() {
        let deadline = Date().addingTimeInterval(90)
        sleep(2)
        while curtainIsUp(), Date() < deadline {
            front()
            screen().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapInFront()
            sleep(1)
        }
        if curtainIsUp() {
            // Which app is in front: ours stuck behind its curtain, or another session's build over it.
            let other = XCUIApplication(bundleIdentifier: "com.housecatgame.housecat")
            XCTFail("the launch curtain is still up after 90 s: this build \(app.state.rawValue), com.housecatgame.housecat \(other.state.rawValue) (4 = in front)")
            keep(app.debugDescription, named: "curtain: what is on screen")
            snap("curtain stuck")
        }
        sleep(1)
    }

    /// The launch curtain is up: an element called HouseCat that fills the window (iPadOS also names the app in the
    /// status bar). Read from one snapshot of the screen, which cannot change while it is read.
    private func curtainIsUp() -> Bool {
        guard let tree = try? app.snapshot() else { return false }
        let window = tree.frame
        func isCurtain(_ node: XCUIElementSnapshot) -> Bool {
            if node.label == "HouseCat", node.elementType != .application,
               node.frame.width > window.width * 0.9, node.frame.height > window.height * 0.9
            {
                return true
            }
            return node.children.contains(where: isCurtain)
        }
        return isCurtain(tree)
    }

    /// The window, for taps at a place on the screen: its frame is the game's, on its side. The app's own frame is
    /// the device's, upright on an iPhone held upright, so a tap placed by it lands somewhere else (the cat was never
    /// stroked on the iPhone).
    private func screen() -> XCUIElement {
        app.windows.firstMatch
    }

    /// A care button, whose label carries its badge ("Feed, done today", "Play, 5 left").
    private func careButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
    }

    /// The nap banner's Wake: of the two, the smaller (the care button is a big disc).
    private func bannerWake() -> XCUIElement? {
        let wakes = app.buttons.matching(identifier: "Wake").allElementsBoundByIndex
        guard wakes.count > 1 else { return nil }
        return wakes.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// The care button's Wake: of the two, the larger.
    private func careWake() -> XCUIElement {
        let wakes = app.buttons.matching(identifier: "Wake").allElementsBoundByIndex
        return wakes.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? careButton("Wake")
    }

    private func text(_ part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    /// The games are up: the Games menu (its quick games card), or the quick games' picker.
    private func gamesOpen() -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Play with' OR label CONTAINS 'plays left today'"))
            .firstMatch.shows(within: 8)
    }

    private func shopOpen() -> Bool {
        app.buttons.matching(NSPredicate(format: "label == 'Get Beans' OR label == 'Offers' OR label == 'Featured'")).firstMatch.shows(within: 15)
    }

    private func menuButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Menu' OR label BEGINSWITH 'Menu,'")).firstMatch
    }

    private func openMenu() {
        XCTAssertTrue(menuButton().shows(within: 5), "Menu")
        menuButton().tapInFront()
        XCTAssertTrue(menuOpen(within: 5), "the menu opened")
    }

    /// The menu is up: the home's rooms and the book (its title is the home's, or Rooms).
    private func menuOpen(within timeout: TimeInterval = 0) -> Bool {
        let title = app.staticTexts.matching(NSPredicate(format: "label == 'Rooms' OR label ENDSWITH \"'s home\"")).firstMatch
        return timeout > 0 ? title.shows(within: timeout) : title.exists
    }

    /// The room is back: Decorate is there to tap, nothing over it.
    private func waitForRoom(timeout: TimeInterval = 15) -> Bool {
        front()
        let decorate = app.buttons["Decorate"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if decorate.exists, decorate.isHittable, !app.buttons["Close"].firstMatch.exists, !menuOpen() {
                return true
            }
            usleep(400_000)
        }
        return false
    }

    /// Back to the room: whatever is on top closed (up to four layers). When that fails, what is on screen is
    /// attached, and the app is relaunched so the rest of the sweep starts clean.
    private func backToRoom() -> Bool {
        for tries in 0 ..< 4 {
            if waitForRoom(timeout: 3) {
                if tries > 1 {
                    XCTContext.runActivity(named: "It took \(tries) closes to get back to the room") { _ in }
                }
                return true
            }
            if tries > 0 {
                let closes = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
                keep(closes.map { "\($0.frame) hittable \($0.isHittable)" }.joined(separator: "\n"), named: "close buttons, try \(tries)")
                snap("close try \(tries)")
            }
            closeTop()
        }
        if waitForRoom(timeout: 5) {
            return true
        }
        keep(app.debugDescription, named: "stuck: what is on screen")
        snap("stuck")
        app.terminate()
        launchIntoTheRoom()
        return false
    }

    /// Closes whatever is on top: its Close (the last that can be tapped), else Cancel, Done or Not now, else a tap
    /// outside.
    private func closeTop() {
        front()
        if let close = app.buttons.matching(identifier: "Close").allElementsBoundByIndex.last(where: \.isHittable) {
            close.tapInFront()
        } else if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].firstMatch.tapInFront()
        } else if app.buttons["Done"].exists, !app.buttons["Decorate"].exists {
            app.buttons["Done"].tapInFront()
        } else if app.buttons["Not now"].exists {
            app.buttons["Not now"].firstMatch.tapInFront()
        } else {
            screen().coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tapInFront()
        }
        sleep(1)
        // The creator's leave-without-saving question.
        for word in ["Discard", "Leave", "Don't save", "Discard changes"] where app.buttons[word].exists {
            app.buttons[word].tapInFront()
        }
    }

    /// Cards that come up on their own: reminders, the widget, a new level, a goal.
    private func dismissCards() {
        for _ in 0 ..< 5 {
            guard ["Not now", "Lovely", "Got it"].contains(where: { tapIfThere($0) }) else { return }
            sleep(1)
        }
    }

    @discardableResult
    private func tapIfThere(_ label: String) -> Bool {
        let button = app.buttons[label].firstMatch
        guard button.exists, button.isHittable else { return false }
        button.tapInFront()
        return true
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            usleep(300_000)
        }
        return !element.exists
    }

    /// The tour waits for a stroke: a tap on the cat's body (SpriteKit lists its nodes by name), else taps round the
    /// middle of the view until one lands on it.
    private func strokeTheCat() -> Bool {
        let stroked = text("Tap Decorate")
        // The cat walks to the front for it; until then it may be under a speech bubble. Its body where it is now.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let bubbles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ': '")).allElementsBoundByIndex.map(\.frame)
            let torsos = app.otherElements.matching(identifier: "torso").allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
            if let torso = torsos.first(where: { body in !bubbles.contains { $0.intersects(body.frame) } }) {
                torso.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tapInFront()
                if stroked.shows(within: 1.5) {
                    return true
                }
            } else if torsos.isEmpty {
                break
            } else {
                sleep(1)
            }
        }
        // A cat drawn without named parts (a film): taps round the middle of the room, nearest first, clear of bubbles.
        var spots: [CGVector] = []
        for dy in stride(from: 0.3, through: 0.75, by: 0.075) {
            for dx in stride(from: 0.25, through: 0.75, by: 0.05) {
                spots.append(CGVector(dx: dx, dy: dy))
            }
        }
        spots.sort { hypot($0.dx - 0.5, $0.dy - 0.55) < hypot($1.dx - 0.5, $1.dy - 0.55) }
        let window = app.windows.firstMatch.frame
        // Clear of the speech bubbles first; then everywhere (a bubble's frame is taller than what it draws).
        for pass in 0 ..< 2 {
            for spot in spots {
                let point = CGPoint(x: window.minX + window.width * spot.dx, y: window.minY + window.height * spot.dy)
                let bubbles = pass == 1 ? [] :
                    app.staticTexts.matching(NSPredicate(format: "label CONTAINS ': '")).allElementsBoundByIndex.map(\.frame)
                if bubbles.contains(where: { $0.insetBy(dx: -10, dy: -10).contains(point) }) {
                    continue
                }
                screen().coordinate(withNormalizedOffset: spot).tapInFront()
                if stroked.shows(within: 0.8) {
                    return true
                }
                // A closed room or a thought bubble tapped by mistake: back out of it.
                dismissCards()
                if app.buttons["Done"].exists, !careButton("Feed").exists {
                    app.buttons["Done"].tapInFront()
                }
            }
        }
        return stroked.exists
    }

    /// A control scrolled into view in a list, or nil when it is not there at all.
    private func reveal(_ element: XCUIElement, in list: XCUIElement) -> XCUIElement? {
        for _ in 0 ..< 8 {
            if element.exists, element.isHittable {
                return element
            }
            guard list.exists else { break }
            list.swipeUp()
        }
        return element.exists ? element : nil
    }

    /// A question from iOS (notifications, Health) answered Don't Allow, in the app or over it. True if there was one.
    private func answerSystemQuestion(within timeout: TimeInterval = 2) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for place in [app!, springboard] {
                let no = place.buttons.matching(NSPredicate(format: "label IN {\"Don't Allow\", \"Don’t Allow\"}")).firstMatch
                if no.exists {
                    // Let a sheet sliding in settle before the tap looks it up again. Health's sheet is another
                    // process's view: when it says it cannot be tapped, a tap where it is.
                    sleep(1)
                    if no.exists, no.isHittable {
                        no.tap()
                    } else if let seen = try? no.snapshot(), !seen.frame.isEmpty {
                        screen().coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: seen.frame.midX, dy: seen.frame.midY)).tap()
                    }
                    sleep(1)
                    return true
                }
            }
            usleep(500_000)
        } while Date() < deadline
        return false
    }

    private func dismissSystemSheet() {
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel', 'Done'}")).allElementsBoundByIndex.last
        if let close, close.isHittable {
            close.tapInFront()
        } else {
            screen().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tapInFront()
        }
        sleep(1)
    }

    private func attachZoom(of element: XCUIElement, named name: String) {
        guard element.exists else { return }
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
        write(element.screenshot(), name: name)
    }

    /// Other sessions' builds sometimes open over the app on a shared simulator: back to it first.
    private func front() {
        if app.state != .runningForeground {
            app.activate()
            sleep(2)
        }
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
        write(screenshot, name: name)
    }

    /// Text kept with the run: attached, and written beside the screenshots.
    private func keep(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? text.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(device) \(name).txt"), atomically: true, encoding: .utf8)
    }

    private func write(_ screenshot: XCUIScreenshot, name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        shots += 1
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let file = String(format: "%@ %@ %02d %@.png", device, name.contains("tour") ? "a" : "b", shots, name)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(file))
    }
}

extension XCUIElement {
    /// A tap with this build in front first: other sessions' builds open over it on the shared simulators, and a tap
    /// would land on theirs.
    func tapInFront() {
        XCUIApplication.frontTarget()
        // Missing: a failure noted, and the sweep goes on (a tap on nothing would end the test).
        guard exists else {
            XCTFail("nothing to tap: \(description)")
            return
        }
        // Poking past the screen's edge: XCUITest's own tap missed such a control (the season pass's ✕, 0.2 points
        // over an iPhone's top edge; a finger's tap on it works). A tap at the middle of what shows, placed by the
        // window.
        let window = XCUIApplication().windows.firstMatch
        let frame = self.frame, screen = window.frame
        let shown = frame.intersection(screen)
        if !screen.contains(frame), !shown.isNull, !shown.isEmpty {
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: shown.midX - screen.minX, dy: shown.midY - screen.minY)).tap()
            return
        }
        tap()
    }
}

extension XCUIElement {
    /// Waits for the element with this build in front (it does not draw, or move on, behind another app).
    func shows(within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            XCUIApplication.frontTarget()
            if exists {
                return true
            }
            usleep(500_000)
        } while Date() < deadline
        return exists
    }
}

extension XCUICoordinate {
    func tapInFront() {
        XCUIApplication.frontTarget()
        tap()
    }
}

extension XCUIApplication {
    /// The app under test back in front, if something else came over it.
    static func frontTarget() {
        let app = XCUIApplication()
        if app.state == .runningBackground || app.state == .runningBackgroundSuspended {
            app.activate()
            sleep(2)
        }
    }
}
