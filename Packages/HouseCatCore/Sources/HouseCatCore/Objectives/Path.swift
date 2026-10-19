import Foundation

/// One step of the path (objectives.json `path`): something to do, how far to go, and what it pays.
public struct PathStepDefinition: Hashable, Sendable, Identifiable {
    public var id: String
    public var metric: ObjectiveMetric
    public var target: Int
    /// The room a `room_pieces` step counts in.
    public var room: RoomID?
    /// The screen a `screen_seen` step asks for ("map").
    public var screen: String?
    public var beans: Int
    public var xp: Int
    public var passPoints: Int
    /// An outfit it gives (the nightcap for opening the bedroom, so the next step can be putting it on).
    public var outfit: String?
    /// A piece of furniture it gives (catalogue id).
    public var item: String?
    /// Not needed to finish the chapter (a pass step, when no season may be on); it still pays when met.
    public var optional: Bool

    public init(
        id: String,
        metric: ObjectiveMetric,
        target: Int,
        room: RoomID? = nil,
        screen: String? = nil,
        beans: Int = 0,
        xp: Int = 0,
        passPoints: Int = 0,
        outfit: String? = nil,
        item: String? = nil,
        optional: Bool = false
    ) {
        self.id = id
        self.metric = metric
        self.target = target
        self.room = room
        self.screen = screen
        self.beans = beans
        self.xp = xp
        self.passPoints = passPoints
        self.outfit = outfit
        self.item = item
        self.optional = optional
    }
}

/// A chapter of the path: the first hour, the first week, the first month. Its steps can be done in any order once it
/// is open; done, it pays its own reward and opens the next.
public struct PathChapterDefinition: Hashable, Sendable, Identifiable {
    public var id: String
    public var steps: [PathStepDefinition]
    public var beans: Int
    public var xp: Int
    public var outfit: String?
    public var item: String?

    public init(id: String, steps: [PathStepDefinition], beans: Int = 0, xp: Int = 0, outfit: String? = nil, item: String? = nil) {
        self.id = id
        self.steps = steps
        self.beans = beans
        self.xp = xp
        self.outfit = outfit
        self.item = item
    }
}

/// The path (Josh, 19 Oct: "I have been playing for 5 mins and dont know what to do"): a chain of goals that teaches
/// the game a step at a time and pays for each, in chapters. Its progress is derived like everything else: the
/// reducer marks a step done (`HouseholdState.pathDone`) the moment the save meets it, while its chapter is open.
public enum PathRules {
    /// How far along a step is.
    public static func value(_ step: PathStepDefinition, in state: HouseholdState, on day: GameDay) -> Int {
        switch step.metric {
        // What the player has put out: a new home's bowl and moving box were there already.
        case .roomPieces: step.room.map { room in
                state.placed.filter { $0.room == room && !Tuning.Room.firstHome.contains($0.itemID) }.count
            } ?? 0
        case .screenSeen: step.screen.map { state.lifetime.screensSeen.contains($0) ? 1 : 0 } ?? 0
        default: state.lifetimeValue(step.metric, on: day)
        }
    }

    public static func met(_ step: PathStepDefinition, in state: HouseholdState, on day: GameDay) -> Bool {
        value(step, in: state, on: day) >= step.target
    }

    /// A step can be tried now: the pass's need a season on, the other cats' homes a level (`Tuning.Goals.homesLevel`).
    public static func canAttempt(_ step: PathStepDefinition, in state: HouseholdState, context: RulesContext, on day: GameDay) -> Bool {
        switch step.metric {
        case .passTiersClaimed, .seasonsCompleted: context.season(on: day) != nil
        case .homesVisited: state.level >= Tuning.Goals.homesLevel
        default: true
        }
    }

    /// Every step the chapter needs is done.
    public static func isComplete(_ chapter: PathChapterDefinition, done: Set<String>) -> Bool {
        chapter.steps.allSatisfy { $0.optional || done.contains($0.id) }
    }

    /// The chapter being worked through, or nil once the whole path is done.
    public static func openChapter(_ path: [PathChapterDefinition], done: Set<String>) -> PathChapterDefinition? {
        path.first { !done.contains($0.id) }
    }
}
