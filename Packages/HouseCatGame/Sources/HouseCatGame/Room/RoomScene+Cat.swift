import HouseCatCore
import SpriteKit

/// Where the cat goes for an activity: a floor point, a height on the furniture, a pose.
public struct CatSpot: Sendable {
    public var point: CGPoint
    public var lift: CGFloat
    public var pose: CatPose
    /// The draw order when it sits on the furniture.
    public var perchDepth: CGFloat?
    public var itemID: String?
    /// Where it jumps up from: the floor in front of the furniture (nil when it is on the floor).
    public var approach: CGPoint?
}

public extension RoomScene {
    /// Puts the cat in the room, settled in a pose at a floor cell: in its look from the builder when the
    /// builder's art is given, else the plain painted set.
    @discardableResult
    func addCat(
        rig: PuppetRig,
        catArt: CatArt? = nil,
        look: CatLook? = nil,
        isKitten: Bool = false,
        at u: CGFloat,
        _ v: CGFloat,
        pose: CatPose
    ) -> CatDirector {
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, isKitten: isKitten, height: CGFloat(model.catHeight))
        if let room = activeRoom {
            room.addChild(cat)
            catRoom = room.id
        } else {
            world.addChild(cat)
        }
        let director = CatDirector(cat: cat, grid: grid)
        director.place(at: grid.floor(u, v))
        cat.settle(into: pose, duration: 0)
        self.director = director
        return director
    }

    /// Dresses the cat (nil: nothing on).
    func dress(_ outfit: OutfitsFile.Outfit?) {
        director?.cat.wear(outfit)
    }

    /// The spot for an activity in the cat's room.
    func spot(for choice: BehaviourChoice) -> CatSpot {
        guard let room = rooms[choice.room ?? catRoom] ?? activeRoom else {
            return CatSpot(point: grid.floor(grid.cells / 2, grid.cells / 2), lift: 0, pose: choice.pose ?? .sitSide)
        }
        return spot(for: choice, in: room)
    }

    /// The spot for an activity in a room, given the furniture in it.
    internal func spot(for choice: BehaviourChoice, in room: RoomNode) -> CatSpot {
        let pose = choice.pose ?? .sitSide
        let model = room.model
        if let need = choice.affordance, let placement = model.items.first(where: { items[$0.id]?.affordances.contains(need) == true }),
           let item = items[placement.id], let node = room.furniture[item.id]
        {
            let (w, d) = room.footprint(item, facing: placement.facing)
            let u = CGFloat(placement.u), v = CGFloat(placement.v)
            switch need {
            case .sit, .sleep, .perch where !item.decal:
                // On top: the middle of the footprint, raised to the seat (or the top for a perch), jumped up to
                // from the floor in front.
                let seat = CGFloat(need == .perch ? Tuning.Puppet.perchHeight : Tuning.Puppet.seatHeight)
                return CatSpot(
                    point: grid.floor(u + w / 2, v + d / 2),
                    lift: node.size.height * seat,
                    pose: pose,
                    perchDepth: node.zPosition + 1,
                    itemID: item.id,
                    approach: approach(toFootprint: u, v, w, d, in: room)
                )
            default:
                // Beside it, on the floor in front.
                let beside = grid.floor(u + w + CGFloat(Tuning.Puppet.besideGap), v + d / 2 + CGFloat(Tuning.Puppet.besideForward))
                return CatSpot(point: beside, lift: 0, pose: pose, perchDepth: nil, itemID: item.id)
            }
        }
        // No furniture for it: the room's own spots (layout data), or the middle of the floor.
        func floorSpot(_ key: String, _ pose: CatPose) -> CatSpot {
            let cell = model.spots[key] ?? [grid.cells / 2, grid.cells / 2].map(Double.init)
            return CatSpot(point: grid.floor(CGFloat(cell[0]), CGFloat(cell[1])), lift: 0, pose: pose)
        }
        switch choice.activity {
        case .nearPlayer: return floorSpot("nearPlayer", .sitFront)
        case .sunbeamLoaf: return floorSpot("sunbeam", .loafSide)
        case .sulk: return floorSpot("sulk", .sitBack)
        default: return floorSpot("middle", pose)
        }
    }

    /// The floor in front of a footprint, where the cat jumps up from: the middle of whichever front edge has room
    /// in front of it (inside the room, clear of other furniture), the nearer one to the cat if both do.
    internal func approach(toFootprint u: CGFloat, _ v: CGFloat, _ w: CGFloat, _ d: CGFloat, in room: RoomNode) -> CGPoint {
        let gap = CGFloat(Tuning.Puppet.jumpFrom)
        let n = grid.cells, edge: CGFloat = 0.4
        let candidates = [CGPoint(x: u + w / 2, y: v + d + gap), CGPoint(x: u + w + gap, y: v + d / 2)]
        func clear(_ c: CGPoint) -> Bool {
            guard c.x > edge, c.y > edge, c.x < n - edge, c.y < n - edge else { return false }
            return !room.model.items.contains { placement in
                guard let item = items[placement.id], item.layer != .wall, !item.decal else { return false }
                let (pw, pd) = room.footprint(item, facing: placement.facing)
                return c.x >= CGFloat(placement.u) && c.x <= CGFloat(placement.u) + pw && c.y >= CGFloat(placement.v) && c.y <= CGFloat(placement.v) + pd
            }
        }
        let open = candidates.filter(clear)
        let cat = director.map { grid.cell(at: $0.floorPoint) }.map { CGPoint(x: $0.u, y: $0.v) }
        let best = (open.isEmpty ? candidates : open).min { a, b in
            guard let cat else { return false }
            return hypot(a.x - cat.x, a.y - cat.y) < hypot(b.x - cat.x, b.y - cat.y)
        } ?? candidates[0]
        return grid.floor(min(max(best.x, edge), n - edge), min(max(best.y, edge), n - edge))
    }

    /// Furniture moved, turned or put away in the cat's room while the cat was up on something: when nothing
    /// is under it any more, it gets up and hops down where it is (a present it left up there drops with it).
    internal func catGetsDown(in room: RoomNode) {
        guard let director, director.lift > 0, director.cat.parent === room else { return }
        let (cu, cv) = grid.cell(at: director.floorPoint)
        let underneath = room.model.items.contains { placement in
            guard let item = items[placement.id], item.layer != .wall, !item.decal else { return false }
            let (w, d) = room.footprint(item, facing: placement.facing)
            return cu >= CGFloat(placement.u) && cu <= CGFloat(placement.u) + w && cv >= CGFloat(placement.v) && cv <= CGFloat(placement.v) + d
        }
        guard !underneath else { return }
        let lift = director.lift
        if let gift = room.childNode(withName: "gift") {
            let drop = SKAction.moveBy(x: 0, y: -lift, duration: Tuning.Puppet.jumpSeconds)
            drop.timingMode = .easeIn
            gift.run(drop)
        }
        director.run([
            .rise(.tqfront),
            .hop(to: director.floorPoint, lift: 0),
            .call { [weak self] in self?.director?.perchDepth = nil },
            .settle(.sitThreeQuarterFront),
        ])
    }

    /// The floor just in front of where the cat is (to jump down to).
    internal func groundInFront(of point: CGPoint) -> CGPoint {
        let cell = grid.cell(at: point), n = grid.cells, step = CGFloat(Tuning.Puppet.jumpFrom)
        return grid.floor(min(cell.u + step, n - 0.4), min(cell.v + step, n - 0.4))
    }

    /// Steps that take the cat from where it is to a spot (in its room, or another) and settle it there: awake
    /// from a sleep it stretches first, up on something it jumps down, and it jumps up onto furniture from in front.
    func steps(to spot: CatSpot, in room: RoomID? = nil, pace: CatDirector.Pace = .walk) -> [CatDirector.Step] {
        var steps: [CatDirector.Step] = []
        let cat = director?.cat
        if cat?.pose == .sleepCurl {
            steps += [.glance(.stretchSide), .wait(Tuning.Puppet.stretchSeconds)]
        }
        steps.append(.rise(cat?.view ?? .side))
        if let director, director.lift > 0 {
            steps += [.hop(to: groundInFront(of: director.floorPoint), lift: 0), .call { [weak self] in self?.director?.perchDepth = nil }]
        }
        steps += route(to: room ?? catRoom, pace: pace)
        if spot.lift > 0 {
            steps.append(.move(to: spot.approach ?? spot.point, pace: pace))
            steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
            steps.append(.hop(to: spot.point, lift: spot.lift))
        } else {
            steps.append(.move(to: spot.point, pace: pace))
            steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
        }
        steps.append(.settle(spot.pose))
        return steps
    }

    /// The way into another room: doorway by doorway through the open rooms of the storey, or out by the
    /// stairs (or the middle of the room, if there is no way through) and in on the other side, out of sight.
    func route(to target: RoomID, pace: CatDirector.Pace = .walk) -> [CatDirector.Step] {
        guard target != catRoom, let to = rooms[target] else { return [] }
        func walk(_ cell: CGPoint) -> CatDirector.Step {
            .move(to: grid.floor(cell.x, cell.y), pace: pace)
        }
        let step = CGFloat(Tuning.House.doorwayStep), n = grid.cells
        if let path = house.route(from: catRoom, to: target) {
            var steps: [CatDirector.Step] = []
            for link in path {
                guard let node = rooms[link.to] else { continue }
                // Up to the doorway, through it, and a step into the room beyond.
                let inward = CGPoint(
                    x: link.entry.x == 0 ? step : link.entry.x == n ? -step : 0,
                    y: link.entry.y == 0 ? step : link.entry.y == n ? -step : 0
                )
                steps.append(walk(CGPoint(x: link.exit.x - inward.x, y: link.exit.y - inward.y)))
                steps.append(walk(link.exit))
                steps.append(.enter(node, at: grid.floor(link.entry.x, link.entry.y)))
                steps.append(.call { [weak self] in self?.catEntered(link.to) })
                steps.append(walk(CGPoint(x: link.entry.x + inward.x, y: link.entry.y + inward.y)))
            }
            return steps
        }
        // Up or down the stairs where the stairs stand; otherwise the cat slips out of sight in the room.
        let stairs = house.stairs.flatMap { $0.at.count == 2 ? CGPoint(x: $0.at[0] + 0.5, y: $0.at[1] + 1) : nil }
        let middle = CGPoint(x: n / 2, y: n / 2)
        let out = house.stairs?.room == catRoom ? stairs ?? middle : middle
        let into = house.stairs?.room == target ? stairs ?? middle : middle
        return [
            walk(out),
            .fade(to: 0),
            .enter(to, at: grid.floor(into.x, into.y)),
            .call { [weak self] in self?.catEntered(target) },
            .fade(to: 1),
        ]
    }

    /// The arrival (CLAUDE.md "The arrival in the room view is live"): the cat notices you, trots to the front of
    /// its room while the camera leans in, rubs along the front, then goes off to what the behaviour table chose.
    func playArrival(then choice: BehaviourChoice, onRub: @escaping @MainActor () -> Void, onDone: @escaping @MainActor () -> Void) {
        guard let director else { return }
        let a = Tuning.Arrival.self
        let from = grid.floor(CGFloat(a.rubFrom[0]), CGFloat(a.rubFrom[1])), to = grid.floor(CGFloat(a.rubTo[0]), CGFloat(a.rubTo[1]))
        let spot = spot(for: choice)
        let room = choice.room ?? catRoom
        director.run([
            .wait(a.noticeDelay),
            .rise(.tqfront), // ears up, it has noticed you
            .wait(a.noticeHold),
            .call { [weak self] in self?.lookCloser(for: a.greetCloseUpSeconds) },
            .move(to: from, pace: .trot),
            .call(onRub),
            .move(to: to, pace: .stroll),
        ] + steps(to: spot, in: room).filter { step in
            if case .rise = step { return false }
            return true
        } + [.call(onDone)])
        beganActivity(choice.activity)
    }

    /// Sends the cat off to an activity now (fed: to the bowl; petted too much: away), in the choice's room.
    func send(_ choice: BehaviourChoice, pace: CatDirector.Pace? = nil) {
        guard let director else { return }
        let pace = pace ?? (choice.activity == .bowlNag ? .trot : .walk)
        if choice.activity == .zoomies {
            director.run(zoomies())
        } else {
            director.run(steps(to: spot(for: choice), in: choice.room ?? catRoom, pace: pace) + extras(for: choice))
        }
        beganActivity(choice.activity)
    }

    /// What an activity adds once the cat is there: knocking at the thing it sits by, scratching the post.
    internal func extras(for choice: BehaviourChoice) -> [CatDirector.Step] {
        guard [.knockOff, .scratch].contains(choice.activity), let room = rooms[choice.room ?? catRoom],
              let id = spot(for: choice, in: room).itemID, let node = room.furniture[id] else { return [] }
        func rock() -> CatDirector.Step {
            .call { [weak self, weak node] in
                if let node {
                    self?.wobble(node)
                }
            }
        }
        return choice.activity == .knockOff
            ? [.wait(1.2), rock(), .wait(0.9), rock(), .wait(0.5), .call { [weak self] in self?.react("exclaim") }]
            : [rock(), .wait(0.5), rock(), .wait(0.5), rock(), .wait(0.6), .glance(.sitSide)]
    }

    /// A piece of furniture rocks where it stands (batted, scratched).
    internal func wobble(_ node: SKNode) {
        let angle = CGFloat(Tuning.Puppet.wobbleDegrees) * .pi / 180
        let rock = SKAction.sequence([
            .rotate(toAngle: angle, duration: 0.07),
            .rotate(toAngle: -angle * 0.7, duration: 0.1),
            .rotate(toAngle: angle * 0.35, duration: 0.09),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        node.run(rock, withKey: "wobble")
    }

    /// Zoomies: a burst of dashes about the room, a skid, and a flop down to catch its breath.
    internal func zoomies() -> [CatDirector.Step] {
        guard let director else { return [] }
        let n = grid.cells
        var steps: [CatDirector.Step] = [.rise(director.cat.view)]
        if director.lift > 0 {
            steps += [.hop(to: groundInFront(of: director.floorPoint), lift: 0), .call { [weak self] in self?.director?.perchDepth = nil }]
        }
        let dashes = Int.random(in: 4 ... 6)
        var last = grid.cell(at: director.floorPoint)
        for i in 0 ..< dashes {
            // Somewhere well across the room each time.
            var cell = (u: CGFloat.random(in: 1.2 ... n - 1.2), v: CGFloat.random(in: 1.2 ... n - 1.2))
            for _ in 0 ..< 6 where hypot(cell.u - last.u, cell.v - last.v) < n * 0.35 {
                cell = (u: CGFloat.random(in: 1.2 ... n - 1.2), v: CGFloat.random(in: 1.2 ... n - 1.2))
            }
            steps.append(.move(to: grid.floor(cell.u, cell.v), pace: .dash))
            if i == dashes / 2 {
                steps.append(.wait(0.35))
            }
            last = cell
        }
        steps.append(.settle(.loafSide))
        return steps
    }

    /// The cat has started on something: how long it keeps at it once there (Tuning.Puppet.hold).
    internal func beganActivity(_ activity: Activity) {
        catActivity = activity
        fidgeting = false
        settledFor = 0
        let range = Tuning.Puppet.hold[activity.rawValue] ?? [Tuning.Puppet.idleSeconds, Tuning.Puppet.idleSeconds]
        holdFor = TimeInterval.random(in: range[0] ... max(range[0], range[1]))
        nextFidget = TimeInterval.random(in: Tuning.Puppet.fidgetGap[0] ... Tuning.Puppet.fidgetGap[1])
    }

    /// While the cat is settled, now and then: a glance at you and back, a slow blink, a stretch of the neck to
    /// look about, a puff of z's asleep. Only what the painted poses can show.
    internal func fidget() {
        guard let director, director.isIdle, let pose = director.cat.pose else { return }
        let visible = director.cat.parent.map { isShown($0) } ?? false
        switch pose {
        case .sitSide:
            fidgeting = true
            director.run([.glance(.sitThreeQuarterFront), .wait(.random(in: 2 ... 4)), .glance(.sitSide)])
        case .loafSide:
            fidgeting = true
            director.run([.glance(.loafThreeQuarterFront), .wait(.random(in: 2.5 ... 5)), .glance(.loafSide)])
        case .sitThreeQuarterFront, .loafThreeQuarterFront, .sitFront:
            director.cat.blink(slow: Bool.random())
        case .sleepCurl:
            if visible {
                react("zzz")
            }
        case .sitBack, .stretchSide:
            break
        }
    }

    /// A reaction icon (assets/fx/reactions: heart, zzz, notes, sparkle, question, exclaim, paw) pops up over the
    /// cat with a little overshoot, floats up swaying and fades.
    func react(_ icon: String, count: Int = 1) {
        guard let cat = director?.cat, let room = cat.parent else { return }
        let path = "fx/reactions/fx_reactions_\(icon).png"
        guard art.has(path) else { return }
        let painted = art.paintedSize(path)
        let top = cat.bodyFrame.maxY
        for i in 0 ..< max(1, count) {
            let small = i > 0
            let width = CGFloat(Tuning.Puppet.reactionWidth) * (small ? 0.6 : 1)
            let node = SKSpriteNode(
                texture: art.texture(path),
                size: CGSize(width: width, height: width * painted.height / max(painted.width, 1))
            )
            let spread = small ? CGFloat.random(in: -40 ... 40) : 0
            node.position = CGPoint(x: cat.position.x + spread, y: top + 10)
            node.zPosition = Layer.reaction
            node.alpha = 0
            node.setScale(0.3)
            room.addChild(node)
            let seconds = Tuning.Puppet.reactionSeconds
            let rise = CGFloat(Tuning.Puppet.reactionRise) * (small ? 0.8 : 1)
            let pop = SKAction.sequence([
                .scale(to: 1.15, duration: 0.16),
                .scale(to: 0.95, duration: 0.08),
                .scale(to: 1.0, duration: 0.07),
            ])
            pop.timingMode = .easeOut
            let up = SKAction.moveBy(x: 0, y: rise, duration: seconds)
            up.timingMode = .easeOut
            let side = CGFloat.random(in: 6 ... 12) * (Bool.random() ? 1 : -1)
            let sway = SKAction.sequence([
                .moveBy(x: side, y: 0, duration: seconds / 3),
                .moveBy(x: -side * 2, y: 0, duration: seconds / 3),
                .moveBy(x: side, y: 0, duration: seconds / 3),
            ])
            node.run(.sequence([
                .wait(forDuration: Double(i) * 0.14),
                .group([.fadeIn(withDuration: 0.12), pop, up, sway, .sequence([.wait(forDuration: seconds * 0.65), .fadeOut(withDuration: seconds * 0.35)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// Whether a scene point is on the cat.
    func isOnCat(_ point: CGPoint) -> Bool {
        guard let cat = director?.cat, let room = cat.parent, isShown(room) else { return false }
        let frame = cat.bodyFrame
        return frame.insetBy(dx: -CGFloat(Tuning.Puppet.tapPadding), dy: -CGFloat(Tuning.Puppet.tapPadding)).contains(convert(
            point,
            to: room
        ))
    }
}
