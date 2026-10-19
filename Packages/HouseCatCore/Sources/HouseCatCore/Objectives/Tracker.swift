import Foundation

/// What the goal tracker on the room shows (Josh, 19 Oct: a bigger highlight on the objectives, as a builder game keeps
/// its next task on screen): the next goal or two, always. While the path is being walked, the open chapter's next
/// steps in order; after it, today's goal nearest done and the next big thing (the next room, then the nearest
/// milestone). Built from the save and objectives.json; the room only draws it.
public struct GoalTracker: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case path, today, week, milestone, room
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: Kind
        public var name: String
        public var text: String
        public var progress: Int
        public var target: Int
        public var beans: Int
        public var xp: Int
        /// An outfit it gives.
        public var outfit: String?
        /// A piece of furniture it gives.
        public var item: String? = nil
        /// What it asks for, so a tap can show where it is done.
        public var metric: ObjectiveMetric?
        public var room: RoomID?
        public var screen: String?

        /// How far along, 0 to 1.
        public var fraction: Double {
            target > 0 ? min(1, Double(progress) / Double(target)) : 1
        }
    }

    /// The open chapter: its name and how many of the steps it needs are done.
    public struct Chapter: Equatable, Sendable {
        public var id: String
        public var name: String
        public var when: String
        public var done: Int
        public var of: Int
    }

    public var chapter: Chapter?
    public var entries: [Entry]

    /// The tracker for `state` on `day`. `{cat}` in the words becomes `catName`; `roomTitle` names a room ("Garden",
    /// or "Balcony" upstairs).
    public static func make(
        _ state: HouseholdState,
        objectives: ObjectivesFile,
        context: RulesContext,
        catName: String,
        on day: GameDay,
        roomTitle: (RoomID) -> String = { $0.rawValue.capitalized }
    ) -> GoalTracker {
        func fill(_ text: String) -> String {
            text.replacingOccurrences(of: "{cat}", with: catName)
        }
        let slots = Tuning.Goals.trackerSlots
        if let open = PathRules.openChapter(context.path, done: state.pathDone),
           let words = objectives.chapters.first(where: { $0.id == open.id })
        {
            let needed = open.steps.filter { !$0.optional }
            let next = words.steps.filter { step in
                !state.pathDone.contains(step.id)
                    && (step.optional != true || PathRules.canAttempt(step.definition, in: state, context: context, on: day))
            }
            let entries = next.prefix(slots).map { step in
                Entry(
                    id: step.id, kind: .path, name: fill(step.name), text: fill(step.text),
                    progress: min(PathRules.value(step.definition, in: state, on: day), step.target), target: step.target,
                    beans: step.beans, xp: step.xp, outfit: step.outfit, item: step.item,
                    metric: step.metric, room: step.room, screen: step.screen
                )
            }
            return GoalTracker(
                chapter: Chapter(
                    id: open.id, name: fill(words.name), when: words.when,
                    done: needed.filter { state.pathDone.contains($0.id) }.count, of: needed.count
                ),
                entries: Array(entries)
            )
        }

        // The path walked: something for today, and something bigger.
        let board = GoalBoard.make(state, objectives: objectives, on: day)
        var entries: [Entry] = []
        let nearest = { (goals: [GoalBoard.Goal]) in goals.filter { !$0.done }.max { $0.fraction < $1.fraction } }
        if let goal = nearest(board.today) {
            entries.append(entry(goal, kind: .today, objectives: objectives, fill: fill))
        } else if let goal = nearest(board.week) {
            entries.append(entry(goal, kind: .week, objectives: objectives, fill: fill))
        }
        if let room = nextRoom(state) {
            let title = roomTitle(room).lowercased()
            if state.level < room.requiredLevel {
                let into = state.xp - LevelCurve.threshold(for: state.level)
                let span = LevelCurve.threshold(for: room.requiredLevel) - LevelCurve.threshold(for: state.level)
                entries.append(Entry(
                    id: "room.\(room.rawValue).level", kind: .room, name: "Level \(room.requiredLevel)",
                    text: "Reach level \(room.requiredLevel) to open the \(title)",
                    progress: max(0, into), target: max(1, span), beans: 0, xp: 0, room: room
                ))
            } else {
                let cost = RoomRules.cost(of: room, clubActive: state.today?.clubDay == true)
                entries.append(Entry(
                    id: "room.\(room.rawValue).open", kind: .room, name: "Open the \(title)",
                    text: "\(cost.formatted()) Beans to open it", progress: min(state.beans, cost), target: cost,
                    beans: 0, xp: 0, room: room
                ))
            }
        }
        for milestone in board.milestones where !milestone.climbed && entries.count < slots {
            entries.append(entry(milestone.next, kind: .milestone, objectives: objectives, fill: fill))
        }
        return GoalTracker(chapter: nil, entries: Array(entries.prefix(slots)))
    }

    /// The first room not yet open, in the order the levels open them.
    static func nextRoom(_ state: HouseholdState) -> RoomID? {
        RoomID.allCases.filter { !state.openedRooms.contains($0) }.min { $0.requiredLevel < $1.requiredLevel }
    }

    private static func entry(
        _ goal: GoalBoard.Goal,
        kind: Kind,
        objectives: ObjectivesFile,
        fill: (String) -> String
    ) -> Entry {
        let metric = (objectives.daily + objectives.weekly + objectives.achievements).first { $0.id == goal.id }?.metric
        return Entry(
            id: goal.id, kind: kind, name: fill(goal.name), text: fill(goal.text), progress: goal.progress,
            target: goal.target, beans: goal.beans, xp: 0, metric: metric
        )
    }

    /// Every goal met in `state`: the path's steps and chapters, today's, this week's and the milestones. A goal
    /// that is new here since the last look is one to celebrate.
    public static func met(_ state: HouseholdState) -> Set<String> {
        state.pathDone
            .union(state.today?.completed ?? [])
            .union(state.week?.completed ?? [])
            .union(state.completedAchievements)
    }
}

/// A goal just met, as the room celebrates it: its name and everything it paid.
public struct GoalReward: Equatable, Sendable {
    public var id: String
    public var name: String
    public var beans: Int
    public var xp: Int
    public var outfit: String?
    public var item: String?
    /// A chapter of the path, finished: the card says what it was and what comes next.
    public var chapter: Bool
    /// The chapter's line when it is done ("{cat} feels at home."), with the name filled in.
    public var line: String?
    /// The next chapter's name, after a chapter.
    public var next: String?

    /// What `id` paid, for a goal met (nil for an id objectives.json does not have).
    public static func of(_ id: String, objectives: ObjectivesFile, catName: String) -> GoalReward? {
        func fill(_ text: String) -> String {
            text.replacingOccurrences(of: "{cat}", with: catName)
        }
        let chapters = objectives.chapters
        if let index = chapters.firstIndex(where: { $0.id == id }) {
            let chapter = chapters[index]
            return GoalReward(
                id: id, name: fill(chapter.name), beans: chapter.beans, xp: chapter.xp, outfit: chapter.outfit, item: chapter.item,
                chapter: true, line: fill(chapter.done),
                next: chapters.indices.contains(index + 1) ? fill(chapters[index + 1].name) : nil
            )
        }
        if let step = chapters.flatMap(\.steps).first(where: { $0.id == id }) {
            return GoalReward(
                id: id, name: fill(step.name), beans: step.beans, xp: step.xp, outfit: step.outfit, item: step.item, chapter: false
            )
        }
        if let goal = (objectives.daily + objectives.weekly + objectives.achievements).first(where: { $0.id == id }) {
            return GoalReward(id: id, name: fill(goal.name), beans: goal.beans, xp: 0, chapter: false)
        }
        return nil
    }
}
