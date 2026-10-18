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

/// How the widget feels about you today (Josh, 18 Oct; Duolingo's escalating widget, without the shame): glad
/// after a visit, waiting before one, a gentle last chance in the evening while there is a streak to keep, and
/// a sulk only the next morning after a missed day.
public enum WidgetMood: String, CaseIterable, Codable, Sendable {
    case content
    case waiting
    case lastChance
    case sulking
}

public struct WidgetState: Codable, Equatable, Sendable {
    public var date: Date
    public var streak: Int
    public var visitedToday: Bool
    public var fedToday: Bool
    public var pose: WidgetPose
    /// A line context for the caption, from Content/lines.json (never hard-coded text).
    public var lineContext: String?
    /// Minutes until the game day ends (the next wake time).
    public var minutesLeftToday = 0

    public var mood: WidgetMood {
        switch pose {
        case .sulk: .sulking
        case .stillWaiting: streak > 0 ? .lastChance : .waiting
        case .waitingByDoor, .lookingOutWindow: .waiting
        default: .content
        }
    }

    /// "3 hours left today" for the last chance (whole hours, at least one), nil otherwise.
    public var hoursLeft: Int? {
        mood == .lastChance ? max(1, minutesLeftToday / 60) : nil
    }
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
            lineContext: line,
            minutesLeftToday: max(0, Int(now.clock.start(of: day.advanced(by: 1)).timeIntervalSince(date) / 60))
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

public extension WidgetPose {
    /// The painted resting pose that shows it (the widget draws no puppet): waiting faces you, the window
    /// watch is seen from behind, a sulk turns side-on.
    var catPose: CatPose {
        switch self {
        case .waitingByDoor, .stillWaiting, .holdingGift: .sitFront
        case .lookingOutWindow: .sitBack
        case .content: .sitThreeQuarterFront
        case .loaf: .loafThreeQuarterFront
        case .box, .sofa: .loafSide
        case .zoomies: .stretchSide
        case .asleep: .sleepCurl
        case .sulk: .sitSide
        }
    }
}

public extension HouseStyle {
    /// The home's window in the widget (`assets/widget/widget_<frame>[_wide].png`).
    var widgetFrame: String {
        switch self {
        case .londonTerrace: "sash"
        case .georgianTownhouse: "arched"
        case .mansionFlat: "bay"
        case .cottage: "casement"
        case .woodlandCabin: "cabin"
        case .houseboat: "porthole"
        case .mediterraneanRooftop: "shuttered"
        case .newbuildBalcony: "picture"
        }
    }
}

/// One widget entry (CLAUDE.md "The widget scene"): the cat in its pose on the home's window sill, the
/// home's sky, season and weather behind the glass, the streak on top.
public struct WidgetScene: Codable, Equatable, Sendable {
    public var state: WidgetState
    public var catPose: CatPose
    public var frame: String
    public var biome: Biome
    public var season: NatureSeason
    public var sky: SkyPhase
    public var weather: Weather
    /// From the real weather report, when there is one.
    public var temperatureC: Double?
}

/// What a widget's buttons do (SPEC "Widgets, the Duolingo layer"): Feed and Pet append the same events as
/// the app, marked as from the widget, so a widget-only day keeps the streak.
public enum WidgetAction: String, Codable, Sendable {
    case feed
    case pet
}

public extension WidgetRules {
    /// The entry at a widget state's moment: the pose's painting, the home's window and what is outside it.
    static func scene(for state: WidgetState, save: HouseholdState, weather tables: WeatherFile, report: WeatherReport?) -> WidgetScene {
        let home = save.homeNow(at: state.date, weather: tables, report: report)
        let real = save.home.season == .auto && report?.isFor(home.place) == true ? report?.hour(at: state.date) : nil
        return WidgetScene(
            state: state,
            catPose: state.pose.catPose,
            frame: (save.home.style ?? .londonTerrace).widgetFrame,
            biome: home.biome,
            season: home.season,
            sky: home.sky,
            weather: home.weather,
            temperatureC: real?.temperatureC
        )
    }

    /// The timeline's entries as scenes.
    static func scenes(
        from date: Date,
        save: HouseholdState,
        context: RulesContext,
        weather tables: WeatherFile,
        report: WeatherReport?
    ) -> [WidgetScene] {
        timeline(from: date, save: save, context: context).map { scene(for: $0, save: save, weather: tables, report: report) }
    }

    /// The event a widget button appends, or nil when there is nothing to do (the bowl is already full).
    static func event(for action: WidgetAction, at date: Date, save: HouseholdState, context: RulesContext) -> GameEvent.Kind? {
        let now = save.resolved(through: save.clock.day(of: date), context: context)
        guard let cat = now.cats.first else { return nil }
        switch action {
        case .feed: return now.isFedToday(cat.id) ? nil : .fed(catID: cat.id)
        case .pet: return .petted(catID: cat.id)
        }
    }
}

/// When to ask the player to put the cat on the Home Screen (Josh, 18 Oct; Liven's add-widget prompt): once after
/// the first feed, and once more on the third day of care, never when the widget is already there.
public enum WidgetPromptRules {
    public enum Ask: String, CaseIterable, Sendable {
        case firstFeed
        case thirdDay
    }

    public static func due(_ state: HouseholdState, asked: Set<String>, installed: Bool) -> Ask? {
        guard !installed else { return nil }
        if (state.cats.first?.careDays ?? 0) >= Tuning.Widget.promptCareDay, !asked.contains(Ask.thirdDay.rawValue) {
            return .thirdDay
        }
        if state.lifetime.feeds > 0, !asked.contains(Ask.firstFeed.rawValue), !asked.contains(Ask.thirdDay.rawValue) {
            return .firstFeed
        }
        return nil
    }
}
