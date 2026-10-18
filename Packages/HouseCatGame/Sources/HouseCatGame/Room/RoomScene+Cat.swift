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
        } else {
            world.addChild(cat)
        }
        let director = CatDirector(cat: cat, grid: grid)
        director.place(at: grid.floor(u, v))
        cat.settle(into: pose, duration: 0)
        self.director = director
        return director
    }

    /// The spot for an activity, given the furniture in the room.
    func spot(for choice: BehaviourChoice) -> CatSpot {
        let pose = choice.pose ?? .sitSide
        if let need = choice.affordance, let placement = model.items.first(where: { items[$0.id]?.affordances.contains(need) == true }),
           let item = items[placement.id], let node = furniture[item.id]
        {
            let (w, d) = footprint(item, facing: placement.facing)
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

    /// Steps that take the cat from where it is to a spot and settle it there.
    func steps(to spot: CatSpot, run: Bool = false) -> [CatDirector.Step] {
        var steps: [CatDirector.Step] = [.rise(.side)]
        steps.append(.move(to: spot.point, run: run, view: .side, scale: 1, lift: 0, speed: run ? Pace.run : Pace.walk))
        if spot.lift > 0 {
            steps.append(.hop(to: spot.lift))
        }
        steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
        steps.append(.settle(spot.pose))
        return steps
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
        director.run([
            .wait(Tuning.Arrival.noticeDelay),
            .rise(.tqfront), // ears up, it has noticed you
            .wait(Tuning.Arrival.noticeHold),
            .move(to: start, run: true, view: .front, scale: near, lift: 0, speed: Pace.run),
            .call(onRub),
            .move(to: end, run: false, view: .side, scale: near, lift: 0, speed: Pace.rub),
            .move(to: spot.point, run: false, view: .side, scale: 1, lift: 0, speed: Pace.walk * CGFloat(Tuning.Arrival.walkOffPace)),
        ] + Array(steps(to: spot).dropFirst(2)) + [.call(onDone)])
    }

    /// Sends the cat off to an activity now (fed: to the bowl; petted too much: away).
    func send(_ choice: BehaviourChoice) {
        guard let director else { return }
        director.run(steps(to: spot(for: choice)))
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
        guard let cat = director?.cat, let room = cat.parent else { return false }
        let frame = cat.calculateAccumulatedFrame().offsetBy(dx: 0, dy: 0)
        return frame.insetBy(dx: -CGFloat(Tuning.Puppet.tapPadding), dy: -CGFloat(Tuning.Puppet.tapPadding)).contains(convert(
            point,
            to: room
        ))
    }
}
