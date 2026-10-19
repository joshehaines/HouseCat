import Foundation
import HouseCatCore

/// The Games menu's side of the save (CLAUDE.md "The Games menu"): its content, today's state, the seed for a
/// game, and a finished game or puzzle as its event, with what it paid.
extension GameSession {
    /// The Games menu's words, cats and levels (Content/arcade.json, match_levels.json, catapult_levels.json).
    static let arcadeContent: ArcadeContent? = Bundle.main.url(forResource: "Content", withExtension: nil)
        .flatMap { try? ArcadeContent.load(from: $0) }

    /// What a game or the puzzle paid, for its card: the Beans and XP that reached the save (Cat Club's bonus in),
    /// the rule's account of it, the cat's line.
    struct ArcadeReward {
        var beans: Int
        var xp: Int
        var payout: ArcadePayout
        var line: String?
        /// A level reached on the way (its own card comes up in the room).
        var levelUp: Bool
    }

    var arcadeDay: GameDay {
        let date = now()
        return state(at: date).clock.day(of: date)
    }

    var arcade: ArcadeState {
        state(at: now()).arcade
    }

    /// Today's challenges with their words and how far along each is.
    var arcadeChallenges: [(challenge: ArcadeChallenge, text: String, progress: Int, done: Bool)] {
        let date = now()
        let state = state(at: date)
        let day = state.clock.day(of: date)
        let words = Self.arcadeContent?.file.challenges ?? [:]
        return ArcadeChallenges.today(on: day, seed: state.seed).map { challenge in
            let progress = state.arcade.progress(challenge, on: day)
            return (challenge, words[challenge.id] ?? challenge.id, min(progress, challenge.target),
                    state.arcade.challengesPaid.contains(challenge.id) && state.arcade.day == day)
        }
    }

    /// The seed for one game: the household's, today, the game, how many of it were played today.
    func arcadeSeed(_ game: ArcadeGame) -> DaySeed {
        let date = now()
        let state = state(at: date)
        let day = state.clock.day(of: date)
        let played = state.arcade.day == day ? state.arcade.plays[game.rawValue, default: 0] : 0
        return DaySeed(household: state.seed, day: day, purpose: "arcade.\(game.rawValue)", salt: "\(played).\(log.events.count)")
    }

    /// A finished game from the Games menu.
    func finishArcade(_ result: ArcadeResult) -> ArcadeReward {
        Analytics.track(.gamePlayed, detail: "arcade.\(result.game.rawValue)")
        return record(.arcadePlayed(result)) { state, day in
            var arcade = state.arcade
            return arcade.record(result, on: day, seed: state.seed)
        } line: { payout in
            result.won || result.stars > 0 || payout.newStars > 0 ? "play.win" : "play.lose"
        }
    }

    /// Today's puzzle solved.
    func solvePuzzle(_ solve: PuzzleSolve) -> ArcadeReward {
        Analytics.track(.gamePlayed, detail: "arcade.puzzle")
        return record(.puzzleSolved(solve)) { state, day in
            var arcade = state.arcade
            return arcade.record(solve, on: day)
        } line: { _ in "play.win" }
    }

    private func record(
        _ kind: GameEvent.Kind,
        payout: (HouseholdState, GameDay) -> ArcadePayout,
        line: (ArcadePayout) -> String
    ) -> ArcadeReward {
        let date = now()
        let before = state(at: date)
        let account = payout(before, before.clock.day(of: date))
        append(kind, at: date)
        let after = state(at: now())
        return ArcadeReward(
            beans: after.beans - before.beans,
            xp: after.xp - before.xp,
            payout: account,
            line: self.line(line(account)),
            levelUp: after.level > before.level
        )
    }
}
