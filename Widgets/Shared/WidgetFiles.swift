import Foundation
import HouseCatCore

/// What the app leaves in the App Group for the widget, and what the widget leaves for the app (CLAUDE.md
/// "The widget scene"). Compiled into both. The app writes the save's state, the weather report and a kit of
/// pictures made for the player's cat and home; the widget's Feed and Pet drop events in the inbox, which
/// the app folds into the save the next time it opens. Neither ever touches the network to draw.
enum WidgetFiles {
    static let appGroup = "group.com.housecatgame.housecat"

    static var group: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var root: URL? {
        group?.appendingPathComponent("Widget", isDirectory: true)
    }

    static var snapshot: URL? {
        root?.appendingPathComponent("snapshot.json")
    }

    static var weather: URL? {
        root?.appendingPathComponent("weather.json")
    }

    static var inbox: URL? {
        root?.appendingPathComponent("Inbox", isDirectory: true)
    }

    static var kit: URL? {
        root?.appendingPathComponent("Kit", isDirectory: true)
    }

    static func kitFile(_ name: String) -> URL? {
        kit?.appendingPathComponent(name)
    }

    static func catFile(_ pose: CatPose) -> String {
        "cat_\(pose.rawValue).png"
    }

    /// The app's own bundle, from the app or from its widget extension inside it (its Content is read from
    /// there, so the widget follows the same rules and lines as the app).
    static var appBundle: URL {
        let main = Bundle.main.bundleURL
        return main.pathExtension == "appex" ? main.deletingLastPathComponent().deletingLastPathComponent() : main
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write(_ value: some Encodable, to url: URL?) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

/// The save as the app last left it, for the widget.
struct WidgetSnapshot: Codable {
    /// Derived through the last event (the widget closes the days since).
    var state: HouseholdState
    var writtenAt: Date
}

/// Where the kit's pictures sit and how big they are, measured by the app when it made them.
struct WidgetKitInfo: Codable, Equatable {
    /// A rectangle as fractions of a picture (origin top left).
    struct Box: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// What the kit was made for; the app makes it again when this changes.
    var key: String
    /// The window's glass in the square and the wide frame.
    var glass: Box
    var glassWide: Box
    /// Each pose's picture size in pixels, all drawn at the same scale, so a loaf is lower than a sit.
    var poses: [String: [Double]]
}

/// Events from the widget's buttons, waiting for the app.
enum WidgetInbox {
    static func pending() -> [GameEvent] {
        guard let inbox = WidgetFiles.inbox,
              let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { WidgetFiles.read(GameEvent.self, from: $0) }
            .sorted { $0.at < $1.at }
    }

    static func add(_ event: GameEvent) throws {
        try WidgetFiles.write(event, to: WidgetFiles.inbox?.appendingPathComponent("\(event.id.uuidString).json"))
    }

    /// The app has these in the save now.
    static func remove(_ events: [GameEvent]) {
        for event in events {
            if let url = WidgetFiles.inbox?.appendingPathComponent("\(event.id.uuidString).json") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// Everything a widget entry needs, read from the App Group and the app's Content.
struct WidgetWorld {
    var state: HouseholdState
    var context: RulesContext
    var content: ContentBundle?
    var report: WeatherReport?
    var kit: WidgetKitInfo?

    /// Nil before the app has ever run (no snapshot yet).
    static func load() -> WidgetWorld? {
        guard let snapshot = WidgetFiles.read(WidgetSnapshot.self, from: WidgetFiles.snapshot) else { return nil }
        let content = try? ContentBundle.load(from: WidgetFiles.appBundle.appendingPathComponent("Content"))
        let context = (try? content?.rulesContext()) ?? RulesContext()
        // The widget's own taps since the app last wrote the save.
        var state = snapshot.state
        for event in WidgetInbox.pending() where event.at > (state.lastEventAt ?? .distantPast) {
            state.apply(event, context: context)
        }
        return WidgetWorld(
            state: state,
            context: context,
            content: content,
            report: WidgetFiles.read(WeatherReport.self, from: WidgetFiles.weather),
            kit: WidgetFiles.read(WidgetKitInfo.self, from: WidgetFiles.kitFile("kit.json"))
        )
    }

    var weatherTables: WeatherFile {
        content?.weather ?? WeatherFile(tables: [:])
    }

    var catName: String {
        state.cats.first?.name ?? "Your cat"
    }

    func scenes(from date: Date) -> [WidgetScene] {
        WidgetRules.scenes(from: date, save: state, context: context, weather: weatherTables, report: report)
    }

    /// The cat's line for a scene's caption, the same all half hour.
    func caption(_ scene: WidgetScene) -> String? {
        guard let context = scene.state.lineContext, let cat = state.cats.first, let lines = content?.lines else { return nil }
        var rng = DaySeed(household: state.seed, day: state.clock.day(of: scene.state.date), purpose: "widget", salt: context)
        return Greeting.line(context, cat: cat, lines: lines, rng: &rng)
    }

    /// A widget button: the event it appends (in the inbox, for the app), or nil when there is nothing to do.
    func perform(_ action: WidgetAction, at date: Date = Date(), source: GameEvent.Source = .widget) throws -> GameEvent? {
        guard let kind = WidgetRules.event(for: action, at: date, save: state, context: context) else { return nil }
        // Never before the newest event, as in the app (the trusted-time rule).
        let at = max(date, (state.lastEventAt ?? .distantPast).addingTimeInterval(0.001))
        let event = GameEvent(at: at, day: state.clock.day(of: at), source: source, kind: kind)
        try WidgetInbox.add(event)
        return event
    }
}
