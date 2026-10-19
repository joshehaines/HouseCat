import Foundation

/// Which room the cat goes to for an activity (SPEC "Cat brain": targets are furniture affordances weighted
/// by time of day; "between rooms it walks through the doorway"). Only open rooms; the cat favours the room
/// it is in, each room type has what it is for (the bed at night, the bowl in the kitchen, the garden to
/// watch from), and otherwise any open room that offers the thing it wants.
public enum RoomChoice {
    /// What each open room offers, from the furniture placed in it.
    public static func offers(in state: HouseholdState, catalogue: [String: Set<Affordance>]) -> [RoomID: Set<Affordance>] {
        Dictionary(uniqueKeysWithValues: state.openedRooms.union([.living]).map { ($0, state.affordances(in: $0, catalogue: catalogue)) })
    }

    /// The room a room type is for, for an affordance at a time of day (Tuning.CatRooms.preferred).
    static func preferred(for need: Affordance, at time: TimeOfDay) -> RoomID? {
        let table = Tuning.CatRooms.preferred
        return (table["\(need.rawValue).\(time.rawValue)"] ?? table[need.rawValue]).flatMap(RoomID.init(rawValue:))
    }

    /// - Parameters:
    ///   - current: the room the cat is in.
    ///   - viewing: the room the player is looking at (where "near you" is).
    public static func room(
        for activity: Activity,
        current: RoomID,
        viewing: RoomID,
        offers: [RoomID: Set<Affordance>],
        timeOfDay: TimeOfDay,
        rng: inout DaySeed
    ) -> RoomID {
        let open = Set(offers.keys).union([.living])
        let here = open.contains(current) ? current : .living
        guard let need = activity.affordance else {
            // Nothing to use: near you comes to the room you are looking at; a wander sometimes goes next door;
            // the rest happens where it is.
            if activity == .nearPlayer, open.contains(viewing) {
                return viewing
            }
            let elsewhere = open.subtracting([here]).sorted()
            if activity == .explore, !elsewhere.isEmpty, rng.below(100) < Tuning.CatRooms.exploreElsewherePercent {
                return elsewhere[rng.below(elsewhere.count)]
            }
            return here
        }
        let candidates = offers.filter { $0.value.contains(need) }.map(\.key).sorted()
        guard !candidates.isEmpty else { return here }
        if let room = preferred(for: need, at: timeOfDay), candidates.contains(room), rng.below(100) < Tuning.CatRooms.preferredPercent {
            return room
        }
        if candidates.contains(here), rng.below(100) < Tuning.CatRooms.stayPercent {
            return here
        }
        return candidates[rng.below(candidates.count)]
    }

    /// The choice with its room filled in.
    public static func placed(
        _ choice: BehaviourChoice,
        current: RoomID,
        viewing: RoomID,
        offers: [RoomID: Set<Affordance>],
        timeOfDay: TimeOfDay,
        rng: inout DaySeed
    ) -> BehaviourChoice {
        var choice = choice
        choice.room = room(for: choice.activity, current: current, viewing: viewing, offers: offers, timeOfDay: timeOfDay, rng: &rng)
        return choice
    }
}
