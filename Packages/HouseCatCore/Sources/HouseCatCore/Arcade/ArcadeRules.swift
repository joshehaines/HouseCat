import Foundation

/// The Games menu's games (CLAUDE.md "The Games menu"). The three quick games with the cat (`MiniGameRules`) are
/// apart from these: they keep their own five plays a day.
public enum ArcadeGame: String, Codable, Sendable, CaseIterable {
    /// The runner: three lanes, biscuits and mice.
    case zoomies
    /// The pounce game: knock the toy mice off their towers, levels set in each place on the map.
    case catapult
    /// The match-three.
    case match
    /// Four in a row against the cats from the intro's homes.
    case row

    /// Played in levels whose stars pay once (otherwise a score, paid for the first plays of the day).
    public var hasLevels: Bool {
        self == .catapult || self == .match
    }

    public var levelCount: Int {
        switch self {
        case .catapult: Tuning.Arcade.catapultLevels
        case .match: Tuning.Arcade.matchLevels
        case .zoomies, .row: 0
        }
    }
}

/// A finished game, as the `arcadePlayed` event carries it. `stats` are what the challenges count ("biscuits",
/// "mice", "distance", "clears", "threeStars", "boxes", "lasers", "dust", "wins", "games" ...).
public struct ArcadeResult: Codable, Hashable, Sendable {
    public var game: ArcadeGame
    /// Catapult and Purrfect Match: the level, from 0.
    public var level: Int?
    public var score: Int
    /// 0 to 3.
    public var stars: Int
    /// Cats in a Row: the cat played and whether the player won (two people on one device record no opponent).
    public var opponent: String?
    public var won: Bool
    public var stats: [String: Int]

    public init(game: ArcadeGame, level: Int? = nil, score: Int, stars: Int, opponent: String? = nil, won: Bool,
                stats: [String: Int] = [:])
    {
        self.game = game
        self.level = level
        self.score = score
        self.stars = stars
        self.opponent = opponent
        self.won = won
        self.stats = stats
    }
}

/// Today's puzzle solved: its number, how long it took and the hints used (shown in the album; the pay is the same).
public struct PuzzleSolve: Codable, Hashable, Sendable {
    public var number: Int
    public var seconds: Int
    public var hints: Int

    public init(number: Int, seconds: Int, hints: Int = 0) {
        self.number = number
        self.seconds = seconds
        self.hints = hints
    }
}

/// What a game or a puzzle paid, for the results card.
public struct ArcadePayout: Equatable, Sendable {
    public var beans = 0
    public var xp = 0
    /// The paid play this was (1-based), nil when it was past the day's paid plays or a level game.
    public var paidPlay: Int?
    public var newBest = false
    /// Level games: stars reached for the first time.
    public var newStars = 0
    public var firstClear = false
    /// Cats in a Row: the first win against this cat.
    public var firstWin = false
    /// Challenges met by this game (ids from `ArcadeChallenges.pool`).
    public var challenges: [String] = []
    /// The puzzle: the streak after it and any streak bonus in `beans`.
    public var puzzleStreak = 0
    public var streakBonus = 0

    public init() {}
}

/// Everything the games keep in the save, derived from `arcadePlayed` and `puzzleSolved` events only.
public struct ArcadeState: Codable, Equatable, Sendable {
    /// The day the daily counts are for.
    public internal(set) var day: GameDay?
    /// Plays of each game today.
    public internal(set) var plays: [String: Int] = [:]
    /// Today's stats added up over every play ("zoomies.biscuits") and the best of one play.
    public internal(set) var total: [String: Int] = [:]
    public internal(set) var top: [String: Int] = [:]
    /// Challenges paid today.
    public internal(set) var challengesPaid: Set<String> = []
    /// Best score at each score game.
    public internal(set) var best: [String: Int] = [:]
    /// Level games: the most stars reached on each level ("catapult" → level → stars).
    public internal(set) var stars: [String: [Int: Int]] = [:]
    /// Cats in a Row: the cats beaten.
    public internal(set) var beaten: Set<String> = []
    /// Puzzles solved on their own day, by number.
    public internal(set) var puzzles: [Int: PuzzleSolve] = [:]
    public internal(set) var puzzleStreak = 0
    public internal(set) var longestPuzzleStreak = 0
    public internal(set) var lastPuzzleDay: GameDay?
    public internal(set) var lifetimePlays = 0

    public init() {}

    /// Moves the daily counts to `day` (a new day starts them again).
    mutating func roll(to day: GameDay) {
        guard self.day != day else { return }
        if let current = self.day, day < current {
            return
        }
        self.day = day
        plays = [:]
        total = [:]
        top = [:]
        challengesPaid = []
    }

    /// The paid plays left today at a score game.
    public func paidPlaysLeft(_ game: ArcadeGame, on day: GameDay) -> Int {
        guard !game.hasLevels else { return 0 }
        let used = self.day == day ? plays[game.rawValue, default: 0] : 0
        return max(0, Tuning.Arcade.paidPlaysPerDay - used)
    }

    public func stars(_ game: ArcadeGame, level: Int) -> Int {
        stars[game.rawValue]?[level] ?? 0
    }

    /// Stars over every level of a level game.
    public func totalStars(_ game: ArcadeGame) -> Int {
        stars[game.rawValue]?.values.reduce(0, +) ?? 0
    }

    /// The first level not yet cleared (every level before it has at least a star), capped at the last.
    public func nextLevel(_ game: ArcadeGame) -> Int {
        let cleared = stars[game.rawValue] ?? [:]
        var level = 0
        while level < game.levelCount - 1, cleared[level, default: 0] > 0 {
            level += 1
        }
        return level
    }

    /// A level can be played once the one before it is cleared; Catapult's places each start open.
    public func isOpen(_ game: ArcadeGame, level: Int) -> Bool {
        guard level >= 0, level < game.levelCount else { return false }
        if level == 0 || game == .catapult && level % Tuning.Arcade.Catapult.levelsPerPlace == 0 {
            return true
        }
        return self.stars(game, level: level - 1) > 0
    }

    /// Today's progress at a challenge.
    public func progress(_ challenge: ArcadeChallenge, on day: GameDay) -> Int {
        guard self.day == day else { return 0 }
        let key = "\(challenge.game.rawValue).\(challenge.stat)"
        return challenge.mode == .best ? top[key, default: 0] : total[key, default: 0]
    }

    /// A finished game: what it pays (the reducer earns the Beans and XP).
    public mutating func record(_ result: ArcadeResult, on day: GameDay, seed: UInt64) -> ArcadePayout {
        roll(to: day)
        var payout = ArcadePayout()
        let game = result.game
        let stars = min(max(result.stars, 0), 3)
        plays[game.rawValue, default: 0] += 1
        lifetimePlays += 1
        if game.hasLevels {
            if let level = result.level, level >= 0, level < game.levelCount, isOpen(game, level: level) {
                let before = self.stars(game, level: level)
                if stars > before {
                    self.stars[game.rawValue, default: [:]][level] = stars
                    payout.newStars = stars - before
                    payout.beans += payout.newStars * Tuning.Arcade.beansPerLevelStar
                    if before == 0 {
                        payout.firstClear = true
                        payout.xp += Tuning.Arcade.xpPerFirstClear
                    }
                }
            }
        } else {
            if result.score > best[game.rawValue, default: 0] {
                best[game.rawValue] = result.score
                payout.newBest = true
            }
            let play = plays[game.rawValue, default: 0]
            if play <= Tuning.Arcade.paidPlaysPerDay {
                payout.paidPlay = play
                payout.xp += Tuning.Arcade.xpPerPaidPlay
                if stars > 0 {
                    payout.beans += Tuning.Arcade.starBeans[stars - 1]
                }
            }
            if game == .row, result.won, let opponent = result.opponent, ArcadeOpponents.ids.contains(opponent),
               !beaten.contains(opponent)
            {
                beaten.insert(opponent)
                payout.firstWin = true
                payout.beans += Tuning.Arcade.firstWinBeans
            }
        }
        for (stat, value) in result.stats {
            let key = "\(game.rawValue).\(stat)"
            total[key, default: 0] += value
            top[key] = max(top[key, default: 0], value)
        }
        payChallenges(on: day, seed: seed, into: &payout)
        return payout
    }

    /// Today's puzzle solved: its Beans and XP, and the streak's. A puzzle of another day pays nothing.
    public mutating func record(_ solve: PuzzleSolve, on day: GameDay) -> ArcadePayout {
        roll(to: day)
        var payout = ArcadePayout()
        guard solve.number == ArcadePuzzles.number(on: day), puzzles[solve.number] == nil else {
            payout.puzzleStreak = puzzleStreak
            return payout
        }
        puzzles[solve.number] = solve
        if let last = lastPuzzleDay, last.advanced(by: 1) == day {
            puzzleStreak += 1
        } else {
            puzzleStreak = 1
        }
        lastPuzzleDay = day
        longestPuzzleStreak = max(longestPuzzleStreak, puzzleStreak)
        payout.beans = Tuning.Arcade.Puzzle.beans
        payout.xp = Tuning.Arcade.Puzzle.xp
        payout.streakBonus = ArcadePuzzles.streakBonus(day: puzzleStreak)
        payout.beans += payout.streakBonus
        payout.puzzleStreak = puzzleStreak
        return payout
    }

    /// The puzzle streak as it stands on `day`: kept through yesterday, gone once a day is missed.
    public func puzzleStreak(on day: GameDay) -> Int {
        guard let last = lastPuzzleDay else { return 0 }
        return last == day || last.advanced(by: 1) == day ? puzzleStreak : 0
    }

    public func solvedToday(on day: GameDay) -> Bool {
        puzzles[ArcadePuzzles.number(on: day)] != nil
    }

    private mutating func payChallenges(on day: GameDay, seed: UInt64, into payout: inout ArcadePayout) {
        for challenge in ArcadeChallenges.today(on: day, seed: seed) where !challengesPaid.contains(challenge.id) {
            if progress(challenge, on: day) >= challenge.target {
                challengesPaid.insert(challenge.id)
                payout.challenges.append(challenge.id)
                payout.beans += Tuning.Arcade.Challenges.beans
                payout.xp += Tuning.Arcade.Challenges.xp
            }
        }
    }
}

/// The daily puzzle's numbering: No. 1 on `Tuning.Arcade.Puzzle.firstDay`, one a day after it.
public enum ArcadePuzzles {
    public static func number(on day: GameDay) -> Int {
        day.index - Tuning.Arcade.Puzzle.firstDay.index + 1
    }

    /// The extra Beans for reaching `day` days in a row (the 3rd and 7th of every week of the streak).
    public static func streakBonus(day streak: Int) -> Int {
        guard streak > 0 else { return 0 }
        return Tuning.Arcade.Puzzle.streakBonus[streak % Tuning.Arcade.Puzzle.streakCycle] ?? 0
    }
}

/// The cats to play at Cats in a Row, easiest first (names and looks: Content/arcade.json; the ids the save pays
/// a first win for).
public enum ArcadeOpponents {
    public static let ids = ["biscuit", "clover", "bram", "nata", "mango", "juniper", "saffron", "pat"]
}

/// A daily challenge: reach `target` of a stat at one game, in one play (`best`) or over the day (`total`).
public struct ArcadeChallenge: Equatable, Sendable, Identifiable {
    public enum Mode: Sendable {
        case best, total
    }

    public let id: String
    public let game: ArcadeGame
    public let stat: String
    public let mode: Mode
    public let target: Int
}

/// Three a day, one each from three different games, picked by the household's seed (the same on every device);
/// the words for each are in Content/arcade.json by id.
public enum ArcadeChallenges {
    public static let pool: [ArcadeChallenge] = [
        ArcadeChallenge(id: "zoomies.biscuits40", game: .zoomies, stat: "biscuits", mode: .best, target: 40),
        ArcadeChallenge(id: "zoomies.biscuits80", game: .zoomies, stat: "biscuits", mode: .best, target: 80),
        ArcadeChallenge(id: "zoomies.mice3", game: .zoomies, stat: "mice", mode: .best, target: 3),
        ArcadeChallenge(id: "zoomies.distance500", game: .zoomies, stat: "distance", mode: .best, target: 500),
        ArcadeChallenge(id: "zoomies.runs3", game: .zoomies, stat: "runs", mode: .total, target: 3),
        ArcadeChallenge(id: "catapult.clear1", game: .catapult, stat: "clears", mode: .total, target: 1),
        ArcadeChallenge(id: "catapult.clear3", game: .catapult, stat: "clears", mode: .total, target: 3),
        ArcadeChallenge(id: "catapult.three", game: .catapult, stat: "threeStars", mode: .total, target: 1),
        ArcadeChallenge(id: "catapult.mice10", game: .catapult, stat: "mice", mode: .total, target: 10),
        ArcadeChallenge(id: "match.clear1", game: .match, stat: "clears", mode: .total, target: 1),
        ArcadeChallenge(id: "match.three", game: .match, stat: "threeStars", mode: .total, target: 1),
        ArcadeChallenge(id: "match.box", game: .match, stat: "boxes", mode: .total, target: 1),
        ArcadeChallenge(id: "match.laser", game: .match, stat: "lasers", mode: .total, target: 1),
        ArcadeChallenge(id: "match.dust30", game: .match, stat: "dust", mode: .total, target: 30),
        ArcadeChallenge(id: "row.win1", game: .row, stat: "wins", mode: .total, target: 1),
        ArcadeChallenge(id: "row.win2", game: .row, stat: "wins", mode: .total, target: 2),
        ArcadeChallenge(id: "row.games3", game: .row, stat: "games", mode: .total, target: 3),
    ]

    public static func today(on day: GameDay, seed: UInt64) -> [ArcadeChallenge] {
        var draw = DaySeed(household: seed, day: day, purpose: "arcade.challenges")
        let games = Array(draw.shuffled(ArcadeGame.allCases).prefix(Tuning.Arcade.Challenges.perDay))
        return games.map { game in
            let choices = pool.filter { $0.game == game }
            return choices[draw.below(choices.count)]
        }
    }
}
