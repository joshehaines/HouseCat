import HouseCatCore
import SpriteKit

/// The gift (SPEC "The session loop" 4): if one is waiting, the cat drops it at your feet during the greeting;
/// it sits on the floor in front of the cat, bobbing, until it is tapped and goes into the book.
public extension RoomScene {
    private static let giftName = "gift"

    /// Drops the gift in front of the cat.
    func dropGift(_ texture: SKTexture, after delay: TimeInterval = Tuning.Gifts.dropDelay) {
        removeGift(collected: false)
        guard let cat = director?.cat, let parent = cat.parent else { return }
        let height = CGFloat(model.catHeight * Tuning.Gifts.dropSize)
        let aspect = texture.size().width / max(1, texture.size().height)
        let gift = SKSpriteNode(texture: texture, size: CGSize(width: height * aspect, height: height))
        gift.name = Self.giftName
        gift.anchorPoint = CGPoint(x: 0.5, y: 0)
        let side: CGFloat = cat.facingRight ? 1 : -1
        let spot = CGPoint(x: cat.position.x + side * CGFloat(model.catHeight) * 0.42, y: cat.position.y - CGFloat(model.catHeight) * 0.08)
        gift.position = CGPoint(x: spot.x, y: spot.y + height)
        gift.zPosition = cat.zPosition + 0.5
        gift.alpha = 0
        parent.addChild(gift)
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: height * 0.08, duration: 0.6),
            .moveBy(x: 0, y: -height * 0.08, duration: 0.6),
        ])
        bob.timingMode = .easeInEaseOut
        let land = SKAction.move(to: spot, duration: 0.3)
        land.timingMode = .easeIn
        gift.run(.sequence([
            .wait(forDuration: delay),
            .group([.fadeIn(withDuration: 0.15), land]),
            .wait(forDuration: 0.4),
            .repeatForever(bob),
        ]))
    }

    /// Takes the gift away: up and out when collected.
    func removeGift(collected: Bool) {
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

    var hasGift: Bool {
        childNode(withName: "//\(Self.giftName)") != nil
    }

    /// Whether a scene point is on the gift (with some room for a finger).
    func isOnGift(_ point: CGPoint) -> Bool {
        guard let gift = childNode(withName: "//\(Self.giftName)") as? SKSpriteNode, let parent = gift.parent,
              gift.alpha > 0.5 else { return false }
        let pad = CGFloat(Tuning.Puppet.tapPadding)
        return gift.frame.insetBy(dx: -pad, dy: -pad).contains(convert(point, to: parent))
    }
}
