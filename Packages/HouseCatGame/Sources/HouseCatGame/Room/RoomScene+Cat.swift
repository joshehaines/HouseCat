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
}

public extension RoomScene {
    /// Speeds in room units a second.
    internal enum Pace {
        static let walk = CGFloat(Tuning.Puppet.walkSpeed)
        static let run = CGFloat(Tuning.Puppet.runSpeed)
        static let rub = CGFloat(Tuning.Puppet.rubSpeed)
    }

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
                // On top: the middle of the footprint, raised to the seat (or the top for a perch).
                let seat = CGFloat(need == .perch ? Tuning.Puppet.perchHeight : Tuning.Puppet.seatHeight)
                return CatSpot(
                    point: grid.floor(u + w / 2, v + d / 2),
                    lift: node.size.height * seat,
                    pose: pose,
                    perchDepth: node.zPosition + 1,
                    itemID: item.id
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

    /// Steps that take the cat from where it is to a spot (in its room, or another) and settle it there.
    func steps(to spot: CatSpot, in room: RoomID? = nil, run: Bool = false) -> [CatDirector.Step] {
        var steps: [CatDirector.Step] = [.rise(.side)]
        steps += route(to: room ?? catRoom, run: run)
        steps.append(.move(to: spot.point, run: run, view: .side, scale: 1, lift: 0, speed: run ? Pace.run : Pace.walk))
        if spot.lift > 0 {
            steps.append(.hop(to: spot.lift))
        }
        steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
        steps.append(.settle(spot.pose))
        return steps
    }

    /// The way into another room: doorway by doorway through the open rooms of the storey, or out by the
    /// stairs (or the middle of the room, if there is no way through) and in on the other side, out of sight.
    func route(to target: RoomID, run: Bool = false) -> [CatDirector.Step] {
        guard target != catRoom, let to = rooms[target] else { return [] }
        let speed = run ? Pace.run : Pace.walk
        func walk(_ cell: CGPoint) -> CatDirector.Step {
            .move(to: grid.floor(cell.x, cell.y), run: run, view: .side, scale: 1, lift: 0, speed: speed)
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

    /// The arrival (CLAUDE.md "The arrival in the room view is live"): the cat notices
    /// you, runs towards the camera in the front view, growing as it comes, rubs along
    /// the bottom edge in the side view, then goes off to what the behaviour table chose.
    func playArrival(then choice: BehaviourChoice, onRub: @escaping @MainActor () -> Void, onDone: @escaping @MainActor () -> Void) {
        guard let director else { return }
        let bottom = grid.floor(grid.cells, grid.cells).y
        let near = CGFloat(Tuning.Arrival.nearScale)
        let start = CGPoint(x: Tuning.Arrival.rubStartX, y: bottom - Tuning.Arrival.rubStartDrop)
        let end = CGPoint(x: Tuning.Arrival.rubEndX, y: bottom - Tuning.Arrival.rubEndDrop)
        let spot = spot(for: choice)
        let room = choice.room ?? catRoom
        // Off to what it chose: in this room, the walk-off from the rub; in another, the way there.
        let walkOff: [CatDirector.Step] = room == catRoom
            ? [.move(to: spot.point, run: false, view: .side, scale: 1, lift: 0, speed: Pace.walk * CGFloat(Tuning.Arrival.walkOffPace))]
            + Array(steps(to: spot).dropFirst(2))
            : [.move(to: end, run: false, view: .side, scale: 1, lift: 0, speed: Pace.walk)] + Array(steps(to: spot, in: room).dropFirst())
        director.run([
            .wait(Tuning.Arrival.noticeDelay),
            .rise(.tqfront), // ears up, it has noticed you
            .wait(Tuning.Arrival.noticeHold),
            .move(to: start, run: true, view: .front, scale: near, lift: 0, speed: Pace.run),
            .call(onRub),
            .move(to: end, run: false, view: .side, scale: near, lift: 0, speed: Pace.rub),
        ] + walkOff + [.call(onDone)])
    }

    /// Sends the cat off to an activity now (fed: to the bowl; petted too much: away), in the choice's room.
    func send(_ choice: BehaviourChoice) {
        guard let director else { return }
        director.run(steps(to: spot(for: choice), in: choice.room ?? catRoom))
    }

    /// A reaction icon (assets/fx/reactions: heart, zzz, notes, sparkle, question, exclaim, paw) floats up over the cat.
    func react(_ icon: String) {
        guard let cat = director?.cat, let room = cat.parent else { return }
        let path = "fx/reactions/fx_reactions_\(icon).png"
        guard art.has(path) else { return }
        let painted = art.paintedSize(path)
        let width = CGFloat(Tuning.Puppet.reactionWidth)
        let node = SKSpriteNode(
            texture: art.texture(path),
            size: CGSize(width: width, height: width * painted.height / max(painted.width, 1))
        )
        node.position = CGPoint(x: cat.position.x, y: cat.position.y + cat.calculateAccumulatedFrame().height + 10)
        node.zPosition = Layer.atCamera + 1
        node.alpha = 0
        room.addChild(node)
        let seconds = Tuning.Puppet.reactionSeconds
        node.run(.sequence([
            .group([.fadeIn(withDuration: seconds * 0.2), .moveBy(x: 0, y: CGFloat(Tuning.Puppet.reactionRise), duration: seconds)]),
            .fadeOut(withDuration: seconds * 0.3),
            .removeFromParent(),
        ]))
    }

    /// Whether a scene point is on the cat.
    func isOnCat(_ point: CGPoint) -> Bool {
        guard let cat = director?.cat, let room = cat.parent, isShown(room) else { return false }
        let frame = cat.calculateAccumulatedFrame().offsetBy(dx: 0, dy: 0)
        return frame.insetBy(dx: -CGFloat(Tuning.Puppet.tapPadding), dy: -CGFloat(Tuning.Puppet.tapPadding)).contains(convert(
            point,
            to: room
        ))
    }
}
