import HouseCatCore
import HouseCatUI
import SwiftUI
import WidgetKit

/// Whether the add-widget card has asked, a device preference (each phone has its own Home Screen).
@MainActor
enum WidgetPrompt {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var asked: Set<String> {
        get { Set(defaults.stringArray(forKey: "widget.prompt.asked") ?? []) }
        set { defaults.set(Array(newValue), forKey: "widget.prompt.asked") }
    }

    /// Whether a HouseCat widget is on this phone already.
    static func installed() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let found = (try? result.get())?.contains { $0.kind == "HouseCatWidget" } ?? false
                continuation.resume(returning: found)
            }
        }
    }

    /// The ask due now, marked as asked, or nil.
    static func take(_ state: HouseholdState) async -> WidgetPromptRules.Ask? {
        var due = WidgetPromptRules.due(state, asked: asked, installed: await installed())
        #if DEBUG
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "addwidget" {
                due = .firstFeed
            }
        #endif
        if let due {
            asked.insert(due.rawValue)
        }
        return due
    }
}

/// Putting the cat on the Home Screen (Josh, 18 Oct; Liven's add-widget prompt): the player's own cat in their
/// own window, drawn by the widget's views from what the app left for it, and the three steps to add it.
struct WidgetPromptCard: View {
    let catName: String
    let close: () -> Void
    @State private var entry: WidgetEntry?

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            preview
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep \(catName) on your Home Screen").font(Theme.title(23)).fixedSize(horizontal: false, vertical: true)
                Text("Your window, your weather, and \(catName) waiting by the door. Feed and stroke from there too.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 5) {
                    step(1, "Touch and hold an empty spot on your Home Screen.")
                    step(2, "Tap Edit, then Add Widget.")
                    step(3, "Find HouseCat and pick a size.")
                }
                HStack(spacing: 10) {
                    Spacer()
                    HUDButton("Not now", action: close)
                    HUDButton("Got it", icon: "trust_heart_with_a_paw_print", prominent: true, action: close)
                }
            }
            .frame(maxWidth: 330)
        }
        .padding(20)
        .frame(maxWidth: 640)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
        .task {
            // The widget's pictures are made for this cat and home in the background; wait for them a little.
            WidgetBridge.publish()
            for _ in 0 ..< 20 {
                if let world = WidgetWorld.load(), world.kit != nil, let scene = world.scenes(from: .now).first {
                    entry = WidgetEntry(date: scene.state.date, scene: scene, catName: world.catName, caption: world.caption(scene), kit: world.kit)
                    return
                }
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.56, blue: 0.7), Color(red: 0.62, green: 0.5, blue: 0.66)], startPoint: .top, endPoint: .bottom))
            if let entry {
                HouseCatWidgetView(entry: entry, family: .systemSmall)
                    .frame(width: 150, height: 150)
                    .background(Theme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(width: 196, height: 196)
        .animation(.spring(duration: 0.45), value: entry != nil)
        .accessibilityLabel("How the widget looks with \(catName)")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.subheadline.weight(.semibold))
        }
    }
}
