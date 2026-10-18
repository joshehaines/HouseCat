import HouseCatCore
import HouseCatUI
import SwiftUI

/// What this phone has already seen of the other owner (paw prints, presents): a device preference, since each
/// owner sees them on their own phone.
@MainActor
enum Together {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var lastLooked: Date? {
        get { defaults.object(forKey: "together.lastLooked") as? Date }
        set { defaults.set(newValue, forKey: "together.lastLooked") }
    }

    /// What the other owner left since this phone last looked, marked seen.
    static func take() -> (prints: [String: Int], gifts: [OutfitGift]) {
        let session = GameSession.shared
        let since = lastLooked
        lastLooked = session.now()
        #if DEBUG
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "present" {
                return ([:], [OutfitGift(outfitID: "raincoat", from: "co:Sam", at: Date())])
            }
        #endif
        return (session.pawPrints(since: since), session.unopenedGifts(since: since))
    }
}

/// Looking after the cat together (Josh, 18 Oct; Duolingo's friends quest, Finch's nudges): this week's shared
/// goal with who has pitched in, its Beans once it is met, a paw print to send (one a day, seen at the other
/// owner's next visit) and a present to give from the shop's outfits.
struct TogetherCard: View {
    let catName: String
    let givePresent: () -> Void
    let close: () -> Void
    @State private var quest = Self.progress
    @State private var canSend = GameSession.shared.canSendPawPrint
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PaintedIcon("group_of_three_paw_prints", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking after \(catName) together").font(Theme.title(23))
                    Text("Visits this week, between you.").font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                CloseButton(action: close)
            }
            if let quest {
                questView(quest)
            }
            HStack(spacing: 10) {
                HUDButton(canSend ? "Send a paw print" : "Paw print sent today", icon: "group_of_three_paw_prints") {
                    feedback.tap()
                    GameSession.shared.sendPawPrint()
                    canSend = GameSession.shared.canSendPawPrint
                }
                .disabled(!canSend)
                HUDButton("Give a present", icon: "gift_box_with_a_ribbon", action: givePresent)
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
    }

    private static var progress: CoopQuest.Progress? {
        #if DEBUG
            // Screenshot runs (HOUSECAT_SCREEN=together) on a save with one owner: a week part done.
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "together", GameSession.shared.questProgress == nil {
                return CoopQuest.Progress(total: 7, byOwner: ["owner": 4, "co:Sam": 3], target: Tuning.Coop.questVisits, claimed: false)
            }
        #endif
        return GameSession.shared.questProgress
    }

    private func questView(_ quest: CoopQuest.Progress) -> some View {
        let session = GameSession.shared
        let me = HouseholdSync.actor.key
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(min(quest.total, quest.target)) of \(quest.target) visits").font(.headline)
                Spacer()
                HStack(spacing: 3) {
                    PaintedIcon("bean_coin", size: 20)
                    Text("\(Tuning.Coop.questBeans)").font(.subheadline.weight(.bold))
                }
            }
            ProgressView(value: Double(min(quest.total, quest.target)), total: Double(quest.target)).tint(Theme.accent)
            ForEach(quest.byOwner.sorted { $0.key < $1.key }, id: \.key) { key, visits in
                HStack(spacing: 6) {
                    Image(systemName: visits >= Tuning.Coop.questMinimumEach ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(visits >= Tuning.Coop.questMinimumEach ? Theme.accent : Theme.inkSoft)
                    Text(key == me ? "You" : session.otherOwnerName(key)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(visits) \(visits == 1 ? "day" : "days")").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                }
            }
            Text("Each of you visits on at least \(Tuning.Coop.questMinimumEach) days.").font(.caption).foregroundStyle(Theme.inkSoft)
            if quest.claimed {
                Text("This week's Beans are in. A new week starts on Monday.").font(.subheadline.weight(.semibold))
            } else if quest.isComplete {
                ChunkyButton("Claim \(Tuning.Coop.questBeans) Beans") {
                    GameSession.shared.claimQuest()
                    self.quest = GameSession.shared.questProgress
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cream))
    }
}

/// A present from the other owner, waiting at this phone's next visit: a wrapped box that opens on a tap to
/// show the outfit and who gave it.
struct PresentCard: View {
    let gift: OutfitGift
    let catName: String
    let close: () -> Void
    @State private var opened = false

    private var outfit: OutfitsFile.Outfit? {
        GameWorld.content?.outfits.outfits.first { $0.id == gift.outfitID }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(opened ? "\(outfit?.name ?? "An outfit") for \(catName)" : "A present for \(catName)")
                .font(Theme.title(25))
                .contentTransition(.opacity)
            ZStack {
                if opened, let sprite = outfit?.sprites["tqfront"], let picture = CatScreens.picture(sprite) {
                    picture.resizable().interpolation(.high).scaledToFit()
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Button {
                        Sound.play("ui_gift_open_rare", volume: Tuning.Sound.gift)
                        withAnimation(.spring(duration: 0.55, bounce: 0.45)) { opened = true }
                    } label: {
                        PaintedIcon("gift_box_with_a_ribbon", size: 130)
                            .rotationEffect(.degrees(opened ? 0 : -4))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Open the present")
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
                }
            }
            .frame(height: 150)
            Text(opened ? "From \(GameSession.shared.otherOwnerName(gift.from)). It's in \(catName)'s wardrobe." : "From \(GameSession.shared.otherOwnerName(gift.from)). Tap to open it.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            if opened {
                ChunkyButton("Lovely", action: close)
            }
        }
        .padding(22)
        .frame(maxWidth: 440)
        .paper(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Theme.ink)
    }
}
