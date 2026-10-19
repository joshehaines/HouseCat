/// The behaviour table (ASSETS.md §3): mood × weather × personality → an
/// activity on a furniture affordance plus a pose. Everything the cat does is
/// an affordance plus a pose, so new furniture adds behaviour without new art.
public enum Weather: String, CaseIterable, Codable, Sendable {
    case sun
    case cloud
    case rain
    case storm
    case snow
    case fog
    case wind
    case heat

    /// Weather that sends the cat to the window.
    public var isWindowWeather: Bool {
        [.rain, .storm, .snow, .fog].contains(self)
    }

    public var isSunny: Bool {
        [.sun, .heat].contains(self)
    }
}

public enum TimeOfDay: String, CaseIterable, Codable, Sendable {
    case morning
    case midday
    case afternoon
    case evening
    case night

    /// The band for a local time, given the player's wake time and bedtime.
    public static func at(localMinutes minutes: Int, clock: DayClock) -> TimeOfDay {
        let wake = clock.wakeMinutes, bed = clock.bedtimeMinutes
        let isNight = bed > wake ? (minutes >= bed || minutes < wake) : (minutes >= bed && minutes < wake)
        if isNight {
            return .night
        }
        if minutes >= Tuning.Day.eveningStartMinutes {
            return .evening
        }
        if minutes >= Tuning.Day.afternoonStartMinutes {
            return .afternoon
        }
        if minutes >= Tuning.Day.middayStartMinutes {
            return .midday
        }
        return .morning
    }
}

public enum Mood: String, CaseIterable, Codable, Sendable {
    case content
    case hungry
    /// The first return visit after a missed day.
    case sulky
    /// The second return visit after a missed day.
    case thawing
    case sleepy
    case playful
}

public enum Affordance: String, CaseIterable, Codable, Sendable {
    case sit
    case sleep
    case hide
    case perch
    case scratch
    case eat
    case watch
    case bat
    case none
}

/// The painted resting poses in `assets/cat/poses`; movement is the puppet's.
public enum CatPose: String, CaseIterable, Codable, Sendable {
    case sitSide = "sit_side"
    case sitThreeQuarterFront = "sit_tqfront"
    case sitFront = "sit_front"
    case sitBack = "sit_back"
    case loafSide = "loaf_side"
    case loafThreeQuarterFront = "loaf_tqfront"
    case sleepCurl = "sleep_curl"
    case stretchSide = "stretch_side"
}

public enum Activity: String, CaseIterable, Codable, Sendable {
    case bowlNag
    case sulk
    case windowWatch
    case sunbeamLoaf
    case zoomies
    case nearPlayer
    case sit
    case sleep
    case hide
    case perch
    case scratch
    case knockOff
    /// Nothing to sit on: the cat loafs on the floor and says so.
    case floorLoaf
    /// A wander: a few spots about the room (or the next room), a pause and a look round at each.
    case explore

    /// The furniture affordance the activity needs, or nil if it happens on the floor.
    public var affordance: Affordance? {
        switch self {
        case .bowlNag: .eat
        case .windowWatch: .watch
        case .sit: .sit
        case .sleep: .sleep
        case .hide: .hide
        case .perch: .perch
        case .scratch: .scratch
        case .knockOff: .bat
        case .sulk, .sunbeamLoaf, .zoomies, .nearPlayer, .floorLoaf, .explore: nil
        }
    }

    /// The resting pose it settles into; nil when the puppet animates it.
    public var pose: CatPose? {
        switch self {
        case .bowlNag, .nearPlayer: .sitFront
        case .sulk, .windowWatch: .sitBack
        case .sunbeamLoaf, .floorLoaf: .loafSide
        case .sit: .sitSide
        case .sleep: .sleepCurl
        case .hide: .loafThreeQuarterFront
        case .perch: .sitThreeQuarterFront
        case .scratch: .stretchSide
        case .zoomies, .knockOff, .explore: nil
        }
    }
}

public struct BehaviourContext: Equatable, Sendable {
    public var mood: Mood
    public var weather: Weather
    public var personality: Personality
    public var timeOfDay: TimeOfDay
    /// Affordances offered by the furniture in the cat's room.
    public var available: Set<Affordance>
    /// Whether sun is shining into the room through its window.
    public var sunlit: Bool
    /// The cat's own ways (favourite spot, quirks, its hours), when known.
    public var identity: CatIdentity?
    /// What the home lacks that the cat would love, most wanted first (`Wellbeing.wants`).
    public var wants: [Want]

    public init(
        mood: Mood,
        weather: Weather,
        personality: Personality,
        timeOfDay: TimeOfDay,
        available: Set<Affordance>,
        sunlit: Bool,
        identity: CatIdentity? = nil,
        wants: [Want] = []
    ) {
        self.mood = mood
        self.weather = weather
        self.personality = personality
        self.timeOfDay = timeOfDay
        self.available = available
        self.sunlit = sunlit
        self.identity = identity
        self.wants = wants
    }
}

public struct BehaviourChoice: Equatable, Sendable {
    public var activity: Activity
    /// A line context to show with it (from Content/lines.json), if any.
    public var lineContext: String?
    /// The room it happens in (`RoomChoice`); nil: wherever the cat is.
    public var room: RoomID?
    /// The furniture it uses instead of the activity's own (no scratching post: it scratches the sofa).
    public var use: Affordance?

    public init(activity: Activity, lineContext: String? = nil, room: RoomID? = nil, use: Affordance? = nil) {
        self.activity = activity
        self.lineContext = lineContext
        self.room = room
        self.use = use
    }

    public var affordance: Affordance? {
        use ?? activity.affordance
    }

    public var pose: CatPose? {
        activity.pose
    }
}

public enum BehaviourTable {
    /// Line contexts the table can ask for.
    public static let emptyRoomLine = "home.empty_room"

    /// Weighted options for a context (before personality multipliers).
    public static func options(for context: BehaviourContext) -> [(Activity, Int)] {
        let w = Tuning.Behaviour.self
        var options: [(Activity, Int)] = []
        func add(_ activity: Activity, _ weight: Int) {
            if let need = activity.affordance, !context.available.contains(need) {
                return
            }
            options.append((activity, weight))
        }

        if context.weather.isWindowWeather {
            add(.windowWatch, w.windowWatchInWeather)
        }
        if context.sunlit, context.weather.isSunny, [.midday, .afternoon].contains(context.timeOfDay) {
            add(.sunbeamLoaf, w.sunbeam)
        }
        if context.timeOfDay == .evening || context.mood == .playful {
            add(.zoomies, context.personality == .gremlin ? w.zoomiesGremlin : w.zoomiesOther)
        }
        if context.timeOfDay == .evening {
            add(.nearPlayer, context.personality == .velcro ? w.nearPlayerVelcro : w.nearPlayerOther)
        }

        // The daily schedule: morning windowsill, midday perch, afternoon box,
        // evening sofa, night bed (SPEC "Cat brain").
        switch context.timeOfDay {
        case .morning:
            add(.windowWatch, w.scheduleFavourite)
            add(.perch, w.scheduleSecond)
        case .midday:
            add(.perch, w.scheduleFavourite)
            add(.sit, w.scheduleSecond)
        case .afternoon:
            add(.hide, w.scheduleFavourite)
            add(.sit, w.scheduleSecond)
        case .evening:
            add(.sit, w.scheduleFavourite)
            add(.perch, w.scheduleSecond)
        case .night:
            add(.sleep, w.scheduleFavourite * 2)
            add(.sit, w.scheduleSecond)
        }
        for background in [Activity.scratch, .knockOff, .sit, .sleep, .perch, .hide] {
            add(background, w.background)
        }
        // A wander now and then, more for a lively cat, never in the small hours.
        if context.timeOfDay != .night {
            add(.explore, context.personality.sliders.energy >= 0.6 ? w.exploreLively : w.explore)
        }
        return options
    }

    /// Where the cat is resting when you come home (SPEC "The session loop" 3: "wherever its brain put it for
    /// this time of day: sofa, box, windowsill, or asleep in the bedroom"): the day's schedule and the cat's
    /// favourites, only the things it settles into (no wandering, no zoomies, nothing that needs you there).
    public static func resting(_ context: BehaviourContext, rng: inout DaySeed) -> BehaviourChoice {
        let settles: Set<Activity> = [.windowWatch, .sunbeamLoaf, .sit, .sleep, .perch, .hide]
        let favourites = context.personality.favourites
        let weighted = options(for: context).filter { settles.contains($0.0) }.map { activity, weight in
            (activity, favourites.contains(activity) ? weight * Tuning.Personality.favouriteMultiplier : weight)
        }
        guard let index = rng.pick(weights: weighted.map(\.1)) else {
            return BehaviourChoice(activity: .floorLoaf, lineContext: emptyRoomLine)
        }
        return BehaviourChoice(activity: weighted[index].0)
    }

    /// Chooses what the cat does next. Deterministic for a given seed.
    public static func choose(_ context: BehaviourContext, rng: inout DaySeed) -> BehaviourChoice {
        if context.mood == .sulky {
            return BehaviourChoice(activity: .sulk)
        }
        if context.mood == .hungry, context.available.contains(.eat) {
            return BehaviourChoice(activity: .bowlNag)
        }
        let w = Tuning.Wellbeing.self
        // No bed anywhere: at night (or sleepy) it curls up on the floor, and would love a bed.
        if context.wants.contains(.bed), !context.available.contains(.sleep),
           context.timeOfDay == .night || context.mood == .sleepy, rng.below(100) < w.floorSleepPercent
        {
            return BehaviourChoice(activity: .sleep, lineContext: Want.bed.lineContext)
        }

        // A room with nothing to sit on: the cat loafs on the floor and a line says so.
        if context.available.isDisjoint(with: [.sit, .sleep, .perch]) {
            return BehaviourChoice(activity: .floorLoaf, lineContext: emptyRoomLine)
        }

        let favourites = context.personality.favourites
        var weighted: [(BehaviourChoice, Int)] = options(for: context).map { activity, weight in
            var weight = weight
            if favourites.contains(activity) {
                weight *= Tuning.Personality.favouriteMultiplier
            }
            if context.mood == .sleepy, activity == .sleep {
                weight *= 2
            }
            if context.mood == .playful, [.zoomies, .knockOff].contains(activity) {
                weight *= 2
            }
            // Nothing to bat about: a lively cat makes its own fun.
            if activity == .zoomies, context.wants.contains(.toy), context.mood == .playful || context.personality == .gremlin {
                weight *= 2
            }
            weight *= context.identity?.weight(for: activity, at: context.timeOfDay) ?? 1
            return (BehaviourChoice(activity: activity), weight)
        }
        // No scratching post: the sofa (or whatever it sits on) gets it instead.
        if context.wants.contains(.scratcher), let seat = [Affordance.sit, .sleep].first(where: context.available.contains) {
            weighted.append((BehaviourChoice(activity: .scratch, lineContext: Want.scratcher.lineContext, use: seat), Tuning.Behaviour.background * 2))
        }
        guard let index = rng.pick(weights: weighted.map(\.1)) else {
            return BehaviourChoice(activity: .floorLoaf, lineContext: emptyRoomLine)
        }
        var choice = weighted[index].0
        // Now and then it mentions what it would love.
        if choice.lineContext == nil, let want = context.wants.first, rng.below(100) < w.wantLinePercent {
            choice.lineContext = want.lineContext
        }
        return choice
    }
}

/// How the cat greets you when you come home (SPEC "The session loop" 3: personality × trust): "a Velcro cat runs
/// to you from tier 1; an Aloof cat glances up until tier 3 and only ever walks; a Gremlin ambushes from behind
/// the sofa; a Loaf lifts its head and goes back to sleep." Sulking after a missed day, it keeps its back to you.
public enum GreetingStyle: String, CaseIterable, Sendable {
    /// Runs to you and rubs along the front of the room.
    case runs
    /// Walks over and rubs.
    case walks
    /// Hides by something, then dashes out at you.
    case ambush
    /// Looks up, slow-blinks, and stays where it is.
    case glances
    /// Asleep: lifts its head, and goes back to sleep.
    case dozes
    /// Sulking: no greeting at all.
    case ignores

    /// Whether the cat comes all the way to you (the rub, and the gift it carries).
    public var comesToYou: Bool {
        [.runs, .walks, .ambush].contains(self)
    }

    public static func style(personality: Personality, trust: TrustTier, mood: Mood, asleep: Bool) -> GreetingStyle {
        switch mood {
        case .sulky:
            return .ignores
        case .thawing:
            return personality == .velcro ? .walks : asleep ? .dozes : .glances
        default:
            break
        }
        switch personality {
        case .velcro:
            return trust >= .wary ? .runs : .walks
        case .aloof:
            return trust >= .comfortable ? .walks : .glances
        case .gremlin:
            return .ambush
        case .loaf:
            if asleep {
                return trust >= .devoted ? .walks : .dozes
            }
            return trust >= .comfortable ? .walks : .glances
        }
    }
}
