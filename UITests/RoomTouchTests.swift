import XCTest

/// Taps as a finger does (XCUITest), for what the simulator panel cannot show: the room takes a tap on the floor and
/// Decorate opens.
final class RoomTouchTests: XCTestCase {
    func testDecorateOpensAndTheRoomTakesTaps() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOUSECAT_SKIP_STORE"] = "1"
        app.launch()
        let decorate = app.buttons["Decorate"]
        XCTAssertTrue(decorate.waitForExistence(timeout: 60), "the room's controls")
        sleep(3)
        // A tap on the middle of the room (the scene logs it in debug builds).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        sleep(1)
        decorate.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "Decorate opened")
    }
}
