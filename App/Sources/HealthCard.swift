import HouseCatCore
import HouseCatUI
import SwiftUI

/// Day 3: may the cat notice your steps, sleep and workouts? (Josh, 18 Oct: value first, then the system's
/// question.) The three things it would read, each with what it pays and how the cat takes it, then plainly
/// what is read and where; never a penalty for a day without.
struct HealthCard: View {
    let catName: String
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon("trust_heart_with_a_paw_print", size: 34)
                Text("\(catName) notices how your day went").font(Theme.title(22))
            }
            HStack(spacing: 10) {
                tile("group_of_three_paw_prints", "\(Tuning.Health.stepsGoal.formatted()) steps", xp: Tuning.XP.stepsGoalMet, goal: .steps)
                tile("nap_moon", "\(Int(Tuning.Health.sleepGoalHours)) hours' sleep", xp: Tuning.XP.sleepGoalMet, goal: .sleep)
                tile("play_laser_dot", "A workout", xp: Tuning.XP.workoutLogged, goal: .workout)
            }
            // As tall as its tallest tile, the three the same (on an iPad's tall screen they stretched to fill it).
            .fixedSize(horizontal: false, vertical: true)
            Text(
                "Only these three, read from Health on this device. Nothing is written to Health or sent anywhere, and a day without is never held against you."
            )
            .font(.caption).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                HUDButton("Not now") {
                    HealthLayer.asked = true
                    done()
                }
                HUDButton("Connect Health", icon: "trust_heart_with_a_paw_print", prominent: true) {
                    Task {
                        await HealthLayer.ask()
                        done()
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }

    private func tile(_ icon: String, _ title: String, xp: Int, goal: GameEvent.HealthGoal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PaintedIcon(icon, size: 34)
            Text(title).font(.subheadline.weight(.bold))
            HStack(spacing: 3) {
                PaintedIcon("xp_star", size: 15)
                Text("+\(xp) XP").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            }
            if let line = GameSession.shared.line(HealthRules.line(goal)) {
                Text("\u{201C}\(line)\u{201D}").font(.caption2).italic().foregroundStyle(Theme.inkSoft).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
        .accessibilityElement(children: .combine)
    }
}

/// In the cat's settings: the health layer on or off.
struct HealthSettingsCard: View {
    @State private var on = HealthLayer.on

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $on) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Steps, sleep and workouts").font(.headline)
                    Text("Extra XP when you meet a goal. Read from Health on this device only.")
                        .font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.accent)
            .disabled(!HealthLayer.isAvailable)
        }
        .padding(16)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: on) { _, on in
            if on, !HealthLayer.on {
                Task { await HealthLayer.ask() }
            } else {
                HealthLayer.on = on
            }
        }
    }
}

/// "Help improve HouseCat?", once, on the second day of care (Josh, 21 Oct: a card in the house style rather than
/// only the switch in Settings; `AnalyticsRules` keeps it off the days the reminders and Health cards have). Plain
/// about what is sent and what never is; Not now never asks again, and the Settings switch stays either way.
struct AnalyticsPromptCard: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon("group_of_three_paw_prints", size: 34)
                Text("Help improve HouseCat?").font(Theme.title(22))
            }
            Text(
                "Send anonymous counts of what gets used, such as how many people finish the tour or open the shop. No account, no names or places, nothing you type, and never tracked across other apps or websites."
            )
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            Text("You can change this any time in Settings.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                Spacer()
                HUDButton("Not now") {
                    Analytics.asked = true
                    done()
                }
                .accessibilityIdentifier("analyticsNotNow")
                HUDButton("Yes, help", icon: "group_of_three_paw_prints", prominent: true) {
                    Analytics.on = true
                    Analytics.asked = true
                    done()
                }
                .accessibilityIdentifier("analyticsYes")
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
        .accessibilityIdentifier("analyticsCard")
    }
}

/// In the cat's settings: anonymous usage counts, off until switched on (UK AADC: high privacy by default).
struct AnalyticsCard: View {
    @State private var on = Analytics.on

    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Help improve HouseCat").font(.headline)
                Text("Sends anonymous counts, such as how many people finish the tour. No names, places or anything you type.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: on) { _, on in Analytics.on = on }
    }
}
