import HouseCatCore
import HouseCatUI
import SwiftUI

/// One game being played (a new one each time Play is chosen).
struct PlayRound: Identifiable {
    let id = UUID()
    let game: MinigamesFile.Game
}

/// Before a nap (SPEC "Care": a 20-minute wind-down timer; complete it for XP).
struct NapCard: View {
    let catName: String
    /// Whether today's nap still pays.
    let pays: Bool
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon("nap_moon", size: 36)
                Text("A nap for \(catName)?").font(Theme.title(24))
            }
            Text("Twenty quiet minutes. \(catName) curls up here and on your Lock Screen, and you can wind down too.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(pays ? "Let it run its course for \(Tuning.XP.nap) XP." :
                "Today's nap XP is already in; this one is just for the cosiness.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                Spacer()
                HUDButton("Not now", action: close)
                HUDButton("Start the nap", icon: "nap_moon", prominent: true, action: start)
            }
        }
        .padding(20)
        .frame(maxWidth: 440)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }
}

/// While the cat naps: the time left, and a way to wake it.
struct NapBanner: View {
    let catName: String
    let endsAt: Date
    let wake: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PaintedIcon("nap_moon", size: 28)
            Text("\(catName) is napping").font(.system(size: 15, weight: .bold))
            Text(timerInterval: Date() ... max(Date(), endsAt), countsDown: true)
                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                .frame(minWidth: 52)
            HUDButton("Wake", symbol: "sun.max", action: wake)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .paper(Capsule())
        .foregroundStyle(Theme.ink)
    }
}
