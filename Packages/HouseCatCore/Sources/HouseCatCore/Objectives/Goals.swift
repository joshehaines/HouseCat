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

    /// The board for `state` on `day`.
    public static func make(_ state: HouseholdState, objectives: ObjectivesFile, on day: GameDay) -> GoalBoard {
        func goal(_ objective: ObjectivesFile.Objective, progress: Int, done: Bool) -> Goal {
            Goal(
                id: objective.id,
                name: objective.name,
                text: objective.text,
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
        for achievement in objectives.achievements {
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
        return GoalBoard(today: today, week: week, milestones: open + milestones.filter(\.climbed))
    }
}
