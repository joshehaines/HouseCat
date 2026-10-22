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
        /// The windows the cat can sit in (scenes.json "windows"), for `seat(_:at:)`.
        public var windows: [SceneWindow]

        public init(
            scene: String,
            sky: SkyPhase,
            door: CGPoint,
            weather: Weather = .sun,
            season: NatureSeason = .summer,
            house: CGRect? = nil,
            windows: [SceneWindow] = []
        ) {
            self.scene = scene
            self.sky = sky
            self.door = door
            self.weather = weather
            self.season = season
            self.house = house
            self.windows = windows
        }
    }

    public let model: Model
    /// Called once the push is far enough in for the room to take over.
    public var onEnter: (@MainActor () -> Void)?
    /// Called as the door starts to open (the app plays its sound).
    public var onDoorOpens: (@MainActor () -> Void)?
    /// Shown, not entered (set before the scene is presented).
    public var showcase = false
    /// Stepped out of the room to look at the house (Josh, 20 Oct: "a way to view your house from the outside"): it
    /// waits for you; a tap on the door, or the app's Go in, goes back in (set before the scene is presented).
    public var looking = false
    /// A tap on the cat in its window (it slow-blinks back).
    public var onCatTapped: (@MainActor () -> Void)?
    private let art: ArtLibrary
    private let cameraNode = SKCameraNode()
    private let skyNode = SKSpriteNode()
    private let painting = SKSpriteNode()
    private let doorOpen = SKSpriteNode()
    private var entering = false
    /// The cat at a window (`seat`): the window's glass as a crop, the cat tinted by the glass and the room's light
    /// inside it, the sky caught in the glass over it.
    public private(set) var windowCat: CatNode?
    public private(set) var sighting: WindowSighting?
    private var windowNode: SKCropNode?
    /// The window's glass over the painting (its own units) and the cat's height sitting looking out, unscaled.
    private var windowFrame = CGRect.zero
    private var sittingHeight: CGFloat = 1
    /// Where across the window it sits (0 its left, 1 its right): the widest run of glass, a bay's middle face.
    private var seatX: CGFloat = 0.5
    private var lastUpdate: TimeInterval?
    private var lastBlink: TimeInterval = -.infinity
    /// Out to look, closer on the cat's window (a tap on it; another tap steps back).
    public private(set) var closeUp = false

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
        closeUp = false
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
        placeWindowCat()
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
        // Out to look: out of the front door, the camera drawing back from the doorway to the whole house as the door
        // closes behind you. Then nothing happens by itself; the door, or the app's Go in, goes back in.
        if looking {
            stepOut()
            return
        }
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
        override public func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard !showcase else { return }
            guard looking, let touch = touches.first else {
                enter()
                return
            }
            tapped(at: touch.location(in: self))
        }

    #elseif os(macOS)
        override public func mouseDown(with event: NSEvent) {
            guard looking else {
                enter()
                return
            }
            tapped(at: event.location(in: self))
        }
    #endif

    /// Out to look: a tap on the cat's window leans in closer on it and gets a slow blink; any tap close up steps
    /// back; one on the door goes back in.
    private func tapped(at point: CGPoint) {
        if closeUp {
            lookCloser(false)
            return
        }
        if windowNode != nil,
           windowFrame.insetBy(dx: -windowFrame.width * 0.3, dy: -windowFrame.height * 0.2).contains(painting.convert(point, from: self))
        {
            lookCloser(true)
            let now = lastUpdate ?? 0
            if now - lastBlink > Tuning.WindowCat.blinkEverySeconds {
                lastBlink = now
                windowCat?.blink(slow: true)
                onCatTapped?()
            }
            return
        }
        let door = doorPoint, reach = max(painting.size.width * 0.05, 44)
        if hypot(point.x - door.x, point.y - door.y) < reach {
            enter()
        }
    }

    /// Eases the camera in on the cat's window (a little above its middle, where the cat's head is), or back out.
    public func lookCloser(_ closer: Bool) {
        guard !entering, windowNode != nil || !closer else { return }
        closeUp = closer
        let target = closer
            ? CGPoint(x: painting.position.x + windowFrame.midX, y: painting.position.y + windowFrame.midY)
            : CGPoint(x: size.width / 2, y: size.height / 2)
        let zoom = closer ? 1 / CGFloat(Tuning.WindowCat.closeUp) : 1
        let move = SKAction.group([
            .move(to: target, duration: Tuning.WindowCat.closeUpSeconds),
            .scale(to: zoom, duration: Tuning.WindowCat.closeUpSeconds),
        ])
        move.timingMode = .easeInEaseOut
        cameraNode.removeAllActions()
        cameraNode.run(move)
    }

    override public func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 1.0 / 20) } ?? 0
        lastUpdate = currentTime
        windowCat?.step(dt)
        doorCat?.step(dt)
    }

    // MARK: The cutscene's greeting

    /// The cat that came to the door (the opening cutscene).
    public private(set) var doorCat: CatNode?

    /// The opening cutscene (docs/LADDER.md): the door opens and the cat walks out onto the step towards you, then
    /// sits. Use on a showcase, so the door never opens by itself.
    public func greet(_ cat: CatNode) {
        guard doorCat == nil else { return }
        removeAction(forKey: "autoAdvance")
        onDoorOpens?()
        if doorOpen.texture != nil {
            doorOpen.removeAllActions()
            doorOpen.run(.fadeIn(withDuration: Tuning.Exterior.doorOpenSeconds))
        }
        let height = painting.size.height * CGFloat(Tuning.Cutscene.catHeight)
        cat.childNode(withName: "shadow")?.isHidden = true
        cat.setScale(1)
        cat.show(.front, facingRight: true)
        let scale = height / max(1, cat.bodyFrame.height)
        cat.setScale(scale)
        // Its feet on the threshold, the bottom of the door.
        cat.position = CGPoint(x: doorPoint.x, y: doorPoint.y - painting.size.height * CGFloat(Tuning.Cutscene.thresholdDrop))
        cat.zPosition = 1.5
        cat.alpha = 0
        addChild(cat)
        doorCat = cat
        let walk = CGFloat(Tuning.Cutscene.walkSeconds)
        let open = Tuning.Exterior.doorOpenSeconds
        cat.run(.sequence([
            .wait(forDuration: open * 0.6),
            .fadeIn(withDuration: 0.4),
            .run { [weak cat] in cat?.walk() },
            .group([
                .moveBy(x: 0, y: -painting.size.height * CGFloat(Tuning.Cutscene.walkDrop), duration: walk),
                .scale(to: scale * CGFloat(Tuning.Cutscene.walkGrowth), duration: walk),
            ]),
            .run { [weak cat] in
                cat?.stopCycle()
                _ = cat?.settle(into: .sitFront)
            },
        ]))
        // The camera leans in as the cat comes out (only closer, never off the painting's edge).
        let lean = SKAction.scale(to: cameraNode.xScale * 0.85, duration: open + walk)
        lean.timingMode = .easeInEaseOut
        cameraNode.run(lean)
    }

    // MARK: The cat at a window

    /// Puts the cat at one of the windows (`model.windows`), sitting on the inside sill behind the glass: cut to the
    /// window's panes (its bars and frame in front of it), tinted by the glass and the room's light (lamplit round
    /// its edges after dark), with the sky caught in the glass over it. It fades in, or out when `sighting` is nil.
    public func seat(_ cat: CatNode?, at sighting: WindowSighting?, fade: Bool = true) {
        if let old = windowNode {
            windowNode = nil
            windowCat = nil
            if fade {
                old.run(.sequence([.fadeOut(withDuration: Tuning.WindowCat.fadeSeconds), .removeFromParent()]))
            } else {
                old.removeFromParent()
            }
        }
        self.sighting = sighting
        guard let cat, let sighting, model.windows.indices.contains(sighting.window) else { return }
        let window = model.windows[sighting.window]
        let path = model.scene + "_glass.png"
        guard art.has(path), let (mask, seat) = Self.windowMask(art.texture(path), window: window) else { return }
        seatX = seat
        let crop = SKCropNode()
        crop.name = "windowCat"
        crop.zPosition = 0.15
        crop.maskNode = SKSpriteNode(texture: mask)
        let sky = model.sky
        // The cat, in the glass's colour and the room's light.
        let tint = SKEffectNode()
        tint.name = "tint"
        tint.shader = Self.tintShader(sky: sky)
        cat.childNode(withName: "shadow")?.isHidden = true
        cat.setScale(1)
        tint.addChild(cat)
        cat.show(.tqfront, facingRight: sighting.facingRight)
        // Sized by how tall it sits looking out, whatever it is doing.
        cat.settle(into: .sitFront, duration: 0)
        sittingHeight = max(1, cat.bodyFrame.height)
        cat.settle(into: sighting.pose.catPose, duration: 0)
        crop.addChild(tint)
        // The sky caught in the glass in front of it.
        let glass = Tuning.Sky.glassByDay, grade = Tuning.Sky.grade[sky] ?? [1, 1, 1]
        let reflection = SKSpriteNode(texture: mask)
        reflection.name = "reflection"
        reflection.color = SKColor(red: glass[0] * grade[0], green: glass[1] * grade[1], blue: glass[2] * grade[2], alpha: 1)
        reflection.colorBlendFactor = 1
        reflection.alpha = CGFloat(Tuning.WindowCat.reflection[sky] ?? 0)
        reflection.zPosition = 0.01
        crop.addChild(reflection)
        painting.addChild(crop)
        windowNode = crop
        windowCat = cat
        placeWindowCat()
        if fade {
            crop.alpha = 0
            crop.run(.fadeIn(withDuration: Tuning.WindowCat.fadeSeconds))
        }
    }

    /// The window's crop, cat and reflection placed over the painting as it is drawn now.
    private func placeWindowCat() {
        guard let crop = windowNode, let cat = windowCat, let sighting, model.windows.indices.contains(sighting.window),
              painting.size.width > 0
        else { return }
        let window = model.windows[sighting.window]
        let size = painting.size
        let frame = CGRect(
            x: (window.left - 0.5) * size.width,
            y: (1 - window.bottom) * size.height,
            width: window.width * size.width,
            height: window.height * size.height
        )
        windowFrame = frame
        crop.position = CGPoint(x: frame.midX, y: frame.midY)
        (crop.maskNode as? SKSpriteNode)?.size = frame.size
        (crop.childNode(withName: "reflection") as? SKSpriteNode)?.size = frame.size
        // Its size by the window: a sitting cat's height a share of the glass's, narrower than the glass.
        cat.setScale(1)
        var scale = frame.height * CGFloat(Tuning.WindowCat.heightShare) / sittingHeight
        let body = cat.bodyFrame
        if body.width * scale > frame.width * CGFloat(Tuning.WindowCat.widthShare) {
            scale = frame.width * CGFloat(Tuning.WindowCat.widthShare) / max(1, body.width)
        }
        cat.setScale(scale)
        let drawn = cat.bodyFrame
        // On the inside sill behind the frame, where the glass is widest, all of it inside the window.
        let room = max(0, (frame.width - drawn.width) / 2)
        let across = min(room, max(-room, (seatX - 0.5) * frame.width))
        cat.position = CGPoint(
            x: cat.position.x - drawn.midX + across,
            y: -frame.height / 2 - frame.height * CGFloat(Tuning.WindowCat.sillDrop)
        )
        // The rim's width in the tint's own pixels.
        if let tint = crop.childNode(withName: "tint") as? SKEffectNode {
            let pixels = max(1, drawn.width * cameraScreenScale), tall = max(1, drawn.height * cameraScreenScale)
            tint.shader?.uniformNamed("u_px")?.vectorFloat2Value = SIMD2(Float(1.5 / pixels), Float(1.5 / tall))
        }
    }

    /// Screen pixels per scene point.
    private var cameraScreenScale: CGFloat {
        #if os(iOS)
            (view?.contentScaleFactor ?? 2) / max(0.01, cameraNode.xScale)
        #else
            2 / max(0.01, cameraNode.xScale)
        #endif
    }

    /// The window's glass from the scene's mask as an alpha picture for the crop (the mask is grey, white the glass),
    /// and where across it the glass is widest for a cat's width (`Tuning.WindowCat.seatSpan`): a bay's middle face.
    static func windowMask(_ glass: SKTexture, window: SceneWindow) -> (SKTexture, CGFloat)? {
        let image = glass.cgImage()
        let crop = CGRect(
            x: window.left * Double(image.width),
            y: window.top * Double(image.height),
            width: window.width * Double(image.width),
            height: window.height * Double(image.height)
        ).integral
        guard let cut = image.cropping(to: crop) else { return nil }
        let width = cut.width, height = cut.height
        var grey = [UInt8](repeating: 0, count: width * height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var seat: CGFloat = 0.5
        let made: CGImage? = grey.withUnsafeMutableBytes { greyBytes in
            guard let context = CGContext(
                data: greyBytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(cut, in: CGRect(x: 0, y: 0, width: width, height: height))
            for index in 0 ..< width * height {
                let value = greyBytes[index]
                rgba[index * 4] = value
                rgba[index * 4 + 1] = value
                rgba[index * 4 + 2] = value
                rgba[index * 4 + 3] = value
            }
            // How much glass each column has, then the run of columns a cat wide with the most.
            var columns = [Double](repeating: 0, count: width)
            for row in 0 ..< height {
                for column in 0 ..< width {
                    columns[column] += Double(greyBytes[row * width + column])
                }
            }
            let span = max(1, min(width, Int(Double(width) * Tuning.WindowCat.seatSpan)))
            var run = columns[0 ..< span].reduce(0, +), best = run, start = 0
            for column in span ..< max(span, width) {
                run += columns[column] - columns[column - span]
                if run > best + 1 {
                    best = run
                    start = column - span + 1
                }
            }
            seat = (CGFloat(start) + CGFloat(span) / 2) / CGFloat(max(1, width))
            return rgba.withUnsafeMutableBytes { bytes in
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )?.makeImage()
            }
        }
        return made.map { (SKTexture(cgImage: $0), seat) }
    }

    /// The cat seen through the glass: its colours multiplied by the glass and the room's light, and after dark the
    /// lamps behind it lighting its outline.
    static func tintShader(sky: SkyPhase) -> SKShader {
        let shader = SKShader(source: """
        void main() {
            vec4 c = texture2D(u_texture, v_tex_coord);
            float around = texture2D(u_texture, v_tex_coord + vec2(u_px.x, 0.0)).a
                + texture2D(u_texture, v_tex_coord - vec2(u_px.x, 0.0)).a
                + texture2D(u_texture, v_tex_coord + vec2(0.0, u_px.y)).a
                + texture2D(u_texture, v_tex_coord - vec2(0.0, u_px.y)).a;
            float edge = clamp(c.a - around * 0.25, 0.0, 1.0) * u_rim;
            gl_FragColor = vec4(c.rgb * u_tint + u_lamp * edge * 2.5, c.a);
        }
        """)
        let tint = Tuning.WindowCat.tint[sky] ?? [1, 1, 1], lamp = Tuning.Sky.glassLit
        shader.uniforms = [
            SKUniform(name: "u_tint", vectorFloat3: SIMD3(Float(tint[0]), Float(tint[1]), Float(tint[2]))),
            SKUniform(name: "u_lamp", vectorFloat3: SIMD3(Float(lamp[0]), Float(lamp[1]), Float(lamp[2]))),
            SKUniform(name: "u_rim", float: Float(Tuning.WindowCat.rim[sky] ?? 0)),
            SKUniform(name: "u_px", vectorFloat2: SIMD2(0.01, 0.01)),
        ]
        return shader
    }

    /// The push into the door, backwards: from the doorway (the door open) out to the house, the door closing.
    private func stepOut() {
        let home = cameraNode.position, seconds = Tuning.Arrival.doorSeconds
        cameraNode.position = doorPoint
        cameraNode.setScale(1 / CGFloat(Tuning.Exterior.pushScale))
        if doorOpen.texture != nil {
            doorOpen.alpha = 1
            doorOpen.run(.sequence([
                .wait(forDuration: seconds * Tuning.WindowCat.doorClosesAt),
                .fadeOut(withDuration: Tuning.Exterior.doorOpenSeconds),
            ]))
        }
        let pull = SKAction.group([.move(to: home, duration: seconds), .scale(to: 1, duration: seconds)])
        pull.timingMode = .easeOut
        cameraNode.run(pull)
    }

    /// The door opens and the camera pushes into it; the room takes over part-way.
    public func enter() {
        guard !entering else { return }
        removeAction(forKey: "autoAdvance")
        let target = doorPoint
        entering = true
        onDoorOpens?()
        if doorOpen.texture != nil {
            doorOpen.removeAllActions()
            doorOpen.run(.fadeIn(withDuration: Tuning.Exterior.doorOpenSeconds))
        }
        let seconds = Tuning.Arrival.doorSeconds
        // From wherever stepping out had got to.
        cameraNode.removeAllActions()
        let push = SKAction.group([
            .move(to: target, duration: seconds),
            .scale(to: 1 / CGFloat(Tuning.Exterior.pushScale), duration: seconds),
        ])
        push.timingMode = .easeIn
        cameraNode.run(push)
        run(.sequence([.wait(forDuration: seconds * Tuning.Exterior.roomFadeAt), .run { [weak self] in self?.onEnter?() }]))
    }
}
