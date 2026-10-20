import Foundation

/// What a cat would love its home to have (SPEC: "Furniture carries cat behaviours"; Josh, 19 Oct: a cat in an empty
/// home should feel it). Each is a kind of furniture, by what the cat does with it. Nothing is ever lost for the
/// lack of one: the cat makes do (the floor, the sofa's side) and says what it would love.
public enum Want: String, CaseIterable, Codable, Sendable {
    case bed
    case seat
    case scratcher
    case hideaway
    case perch
    case window
    case toy

    /// What a piece of furniture must let the cat do to answer it.
    public var affordance: Affordance {
        switch self {
        case .bed: .sleep
        case .seat: .sit
        case .scratcher: .scratch
        case .hideaway: .hide
        case .perch: .perch
        case .window: .watch
        case .toy: .bat
        }
    }

    /// The line the cat says while it has not got it (Content/lines.json).
    public var lineContext: String {
        "want.\(rawValue)"
    }

    /// In words, for the profile ("would love a soft bed").
    public var phrase: String {
        switch self {
        case .bed: "a soft bed"
        case .seat: "a comfy seat"
        case .scratcher: "something to scratch"
        case .hideaway: "a box to hide in"
        case .perch: "somewhere up high"
        case .window: "somewhere to watch from"
        case .toy: "something to bat about"
        }
    }

    /// The line when it gets one.
    public static let metLine = "want.met"
}

/// How settled and happy the cat is, in words (never anything sadder than "settling in").
public enum Contentment: Int, CaseIterable, Comparable, Codable, Sendable {
    case settlingIn
    case comfortable
    case happy
    case overTheMoon

    public var title: String {
        switch self {
        case .settlingIn: "Settling in"
        case .comfortable: "Comfortable"
        case .happy: "Happy"
        case .overTheMoon: "Couldn't be happier"
        }
    }

    /// After the cat's name: "Pip is settling in", "Pip couldn't be happier".
    public var phrase: String {
        switch self {
        case .settlingIn: "is settling in"
        case .comfortable: "is comfortable"
        case .happy: "is happy"
        case .overTheMoon: "couldn't be happier"
        }
    }

    public static func < (a: Contentment, b: Contentment) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// The cat's own ways, the same every day for the same cat (from the household's seed and the cat's id), nudged by
/// its personality: where it most likes to be, two quirks, and whether it is a morning cat or a night owl. They
/// bias what it chooses to do and are listed on its profile.
public struct CatIdentity: Equatable, Sendable {
    public enum Spot: String, CaseIterable, Sendable {
        case high
        case soft
        case hidden
        case sunny
        case window
        case nearYou

        /// The activity it favours for it.
        public var activity: Activity {
            switch self {
            case .high: .perch
            case .soft: .sleep
            case .hidden: .hide
            case .sunny: .sunbeamLoaf
            case .window: .windowWatch
            case .nearYou: .nearPlayer
            }
        }

        public var phrase: String {
            switch self {
            case .high: "Happiest somewhere up high"
            case .soft: "Picks the softest spot in the house"
            case .hidden: "Loves a good hiding place"
            case .sunny: "Follows the sun round the house"
            case .window: "Never misses what goes on outside"
            case .nearYou: "Likes to be wherever you are"
            }
        }

        /// The kind of furniture it most wants for it, if there is one.
        var want: Want? {
            switch self {
            case .high: .perch
            case .soft: .bed
            case .hidden: .hideaway
            case .sunny, .window: .window
            case .nearYou: .seat
            }
        }
    }

    public enum Quirk: String, CaseIterable, Sendable {
        case chattersAtBirds
        case tuckedLoaf
        case followsYou
        case lovesBoxes
        case sunWorshipper
        case chatty
        case curlsTight

        public var phrase: String {
            switch self {
            case .chattersAtBirds: "Chatters at the birds"
            case .tuckedLoaf: "Loafs with its paws tucked right in"
            case .followsYou: "Follows you from room to room"
            case .lovesBoxes: "Cannot pass an empty box"
            case .sunWorshipper: "Sleeps in any patch of sun"
            case .chatty: "Has a lot to say"
            case .curlsTight: "Sleeps curled up as tight as a bun"
            }
        }
    }

    public enum Hours: String, CaseIterable, Sendable {
        case morning
        case nightOwl

        public var phrase: String {
            switch self {
            case .morning: "A morning cat"
            case .nightOwl: "A night owl"
            }
        }
    }

    public var favouriteSpot: Spot
    public var quirks: [Quirk]
    public var hours: Hours

    public init(favouriteSpot: Spot, quirks: [Quirk], hours: Hours) {
        self.favouriteSpot = favouriteSpot
        self.quirks = quirks
        self.hours = hours
    }

    /// The cat's ways, drawn once from its id and the household's seed (the same on every device, every day).
    public static func of(_ cat: CatState, household seed: UInt64) -> CatIdentity {
        var rng = DaySeed(household: seed, day: GameDay(index: 0), purpose: "identity", salt: cat.id)
        let spots = Spot.allCases
        let spotWeights = spots.map { Tuning.Identity.spotWeights[cat.personality.rawValue]?[$0.rawValue] ?? 1 }
        let spot = spots[rng.pick(weights: spotWeights) ?? 0]
        var pool = Quirk.allCases
        // A Velcro cat already follows you; an Aloof one is not the chatty sort.
        if cat.personality == .velcro {
            pool.removeAll { $0 == .followsYou }
        }
        if cat.personality == .aloof {
            pool.removeAll { $0 == .chatty }
        }
        var quirks: [Quirk] = []
        for _ in 0 ..< Tuning.Identity.quirks where !pool.isEmpty {
            quirks.append(pool.remove(at: rng.below(pool.count)))
        }
        let owl = rng.below(100) < (Tuning.Identity.nightOwlPercent[cat.personality.rawValue] ?? 50)
        return CatIdentity(favouriteSpot: spot, quirks: quirks, hours: owl ? .nightOwl : .morning)
    }

    /// The cat's ways in words, for its profile.
    public var ways: [String] {
        [favouriteSpot.phrase] + quirks.map(\.phrase) + [hours.phrase]
    }

    public func has(_ quirk: Quirk) -> Bool {
        quirks.contains(quirk)
    }

    /// How much more it likes doing something than another cat of its personality would.
    public func weight(for activity: Activity, at time: TimeOfDay) -> Int {
        var weight = 1
        if favouriteSpot.activity == activity {
            weight *= Tuning.Identity.favouriteSpotMultiplier
        }
        switch activity {
        case .hide where has(.lovesBoxes), .sunbeamLoaf where has(.sunWorshipper), .windowWatch where has(.chattersAtBirds),
             .sleep where has(.curlsTight):
            weight *= Tuning.Identity.quirkMultiplier
        case .zoomies where hours == .morning && time == .morning, .zoomies where hours == .nightOwl && [.evening, .night].contains(time):
            weight *= Tuning.Identity.quirkMultiplier
        case .sleep where hours == .nightOwl && time == .morning, .sleep where hours == .morning && time == .evening:
            weight *= Tuning.Identity.quirkMultiplier
        default:
            break
        }
        return weight
    }
}

/// How the cat is doing: what its home has of what it cares about, today's fuss and how well it knows you, in one
/// number and in words, and what it would love next. Derived from the save; nothing in it is ever taken away.
public struct Wellbeing: Equatable, Sendable {
    /// What it would love next, most wanted first (only what no open room has).
    public var wants: [Want]
    /// The share of what it cares about that the home has (0–1).
    public var comfort: Double
    /// Today's fuss: fed, stroked, played with (0–1).
    public var care: Double
    /// All together (0–1).
    public var score: Double
    public var level: Contentment

    /// - Parameter offers: what the open rooms' furniture lets the cat do (`RoomChoice.offers`, merged).
    public static func of(_ cat: CatState, identity: CatIdentity, offers: Set<Affordance>, today: DayTally?) -> Wellbeing {
        let t = Tuning.Wellbeing.self
        let weights = Dictionary(uniqueKeysWithValues: Want.allCases.map { ($0, weight(of: $0, cat: cat, identity: identity)) })
        let total = weights.values.reduce(0, +)
        let had = weights.filter { offers.contains($0.key.affordance) }.values.reduce(0, +)
        let comfort = total > 0 ? had / total : 1
        let fed = today?.fedCats.contains(cat.id) == true
        let strokes = min(Double(today?.pets ?? 0), t.strokesForFullCare) / t.strokesForFullCare
        let played = today?.playedAnyGame == true
        let care = (fed ? t.fedCare : 0) + strokes * t.strokeCare + (played ? t.playCare : 0)
        let trust = Double(cat.trust.rawValue) / Double(TrustTier.allCases.count - 1)
        let score = min(1, comfort * t.homeShare + care * t.careShare + trust * t.trustShare)
        let level = Contentment.allCases.last { score >= t.levelFrom[$0.rawValue] } ?? .settlingIn
        let wants = Want.allCases.filter { !offers.contains($0.affordance) }
            .sorted { (weights[$0] ?? 0, $1.rawValue) > (weights[$1] ?? 0, $0.rawValue) }
        return Wellbeing(wants: wants, comfort: comfort, care: care, score: score, level: level)
    }

    /// How much a cat cares about a kind of furniture: its personality's favourites and its own favourite spot count most.
    static func weight(of want: Want, cat: CatState, identity: CatIdentity) -> Double {
        var weight = Tuning.Wellbeing.wantWeight[want.rawValue] ?? 1
        weight *= Tuning.Wellbeing.personalityWant[cat.personality.rawValue]?[want.rawValue] ?? 1
        if identity.favouriteSpot.want == want {
            weight *= Tuning.Wellbeing.favouriteSpotWant
        }
        if want == .hideaway, identity.has(.lovesBoxes) {
            weight *= Tuning.Wellbeing.favouriteSpotWant
        }
        return weight
    }
}
