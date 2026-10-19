import Foundation
import HouseCatCore

/// The path and the goal tracker (HouseCatCore `PathRules`, `GoalTracker`), as the room reads them, and the two
/// things the app tells the save so the path can count them: a screen found, a piece the cat has tried.
extension GameSession {
    /// What the tracker on the room shows now. `roomTitle` names a room as this home has it (a garden upstairs is
    /// the balcony).
    func goalTracker(roomTitle: @escaping (RoomID) -> String) -> GoalTracker? {
        guard let objectives = content?.objectives else { return nil }
        let date = now()
        let state = state(at: date)
        return GoalTracker.make(
            state, objectives: objectives, context: rules, catName: cat?.name ?? "your cat",
            on: state.clock.day(of: date), roomTitle: roomTitle
        )
    }

    /// Every goal met so far: the path's steps and chapters, today's, this week's and the milestones.
    func goalsMet() -> Set<String> {
        GoalTracker.met(state(at: now()))
    }

    /// What a goal just met paid, for its celebration.
    func reward(for goal: String) -> GoalReward? {
        content.flatMap { GoalReward.of(goal, objectives: $0.objectives, catName: cat?.name ?? "your cat") }
    }

    /// A screen opened ("map"): written to the save the first time only.
    func saw(_ screen: String) {
        guard !state(at: now()).lifetime.screensSeen.contains(screen) else { return }
        append(.screenSeen(screen), at: now())
    }

    /// The cat set off to a piece by itself: the first time it uses one that is out, the save records it (its XP,
    /// and the goals for what it loves).
    @discardableResult
    func catUses(_ item: String?) -> Bool {
        let state = state(at: now())
        guard let item, state.placedCount(of: item) > 0, !state.lifetime.usedItems.contains(item) else { return false }
        append(.catUsedNewItem(catID: Self.catID, itemID: item), at: now())
        return true
    }
}
