import HouseCatCore

/// Names for places and weather on screen (they lived with the world map, which is gone: Josh, 22 Oct).
enum PlaceLabels {
    /// "cabin" from "A cabin".
    static func homeWord(_ home: String) -> String {
        home.replacingOccurrences(of: "^(A|An) ", with: "", options: .regularExpression)
    }

    /// "Lyon" from "Lyon, France", and "Haqil" from an older save's "49944, Haqil, Saudi Arabia".
    static func town(_ name: String) -> String {
        let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first { $0.contains(where: \.isLetter) } ?? parts.first ?? name
    }

    /// The weather's name at the home's sky now: clear weather is only "Sunny" by day (Josh, 20 Oct: Bali at 2:57 said
    /// "Sunny").
    static func weatherName(_ weather: Weather, sky: SkyPhase = .day) -> String {
        switch weather {
        case .sun: sky == .day ? "Sunny" : "Clear"
        case .cloud: "Cloudy"
        case .rain: "Raining"
        case .storm: "Stormy"
        case .snow: "Snowing"
        case .fog: "Foggy"
        case .wind: "Windy"
        case .heat: "Hot"
        }
    }

    static func weatherIcon(_ weather: Weather, sky: SkyPhase = .day) -> String {
        switch weather {
        case .sun:
            switch sky {
            case .dawn: "sunrise"
            case .day: "sun.max"
            case .dusk: "sunset"
            case .night: "moon.stars"
            }
        case .cloud: "cloud"
        case .rain: "cloud.rain"
        case .storm: "cloud.bolt.rain"
        case .snow: "snowflake"
        case .fog: "cloud.fog"
        case .wind: "wind"
        case .heat: "thermometer.sun"
        }
    }
}

extension CatScreens {
    /// The home in a line for the profile: "Puddlebury · London terrace".
    static func homeLine() -> String {
        let session = GameSession.shared
        let state = session.state(at: session.now())
        return "\(PlaceLabels.town(state.homePlace.name)) · \(GameWorld.style(state).name)"
    }
}
