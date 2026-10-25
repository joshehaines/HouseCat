import HouseCatCore
import SwiftUI

/// How far in from the screen's side each corner's controls go to clear a camera in that corner
/// (`Tuning.Stage.cameraCornerBand`): the controls stay out at the edges, as Josh wants, but never under iPhone Duo's
/// outer camera. Read from a GeometryReader that ignores the safe area, so its frame is the whole screen; a fold or
/// a turn of the phone lays the view out again, and the regions with it.
struct CameraClearance: Equatable {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0

    init() {}

    init(_ geometry: GeometryProxy, edge: CGFloat) {
        guard #available(iOS 27.1, *) else { return }
        let size = geometry.size
        let band = size.height * Tuning.Stage.cameraCornerBand
        let gap = CGFloat(Tuning.Stage.cameraGap)
        for region in geometry.reservedRegions(kind: .occlusion) where region.isActive {
            let frame = region.frame
            let top = frame.minY < band, bottom = frame.maxY > size.height - band
            if frame.midX < size.width / 2 {
                let inset = max(0, frame.maxX + gap - edge)
                if top { topLeading = max(topLeading, inset) }
                if bottom { bottomLeading = max(bottomLeading, inset) }
            } else {
                let inset = max(0, size.width - frame.minX + gap - edge)
                if top { topTrailing = max(topTrailing, inset) }
                if bottom { bottomTrailing = max(bottomTrailing, inset) }
            }
        }
    }
}
