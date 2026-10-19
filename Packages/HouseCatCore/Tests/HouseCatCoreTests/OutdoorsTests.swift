import Foundation
@testable import HouseCatCore
import Testing

@Suite("Scenery round the house")
struct OutdoorsTests {
    let content: ContentBundle

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
    }

    @Test func everyBiomeHasItsSceneryAndEveryPictureIsPainted() {
        let assets = ContentValidationTests.repo.appendingPathComponent("assets")
        for biome in Biome.allCases {
            let props = content.outdoors.props(biome)
            #expect(props.contains { $0.tall } && props.contains { !$0.tall }, "\(biome)")
            for prop in props {
                for season in NatureSeason.allCases {
                    for snowy in [false, true] {
                        let path = OutdoorRules.sprite(prop, biome: biome, season: season, snowy: snowy)
                        #expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(path).path), "\(path)")
                    }
                }
            }
        }
    }

    @Test func sceneryKeepsClearOfTheRoomsAndTallPiecesStayBehind() {
        let rooms: [(u: Double, v: Double)] = [(0, 0), (10, 0), (0, 10)]
        let cells = Double(Tuning.Room.gridWidth)
        for biome in Biome.allCases {
            let pieces = OutdoorRules.layout(biome: biome, rooms: rooms, seed: 42, season: .summer, snowy: false, file: content.outdoors)
            #expect(pieces.count > 20, "\(biome): \(pieces.count)")
            for piece in pieces {
                for room in rooms {
                    let inside = piece.u > room.u - Tuning.Outdoors.margin && piece.u < room.u + cells + Tuning.Outdoors.margin
                        && piece.v > room.v - Tuning.Outdoors.margin && piece.v < room.v + cells + Tuning.Outdoors.margin
                    #expect(!inside, "\(biome) \(piece.prop) at \(piece.u), \(piece.v)")
                }
                if piece.tall {
                    #expect(piece.behind && (piece.u < -Tuning.Outdoors.margin || piece.v < -Tuning.Outdoors.margin))
                }
            }
        }
    }

    @Test func aHomeAlwaysHasTheSameGardenInTheSeasonsDress() throws {
        let rooms: [(u: Double, v: Double)] = [(0, 0)]
        let summer = OutdoorRules.layout(biome: .countryside, rooms: rooms, seed: 7, season: .summer, snowy: false, file: content.outdoors)
        let again = OutdoorRules.layout(biome: .countryside, rooms: rooms, seed: 7, season: .summer, snowy: false, file: content.outdoors)
        let autumn = OutdoorRules.layout(biome: .countryside, rooms: rooms, seed: 7, season: .autumn, snowy: false, file: content.outdoors)
        let other = OutdoorRules.layout(biome: .countryside, rooms: rooms, seed: 8, season: .summer, snowy: false, file: content.outdoors)
        #expect(summer == again)
        #expect(summer.map(\.u) == autumn.map(\.u))
        #expect(summer.map(\.u) != other.map(\.u))
        let oak = try #require(autumn.first { $0.prop == "oak" })
        #expect(oak.sprite == "world/props/countryside_oak_autumn.png")
        let snow = OutdoorRules.layout(biome: .countryside, rooms: rooms, seed: 7, season: .spring, snowy: true, file: content.outdoors)
        #expect(snow.allSatisfy { $0.sprite.hasSuffix("_winter.png") })
    }
}
