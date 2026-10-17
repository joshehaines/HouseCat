import HouseCatUI
import SwiftUI

@main
struct HouseCatApp: App {
    var body: some Scene {
        WindowGroup {
            RoomView()
                .ignoresSafeArea()
        }
    }
}
