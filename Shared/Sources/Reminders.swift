import Foundation
import HouseCatCore
import UserNotifications

/// Local reminders (SPEC "Notifications": local only, at the player's own times, in the cat's voice). What
/// to schedule is HouseCatCore's `ReminderRules`; nothing is asked for until the player says yes on the card
/// after the first feed (App Review 4.5.4: opt-in, a pre-permission screen first).
@MainActor
enum Reminders {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    private static let enabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    static var settings: ReminderSettings {
        get {
            defaults.data(forKey: "reminders").flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) } ?? ReminderSettings()
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "reminders")
            reschedule()
        }
    }

    /// Whether the card has been shown (it asks once; the profile has the settings after that).
    static var asked: Bool {
        get { defaults.bool(forKey: "remindersAsked") }
        set { defaults.set(newValue, forKey: "remindersAsked") }
    }

    /// The card's yes: the system's own question, then the schedule.
    @discardableResult
    static func ask() async -> Bool {
        asked = true
        let granted = await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        reschedule()
        return granted
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func authorised() async -> Bool {
        let status = await status()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Replaces every pending reminder with the plan from now (after each change to the save, so today's
    /// breakfast and nudge fall away once they are done).
    static func reschedule() {
        guard enabled, asked else { return }
        let session = GameSession.shared
        let now = session.now()
        let plan = ReminderRules.plan(from: now, save: session.state(at: now), settings: settings)
        let name = session.cat?.name ?? "Your cat"
        let requests = plan.map { reminder in
            let content = UNMutableNotificationContent()
            content.title = name
            content.body = session.reminderLine(reminder.lineContext, id: reminder.id, at: reminder.at) ?? ""
            content.sound = .default
            content.threadIdentifier = "housecat"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.at.timeIntervalSince(now)), repeats: false)
            return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        }
        Task {
            guard await authorised() else { return }
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            for request in requests where !request.content.body.isEmpty {
                try? await center.add(request)
            }
        }
    }
}
