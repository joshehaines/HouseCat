import Foundation

/// The Games menu's words and cats (Content/arcade.json): each game's name, line and how to play, the cats to play
/// at Cats in a Row with their lines, the challenges' words by id, the places' names.
public struct ArcadeFile: Codable, Sendable {
    public struct Game: Codable, Sendable {
        public var id: String
        public var name: String
        public var tagline: String
        public var howTo: [String]
    }

    public struct Opponent: Codable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// A cat builder preset (its look).
        public var preset: String
        public var personality: Personality
        public var home: String
        public var skill: RowSkill
        /// How it plays, in a few words.
        public var style: String
        public var meet: String
        public var wins: String
        public var loses: String
    }

    public var version: Int
    public var games: [Game]
    public var opponents: [Opponent]
    public var challenges: [String: String]
    public var places: [String: String]

    public func game(_ id: ArcadeGame) -> Game? {
        games.first { $0.id == id.rawValue }
    }

    public func opponent(_ id: String) -> Opponent? {
        opponents.first { $0.id == id }
    }
}

/// Everything the Games menu reads from Content/.
public struct ArcadeContent: Sendable {
    public var file: ArcadeFile
    public var match: MatchLevelsFile
    public var catapult: CatapultLevelsFile

    public init(file: ArcadeFile, match: MatchLevelsFile, catapult: CatapultLevelsFile) {
        self.file = file
        self.match = match
        self.catapult = catapult
    }

    public static func load(from directory: URL) throws -> ArcadeContent {
        let decoder = JSONDecoder()
        func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            try decoder.decode(type, from: Data(contentsOf: directory.appendingPathComponent(name)))
        }
        return try ArcadeContent(
            file: read("arcade.json", as: ArcadeFile.self),
            match: read("match_levels.json", as: MatchLevelsFile.self),
            catapult: read("catapult_levels.json", as: CatapultLevelsFile.self)
        )
    }

    /// Catapult's levels in a place, in order.
    public func catapultLevels(in place: Biome) -> [CatapultLevel] {
        catapult.levels.filter { $0.place == place }.sorted { $0.id < $1.id }
    }

    /// The places in the order the menu shows them: the home's first, then the map's order.
    public static func places(home: Biome) -> [Biome] {
        [home] + Biome.allCases.filter { $0 != home }
    }
}
