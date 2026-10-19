import Foundation

/// A point on a mini-game's floor, in cells (the arena is `Tuning.MiniGames.arenaWidth` by `arenaHeight`,
/// origin bottom left).
public struct GamePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: GamePoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }

    /// The point `length` cells from here towards `target` (or the target, if nearer).
    public func moved(towards target: GamePoint, by length: Double) -> GamePoint {
        let gap = distance(to: target)
        guard gap > length, gap > 0 else { return target }
        return GamePoint(x: x + (target.x - x) / gap * length, y: y + (target.y - y) / gap * length)
    }

    /// Kept inside the arena.
    public var clamped: GamePoint {
        GamePoint(x: min(max(x, 0), Tuning.MiniGames.arenaWidth), y: min(max(y, 0), Tuning.MiniGames.arenaHeight))
    }
}

/// The mini-games' shared rules (SPEC "Mini-games", CONTENT.md §6): stars from the score against the game's
/// thresholds, five plays a day (the reducer pays them: `miniGamePlayed`), and the cat's speed by personality,
/// which changes how a game feels but never its thresholds.
public enum MiniGameRules {
    public static func stars(score: Double, thresholds: [Int]) -> Int {
        thresholds.filter { score >= Double($0) }.count
    }

    /// Plays left today (the state resolved through today).
    public static func playsLeft(_ state: HouseholdState) -> Int {
        max(0, Tuning.MiniGames.playsPerDay - (state.today?.plays ?? 0))
    }

    /// How fast the cat chases, in cells a second.
    public static func chaseSpeed(_ personality: Personality) -> Double {
        Tuning.MiniGames.chaseSpeed[personality.rawValue] ?? 3.2
    }

    /// The line after a game: a win with any star, otherwise the gentle loss (never an upset cat).
    public static func endLine(stars: Int) -> String {
        stars > 0 ? "play.win" : "play.lose"
    }

    /// How far into the game's ramp `elapsed` is, 0 at the start and 1 at the end.
    static func ramp(_ elapsed: Double, of duration: Double) -> Double {
        duration > 0 ? min(1, max(0, elapsed / duration)) : 1
    }

    /// From `values[0]` at the start of the game to `values[1]` at its end.
    static func along(_ values: [Double], _ elapsed: Double, of duration: Double) -> Double {
        let t = ramp(elapsed, of: duration)
        return values[0] + (values[values.count - 1] - values[0]) * t
    }

    /// Seconds into a game, between `low` and `high`, from the game's seed.
    static func moment(_ low: Double, _ high: Double, seed: inout DaySeed) -> Double {
        low + Double(seed.below(1000)) / 1000 * (high - low)
    }

    /// A spot on the floor at least `margin` cells in from its edges.
    static func spot(margin: Double, seed: inout DaySeed) -> GamePoint {
        let w = Tuning.MiniGames.arenaWidth, h = Tuning.MiniGames.arenaHeight
        return GamePoint(
            x: margin + Double(seed.below(1000)) / 1000 * (w - 2 * margin),
            y: margin + Double(seed.below(1000)) / 1000 * (h - 2 * margin)
        )
    }
}

/// Hits in a row (every game): a hit scores 1, and 1 more for every `Tuning.MiniGames.comboStep` hits in a row before
/// it, up to `comboCap`; a miss, or `comboSeconds` without a hit, starts it again.
public struct Combo: Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var best = 0
    private var since = 0.0

    public init() {}

    /// What a hit is worth (before golden or zoomies) as the `count`th in a row.
    public static func worth(_ count: Int) -> Int {
        min(1 + max(0, count - 1) / Tuning.MiniGames.comboStep, Tuning.MiniGames.comboCap)
    }

    /// What the combo is worth now: the multiplier the last hit scored at.
    public var multiplier: Int {
        Self.worth(max(count, 1))
    }

    /// A hit: the points it scores before golden or zoomies.
    public mutating func hit() -> Int {
        count += 1
        best = max(best, count)
        since = 0
        return Self.worth(count)
    }

    /// A miss. Returns whether there was a combo to lose.
    @discardableResult
    public mutating func breakOff() -> Bool {
        defer { count = 0 }
        return count > 1
    }

    /// Time passes; returns whether the combo lapsed just now.
    public mutating func tick(_ dt: Double) -> Bool {
        guard count > 0 else { return false }
        since += dt
        guard since >= Tuning.MiniGames.comboSeconds else { return false }
        return breakOff()
    }
}

/// What happened in a game's step, for the scene to make something of (a burst, a shake, a sound, the cat's
/// reaction). The game model keeps the score; beats only say what changed.
public enum PlayBeat: Equatable, Sendable {
    /// Points scored.
    case scored(Hit)
    /// A try that came to nothing (a pounce that landed short, a swipe at thin air). `lost` when a combo went with it.
    case missed(at: GamePoint, lost: Bool)
    /// A combo ran out of time.
    case comboLapsed
    /// The catnip: the zoomies start, and end.
    case zoomies(at: GamePoint)
    case zoomiesOver
    /// Laser Pointer: the cat crouches, then springs at a spot.
    case crouched
    case sprang(to: GamePoint)
    /// A golden target is out (Laser Pointer: the dot itself; Hide and Seek: a golden round).
    case goldenAppeared
    /// Hide and Seek: the cat has hidden (a new round), peeks out from its place, a decoy place rustles, and the cat
    /// comes out by itself, unfound.
    case hid
    case peeked(place: Int)
    case rustled(place: Int)
    case cameOut(place: Int)
}

/// A hit's points, where (on the floor; Knock It Off: `x` along the shelf), the combo it made, and what was in it.
public struct Hit: Equatable, Sendable {
    public let points: Int
    public let combo: Int
    public let at: GamePoint
    public var golden = false
    public var zoomies = false
    /// Laser Pointer: the pounce landed right on the dot; Hide and Seek: the cat found quickly.
    public var perfect = false
}

/// The catnip in a game: where it lies and when, once a game; the cat's zoomies once it gets there.
public struct Catnip: Equatable, Sendable {
    public let at: GamePoint
    public let from: Double
    public let until: Double
    public private(set) var taken = false

    init(at: GamePoint, from: Double, until: Double) {
        self.at = at
        self.from = from
        self.until = until
    }

    /// Out on the floor at `elapsed`.
    public func showing(_ elapsed: Double) -> Bool {
        !taken && elapsed >= from && elapsed < until
    }

    /// Taken if the cat is within reach while it shows.
    mutating func take(by cat: GamePoint, at elapsed: Double) -> Bool {
        guard showing(elapsed), cat.distance(to: at) <= Tuning.MiniGames.sparkleReach + 0.1 else { return false }
        taken = true
        return true
    }
}

/// The nap (SPEC "Care": a 20-minute wind-down timer as a Live Activity; complete it for XP). The reducer pays
/// `napCompleted` once a day; waking the cat early pays nothing.
public enum NapRules {
    public static func end(of start: Date) -> Date {
        start.addingTimeInterval(Tuning.Nap.minutes * 60)
    }

    public static func isComplete(startedAt start: Date, at date: Date) -> Bool {
        date >= end(of: start)
    }

    /// Whether today's nap would still pay (the state resolved through today).
    public static func pays(_ state: HouseholdState) -> Bool {
        state.today?.napped == false
    }
}
