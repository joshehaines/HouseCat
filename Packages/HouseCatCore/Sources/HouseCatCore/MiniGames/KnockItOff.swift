import Foundation

/// Knock It Off (CONTENT.md §6): the cat walks the length of the mantel and back, and a tap swipes off whatever is in
/// front of it. Things keep arriving (quicker as the game goes on) up to a full shelf; each hit in a row scores the
/// combo and quickens the cat a little; a swipe at nothing breaks the combo and the cat stops a moment to look at
/// you. Now and then a golden thing, and once a catnip fish: knock it off for the zoomies, a longer reach.
public struct KnockItOff: Sendable {
    public enum Kind: Equatable, Sendable {
        /// One of the shelf's things (an index into the pictures).
        case plain(Int)
        case golden(Int)
        case catnip
    }

    public struct Thing: Equatable, Sendable {
        public let id: Int
        /// Its place along the shelf, 0 to 1 (a slot's middle).
        public let at: Double
        public let kind: Kind
        public let arrived: Double
    }

    /// What stands on the shelf now.
    public private(set) var things: [Thing] = []
    /// The cat (its nose, which is what swipes) along the shelf, 0 to 1, and the way it is walking.
    public private(set) var paw = 0.05
    public private(set) var direction = 1.0
    public private(set) var elapsed = 0.0
    public private(set) var points = 0
    public private(set) var knocked = 0
    public private(set) var combo = Combo()
    /// After a miss the cat rests this long.
    public private(set) var resting = 0.0
    public private(set) var zoomiesLeft = 0.0
    /// How fast the cat crosses the shelf (a share of it a second), before the ramp.
    public private(set) var walk: Double
    public let duration: Double
    private var seed: DaySeed
    private var nextID = 0
    private var arrivals = 0
    private var untilNext = 0.0
    private let goldenArrivals: Set<Int>
    private let catnipArrival: Int

    public init(duration: Double, personality: Personality, seed: inout DaySeed) {
        self.duration = duration
        // The chase speed sets how fast the cat walks it (a gremlin bustles, a loaf ambles).
        walk = Tuning.MiniGames.walkShelf * MiniGameRules.chaseSpeed(personality) / 3.2
        let first = 4 + seed.below(3), second = 10 + seed.below(4)
        goldenArrivals = [first, second]
        catnipArrival = 6 + seed.below(3)
        self.seed = seed
        for _ in 0 ..< Tuning.MiniGames.shelfStart {
            arrive()
        }
        untilNext = Tuning.MiniGames.spawnSeconds[0]
    }

    public var isOver: Bool {
        elapsed >= duration
    }

    public var score: Double {
        Double(points)
    }

    public var hasZoomies: Bool {
        zoomiesLeft > 0
    }

    /// How near the cat must be to a thing to swipe it: further with the zoomies.
    public var reach: Double {
        Tuning.MiniGames.pawReach * (hasZoomies ? 1.8 : 1)
    }

    /// The cat's pace now, a share of the shelf a second.
    public var pace: Double {
        walk * (1 + Tuning.MiniGames.rampShare * MiniGameRules.ramp(elapsed, of: duration))
    }

    /// The slots' middles along the shelf.
    public static var slots: [Double] {
        let count = Tuning.MiniGames.shelfSlots
        return (0 ..< count).map { (Double($0) + 0.5) / Double(count) }
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [PlayBeat] {
        guard !isOver else { return [] }
        let dt = min(dt, duration - elapsed)
        var beats: [PlayBeat] = []
        elapsed += dt
        // A rest after a miss uses up the start of the step; the cat walks for what is left.
        let rest = min(resting, dt)
        resting -= rest
        let moving = dt - rest
        if moving > 0 {
            paw += direction * pace * moving
            let ends = (low: 0.03, high: 0.97)
            if paw >= ends.high {
                paw = 2 * ends.high - paw
                direction = -1
            } else if paw <= ends.low {
                paw = 2 * ends.low - paw
                direction = 1
            }
        }
        untilNext -= dt
        if untilNext <= 0 {
            arrive()
            untilNext += MiniGameRules.along(Tuning.MiniGames.spawnSeconds, elapsed, of: duration)
        }
        if zoomiesLeft > 0 {
            zoomiesLeft -= dt
            if zoomiesLeft <= 0 {
                zoomiesLeft = 0
                beats.append(.zoomiesOver)
            }
        }
        if combo.tick(dt) {
            beats.append(.comboLapsed)
        }
        return beats
    }

    /// The thing in front of the cat, if any: the nearest within reach.
    public var inReach: Thing? {
        things.filter { abs($0.at - paw) <= reach }.min { abs($0.at - paw) < abs($1.at - paw) }
    }

    /// A tap: the thing in front of the cat goes over the edge, or the combo breaks and it rests. The beats say which.
    @discardableResult
    public mutating func tap() -> [PlayBeat] {
        guard !isOver, resting == 0 else { return [] }
        guard let thing = inReach else {
            resting = Tuning.MiniGames.missRestSeconds
            return [.missed(at: GamePoint(x: paw, y: 0), lost: combo.breakOff())]
        }
        things.removeAll { $0.id == thing.id }
        knocked += 1
        var beats: [PlayBeat] = []
        var scored = combo.hit()
        var golden = false
        switch thing.kind {
        case .golden:
            golden = true
            scored *= Tuning.MiniGames.goldenTimes
        case .catnip:
            zoomiesLeft = Tuning.MiniGames.zoomiesSeconds
            beats.append(.zoomies(at: GamePoint(x: thing.at, y: 0)))
        case .plain:
            break
        }
        if hasZoomies {
            scored *= Tuning.MiniGames.zoomiesTimes
        }
        points += scored
        walk = min(walk * Tuning.MiniGames.pawSpeedUp, Tuning.MiniGames.walkShelf * Tuning.MiniGames.pawTopSpeed)
        beats.insert(.scored(Hit(points: scored, combo: combo.count, at: GamePoint(x: thing.at, y: 0), golden: golden, zoomies: hasZoomies)), at: 0)
        return beats
    }

    /// Something new on a free slot (not the one the cat is at), unless the shelf is full.
    private mutating func arrive() {
        let free = Self.slots.filter { slot in !things.contains { $0.at == slot } && abs(slot - paw) > reach * 1.5 }
        guard !free.isEmpty else { return }
        let at = free[seed.below(free.count)]
        arrivals += 1
        let picture = seed.below(Tuning.MiniGames.shelfThings.count)
        let kind: Kind = arrivals == catnipArrival ? .catnip : goldenArrivals.contains(arrivals) ? .golden(picture) : .plain(picture)
        things.append(Thing(id: nextID, at: at, kind: kind, arrived: elapsed))
        nextID += 1
    }
}
