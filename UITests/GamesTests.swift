import XCTest

/// The Games menu and its games after Josh's play on his iPad Air 13-inch (20 Oct): the "Play with" card on screen with
/// the longest name a cat can have ("Play with "whoever" is off the screen when clicking games"), Zoomies run twice in
/// a row ("Zoomies bugged out when I tried again and the cat didn't run again"), a quick game played again (the same
/// new-scene path as Zoomies), and today's Pawcross. A fresh save in memory with a cat already made, the tour skipped.
/// A debug build. Run on the iPhone 18 Pro and the 13-inch iPad: `xcodebuild test … -only-testing:HouseCatUITests/GamesTests`.
/// Every screen is attached, and written to `SHOTS` when the runner has it (`TEST_RUNNER_SHOTS=<folder>`).
@MainActor
final class GamesTests: XCTestCase {
    private var app: XCUIApplication!
    /// The longest a cat's name can be (`Tuning.Cat.nameMaxLength`, 20).
    private let longName = "Wolfgang Amadeus Paw"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launchEnvironment["HOUSECAT_FRESH"] = "1"
        app.launchEnvironment["HOUSECAT_CAT"] = "midnight"
        app.launchEnvironment["HOUSECAT_NAME"] = longName
        // The game is on its side; a device held upright gives sideways screenshots and taps.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// The quick games' card says "Play with" and the cat's whole name, inside the card and on the screen.
    func testThePlayWithCardIsOnScreen() throws {
        openTheGames()
        let card = quickCard()
        XCTAssertTrue(card.shows(within: 10), "the Play with card")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(card.frame), "the card \(card.frame) is inside the screen \(window)")
        // The card reads as one element ("Play with <name>. 5 plays left"); its band and the name line are checked
        // by eye in the screenshot.
        XCTAssertTrue(card.label.hasPrefix("Play with \(longName)."), "the card names the cat in full: \(card.label)")
        snap("games menu")
    }

    /// Play, finish, play again: the second run's cat runs and its score climbs, and it ends with its own card.
    func testZoomiesRunsTwiceInARow() throws {
        openTheGames()
        let zoomies = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Zoomies'")).firstMatch
        XCTAssertTrue(zoomies.shows(within: 5), "Zoomies in the Games menu")
        zoomies.tapInFront()
        let score = app.staticTexts["zoomies.score"]
        XCTAssertTrue(score.shows(within: 10), "Zoomies opened")
        // Left alone, the cat runs into something in its lane before long.
        let again = app.buttons["Run again"]
        XCTAssertTrue(again.shows(within: 120), "the first run ended")
        snap("zoomies first run over")
        again.tapInFront()
        XCTAssertTrue(waitUntil(timeout: 10) { (Int(score.label.filter(\.isNumber)) ?? 0) > 0 },
                      "the second run is running: its score is \(score.label)")
        let early = Int(score.label.filter(\.isNumber)) ?? 0
        sleep(2)
        snap("zoomies second run")
        XCTAssertGreaterThan(Int(score.label.filter(\.isNumber)) ?? 0, early, "the second run's score climbs as the cat runs")
        XCTAssertTrue(again.shows(within: 120), "the second run ended with its own card")
        snap("zoomies second run over")
    }

    /// A quick game played again: the new game's clock runs down.
    func testAQuickGamePlaysAgain() throws {
        openTheGames()
        quickCard().tapInFront()
        let game = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hide and Seek'")).firstMatch
        XCTAssertTrue(game.shows(within: 5), "Hide and Seek is offered")
        game.tapInFront()
        let clock = app.staticTexts["game.clock"]
        XCTAssertTrue(clock.shows(within: 15), "Hide and Seek opened")
        let again = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Again'")).firstMatch
        XCTAssertTrue(again.shows(within: 45), "the game ended")
        snap("quick game over")
        again.tapInFront()
        XCTAssertTrue(waitUntil(timeout: 12) { (Int(clock.label) ?? 99) < 18 }, "the new game's clock runs: \(clock.label)")
        snap("quick game again")
    }

    /// Today's Pawcross: the small grid and its one-line rules.
    func testThePuzzle() throws {
        openTheGames()
        let puzzle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH \"Pat's daily puzzle\"")).firstMatch
        XCTAssertTrue(puzzle.shows(within: 5), "Pat's daily puzzle in the Games menu")
        puzzle.tapInFront()
        XCTAssertTrue(app.buttons["Fill"].shows(within: 10), "the puzzle opened")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Each number is a run'")).firstMatch.exists,
                      "the rules in one line")
        sleep(1)
        snap("pawcross")
    }

    // MARK: Getting there

    /// Launched, in the room with the tour skipped, and Play pressed.
    private func openTheGames() {
        app.launch()
        let skip = app.buttons["Skip the tour"]
        let decorate = app.buttons["Decorate"]
        let arrival = Date().addingTimeInterval(120)
        // Past the launch curtain and the cold open outside (a tap on the house opens the door).
        while !(decorate.exists && decorate.isHittable), !skip.exists, Date() < arrival {
            XCUIApplication.frontTarget()
            if !decorate.exists {
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            sleep(2)
        }
        XCTAssertTrue(decorate.exists || skip.exists, "the room")
        if skip.shows(within: 8) {
            skip.tapInFront()
        }
        let settled = Date().addingTimeInterval(20)
        while Date() < settled {
            for button in ["Thank you", "Not now", "Lovely", "Got it"] where app.buttons[button].exists && app.buttons[button].isHittable {
                app.buttons[button].tapInFront()
            }
            if decorate.exists, decorate.isHittable, !skip.exists {
                break
            }
            sleep(1)
        }
        let play = app.buttons.matching(NSPredicate(format: "label == 'Play' OR label BEGINSWITH 'Play,'")).firstMatch
        XCTAssertTrue(play.shows(within: 10), "Play")
        play.tapInFront()
        XCTAssertTrue(quickCard().shows(within: 10), "Play opened the Games menu")
        sleep(1)
    }

    private func quickCard() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play with'")).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            XCUIApplication.frontTarget()
            if condition() {
                return true
            }
            usleep(400_000)
        }
        return condition()
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
        guard let folder = ProcessInfo.processInfo.environment["SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(device) games \(name).png"))
    }
}
