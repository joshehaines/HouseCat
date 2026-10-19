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
    /// In it (a box): hopped into over its front rim, drawn behind its front walls.
    public var inside = false
    /// Scratching it: up on its hind legs facing it (right or left) before it sits down.
    public var scratchFacingRight: Bool?
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
        director.floorDepth = { [weak self] point in self?.catDepth(at: point) ?? 0 }
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

    /// The spot for an activity in a room, given the furniture in it: on the piece, in it, in front of it, on it on
    /// the floor or beside it (CatalogueFile.Item.CatUse), in the piece's own pose (a loaf on the sofa, curled up
    /// on the rug, looking out from the window seat; asleep, always curled up).
    internal func spot(for choice: BehaviourChoice, in room: RoomNode) -> CatSpot {
        let pose = choice.pose ?? .sitSide
        let model = room.model
        if let need = choice.affordance, let placement = piece(for: choice, need: need, in: room),
           let item = items[placement.id], let node = room.furniture[item.id]
        {
            // Where the piece is drawn (smaller than its cells); it is jumped up to from in front of its cells.
            let (u, v, w, d) = room.stand(item, placement)
            let cells = room.footprint(item, facing: placement.facing)
            let front = (u: CGFloat(placement.u), v: CGFloat(placement.v), w: cells.w, d: cells.d)
            let middle = grid.floor(u + w / 2, v + d / 2)
            if choice.activity == .scratch {
                return scratchSpot(at: item, node: node, u, v, w, d, in: room)
            }
            let own = choice.activity == .sleep || choice.use != nil ? pose : item.catPose ?? pose
            var use = item.use(for: need)
            if use == .inside, item.rim?[placement.facing] == nil {
                use = .beside
            }
            switch use {
            case .on:
                // On top: the middle of the footprint, raised to the seat (or the top for a perch), jumped up to
                // from the floor in front.
                let seat = CGFloat(need == .perch ? Tuning.Puppet.perchHeight : Tuning.Puppet.seatHeight)
                return CatSpot(
                    point: middle,
                    lift: node.size.height * seat,
                    pose: own,
                    perchDepth: node.zPosition + 1,
                    itemID: item.id,
                    approach: approach(toFootprint: front.u, front.v, front.w, front.d, in: room)
                )
            case .inside:
                // In it, on its floor, between its back and its front.
                return CatSpot(
                    point: middle, lift: 0, pose: own, perchDepth: node.zPosition + Self.insideDepth, itemID: item.id,
                    approach: approach(toFootprint: front.u, front.v, front.w, front.d, in: room), inside: true
                )
            case .front:
                // On the floor in front of the side it faces (a piece facing L faces along u, else along v): before
                // the fire, curled up in its warmth; at the mirror or the bird table, looking.
                let gap = CGFloat(Tuning.Puppet.jumpFrom)
                let before = placement.facing == "L" ? grid.floor(u + w + gap, v + d / 2) : grid.floor(u + w / 2, v + d + gap)
                return CatSpot(point: before, lift: 0, pose: own, perchDepth: nil, itemID: item.id)
            case .floor:
                return CatSpot(point: middle, lift: 0, pose: own, perchDepth: nil, itemID: item.id)
            case .beside:
                let beside = grid.floor(u + w + CGFloat(Tuning.Puppet.besideGap), v + d / 2 + CGFloat(Tuning.Puppet.besideForward))
                return CatSpot(point: beside, lift: 0, pose: own, perchDepth: nil, itemID: item.id)
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
        let open = candidates.filter { floorIsClear($0, in: room) }
        let cat = director.map { grid.cell(at: $0.floorPoint) }.map { CGPoint(x: $0.u, y: $0.v) }
        let best = (open.isEmpty ? candidates : open).min { a, b in
            guard let cat else { return false }
            return hypot(a.x - cat.x, a.y - cat.y) < hypot(b.x - cat.x, b.y - cat.y)
        } ?? candidates[0]
        return grid.floor(min(max(best.x, edge), n - edge), min(max(best.y, edge), n - edge))
    }

    /// Whether a floor cell is inside the room and clear of the furniture standing on the floor (rugs are fine).
    internal func floorIsClear(_ c: CGPoint, in room: RoomNode, edge: CGFloat = 0.4) -> Bool {
        let n = grid.cells
        guard c.x > edge, c.y > edge, c.x < n - edge, c.y < n - edge else { return false }
        return !room.model.items.contains { placement in
            guard let item = items[placement.id], item.layer != .wall, !item.decal else { return false }
            let (pw, pd) = room.footprint(item, facing: placement.facing)
            return c.x >= CGFloat(placement.u) && c.x <= CGFloat(placement.u) + pw && c.y >= CGFloat(placement.v) && c.y <= CGFloat(placement.v) + pd
        }
    }

    /// The cat's draw order on the floor of its room: by its depth, and over anything it is in front of along either
    /// side (a long sofa sorts by its front corner, so a cat just in front of its middle would draw behind it).
    internal func catDepth(at point: CGPoint) -> CGFloat {
        let (cu, cv) = grid.cell(at: point)
        var z = Layer.standing + grid.depth(cu, cv) * Layer.perDepth + Layer.catOverItem
        guard let room = rooms[catRoom] else { return z }
        for placement in room.model.items {
            guard let item = items[placement.id], item.layer != .wall, !item.decal, let node = room.furniture[placement.id] else { continue }
            let (w, d) = room.footprint(item, facing: placement.facing)
            let u = CGFloat(placement.u), v = CGFloat(placement.v)
            let inFront = (cu >= u + w && cv > v - 0.5 && cv < v + d + 1.5) || (cv >= v + d && cu > u - 0.5 && cu < u + w + 1.5)
            if inFront {
                z = max(z, node.zPosition + Layer.catOverItem)
            }
        }
        return z
    }

    /// The pieces in a room for something, in the layout's order.
    private func fits(_ need: Affordance, in room: RoomNode) -> [RoomModel.Placement] {
        room.model.items.filter { items[$0.id]?.affordances.contains(need) == true && room.furniture[$0.id] != nil }
    }

    /// The piece in a room the cat uses for something: the one the choice names if it is there, else the one it last
    /// went to for it (`pin`), else the first.
    internal func piece(for choice: BehaviourChoice, need: Affordance, in room: RoomNode) -> RoomModel.Placement? {
        let fits = fits(need, in: room)
        let named = choice.item ?? piecesUsed["\(room.id.rawValue)/\(need.rawValue)"]
        return fits.first { $0.id == named } ?? fits.first
    }

    /// A choice made for good: the piece it goes to is settled (the next one along from last time, turn and turn
    /// about: the rug, then the fire), so where it heads and where it settles are the same piece.
    internal func pin(_ choice: BehaviourChoice, in room: RoomNode) -> BehaviourChoice {
        guard let need = choice.affordance else { return choice }
        let key = "\(room.id.rawValue)/\(need.rawValue)"
        var choice = choice
        let fits = fits(need, in: room)
        if choice.item == nil, !fits.isEmpty {
            if let last = piecesUsed[key], let at = fits.firstIndex(where: { $0.id == last }) {
                choice.item = fits[(at + 1) % fits.count].id
            } else {
                choice.item = fits[0].id
            }
        }
        if let id = choice.item {
            piecesUsed[key] = id
        }
        return choice
    }

    /// The biggest seat in a room (the sofa, where the cat waits for you).
    internal func biggestSeat(in room: RoomNode) -> String? {
        room.model.items
            .compactMap { placement in items[placement.id].map { (placement.id, $0) } }
            .filter { $0.1.affordances.contains(.sit) && room.furniture[$0.0] != nil }
            .max { $0.1.footprint.w * $0.1.footprint.d < $1.1.footprint.w * $1.1.footprint.d }?.0
    }

    /// Scratching: on the floor beside it (a post: level with its middle on whichever side is clear, a reach away;
    /// anything else: by its end), facing it, drawn over it.
    internal func scratchSpot(
        at item: CatalogueFile.Item, node: SKSpriteNode, _ u: CGFloat, _ v: CGFloat, _ w: CGFloat, _ d: CGFloat, in room: RoomNode
    ) -> CatSpot {
        var point: CGPoint
        if item.affordances.contains(.scratch) {
            let height = director?.cat.height ?? CGFloat(model.catHeight)
            let a = height * CGFloat(Tuning.Puppet.scratchStandOff) / (2 * grid.cellHalfWidth)
            let f = CGFloat(Tuning.Puppet.besideForward) / 2
            let cu = u + w / 2, cv = v + d / 2
            let right = CGPoint(x: cu + a + f, y: cv - a + f), left = CGPoint(x: cu - a + f, y: cv + a + f)
            // The side towards the middle of the room first, if it is clear.
            let sides = node.position.x < 0 ? [right, left] : [left, right]
            let cell = sides.first { floorIsClear($0, in: room) } ?? sides[0]
            point = grid.floor(cell.x, cell.y)
        } else {
            point = grid.floor(u + w + CGFloat(Tuning.Puppet.besideGap), v + d / 2 + CGFloat(Tuning.Puppet.besideForward))
        }
        return CatSpot(
            point: point, lift: 0, pose: .sitSide, perchDepth: node.zPosition + Layer.catOverItem, itemID: item.id,
            scratchFacingRight: node.position.x > point.x
        )
    }

    /// The cat in a box draws between its back (the box) and its front (drawn again over the cat).
    static let insideDepth: CGFloat = 0.2
    static let boxFrontDepth: CGFloat = 0.4

    /// Where the cat stands on a box's front rim, hopping in or out: its front corner, at the rim's height.
    internal func rimStand(of id: String, in room: RoomNode) -> (point: CGPoint, lift: CGFloat, depth: CGFloat)? {
        guard let placement = room.model.items.first(where: { $0.id == id }), let item = items[id], let node = room.furniture[id],
              let rim = item.rim?[placement.facing], let low = rim.map({ $0[1] }).max() else { return nil }
        let at = room.stand(item, placement)
        return (grid.floor(at.u + at.w, at.v + at.d), node.size.height * CGFloat(1 - low), node.zPosition + 1)
    }

    /// Into a box: up onto its front rim, then down inside, its front drawn over the cat.
    internal func climbIn(_ spot: CatSpot, room: RoomID) -> [CatDirector.Step] {
        guard let id = spot.itemID, let node = rooms[room], let stand = rimStand(of: id, in: node) else {
            return [.move(to: spot.point, pace: .walk)]
        }
        return [
            .move(to: spot.approach ?? stand.point, pace: .walk),
            .call { [weak self] in self?.director?.perchDepth = stand.depth },
            .hop(to: stand.point, lift: stand.lift),
            .call { [weak self] in self?.settleIn(id, room: room) },
            .hop(to: spot.point, lift: 0),
        ]
    }

    /// The cat is in a box: drawn behind its front, which is drawn again over it.
    internal func settleIn(_ id: String, room: RoomID) {
        guard let director, let roomNode = rooms[room], let node = roomNode.furniture[id] else { return }
        director.insideItem = id
        director.perchDepth = node.zPosition + Self.insideDepth
        guard node.childNode(withName: "boxFront") == nil, let item = items[id],
              let placement = roomNode.model.items.first(where: { $0.id == id }), let rim = item.rim?[placement.facing],
              let texture = node.texture else { return }
        let w = node.size.width, h = node.size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w / 2 - 2, y: -2))
        for p in rim where p.count == 2 {
            path.addLine(to: CGPoint(x: (CGFloat(p[0]) - 0.5) * w, y: (1 - CGFloat(p[1])) * h))
        }
        path.addLine(to: CGPoint(x: w / 2 + 2, y: -2))
        path.closeSubpath()
        let mask = SKShapeNode(path: path)
        mask.fillColor = .white
        mask.strokeColor = .clear
        let crop = SKCropNode()
        crop.maskNode = mask
        let front = SKSpriteNode(texture: texture, size: node.size)
        front.anchorPoint = node.anchorPoint
        crop.addChild(front)
        crop.zPosition = Self.boxFrontDepth
        crop.name = "boxFront"
        node.addChild(crop)
    }

    /// Out of the box: its front no longer drawn over the cat.
    internal func climbOut() {
        guard let director, let id = director.insideItem else { return }
        director.insideItem = nil
        for room in rooms.values {
            room.furniture[id]?.childNode(withName: "boxFront")?.removeFromParent()
        }
    }

    /// Off what it is on (or out of what it is in) to the floor in front, first.
    internal func getDown() -> [CatDirector.Step] {
        guard let director else { return [] }
        let ground = groundInFront(of: director.floorPoint)
        if let id = director.insideItem {
            guard let room = rooms[catRoom], let stand = rimStand(of: id, in: room) else {
                return [.call { [weak self] in self?.climbOut() }, .hop(to: ground, lift: 0), .call { [weak self] in self?.director?.perchDepth = nil }]
            }
            return [
                .hop(to: stand.point, lift: stand.lift),
                .call { [weak self] in
                    self?.climbOut()
                    self?.director?.perchDepth = stand.depth
                },
                .hop(to: grid.floor(grid.cell(at: stand.point).u + CGFloat(Tuning.Puppet.jumpFrom) * 0.6, grid.cell(at: stand.point).v + CGFloat(Tuning.Puppet.jumpFrom) * 0.6), lift: 0),
                .call { [weak self] in self?.director?.perchDepth = nil },
            ]
        }
        guard director.lift > 0 else { return [] }
        return [.hop(to: ground, lift: 0), .call { [weak self] in self?.director?.perchDepth = nil }]
    }

    /// Furniture moved, turned or put away in the cat's room while the cat was up on something: when nothing
    /// is under it any more, it gets up and hops down where it is (a present it left up there drops with it).
    internal func catGetsDown(in room: RoomNode) {
        guard let director, director.lift > 0 || director.insideItem != nil, director.cat.parent === room else { return }
        let (cu, cv) = grid.cell(at: director.floorPoint)
        let underneath = room.model.items.contains { placement in
            guard let item = items[placement.id], item.layer != .wall, !item.decal else { return false }
            let (w, d) = room.footprint(item, facing: placement.facing)
            return cu >= CGFloat(placement.u) && cu <= CGFloat(placement.u) + w && cv >= CGFloat(placement.v) && cv <= CGFloat(placement.v) + d
        }
        if underneath, let id = director.insideItem {
            // Still in its box (moved with it, or something else moved): its front over the cat again.
            settleIn(id, room: room.id)
            return
        }
        guard !underneath else { return }
        climbOut()
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
        steps += getDown()
        steps += route(to: room ?? catRoom, pace: pace)
        if spot.inside {
            steps += climbIn(spot, room: room ?? catRoom)
        } else if spot.lift > 0 {
            steps.append(.move(to: spot.approach ?? spot.point, pace: pace))
            steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
            steps.append(.hop(to: spot.point, lift: spot.lift))
        } else {
            steps.append(.move(to: spot.point, pace: pace))
            steps.append(.call { [weak self] in self?.director?.perchDepth = spot.perchDepth })
        }
        if let right = spot.scratchFacingRight {
            // Up on its hind legs at it, raking, the piece rocking under its claws.
            let id = spot.itemID, target = room ?? catRoom
            steps += [
                .face(.side, right: right),
                .call { [weak self] in
                    if let self, let id, let node = self.rooms[target]?.furniture[id] {
                        self.scratched(node, for: Tuning.Puppet.scratchSeconds)
                    }
                },
                .scratch(Tuning.Puppet.scratchSeconds),
            ]
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

    /// Puts the cat where it was when you came in (`BehaviourTable.resting`): settled at the activity's spot in its
    /// room, on the furniture if that is where, and the view on that room.
    func placeCat(for choice: BehaviourChoice) {
        guard let director, let room = rooms[choice.room ?? catRoom] else { return }
        var choice = choice
        if choice.activity == .sit, choice.item == nil {
            // Sitting up waiting for you: on the sofa, if there is one.
            choice.item = biggestSeat(in: room)
        }
        choice = pin(choice, in: room)
        var spot = spot(for: choice, in: room)
        spot.pose = Self.variety(spot.pose)
        director.cat.removeFromParent()
        room.addChild(director.cat)
        catRoom = room.id
        director.perchDepth = spot.perchDepth
        director.place(at: spot.point, lift: spot.lift)
        if spot.inside, let id = spot.itemID {
            settleIn(id, room: room.id)
        }
        director.cat.settle(into: spot.pose, duration: 0)
        startIn(room: room.id)
        beganActivity(choice.activity)
    }

    /// The arrival (CLAUDE.md "The arrival in the room view is live", SPEC "The session loop" 3): the cat greets
    /// you in its own way (`GreetingStyle`), then goes off to what the behaviour table chose. One that comes to you
    /// notices you, comes to the front of its room while the camera leans in and rubs along it (`onRub`); one that
    /// does not looks up, or lifts its head from its sleep, or keeps its back to you. `onDone` when it is settled.
    func playArrival(
        _ style: GreetingStyle = .runs,
        then choice: BehaviourChoice,
        onRub: @escaping @MainActor () -> Void,
        onDone: @escaping @MainActor () -> Void
    ) {
        guard let director else { return }
        let a = Tuning.Arrival.self
        let from = grid.floor(CGFloat(a.rubFrom[0]), CGFloat(a.rubFrom[1])), to = grid.floor(CGFloat(a.rubTo[0]), CGFloat(a.rubTo[1]))
        let room = choice.room ?? catRoom
        let choice = rooms[room].map { pin(choice, in: $0) } ?? choice
        let spot = (rooms[room] ?? activeRoom).map { self.spot(for: choice, in: $0) } ?? self.spot(for: choice)
        let lean: CatDirector.Step = .call { [weak self] in self?.lookCloser(for: a.greetCloseUpSeconds) }
        let pose = director.cat.pose
        var steps: [CatDirector.Step] = [.wait(a.noticeDelay)]
        // Off what it is on (or out of what it is in), first.
        func down() -> [CatDirector.Step] {
            getDown()
        }
        /// After the greeting: off to what the table chose, or (one that stayed put, not hungry) where it is.
        func then(going: Bool) -> [CatDirector.Step] {
            guard going else { return [] }
            return self.steps(to: spot, in: room) + extras(for: choice)
        }
        let hungry = choice.activity == .bowlNag
        switch style {
        case .runs, .walks:
            if pose == .sleepCurl {
                steps += [.glance(.stretchSide), .wait(Tuning.Puppet.stretchSeconds)]
            }
            steps += [.rise(.tqfront), .wait(a.noticeHold)] + down() + [
                lean,
                .move(to: from, pace: style == .runs ? .run : .walk),
                .call(onRub),
                .move(to: to, pace: .stroll),
            ] + then(going: true).filter { step in
                if case .rise = step { return false }
                return true
            }
            beganActivity(choice.activity)
        case .ambush:
            // Crouched by its hiding place a moment, then out at you at a dash, with a pounce at the end.
            steps += [.wait(a.ambushWait), .rise(.tqfront), .call { [weak self] in self?.director?.cat.squash(CGFloat(Tuning.Puppet.squash) * 1.6) },
                      .wait(Tuning.Puppet.crouchSeconds)] + down() + [
                lean,
                .move(to: from, pace: .dash),
                .hop(to: from, lift: 0),
                .call { [weak self] in self?.react("exclaim") },
                .call(onRub),
                .move(to: to, pace: .stroll),
            ] + then(going: true).filter { step in
                if case .rise = step { return false }
                return true
            }
            beganActivity(choice.activity)
        case .glances:
            // A look up, a slow blink, and back to what it was doing (unless the bowl is empty).
            let turned = Self.towardsYou(pose)
            steps += [.call { [weak self] in self?.lookCloser(for: a.greetCloseUpSeconds * 0.6) }]
            if let turned, let pose, turned != pose {
                steps += [.glance(turned), .call { [weak director] in director?.cat.blink(slow: true) }, .wait(a.glanceHold), .glance(pose)]
            } else {
                steps += [.call { [weak director] in director?.cat.blink(slow: true) }, .wait(a.glanceHold)]
            }
            steps += then(going: hungry)
            if hungry {
                beganActivity(choice.activity)
            }
        case .dozes:
            // Asleep: the head comes up, a slow blink, and down again (it gets up only for an empty bowl).
            steps += [.call { [weak self] in self?.lookCloser(for: a.greetCloseUpSeconds * 0.6) }]
            if pose == .sleepCurl {
                steps += [.glance(.loafThreeQuarterFront), .call { [weak director] in director?.cat.blink(slow: true) },
                          .wait(a.glanceHold), .glance(.sleepCurl)]
            } else if let pose, let turned = Self.towardsYou(pose) {
                steps += [.glance(turned), .wait(a.glanceHold), .glance(pose)]
            }
            steps += then(going: hungry)
            if hungry {
                beganActivity(choice.activity)
            }
        case .ignores:
            // Sulking: straight off to sulk, its back to you.
            steps += then(going: true)
            beganActivity(choice.activity)
        }
        director.run(steps + [.call(onDone)])
    }

    /// The painting of the same pose turned towards you (a glance), if there is one.
    static func towardsYou(_ pose: CatPose?) -> CatPose? {
        switch pose {
        case .sitSide, .sitBack: .sitThreeQuarterFront
        case .loafSide: .loafThreeQuarterFront
        case .sitThreeQuarterFront, .loafThreeQuarterFront, .sitFront: pose
        case .sleepCurl: .loafThreeQuarterFront
        case .stretchSide, nil: nil
        }
    }

    /// A wander: a few clear spots about a room (this one or the next), a pause and a look round at each, and a
    /// sit at the last.
    internal func explore(in target: RoomID) -> [CatDirector.Step] {
        guard let director, let room = rooms[target] else { return [] }
        var steps: [CatDirector.Step] = []
        if director.cat.pose == .sleepCurl {
            steps += [.glance(.stretchSide), .wait(Tuning.Puppet.stretchSeconds)]
        }
        steps.append(.rise(director.cat.view))
        steps += getDown()
        steps += route(to: target, pace: .stroll)
        let n = grid.cells, stops = Int.random(in: Tuning.Puppet.exploreStops[0] ... Tuning.Puppet.exploreStops[1])
        for i in 0 ..< stops {
            var cell = CGPoint(x: CGFloat.random(in: 1.2 ... n - 1.2), y: CGFloat.random(in: 1.2 ... n - 1.2))
            for _ in 0 ..< 10 where !floorIsClear(cell, in: room, edge: 1) {
                cell = CGPoint(x: CGFloat.random(in: 1.2 ... n - 1.2), y: CGFloat.random(in: 1.2 ... n - 1.2))
            }
            steps.append(.move(to: grid.floor(cell.x, cell.y), pace: .stroll))
            steps.append(.wait(TimeInterval.random(in: Tuning.Puppet.explorePause[0] ... Tuning.Puppet.explorePause[1])))
            if i == stops - 1 {
                steps.append(.settle([.sitSide, .sitThreeQuarterFront, .loafSide].randomElement() ?? .sitSide))
            }
        }
        return steps
    }

    /// Sends the cat off to an activity now (fed: to the bowl; petted too much: away), in the choice's room.
    func send(_ choice: BehaviourChoice, pace: CatDirector.Pace? = nil) {
        guard let director else { return }
        let choice = rooms[choice.room ?? catRoom].map { pin(choice, in: $0) } ?? choice
        let pace = pace ?? (choice.activity == .bowlNag ? .trot : .walk)
        if choice.activity == .zoomies {
            director.run(zoomies())
        } else if choice.activity == .explore {
            director.run(explore(in: choice.room ?? catRoom))
        } else {
            director.run(steps(to: spot(for: choice), in: choice.room ?? catRoom, pace: pace) + extras(for: choice))
        }
        beganActivity(choice.activity)
    }

    /// What an activity adds once the cat is there: knocking at the thing it sits by, scratching the post.
    internal func extras(for choice: BehaviourChoice) -> [CatDirector.Step] {
        guard choice.activity == .knockOff, let room = rooms[choice.room ?? catRoom],
              let id = spot(for: choice, in: room).itemID, let node = room.furniture[id] else { return [] }
        func rock() -> CatDirector.Step {
            .call { [weak self, weak node] in
                if let node {
                    self?.wobble(node)
                }
            }
        }
        return [.wait(1.2), rock(), .wait(0.9), rock(), .wait(0.5), .call { [weak self] in self?.react("exclaim") }]
    }

    /// A piece rocks under the cat's claws while it scratches, a stroke at a time.
    internal func scratched(_ node: SKNode, for seconds: TimeInterval) {
        let angle = CGFloat(Tuning.Puppet.wobbleDegrees) * 0.6 * .pi / 180
        let beat = 1 / Tuning.Puppet.scratchHz
        let stroke = SKAction.sequence([
            .rotate(toAngle: angle, duration: beat * 0.25),
            .rotate(toAngle: -angle * 0.5, duration: beat * 0.35),
            .rotate(toAngle: 0, duration: beat * 0.4),
        ])
        node.run(.sequence([
            .wait(forDuration: Tuning.Puppet.scratchRiseSeconds),
            .repeat(stroke, count: max(1, Int((seconds - Tuning.Puppet.scratchRiseSeconds) / beat))),
        ]), withKey: "wobble")
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
        var steps: [CatDirector.Step] = [.rise(director.cat.view)] + getDown()
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

    /// A thought bubble over the cat with a picture in it (what it would love), popping up, bobbing a little and
    /// fading after a while; a tap on it calls `onThoughtTapped` with its tag. It moves with the cat.
    func think(about sprite: String, tag: String, for seconds: TimeInterval = Tuning.Wellbeing.bubbleSeconds) {
        guard let cat = director?.cat, art.has(sprite) else { return }
        cat.childNode(withName: "thought")?.removeFromParent()
        let size = CGFloat(Tuning.Wellbeing.bubbleSize)
        let bubble = SKNode()
        bubble.name = "thought"
        bubble.userData = ["tag": tag]
        let paper = SKColor(red: 0.995, green: 0.97, blue: 0.925, alpha: 0.97)
        let ink = SKColor(red: 0.24, green: 0.18, blue: 0.22, alpha: 0.35)
        func puff(_ rect: CGRect, corner: CGFloat) -> SKShapeNode {
            let node = SKShapeNode(rect: rect, cornerRadius: corner)
            node.fillColor = paper
            node.strokeColor = ink
            node.lineWidth = 3
            return node
        }
        bubble.addChild(puff(CGRect(x: -size / 2, y: -size * 0.41, width: size, height: size * 0.82), corner: size * 0.32))
        for (x, y, r) in [(-0.2, -0.56, 0.085), (-0.31, -0.73, 0.05)] {
            let dot = SKShapeNode(circleOfRadius: size * CGFloat(r))
            dot.fillColor = paper
            dot.strokeColor = ink
            dot.lineWidth = 2.5
            dot.position = CGPoint(x: size * CGFloat(x), y: size * CGFloat(y))
            bubble.addChild(dot)
        }
        let painted = art.paintedSize(sprite)
        let fit = size * 0.66 / max(1, max(painted.width, painted.height * 1.2))
        let picture = SKSpriteNode(texture: art.texture(sprite), size: CGSize(width: painted.width * fit, height: painted.height * fit))
        picture.zPosition = 1
        bubble.addChild(picture)
        let top = cat.bodyFrame.maxY - cat.position.y
        bubble.position = CGPoint(x: size * 0.42, y: top + size * 0.62)
        bubble.zPosition = Layer.reaction
        bubble.setScale(0.2)
        bubble.alpha = 0
        cat.addChild(bubble)
        let pop = SKAction.sequence([.scale(to: 1.08, duration: 0.18), .scale(to: 1, duration: 0.1)])
        pop.timingMode = .easeOut
        let bob = SKAction.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.9), .moveBy(x: 0, y: -5, duration: 0.9)]))
        bubble.run(.group([.fadeIn(withDuration: 0.15), pop, bob]))
        bubble.run(.sequence([.wait(forDuration: seconds), .fadeOut(withDuration: 0.3), .removeFromParent()]), withKey: "life")
    }

    /// The tag of the thought bubble under a scene point, if there is one.
    func thought(at point: CGPoint) -> String? {
        guard let cat = director?.cat, let bubble = cat.childNode(withName: "thought"), let room = cat.parent, isShown(room) else { return nil }
        let local = convert(point, to: bubble)
        let size = CGFloat(Tuning.Wellbeing.bubbleSize)
        guard CGRect(x: -size * 0.6, y: -size * 0.8, width: size * 1.2, height: size * 1.3).contains(local) else { return nil }
        return bubble.userData?["tag"] as? String
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
