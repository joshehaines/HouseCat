import Foundation
@testable import HouseCatCore
import Testing

@Suite("Event-log save")
struct SaveLogTests {
    /// Forty days of mixed play with misses, a pause, purchases and claims.
    func busyLog() -> Fixture {
        var context = RulesContext()
        context.gifts = [
            GiftDefinition(id: "oddities_sock", rarity: .common),
            GiftDefinition(id: "toys_mouse", rarity: .uncommon),
            GiftDefinition(id: "keepsakes_key", rarity: .rare),
            GiftDefinition(id: "keepsakes_moonstone", rarity: .legendary),
        ]
        context.dailyObjectives = [
            ObjectiveDefinition(id: "pet_twice", metric: .pet, target: 2, beans: 15, passPoints: 5),
            ObjectiveDefinition(id: "play_one", metric: .playMinigame, target: 1, beans: 10, passPoints: 5),
            ObjectiveDefinition(id: "early", metric: .feedBefore9, target: 1, beans: 20, passPoints: 5),
            ObjectiveDefinition(id: "window", metric: .tapWindow, target: 1, beans: 10, passPoints: 5),
        ]
        context.weeklyObjectives = [ObjectiveDefinition(id: "five_days", metric: .visitDay, target: 5, beans: 80, passPoints: 20)]
        context.achievements = [ObjectiveDefinition(id: "fed_20", metric: .totalFeeds, target: 20, beans: 100, passPoints: 0)]
        let start = GameDay(year: 2026, month: 11, day: 2)
        context.seasons = [SeasonDefinition(
            id: "s1", startDay: start, endDay: start.advanced(by: 28),
            freeTrack: (1 ... 20).map { PassReward(tier: $0, kind: .beans, amount: 10) },
            paidTrack: (1 ... 20).map { PassReward(tier: $0, kind: .beans, amount: 25) }
        )]
        var f = Fixture(context: context)
        for day in 0 ..< 40 where ![5, 6, 13, 14, 15, 30].contains(day) {
            f.add(.arrived, day: day, hour: 8)
            f.add(.fed(catID: f.cat), day: day, hour: 8, minute: day % 3 == 0 ? 50 : 10)
            f.add(.petted(catID: f.cat), day: day, hour: 9)
            f.add(.petted(catID: f.cat), day: day, hour: 9, minute: 1)
            f.add(.miniGamePlayed(game: "laser_pointer", stars: day % 4), day: day, hour: 10)
            if day % 2 == 0 {
                f.add(.windowTapped, day: day, hour: 11)
            }
            if day == 3 {
                f.add(.itemBought(itemID: "living_lamp", beans: 60), day: day, hour: 12)
            }
            if day == 4 {
                f.add(.itemPlaced(itemID: "living_lamp", room: .living, x: 3, y: 3, facing: .left), day: day, hour: 12)
            }
            if day == 9 {
                f.add(.passPurchased(seasonID: "s1"), day: day, hour: 12)
            }
            if day == 12 {
                f.add(.pauseStarted(days: 3), day: day, hour: 21)
            }
            if day % 5 == 0 {
                f.collectGifts(day: day, hour: 23)
            }
            if day == 20 {
                for tier in 1 ... 8 {
                    f.add(.passTierClaimed(seasonID: "s1", track: .free, tier: tier), day: day, hour: 22)
                    f.add(.passTierClaimed(seasonID: "s1", track: .paid, tier: tier), day: day, hour: 22)
                }
            }
        }
        return f
    }

    @Test func appendIgnoresDuplicates() {
        var f = Fixture()
        let event = f.add(.arrived, day: 0)
        let added = f.log.append(event)
        #expect(!added)
        #expect(f.log.events.filter { $0.id == event.id }.count == 1)
    }

    @Test func eventsAddedAtTheSameMomentKeepTheirOrder() {
        var log = SaveLog()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let first = log.timestamp(for: moment)
        log.append(GameEvent(at: first, day: GameDay(index: 20000), kind: .arrived))
        let second = log.timestamp(for: moment)
        #expect(second > first)
    }

    @Test func devicesMergeToTheSameStateInAnyOrder() {
        let f = busyLog()
        let all = f.log.events
        // Split the events between "iPhone" and "widget" and merge both ways.
        let phone = all.enumerated().filter { $0.offset % 3 != 0 }.map(\.element)
        let widget = all.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        var a = SaveLog(events: phone)
        a.merge(widget)
        var b = SaveLog(events: widget.reversed())
        b.merge(phone.shuffled())
        b.merge(widget) // merging twice changes nothing
        #expect(a == b)
        #expect(a.derive(through: f.day(45), context: f.context) == f.state(through: 45))
    }

    @Test func compactionNeverChangesTheDerivedState() {
        let f = busyLog()
        let full = f.state(through: 45)
        for boundary in [1, 7, 12, 14, 16, 25, 39, 40, 44] {
            let compacted = f.log.compacted(before: f.day(boundary), context: f.context)
            #expect(compacted.events.allSatisfy { $0.day >= f.day(boundary) })
            #expect(compacted.derive(through: f.day(45), context: f.context) == full, "boundary \(boundary)")
            // Compacting again, later, is still the same.
            let twice = compacted.compacted(before: f.day(min(boundary + 3, 45)), context: f.context)
            #expect(twice.derive(through: f.day(45), context: f.context) == full, "boundary \(boundary) twice")
        }
    }

    @Test func theBusyLogExercisesEveryRule() {
        let state = busyLog().state(through: 45)
        #expect(state.streak.longest >= 5)
        #expect(state.streak.graceDays.isEmpty == false || state.streak.current == 0)
        #expect(state.pause.usedByQuarter.values.reduce(0, +) >= 2)
        #expect(state.completedAchievements == ["fed_20"])
        #expect(state.passes["s1"]?.claimedPaid.count == 8)
        #expect(state.placed.count == 1)
        #expect(state.lifetime.gifts > 0)
        #expect(state.beans > 150)
    }

    @Test func theSaveSurvivesEncoding() throws {
        let f = busyLog()
        let compacted = f.log.compacted(before: f.day(20), context: f.context)
        let data = try JSONEncoder().encode(compacted)
        let decoded = try JSONDecoder().decode(SaveLog.self, from: data)
        #expect(decoded == compacted)
        #expect(decoded.derive(through: f.day(45), context: f.context) == f.state(through: 45))
    }

    @Test func compactionBoundaryIsThirtyDaysBack() {
        let today = GameDay(year: 2026, month: 12, day: 31)
        #expect(SaveLog.compactionBoundary(today: today) == GameDay(year: 2026, month: 12, day: 1))
    }

    @Test func aLateEventFromBeforeTheSnapshotLandsOnTheOpenDay() {
        var f = Fixture()
        f.visit(days: [0, 1, 2, 3])
        var compacted = f.log.compacted(before: f.day(3), context: f.context)
        let late = GameEvent(at: f.at(1, 12), day: f.day(1), kind: .windowTapped)
        compacted.append(late)
        let state = compacted.derive(context: f.context)
        #expect(state.today?.day == f.day(3))
        #expect(state.today?.metrics[.tapWindow] == 1)
    }
}
