import Foundation
@testable import HouseCatCore
import Testing

@Test func seasonsFollowTheMonthAndFlipSouthOfTheEquator() {
    #expect(NatureSeason.of(month: 4, southernHemisphere: false) == .spring)
    #expect(NatureSeason.of(month: 7, southernHemisphere: false) == .summer)
    #expect(NatureSeason.of(month: 10, southernHemisphere: false) == .autumn)
    #expect(NatureSeason.of(month: 12, southernHemisphere: false) == .winter)
    #expect(NatureSeason.of(month: 1, southernHemisphere: false) == .winter)
    #expect(NatureSeason.of(month: 7, southernHemisphere: true) == .winter)
    #expect(NatureSeason.of(month: 12, southernHemisphere: true) == .summer)
}

@Test func autoSeasonUsesTheHomesTimeZoneAndAFixedSeasonNeverChanges() throws {
    // 31 Aug 23:30 in London is already 1 Sep in Tokyo.
    let date = try #require(ISO8601DateFormatter().date(from: "2026-08-31T22:30:00Z"))
    let london = try #require(TimeZone(identifier: "Europe/London")), tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    #expect(SeasonSetting.auto.season(at: date, timeZone: london, southernHemisphere: false) == .summer)
    #expect(SeasonSetting.auto.season(at: date, timeZone: tokyo, southernHemisphere: false) == .autumn)
    #expect(SeasonSetting.fixed(.winter).season(at: date, timeZone: london, southernHemisphere: false) == .winter)
}

@Test func skyPhaseFollowsTheHomesLocalTime() {
    #expect(SkyPhase.at(localMinutes: 6 * 60) == .dawn)
    #expect(SkyPhase.at(localMinutes: 12 * 60) == .day)
    #expect(SkyPhase.at(localMinutes: 19 * 60) == .dusk)
    #expect(SkyPhase.at(localMinutes: 23 * 60) == .night)
    #expect(SkyPhase.at(localMinutes: 2 * 60) == .night)
    #expect(SkyPhase.day.lightMap(weather: .sun) == "midday")
    #expect(SkyPhase.day.lightMap(weather: .rain) == "overcast")
    #expect(SkyPhase.night.lightMap(weather: .rain) == "night")
}

@Test func everySkyPhaseHasItsColours() {
    for phase in SkyPhase.allCases {
        #expect(Tuning.Sky.top[phase]?.count == 3)
        #expect(Tuning.Sky.bottom[phase]?.count == 3)
        #expect(Tuning.Sky.grade[phase]?.count == 3)
        #expect(Tuning.Sky.windowGlow[phase] != nil)
    }
}

@Test func exteriorPlaysOnlyAfterAnHourAway() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(ArrivalRules.showsExterior(lastActive: nil, now: now))
    #expect(!ArrivalRules.showsExterior(lastActive: now.addingTimeInterval(-59 * 60), now: now))
    #expect(ArrivalRules.showsExterior(lastActive: now.addingTimeInterval(-61 * 60), now: now))
}
