import HouseCatCore
import HouseCatUI
import SwiftUI
import WidgetKit

/// The widget's timeline (SPEC "Widgets, the Duolingo layer"): 48 entries half an hour apart, each computed
/// by HouseCatCore from the save the app left in the App Group (plus the widget's own taps), so the app and
/// the widget always agree. Feed and Pet reload it at once.
struct HouseCatProvider: TimelineProvider {
    func placeholder(in _: Context) -> WidgetEntry {
        WidgetEntry(date: .now, scene: nil, catName: "Your cat", caption: nil, kit: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(Self.entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entries = Self.entries(from: .now)
        completion(Timeline(entries: entries.isEmpty ? [placeholder(in: context)] : entries, policy: .atEnd))
    }

    static func entries(from date: Date) -> [WidgetEntry] {
        guard let world = WidgetWorld.load() else { return [] }
        return world.scenes(from: date).map {
            WidgetEntry(date: $0.state.date, scene: $0, catName: world.catName, caption: world.caption($0), kit: world.kit)
        }
    }
}

struct HouseCatWidgetEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HouseCatWidgetView(entry: entry, family: family)
            .containerBackground(for: .widget) {
                Theme.paper
            }
    }
}

/// Your cat in your window: every size from the small square to the Lock Screen, and StandBy at night.
struct HouseCatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HouseCatWidget", provider: HouseCatProvider()) { entry in
            HouseCatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Your cat")
        .description("Your cat in your window and your visit streak. Feed and pet it from here.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct HouseCatWidgetBundle: WidgetBundle {
    var body: some Widget {
        HouseCatWidget()
    }
}
