import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let art: ArtLibrary? = MainActor.assumeIsolated {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try? ArtLibrary(root: repo.appendingPathComponent("App/Art"))
}

@MainActor
private func exterior(_ size: CGSize, sky: SkyPhase = .day) throws -> ExteriorScene {
    let art = try #require(art)
    let model = ExteriorScene.Model(scene: "world/scenes/london_terrace_city_autumn", sky: sky, door: CGPoint(x: 0.39, y: 0.62))
    return ExteriorScene(size: size, art: art, model: model)
}

@MainActor
private func painting(_ scene: ExteriorScene) throws -> SKSpriteNode {
    try #require(scene.childNode(withName: "exterior") as? SKSpriteNode)
}

@MainActor
@Test func demoHomeIsPaintedForEverySeasonWithItsMasks() throws {
    let art = try #require(art)
    for season in NatureSeason.allCases {
        let base = "world/scenes/london_terrace_city_\(season.rawValue)"
        #expect(art.has(base + ".jpg") && art.has(base + "_land.png") && art.has(base + "_glass.png"), "\(season)")
    }
}

@MainActor
@Test(arguments: [CGSize(width: 852, height: 393), CGSize(width: 1366, height: 1024), CGSize(width: 1024, height: 1366)])
func theHouseIsNeverCroppedAndTheGroundReachesTheBottom(size: CGSize) throws {
    let scene = try exterior(size)
    let node = try painting(scene)
    let band = CGRect(
        x: node.position.x - node.size.width * Tuning.Exterior.focusWidth / 2,
        y: node.position.y + node.size.height * (1 - Tuning.Exterior.focusHeight) / 2,
        width: node.size.width * Tuning.Exterior.focusWidth,
        height: node.size.height * Tuning.Exterior.focusHeight
    )
    #expect(band.minX >= -0.5 && band.maxX <= size.width + 0.5, "house band fits across at \(size)")
    #expect(band.minY >= -0.5 && band.maxY <= size.height + 0.5, "house band fits up and down at \(size)")
    #expect(node.position.y <= 0.5, "the painting reaches the bottom of the view")
    // As big as it can be: one of the limits binds.
    let coversWidth = node.size.width >= size.width - 0.5
    let bandBinds = abs(band.width - size.width) < 1 || abs(band.height - size.height) < 1
    #expect(coversWidth || bandBinds)
}

@MainActor
@Test func doorPointLandsOnThePaintingWhereTheDataSays() throws {
    let scene = try exterior(CGSize(width: 393, height: 852))
    let node = try painting(scene)
    let door = scene.doorPoint
    #expect(abs(door.x - (node.position.x + (0.39 - 0.5) * node.size.width)) < 0.01)
    #expect(abs(door.y - (node.position.y + 0.38 * node.size.height)) < 0.01)
}

@MainActor
@Test func windowsGlowOnlyAfterDark() throws {
    #expect(Tuning.Sky.windowGlow[.day] == 0)
    #expect((Tuning.Sky.windowGlow[.night] ?? 0) > 0)
    let night = try exterior(CGSize(width: 393, height: 852), sky: .night)
    #expect(try painting(night).childNode(withName: "glass") != nil)
}
