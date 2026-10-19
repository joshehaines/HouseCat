import Foundation

/// Laser Pointer (CONTENT.md §6): drag the dot and the cat chases it, steering with some weight; once it has
/// chased a moment and is close, it crouches and pounces at the dot. Keep the dot still while it is in the air and
/// it lands on it: a catch, scoring the combo (twice over when it lands right on it). A dot left still bores it, as it would a cat; flick the dot away
/// mid-pounce and it lands on nothing. Twice a game the dot turns golden, and a catnip fish on the floor gives the
/// cat the zoomies. The cat is a little quicker by the end.
public struct LaserChase: Sendable {
    public enum Phase: Equatable, Sendable {
        case chasing
        case crouching
        case leaping
        /// On its catch (or where it missed), a moment before it is off again.
        case landed
    }

    public private(set) var cat: GamePoint
    public private(set) var velocity = GamePoint(x: 0, y: 0)
    public private(set) var dot: GamePoint
    public private(set) var elapsed = 0.0
    public private(set) var phase = Phase.chasing
    /// Seconds into the phase.
    public private(set) var phaseTime = 0.0
    /// Seconds of chase since the last pounce.
    public private(set) var stalk = 0.0
    public private(set) var leapFrom = GamePoint(x: 0, y: 0)
    public private(set) var leapTo = GamePoint(x: 0, y: 0)
    public private(set) var points = 0
    public private(set) var catches = 0
    public private(set) var combo = Combo()
    /// How long the dot has been still.
    public private(set) var stillFor = 0.0
    /// When the dot is golden: [from, until) twice a game.
    public let golden: [ClosedRange<Double>]
    public private(set) var catnip: Catnip
    public private(set) var zoomiesLeft = 0.0
    public let duration: Double
    public let speed: Double

    /// The catnip and the golden dot fall at moments set by the play's seed.
    public init(duration: Double, personality: Personality, seed: inout DaySeed) {
        self.duration = duration
        speed = MiniGameRules.chaseSpeed(personality)
        let w = Tuning.MiniGames.arenaWidth, h = Tuning.MiniGames.arenaHeight
        cat = GamePoint(x: w * 0.3, y: h * 0.4)
        dot = GamePoint(x: w * 0.6, y: h * 0.5)
        let gold = Tuning.MiniGames.goldenSeconds
        let first = MiniGameRules.moment(duration * 0.25, duration * 0.4, seed: &seed)
        let second = MiniGameRules.moment(duration * 0.6, duration * 0.95 - gold, seed: &seed)
        golden = [first ... first + gold, second ... second + gold]
        var spot = MiniGameRules.spot(margin: 1.2, seed: &seed)
        for _ in 0 ..< 8 where spot.distance(to: cat) < 3 {
            spot = MiniGameRules.spot(margin: 1.2, seed: &seed)
        }
        let shows = MiniGameRules.moment(duration * 0.15, duration * 0.3, seed: &seed)
        catnip = Catnip(at: spot, from: shows, until: shows + duration * 0.35)
    }

    public var isOver: Bool {
        elapsed >= duration
    }

    public var score: Double {
        Double(points)
    }

    /// Whether the cat is after the dot (a still dot bores it).
    public var interested: Bool {
        stillFor < Tuning.MiniGames.laserBoredSeconds
    }

    public var isGolden: Bool {
        golden.contains { $0.contains(elapsed) }
    }

    public var hasZoomies: Bool {
        zoomiesLeft > 0
    }

    /// How fast the cat runs now: its personality's chase, quicker as the game goes on and with the zoomies.
    public var currentSpeed: Double {
        speed * (1 + Tuning.MiniGames.rampShare * MiniGameRules.ramp(elapsed, of: duration)) * (hasZoomies ? 1.35 : 1)
    }

    /// How near the landing the dot must be for a catch: a little less with each catch in the combo.
    public var catchReach: Double {
        Tuning.MiniGames.catchReach - Tuning.MiniGames.catchReachPerCombo * Double(min(combo.count, 4))
    }

    /// Moves the dot (the finger) and the cat on by `dt` seconds; what happened, for the scene.
    @discardableResult
    public mutating func step(_ dt: Double, dot newDot: GamePoint? = nil) -> [PlayBeat] {
        guard !isOver else { return [] }
        let dt = min(dt, duration - elapsed)
        var beats: [PlayBeat] = []
        let wasGolden = isGolden
        if let newDot {
            // Moving if it goes faster than a crawl.
            let moved = newDot.clamped.distance(to: dot)
            stillFor = moved / max(dt, 0.001) > Tuning.MiniGames.laserMovingSpeed ? 0 : stillFor + dt
            dot = newDot.clamped
        } else {
            stillFor += dt
        }
        phaseTime += dt
        let t = Tuning.MiniGames.self
        switch phase {
        case .chasing:
            chase(dt)
            if interested, (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() > 0.6 {
                stalk += dt
            }
            if interested, stalk >= t.stalkSeconds, cat.distance(to: dot) <= t.pounceRange + (hasZoomies ? 0.4 : 0) {
                enter(.crouching)
                velocity = GamePoint(x: 0, y: 0)
                beats.append(.crouched)
            }
        case .crouching:
            // It keeps its eyes on the dot, and springs at where it is when the crouch ends.
            if phaseTime >= t.crouchSeconds {
                leapFrom = cat
                leapTo = cat.moved(towards: dot, by: t.leapCells).clamped
                enter(.leaping)
                beats.append(.sprang(to: leapTo))
            }
        case .leaping:
            let u = min(1, phaseTime / t.leapSeconds)
            cat = GamePoint(x: leapFrom.x + (leapTo.x - leapFrom.x) * u, y: leapFrom.y + (leapTo.y - leapFrom.y) * u)
            if u >= 1 {
                beats.append(land())
                enter(.landed)
            }
        case .landed:
            if phaseTime >= t.landSeconds {
                enter(.chasing)
                stalk = 0
            }
        }
        if catnip.take(by: cat, at: elapsed) {
            zoomiesLeft = t.zoomiesSeconds
            beats.append(.zoomies(at: catnip.at))
        } else if zoomiesLeft > 0 {
            zoomiesLeft -= dt
            if zoomiesLeft <= 0 {
                zoomiesLeft = 0
                beats.append(.zoomiesOver)
            }
        }
        if combo.tick(dt) {
            beats.append(.comboLapsed)
        }
        elapsed += dt
        if isGolden, !wasGolden {
            beats.append(.goldenAppeared)
        }
        return beats
    }

    private mutating func enter(_ next: Phase) {
        phase = next
        phaseTime = 0
    }

    /// Steering towards the dot with a little inertia: it takes a moment to turn and a fast zigzag loses it.
    private mutating func chase(_ dt: Double) {
        var target = GamePoint(x: 0, y: 0)
        if interested {
            let gap = cat.distance(to: dot)
            if gap > 0.15 {
                let speed = currentSpeed
                target = GamePoint(x: (dot.x - cat.x) / gap * speed, y: (dot.y - cat.y) / gap * speed)
            }
        }
        let grip = min(1, Tuning.MiniGames.laserGrip * dt)
        velocity = GamePoint(x: velocity.x + (target.x - velocity.x) * grip, y: velocity.y + (target.y - velocity.y) * grip)
        cat = GamePoint(x: cat.x + velocity.x * dt, y: cat.y + velocity.y * dt).clamped
    }

    /// The landing: the dot under its paws, or nothing.
    private mutating func land() -> PlayBeat {
        guard interested, dot.distance(to: leapTo) <= catchReach else {
            return .missed(at: leapTo, lost: combo.breakOff())
        }
        let golden = isGolden
        let perfect = dot.distance(to: leapTo) <= Tuning.MiniGames.perfectReach
        var scored = combo.hit()
        if perfect {
            scored *= Tuning.MiniGames.perfectTimes
        }
        if golden {
            scored *= Tuning.MiniGames.goldenTimes
        }
        if hasZoomies {
            scored *= Tuning.MiniGames.zoomiesTimes
        }
        points += scored
        catches += 1
        return .scored(Hit(points: scored, combo: combo.count, at: leapTo, golden: golden, zoomies: hasZoomies, perfect: perfect))
    }
}
