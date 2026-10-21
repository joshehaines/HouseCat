import HouseCatCore
import SpriteKit

/// Moves the cat through the room one step at a time: over the floor at a pace (getting up to speed and slowing
/// down, turning to face the way it goes, its stride keeping pace), jumping in an arc onto furniture and down,
/// settling into a painted pose and glancing from one to another. The scene calls `update` every frame. Which
/// activity the cat chooses comes from HouseCatCore's behaviour table; this only carries it out.
@MainActor
public final class CatDirector {
    /// How fast the cat goes, and the gait it goes in.
    public enum Pace: Sendable {
        /// An amble about the room, sniffing round.
        case stroll
        case walk
        /// Somewhere it wants to be: the bowl, you.
        case trot
        case run
        /// Zoomies.
        case dash

        public var speed: CGFloat {
            let p = Tuning.Puppet.self
            let speed: Double = switch self {
            case .stroll: p.strollSpeed
            case .walk: p.walkSpeed
            case .trot: p.trotSpeed
            case .run: p.runSpeed
            case .dash: p.dashSpeed
            }
            return CGFloat(speed)
        }

        public var gait: CatNode.Gait {
            switch self {
            case .stroll, .walk: .walk
            case .trot: .trot
            case .run, .dash: .run
            }
        }
    }

    public enum Step {
        case wait(TimeInterval)
        /// Into a painted pose: from moving, the cat sits down into it.
        case settle(CatPose)
        /// From one painting to another without getting up (a glance at you, a stretch).
        case glance(CatPose)
        /// Back to the puppet in a view, ready to move.
        case rise(CatNode.View)
        /// Over the floor to a point (room units) at a pace; the view and facing follow the way it goes.
        case move(to: CGPoint, pace: Pace)
        /// A jump in an arc to a point and a height off the floor: onto a seat, or down from one (height 0).
        case hop(to: CGPoint, lift: CGFloat)
        /// Turns to a view where it stands (towards you, say).
        case face(CatNode.View, right: Bool)
        /// Through a doorway (or up the stairs, out of sight): into another room's node at a floor point there.
        case enter(SKNode, at: CGPoint)
        /// Fade the cat out or in (going up or down the stairs).
        case fade(to: CGFloat)
        /// Up on its hind legs scratching what it faces, for so long, then down on all fours.
        case scratch(TimeInterval)
        case call(@MainActor () -> Void)
    }

    public let cat: CatNode
    private let grid: IsoGrid
    private var steps: [Step] = []
    private var current: Step?
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var from: (point: CGPoint, lift: CGFloat) = (.zero, 0)
    /// The move under way: its speed profile along the straight line.
    private var profile: Profile?
    /// The speed the cat is going at the end of the last move (it runs on into the next one without stopping).
    private var speedNow: CGFloat = 0
    /// A move the other way waits for a turn first; set once the turn is queued.
    private var pivoted = false
    /// Where the cat stands on the floor (its feet), in room units; `lift` raises it onto furniture.
    public private(set) var floorPoint: CGPoint = .zero
    public private(set) var lift: CGFloat = 0
    /// Draw order on top of a piece of furniture, when the cat is sitting on it.
    public var perchDepth: CGFloat?
    /// The box it is in (catalogue id), drawn behind its front.
    public var insideItem: String?
    /// Its draw order standing on the floor at a point, given the furniture (nil: by its own depth alone).
    public var floorDepth: ((CGPoint) -> CGFloat)?

    public init(cat: CatNode, grid: IsoGrid) {
        self.cat = cat
        self.grid = grid
    }

    public var isIdle: Bool {
        current == nil && steps.isEmpty
    }

    /// What the cat is doing now.
    public var currentStep: Step? {
        current
    }

    public func place(at point: CGPoint, lift: CGFloat = 0) {
        floorPoint = point
        self.lift = lift
        apply()
    }

    public func run(_ steps: [Step]) {
        cat.stopScratching()
        self.steps = steps
        current = nil
        speedNow = 0
        pivoted = false
        next()
    }

    public func then(_ steps: [Step]) {
        self.steps += steps
        if current == nil {
            next()
        }
    }

    /// The way a move to `target` faces: the side view across the room or away, the three-quarter view coming
    /// towards you at a slant, the front view coming straight at you.
    func heading(to target: CGPoint) -> (view: CatNode.View, right: Bool) {
        let dx = target.x - floorPoint.x, dy = target.y - floorPoint.y
        let right = dx > 0
        if dy < 0, abs(dx) < -dy * 0.55 {
            return (.front, false)
        }
        if dy < 0, -dy > abs(dx) * 0.4 {
            return (.tqfront, right)
        }
        return (.side, right)
    }

    private func next() {
        guard !steps.isEmpty else {
            current = nil
            return
        }
        let step = steps.removeFirst()
        // Going the other way from the side view: turn through the three-quarter view first.
        if case let .move(target, _) = step, !pivoted, cat.pose == nil, cat.view == .side {
            let (view, right) = heading(to: target)
            if view == .side, right != cat.facingRight, hypot(target.x - floorPoint.x, target.y - floorPoint.y) > 1 {
                pivoted = true
                speedNow = 0
                steps.insert(contentsOf: [.face(.tqfront, right: right), .wait(Tuning.Puppet.pivotSeconds), step], at: 0)
                next()
                return
            }
        }
        current = step
        elapsed = 0
        from = (floorPoint, lift)
        profile = nil
        switch step {
        case let .wait(t):
            duration = t
        case let .settle(pose):
            // On a sit-down film it takes as long as the film (after any stride finishing).
            let takes = cat.settle(into: pose)
            duration = max(Tuning.Puppet.settleSeconds + Tuning.Puppet.sitDownSeconds, takes + Tuning.Puppet.settleSeconds)
            speedNow = 0
        case let .glance(pose):
            cat.settle(into: pose, duration: Tuning.Puppet.glanceFadeSeconds)
            duration = Tuning.Puppet.glanceFadeSeconds
        case let .rise(view):
            duration = max(Tuning.Puppet.riseSeconds, cat.rise(to: view, facingRight: cat.facingRight))
        case let .move(target, pace):
            pivoted = false
            let distance = hypot(target.x - floorPoint.x, target.y - floorPoint.y)
            // Running on into another move: no slowing down at the corner.
            let carries: Bool = if case .move = steps.first { true } else { false }
            let made = Profile(distance: distance, top: pace.speed, start: min(speedNow, pace.speed), end: carries ? pace.speed : 0)
            profile = made
            duration = max(made.duration, distance < 1 ? 0 : Tuning.Puppet.minMoveSeconds * 0.5)
            perchDepth = nil
            let (view, right) = heading(to: target)
            if view != cat.view {
                cat.turn(to: view, facingRight: right)
            } else if right != cat.facingRight {
                cat.show(view, facingRight: right)
            }
            cat.move(pace.gait)
        case .hop:
            cat.stopCycle()
            let p = Tuning.Puppet.self
            duration = p.crouchSeconds + p.jumpSeconds + p.landSeconds
            cat.squash(CGFloat(p.squash) * 1.4)
            speedNow = 0
        case let .face(view, right):
            cat.turn(to: view, facingRight: right)
            duration = Tuning.Puppet.turnSeconds
        case let .enter(room, point):
            cat.removeFromParent()
            room.addChild(cat)
            floorPoint = point
            lift = 0
            perchDepth = nil
            apply()
            duration = 0
        case let .fade(alpha):
            cat.run(.fadeAlpha(to: alpha, duration: Tuning.Puppet.stairsFadeSeconds))
            duration = Tuning.Puppet.stairsFadeSeconds
        case let .call(action):
            action()
            duration = 0
        case let .scratch(seconds):
            cat.scratch()
            duration = seconds
            falling = false
            speedNow = 0
        }
    }

    /// Scratching: the cat is on its way down (the step lasts that much longer).
    private var falling = false

    public func update(_ dt: TimeInterval) {
        cat.step(dt)
        guard let step = current else { return }
        elapsed += dt
        if case .scratch = step, !falling, elapsed >= duration {
            // Down off the post takes its own time on the scratch film.
            falling = true
            duration += cat.stopScratching()
        }
        let t = duration > 0 ? min(1, elapsed / duration) : 1
        var surface = lift
        switch step {
        case let .move(target, _):
            guard let profile else { break }
            let (s, v) = profile.at(min(elapsed, profile.duration))
            let k = profile.distance > 0 ? s / profile.distance : 1
            floorPoint = CGPoint(x: from.point.x + (target.x - from.point.x) * k, y: from.point.y + (target.y - from.point.y) * k)
            cat.moveSpeed = v
            // The paws step back along the way the cat is going, so planted they stay put on the floor.
            cat.moveDirection = CGVector(dx: target.x - from.point.x, dy: target.y - from.point.y)
            speedNow = v
            surface = lift
            if t >= 1 {
                floorPoint = target
                if profile.end == 0 {
                    cat.stopCycle()
                    speedNow = 0
                }
            }
        case let .hop(target, height):
            let p = Tuning.Puppet.self
            let jumpStart = p.crouchSeconds, jumpEnd = p.crouchSeconds + p.jumpSeconds
            if elapsed < jumpStart {
                break
            }
            if elapsed - dt < jumpStart {
                // Off the ground: the run film's stretched picture, held through the arc.
                cat.leap(true)
            }
            let k = CGFloat(min(1, (elapsed - jumpStart) / p.jumpSeconds))
            let glide = k * k * (3 - 2 * k)
            floorPoint = CGPoint(x: from.point.x + (target.x - from.point.x) * glide, y: from.point.y + (target.y - from.point.y) * glide)
            let arc = CGFloat(p.jumpArc) * cat.height + max(0, height - from.lift) * 0.2
            surface = from.lift + (height - from.lift) * k
            lift = surface + sin(k * .pi) * arc
            if elapsed >= jumpEnd, elapsed - dt < jumpEnd {
                lift = height
                surface = height
                cat.leap(false)
                cat.squash(CGFloat(p.squash))
            }
            if t >= 1 {
                floorPoint = target
                lift = height
                surface = height
            }
        default:
            break
        }
        cat.shadowDrop = lift - surface
        apply()
        if t >= 1 {
            next()
        }
    }

    /// Positions the cat and sorts it among the furniture by where it stands.
    private func apply() {
        cat.position = CGPoint(x: floorPoint.x, y: floorPoint.y + lift)
        if let perchDepth {
            cat.zPosition = perchDepth
        } else if let floorDepth {
            cat.zPosition = floorDepth(floorPoint)
        } else {
            let cell = grid.cell(at: floorPoint)
            cat.zPosition = RoomScene.Layer.standing + grid.depth(cell.u, cell.v) * RoomScene.Layer.perDepth + RoomScene.Layer.catOverItem
        }
    }

    /// A move's speed along its line: up to speed, steady, then slowing (to a stop, or on into the next move).
    struct Profile {
        var distance: CGFloat
        var top: CGFloat
        var start: CGFloat
        var end: CGFloat
        var up: TimeInterval = 0
        var cruise: TimeInterval = 0
        var down: TimeInterval = 0

        init(distance: CGFloat, top: CGFloat, start: CGFloat, end: CGFloat) {
            self.distance = max(0, distance)
            self.start = start
            self.end = end
            let p = Tuning.Puppet.self
            let accel = top / CGFloat(p.accelerateSeconds), decel = top / CGFloat(p.slowSeconds)
            var peak = top
            func reach(_ peak: CGFloat) -> CGFloat {
                (peak * peak - start * start) / (2 * accel) + (peak * peak - end * end) / (2 * decel)
            }
            if reach(top) > self.distance {
                // Too short to get up to speed: as fast as it can go and still stop in time.
                let squared = (self.distance + start * start / (2 * accel) + end * end / (2 * decel)) / (1 / (2 * accel) + 1 / (2 * decel))
                peak = max(max(start, end), squared.squareRoot())
            }
            self.top = peak
            up = TimeInterval(max(0, peak - start) / accel)
            down = TimeInterval(max(0, peak - end) / decel)
            let covered = (start + peak) / 2 * CGFloat(up) + (peak + end) / 2 * CGFloat(down)
            cruise = peak > 0 ? TimeInterval(max(0, self.distance - covered) / peak) : 0
        }

        var duration: TimeInterval {
            up + cruise + down
        }

        /// How far along and how fast, at a time into the move.
        func at(_ t: TimeInterval) -> (CGFloat, CGFloat) {
            if t <= up, up > 0 {
                let k = CGFloat(t / up)
                let v = start + (top - start) * k
                return ((start + v) / 2 * CGFloat(t), v)
            }
            let before = (start + top) / 2 * CGFloat(up)
            if t <= up + cruise {
                return (before + top * CGFloat(t - up), top)
            }
            let late = min(down, t - up - cruise)
            let k = down > 0 ? CGFloat(late / down) : 1
            let v = top + (end - top) * k
            return (min(distance, before + top * CGFloat(cruise) + (top + v) / 2 * CGFloat(late)), v)
        }
    }
}
