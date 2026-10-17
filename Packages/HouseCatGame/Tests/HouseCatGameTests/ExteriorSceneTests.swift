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
@Test func inPortraitTheHouseFillsTheWidthAndTheSkyRunsAbove() throws {
    let scene = try exterior(CGSize(width: 393, height: 852))
    let node = try painting(scene)
    #expect(abs(node.size.width - 393 / Tuning.Exterior.portraitWidthShare) < 0.5)
    #expect(node.position.y == 0)
    #expect(node.size.height < 852)
}

@MainActor
@Test func inLandscapeThePaintingFillsTheWidthCroppedFromTheTop() throws {
    let scene = try exterior(CGSize(width: 1366, height: 1024))
    let node = try painting(scene)
    #expect(node.size.width == 1366)
    // The painting reaches the bottom of the view and hides only its top band.
    #expect(node.position.y <= 0)
    #expect(node.position.y + node.size.height >= 1024)
    let hiddenTop = node.position.y + node.size.height - 1024
    #expect(hiddenTop <= node.size.height * Tuning.Exterior.landscapeTopCrop + 0.5)
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
