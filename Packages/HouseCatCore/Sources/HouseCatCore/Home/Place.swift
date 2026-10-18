import Foundation

/// Where the home is (SPEC "World map, search and seasons"): the pin's place name, its coordinates, its time
/// zone (the sky's local time) and the biome it generalises to. No device location is ever read: the player
/// searches or taps the map.
public struct HomePlace: Codable, Hashable, Sendable {
    /// As the map labels it ("Elephant and Castle, London").
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneID: String
    public var biome: Biome

    public init(name: String, latitude: Double, longitude: Double, timeZoneID: String, biome: Biome) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
        self.biome = biome
    }

    /// The seasons are the other way round south of the equator.
    public var southernHemisphere: Bool {
        latitude < 0
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: Self.roughOffset(longitude: longitude)) ?? .gmt
    }

    /// A time zone from the longitude alone, for a pin no geocoder could name (15° an hour).
    public static func roughOffset(longitude: Double) -> Int {
        Int((longitude / 15).rounded()) * 3600
    }

    /// Where a new home is until the player pins one: London, as the demo home has always been.
    public static let london = HomePlace(name: "London", latitude: 51.4946, longitude: -0.1003, timeZoneID: "Europe/London", biome: .city)
}

/// The painted world map's projection (assets/world/map, equirectangular): longitude −180…180 left to right,
/// latitude 90…−90 top to bottom.
public enum WorldMap {
    /// The pixel (fractional) for a coordinate on a map of this size.
    public static func point(latitude: Double, longitude: Double, width: Double, height: Double) -> (x: Double, y: Double) {
        ((longitude + 180) / 360 * width, (90 - latitude) / 180 * height)
    }

    /// The coordinate under a point of the map.
    public static func coordinate(x: Double, y: Double, width: Double, height: Double) -> (latitude: Double, longitude: Double) {
        let latitude = 90 - y / height * 180
        var longitude = x / width * 360 - 180
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return (min(90, max(-90, latitude)), longitude)
    }

    /// Great-circle distance in kilometres.
    public static func distance(_ a: (latitude: Double, longitude: Double), _ b: (latitude: Double, longitude: Double)) -> Double {
        let r = 6371.0, rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// The cities the map names when zoomed in, and where a pin counts as city (assets/world/map/cities.json).
public struct CitiesFile: Codable, Sendable {
    public struct City: Codable, Hashable, Sendable {
        public var name: String
        public var country: String
        public var latitude: Double
        public var longitude: Double
        /// A big city spreads further (Tuning.World.bigCityRadiusKm).
        public var big: Bool
    }

    public var cities: [City]

    /// The nearest city whose reach covers a coordinate.
    public func city(near latitude: Double, _ longitude: Double) -> City? {
        cities
            .map { ($0, WorldMap.distance((latitude, longitude), ($0.latitude, $0.longitude))) }
            .filter { $0.1 <= ($0.0.big ? Tuning.World.bigCityRadiusKm : Tuning.World.cityRadiusKm) }
            .min { $0.1 < $1.1 }?.0
    }
}

/// The biome under a pin: the painted mask's index (map_biome_legend.json: 0 sea, 1 coast, 2 countryside,
/// 3 mountain, 4 forest, 5 desert, 6 tropical, 7 snow) unless the pin is in a city's reach. A pin on the sea
/// (a harbour, a houseboat mooring) is coast.
public enum BiomeRules {
    public static let maskOrder: [Biome?] = [nil, .coast, .countryside, .mountain, .forest, .desert, .tropical, .snow, .city]

    public static func biome(maskIndex: Int, inCity: Bool) -> Biome {
        if inCity {
            return .city
        }
        guard maskIndex >= 0, maskIndex < maskOrder.count, let biome = maskOrder[maskIndex] else { return .coast }
        return biome
    }
}

/// The weather when it is simulated (SPEC: a fixed season uses the biome's seasonal table instead of
/// WeatherKit; until WeatherKit is wired, Auto uses the table for the real season too). One weather a day,
/// the same on every device (`DaySeed`). Content/weather.json holds the tables for Josh to tune.
public struct WeatherFile: Codable, Sendable {
    /// biome → season → weather → weight.
    public var tables: [String: [String: [String: Int]]]

    public init(tables: [String: [String: [String: Int]]]) {
        self.tables = tables
    }

    public func weights(biome: Biome, season: NatureSeason) -> [(Weather, Int)] {
        let row = tables[biome.rawValue]?[season.rawValue] ?? [:]
        return Weather.allCases.compactMap { weather in row[weather.rawValue].map { (weather, $0) } }.filter { $0.1 > 0 }
    }
}

public enum WeatherRules {
    public static func simulated(
        biome: Biome,
        season: NatureSeason,
        day: GameDay,
        household seed: UInt64,
        tables: WeatherFile
    ) -> Weather {
        let options = tables.weights(biome: biome, season: season)
        guard !options.isEmpty else { return .sun }
        var rng = DaySeed(household: seed, day: day, purpose: "weather", salt: "\(biome.rawValue).\(season.rawValue)")
        return options[rng.pick(weights: options.map(\.1)) ?? 0].0
    }
}

/// The home's place and season as the save has them.
public struct HomeSettings: Codable, Equatable, Sendable {
    /// Nil until the player pins one (the app shows `HomePlace.london`).
    public var place: HomePlace?
    public var season: SeasonSetting = .auto
    /// Which home it is; nil until chosen (the app shows the London terrace).
    public var style: HouseStyle?
    /// A paid or free move was recorded and the next pin may land.
    public var moving = false

    public init() {}
}

/// The home right now (SPEC "Sky, season, weather and windows: one layered scene"): its place, the season
/// there, the sky at its local time and today's weather. Everything outside and in every window follows this.
public struct HomeNow: Equatable, Sendable {
    public var place: HomePlace
    public var biome: Biome
    public var season: NatureSeason
    public var sky: SkyPhase
    public var weather: Weather
    /// Minutes past midnight at the home.
    public var localMinutes: Int

    public init(place: HomePlace, biome: Biome, season: NatureSeason, sky: SkyPhase, weather: Weather, localMinutes: Int) {
        self.place = place
        self.biome = biome
        self.season = season
        self.sky = sky
        self.weather = weather
        self.localMinutes = localMinutes
    }
}

public extension HouseholdState {
    func homeNow(at date: Date, weather tables: WeatherFile) -> HomeNow {
        let place = home.place ?? .london
        let zone = place.timeZone
        let season = home.season.season(at: date, timeZone: zone, southernHemisphere: place.southernHemisphere)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 0)
        let weather = WeatherRules.simulated(biome: place.biome, season: season, day: clock.day(of: date), household: seed, tables: tables)
        return HomeNow(
            place: place,
            biome: place.biome,
            season: season,
            sky: .at(localMinutes: minutes),
            weather: weather,
            localMinutes: minutes
        )
    }
}

public extension HouseholdState {
    /// What pinning a new home costs now: nothing for the first pin or the free move (or on a Cat Club day),
    /// then Tuning.Beans.moveHome.
    var moveCost: Int {
        guard home.place != nil else { return 0 }
        return homeMovesUsed < Tuning.Beans.freeHomeMoves || today?.clubDay == true ? 0 : Tuning.Beans.moveHome
    }
}
