import HouseCatCore
import SwiftUI
import WidgetKit

/// One moment of the complication: the streak and how the cat is.
struct StreakEntry: TimelineEntry {
    var date: Date
    /// Nil before the iPhone has sent a cat.
    var name: String?
    var state: WidgetState?
}

/// The complication in each family (shared with the Watch app, whose debug screen draws every one).
struct StreakView: View {
    let entry: StreakEntry
    let family: WidgetFamily

    private var streak: Int {
        entry.state?.streak ?? 0
    }

    private var symbol: String {
        entry.state.map { WatchWords.symbol($0.mood) } ?? "pawprint.fill"
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("\(streak)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityLabel(label)
    }

    private var corner: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                Text(WatchWords.days(streak))
            }
            .accessibilityLabel(label)
    }

    private var inline: some View {
        Label(entry.name.map { "\($0) · \(WatchWords.days(streak))" } ?? "HouseCat", systemImage: symbol)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .widgetAccentable()
                Text(entry.name ?? "HouseCat")
                    .font(.headline)
                    .widgetAccentable()
            }
            if let state = entry.state {
                Text(WatchWords.short(state))
                    .font(.caption)
                Text("\(WatchWords.days(state.streak)) in a row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open HouseCat on your iPhone")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        guard let state = entry.state, let name = entry.name else { return "HouseCat" }
        return "\(name): \(WatchWords.short(state)). Streak, \(WatchWords.days(state.streak))."
    }
}
