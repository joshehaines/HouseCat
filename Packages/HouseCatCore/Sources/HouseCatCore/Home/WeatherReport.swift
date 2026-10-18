import Foundation

/// The real weather at the home, hour by hour (SPEC "World map, search and seasons": WeatherKit by
/// coordinate drives the scene on Auto; a fixed season keeps the simulation). The app fetches it and keeps it
/// beside the save, and the widget reads the same report, so drawing never touches the network.
public struct WeatherReport: Codable, Equatable, Sendable {
    public struct Hour: Codable, Equatable, Sendable {
        public var start: Date
        public var weather: Weather
        public var temperatureC: Double

        public init(start: Date, weather: Weather, temperatureC: Double) {
            self.start = start
            self.weather = weather
            self.temperatureC = temperatureC
        }
    }

    public var latitude: Double
    public var longitude: Double
    public var fetchedAt: Date
    public var hours: [Hour]

    public init(latitude: Double, longitude: Double, fetchedAt: Date, hours: [Hour]) {
        self.latitude = latitude
        self.longitude = longitude
        self.fetchedAt = fetchedAt
        self.hours = hours.sorted { $0.start < $1.start }
    }

    /// The hour covering `date`, if the report reaches it.
    public func hour(at date: Date) -> Hour? {
        hours.last { $0.start <= date && date.timeIntervalSince($0.start) < 3600 }
    }

    /// Whether the report was taken at this place (a move makes it stale).
    public func isFor(_ place: HomePlace) -> Bool {
        WorldMap.distance((latitude, longitude), (place.latitude, place.longitude)) <= Tuning.Weather.reportRadiusKm
    }

    /// Whether it is worth asking again: older than the refresh interval, or running out within a day.
    public func needsRefresh(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > Tuning.Weather.reportRefreshMinutes * 60
            || (hours.last?.start ?? .distantPast) < date.addingTimeInterval(86400)
    }
}

public extension WeatherRules {
    /// The game's weather for a WeatherKit condition (its `WeatherCondition` raw value), or nil for one it
    /// does not know, which leaves the simulation in charge.
    static func weather(condition: String) -> Weather? {
        switch condition {
        case "clear", "mostlyClear", "frigid":
            .sun
        case "hot":
            .heat
        case "partlyCloudy", "mostlyCloudy", "cloudy":
            .cloud
        case "drizzle", "rain", "heavyRain", "sunShowers", "freezingDrizzle", "freezingRain":
            .rain
        case "thunderstorms", "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms", "tropicalStorm",
             "hurricane", "hail":
            .storm
        case "snow", "heavySnow", "flurries", "sunFlurries", "blizzard", "blowingSnow", "sleet", "wintryMix":
            .snow
        case "foggy", "haze", "smoky", "blowingDust":
            .fog
        case "windy", "breezy":
            .wind
        default:
            nil
        }
    }

    /// The weather at the home at `date`: the real report's hour when the season is Auto and the report is
    /// for this place, otherwise the day's simulated weather.
    static func weather(at date: Date, home: HomeSettings, report: WeatherReport?, simulated: Weather) -> Weather {
        guard home.season == .auto, let report, report.isFor(home.place ?? .london), let hour = report.hour(at: date)
        else { return simulated }
        return hour.weather
    }
}
