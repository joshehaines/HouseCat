/// The six rooms. The living room is open from the first arrival; every other
/// room needs a level AND Beans (CLAUDE.md "First arrival"). Money never skips
/// a level: Cat Club halves the Bean cost only.
public enum RoomID: String, CaseIterable, Codable, Sendable, Comparable {
    case living
    case bedroom
    case kitchen
    /// Garden or balcony, depending on the house.
    case garden
    case study
    case attic

    public var requiredLevel: Int {
        switch self {
        case .living: 1
        case .bedroom: Tuning.Rooms.bedroomLevel
        case .kitchen: Tuning.Rooms.kitchenLevel
        case .garden: Tuning.Rooms.gardenLevel
        case .study: Tuning.Rooms.studyLevel
        case .attic: Tuning.Rooms.atticLevel
        }
    }

    public var fullBeanCost: Int {
        switch self {
        case .living: 0
        case .bedroom: Tuning.Rooms.bedroomBeans
        case .kitchen: Tuning.Rooms.kitchenBeans
        case .garden: Tuning.Rooms.gardenBeans
        case .study: Tuning.Rooms.studyBeans
        case .attic: Tuning.Rooms.atticBeans
        }
    }

    public static func < (lhs: RoomID, rhs: RoomID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum RoomAvailability: Equatable, Sendable {
    case open
    /// Level reached and enough Beans: opening costs this much.
    case unlockable(cost: Int)
    /// Shown as a lit silhouette with its level and price.
    case locked(level: Int, cost: Int, needsLevel: Bool, needsBeans: Bool)
}

public enum RoomRules {
    public static func cost(of room: RoomID, clubActive: Bool) -> Int {
        let full = room.fullBeanCost
        guard clubActive else { return full }
        // Round up, so the discount never rounds a price below half.
        return (full * (100 - Tuning.Rooms.clubDiscountPercent) + 99) / 100
    }

    public static func availability(
        of room: RoomID,
        opened: Set<RoomID>,
        level: Int,
        beans: Int,
        clubActive: Bool
    ) -> RoomAvailability {
        if room == .living || opened.contains(room) {
            return .open
        }
        let cost = cost(of: room, clubActive: clubActive)
        let needsLevel = level < room.requiredLevel
        let needsBeans = beans < cost
        if needsLevel || needsBeans {
            return .locked(level: room.requiredLevel, cost: cost, needsLevel: needsLevel, needsBeans: needsBeans)
        }
        return .unlockable(cost: cost)
    }
}
