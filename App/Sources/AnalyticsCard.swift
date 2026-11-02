import HouseCatCore
import HouseCatUI
import SwiftUI

/// "Help improve HouseCat?", once, on the second day of care (Josh, 21 Oct: a card in the house style rather than
/// only the switch in Settings; `AnalyticsRules` keeps it off the day the reminders card has). Plain
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
