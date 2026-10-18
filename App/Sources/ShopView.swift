import HouseCatCore
import HouseCatStore
import HouseCatUI
import StoreKit
import SwiftUI

/// Placeholder shop for milestone 0: the outfits with their real StoreKit
/// prices, Buy, and Restore Purchases. The designed shop comes in step 7.
struct ShopView: View {
    static func monthName(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1) % 12]
    }

    let store: any EntitlementService
    @State private var products: [ProductInfo] = []
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Outfits") {
                    ForEach(outfits, id: \.id) { product in
                        row(product)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Restore Purchases") {
                        Task {
                            try? await store.restore()
                            message = "Purchases restored."
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Shop")
            .toolbar {
                Button("Done") { dismiss() }
            }
            .task {
                do {
                    products = try await store.products().sorted { $0.displayName < $1.displayName }
                } catch {
                    message = "The shop is not available right now."
                }
            }
        }
    }

    /// Today's game day; the app's clock comes from the save once the event log is wired in.
    private var today: GameDay {
        DayClock().day(of: .now)
    }

    private func isOwned(_ product: ProductInfo) -> Bool {
        store.entitlements.outfits.contains(String(product.id.dropFirst("housecat.outfit.".count)))
    }

    /// Outfits on sale today, plus any already owned. Seasonal ones come back every year.
    private var outfits: [ProductInfo] {
        products.filter { product in
            guard product.id.hasPrefix("housecat.outfit.") else { return false }
            return isOwned(product) || store.catalog.product(product.id)?.isOnSale(on: today) != false
        }
    }

    private func row(_ product: ProductInfo) -> some View {
        let owned = isOwned(product)
        let months = store.catalog.product(product.id)?.months ?? []
        let until = ShopRules.lastSaleDay(months: months, from: today)
        return HStack {
            VStack(alignment: .leading) {
                Text(product.displayName)
                if let until, !owned {
                    // A real date, never a countdown.
                    Text("On sale until \(until.date.day) \(Self.monthName(until.month))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if owned {
                Label("Owned", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            } else {
                Button(product.displayPrice) {
                    Task {
                        do {
                            _ = try await store.purchase(product.id)
                        } catch {
                            message = "That purchase did not go through."
                        }
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Buy \(product.displayName) for \(product.displayPrice)")
            }
        }
    }
}
