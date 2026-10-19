import HouseCatCore
import SpriteKit

/// The home seen as a dollhouse (ASSETS.md §2, SPEC "Rooms"): the room you are in at the centre, the
/// rest of the house laid out around it on the same 2:1 grid (partitions cut down with a doorway in each,
/// one storey at a time, closed rooms as lit silhouettes with their price), all under the code-drawn sky.
/// The active room is the one you are in (tap another open room to go there; decorating acts on it); the
/// cat has its own room and walks between rooms through the doorways, up and down the stairs out of sight.
/// The view settles on the active room, follows the cat and pans on a drag.
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
    /// The room the cat is in (its node holds the cat, on screen or not).
    public internal(set) var catRoom: RoomID
    var lastUpdate: TimeInterval?
    /// When the player last picked a room: the view stays there a while rather than following the cat.
    var roomChosenAt: TimeInterval = -.infinity
    /// What the cat is doing (the last activity sent), how long it has been settled at it, how long it stays, and
    /// when it next fidgets (RoomScene+Cat.swift).
    public internal(set) var catActivity: Activity?
    var settledFor: TimeInterval = 0
    var holdFor: TimeInterval = Tuning.Puppet.idleSeconds
    var nextFidget: TimeInterval = 8
    /// The cat is glancing about where it sits (not off to something new).
    var fidgeting = false
    /// The piece the cat last went to in each room for each use ("living/sleep": the rug); the next time it goes for
    /// that it takes the next one (the fire), turn and turn about.
    var piecesUsed: [String: String] = [:]

    /// Draw order the cat needs across the house.
    enum Layer {
        static let standing = RoomNode.Layer.standing
        static let perDepth = RoomNode.Layer.perDepth
        static let catOverItem = RoomNode.Layer.catOverItem
        /// Reaction icons draw over everything on the cat's storey.
        static let reaction: CGFloat = 90000
    }

    public init(size: CGSize, art: ArtLibrary, content: ContentBundle, house: HouseModel) {
        self.art = art
        items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
        self.house = house
        storey = house.storey
        catRoom = house.active
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
        attachStorey()
    }

    /// Goes to another room: the view glides to it (or moves to its storey) and decorating acts on it.
    public func show(room id: RoomID) {
        guard let room = house.room(id), room.lockLabel == nil else { return }
        setDecorating(false)
        house.active = id
        roomChosenAt = lastUpdate ?? 0
        // A drag a moment ago no longer holds the view.
        heldUntil = 0
        if room.storey != storey {
            focus = nil
            storey = room.storey
            attachStorey()
        } else if focus == nil {
            fit()
        }
    }

    /// The view starts on the room the cat is in when you come home (not a pick of yours: it follows the cat on).
    func startIn(room id: RoomID) {
        guard id != house.active, let room = house.room(id), room.lockLabel == nil else { return }
        house.active = id
        focus = nil
        if room.storey != storey {
            storey = room.storey
            attachStorey()
        } else {
            fit()
        }
    }

    /// The active room changed without the player picking it (the view followed the cat).
    public var onActiveRoomChanged: ((RoomID) -> Void)?
    /// A tap on an open room other than the one you are in.
    public var onRoomTapped: ((RoomID) -> Void)?

    /// The cat went through a doorway or up the stairs; unless you are decorating or picked a room a moment
    /// ago, the view goes with it.
    func catEntered(_ id: RoomID) {
        let from = catRoom
        catRoom = id
        guard !decorating, from == house.active, (lastUpdate ?? 0) - roomChosenAt > Tuning.House.roomHoldSeconds,
              let room = house.room(id) else { return }
        house.active = id
        if room.storey != storey {
            storey = room.storey
            focus = nil
            attachStorey()
        }
        onActiveRoomChanged?(id)
    }

    /// Every room's node, built once; a storey's are put in the world when it is shown.
    private func build() {
        let cat = director?.cat
        cat?.removeFromParent()
        for node in rooms.values {
            node.removeFromParent()
        }
        rooms = [:]
        let cells = CGFloat(Tuning.Room.gridWidth)
        for room in house.rooms {
            let node = RoomNode(
                id: room.id, model: room.model, art: art, items: items, surfaces: surfaces,
                walls: house.walls(of: room), outdoor: room.outdoor, doorways: house.doorways(of: room)
            )
            let origin = grid.floor(CGFloat(room.u), CGFloat(room.v))
            node.position = origin
            // Back to front.
            node.zPosition = CGFloat(room.u + room.v) / cells * CGFloat(Tuning.House.roomBand)
            if let stairs = house.stairs, stairs.room == room.id, stairs.at.count == 2 {
                node.addStairs(at: CGFloat(stairs.at[0]), CGFloat(stairs.at[1]), facing: stairs.facing)
            }
            if let label = room.lockLabel {
                // The badge sits towards the room you are in, near the back of the closed room, so it stays
                // in view and clear of the controls along the bottom of the screen.
                let active = house.rooms.first { $0.id == house.active && $0.storey == room.storey }
                let lean = CGFloat(Tuning.House.labelLean), back = CGFloat(Tuning.House.labelBack)
                func toward(_ delta: Double) -> CGFloat {
                    delta == 0 ? back : delta < 0 ? cells / 2 - lean : cells / 2 + lean
                }
                let cell = active.map { (u: toward($0.u - room.u), v: toward($0.v - room.v)) }
                node.veil(label: label, at: cell)
            }
            rooms[room.id] = node
        }
        if let cat, let room = rooms[catRoom] ?? activeRoom {
            room.addChild(cat)
        }
        attachStorey()
    }

    /// Puts the shown storey's rooms (and the ground, downstairs) in the world.
    private func attachStorey() {
        for node in rooms.values {
            node.removeFromParent()
        }
        world.removeAllChildren()
        buildGround()
        for room in house.rooms where room.storey == storey {
            if let node = rooms[room.id] {
                world.addChild(node)
            }
        }
        fit()
    }

    /// Whether a room is on the storey on screen.
    func isShown(_ node: SKNode?) -> Bool {
        node?.parent === world
    }

    /// The rooms on the storey on screen.
    var shownRooms: [RoomID] {
        rooms.filter { isShown($0.value) }.map(\.key)
    }

    /// The ground the house stands on, out past the edges of the view (a builder game's base on its field), on
    /// every storey, with the scenery of the home's place round it.
    private func buildGround() {
        buildScenery()
        guard let tile = house.ground else { return }
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

    /// The trees, bushes and stones round the plot (Josh, 18 Oct: the outside as the place the player picked),
    /// each standing on its cell with a soft shadow, in the sky's light. Those behind the house draw under the
    /// rooms, the low ones in front over them.
    private func buildScenery() {
        let rgb = Tuning.Sky.grade[house.sky] ?? [1, 1, 1]
        let grade = SKColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        let band = CGFloat(Tuning.House.storeyBand) / 2
        let sway = swayShaders(grade: grade)
        for piece in house.scenery {
            let texture = art.texture(piece.sprite)
            let painted = art.paintedSize(piece.sprite)
            guard painted.width > 0 else { continue }
            let width = CGFloat(piece.width) * grid.cellHalfWidth * 2
            let height = width * painted.height / painted.width
            let node = SKSpriteNode(texture: texture, size: CGSize(width: width, height: height))
            node.anchorPoint = CGPoint(x: 0.5, y: CGFloat(Tuning.Outdoors.baseLift))
            node.position = grid.floor(CGFloat(piece.u), CGFloat(piece.v))
            node.color = grade
            node.colorBlendFactor = 1
            let depth = grid.depth(CGFloat(piece.u), CGFloat(piece.v))
            node.zPosition = (piece.behind ? -band : band) + depth
            node.name = "scenery"
            let shadowWidth = width * CGFloat(piece.tall ? Tuning.Outdoors.shadowWidthTall : Tuning.Outdoors.shadowWidth)
            let shadow = SKShapeNode(ellipseOf: CGSize(width: shadowWidth, height: shadowWidth / 2))
            shadow.fillColor = SKColor(white: 0, alpha: CGFloat(Tuning.Outdoors.shadowAlpha))
            shadow.strokeColor = .clear
            shadow.position = .zero
            shadow.zPosition = -1
            node.addChild(shadow)
            world.addChild(node)
            bringToLife(node, piece: piece, shaders: sway)
        }
        startSkyLife()
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
        ease(dt)
        follow(dt)
        idle(dt)
    }

    /// After a while at something (how long depends on what: a sleep is long, a sit short), the cat asks the app
    /// (and so the behaviour table) what to do next, saying which room it is in; the choice says which room it
    /// happens in. In between it fidgets: glances, slow blinks, a stretch.
    public var nextActivity: ((RoomID) -> BehaviourChoice?)?
    /// The cat has set off to something new by itself (for a line about it).
    public var onActivityChosen: ((BehaviourChoice) -> Void)?
    /// A tap on the cat's thought bubble, with its tag (the piece it would love).
    public var onThoughtTapped: ((String) -> Void)?

    private func idle(_ dt: TimeInterval) {
        guard let director, !decorating else { return }
        if director.isIdle {
            fidgeting = false
            settledFor += dt
            if settledFor >= nextFidget, settledFor < holdFor {
                nextFidget = settledFor + TimeInterval.random(in: Tuning.Puppet.fidgetGap[0] ... Tuning.Puppet.fidgetGap[1])
                fidget()
                return
            }
        } else {
            // A fidget is part of being settled: the time at the activity runs on, and it is broken off when up.
            guard fidgeting else { return }
            settledFor += dt
        }
        guard settledFor >= holdFor, let chosen = nextActivity?(catRoom) else { return }
        let target = chosen.room ?? catRoom
        guard let node = rooms[target] else { return }
        let choice = pin(chosen, in: node)
        var spot = spot(for: choice, in: node)
        // Already there doing it: stay put a while longer.
        if target == catRoom, hypot(spot.point.x - director.floorPoint.x, spot.point.y - director.floorPoint.y) < 1,
           director.cat.pose == spot.pose
        {
            beganActivity(choice.activity)
            return
        }
        spot.pose = Self.variety(spot.pose)
        onActivityChosen?(choice)
        if choice.activity == .zoomies {
            director.run(zoomies())
        } else if choice.activity == .explore {
            director.run(explore(in: target))
        } else {
            director.run(steps(to: spot, in: target, pace: Self.pace(for: choice.activity)) + extras(for: choice))
        }
        beganActivity(choice.activity)
    }

    /// Sitting is not always the same sit: sometimes three-quarters on, sometimes a loaf.
    static func variety(_ pose: CatPose) -> CatPose {
        switch pose {
        case .sitSide: [.sitSide, .sitSide, .sitThreeQuarterFront, .loafSide].randomElement() ?? pose
        case .sitThreeQuarterFront: [.sitThreeQuarterFront, .sitThreeQuarterFront, .sitSide, .loafThreeQuarterFront].randomElement() ?? pose
        case .loafSide: [.loafSide, .loafSide, .loafThreeQuarterFront].randomElement() ?? pose
        default: pose
        }
    }

    /// The pace an activity is gone to at: an amble for a sit, a trot to the bowl or to you.
    static func pace(for activity: Activity) -> CatDirector.Pace {
        switch activity {
        case .bowlNag, .nearPlayer: .trot
        case .sit, .perch, .windowWatch, .sunbeamLoaf, .floorLoaf: [.stroll, .walk].randomElement() ?? .walk
        case .hide, .knockOff: .trot
        case .zoomies: .dash
        default: .walk
        }
    }

    /// Screen points along the bottom covered by the app's controls (the decorate tray): the room is framed
    /// in the space above them.
    public var bottomInset: CGFloat = 0 {
        didSet {
            guard bottomInset != oldValue else { return }
            run(.customAction(withDuration: Tuning.Stage.insetSeconds) { [weak self] _, _ in self?.fit() }, withKey: "inset")
        }
    }

    /// Where the view looks, in world units; it follows the cat unless the player has just panned.
    var focus: CGPoint?
    private var heldUntil: TimeInterval = 0

    /// The active room's frame in the world.
    private var activeBounds: CGRect {
        let bounds = grid.bounds
        // Up the stairs, the room furthest back on that storey stands in for the active one.
        let node = activeRoom.flatMap { isShown($0) ? $0 : nil }
            ?? house.rooms.filter { $0.storey == storey }.min { $0.u + $0.v < $1.u + $1.v }.flatMap { rooms[$0.id] }
        guard let node else { return bounds }
        return bounds.offsetBy(dx: node.position.x, dy: node.position.y)
    }

    /// Everything on the storey on screen, for clamping the pan.
    private var houseBounds: CGRect {
        rooms.values.filter(isShown).reduce(CGRect.null) { $0.union(grid.bounds.offsetBy(dx: $1.position.x, dy: $1.position.y)) }
    }

    /// The scale at which the active room fills the view's height (Tuning.Stage), centred on it, the rest of the
    /// house filling the sides (on a phone-tall screen, zoomed in further). The camera's zoom multiplies it.
    private var fitScale: CGFloat = 1

    /// Works out `fitScale` for the view and the room, and frames it at once at the camera's zoom.
    func fit() {
        let bounds = activeBounds
        // didChangeSize can arrive from super.init, before the house is built.
        guard size.width > 0, size.height > 0, bounds.width > 0, !rooms.isEmpty else { return }
        // On a screen taller than the room, leave room at the sides for the house around it.
        let widthShare = size.height > size.width ? Tuning.House.portraitFitWidth : Tuning.Stage.fitWidth
        let height = max(1, size.height - bottomInset)
        var scale = min(size.width * widthShare / bounds.width, height * Tuning.Stage.fitHeight / bounds.height)
        if size.height > size.width * CGFloat(Tuning.Stage.portraitZoomAspect) {
            scale = min(scale * Tuning.Stage.portraitZoom, height * Tuning.Stage.fitHeight / bounds.height)
        }
        fitScale = scale
        world.setScale(targetScale)
        look(at: focus ?? restingPoint)
    }

    // MARK: The camera

    /// Where the camera starts: a phone's screen is small, so closer than an iPad's (Tuning.Camera).
    var homeZoom: CGFloat {
        #if os(iOS)
            CGFloat(UIDevice.current.userInterfaceIdiom == .pad ? Tuning.Camera.homeZoomPad : Tuning.Camera.homeZoomPhone)
        #else
            CGFloat(Tuning.Camera.homeZoomPhone)
        #endif
    }

    /// How close the view is, as a multiple of the whole room filling it: a pinch changes it; nil is where the
    /// camera starts (`homeZoom`).
    public var zoom: CGFloat? {
        didSet {
            if let zoom, zoom != oldValue {
                let clamped = min(max(zoom, CGFloat(Tuning.Camera.minZoom)), CGFloat(Tuning.Camera.maxZoom))
                if clamped != zoom {
                    self.zoom = clamped
                }
                onZoomChanged?(clamped)
            }
        }
    }

    /// The zoom changed (a pinch), for the app to keep for the next visit.
    public var onZoomChanged: ((CGFloat) -> Void)?
    /// Until when the camera leans in on the cat.
    private var closeUpUntil: TimeInterval = 0

    /// The camera leans in on the cat for a moment (a greeting, a stroke, a meal) and eases back out after.
    public func lookCloser(for seconds: TimeInterval = Tuning.Camera.closeUpSeconds) {
        closeUpUntil = max(closeUpUntil, (lastUpdate ?? 0) + seconds)
        // A drag a moment ago gives way to the cat.
        heldUntil = 0
    }

    /// Whether the camera is leaning in on the cat now.
    var isCloseUp: Bool {
        !decorating && (lastUpdate ?? 0) < closeUpUntil && catWorldPosition != nil
    }

    /// The scale the camera is easing towards: the whole room while decorating.
    private var targetScale: CGFloat {
        guard !decorating else { return fitScale }
        let close = isCloseUp ? CGFloat(Tuning.Camera.closeUp) : 1
        return fitScale * min((zoom ?? homeZoom) * close, CGFloat(Tuning.Camera.maxZoom))
    }

    /// Eases the scale towards its target, keeping the point in the middle of the view where it is.
    private func ease(_ dt: TimeInterval) {
        let target = targetScale, now = world.xScale
        guard abs(target - now) > now * 0.001 else { return }
        let rate = min(1, CGFloat(dt * Tuning.Camera.zoomRate))
        world.setScale(now + (target - now) * rate)
        look(at: focus ?? restingPoint)
    }

    /// Keeps each closed room's badge readable: the same size on screen however close the camera is (it grew with
    /// the zoom and ran under the controls), slid along the sides when its room runs off the view, and kept out of
    /// the bands along the top and bottom where the controls are.
    private func keepBadgesInView() {
        let margin = CGFloat(Tuning.House.badgeMargin)
        let scale = max(world.xScale, 0.0001)
        let own = CGFloat(Tuning.House.badgePoints / Tuning.House.lockFontSize) / scale
        for room in rooms.values where isShown(room) {
            guard let badge = room.childNode(withName: "lock"),
                  let hx = badge.userData?["homeX"] as? CGFloat, let hy = badge.userData?["homeY"] as? CGFloat,
                  let half = badge.userData?["halfWidth"] as? CGFloat else { continue }
            badge.setScale(own)
            let home = CGPoint(x: hx, y: hy)
            let onScreen = convert(home, from: room)
            // A room out of the view keeps its badge out too (the menu lists every closed room and its price).
            let inView = CGRect(origin: .zero, size: size).contains(onScreen)
            badge.alpha = inView ? 1 : 0
            let halfOnScreen = half * own * scale
            let low = margin + halfOnScreen, high = size.width - margin - halfOnScreen
            let x = low <= high ? min(max(onScreen.x, low), high) : size.width / 2
            let floor = bottomInset + CGFloat(Tuning.House.badgeClearBottom)
            let ceiling = size.height - CGFloat(Tuning.House.badgeClearTop)
            let y = floor <= ceiling ? min(max(onScreen.y, floor), ceiling) : size.height / 2
            badge.position = CGPoint(x: home.x + (x - onScreen.x) / scale, y: home.y + (y - onScreen.y) / scale)
        }
    }

    /// The middle of the cat in the view's points (the room tour points at it), when it is on screen.
    public var catPointInView: CGPoint? {
        guard let cat = director?.cat, let room = cat.parent, isShown(room), view != nil else { return nil }
        let middle = convert(CGPoint(x: cat.position.x, y: cat.position.y + cat.height * 0.45), from: room)
        return convertPoint(toView: middle)
    }

    /// The cat's position in world units, when it is on the storey on screen.
    private var catWorldPosition: CGPoint? {
        guard let cat = director?.cat, let room = cat.parent, isShown(room) else { return nil }
        return world.convert(cat.position, from: room)
    }

    /// Centres a world point; the middle of the view stays over the house, so any room can come to the centre
    /// and the house never leaves the view (the garden and street are drawn around it).
    private func look(at point: CGPoint) {
        let scale = world.xScale, house = houseBounds
        var target = point
        let shown = max(1, size.height - bottomInset)
        target.x = min(max(target.x, house.minX), house.maxX)
        target.y = min(max(target.y, house.minY), house.maxY)
        focus = target
        // Centred in the part of the view the controls leave open.
        world.position = CGPoint(x: size.width / 2 - target.x * scale, y: bottomInset + shown / 2 - target.y * scale)
        keepBadgesInView()
    }

    /// The middle of the cat in world units, when it is on the storey on screen.
    private var catWorldMiddle: CGPoint? {
        guard let cat = director?.cat, let room = cat.parent, isShown(room) else { return nil }
        return world.convert(CGPoint(x: cat.position.x, y: cat.position.y + cat.height * cat.yScale * 0.45), from: room)
    }

    /// Where the view rests: the active room's middle (a room picked with the arrows comes to the centre). When the
    /// room is bigger than the view, the view moves with the cat while it is in there, keeping the room filling the
    /// view; leaning in, the cat is in the middle.
    private var restingPoint: CGPoint {
        let bounds = activeBounds
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        if isCloseUp, let cat = catWorldMiddle {
            return cat
        }
        guard !decorating, catRoom == house.active, let cat = catWorldMiddle else { return middle }
        let scale = max(world.xScale, 0.0001)
        let half = CGSize(width: size.width / scale / 2, height: max(1, size.height - bottomInset) / scale / 2)
        // Each way the room overflows the view, the view keeps the cat near its middle, never past the room's edge.
        func along(_ cat: CGFloat, _ low: CGFloat, _ high: CGFloat, _ half: CGFloat, _ current: CGFloat) -> CGFloat {
            guard high - low > half * 2 else { return (low + high) / 2 }
            let slack = half * 2 * CGFloat(Tuning.Camera.followSlack)
            let wanted = min(max(cat, current - slack), current + slack) == cat ? current : cat + (cat > current ? -slack : slack)
            return min(max(wanted, low + half), high - half)
        }
        let current = focus ?? middle
        return CGPoint(
            x: along(cat.x, bounds.minX, bounds.maxX, half.width, current.x),
            y: along(cat.y, bounds.minY, bounds.maxY, half.height, current.y)
        )
    }

    /// The view eases towards where it rests (unless a drag holds it).
    private func follow(_ dt: TimeInterval) {
        guard let focus, lastUpdate ?? 0 >= heldUntil else { return }
        let target = restingPoint
        guard hypot(target.x - focus.x, target.y - focus.y) > 0.5 else { return }
        let rate = min(1, CGFloat(dt * Tuning.Stage.followRate))
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
        private var pinch: UIPinchGestureRecognizer?
        private var pinchFrom: CGFloat = 1
        private var pinching = false

        /// Pinching zooms from the house around the room to a close look at the cat.
        override public func didMove(to view: SKView) {
            guard pinch == nil else { return }
            let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
            recognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(recognizer)
            pinch = recognizer
        }

        override public func willMove(from view: SKView) {
            if let pinch {
                view.removeGestureRecognizer(pinch)
            }
            pinch = nil
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard !decorating else { return }
            switch recognizer.state {
            case .began:
                pinching = true
                pinchFrom = zoom ?? homeZoom
                // Pinching out of a close look keeps what you see.
                if isCloseUp {
                    pinchFrom *= CGFloat(Tuning.Camera.closeUp)
                    closeUpUntil = 0
                }
                touchTravel = .infinity
            case .changed:
                zoom = pinchFrom * recognizer.scale
                world.setScale(targetScale)
                look(at: focus ?? restingPoint)
            default:
                pinching = false
            }
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let touch = touches.first else { return }
            touchTravel = 0
            if decorating, beginDecorating(touch.location(in: self)) {
                return
            }
            lastTouch = touch.location(in: view)
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            if dragging {
                dragDecorating(to: touch.location(in: self))
                return
            }
            let point = touch.location(in: view)
            if pinching || (event?.allTouches?.count ?? 1) > 1 {
                lastTouch = point
                return
            }
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
                } else if let tag = thought(at: point) {
                    onThoughtTapped?(tag)
                } else if isOnCat(point) {
                    onCatTapped?()
                } else if let room = closedRoom(at: point) {
                    onClosedRoomTapped?(room)
                } else if let room = openRoom(at: point), room != house.active {
                    onRoomTapped?(room)
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

    /// The open room on screen under a scene point, if any (its floor).
    func openRoom(at point: CGPoint) -> RoomID? {
        for room in house.rooms where room.storey == storey && room.lockLabel == nil {
            guard let node = rooms[room.id], isShown(node) else { continue }
            let cell = grid.cell(at: convert(point, to: node))
            if (0 ..< grid.cells).contains(cell.u), (0 ..< grid.cells).contains(cell.v) {
                return room.id
            }
        }
        return nil
    }

    /// Replaces the house (a room opened, a surface changed) and rebuilds it, keeping the cat where it is and
    /// the room you are in.
    public func update(house: HouseModel) {
        var house = house
        if house.room(self.house.active) != nil {
            house.active = self.house.active
        }
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
    /// A room look tried in the room (RoomScene+Decorate.swift `showPreview`).
    var previewNodes: [SKNode] = []
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
