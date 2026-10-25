import Foundation

/// What the cat calls the player (asked, optionally, with the cat's own name; Josh, 25 Oct: the onboarding research,
/// "the cat never learns your name"). On this device only: each co-owner has their own.
@MainActor
enum PlayerName {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var current: String? {
        get { defaults.string(forKey: "player.name").flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "player.name") }
    }
}
