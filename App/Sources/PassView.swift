import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The season pass, the game's main progression and the main thing it sells (Josh, 19 Oct: "the 'battle pass' like
/// system with levels and paid/free journies along it"; drawn after Clash of Clans' Gold Pass and Fortnite's pass
/// screens, painted like the shop). On the left the season: its name, its real last day, the season's own room with
/// the player's cat in the top prize, and Get Premium. On the right one road of thirty tiers: the free track's
/// rewards above it (to tier twenty), the premium track's below (all thirty), every reward shown from the first
/// day, Claim on each one reached, Claim all, and a celebration for what is claimed. Get Premium opens a panel with
/// all thirty premium rewards, what opens at once, the end date and the price before anything is bought (App
/// Review 3.1.1); it is paid once, for the season, and comes with Cat Club. Nothing is random and nothing counts
/// down but the season's real end. Drawn for a landscape phone and scaled to the screen, like the shop.
struct PassView: View {
    let store: (any EntitlementService)?
    /// Cat Club's page in the shop.
    let openClub: () -> Void
    /// A claimed piece put out now: the pass closes and the decorate tray opens on it.
    let placePiece: (String) -> Void
    let close: () -> Void

    @State private var info: GameSession.PassInfo?
    @State private var showPremium = false
    @State private var celebration: Celebration?
    @State private var buying = false
    @State private var message: String?
    @State private var portrait: CGImage?
    @State private var prices = StorePrices.shared
    @Environment(\.controlFeedback) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the celebration shows: one reward, several claimed at once, or Premium just bought.
    enum Celebration: Equatable {
        case one(PassReward, PassTrack)
        case many([PassReward])
        case premium(opened: Int)
    }

    var body: some View {
        GeometryReader { geometry in
            let s = Self.scale(for: geometry.size)
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.9), Color(red: 0.95, green: 0.88, blue: 0.78)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if let info {
                    HStack(spacing: 12 * s) {
                        hero(info, s: s)
                            .frame(width: 236 * s)
                        VStack(spacing: 8 * s) {
                            header(info, s: s)
                            track(info, s: s)
                        }
                    }
                    .padding(.vertical, 10 * s)
                    .overlay(alignment: .topLeading) {
                        CloseButton(action: close).scaleEffect(s * 0.9).offset(x: -14 * s, y: -2 * s)
                    }
                    if showPremium {
                        premiumPanel(info, s: s)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if let celebration {
                        celebrationView(celebration, info: info, s: s)
                            .transition(.opacity)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("The season pass will be back shortly.").font(Theme.title(20))
                        HUDButton("Close", symbol: "xmark", action: close)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.25), value: showPremium)
            .animation(.easeOut(duration: 0.25), value: celebration)
        }
        .foregroundStyle(Theme.ink)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear(perform: reload)
        .task(id: info?.season.id) { await drawPortrait() }
        #if DEBUG
            // Screenshot runs: HOUSECAT_PASS=premium opens the panel, claim and claimall claim what waits, bought
            // shows Premium just bought; HOUSECAT_PASS_OWNED=1 records this season's pass first.
            .task {
                if ProcessInfo.processInfo.environment["HOUSECAT_PASS_OWNED"] == "1", let season = info?.season {
                    GameSession.shared.recordPass(season.passID)
                    reload()
                }
                guard let info else { return }
                switch ProcessInfo.processInfo.environment["HOUSECAT_PASS"] {
                case "premium": showPremium = true
                case "claim":
                    if let tier = info.claimablePaid.first {
                        claim(info, track: .paid, tier: tier)
                    } else if let tier = info.claimableFree.first {
                        claim(info, track: .free, tier: tier)
                    }
                case "claimall": claimAll(info)
                case "bought": celebrate(.premium(opened: info.openAtOnce.count))
                default: break
                }
            }
        #endif
        .task {
            if prices.products.isEmpty {
                await prices.load(store: store, content: GameWorld.content)
            }
        }
    }

    /// Drawn for a landscape phone (inside the safe area), scaled to the screen in steps.
    static func scale(for size: CGSize) -> CGFloat {
        let fit = min(size.width / Tuning.Pass.screenDesignWidth, size.height / Tuning.Pass.screenDesignHeight)
        let stepped = (fit * 20).rounded(.down) / 20
        return min(max(stepped, Tuning.Pass.screenSmallestScale), Tuning.Pass.screenLargestScale)
    }

    private func reload() {
        let owned = store?.entitlements ?? .none
        info = GameSession.shared.passInfo(club: owned.hasClub, passes: owned.passes)
    }

    private var owned: Entitlements {
        store?.entitlements ?? .none
    }

    // MARK: The season (left)

    private func hero(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let capstone = info.season.paidTrack.last
        return VStack(alignment: .leading, spacing: 4 * s) {
            Text("SEASON PASS").font(.system(size: 10 * s, weight: .heavy, design: .rounded)).tracking(2 * s).foregroundStyle(GameHUD.gold)
            Text(info.name).font(Theme.title(26 * s)).foregroundStyle(Theme.cream).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 5 * s) {
                PaintedIcon("calendar", size: 15 * s)
                Text(Self.endsLine(info)).font(.system(size: 11 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cream.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            }
            stage(info, s: s)
                .frame(height: 132 * s)
                .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                .padding(.top, 4 * s)
            VStack(spacing: 1 * s) {
                Text("Tier \(Tuning.Pass.tiers): \(Self.name(capstone))").font(.system(size: 12 * s, weight: .heavy, design: .rounded))
                    .foregroundStyle(GameHUD.gold)
                Text("and \(info.season.paidTrack.count - 1) more rewards on Premium").font(.system(size: 10.5 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2 * s)
            Spacer(minLength: 4 * s)
            if info.ownsPaid {
                Label(owned.hasClub && !owned.passes.contains(info.season.passID) ? "Premium with Cat Club" : "Premium is yours", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42 * s)
                    .background(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).fill(GameHUD.green))
                Text("Every reward on both tracks is yours to claim.")
                    .font(.system(size: 10.5 * s, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.8))
                    .frame(maxWidth: .infinity)
            } else {
                goldButton(premiumButtonTitle(info), s: s) {
                    feedback.tap()
                    showPremium = true
                }
                Button {
                    feedback.tap()
                    openClub()
                } label: {
                    (Text("or ") + Text("included with Cat Club").underline())
                        .font(.system(size: 11.5 * s, weight: .bold, design: .rounded)).foregroundStyle(GameHUD.gold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(14 * s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Self.premiumFill, in: RoundedRectangle(cornerRadius: 24 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).strokeBorder(GameHUD.deepGold, lineWidth: 2.5 * s))
        .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
        .accessibilityElement(children: .contain)
    }

    /// The season's own room: its premium wallpaper and floor, its signature piece, and the player's cat in the top
    /// prize.
    private func stage(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let surfaces = info.season.paidTrack.filter { $0.kind == .surface }.compactMap(\.id)
        let wall = surfaces.first { !$0.hasPrefix("floor") }.flatMap(Self.surfaceImage)
        let floor = surfaces.first { $0.hasPrefix("floor") }.flatMap(Self.surfaceImage)
        let piece = info.season.paidTrack.first { $0.kind == .item }?.id.flatMap(Pieces.picture)
        return ZStack(alignment: .bottom) {
            Tiled(image: wall, tile: 74 * s).overlay(Color.black.opacity(0.06))
            Tiled(image: floor, tile: 64 * s).frame(height: 34 * s)
            RadialGradient(colors: [.clear, Color(red: 0.12, green: 0.1, blue: 0.22).opacity(0.5)], center: .center, startRadius: 40 * s, endRadius: 150 * s)
            HStack(alignment: .bottom, spacing: 0) {
                piece?.resizable().interpolation(.high).scaledToFit().frame(width: 84 * s, height: 70 * s)
                    .shadow(color: .black.opacity(0.3), radius: 3 * s, y: 2 * s)
                Spacer(minLength: 0)
                if let portrait {
                    Image(decorative: portrait, scale: 1).resizable().interpolation(.high).scaledToFit()
                        .frame(height: 118 * s)
                        .shadow(color: .black.opacity(0.35), radius: 5 * s, y: 4 * s)
                }
            }
            .padding(.horizontal, 10 * s)
            .padding(.bottom, 6 * s)
        }
        .accessibilityHidden(true)
    }

    /// The player's cat wearing the season's top prize, drawn off the main thread's way once a season.
    private func drawPortrait() async {
        guard let info, let look = GameSession.shared.cat?.look else { return }
        let outfit = info.season.paidTrack.last.flatMap { reward in GameWorld.content?.outfits.outfits.first { $0.id == reward.id } }
        portrait = CatScreens.portrait(look, outfit: outfit)
    }

    // MARK: Progress (top)

    private func header(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let step = PassRules.toNextTier(info.progress)
        return HStack(spacing: 12 * s) {
            VStack(spacing: -2 * s) {
                Text("TIER").font(.system(size: 9 * s, weight: .heavy, design: .rounded)).tracking(1.4 * s).opacity(0.9)
                Text("\(info.tier)").font(.system(size: 23 * s, weight: .black, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .frame(width: 58 * s, height: 44 * s)
            .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Self.orange))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tier \(info.tier) of \(Tuning.Pass.tiers)")
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(step.needed > 0 ? "\(step.into) / \(step.needed) XP to tier \(info.tier + 1)" : "Every tier reached this season")
                    .font(.system(size: 13 * s, weight: .heavy, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Bar(fraction: step.needed > 0 ? Double(step.into) / Double(step.needed) : 1, s: s)
                    .frame(height: 11 * s)
                Text(info.tier < Tuning.Pass.freeTiers ? "Care, games and goals all count" : info.tier < Tuning.Pass.tiers ? "The free track is done: Premium goes on to \(Tuning.Pass.tiers)" : "Well done. See you next season")
                    .font(.system(size: 10 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
            }
            if let next = info.next {
                HStack(spacing: 6 * s) {
                    RewardPicture(reward: next.reward, s: s).frame(width: 38 * s, height: 34 * s)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Next").font(.system(size: 10 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        Text(Self.name(next.reward)).font(.system(size: 11.5 * s, weight: .heavy, design: .rounded)).lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: 90 * s, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next reward, tier \(next.reward.tier): \(Self.name(next.reward))")
            }
            if info.waiting > 0 {
                Button {
                    claimAll(info)
                } label: {
                    Text(info.waiting == 1 ? "Claim" : "Claim all (\(info.waiting))")
                        .font(.system(size: 13.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 14 * s)
                        .frame(height: 34 * s)
                        .background(Capsule().fill(Self.orange))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                        .shadow(color: Self.orangeLip, radius: 0, y: 3 * s)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 12 * s)
        .frame(height: 58 * s)
        .paper(RoundedRectangle(cornerRadius: 18 * s, style: .continuous))
    }

    // MARK: The road (right)

    private func track(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let card = CGSize(width: 86 * s, height: 122 * s)
        let rope = 34 * s
        return ZStack(alignment: .topLeading) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8 * s) {
                        ForEach(1 ... Tuning.Pass.tiers, id: \.self) { tier in
                            VStack(spacing: 0) {
                                cell(info, track: .free, tier: tier, size: card, s: s)
                                ropeSegment(info, tier: tier, s: s).frame(height: rope)
                                cell(info, track: .paid, tier: tier, size: card, s: s)
                            }
                            .frame(width: card.width)
                            .id(tier)
                        }
                    }
                    .padding(.leading, 38 * s)
                    .padding(.trailing, 16 * s)
                    .padding(.vertical, 6 * s)
                }
                .onAppear {
                    // The first reward waiting, else the tier being climbed, comes into view.
                    let focus = (info.claimableFree + info.claimablePaid).min() ?? info.tier + 1
                    if focus > 3 {
                        reader.scrollTo(min(focus, Tuning.Pass.tiers) - 2, anchor: .leading)
                    }
                }
            }
            VStack(spacing: 0) {
                rowLabel("FREE", premium: false, s: s).frame(height: card.height)
                Color.clear.frame(height: rope)
                rowLabel("PREMIUM", premium: true, s: s).frame(height: card.height)
            }
            .frame(width: 28 * s)
            .padding(.vertical, 6 * s)
        }
    }

    private func rowLabel(_ text: String, premium: Bool, s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10.5 * s, weight: .black, design: .rounded)).tracking(1.6 * s)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .foregroundStyle(premium ? GameHUD.gold : Color(red: 0.54, green: 0.42, blue: 0.33))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(premium ? AnyShapeStyle(Self.premiumFill) : AnyShapeStyle(Theme.cream), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(premium ? GameHUD.deepGold : Theme.rim, lineWidth: premium ? 2 * s : 1))
            .accessibilityHidden(true)
    }

    /// The road between the rows: filled up to the tier reached, part-filled through the tier being climbed, the
    /// tier's number on a medallion, and where the free track ends.
    private func ropeSegment(_ info: GameSession.PassInfo, tier: Int, s: CGFloat) -> some View {
        let step = PassRules.toNextTier(info.progress)
        let fill: Double = tier <= info.tier ? 1 : tier == info.tier + 1 && step.needed > 0 ? Double(step.into) / Double(step.needed) : 0
        let reached = tier <= info.tier
        return ZStack {
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.9, green: 0.83, blue: 0.71))
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.97, green: 0.7, blue: 0.37), Self.orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: (box.size.width + 8 * s) * fill)
                }
                // Across the column and half the gap either side, so the segments meet.
                .frame(width: box.size.width + 8 * s, height: 7 * s)
                .offset(x: -4 * s, y: (box.size.height - 7 * s) / 2)
            }
            Text("\(tier)")
                .font(.system(size: 13.5 * s, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(reached ? .white : Color(red: 0.54, green: 0.42, blue: 0.33))
                .frame(width: 30 * s, height: 30 * s)
                .background(Circle().fill(reached ? AnyShapeStyle(Self.orange) : AnyShapeStyle(Theme.cream)))
                .overlay(Circle().strokeBorder(reached ? .white : Color(red: 0.9, green: 0.83, blue: 0.71), lineWidth: 2 * s))
                .shadow(color: tier == info.tier ? Self.orange.opacity(0.6) : .clear, radius: 5 * s)
            if tier == Tuning.Pass.freeTiers {
                Text(info.tier >= tier ? "FREE TRACK DONE" : "FREE TRACK ENDS")
                    .font(.system(size: 7.5 * s, weight: .black, design: .rounded)).tracking(0.4 * s)
                    .foregroundStyle(Self.orange)
                    .fixedSize()
                    .offset(y: -12 * s)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ info: GameSession.PassInfo, track: PassTrack, tier: Int, size: CGSize, s: CGFloat) -> some View {
        if let reward = info.season.reward(track: track, tier: tier) {
            RewardCard(
                reward: reward,
                premium: track == .paid,
                claimed: info.progress.claimed(track).contains(tier),
                claimable: (track == .free ? info.claimableFree : info.claimablePaid).contains(tier),
                locked: track == .paid && !info.ownsPaid,
                reached: tier <= info.tier,
                s: s
            ) {
                tapped(info, track: track, tier: tier)
            }
            .frame(width: size.width, height: size.height)
        } else {
            // Past the free track's end: Premium only.
            RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5 * s, dash: [5 * s, 4 * s]))
                .foregroundStyle(Theme.rim)
                .overlay {
                    Text("Premium\nonly").font(.system(size: 10 * s, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                        .foregroundStyle(Theme.inkSoft.opacity(0.7))
                }
                .frame(width: size.width, height: size.height)
                .accessibilityLabel("Tier \(tier): Premium only")
        }
    }

    private func tapped(_ info: GameSession.PassInfo, track: PassTrack, tier: Int) {
        feedback.tap()
        if (track == .free ? info.claimableFree : info.claimablePaid).contains(tier) {
            claim(info, track: track, tier: tier)
        } else if track == .paid, !info.ownsPaid {
            showPremium = true
        }
    }

    // MARK: Claiming

    private func claim(_ info: GameSession.PassInfo, track: PassTrack, tier: Int) {
        if track == .paid {
            GameSession.shared.recordPremium(club: owned.hasClub, passes: owned.passes)
        }
        guard let reward = GameSession.shared.claim(season: info.season.id, track: track, tier: tier) else {
            reload()
            return
        }
        celebrate(.one(reward, track))
        reload()
    }

    private func claimAll(_ info: GameSession.PassInfo) {
        feedback.tap()
        if !info.claimablePaid.isEmpty {
            GameSession.shared.recordPremium(club: owned.hasClub, passes: owned.passes)
        }
        let claimed = GameSession.shared.claimAll(info)
        reload()
        if claimed.count == 1, let reward = claimed.first {
            celebrate(.one(reward, info.season.paidTrack.contains(reward) ? .paid : .free))
        } else if !claimed.isEmpty {
            celebrate(.many(claimed))
        }
    }

    private func celebrate(_ moment: Celebration) {
        celebration = moment
        if case .premium = moment {
            Sound.play("ui_purchase_confirm", volume: Tuning.Sound.levelUp)
        } else {
            Sound.play("ui_sparkle", volume: Tuning.Sound.levelUp)
        }
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func celebrationView(_ moment: Celebration, info: GameSession.PassInfo, s: CGFloat) -> some View {
        ZStack {
            Color(red: 0.11, green: 0.07, blue: 0.1).opacity(0.74).ignoresSafeArea()
                .onTapGesture { celebration = nil }
            Sunburst(s: s).allowsHitTesting(false)
            VStack(spacing: 6 * s) {
                switch moment {
                case let .one(reward, track):
                    RewardPicture(reward: reward, s: s * 2.6).frame(width: 220 * s, height: 140 * s)
                        .shadow(color: .black.opacity(0.4), radius: 10 * s, y: 8 * s)
                    Text("TIER \(reward.tier) · \(track == .paid ? "PREMIUM" : "FREE")")
                        .font(.system(size: 11 * s, weight: .black, design: .rounded)).tracking(2.4 * s).foregroundStyle(GameHUD.gold)
                    Text(Self.name(reward)).font(Theme.title(30 * s)).foregroundStyle(Theme.cream)
                    Text(Self.blurb(reward)).font(.system(size: 13 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.85))
                    HStack(spacing: 14 * s) {
                        celebrationButton(info.waiting > 0 ? "Next reward" : "Lovely", cream: true, s: s) {
                            celebration = nil
                            if info.waiting > 0, let first = info.claimableFree.first {
                                claim(info, track: .free, tier: first)
                            } else if let first = info.claimablePaid.first {
                                claim(info, track: .paid, tier: first)
                            }
                        }
                        if reward.kind == .item, let id = reward.id {
                            celebrationButton("Put it out now", cream: false, s: s) {
                                celebration = nil
                                placePiece(id)
                            }
                        } else if reward.kind == .outfit, let id = reward.id {
                            celebrationButton("Wear it", cream: false, s: s) {
                                GameSession.shared.wear(id)
                                celebration = nil
                            }
                        }
                    }
                    .padding(.top, 8 * s)
                case let .many(rewards):
                    Text("\(rewards.count) REWARDS CLAIMED").font(.system(size: 11 * s, weight: .black, design: .rounded)).tracking(2.4 * s).foregroundStyle(GameHUD.gold)
                    HStack(spacing: 8 * s) {
                        ForEach(Array(rewards.filter { $0.kind != .beans }.prefix(6).enumerated()), id: \.offset) { _, reward in
                            RewardPicture(reward: reward, s: s * 1.2).frame(width: 74 * s, height: 64 * s)
                        }
                    }
                    let beans = rewards.filter { $0.kind == .beans }.compactMap(\.amount).reduce(0, +)
                    if beans > 0 {
                        HStack(spacing: 6 * s) {
                            PaintedIcon("bean_coin", size: 30 * s)
                            Text("+\(beans) Beans").font(Theme.title(28 * s)).foregroundStyle(Theme.cream)
                        }
                    }
                    Text("Yours to keep. Pieces and outfits wait in your things.")
                        .font(.system(size: 13 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.85))
                    celebrationButton("Lovely", cream: false, s: s) { celebration = nil }.padding(.top, 8 * s)
                case let .premium(opened):
                    PaintedIcon("season_pass_ticket", size: 110 * s)
                    Text("PREMIUM").font(.system(size: 11 * s, weight: .black, design: .rounded)).tracking(2.4 * s).foregroundStyle(GameHUD.gold)
                    Text("\(info.name) Premium is yours").font(Theme.title(28 * s)).foregroundStyle(Theme.cream)
                    Text(opened > 0 ? "\(opened) premium rewards are ready to claim now." : "Every premium reward opens as you climb.")
                        .font(.system(size: 13 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.85))
                    celebrationButton(info.waiting > 0 ? "Claim all (\(info.waiting))" : "Lovely", cream: false, s: s) {
                        celebration = nil
                        if info.waiting > 0 {
                            claimAll(info)
                        }
                    }
                    .padding(.top, 8 * s)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40 * s)
            .background(alignment: .bottom) {
                // Under the words, so the label and the name read over the glow.
                RoundedRectangle(cornerRadius: 26 * s, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.07, blue: 0.1).opacity(0.55))
                    .frame(height: 150 * s)
                    .padding(.horizontal, 10 * s)
                    .blur(radius: 14 * s)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func celebrationButton(_ title: String, cream: Bool, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            feedback.tap()
            action()
        } label: {
            Text(title).font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(cream ? Theme.ink : .white)
                .padding(.horizontal, 24 * s)
                .frame(height: 44 * s)
                .background(RoundedRectangle(cornerRadius: 15 * s, style: .continuous).fill(cream ? AnyShapeStyle(Theme.cream) : AnyShapeStyle(Self.orange)))
                .shadow(color: cream ? Color(red: 0.8, green: 0.72, blue: 0.6) : Self.orangeLip, radius: 0, y: 4 * s)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Premium (the panel before buying)

    private func premiumPanel(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let contents = PassRules.contents(of: info.season.paidTrack)
        let opens = info.openAtOnce.count
        let last = info.season.lastDay
        return ZStack {
            Color(red: 0.11, green: 0.07, blue: 0.1).opacity(0.6).ignoresSafeArea()
                .onTapGesture { showPremium = false }
            HStack(alignment: .top, spacing: 16 * s) {
                VStack(alignment: .leading, spacing: 6 * s) {
                    Text("\(info.name.uppercased()) PREMIUM").font(.system(size: 10 * s, weight: .heavy, design: .rounded)).tracking(2 * s)
                        .foregroundStyle(GameHUD.gold).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(contents.rewards) more rewards").font(Theme.title(23 * s)).foregroundStyle(Theme.cream)
                    panelLine("sofa_for_furniture", Self.piecesLine(contents), s: s)
                    panelLine("cat_face", Self.outfitsLine(info), s: s)
                    panelLine("bean_coin", "\(contents.beans.formatted()) Beans, on top of the free track's", s: s)
                    panelLine(
                        "xp_star",
                        opens > 0 ? "You're at tier \(info.tier): \(opens) open at once (ticked)" : "Each opens as you climb, tier by tier",
                        s: s
                    )
                    panelLine("calendar", "Ends \(Self.dayName(last)). Claim before then; what you claim is yours to keep.", s: s)
                    Spacer(minLength: 2 * s)
                    goldButton(buying ? "Buying…" : premiumButtonTitle(info), s: s) { buy(info) }
                        .disabled(buying)
                    Button {
                        feedback.tap()
                        showPremium = false
                        openClub()
                    } label: {
                        (Text("or ") + Text("included with Cat Club").underline())
                            .font(.system(size: 11.5 * s, weight: .bold, design: .rounded)).foregroundStyle(GameHUD.gold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressStyle())
                    if let message {
                        Text(message).font(.system(size: 10 * s, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cream).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 3 * s) {
                        Text("Paid once, for this season.")
                        HStack(spacing: 10 * s) {
                            Button("Restore Purchases") { restore() }
                            Link("Terms", destination: Tuning.Store.termsURL)
                            Link("Privacy", destination: Tuning.Store.privacyURL)
                        }
                    }
                    .font(.system(size: 10 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .tint(Theme.cream.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 236 * s)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6 * s), count: 8), spacing: 6 * s) {
                    ForEach(info.season.paidTrack, id: \.tier) { reward in
                        let open = info.openAtOnce.contains(reward.tier)
                        VStack(spacing: 2 * s) {
                            RewardPicture(reward: reward, s: s * 0.62).frame(height: 38 * s)
                            Text(Self.name(reward)).font(.system(size: 8.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream)
                                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72 * s)
                        .background(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(.white.opacity(reward.kind == .beans ? 0.07 : 0.15)))
                        .overlay(RoundedRectangle(cornerRadius: 11 * s, style: .continuous)
                            .strokeBorder(open ? Self.orange : GameHUD.gold.opacity(reward.kind == .beans ? 0.25 : 0.6), lineWidth: open ? 2 * s : 1))
                        .overlay(alignment: .topLeading) {
                            Text("\(reward.tier)").font(.system(size: 8.5 * s, weight: .black, design: .rounded)).foregroundStyle(GameHUD.gold.opacity(0.85))
                                .padding(4 * s)
                        }
                        .overlay(alignment: .topTrailing) {
                            if open {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12 * s)).foregroundStyle(.white, Self.orange).padding(3 * s)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tier \(reward.tier): \(Self.name(reward))\(open ? ", opens at once" : "")")
                    }
                }
            }
            .padding(18 * s)
            .background(Self.premiumFill, in: RoundedRectangle(cornerRadius: 26 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).strokeBorder(GameHUD.deepGold, lineWidth: 2.5 * s))
            .overlay(alignment: .topTrailing) {
                CloseButton { showPremium = false }.scaleEffect(s * 0.85).offset(x: 12 * s, y: -12 * s)
            }
            .padding(.vertical, 12 * s)
            .padding(.horizontal, 8 * s)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func panelLine(_ icon: String, _ text: String, s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 7 * s) {
            PaintedIcon(icon, size: 18 * s)
            Text(text).font(.system(size: 11 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func premiumButtonTitle(_ info: GameSession.PassInfo) -> String {
        "Get Premium · " + (prices.price(info.season.sku) ?? "…")
    }

    private func buy(_ info: GameSession.PassInfo) {
        feedback.tap()
        buying = true
        message = nil
        Task {
            defer { buying = false }
            switch await ShopPurchase.buy(info.season.sku, store: store) {
            case .bought:
                // The grant has recorded the pass in the save; Cat Club or not, the premium track is open.
                GameSession.shared.recordPass(info.season.passID)
                reload()
                showPremium = false
                celebrate(.premium(opened: info.openAtOnce.count))
            case .pending: message = "Waiting for approval. Premium opens as soon as it goes through."
            case .cancelled: break
            case .failed: message = "That purchase did not go through. Nothing was charged."
            }
        }
    }

    private func restore() {
        Task {
            message = await RestorePurchases.run(store)
            if let info, owned.passes.contains(info.season.passID) {
                GameSession.shared.recordPass(info.season.passID)
            }
            reload()
        }
    }

    // MARK: Pieces

    private func goldButton(_ title: String, s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17 * s, weight: .black, design: .rounded)).foregroundStyle(.white)
                .shadow(color: Color(red: 0.43, green: 0.24, blue: 0).opacity(0.45), radius: 0, y: 1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44 * s)
                .background(RoundedRectangle(cornerRadius: 15 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.77, blue: 0.36), Color(red: 0.86, green: 0.6, blue: 0.16)], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Color(red: 0.66, green: 0.42, blue: 0.07), radius: 0, y: 4 * s)
        }
        .buttonStyle(PressStyle())
    }

    static let orange = Color(red: 0.89, green: 0.45, blue: 0.16)
    static let orangeLip = Color(red: 0.71, green: 0.33, blue: 0.1)
    static let premiumFill = LinearGradient(
        colors: [Color(red: 0.18, green: 0.29, blue: 0.39), Color(red: 0.24, green: 0.23, blue: 0.38), Color(red: 0.3, green: 0.21, blue: 0.38)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func endsLine(_ info: GameSession.PassInfo) -> String {
        let ends = "Ends \(dayName(info.season.lastDay))"
        // The season's real end is the only count shown, and only in its last week (CLAUDE.md "no countdowns").
        return info.daysLeft <= 7 ? ends + (info.daysLeft == 1 ? " · last day" : " · \(info.daysLeft) days left") : ends
    }

    static func dayName(_ day: GameDay) -> String {
        let date = day.date
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        let calendar = Calendar(identifier: .gregorian)
        guard let real = calendar.date(from: components) else { return "\(date.day) \(ShopView.monthName(date.month))" }
        return real.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }

    static func name(_ reward: PassReward?) -> String {
        guard let reward else { return "" }
        switch reward.kind {
        case .beans: return "\(reward.amount ?? 0) Beans"
        case .item: return reward.id.flatMap { Pieces.item($0)?.name } ?? "A piece"
        case .outfit: return GameWorld.content?.outfits.outfits.first { $0.id == reward.id }?.name ?? "An outfit"
        case .surface: return GameWorld.content?.catalogue.surfaces.first { $0.id == reward.id }?.name ?? "A wallpaper"
        }
    }

    static func blurb(_ reward: PassReward) -> String {
        switch reward.kind {
        case .beans: "Into your Beans."
        case .item: "Yours to keep. Put it in any room."
        case .outfit: "Yours to keep, in the wardrobe."
        case .surface: reward.id?.hasPrefix("floor") == true ? "A new floor for any room, in Decorate." : "A new wallpaper for any room, in Decorate."
        }
    }

    static func piecesLine(_ contents: PassContents) -> String {
        var parts = ["\(contents.pieces) pieces for your home"]
        if contents.wallpapers > 0 {
            parts.append(contents.wallpapers == 1 ? "a wallpaper" : "\(contents.wallpapers) wallpapers")
        }
        if contents.floors > 0 {
            parts.append(contents.floors == 1 ? "a floor" : "\(contents.floors) floors")
        }
        return ListFormatter.localizedString(byJoining: parts)
    }

    static func outfitsLine(_ info: GameSession.PassInfo) -> String {
        let outfits = info.season.paidTrack.filter { $0.kind == .outfit }
        guard let top = outfits.last else { return "" }
        let others = outfits.dropLast().map { name($0) }
        return "\(name(top)) at tier \(top.tier)" + (others.isEmpty ? "" : ", and " + ListFormatter.localizedString(byJoining: others))
    }

    static func surfaceImage(_ id: String) -> Image? {
        GameWorld.content?.catalogue.surfaces.first { $0.id == id }.flatMap { CatScreens.picture($0.sprite) }
    }
}

/// One reward on the road: its picture, its name, and Claim, a tick, or a padlock.
private struct RewardCard: View {
    let reward: PassReward
    let premium: Bool
    let claimed: Bool
    let claimable: Bool
    let locked: Bool
    let reached: Bool
    let s: CGFloat
    let action: () -> Void
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4 * s) {
                RewardPicture(reward: reward, s: s).frame(height: 58 * s)
                    .saturation(locked ? 0.75 : 1)
                    .padding(.top, 10 * s)
                Text(PassView.name(reward))
                    .font(.system(size: 11 * s, weight: .heavy, design: .rounded))
                    .foregroundStyle(premium ? Theme.cream : Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                    .frame(height: 26 * s)
                    .padding(.horizontal, 4 * s)
                Group {
                    if claimed {
                        Image(systemName: "checkmark").font(.system(size: 12 * s, weight: .black)).foregroundStyle(.white)
                            .frame(width: 22 * s, height: 22 * s).background(Circle().fill(GameHUD.green))
                    } else if claimable {
                        Text("Claim").font(.system(size: 12 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 14 * s).frame(height: 22 * s)
                            .background(Capsule().fill(PassView.orange))
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 22 * s)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(premium ? AnyShapeStyle(PassView.premiumFill) : AnyShapeStyle(Theme.cream), in: RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                .strokeBorder(premium ? GameHUD.deepGold : Theme.rim, lineWidth: premium ? 2 * s : 1))
            .overlay {
                if claimable {
                    RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                        .strokeBorder(premium ? GameHUD.gold : PassView.orange, lineWidth: 3 * s)
                        .shadow(color: (premium ? GameHUD.gold : PassView.orange).opacity(glowing ? 0.9 : 0.4), radius: (glowing ? 10 : 5) * s)
                }
            }
            .overlay(alignment: .topTrailing) {
                if locked {
                    PaintedIcon("padlock", size: 22 * s).padding(4 * s)
                }
            }
            .opacity(claimed ? 0.55 : 1)
            .shadow(color: Theme.shadow, radius: 3 * s, y: 2 * s)
        }
        .buttonStyle(PressStyle())
        .onAppear {
            guard claimable, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glowing = true }
        }
        .accessibilityLabel("Tier \(reward.tier), \(premium ? "premium" : "free"): \(PassView.name(reward))")
        .accessibilityValue(claimed ? "claimed" : claimable ? "ready to claim" : locked ? "with Premium" : reached ? "" : "not reached yet")
        .accessibilityHint(claimable ? "Claims it" : locked ? "Shows Premium" : "")
    }
}

/// A reward's picture: the Bean coin, a piece, an outfit, or a swatch of a wallpaper or floor.
private struct RewardPicture: View {
    let reward: PassReward
    let s: CGFloat

    var body: some View {
        switch reward.kind {
        case .beans:
            PaintedIcon("bean_coin", size: 46 * s)
        case .item:
            (reward.id.flatMap(Pieces.picture) ?? Image(systemName: "shippingbox")).resizable().interpolation(.high).scaledToFit()
                .shadow(color: .black.opacity(0.18), radius: 2 * s, y: 2 * s)
        case .outfit:
            let sprite = GameWorld.content?.outfits.outfits.first { $0.id == reward.id }?.sprites["tqfront"]
            (sprite.flatMap(CatScreens.picture) ?? Image(systemName: "tshirt")).resizable().interpolation(.high).scaledToFit()
                .shadow(color: .black.opacity(0.18), radius: 2 * s, y: 2 * s)
        case .surface:
            Tiled(image: reward.id.flatMap(PassView.surfaceImage), tile: 46 * s)
                .frame(width: 50 * s, height: 50 * s)
                .clipShape(RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9 * s, style: .continuous).strokeBorder(.white, lineWidth: 2 * s))
                .shadow(color: .black.opacity(0.25), radius: 3 * s, y: 2 * s)
        }
    }
}

/// A wallpaper or floor laid as tiles of a given size.
private struct Tiled: View {
    let image: Image?
    let tile: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let image, tile > 0 else { return }
            let resolved = context.resolve(image)
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.draw(resolved, in: CGRect(x: x, y: y, width: tile, height: tile))
                    x += tile
                }
                y += tile
            }
        }
        .background(Color(red: 0.93, green: 0.86, blue: 0.74))
    }
}

/// The progress bar along the header.
private struct Bar: View {
    let fraction: Double
    let s: CGFloat

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.92, green: 0.85, blue: 0.75))
                Capsule().fill(LinearGradient(colors: [Color(red: 0.97, green: 0.7, blue: 0.37), PassView.orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(box.size.height, box.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}

/// Rays turning slowly behind a claimed reward (still with Reduce Motion).
private struct Sunburst: View {
    let s: CGFloat
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0 ..< 16, id: \.self) { ray in
                Capsule()
                    .fill(LinearGradient(colors: [GameHUD.gold.opacity(0.3), GameHUD.gold.opacity(0)], startPoint: .bottom, endPoint: .top))
                    .frame(width: 22 * s, height: 190 * s)
                    .offset(y: -95 * s)
                    .rotationEffect(.degrees(Double(ray) * 22.5))
            }
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.67).opacity(0.85), Color(red: 1, green: 0.82, blue: 0.43).opacity(0)], center: .center, startRadius: 0, endRadius: 110 * s))
                .frame(width: 220 * s, height: 220 * s)
        }
        .rotationEffect(.degrees(turning ? 360 : 0))
        .offset(y: -40 * s)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}

/// The pass on the room's screen (Josh, 19 Oct: where it pulls the player along), under the Beans and the streak: the
/// ticket, the tier, the bar to the next one, the next reward, and a count when something is ready to claim.
struct PassBadge: View {
    let info: GameSession.PassInfo
    let action: () -> Void
    @Environment(\.hudScale) private var s
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        let step = PassRules.toNextTier(info.progress)
        Button {
            feedback.tap()
            action()
        } label: {
            HStack(spacing: 7 * s) {
                PaintedIcon("season_pass_ticket", size: 34 * s)
                VStack(alignment: .leading, spacing: 4 * s) {
                    HStack(spacing: 4 * s) {
                        Text("Tier \(info.tier)").font(.system(size: 13 * s, weight: .heavy, design: .rounded))
                        Spacer(minLength: 2 * s)
                        if step.needed > 0 {
                            Text("\(step.into)/\(step.needed)").font(.system(size: 10.5 * s, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Bar(fraction: step.needed > 0 ? Double(step.into) / Double(step.needed) : 1, s: s).frame(height: 7 * s)
                }
                .frame(width: 92 * s)
                if let next = info.next {
                    let premium = next.track == .paid
                    RewardPicture(reward: next.reward, s: s * 0.7)
                        .frame(width: 36 * s, height: 32 * s)
                        .padding(3 * s)
                        .background(premium ? AnyShapeStyle(PassView.premiumFill) : AnyShapeStyle(Theme.paper), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(premium ? GameHUD.deepGold : Theme.rim, lineWidth: premium ? 1.5 * s : 1))
                        .overlay(alignment: .bottomTrailing) {
                            if premium, !info.ownsPaid {
                                PaintedIcon("padlock", size: 14 * s).offset(x: 4 * s, y: 4 * s)
                            }
                        }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 6 * s)
            .padding(.trailing, 6 * s)
            .frame(height: 50 * s)
            .paper(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if info.waiting > 0 {
                    Text("\(info.waiting)").font(.system(size: 11 * s, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .frame(minWidth: 20 * s, minHeight: 20 * s)
                        .background(Circle().fill(PassView.orange))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5 * s))
                        .offset(x: 6 * s, y: -6 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Season pass, tier \(info.tier) of \(Tuning.Pass.tiers)")
        .accessibilityValue(info.waiting > 0 ? "\(info.waiting) ready to claim" : info.next.map { "Next: \(PassView.name($0.reward))" } ?? "")
        .accessibilityHint("Opens the season pass")
    }
}
