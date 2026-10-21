import CoreLocation
import Foundation
import HouseCatCore
import WeatherKit

/// The real weather at the home (SPEC "World map, search and seasons": WeatherKit by the pin's coordinate, no
/// device location; it drives the scene on Auto, a fixed season keeps the simulation). Asked for at most every
/// half hour while the app is open and kept in the App Group, where the widget reads the same hours.
/// Without the WeatherKit capability (it needs the developer team) every request fails and the simulated
/// weather stays, so nothing breaks before then.
@MainActor
enum RealWeather {
    private(set) static var report: WeatherReport? = WidgetFiles.read(WeatherReport.self, from: WidgetFiles.weather)
    /// Apple's mark and legal page (WeatherKit's attribution rule): `WeatherMark` shows them wherever the weather is
    /// Apple's, and the settings and licences always.
    private(set) static var attribution: (mark: URL, legal: URL)?
    private static var asking = false

    static func refreshIfNeeded(state: HouseholdState) {
        guard state.home.season == .auto, !asking else { return }
        let place = state.home.place ?? .london
        #if DEBUG
            // HOUSECAT_WEATHER_REPORT=1 stands in for Apple: a report of HOUSECAT_WEATHER's weather (rain if unset)
            // for the home, written where the widget reads it too, so the Apple Weather mark can be seen in a
            // simulator without the WeatherKit capability.
            if ProcessInfo.processInfo.environment["HOUSECAT_WEATHER_REPORT"] == "1" {
                if report?.isFor(place) != true {
                    let weather = ProcessInfo.processInfo.environment["HOUSECAT_WEATHER"].flatMap(Weather.init(rawValue:)) ?? .rain
                    let start = Date().addingTimeInterval(-1800)
                    let hours = (0 ..< Tuning.Weather.reportHours).map {
                        WeatherReport.Hour(start: start.addingTimeInterval(Double($0) * 3600), weather: weather, temperatureC: 9)
                    }
                    let fake = WeatherReport(latitude: place.latitude, longitude: place.longitude, fetchedAt: Date(), hours: hours)
                    report = fake
                    try? WidgetFiles.write(fake, to: WidgetFiles.weather)
                    WidgetBridge.changed()
                }
                return
            }
        #endif
        if let report, report.isFor(place), !report.needsRefresh(at: Date()) {
            return
        }
        asking = true
        Task {
            defer { asking = false }
            do {
                let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let forecast = try await WeatherService.shared.weather(for: location, including: .hourly)
                let hours = forecast.prefix(Tuning.Weather.reportHours).compactMap { hour -> WeatherReport.Hour? in
                    guard let weather = WeatherRules.weather(condition: hour.condition.rawValue) else { return nil }
                    return .init(start: hour.date, weather: weather, temperatureC: hour.temperature.converted(to: .celsius).value)
                }
                guard !hours.isEmpty else { return }
                let report = WeatherReport(latitude: place.latitude, longitude: place.longitude, fetchedAt: Date(), hours: hours)
                self.report = report
                try? WidgetFiles.write(report, to: WidgetFiles.weather)
                WidgetBridge.changed()
            } catch {
                // No WeatherKit capability yet, offline, or refused: the simulation stays in charge.
            }
        }
    }

    static func loadAttribution() async {
        guard attribution == nil, let found = try? await WeatherService.shared.attribution else { return }
        attribution = (found.combinedMarkLightURL, found.legalPageURL)
    }
}
