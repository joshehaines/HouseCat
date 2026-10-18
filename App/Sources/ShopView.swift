import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The shop (SPEC "Monetisation and the shop"): Cat Club first, then the furniture sets, the outfits, the
/// packs, another cat and gifts, every price StoreKit's own. Nothing random, no currency, no countdown:
/// a seasonal item says the real day it goes off sale. Restore Purchases and the subscription's terms sit
/// at the foot.
struct ShopView: View {
    static func monthName(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1) % 12]
    }

    /// Nil when StoreKit is off (command-line screenshot runs): the shop then shows the catalogue's own UK
    /// prices in debug builds, and nothing can be bought.
    let store: (any EntitlementService)?
    let content: ContentBundle?
    @State private var prices: [String: String] = [:]
    @State private var message: String?
    @State private var buying: String?
    @State private var owned = Entitlements.none
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var catalog: StoreCatalog? {
        store?.catalog ?? content.map(StoreCatalog.init(content:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                club
                section("Furniture sets", icon: "sofa_for_furniture") { sets }
                section("Outfits", icon: "cat_face") { outfits }
                section("Packs", icon: "gift_box_with_a_ribbon") { packs }
                section("Gifts", icon: "share_arrow") { gifts }
                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .scrollClipDisabled()
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .overlay(alignment: .topTrailing) {
            CloseButton { dismiss() }.padding(18)
        }
        .task {
            owned = store?.entitlements ?? .none
            await loadPrices()
        }
    }

    // MARK: Prices and buying

    private func loadPrices() async {
        if let store {
            do {
                prices = try await Dictionary(store.products().map { ($0.id, $0.displayPrice) }, uniquingKeysWith: { a, _ in a })
            } catch {
                message = "The shop is not available right now."
            }
        } else {
            #if DEBUG
                prices = Dictionary(catalog?.products.map { ($0.id, "£" + $0.priceGBP) } ?? [], uniquingKeysWith: { a, _ in a })
            #endif
        }
    }

    private func buy(_ productID: String) {
        guard let store, buying == nil else { return }
        buying = productID
        Task {
            defer { buying = nil }
            do {
                switch try await store.purchase(productID) {
                case .purchased:
                    owned = store.entitlements
                    #if canImport(UIKit)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                case .pending: message = "Waiting for approval."
                case .cancelled: break
                }
            } catch {
                message = "That purchase did not go through."
            }
        }
    }

    /// The price button, or "Owned".
    @ViewBuilder
    private func price(_ productID: String, owned isOwned: Bool, prominent: Bool = false, label: String? = nil) -> some View {
        if isOwned {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text("Owned").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.inkSoft)
        } else if let price = prices[productID] {
            HUDButton(label.map { "\($0) · \(price)" } ?? price, prominent: prominent) { buy(productID) }
                .disabled(store == nil || buying != nil)
                .opacity(buying == productID ? 0.5 : 1)
                .accessibilityLabel("Buy for \(price)")
        } else {
            Text("…").foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            PaintedIcon("shop_bag", size: 44)
            Text("Shop").font(Theme.title(36))
            Spacer()
        }
    }

    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PaintedIcon(icon, size: 28)
                Text(title).font(Theme.title(22))
            }
            content()
        }
    }

    /// Cat Club: what it gives, the yearly plan with its trial, the monthly plan, and the renewal terms in full.
    private var club: some View {
        HStack(alignment: .top, spacing: 18) {
            PaintedIcon("cat_face", size: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text("Cat Club").font(Theme.title(26))
                VStack(alignment: .leading, spacing: 4) {
                    perk("trust_heart_with_a_paw_print", "A second cat, included")
                    perk("bean_coin", "+20% Beans on everything you earn")
                    perk("house", "Rooms open at half the Beans")
                    perk("cat_face", "An outfit of the month, every month")
                    perk("season_pass_ticket", "Every season pass's paid track")
                }
                if owned.hasClub {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                        Text(owned.lifetime ? "Yours forever" : owned.founders ? "Yours forever, founder" : "You're a member")
                            .font(.headline)
                    }
                } else {
                    HStack(spacing: 10) {
                        price(
                            StoreCatalog.clubYearly,
                            owned: false,
                            prominent: true,
                            label: "\(StoreCatalog.yearlyTrialDays) days free, then a year"
                        )
                        price(StoreCatalog.clubMonthly, owned: false, label: "Monthly")
                    }
                    if let yearly = prices[StoreCatalog.clubYearly], let monthly = prices[StoreCatalog.clubMonthly] {
                        Text(
                            "Yearly: free for \(StoreCatalog.yearlyTrialDays) days, then \(yearly) a year. Monthly: \(monthly) a month. "
                                + "Renews until you cancel, at least a day before it renews, in Settings."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous), fill: Theme.cream)
    }

    private func perk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            PaintedIcon(icon, size: 20)
            Text(text).font(.subheadline)
        }
    }

    /// Each set: three of its pieces, what comes with it, the set and the bundle with its outfit and Beans.
    private var sets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(content?.catalogue.sets ?? [], id: \.id) { set in
                    let pieces = (content?.catalogue.items ?? []).filter { $0.set == set.id }
                    let isOwned = owned.sets.contains(set.id)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom, spacing: -10) {
                            ForEach(Array(pieces.prefix(3).enumerated()), id: \.offset) { _, piece in
                                art(piece.sprites["R"] ?? piece.sprites.values.first ?? "")
                                    .frame(width: 74, height: 74)
                            }
                        }
                        .frame(height: 80)
                        Text(set.name).font(Theme.title(18))
                        Text("\(pieces.count) pieces, a wallpaper and a floor")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSoft)
                        price("housecat.set.\(set.id)", owned: isOwned)
                        if !isOwned, let bundle = prices["housecat.bundle.\(set.id)"] {
                            Button {
                                buy("housecat.bundle.\(set.id)")
                            } label: {
                                Text("Or \(bundle) with its outfit and \(set.bundleBeans) Beans")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(store == nil || buying != nil)
                        }
                    }
                    .padding(14)
                    .frame(width: 270, alignment: .leading)
                    .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    /// The outfits on sale today (seasonal ones in their months) and any already owned.
    private var outfits: some View {
        let today = DayClock().day(of: .now)
        let shown = (content?.outfits.outfits ?? []).filter { outfit in
            guard outfit.pool == .paid else { return false }
            return owned.outfits.contains(outfit.id) || ShopRules.isOnSale(months: outfit.months, on: today)
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
            ForEach(shown, id: \.id) { outfit in
                let isOwned = owned.outfits.contains(outfit.id)
                VStack(spacing: 6) {
                    art(outfit.sprites["tqfront"] ?? "").frame(height: 80)
                    Text(outfit.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let until = ShopRules.lastSaleDay(months: outfit.months, from: today), !isOwned {
                        // A real date, never a countdown.
                        Text("On sale until \(until.date.day) \(Self.monthName(until.month))")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    price("housecat.outfit.\(outfit.id)", owned: isOwned)
                        .scaleEffect(0.9)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 196)
                .paper(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var packs: some View {
        VStack(spacing: 10) {
            pack(
                StoreCatalog.starter,
                icon: "gift_box_with_a_ribbon",
                title: "Starter Pack",
                detail: "An outfit, a furniture set and 500 Beans. Once only.",
                owned: owned.starter
            )
            pack(
                StoreCatalog.housewarmingPack,
                icon: "house",
                title: "Housewarming Pack",
                detail: "A grand fireplace, a hi-fi, string lights, a welcome mat, a portrait of your house and 300 Beans.",
                owned: owned.housewarmingPack
            )
            pack(
                "housecat.cat.slot2",
                icon: "trust_heart_with_a_paw_print",
                title: "Adopt a Cat",
                detail: "A second cat, built in the cat builder, with a personality of its own.",
                owned: owned.catSlots.contains(2)
            )
            pack(
                StoreCatalog.lifetime,
                icon: "xp_star",
                title: "Forever Home",
                detail: "Cat Club, forever. Paid once.",
                owned: owned.lifetime || owned.founders
            )
        }
    }

    private func pack(_ productID: String, icon: String, title: String, detail: String, owned isOwned: Bool) -> some View {
        HStack(spacing: 14) {
            PaintedIcon(icon, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(18))
                Text(detail).font(.caption).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            price(productID, owned: isOwned)
        }
        .padding(14)
        .paper(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Gifts: the giver buys, the friend's cat brings it at their next visit.
    private var gifts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send a year of Cat Club, a cat, a set or a season pass. Your friend's cat brings it in, wrapped, at their next visit.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                price("housecat.gift.club.yearly", owned: false, label: "A year of Cat Club")
                price("housecat.gift.cat", owned: false, label: "A cat")
                price("housecat.gift.pass", owned: false, label: "A season pass")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 10) {
                HUDButton("Restore Purchases", symbol: "arrow.clockwise") {
                    Task {
                        try? await store?.restore()
                        owned = store?.entitlements ?? .none
                        message = "Purchases restored."
                    }
                }
                .disabled(store == nil)
                HUDButton("Manage subscription", symbol: "gearshape") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
            }
            HStack(spacing: 16) {
                Link("Terms of Use", destination: Tuning.Store.termsURL)
                Link("Privacy Policy", destination: Tuning.Store.privacyURL)
            }
            .font(.footnote.weight(.semibold))
            .tint(Theme.accent)
            Text("Everything here is paid for once and kept, except Cat Club, which renews. Nothing is random, and Beans are never sold.")
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 6)
    }

    /// A piece of the app's art by its path, or nothing.
    @ViewBuilder
    private func art(_ path: String) -> some View {
        if let image = CatScreens.picture(path) {
            image.resizable().interpolation(.high).scaledToFit()
        } else {
            Color.clear
        }
    }
}
