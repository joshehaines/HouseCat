import Foundation
@testable import HouseCatCore

/// The 80 Catapult levels as laid out by hand (ten for each place on the map), before their solutions are found.
/// `CatapultLevelSearch` finds a solution for each and writes Content/catapult_levels.json; `CatapultLevelTests`
/// checks the file. Heights are bottoms, in metres; the cat pounces from x = 1.5.
struct CatapultDraft {
    var pieces: [CatapultLevel.Placed] = []
    var ledges: [CatapultLevel.Ledge] = []
    var mice: [Vec2] = []

    /// Things stacked one on another at `x` from `y`; returns the top.
    @discardableResult
    mutating func stack(_ x: Double, _ kinds: [CatapultPiece], from y: Double = 0, upright: Set<Int> = []) -> Double {
        var top = y
        for (n, kind) in kinds.enumerated() {
            let piece = CatapultLevel.Placed(kind, x: x, y: top, upright: upright.contains(n))
            pieces.append(piece)
            top = piece.top
        }
        return top
    }

    /// Two pillars `span` apart with a plank across; returns the plank's top.
    @discardableResult
    mutating func bridge(_ x: Double, span: Double, pillar: [CatapultPiece], plank: CatapultPiece = .plank, from y: Double = 0,
                         upright: Set<Int> = []) -> Double
    {
        let a = stack(x - span / 2, pillar, from: y, upright: upright)
        _ = stack(x + span / 2, pillar, from: y, upright: upright)
        return stack(x, [plank], from: a)
    }

    /// A pyramid of `rows` rows of a piece (the bottom row `rows` wide); returns its top.
    @discardableResult
    mutating func pyramid(_ x: Double, rows: Int, kind: CatapultPiece = .box, from y: Double = 0) -> Double {
        let width = 2 * kind.half.x + 0.02
        var top = y
        for row in 0 ..< rows {
            let count = rows - row
            for n in 0 ..< count {
                pieces.append(CatapultLevel.Placed(kind, x: x + (Double(n) - Double(count - 1) / 2) * width, y: top))
            }
            top += 2 * kind.half.y
        }
        return top
    }

    mutating func ledge(_ x: Double, y: Double = 0, width: Double, height: Double) {
        ledges.append(CatapultLevel.Ledge(x: x, y: y, width: width, height: height))
    }

    mutating func mouse(_ x: Double, on y: Double) {
        mice.append(Vec2(x, y))
    }
}

enum CatapultDesigns {
    struct Spec {
        let title: String
        let pounces: Int
        let par: Int
        let build: (inout CatapultDraft) -> Void
    }

    /// Each place's own pieces and the fixed thing it has (a wall, rocks, a log ...), so the same kind of level
    /// looks and plays its own way in each.
    struct Place {
        let biome: Biome
        let titles: [String]
        /// The kinds that make up its stacks, lightest first.
        let light: CatapultPiece
        let heavy: CatapultPiece
        /// Its fixed ledge: middle, width, height.
        let ledge: (Double, Double, Double)
        /// Pushes levels a little further or nearer.
        let shift: Double
    }

    static let places: [Place] = [
        Place(biome: .city, titles: ["The back step", "Bin day", "Over the wall", "Two towers", "The shed roof", "Pallet pile",
                                     "Chimney pots", "Washing day", "Window boxes", "Rooftop party"],
              light: .box, heavy: .book, ledge: (9.5, 0.5, 1.0), shift: 0),
        Place(biome: .coast, titles: ["Sandcastle", "Beach huts", "The sea wall", "Rock pools", "Deckchairs", "Lobster pots",
                                      "Pier end", "Lighthouse", "Ice cream queue", "High tide"],
              light: .wide, heavy: .pot, ledge: (10.5, 1.2, 0.6), shift: 0.5),
        Place(biome: .countryside, titles: ["Hay bales", "The barn door", "Over the stile", "Milk churns", "Hen house",
                                            "Apple crates", "The tractor", "Harvest", "Scarecrow", "Village fête"],
              light: .box, heavy: .pot, ledge: (8.5, 1.4, 0.8), shift: -0.3),
        Place(biome: .mountain, titles: ["Base camp", "First ledge", "Boulder field", "The pass", "Mountain hut",
                                         "Two peaks", "The gully", "Rope bridge", "Summit cairn", "Above the clouds"],
              light: .book, heavy: .pot, ledge: (11.0, 1.6, 1.4), shift: 0.8),
        Place(biome: .forest, titles: ["Fallen log", "Toadstools", "The woodpile", "Badger sett", "Tree stump", "Bluebells",
                                       "The clearing", "Owl's hollow", "Ferns", "Deep in the woods"],
              light: .box, heavy: .book, ledge: (9.0, 2.2, 0.5), shift: 0.2),
        Place(biome: .desert, titles: ["Sand dune", "The oasis", "Cactus pots", "Market stall", "Rug sellers", "Spice sacks",
                                       "The well", "Palm shade", "Courtyard", "Starry night"],
              light: .wide, heavy: .pot, ledge: (10.0, 1.0, 1.0), shift: 0.4),
        Place(biome: .tropical, titles: ["Coconut shy", "Beach cafe", "The jetty", "Hammock", "Surf shack", "Mango tree",
                                         "Lagoon", "Tiki torches", "Sunset deck", "Monsoon"],
              light: .box, heavy: .book, ledge: (9.8, 1.8, 0.4), shift: -0.2),
        Place(biome: .snow, titles: ["Snowman", "Sledge run", "The igloo", "Snowbank", "Ski lodge", "Icicles",
                                     "Frozen pond", "Log cabin", "Snowball fort", "Northern lights"],
              light: .wide, heavy: .book, ledge: (10.2, 1.2, 1.2), shift: 0.6),
    ]

    /// The ten kinds of level, easiest first; each place builds them with its own pieces and ledge.
    static func specs(for place: Place) -> [Spec] {
        let s = place.shift, light = place.light, heavy = place.heavy
        let (lx, lw, lh) = place.ledge
        return [
            Spec(title: place.titles[0], pounces: 3, par: 1) { d in
                let top = d.stack(8 + s, [light, light])
                d.mouse(8 + s, on: top)
            },
            Spec(title: place.titles[1], pounces: 3, par: 1) { d in
                let top = d.stack(9.5 + s, [heavy, heavy, heavy, light])
                d.mouse(9.5 + s, on: top)
            },
            Spec(title: place.titles[2], pounces: 3, par: 1) { d in
                d.ledge(lx + s - 2.2, width: 0.5, height: 1.4)
                let top = d.stack(lx + s, [light, light, heavy])
                d.mouse(lx + s, on: top)
            },
            Spec(title: place.titles[3], pounces: 3, par: 2) { d in
                let a = d.stack(8 + s, [light, heavy, light])
                d.mouse(8 + s, on: a)
                let b = d.stack(12 + s, [heavy, light, light, light])
                d.mouse(12 + s, on: b)
            },
            Spec(title: place.titles[4], pounces: 3, par: 1) { d in
                d.ledge(lx + s, width: lw, height: lh)
                let top = d.stack(lx + s, [light, light], from: lh)
                d.mouse(lx + s, on: top)
            },
            Spec(title: place.titles[5], pounces: 4, par: 2) { d in
                let top = d.pyramid(10 + s, rows: 3, kind: light)
                d.mouse(10 + s, on: top)
                let side = d.stack(12.5 + s, [heavy, light])
                d.mouse(12.5 + s, on: side)
            },
            Spec(title: place.titles[6], pounces: 4, par: 2) { d in
                let top = d.bridge(10 + s, span: 1.0, pillar: [light, light])
                d.mouse(9.75 + s, on: top)
                d.mouse(10.25 + s, on: top)
                let up = d.stack(10 + s, [heavy, light], from: top)
                d.mouse(10 + s, on: up)
            },
            Spec(title: place.titles[7], pounces: 4, par: 2) { d in
                d.ledge(8 + s, width: 0.4, height: 2.0)
                let a = d.stack(10.5 + s, [heavy, heavy, light, light])
                d.mouse(10.5 + s, on: a)
                let b = d.bridge(13 + s, span: 1.2, pillar: [light, heavy], plank: .short)
                d.mouse(13 + s, on: b)
            },
            Spec(title: place.titles[8], pounces: 5, par: 3) { d in
                d.ledge(lx + s, width: lw, height: lh)
                let a = d.stack(lx + s, [light], from: lh)
                d.mouse(lx + s, on: a)
                let b = d.bridge(lx + s + 2.4, span: 1.0, pillar: [heavy, light, light])
                d.stack(lx + s + 2.15, [.tin], from: b)
                d.mouse(lx + s + 2.6, on: b)
                let c = d.stack(lx + s - 2.4, [light, light, light])
                d.mouse(lx + s - 2.4, on: c)
            },
            Spec(title: place.titles[9], pounces: 5, par: 3) { d in
                let base = d.bridge(10 + s, span: 1.6, pillar: [heavy, light, light])
                let mid = d.bridge(10 + s, span: 0.9, pillar: [light], plank: .short, from: base)
                d.mouse(10 + s, on: mid)
                d.mouse(9.1 + s, on: base)
                d.mouse(10.9 + s, on: base)
                d.ledge(13.4 + s, width: 0.8, height: 0.9)
                let far = d.stack(13.4 + s, [light, heavy], from: 0.9)
                d.mouse(13.4 + s, on: far)
            },
        ]
    }

    /// Every level, without solutions, in the order of `Biome.allCases`, ten a place.
    static var drafts: [CatapultLevel] {
        var levels: [CatapultLevel] = []
        for place in places {
            for spec in specs(for: place) {
                var draft = CatapultDraft()
                spec.build(&draft)
                levels.append(CatapultLevel(id: levels.count, place: place.biome, title: spec.title, pounces: spec.pounces,
                                            par: spec.par, ledges: draft.ledges, pieces: draft.pieces, mice: draft.mice))
            }
        }
        return levels
    }
}
