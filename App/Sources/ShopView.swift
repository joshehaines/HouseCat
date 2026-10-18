import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The shop (SPEC "Monetisation and the shop"), laid out like a builder game's shop: a rail of sections down
/// the left, big illustrated offers in a row, a Cat Club page that shows everything membership holds, a detail
/// panel before buying and a celebration after. Three kinds of product (Josh, 18 Oct): Bean packs, the one
/// currency, bought like a builder game's gems; room looks, a whole room in one tap; and Cat Club. Outfits are
/// bought with Beans, and when Beans fall short Buy becomes Top up. Every price is StoreKit's own, a Bean price
/// shows what it comes to in money, nothing is random, nothing counts down (a limited look gives its real last
/// day), the two Cat Club plans sit side by side with the full renewal terms, and Close is always on screen.
struct ShopView: View {
    static func monthName(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1) % 12]
    }

    enum Section: String, CaseIterable, Identifiable {
        case featured, beans, looks, club, outfits

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .featured: "Featured"
            case .beans: "Beans"
            case .looks: "Room looks"
            case .club: "Cat Club"
            case .outfits: "Outfits"
            }
        }

        var icon: String {
            switch self {
            case .featured: "xp_star"
            case .beans: "bean_coin"
            case .looks: "sofa_for_furniture"
            case .club: "cat_face"
            case .outfits: "decorate_paintbrush"
            }
        }
    }

    /// Something to buy, as a tile and its detail panel.
    struct Offer: Identifiable, Equatable {
        struct Line: Equatable {
            var icon: String
            var text: String
        }

        var id: String
        var title: String
        /// One illustration, or a few pieces of furniture side by side.
        var art: [String]
        var ribbon: String?
        var contents: [Line]
        var note: String?
        var tint: Color
        var isClub = false
        /// Bought with Beans (an outfit): its price in Beans, and the outfit.
        var beanPrice: Int?
        var outfitID: String?
        /// A room look.
        var bundle: BundlesFile.Bundle?
    }

    /// Beans short for something, and what to do once topped up.
    struct TopUpRequest: Identifiable {
        let id = UUID()
        var need: Int
        var purpose: String
        var then: @MainActor () -> Void
    }

    /// Nil when StoreKit is off (command-line screenshot runs): debug builds then show the catalogue's own UK
    /// prices, and Buy plays the celebration as a preview without charging anything.
    let store: (any EntitlementService)?
    let content: ContentBundle?
    /// "Try it in your room" and "Add the whole room": the shop closes and the room does it.
    var tryLook: ((BundlesFile.Bundle) -> Void)?
    var addLook: ((BundlesFile.Bundle) -> Void)?
    @State private var prices = StorePrices.shared
    @State private var message: String?
    @State private var buying: String?
    @State private var owned = Entitlements.none
    @State private var beans = 0
    @State private var section: Section = .featured
    @State private var detail: Offer?
    @State private var celebrating: Offer?
    @State private var topUp: TopUpRequest?
    @State private var yearly = true
    @State private var refunding = false
    /// Everything is laid out for a landscape phone and scaled up to fill a bigger screen.
    @State private var s: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.controlFeedback) private var feedback

    private var session: GameSession {
        GameSession.shared
    }

    var body: some View {
        // The scale comes from the screen alone, never from what it sizes (a feedback loop otherwise).
        GeometryReader { proxy in
            let screen = CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            shop
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onChange(of: screen, initial: true) { _, screen in
                    let fit = min(screen.height / Tuning.Shop.designHeight, screen.width / Tuning.Shop.designWidth)
                    s = (min(Tuning.Shop.largestScale, max(1, fit)) * 20).rounded(.down) / 20
                }
        }
    }

    private var shop: some View {
        ZStack {
            page.ignoresSafeArea()
            HStack(spacing: 0) {
                // Offers slide under the rail, which keeps the page behind it.
                rail
                    .background(alignment: .trailing) {
                        page.ignoresSafeArea(edges: [.vertical, .leading])
                            .shadow(color: Theme.shadow, radius: 6 * s, x: 2 * s)
                    }
                    .zIndex(1)
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 22 * s) {
                            group(.featured) { featured }
                            group(.beans) { ForEach(beanOffers) { beanTile($0) } }
                            group(.looks) { ForEach(lookOffers) { tile($0) } }
                            group(.club) { clubPage }
                            group(.outfits) { outfitGrid }
                            footer
                        }
                        .padding(.horizontal, 16 * s)
                        .padding(.vertical, 12 * s)
                    }
                    .scrollClipDisabled()
                    // The row of offers sits in the middle of a tall screen.
                    .frame(height: (Tuning.Shop.tileHeight + 54) * s)
                    .frame(maxHeight: .infinity)
                    .onChange(of: section) { _, section in
                        withAnimation(.easeInOut(duration: 0.45)) { reader.scrollTo(section.id, anchor: .leading) }
                    }
                }
            }
            .overlay(alignment: .topTrailing) { balance.padding(14 * s) }
            if let detail {
                detailPanel(detail)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            if let celebrating {
                Celebration(offer: celebrating, scale: s) { self.celebrating = nil }
                    .transition(.opacity)
            }
            if let topUp {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { self.topUp = nil }
                    BeanTopUp(need: topUp.need, purpose: topUp.purpose, store: store) { bought in
                        self.topUp = nil
                        refresh()
                        if bought {
                            topUp.then()
                        }
                    }
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
        .environment(\.hudScale, s)
        .sheet(isPresented: $refunding) { RefundView { refunding = false } }
        .animation(.spring(duration: 0.35), value: detail)
        .animation(.easeOut(duration: 0.3), value: celebrating)
        .animation(.easeOut(duration: 0.25), value: topUp?.id)
        .task {
            Analytics.track(.shopOpened)
            refresh()
            await prices.load(store: store, content: content)
            if prices.unavailable {
                message = "The shop is not available right now."
            }
            #if DEBUG
                // Screenshot runs: HOUSECAT_SHOP=<section>, detail (the starter's panel), look (a room look's),
                // topup (short for an outfit) or celebrate (Cat Club's).
                if let wanted = ProcessInfo.processInfo.environment["HOUSECAT_SHOP"] {
                    try? await Task.sleep(for: .seconds(1))
                    if let open = Section(rawValue: wanted) {
                        section = open
                    } else if wanted == "detail" {
                        detail = starter
                    } else if wanted == "look" {
                        detail = lookOffers.first { $0.bundle?.room != .living } ?? lookOffers.first
                    } else if wanted == "topup" {
                        topUp = TopUpRequest(need: 900, purpose: "the Raincoat") {}
                    } else if wanted == "celebrate" {
                        celebrate(clubOffer)
                    }
                }
            #endif
        }
    }

    private var page: LinearGradient {
        LinearGradient(colors: [Theme.paper, Color(red: 0.95, green: 0.84, blue: 0.74)], startPoint: .top, endPoint: .bottom)
    }

    private func font(_ size: CGFloat, _ weight: Font.Weight = .semibold, rounded: Bool = false) -> Font {
        .system(size: size * s, weight: weight, design: rounded ? .rounded : .default)
    }

    private func refresh() {
        owned = store?.entitlements ?? .none
        beans = session.beans
    }

    /// The player's Beans, top right, as in a builder game's shop.
    private var balance: some View {
        HStack(spacing: 5 * s) {
            PaintedIcon("bean_coin", size: 24 * s)
            Text(beans.formatted()).font(font(16, .heavy, rounded: true)).monospacedDigit().contentTransition(.numericText())
            Button {
                feedback.tap()
                section = .beans
            } label: {
                Image(systemName: "plus").font(font(12, .black)).foregroundStyle(.white)
                    .frame(width: 22 * s, height: 22 * s)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Get Beans")
        }
        .padding(.leading, 10 * s)
        .padding(.trailing, 5 * s)
        .padding(.vertical, 5 * s)
        .paper(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(beans) Beans")
        .animation(.spring(duration: 0.4), value: beans)
    }

    // MARK: Prices and buying

    private func price(_ id: String) -> String? {
        prices.price(id)
    }

    /// Buys a real-money product (a Bean pack, the starter, a room look, Cat Club).
    private func buy(_ id: String, offer: Offer) {
        guard buying == nil else { return }
        buying = id
        Task {
            defer { buying = nil }
            switch await ShopPurchase.buy(id, store: store) {
            case .bought:
                refresh()
                detail = nil
                celebrate(offer)
            case .pending: message = "Waiting for approval."
            case .cancelled: break
            case .failed: message = "That purchase did not go through."
            }
        }
    }

    /// Buys an outfit with Beans, or offers a top-up for what is short (and then buys it).
    private func buyWithBeans(_ offer: Offer, gift: Bool = false) {
        guard let outfitID = offer.outfitID, let cost = offer.beanPrice else { return }
        let short = BeanPrices.shortfall(price: cost, balance: session.beans)
        if short > 0 {
            topUp = TopUpRequest(need: short, purpose: "the \(offer.title)") { buyWithBeans(offer, gift: gift) }
            return
        }
        guard session.buyOutfit(outfitID, gift: gift) else { return }
        refresh()
        detail = nil
        var shown = offer
        if gift {
            shown.contents = [.init(icon: "gift_box_with_a_ribbon", text: "Wrapped, for the next visit")]
        }
        celebrate(shown)
    }

    private func celebrate(_ offer: Offer) {
        Sound.play("ui_purchase_confirm", volume: Tuning.Sound.levelUp)
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        celebrating = offer
    }

    private func isOwned(_ offer: Offer) -> Bool {
        if offer.isClub {
            return owned.hasClub
        }
        if offer.id == StoreCatalog.starter {
            return owned.starter
        }
        if let bundle = offer.bundle {
            // Bought on this Apple Account, or by a co-owner (its pieces are in the shared save).
            return owned.bundles.contains(bundle.id) || session.state(at: session.now()).grantedBundles.values.contains(bundle.id)
        }
        if let outfit = offer.outfitID {
            return session.ownedOutfits.contains(outfit)
        }
        return false
    }

    // MARK: The rail and the groups

    private var rail: some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack(spacing: 6 * s) {
                PaintedIcon("shop_bag", size: 34 * s)
                Text("Shop").font(Theme.title(26 * s))
            }
            .padding(.bottom, 6 * s)
            ForEach(Section.allCases) { item in
                Button {
                    feedback.tap()
                    section = item
                } label: {
                    HStack(spacing: 8 * s) {
                        PaintedIcon(item.icon, size: 26 * s)
                        Text(item.title).font(font(15, .bold, rounded: true)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10 * s)
                    .padding(.vertical, 6 * s)
                    .background(Capsule().fill(section == item ? Theme.cream : .clear))
                    .overlay(Capsule().strokeBorder(section == item ? Theme.rim : .clear, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .foregroundStyle(section == item ? Theme.ink : Theme.inkSoft)
            }
            Spacer(minLength: 4 * s)
            CloseButton { dismiss() }.scaleEffect(s, anchor: .bottomLeading)
        }
        .padding(.leading, 14 * s)
        .padding(.vertical, 12 * s)
        .frame(width: 176 * s)
    }

    private func group(_ section: Section, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text(section.title.uppercased())
                .font(font(13, .heavy, rounded: true))
                .tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
            HStack(alignment: .top, spacing: 14 * s) { content() }
        }
        // A gap at the left once the rail scrolls a section in.
        .padding(.leading, 6 * s)
        .id(section.id)
    }

    // MARK: Offers

    private var starter: Offer {
        let pouch = StoreCatalog.beanPacks[1]
        let samePrice = prices.products[StoreCatalog.starter]?.price != nil
            && prices.products[StoreCatalog.starter]?.price == prices.products[pouch.id]?.price
        return Offer(
            id: StoreCatalog.starter,
            title: "Starter Pack",
            art: ["ui/shop/shop_starter.png"],
            ribbon: "Once only",
            contents: [
                .init(icon: "bean_coin", text: "\(Tuning.Beans.starterPack.formatted()) Beans"),
                .init(icon: "cat_face", text: "The knitted beanie"),
                .init(icon: "sofa_for_furniture", text: "An armchair"),
            ],
            note: samePrice ? "The same price as a pouch of \(pouch.beans.formatted()) Beans, once per household." : nil,
            tint: Color(red: 0.98, green: 0.8, blue: 0.6)
        )
    }

    private var clubOffer: Offer {
        Offer(
            id: StoreCatalog.clubYearly,
            title: "Cat Club",
            art: ["ui/shop/shop_club.png"],
            contents: [
                .init(icon: "bean_coin", text: "+20% Beans"),
                .init(icon: "house", text: "Rooms for half"),
                .init(icon: "season_pass_ticket", text: "Every paid track"),
            ],
            tint: Color(red: 0.42, green: 0.62, blue: 0.66),
            isClub: true
        )
    }

    /// The Bean packs, smallest first, each with how many more Beans a pound it gives than the smallest.
    private var beanOffers: [Offer] {
        StoreCatalog.beanPacks.map { pack in
            Offer(
                id: pack.id,
                title: pack.name,
                art: [BeanArt.path(pack.id)],
                ribbon: pack.id == StoreCatalog.beanPacks.last?.id ? "Best value" : prices.bonus(pack).map { "+\($0)% a pound" },
                contents: [.init(icon: "bean_coin", text: "+\(pack.beans.formatted()) Beans")],
                tint: Color(red: 0.98, green: 0.88, blue: 0.6)
            )
        }
    }

    /// The room looks: every one on sale, the limited one only during its sale (or for someone who has it).
    private var lookOffers: [Offer] {
        guard let content else { return [] }
        let items = Dictionary(uniqueKeysWithValues: content.catalogue.items.map { ($0.id, $0) })
        return content.bundles.bundles.compactMap { bundle in
            let sale = bundle.limited == true ? lookSale(bundle) : nil
            let offer = lookOffer(bundle, items: items, lastDay: sale?.lastDay)
            if bundle.limited == true, sale == nil, !isOwned(offer) {
                return nil
            }
            return offer
        }
    }

    private func lookOffer(_ bundle: BundlesFile.Bundle, items: [String: CatalogueFile.Item], lastDay: GameDay?) -> Offer {
        // The three biggest pieces, side by side.
        let pieces = bundle.items.compactMap { items[$0] }.sorted { $0.footprint.w * $0.footprint.d > $1.footprint.w * $1.footprint.d }
        let art = pieces.filter { $0.layer != .wall }.prefix(3).compactMap { $0.sprites["R"] ?? $0.sprites.values.first }
        var contents: [Offer.Line] = [.init(icon: "sofa_for_furniture", text: "\(bundle.items.count) pieces")]
        if !bundle.surfaces.isEmpty {
            contents.append(.init(icon: "wallpaper_roll", text: bundle.surfaces.count == 2 ? "Its wallpaper and floor" : "Its wallpaper"))
        }
        contents.append(.init(icon: "house", text: Visit.title(of: bundle.room, upstairs: false)))
        return Offer(
            id: bundle.sku,
            title: bundle.name,
            art: art,
            // Its real last day (UK DMCC: a limited offer states a true end date).
            ribbon: lastDay.map { "Until \($0.date.day) \(Self.monthName($0.month))" },
            contents: contents,
            note: bundle.blurb,
            tint: Color(red: 0.78, green: 0.85, blue: 0.72),
            bundle: bundle
        )
    }

    /// A limited look's sale, while it is on (events.json).
    private func lookSale(_ bundle: BundlesFile.Bundle) -> EventDefinition? {
        guard let context = try? content?.rulesContext() else { return nil }
        let today = session.state(at: session.now()).clock.day(of: session.now())
        return EventRules.onSale(bundle.sku, on: today, context: context)
    }

    @ViewBuilder
    private var featured: some View {
        clubBanner
        tile(starter)
        // The launch month's look, only during its sale.
        ForEach(lookOffers.filter { $0.bundle?.limited == true }) { tile($0) }
    }

    // MARK: Tiles

    /// A tall offer tile: the picture big at the top, a ribbon, what is in it, the price.
    private func tile(_ offer: Offer) -> some View {
        Button {
            feedback.tap()
            detail = offer
        } label: {
            VStack(spacing: 5 * s) {
                artView(offer.art)
                    .frame(height: 112 * s)
                    .frame(maxWidth: .infinity)
                Text(offer.title).font(Theme.title(19 * s)).lineLimit(1).minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 3 * s) {
                    ForEach(offer.contents, id: \.text) { line in
                        HStack(spacing: 5 * s) {
                            PaintedIcon(line.icon, size: 18 * s)
                            Text(line.text).font(font(12)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                priceTag(offer)
            }
            .padding(12 * s)
            .frame(width: 204 * s, height: Tuning.Shop.tileHeight * s)
            .background(tileBackground(offer.tint))
            .overlay(alignment: .topLeading) {
                if let ribbon = offer.ribbon, !isOwned(offer) {
                    Ribbon(ribbon).offset(x: 10 * s, y: -8 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(offer.title), \(isOwned(offer) ? "owned" : price(offer.id) ?? "")")
    }

    /// A Bean pack, as a builder game shows its gems: the pile big, the amount, the price, bought in one tap.
    private func beanTile(_ offer: Offer) -> some View {
        let amount = StoreCatalog.beanPacks.first { $0.id == offer.id }?.beans ?? 0
        return Button {
            feedback.tap()
            buy(offer.id, offer: offer)
        } label: {
            VStack(spacing: 4 * s) {
                artView(offer.art)
                    .frame(height: 150 * s)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 4 * s) {
                    PaintedIcon("bean_coin", size: 24 * s)
                    Text(amount.formatted()).font(font(24, .heavy, rounded: true)).monospacedDigit()
                }
                Text(offer.title).font(font(12, .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                Spacer(minLength: 0)
                priceTag(offer)
            }
            .padding(12 * s)
            .frame(width: 168 * s, height: Tuning.Shop.tileHeight * s)
            .background(tileBackground(offer.tint))
            .overlay(alignment: .topLeading) {
                if let ribbon = offer.ribbon {
                    Ribbon(ribbon, colour: offer.id == StoreCatalog.beanPacks.last?.id ? Self.deepGold : Theme.accent)
                        .offset(x: 10 * s, y: -8 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(buying != nil)
        .accessibilityLabel("\(amount) Beans, \(price(offer.id) ?? "")")
    }

    private func tileBackground(_ tint: Color, corner: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner * s, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.5), tint], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Theme.cream, lineWidth: 4 * s))
            .overlay(shape.strokeBorder(Theme.rim, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
    }

    /// The price as a raised button (in Beans for an outfit, with Top up when they fall short), or Owned.
    @ViewBuilder
    private func priceTag(_ offer: Offer, compact: Bool = false) -> some View {
        if isOwned(offer) {
            HStack(spacing: 4 * s) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text("Owned").font(font(compact ? 13 : 15, .heavy, rounded: true))
            }
            .padding(.vertical, (compact ? 6 : 9) * s)
        } else if let cost = offer.beanPrice {
            let short = cost > beans
            raised(compact: compact, colour: short ? Color(red: 0.36, green: 0.6, blue: 0.42) : Theme.accent) {
                HStack(spacing: 3 * s) {
                    if short {
                        Text("Top up").font(font(compact ? 13 : 16, .heavy, rounded: true))
                    } else {
                        PaintedIcon("bean_coin", size: (compact ? 16 : 20) * s)
                        Text(cost.formatted()).font(font(compact ? 14 : 18, .heavy, rounded: true))
                    }
                }
            }
        } else {
            raised(compact: compact, colour: Theme.accent) {
                Text(buying == offer.id ? "…" : price(offer.id) ?? "…").font(font(compact ? 14 : 18, .heavy, rounded: true))
            }
        }
    }

    private func raised(compact: Bool, colour: Color, @ViewBuilder label: () -> some View) -> some View {
        label()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, (compact ? 5 : 8) * s)
            .background {
                ZStack {
                    Capsule().fill(colour.mix(with: .black, by: 0.3)).offset(y: (compact ? 3 : 4) * s)
                    Capsule().fill(LinearGradient(colors: [colour.mix(with: .white, by: 0.18), colour], startPoint: .top, endPoint: .bottom))
                }
            }
    }

    private func artView(_ art: [String]) -> some View {
        Group {
            if art.count == 1, let picture = CatScreens.picture(art[0]) {
                picture.resizable().interpolation(.high).scaledToFit()
            } else {
                HStack(alignment: .bottom, spacing: -14 * s) {
                    ForEach(Array(art.enumerated()), id: \.offset) { _, path in
                        CatScreens.picture(path).map { $0.resizable().interpolation(.high).scaledToFit() }
                    }
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 6 * s, y: 4 * s)
    }

    // MARK: Cat Club

    private static let gold = Color(red: 1, green: 0.87, blue: 0.52)
    private static let deepGold = Color(red: 0.86, green: 0.6, blue: 0.16)

    /// The featured banner: the crowned cat, what you get at a glance, the way in.
    private var clubBanner: some View {
        Button {
            feedback.tap()
            section = .club
        } label: {
            HStack(spacing: 0) {
                artView(["ui/shop/shop_club.png"]).frame(width: 200 * s).padding(.leading, 6 * s)
                VStack(alignment: .leading, spacing: 8 * s) {
                    Ribbon(owned.hasClub ? "You're a member" : "\(StoreCatalog.yearlyTrialDays) days free", colour: Self.deepGold)
                    Text("Cat Club").font(Theme.title(32 * s)).foregroundStyle(.white)
                    Text("+20% Beans, rooms for half the Beans, moving home for free and every season's paid track.")
                        .font(font(13))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !owned.hasClub {
                        // Both plans, side by side as on the club page.
                        Text(
                            "\(price(StoreCatalog.clubYearly) ?? "…") a year after the free week, or \(price(StoreCatalog.clubMonthly) ?? "…") a month"
                        )
                        .font(font(12, .bold))
                        .foregroundStyle(Self.gold)
                        Text("See what's in it  ›").font(font(15, .heavy, rounded: true)).foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 18 * s)
                .padding(.trailing, 18 * s)
            }
            .frame(width: 480 * s, height: Tuning.Shop.tileHeight * s)
            .background(clubBackground)
        }
        .buttonStyle(PressStyle())
    }

    private var clubBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24 * s, style: .continuous)
        return shape
            .fill(LinearGradient(
                colors: [Color(red: 0.2, green: 0.36, blue: 0.44), Color(red: 0.33, green: 0.24, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Self.gold, Self.deepGold], startPoint: .top, endPoint: .bottom),
                lineWidth: 4 * s
            ))
            .shadow(color: Theme.shadow, radius: 10 * s, y: 5 * s)
    }

    /// The Cat Club page, one screen on a phone: the crowned cat, the perks as big numbers, the two plans side by
    /// side, the button and the renewal terms in full. Only perks the game has are listed.
    private var clubPage: some View {
        HStack(alignment: .top, spacing: 14 * s) {
            VStack(spacing: 4 * s) {
                artView(["ui/shop/shop_club.png"]).frame(width: 160 * s, height: 140 * s)
                Text("Cat Club").font(Theme.title(28 * s)).foregroundStyle(.white)
                if let pass = session.passInfo(club: false) {
                    Text("This season's paid track: \(pass.season.paidTrack.count) rewards in \(pass.name).")
                        .font(font(10.5, .bold))
                        .foregroundStyle(Self.gold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 160 * s)
            VStack(alignment: .leading, spacing: 8 * s) {
                Grid(horizontalSpacing: 8 * s, verticalSpacing: 8 * s) {
                    GridRow {
                        perk("+20%", "Beans on all you earn", icon: "bean_coin")
                        perk("½", "the Beans to open rooms", icon: "house")
                    }
                    GridRow {
                        perk("Free", "moving home", icon: "map_pin")
                        perk("Every", "season's paid track", icon: "season_pass_ticket")
                    }
                }
                if owned.hasClub {
                    Text("You're a member. Thank you.").font(Theme.title(20 * s)).foregroundStyle(.white)
                    Text("Every perk is on. The subscription is managed at the end of the shop.")
                        .font(font(11)).foregroundStyle(.white.opacity(0.85))
                } else {
                    HStack(spacing: 8 * s) {
                        plan(yearly: true)
                        plan(yearly: false)
                    }
                    HStack(alignment: .center, spacing: 10 * s) {
                        ChunkyButton(
                            yearly ? "Start \(StoreCatalog.yearlyTrialDays) days free" :
                                "Join for \(price(StoreCatalog.clubMonthly) ?? "…")",
                            colour: Self.deepGold
                        ) {
                            buy(yearly ? StoreCatalog.clubYearly : StoreCatalog.clubMonthly, offer: clubOffer)
                        }
                        .disabled(buying != nil)
                        .layoutPriority(1)
                        Text(clubTerms)
                            .font(font(9))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 358 * s, alignment: .leading)
        }
        .padding(14 * s)
        .frame(height: Tuning.Shop.tileHeight * s, alignment: .top)
        .background(clubBackground)
    }

    private var clubTerms: String {
        let year = price(StoreCatalog.clubYearly) ?? "…", month = price(StoreCatalog.clubMonthly) ?? "…"
        return "Yearly: free for \(StoreCatalog.yearlyTrialDays) days, then \(year) a year. Monthly: \(month) a month. "
            + "Renews automatically until you cancel, at least a day before it renews, in Settings."
    }

    private func perk(_ big: String, _ detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6 * s) {
            PaintedIcon(icon, size: 28 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(big).font(font(22, .heavy, rounded: true)).foregroundStyle(Self.gold).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(font(10.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8 * s)
        .frame(width: 175 * s, height: 62 * s, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(.white.opacity(0.1)))
    }

    /// A plan card: the yearly one with its trial and its price a month, the monthly one.
    private func plan(yearly isYearly: Bool) -> some View {
        let chosen = yearly == isYearly
        let id = isYearly ? StoreCatalog.clubYearly : StoreCatalog.clubMonthly
        let perMonth = isYearly ? prices.products[id].flatMap { product in
            product.price.flatMap { price in product.currencyCode.map { (price / 12).formatted(.currency(code: $0)) } }
        } : nil
        return Button {
            feedback.tap()
            yearly = isYearly
        } label: {
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(price(id).map { isYearly ? "Yearly · \($0)" : "Monthly · \($0)" } ?? "…")
                    .font(font(14, .heavy, rounded: true))
                Text(isYearly ? "\(StoreCatalog.yearlyTrialDays) days free" + (perMonth.map { " · \($0) a month" } ?? "") :
                    "Cancel any time")
                    .font(font(10.5, .semibold))
                    .opacity(0.88)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 10 * s)
            .padding(.vertical, 8 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(.white.opacity(chosen ? 0.22 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 13 * s, style: .continuous)
                .strokeBorder(chosen ? Self.gold : .white.opacity(0.25), lineWidth: chosen ? 2.5 * s : 1))
            .overlay(alignment: .topTrailing) {
                if isYearly {
                    // True of the yearly plan: it costs less a month than the monthly one.
                    Ribbon("Best value", colour: Self.deepGold).scaleEffect(0.78).offset(x: 6 * s, y: -11 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Outfits

    /// The outfits sold for Beans (catalogue pool "paid"), a seasonal one only in its months.
    private var outfitOffers: [Offer] {
        let today = DayClock().day(of: .now)
        let mine = session.ownedOutfits
        return (content?.outfits.outfits ?? []).filter { outfit in
            guard outfit.pool == .paid else { return false }
            return mine.contains(outfit.id) || ShopRules.isOnSale(months: outfit.months, on: today)
        }
        .map { outfit in
            Offer(
                id: "outfit.\(outfit.id)",
                title: outfit.name,
                art: [outfit.sprites["tqfront"] ?? ""],
                // A real last day, never a countdown.
                ribbon: ShopRules.lastSaleDay(months: outfit.months, from: today).map { "Until \($0.date.day) \(Self.monthName($0.month))" },
                contents: [.init(icon: "cat_face", text: "Fits every cat")],
                note: prices.value(ofBeans: Tuning.Beans.outfit).map { "\(Tuning.Beans.outfit) Beans is about \($0)." },
                tint: Color(red: 0.96, green: 0.88, blue: 0.8),
                beanPrice: Tuning.Beans.outfit,
                outfitID: outfit.id
            )
        }
    }

    private var outfitGrid: some View {
        let row = (Tuning.Shop.tileHeight - 12) / 2 * s
        return LazyHGrid(rows: [GridItem(.fixed(row), spacing: 12 * s), GridItem(.fixed(row), spacing: 12 * s)], spacing: 12 * s) {
            ForEach(outfitOffers) { offer in
                Button {
                    feedback.tap()
                    detail = offer
                } label: {
                    VStack(spacing: 3 * s) {
                        artView(offer.art).frame(height: 66 * s)
                        Text(offer.title).font(font(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        priceTag(offer, compact: true)
                    }
                    .padding(9 * s)
                    .frame(width: 124 * s, height: row)
                    .background(tileBackground(offer.tint, corner: 18))
                    .overlay(alignment: .top) {
                        if let ribbon = offer.ribbon, !isOwned(offer) {
                            Ribbon(ribbon).scaleEffect(0.75).offset(y: -9 * s)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(offer.title), \(isOwned(offer) ? "owned" : "\(Tuning.Beans.outfit) Beans")")
            }
        }
    }

    // MARK: Detail and the foot

    /// Before buying: the offer big, everything in it, the price, Close. A room look can be tried in its room
    /// first and, once owned, put in all at once; an outfit can be wrapped for a co-owner to find.
    private func detailPanel(_ offer: Offer) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { detail = nil }
            HStack(spacing: 20 * s) {
                artView(offer.art).frame(width: 230 * s, height: 220 * s)
                VStack(alignment: .leading, spacing: 9 * s) {
                    if let ribbon = offer.ribbon, !isOwned(offer) {
                        Ribbon(ribbon)
                    }
                    Text(offer.title).font(Theme.title(28 * s))
                    VStack(alignment: .leading, spacing: 5 * s) {
                        ForEach(offer.contents, id: \.text) { line in
                            HStack(spacing: 8 * s) {
                                PaintedIcon(line.icon, size: 28 * s)
                                Text(line.text).font(font(15))
                            }
                        }
                    }
                    if let note = offer.note {
                        Text(note).font(font(12, .semibold)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 2 * s)
                    actions(for: offer)
                }
                .frame(width: 300 * s, alignment: .leading)
            }
            .padding(22 * s)
            .frame(height: Tuning.Shop.tileHeight * s)
            .background(tileBackground(offer.tint.mix(with: Theme.cream, by: 0.55), corner: 26))
            .overlay(alignment: .topTrailing) {
                CloseButton { detail = nil }.scaleEffect(s).offset(x: 12 * s, y: -12 * s)
            }
        }
    }

    @ViewBuilder
    private func actions(for offer: Offer) -> some View {
        let roomOpen = offer.bundle.map { session.state(at: session.now()).openedRooms.contains($0.room) } ?? false
        if let bundle = offer.bundle {
            if isOwned(offer) {
                if roomOpen, let addLook {
                    ChunkyButton("Add the whole room") {
                        detail = nil
                        dismiss()
                        addLook(bundle)
                    }
                } else {
                    Text("Yours. Its pieces wait in your things for the \(Visit.title(of: bundle.room, upstairs: false).lowercased()).")
                        .font(font(13, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ChunkyButton("Buy for \(price(offer.id) ?? "…")") { buy(offer.id, offer: offer) }
                    .disabled(buying != nil)
                if roomOpen, let tryLook {
                    Button {
                        feedback.tap()
                        detail = nil
                        dismiss()
                        tryLook(bundle)
                    } label: {
                        Label("Try it in your room", systemImage: "eye").font(font(13, .bold)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(PressStyle())
                } else if !roomOpen {
                    Text("For the \(Visit.title(of: bundle.room, upstairs: false).lowercased()), which opens at level \(bundle.room.requiredLevel).")
                        .font(font(11, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if isOwned(offer) {
            Text("You own this.").font(font(16, .bold))
        } else if let cost = offer.beanPrice {
            let short = BeanPrices.shortfall(price: cost, balance: beans)
            ChunkyButton(short > 0 ? "Top up \(short.formatted()) Beans" : "Buy for \(cost.formatted()) Beans") { buyWithBeans(offer) }
            if session.isCoOwned {
                Button {
                    feedback.tap()
                    buyWithBeans(offer, gift: true)
                } label: {
                    Label("Wrap it as a present", systemImage: "gift").font(font(13, .bold)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(PressStyle())
            }
        } else {
            ChunkyButton("Buy for \(price(offer.id) ?? "…")") { buy(offer.id, offer: offer) }
                .disabled(buying != nil)
            #if DEBUG
                if store == nil {
                    Text("Debug preview: nothing is charged.").font(font(10)).foregroundStyle(Theme.inkSoft)
                }
            #endif
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text("ALSO").font(font(13, .heavy, rounded: true)).tracking(1.2).foregroundStyle(Theme.inkSoft)
            if let message {
                Text(message).font(font(12)).foregroundStyle(Theme.inkSoft)
            }
            HUDButton("Restore Purchases", symbol: "arrow.clockwise") {
                Task {
                    try? await store?.restore()
                    refresh()
                    message = "Purchases restored."
                }
            }
            .disabled(store == nil)
            HUDButton("Request a refund", symbol: "arrow.uturn.backward") { refunding = true }
                .disabled(store == nil)
            HUDButton("Manage subscription", symbol: "gearshape") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            }
            Link("Terms of Use", destination: Tuning.Store.termsURL).font(font(12, .semibold)).tint(Theme.accent)
            Link("Privacy Policy", destination: Tuning.Store.privacyURL).font(font(12, .semibold)).tint(Theme.accent)
            Text("Beans come in packs and every day from looking after your cat. Room looks are kept for good; Cat Club renews until you cancel. Nothing is random.")
                .font(font(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 220 * s, alignment: .leading)
    }
}

/// After a purchase: the item springs in over a turning sunburst, paw prints, stars and beans drift down, and
/// what it unlocked is listed (a builder game's reward screen, in the house style).
struct Celebration: View {
    let offer: ShopView.Offer
    let scale: CGFloat
    let done: () -> Void
    @State private var shown = false
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.76).ignoresSafeArea()
            // Drawn over a clear layer so its size never reaches the layout. With Reduce Motion: the sunburst still,
            // no confetti.
            Color.clear
                .overlay {
                    TimelineView(.animation(paused: reduceMotion)) { timeline in
                        let t = timeline.date.timeIntervalSince(start)
                        ZStack {
                            sunburst.rotationEffect(.degrees(reduceMotion ? 0 : t * 10))
                            if !reduceMotion {
                                confetti(t)
                            }
                        }
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 10 * scale) {
                Text(offer.isClub ? "Welcome to Cat Club!" : "It's yours!")
                    .font(Theme.title(34 * scale))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                Group {
                    if offer.art.count == 1, let picture = CatScreens.picture(offer.art[0]) {
                        picture.resizable().interpolation(.high).scaledToFit()
                    } else {
                        HStack(spacing: -16 * scale) {
                            ForEach(Array(offer.art.enumerated()), id: \.offset) { _, path in
                                CatScreens.picture(path).map { $0.resizable().interpolation(.high).scaledToFit() }
                            }
                        }
                    }
                }
                .frame(height: 170 * scale)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .scaleEffect(shown ? 1 : 0.3)
                .rotationEffect(.degrees(shown ? 0 : -12))
                HStack(spacing: 14 * scale) {
                    ForEach(offer.contents, id: \.text) { line in
                        HStack(spacing: 5 * scale) {
                            PaintedIcon(line.icon, size: 24 * scale)
                            Text(line.text).font(.system(size: 14 * scale, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                }
                .opacity(shown ? 1 : 0)
                ChunkyButton("Lovely") { done() }
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            start = Date()
            withAnimation(.spring(duration: 0.6, bounce: 0.45).delay(0.1)) { shown = true }
        }
    }

    private var sunburst: some View {
        ZStack {
            ForEach(0 ..< 16, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.86, blue: 0.48).opacity(0.3), .clear],
                        startPoint: .center,
                        endPoint: .top
                    ))
                    .frame(width: 26 * scale, height: 620 * scale)
                    .rotationEffect(.degrees(Double(i) * 22.5))
            }
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.9, blue: 0.62).opacity(0.45), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 200 * scale
                ))
                .frame(width: 400 * scale, height: 400 * scale)
        }
    }

    /// Paw prints, stars, beans and hearts drifting down, the same pattern every time (placed by index).
    private func confetti(_ t: TimeInterval) -> some View {
        GeometryReader { geometry in
            let icons = ["group_of_three_paw_prints", "xp_star", "bean_coin", "trust_heart_with_a_paw_print"]
            ForEach(0 ..< 34, id: \.self) { i in
                let seed = Double((i * 7919) % 1000) / 1000
                let x = geometry.size.width * (Double((i * 3571) % 1000) / 1000)
                let speed = (70 + seed * 90) * scale
                let fall = geometry.size.height + 80
                let y = (t * speed + seed * fall).truncatingRemainder(dividingBy: fall) - 40
                PaintedIcon(icons[i % icons.count], size: (18 + seed * 16) * scale)
                    .rotationEffect(.degrees(t * (40 + seed * 80) * (i.isMultiple(of: 2) ? 1 : -1)))
                    .position(x: x + sin(t * 1.5 + seed * 6) * 18, y: y)
                    .opacity(0.9)
            }
        }
    }
}
