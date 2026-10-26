import CoreGraphics
import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private struct World {
    let art: ArtLibrary
    let content: ContentBundle
    let plans: HousePlans
    let layout: RoomModel
    let mask: Raster
    let cities: CitiesFile

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        plans = try art.data("rooms/houses.json", as: HousePlans.self)
        layout = try art.data("rooms/layout_living_demo.json", as: RoomModel.self)
        mask = try #require(Raster.read(repo.appendingPathComponent("App/Art/world/map/map_biome.png")))
        cities = try art.data("world/map/cities.json", as: CitiesFile.self)
    }

    /// The biome under a pin, as the map screen works it out.
    func biome(_ latitude: Double, _ longitude: Double) -> Biome {
        let p = WorldMap.point(latitude: latitude, longitude: longitude, width: Double(mask.width), height: Double(mask.height))
        let index = mask.planes[0][min(mask.height - 1, Int(p.y)) * mask.width + min(mask.width - 1, Int(p.x))]
        return BiomeRules.biome(maskIndex: Int(index), inCity: cities.city(near: latitude, longitude) != nil)
    }

    /// Every room of a home open, for its windows.
    func state() -> HouseholdState {
        var log = SaveLog()
        let clock = DayClock(wakeMinutes: 360, bedtimeMinutes: 1380, timeZoneID: "Europe/London")
        let day = GameDay(year: 2026, month: 11, day: 2)
        log.append(GameEvent(at: clock.date(on: day, atLocalMinutes: 480), day: day, kind: .householdCreated(seed: 1, clock: clock)))
        return log.derive(context: .empty)
    }
}

/// Step 4's exit test: pin anywhere and every window shows it. Each pin generalises to its biome (the painted
/// mask, or a listed city), and every room of the home looks out on that biome's terrain in the season there.
@MainActor
@Test func pinAnywhereAndEveryWindowShowsIt() throws {
    let world = try World()
    let pins: [(String, Double, Double, Biome)] = [
        ("Elephant and Castle", 51.4946, -0.1003, .city),
        ("the Cotswolds", 51.8, -1.8, .countryside),
        ("Zermatt", 46.02, 7.75, .mountain),
        ("the Sahara", 23, 12, .desert),
        ("the Amazon", -3.5, -62, .tropical),
        ("Siberia", 60, 100, .forest),
        ("Svalbard", 78.2, 15.6, .snow),
        ("a Cornish cove", 50.2, -5.5, .coast),
    ]
    let state = world.state()
    for (name, latitude, longitude, expected) in pins {
        let biome = world.biome(latitude, longitude)
        #expect(biome == expected, "\(name)")
        let place = HomePlace(name: name, latitude: latitude, longitude: longitude, timeZoneID: "UTC", biome: biome)
        for season in NatureSeason.allCases {
            let now = HomeNow(place: place, biome: biome, season: season, sky: .day, weather: .sun, localMinutes: 720)
            let house = try #require(HouseBuilder.house(
                style: .londonTerrace, plans: world.plans, layout: world.layout, state: state,
                catalogue: world.content.catalogue, now: now
            ))
            let terrain = HouseBuilder.terrain(biome, season)
            #expect(world.art.has(terrain), "\(terrain) is bundled")
            let windows = house.rooms.filter { $0.model.window != nil }
            #expect(windows.count == house.rooms.filter { !$0.outdoor }.count, "every room but the garden has a window")
            #expect(windows.allSatisfy { $0.model.terrain == terrain }, "\(name) in \(season)")
            // The terrace's exterior is painted in its own town's biome only, the city (26 Oct: the ladder fixes the town).
            #expect(world.art.has(HouseBuilder.scene(.londonTerrace, biome, season) + ".jpg") == (biome == .city))
        }
    }
    // The windows are drawn: a room with its window up shows a view behind the frame.
    let place = HomePlace(name: "Zermatt", latitude: 46.02, longitude: 7.75, timeZoneID: "Europe/Zurich", biome: .mountain)
    let now = HomeNow(place: place, biome: .mountain, season: .winter, sky: .day, weather: .snow, localMinutes: 720)
    let house = try #require(HouseBuilder.house(
        style: .londonTerrace, plans: world.plans, layout: world.layout, state: state, catalogue: world.content.catalogue, now: now
    ))
    let scene = RoomScene(size: CGSize(width: 1366, height: 1024), art: world.art, content: world.content, house: house)
    for (id, node) in scene.rooms where house.room(id)?.model.window != nil {
        #expect(node.childNode(withName: "window.view") != nil, "\(id) has its view")
    }
}

/// And the grading reads right at four times of day: the same view is brightest by day, warm at dawn and dusk,
/// darkest at night; the sky over the window and the painting outside follow.
@MainActor
@Test func theGradingReadsRightAtFourTimesOfDay() throws {
    let world = try World()
    let terrain = try #require(world.art.image(HouseBuilder.terrain(.countryside, .summer)))
    let opening = try #require(world.art.image("rooms/windows/window_sash_opening.png"))
    func color(_ rgb: [Double]?) -> CGColor {
        let c = rgb ?? [1, 1, 1]
        return CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
    }
    var brightness: [SkyPhase: Double] = [:], warmth: [SkyPhase: Double] = [:]
    for phase in SkyPhase.allCases {
        let view = try #require(Composite.windowView(
            size: CGSize(width: 240, height: 320),
            opening: opening,
            skyTop: color(Tuning.Sky.top[phase]),
            skyBottom: color(Tuning.Sky.bottom[phase]),
            terrain: terrain,
            grade: color(Tuning.Sky.grade[phase])
        ))
        let raster = try #require(Raster(view))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in 0 ..< raster.width * raster.height where raster.planes[3][i] > 200 {
            r += Double(raster.planes[0][i])
            g += Double(raster.planes[1][i])
            b += Double(raster.planes[2][i])
            n += 1
        }
        #expect(n > 1000, "\(phase): the window shows something")
        brightness[phase] = (0.3 * r + 0.55 * g + 0.15 * b) / n
        warmth[phase] = (r - b) / n
    }
    let b = brightness.mapValues { $0 }
    #expect(try #require(b[.day]) > #require(b[.dawn]) && #require(b[.day]) > #require(b[.dusk]), "day is brightest: \(b)")
    #expect(try #require(b[.night]) < #require(b[.dawn]) && #require(b[.night]) < #require(b[.dusk]), "night is darkest: \(b)")
    #expect(try #require(b[.night]) < #require(b[.day]) * 0.6, "night is properly dark")
    #expect(try #require(warmth[.dusk]) > #require(warmth[.day]), "dusk is warmer than noon")
    #expect(try #require(warmth[.dawn]) > #require(warmth[.night]), "dawn is warmer than night")
    // The light in the rooms follows the same clock, overcast by day in grey weather.
    #expect(SkyPhase.day.lightMap(weather: .sun) == "midday")
    #expect(SkyPhase.day.lightMap(weather: .rain) == "overcast")
    #expect(Set(SkyPhase.allCases.map { $0.lightMap(weather: .sun) }).count == 4)
    for phase in SkyPhase.allCases {
        #expect(world.art.has("rooms/lightmaps/lm_\(phase.lightMap(weather: .sun))_floor.png"))
    }
}

/// The weather shows outside and in every window: what falls, the wash, fog, lightning, clouds.
@MainActor
@Test func theWeatherShowsOutsideAndInEveryWindow() throws {
    let world = try World()
    #expect(WeatherLayer.recipe(weather: .storm, season: .summer).lightning)
    #expect(WeatherLayer.recipe(weather: .rain, season: .spring).falls == [.rain(heavy: false)], "rain, not blossom, when it rains")
    #expect(WeatherLayer.recipe(weather: .sun, season: .spring).falls == [.petals])
    #expect(WeatherLayer.recipe(weather: .sun, season: .autumn).falls == [.leaves])
    #expect(WeatherLayer.recipe(weather: .sun, season: .summer).falls.isEmpty)
    #expect(WeatherLayer.recipe(weather: .fog, season: .autumn).fog)
    for weather in Weather.allCases {
        for season in NatureSeason.allCases {
            let layer = WeatherLayer.node(weather: weather, season: season, size: CGSize(width: 800, height: 400), unit: 24, art: world.art)
            #expect(layer.name == "weather")
            if weather != .sun || season == .spring || season == .autumn {
                #expect(!layer.children.isEmpty, "\(weather) in \(season) shows something")
            }
        }
    }
    for path in ["raindrop", "snowflake", "leaf", "petal", "cloud", "fog"] {
        #expect(world.art.has("world/weather/\(path).png"))
    }
    // Every window of a rainy house carries the rain.
    let place = HomePlace(name: "Bristol", latitude: 51.45, longitude: -2.59, timeZoneID: "Europe/London", biome: .city)
    let now = HomeNow(place: place, biome: .city, season: .autumn, sky: .day, weather: .rain, localMinutes: 720)
    let house = try #require(HouseBuilder.house(
        style: .londonTerrace, plans: world.plans, layout: world.layout, state: world.state(),
        catalogue: world.content.catalogue, now: now
    ))
    let scene = RoomScene(size: CGSize(width: 1366, height: 1024), art: world.art, content: world.content, house: house)
    for (id, node) in scene.rooms where house.room(id)?.model.window != nil {
        #expect(node.childNode(withName: "window.weather") != nil, "\(id) shows the rain")
    }
}

@MainActor
@Test func theGroundIsTheBiomesOwnUnderSnowInWinterHills() throws {
    let world = try World()
    for biome in Biome.allCases {
        let path = HouseBuilder.ground(biome, season: .summer, weather: .sun)
        #expect(world.art.has(path), "\(path)")
    }
    #expect(HouseBuilder.ground(.city, season: .summer, weather: .sun) == "world/ground/ground_city.png")
    #expect(HouseBuilder.ground(.city, season: .winter, weather: .snow) == "world/ground/ground_snow.png")
    #expect(HouseBuilder.ground(.desert, season: .winter, weather: .snow) == "world/ground/ground_desert.png")
    #expect(HouseBuilder.ground(.mountain, season: .winter, weather: .sun) == "world/ground/ground_snow.png")
    #expect(HouseBuilder.ground(.countryside, season: .autumn, weather: .rain) == "world/ground/ground_autumn.png")
    #expect(world.art.has("world/ground/ground_autumn.png") && world.art.has("world/ground/ground_snow.png"))
}

/// A house is the rooms it has (Josh, 23 Oct: "the boat cannot be a big 3 room space, just 2 long rooms"): the
/// houseboat, bought with the bedroom, is the lounge and the bedroom end to end, nothing upstairs and no closed rooms
/// of the next house.
@MainActor
@Test func aHouseIsOnlyItsOwnRooms() throws {
    let world = try World()
    var log = SaveLog()
    let clock = DayClock(wakeMinutes: 360, bedtimeMinutes: 1380, timeZoneID: "Europe/London")
    let day = GameDay(year: 2026, month: 11, day: 2)
    func at(_ minute: Int) -> Date {
        clock.date(on: day, atLocalMinutes: 480 + minute)
    }
    log.append(GameEvent(at: at(0), day: day, kind: .householdCreated(seed: 1, clock: clock)))
    log.append(GameEvent(at: at(1), day: day, kind: .purchaseBeansGranted(transactionID: "t1", beans: 5000)))
    log.append(GameEvent(at: at(2), day: day, kind: .houseBought(rung: 2, beans: HouseLadder.rung(2).price)))
    let state = log.derive(context: .empty)
    #expect(state.rung == 2 && state.roomSize == RoomSize(u: 10, v: 6))
    let place = HouseLadder.rung(2).place
    let now = HomeNow(place: place, biome: place.biome, season: .summer, sky: .day, weather: .sun, localMinutes: 720)
    let house = try #require(HouseBuilder.house(
        style: .houseboat, plans: world.plans, layout: world.layout, state: state,
        catalogue: world.content.catalogue, now: now, outdoors: world.content.outdoors
    ))
    #expect(Set(house.rooms.map(\.id)) == [.living, .bedroom])
    #expect(house.rooms.allSatisfy { $0.lockLabel == nil && $0.storey == 0 && $0.v == 0 }, "one long boat")
    #expect(house.rooms.map(\.u).sorted() == [0, 10] && house.stairs == nil)
    #expect(house.roomSize == RoomSize(u: 10, v: 6))
}

/// The homes get bigger up the ladder (Josh, 23 Oct: "the final house cant be the same room size as the second"): each
/// house's rooms are at least as big as the one before, London's the biggest, and the plans tile by their size.
@MainActor
@Test func theHomesGetBiggerUpTheLadder() throws {
    let world = try World()
    let areas = HouseLadder.rungs.map { (Tuning.Room.sizes[$0.style] ?? .standard).u * (Tuning.Room.sizes[$0.style] ?? .standard).v }
    #expect(zip(areas.dropFirst(2), areas.dropFirst(3)).allSatisfy { $0 < $1 }, "\(areas)")
    #expect(areas.last == areas.max() && areas[0] < areas[2])
    for rung in HouseLadder.rungs {
        let size = try #require(Tuning.Room.sizes[rung.style])
        let plan = try #require(world.plans.houses[rung.style.rawValue])
        for room in plan.rooms {
            let u = room.at[0].truncatingRemainder(dividingBy: Double(size.u)), v = room.at[1].truncatingRemainder(dividingBy: Double(size.v))
            #expect(u == 0 && v == 0, "\(rung.style) \(room.room)")
        }
        if let stairs = plan.stairs {
            let along = stairs.facing == "L" ? stairs.at[1] : stairs.at[0]
            #expect(along + Tuning.House.stairsLength <= Double(stairs.facing == "L" ? size.v : size.u), "\(rung.style)'s stairs")
        }
    }
}

/// The outside moves (Josh, 19 Oct): in a country autumn the oaks bend in the wind and drop their leaves, the field
/// stones stand still, the garden's pieces are about the house, and on a fine day cloud shadows cross the ground.
@MainActor
@Test func theOutsideMovesWithTheWindAndTheSeason() throws {
    let world = try World()
    let place = HomePlace(name: "the Cotswolds", latitude: 51.8, longitude: -1.8, timeZoneID: "Europe/London", biome: .countryside)
    let now = HomeNow(place: place, biome: .countryside, season: .autumn, sky: .day, weather: .sun, localMinutes: 720)
    let house = try #require(HouseBuilder.house(
        style: .londonTerrace, plans: world.plans, layout: world.layout, state: world.state(),
        catalogue: world.content.catalogue, now: now, outdoors: world.content.outdoors
    ))
    #expect(house.scenery.contains { $0.prop == "hawthorn" && !$0.behind }, "a hedge round the front of a country house")
    #expect(!house.scenery.contains { $0.sprite.hasPrefix("furniture/garden/") && !$0.behind }, "the shop's garden pieces are the player's")
    let scene = RoomScene(size: CGSize(width: 1366, height: 1024), art: world.art, content: world.content, house: house)
    let pieces = scene.world.children.compactMap { $0 as? SKSpriteNode }.filter { $0.name == "scenery" }
    #expect(pieces.count == house.scenery.count)
    for (node, piece) in zip(pieces, house.scenery) {
        #expect((node.shader != nil) == (piece.sway > 0), "\(piece.prop) sways only if it bends")
        #expect((node.childNode(withName: "falling") != nil) == (piece.sprite.hasSuffix("_autumn.png")), "\(piece.prop)")
    }
    #expect(house.scenery.contains { $0.prop == "oak" && $0.sway > 0 && $0.sheds == "leaf" })
    #expect(house.scenery.filter { $0.prop == "stone" }.allSatisfy { $0.sway == 0 && $0.sheds == nil })
    #expect(scene.world.childNode(withName: "cloudShadows") != nil, "cloud shadows on a fine day")
    #expect(RoomScene.wind(.storm) > RoomScene.wind(.rain) && RoomScene.wind(.rain) > RoomScene.wind(.sun))
}

/// A city home has a street behind it (Josh, 19 Oct: a city should look like a city): a road the scenery keeps off,
/// terraces and a cafe across it, cars parked at its far kerb, a bus shelter, post box or phone box on the near
/// pavement, and the road drawn under it all; the country has none.
@MainActor
@Test func aCityHomeHasItsStreet() throws {
    let world = try World()
    let place = HomePlace(name: "Elephant and Castle", latitude: 51.4946, longitude: -0.1003, timeZoneID: "Europe/London", biome: .city)
    let now = HomeNow(place: place, biome: .city, season: .summer, sky: .day, weather: .sun, localMinutes: 720)
    let house = try #require(HouseBuilder.house(
        style: .londonTerrace, plans: world.plans, layout: world.layout, state: world.state(),
        catalogue: world.content.catalogue, now: now, outdoors: world.content.outdoors
    ))
    let street = try #require(house.street)
    let places = Dictionary(uniqueKeysWithValues: world.content.outdoors.props(.city).map { ($0.id, $0.place) })
    let row = house.scenery.filter { places[$0.prop] == "row" }
    let kerb = house.scenery.filter { places[$0.prop] == "kerb" }
    #expect(row.count >= 3 && row.allSatisfy { $0.v < street.v - street.width / 2 }, "buildings across the road")
    #expect(!kerb.isEmpty && kerb.allSatisfy { abs($0.v - street.kerb) < 0.01 }, "cars at the kerb")
    #expect(house.scenery.contains { places[$0.prop] == "pavement" })
    for piece in house.scenery where places[piece.prop] == nil {
        #expect(abs(piece.v - street.v) > street.width / 2, "\(piece.prop) keeps off the road")
    }
    // The props' pictures are not bundled since every ladder town has its backdrop (26 Oct); this place has none, so
    // the plan is laid out but not painted.
    let scene = RoomScene(size: CGSize(width: 1366, height: 1024), art: world.art, content: world.content, house: house)
    #expect(scene.world.childNode(withName: "street") != nil)
    let country = HomeNow(place: place, biome: .countryside, season: .summer, sky: .day, weather: .sun, localMinutes: 720)
    let farm = try #require(HouseBuilder.house(
        style: .londonTerrace, plans: world.plans, layout: world.layout, state: world.state(),
        catalogue: world.content.catalogue, now: country, outdoors: world.content.outdoors
    ))
    #expect(farm.street == nil)
}

/// Every ladder town has its painted neighbourhood (Josh, 23 Oct: "perfectly natural and generated per house"), bundled,
/// with its plot under the house's ground floor, and none of the assembled scenery, street or roads.
@MainActor
@Test func everyLadderTownHasItsPaintedNeighbourhood() throws {
    let world = try World()
    for rung in HouseLadder.rungs {
        let now = HomeNow(place: rung.place, biome: rung.place.biome, season: .summer, sky: .day, weather: .sun, localMinutes: 720)
        let house = try #require(HouseBuilder.house(
            style: rung.style, plans: world.plans, layout: world.layout, state: world.state(),
            catalogue: world.content.catalogue, now: now, outdoors: world.content.outdoors
        ))
        let backdrop = try #require(house.backdrop, "\(rung.place.name)")
        #expect(world.art.has(backdrop.image), "\(backdrop.image) is bundled")
        #expect(house.scenery.isEmpty && house.street == nil && house.roads.isEmpty)
        let scene = RoomScene(size: CGSize(width: 1366, height: 1024), art: world.art, content: world.content, house: house)
        let node = try #require(scene.world.childNode(withName: "backdrop") as? SKSpriteNode)
        let rooms = scene.world.children.filter { $0 is RoomNode }.map { $0.calculateAccumulatedFrame() }
        let box = rooms.dropFirst().reduce(rooms.first ?? .zero) { $0.union($1) }
        #expect(node.frame.contains(CGPoint(x: box.midX, y: box.midY)), "the house stands on its plot in \(rung.place.name)")
    }
}
