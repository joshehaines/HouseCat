import Foundation

// MARK: outdoors.json

/// The scenery round the house (Josh, 18 Oct: the outside shows the place the player picked): trees, bushes and
/// stones of the home's biome on the ground about the plot, in the season's dress. Content/outdoors.json lists
/// each biome's pieces; their pictures are `world/props/<biome>_<id>[_<season>].png`.
public struct OutdoorsFile: Codable, Sendable {
    public struct Prop: Codable, Sendable, Hashable {
        public var id: String
        /// Trees and lamps stand only behind the house, so nothing tall ever hides a room.
        public var tall: Bool
        /// How often it is picked against the biome's others.
        public var weight: Int
        /// Its width on the ground, in cells.
        public var width: Double
        /// The seasons it has its own picture for ("autumn", "winter"); otherwise the summer one.
        public var seasons: [String]
    }

    public var version: Int
    public var biomes: [String: [Prop]]

    public func props(_ biome: Biome) -> [Prop] {
        biomes[biome.rawValue] ?? []
    }
}

/// One piece of scenery on the ground, where it stands and how it is drawn.
public struct OutdoorPiece: Equatable, Sendable {
    public var prop: String
    public var sprite: String
    /// The cell its base stands on.
    public var u: Double
    public var v: Double
    /// Its width on the ground in cells, after the piece's own small variation.
    public var width: Double
    public var tall: Bool
    /// Behind the house's back walls (drawn under the rooms), or in front of it (over them).
    public var behind: Bool
}

public enum OutdoorRules {
    /// The picture for a piece: its winter one on snow or in winter, its autumn one in autumn, else the summer one.
    public static func sprite(_ prop: OutdoorsFile.Prop, biome: Biome, season: NatureSeason, snowy: Bool) -> String {
        let wanted: String? = if snowy || season == .winter {
            "winter"
        } else if season == .autumn {
            "autumn"
        } else {
            nil
        }
        let suffix = wanted.flatMap { prop.seasons.contains($0) ? "_\($0)" : nil } ?? ""
        return "world/props/\(biome.rawValue)_\(prop.id)\(suffix).png"
    }

    /// Where the scenery stands round a plot of rooms (each a square of `Tuning.Room.gridWidth` cells from its
    /// corner), laid out once from the household's seed: the same home always has the same garden. Pieces keep a
    /// margin from every room and room from each other; tall ones only behind the house.
    public static func layout(
        biome: Biome,
        rooms: [(u: Double, v: Double)],
        seed: UInt64,
        season: NatureSeason,
        snowy: Bool,
        file: OutdoorsFile
    ) -> [OutdoorPiece] {
        let props = file.props(biome)
        let total = props.map(\.weight).reduce(0, +)
        guard !rooms.isEmpty, total > 0 else { return [] }
        let t = Tuning.Outdoors.self
        let cells = Double(Tuning.Room.gridWidth)
        let minU = rooms.map(\.u).min() ?? 0, minV = rooms.map(\.v).min() ?? 0
        let maxU = (rooms.map(\.u).max() ?? 0) + cells, maxV = (rooms.map(\.v).max() ?? 0) + cells
        var rng = DaySeed(household: seed, day: GameDay(index: 0), purpose: "outdoors", salt: biome.rawValue)
        func unit() -> Double {
            Double(rng.below(1_000_000)) / 1_000_000
        }
        func clearOfRooms(_ u: Double, _ v: Double, _ half: Double) -> Bool {
            rooms.allSatisfy { room in
                let margin = t.margin + half
                return u < room.u - margin || u > room.u + cells + margin || v < room.v - margin || v > room.v + cells + margin
            }
        }
        var pieces: [OutdoorPiece] = []
        for _ in 0 ..< t.attempts where pieces.count < t.count {
            let u = minU - t.reach + unit() * (maxU - minU + 2 * t.reach)
            let v = minV - t.reach + unit() * (maxV - minV + 2 * t.reach)
            var pick = rng.below(total)
            guard let prop = props.first(where: { pick -= $0.weight; return pick < 0 }) else { continue }
            let width = prop.width * (1 - t.sizeVariation + 2 * t.sizeVariation * unit())
            let behind = u < minU - t.margin || v < minV - t.margin
            guard clearOfRooms(u, v, width / 2), !prop.tall || behind else { continue }
            let spaced = pieces.allSatisfy { other in
                let du = other.u - u, dv = other.v - v
                return (du * du + dv * dv).squareRoot() >= (other.width + width) / 2 * t.spacing
            }
            guard spaced else { continue }
            pieces.append(OutdoorPiece(
                prop: prop.id,
                sprite: sprite(prop, biome: biome, season: season, snowy: snowy),
                u: u,
                v: v,
                width: width,
                tall: prop.tall,
                behind: behind
            ))
        }
        return pieces
    }
}
