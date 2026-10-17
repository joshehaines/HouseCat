@testable import HouseCatUI
import Testing

@MainActor
@Test func roomViewBuilds() {
    _ = RoomView().body
}
