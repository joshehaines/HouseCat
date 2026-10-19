import Foundation
@testable import HouseCatCore
import Testing

/// Sets each designed Purrfect Match level's moves and star scores from games of `MatchBot`, and writes
/// Content/match_levels.json. Off unless asked:
/// HOUSECAT_MATCH_SEARCH=1 swift test -c release -Xswiftc -enable-testing --filter MatchLevelSearch
@Suite("Match level search")
struct MatchLevelSearch {
    static let contentURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Content/match_levels.json")

    static let games = 32

    /// The bot's games of `level` with `moves`: whether each was won and its score.
    static func play(_ level: MatchLevel, moves: Int) -> [(won: Bool, score: Int)] {
        var level = level
        level.moves = moves
        return (0 ..< games).map { n in
            var game = MatchGame(level: level, seed: DaySeed(household: 77, day: GameDay(index: level.id), purpose: "match", salt: "\(n)"))
            var bot = DaySeed(household: 78, day: GameDay(index: level.id), purpose: "bot", salt: "\(n)")
            MatchBot.play(&game, seed: &bot)
            return (game.goalsMet, game.score)
        }
    }

    @Test func calibrate() throws {
        guard ProcessInfo.processInfo.environment["HOUSECAT_MATCH_SEARCH"] == "1" else { return }
        var levels: [MatchLevel] = []
        for (id, draft) in MatchDesigns.drafts.enumerated() {
            let start = Date()
            var level = MatchLevel(id: id, layout: draft.layout, moves: 0, kinds: draft.kinds, goals: draft.goals, stars: [0, 0],
                                   title: draft.title)
            let rate = { (level: MatchLevel) in Double(Self.play(level, moves: level.moves).filter(\.won).count) / Double(Self.games) }
            if draft.goals.contains(where: { $0.hasPrefix("collect:") }) {
                // A set number of moves; the counts to collect scaled to the most the bot gets as often as asked.
                level.moves = id < 10 ? 20 : id < 40 ? 22 : 25
                func scaled(_ factor: Double) -> MatchLevel {
                    var l = level
                    l.goals = draft.goals.map { goal in
                        let parts = goal.split(separator: ":")
                        guard parts.count == 3, let count = Int(parts[2]) else { return goal }
                        return "collect:\(parts[1]):\(max(5, Int((Double(count) * factor / 5).rounded()) * 5))"
                    }
                    return l
                }
                var lowF = 0.3, highF = 6.0
                for _ in 0 ..< 9 {
                    let mid = (lowF + highF) / 2
                    if rate(scaled(mid)) >= draft.target { lowF = mid } else { highF = mid }
                }
                level = scaled(lowF)
            } else {
                // The fewest moves at which the bot wins as often as the draft asks.
                var low = 12, high = 60
                while low < high {
                    let mid = (low + high) / 2
                    var l = level
                    l.moves = mid
                    if rate(l) >= draft.target { high = mid } else { low = mid + 1 }
                }
                level.moves = low
            }
            let low = level.moves
            let results = Self.play(level, moves: low)
            let scores = results.filter(\.won).map(\.score).sorted()
            func percentile(_ p: Double) -> Int {
                guard !scores.isEmpty else { return 0 }
                return scores[min(scores.count - 1, Int(Double(scores.count) * p))]
            }
            // Round to tens so the targets read cleanly.
            level.stars = [percentile(0.5) / 10 * 10, percentile(0.85) / 10 * 10]
            let won = Double(results.filter(\.won).count) / Double(Self.games)
            print(String(format: "MATCH %2d %@: %d moves, %@, bot wins %.0f%%, stars %d / %d (%.0fs)", id, level.title, level.moves,
                         level.goals.joined(separator: " "), won * 100, level.stars[0], level.stars[1], Date().timeIntervalSince(start)))
            levels.append(level)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(MatchLevelsFile(version: 1, levels: levels)).write(to: Self.contentURL)
    }
}
