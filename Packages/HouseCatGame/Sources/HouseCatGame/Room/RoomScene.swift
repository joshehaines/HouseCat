import HouseCatCore
import SpriteKit

/// A 2:1 isometric corner room built from the real art (ASSETS.md §2): flat
/// tiles projected onto the two walls and the floor and multiplied by the
/// painted light map, a window showing the outside, a door, and furniture placed
/// by its footprint, back to front, with the cat among them.
@MainActor
public final class RoomScene: SKScene {
    public let grid = IsoGrid()
    /// Holds the room in room units; scaled to fit the view.
    public let world = SKNode()
    public let art: ArtLibrary
    public let items: [String: CatalogueFile.Item]
    public private(set) var model: RoomModel
    /// Placed furniture by item id.
    public private(set) var furniture: [String: SKSpriteNode] = [:]
    private var surfaces: [String: CatalogueFile.Surface]
    /// The cat, once added.
    public internal(set) var director: CatDirector?
    private var lastUpdate: TimeInterval?

    /// Draw-order bands; furniture and the cat sort by floor depth above `standing`.
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
        /// The cat at the camera draws over everything.
        static let atCamera: CGFloat = 10000
    }

    public init(size: CGSize, art: ArtLibrary, content: ContentBundle, model: RoomModel) {
        self.art = art
        items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
        self.model = model
        super.init(size: size)
        scaleMode = .resizeFill
        let grade = Tuning.Sky.grade[model.sky] ?? [1, 1, 1], back = Tuning.Stage.roomBackground
        backgroundColor = SKColor(red: back[0] * grade[0], green: back[1] * grade[1], blue: back[2] * grade[2], alpha: 1)
        addChild(world)
        build()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didChangeSize(_: CGSize) {
        fit()
    }

    override public func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 1.0 / 20) } ?? 0
        lastUpdate = currentTime
        director?.update(dt)
        follow(dt)
    }

    /// Where the view looks across the room, in room units; it follows the cat when the room is wider than the view.
    private var focusX: CGFloat?

    /// Scales and centres the room in the view. On a tall screen the room is zoomed in past its width
    /// (Tuning.Stage.portraitZoom) and the view pans to follow the cat.
    func fit() {
        let bounds = grid.bounds
        guard size.width > 0, size.height > 0 else { return }
        var scale = min(size.width * Tuning.Stage.fitWidth / bounds.width, size.height * Tuning.Stage.fitHeight / bounds.height)
        if size.height > size.width {
            scale = min(scale * Tuning.Stage.portraitZoom, size.height * Tuning.Stage.fitHeight / bounds.height)
        }
        world.setScale(scale)
        world.position.y = size.height / 2 - bounds.midY * scale
        place(focusX ?? director?.cat.position.x ?? bounds.midX)
    }

    /// Pans so a room x sits mid-view, without showing past the room's sides.
    private func place(_ x: CGFloat) {
        let bounds = grid.bounds, scale = world.xScale
        focusX = x
        var left = size.width / 2 - x * scale
        if bounds.width * scale > size.width {
            left = min(-bounds.minX * scale, max(size.width - bounds.maxX * scale, left))
        } else {
            left = size.width / 2 - bounds.midX * scale
        }
        world.position.x = left
    }

    private func follow(_ dt: TimeInterval) {
        guard let cat = director?.cat, let focus = focusX else { return }
        place(focus + (cat.position.x - focus) * min(1, CGFloat(dt * Tuning.Stage.followRate)))
    }

    /// The scene point of a floor position.
    public func scenePoint(u: CGFloat, v: CGFloat) -> CGPoint {
        world.convert(grid.floor(u, v), to: self)
    }

    // MARK: Build

    private func build() {
        world.removeAllChildren()
        furniture = [:]
        buildPlanes()
        buildOpening(model.window, isWindow: true)
        buildOpening(model.door, isWindow: false)
        for placement in model.items {
            placeFurniture(placement)
        }
        fit()
    }

    private func buildPlanes() {
        let n = grid.cells, h = grid.wallCells
        let wallTile = surfaces[model.wall]?.sprite ?? "rooms/walls/\(model.wall).png"
        let floorTile = surfaces[model.floor]?.sprite ?? "rooms/floors/\(model.floor).png"
        // One painted tile covers two cells.
        let wallRepeat = SIMD2<Float>(Float(n / 2), Float(h / 2))
        let floorRepeat = SIMD2<Float>(Float(n / 2), Float(n / 2))
        let right = Quad(bl: grid.floor(0, 0), br: grid.floor(n, 0), tl: grid.rightWall(0, up: h), tr: grid.rightWall(n, up: h))
        let left = Quad(bl: grid.floor(0, 0), br: grid.floor(0, n), tl: grid.leftWall(0, up: h), tr: grid.leftWall(n, up: h))
        let floor = Quad(bl: grid.floor(0, n), br: grid.floor(n, n), tl: grid.floor(0, 0), tr: grid.floor(n, 0))
        world.addChild(plane(light: "right", tile: wallTile, repeats: wallRepeat, corners: right))
        world.addChild(plane(light: "left", tile: wallTile, repeats: wallRepeat, corners: left))
        world.addChild(plane(light: "floor", tile: floorTile, repeats: floorRepeat, corners: floor))
    }

    /// Four room points a flat sprite is warped onto.
    struct Quad {
        var bl: CGPoint
        var br: CGPoint
        var tl: CGPoint
        var tr: CGPoint
    }

    /// A flat plane warped onto four corners: the tile repeats across it and the light map multiplies it.
    private func plane(light: String, tile: String, repeats: SIMD2<Float>, corners: Quad) -> SKSpriteNode {
        let lightMap = art.texture("rooms/lightmaps/lm_\(model.light)_\(light).png")
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
        let rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
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

    private func wallPoint(_ wall: String, along: CGFloat, up: CGFloat) -> CGPoint {
        wall == "R" ? grid.rightWall(along, up: up) : grid.leftWall(along, up: up)
    }

    private func buildOpening(_ opening: RoomModel.Opening, isWindow: Bool) {
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
            world.addChild(view)
        }
        let node = quad(texture: art.texture(framePath), corners)
        node.zPosition = Layer.openings + 1
        node.name = isWindow ? "window" : "door"
        world.addChild(node)
    }

    // MARK: Furniture

    /// The scale that turns a sprite's painted pixels into room units.
    public func scale(for item: CatalogueFile.Item, sprite: String) -> CGFloat {
        let ref = art.referenceRoom(sprite) ?? "grey"
        let painted = model.refScale[ref] ?? 0.46
        return CGFloat(painted * (item.suggestedScale ?? 1) * (model.scale[item.id] ?? 1))
    }

    /// The footprint along u and v for a facing: an item turned to face L swaps them.
    func footprint(_ item: CatalogueFile.Item, facing: String) -> (w: CGFloat, d: CGFloat) {
        let w = CGFloat(item.footprint.w), d = CGFloat(item.footprint.d)
        return facing == "L" ? (d, w) : (w, d)
    }

    private func placeFurniture(_ placement: RoomModel.Placement) {
        guard let item = items[placement.id], let sprite = item.sprites[placement.facing] else { return }
        let s = scale(for: item, sprite: sprite)
        let painted = art.paintedSize(sprite)
        let node = SKSpriteNode(texture: art.texture(sprite), size: CGSize(width: painted.width * s, height: painted.height * s))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.name = item.id
        let u = CGFloat(placement.u), v = CGFloat(placement.v)
        let (w, d) = footprint(item, facing: placement.facing)
        if item.layer == .wall {
            let along = (placement.facing == "R" ? u : v) + w / 2
            node.position = wallPoint(placement.facing, along: along, up: CGFloat(placement.up ?? Tuning.Stage.wallItemHeight))
            node.zPosition = Layer.wallItems
        } else {
            // Anchored by the bottom centre of its footprint: centred on the footprint, standing on its front corner.
            node.position = CGPoint(x: grid.floor(u + w / 2, v + d / 2).x, y: grid.floor(u + w, v + d).y)
            node.zPosition = item.decal ? Layer.decals : Layer.standing + grid.depth(u + w, v + d) * Layer.perDepth
        }
        addEffects(to: node, item: item, sprite: sprite, scale: s)
        world.addChild(node)
        furniture[item.id] = node
    }

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
    private func addEffects(to node: SKSpriteNode, item _: CatalogueFile.Item, sprite: String, scale s: CGFloat) {
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
