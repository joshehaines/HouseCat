import HouseCatCore
import SpriteKit

/// The cat builder's live preview (SPEC "The session loop", onboarding: "the cat live on a sofa as you change
/// it"): the cat sitting on a rug in front of the sofa, drawn again in each look as the player changes it.
/// Now and then (and when tapped) it gets up, walks across and sits again, so the puppet is seen moving too.
@MainActor
public final class CatPreviewScene: SKScene {
    public private(set) var cat: CatNode?
    private let art: ArtLibrary
    private let catArt: CatArt
    private let rig: PuppetRig
    private var lastUpdate: TimeInterval?
    private var nextStroll: TimeInterval = Tuning.Builder.firstStrollSeconds
    private var strolling = false
    private let stage = SKNode()

    public init(size: CGSize, art: ArtLibrary, catArt: CatArt, rig: PuppetRig, look: CatLook) {
        self.art = art
        self.catArt = catArt
        self.rig = rig
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0)
        backgroundColor = SKColor(red: 0.95, green: 0.9, blue: 0.86, alpha: 1)
        addChild(stage)
        let sofa = SKSpriteNode(texture: art.texture("furniture/living/furn_living_sofa_R.png"))
        sofa.name = "sofa"
        sofa.zPosition = -2
        stage.addChild(sofa)
        let rug = SKSpriteNode(texture: art.texture("furniture/living/furn_living_rug_R.png"))
        rug.name = "rug"
        rug.zPosition = -1
        stage.addChild(rug)
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: CGFloat(Tuning.Builder.catHeight))
        cat.zPosition = 1
        stage.addChild(cat)
        cat.settle(into: .sitThreeQuarterFront, duration: 0)
        self.cat = cat
        layoutStage()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Draws the cat in the look, in whatever it is doing.
    public func show(_ look: CatLook) {
        guard let cat, cat.look != look else { return }
        cat.apply(look: look, isKitten: look.age.isKitten)
    }

    override public func didChangeSize(_: CGSize) {
        layoutStage()
    }

    /// The rug and sofa behind the cat, all scaled to fit the view with the cat at the bottom third.
    private func layoutStage() {
        let height = CGFloat(Tuning.Builder.catHeight)
        // The cat standing would be half the view's height (less in a narrow view); the sofa may run off the sides.
        stage.setScale(max(0.1, min(size.height * 0.5, size.width * 0.42) / height))
        stage.position = CGPoint(x: 0, y: size.height * 0.14)
        func fit(_ name: String, width: CGFloat, at point: CGPoint) {
            guard let node = stage.childNode(withName: name) as? SKSpriteNode, let texture = node.texture else { return }
            node.size = CGSize(width: width, height: width * texture.size().height / max(1, texture.size().width))
            node.position = point
        }
        fit("sofa", width: height * 2.7, at: CGPoint(x: height * 0.2, y: height * 0.72))
        fit("rug", width: height * 2.3, at: CGPoint(x: 0, y: height * 0.12))
    }

    #if canImport(UIKit)
        override public func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
            stroll()
        }
    #endif

    /// Up, a walk across the rug and back, and down again.
    public func stroll() {
        guard let cat, !strolling else { return }
        strolling = true
        let reach = CGFloat(Tuning.Builder.catHeight) * 0.9
        let pace = CGFloat(Tuning.Puppet.walkSpeed) * 0.6
        let walk = { (dx: CGFloat, right: Bool) -> SKAction in
            .sequence([
                .run { cat.turn(to: .side, facingRight: right)
                    cat.walk()
                },
                .moveBy(x: dx, y: 0, duration: TimeInterval(abs(dx) / pace)),
            ])
        }
        cat.run(.sequence([
            .run { cat.rise(to: .side, facingRight: true) },
            .wait(forDuration: Tuning.Puppet.riseSeconds),
            walk(reach, true),
            walk(-reach, false),
            .run {
                cat.stopCycle()
                cat.turn(to: .tqfront, facingRight: false)
            },
            .wait(forDuration: Tuning.Puppet.turnSeconds),
            .run { cat.settle(into: .sitThreeQuarterFront) },
            .wait(forDuration: Tuning.Puppet.settleSeconds),
            .run { [weak self] in
                self?.strolling = false
            },
        ]))
    }

    override public func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(0.1, currentTime - $0) } ?? 0
        lastUpdate = currentTime
        cat?.step(dt)
        nextStroll -= dt
        if nextStroll <= 0 {
            nextStroll = Tuning.Builder.strollEverySeconds
            stroll()
        }
    }
}
