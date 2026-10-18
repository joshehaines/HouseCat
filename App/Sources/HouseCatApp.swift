import HouseCatCore
import HouseCatGame
import HouseCatStore
import HouseCatUI
import SpriteKit
import SwiftUI

@main
struct HouseCatApp: App {
    @UIApplicationDelegateAdaptor(HouseCatAppDelegate.self) private var appDelegate
    @State private var invites = Invites.shared
    @State private var store = Self.makeStore()
    @State private var visit: Visit?
    /// Adoption (onboarding's cat creation) when the save has no cat yet, then where you live.
    @State private var adopting: CatBuilderModel?
    @State private var placing: WorldMapModel?
    /// The house step, after the map: where it is, to paint the choices there.
    @State private var choosingHome: HomePlace?
    /// Debug: the widget gallery instead of the game.
    @State private var gallery = false
    /// A new player sees the intro before the builder.
    @State private var introducing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if gallery {
                    #if DEBUG
                        WidgetGallery()
                    #endif
                } else if let visit {
                    RoomScreen(visit: visit, store: store) {
                        // Moved home: the cold open at the new place.
                        self.visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: nil)
                    }
                    // A new visit is a new screen: SpriteView keeps showing its first scene otherwise.
                    .id(ObjectIdentifier(visit))
                } else if let choosingHome {
                    HomePicker(biome: choosingHome.biome, place: choosingHome.name) { style in
                        GameSession.shared.chooseHome(style)
                        self.choosingHome = nil
                        visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: nil)
                    }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                } else if let placing {
                    WorldMapView(model: placing, cost: 0, canAfford: true, cancel: nil) { place, season in
                        GameSession.shared.placeHome(place, season: season)
                        self.placing = nil
                        choosingHome = place
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .overlay(alignment: .topTrailing) {
                        if placing.mode == .first {
                            HostHint(\.map, width: 330).padding(.top, 16).padding(.trailing, 20)
                        }
                    }
                } else if let adopting {
                    CatBuilderView(model: adopting) { model in
                        guard let name = model.checkedName else { return }
                        GameSession.shared.adopt(name: name, personality: model.personality, look: model.look)
                        self.adopting = nil
                        // Then where you live (SPEC onboarding: cat, geography, house, first arrival).
                        let session = GameSession.shared
                        placing = WorldMapModel(mode: .first, current: session.state(at: session.now()))
                    }
                    .overlay(alignment: .topLeading) {
                        if adopting.mode == .adopt {
                            HostHint(\.builder, width: 370).padding(.top, 14).padding(.leading, 16)
                        }
                    }
                } else if introducing, let intro = GameWorld.content?.intro {
                    // A new player: the intro, then the builder (SPEC onboarding: cat, geography, house, arrival).
                    IntroView(intro: intro) {
                        introducing = false
                        adopting = CatScreens.builder(mode: .adopt)
                    }
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .onAppear(perform: start)
            // Someone's invite was opened on this phone.
            .overlay {
                if let metadata = invites.pending {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        JoinView(metadata: metadata) { invites.pending = nil }
                            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                            .padding(24)
                    }
                }
            }
            .task {
                await store?.refresh()
            }
            .onChange(of: scenePhase) { old, new in
                // The widget's Feed and Pet since the app was last open are in the save before anything else.
                if new == .active {
                    WidgetBridge.importInbox()
                }
                if new == .active, old == .background, visit != nil, ArrivalRules.showsExterior(lastActive: Visit.lastActive, now: Date()) {
                    visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: Visit.lastActive)
                }
                if new == .active {
                    let session = GameSession.shared
                    RealWeather.refreshIfNeeded(state: session.state(at: session.now()))
                    // A nap that ended while the app was away is recorded now.
                    visit?.checkNap()
                }
                if new != .active {
                    Visit.lastActive = Date()
                }
                // The widget leaves with the save as it is now.
                WidgetBridge.publish()
            }
        }
    }

    /// The builder for a new player, else the visit.
    private func start() {
        guard visit == nil, adopting == nil else { return }
        HouseholdSync.start()
        WidgetBridge.importInbox()
        #if DEBUG
            // HOUSECAT_SCREEN=widgets: every widget size and pose, drawn as the widget draws them.
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "widgets" {
                WidgetBridge.publish()
                gallery = true
                return
            }
            // Screenshot runs: HOUSECAT_SCREEN=homes opens the house step, painted for HOUSECAT_BIOME.
            let environment = ProcessInfo.processInfo.environment
            // HOUSECAT_SCREEN=map opens the globe (HOUSECAT_SEARCH=<place> searches and flies there).
            if environment["HOUSECAT_SCREEN"] == "map" {
                let session = GameSession.shared
                let model = WorldMapModel(mode: .first, current: session.state(at: session.now()))
                placing = model
                if let wanted = environment["HOUSECAT_SEARCH"] {
                    model.query = wanted
                    Task {
                        for _ in 0 ..< 40 where model.search.results.isEmpty {
                            try? await Task.sleep(for: .seconds(0.25))
                        }
                        try? await Task.sleep(for: .seconds(3))
                        if let first = model.search.results.first {
                            model.choose(first)
                        }
                    }
                }
                return
            }
            if environment["HOUSECAT_SCREEN"] == "homes" {
                let biome = environment["HOUSECAT_BIOME"].flatMap(Biome.init(rawValue:)) ?? .countryside
                choosingHome = HomePlace(
                    name: "Debug, \(biome.rawValue)",
                    latitude: 0,
                    longitude: 0,
                    timeZoneID: "Europe/London",
                    biome: biome
                )
                return
            }
        #endif
        #if DEBUG
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "intro" {
                introducing = true
                return
            }
        #endif
        if GameSession.shared.cat == nil {
            introducing = true
        } else {
            visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: Visit.lastActive)
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

/// The builder, the profile and the book, made from the save and the bundled art.
@MainActor
enum CatScreens {
    static func builder(mode: CatBuilderModel.Mode) -> CatBuilderModel? {
        guard let art = GameWorld.art, let catArt = GameWorld.catArt else { return nil }
        let cat = GameSession.shared.cat
        return CatBuilderModel(
            mode: mode,
            look: cat?.look ?? .midnight,
            name: cat?.name ?? "",
            personality: cat?.personality ?? .velcro,
            art: art,
            catArt: catArt,
            rig: GameWorld.rig,
            names: GameWorld.content?.names ?? NameFilter()
        )
    }

    static func profile() -> (profile: CatProfile, xp: Int)? {
        let session = GameSession.shared
        let now = session.now()
        let state = session.state(at: now)
        return state.profile(of: GameSession.catID, on: state.clock.day(of: now)).map { ($0, state.xp) }
    }

    /// A picture from the app's art by its master path (whatever format it is stored in).
    static func picture(_ path: String) -> Image? {
        GameWorld.art?.image(path).map { Image(decorative: $0, scale: 1) }
    }

    static func portrait(_ look: CatLook) -> CGImage? {
        guard let catArt = GameWorld.catArt else { return nil }
        return catArt.image(catArt.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look), look: look)
    }

    static func book() -> [GiftBookView.Entry] {
        let session = GameSession.shared
        let collected = session.state(at: session.now()).giftsCollected
        return (session.content?.gifts.gifts ?? []).map { gift in
            GiftBookView.Entry(
                id: gift.id,
                name: gift.name,
                description: gift.description,
                rarity: gift.rarity,
                count: collected[gift.id] ?? 0,
                image: GameWorld.art?.image(gift.sprite)
            )
        }
    }

    /// Renames the cat; returns what is wrong with the name, or nil once it is taken.
    static func rename(_ name: String) -> String? {
        switch CatNames.check(name, filter: GameWorld.content?.names ?? NameFilter()) {
        case let .ok(checked):
            GameSession.shared.edit(name: checked)
            return nil
        case .empty: return "A name needs a letter or two."
        case .tooLong: return "Up to \(Tuning.Cat.nameMaxLength) characters."
        case .blocked: return "Try another name."
        }
    }
}

/// The room with its controls: the greeting, Decorate and Feed, the status, the cat's profile, the book and
/// the shop.
struct RoomScreen: View {
    @Bindable var visit: Visit
    let store: (any EntitlementService)?
    /// Starts a new visit (after moving home).
    let restart: () -> Void
    @State private var moving: WorldMapModel?
    @State private var showShop = false
    @State private var showProfile = false
    @State private var showSettings = false
    /// The profile's Reminders button: the settings open once the profile has gone.
    @State private var settingsNext = false
    @State private var showBook = false
    @State private var choosingGame = false
    @State private var playing: PlayRound?
    @State private var offeringNap = false
    @State private var naps = Naps.shared
    @State private var tour = RoomTour.shared
    @State private var offering = false
    @State private var track: EventDefinition?
    @State private var askingHealth = false
    @State private var editing: CatBuilderModel?
    @State private var profileVersion = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The room tour, once, a moment after the first arrival (or from the top on a debug run).
    private func startTour() async {
        guard visit.ready, visit.scene is RoomScene, !tour.isRunning else { return }
        try? await Task.sleep(for: .seconds(Tuning.Intro.tourDelay))
        #if DEBUG
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "tour" {
                tour.restart()
                return
            }
        #endif
        let session = GameSession.shared
        if !tour.isDone, session.state(at: session.now()).lifetime.visits <= 1 {
            tour.start()
        }
    }

    /// Larger controls on an iPad.
    private var hudScale: CGFloat {
        sizeClass == .regular ? Tuning.Stage.iPadHUDScale : 1
    }

    var body: some View {
        RoomView(scene: visit.scene) { visit.sceneIsReady() }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                // At the top in landscape: the cat runs to the bottom edge to rub.
                VStack(spacing: 8) {
                    if let line = visit.greeting {
                        GreetingBubble(line, name: visit.catName)
                            .padding(.horizontal, 90)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onTapGesture { visit.dismissGreeting() }
                    }
                    if let toast = visit.toast {
                        Toast(toast, icon: visit.toastIcon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                // Below the room controls and the status along the top.
                .padding(.top, 74 * hudScale)
            }
            .animation(.easeOut(duration: 0.3), value: visit.greeting)
            .animation(.spring(duration: 0.35), value: visit.toast)
            .overlay(alignment: .topLeading) {
                if visit.scene is RoomScene {
                    DecorateBar(
                        decorating: visit.decorating,
                        hasSelection: visit.selected != nil,
                        storeyTitle: visit.storeyTitle,
                        canDecorate: visit.canDecorate,
                        toggle: { visit.toggleDecorating() },
                        turn: { visit.turnSelection() },
                        store: { visit.storeSelection() },
                        changeStorey: { visit.changeStorey() },
                        feed: { visit.feed() },
                        play: {
                            if visit.wantsToPlay() {
                                choosingGame = true
                            }
                        }
                    )
                    .padding(20)
                }
            }
            .overlay(alignment: .topTrailing) {
                if visit.scene is RoomScene {
                    VStack(alignment: .trailing, spacing: 8) {
                        StatusPill(level: visit.stats.level, beans: visit.stats.beans, streak: visit.stats.streak)
                        // The launch's gift track, while it runs, with a dot when a present waits.
                        if !visit.decorating, let live = GameSession.shared.liveTrack() {
                            RoundIconButton(
                                "gift_box_with_a_ribbon",
                                label: live.name,
                                badge: !GameSession.shared.trackProgress(live).waiting.isEmpty
                            ) { track = live }
                                .id(visit.stats.beans)
                        }
                    }
                    .padding(20)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !visit.decorating, visit.scene is RoomScene {
                    RoomSwitcher(title: visit.roomTitle, canStep: visit.openRooms.count > 1) { visit.stepRoom($0) }
                        .padding(20)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Nothing over the cold open: the exterior is the picture.
                if !visit.decorating, visit.scene is RoomScene {
                    HStack(spacing: 10) {
                        RoundIconButton("nap_moon", label: "Nap") {
                            if naps.isNapping {
                                visit.wakeFromNap()
                            } else {
                                offeringNap = true
                            }
                        }
                        .tourTarget("nap")
                        RoundIconButton("map_pin", label: "Where you live") {
                            let session = GameSession.shared
                            moving = WorldMapModel(mode: .move, current: session.state(at: session.now()))
                        }
                        .tourTarget("map")
                        RoundIconButton("cat_face", label: "Your cat") { showProfile = true }
                            .tourTarget("profile")
                        RoundIconButton("collection_book", label: "The book") { showBook = true }
                            .tourTarget("book")
                        RoundIconButton("shop_bag", label: "Shop") { showShop = true }
                            .tourTarget("shop")
                    }
                    .padding(20)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if visit.decorating {
                    DecorateTray(
                        entries: trayEntries(),
                        modes: Visit.TrayMode.allCases.map { DecorateTray.Mode($0.title, icon: $0.icon) },
                        mode: visit.trayMode.rawValue,
                        selectMode: { visit.trayMode = Visit.TrayMode(rawValue: $0) ?? .furniture },
                        empty: visit.trayMode == .furniture
                            ? "Everything you own is out. Store a piece, or buy one in the shop."
                            : "Nothing here yet."
                    ) { id in
                        switch visit.trayMode {
                        case .furniture: visit.placeFromInventory(id)
                        case .shop: visit.buy(id)
                        case .walls, .floors: visit.chooseSurface(id)
                        }
                    }
                    .frame(maxWidth: 900 * hudScale)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: visit.decorating)
            .onChange(of: visit.decorating) { _, decorating in
                (visit.scene as? RoomScene)?.bottomInset = decorating ? DecorateTray.height(scale: hudScale) : 0
            }
            .overlay {
                // The launch screen stays up until the first picture is drawn, then lifts.
                if !visit.ready {
                    LaunchCurtain().transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.45), value: visit.ready)
            .environment(\.hudScale, hudScale)
            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .alert(item: $visit.roomOffer) { offer in
                roomAlert(offer)
            }
            .fullScreenCover(isPresented: $showShop) {
                ShopView(store: store, content: GameWorld.content)
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
            .onChange(of: visit.openGame, initial: true) { _, id in
                guard let id else { return }
                visit.openGame = nil
                if id == "picker" {
                    choosingGame = true
                } else if let game = GameWorld.content?.minigames.games.first(where: { $0.id == id }) {
                    playing = PlayRound(game: game)
                }
            }
            .onChange(of: visit.openShop, initial: true) { _, open in
                if open {
                    showShop = true
                    visit.openShop = false
                }
            }
            .sheet(isPresented: $showProfile, onDismiss: {
                if settingsNext {
                    settingsNext = false
                    showSettings = true
                }
            }) {
                if let info = CatScreens.profile() {
                    CatProfileView(
                        profile: info.profile,
                        portrait: CatScreens.portrait(info.profile.look),
                        xp: info.xp,
                        editLook: {
                            showProfile = false
                            editing = CatScreens.builder(mode: .edit)
                        },
                        rename: { name in
                            let problem = CatScreens.rename(name)
                            profileVersion += 1
                            return problem
                        },
                        setPersonality: { personality in
                            GameSession.shared.edit(personality: personality)
                            profileVersion += 1
                        },
                        settings: {
                            settingsNext = true
                            showProfile = false
                        },
                        close: { showProfile = false }
                    )
                    .id(profileVersion)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(catName: visit.catName ?? "Your cat") { showSettings = false }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
            .overlay {
                if visit.askReminders {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        RemindersCard(catName: visit.catName ?? "Your cat") { visit.askReminders = false }
                            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                            .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: visit.askReminders)
            // The room tour, over everything in the room (Content/intro.json "room").
            .overlayPreferenceValue(TourTargets.self) { targets in
                if tour.isRunning, visit.scene is RoomScene {
                    RoomTourOverlay(
                        tour: tour,
                        catName: visit.catName ?? "Your cat",
                        host: GameWorld.content?.intro.host ?? "Soot",
                        targets: targets,
                        catPoint: { visit.catPoint }
                    )
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                }
            }
            // Once the room itself is up (the cold open comes first on a first arrival).
            .task(id: visit.ready && visit.scene is RoomScene) { await startTour() }
            // The once-only offer, a moment after the trust toast, never during the tour.
            .onChange(of: visit.trustRose) { _, tier in
                var due = tier.map { Offers.due(tier: $0, owned: store?.entitlements ?? .none) } ?? false
                #if DEBUG
                    due = due || ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "offer"
                #endif
                guard due, !tour.isRunning else { return }
                Offers.trustOfferShown = true
                Task {
                    try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
                    offering = true
                }
            }
            .overlay {
                if offering {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { offering = false }
                        OfferCard(catName: visit.catName ?? "Your cat", store: store, content: GameWorld.content) {
                            offering = false
                            showShop = true
                        } close: {
                            offering = false
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: offering)
            .overlay {
                if let live = track {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { track = nil }
                        GiftTrackView(event: live) {
                            track = nil
                            visit.refreshStats()
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: track?.id)
            // Day 3: may the cat notice your steps, sleep and workouts? Then any goal met today.
            .task(id: visit.ready) {
                guard visit.ready, !tour.isRunning else { return }
                let session = GameSession.shared
                if HealthLayer.isAvailable, HealthRules.shouldAsk(session.state(at: session.now()), asked: HealthLayer.asked) {
                    try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds + 2))
                    askingHealth = true
                } else {
                    for goal in await HealthLayer.check() {
                        visit.say(session.line(HealthRules.line(goal)))
                        visit.refreshStats()
                    }
                }
            }
            .overlay {
                if askingHealth {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        HealthCard(catName: visit.catName ?? "Your cat") { askingHealth = false }
                            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                            .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: askingHealth)
            .onChange(of: tour.step?.id) { _, id in
                if id == "pet" {
                    visit.callCatForTour()
                }
            }
            .onChange(of: tour.isRunning) { was, running in
                // The reminders card waited for the tour.
                if was, !running {
                    visit.refreshStats()
                    if !Reminders.asked {
                        visit.askReminders = true
                    }
                }
            }
            .overlay {
                if choosingGame, let games = GameWorld.content?.minigames.games {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { choosingGame = false }
                        PlayPicker(games: games, playsLeft: GameSession.shared.playsLeft) { game in
                            choosingGame = false
                            playing = PlayRound(game: game)
                        } close: {
                            choosingGame = false
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                    }
                    .transition(.opacity)
                }
                if offeringNap {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { offeringNap = false }
                        NapCard(
                            catName: visit.catName ?? "Your cat",
                            pays: NapRules.pays(GameSession.shared.state(at: GameSession.shared.now()))
                        ) {
                            offeringNap = false
                            visit.startNap()
                        } close: {
                            offeringNap = false
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if let end = naps.endsAt, !visit.decorating {
                    NapBanner(catName: visit.catName ?? "Your cat", endsAt: end) { visit.wakeFromNap() }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(.top, 74 * hudScale + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: choosingGame)
            .animation(.easeOut(duration: 0.25), value: offeringNap)
            .animation(.spring(duration: 0.35), value: naps.endsAt)
            // When the nap's time is up while the room is open.
            .task(id: naps.endsAt) {
                guard let end = naps.endsAt else { return }
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.5))
                visit.checkNap()
            }
            .fullScreenCover(item: $playing) { round in
                MiniGameView(game: round.game, catName: visit.catName ?? "Your cat") { reward in
                    playing = nil
                    if let reward {
                        visit.played(reward)
                    }
                }
            }
            .sheet(isPresented: $showBook) {
                GiftBookView(entries: CatScreens.book()) { showBook = false }
            }
            .fullScreenCover(item: $moving) { model in
                let state = GameSession.shared.state(at: GameSession.shared.now())
                WorldMapView(
                    model: model,
                    cost: state.moveCost,
                    canAfford: state.beans >= state.moveCost,
                    cancel: { moving = nil }
                ) { place, season in
                    GameSession.shared.placeHome(place, season: season)
                    moving = nil
                    restart()
                }
            }
            .fullScreenCover(item: $editing) { model in
                CatBuilderView(model: model, cancel: { editing = nil }) { model in
                    GameSession.shared.edit(look: model.look)
                    editing = nil
                    visit.refreshCat()
                }
            }
    }

    private func trayEntries() -> [DecorateTray.Entry] {
        switch visit.trayMode {
        case .furniture: visit.inventory.map(trayEntry)
        case .shop: visit.shopEntries.map(shopEntry)
        case .walls, .floors: surfaceEntries()
        }
    }

    /// A Bean-shop piece with its price (or the level it needs).
    private func shopEntry(_ entry: GameSession.ShopEntry) -> DecorateTray.Entry {
        let image = CatScreens.picture(entry.sprite)
        let (price, enabled) = switch entry.status {
        case let .buyable(price): ("\(price) Beans", true)
        case let .needsBeans(price): ("\(price) Beans", false)
        case let .needsLevel(level): ("Level \(level)", false)
        }
        return DecorateTray.Entry(id: entry.id, name: entry.name, count: 1, image: image, price: price, enabled: enabled)
    }

    /// The room's wallpapers or floors as tray entries, the one up now marked.
    private func surfaceEntries() -> [DecorateTray.Entry] {
        let (options, current) = visit.surfaceOptions
        return options.map { surface in
            let image = CatScreens.picture(surface.sprite)
            return DecorateTray.Entry(id: surface.id, name: surface.name, count: 1, image: image, selected: surface.id == current)
        }
    }

    /// A tray entry with the piece's picture from the app art.
    private func trayEntry(_ entry: GameSession.InventoryEntry) -> DecorateTray.Entry {
        let image = CatScreens.picture(entry.sprite)
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
}

/// The launch screen's look (the logo on cream), kept over the first scene while it loads.
struct LaunchCurtain: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchLogo")
        }
        .accessibilityHidden(true)
    }
}
