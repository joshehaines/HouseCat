@testable import HouseCatCore
import Testing

@Suite("XP and Beans")
struct EconomyTests {
    @Test func aFreshHouseholdHasTheHousewarmingAllowance() {
        let f = Fixture()
        #expect(f.state.beans == 150)
        #expect(f.state.openedRooms == [.living])
        #expect(f.state.placed.isEmpty) // the house is empty apart from the cat
    }

    @Test func arrivalPaysOnceADay() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        f.add(.arrived, day: 0, hour: 12)
        #expect(f.state.beans == 160)
        #expect(f.state.xp == 5)
    }

    @Test func aTypicalDayOfCare() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        for minute in 1 ... 4 {
            f.add(.petted(catID: f.cat), day: 0, hour: 8, minute: minute)
        }
        f.add(.napCompleted, day: 0, hour: 22)
        f.add(.napCompleted, day: 0, hour: 22, minute: 30)
        f.add(.healthGoalMet(.steps), day: 0, hour: 20)
        // arrival 5 + feed 10 + pets 5+2+1 + nap 10 + steps 10
        #expect(f.state.xp == 43)
    }

    @Test func levelUpsPayBeans() {
        var f = Fixture()
        for day in 0 ..< 3 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8)
            f.add(.healthGoalMet(.steps), day: day, hour: 20)
            f.add(.healthGoalMet(.sleep), day: day, hour: 20)
            f.add(.healthGoalMet(.workout), day: day, hour: 20)
        }
        let state = f.state(through: 3)
        #expect(state.xp == 3 * 45)
        #expect(state.level == 2)
        #expect(state.beans == 150 + 30 + 100)
    }

    @Test func miniGamesPayStarsAndStopAfterFivePlays() {
        var f = Fixture()
        for (minute, stars) in [0, 1, 2, 3, 3, 3].enumerated() {
            f.add(.miniGamePlayed(game: "laser_pointer", stars: stars), day: 0, hour: 10, minute: minute)
        }
        let state = f.state
        #expect(state.today?.plays == 5)
        #expect(state.xp == 25)
        #expect(state.beans == 150 + 0 + 2 + 4 + 6 + 6)
        #expect(state.lifetime.minigameWins == 4)
        #expect(state.lifetime.threeStarGames == 2)
    }

    @Test func furnitureXPIsCappedPerDay() {
        var f = Fixture()
        for i in 0 ..< 5 {
            f.add(.itemGranted(itemID: "living_box"), day: 0)
            f.add(.itemPlaced(itemID: "living_box", room: .living, x: i, y: 0, facing: .right), day: 0)
        }
        #expect(f.state.xp == 9)
        #expect(f.state.placed.count == 5)
    }

    @Test func theCatUsingNewFurniturePaysOncePerItemAndIsCapped() {
        var f = Fixture()
        for (i, item) in ["living_sofa", "living_box", "living_cattree"].enumerated() {
            f.add(.itemGranted(itemID: item), day: 0)
            f.add(.itemPlaced(itemID: item, room: .living, x: i * 3, y: 4, facing: .left), day: 0)
        }
        let placingXP = 9
        f.add(.catUsedNewItem(catID: f.cat, itemID: "living_sofa"), day: 0, hour: 10)
        f.add(.catUsedNewItem(catID: f.cat, itemID: "living_sofa"), day: 0, hour: 11)
        f.add(.catUsedNewItem(catID: f.cat, itemID: "living_box"), day: 0, hour: 12)
        f.add(.catUsedNewItem(catID: f.cat, itemID: "living_cattree"), day: 0, hour: 13)
        #expect(f.state.xp == placingXP + 6)
    }

    @Test func spendingNeedsTheBeans() {
        var f = Fixture()
        f.add(.itemBought(itemID: "living_lamp", beans: 60), day: 0)
        f.add(.itemBought(itemID: "living_sofa", beans: 600), day: 0) // cannot afford: ignored
        let state = f.state
        #expect(state.beans == 90)
        #expect(state.owned == ["living_lamp": 1])
    }

    @Test func itemsCanOnlyBePlacedIfOwnedInsideTheGridInAnOpenRoom() {
        var f = Fixture()
        f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 1, y: 1, facing: .right), day: 0) // not owned
        f.add(.itemGranted(itemID: "living_sofa"), day: 0)
        f.add(.itemPlaced(itemID: "living_sofa", room: .bedroom, x: 1, y: 1, facing: .right), day: 0) // locked room
        // The first home's rooms are 8 cells square (Tuning.Room.sizes).
        f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 8, y: 1, facing: .right), day: 0) // off the grid
        let placed = f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 7, y: 7, facing: .right), day: 0)
        f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 2, y: 2, facing: .right), day: 0) // only one owned
        #expect(f.state.placed.count == 1)
        f.add(.itemMoved(placementID: placed.id, room: .living, x: 0, y: 0, facing: .left), day: 0)
        #expect(f.state.placed.first?.x == 0 && f.state.placed.first?.facing == .left)
        f.add(.itemStored(placementID: placed.id), day: 0)
        #expect(f.state.placed.isEmpty)
        #expect(f.state.owned["living_sofa"] == 1)
    }

    @Test func catClubAddsTwentyPercentOnClubDaysOnly() {
        var f = Fixture()
        f.add(.arrived, day: 1, hour: 8)
        f.add(.miniGamePlayed(game: "knock_it_off", stars: 3), day: 1, hour: 9)
        f.add(.miniGamePlayed(game: "knock_it_off", stars: 3), day: 1, hour: 10)
        f.add(.clubDayRecorded, day: 1, hour: 11) // recorded after the earning, still counts for the day
        f.add(.arrived, day: 2, hour: 8)
        let state = f.state(through: 3)
        // Day 1: (10 + 6 + 6) × 1.2 = 26 (rounded down) and the members' treat; day 2: 10, no Club.
        #expect(state.beans == 150 + 26 + Tuning.Beans.clubTreat + 10)
    }

    @Test func movingHomeIsFreeOnceThenCostsBeansUnlessClub() {
        var f = Fixture()
        f.add(.homeMoved(beans: 0), day: 0)
        f.add(.homeMoved(beans: 0), day: 0) // second move needs 500: ignored
        #expect(f.state.lifetime.homeMoves == 1)
        f.add(.clubDayRecorded, day: 1)
        f.add(.homeMoved(beans: 0), day: 1)
        #expect(f.state.lifetime.homeMoves == 2)
    }

    @Test func overPettingMakesTheCatWalkOffExceptAVelcroCat() {
        #expect(Personality.aloof.walksOff(afterConsecutivePets: 6))
        #expect(!Personality.aloof.walksOff(afterConsecutivePets: 5))
        #expect(!Personality.velcro.walksOff(afterConsecutivePets: 60))
    }
}

@Suite("Room gating")
struct RoomTests {
    @Test func gatesMatchTheSpec() {
        let expected: [RoomID: (Int, Int)] = [
            .living: (1, 0), .bedroom: (2, 200), .kitchen: (3, 300), .garden: (6, 800), .study: (9, 1500), .attic: (12, 2500),
        ]
        for (room, gate) in expected {
            #expect(room.requiredLevel == gate.0)
            #expect(room.fullBeanCost == gate.1)
        }
    }

    @Test func aRoomNeedsTheLevelAndTheBeans() {
        #expect(RoomRules.availability(of: .bedroom, opened: [.living], level: 1, beans: 5000, clubActive: false)
            == .locked(level: 2, cost: 200, needsLevel: true, needsBeans: false))
        #expect(RoomRules.availability(of: .bedroom, opened: [.living], level: 2, beans: 199, clubActive: false)
            == .locked(level: 2, cost: 200, needsLevel: false, needsBeans: true))
        #expect(RoomRules.availability(of: .bedroom, opened: [.living], level: 2, beans: 200, clubActive: false) == .unlockable(cost: 200))
        #expect(RoomRules.availability(of: .living, opened: [], level: 1, beans: 0, clubActive: false) == .open)
    }

    @Test func catClubHalvesTheBeansButNeverSkipsALevel() {
        #expect(RoomRules.cost(of: .attic, clubActive: true) == 1250)
        #expect(RoomRules.availability(of: .attic, opened: [.living], level: 11, beans: 99999, clubActive: true)
            == .locked(level: 12, cost: 1250, needsLevel: true, needsBeans: false))
    }

    @Test func emptyHouseThenTheSecondRoomNeedsLevelTwoAnd200Beans() {
        var f = Fixture()
        f.add(.roomOpened(.bedroom, beans: 200), day: 0) // level 1: refused
        #expect(f.state.openedRooms == [.living])
        // Earn level 2 (100 XP) over a few days, and the Beans to go with it.
        for day in 0 ..< 3 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8)
            for goal in GameEvent.HealthGoal.allCases {
                f.add(.healthGoalMet(goal), day: day, hour: 20)
            }
        }
        f.add(.roomOpened(.bedroom, beans: 100), day: 3) // underpaid: refused
        #expect(f.state.openedRooms == [.living])
        f.add(.roomOpened(.bedroom, beans: 200), day: 3)
        let state = f.state
        #expect(state.level >= 2)
        #expect(state.openedRooms == [.living, .bedroom])
        #expect(state.beans == 150 + 30 + 100 - 200)
    }
}

@Suite("Gifts")
struct GiftTests {
    let pool = [
        GiftDefinition(id: "oddities_sock", rarity: .common),
        GiftDefinition(id: "toys_mouse", rarity: .uncommon),
        GiftDefinition(id: "keepsakes_brass_key", rarity: .rare),
        GiftDefinition(id: "keepsakes_moonstone", rarity: .legendary),
        GiftDefinition(id: "seasonal_holly", rarity: .common, months: [12]),
    ]

    @Test func oddsShiftThreePointsPerTierFromCommonToRareAndLegendary() {
        #expect(GiftRules.weights(for: .newcomer) == [.common: 60, .uncommon: 28, .rare: 10, .legendary: 2])
        #expect(GiftRules.weights(for: .soulmate) == [.common: 42, .uncommon: 28, .rare: 22, .legendary: 8])
        for tier in TrustTier.allCases {
            #expect(GiftRules.weights(for: tier).values.reduce(0, +) == 100)
        }
    }

    @Test func drawsFollowTheOdds() {
        var counts: [GiftRarity: Int] = [:]
        let clock = DayClock()
        let start = GameDay(year: 2026, month: 11, day: 2)
        for i in 0 ..< 4000 {
            let day = start.advanced(by: i)
            let draw = GiftRules.draw(
                household: 1,
                catID: "pip",
                fedDay: day,
                fedAt: clock.date(on: day, atLocalMinutes: 480),
                tier: .newcomer,
                pool: [],
                clock: clock
            )
            counts[draw.rarity, default: 0] += 1
        }
        #expect((2200 ... 2600).contains(counts[.common] ?? 0))
        #expect((25 ... 140).contains(counts[.legendary] ?? 0))
    }

    @Test func dropsBetweenAnHourAfterFeedingAndTenAtNight() {
        let f = Fixture()
        for offset in 0 ..< 50 {
            let fedAt = f.at(offset, 8)
            let draw = GiftRules.draw(
                household: f.seed,
                catID: f.cat,
                fedDay: f.day(offset),
                fedAt: fedAt,
                tier: .wary,
                pool: pool,
                clock: f.clock
            )
            #expect(draw.dropAt >= fedAt.addingTimeInterval(3600))
            #expect(draw.dropAt < f.at(offset, 22))
        }
    }

    @Test func aLateFeedDropsTheGiftNextMorning() {
        let f = Fixture()
        let draw = GiftRules.draw(
            household: f.seed,
            catID: f.cat,
            fedDay: f.day(0),
            fedAt: f.at(0, 21, 30),
            tier: .wary,
            pool: pool,
            clock: f.clock
        )
        #expect(draw.dropAt >= f.at(1, 6))
        #expect(draw.dropAt < f.at(1, 7))
    }

    @Test func seasonalGiftsOnlyInTheirMonths() {
        let f = Fixture()
        let commons = (0 ..< 200).map {
            GiftRules.draw(
                household: UInt64($0),
                catID: f.cat,
                fedDay: f.day(0),
                fedAt: f.at(0, 8),
                tier: .newcomer,
                pool: pool,
                clock: f.clock
            )
        }.filter { $0.rarity == .common }
        #expect(!commons.isEmpty)
        #expect(commons.allSatisfy { $0.giftID == "oddities_sock" }) // November: no holly
    }

    @Test func oneGiftADayWhenFedCollectedOnce() {
        var f = Fixture(context: RulesContext(gifts: pool))
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        var state = f.state
        #expect(state.pendingGifts.count == 1)
        let gift = state.pendingGifts[0]
        #expect(state.waitingGifts(at: f.at(0, 8, 30)).isEmpty)
        f.log.append(GameEvent(
            at: gift.dropAt.addingTimeInterval(60),
            day: f.day(0),
            kind: .giftCollected(catID: f.cat, giftID: gift.giftID, rarity: gift.rarity)
        ))
        f.log.append(GameEvent(
            at: gift.dropAt.addingTimeInterval(120),
            day: f.day(0),
            kind: .giftCollected(catID: f.cat, giftID: gift.giftID, rarity: gift.rarity)
        ))
        state = f.state
        #expect(state.pendingGifts.isEmpty)
        #expect(state.lifetime.gifts == 1)
        #expect(state.beans == 150 + gift.rarity.collectBeans)
    }

    @Test func noGiftTheDayAfterAMissedDay() {
        var f = Fixture(context: RulesContext(gifts: pool))
        f.visit(days: [0]) // day 1 missed
        f.visit(days: [2])
        let state = f.state(through: 2)
        #expect(state.missedYesterday)
        #expect(state.pendingGifts.map(\.fedDay) == [f.day(0)])
    }

    @Test func paidProductsNeverChangeTheGift() {
        var plain = Fixture(context: RulesContext(gifts: pool))
        var club = Fixture(context: RulesContext(gifts: pool))
        club.add(.clubDayRecorded, day: 0, hour: 7, minute: 30)
        club.add(.passPurchased(seasonID: "housewarming"), day: 0, hour: 7, minute: 31)
        plain.add(.fed(catID: plain.cat), day: 0, hour: 8)
        club.add(.fed(catID: club.cat), day: 0, hour: 8)
        #expect(plain.state.pendingGifts == club.state.pendingGifts)
    }

    @Test func duplicatesSellBackForBeans() throws {
        var f = Fixture(context: RulesContext(gifts: pool))
        var collected: [GiftDraw] = []
        for day in 0 ..< 40 {
            f.add(.fed(catID: f.cat), day: day, hour: 8)
            let gift = try #require(f.state.pendingGifts.last)
            f.log.append(GameEvent(
                at: f.at(day, 22, 30),
                day: f.day(day),
                kind: .giftCollected(catID: f.cat, giftID: gift.giftID, rarity: gift.rarity)
            ))
            collected.append(gift)
        }
        let before = f.state
        let duplicate = try #require(before.giftsCollected.first { $0.value >= 2 })
        let rarity = try #require(pool.first { $0.id == duplicate.key }?.rarity)
        f.add(.giftSold(giftID: duplicate.key, rarity: rarity), day: 40, hour: 9)
        let after = f.state
        #expect(after.giftsCollected[duplicate.key] == duplicate.value - 1)
        #expect(after.beans - before.beans == rarity.sellBackBeans)
        // A single copy cannot be sold.
        if let single = after.giftsCollected.first(where: { $0.value == 1 }) {
            f.add(.giftSold(giftID: single.key, rarity: .common), day: 40, hour: 10)
            #expect(f.state.giftsCollected[single.key] == 1)
        }
        #expect(collected.count == 40)
    }
}

@Suite("Purchases in the save")
struct PurchaseRulesTests {
    @Test func purchaseBeansCountOncePerTransactionAndGetNoClubBonus() {
        var f = Fixture()
        f.add(.clubDayRecorded, day: 0, hour: 8)
        f.add(.purchaseBeansGranted(transactionID: "2000000123", beans: 300), day: 0, hour: 9)
        f.add(.purchaseBeansGranted(transactionID: "2000000123", beans: 300), day: 0, hour: 9, source: .mac) // another device
        #expect(f.state(through: 1).beans == 150 + Tuning.Beans.clubTreat + 300, "no +20% on bought Beans; the members' treat only")
    }

    @Test func paidSetItemsCanBePlacedOnceWithoutABeanPurchase() {
        var f = Fixture(context: RulesContext(paidItems: ["living_fireplace"]))
        f.add(.itemPlaced(itemID: "living_fireplace", room: .living, x: 0, y: 0, facing: .right), day: 0)
        f.add(.itemPlaced(itemID: "living_fireplace", room: .living, x: 4, y: 0, facing: .right), day: 0)
        f.add(.itemPlaced(itemID: "living_sofa", room: .living, x: 6, y: 0, facing: .right), day: 0) // not owned, not paid
        #expect(f.state.placed.map(\.itemID) == ["living_fireplace"])
    }
}
