import Foundation

/// String Chase (CONTENT.md §6): draw a string with one finger and the cat runs along it. Sparkles keep appearing
/// about the floor, a few at a time, each for a few seconds before it fades (sooner as the game goes on); run the
/// cat through them and each one scores the combo, so chain them quickly. Two golden sparkles a game, and once a
/// catnip fish: the zoomies, a faster cat. A new string starts from wherever the finger goes down; the cat runs to
/// it first.
public struct StringChase: Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        case golden
        case catnip
    }

    public struct Sparkle: Equatable, Sendable {
        public let id: Int
        public let at: GamePoint
        public let kind: Kind
        public let born: Double
        public let life: Double

        /// How much of its life is left, 1 new to 0 gone.
        public func left(at elapsed: Double) -> Double {
            max(0, 1 - (elapsed - born) / life)
        }
    }

    /// What is out on the floor now.
    public private(set) var sparkles: [Sparkle] = []
    public private(set) var cat: GamePoint
    public private(set) var string: [GamePoint] = []
    public private(set) var elapsed = 0.0
    public private(set) var points = 0
    public private(set) var gathered = 0
    public private(set) var combo = Combo()
    public private(set) var zoomiesLeft = 0.0
    public let duration: Double
    public let speed: Double
    private var seed: DaySeed
    private var nextID = 0
    private var arrivals = 0
    /// Seconds until the next sparkle may come (one comes a moment after another goes).
    private var gap = 0.0
    private let goldenArrivals: Set<Int>
    private let catnipArrival: Int

    /// The sparkles are laid out by the play's seed, so a replay of the same play is the same game.
    public init(duration: Double, personality: Personality, seed: inout DaySeed) {
        self.duration = duration
        let average = Tuning.MiniGames.chaseSpeed.values.reduce(0, +) / Double(Tuning.MiniGames.chaseSpeed.count)
        speed = average + (MiniGameRules.chaseSpeed(personality) - average) * Tuning.MiniGames.stringSpeedShare
        cat = GamePoint(x: Tuning.MiniGames.arenaWidth / 2, y: Tuning.MiniGames.arenaHeight * 0.2)
        goldenArrivals = [5 + seed.below(3), 11 + seed.below(4)]
        catnipArrival = 4 + seed.below(3)
        self.seed = seed
        for _ in 0 ..< Tuning.MiniGames.sparklesAtOnce {
            arrive()
        }
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

    /// How fast the cat runs along the string now.
    public var currentSpeed: Double {
        speed * (1 + Tuning.MiniGames.rampShare * MiniGameRules.ramp(elapsed, of: duration)) * (hasZoomies ? 1.5 : 1)
    }

    /// A new string (the finger's path, oldest point first).
    public mutating func draw(_ path: [GamePoint]) {
        string = path.map(\.clamped)
    }

    /// The finger keeps drawing: the string grows at its end.
    public mutating func extend(_ point: GamePoint) {
        string.append(point.clamped)
    }

    @discardableResult
    public mutating func step(_ dt: Double) -> [PlayBeat] {
        guard !isOver else { return [] }
        let dt = min(dt, duration - elapsed)
        elapsed += dt
        var beats: [PlayBeat] = []
        var budget = currentSpeed * dt
        // Along the string from its start, dropping each point the cat reaches.
        while budget > 0, let next = string.first {
            let gap = cat.distance(to: next)
            if gap <= budget {
                cat = next
                budget -= gap
                string.removeFirst()
            } else {
                cat = cat.moved(towards: next, by: budget)
                budget = 0
            }
            beats += collect()
        }
        beats += collect()
        // Faded sparkles go; new ones come a moment after.
        let before = sparkles.count
        sparkles.removeAll { $0.left(at: elapsed) <= 0 }
        if sparkles.count < before {
            gap = max(gap, Tuning.MiniGames.sparkleGap)
        }
        gap -= dt
        if gap <= 0, sparkles.count < Tuning.MiniGames.sparklesAtOnce {
            arrive()
            gap = Tuning.MiniGames.sparkleGap
        }
        if zoomiesLeft > 0, !beats.contains(where: { if case .zoomies = $0 { true } else { false } }) {
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

    private mutating func collect() -> [PlayBeat] {
        var beats: [PlayBeat] = []
        for sparkle in sparkles where cat.distance(to: sparkle.at) <= Tuning.MiniGames.sparkleReach {
            sparkles.removeAll { $0.id == sparkle.id }
            gap = max(gap, Tuning.MiniGames.sparkleGap)
            if sparkle.kind == .catnip {
                zoomiesLeft = Tuning.MiniGames.zoomiesSeconds
                beats.append(.zoomies(at: sparkle.at))
                continue
            }
            gathered += 1
            var scored = combo.hit()
            if sparkle.kind == .golden {
                scored *= Tuning.MiniGames.goldenTimes
            }
            if hasZoomies {
                scored *= Tuning.MiniGames.zoomiesTimes
            }
            points += scored
            beats.append(.scored(Hit(points: scored, combo: combo.count, at: sparkle.at, golden: sparkle.kind == .golden, zoomies: hasZoomies)))
        }
        return beats
    }

    /// A new sparkle a run away from the cat, clear of the others.
    private mutating func arrive() {
        let spacing = Tuning.MiniGames.sparkleSpacing
        func fits(_ point: GamePoint) -> Bool {
            let run = point.distance(to: cat)
            return run >= spacing[0] && run <= spacing[1] && !sparkles.contains { $0.at.distance(to: point) < 2 }
        }
        var point = MiniGameRules.spot(margin: 1, seed: &seed)
        for _ in 0 ..< 24 where !fits(point) {
            point = MiniGameRules.spot(margin: 1, seed: &seed)
        }
        arrivals += 1
        let kind: Kind = arrivals == catnipArrival ? .catnip : goldenArrivals.contains(arrivals) ? .golden : .plain
        let life = MiniGameRules.along(Tuning.MiniGames.sparkleLife, elapsed, of: duration) * (kind == .plain ? 1 : 0.8)
        sparkles.append(Sparkle(id: nextID, at: point, kind: kind, born: elapsed, life: life))
        nextID += 1
    }
}
