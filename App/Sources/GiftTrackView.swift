import HouseCatCore
import HouseCatUI
import SwiftUI

/// The launch's gift track (SPEC "Launch": a 14-day Housewarming track with a real end date): every day's
/// present on show from the first day, today's and any missed ones to open, the last day as a real date.
struct GiftTrackView: View {
    let event: EventDefinition
    let close: () -> Void
    @State private var progress = (waiting: [Int](), claimed: Set<Int>(), today: Int?.none)
    @State private var opened: Int?
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PaintedIcon("gift_box_with_a_ribbon", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name).font(Theme.title(28))
                    Text(
                        "A present for the new house every day, until \(event.lastDay.date.day) \(ShopView.monthName(event.lastDay.month)). Missed one? Open it any day before then."
                    )
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CloseButton(action: close)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                ForEach(event.rewards, id: \.day) { reward in
                    cell(reward)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 760)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Theme.ink)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        progress = GameSession.shared.trackProgress(event)
    }

    @ViewBuilder
    private func cell(_ reward: EventReward) -> some View {
        let claimed = progress.claimed.contains(reward.day)
        let waiting = progress.waiting.contains(reward.day)
        Button {
            guard waiting else { return }
            feedback.tap()
            GameSession.shared.claim(event, day: reward.day)
            Sound.play("ui_gift_open_common", volume: Tuning.Sound.gift)
            withAnimation(.spring(duration: 0.4, bounce: 0.5)) { opened = reward.day }
            refresh()
        } label: {
            VStack(spacing: 3) {
                Text("Day \(reward.day)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                ZStack {
                    if let item = reward.item,
                       let sprite = GameWorld.content?.catalogue.items.first(where: { $0.id == item })?.sprites["R"],
                       let picture = CatScreens.picture(sprite)
                    {
                        picture.resizable().scaledToFit()
                    } else {
                        PaintedIcon("bean_coin", size: 34)
                    }
                }
                .frame(height: 42)
                .scaleEffect(opened == reward.day ? 1.2 : 1)
                Text(label(reward)).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Group {
                    if claimed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    } else if waiting {
                        Text("Open").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                    } else {
                        PaintedIcon("padlock", size: 14)
                    }
                }
                .frame(height: 18)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(waiting ? Theme.cream : Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                waiting ? Theme.accent : Theme.rim,
                lineWidth: waiting ? 2 : 1
            ))
            .opacity(claimed ? 0.7 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(!waiting)
        .accessibilityLabel("Day \(reward.day): \(label(reward))\(claimed ? ", opened" : waiting ? ", ready to open" : "")")
    }

    private func label(_ reward: EventReward) -> String {
        let item = reward.item.flatMap { id in GameWorld.content?.catalogue.items.first { $0.id == id }?.name }
        switch (item, reward.beans) {
        case let (item?, beans?): return "\(item) + \(beans)"
        case let (item?, nil): return item
        case let (nil, beans?): return "\(beans) Beans"
        default: return ""
        }
    }
}
