import Foundation
@testable import HouseCatCore
import Testing

/// A four-week season from fixture day 0: Beans on the free track's twenty tiers but an item on 5 and the season's
/// outfit on 20; on the premium track's thirty, a piece on 1, the wallpaper on 4, Beans, and the outfit on 30.
private func testSeason(_ f: Fixture, id: String = "housewarming") -> SeasonDefinition {
    SeasonDefinition(
        id: id,
        name: "Housewarming",
        startDay: f.day(0),
        endDay: f.day(28),
        freeTrack: (1 ... Tuning.Pass.freeTiers).map { tier in
            switch tier {
            case 5: PassReward(tier: 5, kind: .item, id: "pass_housewarming_movingboxes")
            case Tuning.Pass.freeTiers: PassReward(tier: tier, kind: .outfit, id: "scarf")
            default: PassReward(tier: tier, kind: .beans, amount: 10)
            }
        },
        paidTrack: (1 ... Tuning.Pass.tiers).map { tier in
            switch tier {
            case 1: PassReward(tier: 1, kind: .item, id: "pass_housewarming_teachest")
            case 4: PassReward(tier: 4, kind: .surface, id: "wall_pass_housewarming_apricot_houses")
            case Tuning.Pass.tiers: PassReward(tier: tier, kind: .outfit, id: "crown")
            default: PassReward(tier: tier, kind: .beans, amount: 25)
            }
        }
    )
}

@Suite("Season pass")
struct PassRulesTests {
    func fixture(objectives: [ObjectiveDefinition] = []) -> Fixture {
        var context = RulesContext(dailyObjectives: objectives)
        context.seasons = [testSeason(Fixture(created: false))]
        return Fixture(context: context)
    }

    /// A busy day: arrive, feed, three strokes, five games, place a piece, a nap. XP 5 + 10 + 8 + 25 + 3 + 10 = 61.
    func busyDay(_ f: inout Fixture, _ day: Int) {
        f.add(.arrived, day: day, hour: 8)
        f.add(.fed(catID: f.cat), day: day, hour: 8)
        for minute in 0 ..< 3 {
            f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 10 + minute)
        }
        for minute in 0 ..< 5 {
            f.add(.miniGamePlayed(game: "string_chase", stars: 1), day: day, hour: 10, minute: minute)
        }
        f.add(.itemGranted(itemID: "living_box"), day: day, hour: 11)
        f.add(.itemPlaced(itemID: "living_box", room: .living, x: day % 10, y: day / 10, facing: .right), day: day, hour: 11)
        f.add(.napCompleted, day: day, hour: 12)
    }

    /// Busy days, with the Sunday card's bonus, until `tier` is reached, within the season's four weeks.
    func climb(_ f: inout Fixture, to tier: Int) {
        var day = 0
        while (f.state.passes["housewarming"]?.tier ?? 0) < tier, day < 28 {
            busyDay(&f, day)
            f.add(.sundayCardShared, day: day, hour: 13)
            day += 1
        }
        #expect((f.state.passes["housewarming"]?.tier ?? 0) >= tier, "only reached tier \(f.state.passes["housewarming"]?.tier ?? 0)")
    }

    @Test func theXPPlayEarnsClimbsThePass() throws {
        var f = fixture()
        busyDay(&f, 0)
        let state = f.state
        #expect(state.xp == 61)
        #expect(state.passes["housewarming"]?.points == 61)
        #expect(state.passes["housewarming"]?.tier == 1)
        #expect(state.today?.passPoints == 61)
        #expect(PassRules.toNextTier(try #require(state.passes["housewarming"])) == (61 - Tuning.Pass.pointsPerTier, Tuning.Pass.pointsPerTier))
    }

    @Test func goalsPayBonusPassXPOnTop() {
        let goal = ObjectiveDefinition(id: "pet_twice", metric: .pet, target: 2, beans: 15, passPoints: 20)
        var f = fixture(objectives: [goal])
        f.add(.petted(catID: f.cat), day: 0, hour: 9)
        f.add(.petted(catID: f.cat), day: 0, hour: 9, minute: 1)
        // Strokes 5 + 2 XP, and the goal's 20 on top.
        #expect(f.state.passes["housewarming"]?.points == 7 + 20)
        f.add(.sundayCardShared, day: 0, hour: 12)
        #expect(f.state.passes["housewarming"]?.points == 7 + 20 + Tuning.Pass.sundayCard)
    }

    @Test func tiersFillEverySixtyXPUpToThirty() {
        let step = Tuning.Pass.pointsPerTier
        #expect(step == 60)
        #expect(PassRules.tier(forPoints: step - 1) == 0)
        #expect(PassRules.tier(forPoints: step) == 1)
        #expect(PassRules.tier(forPoints: 20 * step - 1) == 19)
        #expect(PassRules.tier(forPoints: 30 * step - 1) == 29)
        #expect(PassRules.tier(forPoints: 50_000) == Tuning.Pass.tiers)
        var top = SeasonProgress()
        top.points = 9_999
        #expect(PassRules.toNextTier(top) == (0, 0))
    }

    @Test func theFreeTrackEndsAtTwentyAndPremiumRunsToThirty() throws {
        var f = fixture()
        f.add(.clubDayRecorded, day: 0, hour: 7, minute: 30)
        climb(&f, to: 25)
        let progress = try #require(f.state.passes["housewarming"])
        let season = testSeason(f)
        let day = f.day(27)
        #expect(PassRules.claimable(track: .free, progress: progress, season: season, day: day, ownsPaidTrack: true) == Array(1 ... 20))
        #expect(PassRules.claimable(track: .paid, progress: progress, season: season, day: day, ownsPaidTrack: true) == Array(1 ... 25))
        #expect(!PassRules.canClaim(track: .free, tier: 21, progress: progress, season: season, day: day, ownsPaidTrack: true))
    }

    @Test func freeTrackClaimsPayAndCannotRepeat() {
        var f = fixture()
        busyDay(&f, 0)
        let before = f.state.beans
        f.add(.passTierClaimed(seasonID: "housewarming", track: .free, tier: 1), day: 0, hour: 13)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .free, tier: 1), day: 0, hour: 14)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .free, tier: 2), day: 0, hour: 15) // not reached
        let state = f.state
        #expect(state.passes["housewarming"]?.claimedFree == [1])
        #expect(state.beans == before + 10)
        #expect(state.lifetime.passTiersClaimed == 1)
    }

    @Test func thePremiumTrackNeedsThePass() {
        var f = fixture()
        busyDay(&f, 0)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .paid, tier: 1), day: 0, hour: 13)
        #expect(f.state.passes["housewarming"]?.claimedPaid.isEmpty == true)
        #expect(f.state.owned["pass_housewarming_teachest"] == nil)
    }

    @Test func buyingMidSeasonOpensEveryTierReachedAtOnce() throws {
        var f = fixture()
        climb(&f, to: 12)
        let progress = try #require(f.state.passes["housewarming"])
        let season = testSeason(f)
        let day = f.day(13)
        #expect(PassRules.claimable(track: .paid, progress: progress, season: season, day: day, ownsPaidTrack: false).isEmpty)
        #expect(PassRules.openAtOnce(progress: progress, season: season) == Array(1 ... 12))

        f.add(.passPurchased(seasonID: "housewarming"), day: 13, hour: 9)
        let bought = try #require(f.state.passes["housewarming"])
        #expect(PassRules.claimable(track: .paid, progress: bought, season: season, day: day, ownsPaidTrack: bought.purchased) == Array(1 ... 12))
        for tier in 1 ... 12 {
            f.add(.passTierClaimed(seasonID: "housewarming", track: .paid, tier: tier), day: 13, hour: 10)
        }
        let state = f.state
        #expect(state.passes["housewarming"]?.claimedPaid == Set(1 ... 12))
        #expect(state.owned["pass_housewarming_teachest"] == 1)
        #expect(state.ownedSurfaces.contains("wall_pass_housewarming_apricot_houses"))
        #expect(try PassRules.openAtOnce(progress: #require(state.passes["housewarming"]), season: season).isEmpty)
    }

    @Test func catClubIncludesThePremiumTrack() {
        var f = fixture()
        busyDay(&f, 0)
        f.add(.clubDayRecorded, day: 0, hour: 12, minute: 30)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .paid, tier: 1), day: 0, hour: 13)
        #expect(f.state.passes["housewarming"]?.claimedPaid == [1])
    }

    @Test func nothingCanBeClaimedAfterTheSeasonEnds() throws {
        var f = fixture()
        busyDay(&f, 0)
        f.add(.passPurchased(seasonID: "housewarming"), day: 1)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .free, tier: 1), day: 28)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .paid, tier: 1), day: 28)
        let progress = try #require(f.state.passes["housewarming"])
        #expect(progress.claimedFree.isEmpty && progress.claimedPaid.isEmpty)
        #expect(testSeason(f).daysLeft(on: f.day(21)) == 7)
        #expect(testSeason(f).lastDay == f.day(27))
    }

    @Test func whatIsClaimedIsKeptForever() {
        var f = fixture()
        f.add(.passPurchased(seasonID: "housewarming"), day: 0, hour: 7, minute: 30)
        climb(&f, to: Tuning.Pass.tiers)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .paid, tier: Tuning.Pass.tiers), day: 27, hour: 20)
        f.add(.passTierClaimed(seasonID: "housewarming", track: .free, tier: Tuning.Pass.freeTiers), day: 27, hour: 20)
        #expect(f.state(through: 90).ownedOutfits == ["crown", "scarf"])
    }

    @Test func theNextRewardIsAlwaysInView() {
        let f = Fixture(created: false)
        let season = testSeason(f)
        var progress = SeasonProgress()
        progress.points = 3 * Tuning.Pass.pointsPerTier
        // Without the pass the next free reward; with it the premium one.
        #expect(PassRules.next(progress: progress, season: season, ownsPaidTrack: false)?.track == .free)
        #expect(PassRules.next(progress: progress, season: season, ownsPaidTrack: true)?.reward == season.reward(track: .paid, tier: 4))
        // Past the free track's end, the premium track's next reward, shown locked.
        progress.points = Tuning.Pass.freeTiers * Tuning.Pass.pointsPerTier
        let next = PassRules.next(progress: progress, season: season, ownsPaidTrack: false)
        #expect(next?.track == .paid && next?.reward.tier == Tuning.Pass.freeTiers + 1)
        // At the top there is nothing further.
        progress.points = Tuning.Pass.tiers * Tuning.Pass.pointsPerTier
        #expect(PassRules.next(progress: progress, season: season, ownsPaidTrack: true) == nil)
    }

    @Test func theTracksAreCountedForThePremiumPanel() {
        let season = testSeason(Fixture(created: false))
        let premium = PassRules.contents(of: season.paidTrack)
        #expect(premium == PassContents(pieces: 1, wallpapers: 1, floors: 0, outfits: 1, beans: 27 * 25, rewards: 30))
        #expect(PassRules.contents(of: season.freeTrack).beans == 18 * 10)
    }
}

@Suite("Season schedule")
struct SeasonScheduleTests {
    /// Black Cat (5 Oct 2026), Housewarming and Midwinter, as seasons.json names them, each with the test tracks.
    let named = [("blackcat", 10, 5, 11, 2), ("housewarming", 11, 2, 12, 1), ("midwinter", 12, 1, 12, 29)].map { id, m1, d1, m2, d2 in
        var season = testSeason(Fixture(created: false), id: id)
        season.startDay = GameDay(year: 2026, month: m1, day: d1)
        season.endDay = GameDay(year: 2026, month: m2, day: d2)
        return season
    }

    var seasons: [SeasonDefinition] {
        SeasonSchedule.seasons(named: named, through: GameDay(year: 2030, month: 12, day: 31))
    }

    @Test func everyDayFromTheFirstSeasonHasExactlyOne() {
        let seasons = seasons
        #expect(seasons.first?.id == "blackcat")
        for (a, b) in zip(seasons, seasons.dropFirst()) {
            #expect(a.endDay == b.startDay, "\(a.id) to \(b.id)")
        }
        var day = GameDay(year: 2026, month: 10, day: 5)
        while day <= GameDay(year: 2030, month: 12, day: 31) {
            #expect(seasons.count(where: { $0.contains(day) }) == 1, "\(day)")
            day = day.advanced(by: 1)
        }
        #expect(Set(seasons.map(\.id)).count == seasons.count, "every run has its own id")
    }

    @Test func aSlotThatWasNamedLastYearRunsItAgain() throws {
        let seasons = seasons
        let christmas = try #require(seasons.first { $0.contains(GameDay(year: 2027, month: 12, day: 25)) })
        #expect(christmas.passID == "midwinter" && christmas.isRerun)
        #expect(christmas.id == "midwinter@2027-12-01")
        #expect(christmas.sku == "housecat.pass.midwinter")
        let october = try #require(seasons.first { $0.contains(GameDay(year: 2027, month: 10, day: 20)) })
        #expect(october.passID == "blackcat")
        let november = try #require(seasons.first { $0.contains(GameDay(year: 2028, month: 11, day: 15)) })
        #expect(november.passID == "housewarming")
    }

    @Test func slotsNeverNamedTakeTheOrdinarySeasonsInTurnAndChristmasStaysInDecember() {
        let seasons = seasons
        for season in seasons {
            let slot = SeasonCalendar.slot(containing: season.startDay)
            #expect(slot.start == season.startDay && slot.end == season.endDay)
            #expect((season.passID == "midwinter") == slot.isChristmas, "\(season.id)")
        }
        // Between Christmas 2026 and the next October, Black Cat and Housewarming come round in turn.
        let year = seasons.filter { $0.startDay > GameDay(year: 2026, month: 12, day: 28) && $0.startDay < GameDay(year: 2027, month: 10, day: 1) }
        #expect(Set(year.map(\.passID)) == ["blackcat", "housewarming"])
        for (a, b) in zip(year, year.dropFirst()) {
            #expect(a.passID != b.passID)
        }
    }

    @Test func aRunAgainStartsFromNothingAndItsPassCanBeHad() throws {
        var context = RulesContext()
        context.seasons = seasons
        var f = Fixture(context: context)
        let rerun = try #require(context.season(on: GameDay(year: 2027, month: 11, day: 15)))
        let offset = f.day(0).distance(to: GameDay(year: 2027, month: 11, day: 15))
        f.add(.passPurchased(seasonID: rerun.id), day: offset, hour: 8)
        f.add(.arrived, day: offset, hour: 9)
        f.add(.fed(catID: f.cat), day: offset, hour: 9, minute: 1)
        for minute in 0 ..< 5 {
            f.add(.miniGamePlayed(game: "laser_pointer", stars: 2), day: offset, hour: 10, minute: minute)
        }
        f.add(.napCompleted, day: offset, hour: 10, minute: 30)
        f.add(.sundayCardShared, day: offset, hour: 10, minute: 40)
        f.add(.passTierClaimed(seasonID: rerun.id, track: .paid, tier: 1), day: offset, hour: 11)
        let state = f.state
        #expect(state.passes[rerun.id]?.tier == 1)
        #expect(state.passes[rerun.id]?.purchased == true)
        #expect(state.passes[rerun.id]?.claimedPaid == [1])
        #expect(state.owned["pass_housewarming_teachest"] == 1)
        #expect(state.passes["housewarming"] == nil)
    }
}

@Suite("Season pass content")
struct PassContentTests {
    let content: ContentBundle
    let context: RulesContext

    init() throws {
        content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        context = try content.rulesContext()
    }

    @Test func thePassIsAlwaysOn() throws {
        // From Black Cat (5 Oct 2026, so TestFlight and App Review see the pass) for years: one season every day.
        let first = try #require(GameDay(iso: content.seasons.seasons[0].startAt))
        #expect(context.season(on: GameDay(year: 2026, month: 10, day: 19))?.id == "blackcat")
        var day = first
        while day < first.advanced(by: 365 * 8) {
            #expect(context.season(on: day) != nil, "\(day)")
            day = day.advanced(by: 7)
        }
        let named = Set(content.seasons.seasons.map(\.id))
        for season in context.seasons {
            #expect(named.contains(season.passID))
            #expect(season.sku == "housecat.pass.\(season.passID)")
            #expect(context.season(id: season.id) == season)
        }
        for year in 2026 ... 2033 {
            #expect(context.season(on: GameDay(year: year, month: 12, day: 25))?.passID == "midwinter")
        }
        // The launch events still count from the launch, not from Black Cat.
        #expect(content.seasons.launchDay == GameDay(year: 2026, month: 11, day: 2))
    }

    @Test func premiumIsClearlyBetterThanFree() throws {
        for season in content.seasons.seasons {
            let definition = try season.definition()
            let free = PassRules.contents(of: definition.freeTrack)
            let premium = PassRules.contents(of: definition.paidTrack)
            #expect(premium.beans >= 2 * free.beans, "\(season.id)")
            #expect(premium.pieces >= free.pieces, "\(season.id)")
            #expect(premium.wallpapers == 1 && premium.floors == 1, "\(season.id)")
            #expect(premium.outfits == 2 && free.outfits == 1, "\(season.id)")
            #expect(premium.rewards == Tuning.Pass.tiers && free.rewards == Tuning.Pass.freeTiers, "\(season.id)")
        }
    }

    @Test func noTwoSeasonsGiveTheSameOutfit() {
        let outfits = content.seasons.seasons.flatMap { ($0.freeTrack + $0.paidTrack).filter { $0.kind == .outfit }.compactMap(\.id) }
        #expect(Set(outfits).count == outfits.count)
    }
}

/// The pass's month through the real rules and content (Josh, 19 Oct: the pass is the main progression). Three players
/// as PacingTests has them, through Housewarming's four weeks: a light one feeds and strokes the cat and takes the
/// present, a regular one also plays two games, a keen one plays all five, naps and strokes more. A regular player
/// ends the free track and a keen one the premium track. HOUSECAT_PACING=1 prints the weeks.
@Suite("Pass pacing")
struct PassPacingTests {
    static func season(_ player: PacingTests.Player, context: RulesContext) -> [Int] {
        var f = Fixture(context: context)
        f.add(.tourFinished, day: 0, hour: 7, minute: 30)
        var tiers: [Int] = []
        for day in 0 ..< Tuning.Pass.seasonLengthDays {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: 2)
            let pets = player == .light ? 2 : player == .regular ? 4 : 6
            for pet in 0 ..< pets {
                f.add(.petted(catID: f.cat), day: day, hour: 8, minute: 4 + pet)
            }
            f.collectGifts(day: day, hour: 12)
            let games = player == .light ? 0 : player == .regular ? 2 : 5
            for game in 0 ..< games {
                f.add(.miniGamePlayed(game: ["laser", "knock", "string"][game % 3], stars: player == .keen ? 3 : 2), day: day, hour: 18, minute: game)
            }
            if player == .keen {
                f.add(.napCompleted, day: day, hour: 21)
            }
            tiers.append(f.state.passes["housewarming"]?.tier ?? 0)
        }
        return tiers
    }

    @Test func aRegularPlayerEndsTheFreeTrackAndAKeenOneThePremium() throws {
        let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
        let context = try content.rulesContext()
        let print = ProcessInfo.processInfo.environment["HOUSECAT_PACING"] != nil
        var reached: [PacingTests.Player: [Int]] = [:]
        for player in PacingTests.Player.allCases {
            let tiers = Self.season(player, context: context)
            reached[player] = tiers
            if print {
                Swift.print("== pass, \(player.rawValue): week by week \([6, 13, 20, 27].map { tiers[$0] })")
            }
        }
        let light = try #require(reached[.light]), regular = try #require(reached[.regular]), keen = try #require(reached[.keen])
        // A regular player ends the free track in the last week, and a keen one the premium track.
        #expect(regular[27] >= Tuning.Pass.freeTiers && regular[20] < Tuning.Pass.freeTiers, "regular: \(regular)")
        #expect(keen[27] >= Tuning.Pass.tiers, "keen: \(keen)")
        // ... though not in the first three weeks, so the last one still matters.
        #expect(keen[20] < Tuning.Pass.tiers, "keen: \(keen)")
        // A light player gets well along the free track, and a regular one is short of the top.
        #expect(light[27] >= 12 && light[27] < Tuning.Pass.freeTiers, "light: \(light)")
        #expect(regular[27] < Tuning.Pass.tiers, "regular: \(regular)")
    }
}
