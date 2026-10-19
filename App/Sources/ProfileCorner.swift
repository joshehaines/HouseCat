import HouseCatCore
import HouseCatUI
import SwiftUI

extension CatScreens {
    /// The painted corner the cat sits in on its profile (assets/ui/profile, 19 Oct): the sunny window by day and
    /// at dawn, the fireside from dusk, at the home's own time. Where the cushion is and how tall the cat stands on
    /// it are measured on each painting (2688 x 1520).
    static func profileCorner() -> ProfileCorner? {
        let session = GameSession.shared
        let now = session.now()
        let sky = GameWorld.skyPhase(at: now, state: session.state(at: now))
        let evening = sky == .dusk || sky == .night
        let path = evening ? "ui/profile/profile_corner_fire.jpg" : "ui/profile/profile_corner_sun.jpg"
        guard let image = GameWorld.art?.image(path) else { return nil }
        let k = CGFloat(image.width) / 2688
        return evening
            ? ProfileCorner(image: image, perch: CGPoint(x: 870 * k, y: 1120 * k), catHeight: 0.5)
            : ProfileCorner(image: image, perch: CGPoint(x: 930 * k, y: 1010 * k), catHeight: 0.47)
    }
}
