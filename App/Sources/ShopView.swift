import HouseCatStore
import StoreKit
import SwiftUI

/// Placeholder shop for milestone 0: the outfits with their real StoreKit
/// prices, Buy, and Restore Purchases. The designed shop comes in step 7.
struct ShopView: View {
    let store: any EntitlementService
    @State private var products: [ProductInfo] = []
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Outfits") {
                    ForEach(products.filter { $0.id.hasPrefix("housecat.outfit.") }, id: \.id) { product in
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

    private func row(_ product: ProductInfo) -> some View {
        let outfitID = String(product.id.dropFirst("housecat.outfit.".count))
        let owned = store.entitlements.outfits.contains(outfitID)
        return HStack {
            Text(product.displayName)
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
