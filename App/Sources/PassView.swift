import HouseCatCore
import HouseCatUI
import SwiftUI

/// The season pass (SPEC "Season pass"; Josh, 18 Oct: seasonal drops with a free and a paid track, the paid one
/// part of Cat Club): twenty tiers side by side, the free track on top and Cat Club's below, each reward shown
/// before it is earned, Claim on every tier reached, the season's real last day, and the way into Cat Club for
/// the paid track. Before the first season: when it starts and what it holds.
struct PassView: View {
    let club: Bool
    let joinClub: () -> Void
    let close: () -> Void
    @State private var info: GameSession.PassInfo?
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                PaintedIcon("season_pass_ticket", size: 40)
                header
                Spacer()
                CloseButton(action: close)
            }
            if let info {
                tracks(info)
                if !info.ownsPaid {
                    HStack(spacing: 10) {
                        Text("The lower track comes with Cat Club, and every tier you have reached opens at once.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        HUDButton("Cat Club", icon: "cat_face", prominent: true, action: joinClub)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 820)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
        .onAppear { info = GameSession.shared.passInfo(club: club) }
    }

    @ViewBuilder
    private var header: some View {
        if let info {
            let last = info.season.endDay.advanced(by: -1)
            let points = info.progress.points % Tuning.Pass.pointsPerTier
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(Theme.title(22))
                HStack(spacing: 10) {
                    Text("Tier \(info.progress.tier) of \(Tuning.Pass.tiers) · ends \(last.date.day) \(ShopView.monthName(last.month))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                    if info.progress.tier < Tuning.Pass.tiers {
                        ProgressView(value: Double(points), total: Double(Tuning.Pass.pointsPerTier)).tint(Theme.accent).frame(width: 120)
                        Text("\(points)/\(Tuning.Pass.pointsPerTier) points").font(.caption.monospacedDigit()).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        } else if let next = Self.nextSeason {
            VStack(alignment: .leading, spacing: 3) {
                Text(next.name).font(Theme.title(26))
                Text("Starts on \(next.start.date.day) \(ShopView.monthName(next.start.month)): twenty tiers of rewards for looking after your cat, on a free track and Cat Club's.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The first season that has not started yet.
    static var nextSeason: (name: String, start: GameDay)? {
        let today = DayClock().day(of: .now)
        return (GameWorld.content?.seasons.seasons ?? [])
            .compactMap { season in GameDay(iso: season.startAt).map { (season.name, $0) } }
            .filter { $0.1 > today }
            .min { $0.1 < $1.1 }
    }

    private func tracks(_ info: GameSession.PassInfo) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    VStack(spacing: 6) {
                        trackLabel("Free", icon: "gift_box_with_a_ribbon")
                        Color.clear.frame(height: 22)
                        trackLabel("Cat Club", icon: "cat_face")
                    }
                    ForEach(1 ... Tuning.Pass.tiers, id: \.self) { tier in
                        VStack(spacing: 6) {
                            cell(info, track: .free, tier: tier)
                            Text("\(tier)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(tier <= info.progress.tier ? .white : Theme.inkSoft)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(tier <= info.progress.tier ? Theme.accent : Theme.cream))
                            cell(info, track: .paid, tier: tier)
                        }
                        .id(tier)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                // Further on, the tier reached comes into view; early on the track names stay.
                if info.progress.tier > 4 {
                    reader.scrollTo(info.progress.tier - 1, anchor: .leading)
                }
            }
        }
    }

    private func trackLabel(_ text: String, icon: String) -> some View {
        VStack(spacing: 2) {
            PaintedIcon(icon, size: 28)
            Text(text).font(.caption2.weight(.bold))
        }
        .frame(width: 56, height: 98)
    }

    private func cell(_ info: GameSession.PassInfo, track: PassTrack, tier: Int) -> some View {
        let reward = info.season.reward(track: track, tier: tier)
        let claimed = (track == .free ? info.progress.claimedFree : info.progress.claimedPaid).contains(tier)
        let claimable = (track == .free ? info.claimableFree : info.claimablePaid).contains(tier)
        let locked = track == .paid && !info.ownsPaid
        return VStack(spacing: 3) {
            ZStack {
                rewardPicture(reward).frame(width: 56, height: 40).opacity(locked ? 0.55 : 1)
                if locked {
                    PaintedIcon("padlock", size: 20).offset(x: 24, y: -16)
                }
            }
            Text(rewardName(reward)).font(.system(size: 10, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 24)
            if claimed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).frame(height: 20)
            } else if claimable {
                Button {
                    feedback.tap()
                    GameSession.shared.claim(season: info.season.id, track: track, tier: tier)
                    self.info = GameSession.shared.passInfo(club: club)
                } label: {
                    Text("Claim").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 20)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressStyle())
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .padding(5)
        .frame(width: 76, height: 98)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(claimable ? Theme.accent.opacity(0.14) : Theme.cream))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(claimable ? Theme.accent : Theme.rim, lineWidth: claimable ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tier \(tier), \(track == .free ? "free" : "Cat Club"): \(rewardName(reward))\(claimed ? ", claimed" : claimable ? ", ready to claim" : locked ? ", with Cat Club" : "")")
    }

    @ViewBuilder
    private func rewardPicture(_ reward: PassReward?) -> some View {
        if let reward {
            switch reward.kind {
            case .beans: PaintedIcon("bean_coin", size: 40)
            case .item: (reward.id.flatMap(Pieces.picture) ?? Image(systemName: "shippingbox")).resizable().interpolation(.high).scaledToFit()
            case .outfit:
                let sprite = GameWorld.content?.outfits.outfits.first { $0.id == reward.id }?.sprites["tqfront"]
                (sprite.flatMap(CatScreens.picture) ?? Image(systemName: "tshirt")).resizable().interpolation(.high).scaledToFit()
            case .surface:
                let sprite = GameWorld.content?.catalogue.surfaces.first { $0.id == reward.id }?.sprite
                (sprite.flatMap(CatScreens.picture) ?? Image(systemName: "square.grid.3x3")).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            Color.clear
        }
    }

    private func rewardName(_ reward: PassReward?) -> String {
        guard let reward else { return "" }
        switch reward.kind {
        case .beans: return "\(reward.amount ?? 0) Beans"
        case .item: return reward.id.flatMap { Pieces.item($0)?.name } ?? "A piece"
        case .outfit: return GameWorld.content?.outfits.outfits.first { $0.id == reward.id }?.name ?? "An outfit"
        case .surface: return GameWorld.content?.catalogue.surfaces.first { $0.id == reward.id }?.name ?? "A wallpaper"
        }
    }
}
