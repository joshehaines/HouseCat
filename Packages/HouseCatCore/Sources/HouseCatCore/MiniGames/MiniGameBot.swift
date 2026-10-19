import Foundation

/// A steady player for each game: the debug runs' autoplay (`HOUSECAT_AUTOPLAY`) and the tests that set the stars
/// play the games with it, so what the screen recordings show is what the thresholds were set against.
public enum MiniGameBot {
    /// Laser Pointer: the dot a little ahead of the cat, led round the room (to the catnip while it shows), and
    /// held still from the crouch until the cat is off again.
    public static func laser(_ game: LaserChase) -> GamePoint {
        guard game.phase == .chasing else { return game.dot }
        let w = Tuning.MiniGames.arenaWidth, h = Tuning.MiniGames.arenaHeight
        let t = game.elapsed
        var goal = GamePoint(x: w / 2 + w * 0.32 * cos(t * 0.55), y: h / 2 + h * 0.3 * sin(t * 0.55))
        if game.catnip.showing(t) {
            goal = game.catnip.at
        }
        let ahead = 1.6
        let gap = game.cat.distance(to: goal)
        guard gap > 0.01 else { return goal }
        return GamePoint(x: game.cat.x + (goal.x - game.cat.x) / gap * ahead, y: game.cat.y + (goal.y - game.cat.y) / gap * ahead).clamped
    }

    /// Knock It Off: a tap when something is close in front of the cat.
    public static func knock(_ game: KnockItOff) -> Bool {
        guard game.resting == 0, let thing = game.inReach else { return false }
        return abs(thing.at - game.paw) <= game.reach * 0.6
    }

    /// String Chase: once the cat has run the last string, a new one to the best sparkle (catnip, then golden,
    /// then the nearest); nil while it is still running.
    public static func string(_ game: StringChase) -> [GamePoint]? {
        guard game.string.isEmpty, !game.sparkles.isEmpty else { return nil }
        func worth(_ sparkle: StringChase.Sparkle) -> Double {
            let bonus = switch sparkle.kind {
            case .catnip: 3.0
            case .golden: 5.0
            case .plain: 0.0
            }
            return game.cat.distance(to: sparkle.at) - bonus
        }
        guard let next = game.sparkles.min(by: { worth($0) < worth($1) }) else { return nil }
        return [next.at]
    }

    /// Hide and Seek: the catnip while it lies out, then the cat's place a moment after it peeks (as quick as a person
    /// sees it); nil to wait. -1 is the catnip.
    public static func hide(_ game: HideAndSeek) -> Int? {
        guard game.phase == .seeking, game.resting == 0 else { return nil }
        if game.catnip.showing(game.elapsed), !game.hasZoomies {
            return -1
        }
        return game.peeking && (game.peekedFor >= 0.2 || game.hasZoomies) ? game.spot : nil
    }
}
