import Foundation

/// The game's words and items as data (docs/CONTENT.md): decoded from
/// `Content/*.json`, never hard-coded. Field names match the JSON exactly.
public struct ContentBundle: Sendable {
    public var lines: LinesFile
    public var catalogue: CatalogueFile
    public var gifts: GiftsFile
    public var outfits: OutfitsFile
    public var objectives: ObjectivesFile
    public var seasons: SeasonsFile
    public var minigames: MinigamesFile
    /// The word filter for cat names.
    public var names: NameFilter
    /// The seasonal weather tables per biome.
    public var weather: WeatherFile
    /// The intro: the host's words, the tour of homes round the world, the room tour.
    public var intro: IntroFile
    /// Launch events: the Housewarming gift track and the Housewarming pack's sale.
    public var events: EventsFile
    /// Room looks sold for money.
    public var bundles: BundlesFile
    /// What each level gives.
    public var levels: LevelsFile

    /// Loads every content file from a directory (the app bundle's `Content`).
    public static func load(from directory: URL) throws -> ContentBundle {
        func read<T: Decodable>(_ name: String) throws -> T {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ContentError.invalidFile(name, String(describing: error))
            }
        }
        return try ContentBundle(
            lines: read("lines"),
            catalogue: read("catalogue"),
            gifts: read("gifts"),
            outfits: read("outfits"),
            objectives: read("objectives"),
            seasons: read("seasons"),
            minigames: read("minigames"),
            names: read("names"),
            weather: read("weather"),
            intro: read("intro"),
            events: read("events"),
            bundles: read("bundles"),
            levels: read("levels")
        )
    }

    /// The content the rules engine needs.
    public func rulesContext() throws -> RulesContext {
        try RulesContext(
            gifts: gifts.gifts.map { GiftDefinition(id: $0.id, rarity: $0.rarity, months: $0.months) },
            dailyObjectives: objectives.daily.map(\.definition),
            weeklyObjectives: objectives.weekly.map(\.definition),
            achievements: objectives.achievements.map(\.definition),
            seasons: seasons.seasons.map { try $0.definition() },
            paidItems: Set(catalogue.items.filter { [.set, .housewarming, .founders].contains($0.pool) }.map(\.id)),
            events: events.definitions(launch: GameDay(iso: seasons.seasons.first?.startAt ?? "") ?? GameDay(index: 0)),
            bundles: Dictionary(uniqueKeysWithValues: bundles.bundles.map { ($0.id, $0) }),
            levels: levels,
            shapes: Dictionary(uniqueKeysWithValues: catalogue.items.map {
                ($0.id, RulesContext.Shape(width: $0.footprint.w, depth: $0.footprint.d, onWall: $0.layer == .wall, decal: $0.decal))
            })
        )
    }

    /// Affordances by catalogue item id, for the behaviour table.
    public var affordances: [String: Set<Affordance>] {
        Dictionary(uniqueKeysWithValues: catalogue.items.map { ($0.id, Set($0.affordances)) })
    }
}

public enum ContentError: Error, Equatable {
    case invalidFile(String, String)
    case invalidDate(String)
}

// MARK: lines.json

public struct LinesFile: Codable, Sendable {
    public struct Context: Codable, Sendable {
        public var id: String
        public var condition: String
    }

    public struct Line: Codable, Sendable {
        public enum Meow: String, Codable, Sendable {
            case short, long, chirp, trill, purr, grumble, silent
        }

        public var context: String
        public var personality: Personality
        public var variants: [String]
        public var meow: Meow
    }

    public var version: Int
    public var placeholders: [String]
    public var contexts: [Context]
    public var lines: [Line]

    /// The variants for a context and personality.
    public func variants(for context: String, personality: Personality) -> [String] {
        lines.first { $0.context == context && $0.personality == personality }?.variants ?? []
    }
}

// MARK: catalogue.json

public enum ItemPool: String, Codable, Sendable, CaseIterable {
    case free
    case beans
    case set
    case passFree = "pass-free"
    case passPaid = "pass-paid"
    case housewarming
    case founders
    case club
}

public struct CatalogueFile: Codable, Sendable {
    public struct FurnitureSet: Codable, Sendable {
        public var id: String
        public var name: String
        public var sku: String
        public var bundleSku: String
        public var bundleBeans: Int
        public var outfit: String
        public var wallpaper: String
        public var floor: String
    }

    public struct Footprint: Codable, Sendable, Equatable {
        public var w: Int
        public var d: Int
    }

    public struct Motion: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case `static`, sway, bob, glow, spin, frames
        }

        public var type: Kind
        public var pivot: [Double]?
        public var period: Double?
        public var fx: String?
        public var frames: Int?
    }

    public struct Effect: Codable, Sendable, Equatable {
        public var fx: String
        public var anchor: [Double]
    }

    public struct Item: Codable, Sendable {
        public enum Layer: String, Codable, Sendable {
            case floor, wall
        }

        public var id: String
        public var name: String
        public var set: String?
        public var room: String
        public var footprint: Footprint
        public var layer: Layer
        public var decal: Bool
        public var affordances: [Affordance]
        public var capacity: Int
        public var motion: Motion
        public var pool: ItemPool
        public var level: Int
        public var beans: Int?
        public var sku: String?
        public var description: String
        public var catPose: CatPose?
        public var sprites: [String: String]
        public var suggestedScale: Double?
        public var fx: Effect?
    }

    public struct Surface: Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case wall, floor
        }

        public var id: String
        public var kind: Kind
        public var room: String
        public var name: String
        public var pool: ItemPool
        public var beans: Int?
        public var set: String?
        public var sprite: String
    }

    /// Painted items left out of the game on purpose, with the reason.
    public struct Excluded: Codable, Sendable {
        public var id: String
        public var reason: String
    }

    public var version: Int
    public var sets: [FurnitureSet]
    public var items: [Item]
    public var surfaces: [Surface]
    public var excluded: [Excluded]?
}

// MARK: gifts.json, outfits.json

public struct GiftsFile: Codable, Sendable {
    public struct Gift: Codable, Sendable {
        public var id: String
        public var name: String
        public var category: String
        public var rarity: GiftRarity
        public var description: String
        public var months: [Int]
        public var sprite: String
    }

    public var version: Int
    public var gifts: [Gift]
}

public struct OutfitsFile: Codable, Sendable {
    public struct Outfit: Codable, Sendable {
        public enum Slot: String, Codable, Sendable {
            case head, neck, body
        }

        public enum Pool: String, Codable, Sendable, CaseIterable {
            case paid
            case earned
            case passFree = "pass-free"
            case passPaid = "pass-paid"
            case founders
        }

        public var id: String
        public var name: String
        public var slot: Slot
        public var views: [String]
        public var pool: Pool
        public var sku: String?
        public var earnedBy: String?
        public var months: [Int]
        public var sprites: [String: String]
    }

    public var version: Int
    public var outfits: [Outfit]
}

// MARK: objectives.json

public struct ObjectivesFile: Codable, Sendable {
    public struct Objective: Codable, Sendable {
        public var id: String
        public var name: String
        public var text: String
        public var metric: ObjectiveMetric
        public var target: Int
        public var beans: Int
        public var passPoints: Int
        public var ladder: String?

        public var definition: ObjectiveDefinition {
            ObjectiveDefinition(id: id, metric: metric, target: target, beans: beans, passPoints: passPoints)
        }
    }

    public var version: Int
    public var daily: [Objective]
    public var weekly: [Objective]
    public var achievements: [Objective]
}

// MARK: seasons.json, minigames.json

public struct SeasonsFile: Codable, Sendable {
    public struct Season: Codable, Sendable {
        public var id: String
        public var name: String
        public var theme: String
        public var startAt: String
        public var endAt: String
        public var provisional: Bool?
        /// The December season.
        public var christmas: Bool?
        public var sku: String
        public var freeTrack: [PassReward]
        public var paidTrack: [PassReward]

        public func definition() throws -> SeasonDefinition {
            guard let start = GameDay(iso: startAt) else { throw ContentError.invalidDate(startAt) }
            guard let end = GameDay(iso: endAt) else { throw ContentError.invalidDate(endAt) }
            return SeasonDefinition(id: id, startDay: start, endDay: end, freeTrack: freeTrack, paidTrack: paidTrack)
        }
    }

    public var version: Int
    public var seasonLengthDays: Int
    public var tiers: Int
    public var seasons: [Season]
}

public struct MinigamesFile: Codable, Sendable {
    public struct Game: Codable, Sendable {
        public var id: String
        public var name: String
        public var durationSeconds: Int
        public var score: String
        public var stars: [Int]
        public var rules: String
    }

    public var version: Int
    public var playsPerDay: Int
    public var xpPerPlay: Int
    public var starBeans: [Int]
    public var passPointsPerPlay: Int
    public var games: [Game]
}

public extension CatalogueFile {
    /// A room's starting wallpaper or floor until the player picks one: its first free surface by id
    /// (SPEC: five per room, three of each free).
    func defaultSurface(_ kind: Surface.Kind, in room: RoomID) -> Surface? {
        surfaces.filter { $0.room == room.rawValue && $0.kind == kind && $0.pool == .free }.min { $0.id < $1.id }
    }
}

// MARK: intro.json

/// The intro (a builder game's first five minutes, in the house style): the host's lines, the tour of example
/// homes round the world (a real place, a home painted there, a cat living in it), and the steps of the guided
/// tour of the room. Text here is the intro's own; the player's cat speaks from lines.json.
public struct IntroFile: Codable, Sendable {
    public struct Stop: Codable, Sendable, Identifiable {
        public struct Cat: Codable, Sendable {
            public var preset: String
            public var name: String
            public var personality: Personality
        }

        public var id: String
        public var place: String
        public var country: String
        public var latitude: Double
        public var longitude: Double
        public var timeZone: String
        /// The painting (art path without extension).
        public var scene: String
        public var home: String
        public var season: NatureSeason
        public var weather: Weather
        public var cat: Cat
        public var line: String

        /// The sky there now, at its own local time (the homes are somewhere real).
        public func sky(at date: Date) -> SkyPhase {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return .at(localMinutes: (parts.hour ?? 12) * 60 + (parts.minute ?? 0))
        }
    }

    /// A step of the room tour: what the host says, the control it points at, what the player must do to go on
    /// (none: a tap on Next), and whether it gives the welcome Beans.
    public struct RoomStep: Codable, Sendable, Identifiable {
        public enum Wait: String, Codable, Sendable {
            case fed, petted, decorating, placed, decorated
        }

        public var id: String
        public var target: String?
        public var waitFor: Wait?
        public var reward: Bool?
        public var text: String

        /// The text with the cat's name in it.
        public func text(cat: String) -> String {
            text.replacingOccurrences(of: "{cat}", with: cat)
        }
    }

    public var version: Int
    public var host: String
    public var tagline: String
    public var hello: [String]
    public var stops: [Stop]
    public var outro: String
    public var builder: String
    public var map: String
    public var homes: String
    public var room: [RoomStep]
}

// MARK: events.json

/// Launch events (SPEC "Launch"): a gift track (one present a day for a run of days) or a sale (an item on sale
/// for a run of days). Days count from launch, the first season's start, so every date shown is real.
public struct EventsFile: Codable, Sendable {
    public struct Event: Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case track, sale
        }

        public var id: String
        public var name: String
        public var kind: Kind
        public var startDay: Int
        public var days: Int
        public var sku: String?
        public var blurb: String
        public var rewards: [EventReward]?
    }

    public var version: Int
    public var events: [Event]

    func definitions(launch: GameDay) -> [EventDefinition] {
        events.map {
            EventDefinition(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                startDay: launch.advanced(by: $0.startDay),
                endDay: launch.advanced(by: $0.startDay + $0.days),
                sku: $0.sku,
                rewards: $0.rewards ?? []
            )
        }
    }
}
