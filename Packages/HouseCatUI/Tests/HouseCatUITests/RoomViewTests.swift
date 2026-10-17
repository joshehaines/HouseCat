@testable import HouseCatUI
import SpriteKit
import Testing

@MainActor
@Test func roomViewBuilds() {
    _ = RoomView(scene: SKScene(size: CGSize(width: 400, height: 300))).body
}
