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
        /// kerb, "pavement" the near pavement (a bus shelter, a post box).
        public var place: String?
        /// What it is in the garden's plan (OutdoorPlan.Role): "tree", "hedge", "rock", "feature", "seat",
        /// "birdtable", "pots", "shed", "line", "lamp".
        public var role: String?
        /// Whose picture it is, when a place borrows a biome's piece (`places`): world/props/<from>_<id>.png.
        public var from: String?
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
    /// A house's own town (Josh, 22 Oct: "base it around the house the user is in, London being a city"): the
    /// ladder's places with their own scenery (Amsterdam's canal houses, Tokyo's vending machines), by
    /// `HomePlace.setting`; a place without a list has its biome's.
    public var places: [String: [Prop]]?

    /// One painted neighbourhood round a ladder house (Josh, 23 Oct: "something from Higgs that is perfectly
    /// natural"): `image` (assets/world/backdrops), `size` its master pixels, `plot` the empty plot's diamond in them
    /// (left, top, right, bottom), which the house's ground-floor rooms cover.
    public struct Backdrop: Codable, Sendable, Hashable {
        public var image: String
        public var size: [Double]
        public var plot: [Double]

        public init(image: String, size: [Double], plot: [Double]) {
            self.image = image
            self.size = size
            self.plot = plot
        }
    }

    /// By `HomePlace.setting`; a place with one has no assembled scenery, street or roads.
    public var backdrops: [String: Backdrop]?

    public func props(_ biome: Biome, setting: String? = nil) -> [Prop] {
        setting.flatMap { places?[$0] } ?? biomes[biome.rawValue] ?? []
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

/// A road of the neighbourhood round the house's block (Josh, 22 Oct: the outside "still looks very unnatural": a
/// suburb's streets between the gardens): along u at `at` (or along v), `width` cells of tarmac, from `from` to `to`.
public struct OutdoorRoad: Equatable, Sendable {
    public var alongU: Bool
    public var at: Double
    public var width: Double
    public var from: Double
    public var to: Double
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
    public static func sprite(_ prop: OutdoorsFile.Prop, biome: Biome, setting: String? = nil, season: NatureSeason, snowy: Bool) -> String {
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
        return "world/props/\(prop.from ?? setting ?? biome.rawValue)_\(prop.id)\(suffix).png"
    }

    /// The street behind a plot, for a biome that has one.
    public static func street(biome: Biome, setting: String? = nil, rooms: [(u: Double, v: Double)], file: OutdoorsFile) -> OutdoorStreet? {
        guard let street = setting.flatMap({ file.streets?[$0] }) ?? file.streets?[biome.rawValue], !rooms.isEmpty else { return nil }
        let cells = Double(Tuning.Room.gridWidth), reach = Tuning.Outdoors.reach
        let minU = rooms.map(\.u).min() ?? 0, maxU = (rooms.map(\.u).max() ?? 0) + cells
        let minV = rooms.map(\.v).min() ?? 0
        return OutdoorStreet(v: minV - street.offset, width: street.width, from: minU - reach * 1.5, to: maxU + reach * 1.5)
    }

    /// The roads round the house's block, between its garden and the houses next door: in front, at both sides, and
    /// behind where no street runs (a place with next-door plots only).
    public static func roads(rooms: [(u: Double, v: Double)], street: OutdoorStreet?, setting: String?, file: OutdoorsFile) -> [OutdoorRoad] {
        guard !rooms.isEmpty, let setting, file.places?[setting]?.contains(where: { $0.place == "plot" }) == true else { return [] }
        let t = Tuning.Outdoors.self
        let cells = Double(Tuning.Room.gridWidth)
        let minU = rooms.map(\.u).min() ?? 0, maxU = (rooms.map(\.u).max() ?? 0) + cells
        let minV = rooms.map(\.v).min() ?? 0, maxV = (rooms.map(\.v).max() ?? 0) + cells
        let off = t.roadOffset, w = t.roadWidth
        let far = t.plotGap + t.plotCells * 2
        let back = street.map { $0.v } ?? minV - far
        var roads = [
            OutdoorRoad(alongU: true, at: maxV + off, width: w, from: minU - far, to: maxU + far),
            OutdoorRoad(alongU: false, at: minU - off, width: w, from: back, to: maxV + far),
            OutdoorRoad(alongU: false, at: maxU + off, width: w, from: back, to: maxV + far),
        ]
        if street == nil {
            roads.append(OutdoorRoad(alongU: true, at: minV - off, width: w, from: minU - far, to: maxU + far))
        }
        return roads
    }

    /// Where the scenery stands round a plot of rooms (each a square of `Tuning.Room.gridWidth` cells from its
    /// corner), laid out once from the household's seed as a garden is (OutdoorPlan): the same home always has the
    /// same garden. Pieces keep a margin from every room; tall ones only behind the house.
    public static func layout(
        biome: Biome,
        setting: String? = nil,
        rooms: [(u: Double, v: Double)],
        seed: UInt64,
        season: NatureSeason,
        snowy: Bool,
        file: OutdoorsFile
    ) -> [OutdoorPiece] {
        // A place's own pieces only when it has its own list (its setting picture prefix goes with them).
        let setting = setting.flatMap { file.places?[$0] == nil ? nil : $0 }
        let props = file.props(biome, setting: setting)
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
        let street = street(biome: biome, setting: setting, rooms: rooms, file: file)
        if let street {
            pieces = streetPieces(street, props: props, biome: biome, setting: setting, season: season, snowy: snowy, unit: unit)
        }
        // The garden's plan: each spot gets one of its role's pieces, in turn by weight along a line.
        func choices(_ role: OutdoorPlan.Role) -> [OutdoorsFile.Prop] {
            props.filter { $0.role == role.rawValue }.flatMap { Array(repeating: $0, count: max(1, $0.weight)) }
        }
        let spots = OutdoorPlan.spots(rooms: rooms, street: street, has: { !choices($0).isEmpty }, unit: unit)
        for spot in spots {
            let options = choices(spot.role)
            guard !options.isEmpty else { continue }
            let prop = options[(spot.pick * 7 + Int(unit() * 3)) % options.count]
            let width = prop.width * (1 - t.sizeVariation + 2 * t.sizeVariation * unit())
            guard clearOfRooms(spot.u, spot.v, width / 2) else { continue }
            let behind = spot.u < minU - t.margin || spot.v < minV - t.margin
            guard !prop.tall || behind else { continue }
            let picture = sprite(prop, biome: biome, setting: setting, season: season, snowy: snowy)
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
                u: spot.u,
                v: spot.v,
                width: width,
                tall: prop.tall,
                behind: behind,
                sway: snowy && prop.sprite == nil ? (prop.sway ?? 0) * 0.5 : prop.sway ?? 0,
                sheds: sheds
            ))
        }
        pieces += neighbours(props: props, minU: minU, maxU: maxU, minV: minV, maxV: maxV, street: street != nil,
                             biome: biome, setting: setting, season: season, snowy: snowy, unit: unit)
        // A garden piece is laid out all year, so everything else keeps its place, and put away under snow.
        return snowy ? pieces.filter { piece in props.first { $0.id == piece.prop }?.sprite == nil } : pieces
    }

    /// The houses next door (Josh, 22 Oct: "houses and gardens next door, trees etc", like a city builder's suburb):
    /// the town's neighbour plots (`place` "plot", each a square lot `Tuning.Outdoors.plotCells` across with its house
    /// and garden) in a ring round the garden, left, right and in front, and behind where no street runs.
    private static func neighbours( // swiftlint:disable:this function_parameter_count
        props: [OutdoorsFile.Prop],
        minU: Double, maxU: Double, minV: Double, maxV: Double,
        street: Bool,
        biome: Biome,
        setting: String?,
        season: NatureSeason,
        snowy: Bool,
        unit: () -> Double
    ) -> [OutdoorPiece] {
        let lots = props.filter { $0.place == "plot" }
        guard !lots.isEmpty else { return [] }
        let t = Tuning.Outdoors.self
        let size = t.plotCells, gap = t.plotGap
        var corners: [(u: Double, v: Double)] = []
        // The lot's back corner (its square runs from there to +size along u and v).
        let us = stride(from: minU - gap - size, through: maxU + gap, by: size).map { $0 }
        let vs = stride(from: minV - size, through: maxV, by: size).map { $0 }
        for v in vs {
            corners.append((minU - gap - size, v))
            corners.append((maxU + gap, v))
        }
        for u in us {
            corners.append((u, maxV + gap))
            if !street {
                corners.append((u, minV - gap - size))
            }
        }
        var last = -1
        return corners.map { corner in
            var pick = Int(unit() * Double(lots.count)) % lots.count
            if pick == last {
                pick = (pick + 1) % lots.count
            }
            last = pick
            let lot = lots[pick]
            // Drawn from its front corner, the bottom of its diamond, a little inside its square so a strip of the
            // ground shows between neighbours.
            let inset = size * (1 - t.plotFill) / 2
            let u = corner.u + size - inset, v = corner.v + size - inset
            return OutdoorPiece(
                prop: lot.id,
                sprite: sprite(lot, biome: biome, setting: setting, season: season, snowy: snowy),
                u: u,
                v: v,
                width: size * t.plotFill,
                tall: false,
                behind: u < minU || v < minV
            )
        }
    }

    /// The street's own pieces: the buildings in a row across the road, cars parked here and there along its far kerb,
    /// and a few things on the near pavement, each picked by weight from its place's props.
    private static func streetPieces( // swiftlint:disable:this function_parameter_count
        _ street: OutdoorStreet,
        props: [OutdoorsFile.Prop],
        biome: Biome,
        setting: String?,
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
                sprite: sprite(prop, biome: biome, setting: setting, season: season, snowy: snowy),
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
            u += prop.width * 3 + 2 + unit() * 6
        }
        u = street.from + 4 + unit() * 4
        while u < street.to, let prop = pick("pavement") {
            pieces.append(piece(prop, u: u, v: street.v + street.width / 2 + 0.7))
            u += 6 + unit() * 8
        }
        return pieces
    }
}
