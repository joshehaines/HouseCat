import CoreGraphics
import HouseCatCore
import HouseCatGame

extension CatScreens {
    /// The cat's head and shoulders, square, for the player's badge: its portrait (wearing what it has on) cut
    /// around the head so the ears show whole inside the ring (HouseCatGame `Headshot`).
    static func headshot(_ look: CatLook) -> CGImage? {
        guard let catArt = GameWorld.catArt, let image = portrait(look) else { return nil }
        let sprite = catArt.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look)
        return Headshot.cut(image, face: catArt.face(sprite.path))
    }
}
