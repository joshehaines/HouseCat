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
        /// A picture from elsewhere in the art, the same all year (a garden piece of the catalogue's: the bench, the
        /// pond); such a piece is left out while snow lies (Josh, 19 Oct: a garden round a house in the country).
        public var sprite: String?
        /// How much it bends in the wind, 0 to 1 (a tree's crown, a grass's tips; stones and lamps not at all).
        public var sway: Double?
        /// It blossoms in spring: petals drift from it, as leaves drift from a tree with an autumn picture.
        public var blossom: Bool?
        /// Where it goes on a street (a city's): "row" the buildings across the road, "kerb" a car parked at the far
        /// kerb, "pavement" the near pavement (a bus shelter, a post box); nil, anywhere about the plot.
        public var place: String?
    }

    /// A street behind the house (Josh, 19 Oct: a city should look like a city): a road along the plot this many
    /// cells behind it, this wide, with the buildings across it and the traffic along it.
    public struct Street: Codable, Sendable, Hashable {
        public var offset: Double
        public var width: Double
    }

    public var version: Int
    public var biomes: [String: [Prop]]
    public var streets: [String: Street]?

    public func props(_ biome: Biome) -> [Prop] {
        biomes[biome.rawValue] ?? []
    }
}

/// The road behind the house: along u at `v`, `width` cells across, from `from` to `to`; traffic drives along `lane`
/// towards larger u, cars park along `kerb`.
public struct OutdoorStreet: Equatable, Sendable {
    public var v: Double
    public var width: Double
    public var from: Double
    public var to: Double

    public var lane: Double {
        v + width * 0.2
    }

    public var kerb: Double {
        v - width * 0.3
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
    /// How much it bends in the wind, 0 to 1.
    public var sway: Double = 0
    /// What drifts down from it now: "leaf" from a tree in its autumn picture, "petal" from a blossom in spring.
    public var sheds: String?
}

public enum OutdoorRules {
    /// The picture for a piece: its winter one on snow or in winter, its autumn one in autumn, else the summer one.
    public static func sprite(_ prop: OutdoorsFile.Prop, biome: Biome, season: NatureSeason, snowy: Bool) -> String {
        if let fixed = prop.sprite {
            return fixed
        }
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

    /// The street behind a plot, for a biome that has one.
    public static func street(biome: Biome, rooms: [(u: Double, v: Double)], file: OutdoorsFile) -> OutdoorStreet? {
        guard let street = file.streets?[biome.rawValue], !rooms.isEmpty else { return nil }
        let cells = Double(Tuning.Room.gridWidth), reach = Tuning.Outdoors.reach
        let minU = rooms.map(\.u).min() ?? 0, maxU = (rooms.map(\.u).max() ?? 0) + cells
        let minV = rooms.map(\.v).min() ?? 0
        return OutdoorStreet(v: minV - street.offset, width: street.width, from: minU - reach * 1.5, to: maxU + reach * 1.5)
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
        let street = street(biome: biome, rooms: rooms, file: file)
        if let street {
            pieces = streetPieces(street, props: props, biome: biome, season: season, snowy: snowy, unit: unit)
        }
        let free = props.filter { $0.place == nil }
        let freeTotal = free.map(\.weight).reduce(0, +)
        let target = pieces.count + t.count
        for _ in 0 ..< t.attempts where pieces.count < target {
            let u = minU - t.reach + unit() * (maxU - minU + 2 * t.reach)
            let v = minV - t.reach + unit() * (maxV - minV + 2 * t.reach)
            guard freeTotal > 0 else { break }
            var pick = rng.below(freeTotal)
            guard let prop = free.first(where: { pick -= $0.weight; return pick < 0 }) else { continue }
            let width = prop.width * (1 - t.sizeVariation + 2 * t.sizeVariation * unit())
            let behind = u < minU - t.margin || v < minV - t.margin
            let offRoad = street.map { abs(v - $0.v) > $0.width / 2 + width / 2 + 0.6 } ?? true
            guard clearOfRooms(u, v, width / 2), !prop.tall || behind, offRoad else { continue }
            let spaced = pieces.allSatisfy { other in
                let du = other.u - u, dv = other.v - v
                return (du * du + dv * dv).squareRoot() >= (other.width + width) / 2 * t.spacing
            }
            guard spaced else { continue }
            let picture = sprite(prop, biome: biome, season: season, snowy: snowy)
            let sheds: String? = if picture.hasSuffix("_autumn.png") {
                "leaf"
            } else if season == .spring, prop.blossom == true, !snowy {
                "petal"
            } else {
                nil
            }
            pieces.append(OutdoorPiece(
                prop: prop.id,
                sprite: picture,
                u: u,
                v: v,
                width: width,
                tall: prop.tall,
                behind: behind,
                sway: snowy && prop.sprite == nil ? (prop.sway ?? 0) * 0.5 : prop.sway ?? 0,
                sheds: sheds
            ))
        }
        // A garden piece is laid out all year, so everything else keeps its place, and put away under snow.
        return snowy ? pieces.filter { piece in props.first { $0.id == piece.prop }?.sprite == nil } : pieces
    }

    /// The street's own pieces: the buildings in a row across the road, cars parked here and there along its far kerb,
    /// and a few things on the near pavement, each picked by weight from its place's props.
    private static func streetPieces( // swiftlint:disable:this function_parameter_count
        _ street: OutdoorStreet,
        props: [OutdoorsFile.Prop],
        biome: Biome,
        season: NatureSeason,
        snowy: Bool,
        unit: () -> Double
    ) -> [OutdoorPiece] {
        func pick(_ place: String) -> OutdoorsFile.Prop? {
            let choices = props.filter { $0.place == place }
            let total = choices.map(\.weight).reduce(0, +)
            guard total > 0 else { return nil }
            var left = unit() * Double(total)
            return choices.first { left -= Double($0.weight); return left < 0 } ?? choices.last
        }
        func piece(_ prop: OutdoorsFile.Prop, u: Double, v: Double) -> OutdoorPiece {
            OutdoorPiece(
                prop: prop.id,
                sprite: sprite(prop, biome: biome, season: season, snowy: snowy),
                u: u,
                v: v,
                width: prop.width,
                tall: prop.tall,
                behind: true,
                sway: prop.sway ?? 0
            )
        }
        var pieces: [OutdoorPiece] = []
        var u = street.from
        while u < street.to, let prop = pick("row") {
            pieces.append(piece(prop, u: u + prop.width * 0.8, v: street.v - street.width / 2 - 1.2))
            u += prop.width * 1.6 + unit()
        }
        u = street.from + 2 + unit() * 3
        while u < street.to, let prop = pick("kerb") {
            pieces.append(piece(prop, u: u, v: street.kerb))
            u += prop.width * 2 + 1 + unit() * 6
        }
        u = street.from + 4 + unit() * 4
        while u < street.to, let prop = pick("pavement") {
            pieces.append(piece(prop, u: u, v: street.v + street.width / 2 + 0.7))
            u += 6 + unit() * 8
        }
        return pieces
    }
}
