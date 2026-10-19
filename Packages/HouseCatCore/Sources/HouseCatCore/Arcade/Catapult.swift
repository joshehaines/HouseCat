import Foundation

/// Catapult (the Games menu's pounce game): the cat crouches on a cushion at the left; drag back and let go and it
/// pounces in a curled-up ball along the arc. Knock every toy mouse off its tower (onto the ground, or pounce right
/// on it) within the level's pounces. Each place on the map (`Biome`) has `Tuning.Arcade.Catapult.levelsPerPlace`
/// levels in its own setting, the player's home's first. Stars: the level's `par` pounces or fewer three, one more
/// two, any clear one. The physics is `PounceWorld`, stepped at a fixed rate, so a level's recorded solution clears
/// it on every device.
public enum CatapultPiece: String, Codable, Sendable, CaseIterable {
    case box, wide, book, plank, short, tin, pot, cushion

    /// Half its size lying flat (width, height), or the ball's radius in `x`.
    public var half: Vec2 {
        switch self {
        case .box: Vec2(0.225, 0.225)
        case .wide: Vec2(0.4, 0.2)
        case .book: Vec2(0.25, 0.06)
        case .plank: Vec2(0.8, 0.05)
        case .short: Vec2(0.45, 0.05)
        case .tin: Vec2(0.17, 0.17)
        case .pot: Vec2(0.16, 0.17)
        case .cushion: Vec2(0.3, 0.1)
        }
    }

    public var isBall: Bool {
        self == .tin
    }

    var density: Double {
        switch self {
        case .box: 1.5
        case .wide: 1.2
        case .book: 5
        case .plank, .short: 4
        case .tin: 4
        case .pot: 7
        case .cushion: 1
        }
    }

    var friction: Double {
        switch self {
        case .tin: 0.4
        case .book, .cushion: 0.8
        default: 0.6
        }
    }

    var bounce: Double {
        self == .cushion ? 0.45 : 0
    }
}

/// One Catapult level (Content/catapult_levels.json).
public struct CatapultLevel: Codable, Equatable, Sendable {
    public struct Placed: Codable, Equatable, Sendable {
        public var kind: CatapultPiece
        /// Its middle along the ground and its bottom, in metres.
        public var x: Double
        public var y: Double
        /// Stood on end (turned a quarter).
        public var upright: Bool

        public init(_ kind: CatapultPiece, x: Double, y: Double, upright: Bool = false) {
            self.kind = kind
            self.x = x
            self.y = y
            self.upright = upright
        }

        /// Half its size as it stands.
        public var half: Vec2 {
            upright ? Vec2(kind.half.y, kind.half.x) : kind.half
        }

        public var top: Double {
            kind.isBall ? y + 2 * kind.half.x : y + 2 * half.y
        }
    }

    /// A fixed ledge: its middle, bottom, width and height (a wall top, a shed roof, a rock).
    public struct Ledge: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// A pounce: the angle above level in degrees and the pull, 0 to 1.
    public struct Shot: Codable, Equatable, Sendable {
        public var angle: Double
        public var power: Double

        public init(angle: Double, power: Double) {
            self.angle = angle
            self.power = power
        }
    }

    public var id: Int
    public var place: Biome
    public var title: String
    public var pounces: Int
    public var par: Int
    public var ledges: [Ledge]
    public var pieces: [Placed]
    /// Where each toy mouse sits: its middle along and its bottom.
    public var mice: [Vec2]
    /// A way through, found when the level was made (`par` shots or fewer).
    public var solution: [Shot]

    public init(id: Int, place: Biome, title: String, pounces: Int, par: Int, ledges: [Ledge], pieces: [Placed], mice: [Vec2],
                solution: [Shot] = [])
    {
        self.id = id
        self.place = place
        self.title = title
        self.pounces = pounces
        self.par = par
        self.ledges = ledges
        self.pieces = pieces
        self.mice = mice
        self.solution = solution
    }
}

public struct CatapultLevelsFile: Codable, Sendable {
    public var version: Int
    public var levels: [CatapultLevel]

    public init(version: Int, levels: [CatapultLevel]) {
        self.version = version
        self.levels = levels
    }
}

public enum CatapultBeat: Equatable, Sendable {
    /// A toy mouse knocked to the ground (or pounced on, `caught`).
    case knocked(mouse: Int, caught: Bool)
    /// The cat has come to rest: the pounce is over.
    case settled
    case won
    case lost
}

public struct CatapultGame: Sendable {
    public let level: CatapultLevel
    public private(set) var world = PounceWorld()
    public private(set) var groundID = 0
    /// Each mouse's body id, by its index in the level; knocked ones are gone from the world.
    public private(set) var mouseIDs: [Int] = []
    public private(set) var knocked: Set<Int> = []
    public private(set) var used = 0
    /// The cat's body while a pounce is on.
    public private(set) var catID: Int?
    public private(set) var flying = false
    private var calm = 0.0
    private var airborne = 0.0
    private var leftover = 0.0

    /// Where the cat pounces from (the top of its cushion).
    public var launch: Vec2 {
        Tuning.Arcade.Catapult.launch
    }

    public init(level: CatapultLevel) {
        self.level = level
        let c = Tuning.Arcade.Catapult.self
        groundID = world.add(.box(Vec2(c.groundHalfWidth, 1)), at: Vec2(c.groundMiddle, -1), density: .infinity, friction: 0.8,
                             role: "ground")
        for ledge in level.ledges {
            world.add(.box(Vec2(ledge.width / 2, ledge.height / 2)), at: Vec2(ledge.x, ledge.y + ledge.height / 2),
                      density: .infinity, friction: 0.8, role: "ledge")
        }
        for piece in level.pieces {
            let kind = piece.kind
            if kind.isBall {
                world.add(.ball(kind.half.x), at: Vec2(piece.x, piece.y + kind.half.x), density: kind.density,
                          friction: kind.friction, role: kind.rawValue)
            } else {
                world.add(.box(kind.half), at: Vec2(piece.x, piece.y + piece.half.y), rotation: piece.upright ? .pi / 2 : 0,
                          density: kind.density, friction: kind.friction, bounce: kind.bounce, role: kind.rawValue)
            }
        }
        for mouse in level.mice {
            mouseIDs.append(world.add(.box(c.mouseHalf), at: Vec2(mouse.x, mouse.y + c.mouseHalf.y), density: c.mouseDensity,
                                      friction: 0.7, role: "mouse"))
        }
        // Settle what was laid out (pieces touch to within a hair), so every game starts from the same rest.
        var still = 0.0, waited = 0.0
        while waited < c.settleSeconds, still < c.restSeconds {
            world.step(c.step)
            waited += c.step
            still = world.fastest < c.restSpeed ? still + c.step : 0
        }
        for i in world.bodies.indices {
            world.bodies[i].velocity = .zero
            world.bodies[i].spin = 0
        }
        calmWorld = true
    }

    /// The world is at rest and no pounce is on: it waits, unstepped.
    private var calmWorld = false

    public var won: Bool {
        knocked.count == level.mice.count
    }

    public var over: Bool {
        !flying && (won || used >= level.pounces)
    }

    public var pouncesLeft: Int {
        level.pounces - used
    }

    public var stars: Int {
        guard won else { return 0 }
        return used <= level.par ? 3 : used == level.par + 1 ? 2 : 1
    }

    /// The cat's speed for a pull (0 to 1) and its velocity for an angle.
    public static func velocity(angle: Double, power: Double) -> Vec2 {
        let c = Tuning.Arcade.Catapult.self
        let speed = c.slowest + (c.fastest - c.slowest) * min(max(power, 0), 1)
        let radians = min(max(angle, c.lowestAngle), c.highestAngle) * .pi / 180
        return Vec2(speed * cos(radians), speed * sin(radians))
    }

    /// Where the cat would be `t` seconds into a pounce, ignoring what it hits (the aiming dots).
    public static func arc(angle: Double, power: Double, at t: Double) -> Vec2 {
        let v = velocity(angle: angle, power: power)
        let g = Tuning.Arcade.Catapult.gravity
        let start = Tuning.Arcade.Catapult.launch
        return Vec2(start.x + v.x * t, start.y + v.y * t - g * t * t / 2)
    }

    /// The cat pounces: false if a pounce is still on or none are left.
    @discardableResult
    public mutating func pounce(angle: Double, power: Double) -> Bool {
        guard !flying, !over else { return false }
        let c = Tuning.Arcade.Catapult.self
        let cat = world.add(.ball(c.catRadius), at: launch, density: c.catDensity, friction: 0.5, bounce: 0.15, role: "cat")
        world.setVelocity(cat, Self.velocity(angle: angle, power: power))
        catID = cat
        used += 1
        flying = true
        calmWorld = false
        calm = 0
        airborne = 0
        return true
    }

    /// Runs the world on by `dt` (in fixed steps; what is left over waits for the next call).
    public mutating func step(_ dt: Double) -> [CatapultBeat] {
        let c = Tuning.Arcade.Catapult.self
        var beats: [CatapultBeat] = []
        if calmWorld, !flying {
            return beats
        }
        leftover += dt
        while leftover >= c.step {
            leftover -= c.step
            beats += fixedStep()
        }
        return beats
    }

    private mutating func fixedStep() -> [CatapultBeat] {
        let c = Tuning.Arcade.Catapult.self
        var beats: [CatapultBeat] = []
        world.step(c.step)
        // The cat lands on its feet: on the ground it skids to a stop instead of rolling on.
        if let cat = catID, world.touching.contains([min(groundID, cat), max(groundID, cat)]) {
            world.land(cat, keeping: c.landingGrip)
        }
        for (index, id) in mouseIDs.enumerated() where !knocked.contains(index) {
            guard let mouse = world.body(id) else { continue }
            let caught = catID.map { world.touching.contains([min($0, id), max($0, id)]) } ?? false
            let grounded = world.touching.contains([min(groundID, id), max(groundID, id)]) || mouse.bottom < c.groundSlack
            let lost = mouse.position.x < c.left || mouse.position.x > c.right || mouse.position.y < -1
            if caught || grounded || lost {
                knocked.insert(index)
                world.remove(id)
                beats.append(.knocked(mouse: index, caught: caught))
            }
        }
        guard flying else { return beats }
        airborne += c.step
        calm = world.fastest < c.restSpeed ? calm + c.step : 0
        if calm >= c.restSeconds || airborne >= c.longestPounce || won && calm >= c.restSeconds / 3 {
            if let cat = catID { world.remove(cat) }
            catID = nil
            flying = false
            // At rest again: it waits for the next pounce exactly as it is.
            for i in world.bodies.indices {
                world.bodies[i].velocity = .zero
                world.bodies[i].spin = 0
            }
            calmWorld = true
            beats.append(.settled)
            if won {
                beats.append(.won)
            } else if used >= level.pounces {
                beats.append(.lost)
            }
        }
        return beats
    }

    /// Plays a whole pounce out to its end (for checking levels).
    public mutating func playOut(angle: Double, power: Double) {
        guard pounce(angle: angle, power: power) else { return }
        while flying {
            _ = fixedStep()
        }
    }

    /// Lets the level stand for `seconds` without a pounce (it must not fall over by itself).
    public mutating func stand(_ seconds: Double) -> [CatapultBeat] {
        var beats: [CatapultBeat] = []
        for _ in 0 ..< Int(seconds / Tuning.Arcade.Catapult.step) {
            beats += fixedStep()
        }
        return beats
    }

    /// The stats a finished level records for the challenges.
    public var stats: [String: Int] {
        ["mice": knocked.count, "clears": won ? 1 : 0, "threeStars": stars == 3 ? 1 : 0]
    }
}
