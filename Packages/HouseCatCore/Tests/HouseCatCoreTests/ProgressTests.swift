@testable import HouseCatCore
import Testing

@Suite("Levels and trust")
struct LevelAndTrustTests {
    @Test func levelThresholdsMatchTheSpec() {
        let expected = [1: 0, 2: 100, 3: 250, 4: 450, 5: 700, 6: 1000, 7: 1350, 8: 1750, 9: 2200, 10: 2700, 11: 3250, 12: 3850]
        for (level, xp) in expected {
            #expect(LevelCurve.threshold(for: level) == xp)
            #expect(LevelCurve.level(forXP: xp) == level)
            if xp > 0 {
                #expect(LevelCurve.level(forXP: xp - 1) == level - 1)
            }
        }
    }

    @Test func afterLevelTwelveEachLevelCosts650() {
        #expect(LevelCurve.threshold(for: 13) == 4500)
        #expect(LevelCurve.threshold(for: 14) == 5150)
        #expect(LevelCurve.level(forXP: 4499) == 12)
        #expect(LevelCurve.level(forXP: 4500) == 13)
        #expect(LevelCurve.level(forXP: 100_000) == 12 + (100_000 - 3850) / 650)
        let progress = LevelCurve.progress(xp: 300)
        #expect(progress.level == 3 && progress.intoLevel == 50 && progress.toNext == 150)
    }

    @Test func trustTiersAtThreeSevenFourteenThirtySixtyAndAHundredCareDays() {
        #expect(TrustTier.forCareDays(0) == .newcomer)
        #expect(TrustTier.forCareDays(2) == .newcomer)
        #expect(TrustTier.forCareDays(3) == .wary)
        #expect(TrustTier.forCareDays(7) == .curious)
        #expect(TrustTier.forCareDays(14) == .comfortable)
        #expect(TrustTier.forCareDays(29) == .comfortable)
        #expect(TrustTier.forCareDays(30) == .bonded)
        #expect(TrustTier.forCareDays(60) == .devoted)
        #expect(TrustTier.forCareDays(100) == .soulmate)
        #expect(TrustTier.forCareDays(5000) == .soulmate)
        #expect(TrustTier.soulmate.careDaysRequired == 100)
    }

    @Test func trustCountsFedDaysAndNeverFalls() {
        var f = Fixture()
        f.visit(days: [0, 1, 2]) // three fed days
        f.visit(days: [3], feed: false)
        // A long absence: trust stays.
        f.visit(days: [20])
        let state = f.state(through: 40)
        #expect(state.cat(f.cat)?.careDays == 4)
        #expect(state.cat(f.cat)?.trust == .wary)
    }

    @Test func feedingTwiceInADayCountsOnce() {
        var f = Fixture()
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        f.add(.fed(catID: f.cat), day: 0, hour: 18)
        #expect(f.state.cat(f.cat)?.careDays == 1)
        #expect(f.state.lifetime.feeds == 1)
    }
}

@Suite("Visit streak")
struct StreakTests {
    @Test func consecutiveVisitsCount() {
        var f = Fixture()
        f.visit(days: Array(0 ..< 5))
        let state = f.state(through: 4)
        #expect(state.streak.current == 5)
        #expect(state.streak.longest == 5)
    }

    @Test func aWidgetOnlyDayKeepsTheStreak() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.petted(catID: f.cat), day: 1, hour: 12, source: .widget)
        f.add(.fed(catID: f.cat), day: 2, hour: 7, source: .watch)
        f.add(.fed(catID: f.cat), day: 3, hour: 7, source: .mac)
        let state = f.state(through: 4)
        #expect(state.streak.current == 4)
    }

    @Test func oneFreeMissPerRollingWeek() {
        var f = Fixture()
        f.visit(days: [0, 1, 2]) // miss day 3
        f.visit(days: [4, 5])
        var state = f.state(through: 6)
        #expect(state.streak.current == 5) // the missed day is forgiven but does not count
        #expect(state.streak.graceDays == [f.day(3)])

        // A second miss within the same rolling week loses the streak.
        f.visit(days: [6]) // miss day 7
        state = f.state(through: 8)
        #expect(state.streak.current == 0)
        #expect(state.streak.longest == 6)
    }

    @Test func theFreeMissComesBackAfterAWeek() {
        var f = Fixture()
        f.visit(days: [0, 1, 2]) // miss 3 (graced)
        f.visit(days: [4, 5, 6, 7, 8, 9]) // miss 10: 3 + 7, outside the window
        f.visit(days: [11])
        let state = f.state(through: 12)
        #expect(state.streak.current == 10)
        #expect(state.streak.graceDays == [f.day(10)])
    }

    @Test func aLostStreakRestartsAtOneAndKeepsTheLongest() {
        var f = Fixture()
        f.visit(days: Array(0 ..< 10)) // 10 days, then miss 10 and 11
        f.visit(days: [12, 13])
        let state = f.state(through: 14)
        #expect(state.streak.current == 2)
        #expect(state.streak.longest == 10)
    }

    @Test func milestonesPayOnceWithBeans() {
        var f = Fixture()
        f.visit(days: Array(0 ..< 7), feed: false)
        let state = f.state(through: 7)
        #expect(state.streak.milestonesReached == [7])
        // allowance 150 + 7 arrivals × 10 + the 7-day milestone 100
        #expect(state.beans == 150 + 70 + 100)
        // Losing it and reaching 7 again pays nothing more.
        f.visit(days: Array(9 ..< 16), feed: false)
        #expect(f.state(through: 16).streak.milestonesReached == [7])
    }

    @Test func milestoneBeansMatchTheSpec() {
        #expect([7, 30, 100, 365].map(StreakState.beans(forMilestone:)) == [100, 300, 1000, 3000])
    }

    @Test func pausedDaysNeitherCountNorBreak() {
        var f = Fixture()
        f.visit(days: [0, 1])
        f.add(.pauseStarted(days: 5), day: 1, hour: 21)
        f.visit(days: [7]) // days 2–6 paused (day 1 was visited)
        let state = f.state(through: 8)
        #expect(state.streak.current == 3)
        #expect(state.streak.graceDays.isEmpty)
        #expect(state.pause.usedByQuarter.values.reduce(0, +) == 5)
    }

    @Test func pauseIsCappedAtFourteenDaysAQuarter() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.pauseStarted(days: 14), day: 0, hour: 21) // days 1–13 paused
        f.visit(days: [14])
        f.add(.pauseStarted(days: 14), day: 14, hour: 21) // only one day left this quarter
        f.visit(days: [17])
        let state = f.state(through: 18)
        // Day 15 is the last paused day; day 16 is a miss (graced), so the streak holds.
        #expect(state.pause.usedByQuarter[f.day(15).quarter] == 14)
        #expect(state.streak.graceDays == [f.day(16)])
        #expect(state.streak.current == 3)
    }

    @Test func endingAPauseEarlyMakesLaterDaysCountAgain() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.pauseStarted(days: 10), day: 0, hour: 21)
        f.add(.pauseEnded, day: 3, hour: 9)
        // Day 3 had an event but no visit; the pause ended that morning.
        let state = f.state(through: 6)
        #expect(state.streak.current == 0) // days 3 and 4 missed after the pause: lost
    }

    @Test func aSitterOrCoOwnerVisitCounts() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.fed(catID: f.cat), day: 1, actor: .sitter("friend"))
        f.add(.arrived, day: 2, actor: .coOwner("partner"))
        #expect(f.state(through: 3).streak.current == 3)
    }
}
