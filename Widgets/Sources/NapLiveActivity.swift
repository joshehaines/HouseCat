import ActivityKit
import HouseCatCore
import HouseCatUI
import SwiftUI
import WidgetKit

/// The nap's Live Activity: the cat curled up (the kit's sleep pose, the player's own look) and the time left.
struct NapLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NapAttributes.self) { context in
            NapLockScreen(context: context)
                .activityBackgroundTint(Color(red: 0.16, green: 0.15, blue: 0.27))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    NapCat(size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NapClock(state: context.state, font: .title2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.awake ? "\(context.attributes.catName) is up again." : "\(context.attributes.catName) is napping.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5))
            } compactTrailing: {
                NapClock(state: context.state, font: .caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5))
            }
        }
    }
}

private struct NapLockScreen: View {
    let context: ActivityViewContext<NapAttributes>

    var body: some View {
        HStack(spacing: 14) {
            NapCat(size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.awake ? "\(context.attributes.catName) is up" : "\(context.attributes.catName) is napping")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                if context.state.awake {
                    Text("Nap over").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                } else {
                    ProgressView(timerInterval: context.attributes.startedAt ... context.state.endsAt, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(Color(red: 1, green: 0.85, blue: 0.5))
                    Text("Finish it for \(Tuning.XP.nap) XP").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            NapClock(state: context.state, font: .title.monospacedDigit())
        }
        .padding(16)
    }
}

/// The time left, counting down by itself (the Live Activity is never redrawn each second).
private struct NapClock: View {
    let state: NapAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.awake {
                Image(systemName: "sun.max.fill")
            } else {
                Text(timerInterval: Date() ... state.endsAt, countsDown: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(font)
        .foregroundStyle(.white)
    }
}

/// The player's cat curled up, from the widget kit (the moon if the kit is not made yet).
private struct NapCat: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let picture = WidgetPictures.image(WidgetFiles.catFile(.sleepCurl)) {
                picture.resizable().scaledToFit()
            } else {
                Image(systemName: "moon.zzz.fill").resizable().scaledToFit().foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5))
            }
        }
        .frame(width: size, height: size)
    }
}
