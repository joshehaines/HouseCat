import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The shop (SPEC "Monetisation and the shop"), laid out like a builder game's shop: a rail of sections down
/// the left, big illustrated offers in a row, a Cat Club page that shows everything membership holds (as a
/// battle pass does), a detail panel before buying and a celebration after. Every price is StoreKit's own;
/// nothing is random, no currency is sold, nothing counts down (a seasonal item gives its real last day), the
/// two Cat Club plans sit side by side with the full renewal terms, and Close is always on screen.
struct ShopView: View {
    static func monthName(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1) % 12]
    }

    enum Section: String, CaseIterable, Identifiable {
        case featured, club, sets, outfits, cats, gifts

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .featured: "Featured"
            case .club: "Cat Club"
            case .sets: "Furniture"
            case .outfits: "Outfits"
            case .cats: "Cats & more"
            case .gifts: "Gifts"
            }
        }

        var icon: String {
            switch self {
            case .featured: "xp_star"
            case .club: "cat_face"
            case .sets: "sofa_for_furniture"
            case .outfits: "decorate_paintbrush"
            case .cats: "trust_heart_with_a_paw_print"
            case .gifts: "gift_box_with_a_ribbon"
            }
        }
    }

    /// Something to buy, as a tile and its detail panel.
    struct Offer: Identifiable, Equatable {
        struct Line: Equatable {
            var icon: String
            var text: String
        }

        struct Alternative: Equatable {
            var id: String
            var label: String
        }

        var id: String
        var title: String
        /// One illustration, or a few pieces of furniture side by side.
        var art: [String]
        var ribbon: String?
        var contents: [Line]
        var note: String?
        /// A second way to buy it (a set's bundle, with its outfit and Beans).
        var alternative: Alternative?
        var tint: Color
        var isClub = false
    }

    /// Nil when StoreKit is off (command-line screenshot runs): debug builds then show the catalogue's own UK
    /// prices, and Buy plays the celebration as a preview without charging anything.
    let store: (any EntitlementService)?
    let content: ContentBundle?
    @State private var products: [String: ProductInfo] = [:]
    @State private var message: String?
    @State private var buying: String?
    @State private var owned = Entitlements.none
    @State private var section: Section = .featured
    @State private var detail: Offer?
    @State private var celebrating: Offer?
    @State private var yearly = true
    @State private var refunding = false
    /// Everything is laid out for a landscape phone and scaled up to fill a bigger screen.
    @State private var s: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.controlFeedback) private var feedback

    private var catalog: StoreCatalog? {
        store?.catalog ?? content.map(StoreCatalog.init(content:))
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
                            group(.club) { clubPage }
                            group(.sets) { ForEach(setOffers) { tile($0) } }
                            group(.outfits) { outfitGrid }
                            group(.cats) { ForEach(catOffers) { tile($0) } }
                            group(.gifts) { ForEach(giftOffers) { tile($0) } }
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
            if let detail {
                detailPanel(detail)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            if let celebrating {
                Celebration(offer: celebrating, scale: s) { self.celebrating = nil }
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
        .environment(\.hudScale, s)
        .sheet(isPresented: $refunding) { RefundView { refunding = false } }
        .animation(.spring(duration: 0.35), value: detail)
        .animation(.easeOut(duration: 0.3), value: celebrating)
        .task {
            owned = store?.entitlements ?? .none
            await loadProducts()
            #if DEBUG
                // Screenshot runs: HOUSECAT_SHOP=<section>, detail (the Starter Pack's panel) or celebrate (Cat Club's).
                if let wanted = ProcessInfo.processInfo.environment["HOUSECAT_SHOP"] {
                    try? await Task.sleep(for: .seconds(1))
                    if let open = Section(rawValue: wanted) {
                        section = open
                    } else if wanted == "detail" {
                        detail = starter
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

    // MARK: Prices and buying

    private func loadProducts() async {
        if let store {
            do {
                products = try await Dictionary(store.products().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            } catch {
                message = "The shop is not available right now."
            }
        } else {
            #if DEBUG
                let pounds = (catalog?.products ?? []).map {
                    ($0.id, ProductInfo(
                        id: $0.id,
                        displayName: $0.displayName,
                        displayPrice: "£" + $0.priceGBP,
                        kind: $0.kind,
                        price: Decimal(string: $0.priceGBP),
                        currencyCode: "GBP"
                    ))
                }
                products = Dictionary(pounds, uniquingKeysWith: { a, _ in a })
            #endif
        }
    }

    private func price(_ id: String) -> String? {
        products[id]?.displayPrice
    }

    private func buy(_ id: String, offer: Offer) {
        guard buying == nil else { return }
        guard let store else {
            #if DEBUG
                // Debug preview: nothing is charged.
                detail = nil
                celebrate(offer)
            #endif
            return
        }
        buying = id
        Task {
            defer { buying = nil }
            do {
                switch try await store.purchase(id) {
                case .purchased:
                    owned = store.entitlements
                    detail = nil
                    celebrate(offer)
                case .pending: message = "Waiting for approval."
                case .cancelled: break
                }
            } catch {
                message = "That purchase did not go through."
            }
        }
    }

    private func celebrate(_ offer: Offer) {
        Sound.play("ui_purchase_confirm", volume: Tuning.Sound.levelUp)
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        celebrating = offer
    }

    private func isOwned(_ id: String) -> Bool {
        if id == StoreCatalog.clubMonthly || id == StoreCatalog.clubYearly {
            return owned.hasClub
        }
        if id == StoreCatalog.lifetime {
            return owned.lifetime || owned.founders
        }
        if id == StoreCatalog.starter {
            return owned.starter
        }
        if id == StoreCatalog.housewarmingPack {
            return owned.housewarmingPack
        }
        if id.hasPrefix("housecat.set.") {
            return owned.sets.contains(String(id.dropFirst("housecat.set.".count)))
        }
        if id.hasPrefix("housecat.outfit.") {
            return owned.outfits.contains(String(id.dropFirst("housecat.outfit.".count)))
        }
        if id.hasPrefix("housecat.cat.slot") {
            return owned.catSlots.contains(Int(id.dropFirst("housecat.cat.slot".count)) ?? 0)
        }
        return false
    }

    /// Several products' prices added up, in the player's own currency.
    private func sum(_ parts: [(id: String, count: Int)]) -> String? {
        var total = Decimal(0)
        var code: String?
        for part in parts {
            guard let product = products[part.id], let price = product.price else { return nil }
            total += price * Decimal(part.count)
            code = product.currencyCode
        }
        return code.map { total.formatted(.currency(code: $0)) }
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
        Offer(
            id: StoreCatalog.starter,
            title: "Starter Pack",
            art: ["ui/shop/shop_starter.png"],
            ribbon: "Once only",
            contents: [
                .init(icon: "sofa_for_furniture", text: "A furniture set"),
                .init(icon: "cat_face", text: "An outfit"),
                .init(icon: "bean_coin", text: "500 Beans"),
            ],
            note: sum([("housecat.set.cottagecore", 1), ("housecat.outfit.cardigan", 1)])
                .map { "A set and an outfit on their own: \($0), before the Beans." },
            tint: Color(red: 0.98, green: 0.8, blue: 0.6)
        )
    }

    private var housewarming: Offer {
        Offer(
            id: StoreCatalog.housewarmingPack,
            title: "Housewarming",
            art: ["ui/shop/shop_housewarming.png"],
            // Its real last day (UK DMCC: a limited offer states a true end date).
            ribbon: housewarmingSale.map { "Until \($0.lastDay.date.day) \(Self.monthName($0.lastDay.month))" },
            contents: [
                .init(icon: "house", text: "A grand fireplace"),
                .init(icon: "sofa_for_furniture", text: "Hi-fi, lights and a mat"),
                .init(icon: "decorate_paintbrush", text: "A portrait of your house"),
                .init(icon: "bean_coin", text: "300 Beans"),
            ],
            tint: Color(red: 0.96, green: 0.72, blue: 0.6)
        )
    }

    private var clubOffer: Offer {
        Offer(
            id: StoreCatalog.clubYearly,
            title: "Cat Club",
            art: ["ui/shop/shop_club.png"],
            contents: [
                .init(icon: "trust_heart_with_a_paw_print", text: "A second cat"),
                .init(icon: "bean_coin", text: "+20% Beans"),
                .init(icon: "season_pass_ticket", text: "Every season pass"),
            ],
            tint: Color(red: 0.42, green: 0.62, blue: 0.66),
            isClub: true
        )
    }

    private var setOffers: [Offer] {
        (content?.catalogue.sets ?? []).map { set in
            let pieces = (content?.catalogue.items ?? []).filter { $0.set == set.id }
            return Offer(
                id: "housecat.set.\(set.id)",
                title: set.name,
                art: pieces.prefix(3).compactMap { $0.sprites["R"] ?? $0.sprites.values.first },
                contents: [
                    .init(icon: "sofa_for_furniture", text: "\(pieces.count) pieces"),
                    .init(icon: "wallpaper_roll", text: "A wallpaper and a floor"),
                ],
                alternative: price("housecat.bundle.\(set.id)").map {
                    .init(id: "housecat.bundle.\(set.id)", label: "with its outfit and \(set.bundleBeans) Beans, \($0)")
                },
                tint: Color(red: 0.78, green: 0.85, blue: 0.72)
            )
        }
    }

    private var catOffers: [Offer] {
        [
            Offer(
                id: "housecat.cat.slot2",
                title: "Adopt a Cat",
                art: ["ui/shop/shop_adopt.png"],
                contents: [
                    .init(icon: "cat_face", text: "Made in the cat builder"),
                    .init(icon: "trust_heart_with_a_paw_print", text: "A personality of its own"),
                ],
                tint: Color(red: 0.98, green: 0.78, blue: 0.68)
            ),
            Offer(
                id: StoreCatalog.lifetime,
                title: "Forever Home",
                art: ["ui/shop/shop_forever.png"],
                ribbon: "Paid once",
                contents: [
                    .init(icon: "cat_face", text: "Cat Club, for good"),
                    .init(icon: "xp_star", text: "Every perk, no renewals"),
                ],
                tint: Color(red: 0.62, green: 0.72, blue: 0.9),
                isClub: true
            ),
        ]
    }

    private var giftOffers: [Offer] {
        [
            Offer(
                id: "housecat.gift.club.yearly",
                title: "A year of Cat Club",
                art: ["ui/shop/shop_gifts.png"],
                ribbon: "Gift",
                contents: [.init(icon: "share_arrow", text: "For a friend's cat")],
                note: "You get a link to send. Their cat brings it in, wrapped, at their next visit.",
                tint: Color(red: 0.95, green: 0.84, blue: 0.58)
            ),
            Offer(
                id: "housecat.gift.cat",
                title: "A cat",
                art: ["ui/shop/shop_adopt.png"],
                ribbon: "Gift",
                contents: [.init(icon: "share_arrow", text: "A cat for a friend")],
                note: "You get a link to send. Their new cat is waiting at their next visit.",
                tint: Color(red: 0.98, green: 0.78, blue: 0.68)
            ),
            Offer(
                id: "housecat.gift.pass",
                title: "A season pass",
                art: ["ui/shop/shop_gifts.png"],
                ribbon: "Gift",
                contents: [.init(icon: "season_pass_ticket", text: "This season's paid track")],
                note: "You get a link to send. Their cat brings it in, wrapped, at their next visit.",
                tint: Color(red: 0.85, green: 0.8, blue: 0.95)
            ),
        ]
    }

    @ViewBuilder
    private var featured: some View {
        clubBanner
        tile(starter)
        // Only during its sale (events.json), or for someone who has it.
        if housewarmingSale != nil || owned.housewarmingPack {
            tile(housewarming)
        }
    }

    /// The Housewarming pack's sale, while it is on (the first month after launch).
    private var housewarmingSale: EventDefinition? {
        guard let context = try? content?.rulesContext() else { return nil }
        let session = GameSession.shared
        let today = session.state(at: session.now()).clock.day(of: session.now())
        return EventRules.onSale(StoreCatalog.housewarmingPack, on: today, context: context)
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
                priceTag(offer.id)
            }
            .padding(12 * s)
            .frame(width: 204 * s, height: Tuning.Shop.tileHeight * s)
            .background(tileBackground(offer.tint))
            .overlay(alignment: .topLeading) {
                if let ribbon = offer.ribbon, !isOwned(offer.id) {
                    Ribbon(ribbon).offset(x: 10 * s, y: -8 * s)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(offer.title), \(price(offer.id) ?? "")")
    }

    private func tileBackground(_ tint: Color, corner: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner * s, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [tint.mix(with: .white, by: 0.5), tint], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Theme.cream, lineWidth: 4 * s))
            .overlay(shape.strokeBorder(Theme.rim, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
    }

    /// The price as a raised button, or Owned.
    @ViewBuilder
    private func priceTag(_ id: String, compact: Bool = false) -> some View {
        if isOwned(id) {
            HStack(spacing: 4 * s) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text("Owned").font(font(compact ? 13 : 15, .heavy, rounded: true))
            }
            .padding(.vertical, (compact ? 6 : 9) * s)
        } else {
            Text(price(id) ?? "…")
                .font(font(compact ? 14 : 18, .heavy, rounded: true))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, (compact ? 5 : 8) * s)
                .background {
                    ZStack {
                        Capsule().fill(Theme.accent.mix(with: .black, by: 0.3)).offset(y: (compact ? 3 : 4) * s)
                        Capsule().fill(LinearGradient(
                            colors: [Theme.accent.mix(with: .white, by: 0.18), Theme.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
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
                    Text("A second cat, +20% Beans, rooms for half the Beans, an outfit every month and every season pass.")
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

    /// The Cat Club page, one screen on a phone: the crowned cat and what the parts sold on their own come to,
    /// the perks as big numbers, the two plans side by side, the button and the renewal terms in full.
    private var clubPage: some View {
        HStack(alignment: .top, spacing: 14 * s) {
            VStack(spacing: 4 * s) {
                artView(["ui/shop/shop_club.png"]).frame(width: 160 * s, height: 140 * s)
                Text("Cat Club").font(Theme.title(28 * s)).foregroundStyle(.white)
                if let value = sum([("housecat.pass.\(currentSeasonID)", Tuning.Pass.seasonsPerYear), ("housecat.cat.slot2", 1)]) {
                    Text("A year's season passes and a second cat, bought on their own: \(value)")
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
                        perk("+1", "cat, its own self", icon: "trust_heart_with_a_paw_print")
                        perk("+20%", "Beans on all you earn", icon: "bean_coin")
                        perk("½", "the Beans for rooms", icon: "house")
                    }
                    GridRow {
                        perk("\(Tuning.Store.clubOutfitsPerYear)", "outfits a year", icon: "cat_face")
                        perk("\(Tuning.Pass.seasonsPerYear)", "season passes", icon: "season_pass_ticket")
                        perk("Early", "seasonal sets", icon: "sofa_for_furniture")
                    }
                }
                if owned.hasClub {
                    Text(owned.lifetime || owned.founders ? "Yours forever." : "You're a member. Thank you.")
                        .font(Theme.title(20 * s)).foregroundStyle(.white)
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

    private var currentSeasonID: String {
        content?.seasons.seasons.first?.id ?? "housewarming"
    }

    private var clubTerms: String {
        let year = price(StoreCatalog.clubYearly) ?? "…", month = price(StoreCatalog.clubMonthly) ?? "…"
        return "Yearly: free for \(StoreCatalog.yearlyTrialDays) days, then \(year) a year. Monthly: \(month) a month. "
            + "Renews automatically until you cancel, at least a day before it renews, in Settings."
    }

    private func perk(_ big: String, _ detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 5 * s) {
            PaintedIcon(icon, size: 24 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(big).font(font(21, .heavy, rounded: true)).foregroundStyle(Self.gold).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(font(10, .semibold)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(7 * s)
        .frame(width: 114 * s, height: 64 * s, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(.white.opacity(0.1)))
    }

    /// A plan card: the yearly one with its trial and its price a month, the monthly one.
    private func plan(yearly isYearly: Bool) -> some View {
        let chosen = yearly == isYearly
        let id = isYearly ? StoreCatalog.clubYearly : StoreCatalog.clubMonthly
        let perMonth = isYearly ? products[id].flatMap { product in
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

    private var outfitGrid: some View {
        let today = DayClock().day(of: .now)
        let shown = (content?.outfits.outfits ?? []).filter { outfit in
            guard outfit.pool == .paid else { return false }
            return owned.outfits.contains(outfit.id) || ShopRules.isOnSale(months: outfit.months, on: today)
        }
        let row = (Tuning.Shop.tileHeight - 12) / 2 * s
        return LazyHGrid(rows: [GridItem(.fixed(row), spacing: 12 * s), GridItem(.fixed(row), spacing: 12 * s)], spacing: 12 * s) {
            ForEach(shown, id: \.id) { outfit in
                let offer = Offer(
                    id: "housecat.outfit.\(outfit.id)",
                    title: outfit.name,
                    art: [outfit.sprites["tqfront"] ?? ""],
                    // A real last day, never a countdown.
                    ribbon: ShopRules.lastSaleDay(months: outfit.months, from: today)
                        .map { "Until \($0.date.day) \(Self.monthName($0.month))" },
                    contents: [.init(icon: "cat_face", text: "Fits every cat")],
                    tint: Color(red: 0.96, green: 0.88, blue: 0.8)
                )
                Button {
                    feedback.tap()
                    detail = offer
                } label: {
                    VStack(spacing: 3 * s) {
                        artView(offer.art).frame(height: 66 * s)
                        Text(outfit.name).font(font(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        priceTag(offer.id, compact: true)
                    }
                    .padding(9 * s)
                    .frame(width: 124 * s, height: row)
                    .background(tileBackground(offer.tint, corner: 18))
                    .overlay(alignment: .top) {
                        if let ribbon = offer.ribbon, !isOwned(offer.id) {
                            Ribbon(ribbon).scaleEffect(0.75).offset(y: -9 * s)
                        }
                    }
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: Detail and the foot

    /// Before buying: the offer big, everything in it, the price (and a second way to buy it), Close.
    private func detailPanel(_ offer: Offer) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { detail = nil }
            HStack(spacing: 20 * s) {
                artView(offer.art).frame(width: 230 * s, height: 220 * s)
                VStack(alignment: .leading, spacing: 9 * s) {
                    if let ribbon = offer.ribbon {
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
                    if isOwned(offer.id) {
                        Text("You own this.").font(font(16, .bold))
                    } else {
                        ChunkyButton("Buy for \(price(offer.id) ?? "…")") { buy(offer.id, offer: offer) }
                            .disabled(buying != nil)
                        if let alternative = offer.alternative {
                            Button {
                                feedback.tap()
                                buy(alternative.id, offer: offer)
                            } label: {
                                Text("Or the bundle, " + alternative.label)
                                    .font(font(12, .bold))
                                    .foregroundStyle(Theme.accent)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(buying != nil)
                        }
                        #if DEBUG
                            if store == nil {
                                Text("Debug preview: nothing is charged.").font(font(10)).foregroundStyle(Theme.inkSoft)
                            }
                        #endif
                    }
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text("ALSO").font(font(13, .heavy, rounded: true)).tracking(1.2).foregroundStyle(Theme.inkSoft)
            if let message {
                Text(message).font(font(12)).foregroundStyle(Theme.inkSoft)
            }
            HUDButton("Restore Purchases", symbol: "arrow.clockwise") {
                Task {
                    try? await store?.restore()
                    owned = store?.entitlements ?? .none
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
            Text("Everything is paid for once and kept, except Cat Club, which renews. Nothing is random, and Beans are never sold.")
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.76).ignoresSafeArea()
            // Drawn over a clear layer so its size never reaches the layout.
            Color.clear
                .overlay {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSince(start)
                        ZStack {
                            sunburst.rotationEffect(.degrees(t * 10))
                            confetti(t)
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
