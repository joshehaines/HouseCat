import HouseCatCore
import HouseCatGame
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
                .overlay(alignment: .top) {
                    // At the top in landscape: the cat runs to the bottom edge to rub.
                    if let line = visit.greeting {
                        GreetingBubble(line)
                            .padding(.horizontal, 90)
                            // Below the room controls and the status along the top.
                            .padding(.top, 76)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onTapGesture { visit.dismissGreeting() }
                    }
                }
                .animation(.easeOut(duration: 0.3), value: visit.greeting)
                .overlay(alignment: .topLeading) {
                    if visit.scene is RoomScene {
                        DecorateBar(
                            decorating: visit.decorating,
                            hasSelection: visit.selected != nil,
                            storeyTitle: visit.storeyTitle,
                            canDecorate: visit.storey == 0,
                            toggle: { visit.toggleDecorating() },
                            turn: { visit.turnSelection() },
                            store: { visit.storeSelection() },
                            changeStorey: { visit.changeStorey() },
                            feed: { visit.feed() }
                        )
                        .padding(20)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 10) {
                        if visit.scene is RoomScene {
                            StatusPill(level: visit.stats.level, beans: visit.stats.beans, streak: visit.stats.streak)
                        }
                        Button {
                            showShop = true
                        } label: {
                            Image(systemName: "bag")
                                .font(.title2)
                                .padding(12)
                                .background(.thinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Shop")
                    }
                    .padding()
                }
                .overlay(alignment: .bottom) {
                    if visit.decorating {
                        DecorateTray(entries: visit.inventory.map(trayEntry)) { visit.placeFromInventory($0) }
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: visit.decorating)
                .alert(item: $visit.roomOffer) { offer in
                    roomAlert(offer)
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

    /// A tray entry with the piece's picture from the app art.
    private func trayEntry(_ entry: GameSession.InventoryEntry) -> DecorateTray.Entry {
        let url = Bundle.main.url(forResource: "Art/" + entry.sprite, withExtension: nil)
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }.map { Image(uiImage: $0) }
        return DecorateTray.Entry(id: entry.id, name: entry.name, count: entry.count, image: image)
    }

    /// Opening a room (SPEC "Home and furniture": every room needs a level and Beans).
    private func roomAlert(_ offer: Visit.RoomOffer) -> Alert {
        let name = offer.room.rawValue.capitalized
        switch offer.availability {
        case let .unlockable(cost):
            return Alert(
                title: Text("Open the \(name)?"),
                message: Text("\(cost) Beans. You have \(offer.beans)."),
                primaryButton: .default(Text("Open for \(cost) Beans")) { visit.openOfferedRoom() },
                secondaryButton: .cancel()
            )
        case let .locked(level, cost, needsLevel, needsBeans):
            var needs: [String] = []
            if needsLevel {
                needs.append("level \(level) (you are level \(offer.level))")
            }
            if needsBeans {
                needs.append("\(cost) Beans (you have \(offer.beans))")
            }
            return Alert(
                title: Text("The \(name)"),
                message: Text("Opens at " + needs.joined(separator: " and ") + "."),
                dismissButton: .default(Text("OK"))
            )
        case .open:
            return Alert(title: Text("The \(name) is open"))
        }
    }

    /// RevenueCat once an API key is set in Info.plist (`RevenueCatAPIKey`), StoreKit 2 directly until then.
    @MainActor
    private static func makeStore() -> (any EntitlementService)? {
        // When the app hosts the StoreKit tests, StoreKit must not start before the
        // test session loads Store/HouseCat.storekit, or every request goes to the sandbox.
        // HOUSECAT_SKIP_STORE: launches from the command line for screenshots, where StoreKit would ask for a sandbox sign-in.
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil, environment["HOUSECAT_SKIP_STORE"] == nil, let folder = Bundle.main.url(
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
