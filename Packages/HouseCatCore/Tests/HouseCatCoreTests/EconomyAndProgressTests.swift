import Foundation
@testable import HouseCatCore
import Testing

@Suite("Room looks and Beans")
struct RoomLookTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    @Test func everyLookIsForOneRoomWithRealPieces() {
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        let surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
        #expect(content.bundles.bundles.count >= 6)
        #expect(Set(content.bundles.bundles.map(\.sku)).count == content.bundles.bundles.count)
        for bundle in content.bundles.bundles {
            #expect(bundle.items.count >= 4, "\(bundle.id)")
            for id in bundle.items {
                #expect(items[id] != nil, "\(bundle.id): \(id)")
            }
            for id in bundle.surfaces {
                #expect(surfaces[id]?.room == bundle.room.rawValue, "\(bundle.id): \(id)")
            }
        }
    }

    @Test func aLookIsGrantedOncePerPurchase() throws {
        var f = Fixture(context: context)
        let bundle = try #require(content.bundles.bundles.first { $0.id == "cosy_study" })
        f.add(.bundleGranted(bundleID: bundle.id, transactionID: "t1"), day: 0)
        f.add(.bundleGranted(bundleID: bundle.id, transactionID: "t1"), day: 0, hour: 10)
        for item in bundle.items {
            #expect(f.state.owned[item] == 1, "\(item)")
        }
        #expect(f.state.ownedSurfaces.isSuperset(of: bundle.surfaces))
    }

    @Test func boughtBeansArriveOnceAndPayForThings() {
        var f = Fixture(context: context)
        let start = f.state.beans
        f.add(.purchaseBeansGranted(transactionID: "pack-1", beans: 1200), day: 0)
        f.add(.purchaseBeansGranted(transactionID: "pack-1", beans: 1200), day: 0, hour: 10)
        #expect(f.state.beans == start + 1200)
        f.add(.outfitBought(outfitID: "raincoat", beans: Tuning.Beans.outfit, gift: false), day: 0, hour: 11)
        #expect(f.state.ownedOutfits.contains("raincoat"))
        #expect(f.state.beans == start + 1200 - Tuning.Beans.outfit)
        // Not twice, and not when the Beans do not cover it.
        f.add(.outfitBought(outfitID: "raincoat", beans: Tuning.Beans.outfit, gift: false), day: 0, hour: 12)
        f.add(.outfitBought(outfitID: "beanie", beans: 1_000_000, gift: false), day: 0, hour: 12)
        #expect(f.state.beans == start + 1200 - Tuning.Beans.outfit)
        #expect(!f.state.ownedOutfits.contains("beanie"))
    }

    @Test func theCatWearsOnlyWhatTheHouseholdOwnsAndCanTakeItOff() {
        var f = Fixture(context: context)
        f.add(.outfitWorn(catID: f.cat, outfitID: "beanie"), day: 0)
        #expect(f.state.cat(f.cat)?.outfitID == nil)
        f.add(.purchaseBeansGranted(transactionID: "w", beans: 1000), day: 0, hour: 9)
        f.add(.outfitBought(outfitID: "beanie", beans: Tuning.Beans.outfit, gift: false), day: 0, hour: 10)
        f.add(.outfitWorn(catID: f.cat, outfitID: "beanie"), day: 0, hour: 11)
        #expect(f.state.cat(f.cat)?.outfitID == "beanie")
        f.add(.outfitTakenOff(catID: f.cat), day: 0, hour: 12)
        #expect(f.state.cat(f.cat)?.outfitID == nil)
    }

    @Test func everythingSoldOrGivenIsSomethingTheCatCanBeSeenIn() {
        let outfits = Dictionary(uniqueKeysWithValues: content.outfits.outfits.map { ($0.id, $0) })
        for season in content.seasons.seasons {
            for reward in season.freeTrack + season.paidTrack where reward.kind == .outfit {
                #expect(reward.id.flatMap { outfits[$0]?.wearable } == true, "\(season.id): \(reward.id ?? "")")
            }
        }
        #expect(outfits[Tuning.Store.starterOutfit]?.wearable == true)
        #expect(outfits.values.filter(\.wearable).count == 35)
    }

    @Test func singlePiecesFromLooksArePricedBySize() throws {
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        #expect(try BeanPrices.piece(#require(items["study_mug"])) == Tuning.Beans.paidPieceSmall)
        #expect(try BeanPrices.piece(#require(items["living_radiator"])) == Tuning.Beans.paidPieceMedium)
        #expect(try BeanPrices.piece(#require(items["attic_rolledrug"])) == Tuning.Beans.paidPieceLarge)
        #expect(try BeanPrices.piece(#require(items["living_armchair"])) == #require(items["living_armchair"]?.beans))
        #expect(BeanPrices.shortfall(price: 400, balance: 150) == 250)
        #expect(BeanPrices.shortfall(price: 100, balance: 150) == 0)
    }
}

@Suite("Levels")
struct LevelTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    @Test func eachLevelPaysItsBeansAndGivesItsPiece() {
        var f = Fixture(context: context)
        f.visit(days: [0])
        let before = f.state
        // Level 2 needs 100 XP: feed and visit over several days.
        f.visit(days: Array(1 ... 8))
        let after = f.state(through: 9)
        #expect(after.level >= 2)
        #expect(after.owned["living_clock"] == 1)
        let level2 = content.levels.reward(for: 2)
        #expect(level2.beans == 100)
        #expect(after.beans > before.beans)
    }

    @Test func theRoadmapShowsRoomsPiecesAndGifts() {
        let stops = LevelRoadmap.stops(after: 1, through: 12, levels: content.levels, catalogue: content.catalogue)
        #expect(stops.map(\.level) == Array(2 ... 12))
        #expect(stops.first { $0.level == 3 }?.rooms == [.kitchen])
        #expect(stops.first { $0.level == 3 }?.pieces.contains("kitchen_table") == true)
        #expect(stops.first { $0.level == 2 }?.gift == "living_clock")
        #expect(stops.allSatisfy { $0.xp == LevelCurve.threshold(for: $0.level) })
        #expect(LevelRoadmap.nextRoomLevel(after: 3)?.room == .garden)
        #expect(LevelRoadmap.nextRoomLevel(after: 12) == nil)
        #expect(content.levels.reward(for: 40).beans == content.levels.beyond.beans)
    }
}

@Suite("Gentle streaks")
struct StreakRepairTests {
    @Test func aBrokenStreakIsMendedByADayOfCareInTime() {
        var f = Fixture()
        f.visit(days: Array(0 ... 9)) // ten days
        // Two missed days: the first is graced, the second breaks it.
        #expect(f.state(through: 12).streak.current == 0)
        #expect(f.state(through: 12).streak.brokenLength == 10)
        f.add(.arrived, day: 12, hour: 8)
        #expect(!StreakRepair.canRepair(f.state, on: f.day(12)))
        #expect(StreakRepair.remaining(f.state) == ["feed", "play"])
        f.add(.fed(catID: f.cat), day: 12, hour: 8, minute: 1)
        f.add(.miniGamePlayed(game: "laser_pointer", stars: 1), day: 12, hour: 8, minute: 2)
        #expect(StreakRepair.canRepair(f.state, on: f.day(12)))
        f.add(.streakRepaired, day: 12, hour: 8, minute: 3)
        #expect(f.state.streak.current == 11)
        #expect(f.state.streak.longest == 11)
        // Once only.
        f.add(.streakRepaired, day: 12, hour: 8, minute: 4)
        #expect(f.state.streak.current == 11)
    }

    @Test func pastItsWindowABreakIsLetGo() {
        var f = Fixture()
        f.visit(days: Array(0 ... 4))
        f.visit(days: [12])
        f.add(.miniGamePlayed(game: "laser_pointer", stars: 1), day: 12, hour: 9)
        #expect(!StreakRepair.canRepair(f.state, on: f.day(12)))
        f.add(.streakRepaired, day: 12, hour: 9, minute: 1)
        #expect(f.state.streak.current == 1)
    }

    @Test func aPausedHolidayNeverBreaksIt() {
        var f = Fixture()
        f.visit(days: Array(0 ... 4))
        f.add(.pauseStarted(days: 7), day: 4, hour: 20)
        f.visit(days: [12])
        #expect(f.state.streak.current == 6)
    }
}

@Suite("Co-owners' quest and gifts")
struct CoopTests {
    @Test func aWeekOfVisitsTogetherPaysOnce() {
        var f = Fixture()
        // The owner visits on four days, the co-owner on six, day by day (the log never goes back in time).
        for day in 0 ..< 6 {
            if day < 4 {
                f.add(.arrived, day: day, hour: 8)
            }
            f.add(.arrived, day: day, hour: 9, actor: .coOwner("sam"))
            f.add(.arrived, day: day, hour: 9, minute: 30, actor: .coOwner("sam")) // twice a day counts once
        }
        let progress = CoopQuest.progress(f.state)
        #expect(progress?.total == 10)
        #expect(progress?.byOwner["co:sam"] == 6)
        #expect(progress?.isComplete == true)
        let beans = f.state.beans
        f.add(.questClaimed, day: 5, hour: 10)
        f.add(.questClaimed, day: 5, hour: 11)
        #expect(f.state.beans == beans + Tuning.Coop.questBeans)
    }

    @Test func aLoneOwnerHasNoQuestAndOneWhoDidNothingBlocksIt() {
        var f = Fixture()
        f.visit(days: Array(0 ..< 6))
        #expect(CoopQuest.progress(f.state) == nil)
        f.add(.arrived, day: 6, hour: 9, actor: .coOwner("sam"))
        let progress = CoopQuest.progress(f.state)
        #expect(progress?.isComplete == false) // sam has one visit, needs three
    }

    @Test func aFriendCodeIsSixClearCharactersAndForgivesHowItIsTyped() {
        var rng = DaySeed(household: 7, day: GameDay(index: 1), purpose: "code")
        let code = FriendCode.make(using: &rng)
        #expect(code.count == 6)
        #expect(FriendCode.normalised(code) == code)
        #expect(FriendCode.normalised(FriendCode.display(code).lowercased()) == code)
        #expect(FriendCode.normalised(" k7p q3m ") == "K7PQ3M")
        #expect(FriendCode.normalised("K7P-Q2") == nil)
        #expect(FriendCode.normalised("O0ILSZ") == nil)
        #expect(FriendCode.display("K7PQ3M") == "K7P-Q3M")
        #expect(OwnerName.display("co:Sam", otherwise: "x") == "Sam")
        #expect(OwnerName.display("owner", otherwise: "Pip's other owner") == "Pip's other owner")
    }

    @Test func anOutfitGivenByOneOwnerIsMarkedFromThem() {
        var f = Fixture()
        f.add(.purchaseBeansGranted(transactionID: "p", beans: 1000), day: 0)
        f.add(.outfitBought(outfitID: "beanie", beans: Tuning.Beans.outfit, gift: true), day: 0, hour: 10, actor: .coOwner("sam"))
        #expect(f.state.ownedOutfits.contains("beanie"))
        #expect(f.state.outfitGifts.first?.from == "co:sam")
    }
}
