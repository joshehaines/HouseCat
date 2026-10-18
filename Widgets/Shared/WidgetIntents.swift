import AppIntents
import Foundation
import HouseCatCore
import UserNotifications
import WidgetKit

/// The widget's Feed button (SPEC "Widgets": App Intents for the buttons, reloads free and immediate).
struct FeedCatIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed the cat"
    static let description = IntentDescription("Fills the bowl. It counts as today's visit.")

    func perform() async throws -> some IntentResult {
        try WidgetActions.run(.feed)
        return .result()
    }
}

/// The widget's Pet button.
struct PetCatIntent: AppIntent {
    static let title: LocalizedStringResource = "Pet the cat"
    static let description = IntentDescription("A stroke from the Home Screen. It counts as today's visit.")

    func perform() async throws -> some IntentResult {
        try WidgetActions.run(.pet)
        return .result()
    }
}

enum WidgetActions {
    /// Appends the button's event to the inbox, clears the reminders it has made pointless, redraws.
    static func run(_ action: WidgetAction) throws {
        guard let world = WidgetWorld.load(), let event = try world.perform(action) else { return }
        // The visit is in, and a feed is breakfast: those reminders for today go (the app reschedules the rest).
        var done = ["evening.\(event.day.index)"]
        if action == .feed {
            done.append("breakfast.\(event.day.index)")
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: done)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
