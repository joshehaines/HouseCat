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

/// The view is framed on the house where it stands in its painting (Josh, 19 Oct: the demo's chimney was cut off on
/// a wide phone): a house high in the painting keeps its top in view, and a house off to one side comes to the
/// middle where the painting runs past the view; the painting still covers the view.
@MainActor
@Test(arguments: [CGSize(width: 956, height: 440), CGSize(width: 1366, height: 1024)])
func theViewIsFramedOnTheHouse(size: CGSize) throws {
    let art = try #require(art)
    let house = CGRect(x: 0.36, y: 0.05, width: 0.33, height: 0.75)
    let model = ExteriorScene.Model(
        scene: "world/scenes/london_terrace_city_autumn",
        sky: .day,
        door: CGPoint(x: 0.43, y: 0.6),
        house: house
    )
    let node = try painting(ExteriorScene(size: size, art: art, model: model))
    let top = node.position.y + (1 - house.minY) * node.size.height
    let bottom = node.position.y + (1 - house.maxY) * node.size.height
    #expect(top <= size.height + 0.5 && bottom >= -0.5, "the whole house is in view at \(size): \(bottom)...\(top)")
    #expect(abs((size.height - top) - bottom) < 2 || node.position.y > -0.5 || node.position.y + node.size.height < size.height + 0.5)
    #expect(node.position.y <= 0.5 && node.position.y + node.size.height >= size.height - 0.5, "covers the view up and down")
    #expect(node.position.x - node.size.width / 2 <= 0.5 && node.position.x + node.size.width / 2 >= size.width - 0.5)
}

/// Every painting has where its house stands, and its door is on the house: every home in every place and season, and
/// the intro's own (Josh, 20 Oct: the London terrace fully decorated and a beach house in Bali, painted for it alone).
@MainActor
@Test func everyPaintingKnowsWhereItsHouseIs() throws {
    struct Index: Decodable {
        var doors: [String: [Double]]
        var houses: [String: [Double]]
    }
    let art = try #require(art)
    let index = try art.data("world/scenes/scenes.json", as: Index.self)
    let homes = Set(HouseStyle.allCases.flatMap { house in
        Biome.allCases.flatMap { biome in NatureSeason.allCases.map { "\(house.rawValue)_\(biome.rawValue)_\($0.rawValue)" } }
    })
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let intro = try JSONDecoder().decode(IntroFile.self, from: Data(contentsOf: repo.appendingPathComponent("Content/intro.json")))
    let introScenes = Set(intro.stops.compactMap { $0.scene.split(separator: "/").last.map(String.init) })
    // The ladder's first house, painted run down for itself (docs/LADDER.md).
    let firstHouse: Set = ["\(Tuning.Cutscene.firstHouseScene)_city_autumn"]
    #expect(Set(index.houses.keys) == homes.union(introScenes).union(firstHouse), "a box for every home's painting and every intro scene")
    for name in introScenes.union(firstHouse) {
        #expect(index.doors[name] != nil, "\(name): door")
    }
    for (name, box) in index.houses {
        #expect(box.count == 4 && box[0] < box[2] && box[1] < box[3] && box.allSatisfy { (0 ... 1).contains($0) }, "\(name)")
        if let door = index.doors[name] {
            #expect(door[0] >= box[0] - 0.02 && door[0] <= box[2] + 0.02 && door[1] < 0.9, "\(name)'s door is on its house")
        }
    }
}
