/// One window of a painted exterior (assets/world/scenes/scenes.json "windows", measured from the scene's glass mask
/// by tools/asset-pipeline/scenes.py windows): its glass as fractions of the painting (x right, y down) and its row
/// counted up from the ground floor's (0). Only windows big enough for the cat to sit in are listed; the door's glass,
/// skylights, basements and reflections in water are left out.
public struct SceneWindow: Codable, Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var row: Int

    public init(left: Double, top: Double, right: Double, bottom: Double, row: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.row = row
    }

    /// scenes.json keeps each window as [left, top, right, bottom, row].
    public init?(_ numbers: [Double]) {
        guard numbers.count == 5 else { return nil }
        self.init(left: numbers[0], top: numbers[1], right: numbers[2], bottom: numbers[3], row: Int(numbers[4]))
    }

    public var width: Double {
        right - left
    }

    public var height: Double {
        bottom - top
    }

    public var area: Double {
        width * height
    }

    public var middleX: Double {
        (left + right) / 2
    }
}

/// How the cat shows at a window, seen from the street: the resting painting it is drawn in.
public enum WindowPose: String, CaseIterable, Codable, Sendable {
    /// Sitting on the sill looking out at you.
    case lookingOut
    /// Sitting side on, watching the street go by.
    case watchingStreet
    /// Loafed on the sill.
    case loafing
    /// Curled up asleep on the sill.
    case asleep
    /// Sitting with its back to the glass (a sulk).
    case backTurned

    public var catPose: CatPose {
        switch self {
        case .lookingOut: .sitFront
        case .watchingStreet: .sitSide
        case .loafing: .loafThreeQuarterFront
        case .asleep: .sleepCurl
        case .backTurned: .sitBack
        }
    }
}

/// The cat at a window: which of the scene's windows, how it sits there and which way it faces.
public struct WindowSighting: Equatable, Sendable {
    public var window: Int
    public var pose: WindowPose
    public var facingRight: Bool

    public init(window: Int, pose: WindowPose, facingRight: Bool) {
        self.window = window
        self.pose = pose
        self.facingRight = facingRight
    }
}

/// Where the cat shows from outside (Josh, 20 Oct: "a way to view your house from the outside as well and then have
/// your cat in the window"): a window on the floor of the room it is in, the one it likes changing through the day,
/// sitting there as it is doing inside.
public enum WindowCatRules {
    /// What the app knows about the cat inside.
    public struct Context: Sendable {
        /// The storey of the room it is in (0 the ground floor) and how many storeys the home's plan has.
        public var storey: Int
        public var storeys: Int
        /// What it is doing in there; nil when nobody has looked (the window then goes by the time of day).
        public var activity: Activity?
        public var mood: Mood?
        public var sky: SkyPhase
        /// It is watching you: you have just stepped out with a cat that follows you, or come home to one that runs
        /// to greet you. It is at the ground floor's window nearest the door, looking out.
        public var watchingYou: Bool
        /// The door's place across the painting (a fraction), for the window nearest it.
        public var door: Double?

        public init(
            storey: Int,
            storeys: Int,
            activity: Activity?,
            mood: Mood? = nil,
            sky: SkyPhase,
            watchingYou: Bool = false,
            door: Double? = nil
        ) {
            self.storey = storey
            self.storeys = storeys
            self.activity = activity
            self.mood = mood
            self.sky = sky
            self.watchingYou = watchingYou
            self.door = door
        }
    }

    /// The window and pose, or nil for a scene with no window to sit in. The same household, day and part of the day
    /// (`Tuning.WindowCat.slotMinutes`) always give the same window, so it moves window to window through the day
    /// and the app and any other surface agree.
    public static func sighting(
        windows: [SceneWindow],
        context: Context,
        household: UInt64,
        day: GameDay,
        minutes: Int
    ) -> WindowSighting? {
        guard !windows.isEmpty else { return nil }
        let slot = max(0, minutes) / Tuning.WindowCat.slotMinutes
        var rng = DaySeed(household: household, day: day, purpose: "window.cat", salt: "\(slot)")
        if context.watchingYou {
            let ground = windows.indices.filter { windows[$0].row == windows.map(\.row).min() }
            let door = context.door ?? 0.5
            let near = ground.min { abs(windows[$0].middleX - door) < abs(windows[$1].middleX - door) } ?? 0
            return WindowSighting(window: near, pose: .lookingOut, facingRight: windows[near].middleX < door)
        }
        let wanted = row(storey: context.storey, storeys: context.storeys, rows: Set(windows.map(\.row)).sorted())
        // Not the slim side lights of a bay or a narrow stair window, where it would hardly show.
        let widest = windows.filter { $0.row == wanted }.map(\.width).max() ?? 0
        let candidates = windows.indices.filter {
            windows[$0].row == wanted && windows[$0].width >= widest * Tuning.WindowCat.narrowest
        }
        let index: Int
        if context.activity == .windowWatch {
            // At the window: the biggest one on its floor.
            index = candidates.max { windows[$0].area < windows[$1].area } ?? candidates[0]
        } else {
            // Bigger windows more often (a bay is a favourite seat).
            let weights = candidates.map { max(1, Int((windows[$0].area * Tuning.WindowCat.areaWeight).rounded())) }
            index = candidates[rng.pick(weights: weights) ?? 0]
        }
        let seated = pose(context, rng: &rng)
        return WindowSighting(window: index, pose: seated, facingRight: rng.below(2) == 0)
    }

    /// The row of windows for a storey of the plan: the ground floor's for the ground floor, otherwise spread over
    /// the rows above (the painted homes do not always have as many rows of windows as their plans have storeys).
    public static func row(storey: Int, storeys: Int, rows: [Int]) -> Int {
        guard let lowest = rows.first else { return 0 }
        guard storey > 0, rows.count > 1 else { return lowest }
        let share = Double(min(storey, max(1, storeys - 1))) / Double(max(1, storeys - 1))
        let step = max(1, Int((share * Double(rows.count - 1)).rounded()))
        return rows[min(rows.count - 1, step)]
    }

    /// How it sits at the window: as it is inside, or by the time of day when that is not known.
    static func pose(_ context: Context, rng: inout DaySeed) -> WindowPose {
        if context.mood == .sulky || context.activity == .sulk {
            return .backTurned
        }
        switch context.activity {
        case .sulk: return .backTurned
        case .sleep: return .asleep
        case .windowWatch, .bowlNag, .nearPlayer, .zoomies, .knockOff, .explore, .scratch: return .lookingOut
        case .sunbeamLoaf, .floorLoaf, .hide: return .loafing
        case .sit, .perch: return rng.below(2) == 0 ? .lookingOut : .watchingStreet
        case nil: break
        }
        if context.mood == .sleepy {
            return .asleep
        }
        switch context.sky {
        case .night: return .asleep
        case .dusk: return .loafing
        case .dawn, .day: return rng.below(100) < Tuning.WindowCat.lookingOutPercent ? .lookingOut : .watchingStreet
        }
    }
}
