import Foundation
@testable import HouseCatCore
import Testing

/// Step 2's exit test: on a test clock the together count rises through a missed day and a lost streak.
@Test func theTogetherCountRisesThroughAMissedDayAndALostStreak() throws {
    var fixture = Fixture()
    fixture.visit(days: [0, 1, 2, 3, 4])
    var profile = try #require(fixture.state(through: 4).profile(of: fixture.cat, on: fixture.day(4)))
    #expect(profile.togetherDays == 4)
    #expect(profile.currentStreak == 5)
    // One missed day (the week's free miss), then a long gap that loses the streak.
    fixture.visit(days: [6])
    profile = try #require(fixture.state(through: 6).profile(of: fixture.cat, on: fixture.day(6)))
    #expect(profile.togetherDays == 6)
    fixture.visit(days: [20])
    profile = try #require(fixture.state(through: 20).profile(of: fixture.cat, on: fixture.day(20)))
    #expect(profile.currentStreak == 1)
    #expect(profile.longestStreak >= 5)
    #expect(profile.togetherDays == 20)
    // Days pass with no visit at all: it keeps counting.
    profile = try #require(fixture.state(through: 30).profile(of: fixture.cat, on: fixture.day(30)))
    #expect(profile.togetherDays == 30)
    #expect(profile.meals == 7)
    #expect(profile.visits == 7)
}

@Test func pauseModeNeverTouchesTheTogetherCount() throws {
    var fixture = Fixture()
    fixture.visit(days: [0, 1])
    fixture.add(.pauseStarted(days: 5), day: 1, hour: 21)
    let profile = try #require(fixture.state(through: 5).profile(of: fixture.cat, on: fixture.day(5)))
    #expect(profile.togetherDays == 5)
}

@Test func theProfileCountsTrustAndTheTierAhead() throws {
    var fixture = Fixture()
    fixture.visit(days: [0, 1, 2])
    let profile = try #require(fixture.state(through: 3).profile(of: fixture.cat, on: fixture.day(3)))
    #expect(profile.careDays == 3)
    #expect(profile.trust == .wary)
    #expect(profile.careDaysToNextTier == 4)
}

@Test func gotchaDaysMonthsAndTheHundredthDay() {
    let adopted = GameDay(year: 2026, month: 1, day: 31)
    #expect(HouseholdState.anniversary(adopted: adopted, on: adopted) == nil)
    #expect(HouseholdState.anniversary(adopted: adopted, on: GameDay(year: 2026, month: 2, day: 28)) == .monthly(months: 1))
    #expect(HouseholdState.anniversary(adopted: adopted, on: GameDay(year: 2026, month: 3, day: 31)) == .monthly(months: 2))
    #expect(HouseholdState.anniversary(adopted: adopted, on: GameDay(year: 2026, month: 3, day: 30)) == nil)
    #expect(HouseholdState.anniversary(adopted: adopted, on: adopted.advanced(by: 100)) == .hundredDays)
    #expect(HouseholdState.anniversary(adopted: adopted, on: GameDay(year: 2027, month: 1, day: 31)) == .yearly(years: 1))
    #expect(HouseholdState.anniversary(adopted: adopted, on: GameDay(year: 2027, month: 2, day: 28)) == nil)
    let leap = GameDay(year: 2028, month: 2, day: 29)
    #expect(HouseholdState.anniversary(adopted: leap, on: GameDay(year: 2029, month: 2, day: 28)) == .yearly(years: 1))
    #expect(HouseholdState.wholeYears(from: leap, to: GameDay(year: 2029, month: 2, day: 27)) == 0)
    #expect(HouseholdState.wholeYears(from: leap, to: GameDay(year: 2029, month: 2, day: 28)) == 1)
}

@Test func badgesForAHundredDaysAndEachYear() {
    let fixture = Fixture()
    let state = fixture.state(through: 0)
    #expect(state.profile(of: fixture.cat, on: fixture.day(99))?.badges == [])
    #expect(state.profile(of: fixture.cat, on: fixture.day(100))?.badges == [.hundredDays])
    #expect(state.profile(of: fixture.cat, on: fixture.day(366))?.badges == [.hundredDays, .years(1)])
    #expect(state.profile(of: fixture.cat, on: fixture.day(731))?.badges == [.hundredDays, .years(1), .years(2)])
}
