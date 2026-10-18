import Foundation

/// One entry in the append-only save. Every piece of state is derived from
/// these plus `DaySeed`; nothing is stored as a mutable counter. Events record
/// facts ("fed at t", "bought y for 120 Beans"), never totals.
public struct GameEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Trusted game time (see `TrustedTime`).
    public let at: Date
    /// The game day at `at`, fixed when the event is appended so a later change
    /// of wake time or time zone never re-buckets history.
    public let day: GameDay
    public let actor: Actor
    public let source: Source
    public let kind: Kind

    public init(id: UUID = UUID(), at: Date, day: GameDay, actor: Actor = .owner, source: Source = .app, kind: Kind) {
        self.id = id
        self.at = at
        self.day = day
        self.actor = actor
        self.source = source
        self.kind = kind
    }

    /// Who did it. Co-owners' and sitters' visits count for the household.
    public enum Actor: Codable, Hashable, Sendable {
        case owner
        case coOwner(String)
        case sitter(String)
    }

    /// Where it happened. Feed or Pet from any surface counts as the day's visit.
    public enum Source: String, Codable, Hashable, Sendable {
        case app
        case widget
        case watch
        case mac
        case siri
    }

    public enum HealthGoal: String, Codable, Hashable, Sendable, CaseIterable {
        case steps
        case sleep
        case workout
    }

    public enum Facing: String, Codable, Hashable, Sendable {
        case left = "L"
        case right = "R"
    }

    public enum Kind: Codable, Hashable, Sendable {
        // Household and cats
        case householdCreated(seed: UInt64, clock: DayClock)
        case clockChanged(DayClock)
        case catAdopted(catID: String, name: String, personality: Personality, isKitten: Bool)
        case catRenamed(catID: String, name: String)
        case personalityChanged(catID: String, personality: Personality)
        /// The cat's look from the builder: at adoption, and each time it is edited from the profile.
        case catLookSet(catID: String, look: CatLook)

        // The visit and care
        case arrived
        case fed(catID: String)
        case petted(catID: String)
        case miniGamePlayed(game: String, stars: Int)
        case giftCollected(catID: String, giftID: String, rarity: GiftRarity)
        case giftSold(giftID: String, rarity: GiftRarity)
        case napCompleted
        case healthGoalMet(HealthGoal)
        case windowTapped

        /// Home
        case itemBought(itemID: String, beans: Int)
        /// Items from free starters, sets, packs, the pass or gifts: no Beans move.
        case itemGranted(itemID: String)
        case itemPlaced(itemID: String, room: RoomID, x: Int, y: Int, facing: Facing)
        case itemMoved(placementID: UUID, room: RoomID, x: Int, y: Int, facing: Facing)
        case itemStored(placementID: UUID)
        case catUsedNewItem(catID: String, itemID: String)
        case roomOpened(RoomID, beans: Int)
        case roomVisited(RoomID)
        case surfaceChanged(room: RoomID, surfaceID: String)
        case outfitWorn(catID: String, outfitID: String)
        case homeMoved(beans: Int)
        case seasonModeChanged
        /// The pin on the world map: the first one free (onboarding), later ones after a `homeMoved`.
        case homePlaced(HomePlace)
        /// Auto, or a season fixed by the player.
        case seasonSet(SeasonSetting)
        /// Which of the eight homes it is (onboarding's house step; again when moving).
        case homeStyleChosen(HouseStyle)

        // Streak
        case pauseStarted(days: Int)
        case pauseEnded

        /// Beans that come with a purchase (bundles, the starter pack, the Housewarming pack).
        /// Counted once per store transaction, however many devices record it.
        case purchaseBeansGranted(transactionID: String, beans: Int)

        // Season pass and Cat Club
        case passPurchased(seasonID: String)
        case passTierClaimed(seasonID: String, track: PassTrack, tier: Int)
        /// Written once a day while a verified Cat Club entitlement is live, so
        /// that day's +20% Beans and paid-track claims re-derive the same way
        /// forever. It grants nothing by itself.
        case clubDayRecorded

        // Social and sharing
        case sundayCardShared
        case pawPrintSent
        case groupJoined
        case giftSent
        case satForFriend
    }

    /// Whether this event counts as the day's visit.
    public var isVisit: Bool {
        switch kind {
        case .arrived, .fed, .petted: true
        default: false
        }
    }
}

/// Sort order for the log: by game day, then time, then id, so every device
/// folds the same events in the same order.
extension GameEvent {
    static func logOrder(_ lhs: GameEvent, _ rhs: GameEvent) -> Bool {
        if lhs.day != rhs.day {
            return lhs.day < rhs.day
        }
        if lhs.at != rhs.at {
            return lhs.at < rhs.at
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
