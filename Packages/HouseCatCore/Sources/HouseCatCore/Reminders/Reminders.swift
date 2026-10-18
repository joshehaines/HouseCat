import Foundation

/// The player's reminder choices (SPEC "Notifications": local only, at the times they chose). Device
/// preferences, not game state: each co-owner sets their own.
public struct ReminderSettings: Codable, Equatable, Sendable {
    public var breakfast = true
    public var breakfastMinutes = Tuning.Reminders.breakfastMinutes
    public var gifts = true
    /// The evening nudge is optional and starts off.
    public var evening = false
    public var eveningMinutes = Tuning.Reminders.eveningMinutes

    public init() {}
}

/// One local notification to schedule, in the cat's voice (`lineContext` picks the line).
public struct Reminder: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case breakfast
        case gift
        case evening
    }

    /// Stable, so rescheduling replaces rather than duplicates.
    public var id: String
    public var kind: Kind
    public var at: Date
    public var lineContext: String
}

/// Which reminders to schedule (SPEC "Notifications"): breakfast at the chosen time unless the cat is already
/// fed, "brought you something" when a gift drops, and the optional evening nudge unless today's visit is in.
/// None on paused days. The app reschedules after every change, so today's fall away once they are done.
public enum ReminderRules {
    public static func plan(
        from now: Date,
        save state: HouseholdState,
        settings: ReminderSettings,
        days: Int = Tuning.Reminders.daysAhead
    ) -> [Reminder] {
        let clock = state.clock
        let today = clock.day(of: now)
        let cat = state.cats.first
        var reminders: [Reminder] = []
        for offset in 0 ..< days {
            let day = today.advanced(by: offset)
            guard !isPaused(day, state: state) else { continue }
            if settings.breakfast {
                let at = clock.date(on: day, atLocalMinutes: settings.breakfastMinutes)
                let fed = offset == 0 && cat.map { state.isFedToday($0.id) } == true
                if at > now, !fed {
                    reminders.append(Reminder(id: "breakfast.\(day.index)", kind: .breakfast, at: at, lineContext: "feed.nag_morning"))
                }
            }
            if settings.evening {
                let at = clock.date(on: day, atLocalMinutes: settings.eveningMinutes)
                if at > now, !(offset == 0 && state.visitedToday) {
                    reminders.append(Reminder(
                        id: "evening.\(day.index)",
                        kind: .evening,
                        at: at,
                        lineContext: WidgetRules.stillWaitingLine
                    ))
                }
            }
        }
        if settings.gifts {
            for gift in state.pendingGifts where gift.dropAt > now {
                reminders.append(Reminder(
                    id: "gift.\(gift.giftID).\(gift.fedDay.index)",
                    kind: .gift,
                    at: gift.dropAt,
                    lineContext: "gift.\(gift.rarity.rawValue)"
                ))
            }
        }
        return reminders.sorted { $0.at < $1.at }
    }

    private static func isPaused(_ day: GameDay, state: HouseholdState) -> Bool {
        guard let from = state.pause.from, let until = state.pause.until else { return false }
        return from <= day && day <= until
    }
}
