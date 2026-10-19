import Foundation

/// Zoomies (the Games menu's runner): the cat gallops to the right along three lanes (0 at the back, 2 at the front)
/// through the house, the garden and down the street. Swipe up or down to change lane, tap to jump, hold to slide
/// under. Biscuits and toy mice to collect; catnip draws biscuits in, a cardboard box takes one bump. A bump ends the
/// run (the cat lands on its feet). The course is laid out from hand-made stretches (`ZoomiesCourse.stretches`),
/// picked by the run's seed, harder as the run goes on; every stretch is checked passable at full speed.
public enum ZoomiesThing: String, Codable, Sendable, CaseIterable {
    /// Jump over it (a pile of books, boots, a watering can, a hedgehog).
    case low
    /// Slide under it (a coffee table, an ironing board, a washing line).
    case high
    /// Change lane (a laundry basket, a wheelie bin, a bicycle).
    case block
    case biscuit
    case mouse
    case catnip
    case box

    public var isObstacle: Bool {
        self == .low || self == .high || self == .block
    }

    /// How long it is along the run, in metres.
    public var length: Double {
        switch self {
        case .low: Tuning.Arcade.Zoomies.lowLength
        case .high: Tuning.Arcade.Zoomies.highLength
        case .block: Tuning.Arcade.Zoomies.blockLength
        case .biscuit, .mouse, .catnip, .box: Tuning.Arcade.Zoomies.pickupLength
        }
    }
}

/// Something on the course: where it starts (metres from the start of the run) and its lane.
public struct ZoomiesItem: Equatable, Sendable, Identifiable {
    public let id: Int
    public let thing: ZoomiesThing
    public let at: Double
    public let lane: Int
}

/// A stretch of course, as hand-made: items at metres from its start; harder ones come later in a run.
public struct ZoomiesStretch: Sendable {
    public let name: String
    public let length: Double
    /// 1 (easy) to 3 (hard).
    public let tier: Int
    public let items: [(ZoomiesThing, Double, Int)]
}

public enum ZoomiesInput: Equatable, Sendable {
    case up, down, jump, slideStart, slideEnd
}

/// What happened in a step, for the scene.
public enum ZoomiesBeat: Equatable, Sendable {
    case collected(ZoomiesItem)
    case shieldUsed(ZoomiesItem)
    case bumped(ZoomiesItem)
    /// The run moved into the next part of the home (hall, kitchen, garden, street).
    case zone(Int)
}

public struct ZoomiesRun: Sendable {
    public private(set) var distance = 0.0
    public private(set) var speed = Tuning.Arcade.Zoomies.startSpeed
    public private(set) var elapsed = 0.0
    /// The lane the cat is in (or moving to) and how far through the move it is (1 when settled).
    public private(set) var lane = 1
    public private(set) var fromLane = 1
    public private(set) var laneProgress = 1.0
    /// Seconds into a jump (nil on the ground).
    public private(set) var jumpTime: Double?
    /// Seconds into a slide (nil when not sliding), and whether the finger is still down.
    public private(set) var slideTime: Double?
    private var holding = false
    public private(set) var biscuits = 0
    public private(set) var mice = 0
    /// Catnip: seconds of biscuits flying to the cat left.
    public private(set) var magnet = 0.0
    public private(set) var shield = false
    public private(set) var over = false
    public private(set) var zone = 0
    /// What is ahead, nearest first; collected things and things passed are dropped.
    public private(set) var items: [ZoomiesItem] = []
    private var laidTo = 0.0
    private var nextID = 0
    private var seed: DaySeed
    /// For checking stretches: these, in order, then nothing; and a speed held still.
    private var fixedCourse: [ZoomiesStretch]?
    private var fixedSpeed: Double?

    public init(seed: DaySeed) {
        self.seed = seed
        // A clear run-up before the first stretch.
        laidTo = Tuning.Arcade.Zoomies.runUp
        layCourse()
    }

    init(course: [ZoomiesStretch], speed: Double, lane: Int = 1) {
        seed = DaySeed(household: 0, day: GameDay(index: 0), purpose: "zoomies")
        fixedCourse = course
        fixedSpeed = speed
        self.speed = speed
        self.lane = lane
        fromLane = lane
        laidTo = Tuning.Arcade.Zoomies.runUp
        layCourse()
    }

    /// The far end of what has been laid (checking runs end there).
    var courseEnd: Double {
        laidTo
    }

    public var score: Int {
        Int(distance) + biscuits * Tuning.Arcade.Zoomies.biscuitPoints + mice * Tuning.Arcade.Zoomies.mousePoints
    }

    public var stars: Int {
        Tuning.Arcade.Zoomies.stars.filter { score >= $0 }.count
    }

    /// The lane the cat counts as in for bumps and pickups (it changes halfway through a move).
    public var effectiveLane: Int {
        laneProgress >= 0.5 ? lane : fromLane
    }

    /// Height off the ground in metres.
    public var height: Double {
        guard let t = jumpTime else { return 0 }
        let total = Tuning.Arcade.Zoomies.jumpSeconds
        return 4 * Tuning.Arcade.Zoomies.jumpHeight * t * (total - t) / (total * total)
    }

    public var isSliding: Bool {
        slideTime != nil
    }

    public mutating func input(_ input: ZoomiesInput) {
        guard !over else { return }
        switch input {
        case .up, .down:
            let target = lane + (input == .up ? -1 : 1)
            guard target >= 0, target < Tuning.Arcade.Zoomies.lanes else { return }
            fromLane = effectiveLane
            lane = target
            laneProgress = 0
        case .jump:
            guard jumpTime == nil else { return }
            slideTime = nil
            holding = false
            jumpTime = 0
        case .slideStart:
            holding = true
            if let t = jumpTime {
                // Pressed in the air: come down fast and slide on landing.
                jumpTime = max(t, Tuning.Arcade.Zoomies.jumpSeconds - Tuning.Arcade.Zoomies.dropSeconds)
            } else {
                slideTime = 0
            }
        case .slideEnd:
            holding = false
        }
    }

    /// Moves the run on by `dt` seconds.
    public mutating func step(_ dt: Double) -> [ZoomiesBeat] {
        guard !over, dt > 0 else { return [] }
        var beats: [ZoomiesBeat] = []
        let z = Tuning.Arcade.Zoomies.self
        elapsed += dt
        speed = fixedSpeed ?? min(z.topSpeed, z.startSpeed + z.speedGain * elapsed)
        distance += speed * dt
        laneProgress = min(1, laneProgress + dt / z.laneSeconds)
        if let t = jumpTime {
            let next = t + dt
            if next >= z.jumpSeconds {
                jumpTime = nil
                if holding { slideTime = 0 }
            } else {
                jumpTime = next
            }
        }
        if let t = slideTime {
            let next = t + dt
            if next >= z.slideLongest {
                // A long press ends the slide; the finger must lift and press again.
                slideTime = nil
                holding = false
            } else {
                slideTime = !holding && next >= z.slideShortest ? nil : next
            }
        }
        magnet = max(0, magnet - dt)
        let newZone = Int(distance / z.zoneLength)
        if newZone != zone {
            zone = newZone
            beats.append(.zone(zone))
        }
        // What the cat is touching.
        let front = distance + z.catHalfLength, back = distance - z.catHalfLength
        var keep: [ZoomiesItem] = []
        for item in items {
            if item.at + item.thing.length < back - 1 {
                continue
            }
            let overlaps = item.at < front && item.at + item.thing.length > back
            if item.thing.isObstacle {
                if overlaps, item.lane == effectiveLane, !clears(item.thing) {
                    if shield {
                        shield = false
                        beats.append(.shieldUsed(item))
                        continue
                    }
                    over = true
                    beats.append(.bumped(item))
                    keep.append(item)
                    continue
                }
                keep.append(item)
            } else {
                let reach = item.thing == .biscuit && magnet > 0 ? z.magnetReach : 0
                let near = item.at < front + reach && item.at + item.thing.length > back - reach
                let laneOK = item.lane == effectiveLane || (magnet > 0 && item.thing == .biscuit)
                if near, laneOK, item.thing == .mouse ? height < z.mouseHeight : true {
                    collect(item)
                    beats.append(.collected(item))
                } else {
                    keep.append(item)
                }
            }
        }
        items = keep
        layCourse()
        return beats
    }

    /// Whether the cat, as it is now, gets past an obstacle of this kind.
    func clears(_ thing: ZoomiesThing) -> Bool {
        switch thing {
        case .low: height >= Tuning.Arcade.Zoomies.clearHeight
        case .high: isSliding
        default: false
        }
    }

    private mutating func collect(_ item: ZoomiesItem) {
        switch item.thing {
        case .biscuit: biscuits += 1
        case .mouse: mice += 1
        case .catnip: magnet = Tuning.Arcade.Zoomies.magnetSeconds
        case .box: shield = true
        default: break
        }
    }

    /// Lays stretches ahead of the cat to `lookAhead` metres.
    private mutating func layCourse() {
        while laidTo < distance + Tuning.Arcade.Zoomies.lookAhead {
            let stretch: ZoomiesStretch
            if var fixed = fixedCourse {
                guard !fixed.isEmpty else { return }
                stretch = fixed.removeFirst()
                fixedCourse = fixed
            } else {
                stretch = ZoomiesCourse.pick(at: laidTo, seed: &seed)
            }
            for (thing, offset, lane) in stretch.items {
                items.append(ZoomiesItem(id: nextID, thing: thing, at: laidTo + offset, lane: lane))
                nextID += 1
            }
            laidTo += stretch.length
        }
        items.sort { $0.at < $1.at }
    }

    /// The stats a finished run records for the challenges.
    public var stats: [String: Int] {
        ["biscuits": biscuits, "mice": mice, "distance": Int(distance), "runs": 1]
    }
}

/// The hand-made stretches: each lays biscuits along the safe line and its things so that one lane at least is
/// always open, with time to get there at full speed (`ZoomiesTests` runs every stretch with a reflex player).
public enum ZoomiesCourse {
    static func biscuits(_ from: Double, _ to: Double, lane: Int, every gap: Double = 2) -> [(ZoomiesThing, Double, Int)] {
        stride(from: from, through: to, by: gap).map { (.biscuit, $0, lane) }
    }

    public static let stretches: [ZoomiesStretch] = [
        // Tier 1: one thing at a time.
        ZoomiesStretch(name: "biscuit trail", length: 30, tier: 1, items: biscuits(4, 26, lane: 1)),
        ZoomiesStretch(name: "books", length: 30, tier: 1, items: [(.low, 14, 1)] + biscuits(4, 10, lane: 1) + biscuits(18, 26, lane: 1)),
        ZoomiesStretch(name: "table", length: 30, tier: 1, items: [(.high, 14, 2)] + biscuits(6, 26, lane: 2)),
        ZoomiesStretch(name: "basket", length: 30, tier: 1, items: [(.block, 16, 1)] + biscuits(6, 26, lane: 0)),
        ZoomiesStretch(name: "step aside", length: 30, tier: 1, items: [(.block, 12, 0), (.block, 12, 2)] + biscuits(4, 26, lane: 1)),
        ZoomiesStretch(name: "mouse", length: 30, tier: 1, items: [(.mouse, 18, 0)] + biscuits(4, 12, lane: 0)),
        // Tier 2: two lanes shut, a jump and a slide.
        ZoomiesStretch(name: "hop and duck", length: 40, tier: 2,
                       items: [(.low, 10, 1), (.high, 26, 1)] + biscuits(2, 8, lane: 1) + biscuits(14, 22, lane: 1) + biscuits(30, 36, lane: 1)),
        ZoomiesStretch(name: "zigzag", length: 44, tier: 2,
                       items: [(.block, 10, 0), (.block, 10, 1), (.block, 26, 2), (.block, 26, 1)] + biscuits(4, 14, lane: 2)
                           + biscuits(18, 32, lane: 0)),
        ZoomiesStretch(name: "washing line", length: 40, tier: 2,
                       items: [(.high, 16, 0), (.high, 16, 1), (.high, 16, 2), (.mouse, 30, 1)] + biscuits(6, 26, lane: 1)),
        ZoomiesStretch(name: "boots in a row", length: 40, tier: 2,
                       items: [(.low, 12, 0), (.low, 12, 1), (.low, 12, 2), (.catnip, 24, 1)] + biscuits(20, 36, lane: 0)
                           + biscuits(20, 36, lane: 2)),
        ZoomiesStretch(name: "box", length: 36, tier: 2, items: [(.box, 10, 1), (.block, 22, 0), (.block, 22, 2)] + biscuits(14, 32, lane: 1)),
        ZoomiesStretch(name: "two mice", length: 40, tier: 2,
                       items: [(.mouse, 14, 0), (.block, 14, 1), (.mouse, 30, 2), (.low, 30, 1)] + biscuits(4, 10, lane: 1)),
        // Tier 3: things close together across lanes.
        ZoomiesStretch(name: "slalom", length: 56, tier: 3,
                       items: [(.block, 10, 1), (.block, 10, 2), (.block, 24, 0), (.block, 24, 1), (.block, 38, 1), (.block, 38, 2)]
                           + biscuits(4, 16, lane: 0) + biscuits(18, 30, lane: 2) + biscuits(32, 46, lane: 0)),
        ZoomiesStretch(name: "hurdles", length: 50, tier: 3,
                       items: [(.low, 10, 0), (.low, 10, 1), (.low, 10, 2), (.low, 24, 0), (.low, 24, 1), (.low, 24, 2),
                               (.high, 38, 0), (.high, 38, 1), (.high, 38, 2)] + biscuits(13, 21, lane: 1)),
        ZoomiesStretch(name: "jump or go round", length: 48, tier: 3,
                       items: [(.block, 12, 0), (.low, 12, 1), (.block, 12, 2), (.high, 28, 1), (.block, 28, 0), (.mouse, 40, 2)]
                           + biscuits(16, 24, lane: 1) + biscuits(32, 38, lane: 2)),
        ZoomiesStretch(name: "corridor", length: 52, tier: 3,
                       items: [(.block, 8, 0), (.block, 8, 2), (.low, 18, 1), (.block, 28, 0), (.block, 28, 2), (.high, 38, 1)]
                           + biscuits(2, 46, lane: 1, every: 3) + [(.catnip, 46, 1)]),
    ]

    /// The stretch to lay at `distance` metres: easy ones first, harder ones mixed in as the run goes on.
    static func pick(at distance: Double, seed: inout DaySeed) -> ZoomiesStretch {
        let z = Tuning.Arcade.Zoomies.self
        let tier = distance < z.tierTwoFrom ? 1 : distance < z.tierThreeFrom ? 2 : 3
        // Mostly the tier reached, sometimes an easier breather.
        let weights = (1 ... 3).map { t in t > tier ? 0 : t == tier ? 3 : 1 }
        let chosenTier = (seed.pick(weights: weights) ?? 0) + 1
        let pool = stretches.filter { $0.tier == chosenTier }
        return pool[seed.below(pool.count)]
    }
}

/// A player with quick reflexes for checking the course: it looks a little ahead in its lane and jumps, slides or
/// moves to the nearest open lane. A stretch it gets through at full speed is one a person can.
public enum ZoomiesBot {
    public static func act(on run: ZoomiesRun) -> [ZoomiesInput] {
        let z = Tuning.Arcade.Zoomies.self
        let lane = run.lane
        let ahead = run.items.filter { $0.thing.isObstacle && $0.at + $0.thing.length > run.distance - z.catHalfLength }
        func next(in lane: Int) -> ZoomiesItem? {
            ahead.first { $0.lane == lane }
        }
        let threat = next(in: lane)
        let gap = (threat?.at ?? .infinity) - (run.distance + z.catHalfLength)
        let seconds = gap / run.speed
        // Let go of a slide once nothing to slide under is close.
        if run.isSliding, threat?.thing != .high || seconds > 0.3 {
            return [.slideEnd]
        }
        guard let threat else { return [] }
        switch threat.thing {
        case .low:
            // Jump so the cat is at its highest over the thing.
            let rise = z.jumpSeconds / 2 - (threat.thing.length / 2 + z.catHalfLength) / run.speed
            return run.jumpTime == nil && seconds <= max(rise, 0.02) ? [.jump] : []
        case .high:
            return !run.isSliding && run.jumpTime == nil && seconds < 0.25 ? [.slideStart] : []
        default:
            guard seconds < 1.4, run.laneProgress >= 1 else { return [] }
            // The lane whose next block is furthest off, reached through lanes clear for the move.
            let margin = (z.laneSeconds + 0.12) * run.speed
            func nextBlock(_ l: Int) -> Double {
                ahead.first { $0.lane == l && $0.thing == .block }?.at ?? .infinity
            }
            func clearNow(_ l: Int) -> Bool {
                !ahead.contains {
                    $0.lane == l && $0.thing == .block && $0.at < run.distance + z.catHalfLength + margin
                        && $0.at + $0.thing.length > run.distance - z.catHalfLength
                }
            }
            var best: Int?
            for target in 0 ..< z.lanes where target != lane {
                let step = target > lane ? 1 : -1
                guard stride(from: lane + step, through: target, by: step).allSatisfy(clearNow) else { continue }
                if let current = best {
                    let further = nextBlock(target) > nextBlock(current)
                    let nearer = nextBlock(target) == nextBlock(current) && abs(target - lane) < abs(current - lane)
                    if further || nearer { best = target }
                } else {
                    best = target
                }
            }
            guard let target = best, nextBlock(target) > threat.at else { return [] }
            return [target < lane ? .up : .down]
        }
    }
}
