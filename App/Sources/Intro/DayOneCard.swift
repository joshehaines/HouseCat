import HouseCatCore
import HouseCatUI
import SwiftUI

/// The end of the first tour (Josh, 25 Oct, after the onboarding research: Finch's "Day 1… Start today", Duolingo's
/// daily goal): day one with the cat done, what tomorrow brings, and when the player will usually come by, which
/// sets the reminders and asks for them there and then, while it means something. Shown once.
struct DayOneCard: View {
    let catName: String
    let done: () -> Void

    enum Visits: String, CaseIterable, Identifiable {
        case mornings = "Mornings"
        case evenings = "Evenings"
        case both = "Both"

        var id: String {
            rawValue
        }

        /// The reminders this asks for (breakfast in the morning, the nudge in the evening, presents either way).
        func apply(to settings: ReminderSettings) -> ReminderSettings {
            var settings = settings
            settings.breakfast = self != .evenings
            settings.evening = self != .mornings
            return settings
        }
    }

    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var shown: Bool {
        get { defaults.bool(forKey: "dayOne.shown") }
        set { defaults.set(newValue, forKey: "dayOne.shown") }
    }

    @State private var visits = Visits.mornings
    @State private var askedBefore = Reminders.asked
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                Text("Tomorrow").font(.headline).foregroundStyle(Theme.inkSoft)
                row("feed_bowl", "Breakfast, and maybe a present from \(catName)")
                row("streak_paw_print_with_a_small_flame", "Day 2 of your streak, and new goals")
                if !askedBefore {
                    Text("When do you usually visit?").font(.headline).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                    HStack(spacing: 8) {
                        ForEach(Visits.allCases) { option in
                            Button {
                                feedback.tap()
                                visits = option
                            } label: {
                                Text(option.rawValue)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .paper(Capsule(), fill: visits == option ? Theme.accent.opacity(0.25) : Theme.cream)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(visits == option ? .isSelected : [])
                        }
                    }
                }
                HStack(spacing: 12) {
                    if askedBefore {
                        Spacer(minLength: 0)
                        ChunkyButton("See you tomorrow") { done() }
                    } else {
                        Button("Not now") {
                            feedback.tap()
                            done()
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12)
                        Spacer(minLength: 0)
                        ChunkyButton("Remind me") {
                            Reminders.settings = visits.apply(to: Reminders.settings)
                            Task {
                                await Reminders.ask()
                                done()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(maxWidth: 500)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.cream))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom), lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onAppear {
            Self.shown = true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            PaintedIcon("streak_paw_print_with_a_small_flame", size: 56)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Day 1 with \(catName)")
                    .font(Theme.title(26))
                    .foregroundStyle(.white)
                Text(PlayerName.current.map { "See you tomorrow, \($0)?" } ?? "See you tomorrow?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.accent, GameHUD.deepGold], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            PaintedIcon(icon, size: 26)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
