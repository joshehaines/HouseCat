import HouseCatCore
import HouseCatUI
import SwiftUI

/// Day 3's question (SPEC "Health layer": asked with the benefit stated): may the cat notice your steps, sleep
/// and workouts? Rewards only, read-only, and it can be turned off from the cat's settings.
struct HealthCard: View {
    let catName: String
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon("trust_heart_with_a_paw_print", size: 34)
                Text("\(catName) notices things").font(Theme.title(22))
            }
            Text(
                "If you walk \(Tuning.Health.stepsGoal.formatted()) steps, sleep \(Int(Tuning.Health.sleepGoalHours)) hours or do a workout, \(catName) will notice and you'll earn extra XP. A day you don't is never held against you."
            )
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            Text("HouseCat only reads these three things from Health, on this phone. Nothing is written to Health or sent anywhere.")
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
        .frame(maxWidth: 480)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
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
                    Text("Extra XP when you meet a goal. Read from Health on this phone only.")
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
