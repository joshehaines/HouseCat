import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI

/// The one time the game mentions the shop by itself (SPEC "The session loop": the starter pack and Cat Club are
/// offered once at trust tier 1): a card when the cat first trusts you a little, showing the two things with
/// their real prices and terms. Never blocking, never repeated, no countdown; Not now and Close are always there.
/// Whether it was shown is a device preference (the App Group's defaults), not game state: it grants nothing,
/// and each co-owner sees it once on their own phone.
@MainActor
enum Offers {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var trustOfferShown: Bool {
        get { defaults.bool(forKey: "offer.trust.shown") }
        set { defaults.set(newValue, forKey: "offer.trust.shown") }
    }

    /// The card is due: the cat has just reached the tier, and the player owns neither thing.
    static func due(tier: TrustTier, owned: Entitlements) -> Bool {
        !trustOfferShown && tier >= Tuning.Store.offerTrustTier && !(owned.starter && owned.hasClub)
    }
}

struct OfferCard: View {
    let catName: String
    let store: (any EntitlementService)?
    let content: ContentBundle?
    let look: () -> Void
    let close: () -> Void
    @State private var prices: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(catName) trusts you a little more").font(Theme.title(24))
                    Text("Two things in the shop, if you'd like them. Nothing here is needed to play.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                CloseButton(action: close)
            }
            HStack(spacing: 12) {
                offer(
                    art: "ui/shop/shop_starter.png",
                    title: "Starter Pack",
                    detail: "A furniture set, an outfit and 500 Beans. Once only.",
                    price: prices[StoreCatalog.starter]
                )
                offer(
                    art: "ui/shop/shop_club.png",
                    title: "Cat Club",
                    detail: "A second cat, +20% Beans and every season pass.",
                    price: prices[StoreCatalog.clubYearly].map { "\(StoreCatalog.yearlyTrialDays) days free, then \($0) a year" }
                )
            }
            HStack(spacing: 10) {
                Spacer()
                HUDButton("Not now", action: close)
                HUDButton("Have a look", icon: "shop_bag", prominent: true, action: look)
            }
        }
        .padding(20)
        .frame(maxWidth: 560)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
        .task { await loadPrices() }
    }

    private func offer(art: String, title: String, detail: String, price: String?) -> some View {
        HStack(spacing: 10) {
            if let picture = CatScreens.picture(art) {
                picture.resizable().scaledToFit().frame(width: 82, height: 82)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.title(17))
                Text(detail).font(.caption).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Text(price ?? " ").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
    }

    private func loadPrices() async {
        if let store, let products = try? await store.products() {
            prices = Dictionary(products.map { ($0.id, $0.displayPrice) }, uniquingKeysWith: { a, _ in a })
        } else if let content {
            // No StoreKit (debug runs): the catalogue's own UK prices.
            prices = Dictionary(StoreCatalog(content: content).products.map { ($0.id, "£" + $0.priceGBP) }, uniquingKeysWith: { a, _ in a })
        }
    }
}

/// Asking Apple for a refund from inside the app (App Review 5.1.1's refund sheet; SPEC "Monetisation"): the
/// player's purchases, newest first; one tapped opens StoreKit's own request sheet. A refunded item leaves at
/// the next refresh.
struct RefundView: View {
    let close: () -> Void
    @State private var purchases: [(id: UInt64, name: String, date: Date)] = []
    @State private var chosen: UInt64?
    @State private var asking = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if loaded, purchases.isEmpty {
                    Text("No purchases on this Apple Account yet.").foregroundStyle(Theme.inkSoft)
                }
                ForEach(purchases, id: \.id) { purchase in
                    Button {
                        chosen = purchase.id
                        asking = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(purchase.name).font(.headline).foregroundStyle(Theme.ink)
                                Text(purchase.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text("Request a refund").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Refunds")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
            .refundRequestSheet(for: chosen ?? 0, isPresented: $asking)
        }
        .task {
            var found: [(UInt64, String, Date)] = []
            for await result in Transaction.all {
                guard case let .verified(transaction) = result, transaction.revocationDate == nil else { continue }
                found.append((transaction.id, Self.name(transaction.productID), transaction.purchaseDate))
            }
            purchases = found.sorted { $0.2 > $1.2 }.map { (id: $0.0, name: $0.1, date: $0.2) }
            loaded = true
        }
    }

    /// "housecat.outfit.raincoat" as "Outfit: raincoat".
    static func name(_ productID: String) -> String {
        let parts = productID.split(separator: ".").dropFirst()
        guard let kind = parts.first else { return productID }
        let rest = parts.dropFirst().joined(separator: " ").replacingOccurrences(of: "_", with: " ")
        return rest.isEmpty ? kind.capitalized : "\(kind.capitalized): \(rest)"
    }
}
