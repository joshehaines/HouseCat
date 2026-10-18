import Foundation

/// The eight biomes a pin on the world map generalises to (CLAUDE.md "Places").
public enum Biome: String, CaseIterable, Codable, Sendable {
    case city
    case coast
    case countryside
    case mountain
    case forest
    case desert
    case tropical
    case snow
}

/// The eight homes at launch (SPEC "Home and furniture").
public enum HouseStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case londonTerrace = "london_terrace"
    case mansionFlat = "mansion_flat"
    case cottage
    case georgianTownhouse = "georgian_townhouse"
    case newbuildBalcony = "newbuild_balcony"
    case houseboat
    case mediterraneanRooftop = "mediterranean_rooftop"
    case woodlandCabin = "woodland_cabin"

    public var id: String {
        rawValue
    }

    /// As the house step names it.
    public var name: String {
        switch self {
        case .londonTerrace: "London terrace"
        case .mansionFlat: "Mansion-block flat"
        case .cottage: "Cottage"
        case .georgianTownhouse: "Georgian townhouse"
        case .newbuildBalcony: "New-build flat"
        case .houseboat: "Houseboat"
        case .mediterraneanRooftop: "Rooftop flat"
        case .woodlandCabin: "Woodland cabin"
        }
    }

    public var blurb: String {
        switch self {
        case .londonTerrace: "Yellow brick, a bay window and a garden out the back."
        case .mansionFlat: "High ceilings and a lift that thinks about it first."
        case .cottage: "Low beams, a rose round the door, a garden for sunbathing."
        case .georgianTownhouse: "Tall windows, a fanlight, stairs for racing up at night."
        case .newbuildBalcony: "Clean lines and a balcony for watching the birds."
        case .houseboat: "A cabin on the water. The ducks visit."
        case .mediterraneanRooftop: "White walls, blue shutters and a terrace in the sun."
        case .woodlandCabin: "Logs, a stove and the whole forest outside."
        }
    }
}

/// The season the world is painted in (SPEC "World map, search and seasons"): the real
/// one for the home's hemisphere on Auto, or one the player fixed.
public enum NatureSeason: String, CaseIterable, Codable, Sendable {
    case spring
    case summer
    case autumn
    case winter

    /// The meteorological season for a month (1–12): March–May is spring in the north, autumn in the south.
    public static func of(month: Int, southernHemisphere: Bool) -> NatureSeason {
        let north: NatureSeason = switch month {
        case 3 ... 5: .spring
        case 6 ... 8: .summer
        case 9 ... 11: .autumn
        default: .winter
        }
        guard southernHemisphere else { return north }
        return switch north {
        case .spring: .autumn
        case .summer: .winter
        case .autumn: .spring
        case .winter: .summer
        }
    }
}

/// The season setting: Auto follows the calendar for the home's hemisphere.
public enum SeasonSetting: Codable, Hashable, Sendable {
    case auto
    case fixed(NatureSeason)

    public func season(at date: Date, timeZone: TimeZone, southernHemisphere: Bool) -> NatureSeason {
        switch self {
        case let .fixed(season):
            return season
        case .auto:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return .of(month: calendar.component(.month, from: date), southernHemisphere: southernHemisphere)
        }
    }
}

/// The sky over the home at its local time: the code-drawn sky, the grade on the
/// painted scene and whether the windows are lit (SPEC "the sky's local time").
public enum SkyPhase: String, CaseIterable, Codable, Sendable {
    case dawn
    case day
    case dusk
    case night

    public static func at(localMinutes minutes: Int) -> SkyPhase {
        switch minutes {
        case Tuning.Sky.dawnStartMinutes ..< Tuning.Sky.dayStartMinutes: .dawn
        case Tuning.Sky.dayStartMinutes ..< Tuning.Sky.duskStartMinutes: .day
        case Tuning.Sky.duskStartMinutes ..< Tuning.Sky.nightStartMinutes: .dusk
        default: .night
        }
    }

    /// The room's light map for this sky (rooms/lightmaps/lm_<name>_*.png); overcast weather wins by day.
    public func lightMap(weather: Weather) -> String {
        switch self {
        case .dawn: "morning"
        case .day: [.cloud, .rain, .storm, .fog, .snow].contains(weather) ? "overcast" : "midday"
        case .dusk: "evening"
        case .night: "night"
        }
    }
}

/// Arrival rules that decide what the app shows on open (SPEC "The session loop").
public enum ArrivalRules {
    /// The exterior cold open plays when the app was last in the foreground more than an hour ago (or never).
    public static func showsExterior(lastActive: Date?, now: Date) -> Bool {
        guard let lastActive else { return true }
        return now.timeIntervalSince(lastActive) > TimeInterval(Tuning.Arrival.exteriorAfterMinutesAway * 60)
    }
}
