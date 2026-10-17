import SwiftUI

@main
struct HouseCatWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("HouseCat")
                    .font(.headline)
                Text("Placeholder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
