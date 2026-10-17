import HouseCatUI
import SwiftUI

/// The Mac menu-bar cat: a cat in the menu bar that opens the main room.
/// Feed and Pet arrive with the event log; they will count as the day's visit.
@main
struct HouseCatMacApp: App {
    var body: some Scene {
        MenuBarExtra("HouseCat", systemImage: "cat.fill") {
            VStack(spacing: 0) {
                RoomView()
                    .frame(width: 420, height: 315)
                Divider()
                HStack {
                    Button("About HouseCat") {
                        NSApplication.shared.orderFrontStandardAboutPanel(nil)
                        NSApplication.shared.activate()
                    }
                    Spacer()
                    Button("Quit HouseCat") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
                .padding(10)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
