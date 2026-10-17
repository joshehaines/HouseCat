import HouseCatCore
import SpriteKit

/// Moves the cat through the room one step at a time: walking and running
/// between floor points, hopping onto furniture, settling into a painted pose.
/// The scene calls `update` every frame. Which activity the cat chooses comes
/// from HouseCatCore's behaviour table; this only carries it out.
@MainActor
public final class CatDirector {
    public enum Step {
        case wait(TimeInterval)
        /// Cross-fade from the puppet into a painted pose.
        case settle(CatPose)
        /// Cross-fade back to the puppet in a view.
        case rise(CatNode.View)
        /// Move to a point in room units, walking or running, scaling the cat as it goes
        /// (the run towards the camera), with an optional height off the floor (furniture).
        case move(to: CGPoint, run: Bool, view: CatNode.View, scale: CGFloat, lift: CGFloat, speed: CGFloat)
        /// A small hop to a height (onto a seat) without moving across the floor.
        case hop(to: CGFloat)
        case call(@MainActor () -> Void)
    }

    public let cat: CatNode
    private let grid: IsoGrid
    private var steps: [Step] = []
    private var current: Step?
    private var elapsed: TimeInterval = 0
    private var from: (point: CGPoint, scale: CGFloat, lift: CGFloat) = (.zero, 1, 0)
    private var duration: TimeInterval = 0
    /// Where the cat stands on the floor (its feet), in room units; `lift` raises it onto furniture.
    public private(set) var floorPoint: CGPoint = .zero
    public private(set) var lift: CGFloat = 0
    /// Draw order on top of a piece of furniture, when the cat is sitting on it.
    public var perchDepth: CGFloat?

    public init(cat: CatNode, grid: IsoGrid) {
        self.cat = cat
        self.grid = grid
    }

    public var isIdle: Bool {
        current == nil && steps.isEmpty
    }

    public func place(at point: CGPoint, lift: CGFloat = 0) {
        floorPoint = point
        self.lift = lift
        apply()
    }

    public func run(_ steps: [Step]) {
        self.steps = steps
        current = nil
        next()
    }

    public func then(_ steps: [Step]) {
        self.steps += steps
        if current == nil {
            next()
        }
    }

    private func next() {
        guard !steps.isEmpty else {
            current = nil
            return
        }
        let step = steps.removeFirst()
        current = step
        elapsed = 0
        from = (floorPoint, cat.xScale.magnitude, lift)
        switch step {
        case let .wait(t):
            duration = t
        case let .settle(pose):
            cat.settle(into: pose)
            duration = Tuning.Puppet.settleSeconds
        case let .rise(view):
            cat.rise(to: view, facingRight: cat.facingRight)
            duration = Tuning.Puppet.riseSeconds
        case let .move(target, run, view, _, _, speed):
            let distance = hypot(target.x - floorPoint.x, target.y - floorPoint.y)
            duration = max(Tuning.Puppet.minMoveSeconds, TimeInterval(distance / speed))
            // Face the way it is going; the side view is painted facing left.
            let right = target.x > floorPoint.x
            perchDepth = nil
            cat.turn(to: view, facingRight: view == .front ? false : right)
            if run {
                cat.run()
            } else {
                cat.walk()
            }
        case .hop:
            duration = Tuning.Puppet.hopSeconds
            cat.stopCycle()
        case let .call(action):
            action()
            duration = 0
        }
    }

    public func update(_ dt: TimeInterval) {
        cat.step(dt)
        guard let step = current else { return }
        elapsed += dt
        let t = duration > 0 ? min(1, elapsed / duration) : 1
        switch step {
        case let .move(target, _, _, scale, targetLift, _):
            let k = CGFloat(t)
            floorPoint = CGPoint(x: from.point.x + (target.x - from.point.x) * k, y: from.point.y + (target.y - from.point.y) * k)
            lift = from.lift + (targetLift - from.lift) * k
            cat.setScale(from.scale + (scale - from.scale) * smooth(k))
            if t >= 1 {
                cat.stopCycle()
            }
        case let .hop(height):
            let k = CGFloat(t)
            lift = from.lift + (height - from.lift) * k + sin(k * .pi) * CGFloat(Tuning.Puppet.hopHeight)
        default:
            break
        }
        apply()
        if t >= 1 {
            next()
        }
    }

    private func smooth(_ k: CGFloat) -> CGFloat {
        k * k * (3 - 2 * k)
    }

    /// Positions the cat and sorts it among the furniture by where it stands.
    private func apply() {
        cat.position = CGPoint(x: floorPoint.x, y: floorPoint.y + lift)
        if cat.xScale.magnitude > Tuning.Puppet.nearCameraScale {
            cat.zPosition = RoomScene.Layer.atCamera
        } else if let perchDepth {
            cat.zPosition = perchDepth
        } else {
            let cell = grid.cell(at: floorPoint)
            cat.zPosition = RoomScene.Layer.standing + grid.depth(cell.u, cell.v) * RoomScene.Layer.perDepth + RoomScene.Layer.catOverItem
        }
    }
}
