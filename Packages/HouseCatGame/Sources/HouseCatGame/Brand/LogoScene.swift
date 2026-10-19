import HouseCatCore
import SpriteKit
#if canImport(UIKit)
    import UIKit
#endif

/// The HouseCat logo come alive (Josh, 19 Oct, after a reel where a little dog hops onto its wordmark): Midnight runs
/// in along the letters' baseline, leaps over the H onto the lowercase letters, looks round at you, turns away, sits
/// and curls up asleep on top of them, breathing. It is the game's own puppet and painted poses, so it matches the
/// room and costs no download.
///
/// The scene draws only the cat, its shadow and, over a dark background, a soft light behind it so the black cat
/// reads. The wordmark is drawn by whoever shows the scene, which says where the wordmark's box is (`box`): the launch
/// curtain draws the launch screen's own picture, so the hand-over from the still launch screen is exact. Lengths are
/// in the box's pixels from its bottom left (assets/brand/logo/wordmark_on_*.png, `Tuning.Logo`). See-through.
@MainActor
public final class LogoScene: SKScene {
    /// What the logo is drawn over: a light background with dark letters (the launch screen), or a dark one with
    /// cream letters (the intro's night sky, the launch screen in dark mode).
    public enum Ink: Sendable {
        case light
        case dark
    }

    /// How it plays: the launch's quicker telling, the intro's whole scene with a look round at you before it sleeps,
    /// or (Reduce Motion) the cat already asleep and still.
    public enum Act: Sendable {
        case launch
        case intro
        case still
    }

    /// Where the wordmark's box is in the scene (points, from the bottom left). Set by the view that shows the scene
    /// whenever its layout changes.
    public var box: CGRect = .zero {
        didSet { layOut() }
    }

    /// The cat has curled up (it breathes from then on).
    public private(set) var asleep = false

    /// The landing and curling up as a generated film's frames (Higgsfield, Kling 3.0, keyed off green by
    /// tools/asset-pipeline/logo/curlkey.py), played in place of the puppet sitting and curling when given (set before
    /// the scene first updates): they start on the puppet standing as it lands and end on the curl painting.
    public var curlFrames: [SKTexture] = []
    public var curlFrameRate = 24.0

    public let cat: CatNode
    private let act: Act
    /// The box's pixels, scaled and placed over the box.
    private let stage = SKNode()
    /// The cat's middle, which it leans round in a leap and grows about as it curls up; the cat hangs under it with
    /// its feet at the stage point.
    private let pivot = SKNode()
    private let shadow: SKSpriteNode
    private let glow: SKSpriteNode?
    /// The curl film's frame on show, standing in for the cat (its feet at the bottom middle).
    private let filmCat = SKSpriteNode()
    /// How far through the curl film (0 to 1), while it plays and after.
    private var filmProgress: CGFloat?
    private var feet = CGPoint.zero
    private var beats: [Beat] = []
    private var current: Beat?
    private var elapsed: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var from = CGPoint.zero
    /// How fast the cat is going along the letters as a beat begins (it runs on into a leap).
    private var speedNow: CGFloat = 0
    /// The leap under way has left the ground, and has come down.
    private var airborne = false
    private var landed = false
    /// The legs' resting angles, while they stretch out in a leap.
    private var legRest: [String: CGFloat] = [:]
    private var lastUpdate: TimeInterval?
    private var started = false

    private typealias Logo = Tuning.Logo

    private enum Beat {
        case wait(TimeInterval)
        /// Along the tops of the letters (or the ground) to an x, at a speed; slowing to a stop or running on.
        case run(to: CGFloat, speed: CGFloat, gait: CatNode.Gait, stopping: Bool)
        /// A crouch (on the run, if it is running; none for a leap that starts out of sight), a leap in an arc to a
        /// point taking so long in the air and its feet going so high, and the landing.
        case leap(to: CGPoint, seconds: TimeInterval, top: Double, crouch: TimeInterval)
        case face(CatNode.View, right: Bool)
        /// Into a painted pose: from the puppet it sits down into it, from another painting it cross-fades; growing
        /// to a scale as it goes.
        case settle(CatPose, scale: CGFloat)
        /// The curl film in the cat's place.
        case film
        case call(@MainActor () -> Void)
    }

    /// The cat is the painted mascot, the plain black short-haired set (`cat/base/short_slim`, `cat/poses/plain`): lit
    /// warm from behind like the brand's cat, so it reads on cream and on the night sky, and nothing to tint.
    public init(size: CGSize, art: ArtLibrary, rig: PuppetRig, ink: Ink, act: Act) {
        self.act = act
        let height = CGFloat(Logo.catHeight)
        cat = CatNode(art: art, rig: rig, height: height)
        shadow = Self.softDisc(colour: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        glow = ink == .dark ? Self.softDisc(colour: CGColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)) : nil
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        // Transparent black: in a see-through view the clear colour's own red, green and blue show through every
        // half-clear pixel (UIColor.clear is black too; this says so).
        backgroundColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0)
        addChild(stage)
        if let glow {
            glow.zPosition = -2
            glow.alpha = CGFloat(Logo.glowAlpha)
            glow.size = CGSize(width: height * CGFloat(Logo.glowSize), height: height * CGFloat(Logo.glowSize))
            stage.addChild(glow)
        }
        // The puppet's own shadow is a shape node, which draws pale rather than dark in a see-through view: a soft
        // sprite stands in for it.
        cat.childNode(withName: "shadow")?.isHidden = true
        shadow.zPosition = -1
        stage.addChild(shadow)
        stage.addChild(pivot)
        cat.position = CGPoint(x: 0, y: -height * CGFloat(Logo.pivotHeight))
        pivot.addChild(cat)
        filmCat.anchorPoint = CGPoint(x: 0.5, y: 0)
        filmCat.isHidden = true
        stage.addChild(filmCat)
        if act == .still {
            curlUp()
        } else {
            // Off to the left, running; the first frame is the wordmark alone, as the launch screen shows it.
            feet = CGPoint(x: -CGFloat(Logo.boxSize[0]) * 3, y: CGFloat(Logo.baseline))
            cat.show(.side, facingRight: true)
            cat.move(.run)
        }
        place()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didChangeSize(_: CGSize) {
        layOut()
    }

    override public func didMove(to _: SKView) {
        layOut()
    }

    /// Scales the stage so the box's pixels cover `box`.
    private func layOut() {
        guard box.width > 0 else { return }
        stage.setScale(box.width / CGFloat(Logo.boxSize[0]))
        stage.position = box.origin
    }

    /// The left edge of what can be seen, in the box's pixels: the screen's edge when the scene runs past it.
    private var visibleLeft: CGFloat {
        var left: CGFloat = 0
        #if canImport(UIKit)
            if let view, let window = view.window {
                left = convertPoint(fromView: view.convert(CGPoint(x: window.bounds.minX, y: 0), from: window)).x
            }
        #endif
        return stage.convert(CGPoint(x: max(left, 0), y: 0), from: self).x
    }

    // MARK: The story

    private func begin() {
        started = true
        let h = CGFloat(Logo.catHeight)
        // Just out of sight on the left, whatever the screen.
        feet.x = visibleLeft - h * CGFloat(act == .launch ? Logo.launchOffscreen : Logo.offscreen)
        var story: [Beat] = []
        if act == .launch {
            // The launch has a moment while the home is built: one pounce from off the edge onto its spot, as the
            // little dog in Josh's reel leaps onto its letters.
            story.append(.leap(
                to: CGPoint(x: Logo.bed, y: Logo.valleyTop),
                seconds: Logo.launchLeapSeconds,
                top: Logo.launchLeapTop,
                crouch: 0
            ))
        } else {
            // With the curl film it lands straight on its spot, where the film takes over at once; without, it trots
            // the last step.
            let film = !curlFrames.isEmpty
            story += [
                .wait(Logo.introHold),
                .run(to: CGFloat(Logo.takeOff), speed: CGFloat(Logo.runSpeed) * h, gait: .run, stopping: false),
                .leap(
                    to: CGPoint(x: film ? Logo.bed : Logo.landing, y: Logo.valleyTop),
                    seconds: Logo.leapSeconds,
                    top: Logo.leapTop,
                    crouch: Logo.crouchSeconds
                ),
            ]
            if !film {
                story.append(.run(to: CGFloat(Logo.bed), speed: CGFloat(Logo.trotSpeed) * h, gait: .trot, stopping: true))
            }
        }
        if !curlFrames.isEmpty {
            // The film takes over from the cat standing side on, facing the way it came (it sniffs the letters, turns
            // and sits looking at you, and curls up).
            story += [.film, .call { [weak self] in self?.asleep = true }]
            beats = story
            next()
            return
        }
        if act == .intro {
            // A look round at you first.
            story += [.face(.front, right: false), .wait(Logo.lookSeconds)]
        }
        // It sits and curls up (on the intro it turns away first): the paintings are small beside the puppet, so it
        // fluffs up a little as it sits, to end about a letter's size; sitting first, the cross-fade into the curl is
        // painting to painting.
        let grown = CGFloat(Logo.curlScale)
        if act == .intro {
            story.append(.face(.side, right: false))
        }
        story += [
            .settle(.sitSide, scale: grown),
            .wait(act == .intro ? Logo.sitSeconds : Logo.launchSitSeconds),
            .settle(.sleepCurl, scale: grown),
            .call { [weak self] in self?.asleep = true },
        ]
        beats = story
        next()
    }

    /// Asleep where the story ends, from the start (Reduce Motion).
    private func curlUp() {
        started = true
        feet = CGPoint(x: Logo.bed, y: Logo.valleyTop)
        cat.show(.side, facingRight: false)
        cat.settle(into: .sleepCurl, duration: 0)
        pivot.setScale(CGFloat(Logo.curlScale))
        asleep = true
    }

    private func next() {
        guard !beats.isEmpty else {
            current = nil
            return
        }
        let beat = beats.removeFirst()
        current = beat
        elapsed = 0
        from = feet
        switch beat {
        case let .wait(t):
            duration = t
        case let .run(x, speed, gait, stopping):
            duration = TimeInterval(abs(x - feet.x) / max(1, speed)) * (stopping ? 2 : 1)
            cat.move(gait)
            cat.moveSpeed = speed
        case let .leap(_, seconds, _, crouch):
            // It gathers itself without stopping: a crouch on the run, then the spring.
            cat.squash(CGFloat(Tuning.Puppet.squash * Logo.leapSquash))
            airborne = false
            landed = false
            duration = crouch + seconds + Tuning.Puppet.landSeconds
        case let .face(view, right):
            cat.turn(to: view, facingRight: right)
            duration = Tuning.Puppet.turnSeconds
        case let .settle(pose, scale):
            // From the puppet, nearly a cut under the sit-down dip (a slower fade shows the standing cat and the
            // sitting one together); painting to painting, a cross-fade.
            let sitting = cat.pose == nil
            let fade = sitting ? Logo.sitFadeSeconds : Logo.curlSeconds
            cat.settle(into: pose, duration: fade, crossFade: !sitting)
            duration = fade + (sitting ? Tuning.Puppet.sitDownSeconds : 0)
            let grow = SKAction.scale(to: scale, duration: duration)
            grow.timingMode = .easeInEaseOut
            pivot.run(grow)
        case .film:
            let k = CGFloat(Logo.catHeight / Logo.curlFrameCatHeight)
            filmCat.size = CGSize(width: CGFloat(Logo.curlFrameSize[0]) * k, height: CGFloat(Logo.curlFrameSize[1]) * k)
            filmCat.texture = curlFrames.first
            filmCat.isHidden = false
            cat.isHidden = true
            filmProgress = 0
            duration = Double(curlFrames.count) / curlFrameRate
        case let .call(action):
            action()
            duration = 0
        }
    }

    override public func update(_ currentTime: TimeInterval) {
        // Never backwards (an offscreen renderer's clock can start anywhere), never a leap of more than a frame or two.
        let dt = lastUpdate.map { max(0, min(1.0 / 20, currentTime - $0)) } ?? 0
        lastUpdate = currentTime
        if !started, box.width > 0 {
            begin()
        }
        if act != .still {
            cat.step(dt)
        }
        advance(dt)
        place(dt)
    }

    private func advance(_ dt: TimeInterval) {
        guard let beat = current else { return }
        elapsed += dt
        let t = duration > 0 ? min(1, elapsed / duration) : 1
        switch beat {
        case let .run(x, speed, _, stopping):
            let k = CGFloat(t)
            // Slowing to a stop: the distance eases out, so it sets off at its speed and arrives at none.
            feet.x = from.x + (x - from.x) * (stopping ? k * (2 - k) : k)
            speedNow = stopping ? speed * (1 - k) : speed
            cat.moveSpeed = speedNow
            if t >= 1, stopping {
                cat.stopCycle()
                speedNow = 0
            }
        case let .leap(to, seconds, top, crouch):
            let air = (elapsed - crouch) / seconds
            // Where it springs from: on from the beat's start at the speed it came in at.
            let spring = CGPoint(x: from.x + speedNow * CGFloat(crouch), y: from.y)
            if air < 0 {
                feet.x = from.x + speedNow * CGFloat(elapsed)
            } else if air <= 1 {
                if !airborne {
                    airborne = true
                    cat.stopCycle()
                    legRest = (cat.parts[cat.view] ?? [:]).filter { $0.key.hasPrefix("leg_") }.mapValues(\.zRotation)
                }
                let u = CGFloat(air)
                stretch(u)
                let bump = CGFloat(top) - (spring.y + to.y) / 2
                feet.x = spring.x + (to.x - spring.x) * u
                feet.y = spring.y + (to.y - spring.y) * u + 4 * bump * u * (1 - u)
                // Nose up rising, down falling.
                let rise = (to.y - spring.y) + 4 * bump * (1 - 2 * u)
                let lean = atan2(rise, abs(to.x - spring.x)) * CGFloat(Logo.lean)
                pivot.zRotation = cat.facingRight ? lean : -lean
            } else if !landed {
                landed = true
                restLegs()
                feet = to
                pivot.zRotation = 0
                cat.squash(CGFloat(Tuning.Puppet.squash * Logo.leapSquash))
                // It lands still going: the trot after takes it on to its spot.
                speedNow = CGFloat(Logo.trotSpeed * Logo.catHeight)
            }
        case .film:
            let frame = min(curlFrames.count - 1, Int(elapsed * curlFrameRate))
            filmCat.texture = curlFrames[max(0, frame)]
            filmProgress = CGFloat(t)
        default:
            break
        }
        if t >= 1 {
            next()
        }
    }

    /// The legs through a leap (`u` from take-off to landing): the front pair reaching out ahead, the back pair pushed
    /// out behind and drawn in under it for the landing (the far legs a little behind the near ones).
    private func stretch(_ u: CGFloat) {
        guard let legs = cat.parts[cat.view] else { return }
        let reach = CGFloat(Logo.leapReach) * .pi / 180 * (1 - 0.4 * u)
        let push = CGFloat(Logo.leapPush) * .pi / 180
        let back = -push * (1 - u) * (1 - u) + push * 0.25 * u * u
        for (name, rest) in legRest {
            let angle = name.hasPrefix("leg_front") ? reach : back
            // CatNode's legs swing forward for a positive angle taken from the rest.
            legs[name]?.zRotation = rest - angle * (name.hasSuffix("far") ? 0.85 : 1)
        }
    }

    private func restLegs() {
        guard let legs = cat.parts[cat.view] else { return }
        for (name, rest) in legRest {
            legs[name]?.zRotation = rest
        }
        legRest = [:]
    }

    /// The cat at its feet, its shadow on the letter under it (or the ground), the light behind it (eased after it
    /// over `dt`, so it drifts rather than jumps when the cat sits down).
    private func place(_ dt: TimeInterval = 0) {
        let h = CGFloat(Logo.catHeight)
        let scale = pivot.xScale
        // The feet stay on the letters however big the cat is drawn.
        pivot.position = CGPoint(x: feet.x, y: feet.y + h * CGFloat(Logo.pivotHeight) * scale)
        filmCat.position = feet
        // Resting, the cat is a painting (its outline would still count the faded puppet standing behind it); in the
        // curl film it goes from standing to curled.
        let body = cat.pose == nil && filmProgress == nil ? cat.bodyFrame : .null
        let resting = h * CGFloat(Logo.restWidth * Logo.curlScale)
        var width = body.isNull ? h * CGFloat(Logo.restWidth) * scale : body.width * scale
        if let film = filmProgress {
            width = h * CGFloat(Logo.standWidth) + (resting - h * CGFloat(Logo.standWidth)) * film
        }
        // Smaller and fainter the higher the cat is above what is under it.
        let ground = surface(under: feet.x)
        let fade = max(CGFloat(Logo.shadowLeast), 1 - (feet.y - ground) / h)
        shadow.size = CGSize(
            width: width * CGFloat(Logo.shadowWidth) * fade,
            height: width * CGFloat(Logo.shadowWidth * Logo.shadowDepth) * fade
        )
        shadow.position = CGPoint(x: feet.x, y: ground)
        shadow.alpha = CGFloat(Logo.shadowAlpha) * fade
        if let glow {
            var middle = body.isNull
                ? CGPoint(x: feet.x, y: feet.y + h * CGFloat(Logo.restMiddle) * scale)
                : stage.convert(CGPoint(x: body.midX, y: body.midY), from: pivot)
            if let film = filmProgress {
                let rest = CGFloat(Logo.restMiddle * Logo.curlScale)
                middle = CGPoint(x: feet.x, y: feet.y + h * (CGFloat(Logo.standMiddle) + (rest - CGFloat(Logo.standMiddle)) * film))
            }
            let k = dt > 0 ? min(1, CGFloat(dt * Logo.glowFollow)) : 1
            glow.position = CGPoint(
                x: glow.position.x + (middle.x - glow.position.x) * k,
                y: glow.position.y + (middle.y - glow.position.y) * k
            )
        }
    }

    /// The top of whatever is under a point: a letter, or the ground the letters stand on.
    private func surface(under x: CGFloat) -> CGFloat {
        for top in Logo.tops where top.count == 3 && Double(x) >= top[0] && Double(x) <= top[1] {
            return CGFloat(top[2])
        }
        return CGFloat(Logo.baseline)
    }

    /// A soft round spot of a colour, solid in the middle and fading to nothing at the edge (the shadow, the light).
    private static func softDisc(colour: CGColor) -> SKSpriteNode {
        let pixels = 128
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let clear = colour.copy(alpha: 0),
        let gradient = CGGradient(colorsSpace: space, colors: [colour, clear] as CFArray, locations: [0, 1])
        else {
            return SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))
        }
        let middle = CGPoint(x: pixels / 2, y: pixels / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: middle,
            startRadius: 0,
            endCenter: middle,
            endRadius: CGFloat(pixels / 2),
            options: []
        )
        guard let image = context.makeImage() else {
            return SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))
        }
        return SKSpriteNode(texture: SKTexture(cgImage: image), size: CGSize(width: 1, height: 1))
    }
}
