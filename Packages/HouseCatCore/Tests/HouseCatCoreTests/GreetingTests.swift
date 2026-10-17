import Foundation
@testable import HouseCatCore
import Testing

@Test func firstEverArrivalGetsTheFirstEverLine() {
    let fixture = Fixture()
    #expect(Greeting.context(before: fixture.state(through: 0), at: fixture.at(0, 9)) == "arrival.first_ever")
}

@Test func firstAndLaterArrivalsOfTheDay() {
    var fixture = Fixture()
    fixture.visit(days: [0])
    #expect(Greeting.context(before: fixture.state(through: 1), at: fixture.at(1, 9)) == "arrival.first_of_day")
    fixture.visit(days: [1])
    #expect(Greeting.context(before: fixture.state(through: 1), at: fixture.at(1, 15)) == "arrival.second_visit")
}

@Test func lateAndEarlyArrivalsBeatTheDayLines() {
    var fixture = Fixture()
    fixture.visit(days: [0, 1])
    #expect(Greeting.context(before: fixture.state(through: 1), at: fixture.at(1, 23, 30)) == "arrival.late_night")
    // 05:00 belongs to the previous game day (the day starts at wake time).
    #expect(Greeting.context(before: fixture.state(through: 1), at: fixture.at(1, 5)) == "arrival.early")
}

@Test func afterAMissTheCatSulksThenThawsThenIsFine() {
    var fixture = Fixture()
    fixture.visit(days: [0])
    #expect(Greeting.context(before: fixture.state(through: 2), at: fixture.at(2, 9)) == "missed.one_day")
    fixture.visit(days: [2])
    #expect(Greeting.context(before: fixture.state(through: 2), at: fixture.at(2, 12)) == "missed.thawing")
    fixture.add(.arrived, day: 2, hour: 12)
    #expect(Greeting.context(before: fixture.state(through: 2), at: fixture.at(2, 18)) == "missed.fine")
    fixture.add(.arrived, day: 2, hour: 18)
    #expect(Greeting.context(before: fixture.state(through: 2), at: fixture.at(2, 20)) == "arrival.second_visit")
}

@Test func longerAbsencesGetTheirOwnLines() {
    var fixture = Fixture()
    fixture.visit(days: [0])
    #expect(Greeting.context(before: fixture.state(through: 4), at: fixture.at(4, 9)) == "missed.few_days")
    #expect(Greeting.context(before: fixture.state(through: 9), at: fixture.at(9, 9)) == "missed.week_plus")
}

@Test func greetingLinesExistForEveryContextAndPersonality() throws {
    let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
    let contexts = [
        "arrival.first_ever",
        "arrival.first_of_day",
        "arrival.second_visit",
        "arrival.late_night",
        "arrival.early",
        "missed.one_day",
        "missed.few_days",
        "missed.week_plus",
        "missed.thawing",
        "missed.fine",
    ]
    for context in contexts {
        for personality in Personality.allCases {
            #expect(!content.lines.variants(for: context, personality: personality).isEmpty, "\(context) \(personality)")
        }
    }
    let cat = try #require(Fixture().state.cat("midnight"))
    var rng = DaySeed(household: 1, day: GameDay(index: 0), purpose: "greeting")
    let line = try #require(Greeting.line("arrival.first_of_day", cat: cat, lines: content.lines, rng: &rng))
    #expect(!line.contains("{cat}"))
}

@Test func feedLinesKnowWhetherTheBowlIsAlreadyFull() {
    var fixture = Fixture()
    fixture.add(.arrived, day: 1, hour: 8)
    #expect(CareLines.feed(before: fixture.state(through: 1), catID: fixture.cat) == "feed.fed")
    fixture.add(.fed(catID: fixture.cat), day: 1, hour: 8, minute: 5)
    #expect(CareLines.feed(before: fixture.state(through: 1), catID: fixture.cat) == "feed.already_fed")
}

@Test func petLinesCountTheDayAndTheTapsInARow() {
    var fixture = Fixture()
    fixture.add(.arrived, day: 1, hour: 8)
    #expect(CareLines.pet(before: fixture.state(through: 1), catID: fixture.cat, taps: 1) == "pet.first")
    fixture.add(.petted(catID: fixture.cat), day: 1, hour: 8, minute: 1)
    #expect(CareLines.pet(before: fixture.state(through: 1), catID: fixture.cat, taps: 2) == "pet.repeat")
    // The fixture's cat is Aloof: six in a row and it walks off.
    #expect(CareLines.pet(before: fixture.state(through: 1), catID: fixture.cat, taps: Tuning.Care.overPetTaps) == "pet.too_many")
}
