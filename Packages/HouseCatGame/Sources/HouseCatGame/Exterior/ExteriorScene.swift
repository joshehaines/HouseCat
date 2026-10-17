import HouseCatCore
import SpriteKit

/// The cold open (SPEC "The session loop" 1–2): the home painted into its place and season
/// as one picture, under a sky drawn in code for the home's local time; the painting is graded
/// to match and its windows glow after dark. A tap, or the auto-advance, opens the door and the
/// camera pushes in; `onEnter` fires part-way through so the app can cross-fade to the room.
@MainActor
public final class ExteriorScene: SKScene {
    /// What to draw. The app fills it from the save; the scene decides nothing.
    public struct Model: Sendable {
        /// The painted scene's art path without extension: world/scenes/<house>_<biome>_<season>
        /// (.jpg the painting, _land.png its sky mask, _glass.png its window glass).
        public var scene: String
        public var sky: SkyPhase
        /// The front door's centre as a fraction of the painting, top-left origin (assets/world/scenes/scenes.json).
        public var door: CGPoint

        public init(scene: String, sky: SkyPhase, door: CGPoint) {
            self.scene = scene
            self.sky = sky
            self.door = door
        }
    }

    public let model: Model
    /// Called once the push is far enough in for the room to take over.
    public var onEnter: (@MainActor () -> Void)?
    private let art: ArtLibrary
    private let cameraNode = SKCameraNode()
    private let skyNode = SKSpriteNode()
    private let painting = SKSpriteNode()
    private let doorOpen = SKSpriteNode()
    private var entering = false

    public init(size: CGSize, art: ArtLibrary, model: Model) {
        self.art = art
        self.model = model
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Self.color(Tuning.Sky.bottom[model.sky])
        camera = cameraNode
        addChild(cameraNode)
        build()
        layout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Building

    private func build() {
        // The sky hangs off the camera, so the push moves past it.
        skyNode.texture = Self.gradient(top: Tuning.Sky.top[model.sky], bottom: Tuning.Sky.bottom[model.sky])
        skyNode.zPosition = -100
        cameraNode.addChild(skyNode)

        for (node, path) in [(painting, model.scene), (doorOpen, model.scene + "_dooropen")] {
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            guard art.has(path + ".jpg") else { continue }
            node.texture = art.texture(path + ".jpg")
            node.shader = paintingShader(land: art.texture(path + "_land.png"))
            if art.has(path + "_glass.png") {
                let glass = SKSpriteNode(texture: art.texture(path + "_glass.png"))
                glass.anchorPoint = CGPoint(x: 0.5, y: 0)
                glass.shader = glassShader()
                glass.zPosition = 0.1
                glass.name = "glass"
                node.addChild(glass)
            }
            addChild(node)
        }
        painting.name = "exterior"
        doorOpen.name = "exterior.dooropen"
        doorOpen.alpha = 0
        doorOpen.zPosition = 1
        doorOpen.isHidden = doorOpen.texture == nil
    }

    /// The noon painting, cut out by its land mask so the code sky shows above it, and multiplied by the sky's grade.
    private func paintingShader(land: SKTexture) -> SKShader {
        let shader = SKShader(source: """
        void main() {
            vec3 c = texture2D(u_texture, v_tex_coord).rgb;
            float a = texture2D(u_land, v_tex_coord).r;
            gl_FragColor = vec4(c * u_grade * a, a);
        }
        """)
        let grade = Tuning.Sky.grade[model.sky] ?? [1, 1, 1]
        shader.uniforms = [
            SKUniform(name: "u_land", texture: land),
            SKUniform(name: "u_grade", vectorFloat3: SIMD3(Float(grade[0]), Float(grade[1]), Float(grade[2]))),
        ]
        return shader
    }

    /// Fills the window glass: sky-pale by day, warm lamplight after dark.
    private func glassShader() -> SKShader {
        let shader = SKShader(source: """
        void main() {
            float m = texture2D(u_texture, v_tex_coord).r;
            gl_FragColor = vec4(u_glass * m, m);
        }
        """)
        let glow = Tuning.Sky.windowGlow[model.sky] ?? 0
        let day = Tuning.Sky.glassByDay, lit = Tuning.Sky.glassLit
        let grade = Tuning.Sky.grade[model.sky] ?? [1, 1, 1]
        let mix = (0 ..< 3).map { Float(day[$0] * grade[$0] * (1 - glow) + lit[$0] * glow) }
        shader.uniforms = [SKUniform(name: "u_glass", vectorFloat3: SIMD3(mix[0], mix[1], mix[2]))]
        return shader
    }

    private static func color(_ rgb: [Double]?) -> SKColor {
        let c = rgb ?? [1, 1, 1]
        return SKColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
    }

    /// A vertical two-colour gradient as a small texture, stretched over the view.
    private static func gradient(top: [Double]?, bottom: [Double]?) -> SKTexture {
        let space = CGColorSpaceCreateDeviceRGB(), height = 256
        guard let ctx = CGContext(
            data: nil,
            width: 2,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
            let gradient = CGGradient(colorsSpace: space, colors: [color(bottom).cgColor, color(top).cgColor] as CFArray, locations: [0, 1])
        else { return SKTexture() }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        guard let image = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: image)
    }

    // MARK: Framing

    override public func didChangeSize(_: CGSize) {
        layout()
    }

    /// In portrait the house fills the width and the code sky runs above the painting; in landscape the
    /// painting fills the width, shown from a little below its top (Tuning.Exterior).
    private func layout() {
        guard size.width > 0, size.height > 0, !entering else { return }
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cameraNode.setScale(1)
        skyNode.size = size
        let painted = art.paintedSize(model.scene + ".jpg")
        guard painted.width > 0 else { return }
        let scale: CGFloat, bottom: CGFloat
        if size.height >= size.width {
            scale = size.width / (painted.width * CGFloat(Tuning.Exterior.portraitWidthShare))
            bottom = 0
        } else {
            scale = size.width / painted.width
            bottom = min(0, size.height - (1 - CGFloat(Tuning.Exterior.landscapeTopCrop)) * painted.height * scale)
        }
        for node in [painting, doorOpen] {
            node.size = CGSize(width: painted.width * scale, height: painted.height * scale)
            node.position = CGPoint(x: size.width / 2, y: bottom)
            for case let glass as SKSpriteNode in node.children {
                glass.size = node.size
            }
        }
    }

    /// The door in scene coordinates.
    public var doorPoint: CGPoint {
        CGPoint(
            x: painting.position.x + (model.door.x - 0.5) * painting.size.width,
            y: painting.position.y + (1 - model.door.y) * painting.size.height
        )
    }

    // MARK: Entering

    override public func didMove(to _: SKView) {
        run(
            .sequence([.wait(forDuration: Tuning.Arrival.exteriorAutoAdvanceSeconds), .run { [weak self] in self?.enter() }]),
            withKey: "autoAdvance"
        )
    }

    #if os(iOS)
        override public func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
            enter()
        }

    #elseif os(macOS)
        override public func mouseDown(with _: NSEvent) {
            enter()
        }
    #endif

    /// The door opens and the camera pushes into it; the room takes over part-way.
    public func enter() {
        guard !entering else { return }
        removeAction(forKey: "autoAdvance")
        let target = doorPoint
        entering = true
        if doorOpen.texture != nil {
            doorOpen.run(.fadeIn(withDuration: Tuning.Exterior.doorOpenSeconds))
        }
        let seconds = Tuning.Arrival.doorSeconds
        let push = SKAction.group([
            .move(to: target, duration: seconds),
            .scale(to: 1 / CGFloat(Tuning.Exterior.pushScale), duration: seconds),
        ])
        push.timingMode = .easeIn
        cameraNode.run(push)
        run(.sequence([.wait(forDuration: seconds * Tuning.Exterior.roomFadeAt), .run { [weak self] in self?.onEnter?() }]))
    }
}
