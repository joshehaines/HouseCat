import XCTest

/// A new player's first run, played as a finger plays it: the intro, the builder, a pin on the globe, the home,
/// the door, the room's tour (Feed, a stroke, Decorate, a piece put out), a game, Decorate again, the shop and
/// Settings; then a relaunch. Every screen is attached to the result as a screenshot. It drives the app only through
/// what a player sees, so it also serves as the smoke test of a Release build (the debug switches compiled out). It
/// needs a fresh install (`xcrun simctl uninstall <udid> com.housecatgame.housecat` first); with a cat in the save
/// the first run skips. Both check the launch curtain lifts (19 Oct: it stayed up over a new player's first visit).
final class FirstRunTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // No StoreKit, which would ask for a sandbox sign-in: the shop's prices show "…".
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
    }

    func testAFreshInstallPlaysThroughTheFirstRun() throws {
        app.launch()
        let begin = app.buttons["Begin"]
        guard begin.waitForExistence(timeout: 60) else {
            throw XCTSkip("Needs a fresh install: the save already has a cat.")
        }
        try playTheIntro(begin)
        try makeTheCat()
        try goInside()
        try takeTheTour()
        try playAGame()
        try decorate()
        try visitTheShop()
        try openSettings()
    }

    /// After the first run (it needs the save it leaves): the next launch plays the logo film on the curtain, then
    /// the curtain lifts onto the room.
    func testARelaunchLiftsTheCurtain() throws {
        app.launch()
        if app.buttons["Begin"].waitForExistence(timeout: 15) {
            throw XCTSkip("Needs a save with a cat: run testAFreshInstallPlaysThroughTheFirstRun first.")
        }
        XCTAssertTrue(curtainLifts(within: 40), "the curtain lifts onto the room")
        let feed = careButton("Feed")
        XCTAssertTrue(feed.waitForExistence(timeout: 10) && feed.isHittable, "the room's controls")
        snap("22 relaunched")
    }

    // MARK: Onboarding

    private func playTheIntro(_ begin: XCUIElement) throws {
        sleep(2)
        snap("1 intro")
        begin.tap()
        // The host's hello, then the flight round the homes, each with its Next.
        let makeMyCat = app.buttons["Make my cat"]
        var stops = 0
        let deadline = Date().addingTimeInterval(150)
        while !makeMyCat.exists, Date() < deadline {
            if tapIfThere("Next home") {
                stops += 1
                if stops == 1 {
                    snap("2 intro home")
                }
            } else {
                _ = tapIfThere("Next")
            }
            sleep(1)
        }
        XCTAssertGreaterThan(stops, 0, "the intro visited its homes")
        XCTAssertTrue(makeMyCat.waitForExistence(timeout: 10), "the intro's end")
        makeMyCat.tap()
    }

    private func makeTheCat() throws {
        // Each drawer has a "Next: <drawer>" button; the first changes as the drawers do.
        let firstNext = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next: '")).firstMatch
        XCTAssertTrue(firstNext.waitForExistence(timeout: 30), "the builder")
        sleep(2)
        let ginger = app.buttons["Ginger Tabby"]
        if ginger.exists, ginger.isHittable {
            ginger.tap()
            sleep(2)
        }
        snap("3 builder")
        let name = app.textFields["Your cat's name"]
        let deadline = Date().addingTimeInterval(60)
        while !name.exists, Date() < deadline {
            let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next: '")).firstMatch
            if next.waitForExistence(timeout: 5) {
                next.tap()
                sleep(1)
            }
        }
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the name step")
        name.tap()
        // The word filter is in the Release build too.
        name.typeText("Shit")
        XCTAssertTrue(app.staticTexts["Try another name."].waitForExistence(timeout: 5), "a rude name is turned down")
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Pip\n")
        let bringHome = app.buttons["Bring Pip home"]
        XCTAssertTrue(bringHome.waitForExistence(timeout: 5), "the name is taken")
        snap("4 named")
        bringHome.tap()
    }

    private func goInside() throws {
        // The cold open outside; a tap opens the door (it opens on its own after a while too).
        sleep(4)
        snap("8 outside")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(curtainLifts(within: 30), "the curtain lifts onto the first visit")
    }

    // MARK: The room

    private func takeTheTour() throws {
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 60), "the tour's welcome")
        sleep(2)
        snap("9 room")
        // The steps that only ask to be read are passed with Next, until the tour asks for Feed.
        XCTAssertTrue(readOn(until: "Tap Feed"), "the tour asks for Feed")
        let feed = careButton("Feed")
        XCTAssertTrue(feed.waitForExistence(timeout: 10), "Feed")
        sleep(1)
        feed.tap()
        sleep(3)
        snap("10 fed")
        XCTAssertTrue(strokeTheCat(), "a tap on the cat strokes it")
        snap("11 stroked")
        let decorate = app.buttons["Decorate"]
        XCTAssertTrue(decorate.waitForExistence(timeout: 10), "Decorate")
        decorate.tap()
        let piece = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Place '")).firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 10), "the tray")
        piece.tap()
        sleep(2)
        snap("12 placed")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Done")
        done.tap()
        // Play, the nap, the menu and the shop are read and passed with Next; the Beans come last.
        let thanks = app.buttons["Thank you"]
        let deadline = Date().addingTimeInterval(40)
        while !thanks.exists, Date() < deadline {
            _ = tapIfThere("Next")
            sleep(1)
        }
        XCTAssertTrue(thanks.waitForExistence(timeout: 5), "the tour's welcome Beans")
        snap("13 tour done")
        thanks.tap()
        dismissCards()
    }

    /// The tour waits for a stroke: a tap on the cat's body (SpriteKit lists its nodes by name), else taps round the
    /// middle of the view (it follows the cat) until one lands on it.
    private func strokeTheCat() -> Bool {
        let stroked = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tap Decorate'")).firstMatch
        let torso = app.otherElements["Cat"].firstMatch.descendants(matching: .any)["torso"].firstMatch
        for _ in 0 ..< 3 where torso.exists && !torso.frame.isEmpty {
            torso.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if stroked.waitForExistence(timeout: 1.5) {
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
            app.coordinate(withNormalizedOffset: spot).tap()
            if stroked.waitForExistence(timeout: 0.8) {
                return true
            }
            // A closed room tapped by mistake offers itself.
            dismissCards()
        }
        return false
    }

    private func playAGame() throws {
        let play = careButton("Play")
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Play")
        let game = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Knock It Off'")).firstMatch
        // Play opens the Games menu, where the quick games are behind "Play with <cat>". A card that comes up after the
        // tour (reminders, the widget) can take the tap: a tap outside closes it.
        let quick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play with'")).firstMatch
        for _ in 0 ..< 3 where !game.exists {
            dismissCards()
            play.tap()
            if quick.waitForExistence(timeout: 5) {
                quick.tap()
            }
            _ = game.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(game.exists, "the games")
        snap("14 games")
        game.tap()
        // Twenty seconds of knocking things off the shelf, then what it paid.
        let back = app.buttons["Back to the room"]
        let deadline = Date().addingTimeInterval(60)
        var tapped = 0
        while !back.exists, Date() < deadline {
            let spot = CGVector(dx: 0.2 + Double(tapped % 7) * 0.1, dy: 0.35 + Double(tapped % 3) * 0.1)
            app.coordinate(withNormalizedOffset: spot).tap()
            tapped += 1
            if tapped == 12 {
                snap("15 game")
            }
        }
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the game's result")
        snap("16 game result")
        back.tap()
        sleep(2)
        // Back in the Games menu (if it came through it): closed to the room.
        if !app.buttons["Decorate"].isHittable {
            _ = tapIfThere("Close")
            sleep(1)
        }
        dismissCards()
    }

    private func decorate() throws {
        let decorate = app.buttons["Decorate"]
        XCTAssertTrue(decorate.waitForExistence(timeout: 10), "Decorate")
        decorate.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Decorate opened")
        sleep(2)
        snap("17 decorating")
        done.tap()
        XCTAssertTrue(decorate.waitForExistence(timeout: 10), "Decorate closed")
    }

    private func visitTheShop() throws {
        let shop = app.buttons["Shop"]
        XCTAssertTrue(shop.waitForExistence(timeout: 10), "Shop")
        shop.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the shop")
        sleep(3)
        snap("18 shop")
        close.tap()
        XCTAssertTrue(shop.waitForExistence(timeout: 10), "back from the shop")
    }

    private func openSettings() throws {
        let badge = app.buttons["Pip, your cat"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "the player's badge")
        badge.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "the cat's profile")
        sleep(2)
        snap("19 profile")
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 15), "Settings")
        sleep(2)
        snap("20 settings")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Decorate"].waitForExistence(timeout: 15), "back in the room")
        snap("21 room")
    }

    // MARK: Helpers

    /// Next on each tour step that only asks to be read, until the host's bubble says `text`.
    private func readOn(until text: String) -> Bool {
        let asked = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let deadline = Date().addingTimeInterval(30)
        while !asked.exists, Date() < deadline {
            _ = tapIfThere("Next")
            sleep(1)
        }
        return asked.exists
    }

    /// The launch curtain (the logo on cream) has gone: the scene's first picture was drawn.
    private func curtainLifts(within seconds: TimeInterval) -> Bool {
        let curtain = app.images["LaunchLogo"]
        return waitUntil(timeout: seconds) { !curtain.exists }
    }

    /// A care button, whose label carries its badge ("Feed, done today", "Play, 5 left").
    private func careButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
    }

    /// Cards that come up on their own after the tour or a game: reminders, the widget, a new level.
    private func dismissCards() {
        for _ in 0 ..< 4 {
            sleep(2)
            guard ["Not now", "Lovely", "Got it"].contains(where: { tapIfThere($0) }) else { return }
        }
    }

    @discardableResult
    private func tapIfThere(_ label: String) -> Bool {
        let button = app.buttons[label].firstMatch
        guard button.exists, button.isHittable else { return false }
        button.tap()
        return true
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            usleep(500_000)
        }
        return condition()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
