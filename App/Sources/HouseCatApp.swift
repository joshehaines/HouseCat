import HouseCatCore
import HouseCatStore
import HouseCatUI
import SpriteKit
import SwiftUI

@main
struct HouseCatApp: App {
    @State private var store = Self.makeStore()
    @State private var showShop = false
    @State private var visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: Visit.lastActive)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RoomView(scene: visit.scene)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    if let line = visit.greeting {
                        GreetingBubble(line)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onTapGesture { visit.dismissGreeting() }
                    }
                }
                .animation(.easeOut(duration: 0.3), value: visit.greeting)
                .overlay(alignment: .topTrailing) {
                    Button {
                        showShop = true
                    } label: {
                        Image(systemName: "bag")
                            .font(.title2)
                            .padding(12)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Shop")
                    .padding()
                }
                .sheet(isPresented: $showShop) {
                    if let store {
                        ShopView(store: store)
                    }
                }
                .task {
                    await store?.refresh()
                }
                .onChange(of: scenePhase) { old, new in
                    if new == .active, old == .background, ArrivalRules.showsExterior(lastActive: Visit.lastActive, now: Date()) {
                        visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: Visit.lastActive)
                    }
                    if new != .active {
                        Visit.lastActive = Date()
                    }
                }
        }
    }

    /// RevenueCat once an API key is set in Info.plist (`RevenueCatAPIKey`), StoreKit 2 directly until then.
    @MainActor
    private static func makeStore() -> (any EntitlementService)? {
        // When the app hosts the StoreKit tests, StoreKit must not start before the
        // test session loads Store/HouseCat.storekit, or every request goes to the sandbox.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, let folder = Bundle.main.url(
            forResource: "Content",
            withExtension: nil
        ),
            let content = try? ContentBundle.load(from: folder) else { return nil }
        let catalog = StoreCatalog(content: content)
        let cache = KeychainEntitlementCache()
        if let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String, !key.isEmpty {
            return RevenueCatEntitlementService(apiKey: key, catalog: catalog, cache: cache)
        }
        return StoreKitEntitlementService(catalog: catalog, cache: cache)
    }
}
