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

@Test func aTapSnapsToTheNearestCityWithinAFingertip() throws {
    let file = try cities()
    // Taps in the Peak District with a fingertip 60 km across: the nearer of Sheffield and Manchester.
    #expect(file.nearest(to: 53.35, -1.8, within: 60)?.name == "Sheffield")
    #expect(file.nearest(to: 53.45, -2.1, within: 60)?.name == "Manchester")
    #expect(file.nearest(to: 23.0, 12.0, within: 100) == nil, "the middle of the Sahara, close in")
    #expect(file.nearest(to: 23.0, 12.0, within: 2500) != nil, "far out, a fingertip spans a country")
}

@Test func typingFindsListedCitiesWithoutAConnection() throws {
    let file = try cities()
    #expect(file.matching("lon", limit: 3).first?.name == "London")
    #expect(file.matching("  SAO ", limit: 3).map(\.name) == ["São Paulo"], "case and accents ignored")
    #expect(file.matching("mal", limit: 3).contains { $0.name == "Málaga" })
    #expect(file.matching("", limit: 3).isEmpty)
    #expect(file.matching("b", limit: 2).count == 2)
    #expect(file.matching("b", limit: 2).allSatisfy { $0.big }, "big cities first")
}

@Test func theCitiesToPickStartAtHome() throws {
    let file = try cities()
    let british = file.suggestions(country: "United Kingdom")
    #expect(british.count == Tuning.World.suggestedCities)
    #expect(british.prefix(3).map(\.name) == ["London", "Manchester", "Birmingham"])
    #expect(Set(british).count == british.count, "London is not listed twice")
    #expect(british.contains { $0.name == "Tokyo" })
    let nowhere = file.suggestions(country: nil)
    #expect(nowhere.map(\.name) == Array(Tuning.World.suggestedWorld.prefix(Tuning.World.suggestedCities)))
    // Every name in the world list is a listed city.
    #expect(Tuning.World.suggestedWorld.allSatisfy { name in file.cities.contains { $0.name == name } })
}

@Test func theFirstPinIsFreeAndLaterOnesAreMoves() {
    var fixture = Fixture()
    let paris = HomePlace(name: "Paris", latitude: 48.857, longitude: 2.352, timeZoneID: "Europe/Paris", biome: .city)
    let lisbon = HomePlace(name: "Lisbon", latitude: 38.722, longitude: -9.139, timeZoneID: "Europe/Lisbon", biome: .coast)
    let sydney = HomePlace(name: "Sydney", latitude: -33.869, longitude: 151.209, timeZoneID: "Australia/Sydney", biome: .city)
    #expect(fixture.state.home.place == nil)
    #expect(fixture.state.moveCost == 0)
    fixture.add(.homePlaced(paris), day: 0)
    #expect(fixture.state.moveCost == 0, "the first move is free")
    #expect(fixture.state.home.place == paris)
    // Moving needs a move first.
    fixture.add(.homePlaced(lisbon), day: 0)
    #expect(fixture.state.home.place == paris)
    fixture.add(.homeMoved(beans: 0), day: 0)
    fixture.add(.homePlaced(lisbon), day: 0)
    #expect(fixture.state.home.place == lisbon)
    #expect(fixture.state.lifetime.homeMoves == 1)
    #expect(fixture.state.moveCost == Tuning.Beans.moveHome)
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

@Test func theHomeKeepsItsOwnTimeSeasonAndWeather() throws {
    let tables = try ContentBundle.load(from: repo.appendingPathComponent("Content")).weather
    var fixture = Fixture()
    // The home is the ladder's city: made-up Puddlebury at the bottom, on London's clock.
    let noonLondon = fixture.at(0, 12)
    var now = fixture.state.homeNow(at: noonLondon, weather: tables)
    #expect(now.place == HouseLadder.rung(1).place)
    #expect(now.localMinutes == 12 * 60)
    #expect(now.season == .autumn)
    // Up the ladder in Tokyo it is nine at night (an old pin is ignored).
    fixture.add(.homePlaced(.london), day: 0, hour: 9)
    var state = fixture.state
    state.home.rung = 5
    now = state.homeNow(at: noonLondon, weather: tables)
    #expect(now.place.name == "Tokyo")
    #expect(now.season == .autumn)
    #expect(now.biome == .city)
    #expect(now.sky == .night)
    #expect(now.localMinutes == 21 * 60)
    // A season fixed by the player wins over the calendar.
    fixture.add(.seasonSet(.fixed(.winter)), day: 0, hour: 9)
    #expect(fixture.state.homeNow(at: noonLondon, weather: tables).season == .winter)
    // The weather is the biome's seasonal table, the same all day.
    let morning = fixture.state.homeNow(at: fixture.at(0, 7), weather: tables).weather
    #expect(fixture.state.homeNow(at: fixture.at(0, 20), weather: tables).weather == morning)
}

@Test func theHomeStyleIsChosenWithTheFirstPinOrWhileMoving() {
    var fixture = Fixture()
    #expect(fixture.state.home.style == nil)
    fixture.add(.homeStyleChosen(.cottage), day: 0)
    #expect(fixture.state.home.style == .cottage)
    let bath = HomePlace(name: "Bath", latitude: 51.38, longitude: -2.36, timeZoneID: "Europe/London", biome: .countryside)
    fixture.add(.homePlaced(bath), day: 0)
    // Settled in: another style only comes with a move.
    fixture.add(.homeStyleChosen(.houseboat), day: 0)
    #expect(fixture.state.home.style == .cottage)
    fixture.add(.homeMoved(beans: 0), day: 0)
    fixture.add(.homeStyleChosen(.houseboat), day: 0)
    #expect(fixture.state.home.style == .houseboat)
    #expect(HouseStyle.allCases.allSatisfy { !$0.name.isEmpty && !$0.blurb.isEmpty })
}

@Suite("Globe")
struct GlobeTests {
    @Test func theCentreFacesTheViewer() {
        let view = GlobeOrientation(latitude: 51.5, longitude: -0.1)
        let p = view.project(latitude: 51.5, longitude: -0.1)
        #expect(abs(p.x) < 1e-9 && abs(p.y) < 1e-9)
        #expect(abs(p.depth - 1) < 1e-9)
        let back = view.project(latitude: -51.5, longitude: 179.9)
        #expect(back.depth < -0.9)
    }

    @Test func northIsUpAndEastIsRight() {
        let view = GlobeOrientation(latitude: 0, longitude: 0)
        #expect(view.project(latitude: 30, longitude: 0).y > 0)
        #expect(view.project(latitude: 0, longitude: 30).x > 0)
    }

    @Test func aTapFindsThePlaceItWasProjectedFrom() {
        let view = GlobeOrientation(latitude: 38, longitude: 140)
        for (lat, lon) in [(35.68, 139.69), (43.06, 141.35), (21.3, 157.8), (-33.87, 151.2)] {
            let p = view.project(latitude: lat, longitude: lon)
            guard p.depth > 0, let place = view.place(x: p.x, y: p.y) else { continue }
            #expect(abs(place.latitude - lat) < 1e-6)
            #expect(abs(place.longitude - lon) < 1e-6)
        }
        #expect(view.place(x: 0.9, y: 0.9) == nil)
    }

    @Test func dragsFollowTheFingerAndStopShortOfThePoles() {
        let view = GlobeOrientation(latitude: 0, longitude: 0)
        #expect(view.dragged(dx: 0.5, dy: 0).longitude < 0)
        #expect(view.dragged(dx: 0, dy: 0.5).latitude > 0)
        #expect(view.dragged(dx: 0, dy: 10).latitude == Tuning.World.globeTiltLimit)
        #expect(GlobeOrientation(latitude: 0, longitude: 179).dragged(dx: -0.1, dy: 0).longitude < -170)
    }

    @Test func aPinchKeepsThePlaceUnderTheFingers() {
        let view = GlobeOrientation(latitude: 30, longitude: 10)
        // Paris, under the fingers at a point; the globe doubles in size: Paris stays at that point.
        let before = view.project(latitude: 48.857, longitude: 2.352)
        let after = view.keeping(latitude: 48.857, longitude: 2.352, at: before.x / 2, before.y / 2)
        let p = after.project(latitude: 48.857, longitude: 2.352)
        #expect(abs(p.x - before.x / 2) < 0.002 && abs(p.y - before.y / 2) < 0.002)
        // Nothing to keep round the back.
        #expect(view.keeping(latitude: -40, longitude: -170, at: 0, 0) == view)
    }

    @Test func aFlightGoesTheShortWayRound() {
        let from = GlobeOrientation(latitude: 0, longitude: 170), to = GlobeOrientation(latitude: 10, longitude: -170)
        let half = from.blended(to: to, by: 0.5)
        #expect(abs(abs(half.longitude) - 180) < 1e-9)
        #expect(abs(half.latitude - 5) < 1e-9)
        #expect(from.blended(to: to, by: 1).longitude == -170)
    }
}
