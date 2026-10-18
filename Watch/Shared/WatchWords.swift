import HouseCatCore
import SwiftUI

/// How the Watch app and its complication put the widget's state into words, colours and symbols.
enum WatchWords {
    static let ink = Color(red: 0.24, green: 0.18, blue: 0.22)
    static let dusk = Color(red: 0.13, green: 0.09, blue: 0.12)
    static let cream = Color(red: 0.995, green: 0.97, blue: 0.925)
    static let accent = Color(red: 0.89, green: 0.5, blue: 0.2)

    static func days(_ n: Int) -> String {
        n == 1 ? "1 day" : "\(n) days"
    }

    /// The hours left in the game day, for "still waiting up".
    static func hoursLeft(_ state: WidgetState) -> String {
        let hours = max(1, Int((Double(state.minutesLeftToday) / 60).rounded(.up)))
        return hours == 1 ? "1 hour left" : "\(hours) hours left"
    }

    /// A sentence about the cat now.
    static func mood(_ state: WidgetState, name: String) -> String {
        switch state.mood {
        case .content: state.fedToday ? "\(name) is fed and content." : "\(name) is glad you came by."
        case .waiting: "\(name) is waiting for you."
        case .lastChance: "\(name) is still waiting up. \(hoursLeft(state))."
        case .sulking: "\(name) missed you yesterday."
        }
    }

    /// The same, short, for the complication.
    static func short(_ state: WidgetState) -> String {
        switch state.mood {
        case .content: state.fedToday ? "Fed and content" : "Glad you came by"
        case .waiting: "Waiting for you"
        case .lastChance: "Waiting up, \(hoursLeft(state))"
        case .sulking: "Missed you yesterday"
        }
    }

    static func symbol(_ mood: WidgetMood) -> String {
        switch mood {
        case .content: "cat.fill"
        case .waiting: "pawprint.fill"
        case .lastChance: "moon.stars.fill"
        case .sulking: "cloud.rain.fill"
        }
    }
}
