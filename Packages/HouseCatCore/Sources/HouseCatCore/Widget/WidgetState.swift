import Foundation

/// What every widget shows (SPEC "Widgets, the Duolingo layer"): the streak as
/// a paw-print count and a cat pose that answers "have you visited today?".
/// Computed from the save and the clock alone, so the app and the widget agree.
public enum WidgetPose: String, CaseIterable, Codable, Sendable {
    // Before a visit
    case waitingByDoor
    case lookingOutWindow
    /// From 20:00: sitting by the door looking straight at you.
    case stillWaiting
    // After a visit
    case content
    case loaf
    case box
    case sofa
    case zoomies
    case asleep
    // Overrides
    case holdingGift
    case sulk
}

public struct WidgetState: Codable, Equatable, Sendable {
    public var date: Date
    public var streak: Int
    public var visitedToday: Bool
    public var fedToday: Bool
    public var pose: WidgetPose
    /// A line context for the caption, from Content/lines.json (never hard-coded text).
    public var lineContext: String?
}

public enum WidgetRules {
    /// The evening line when there has been no visit yet ("Still waiting." in spirit).
    public static let stillWaitingLine = "progress.streak_at_risk"
    public static let sulkLine = "missed.one_day"

    /// The widget for the main cat at `date`. `state` is the derived save (any
    /// days before `date`'s game day are closed here).
    public static func state(at date: Date, save state: HouseholdState, context: RulesContext) -> WidgetState {
        let day = state.clock.day(of: date)
        let now = state.resolved(through: day, context: context)
        let mainCat = now.cats.first
        let fed = mainCat.map { now.isFedToday($0.id) } ?? false
        let minutes = now.clock.localMinutes(of: date)
        let pose: WidgetPose
        var line: String?

        if !now.visitedToday {
            if now.missedYesterday {
                pose = .sulk
                line = sulkLine
            } else if isBedtime(minutes, clock: now.clock) || minutes >= Tuning.Widget.stillWaitingFromMinutes {
                pose = .stillWaiting
                line = stillWaitingLine
            } else if minutes >= Tuning.Widget.waitingAtWindowFromMinutes {
                pose = .lookingOutWindow
            } else {
                pose = .waitingByDoor
            }
        } else if !now.waitingGifts(at: date).isEmpty {
            pose = .holdingGift
        } else {
            pose = afterVisitPose(minutes: minutes, firstVisitAt: now.today?.firstVisitAt, date: date, clock: now.clock)
        }

        return WidgetState(
            date: date,
            streak: now.streak.current,
            visitedToday: now.visitedToday,
            fedToday: fed,
            pose: pose,
            lineContext: line
        )
    }

    /// Entries every 30 minutes from the next half hour: 48 a day, inside the
    /// widget refresh budget. App Intents reload the timeline on Feed and Pet.
    public static func timeline(from date: Date, save state: HouseholdState, context: RulesContext) -> [WidgetState] {
        let interval = Double(Tuning.Widget.entryIntervalMinutes * 60)
        let first = (date.timeIntervalSince1970 / interval).rounded(.down) * interval
        return (0 ..< Tuning.Widget.entriesPerTimeline).map { index in
            let entryDate = index == 0 ? date : Date(timeIntervalSince1970: first + Double(index) * interval)
            return Self.state(at: entryDate, save: state, context: context)
        }
    }

    private static func isBedtime(_ minutes: Int, clock: DayClock) -> Bool {
        TimeOfDay.at(localMinutes: minutes, clock: clock) == .night
    }

    private static func afterVisitPose(minutes: Int, firstVisitAt: Date?, date: Date, clock: DayClock) -> WidgetPose {
        if isBedtime(minutes, clock: clock) {
            return .asleep
        }
        if let firstVisitAt, date.timeIntervalSince(firstVisitAt) < Double(Tuning.Widget.contentMinutesAfterVisit * 60) {
            return .content
        }
        let w = Tuning.Widget.self
        if minutes >= w.zoomiesFromMinutes {
            return .zoomies
        }
        if minutes >= w.sofaFromMinutes {
            return .sofa
        }
        if minutes >= w.boxFromMinutes {
            return .box
        }
        if minutes >= w.loafFromMinutes {
            return .loaf
        }
        return .content
    }
}
