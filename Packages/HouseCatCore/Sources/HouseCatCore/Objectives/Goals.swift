import Foundation

/// Everything there is to work towards, as the Goals page shows it (Josh, 19 Oct: long-term objectives and milestones,
/// something to aim for): today's three goals and this week's three with how far along each is, and the milestones,
/// each ladder of achievements at its next step (the nearest first), all from the save and objectives.json. The
/// rules already count and pay every one of them; this is what the player sees.
public struct GoalBoard: Equatable, Sendable {
    public struct Goal: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var text: String
        public var progress: Int
        public var target: Int
        public var beans: Int
        public var done: Bool
        /// XP it pays (the path's steps; other goals pay none).
        public var xp = 0
        /// It gives an outfit or a piece of furniture.
        public var gives = false

        /// How far along, 0 to 1.
        public var fraction: Double {
            target > 0 ? min(1, Double(progress) / Double(target)) : 1
        }
    }

    /// A ladder of achievements (10, 100 and 365 meals): the step it is on and how many of its steps are done.
    public struct Milestone: Equatable, Sendable, Identifiable {
        public var id: String
        /// The step being worked towards, or the last one when the ladder is climbed.
        public var next: Goal
        public var stepsDone: Int
        public var steps: Int

        public var climbed: Bool {
            stepsDone == steps
        }
    }

    /// What the game is about, at the top of the page (Josh, 19 Oct: what is the point): the cat's trust, the home,
    /// the level.
    public struct Pillars: Equatable, Sendable {
        public var trust: TrustTier
        /// Days of care until the next tier (nil at the last).
        public var daysToNextTier: Int?
        public var roomsOpen: Int
        public var rooms: Int
        public var pieces: Int
        public var level: Int
        /// The next room to open and the level it needs (nil with every room open).
        public var nextRoom: RoomID?
    }

    /// The open chapter of the path and its steps in order (nil once the path is walked).
    public var chapter: GoalTracker.Chapter?
    public var path: [Goal]
    public var pillars: Pillars
    public var today: [Goal]
    public var week: [Goal]
    /// Unclimbed ladders nearest their next step first, then the climbed ones.
    public var milestones: [Milestone]

    public var achievementsDone: Int {
        milestones.reduce(0) { $0 + $1.stepsDone }
    }

    public var achievementsTotal: Int {
        milestones.reduce(0) { $0 + $1.steps }
    }

    /// The board for `state` on `day`; `{cat}` in the path's words becomes `catName`. Achievements on a metric in
    /// `hiding` are left out (what this build cannot count yet, e.g. `ObjectiveMetric.sharing` while sharing is off:
    /// CLAUDE.md "Nothing is shown that cannot work yet").
    public static func make(
        _ state: HouseholdState,
        objectives: ObjectivesFile,
        on day: GameDay,
        catName: String = "your cat",
        hiding: Set<ObjectiveMetric> = []
    ) -> GoalBoard {
        func fill(_ text: String) -> String {
            text.replacingOccurrences(of: "{cat}", with: catName)
        }
        func goal(_ objective: ObjectivesFile.Objective, progress: Int, done: Bool) -> Goal {
            Goal(
                id: objective.id,
                name: fill(objective.name),
                text: fill(objective.text),
                progress: min(progress, objective.target),
                target: objective.target,
                beans: objective.beans,
                done: done
            )
        }
        let today = (state.today?.objectives ?? []).compactMap { id in
            objectives.daily.first { $0.id == id }.map {
                goal($0, progress: state.today?.metrics[$0.metric] ?? 0, done: state.today?.completed.contains(id) == true)
            }
        }
        let week = (state.week?.objectives ?? []).compactMap { id in
            objectives.weekly.first { $0.id == id }.map {
                goal($0, progress: state.week?.metrics[$0.metric] ?? 0, done: state.week?.completed.contains(id) == true)
            }
        }
        // Ladders in the file's order; an achievement with no ladder is a ladder of one.
        var order: [String] = []
        var ladders: [String: [ObjectivesFile.Objective]] = [:]
        for achievement in objectives.achievements where !hiding.contains(achievement.metric) {
            let ladder = achievement.ladder ?? achievement.id
            if ladders[ladder] == nil {
                order.append(ladder)
            }
            ladders[ladder, default: []].append(achievement)
        }
        let milestones = order.compactMap { id -> Milestone? in
            guard let steps = ladders[id]?.sorted(by: { $0.target < $1.target }), let last = steps.last else { return nil }
            let done = steps.filter { state.completedAchievements.contains($0.id) }.count
            let next = steps.first { !state.completedAchievements.contains($0.id) } ?? last
            let value = state.lifetimeValue(next.metric, on: day)
            return Milestone(id: id, next: goal(next, progress: value, done: done == steps.count), stepsDone: done, steps: steps.count)
        }
        let open = milestones.filter { !$0.climbed }.sorted { $0.next.fraction > $1.next.fraction }

        // The path's open chapter, every step in order with how far along it is.
        let chapters = objectives.chapters
        let current = chapters.first { !state.pathDone.contains($0.id) }
        let path = current?.steps.map { step in
            Goal(
                id: step.id, name: fill(step.name), text: fill(step.text),
                progress: min(PathRules.value(step.definition, in: state, on: day), step.target), target: step.target,
                beans: step.beans, done: state.pathDone.contains(step.id),
                xp: step.xp, gives: step.outfit != nil || step.item != nil
            )
        } ?? []
        let chapter = current.map { chapter in
            let needed = chapter.steps.filter { $0.optional != true }
            return GoalTracker.Chapter(
                id: chapter.id, name: fill(chapter.name), when: chapter.when,
                done: needed.filter { state.pathDone.contains($0.id) }.count, of: needed.count
            )
        }

        let trust = state.cats.max { $0.careDays < $1.careDays }
        let tier = trust?.trust ?? .newcomer
        let nextTier = TrustTier(rawValue: tier.rawValue + 1)
        let pillars = Pillars(
            trust: tier,
            daysToNextTier: nextTier.map { $0.careDaysRequired - (trust?.careDays ?? 0) },
            roomsOpen: state.openedRooms.count,
            rooms: RoomID.allCases.count,
            pieces: state.placed.count,
            level: state.level,
            nextRoom: GoalTracker.nextRoom(state)
        )
        return GoalBoard(
            chapter: chapter, path: path, pillars: pillars,
            today: today, week: week, milestones: open + milestones.filter(\.climbed)
        )
    }
}
