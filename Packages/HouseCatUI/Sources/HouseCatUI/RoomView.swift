import HouseCatGame
import SpriteKit
import SwiftUI

/// Hosts the room scene in SwiftUI. Shared by the iPhone and iPad app and the
/// Mac menu-bar window.
public struct RoomView: View {
    @State private var scene = RoomScene(size: CGSize(width: 1024, height: 768))

    public init() {}

    public var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .accessibilityElement()
            .accessibilityLabel("Living room. Your cat is on the floor.")
    }
}

#Preview {
    RoomView()
}
