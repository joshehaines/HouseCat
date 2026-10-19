import CoreImage
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
        /// Today's weather and the season there: the particles and tint over the picture.
        public var weather: Weather
        public var season: NatureSeason
        /// Where the house stands in the painting, a fraction of it, top-left origin (scenes.json, measured from its
        /// window glass): the view is framed on it. Nil: the painting's middle.
        public var house: CGRect?

        public init(
            scene: String,
            sky: SkyPhase,
            door: CGPoint,
            weather: Weather = .sun,
            season: NatureSeason = .summer,
            house: CGRect? = nil
        ) {
            self.scene = scene
            self.sky = sky
            self.door = door
            self.weather = weather
            self.season = season
            self.house = house
        }
    }

    public let model: Model
    /// Called once the push is far enough in for the room to take over.
    public var onEnter: (@MainActor () -> Void)?
    /// Called as the door starts to open (the app plays its sound).
    public var onDoorOpens: (@MainActor () -> Void)?
    /// Shown, not entered (set before the scene is presented).
    public var showcase = false
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
        backgroundColor = Sky.color(Tuning.Sky.bottom[model.sky])
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
        skyNode.texture = Sky.texture(model.sky)
        skyNode.zPosition = -100
        cameraNode.addChild(skyNode)

        for (node, path) in [(painting, model.scene), (doorOpen, model.scene + "_dooropen")] {
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            guard art.has(path + ".jpg") else { continue }
            node.texture = art.texture(path + ".jpg")
            node.shader = paintingShader(land: art.texture(path + "_land.png"), pixels: art.texture(path + ".jpg").size())
            if art.has(path + "_glass.png") {
                let glass = SKSpriteNode(texture: art.texture(path + "_glass.png"))
                glass.anchorPoint = CGPoint(x: 0.5, y: 0)
                glass.shader = glassShader(painting: art.texture(path + ".jpg"))
                glass.zPosition = 0.1
                glass.name = "glass"
                node.addChild(glass)
                // After dark, lamplight spills softly round the windows.
                let glow = CGFloat(Tuning.Sky.windowGlow[model.sky] ?? 0)
                if glow > 0.3 {
                    let halo = SKEffectNode()
                    halo.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: Tuning.Sky.haloBlur])
                    halo.shouldRasterize = true
                    halo.blendMode = .add
                    halo.alpha = glow * CGFloat(Tuning.Sky.haloAlpha)
                    halo.zPosition = 0.2
                    halo.name = "halo"
                    let light = SKSpriteNode(texture: art.texture(path + "_glass.png"))
                    light.anchorPoint = CGPoint(x: 0.5, y: 0)
                    let lamp = Tuning.Sky.glassLit
                    light.color = SKColor(red: lamp[0], green: lamp[1], blue: lamp[2], alpha: 1)
                    light.colorBlendFactor = 1
                    light.name = "glass"
                    halo.addChild(light)
                    node.addChild(halo)
                }
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
    /// Where it is drawn larger than its pixels it is sharpened (`u_sharp`, set by `sharpen()`): contrast-adaptive,
    /// each pixel pushed away from its four neighbours by how much room it has before clipping.
    private func paintingShader(land: SKTexture, pixels: CGSize) -> SKShader {
        let shader = SKShader(source: """
        void main() {
            vec3 c = texture2D(u_texture, v_tex_coord).rgb;
            if (u_sharp > 0.0) {
                vec3 n = texture2D(u_texture, v_tex_coord + vec2(0.0, u_texel.y)).rgb;
                vec3 s = texture2D(u_texture, v_tex_coord - vec2(0.0, u_texel.y)).rgb;
                vec3 e = texture2D(u_texture, v_tex_coord + vec2(u_texel.x, 0.0)).rgb;
                vec3 w = texture2D(u_texture, v_tex_coord - vec2(u_texel.x, 0.0)).rgb;
                vec3 lo = min(c, min(min(n, s), min(e, w)));
                vec3 hi = max(c, max(max(n, s), max(e, w)));
                vec3 room = sqrt(clamp(min(lo, vec3(1.0) - hi) / max(hi, vec3(0.00001)), 0.0, 1.0));
                vec3 lobe = room * (-1.0 / (8.0 - 3.0 * u_sharp));
                c = clamp((c + lobe * (n + s + e + w)) / (vec3(1.0) + 4.0 * lobe), 0.0, 1.0);
            }
            float a = texture2D(u_land, v_tex_coord).r;
            gl_FragColor = vec4(c * u_grade * a, a);
        }
        """)
        let grade = Tuning.Sky.grade[model.sky] ?? [1, 1, 1]
        shader.uniforms = [
            SKUniform(name: "u_land", texture: land),
            SKUniform(name: "u_grade", vectorFloat3: SIMD3(Float(grade[0]), Float(grade[1]), Float(grade[2]))),
            SKUniform(name: "u_texel", vectorFloat2: SIMD2(Float(1 / max(pixels.width, 1)), Float(1 / max(pixels.height, 1)))),
            SKUniform(name: "u_sharp", float: 0),
        ]
        return shader
    }

    /// Sharpens the painting while it is drawn more than `Tuning.Exterior.sharpenFrom` times its pixels (a big
    /// screen; the full-size masters would add 33 MB to the download).
    private func sharpen() {
        #if os(iOS)
            let screen = view?.contentScaleFactor ?? 2
        #elseif os(macOS)
            let screen = view?.window?.backingScaleFactor ?? 2
        #else
            let screen: CGFloat = 2
        #endif
        for node in [painting, doorOpen] {
            guard let pixels = node.texture?.size(), pixels.width > 1 else { continue }
            let magnified = node.size.width * screen / pixels.width
            node.shader?.uniformNamed("u_sharp")?.floatValue = magnified > Tuning.Exterior.sharpenFrom ? Float(Tuning.Exterior.sharpen) : 0
        }
    }

    /// The window glass (Josh, 19 Oct: flat pale panes looked unfinished): by day the painting's own glass, cooled
    /// towards the sky with a slow sheen drifting across; after dark warm lamplight, keeping the painting's shading.
    private func glassShader(painting: SKTexture) -> SKShader {
        let shader = SKShader(source: """
        void main() {
            float m = texture2D(u_texture, v_tex_coord).r;
            vec3 paint = texture2D(u_paint, v_tex_coord).rgb * u_grade;
            float l = dot(paint, vec3(0.299, 0.587, 0.114));
            // How deep into its pane from the top: glass above means further down the pane.
            float below = 0.0;
            for (int i = 1; i <= 12; i++) {
                below += texture2D(u_texture, v_tex_coord + vec2(0.0, float(i) * u_step)).r;
            }
            below = smoothstep(0.0, 1.0, below / 12.0);
            float band = fract((v_tex_coord.x * 2.2 + v_tex_coord.y * 1.4) * 4.0 - u_time * 0.015);
            float sheen = smoothstep(0.0, 0.06, band) * (1.0 - smoothstep(0.06, 0.16, band));
            // By day: the painted glass with the sky caught in the top of each pane.
            vec3 sky = u_sky * (0.75 + 0.45 * l);
            vec3 day = mix(paint, sky, u_cool + (1.0 - below) * 0.45) + vec3(sheen * 0.1);
            // After dark: warm lamplight, brighter low in the pane where the room's lamps are.
            vec3 lit = u_lamp * (0.72 + 0.32 * below + 0.18 * l);
            vec3 c = mix(day, lit, smoothstep(0.0, 0.7, u_glow));
            gl_FragColor = vec4(c * m, m);
        }
        """)
        let glow = Tuning.Sky.windowGlow[model.sky] ?? 0
        let day = Tuning.Sky.glassByDay, lit = Tuning.Sky.glassLit
        let grade = Tuning.Sky.grade[model.sky] ?? [1, 1, 1]
        func v(_ c: [Double]) -> SIMD3<Float> {
            SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
        }
        shader.uniforms = [
            SKUniform(name: "u_paint", texture: painting),
            SKUniform(name: "u_grade", vectorFloat3: v(grade)),
            SKUniform(name: "u_sky", vectorFloat3: v(zip(day, grade).map { $0 * $1 })),
            SKUniform(name: "u_lamp", vectorFloat3: v(lit)),
            SKUniform(name: "u_glow", float: Float(glow)),
            SKUniform(name: "u_cool", float: Float(Tuning.Sky.glassCool)),
            // A pane is a few per cent of the painting tall: twelve steps up cover most of one.
            SKUniform(name: "u_step", float: Float(Tuning.Sky.glassStep)),
        ]
        return shader
    }

    // MARK: Framing

    override public func didChangeSize(_: CGSize) {
        layout()
    }

    /// Covers the view with the painting, but never so far that the house's band (the middle of the painting,
    /// Tuning.Exterior.focusWidth × focusHeight) is cropped; where the painting then falls short, the code sky
    /// shows above it. Works for the square and the wide paintings in any orientation.
    private func layout() {
        guard size.width > 0, size.height > 0, !entering else { return }
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cameraNode.setScale(1)
        skyNode.size = size
        // Clouds behind the painting (they show only in its sky), and the weather over everything, both fixed
        // to the screen through the push.
        cameraNode.childNode(withName: "weather")?.removeFromParent()
        cameraNode.childNode(withName: "clouds")?.removeFromParent()
        let clouds = WeatherLayer.clouds(
            weather: model.weather,
            season: model.season,
            size: size,
            unit: CGFloat(Tuning.Weather.exteriorUnit),
            art: art
        )
        clouds.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        clouds.zPosition = -50
        cameraNode.addChild(clouds)
        let weather = WeatherLayer.node(
            weather: model.weather,
            season: model.season,
            size: size,
            unit: CGFloat(Tuning.Weather.exteriorUnit),
            art: art
        )
        weather.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        weather.zPosition = 10
        cameraNode.addChild(weather)
        let painted = art.paintedSize(model.scene + ".jpg")
        guard painted.width > 0, painted.height > 0 else { return }
        let focusWidth = CGFloat(Tuning.Exterior.focusWidth), focusHeight = CGFloat(Tuning.Exterior.focusHeight)
        var scale = max(size.width / painted.width, size.height / painted.height)
        scale = min(scale, size.width / (painted.width * focusWidth), size.height / (painted.height * focusHeight))
        let width = painted.width * scale, height = painted.height * scale
        // Centred on the house (Josh, 19 Oct: the house sat off the middle, its chimney cut off on a wide phone),
        // where the painting runs past the view; still covering the view; when shorter, on the ground.
        let house = model.house ?? CGRect(x: 0.5 - focusWidth / 2, y: 0.5 - focusHeight / 2, width: focusWidth, height: focusHeight)
        var bottom = size.height / 2 - (1 - house.midY) * height
        bottom = height >= size.height ? min(0, max(size.height - height, bottom)) : 0
        var middle = size.width / 2 + (0.5 - house.midX) * width
        middle = width >= size.width ? min(width / 2, max(size.width - width / 2, middle)) : size.width / 2
        for node in [painting, doorOpen] {
            node.size = CGSize(width: width, height: height)
            node.position = CGPoint(x: middle, y: bottom)
            for case let glass as SKSpriteNode in node.children {
                glass.size = node.size
            }
            for case let light as SKSpriteNode in node.childNode(withName: "halo")?.children ?? [] {
                light.size = node.size
            }
        }
        sharpen()
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
        // Now the screen's scale is known.
        sharpen()
        // A showcase (the intro's homes round the world) never opens its door: the camera drifts in slowly.
        if showcase {
            cameraNode.run(.group([
                .scale(to: cameraNode.xScale * 0.92, duration: 10),
                .moveBy(x: size.width * 0.03, y: size.height * 0.01, duration: 10),
            ]))
            return
        }
        run(
            .sequence([.wait(forDuration: Tuning.Arrival.exteriorAutoAdvanceSeconds), .run { [weak self] in self?.enter() }]),
            withKey: "autoAdvance"
        )
    }

    #if os(iOS)
        override public func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
            guard !showcase else { return }
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
        onDoorOpens?()
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
