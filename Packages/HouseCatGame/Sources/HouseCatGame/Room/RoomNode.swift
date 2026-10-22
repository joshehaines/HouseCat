import HouseCatCore
import SpriteKit

/// One room of the house in its own coordinates: the back corner of its floor at the origin, room
/// units (IsoGrid). Flat tiles projected onto the walls and floor and multiplied by the painted light
/// map (ASSETS.md §2), a window and a door on the walls that stand, and furniture placed by its
/// footprint, back to front. Walls between rooms, and every wall on the camera side, are cut down to
/// stubs so the house reads as a dollhouse with its front open.
@MainActor
final class RoomNode: SKNode {
    /// How a back wall is drawn: full height, cut down to a stub (a partition seen from above), or not at all.
    enum Wall: Sendable {
        case full
        case stub
        case none
    }

    let id: RoomID
    let grid = IsoGrid()
    private(set) var model: RoomModel
    let outdoor: Bool
    let walls: (left: Wall, right: Wall)
    /// Doorways cut into the partitions, by wall ("L", "R"): the cell along the wall at their middle.
    let doorways: [String: CGFloat]
    /// Placed furniture by item id (the first of each) and by placement.
    private(set) var furniture: [String: SKSpriteNode] = [:]
    private(set) var placements: [UUID: SKSpriteNode] = [:]
    private let art: ArtLibrary
    private let items: [String: CatalogueFile.Item]
    private let surfaces: [String: CatalogueFile.Surface]

    /// Draw-order bands inside a room; furniture and the cat sort by floor depth above `standing`.
    enum Layer {
        static let planes: CGFloat = -1000
        static let openings: CGFloat = -900
        static let wallItems: CGFloat = -800
        static let decals: CGFloat = -700
        static let standing: CGFloat = 0
        /// Standing things sort by floor depth (u + v) times this.
        static let perDepth: CGFloat = 10
        /// The cat draws just over an item standing on the same row.
        static let catOverItem: CGFloat = 0.5
        /// The lock veil over a closed room, over everything in it.
        static let veil: CGFloat = 500
    }

    init(
        id: RoomID,
        model: RoomModel,
        art: ArtLibrary,
        items: [String: CatalogueFile.Item],
        surfaces: [String: CatalogueFile.Surface],
        walls: (left: Wall, right: Wall),
        outdoor: Bool,
        doorways: [String: CGFloat] = [:]
    ) {
        self.id = id
        self.model = model
        self.art = art
        self.items = items
        self.surfaces = surfaces
        self.walls = walls
        self.outdoor = outdoor
        self.doorways = doorways
        super.init()
        name = "room.\(id.rawValue)"
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Building

    private func build() {
        removeAllChildren()
        furniture = [:]
        placements = [:]
        buildPlanes()
        for (opening, isWindow) in [(model.window, true), (model.door, false)] {
            if let opening, wall(opening.wall) == .full {
                buildOpening(opening, isWindow: isWindow)
            }
        }
        for placement in model.items {
            placeFurniture(placement)
        }
    }

    private func wall(_ side: String) -> Wall {
        side == "R" ? walls.right : walls.left
    }

    /// The height a wall is drawn at, in cells.
    func height(of wall: Wall) -> CGFloat {
        switch wall {
        case .full: outdoor ? CGFloat(Tuning.House.gardenWallHeight) : grid.wallCells
        case .stub: CGFloat(Tuning.House.stubHeight)
        case .none: 0
        }
    }

    private func buildPlanes() {
        let n = grid.cells
        let wallTile = surfaces[model.wall]?.sprite ?? "rooms/walls/\(model.wall).png"
        let floorTile = surfaces[model.floor]?.sprite ?? "rooms/floors/\(model.floor).png"
        // One painted tile covers two cells.
        let floorRepeat = SIMD2<Float>(Float(n / 2), Float(n / 2))
        let floor = Quad(bl: grid.floor(0, n), br: grid.floor(n, n), tl: grid.floor(0, 0), tr: grid.floor(n, 0))
        addChild(plane(light: "floor", tile: floorTile, repeats: floorRepeat, corners: floor))
        let right = height(of: walls.right), left = height(of: walls.left)
        if right > 0 {
            for (a, b) in pieces(of: "R") {
                let quad = Quad(
                    bl: grid.floor(a, 0),
                    br: grid.floor(b, 0),
                    tl: grid.rightWall(a, up: right),
                    tr: grid.rightWall(b, up: right)
                )
                addChild(plane(
                    light: "right",
                    tile: wallTile,
                    repeats: SIMD2(Float(n / 2), Float(right / 2)),
                    corners: quad,
                    span: (a / n, b / n)
                ))
                if walls.right == .stub {
                    addCap(from: grid.rightWall(a, up: right), to: grid.rightWall(b, up: right))
                }
            }
        }
        if left > 0 {
            for (a, b) in pieces(of: "L") {
                let quad = Quad(bl: grid.floor(0, a), br: grid.floor(0, b), tl: grid.leftWall(a, up: left), tr: grid.leftWall(b, up: left))
                addChild(plane(
                    light: "left",
                    tile: wallTile,
                    repeats: SIMD2(Float(n / 2), Float(left / 2)),
                    corners: quad,
                    span: (a / n, b / n)
                ))
                if walls.left == .stub {
                    addCap(from: grid.leftWall(a, up: left), to: grid.leftWall(b, up: left))
                }
            }
        }
    }

    /// The stretches of a wall that stand: all of it, or either side of a doorway in a partition.
    private func pieces(of side: String) -> [(CGFloat, CGFloat)] {
        let n = grid.cells
        guard wall(side) == .stub, let middle = doorways[side] else { return [(0, n)] }
        let half = CGFloat(Tuning.House.doorwayWidth) / 2
        return [(0, max(0, middle - half)), (min(n, middle + half), n)].filter { $0.1 - $0.0 > 0.01 }
    }

    /// The cut top of a stub wall, so it reads as a wall seen from above rather than a skirting board.
    private func addCap(from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let cap = SKShapeNode(path: path)
        let c = Tuning.House.capColor
        cap.strokeColor = SKColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
        cap.lineWidth = CGFloat(Tuning.House.capWidth)
        cap.lineCap = .round
        cap.zPosition = Layer.planes + 1
        addChild(cap)
    }

    /// Four room points a flat sprite is warped onto.
    struct Quad {
        var bl: CGPoint
        var br: CGPoint
        var tl: CGPoint
        var tr: CGPoint
    }

    /// A flat plane warped onto four corners: the tile repeats across it and the light map multiplies it.
    /// `span` is the stretch of the whole wall this plane covers (0–1), so a wall in pieces keeps one light
    /// map and one run of tiles (`v_tex_coord` stays in the whole texture's space for a part of it).
    private func plane(
        light: String,
        tile: String,
        repeats: SIMD2<Float>,
        corners: Quad,
        span: (CGFloat, CGFloat) = (0, 1)
    ) -> SKSpriteNode {
        var lightMap = art.texture("rooms/lightmaps/lm_\(model.light)_\(light).png")
        if span != (0, 1) {
            lightMap = SKTexture(rect: CGRect(x: span.0, y: 0, width: span.1 - span.0, height: 1), in: lightMap)
        }
        let node = quad(texture: lightMap, corners)
        node.zPosition = Layer.planes
        let shader = SKShader(source: """
        void main() {
            vec4 tile = texture2D(u_tile, fract(v_tex_coord * u_repeat));
            vec3 light = texture2D(u_texture, v_tex_coord).rgb * 1.5;
            gl_FragColor = vec4(tile.rgb * light, 1.0);
        }
        """)
        shader.uniforms = [
            SKUniform(name: "u_tile", texture: art.texture(tile)),
            SKUniform(name: "u_repeat", vectorFloat2: repeats),
        ]
        node.shader = shader
        return node
    }

    /// A sprite warped so its corners land on four room points (an affine quad for walls and floor).
    private func quad(texture: SKTexture, _ corners: Quad) -> SKSpriteNode {
        let points = [corners.bl, corners.br, corners.tl, corners.tr]
        let left = points.map(\.x).min() ?? 0, right = points.map(\.x).max() ?? 0
        let bottom = points.map(\.y).min() ?? 0, top = points.map(\.y).max() ?? 0
        let rect = CGRect(x: left, y: bottom, width: max(right - left, 1), height: max(top - bottom, 1))
        let node = SKSpriteNode(texture: texture, size: rect.size)
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        func normal(_ p: CGPoint) -> SIMD2<Float> {
            SIMD2(Float((p.x - rect.minX) / rect.width), Float((p.y - rect.minY) / rect.height))
        }
        node.warpGeometry = SKWarpGeometryGrid(
            columns: 1, rows: 1,
            sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
            destinationPositions: points.map(normal)
        )
        return node
    }

    func wallPoint(_ wall: String, along: CGFloat, up: CGFloat) -> CGPoint {
        wall == "R" ? grid.rightWall(along, up: up) : grid.leftWall(along, up: up)
    }

    private func buildOpening(_ opening: RoomModel.Opening, isWindow: Bool) {
        if !isWindow, opening.id.hasPrefix(Self.isoDoorPrefix) {
            buildIsoDoor(opening)
            return
        }
        let folder = isWindow ? "rooms/windows" : "rooms/doors"
        let framePath = "\(folder)/\(opening.id).png", maskPath = "\(folder)/\(opening.id)_opening.png"
        guard let frame = art.image(framePath), let mask = art.image(maskPath) else { return }
        let up = CGFloat(opening.up ?? 0), start = CGFloat(opening.start), along = CGFloat(opening.along), h = CGFloat(opening.height)
        let corners = Quad(
            bl: wallPoint(opening.wall, along: start, up: up), br: wallPoint(opening.wall, along: start + along, up: up),
            tl: wallPoint(opening.wall, along: start, up: up + h), tr: wallPoint(opening.wall, along: start + along, up: up + h)
        )
        let size = CGSize(width: frame.width, height: frame.height)
        func color(_ rgb: [Double]?) -> CGColor {
            let c = rgb ?? [1, 1, 1]
            return CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
        }
        let behind: CGImage? = if isWindow {
            Composite.windowView(
                size: size,
                opening: mask,
                skyTop: color(Tuning.Sky.top[model.sky]),
                skyBottom: color(Tuning.Sky.bottom[model.sky]),
                terrain: art.image(model.terrain),
                grade: color(Tuning.Sky.grade[model.sky])
            )
        } else {
            Composite.doorway(size: size, opening: mask, color: color(Tuning.Stage.doorwayShadow))
        }
        if let behind {
            let view = quad(texture: SKTexture(cgImage: behind), corners)
            view.zPosition = Layer.openings
            view.name = isWindow ? "window.view" : "door.beyond"
            addChild(view)
            if isWindow {
                addWeather(over: view, corners: corners, texture: SKTexture(cgImage: behind))
            }
        }
        let node = quad(texture: art.texture(framePath), corners)
        node.zPosition = Layer.openings + 1
        node.name = isWindow ? "window" : "door"
        addChild(node)
    }

    /// Doors painted in 3D at the left wall's angle (tools/asset-pipeline/isodoors.py), not flat ones laid onto it.
    static let isoDoorPrefix = "door_iso_"

    /// A 3D door stands upright on its wall, not warped onto it: its frame, its depth and the hallway beyond are
    /// painted. Its bottom-left corner is the frame's front foot and it spans `along` cells of the wall; on the right
    /// wall it is mirrored.
    private func buildIsoDoor(_ opening: RoomModel.Opening) {
        let path = "rooms/doors/\(opening.id).png"
        guard art.has(path) else { return }
        let painted = art.paintedSize(path)
        let width = CGFloat(opening.along) * grid.cellHalfWidth
        let node = SKSpriteNode(
            texture: art.texture(path),
            size: CGSize(width: width, height: width * painted.height / max(painted.width, 1))
        )
        node.anchorPoint = .zero
        node.position = wallPoint(opening.wall, along: CGFloat(opening.start + opening.along), up: 0)
        node.xScale = opening.wall == "R" ? -1 : 1
        node.zPosition = Layer.openings + 1
        node.name = "door"
        addChild(node)
    }

    /// The weather outside, clipped to the window's opening.
    private func addWeather(over view: SKSpriteNode, corners: Quad, texture: SKTexture) {
        let frame = view.frame
        let layer = WeatherLayer.node(
            weather: model.weather,
            season: model.season,
            size: frame.size,
            unit: CGFloat(Tuning.Weather.windowUnit),
            art: art
        )
        guard !layer.children.isEmpty else { return }
        layer.position = CGPoint(x: frame.minX, y: frame.minY)
        let crop = SKCropNode()
        crop.maskNode = quad(texture: texture, corners)
        crop.addChild(layer)
        crop.zPosition = Layer.openings + 0.5
        crop.name = "window.weather"
        addChild(crop)
    }

    // MARK: Furniture

    /// The scale that turns a sprite's painted pixels into room units, drawn smaller than painted
    /// (`furnitureScale`) so the furniture sits right beside the cat.
    func scale(for item: CatalogueFile.Item, sprite: String) -> CGFloat {
        let ref = art.referenceRoom(sprite) ?? "grey"
        let painted = model.refScale[ref] ?? model.refScale["grey"] ?? 0.46
        return CGFloat(painted * (item.suggestedScale ?? 1) * (model.scale[item.id] ?? 1) * model.furnitureScale)
    }

    /// The footprint along u and v for a facing: an item turned to face L swaps them.
    func footprint(_ item: CatalogueFile.Item, facing: String) -> (w: CGFloat, d: CGFloat) {
        let w = CGFloat(item.footprint.w), d = CGFloat(item.footprint.d)
        return facing == "L" ? (d, w) : (w, d)
    }

    /// Where a floor piece stands, in cells: its footprint drawn smaller (`furnitureScale`) in the middle of its
    /// cells, or with its back to a wall its cells touch, so a sofa against the wall stays against it.
    func stand(_ item: CatalogueFile.Item, _ placement: RoomModel.Placement) -> (u: CGFloat, v: CGFloat, w: CGFloat, d: CGFloat) {
        let (w, d) = footprint(item, facing: placement.facing)
        let k = CGFloat(model.furnitureScale), u = CGFloat(placement.u), v = CGFloat(placement.v)
        return (u <= 0 ? 0 : u + w * (1 - k) / 2, v <= 0 ? 0 : v + d * (1 - k) / 2, w * k, d * k)
    }

    /// Builds the sprite for a placement, positioned and sorted (also used for the decorate ghost).
    func sprite(for placement: RoomModel.Placement) -> SKSpriteNode? {
        guard let item = items[placement.id], let sprite = item.sprites[placement.facing] else { return nil }
        let s = scale(for: item, sprite: sprite)
        let painted = art.paintedSize(sprite)
        let node = SKSpriteNode(texture: art.texture(sprite), size: CGSize(width: painted.width * s, height: painted.height * s))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.name = item.id
        position(node, item: item, placement: placement)
        addEffects(to: node, sprite: sprite, scale: s)
        return node
    }

    /// Puts a furniture sprite where a placement says: wall items on their wall, the rest by the bottom centre of the footprint.
    func position(_ node: SKSpriteNode, item: CatalogueFile.Item, placement: RoomModel.Placement) {
        let u = CGFloat(placement.u), v = CGFloat(placement.v)
        let (w, d) = footprint(item, facing: placement.facing)
        if item.layer == .wall {
            let along = (placement.facing == "R" ? u : v) + w / 2
            node.position = wallPoint(placement.facing, along: along, up: CGFloat(placement.up ?? Tuning.Stage.wallItemHeight))
            node.zPosition = Layer.wallItems
        } else {
            // Anchored by the bottom centre of where it stands: centred on it, on its front corner. It sorts by its
            // whole footprint's front corner.
            let at = stand(item, placement)
            node.position = CGPoint(x: grid.floor(at.u + at.w / 2, at.v + at.d / 2).x, y: grid.floor(at.u + at.w, at.v + at.d).y)
            node.zPosition = item.decal ? Layer.decals : Layer.standing + grid.depth(u + w, v + d) * Layer.perDepth
        }
    }

    private func placeFurniture(_ placement: RoomModel.Placement) {
        guard let node = sprite(for: placement) else { return }
        addChild(node)
        if furniture[placement.id] == nil {
            furniture[placement.id] = node
        }
        if let id = placement.placementID {
            placements[id] = node
        }
    }

    /// Replaces the furniture after the layout changed (decorating), keeping the walls and floor.
    func update(items placements: [RoomModel.Placement]) {
        for node in self.placements.values {
            node.removeFromParent()
        }
        for node in furniture.values where node.parent != nil {
            node.removeFromParent()
        }
        furniture = [:]
        self.placements = [:]
        model.items = placements
        for placement in placements {
            placeFurniture(placement)
        }
    }

    /// Swaps one placement for an edited copy (moved or turned) and rebuilds its sprite.
    func replace(_ placement: RoomModel.Placement) {
        guard let id = placement.placementID, let index = model.items.firstIndex(where: { $0.placementID == id }) else { return }
        model.items[index] = placement
        placements[id]?.removeFromParent()
        placements[id] = nil
        placeFurniture(placement)
        furniture[placement.id] = placements[id]
    }

    /// Puts a new placement in the room (from the inventory).
    func add(_ placement: RoomModel.Placement) {
        model.items.append(placement)
        placeFurniture(placement)
    }

    /// Takes a placement out of the room (stored in the inventory).
    func remove(_ placementID: UUID) {
        model.items.removeAll { $0.placementID == placementID }
        if let node = placements.removeValue(forKey: placementID) {
            node.removeFromParent()
            if let key = furniture.first(where: { $0.value === node })?.key {
                furniture[key] = model.items.first { $0.id == key }.flatMap(\.placementID).flatMap { placements[$0] }
            }
        }
    }

    /// The placement a furniture sprite shows.
    func placement(of node: SKNode) -> RoomModel.Placement? {
        guard let id = placements.first(where: { $0.value === node })?.key else { return nil }
        return model.items.first { $0.placementID == id }
    }

    /// The staircase up, a fixed part of the house (not furniture): it runs along the wall it faces from
    /// its back cell, Tuning.House.stairsLength cells long, and sorts with the furniture.
    func addStairs(at u: CGFloat, _ v: CGFloat, facing: String) {
        let path = "furniture/living/furn_living_stairs_\(facing).png"
        guard art.has(path) else { return }
        let painted = art.paintedSize(path), s = CGFloat(model.refScale["grey"] ?? 0.46)
        let node = SKSpriteNode(texture: art.texture(path), size: CGSize(width: painted.width * s, height: painted.height * s))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        let length = CGFloat(Tuning.House.stairsLength)
        let (w, d) = facing == "L" ? (CGFloat(1), length) : (length, CGFloat(1))
        node.position = CGPoint(x: grid.floor(u + w / 2, v + d / 2).x, y: grid.floor(u + w, v + d).y)
        node.zPosition = Layer.standing + grid.depth(u + w, v + d) * Layer.perDepth
        node.name = "stairs"
        addChild(node)
    }

    // MARK: Locked rooms

    /// A closed room shows bare, with what it takes to open it (SPEC "Home and furniture"). Its veil is no longer
    /// drawn (Josh, 19 Oct: no dark see-through areas between the rooms); it is kept, clear, as the room's tap area.
    func veil(label: String, at cell: (u: CGFloat, v: CGFloat)? = nil) {
        let n = grid.cells
        let left = height(of: walls.left), right = height(of: walls.right), back = max(left, right)
        let path = CGMutablePath()
        path.move(to: grid.floor(0, n))
        path.addLine(to: grid.leftWall(n, up: left))
        path.addLine(to: grid.leftWall(0, up: back))
        path.addLine(to: grid.rightWall(n, up: right))
        path.addLine(to: grid.floor(n, 0))
        path.addLine(to: grid.floor(n, n))
        path.closeSubpath()
        let veil = SKShapeNode(path: path)
        veil.fillColor = .clear
        veil.strokeColor = .clear
        veil.zPosition = Layer.veil
        veil.name = "veil"
        addChild(veil)
        // Held up at eye height over the floor, like a sign, so it clears the controls along the bottom.
        let floor = grid.floor(cell?.u ?? n / 2, cell?.v ?? n / 2)
        addChild(lockBadge(label, at: CGPoint(x: floor.x, y: floor.y + CGFloat(Tuning.House.labelLift))))
    }

    /// What opening a closed room takes, as a cream badge with the painted padlock (the game's controls' look).
    private func lockBadge(_ label: String, at point: CGPoint) -> SKNode {
        let size = CGFloat(Tuning.House.lockFontSize)
        let text = SKLabelNode(text: label)
        text.fontName = "AvenirNext-Bold"
        text.fontSize = size
        // The house on one line, its price under it: narrow, so neighbouring rooms' badges don't meet.
        text.numberOfLines = 2
        let ink = Tuning.House.lockInk
        text.fontColor = SKColor(red: ink[0], green: ink[1], blue: ink[2], alpha: 1)
        text.verticalAlignmentMode = .center
        text.horizontalAlignmentMode = .left
        let icon = SKSpriteNode(texture: art.texture("ui/icon_padlock.png"))
        let iconSize = size * 1.5
        icon.size = CGSize(width: iconSize * icon.texture!.size().width / max(1, icon.texture!.size().height), height: iconSize)
        let pad = size * 0.5, gap = size * 0.3
        let width = pad + icon.size.width + gap + text.frame.width + pad * 1.4
        let height = max(iconSize, text.frame.height) + pad
        let badge = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: height / 2)
        let c = Tuning.House.lockPaper
        badge.fillColor = SKColor(red: c[0], green: c[1], blue: c[2], alpha: 0.95)
        badge.strokeColor = SKColor(red: 0.6, green: 0.45, blue: 0.38, alpha: 0.3)
        badge.lineWidth = 2
        icon.position = CGPoint(x: -width / 2 + pad + icon.size.width / 2, y: 0)
        text.position = CGPoint(x: icon.position.x + icon.size.width / 2 + gap, y: 0)
        badge.addChild(icon)
        badge.addChild(text)
        badge.position = point
        badge.zPosition = Layer.veil + 1
        badge.name = "lock"
        // Where it belongs; the scene slides it back inside the view when the room runs off screen.
        badge.userData = ["homeX": point.x, "homeY": point.y, "halfWidth": width / 2]
        return badge
    }

    // MARK: Effects

    /// An attach point from assets/fx/anchors.json; water entries have no point yet (placed by eye later).
    private struct FXAnchor: Decodable {
        var fx: String
        var anchor: [Double]?
        var fxWidth: Double?

        enum CodingKeys: String, CodingKey {
            case fx, anchor
            case fxWidth = "fx_width_px"
        }
    }

    private lazy var fxAnchors: [String: FXAnchor] = (try? art.data("fx/anchors.json", as: [String: FXAnchor].self)) ?? [:]

    /// Flames and steam: frame loops attached where the art says (assets/fx/anchors.json), additive, ~10 fps.
    private func addEffects(to node: SKSpriteNode, sprite: String, scale s: CGFloat) {
        guard let anchor = fxAnchors[sprite], let point = anchor.anchor, point.count == 2, anchor.fx == "fire" else { return }
        let frames = (0 ..< 8).map { art.texture(String(format: "fx/fire/fx_fire_%02d.png", $0)) }
        let frameSize = art.paintedSize("fx/fire/fx_fire_00.png")
        let width = CGFloat(anchor.fxWidth ?? 50) * CGFloat(Tuning.Stage.fireWidth) * s
        let fire = SKSpriteNode(
            texture: frames[0],
            size: CGSize(width: width, height: width * frameSize.height / max(frameSize.width, 1))
        )
        fire.anchorPoint = CGPoint(x: 0.5, y: 0)
        let painted = art.paintedSize(sprite)
        fire.position = CGPoint(x: (CGFloat(point[0]) - painted.width / 2) * s, y: (painted.height - CGFloat(point[1])) * s)
        fire.blendMode = .add
        fire.zPosition = 0.5
        fire.name = "fx.fire"
        fire.run(.repeatForever(.animate(with: frames, timePerFrame: Tuning.Stage.fxFrameSeconds)))
        node.addChild(fire)
    }
}
