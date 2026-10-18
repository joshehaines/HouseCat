import Foundation
import HouseCatCore

/// Anonymous usage counts (SPEC "Tech stack": PostHog, no identifiers; App Review 5.1.1: honest privacy labels;
/// UK AADC: high privacy by default). Off unless both a PostHog key is set (Info.plist `PostHogAPIKey`, empty
/// until the project exists) and the player has switched it on in the cat's settings. Each launch uses a fresh
/// random id, people's profiles are never made, and only the funnel is counted: no names, no places, no text.
@MainActor
enum Analytics {
    enum Event: String {
        case introStarted = "intro_started"
        case introFinished = "intro_finished"
        case introSkipped = "intro_skipped"
        case catMade = "cat_made"
        case homePlaced = "home_placed"
        case homeChosen = "home_chosen"
        case tourFinished = "tour_finished"
        case tourSkipped = "tour_skipped"
        case firstFeed = "first_feed"
        case gamePlayed = "game_played"
        case napFinished = "nap_finished"
        case shopOpened = "shop_opened"
        case purchased
        case widgetAdded = "widget_added"
    }

    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard
    /// Fresh each launch: nothing ties one session to the next.
    private static let session = UUID().uuidString

    static var key: String? {
        (Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The player's choice (off by default).
    static var on: Bool {
        get { defaults.bool(forKey: "analytics.on") }
        set { defaults.set(newValue, forKey: "analytics.on") }
    }

    static var isAvailable: Bool {
        key != nil
    }

    /// Counts one thing. `detail` is a fixed word (a game's id, a product id), never anything typed.
    static func track(_ event: Event, detail: String? = nil) {
        guard on, let key, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        var properties: [String: Any] = ["$process_person_profile": false, "app_version": Bundle.main.version]
        if let detail {
            properties["detail"] = detail
        }
        let body: [String: Any] = ["api_key": key, "event": event.rawValue, "distinct_id": session, "properties": properties]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: Tuning.Analytics.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }
}

private extension Bundle {
    var version: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
