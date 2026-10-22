import Foundation
@testable import HouseCatCore
import Testing

/// The path (Josh, 19 Oct: "i have been playing for 5 mins and dont know what to do"): chapters of goals that teach the
/// game a step at a time, each paying Beans and XP, each chapter opening the next; and the tracker on the room, which
/// always has the next goal or two on it.
@Suite("Path")
struct PathTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    func chapter(_ id: String) throws -> PathChapterDefinition {
        try #require(context.path.first { $0.id == id })
    }

    func step(_ id: String) throws -> PathStepDefinition {
        try #require(context.path.flatMap(\.steps).first { $0.id == id })
    }

    @Test func feedingForTheFirstTimePaysTheFirstStepOnce() throws {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        let before = f.state
        f.add(.fed(catID: f.cat), day: 0, hour: 8, minute: 1)
        let after = f.state
        let feed = try step("path_feed")
        #expect(after.pathDone.contains("path_feed"))
        #expect(after.xp - before.xp == Tuning.XP.feed + feed.xp, "the meal's XP and the step's")
        #expect(after.beans - before.beans >= feed.beans, "the step's Beans (a daily goal may pay too)")
        // Fed again tomorrow: nothing more from the path.
        f.add(.arrived, day: 1, hour: 8)
        let tomorrow = f.state
        f.add(.fed(catID: f.cat), day: 1, hour: 8, minute: 1)
        #expect(f.state.xp - tomorrow.xp == Tuning.XP.feed)
    }

    @Test func aStepIsDoneWhateverOrderTheChapterIsWalkedIn() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        f.add(.miniGamePlayed(game: "laser", stars: 1), day: 0, hour: 8, minute: 1)
        f.add(.napCompleted, day: 0, hour: 8, minute: 30)
        #expect(f.state.pathDone.isSuperset(of: ["path_play", "path_nap"]))
        #expect(!f.state.pathDone.contains("path_feed"))
    }

    @Test func aLaterChapterWaitsForTheOneBefore() throws {
        var f = Fixture(context: context)
        // Two days of visits: "See you tomorrow" is met, but Settling in is not open yet.
        f.visit(days: [0, 1])
        #expect(!f.state.pathDone.contains("path_tomorrow"))
        let beforeChapter = f.state
        var walker = Walker(f: f, content: content)
        walker.finishMovingIn(day: 1)
        let state = walker.f.state
        #expect(state.pathDone.contains("path_moving_in"))
        // The moment Moving in is done, Settling in opens and what is already met is paid at once.
        #expect(state.pathDone.contains("path_tomorrow"))
        #expect(state.ownedOutfits.contains("nightcap"))
        #expect(state.beans > beforeChapter.beans)
    }

    @Test func aChapterDonePaysItsOwnReward() throws {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        var walker = Walker(f: f, content: content)
        walker.finishMovingIn(day: 0, skipping: "path_dress")
        let before = walker.f.state
        #expect(!before.pathDone.contains("path_moving_in"))
        walker.f.add(.outfitWorn(catID: walker.f.cat, outfitID: "nightcap"), day: 0, hour: 10)
        let after = walker.f.state
        let map = try step("path_dress")
        let movingIn = try chapter("path_moving_in")
        #expect(after.pathDone.isSuperset(of: ["path_dress", "path_moving_in"]))
        #expect(after.beans - before.beans >= map.beans + movingIn.beans)
        #expect(after.xp - before.xp == map.xp + movingIn.xp)
    }

    @Test func piecesAPathStepGivesAreOwned() throws {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        var walker = Walker(f: f, content: content)
        walker.f.add(.purchaseBeansGranted(transactionID: "t", beans: 500), day: 0, hour: 8)
        let before = walker.state.owned["living_rug", default: 0]
        walker.furnish(.living, pieces: 3, day: 0, hour: 9)
        let state = walker.state
        #expect(state.pathDone.contains("path_cosy"))
        #expect(state.owned["living_rug", default: 0] == before + 1, "Make it cosy gives the rug")
    }

    @Test func movingUpTheLadderIsTheLastChaptersOptionalStep() throws {
        let homes = try step("path_homes")
        #expect(homes.optional && homes.metric == .houseRung && homes.target == 3)
        let houseboat = try step("path_bedroom")
        #expect(!houseboat.optional && houseboat.metric == .houseRung && houseboat.target == 2)
    }

    @Test func seeingAScreenCountsOnceAndPaysNothingByItself() {
        var f = Fixture(context: .empty)
        f.add(.screenSeen("map"), day: 0)
        f.add(.screenSeen("map"), day: 0, hour: 10)
        #expect(f.state.lifetime.screensSeen == ["map"])
        #expect(f.state.beans == Tuning.Beans.housewarmingAllowance && f.state.xp == 0)
    }

    @Test func anOptionalStepNeverHoldsAChapterUp() throws {
        let last = try chapter("path_making_home")
        let optional = last.steps.filter(\.optional)
        #expect(!optional.isEmpty)
        #expect(optional.allSatisfy { [.passTiersClaimed, .houseRung].contains($0.metric) }, "a season may not be on, a house may be far off")
        let required = Set(last.steps.filter { !$0.optional }.map(\.id))
        #expect(PathRules.isComplete(last, done: required))
        #expect(!PathRules.isComplete(last, done: required.subtracting([required.first!])))
    }

    @Test func theCatUsingPiecesCountsDifferentOnesItHasUsed() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        var walker = Walker(f: f, content: content)
        walker.furnish(.living, pieces: 2, day: 0, hour: 9)
        let pieces = walker.f.state.placed.map(\.itemID)
        walker.f.add(.catUsedNewItem(catID: walker.f.cat, itemID: pieces[0]), day: 0, hour: 10)
        walker.f.add(.catUsedNewItem(catID: walker.f.cat, itemID: pieces[0]), day: 0, hour: 11)
        walker.f.add(.catUsedNewItem(catID: walker.f.cat, itemID: pieces[1]), day: 0, hour: 12)
        walker.f.add(.catUsedNewItem(catID: walker.f.cat, itemID: "attic_trunk"), day: 0, hour: 12, minute: 5)
        #expect(walker.f.state.lifetimeValue(.catUsedItems, on: walker.f.day(0)) == 2, "only pieces that are out, each once")
    }

    @Test func roomsCountAsFurnishedWithEnoughPiecesOut() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        f.add(.purchaseBeansGranted(transactionID: "t", beans: 2000), day: 0, hour: 8)
        var walker = Walker(f: f, content: content)
        walker.furnish(.living, pieces: Tuning.Goals.furnishedRoomPieces - 1, day: 0, hour: 9)
        #expect(walker.f.state.furnishedRooms == 0)
        walker.furnish(.living, pieces: Tuning.Goals.furnishedRoomPieces, day: 0, hour: 10)
        #expect(walker.f.state.furnishedRooms == 1)
    }

    @Test func aRefoldedSaveWalksThePathTheSameWay() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        var walker = Walker(f: f, content: content)
        walker.finishMovingIn(day: 0)
        for day in 1 ..< 40 {
            walker.f.visit(days: [day])
        }
        let whole = walker.f.state
        let compacted = walker.f.log.compacted(before: walker.f.day(35), context: context).derive(context: context)
        #expect(compacted.pathDone == whole.pathDone)
        #expect(compacted.beans == whole.beans && compacted.xp == whole.xp)
    }

    // MARK: The tracker

    @Test func theTrackerShowsTheNextTwoStepsOfTheOpenChapter() {
        var f = Fixture(context: context)
        f.add(.arrived, day: 0, hour: 8)
        var tracker = GoalTracker.make(f.state, objectives: content.objectives, context: context, catName: "Pip", on: f.day(0))
        #expect(tracker.chapter?.name == "Moving in")
        #expect(tracker.chapter?.done == 0)
        #expect(tracker.entries.map(\.id) == ["path_feed", "path_stroke"])
        #expect(tracker.entries.first?.text == "Feed Pip.", "the cat's own name")
        f.add(.fed(catID: f.cat), day: 0, hour: 8, minute: 1)
        tracker = GoalTracker.make(f.state, objectives: content.objectives, context: context, catName: "Pip", on: f.day(0))
        #expect(tracker.entries.map(\.id) == ["path_stroke", "path_cosy"])
        #expect(tracker.chapter?.done == 1)
        let cosy = tracker.entries[1]
        #expect(cosy.room == .living && cosy.target == 3 && cosy.progress == 0)
    }

    @Test func afterThePathTheTrackerHasTodayAndTheNextRoom() {
        var walker = Walker(f: Fixture(context: context), content: content)
        walker.f.add(.arrived, day: 0, hour: 8)
        walker.walkWholePath()
        let state = walker.f.state
        #expect(PathRules.openChapter(context.path, done: state.pathDone) == nil, "the path is walked")
        let day = walker.f.clock.day(of: walker.f.log.events.last!.at)
        let tracker = GoalTracker.make(state, objectives: content.objectives, context: context, catName: "Pip", on: day)
        #expect(tracker.chapter == nil)
        #expect(tracker.entries.count == Tuning.Goals.trackerSlots)
        #expect(tracker.entries.contains { $0.kind == .room } || state.openedRooms.count == RoomID.allCases.count)
    }

    @Test func atTheTopTheTrackerShowsTheNearestMilestone() {
        var walker = Walker(f: Fixture(context: context), content: content)
        walker.f.add(.arrived, day: 0, hour: 8)
        walker.walkWholePath()
        var state = walker.f.state
        state.home.rung = HouseLadder.top
        let day = walker.f.clock.day(of: walker.f.log.events.last!.at)
        let tracker = GoalTracker.make(state, objectives: content.objectives, context: context, catName: "Pip", on: day)
        #expect(tracker.entries.last?.kind == .milestone)
        #expect(tracker.entries.allSatisfy { !($0.kind == .room) })
    }

    /// The next house's goal asks for what it still waits for: the Beans for the houseboat, then the level for the
    /// cabin, then the houseboat's tasks one at a time.
    @Test func theHouseGoalAsksForWhatTheNextHouseWaitsFor() {
        var f = Fixture(context: .empty)
        f.add(.arrived, day: 0, hour: 8)
        let objectives = ObjectivesFile(version: 1, daily: [], weekly: [], achievements: [], path: nil)
        var tracker = GoalTracker.make(f.state, objectives: objectives, context: .empty, catName: "Pip", on: f.day(0))
        #expect(tracker.entries.map(\.id) == ["house.2.move"])
        #expect(tracker.entries.first?.target == HouseLadder.rung(2).price)
        f.add(.tourFinished, day: 0, hour: 9)
        f.add(.houseBought(rung: 2, beans: HouseLadder.rung(2).price), day: 0, hour: 9, minute: 1)
        tracker = GoalTracker.make(f.state, objectives: objectives, context: .empty, catName: "Pip", on: f.day(0))
        #expect(tracker.entries.map(\.id) == ["house.3.level"])
        f.add(.purchaseBeansGranted(transactionID: "t", beans: 1), day: 0, hour: 9, minute: 2)
        var state = f.state
        state.xp = LevelCurve.threshold(for: HouseLadder.rung(3).level)
        tracker = GoalTracker.make(state, objectives: objectives, context: .empty, catName: "Pip", on: f.day(0))
        #expect(tracker.entries.first?.id == "house.2.total_feeds")
        #expect(tracker.entries.first?.name == "Feed Pip 7 times")
    }

    @Test func aMetGoalSaysWhatItPaid() throws {
        let objectives = content.objectives
        let movingIn = try #require(GoalReward.of("path_moving_in", objectives: objectives, catName: "Pip"))
        #expect(movingIn.chapter && movingIn.next == "Getting to know you" && movingIn.line == "Pip feels at home.")
        let bedroom = try #require(GoalReward.of("path_bedroom", objectives: objectives, catName: "Pip"))
        #expect(bedroom.outfit == "nightcap" && !bedroom.chapter)
        let cosy = try #require(GoalReward.of("path_cosy", objectives: objectives, catName: "Pip"))
        #expect(cosy.item == "living_rug")
        #expect(movingIn.item == "living_scratch")
        let last = try #require(GoalReward.of("path_making_home", objectives: objectives, catName: "Pip"))
        #expect(last.next == nil)
        #expect(GoalReward.of("d_feed", objectives: objectives, catName: "Pip")?.beans == 10)
        #expect(GoalReward.of("nothing", objectives: objectives, catName: "Pip") == nil)
    }

    @Test func theGoalsPageSaysWhatItIsAllFor() {
        var f = Fixture(context: context)
        f.visit(days: [0, 1])
        let board = GoalBoard.make(f.state, objectives: content.objectives, on: f.day(1), catName: "Pip")
        #expect(board.chapter?.name == "Moving in")
        #expect(board.path.count == context.path[0].steps.count)
        #expect(board.path.first?.done == true && board.path.first?.text == "Feed Pip.")
        #expect(board.pillars.trust == .newcomer && board.pillars.daysToNextTier == 1, "two of the three days to Wary")
        #expect(board.pillars.roomsOpen == 1 && board.pillars.rooms == 6)
        #expect(board.pillars.nextRoom == .bedroom)
    }
}

/// A player who does what the tracker asks: buys and puts out the pieces a step wants, opens the next room as soon
/// as the level and the Beans allow, wears what it has been given, looks at the map. Shared by the path's tests and
/// the pacing of its hour, week and month.
struct Walker {
    var f: Fixture
    let content: ContentBundle
    var minute = 0
    /// The log folded so far, so each new event is applied once (events land at the end of the log, as a phone's do).
    private var folded: (count: Int, last: UUID?, state: HouseholdState)?

    init(f: Fixture, content: ContentBundle) {
        self.f = f
        self.content = content
    }

    /// The state through the last event, as `Fixture.state`, folding only what is new.
    var state: HouseholdState {
        mutating get {
            let events = f.log.events
            if let cached = folded, cached.count <= events.count, cached.count > 0, events[cached.count - 1].id == cached.last {
                var state = cached.state
                for event in events[cached.count...] {
                    state.apply(event, context: f.context)
                }
                folded = (events.count, events.last?.id, state)
                return state
            }
            let state = f.state
            folded = (events.count, events.last?.id, state)
            return state
        }
    }

    /// The next minute of the hour on `day` (events keep their order).
    private mutating func tick(_ day: Int, _ hour: Int) -> (Int, Int) {
        minute += 1
        return (hour + minute / 60, minute % 60)
    }

    /// Buys (with Beans, cheapest first) and puts out pieces in `room` until it has `pieces` out, as far as the Beans go.
    mutating func furnish(_ room: RoomID, pieces: Int, day: Int, hour: Int) {
        let shop = content.catalogue.items
            .filter { $0.room == room.rawValue && $0.pool == .beans && $0.layer == .floor && $0.beans != nil }
            .sorted { ($0.beans ?? 0, $0.id) < ($1.beans ?? 0, $1.id) }
        var index = 0
        while state.pieces(in: room) < pieces, state.openedRooms.contains(room) {
            // Something owned and not out first, else the cheapest piece not yet bought.
            let state = self.state
            let spare = state.owned.first { owned in
                owned.value > state.placedCount(of: owned.key) && shop.contains { $0.id == owned.key }
            }?.key
            let item: String
            if let spare {
                item = spare
            } else {
                guard index < shop.count, let price = shop[index].beans, state.beans >= price else { return }
                item = shop[index].id
                index += 1
                let (h, m) = tick(day, hour)
                f.add(.itemBought(itemID: item, beans: price), day: day, hour: h, minute: m)
            }
            guard place(item, in: room, day: day, hour: hour) else { return }
        }
    }

    /// Puts `item` out in the first cell it fits.
    @discardableResult
    mutating func place(_ item: String, in room: RoomID, day: Int, hour: Int) -> Bool {
        let before = state.pieces(in: room)
        let (h, m) = tick(day, hour)
        for y in stride(from: 1, to: Tuning.Room.gridDepth - 1, by: 2) {
            for x in stride(from: 1, to: Tuning.Room.gridWidth - 1, by: 3) {
                f.add(.itemPlaced(itemID: item, room: room, x: x, y: y, facing: .right), day: day, hour: h, minute: m)
                if state.pieces(in: room) > before {
                    return true
                }
            }
        }
        return false
    }

    /// Moves up to the next house if nothing stands in the way (rooms come with houses: docs/LADDER.md).
    mutating func openNextRoom(day: Int, hour: Int) {
        // A house task asking for new pieces: a piece or two bought for the rooms there are, as a player would.
        let unfinished = Set(state.houseTaskProgress(on: f.day(day)).filter { $0.done < $0.task.target }.map(\.task.metric))
        if unfinished.contains(.itemsOwned) {
            for room in RoomID.allCases where state.openedRooms.contains(room) {
                furnish(room, pieces: state.pieces(in: room) + 1, day: day, hour: hour)
            }
        }
        // A new wallpaper now and then, from the free ones.
        if unfinished.contains(.surfacesChanged) {
            let free = content.catalogue.surfaces.filter { $0.room == RoomID.living.rawValue && $0.pool == .free }
            if let surface = free.randomElement() {
                let (h, m) = tick(day, hour)
                f.add(.surfaceChanged(room: .living, surfaceID: surface.id), day: day, hour: h, minute: m)
            }
        }
        let state = self.state
        guard let next = state.nextRung,
              HouseLadder.block(above: state.rung, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans) == nil
        else { return }
        let (h, m) = tick(day, hour)
        f.add(.houseBought(rung: next.number, beans: next.price), day: day, hour: h, minute: m)
    }

    /// Does what the open chapter's steps ask that costs no more than a tap or what the Beans allow.
    mutating func followThePath(day: Int, hour: Int) {
        defer { openNextRoom(day: day, hour: hour) }
        let state = self.state
        guard let open = PathRules.openChapter(f.context.path, done: state.pathDone) else { return }
        for step in open.steps where !state.pathDone.contains(step.id) {
            switch step.metric {
            case .roomPieces:
                if let room = step.room {
                    furnish(room, pieces: step.target, day: day, hour: hour)
                }
            case .screenSeen:
                if let screen = step.screen {
                    let (h, m) = tick(day, hour)
                    f.add(.screenSeen(screen), day: day, hour: h, minute: m)
                }
            case .outfitsWorn:
                for outfit in state.ownedOutfits.sorted() where !state.lifetime.outfitsTried.contains(outfit) {
                    let (h, m) = tick(day, hour)
                    f.add(.outfitWorn(catID: f.cat, outfitID: outfit), day: day, hour: h, minute: m)
                }
            case .surfacesChanged:
                let free = content.catalogue.surfaces.filter { $0.room == RoomID.living.rawValue && $0.pool == .free }
                for surface in free.prefix(step.target) {
                    let (h, m) = tick(day, hour)
                    f.add(.surfaceChanged(room: .living, surfaceID: surface.id), day: day, hour: h, minute: m)
                }
            case .itemsOwned:
                for room in RoomID.allCases where state.openedRooms.contains(room) {
                    furnish(room, pieces: state.pieces(in: room) + 2, day: day, hour: hour)
                }
            default:
                break
            }
        }
    }

    /// The cat tries out pieces it has not used yet, two a day at most (it wanders to them as the room plays).
    mutating func catUsesNewPieces(day: Int, hour: Int) {
        let unused = state.placed.map(\.itemID).filter { !state.lifetime.usedItems.contains($0) }
        for item in Array(Set(unused)).sorted().prefix(2) {
            let (h, m) = tick(day, hour)
            f.add(.catUsedNewItem(catID: f.cat, itemID: item), day: day, hour: h, minute: m)
        }
    }

    /// The first hour as the tracker leads it, on `day`, with an arrival already made.
    mutating func finishMovingIn(day: Int, skipping: String? = nil) {
        minute = 0
        f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 1)
        f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 2)
        f.add(.tourFinished, day: day, hour: 8, minute: 3)
        minute = 4
        // The tour's sofa and two pieces from the shop, a minute or two each.
        furnish(.living, pieces: 3, day: day, hour: 8)
        f.add(.miniGamePlayed(game: "laser", stars: 2), day: day, hour: 8, minute: 15)
        // A twenty-minute nap from 08:16.
        f.add(.napCompleted, day: day, hour: 8, minute: 36)
        minute = 37
        openNextRoom(day: day, hour: 8)
        if skipping != "path_dress" {
            f.add(.outfitWorn(catID: f.cat, outfitID: "nightcap"), day: day, hour: 8, minute: 39)
        }
    }

    /// Two months of a regular player following the tracker: the whole path.
    mutating func walkWholePath() {
        finishMovingIn(day: 0)
        for day in 1 ..< 60 {
            minute = 0
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 1)
            for pet in 0 ..< 3 {
                f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 2 + pet)
            }
            f.collectGifts(day: day, hour: 8, minute: 6)
            for game in 0 ..< 3 {
                f.add(.miniGamePlayed(game: "laser", stars: game == 0 ? 3 : 2), day: day, hour: 8, minute: 10 + game)
            }
            minute = 20
            followThePath(day: day, hour: 9)
            catUsesNewPieces(day: day, hour: 10)
        }
    }
}
