import HouseCatCore
import SpriteKit

/// The gift (SPEC "The session loop" 4): if one is waiting, the cat drops it at your feet during the greeting;
/// it sits on the floor in front of the cat, bobbing, until it is tapped and goes into the book.
public extension RoomScene {
    private static let giftName = "gift"

    /// Drops the gift in front of the cat, wherever the cat is by then.
    func dropGift(_ texture: SKTexture, after delay: TimeInterval = Tuning.Gifts.dropDelay) {
        removeGift(collected: false)
        guard let cat = director?.cat else { return }
        let height = CGFloat(model.catHeight * Tuning.Gifts.dropSize)
        let aspect = texture.size().width / max(1, texture.size().height)
        let gift = SKSpriteNode(texture: texture, size: CGSize(width: height * aspect, height: height))
        gift.name = Self.giftName
        gift.anchorPoint = CGPoint(x: 0.5, y: 0)
        gift.alpha = 0
        // A soft glow under it, so it reads as something to pick up.
        let glow = SKShapeNode(ellipseOf: CGSize(width: height * 1.5, height: height * 0.55))
        glow.fillColor = SKColor(white: 1, alpha: 0.55)
        glow.strokeColor = .clear
        glow.glowWidth = height * 0.12
        glow.zPosition = -0.01
        glow.position = CGPoint(x: 0, y: height * 0.05)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        gift.addChild(glow)
        let catHeight = CGFloat(model.catHeight)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak cat] in
                guard let cat, let parent = cat.parent else { return }
                // Beside the cat at its size now (it is drawn larger near the camera).
                let near = cat.xScale.magnitude
                gift.setScale(near)
                let side: CGFloat = cat.facingRight ? 1 : -1
                let spot = CGPoint(x: cat.position.x + side * catHeight * 0.42 * near, y: cat.position.y - catHeight * 0.08 * near)
                gift.position = CGPoint(x: spot.x, y: spot.y + height * near)
                gift.zPosition = cat.zPosition + 0.5
                parent.addChild(gift)
                let land = SKAction.move(to: spot, duration: 0.3)
                land.timingMode = .easeIn
                let bob = SKAction.sequence([
                    .moveBy(x: 0, y: height * 0.08, duration: 0.6),
                    .moveBy(x: 0, y: -height * 0.08, duration: 0.6),
                ])
                bob.timingMode = .easeInEaseOut
                gift.run(.sequence([.group([.fadeIn(withDuration: 0.15), land]), .wait(forDuration: 0.4), .repeatForever(bob)]))
            },
        ]), withKey: Self.dropKey)
    }

    private static let dropKey = "gift.drop"

    /// Takes the gift away: up and out when collected.
    func removeGift(collected: Bool) {
        removeAction(forKey: Self.dropKey)
        guard let gift = childNode(withName: "//\(Self.giftName)") else { return }
        gift.name = nil
        gift.removeAllActions()
        if collected {
            gift.run(.sequence([
                .group([
                    .moveBy(x: 0, y: CGFloat(model.catHeight) * 0.6, duration: 0.45),
                    .fadeOut(withDuration: 0.45),
                    .scale(to: 1.3, duration: 0.45),
                ]),
                .removeFromParent(),
            ]))
        } else {
            gift.removeFromParent()
        }
    }

    /// A gift is on the floor, or about to land.
    var hasGift: Bool {
        childNode(withName: "//\(Self.giftName)") != nil || action(forKey: Self.dropKey) != nil
    }

    /// Whether a scene point is on the gift (with some room for a finger).
    func isOnGift(_ point: CGPoint) -> Bool {
        guard let gift = childNode(withName: "//\(Self.giftName)") as? SKSpriteNode, let parent = gift.parent,
              gift.alpha > 0.5 else { return false }
        let pad = CGFloat(Tuning.Puppet.tapPadding)
        return gift.frame.insetBy(dx: -pad, dy: -pad).contains(convert(point, to: parent))
    }
}
