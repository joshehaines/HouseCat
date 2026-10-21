import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The shop (SPEC "Monetisation and the shop"), laid out like a builder game's shop with its pages apart (Josh, 19 Oct:
/// "multiple menu, not one long menu ... take cues from Clash"): a honey-oak header with a painted tab for each page,
/// and each page on its own: Offers, the Season pass while a season is on, Beans, Room looks, Outfits, and Cat Club
/// last (it is kept, not the headline). Big painted tiles with gold rims, a coloured band for the title, the picture
/// over a warm glow and a raised price button, green for money and orange for Beans. Three kinds of product (Josh,
/// 18 Oct): Bean packs, the one currency; room looks, a whole room in one tap; and Cat Club. Outfits are bought with
/// Beans, and when Beans fall short Buy becomes Top up. Every price is StoreKit's own, a Bean price shows what it
/// comes to in money, nothing is random, nothing counts down (a limited look gives its real last day), the two Cat
/// Club plans sit side by side with the full renewal terms, Close is always on screen, and Restore Purchases, Terms
/// and Privacy run along the foot of every page.
struct ShopView: View {
    static func monthName(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1) % 12]
    }

    enum Section: String, CaseIterable, Identifiable {
        case offers, pass, beans, looks, outfits, club

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .offers: "Offers"
            case .pass: "Season pass"
            case .beans: "Beans"
            case .looks: "Room looks"
            case .outfits: "Outfits"
            case .club: "Cat Club"
            }
        }

        var icon: String {
            switch self {
            case .offers: "star_rosette"
            case .pass: "season_pass_ticket"
            case .beans: "bean_coin"
            case .looks: "sofa_for_furniture"
            case .outfits: "jumper_on_hanger"
            case .club: "crown"
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
    /// The Season pass page's "See the pass": the shop closes and the pass opens.
    var openPass: (() -> Void)?
    /// The Outfits page's "Try them on": the shop closes and the cat tries outfits on, on the one given if any.
    /// Without it the page has no way in (nothing is shown that cannot work).
    var tryOutfits: ((String?) -> Void)?
    /// The page to open on (the pill's Beans open the packs, the pass opens Cat Club).
    var opening: Section?
    @State private var prices = StorePrices.shared
    @State private var message: String?
    @State private var restoring = false
    @State private var buying: String?
    @State private var owned = Entitlements.none
    @State private var beans = 0
    @State private var pass: GameSession.PassInfo?
    @State private var section: Section = .offers
    @State private var detail: Offer?
    @State private var celebrating: Offer?
    @State private var topUp: TopUpRequest?
    @State private var yearly = true
    @State private var refunding = false
    /// Everything is laid out for a landscape phone and scaled to fill a bigger screen (a little smaller on the
    /// smallest phones).
    @State private var s: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.controlFeedback) private var feedback

    private var session: GameSession {
        GameSession.shared
    }

    /// The pages shown: the Season pass only while a season is on (App Review 2.1: no "coming soon" pages).
    private var sections: [Section] {
        Section.allCases.filter { $0 != .pass || pass != nil }
    }

    var body: some View {
        // The scale comes from the screen alone, never from what it sizes (a feedback loop otherwise).
        GeometryReader { proxy in
            let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            shop
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onChange(of: CGSize(width: proxy.size.width, height: height), initial: true) { _, screen in
                    let fit = min(screen.height / Tuning.Shop.designHeight, screen.width / Tuning.Shop.designWidth)
                    s = (min(Tuning.Shop.largestScale, max(Tuning.Shop.smallestScale, fit)) * 20).rounded(.down) / 20
                }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private var shop: some View {
        ZStack {
            paperBackground
            VStack(spacing: 0) {
                header.zIndex(2)
                ZStack {
                    page(section)
                        .id(section)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                .padding(.top, 20 * s)
                .padding(.bottom, 6 * s)
                .padding(.horizontal, 10 * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
                footer
            }
            if let message {
                notice(message)
            }
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
        .animation(.easeOut(duration: 0.2), value: section)
        .animation(.spring(duration: 0.35), value: detail)
        .animation(.easeOut(duration: 0.3), value: celebrating)
        .animation(.easeOut(duration: 0.25), value: topUp?.id)
        .animation(.easeOut(duration: 0.25), value: message)
        .task {
            Analytics.track(.shopOpened)
            refresh()
            if let opening, sections.contains(opening) {
                section = opening
            }
            await prices.load(store: store, content: content)
            if prices.unavailable {
                message = "The shop is not available right now."
            }
            #if DEBUG
                // Screenshot runs: HOUSECAT_SHOP=<page>, detail (the starter's panel), look (a room look's),
                // topup (short for an outfit) or celebrate (Cat Club's).
                if let wanted = ProcessInfo.processInfo.environment["HOUSECAT_SHOP"] {
                    try? await Task.sleep(for: .seconds(1))
                    if let open = Section(rawValue: wanted == "featured" ? "offers" : wanted) {
                        section = open
                    } else if wanted == "detail" {
                        detail = starter
                    } else if wanted == "look" {
                        section = .looks
                        detail = lookOffers.first { $0.bundle?.room != .living } ?? lookOffers.first
                    } else if wanted == "topup" {
                        section = .outfits
                        topUp = TopUpRequest(need: 900, purpose: "the Raincoat") {}
                    } else if wanted == "celebrate" {
                        celebrate(clubOffer)
                    }
                }
            #endif
        }
    }

    private func font(_ size: CGFloat, _ weight: Font.Weight = .semibold, rounded: Bool = false) -> Font {
        .system(size: size * s, weight: weight, design: rounded ? .rounded : .default)
    }

    private func refresh() {
        owned = store?.entitlements ?? .none
        beans = session.beans
        pass = session.passInfo(club: owned.hasClub, passes: owned.passes)
    }

    /// Restore Purchases, from the foot of every page or the Cat Club page: the notice says what came back, or why not.
    private func restore() {
        restoring = true
        Task {
            message = await RestorePurchases.run(store)
            refresh()
            restoring = false
        }
    }

    private var catName: String {
        CatScreens.profile()?.profile.name ?? "your cat"
    }

    // MARK: The frame: paper, the header and its tabs, the foot

    /// The painted paper the pages sit on (assets/ui/shop/shop_paper.png, made to tile), warmer at the edges.
    private var paperBackground: some View {
        ZStack {
            Color(red: 0.96, green: 0.88, blue: 0.76)
            if let paper = GameWorld.art?.image("ui/shop/shop_paper.png") {
                Image(decorative: paper, scale: 2).resizable(resizingMode: .tile)
            }
            RadialGradient(
                colors: [Color(red: 1, green: 0.97, blue: 0.9).opacity(0.35), Color(red: 0.55, green: 0.32, blue: 0.16).opacity(0.2)],
                center: .center,
                startRadius: 0,
                endRadius: 700 * s
            )
        }
        .ignoresSafeArea()
    }

    /// The honey-oak plank across the top (assets/ui/shop/shop_plank.png): the bag and the shop's name, a tab for
    /// each page (the open one cream, hanging over the page), the player's Beans with a + and Close.
    private var header: some View {
        HStack(alignment: .center, spacing: 6 * s) {
            ViewThatFits(in: .horizontal) {
                brand(named: true)
                brand(named: false)
            }
            .layoutPriority(-1)
            ForEach(sections) { tab($0) }
            Spacer(minLength: 4 * s)
            balance
            CloseButton { dismiss() }
                .scaleEffect(s)
                .frame(width: 36 * s, height: 36 * s)
        }
        .padding(.horizontal, 8 * s)
        .frame(height: Tuning.Shop.headerHeight * s)
        .background {
            Group {
                if let plank = CatScreens.picture("ui/shop/shop_plank.png") {
                    plank.resizable().interpolation(.high)
                } else {
                    LinearGradient(colors: [Color(red: 0.84, green: 0.56, blue: 0.24), Color(red: 0.7, green: 0.42, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                }
            }
            .shadow(color: Color(red: 0.3, green: 0.15, blue: 0.04).opacity(0.4), radius: 5 * s, y: 4 * s)
            .ignoresSafeArea(edges: [.horizontal, .top])
        }
    }

    private func brand(named: Bool) -> some View {
        HStack(spacing: 3 * s) {
            PaintedIcon("shop_bag", size: 36 * s)
                .shadow(color: .black.opacity(0.3), radius: 1.5 * s, y: 1.5 * s)
            if named {
                Text("Shop")
                    .font(Theme.title(24 * s))
                    .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.89))
                    .shadow(color: Color(red: 0.35, green: 0.18, blue: 0.04).opacity(0.7), radius: 0, y: 2 * s)
                    .fixedSize()
            }
        }
        .padding(.trailing, 4 * s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shop")
        .accessibilityAddTraits(.isHeader)
    }

    private func tab(_ item: Section) -> some View {
        let on = section == item
        return Button {
            feedback.tap()
            withAnimation(.easeOut(duration: 0.2)) { section = item }
        } label: {
            VStack(spacing: 1 * s) {
                PaintedIcon(item.icon, size: (on ? 33 : 29) * s)
                    .shadow(color: .black.opacity(0.3), radius: 1 * s, y: 1 * s)
                Text(item.title)
                    .font(font(11, .heavy, rounded: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(on ? Theme.ink : Color(red: 1, green: 0.95, blue: 0.86))
                    .shadow(color: on ? .clear : Color(red: 0.25, green: 0.1, blue: 0).opacity(0.6), radius: 0, y: 1 * s)
            }
            .frame(width: Tuning.Shop.tabWidth * s, height: (on ? 58 : 50) * s)
            .background {
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: 12 * s, bottomLeadingRadius: (on ? 6 : 12) * s,
                    bottomTrailingRadius: (on ? 6 : 12) * s, topTrailingRadius: 12 * s, style: .continuous
                )
                if on {
                    shape.fill(LinearGradient(colors: [Theme.cream, Color(red: 0.97, green: 0.9, blue: 0.78)], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(Self.deepGold, lineWidth: 2.5 * s))
                        .overlay(shape.inset(by: 2.5 * s).strokeBorder(Color(red: 1, green: 0.95, blue: 0.82), lineWidth: 1.2 * s))
                        .shadow(color: Color(red: 0.3, green: 0.12, blue: 0).opacity(0.35), radius: 4 * s, y: 3 * s)
                } else {
                    shape.fill(LinearGradient(colors: [Color(red: 0.73, green: 0.47, blue: 0.19), Color(red: 0.6, green: 0.37, blue: 0.13)], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(
                            LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.66).opacity(0.5), Color(red: 0.25, green: 0.1, blue: 0).opacity(0.35)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.2 * s
                        ))
                }
            }
            .contentShape(Rectangle())
            // The open tab hangs over the top of the page.
            .offset(y: on ? 11 * s : 0)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    /// The player's Beans, top right, as in a builder game's shop; the + opens the Bean packs.
    private var balance: some View {
        HStack(spacing: 4 * s) {
            PaintedIcon("bean_coin", size: 30 * s)
                .padding(.leading, -10 * s)
                .shadow(color: .black.opacity(0.3), radius: 1 * s, y: 1 * s)
            Text(beans.formatted()).font(font(16, .heavy, rounded: true)).monospacedDigit().contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
            Button {
                feedback.tap()
                withAnimation(.easeOut(duration: 0.2)) { section = .beans }
            } label: {
                Image(systemName: "plus").font(font(13, .black)).foregroundStyle(.white)
                    .frame(width: 25 * s, height: 25 * s)
                    .background(Circle().fill(LinearGradient(colors: [Self.green.mix(with: .white, by: 0.2), Self.green], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5 * s))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Get Beans")
        }
        .padding(.leading, 6 * s)
        .padding(.trailing, 4 * s)
        .frame(height: 34 * s)
        .background(Capsule().fill(LinearGradient(colors: [Theme.cream, Color(red: 0.96, green: 0.89, blue: 0.77)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(Self.deepGold, lineWidth: 2 * s))
        .shadow(color: .black.opacity(0.25), radius: 3 * s, y: 2 * s)
        .padding(.leading, 10 * s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(beans) Beans")
        .animation(.spring(duration: 0.4), value: beans)
    }

    /// The foot of every page (App Review 3.1.1 and 3.1.2): Restore Purchases, a refund, the subscription, the terms,
    /// the privacy policy and help, always in reach.
    private var footer: some View {
        HStack(spacing: 0) {
            footLink(restoring ? "Restoring…" : "Restore Purchases", strong: true) { restore() }
                .disabled(store == nil || restoring)
            dot
            footLink("Request a refund") { refunding = true }
                .disabled(store == nil)
            dot
            footLink("Manage subscription") { openURL(Tuning.Store.manageSubscriptionsURL) }
            Spacer(minLength: 8 * s)
            Link("Terms of Use", destination: Tuning.Store.termsURL)
            dot
            Link("Privacy Policy", destination: Tuning.Store.privacyURL)
            dot
            Link("Help", destination: Tuning.Store.supportURL)
        }
        .font(font(11.5, .bold, rounded: true))
        .tint(Theme.inkSoft)
        .foregroundStyle(Theme.inkSoft)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12 * s)
        .frame(height: Tuning.Shop.footerHeight * s)
    }

    private var dot: some View {
        Text("·").padding(.horizontal, 6 * s).opacity(0.5).accessibilityHidden(true)
    }

    private func footLink(_ title: String, strong: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title) {
            feedback.tap()
            action()
        }
        .buttonStyle(.plain)
        .foregroundStyle(strong ? Self.rust : Theme.inkSoft)
    }

    /// What Restore found, or why the shop cannot sell right now, over the foot until it is tapped away.
    private func notice(_ text: String) -> some View {
        Button {
            message = nil
        } label: {
            HStack(spacing: 8 * s) {
                PaintedIcon("receipt", size: 26 * s)
                Text(text).font(font(13, .semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark").font(font(11, .bold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 9 * s)
            .frame(maxWidth: 560 * s)
            .background(Capsule().fill(Theme.cream))
            .overlay(Capsule().strokeBorder(Self.deepGold, lineWidth: 2 * s))
            .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Closes this message")
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, (Tuning.Shop.footerHeight + 6) * s)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .init(icon: "season_pass_ticket", text: "Every premium track"),
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
        // The look in its room, drawn by the game (LookPreviewRender); else its three biggest pieces side by side.
        let preview = LookArt.path(bundle.id)
        let art: [String]
        if GameWorld.art?.has(preview) == true {
            art = [preview]
        } else {
            let pieces = bundle.items.compactMap { items[$0] }.sorted { $0.footprint.w * $0.footprint.d > $1.footprint.w * $1.footprint.d }
            art = pieces.filter { $0.layer != .wall }.prefix(3).compactMap { $0.sprites["R"] ?? $0.sprites.values.first }
        }
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

    /// The outfits sold for Beans (catalogue pool "paid"), a seasonal one only in its months.
    private var outfitOffers: [Offer] {
        let today = DayClock().day(of: .now)
        let mine = session.ownedOutfits
        return (content?.outfits.outfits ?? []).filter { outfit in
            guard outfit.pool == .paid, outfit.wearable else { return false }
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

    // MARK: Pages

    @ViewBuilder
    private func page(_ section: Section) -> some View {
        switch section {
        case .offers: offersPage
        case .pass: passPage
        case .beans: beansPage
        case .looks: looksPage
        case .outfits: outfitsPage
        case .club: clubPage
        }
    }

    /// Offers: the season's pass first while a season is on, the starter until it is bought, the limited look (or
    /// a look not yet owned) and a small way into Cat Club.
    private var offersPage: some View {
        let featured = lookOffers.first { $0.bundle?.limited == true && !isOwned($0) } ?? lookOffers.first { !isOwned($0) }
        return HStack(spacing: 12 * s) {
            if let pass {
                passHero(pass).frame(width: 312 * s)
            }
            if !owned.starter {
                starterTile.frame(width: (pass == nil ? 214 : 190) * s)
            }
            VStack(spacing: 12 * s) {
                if let featured {
                    featuredLookTile(featured)
                    clubTile.frame(height: 116 * s)
                } else {
                    clubTile
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.pageGrowth)
    }

    private var starterTile: some View {
        let offer = starter
        return Button {
            feedback.tap()
            detail = offer
        } label: {
            VStack(spacing: 0) {
                band(offer.title, colour: Self.terracotta)
                glowArt(offer.art)
                    .padding(.vertical, 4 * s)
                lines(offer.contents)
                PriceButton(text: price(offer.id) ?? "…", style: .money)
                    .padding(.horizontal, 10 * s)
                    .padding(.top, 6 * s)
                    .padding(.bottom, 12 * s)
            }
            .goldTile(s)
            .overlay(alignment: .topLeading) { Ribbon(offer.ribbon ?? "", colour: Self.rust).offset(x: 12 * s, y: -10 * s) }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Starter Pack, \(price(offer.id) ?? ""), once only")
    }

    /// The season's pass on the Offers page: its picture, its name and theme, its real last day, the rewards on its
    /// paid track and the way into the pass.
    private func passHero(_ pass: GameSession.PassInfo) -> some View {
        let last = pass.season.endDay.advanced(by: -1)
        return Button {
            feedback.tap()
            withAnimation(.easeOut(duration: 0.2)) { section = .pass }
        } label: {
            VStack(spacing: 8 * s) {
                // Side by side on a phone; on a taller tile (an iPad) the picture over the words.
                GeometryReader { space in
                    if space.size.height > space.size.width * 1.1 {
                        VStack(alignment: .leading, spacing: 5 * s) {
                            glowArt(["ui/shop/shop_pass.png"], warm: false)
                            passWords(pass)
                            rewards(pass, columns: 6, size: 44)
                        }
                        .padding(.top, 14 * s)
                    } else {
                        HStack(alignment: .top, spacing: 4 * s) {
                            glowArt(["ui/shop/shop_pass.png"], warm: false)
                            VStack(alignment: .leading, spacing: 5 * s) {
                                passWords(pass)
                                rewards(pass, columns: 3, size: 40, count: 3)
                            }
                            .frame(width: 160 * s, alignment: .leading)
                            .padding(.top, 14 * s)
                        }
                    }
                }
                PriceButton(text: "See the pass  ›", style: .gold)
            }
            .padding(.horizontal, 12 * s)
            .padding(.bottom, 12 * s)
            .goldTile(s, fill: Self.dusk)
            .overlay(alignment: .topLeading) {
                Ribbon("Until \(last.date.day) \(Self.monthName(last.month))").offset(x: 12 * s, y: -10 * s)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(pass.name) season pass, until \(last.date.day) \(Self.monthName(last.month))")
    }

    private func passWords(_ pass: GameSession.PassInfo) -> some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            Text("SEASON PASS").font(font(10.5, .heavy, rounded: true)).tracking(1.2).foregroundStyle(GameHUD.gold)
            Text(pass.name).font(Theme.title(24 * s)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
            Text(theme(of: pass)).font(font(11.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(4).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func theme(of pass: GameSession.PassInfo) -> String {
        content?.seasons.seasons.first { $0.id == pass.season.id }?.theme ?? ""
    }

    /// The pass's paid-track rewards worth seeing (pieces, outfits, surfaces before Beans), as small pictures.
    private func rewards(_ pass: GameSession.PassInfo, columns: Int, size: CGFloat, count: Int = 6) -> some View {
        let shown = (pass.season.paidTrack.filter { $0.kind != .beans } + pass.season.paidTrack.filter { $0.kind == .beans }).prefix(count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5 * s), count: columns), spacing: 5 * s) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, reward in
                rewardPicture(reward)
                    .frame(width: size * 0.72 * s, height: size * 0.72 * s)
                    .frame(maxWidth: .infinity)
                    .frame(height: size * s)
                    .background(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).fill(.white.opacity(0.13)))
                    .overlay(RoundedRectangle(cornerRadius: 10 * s, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    /// A reward's picture: the piece or outfit itself, a coin for Beans, a roll of wallpaper for anything else.
    @ViewBuilder
    private func rewardPicture(_ reward: PassReward) -> some View {
        if reward.kind == .item, let id = reward.id, let picture = Pieces.picture(id) {
            picture.resizable().interpolation(.high).scaledToFit()
        } else if reward.kind == .outfit, let id = reward.id,
                  let path = content?.outfits.outfits.first(where: { $0.id == id })?.sprites["tqfront"], let picture = CatScreens.picture(path)
        {
            picture.resizable().interpolation(.high).scaledToFit()
        } else {
            PaintedIcon(reward.kind == .beans ? "bean_coin" : reward.kind == .outfit ? "jumper_on_hanger" : reward.kind == .item ? "sofa_for_furniture" : "wallpaper_roll", size: 30 * s)
        }
    }

    /// A room look on the Offers page: its room big beside its name and price.
    private func featuredLookTile(_ offer: Offer) -> some View {
        Button {
            feedback.tap()
            detail = offer
        } label: {
            GeometryReader { space in
                if space.size.height > space.size.width * 0.85 {
                    VStack(alignment: .leading, spacing: 6 * s) {
                        lookPicture(offer)
                        lookWords(offer).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10 * s)
                } else {
                    HStack(spacing: 8 * s) {
                        lookPicture(offer)
                            .padding(.leading, 10 * s)
                            .padding(.vertical, 10 * s)
                        lookWords(offer)
                            .padding(.vertical, 14 * s)
                            .padding(.trailing, 12 * s)
                            .frame(width: 150 * s, alignment: .leading)
                    }
                }
            }
            .goldTile(s)
            .overlay(alignment: .topLeading) {
                if let ribbon = offer.ribbon, !isOwned(offer) {
                    Ribbon(ribbon).offset(x: 12 * s, y: -10 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(offer.title), \(isOwned(offer) ? "owned" : price(offer.id) ?? "")")
    }

    private func lookWords(_ offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            Text(offer.title).font(Theme.title(17 * s)).lineLimit(2).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(lookSummary(offer)).font(font(11.5)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2 * s)
            priceTag(offer, compact: true)
        }
    }

    /// A look's room filling a rounded frame (the room is in the middle of each picture).
    private func lookPicture(_ offer: Offer) -> some View {
        Color(red: 0.93, green: 0.84, blue: 0.72)
            .overlay {
                if offer.art.count == 1, let picture = CatScreens.picture(offer.art[0]) {
                    picture.resizable().interpolation(.high).scaledToFill()
                } else {
                    artView(offer.art, shadow: false).padding(10 * s)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
    }

    private func lookSummary(_ offer: Offer) -> String {
        guard let bundle = offer.bundle else { return "" }
        let surfaces = bundle.surfaces.count == 2 ? ", its wallpaper and floor" : bundle.surfaces.isEmpty ? "" : ", its wallpaper"
        return "\(bundle.items.count) pieces\(surfaces)"
    }

    /// Cat Club on the Offers page, small: what it gives in a line and the way to its page.
    private var clubTile: some View {
        Button {
            feedback.tap()
            withAnimation(.easeOut(duration: 0.2)) { section = .club }
        } label: {
            // Beside the pass and the starter the column is narrow (a phone, an upright iPad): a smaller cat and a
            // shorter line, so nothing is cut short.
            GeometryReader { space in
                let narrow = space.size.width < 330 * s
                HStack(spacing: 6 * s) {
                    artView(["ui/shop/shop_club.png"])
                        .frame(width: (narrow ? 80 : 104) * s)
                        .padding(.leading, 8 * s)
                        .padding(.vertical, 8 * s)
                    VStack(alignment: .leading, spacing: 3 * s) {
                        HStack(spacing: 4 * s) {
                            Text("Cat Club").font(Theme.title(17 * s)).lineLimit(1).minimumScaleFactor(0.8)
                            PaintedIcon("crown", size: 20 * s)
                        }
                        Text(owned.hasClub ? "You're a member: every perk is on." : narrow ? "+20% Beans and every premium track." : clubSummary)
                            .font(font(11.5)).foregroundStyle(Theme.inkSoft)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(owned.hasClub ? "Your membership  ›" : "See Cat Club  ›").font(font(13, .heavy, rounded: true)).foregroundStyle(Self.rust)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.top, 2 * s)
                    }
                    .padding(.vertical, 8 * s)
                    .padding(.trailing, 10 * s)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
            .goldTile(s, fill: Self.butter)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(owned.hasClub ? "Cat Club, you're a member" : "Cat Club, see what it gives")
    }

    /// What Cat Club gives, in a line: the season's paid track only while a season is on.
    private var clubSummary: String {
        pass == nil
            ? "+20% Beans, rooms for half the Beans and moving home for free."
            : "+20% Beans, rooms for half the Beans, moving home for free and every season's premium track."
    }

    /// The Season pass page: the season big, how far you are, the rewards on its paid track, and the pass itself.
    @ViewBuilder
    private var passPage: some View {
        if let pass {
            let last = pass.season.endDay.advanced(by: -1)
            HStack(spacing: 12 * s) {
                glowArt(["ui/shop/shop_pass.png"], warm: false)
                    .frame(width: 290 * s)
                    .padding(.vertical, 10 * s)
                VStack(alignment: .leading, spacing: 8 * s) {
                    Text("SEASON PASS · UNTIL \(last.date.day) \(Self.monthName(last.month).uppercased())")
                        .font(font(11, .heavy, rounded: true)).tracking(1.2).foregroundStyle(GameHUD.gold)
                    Text(pass.name).font(Theme.title(32 * s)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    Text(theme(of: pass)).font(font(13, .semibold)).foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    tierBar(pass)
                    rewards(pass, columns: 6, size: 54)
                    Spacer(minLength: 4 * s)
                    HStack(spacing: 12 * s) {
                        if openPass != nil {
                            PriceButton(text: "See the pass  ›", style: .gold) {
                                feedback.tap()
                                dismiss()
                                openPass?()
                            }
                            .frame(width: 230 * s)
                        }
                        Text(paidTrackLine(pass))
                            .font(font(11, .semibold)).foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 18 * s)
                .padding(.trailing, 20 * s)
            }
            .goldTile(s, fill: Self.dusk)
            .overlay(alignment: .topLeading) {
                Ribbon("Until \(last.date.day) \(Self.monthName(last.month))").offset(x: 12 * s, y: -10 * s)
            }
            .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.cardGrowth)
        }
    }

    /// How the paid track is had: the season's own pass at StoreKit's price where it is sold, and Cat Club.
    private func paidTrackLine(_ pass: GameSession.PassInfo) -> String {
        if pass.ownsPaid {
            return "Both tracks are yours this season."
        }
        if let sku = content?.seasons.seasons.first(where: { $0.id == pass.season.id })?.sku, let price = price(sku) {
            return "Premium: this season's pass for \(price), paid once, or with Cat Club. Every tier you have reached opens at once."
        }
        return "Premium comes with Cat Club; every tier you have reached opens at once."
    }

    private func tierBar(_ pass: GameSession.PassInfo) -> some View {
        let points = pass.progress.points % Tuning.Pass.pointsPerTier
        let done = pass.progress.tier >= Tuning.Pass.tiers
        return HStack(spacing: 8 * s) {
            Text("Tier \(pass.progress.tier) of \(Tuning.Pass.tiers)").font(font(13, .heavy, rounded: true)).foregroundStyle(.white)
            if !done {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom))
                            .frame(width: max(8 * s, bar.size.width * CGFloat(points) / CGFloat(Tuning.Pass.pointsPerTier)))
                    }
                }
                .frame(width: 150 * s, height: 10 * s)
                Text("\(points)/\(Tuning.Pass.pointsPerTier) points").font(font(11, .bold)).monospacedDigit().foregroundStyle(.white.opacity(0.85))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Beans, as a builder game shows its gems: the five packs side by side, the pile big, the amount, the price,
    /// bought in one tap.
    private var beansPage: some View {
        VStack(spacing: 6 * s) {
            HStack(spacing: 12 * s) {
                ForEach(Array(beanOffers.enumerated()), id: \.element.id) { index, offer in
                    beanTile(offer, index: index)
                }
            }
            .frame(maxHeight: .infinity)
            Text("Beans also come every day from looking after \(catName). Bigger packs give more Beans a pound.")
                .font(font(11.5, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.pageGrowth)
    }

    private func beanTile(_ offer: Offer, index: Int) -> some View {
        let amount = StoreCatalog.beanPacks.first { $0.id == offer.id }?.beans ?? 0
        let biggest = offer.id == StoreCatalog.beanPacks.last?.id
        return Button {
            feedback.tap()
            buy(offer.id, offer: offer)
        } label: {
            VStack(spacing: 0) {
                band(BeanArt.size(offer.id), colour: biggest ? Self.honey : Self.terracotta)
                // A bigger pack's pile is drawn bigger.
                glowArt(offer.art)
                    .scaleEffect(0.8 + 0.05 * CGFloat(index))
                    .padding(.vertical, 2 * s)
                HStack(spacing: 4 * s) {
                    PaintedIcon("bean_coin", size: 26 * s)
                    Text(amount.formatted()).font(font(23, .heavy, rounded: true)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.bottom, 6 * s)
                PriceButton(text: buying == offer.id ? "…" : price(offer.id) ?? "…", style: .money)
                    .padding(.horizontal, 10 * s)
                    .padding(.bottom, 12 * s)
            }
            .goldTile(s)
            .overlay(alignment: .top) {
                if let ribbon = offer.ribbon {
                    Ribbon(ribbon, colour: biggest ? Self.deepGold : Self.green).offset(y: -10 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(buying != nil)
        .accessibilityLabel("\(amount) Beans, \(price(offer.id) ?? "")\(offer.ribbon.map { ", \($0)" } ?? "")")
    }

    /// Room looks, each as its room: the look drawn in its room by the game, its name and room, what is in it, the
    /// price and "Try it" (or, owned, "Add the whole room"), side by side and scrolled.
    private var looksPage: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12 * s) {
                ForEach(lookOffers) { lookCard($0) }
            }
            .padding(.horizontal, 2 * s)
            .padding(.top, 10 * s)
            .padding(.bottom, 8 * s)
        }
        .scrollClipDisabled()
        .padding(.top, -10 * s)
        .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.pageGrowth)
    }

    private func lookCard(_ offer: Offer) -> some View {
        let mine = isOwned(offer)
        let room = offer.bundle?.room
        let open = room.map { session.state(at: session.now()).openedRooms.contains($0) } ?? false
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                feedback.tap()
                detail = offer
            } label: {
                lookPicture(offer)
                    .padding([.horizontal, .top], 10 * s)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(offer.title), see what is in it")
            HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                Text(offer.title).font(Theme.title(16 * s)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let room {
                    Text(Visit.title(of: room, upstairs: false)).font(font(10.5, .bold, rounded: true)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            .padding(.horizontal, 12 * s)
            .padding(.top, 8 * s)
            Text(mine ? "Yours: \(lookSummary(offer).lowercased())" : open || room == nil ? lookSummary(offer) : "\(lookSummary(offer)) · its room opens at level \(room?.requiredLevel ?? 1)")
                .font(font(11, .semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12 * s)
                .padding(.top, 2 * s)
            HStack(spacing: 8 * s) {
                if mine {
                    if open, let addLook, let bundle = offer.bundle {
                        PriceButton(text: "Add the whole room", style: .beans) {
                            feedback.tap()
                            dismiss()
                            addLook(bundle)
                        }
                    } else {
                        Label("Owned", systemImage: "checkmark.circle.fill").font(font(15, .heavy, rounded: true)).foregroundStyle(Self.green)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38 * s)
                    }
                } else {
                    PriceButton(text: buying == offer.id ? "…" : price(offer.id) ?? "…", style: .money) {
                        feedback.tap()
                        detail = offer
                    }
                    if open, let tryLook, let bundle = offer.bundle {
                        PriceButton(text: "Try it", style: .cream) {
                            feedback.tap()
                            dismiss()
                            tryLook(bundle)
                        }
                        .accessibilityLabel("Try \(offer.title) in your room")
                    }
                }
            }
            .padding(.horizontal, 10 * s)
            .padding(.top, 8 * s)
            .padding(.bottom, 12 * s)
        }
        .frame(width: 252 * s)
        .goldTile(s)
        .overlay(alignment: .topLeading) {
            if mine {
                Ribbon("Owned", colour: Self.green).offset(x: 12 * s, y: -10 * s)
            } else if let ribbon = offer.ribbon {
                Ribbon(ribbon).offset(x: 12 * s, y: -10 * s)
            }
        }
    }

    /// Outfits, bought with Beans: the way to try them on first, then every outfit on sale in a grid.
    private var outfitsPage: some View {
        HStack(spacing: 12 * s) {
            if tryOutfits != nil {
                tryOnTile.frame(width: 200 * s)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.flexible(), spacing: 12 * s), GridItem(.flexible(), spacing: 12 * s)], spacing: 10 * s) {
                    ForEach(outfitOffers) { outfitTile($0) }
                }
                .padding(.vertical, 10 * s)
                .padding(.horizontal, 2 * s)
            }
            .scrollClipDisabled()
            .padding(.vertical, -10 * s)
        }
        .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.pageGrowth)
    }

    /// Into the wardrobe, where the cat tries outfits on before a Bean is spent.
    private var tryOnTile: some View {
        Button {
            feedback.tap()
            dismiss()
            tryOutfits?(nil)
        } label: {
            VStack(spacing: 0) {
                band("Try them on", colour: Self.plum)
                glowArt(["ui/shop/shop_tryon.png"])
                    .padding(.vertical, 4 * s)
                Text("See every outfit on \(catName) before you spend a Bean.")
                    .font(font(11.5, .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12 * s)
                PriceButton(text: "Open the wardrobe", style: .gold)
                    .padding(.horizontal, 10 * s)
                    .padding(.top, 8 * s)
                    .padding(.bottom, 12 * s)
            }
            .goldTile(s, fill: Self.butter)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Try the outfits on \(catName)")
    }

    private func outfitTile(_ offer: Offer) -> some View {
        Button {
            feedback.tap()
            detail = offer
        } label: {
            VStack(spacing: 2 * s) {
                glowArt(offer.art)
                    .padding(.top, 8 * s)
                // A long name ("Fisherman's jumper") shrinks a little, then takes a second line, never cut short.
                Text(offer.title).font(font(12, .heavy, rounded: true)).lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4 * s)
                priceTag(offer, compact: true)
                    .padding(.horizontal, 8 * s)
                    .padding(.bottom, 9 * s)
                    .padding(.top, 2 * s)
            }
            .frame(width: 112 * s)
            .goldTile(s, corner: 16)
            .overlay(alignment: .top) {
                if let ribbon = offer.ribbon, !isOwned(offer) {
                    Ribbon(ribbon).scaleEffect(0.78).offset(y: -9 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(offer.title), \(isOwned(offer) ? "owned" : "\(Tuning.Beans.outfit) Beans")")
    }

    // MARK: Cat Club

    /// The Cat Club page, one screen: the crowned cat, the perks as big numbers, the two plans side by side, the
    /// button with the price that will be charged, the renewal terms in full, and Restore Purchases, the terms and
    /// the privacy policy (App Review 3.1.2). Only perks the game has are listed.
    private var clubPage: some View {
        HStack(alignment: .top, spacing: 10 * s) {
            VStack(spacing: 4 * s) {
                glowArt(["ui/shop/shop_club.png"], warm: false, alignment: .bottom)
                Text("Cat Club").font(Theme.title(30 * s)).foregroundStyle(.white)
                Text(owned.hasClub ? "You're a member. Thank you." : "A membership, renewed until you cancel")
                    .font(font(11, .bold)).foregroundStyle(GameHUD.gold)
                    .multilineTextAlignment(.center)
                if let pass {
                    Text("This season's premium track: \(pass.season.paidTrack.count) rewards in \(pass.name).")
                        .font(font(10.5, .semibold)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12 * s)
            .frame(width: 240 * s)
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 9 * s) {
                Grid(horizontalSpacing: 9 * s, verticalSpacing: 9 * s) {
                    GridRow {
                        perk("+20%", "Beans on all you earn", icon: "bean_coin")
                        perk("½", "the Beans to open rooms", icon: "house")
                    }
                    GridRow {
                        perk("Free", "moving home", icon: "map_pin")
                        // The pass perk only while a season is on (nothing to show before the first one).
                        if pass != nil {
                            perk("Every", "season's premium track", icon: "season_pass_ticket")
                        } else {
                            perk("Cancel", "any time, in Settings", icon: "clock")
                        }
                    }
                }
                if owned.hasClub {
                    Text("Every perk is on. Your subscription is in Settings, or Manage subscription below.")
                        .font(font(12, .semibold)).foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    PriceButton(text: "Manage subscription", style: .gold) { openURL(Tuning.Store.manageSubscriptionsURL) }
                        .frame(width: 230 * s)
                } else {
                    HStack(spacing: 9 * s) {
                        plan(yearly: true)
                        plan(yearly: false)
                    }
                    HStack(alignment: .center, spacing: 12 * s) {
                        // The price that will be charged is on the button itself (App Review 3.1.2: the billed
                        // amount is the clearest pricing on the page, the free days second).
                        PriceButton(
                            text: yearly ? "\(price(StoreCatalog.clubYearly) ?? "…") a year" : "\(price(StoreCatalog.clubMonthly) ?? "…") a month",
                            style: .gold
                        ) {
                            feedback.tap()
                            buy(yearly ? StoreCatalog.clubYearly : StoreCatalog.clubMonthly, offer: clubOffer)
                        }
                        .frame(width: 210 * s)
                        .disabled(buying != nil)
                        Text(clubTerms)
                            .font(font(10.5, .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                clubLinks
            }
            .padding(.vertical, 16 * s)
            .padding(.trailing, 16 * s)
        }
        .goldTile(s, fill: Self.dusk)
        .frame(maxHeight: Tuning.Shop.pageHeight * s * Tuning.Shop.cardGrowth)
    }

    private var clubTerms: String {
        ClubWording.terms(
            yearly: yearly,
            yearPrice: price(StoreCatalog.clubYearly),
            monthPrice: price(StoreCatalog.clubMonthly),
            trialDays: prices.products[StoreCatalog.clubYearly]?.trialDays
        )
    }

    /// Restore Purchases, the terms and the privacy policy, on the page that sells the subscription.
    private var clubLinks: some View {
        HStack(spacing: 18 * s) {
            Spacer(minLength: 0)
            Button(restoring ? "Restoring…" : "Restore Purchases") { restore() }
                .disabled(store == nil || restoring)
            Link("Terms of Use", destination: Tuning.Store.termsURL)
            Link("Privacy Policy", destination: Tuning.Store.privacyURL)
        }
        .font(font(12, .heavy, rounded: true))
        .tint(.white)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func perk(_ big: String, _ detail: String, icon: String) -> some View {
        HStack(spacing: 8 * s) {
            PaintedIcon(icon, size: 34 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(big).font(font(21, .heavy, rounded: true)).foregroundStyle(GameHUD.gold).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(font(11, .semibold)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * s)
        .padding(.vertical, 8 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(.white.opacity(0.1)))
    /// The trial is named only when StoreKit says this player may take it (`ProductInfo.trialDays`; App Review
    /// 3.1.2): a lapsed or current subscriber sees the renewal price alone.
        .overlay(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).strokeBorder(.white.opacity(0.13), lineWidth: 1))
    }

    /// A plan card: the yearly one with its trial (when this player gets one) and its price a month, the monthly one.
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
                    .font(font(15, .heavy, rounded: true))
                Text(ClubWording.planLine(yearly: isYearly, perMonth: perMonth, trialDays: prices.products[id]?.trialDays))
                    .font(font(11, .semibold))
                    .opacity(0.88)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 11 * s)
            .padding(.vertical, 8 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(.white.opacity(chosen ? 0.22 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 13 * s, style: .continuous)
                .strokeBorder(chosen ? GameHUD.gold : .white.opacity(0.25), lineWidth: chosen ? 2.5 * s : 1))
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

    // MARK: Tile pieces

    private static let deepGold = GameHUD.deepGold
    private static let green = Color(red: 0.33, green: 0.63, blue: 0.25)
    private static let rust = Color(red: 0.76, green: 0.39, blue: 0.17)
    private static let terracotta = Color(red: 0.84, green: 0.47, blue: 0.22)
    private static let honey = Color(red: 0.84, green: 0.6, blue: 0.18)
    private static let plum = Color(red: 0.5, green: 0.34, blue: 0.56)
    private static let butter = LinearGradient(
        colors: [Color(red: 1, green: 0.97, blue: 0.88), Color(red: 0.97, green: 0.88, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Cat Club's and the pass's evening blue to plum.
    private static let dusk = LinearGradient(
        colors: [Color(red: 0.2, green: 0.38, blue: 0.47), Color(red: 0.31, green: 0.24, blue: 0.43), Color(red: 0.37, green: 0.25, blue: 0.46)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A tile's title on its coloured band, as a builder game heads its cards.
    private func band(_ title: String, colour: Color) -> some View {
        Text(title)
            .font(Theme.title(16 * s))
            .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.9))
            .shadow(color: .black.opacity(0.3), radius: 0, y: 1.5 * s)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8 * s)
            // Low in the band, clear of a ribbon over its top edge.
            .padding(.top, 5 * s)
            .frame(maxWidth: .infinity)
            .frame(height: 36 * s)
            .background(LinearGradient(colors: [colour.mix(with: .white, by: 0.15), colour.mix(with: .black, by: 0.08)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.12)).frame(height: 1.5 * s) }
    }

    /// A picture over a soft warm glow, filling the space it is given.
    private func glowArt(_ art: [String], warm: Bool = true, alignment: Alignment = .center) -> some View {
        artView(art)
            .padding(.horizontal, 8 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [(warm ? Color(red: 1, green: 0.94, blue: 0.72) : Color(red: 1, green: 0.9, blue: 0.62).opacity(0.55)), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110 * s
                    ))
                    .padding(6 * s)
            }
    }

    private func lines(_ contents: [Offer.Line]) -> some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            ForEach(contents, id: \.text) { line in
                HStack(spacing: 6 * s) {
                    PaintedIcon(line.icon, size: 20 * s)
                    Text(line.text).font(font(12.5, .bold, rounded: true)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12 * s)
    }

    /// The price as a raised button (in Beans for an outfit, with Top up when they fall short), or Owned.
    @ViewBuilder
    private func priceTag(_ offer: Offer, compact: Bool = false) -> some View {
        if isOwned(offer) {
            HStack(spacing: 4 * s) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Self.green)
                Text("Owned").font(font(compact ? 13 : 15, .heavy, rounded: true))
            }
            .frame(maxWidth: .infinity)
            .frame(height: (compact ? 30 : 38) * s)
        } else if let cost = offer.beanPrice {
            PriceButton(text: cost > beans ? "Top up" : cost.formatted(), icon: cost > beans ? nil : "bean_coin", style: .beans, compact: compact)
        } else {
            PriceButton(text: buying == offer.id ? "…" : price(offer.id) ?? "…", style: .money, compact: compact)
        }
    }

    private func artView(_ art: [String], shadow: Bool = true) -> some View {
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
        .shadow(color: .black.opacity(shadow ? 0.2 : 0), radius: 6 * s, y: 4 * s)
    }

    // MARK: Detail

    /// Before buying: the offer big, everything in it, the price, Close. A room look can be tried in its room
    /// first and, once owned, put in all at once; an outfit can be wrapped for a co-owner to find.
    private func detailPanel(_ offer: Offer) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { detail = nil }
            VStack(spacing: 0) {
                band(offer.title, colour: offer.bundle != nil ? Self.green.mix(with: .white, by: 0.1) : offer.beanPrice != nil ? Self.plum : Self.terracotta)
                HStack(spacing: 20 * s) {
                    artView(offer.art).frame(width: 250 * s, height: 190 * s)
                    VStack(alignment: .leading, spacing: 9 * s) {
                        if let ribbon = offer.ribbon, !isOwned(offer) {
                            Ribbon(ribbon)
                        }
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
                    .frame(width: 290 * s, alignment: .leading)
                }
                .padding(.horizontal, 20 * s)
                .padding(.vertical, 16 * s)
            }
            // Its own size, never squeezed (a squeezed button cuts its price short).
            .frame(width: 600 * s)
            .fixedSize(horizontal: false, vertical: true)
            .goldPanel(s)
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
                ChunkyButton("Buy for \(price(offer.id) ?? "…")", colour: Self.green) { buy(offer.id, offer: offer) }
                    .disabled(buying != nil)
                if roomOpen, let tryLook {
                    Button {
                        feedback.tap()
                        detail = nil
                        dismiss()
                        tryLook(bundle)
                    } label: {
                        Label("Try it in your room", systemImage: "eye").font(font(13, .bold)).foregroundStyle(Self.rust)
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
            if let outfit = offer.outfitID, let tryOutfits {
                Button {
                    feedback.tap()
                    detail = nil
                    dismiss()
                    tryOutfits(outfit)
                } label: {
                    Label("Try it on \(catName)", systemImage: "eye").font(font(13, .bold)).foregroundStyle(Self.rust)
                }
                .buttonStyle(PressStyle())
            }
            if session.isCoOwned {
                Button {
                    feedback.tap()
                    buyWithBeans(offer, gift: true)
                } label: {
                    Label("Wrap it as a present", systemImage: "gift").font(font(13, .bold)).foregroundStyle(Self.rust)
                }
                .buttonStyle(PressStyle())
            }
        } else {
            ChunkyButton("Buy for \(price(offer.id) ?? "…")", colour: Self.green) { buy(offer.id, offer: offer) }
                .disabled(buying != nil)
            #if DEBUG
                if store == nil {
                    Text("Debug preview: nothing is charged.").font(font(10)).foregroundStyle(Theme.inkSoft)
                }
            #endif
        }
    }
}

/// A room look's picture in its room (assets/ui/shop/shop_look_<bundle id>.png, drawn by the game's
/// LookPreviewRender test).
enum LookArt {
    static func path(_ bundleID: String) -> String {
        "ui/shop/shop_look_\(bundleID).png"
    }
}

/// A shop tile's frame: a gold rim with a cream line inside it, on cream (or the colours given), with a soft shadow.
private struct GoldTile<Fill: ShapeStyle>: ViewModifier {
    let scale: CGFloat
    let fill: Fill
    let corner: CGFloat
    /// A tile fills the space its page gives it; a panel keeps its own size.
    var expands = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner * scale, style: .continuous)
        content
            .frame(maxWidth: expands ? .infinity : nil, maxHeight: expands ? .infinity : nil)
            .background(shape.fill(fill))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(red: 1, green: 0.96, blue: 0.84), lineWidth: 4.5 * scale))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom),
                lineWidth: 3 * scale
            ))
            .shadow(color: Color(red: 0.35, green: 0.17, blue: 0.05).opacity(0.3), radius: 7 * scale, y: 5 * scale)
    }
}

private extension View {
    func goldTile(_ scale: CGFloat, corner: CGFloat = 18) -> some View {
        modifier(GoldTile(
            scale: scale,
            fill: LinearGradient(colors: [Theme.cream, Color(red: 0.97, green: 0.89, blue: 0.76)], startPoint: .top, endPoint: .bottom),
            corner: corner
        ))
    }

    func goldTile(_ scale: CGFloat, fill: some ShapeStyle, corner: CGFloat = 18) -> some View {
        modifier(GoldTile(scale: scale, fill: fill, corner: corner))
    }

    /// The detail panel's frame: the tiles' gold rim at the panel's own size.
    func goldPanel(_ scale: CGFloat) -> some View {
        modifier(GoldTile(
            scale: scale,
            fill: LinearGradient(colors: [Theme.cream, Color(red: 0.97, green: 0.89, blue: 0.76)], startPoint: .top, endPoint: .bottom),
            corner: 24,
            expands: false
        ))
    }
}

/// A raised price button with a darker lip under it, as in a builder game's shop: green for money, orange for Beans,
/// gold for Cat Club and the pass, cream for a second choice. With an action it is a button of its own; without, it
/// is the label of the tile it sits on.
struct PriceButton: View {
    enum Style {
        case money, beans, gold, cream
    }

    @Environment(\.hudScale) private var s
    let text: String
    var icon: String?
    var style: Style
    var compact = false
    var action: (() -> Void)?

    init(text: String, icon: String? = nil, style: Style, compact: Bool = false, action: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.style = style
        self.compact = compact
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { label }.buttonStyle(PressStyle())
        } else {
            label
        }
    }

    private var colour: Color {
        switch style {
        case .money: Color(red: 0.36, green: 0.66, blue: 0.27)
        case .beans: Color(red: 0.88, green: 0.48, blue: 0.2)
        case .gold: Color(red: 0.86, green: 0.6, blue: 0.16)
        case .cream: Color(red: 0.97, green: 0.91, blue: 0.8)
        }
    }

    private var label: some View {
        HStack(spacing: 3 * s) {
            if let icon {
                PaintedIcon(icon, size: (compact ? 17 : 22) * s)
            }
            Text(text).font(.system(size: (compact ? 14 : 18) * s, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(style == .cream ? Theme.ink : .white)
        .shadow(color: .black.opacity(style == .cream ? 0 : 0.28), radius: 0, y: 1)
        .padding(.horizontal, 8 * s)
        .frame(maxWidth: .infinity)
        .frame(height: (compact ? 30 : 38) * s)
        .background {
            ZStack {
                Capsule().fill(style == .cream ? Color(red: 0.74, green: 0.56, blue: 0.3) : colour.mix(with: .black, by: 0.32)).offset(y: (compact ? 3 : 4) * s)
                Capsule().fill(LinearGradient(colors: [colour.mix(with: .white, by: 0.2), colour], startPoint: .top, endPoint: .bottom))
                Capsule().strokeBorder(style == .cream ? GameHUD.deepGold.opacity(0.8) : .white.opacity(0.35), lineWidth: 1.5 * s).padding(0.5)
            }
        }
        .padding(.bottom, (compact ? 3 : 4) * s)
        .contentShape(Capsule())
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

/// Restore Purchases (the shop, the Cat Club page and the cat's settings), told truthfully: what came back from the
/// Apple Account, that there was nothing to restore, or that the App Store could not be reached.
enum RestorePurchases {
    @MainActor
    static func run(_ store: (any EntitlementService)?) async -> String {
        guard let store else {
            return "The App Store can't be reached from here, so nothing was restored."
        }
        do {
            try await store.restore()
        } catch StoreKitError.userCancelled {
            return "Restore cancelled."
        } catch {
            return "Couldn't reach the App Store, so nothing was restored. "
                + "Check you're online and signed in, then try again."
        }
        let owned = store.entitlements
        var found: [String] = []
        if owned.hasClub {
            found.append("Cat Club")
        }
        if owned.starter {
            found.append("the starter pack")
        }
        if !owned.bundles.isEmpty {
            found.append(owned.bundles.count == 1 ? "a room look" : "\(owned.bundles.count) room looks")
        }
        if !owned.passes.isEmpty {
            found.append(owned.passes.count == 1 ? "a season's premium pass" : "\(owned.passes.count) seasons' premium passes")
        }
        guard !found.isEmpty else {
            return "Nothing to restore on this Apple Account. Beans are spent in the game, so they don't come back."
        }
        return "Restored " + ListFormatter.localizedString(byJoining: found) + "."
    }
}
