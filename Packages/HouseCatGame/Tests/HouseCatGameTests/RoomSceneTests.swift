@testable import HouseCatGame
import SpriteKit
import Testing

@MainActor
@Test func placeholderRoomDrawsTheCatAndFurniture() {
    let scene = RoomScene(size: CGSize(width: 1024, height: 768))
    scene.didChangeSize(.zero)
    #expect(scene.childNode(withName: "Cat") != nil)
    #expect(scene.childNode(withName: "Sofa") != nil)
}
