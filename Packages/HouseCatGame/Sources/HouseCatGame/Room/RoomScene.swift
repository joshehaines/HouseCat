import HouseCatCore
import SpriteKit

/// The home seen as a dollhouse (ASSETS.md §2, SPEC "Rooms"): the room you are in at the centre, the
/// rest of the house laid out around it on the same 2:1 grid (partitions cut down, upper storeys lifted
/// clear above, closed rooms as lit silhouettes with their price), all under the code-drawn sky. The
/// cat lives in the active room; the view settles on that room, follows the cat and pans on a drag.
@MainActor
public final class RoomScene: SKScene {
    public let grid = IsoGrid()
    /// Holds the house in room units; scaled and moved to frame the view.
    public let world = SKNode()
    public let art: ArtLibrary
    public let items: [String: CatalogueFile.Item]
    public private(set) var house: HouseModel
    private(set) var rooms: [RoomID: RoomNode] = [:]
    private let surfaces: [String: CatalogueFile.Surface]
    private let sky = SKSpriteNode()
    /// The cat, once added.
    public internal(set) var director: CatDirector?
    private var lastUpdate: TimeInterval?

    /// Draw order the cat needs across the house.
    enum Layer {
        static let standing = RoomNode.Layer.standing
        static let perDepth = RoomNode.Layer.perDepth
        static let catOverItem = RoomNode.Layer.catOverItem
        /// The cat at the camera draws over everything on its storey.
        static let atCamera: CGFloat = 90000
    }

    public init(size: CGSize, art: ArtLibrary, content: ContentBundle, house: HouseModel) {
        self.art = art
        items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
        self.house = house
        storey = house.storey
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Sky.color(Tuning.Sky.bottom[house.sky])
        sky.texture = Sky.texture(house.sky)
        sky.anchorPoint = .zero
        sky.zPosition = -1_000_000
        addChild(sky)
        addChild(world)
        build()
    }

    /// One room on its own.
    public convenience init(size: CGSize, art: ArtLibrary, content: ContentBundle, model: RoomModel) {
        self.init(size: size, art: art, content: content, house: .single(model))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: The active room

    var activeRoom: RoomNode? {
        rooms[house.active]
    }

    /// The active room's layout.
    public var model: RoomModel {
        activeRoom?.model ?? house.rooms[0].model
    }

    /// The active room's furniture by item id.
    public var furniture: [String: SKSpriteNode] {
        activeRoom?.furniture ?? [:]
    }

    public func scale(for item: CatalogueFile.Item, sprite: String) -> CGFloat {
        activeRoom?.scale(for: item, sprite: sprite) ?? 1
    }

    func footprint(_ item: CatalogueFile.Item, facing: String) -> (w: CGFloat, d: CGFloat) {
        activeRoom?.footprint(item, facing: facing) ?? (1, 1)
    }

    // MARK: Building

    /// The storey on screen: the active room's, or another one visited by the stairs.
    public private(set) var storey = 0

    /// The house's storeys, ground floor first.
    public var storeys: [Int] {
        Array(Set(house.rooms.map(\.storey))).sorted()
    }

    /// Shows another storey (up or down the stairs); the cat stays where it is and comes back with its storey.
    public func showStorey(_ next: Int) {
        guard storeys.contains(next), next != storey else { return }
        setDecorating(false)
        storey = next
        focus = nil
        build()
    }

    private func build() {
        let cat = director?.cat
        cat?.removeFromParent()
        world.removeAllChildren()
        rooms = [:]
        let cells = CGFloat(Tuning.Room.gridWidth)
        buildGround()
        // One storey at a time, standing on the ground; the others are reached by the stairs.
        for room in house.rooms where room.storey == storey {
            let node = RoomNode(
                id: room.id, model: room.model, art: art, items: items, surfaces: surfaces,
                walls: house.walls(of: room), outdoor: room.outdoor
            )
            let origin = grid.floor(CGFloat(room.u), CGFloat(room.v))
            node.position = origin
            // Back to front.
            node.zPosition = CGFloat(room.u + room.v) / cells * CGFloat(Tuning.House.roomBand)
            if let stairs = house.stairs, stairs.room == room.id, stairs.at.count == 2 {
                node.addStairs(at: CGFloat(stairs.at[0]), CGFloat(stairs.at[1]), facing: stairs.facing)
            }
            if let label = room.lockLabel {
                // The label sits on the side nearest the room you are in, so it stays in view.
                let active = house.rooms.first { $0.id == house.active && $0.storey == storey }
                let lean = CGFloat(Tuning.House.labelLean)
                func toward(_ delta: Double) -> CGFloat {
                    cells / 2 + (delta == 0 ? 0 : delta < 0 ? -lean : lean)
                }
                let cell = active.map { (u: toward($0.u - room.u), v: toward($0.v - room.v)) }
                node.veil(label: label, at: cell)
            }
            world.addChild(node)
            rooms[room.id] = node
        }
        if let cat, let room = activeRoom {
            room.addChild(cat)
        }
        fit()
    }

    /// The ground the house stands on, out past the edges of the view (a builder game's base on its field).
    private func buildGround() {
        // Upper storeys hang in the sky: the street is downstairs.
        guard let tile = house.ground, storey == 0 else { return }
        let reach = CGFloat(Tuning.House.groundReach), cells = CGFloat(Tuning.Room.gridWidth)
        let maxU = house.rooms.map { CGFloat($0.u) }.max() ?? 0, maxV = house.rooms.map { CGFloat($0.v) }.max() ?? 0
        let low = -reach, highU = maxU + cells + reach, highV = maxV + cells + reach
        let corners = [grid.floor(low, highV), grid.floor(highU, highV), grid.floor(low, low), grid.floor(highU, low)]
        let left = corners.map(\.x).min() ?? 0, right = corners.map(\.x).max() ?? 0
        let bottom = corners.map(\.y).min() ?? 0, top = corners.map(\.y).max() ?? 0
        let rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        let node = SKSpriteNode(color: .white, size: rect.size)
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        func normal(_ p: CGPoint) -> SIMD2<Float> {
            SIMD2(Float((p.x - rect.minX) / rect.width), Float((p.y - rect.minY) / rect.height))
        }
        node.warpGeometry = SKWarpGeometryGrid(
            columns: 1, rows: 1,
            sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
            destinationPositions: corners.map(normal)
        )
        let shader = SKShader(source: """
        void main() {
            vec4 tile = texture2D(u_tile, fract(v_tex_coord * u_repeat));
            gl_FragColor = vec4(tile.rgb * u_grade, 1.0);
        }
        """)
        let grade = (Tuning.Sky.grade[house.sky] ?? [1, 1, 1]).map { Float($0 * Tuning.House.groundShade) }
        // One painted tile covers two cells, as in the rooms.
        let repeats = SIMD2(Float((highU - low) / 2), Float((highV - low) / 2))
        shader.uniforms = [
            SKUniform(name: "u_tile", texture: art.texture(tile)),
            SKUniform(name: "u_repeat", vectorFloat2: repeats),
            SKUniform(name: "u_grade", vectorFloat3: SIMD3(grade[0], grade[1], grade[2])),
        ]
        node.shader = shader
        node.zPosition = -CGFloat(Tuning.House.storeyBand)
        node.name = "ground"
        world.addChild(node)
    }

    // MARK: Framing

    override public func didChangeSize(_: CGSize) {
        sky.size = size
        fit()
    }

    override public func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 1.0 / 20) } ?? 0
        lastUpdate = currentTime
        director?.update(dt)
        follow(dt)
        idle(dt)
    }

    /// After a while settled, the cat asks the app (and so the behaviour table) what to do next.
    public var nextActivity: (() -> BehaviourChoice?)?
    private var settledFor: TimeInterval = 0

    private func idle(_ dt: TimeInterval) {
        guard let director, director.isIdle, !decorating, storey == house.storey else {
            settledFor = 0
            return
        }
        settledFor += dt
        guard settledFor >= Tuning.Puppet.idleSeconds, let choice = nextActivity?() else { return }
        settledFor = 0
        let spot = spot(for: choice)
        // Already there doing it: stay put.
        if hypot(spot.point.x - director.floorPoint.x, spot.point.y - director.floorPoint.y) < 1, director.cat.pose == spot.pose {
            return
        }
        director.run(steps(to: spot))
    }

    /// Where the view looks, in world units; it follows the cat unless the player has just panned.
    private var focus: CGPoint?
    private var heldUntil: TimeInterval = 0

    /// The active room's frame in the world.
    private var activeBounds: CGRect {
        let bounds = grid.bounds
        // Up the stairs, the room furthest back on that storey stands in for the active one.
        let node = activeRoom ?? house.rooms.filter { $0.storey == storey }.min { $0.u + $0.v < $1.u + $1.v }.flatMap { rooms[$0.id] }
        guard let node else { return bounds }
        return bounds.offsetBy(dx: node.position.x, dy: node.position.y)
    }

    /// Everything in the house, for clamping the pan.
    private var houseBounds: CGRect {
        rooms.values.reduce(CGRect.null) { $0.union(grid.bounds.offsetBy(dx: $1.position.x, dy: $1.position.y)) }
    }

    /// Scales so the active room fills the view's height (Tuning.Stage), centred on it; the rest of the house
    /// fills the sides. On a phone-tall screen the room is zoomed in further and the view follows the cat.
    func fit() {
        let bounds = activeBounds
        // didChangeSize can arrive from super.init, before the house is built.
        guard size.width > 0, size.height > 0, bounds.width > 0, !rooms.isEmpty else { return }
        // On a screen taller than the room, leave room at the sides for the house around it.
        let widthShare = size.height > size.width ? Tuning.House.portraitFitWidth : Tuning.Stage.fitWidth
        var scale = min(size.width * widthShare / bounds.width, size.height * Tuning.Stage.fitHeight / bounds.height)
        if size.height > size.width * CGFloat(Tuning.Stage.portraitZoomAspect) {
            scale = min(scale * Tuning.Stage.portraitZoom, size.height * Tuning.Stage.fitHeight / bounds.height)
        }
        world.setScale(scale)
        look(at: focus ?? CGPoint(x: catWorldPosition?.x ?? bounds.midX, y: bounds.midY))
    }

    /// The cat's position in world units.
    private var catWorldPosition: CGPoint? {
        guard let cat = director?.cat, let room = cat.parent else { return nil }
        return world.convert(cat.position, from: room)
    }

    /// Centres a world point, without panning past the house.
    private func look(at point: CGPoint) {
        let scale = world.xScale, house = houseBounds.insetBy(dx: -CGFloat(Tuning.House.margin), dy: -CGFloat(Tuning.House.margin))
        var target = point
        let halfWidth = size.width / 2 / scale, halfHeight = size.height / 2 / scale
        target.x = house.width > halfWidth * 2 ? min(max(target.x, house.minX + halfWidth), house.maxX - halfWidth) : house.midX
        target.y = house.height > halfHeight * 2 ? min(max(target.y, house.minY + halfHeight), house.maxY - halfHeight) : house.midY
        focus = target
        world.position = CGPoint(x: size.width / 2 - target.x * scale, y: size.height / 2 - target.y * scale)
    }

    private func follow(_ dt: TimeInterval) {
        guard let focus, let cat = catWorldPosition, lastUpdate ?? 0 >= heldUntil else { return }
        let rate = min(1, CGFloat(dt * Tuning.Stage.followRate))
        // Follow across; up and down only as far as keeps the active room centred.
        let target = CGPoint(x: cat.x, y: activeBounds.midY)
        look(at: CGPoint(x: focus.x + (target.x - focus.x) * rate, y: focus.y + (target.y - focus.y) * rate))
    }

    /// Pans the view by a drag, in view points; the view stops following the cat for a while.
    func pan(by delta: CGVector) {
        guard let focus else { return }
        let scale = world.xScale
        look(at: CGPoint(x: focus.x - delta.dx / scale, y: focus.y - delta.dy / scale))
        heldUntil = (lastUpdate ?? 0) + Tuning.House.panHoldSeconds
    }

    /// The scene point of a floor position in the active room.
    public func scenePoint(u: CGFloat, v: CGFloat) -> CGPoint {
        guard let room = activeRoom else { return .zero }
        return room.convert(grid.floor(u, v), to: self)
    }

    // MARK: Touches

    #if os(iOS)
        private var lastTouch: CGPoint?
        private var touchTravel: CGFloat = 0

        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            touchTravel = 0
            if decorating, beginDecorating(touch.location(in: self)) {
                return
            }
            lastTouch = touch.location(in: view)
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            if dragging {
                dragDecorating(to: touch.location(in: self))
                return
            }
            let point = touch.location(in: view)
            if let last = lastTouch {
                touchTravel += hypot(point.x - last.x, point.y - last.y)
                // View points have y down; the world has y up.
                pan(by: CGVector(dx: point.x - last.x, dy: last.y - point.y))
            }
            lastTouch = point
        }

        override public func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            if dragging {
                endDecorating(at: touch.location(in: self))
            } else if !decorating, touchTravel < CGFloat(Tuning.House.tapSlop) {
                let point = touch.location(in: self)
                if isOnGift(point) {
                    onGiftTapped?()
                } else if isOnCat(point) {
                    onCatTapped?()
                } else if let room = closedRoom(at: point) {
                    onClosedRoomTapped?(room)
                }
            }
            lastTouch = nil
        }

        override public func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            if dragging {
                cancelDrag()
            }
            lastTouch = nil
        }
    #endif

    /// The closed room under a scene point, if any (its floor or walls).
    func closedRoom(at point: CGPoint) -> RoomID? {
        for room in house.rooms where room.storey == storey && room.lockLabel != nil {
            guard let node = rooms[room.id], let veil = node.childNode(withName: "veil") as? SKShapeNode else { continue }
            if veil.path?.contains(convert(point, to: node)) == true {
                return room.id
            }
        }
        return nil
    }

    /// Replaces the house (a room opened, a surface changed) and rebuilds it, keeping the cat where it is.
    public func update(house: HouseModel) {
        self.house = house
        setDecorating(false)
        build()
    }

    // MARK: Decorating (RoomScene+Decorate.swift)

    /// Decorate mode is on: touches pick up, drag and drop furniture instead of panning.
    public internal(set) var decorating = false
    var dragging = false
    var selection: Selection? {
        didSet {
            if oldValue?.placementID != selection?.placementID {
                onSelect?(selection?.placementID)
            }
        }
    }

    var grabOffset = CGVector.zero
    var footprintNode: SKShapeNode?
    var decorateGrid: SKShapeNode?
    /// Each change the player makes while decorating, for the app to record.
    public var onDecorate: ((DecorateChange) -> Void)?
    /// The piece picked up (or nil), so the app can show Turn and Store.
    public var onSelect: ((UUID?) -> Void)?
    /// A closed room was tapped: the app offers to open it.
    public var onClosedRoomTapped: ((RoomID) -> Void)?
    /// The cat was tapped: a pet.
    public var onCatTapped: (() -> Void)?
    /// A tap on the gift the cat dropped (RoomScene+Gift.swift).
    public var onGiftTapped: (() -> Void)?
}
