import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI

/// StoreKit's prices for every product, loaded once and shared by the shop, the top-up and the tray. Without
/// StoreKit (debug screenshot runs) the catalogue's own UK prices.
@MainActor
@Observable
final class StorePrices {
    static let shared = StorePrices()

    private(set) var products: [String: ProductInfo] = [:]
    private(set) var unavailable = false

    func load(store: (any EntitlementService)?, content: ContentBundle?) async {
        if let store {
            do {
                products = try await Dictionary(store.products().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                unavailable = false
            } catch {
                unavailable = products.isEmpty
            }
        } else if let content {
            #if DEBUG
                let pounds = StoreCatalog(content: content).products.map {
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

    func price(_ id: String) -> String? {
        products[id]?.displayPrice
    }

    /// What some Beans cost in money, at the smallest pack's rate (the dearest a Bean ever is). The EU consumer
    /// authorities' principles on in-game currencies (March 2025) ask for the real price beside a virtual one.
    func value(ofBeans beans: Int) -> String? {
        guard let pack = StoreCatalog.beanPacks.first, let product = products[pack.id], let price = product.price,
              let code = product.currencyCode, beans > 0 else { return nil }
        let value = price * Decimal(beans) / Decimal(pack.beans)
        return value.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    /// How many more Beans a pound buys in a pack than in the smallest one ("+49%"), from the prices shown.
    func bonus(_ pack: (id: String, beans: Int, price: String, name: String)) -> Int? {
        guard let first = StoreCatalog.beanPacks.first, first.id != pack.id,
              let small = products[first.id]?.price, let this = products[pack.id]?.price, small > 0, this > 0 else { return nil }
        let rate = Double(pack.beans) / NSDecimalNumber(decimal: this).doubleValue
        let base = Double(first.beans) / NSDecimalNumber(decimal: small).doubleValue
        let percent = Int(((rate / base - 1) * 100).rounded())
        return percent > 0 ? percent : nil
    }
}

/// A Bean pack's picture (assets/ui/shop/shop_beans_<size>.png).
enum BeanArt {
    static func path(_ packID: String) -> String {
        "ui/shop/shop_beans_\(packID.split(separator: ".").last ?? "handful").png"
    }
}

/// Buying a product (a Bean pack, the starter, a room look, Cat Club), then telling the caller; Beans and looks
/// arrive in the save through the store's grant (once per transaction, a pack finished only after).
@MainActor
enum ShopPurchase {
    enum Result {
        case bought
        case pending
        case cancelled
        case failed
    }

    static func buy(_ id: String, store: (any EntitlementService)?) async -> Result {
        guard let store else {
            #if DEBUG
                // Debug runs without StoreKit: the Beans as if bought, so the flow can be seen.
                if let content = GameWorld.content {
                    GameSession.shared.grant(StoreGrant(productID: id, transactionID: "debug-\(UUID().uuidString)"), catalog: StoreCatalog(content: content))
                    return .bought
                }
            #endif
            return .failed
        }
        do {
            switch try await store.purchase(id) {
            case .purchased:
                Analytics.track(.purchased, detail: id)
                return .bought
            case .pending: return .pending
            case .cancelled: return .cancelled
            }
        } catch {
            return .failed
        }
    }
}

/// When something costs more Beans than the player has (Josh, 18 Oct): Buy becomes Top up, and this sheet offers
/// the smallest pack that covers it first, the bigger ones beside it, each with its real price, bought in place.
/// No timer, no pressure line, Close always there, and a reminder that Beans are earned every day too.
struct BeanTopUp: View {
    /// Beans still needed.
    let need: Int
    /// What they are for ("the Raincoat").
    let purpose: String
    let store: (any EntitlementService)?
    let done: (_ bought: Bool) -> Void
    @State private var prices = StorePrices.shared
    @State private var buying: String?
    @State private var message: String?
    @Environment(\.controlFeedback) private var feedback

    /// The smallest pack that covers it, then the bigger ones (all of them when even the biggest falls short).
    private var packs: [(id: String, beans: Int, price: String, name: String)] {
        let all = StoreCatalog.beanPacks
        guard let first = all.firstIndex(where: { $0.beans >= need }) else { return all.reversed().prefix(3).reversed() }
        return Array(all[first ..< min(all.count, first + 3)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(need.formatted()) more Beans").font(Theme.title(25))
                    Text("for \(purpose). A pack tops you up, or keep looking after your cat: Beans come every day.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CloseButton { done(false) }
            }
            HStack(spacing: 12) {
                ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                    packTile(pack, recommended: index == 0 && pack.beans >= need)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Text("Beans are kept with your cat's home and shared with anyone who looks after it with you.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(20)
        .frame(maxWidth: 600)
        .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Theme.ink)
        .task {
            if prices.products.isEmpty {
                await prices.load(store: store, content: GameWorld.content)
            }
        }
    }

    private func packTile(_ pack: (id: String, beans: Int, price: String, name: String), recommended: Bool) -> some View {
        Button {
            feedback.tap()
            buy(pack.id)
        } label: {
            VStack(spacing: 4) {
                CatScreens.picture(BeanArt.path(pack.id)).map { $0.resizable().interpolation(.high).scaledToFit() }
                    .frame(height: 78)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
                HStack(spacing: 3) {
                    PaintedIcon("bean_coin", size: 18)
                    Text(pack.beans.formatted()).font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                if let bonus = prices.bonus(pack) {
                    Text("+\(bonus)% a pound").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                }
                Spacer(minLength: 0)
                Text(buying == pack.id ? "…" : prices.price(pack.id) ?? "…")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accent))
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cream))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(recommended ? Theme.accent : Theme.rim, lineWidth: recommended ? 3 : 1))
            .overlay(alignment: .top) {
                if recommended {
                    Ribbon("Covers it").scaleEffect(0.8).offset(y: -10)
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(buying != nil)
        .accessibilityLabel("\(pack.beans) Beans, \(prices.price(pack.id) ?? "")")
    }

    private func buy(_ id: String) {
        buying = id
        Task {
            defer { buying = nil }
            switch await ShopPurchase.buy(id, store: store) {
            case .bought:
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
                done(true)
            case .pending: message = "Waiting for approval."
            case .cancelled: break
            case .failed: message = "That purchase did not go through."
            }
        }
    }
}

extension GameSession {
    /// A purchase's Beans or room look into the save (each transaction once; the reducer drops repeats).
    func grant(_ grant: StoreGrant, catalog: StoreCatalog) {
        guard let product = catalog.product(grant.productID) else { return }
        switch product.unlock {
        case let .beans(amount):
            append(.purchaseBeansGranted(transactionID: grant.transactionID, beans: amount), at: now())
        case let .starter(amount):
            // Its Beans, and the beanie and armchair in its picture, the first time this purchase is heard of.
            guard !state(at: now()).grantedTransactions.contains(grant.transactionID) else { return }
            append(.purchaseBeansGranted(transactionID: grant.transactionID, beans: amount), at: now())
            append(.outfitBought(outfitID: Tuning.Store.starterOutfit, beans: 0, gift: false), at: now())
            append(.itemGranted(itemID: Tuning.Store.starterPiece), at: now())
        case let .bundle(id):
            append(.bundleGranted(bundleID: id, transactionID: grant.transactionID), at: now())
        case .club:
            break
        }
    }
}
