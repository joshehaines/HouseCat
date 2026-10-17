import SwiftUI
import WidgetKit

/// Placeholder widget: the streak and the visited-today pose arrive with the
/// widget state in HouseCatCore. Widgets read state; they never compute it.
struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in _: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 0)
    }

    func getSnapshot(in _: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, streak: 0))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        completion(Timeline(entries: [StreakEntry(date: .now, streak: 0)], policy: .never))
    }
}

struct StreakWidgetView: View {
    let entry: StreakEntry

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .accessibilityHidden(true)
            Text("\(entry.streak)")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
            Text("HouseCat")
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visit streak, \(entry.streak) days")
        .containerBackground(for: .widget) {
            Color(red: 0.98, green: 0.95, blue: 0.91)
        }
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your visit streak and your cat.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct HouseCatWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
    }
}
