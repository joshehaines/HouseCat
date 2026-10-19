import Foundation
import HouseCatCore
import HouseCatGame

/// The money, levels, pass, streak and co-owning side of the session: what the shop, the tray, the level card,
/// the pass, the streak card and the quest card ask for. Rules stay in HouseCatCore; this records events.
extension GameSession {
    // MARK: Purchases

    /// While Cat Club is on, today is a club day (its +20% Beans, half-price rooms and the paid track), once a day.
    func recordClubDay(active: Bool) {
        let state = state(at: now())
        guard active, state.today?.clubDay == false else { return }
        append(.clubDayRecorded, at: now())
    }

    var beans: Int {
        state(at: now()).beans
    }

    // MARK: Beans

    /// A paid outfit for Beans; `gift` when a co-owner gives it to the cat for the other owner to find.
    @discardableResult
    func buyOutfit(_ outfitID: String, gift: Bool = false) -> Bool {
        let state = state(at: now())
        guard state.beans >= Tuning.Beans.outfit, !state.ownedOutfits.contains(outfitID) else { return false }
        append(.outfitBought(outfitID: outfitID, beans: Tuning.Beans.outfit, gift: gift), at: now())
        Sound.play("ui_bean_chime", volume: Tuning.Sound.place)
        return true
    }

    var ownedOutfits: Set<String> {
        state(at: now()).ownedOutfits
    }

    // MARK: The wardrobe

    /// The outfits the cat can wear: owned and fitted (hats, glasses, neckwear).
    var wardrobe: [OutfitsFile.Outfit] {
        let owned = ownedOutfits
        return (content?.outfits.outfits ?? []).filter { owned.contains($0.id) && $0.wearable }
    }

    /// What the cat has on.
    var wornOutfit: OutfitsFile.Outfit? {
        guard let id = cat?.outfitID else { return nil }
        return content?.outfits.outfits.first { $0.id == id && $0.wearable }
    }

    /// Puts an outfit on the cat, or takes it off (nil).
    func wear(_ outfitID: String?) {
        guard let cat else { return }
        if let outfitID {
            append(.outfitWorn(catID: cat.id, outfitID: outfitID), at: now())
        } else {
            append(.outfitTakenOff(catID: cat.id), at: now())
        }
        Sound.play("ui_sparkle", volume: Tuning.Sound.place)
    }

    /// Whether more than one person looks after the cat (presents and the shared quest appear then).
    var isCoOwned: Bool {
        state(at: now()).owners.count >= 2
    }

    /// Outfits another owner gave the cat since this phone last looked (for the present at arrival); none from
    /// someone hidden on this phone (the outfit is still in the wardrobe).
    func unopenedGifts(since date: Date?) -> [OutfitGift] {
        let me = HouseholdSync.actor.key
        let hidden = HouseholdSync.hidden
        return state(at: now()).outfitGifts.filter { $0.from != me && !hidden.contains($0.from) && $0.at > (date ?? .distantPast) }
    }

    /// The other owner, as this phone sees them (a debug run with nobody else makes up Sam).
    var otherOwner: String? {
        let state = state(at: now())
        if let other = state.otherOwners(than: HouseholdSync.actor.key).first {
            return other
        }
        #if DEBUG
            if ["together", "present"].contains(ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"]) {
                return "co:Sam"
            }
        #endif
        return nil
    }

    /// The household's reference for a report (`HouseholdReference`).
    var householdReference: String {
        HouseholdReference.code(seed: state(at: now()).seed)
    }

    // MARK: Room looks

    var bundles: [BundlesFile.Bundle] {
        content?.bundles.bundles ?? []
    }

    /// Puts a room look's pieces into its room (those not out already) where each first fits, and its wallpaper and
    /// floor up. Returns how many pieces went in; the rest stay in the inventory (a full room).
    @discardableResult
    func addWholeRoom(_ bundle: BundlesFile.Bundle, among existing: [PlacementRules.Piece]) -> Int {
        guard let catalogue = content?.catalogue else { return 0 }
        let state = state(at: now())
        guard state.openedRooms.contains(bundle.room) else { return 0 }
        let items = Dictionary(uniqueKeysWithValues: catalogue.items.map { ($0.id, $0) })
        var pieces = existing
        var unplaced = state.unplaced()
        var placed = 0
        // Big pieces first, so the small ones fill round them.
        let order = bundle.items.compactMap { items[$0] }.sorted { $0.footprint.w * $0.footprint.d > $1.footprint.w * $1.footprint.d }
        for item in order where unplaced[item.id, default: 0] > 0 {
            let fresh = PlacementRules.Piece(item, x: 0, y: 0, facing: .right)
            guard let spot = PlacementRules.firstFit(fresh, among: pieces) else { continue }
            let event = append(.itemPlaced(itemID: item.id, room: bundle.room, x: spot.x, y: spot.y, facing: spot.facing), at: now())
            var placedPiece = spot
            placedPiece.placementID = event.id
            pieces.append(placedPiece)
            unplaced[item.id, default: 0] -= 1
            placed += 1
        }
        for surface in bundle.surfaces {
            append(.surfaceChanged(room: bundle.room, surfaceID: surface), at: now())
        }
        Sound.play("ui_place_item", volume: Tuning.Sound.place)
        return placed
    }

    /// Where a look's pieces would go in its room now, without placing them (the "try it in your room" preview).
    func preview(_ bundle: BundlesFile.Bundle, among existing: [PlacementRules.Piece]) -> [RoomModel.Placement] {
        guard let catalogue = content?.catalogue else { return [] }
        let items = Dictionary(uniqueKeysWithValues: catalogue.items.map { ($0.id, $0) })
        var pieces = existing
        var out: [RoomModel.Placement] = []
        let order = bundle.items.compactMap { items[$0] }.sorted { $0.footprint.w * $0.footprint.d > $1.footprint.w * $1.footprint.d }
        for item in order {
            let fresh = PlacementRules.Piece(item, x: 0, y: 0, facing: .right)
            guard let spot = PlacementRules.firstFit(fresh, among: pieces) else { continue }
            pieces.append(spot)
            out.append(RoomModel.Placement(id: item.id, u: Double(spot.x), v: Double(spot.y), facing: spot.facing.rawValue, placementID: UUID()))
        }
        return out
    }

    // MARK: Levels

    struct LevelInfo {
        var level: Int
        var intoLevel: Int
        var toNext: Int
        var title: String
    }

    var levelInfo: LevelInfo {
        let state = state(at: now())
        let progress = LevelCurve.progress(xp: state.xp)
        let title = progress.level > 1 ? content?.levels.reward(for: progress.level).title ?? "" : "Newcomer"
        return LevelInfo(level: progress.level, intoLevel: progress.intoLevel, toNext: progress.toNext, title: title)
    }

    func roadmap(ahead: Int = Tuning.Levels.roadmapAhead) -> [RoadmapStop] {
        guard let content else { return [] }
        let level = levelInfo.level
        return LevelRoadmap.stops(after: level, through: level + ahead, levels: content.levels, catalogue: content.catalogue)
    }

    /// What reaching a level brought (the level-up card).
    func stop(for level: Int) -> RoadmapStop? {
        guard let content else { return nil }
        return LevelRoadmap.stops(after: level - 1, through: level, levels: content.levels, catalogue: content.catalogue).first
    }

    // MARK: The season pass

    /// The season running now and the player's place in it: what the pass, the room's badge, the menu and the shop
    /// show. There is always one (`SeasonSchedule`); nil only with no content.
    struct PassInfo {
        var season: SeasonDefinition
        var name: String
        /// The season's line ("Moving in: boxes, tea chests…").
        var theme: String
        var progress: SeasonProgress
        /// The premium track is open: Cat Club, or this season's pass bought (StoreKit or the save).
        var ownsPaid: Bool
        var day: GameDay
        var claimableFree: [Int]
        var claimablePaid: [Int]
        /// The next reward up the road, for the badge and the header.
        var next: (track: PassTrack, reward: PassReward)?
        /// Premium rewards on tiers already reached: what buying opens at once.
        var openAtOnce: [Int]

        var tier: Int {
            progress.tier
        }

        var waiting: Int {
            claimableFree.count + claimablePaid.count
        }

        var daysLeft: Int {
            season.daysLeft(on: day)
        }
    }

    /// `club` is a live Cat Club; `passes` the season passes StoreKit says were bought (by pass id).
    func passInfo(club: Bool, passes: Set<String> = []) -> PassInfo? {
        let date = now()
        let state = state(at: date)
        let day = state.clock.day(of: date)
        guard let season = rules.season(on: day) else { return nil }
        let progress = state.passes[season.id] ?? SeasonProgress()
        let ownsPaid = club || passes.contains(season.passID) || progress.purchased || state.today?.clubDay == true
        let named = content?.seasons.seasons.first { $0.id == season.passID }
        return PassInfo(
            season: season,
            name: named?.name ?? season.name,
            theme: named?.theme ?? "",
            progress: progress,
            ownsPaid: ownsPaid,
            day: day,
            claimableFree: PassRules.claimable(track: .free, progress: progress, season: season, day: day, ownsPaidTrack: false),
            claimablePaid: PassRules.claimable(track: .paid, progress: progress, season: season, day: day, ownsPaidTrack: ownsPaid),
            next: PassRules.next(progress: progress, season: season, ownsPaidTrack: ownsPaid),
            openAtOnce: PassRules.openAtOnce(progress: progress, season: season)
        )
    }

    /// A season's pass is owned (a verified StoreKit purchase, heard on every refresh): the season running now records
    /// it in the save once, so its premium claims count on every device. A pass bought once opens every run of its
    /// season, each recorded as it comes round.
    func recordPass(_ passID: String) {
        let date = now()
        let state = state(at: date)
        guard let season = rules.season(on: state.clock.day(of: date)), season.passID == passID,
              state.passes[season.id]?.purchased != true
        else { return }
        append(.passPurchased(seasonID: season.id), at: date)
    }

    /// Before a premium claim: the pass or today's Cat Club day in the save, if StoreKit says so (the app may have
    /// been open since before midnight, or the purchase heard on another device).
    func recordPremium(club: Bool, passes: Set<String>) {
        guard let info = passInfo(club: false) else { return }
        if passes.contains(info.season.passID) {
            recordPass(info.season.passID)
        }
        recordClubDay(active: club)
    }

    /// Claims a tier; the reward, if the claim counted.
    @discardableResult
    func claim(season: String, track: PassTrack, tier: Int) -> PassReward? {
        let before = state(at: now()).passes[season]?.claimed(track) ?? []
        append(.passTierClaimed(seasonID: season, track: track, tier: tier), at: now())
        let after = state(at: now())
        guard after.passes[season]?.claimed(track).contains(tier) == true, !before.contains(tier) else { return nil }
        return rules.season(id: season)?.reward(track: track, tier: tier)
    }

    /// Claims everything waiting, free track first, tier by tier; the rewards that counted.
    func claimAll(_ info: PassInfo) -> [PassReward] {
        var claimed: [PassReward] = []
        for tier in info.claimableFree {
            claim(season: info.season.id, track: .free, tier: tier).map { claimed.append($0) }
        }
        for tier in info.claimablePaid {
            claim(season: info.season.id, track: .paid, tier: tier).map { claimed.append($0) }
        }
        return claimed
    }

    // MARK: Streaks

    struct StreakInfo {
        var current: Int
        var longest: Int
        var canRepair: Bool
        var repairable: Int
        var repairLeft: [String]
        var repairUntil: GameDay?
        var paused: (from: GameDay, until: GameDay)?
        var pauseDaysLeft: Int
        var graceUsed: Bool
    }

    var streakInfo: StreakInfo {
        let date = now()
        let state = state(at: date)
        let day = state.clock.day(of: date)
        let paused: (from: GameDay, until: GameDay)? = {
            guard let from = state.pause.from, let until = state.pause.until else { return nil }
            return (from, until)
        }()
        let window = day.advanced(by: -(Tuning.Streak.graceWindowDays - 1))
        return StreakInfo(
            current: state.streak.current,
            longest: state.streak.longest,
            canRepair: StreakRepair.canRepair(state, on: day),
            repairable: state.streak.brokenLength,
            repairLeft: StreakRepair.remaining(state),
            repairUntil: StreakRepair.lastDay(state),
            paused: paused,
            pauseDaysLeft: state.pause.remaining(in: day.quarter),
            graceUsed: state.streak.graceDays.contains { $0 >= window }
        )
    }

    func repairStreak() {
        append(.streakRepaired, at: now())
        Sound.play("ui_streak_milestone", volume: Tuning.Sound.levelUp)
    }

    /// Vacation mode: the next `days` days neither count nor break the streak.
    func startPause(days: Int) {
        append(.pauseStarted(days: days), at: now())
    }

    func endPause() {
        append(.pauseEnded, at: now())
    }

    // MARK: Co-owning

    var questProgress: CoopQuest.Progress? {
        CoopQuest.progress(state(at: now()))
    }

    func claimQuest() {
        append(.questClaimed, at: now())
        Sound.play("ui_streak_milestone", volume: Tuning.Sound.levelUp)
    }

    /// Whether this phone can send today's paw print (Tuning.Coop.pawPrintsPerDay).
    var canSendPawPrint: Bool {
        let me = HouseholdSync.actor.key
        let date = now()
        let state = state(at: date)
        let today = state.clock.day(of: date)
        let sent = log.events.filter {
            if case .pawPrintSent = $0.kind { $0.actor.key == me && $0.day == today } else { false }
        }.count
        return sent < Tuning.Coop.pawPrintsPerDay
    }

    /// Who else looks after the cat, by name, for "from Sam" (the owner, seen from a co-owner's phone, by role;
    /// someone hidden on this phone, the same way).
    func otherOwnerName(_ key: String) -> String {
        OwnerName.display(key, otherwise: "\(cat?.name ?? "Your cat")'s other owner", hidden: HouseholdSync.hidden)
    }

    /// A paw print for the other owner: a nudge, never a nag (they see it at their next visit).
    func sendPawPrint() {
        append(.pawPrintSent, at: now())
        Sound.play("cat_trill", volume: Tuning.Sound.meow)
    }

    /// Paw prints the other owner sent since this phone last looked, by sender (none from someone hidden here).
    func pawPrints(since date: Date?) -> [String: Int] {
        let me = HouseholdSync.actor.key
        // Nor from someone who has left or was removed.
        let skip = HouseholdSync.hidden.union(state(at: now()).formerOwners)
        var from: [String: Int] = [:]
        for event in log.events where event.at > (date ?? .distantPast) && event.actor.key != me && !skip.contains(event.actor.key) {
            if case .pawPrintSent = event.kind {
                from[event.actor.key, default: 0] += 1
            }
        }
        return from
    }
}
