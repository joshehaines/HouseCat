import Foundation
@testable import HouseCatCore
import Testing

/// Finds a solution for each designed Catapult level and writes Content/catapult_levels.json. Off unless asked:
/// HOUSECAT_CATAPULT_SEARCH=1 swift test -c release --filter CatapultLevelSearch (HOUSECAT_CATAPULT_LEVELS=0-9 for some).
@Suite("Catapult level search")
struct CatapultLevelSearch {
    static let contentURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Content/catapult_levels.json")

    static let angles = stride(from: 5.0, through: 72.5, by: 2.5).map { $0 }
    static let powers = stride(from: 0.25, through: 1.0, by: 0.05).map { $0 }

    /// What a shot does from a game: the game after it.
    static func after(_ game: CatapultGame, _ shot: CatapultLevel.Shot) -> CatapultGame {
        var next = game
        next.playOut(angle: shot.angle, power: shot.power)
        return next
    }

    /// Of 8 shots close to `shot` (a degree and a half and 3% either way), how many still win from `game` in the
    /// shots left (the rest of `rest` played as found).
    static func robustness(_ game: CatapultGame, _ shot: CatapultLevel.Shot, rest: [CatapultLevel.Shot]) -> Int {
        var wins = 0
        for da in [-1.5, 0, 1.5] {
            for dp in [-0.03, 0, 0.03] where da != 0 || dp != 0 {
                var g = after(game, CatapultLevel.Shot(angle: shot.angle + da, power: min(1, shot.power + dp)))
                for later in rest { g.playOut(angle: later.angle, power: later.power) }
                if g.won { wins += 1 }
            }
        }
        return wins
    }

    /// Up to `depth` shots that knock every mouse off, the sturdiest found.
    static func solve(_ game: CatapultGame, depth: Int) -> [CatapultLevel.Shot]? {
        var tried: [(CatapultLevel.Shot, CatapultGame)] = []
        for angle in angles {
            for power in powers {
                let shot = CatapultLevel.Shot(angle: angle, power: power)
                tried.append((shot, after(game, shot)))
            }
        }
        let winners = tried.filter { $0.1.won }
        if game.used == 0 {
            let knockedAny = tried.filter { $0.1.knocked.count > 0 }.count
            print(String(format: "  first shot: %.1f%% win, %.1f%% knock a mouse", 100 * Double(winners.count) / Double(tried.count),
                         100 * Double(knockedAny) / Double(tried.count)))
        }
        if !winners.isEmpty {
            // The sturdiest of the winning shots (sampled, nearest the middle of the winning patch).
            let sample = stride(from: 0, to: winners.count, by: max(1, winners.count / 12)).map { winners[$0] }
            let best = sample.max { robustness(game, $0.0, rest: []) < robustness(game, $1.0, rest: []) }!
            return [best.0]
        }
        guard depth > 1 else { return nil }
        // Shots that knock the most, then the rest from there.
        let progress = tried.filter { $0.1.knocked.count > game.knocked.count }
            .sorted { $0.1.knocked.count > $1.1.knocked.count }
        var seen = Set<Int>()
        for (shot, next) in progress where seen.count < 4 {
            let key = next.knocked.count * 1000 + Int(shot.angle) / 10 * 10 + Int(shot.power * 10)
            guard seen.insert(key).inserted else { continue }
            if let rest = solve(next, depth: depth - 1) {
                return [shot] + rest
            }
        }
        return nil
    }

    @Test func findSolutions() throws {
        guard ProcessInfo.processInfo.environment["HOUSECAT_CATAPULT_SEARCH"] == "1" else { return }
        var levels = CatapultDesigns.drafts
        var range = 0 ..< levels.count
        if let only = ProcessInfo.processInfo.environment["HOUSECAT_CATAPULT_LEVELS"] {
            let parts = only.split(separator: "-").compactMap { Int($0) }
            range = parts[0] ..< (parts.count > 1 ? parts[1] + 1 : parts[0] + 1)
        }
        // Keep solutions already found for levels outside the range.
        if let data = try? Data(contentsOf: Self.contentURL),
           let old = try? JSONDecoder().decode(CatapultLevelsFile.self, from: data) {
            for level in old.levels where level.id < levels.count && !range.contains(level.id) && levels[level.id] == {
                var l = level
                l.solution = []
                return l
            }() {
                levels[level.id].solution = level.solution
            }
        }
        for id in range {
            let start = Date()
            var stand = CatapultGame(level: levels[id])
            let fell = stand.stand(5).contains { if case .knocked = $0 { true } else { false } }
            let solution = Self.solve(CatapultGame(level: levels[id]), depth: levels[id].par)
            levels[id].solution = solution ?? []
            print(String(format: "CATAPULT %2d %@ %@: %@ %@ (%.0fs)", id, levels[id].place.rawValue, levels[id].title,
                         solution.map { $0.map { String(format: "%.1f°/%.2f", $0.angle, $0.power) }.joined(separator: ", ") } ?? "NO SOLUTION",
                         fell ? "FELL WHILE STANDING" : "", Date().timeIntervalSince(start)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(CatapultLevelsFile(version: 1, levels: levels))
        try data.write(to: Self.contentURL)
    }
}
