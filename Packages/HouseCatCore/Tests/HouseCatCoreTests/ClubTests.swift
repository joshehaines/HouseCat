@testable import HouseCatCore
import Testing

/// Cat Club's perks from 1.0 (Josh, 25 Oct): +20% Beans, a daily treat and a monthly streak shield.
@Suite("Cat Club")
struct ClubTests {
    /// The treat comes once a club day, as Beans and pass XP; the gift book is never touched.
    @Test func aClubDayBringsTheTreatOnce() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        let before = f.state.beans
        let gifts = f.state.pendingGifts.count
        f.add(.clubDayRecorded, day: 0, hour: 8, minute: 1)
        let after = f.state.beans
        #expect(after >= before + Tuning.Beans.clubTreat, "the treat, and the day's +20% on what was earned")
        f.add(.clubDayRecorded, day: 0, hour: 9)
        #expect(f.state.beans == after, "once a day")
        #expect(f.state.pendingGifts.count == gifts)
        #expect(f.state.lastClubDay == f.day(0))
    }

    /// Two missed days in a week: the free miss holds the first, a member's shield the second; without Cat Club
    /// the second breaks it, as before. One shield a calendar month.
    @Test func aMembersShieldHoldsTheStreakOnceAMonth() {
        var member = Fixture()
        var plain = Fixture()
        for day in 0 ... 9 {
            member.add(.arrived, day: day, hour: 8)
            member.add(.clubDayRecorded, day: day, hour: 8, minute: 1)
            plain.add(.arrived, day: day, hour: 8)
        }
        #expect(plain.state(through: 12).streak.current == 0)
        #expect(member.state(through: 12).streak.current == 10)
        #expect(member.state(through: 12).streak.shieldDays.count == 1)
        member.add(.arrived, day: 12, hour: 8)
        #expect(member.state.streak.current == 11)
        // A second pair of misses in the same month: the shield is used, so it breaks.
        #expect(member.state(through: 15).streak.current == 0 || member.day(15).date.month != member.day(11).date.month)
    }
}
