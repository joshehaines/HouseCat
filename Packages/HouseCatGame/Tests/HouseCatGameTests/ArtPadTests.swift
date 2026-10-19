import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let catalog = repo.appendingPathComponent("App/Resources/ArtPad.xcassets")

@MainActor
private func library(pad: Bool) throws -> ArtLibrary {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    if pad {
        art.pad = .folder(catalog)
    }
    return art
}

/// An iPad draws furniture from its sharper copy (Josh, 19 Oct: the iPad looked soft): the master's pixels, laid
/// out at the same size; the pictures in the controls keep the standard copy.
@MainActor
@Test func anIPadDrawsFurnitureFromItsSharperCopy() throws {
    let phone = try library(pad: false), pad = try library(pad: true)
    let sofa = "furniture/living/furn_living_sofa_R.png"
    let painted = phone.paintedSize(sofa)
    #expect(abs(phone.texture(sofa).size().width - painted.width * 0.6) <= 1)
    #expect(pad.texture(sofa).size() == painted, "the iPad's copy is the master's size")
    #expect(pad.paintedSize(sofa) == painted)
    #expect(pad.image(sofa)?.width == phone.image(sofa)?.width, "the controls' pictures stay the standard copy")
    // Shown in the controls first, the piece is still drawn sharp in the room.
    let rug = "furniture/living/furn_living_rug_L.png"
    _ = pad.image(rug)
    #expect(pad.texture(rug).size() == pad.paintedSize(rug))
    // A picture without an iPad copy is the same on both.
    let wall = "rooms/walls/wall_living_powder_lemon.png"
    #expect(pad.texture(wall).size() == phone.texture(wall).size())
}

/// The sharper copies change how crisp a room is, never its layout: every sprite is the same size on both.
@MainActor
@Test func theIPadsCopiesLeaveTheRoomTheSameSize() throws {
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    func sizes(_ art: ArtLibrary) throws -> [String] {
        let model = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
        let scene = RoomScene(size: CGSize(width: 1376, height: 1032), art: art, content: content, model: model)
        var out: [String] = []
        scene.enumerateChildNodes(withName: "//*") { node, _ in
            if let sprite = node as? SKSpriteNode {
                out.append(String(format: "%@ %.2f %.2f", sprite.name ?? "-", sprite.size.width, sprite.size.height))
            }
        }
        return out.sorted()
    }
    let phone = try sizes(library(pad: false)), pad = try sizes(library(pad: true))
    #expect(!phone.isEmpty)
    #expect(phone == pad)
}

/// Every iPad copy the art index names is in the iPad's catalog, for the iPad only (App Store thinning then leaves
/// it out of an iPhone's download).
@Test func everyIPadCopyIsInTheCatalogForTheIPadOnly() throws {
    struct Index: Decodable {
        struct Entry: Decodable {
            var pad: ArtLibrary.Pad?
        }

        var files: [String: Entry]
    }
    struct DataSet: Decodable {
        struct Item: Decodable {
            var filename: String
            var idiom: String
        }

        var data: [Item]
    }
    let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: repo.appendingPathComponent("App/Art/art.json")))
    let pads = index.files.compactMap { path, entry in entry.pad.map { (path, $0) } }
    #expect(pads.contains { $0.0.hasPrefix("furniture/") })
    for (path, pad) in pads {
        let folder = catalog.appendingPathComponent(pad.asset + ".dataset")
        let set = try JSONDecoder().decode(DataSet.self, from: Data(contentsOf: folder.appendingPathComponent("Contents.json")))
        #expect(set.data.map(\.idiom) == ["ipad"], "\(path)")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(set.data[0].filename).path), "\(path)")
    }
}

/// The street outside is sharpened where it is drawn larger than its pixels (an iPad), not where it is not.
@MainActor
@Test func theOutsideIsSharpenedOnlyWhenMagnified() throws {
    let art = try library(pad: false)
    func sharpness(_ size: CGSize) throws -> Float {
        let model = ExteriorScene.Model(scene: "world/scenes/london_terrace_city_autumn", sky: .day, door: CGPoint(x: 0.39, y: 0.62))
        let scene = ExteriorScene(size: size, art: art, model: model)
        let painting = try #require(scene.childNode(withName: "exterior") as? SKSpriteNode)
        return try #require(painting.shader?.uniformNamed("u_sharp")).floatValue
    }
    #expect(try sharpness(CGSize(width: 1376, height: 1032)) == Float(Tuning.Exterior.sharpen), "a 13-inch iPad")
    #expect(try sharpness(CGSize(width: 900, height: 500)) == 0, "drawn no larger than its pixels")
}
