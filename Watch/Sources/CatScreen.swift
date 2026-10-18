import HouseCatCore
import SwiftUI
import UIKit
import WatchKit

/// The Watch app's one screen: the cat in the pose the widget would show now, how it is, the streak, and Feed
/// and Stroke. What the cat says back comes from its own line pack, as in the app.
struct CatScreen: View {
    @State private var link = PhoneLink.shared
    @State private var said: String?
    /// Strokes in a row (close together), for the cat that has had enough.
    @State private var strokes = 0
    @State private var lastStroke = Date.distantPast

    var body: some View {
        let revision = link.revision
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                if let world = WidgetWorld.load(), let cat = world.state.cats.first {
                    page(world: world, cat: cat, state: WidgetRules.state(at: timeline.date, save: world.state, context: world.context))
                } else {
                    waiting
                }
            }
            .id(revision)
            .containerBackground(LinearGradient(colors: [WatchWords.ink, WatchWords.dusk], startPoint: .top, endPoint: .bottom), for: .navigation)
        }
        #if DEBUG
        // HOUSECAT_WATCH_TAPS=feed,pet: those buttons, pressed a few seconds after launch (simulator checks).
        .task {
            let taps = ProcessInfo.processInfo.environment["HOUSECAT_WATCH_TAPS"]?.split(separator: ",") ?? []
            for tap in taps {
                try? await Task.sleep(for: .seconds(4))
                if let action = WidgetAction(rawValue: String(tap)), let world = WidgetWorld.load(), let cat = world.state.cats.first {
                    act(action, world: world, cat: cat)
                }
            }
        }
        #endif
    }

    private func page(world: WidgetWorld, cat: CatState, state: WidgetState) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                picture(WidgetFiles.catFile(state.pose.catPose), fallback: "cat.fill")
                    .frame(height: 86)
                    .accessibilityLabel(cat.name)
                Text(cat.name)
                    .font(.headline)
                    .foregroundStyle(WatchWords.cream)
                Text(said ?? WatchWords.mood(state, name: cat.name))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WatchWords.cream.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: said)
                HStack(spacing: 4) {
                    picture("icon_streak_paw_print_with_a_small_flame.png", fallback: "flame.fill")
                        .frame(width: 18, height: 18)
                    Text(WatchWords.days(state.streak))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WatchWords.cream)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Streak, \(WatchWords.days(state.streak))")
                HStack(spacing: 8) {
                    careButton(state.fedToday ? "Fed" : "Feed", icon: "icon_feed_bowl.png", fallback: "fork.knife") {
                        act(.feed, world: world, cat: cat)
                    }
                    .disabled(state.fedToday)
                    careButton("Stroke", icon: "icon_petting_hand.png", fallback: "hand.raised.fill") {
                        act(.pet, world: world, cat: cat)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundStyle(WatchWords.accent)
                .accessibilityHidden(true)
            Text("Open HouseCat on your iPhone to meet your cat.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchWords.cream)
        }
        .padding()
    }

    private func careButton(_ title: String, icon: String, fallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                picture(icon, fallback: fallback)
                    .frame(width: 30, height: 30)
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(WatchWords.accent)
    }

    /// A picture the iPhone sent, or a symbol until it has.
    @ViewBuilder
    private func picture(_ name: String, fallback: String) -> some View {
        if let url = WidgetFiles.kitFile(name), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallback)
                .resizable()
                .scaledToFit()
                .foregroundStyle(WatchWords.accent)
                .padding(6)
        }
    }

    /// Feed or Stroke: the event into this Watch's inbox and to the iPhone, a tap on the wrist, the cat's reply.
    private func act(_ action: WidgetAction, world: WidgetWorld, cat: CatState) {
        let date = Date()
        let before = world.state.resolved(through: world.state.clock.day(of: date), context: world.context)
        let context: String
        switch action {
        case .feed:
            context = CareLines.feed(before: before, catID: cat.id)
        case .pet:
            strokes = date.timeIntervalSince(lastStroke) < Tuning.Care.petRowSeconds ? strokes + 1 : 1
            lastStroke = date
            context = CareLines.pet(before: before, catID: cat.id, taps: strokes)
        }
        guard let event = try? world.perform(action, at: date, source: .watch) else { return }
        PhoneLink.shared.send(event)
        PhoneLink.shared.refresh()
        WKInterfaceDevice.current().play(action == .feed ? .success : .click)
        // Only the first stroke of the day and the last straw get a line; the rest are purrs.
        guard context != "pet.repeat", let lines = world.content?.lines,
              let current = before.cat(cat.id)
        else { return }
        var rng = DaySeed(household: before.seed, day: before.clock.day(of: date), purpose: "line", salt: "\(context)\(event.id)")
        said = Greeting.line(context, cat: current, lines: lines, rng: &rng)
        Task {
            try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds * 2))
            said = nil
        }
    }
}
