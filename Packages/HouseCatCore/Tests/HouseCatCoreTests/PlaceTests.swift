import Foundation
@testable import HouseCatCore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private func cities() throws -> CitiesFile {
    try JSONDecoder().decode(CitiesFile.self, from: Data(contentsOf: repo.appendingPathComponent("assets/world/map/cities.json")))
}

@Test func theMapIsEquirectangular() {
    let p = WorldMap.point(latitude: 0, longitude: 0, width: 4096, height: 2048)
    #expect(p.x == 2048 && p.y == 1024)
    let london = WorldMap.point(latitude: 51.5, longitude: -0.13, width: 4096, height: 2048)
    let back = WorldMap.coordinate(x: london.x, y: london.y, width: 4096, height: 2048)
    #expect(abs(back.latitude - 51.5) < 0.0001 && abs(back.longitude + 0.13) < 0.0001)
    // Off the right edge wraps round.
    #expect(abs(WorldMap.coordinate(x: 4096 + 2048, y: 0, width: 4096, height: 2048).longitude) < 0.0001)
    #expect(abs(WorldMap.distance((51.507, -0.128), (48.857, 2.352)) - 344) < 5, "London to Paris")
}

@Test func aPinInACityIsCity() throws {
    let file = try cities()
    #expect(file.cities.count > 200)
    #expect(file.city(near: 51.4946, -0.1003)?.name == "London", "Elephant and Castle")
    #expect(file.city(near: 51.75, -0.34)?.name == "London", "St Albans, inside a big city's reach")
    #expect(file.city(near: 23.0, 12.0) == nil, "the middle of the Sahara")
    #expect(BiomeRules.biome(maskIndex: 5, inCity: true) == .city)
    #expect(BiomeRules.biome(maskIndex: 5, inCity: false) == .desert)
    #expect(BiomeRules.biome(maskIndex: 0, inCity: false) == .coast, "a mooring on the sea")
    #expect(BiomeRules.biome(maskIndex: 99, inCity: false) == .coast)
    // Every city sits on the map's land or its shore.
    #expect(Set(file.cities.map(\.name)).count == file.cities.count)
}

@Test func theFirstPinIsFreeAndLaterOnesAreMoves() {
    var fixture = Fixture()
    let paris = HomePlace(name: "Paris", latitude: 48.857, longitude: 2.352, timeZoneID: "Europe/Paris", biome: .city)
    let lisbon = HomePlace(name: "Lisbon", latitude: 38.722, longitude: -9.139, timeZoneID: "Europe/Lisbon", biome: .coast)
    let sydney = HomePlace(name: "Sydney", latitude: -33.869, longitude: 151.209, timeZoneID: "Australia/Sydney", biome: .city)
    #expect(fixture.state.home.place == nil)
    fixture.add(.homePlaced(paris), day: 0)
    #expect(fixture.state.home.place == paris)
    // Moving needs a move first.
    fixture.add(.homePlaced(lisbon), day: 0)
    #expect(fixture.state.home.place == paris)
    fixture.add(.homeMoved(beans: 0), day: 0)
    fixture.add(.homePlaced(lisbon), day: 0)
    #expect(fixture.state.home.place == lisbon)
    #expect(fixture.state.lifetime.homeMoves == 1)
    // The free move is used: the next one costs Beans, which this player does not have.
    fixture.add(.homeMoved(beans: 0), day: 0)
    fixture.add(.homePlaced(sydney), day: 0)
    #expect(fixture.state.home.place == lisbon)
    #expect(sydney.southernHemisphere)
    #expect(sydney.timeZone.identifier == "Australia/Sydney")
}

@Test func theSeasonCanBeFixedOrAuto() {
    var fixture = Fixture()
    #expect(fixture.state.home.season == .auto)
    fixture.add(.seasonSet(.fixed(.winter)), day: 0)
    #expect(fixture.state.home.season == .fixed(.winter))
    fixture.add(.seasonSet(.fixed(.winter)), day: 0)
    #expect(fixture.state.lifetime.seasonChanges == 1, "setting the same season again is not a change")
    fixture.add(.seasonSet(.auto), day: 0)
    #expect(fixture.state.home.season == .auto)
    // On Auto the season follows the home's hemisphere.
    let july = GameDay(year: 2026, month: 7, day: 1)
    #expect(NatureSeason.of(month: july.month, southernHemisphere: false) == .summer)
    #expect(NatureSeason.of(month: july.month, southernHemisphere: true) == .winter)
}

@Test func simulatedWeatherFollowsTheBiomesSeasonalTable() throws {
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    let start = GameDay(year: 2026, month: 1, day: 1)
    for biome in Biome.allCases {
        for season in NatureSeason.allCases {
            #expect(!content.weather.weights(biome: biome, season: season).isEmpty, "\(biome) \(season)")
        }
    }
    var desert: [Weather: Int] = [:], mountain: [Weather: Int] = [:]
    for i in 0 ..< 400 {
        let day = start.advanced(by: i)
        desert[WeatherRules.simulated(biome: .desert, season: .summer, day: day, household: 9, tables: content.weather), default: 0] += 1
        mountain[WeatherRules.simulated(biome: .mountain, season: .winter, day: day, household: 9, tables: content.weather), default: 0] +=
            1
    }
    #expect(desert[.snow] == nil && desert[.rain] == nil)
    #expect((desert[.heat] ?? 0) > 150)
    #expect((mountain[.snow] ?? 0) > 120)
    // The same day gives the same weather on every device.
    let a = WeatherRules.simulated(biome: .coast, season: .autumn, day: start, household: 3, tables: content.weather)
    let b = WeatherRules.simulated(biome: .coast, season: .autumn, day: start, household: 3, tables: content.weather)
    #expect(a == b)
}
