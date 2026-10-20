import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The season pass, the game's main progression and the main thing it sells (Josh, 19 Oct: "the 'battle pass' like
/// system with levels and paid/free journies along it"), redrawn on 20 Oct (Josh: "the season pass section needs some
/// serious UI changes ... Needs to have a countdown to see how long left, the boxes need to be better and I think we
/// need more content in them"). Along the top: the season, the days left to its real last day (a calendar page that
/// turns orange in the last three days; worked out from the season's dates each time the page opens, never a running
/// timer), the tier and the XP to the next, Claim all. On the left a showcase: whichever box was tapped, big, with its
/// rarity, track and tier, what else is in it, and its Claim (or what opens it); Get Premium under it. On the right two
/// lanes of boxes along one rope: the free track's twenty in a cream lane, the premium track's thirty in a plum one,
/// the player's cat on the rope where they have got to. Each box shows its rarity by word and diamonds (never by colour
/// alone), its picture large, a second item or bonus Beans when it holds them, and whether it is not reached yet, ready
/// (glowing, with Claim), claimed (ticked) or Premium's (padlocked). Get Premium opens a panel with every premium box,
/// what opens at once, the last day and the price before anything is bought (App Review 3.1.1); it is paid once, for
/// the season, and comes with Cat Club. Nothing is random. Drawn for a landscape phone and scaled to the screen; on a
/// taller screen the boxes grow and the season's whole set shows on a shelf under them.
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
    /// The box shown in the showcase (the top prize until another is tapped).
    @State private var selected: Box?
    /// The player's cat wearing the outfit in the showcase, by outfit id ("" for none).
    @State private var portraits: [String: CGImage] = [:]
    @State private var headshot: CGImage?
    @State private var prices = StorePrices.shared
    @Environment(\.controlFeedback) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A box on the road: a tier of a track.
    struct Box: Hashable {
        var track: PassTrack
        var tier: Int
    }

    /// What the celebration shows: one box claimed, several claimed at once, or Premium just bought.
    enum Celebration: Equatable {
        case box([PassReward], PassTrack)
        case many([PassReward])
        case premium(opened: Int)
    }

    var body: some View {
        GeometryReader { geometry in
            let s = Self.scale(for: geometry.size)
            let insets = geometry.safeAreaInsets
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.9), Color(red: 0.95, green: 0.88, blue: 0.78)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if let info {
                    VStack(spacing: 8 * s) {
                        header(info, s: s)
                        HStack(alignment: .top, spacing: 10 * s) {
                            showcase(info, s: s)
                                .frame(width: 178 * s)
                            road(info, s: s)
                        }
                    }
                    .padding(.horizontal, 10 * s)
                    .padding(.top, max(4 * s, 10 * s - insets.top))
                    .padding(.bottom, max(4 * s, 10 * s - insets.bottom))
                    if showPremium {
                        premiumPanel(info, s: s, insets: insets)
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
            .animation(.easeOut(duration: 0.18), value: selected)
        }
        .foregroundStyle(Theme.ink)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear(perform: reload)
        .task(id: info?.season.id) { await drawHeadshot() }
        .task(id: showcaseOutfit) { await drawPortrait(showcaseOutfit) }
        #if DEBUG
            // Screenshot runs: HOUSECAT_PASS=premium opens the panel, claim and claimall claim what waits, bought
            // shows Premium just bought; HOUSECAT_PASS_OWNED=1 records this season's pass first;
            // HOUSECAT_PASS_SELECT=free6|paid10 shows that box in the showcase.
            .task {
                let environment = ProcessInfo.processInfo.environment
                if environment["HOUSECAT_PASS_OWNED"] == "1", let season = info?.season {
                    GameSession.shared.recordPass(season.passID)
                    reload()
                }
                if let pick = environment["HOUSECAT_PASS_SELECT"], let tier = Int(pick.filter(\.isNumber)) {
                    selected = Box(track: pick.hasPrefix("paid") ? .paid : .free, tier: tier)
                }
                guard let info else { return }
                switch environment["HOUSECAT_PASS"] {
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

    /// The box in the showcase: the one tapped, else the top prize.
    private func shown(_ info: GameSession.PassInfo) -> Box {
        selected ?? Box(track: .paid, tier: Tuning.Pass.tiers)
    }

    private var showcaseOutfit: String {
        guard let info else { return "" }
        let box = shown(info)
        return info.season.rewards(track: box.track, tier: box.tier).first { $0.kind == .outfit }?.id ?? ""
    }

    // MARK: The top: the season, the days left, the tier

    private func header(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let step = PassRules.toNextTier(info.progress)
        return HStack(spacing: 8 * s) {
            CloseButton(action: close).scaleEffect(s * 0.92).frame(width: 34 * s, height: 34 * s)
            HStack(spacing: 10 * s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SEASON PASS").font(.system(size: 9 * s, weight: .heavy, design: .rounded)).tracking(1.8 * s)
                        .foregroundStyle(Self.orange)
                    Text(info.name).font(Theme.title(21 * s)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .layoutPriority(1)
                .accessibilityElement(children: .combine)
                countdown(info, s: s)
                Spacer(minLength: 4 * s)
                VStack(spacing: -2 * s) {
                    Text("TIER").font(.system(size: 8.5 * s, weight: .heavy, design: .rounded)).tracking(1.3 * s).opacity(0.9)
                    Text("\(info.tier)").font(.system(size: 20 * s, weight: .black, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.white)
                .frame(width: 48 * s, height: 40 * s)
                .background(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.94, green: 0.56, blue: 0.29), Self.orange], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Self.orangeLip, radius: 0, y: 3 * s)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tier \(info.tier) of \(Tuning.Pass.tiers)")
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(step.needed > 0 ? "\(step.into) / \(step.needed) XP to tier \(info.tier + 1)" : "Every tier reached")
                        .font(.system(size: 12 * s, weight: .heavy, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Bar(fraction: step.needed > 0 ? Double(step.into) / Double(step.needed) : 1, s: s)
                        .frame(height: 10 * s)
                    Text(info.tier < Tuning.Pass.freeTiers ? "Care, games and goals all count" : info.tier < Tuning.Pass.tiers ? "Free track done: Premium goes on to \(Tuning.Pass.tiers)" : "Well done. See you next season")
                        .font(.system(size: 9 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 158 * s)
                .accessibilityElement(children: .combine)
                if info.waiting > 0 {
                    Button {
                        claimAll(info)
                    } label: {
                        Text(info.waiting == 1 ? "Claim" : "Claim all (\(info.waiting))")
                            .font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 13 * s)
                            .frame(height: 32 * s)
                            .background(Capsule().fill(Self.orange))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .shadow(color: Self.orangeLip, radius: 0, y: 3 * s)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.leading, 12 * s)
            .padding(.trailing, 8 * s)
            .frame(height: 50 * s)
            .paper(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
        }
    }

    /// The days left to the season's real last day, from its dates: "12 days left · Ends Sun 1 November", orange in
    /// the last three days, "Last day · Ends tonight" on it.
    private func countdown(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let days = info.daysLeft
        let urgent = days <= Tuning.Pass.countdownUrgentDays
        let last = days <= 1
        return HStack(spacing: 7 * s) {
            VStack(spacing: 0) {
                (urgent ? Color(red: 0.89, green: 0.35, blue: 0.16) : Self.orange).frame(height: 9 * s)
                Text("\(max(days, 1))").font(.system(size: 15 * s, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 30 * s, height: 32 * s)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7 * s, style: .continuous).strokeBorder(urgent ? .white : Color(red: 0.89, green: 0.79, blue: 0.64), lineWidth: 1.5 * s))
            .shadow(color: urgent ? Self.orangeLip : Color(red: 0.85, green: 0.75, blue: 0.6), radius: 0, y: 2 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(last ? "Last day" : "\(days) days left").font(.system(size: 14 * s, weight: .black, design: .rounded))
                Text(last ? "Ends tonight" : "Ends \(Self.dayName(info.season.lastDay))")
                    .font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).opacity(0.75)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(urgent ? .white : Theme.ink)
        .padding(.leading, 5 * s)
        .padding(.trailing, 11 * s)
        .frame(height: 38 * s)
        .background(
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .fill(urgent ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.94, green: 0.54, blue: 0.24), Color(red: 0.85, green: 0.38, blue: 0.11)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color(red: 0.965, green: 0.92, blue: 0.83)))
        )
        .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(urgent ? .white : Color(red: 0.92, green: 0.84, blue: 0.71), lineWidth: 1.5 * s))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(last ? "Last day of \(info.name), it ends tonight" : "\(days) days left in \(info.name), it ends \(Self.dayName(info.season.lastDay))")
    }

    // MARK: The showcase (left)

    private func showcase(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        GeometryReader { panel in
            let box = shown(info)
            let rewards = info.season.rewards(track: box.track, tier: box.tier)
            let main = rewards.first
            let tall = panel.size.height > 360 * s
            let stageHeight = tall ? min(panel.size.height * 0.42, 230 * s) : 108 * s
            VStack(spacing: 6 * s) {
                if let main {
                    RarityTag(rarity: main.grade, s: s * 1.1)
                    stage(info, rewards: rewards, s: s)
                        .frame(height: stageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 13 * s, style: .continuous))
                    VStack(spacing: 3 * s) {
                        Text(Self.boxName(rewards)).font(Theme.title((tall ? 22 : 17) * s)).foregroundStyle(Theme.cream)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                        HStack(spacing: 4 * s) {
                            if box.track == .paid {
                                PaintedIcon("season_pass_ticket", size: 15 * s)
                            }
                            Text("\(box.track == .paid ? "Premium" : "Free") · tier \(box.tier)")
                        }
                        .font(.system(size: 10.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(GameHUD.gold)
                        ForEach(Array(rewards.dropFirst().enumerated()), id: \.offset) { _, extra in
                            HStack(spacing: 3 * s) {
                                if extra.kind == .beans {
                                    PaintedIcon("bean_coin", size: 15 * s)
                                }
                                Text("+ \(Self.name(extra))")
                            }
                            .font(.system(size: 10.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream)
                            .padding(.leading, 3 * s).padding(.trailing, 8 * s).padding(.vertical, 1.5 * s)
                            .background(Capsule().fill(.white.opacity(0.14)))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 2 * s)
                showcaseAction(info, box: box, s: s)
                if info.ownsPaid {
                    Label(owned.hasClub && !owned.passes.contains(info.season.passID) ? "Premium with Cat Club" : "Premium is yours", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12.5 * s, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 28 * s)
                        .background(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).fill(GameHUD.green))
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
                            .font(.system(size: 10.5 * s, weight: .bold, design: .rounded)).foregroundStyle(GameHUD.gold)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 9 * s)
            .padding(.top, 9 * s)
            .padding(.bottom, 9 * s)
            .frame(width: panel.size.width, height: panel.size.height)
            .background(Self.premiumFill, in: RoundedRectangle(cornerRadius: 20 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).strokeBorder(GameHUD.deepGold, lineWidth: 2.5 * s))
            .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
        }
        .accessibilityElement(children: .contain)
    }

    /// The showcase's stage: the season's own wallpaper and floor, the box's picture large on them (a wallpaper or
    /// floor shown as the stage itself), the player's cat in an outfit.
    private func stage(_ info: GameSession.PassInfo, rewards: [PassReward], s: CGFloat) -> some View {
        let surfaces = info.season.paidTrack.filter { $0.kind == .surface }.compactMap(\.id)
        let shownSurface = rewards.first { $0.kind == .surface }?.id
        let wallID = shownSurface.flatMap { $0.hasPrefix("floor") ? nil : $0 } ?? surfaces.first { !$0.hasPrefix("floor") }
        let floorID = shownSurface.flatMap { $0.hasPrefix("floor") ? $0 : nil } ?? surfaces.first { $0.hasPrefix("floor") }
        let main = rewards.first
        let glow = main.map { Self.glow($0.grade) } ?? .clear
        return GeometryReader { box in
            ZStack(alignment: .bottom) {
                Tiled(image: wallID.flatMap(Self.surfaceImage), tile: 70 * s)
                Tiled(image: floorID.flatMap(Self.surfaceImage), tile: 60 * s).frame(height: box.size.height * 0.26)
                RadialGradient(colors: [glow.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: box.size.width * 0.55)
                RadialGradient(colors: [.clear, Color(red: 0.12, green: 0.1, blue: 0.22).opacity(0.45)], center: .center, startRadius: box.size.width * 0.35, endRadius: box.size.width * 0.85)
                if let main {
                    if main.kind == .outfit, let id = main.id, let portrait = portraits[id] {
                        Image(decorative: portrait, scale: 1).resizable().interpolation(.high).scaledToFit()
                            .frame(height: box.size.height - 6 * s)
                            .shadow(color: .black.opacity(0.35), radius: 5 * s, y: 4 * s)
                            .padding(.bottom, 2 * s)
                    } else if main.kind == .surface {
                        Color.clear
                    } else {
                        let items = rewards.filter { $0.kind == .item || $0.kind == .outfit || $0.kind == .beans }.prefix(2)
                        HStack(alignment: .bottom, spacing: 4 * s) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, reward in
                                if reward.kind != .beans || items.count == 1 {
                                    RewardPicture(reward: reward, s: s * (index == 0 ? 2.1 : 1.3))
                                        .frame(width: box.size.width * (index == 0 ? 0.62 : 0.34), height: box.size.height * (index == 0 ? 0.8 : 0.52))
                                }
                            }
                        }
                        .padding(.bottom, 8 * s)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The showcase's own action for its box: Claim, or what it is waiting for.
    @ViewBuilder
    private func showcaseAction(_ info: GameSession.PassInfo, box: Box, s: CGFloat) -> some View {
        let claimed = info.progress.claimed(box.track).contains(box.tier)
        let ready = (box.track == .free ? info.claimableFree : info.claimablePaid).contains(box.tier)
        let locked = box.track == .paid && !info.ownsPaid
        if claimed {
            Label("Claimed, yours to keep", systemImage: "checkmark")
                .font(.system(size: 11.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.71, green: 0.94, blue: 0.66))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 30 * s)
                .background(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(GameHUD.green.opacity(0.25)))
        } else if ready {
            Button {
                feedback.tap()
                claim(info, track: box.track, tier: box.tier)
            } label: {
                Text("Claim").font(.system(size: 14 * s, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 32 * s)
                    .background(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.6, blue: 0.32), Self.orange], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: Self.orangeLip, radius: 0, y: 3 * s)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Claim tier \(box.tier), \(Self.boxName(info.season.rewards(track: box.track, tier: box.tier)))")
        } else {
            let reached = box.tier <= info.tier
            Text(reached && locked ? "Opens with Premium" : "Reach tier \(box.tier) · \(box.tier - info.tier) to go")
                .font(.system(size: 11.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.8))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 30 * s)
                .overlay(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).strokeBorder(Theme.cream.opacity(0.3), lineWidth: 1.5 * s))
        }
    }

    /// The player's cat wearing an outfit for the showcase, drawn once an outfit.
    private func drawPortrait(_ outfitID: String) async {
        guard !outfitID.isEmpty, portraits[outfitID] == nil, let look = GameSession.shared.cat?.look,
              let outfit = GameWorld.content?.outfits.outfits.first(where: { $0.id == outfitID })
        else { return }
        portraits[outfitID] = CatScreens.portrait(look, outfit: outfit)
    }

    /// The player's cat's face for the rope, once a season.
    private func drawHeadshot() async {
        guard headshot == nil, let look = GameSession.shared.cat?.look else { return }
        headshot = CatScreens.headshot(look)
    }

    // MARK: The road (right)

    private func road(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        GeometryReader { area in
            let rope = 30 * s, rowPad = 6 * s, gap = 8 * s, label = 26 * s
            let boxHeight = min(((area.size.height - rope - 2 * rowPad) / 2).rounded(.down), 184 * s)
            let boxWidth = min(max(boxHeight * 0.74, 100 * s), 136 * s)
            let roadHeight = boxHeight * 2 + rope + 2 * rowPad
            let spare = area.size.height - roadHeight
            VStack(alignment: .leading, spacing: 12 * s) {
                ZStack(alignment: .topLeading) {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: gap) {
                                ForEach(1 ... Tuning.Pass.tiers, id: \.self) { tier in
                                    let width = tier == Tuning.Pass.tiers ? boxWidth * 2 + gap : boxWidth
                                    VStack(spacing: 0) {
                                        freeCell(info, tier: tier, size: CGSize(width: width, height: boxHeight), s: s)
                                        ropeSegment(info, tier: tier, s: s).frame(height: rope)
                                        boxCell(info, track: .paid, tier: tier, size: CGSize(width: width, height: boxHeight), s: s)
                                    }
                                    .frame(width: width)
                                    .id(tier)
                                }
                            }
                            .padding(.vertical, rowPad)
                            .padding(.leading, label + 8 * s)
                            .padding(.trailing, 22 * s)
                            .background(alignment: .topLeading) {
                                // The two lanes: cream for the free track, plum for the premium one.
                                VStack(spacing: rope - 8 * s) {
                                    RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(Color(red: 1, green: 0.97, blue: 0.93).opacity(0.55))
                                        .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
                                        .frame(height: boxHeight + 8 * s)
                                    RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(Self.premiumFill).opacity(0.9)
                                        .frame(height: boxHeight + 8 * s)
                                }
                                .padding(.top, rowPad - 4 * s)
                                .padding(.leading, label + 2 * s)
                            }
                        }
                        .onAppear {
                            // The first box waiting, else the tier being climbed, comes into view.
                            let focus = (info.claimableFree + info.claimablePaid).min() ?? info.tier + 1
                            if focus > 2 {
                                reader.scrollTo(min(focus, Tuning.Pass.tiers) - 1, anchor: .leading)
                            }
                        }
                    }
                    // The lanes' labels stay put while the road scrolls.
                    VStack(spacing: rope) {
                        laneLabel("FREE", premium: false, locked: false, s: s).frame(height: boxHeight)
                        laneLabel("PREMIUM", premium: true, locked: !info.ownsPaid, s: s).frame(height: boxHeight)
                    }
                    .frame(width: label)
                    .padding(.vertical, rowPad)
                    // More road to the right.
                    LinearGradient(colors: [Color(red: 0.95, green: 0.88, blue: 0.78).opacity(0), Color(red: 0.95, green: 0.88, blue: 0.78).opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 22 * s, height: roadHeight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)
                }
                .frame(height: roadHeight)
                if spare >= 92 * s {
                    shelf(info, s: s)
                        .frame(height: min(spare - 12 * s, 132 * s))
                        .padding(.leading, label + 2 * s)
                }
            }
        }
    }

    private func laneLabel(_ text: String, premium: Bool, locked: Bool, s: CGFloat) -> some View {
        VStack(spacing: 6 * s) {
            if premium {
                PaintedIcon(locked ? "padlock" : "season_pass_ticket", size: 18 * s)
            }
            Text(text)
                .font(.system(size: 10.5 * s, weight: .black, design: .rounded)).tracking(1.8 * s)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 20 * s, height: (premium ? 74 : 40) * s)
        }
        .foregroundStyle(premium ? GameHUD.gold : Color(red: 0.54, green: 0.42, blue: 0.33))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(premium ? AnyShapeStyle(Self.premiumFill) : AnyShapeStyle(Theme.cream), in: RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(premium ? GameHUD.deepGold : Theme.rim, lineWidth: premium ? 2 * s : 1))
        .accessibilityHidden(true)
    }

    /// The free lane: a box to tier twenty, then quiet slots, the first saying the free track is done.
    @ViewBuilder
    private func freeCell(_ info: GameSession.PassInfo, tier: Int, size: CGSize, s: CGFloat) -> some View {
        if tier <= Tuning.Pass.freeTiers {
            boxCell(info, track: .free, tier: tier, size: size, s: s)
        } else {
            VStack(spacing: 6 * s) {
                if tier == Tuning.Pass.freeTiers + 1 {
                    PaintedIcon("star_rosette", size: 40 * s)
                    Text(info.tier >= Tuning.Pass.freeTiers ? "Free track done" : "Free track ends at \(Tuning.Pass.freeTiers)")
                        .font(Theme.title(13.5 * s)).multilineTextAlignment(.center)
                    Text("Premium carries on to \(Tuning.Pass.tiers)").font(.system(size: 9.5 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                } else {
                    PaintedIcon("season_pass_ticket", size: 28 * s).opacity(0.35).saturation(0.5)
                    Text("Premium only").font(.system(size: 9.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft.opacity(0.75))
                }
            }
            .padding(.horizontal, 8 * s)
            .frame(width: size.width, height: size.height)
            .overlay(RoundedRectangle(cornerRadius: 15 * s, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5 * s, dash: [5 * s, 4 * s])).foregroundStyle(Theme.rim))
            .accessibilityElement(children: .combine)
        }
    }

    private func boxCell(_ info: GameSession.PassInfo, track: PassTrack, tier: Int, size: CGSize, s: CGFloat) -> some View {
        let rewards = info.season.rewards(track: track, tier: tier)
        let ready = (track == .free ? info.claimableFree : info.claimablePaid).contains(tier)
        let box = Box(track: track, tier: tier)
        return RewardBox(
            rewards: rewards,
            tier: tier,
            premium: track == .paid,
            claimed: info.progress.claimed(track).contains(tier),
            claimable: ready,
            locked: track == .paid && !info.ownsPaid,
            reached: tier <= info.tier,
            selected: shown(info) == box,
            grand: track == .paid && tier == Tuning.Pass.tiers,
            s: s,
            select: {
                feedback.tap()
                selected = box
            },
            claim: {
                feedback.tap()
                selected = box
                claim(info, track: track, tier: tier)
            }
        )
        .frame(width: size.width, height: size.height)
    }

    /// The rope between the lanes: filled to the tier reached and part way through the one being climbed, each tier's
    /// number on a medallion, the player's cat where they have got to, and where the free track ends.
    private func ropeSegment(_ info: GameSession.PassInfo, tier: Int, s: CGFloat) -> some View {
        let step = PassRules.toNextTier(info.progress)
        let climbing = tier == info.tier + 1 && step.needed > 0
        let fill: Double = tier <= info.tier ? 1 : climbing ? Double(step.into) / Double(step.needed) : 0
        let reached = tier <= info.tier
        return GeometryReader { box in
            let along = box.size.width + 8 * s
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.9, green: 0.83, blue: 0.71))
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.97, green: 0.7, blue: 0.37), Self.orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: along * (tier == 1 && fill == 0 ? 0 : fill))
                }
                // Across the column and half the gap either side, so the segments meet; the top prize's column is
                // twice as wide, its rope ends at its middle.
                .frame(width: along, height: 8 * s)
                .offset(x: -4 * s)
                Text("\(tier)")
                    .font(.system(size: 13 * s, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(reached ? .white : Color(red: 0.54, green: 0.42, blue: 0.33))
                    .frame(width: 28 * s, height: 28 * s)
                    .background(Circle().fill(reached ? AnyShapeStyle(Self.orange) : AnyShapeStyle(Theme.cream)))
                    .overlay(Circle().strokeBorder(reached ? .white : Color(red: 0.9, green: 0.83, blue: 0.71), lineWidth: 2 * s))
                    .position(x: box.size.width / 2, y: box.size.height / 2)
                if tier == Tuning.Pass.freeTiers {
                    Text(info.tier >= tier ? "FREE DONE" : "FREE ENDS")
                        .font(.system(size: 7.5 * s, weight: .black, design: .rounded)).tracking(0.4 * s)
                        .foregroundStyle(Self.orange)
                        .fixedSize()
                        .padding(.horizontal, 5 * s).padding(.vertical, 2 * s)
                        .background(Capsule().fill(Theme.cream))
                        .overlay(Capsule().strokeBorder(Color(red: 0.9, green: 0.83, blue: 0.71), lineWidth: 1))
                        .position(x: box.size.width / 2 + 14 * s + 26 * s, y: box.size.height / 2)
                }
                // The player's cat at the head of the fill.
                if climbing || (info.tier == 0 && tier == 1) {
                    CatMarker(headshot: headshot, s: s)
                        .position(x: max(16 * s, along * fill - 4 * s), y: box.size.height / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Under the road on a tall screen: the season's whole set, what has been claimed ticked.
    private func shelf(_ info: GameSession.PassInfo, s: CGFloat) -> some View {
        let rewards = (PassTrack.allCases.flatMap { track in info.season.track(track).map { (track, $0) } })
            .filter { $0.1.kind != .beans }
        let mine = rewards.filter { info.progress.claimed($0.0).contains($0.1.tier) }.count
        return VStack(alignment: .leading, spacing: 6 * s) {
            HStack {
                Text("THE \(info.name.uppercased()) SET").font(.system(size: 9 * s, weight: .heavy, design: .rounded)).tracking(1.6 * s)
                    .foregroundStyle(Self.orange)
                Spacer()
                Text("\(mine) of \(rewards.count) yours").font(.system(size: 12 * s, weight: .heavy, design: .rounded))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6 * s) {
                    ForEach(Array(rewards.enumerated()), id: \.offset) { _, entry in
                        let reward = entry.1
                        let have = info.progress.claimed(entry.0).contains(reward.tier)
                        RewardPicture(reward: reward, s: s * 0.95)
                            .frame(width: 46 * s, height: 50 * s)
                            .saturation(have ? 1 : 0)
                            .opacity(have ? 1 : 0.4)
                            .frame(width: 58 * s)
                            .frame(maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).fill(have ? Self.glow(reward.grade).opacity(0.35) : Color(red: 0.95, green: 0.89, blue: 0.81)))
                            .overlay(alignment: .topTrailing) {
                                if have {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12 * s)).foregroundStyle(.white, GameHUD.green).padding(2 * s)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 9 * s)
        .paper(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The \(info.name) set: \(mine) of \(rewards.count) yours")
    }

    // MARK: Claiming

    private func claim(_ info: GameSession.PassInfo, track: PassTrack, tier: Int) {
        if track == .paid {
            GameSession.shared.recordPremium(club: owned.hasClub, passes: owned.passes)
        }
        let rewards = GameSession.shared.claim(season: info.season.id, track: track, tier: tier)
        reload()
        if !rewards.isEmpty {
            celebrate(.box(rewards, track))
        }
    }

    private func claimAll(_ info: GameSession.PassInfo) {
        feedback.tap()
        if !info.claimablePaid.isEmpty {
            GameSession.shared.recordPremium(club: owned.hasClub, passes: owned.passes)
        }
        let boxes = info.claimableFree.map { Box(track: .free, tier: $0) } + info.claimablePaid.map { Box(track: .paid, tier: $0) }
        let claimed = GameSession.shared.claimAll(info)
        reload()
        if boxes.count == 1, let box = boxes.first, !claimed.isEmpty {
            celebrate(.box(claimed, box.track))
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
                case let .box(rewards, track):
                    if let reward = rewards.first {
                        RewardPicture(reward: reward, s: s * 2.6).frame(width: 220 * s, height: 140 * s)
                            .shadow(color: .black.opacity(0.4), radius: 10 * s, y: 8 * s)
                        HStack(spacing: 6 * s) {
                            Text("TIER \(reward.tier) · \(track == .paid ? "PREMIUM" : "FREE")")
                                .font(.system(size: 11 * s, weight: .black, design: .rounded)).tracking(2.4 * s).foregroundStyle(GameHUD.gold)
                            RarityTag(rarity: reward.grade, s: s)
                        }
                        Text(Self.name(reward)).font(Theme.title(30 * s)).foregroundStyle(Theme.cream)
                        Text(rewards.count > 1 ? "And " + ListFormatter.localizedString(byJoining: rewards.dropFirst().map { Self.name($0) }) + ". " + Self.blurb(reward) : Self.blurb(reward))
                            .font(.system(size: 13 * s, weight: .bold, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.85))
                        HStack(spacing: 14 * s) {
                            celebrationButton(info.waiting > 0 ? "Next reward" : "Lovely", cream: true, s: s) {
                                celebration = nil
                                if let first = info.claimableFree.first {
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
                    }
                case let .many(rewards):
                    Text("\(rewards.count) REWARDS CLAIMED").font(.system(size: 11 * s, weight: .black, design: .rounded)).tracking(2.4 * s).foregroundStyle(GameHUD.gold)
                    HStack(spacing: 8 * s) {
                        ForEach(Array(rewards.filter { $0.kind != .beans }.prefix(6).enumerated()), id: \.offset) { _, reward in
                            RewardPicture(reward: reward, s: s * 1.2).frame(width: 74 * s, height: 64 * s)
                        }
                    }
                    let beans = rewards.filter { $0.kind == .beans }.compactMap(\.amount).reduce(0, +)
                    let more = rewards.filter { $0.kind != .beans }.count - 6
                    if more > 0 {
                        Text("and \(more) more").font(.system(size: 13 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream.opacity(0.85))
                    }
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
                    Text(opened > 0 ? "\(opened) premium boxes are ready to claim now." : "Every premium box opens as you climb.")
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

    private func premiumPanel(_ info: GameSession.PassInfo, s: CGFloat, insets: EdgeInsets) -> some View {
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
                    Text("\(contents.items) more items").font(Theme.title(23 * s)).foregroundStyle(Theme.cream)
                    panelLine("sofa_for_furniture", Self.piecesLine(contents), s: s)
                    panelLine("cat_face", Self.outfitsLine(info), s: s)
                    panelLine("bean_coin", "\(contents.beans.formatted()) Beans, on top of the free track's", s: s)
                    panelLine(
                        "xp_star",
                        opens > 0 ? "You're at tier \(info.tier): \(opens) open at once (ticked)" : "Each opens as you climb, tier by tier",
                        s: s
                    )
                    panelLine("calendar", "Ends \(Self.dayName(last)) (\(info.daysLeft <= 1 ? "today" : "\(info.daysLeft) days")). Claim before then; what you claim is yours to keep.", s: s)
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
                    ForEach(info.season.tiers(.paid), id: \.self) { tier in
                        let rewards = info.season.rewards(track: .paid, tier: tier)
                        let reward = rewards.first ?? PassReward(tier: tier, kind: .beans)
                        let open = info.openAtOnce.contains(tier)
                        VStack(spacing: 2 * s) {
                            RewardPicture(reward: reward, s: s * 0.62).frame(height: 38 * s)
                            Text(Self.name(reward)).font(.system(size: 8.5 * s, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cream)
                                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72 * s)
                        .background(RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(Self.glow(reward.grade).opacity(reward.kind == .beans ? 0.1 : 0.22)))
                        .overlay(RoundedRectangle(cornerRadius: 11 * s, style: .continuous)
                            .strokeBorder(open ? Self.orange : Self.glow(reward.grade).opacity(reward.kind == .beans ? 0.3 : 0.75), lineWidth: open ? 2 * s : 1))
                        .overlay(alignment: .topLeading) {
                            Text("\(tier)").font(.system(size: 8.5 * s, weight: .black, design: .rounded)).foregroundStyle(GameHUD.gold.opacity(0.85))
                                .padding(4 * s)
                        }
                        .overlay(alignment: .topTrailing) {
                            if open {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 12 * s)).foregroundStyle(.white, Self.orange).padding(3 * s)
                            } else if rewards.count > 1 {
                                Text("+\(rewards.count - 1)").font(.system(size: 8 * s, weight: .black, design: .rounded)).foregroundStyle(Color(red: 0.29, green: 0.2, blue: 0.38))
                                    .padding(.horizontal, 4 * s).padding(.vertical, 1 * s)
                                    .background(Capsule().fill(GameHUD.gold)).padding(3 * s)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tier \(tier): \(Self.boxName(rewards))\(open ? ", opens at once" : "")")
                    }
                }
            }
            .padding(18 * s)
            .background(Self.premiumFill, in: RoundedRectangle(cornerRadius: 26 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26 * s, style: .continuous).strokeBorder(GameHUD.deepGold, lineWidth: 2.5 * s))
            .overlay(alignment: .topTrailing) {
                CloseButton { showPremium = false }.scaleEffect(s * 0.85).offset(x: 6 * s, y: -6 * s)
            }
            // Close sits over the panel's corner, so the panel keeps clear of a screen edge with no safe area.
            .padding(.vertical, max(12 * s, 26 * s - insets.top))
            .padding(.horizontal, max(8 * s, 24 * s - min(insets.leading, insets.trailing)))
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
            Text(title).font(.system(size: 15 * s, weight: .black, design: .rounded)).foregroundStyle(.white)
                .shadow(color: Color(red: 0.43, green: 0.24, blue: 0).opacity(0.45), radius: 0, y: 1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38 * s)
                .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous)
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

    /// Each rarity's colour (the gift book's four), always beside its word.
    static func glow(_ rarity: PassRarity) -> Color {
        switch rarity {
        case .common: Color(red: 0.95, green: 0.87, blue: 0.74)
        case .uncommon: Color(red: 0.66, green: 0.86, blue: 0.61)
        case .rare: Color(red: 0.56, green: 0.75, blue: 0.96)
        case .legendary: Color(red: 1, green: 0.78, blue: 0.35)
        }
    }

    static func tagColour(_ rarity: PassRarity) -> Color {
        switch rarity {
        case .common: Color(red: 0.62, green: 0.53, blue: 0.4)
        case .uncommon: Color(red: 0.29, green: 0.55, blue: 0.28)
        case .rare: Color(red: 0.23, green: 0.44, blue: 0.72)
        case .legendary: Color(red: 0.76, green: 0.45, blue: 0.07)
        }
    }

    /// The season's end for the room's badge and the shop: "Ends Sun 1 November", with the days left in its last week.
    static func endsLine(_ info: GameSession.PassInfo) -> String {
        let ends = "Ends \(dayName(info.season.lastDay))"
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

    /// A box's name: its main reward, and a second item after a plus ("Black cat portrait + Cat doorstop"); bonus
    /// Beans are shown beside it, not named.
    static func boxName(_ rewards: [PassReward]) -> String {
        let named = rewards.filter { $0.kind != .beans }
        return (named.isEmpty ? Array(rewards.prefix(1)) : named).map { name($0) }.joined(separator: " + ")
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

/// A box's rarity, by word and diamonds as well as colour (CLAUDE.md: rarity is never shown by colour alone).
private struct RarityTag: View {
    let rarity: PassRarity
    let s: CGFloat

    var body: some View {
        HStack(spacing: 1.5 * s) {
            ForEach(0 ..< rarity.rank, id: \.self) { _ in
                Image(systemName: "diamond.fill").font(.system(size: 5.5 * s, weight: .black))
            }
            Text(rarity.rawValue.uppercased()).font(.system(size: 7.5 * s, weight: .black, design: .rounded)).tracking(0.6 * s)
                .padding(.leading, 2 * s)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5 * s)
        .frame(height: 14 * s)
        .background(Capsule().fill(PassView.tagColour(rarity)))
        .accessibilityLabel(rarity.rawValue)
    }
}

/// One box on the road: its rarity, its picture (two for two items), bonus Beans, its name, and Claim, a tick, a
/// padlock or its tier. A tap shows it in the showcase; its Claim claims it.
private struct RewardBox: View {
    let rewards: [PassReward]
    let tier: Int
    let premium: Bool
    let claimed: Bool
    let claimable: Bool
    let locked: Bool
    let reached: Bool
    let selected: Bool
    let grand: Bool
    let s: CGFloat
    let select: () -> Void
    let claim: () -> Void
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let main = rewards.first ?? PassReward(tier: tier, kind: .beans)
        let items = rewards.filter { $0.kind != .beans }
        let bonus = rewards.dropFirst().first { $0.kind == .beans }
        let two = items.count > 1
        let shape = RoundedRectangle(cornerRadius: 15 * s, style: .continuous)
        let ink = premium ? Theme.cream : Theme.ink
        Button(action: select) {
            GeometryReader { box in
                let artHeight = box.size.height - 22 * s - 50 * s
                ZStack(alignment: .top) {
                    // The rarity's glow behind the picture, rays for a legendary one.
                    RadialGradient(colors: [PassView.glow(main.grade).opacity(main.kind == .beans ? (premium ? 0.3 : 0.5) : (premium ? 0.6 : 0.8)), .clear], center: UnitPoint(x: 0.5, y: 0.44), startRadius: 0, endRadius: box.size.width * 0.62)
                    if main.grade == .legendary {
                        Rays(s: s).frame(width: box.size.width * 1.6, height: box.size.width * 1.6).position(x: box.size.width / 2, y: box.size.height * 0.44)
                    }
                    VStack(spacing: 0) {
                        HStack {
                            if main.kind != .beans {
                                RarityTag(rarity: main.grade, s: s)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 22 * s)
                        .padding(.horizontal, 6 * s)
                        .padding(.top, 2 * s)
                        ZStack(alignment: .bottomTrailing) {
                            if two {
                                HStack(alignment: .bottom, spacing: 2 * s) {
                                    RewardPicture(reward: items[0], s: s * 1.05).frame(width: box.size.width * 0.58, height: artHeight * 0.92)
                                    RewardPicture(reward: items[1], s: s * 0.75).frame(width: box.size.width * 0.36, height: artHeight * 0.62)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                RewardPicture(reward: main, s: s * (grand ? 1.7 : 1.25))
                                    .frame(width: box.size.width * 0.84, height: artHeight)
                                    .frame(maxWidth: .infinity)
                            }
                            if two {
                                Text("2 ITEMS").font(.system(size: 8 * s, weight: .black, design: .rounded))
                                    .foregroundStyle(premium ? Color(red: 0.29, green: 0.2, blue: 0.38) : .white)
                                    .padding(.horizontal, 5 * s).frame(height: 15 * s)
                                    .background(Capsule().fill(premium ? GameHUD.gold : PassView.orange))
                                    .padding(.trailing, 5 * s)
                            } else if let bonus {
                                HStack(spacing: 1 * s) {
                                    PaintedIcon("bean_coin", size: 16 * s)
                                    Text("+\(bonus.amount ?? 0)").font(.system(size: 10 * s, weight: .black, design: .rounded)).foregroundStyle(Theme.ink)
                                }
                                .padding(.leading, 2 * s).padding(.trailing, 6 * s).frame(height: 20 * s)
                                .background(Capsule().fill(.white))
                                .overlay(Capsule().strokeBorder(Color(red: 0.91, green: 0.81, blue: 0.64), lineWidth: 1))
                                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                                .padding(.trailing, 5 * s)
                            }
                        }
                        .frame(height: artHeight)
                        .saturation(claimed ? 0.35 : 1)
                        .opacity(claimed ? 0.6 : 1)
                        Text(PassView.boxName(rewards))
                            .font(.system(size: (two ? 9 : 10.5) * s, weight: .heavy, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
                            .frame(height: 24 * s)
                            .padding(.horizontal, 5 * s)
                            .opacity(claimed ? 0.65 : 1)
                        state.frame(height: 22 * s)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: box.size.width, height: box.size.height)
            }
            .background(premium ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.2, green: 0.31, blue: 0.42), Color(red: 0.25, green: 0.23, blue: 0.38), Color(red: 0.29, green: 0.2, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.98, blue: 0.945), Color(red: 0.965, green: 0.915, blue: 0.83)], startPoint: .top, endPoint: .bottom)), in: shape)
            .clipShape(shape)
            .overlay { if locked { shape.fill(Color(red: 0.08, green: 0.05, blue: 0.12).opacity(0.28)) } }
            .overlay { if claimed { shape.fill((premium ? Color(red: 0.12, green: 0.09, blue: 0.16) : Theme.cream).opacity(0.3)) } }
            .overlay(shape.strokeBorder(premium ? GameHUD.deepGold : (main.kind == .beans ? Color(red: 0.92, green: 0.85, blue: 0.74) : PassView.glow(main.grade)), lineWidth: 2 * s))
            .overlay {
                if claimable {
                    shape.strokeBorder(premium ? GameHUD.gold : PassView.orange, lineWidth: 3 * s)
                        .shadow(color: (premium ? GameHUD.gold : PassView.orange).opacity(glowing ? 0.95 : 0.45), radius: (glowing ? 11 : 5) * s)
                        .padding(-3 * s)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 19 * s, style: .continuous).strokeBorder(.white, lineWidth: 2.5 * s)
                        .padding(-5 * s)
                }
            }
            .overlay(alignment: .top) {
                if grand {
                    Text("TOP PRIZE").font(.system(size: 9 * s, weight: .black, design: .rounded)).tracking(1.2 * s)
                        .foregroundStyle(Color(red: 0.29, green: 0.2, blue: 0.38))
                        .padding(.horizontal, 9 * s).frame(height: 17 * s)
                        .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), Color(red: 0.91, green: 0.66, blue: 0.23)], startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Color(red: 0.66, green: 0.44, blue: 0.07), radius: 0, y: 2 * s)
                        .offset(y: -9 * s)
                }
            }
            .shadow(color: Theme.shadow, radius: 3 * s, y: 2 * s)
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .bottom) {
            // Claim is its own button over the box, so a tap on the box only shows it.
            if claimable {
                Button(action: claim) {
                    Text("Claim").font(.system(size: 11.5 * s, weight: .black, design: .rounded))
                        .foregroundStyle(premium ? Color(red: 0.29, green: 0.2, blue: 0.38) : .white)
                        .padding(.horizontal, 16 * s).frame(height: 22 * s)
                        .background(Capsule().fill(premium ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), Color(red: 0.91, green: 0.66, blue: 0.23)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.6, blue: 0.32), PassView.orange], startPoint: .top, endPoint: .bottom))))
                        .shadow(color: premium ? Color(red: 0.66, green: 0.44, blue: 0.07) : PassView.orangeLip, radius: 0, y: 2 * s)
                }
                .buttonStyle(PressStyle())
                .padding(.bottom, 6 * s)
                .accessibilityLabel("Tier \(tier) \(premium ? "premium" : "free"), \(PassView.boxName(rewards)), ready to claim")
            }
        }
        .onAppear {
            guard claimable, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glowing = true }
        }
        .accessibilityLabel("Tier \(tier), \(premium ? "premium" : "free"), \(main.grade.rawValue): \(PassView.boxName(rewards))\(rewards.count > 1 && items.count == 1 ? ", and \(PassView.name(bonus))" : "")")
        .accessibilityValue(claimed ? "claimed" : claimable ? "ready to claim" : locked ? "with Premium" : reached ? "" : "not reached yet")
        .accessibilityHint("Shows it")
    }

    @ViewBuilder
    private var state: some View {
        if claimed {
            HStack(spacing: 4 * s) {
                Image(systemName: "checkmark").font(.system(size: 9 * s, weight: .black)).foregroundStyle(.white)
                    .frame(width: 16 * s, height: 16 * s).background(Circle().fill(GameHUD.green))
                Text("Claimed").font(.system(size: 10.5 * s, weight: .black, design: .rounded))
                    .foregroundStyle(premium ? Color(red: 0.64, green: 0.9, blue: 0.58) : Color(red: 0.25, green: 0.56, blue: 0.23))
            }
        } else if claimable {
            Color.clear
        } else if locked {
            HStack(spacing: 3 * s) {
                PaintedIcon("padlock", size: 15 * s)
                Text("Premium").font(.system(size: 9.5 * s, weight: .black, design: .rounded)).foregroundStyle(GameHUD.gold)
            }
        } else {
            Text("Tier \(tier)").font(.system(size: 9.5 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(premium ? Theme.cream.opacity(0.55) : Theme.inkSoft.opacity(0.8))
        }
    }
}

/// Gold rays behind a legendary box's picture.
private struct Rays: View {
    let s: CGFloat

    var body: some View {
        ZStack {
            ForEach(0 ..< 16, id: \.self) { ray in
                Capsule()
                    .fill(LinearGradient(colors: [GameHUD.gold.opacity(0.4), GameHUD.gold.opacity(0)], startPoint: .bottom, endPoint: .top))
                    .frame(width: 9 * s, height: 70 * s)
                    .offset(y: -35 * s)
                    .rotationEffect(.degrees(Double(ray) * 22.5))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The player's cat on the rope where they have got to: its face in a ring (the cat-face icon until it is drawn).
private struct CatMarker: View {
    let headshot: CGImage?
    let s: CGFloat

    var body: some View {
        Group {
            if let headshot {
                Image(decorative: headshot, scale: 1).resizable().interpolation(.high).scaledToFill()
            } else {
                PaintedIcon("cat_face", size: 30 * s)
            }
        }
        .frame(width: 30 * s, height: 30 * s)
        .clipShape(Circle())
        .background(Circle().fill(Theme.cream))
        .overlay(Circle().strokeBorder(PassView.orange, lineWidth: 2.5 * s))
        .shadow(color: .black.opacity(0.3), radius: 3 * s, y: 2 * s)
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
