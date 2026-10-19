import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private func dressingRoom(_ size: CGSize, look: CatLook = .midnight) throws -> DressingRoomScene {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    return DressingRoomScene(size: size, art: art, catArt: catArt, rig: rig, look: look)
}

/// The cat creator's set: whatever the screen and wherever the controls leave room, the painting covers the whole
/// view and the cat stands on the podium in the middle of the open part, a good size.
@MainActor
@Test func theCatStandsOnThePodiumInTheOpenPart() throws {
    // A landscape iPhone with the drawers on the left and the open drawer on the right; an iPad on its side; the
    // top of an upright iPad.
    let cases: [(CGSize, CGRect)] = [
        (CGSize(width: 956, height: 440), CGRect(x: 178, y: 8, width: 350, height: 424)),
        (CGSize(width: 1376, height: 1032), CGRect(x: 260, y: 13, width: 450, height: 1006)),
        (CGSize(width: 1032, height: 605), CGRect(x: 19, y: 19, width: 994, height: 567)),
    ]
    for (size, open) in cases {
        let scene = try dressingRoom(size)
        scene.setOpenRect(open)
        let room = scene.room.calculateAccumulatedFrame()
        let shown = CGRect(
            x: scene.stage.position.x,
            y: scene.stage.position.y,
            width: room.width * scene.stage.xScale,
            height: room.height * scene.stage.yScale
        )
        #expect(
            shown.minX <= 0.5 && shown.minY <= 0.5 && shown.maxX >= size.width - 0.5 && shown.maxY >= size.height - 0.5,
            "\(size): the room covers the view"
        )
        let cat = try #require(scene.cat)
        let feet = scene.stage.convert(cat.position, to: scene)
        // SwiftUI's rect is from the top; the scene's from the bottom.
        let middle = open.midX
        #expect(abs(feet.x - middle) < open.width * 0.2, "\(size): the podium is in the middle of the open part (\(feet.x) vs \(middle))")
        #expect(feet.y > size.height - open.maxY, "\(size): the podium is inside the open part")
        let height = cat.calculateAccumulatedFrame().height * scene.stage.yScale
        #expect(height > open.height * 0.25 && height < open.height * 0.75, "\(size): the cat is a good size (\(height) of \(open.height))")
    }
}

/// Dragged round, the cat turns through all six sitting angles, the back included; standing it has no back view.
@MainActor
@Test func theCatTurnsRoundThePodium() throws {
    let scene = try dressingRoom(CGSize(width: 956, height: 440))
    var seen: [DressingRoomScene.Angle] = [scene.angle]
    for _ in 0 ..< 6 {
        scene.turn(by: 1)
        seen.append(scene.angle)
    }
    #expect(Set(seen) == Set(DressingRoomScene.Angle.allCases))
    #expect(seen.first == seen.last, "a whole turn comes back round")
    #expect(scene.cat?.pose != nil, "sitting, it is drawn in its paintings")
    scene.present(.init(standing: true, angle: .sideLeft))
    #expect(scene.cat?.pose == nil, "standing, it is the puppet")
    for _ in 0 ..< 6 {
        scene.turn(by: 1)
        #expect(scene.angle != .back)
    }
}

/// The eyes and the nose bring the room closer, on the cat's head.
@MainActor
@Test func theFaceComesCloser() throws {
    let scene = try dressingRoom(CGSize(width: 956, height: 440))
    scene.setOpenRect(CGRect(x: 178, y: 8, width: 350, height: 424))
    let whole = scene.stage.xScale
    scene.present(.init(angle: .front, face: true))
    scene.layoutStage(animated: false)
    #expect(scene.stage.xScale > whole * 1.8)
    #expect(scene.angle == .front)
}
