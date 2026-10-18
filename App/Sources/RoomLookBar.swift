import HouseCatCore
import HouseCatStore
import HouseCatUI
import SwiftUI

/// Over the room while a room look is being tried (the shop's "Try it in your room"; IKEA's whole-room view):
/// its name and price, Buy (which puts it all in) and Not now. Owned already, it offers Add the whole room.
struct RoomLookBar: View {
    let bundle: BundlesFile.Bundle
    let store: (any EntitlementService)?
    let add: () -> Void
    let close: () -> Void
    @State private var prices = StorePrices.shared
    @State private var buying = false
    @State private var message: String?

    private var owned: Bool {
        store?.entitlements.bundles.contains(bundle.id) == true
            || GameSession.shared.state(at: GameSession.shared.now()).grantedBundles.values.contains(bundle.id)
    }

    private var surfaces: String {
        switch (bundle.wallpaper != nil, bundle.floor != nil) {
        case (true, true): ", the wallpaper and floor"
        case (true, false): " and the wallpaper"
        case (false, true): " and the floor"
        case (false, false): ""
        }
    }

    /// The bar's height at scale 1, for lifting the room above it.
    static let height: CGFloat = 96

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trying \(bundle.name)").font(Theme.title(19))
                Text(message ?? "\(bundle.items.count) pieces\(surfaces). Nothing changes until you buy it.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            HUDButton("Not now", action: close)
            if owned {
                HUDButton("Add the whole room", icon: "sofa_for_furniture", prominent: true, action: add)
            } else {
                HUDButton(buying ? "…" : "Buy for \(prices.price(bundle.sku) ?? "…")", icon: "shop_bag", prominent: true) { buy() }
                    .disabled(buying)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 680)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(Theme.ink)
        .task {
            if prices.products.isEmpty {
                await prices.load(store: store, content: GameWorld.content)
            }
        }
    }

    private func buy() {
        buying = true
        Task {
            defer { buying = false }
            switch await ShopPurchase.buy(bundle.sku, store: store) {
            case .bought:
                Sound.play("ui_purchase_confirm", volume: Tuning.Sound.levelUp)
                add()
            case .pending: message = "Waiting for approval."
            case .cancelled: break
            case .failed: message = "That purchase did not go through."
            }
        }
    }
}
