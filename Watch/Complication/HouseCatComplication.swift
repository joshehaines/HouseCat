import HouseCatCore
import SwiftUI
import WidgetKit

/// The Watch complication (SPEC "Watch complication"): the streak and how the cat is, from what the iPhone
/// last sent and the Watch's own taps, moving through the day as the widget does (waiting, still waiting up,
/// glad you came).
@main
struct HouseCatComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HouseCatStreak", provider: StreakTimeline()) { entry in
            FamilyStreakView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Your cat")
        .description("Your streak, and whether your cat has seen you today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct StreakTimeline: TimelineProvider {
    func placeholder(in _: Context) -> StreakEntry {
        StreakEntry(date: Date(), name: "Your cat", state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(entries(from: Date()).first ?? placeholder(in: context))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entries = entries(from: Date())
        completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never))
    }

    /// Each change ahead in the widget's day (the same moments its pictures change).
    private func entries(from date: Date) -> [StreakEntry] {
        guard let world = WidgetWorld.load(), world.state.cats.first != nil else {
            return [StreakEntry(date: date, name: nil, state: nil)]
        }
        let scenes = world.scenes(from: date)
        guard !scenes.isEmpty else {
            return [StreakEntry(date: date, name: world.catName, state: WidgetRules.state(at: date, save: world.state, context: world.context))]
        }
        return scenes.map { StreakEntry(date: $0.state.date, name: world.catName, state: $0.state) }
    }
}

/// The complication at the face's size for it.
struct FamilyStreakView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        StreakView(entry: entry, family: family)
    }
}
