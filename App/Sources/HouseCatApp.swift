import HouseCatCore
import HouseCatGame
import HouseCatStore
import HouseCatUI
import SpriteKit
import StoreKit
import SwiftUI

@main
struct HouseCatApp: App {
    @UIApplicationDelegateAdaptor(HouseCatAppDelegate.self) private var appDelegate
    @State private var invites = Invites.shared
    @State private var store = Self.makeStore()
    @State private var visit: Visit?
    /// Adoption (onboarding's cat creation) when the save has no cat yet.
    @State private var adopting: CatBuilderModel?
    /// The opening cutscene after adoption, with the cat's name.
    @State private var cutscene: String?
    /// Debug: the widget gallery instead of the game.
    @State private var gallery = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if gallery {
                    #if DEBUG
                        if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "outfits" {
                            OutfitGallery()
                        } else if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "puppets" {
                            PuppetGallery()
                        } else if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "logo" {
                            // The launch curtain held, to watch the cat curl up on the logo.
                            LaunchCurtain()
                        } else {
                            WidgetGallery()
                        }
                    #endif
                } else if let visit {
                    RoomScreen(visit: visit, store: store) {
                        // Moved home: the cold open at the new place.
                        self.visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: nil)
                    }
                    // A new visit is a new screen: SpriteView keeps showing its first scene otherwise.
                    .id(ObjectIdentifier(visit))
                } else if let cutscene {
                    Cutscene(catName: cutscene) {
                        self.cutscene = nil
                        visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: nil)
                    }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                } else if let adopting {
                    // The host's line sits over the cat, clear of the drawers.
                    CatBuilderView(model: adopting) {
                        if adopting.mode == .adopt {
                            HostHint(\.builder, width: 330)
                        }
                    } done: { model in
                        guard let name = model.checkedName else { return }
                        PlayerName.current = model.checkedOwnerName
                        GameSession.shared.adopt(name: name, personality: model.personality, look: model.look)
                        self.adopting = nil
                        // Then the cutscene, then home: the bottom rung of the house ladder (docs/LADDER.md).
                        cutscene = name
                    }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                } else {
                    // The first frame, before anything is built: the launch screen's own look, so it hands over
                    // without a flash, and the cat pounces onto the letters while the home is built.
                    LaunchCurtain()
                }
            }
            .onAppear(perform: start)
            // Everything was deleted: back to the very first screen, as a fresh install.
            // Text grows with the player's text size, up to the largest a landscape game can lay out (the HUD's
            // buttons keep their own size).
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .onReceive(NotificationCenter.default.publisher(for: .houseCatErased)) { _ in
                visit = nil
                // A new player designs their cat first (Josh, 22 Oct: "cat design and then into a cut scene").
                adopting = CatScreens.builder(mode: .adopt)
            }
            // The household on this phone changed (it joined someone's cat, left it, or sharing ended): the first
            // screen again, for the cat now in the save.
            .onReceive(NotificationCenter.default.publisher(for: .houseCatSwitched)) { note in
                invites.notice = note.userInfo?["notice"] as? String
                visit = nil
                adopting = nil
                if GameSession.shared.cat == nil {
                    adopting = CatScreens.builder(mode: .adopt)
                } else {
                    visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: nil)
                }
            }
            // Someone's invite was opened on this phone; what happened to the household, once.
            .overlay {
                if let metadata = invites.pending {
                    dimmed {
                        JoinView { try await HouseholdSync.accept(metadata, as: $0) } done: { invites.pending = nil }
                    }
                } else if invites.debugJoin {
                    #if DEBUG
                        dimmed {
                            JoinView { HouseholdSync.debugJoin(as: $0) } done: { invites.debugJoin = false }
                        }
                    #endif
                } else if let notice = invites.notice {
                    dimmed {
                        SharingNotice(text: notice) { invites.notice = nil }
                    }
                }
            }
            .task {
                // Siri learns the cat's name for its phrases ("Feed Pip in HouseCat").
                HouseCatShortcuts.updateAppShortcutParameters()
                await store?.refresh()
                // While Cat Club is on, today is a club day (its +20% Beans, the daily treat and the streak shield).
                GameSession.shared.recordClubDay(active: store?.entitlements.hasClub == true)
                await StorePrices.shared.load(store: store, content: GameWorld.content)
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
                if new == .active, old == .background {
                    Task {
                        await store?.refresh()
                        GameSession.shared.recordClubDay(active: store?.entitlements.hasClub == true)
                    }
                }
                if new != .active {
                    Visit.lastActive = Date()
                }
                // The widget leaves with the save as it is now.
                WidgetBridge.publish()
            }
        }
    }

    /// A card over everything, the screen dimmed behind it.
    private func dimmed(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            content()
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                .padding(24)
        }
    }

    /// The builder for a new player, else the visit.
    private func start() {
        guard visit == nil, adopting == nil else { return }
        HouseholdSync.start()
        WidgetBridge.importInbox()
        #if DEBUG
            // HOUSECAT_SCREEN=join: the join card for someone else's cat (Mochi), with CloudKit off.
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "join" {
                invites.debugJoin = true
            }
            // HOUSECAT_SCREEN=widgets: every widget size and pose, drawn as the widget draws them.
            if ["outfits", "puppets", "logo"].contains(ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"]) {
                gallery = true
                return
            }
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "widgets" {
                WidgetBridge.publish()
                gallery = true
                return
            }
        #endif
        #if DEBUG
            // HOUSECAT_SCREEN=creator: the cat creator as a new player meets it
            // (HOUSECAT_CREATOR=<drawer> opens a drawer: looks, body, coat, pattern, white, eyes, nose, earsTail, age, name).
            // HOUSECAT_SCREEN=cutscene: the opening cutscene alone, for the cat in the save.
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "cutscene" {
                cutscene = GameSession.shared.cat?.name ?? "Pip"
                return
            }
            if ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "creator" {
                adopting = CatScreens.builder(mode: .adopt)
                return
            }
        #endif
        if GameSession.shared.cat == nil {
            // A new player designs their cat first, then the cutscene, then home (docs/LADDER.md).
            adopting = CatScreens.builder(mode: .adopt)
        } else {
            // The whole logo animation plays every launch (Josh, 19 Oct): the home is built under it near its end, so
            // it is ready as the curtain lifts (a tap on the curtain skips to it).
            Task { @MainActor in
                await LaunchFilm.onScreen(within: Tuning.Logo.filmWait)
                await LaunchFilm.buildTime(lead: Tuning.Logo.launchBuildLead)
                guard visit == nil else { return }
                visit = Visit(size: CGSize(width: 1024, height: 768), lastActive: Visit.lastActive)
            }
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
        let service: any EntitlementService = if let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
                                                 !key.isEmpty
        {
            RevenueCatEntitlementService(apiKey: key, catalog: catalog, cache: cache)
        } else {
            StoreKitEntitlementService(catalog: catalog, cache: cache)
        }
        // Beans and room looks go into the save, once per transaction (Bean packs bought while the app was
        // closed are handed over here before StoreKit is told they are finished).
        service.onGrant = { grant in GameSession.shared.grant(grant, catalog: catalog) }
        return service
    }
}

/// The builder, the profile and the book, made from the save and the bundled art.
@MainActor
enum CatScreens {
    static func builder(mode: CatBuilderModel.Mode) -> CatBuilderModel? {
        guard let art = GameWorld.art, let catArt = GameWorld.catArt else { return nil }
        let cat = GameSession.shared.cat
        let model = CatBuilderModel(
            mode: mode,
            look: cat?.look ?? .midnight,
            name: cat?.name ?? "",
            personality: cat?.personality ?? .velcro,
            art: art,
            catArt: catArt,
            rig: GameWorld.rig,
            names: GameWorld.content?.names ?? NameFilter()
        )
        #if DEBUG
            if let drawer = ProcessInfo.processInfo.environment["HOUSECAT_CREATOR"].flatMap(CatBuilderModel.Section.init) {
                model.section = drawer
            }
        #endif
        return model
    }

    static func profile() -> (profile: CatProfile, xp: Int)? {
        let session = GameSession.shared
        let now = session.now()
        let state = session.state(at: now)
        return state.profile(of: GameSession.catID, on: state.clock.day(of: now), catalogue: session.content?.affordances).map { (
            $0,
            state.xp
        ) }
    }

    /// A picture from the app's art by its master path (whatever format it is stored in).
    static func picture(_ path: String) -> Image? {
        GameWorld.art?.image(path).map { Image(decorative: $0, scale: 1) }
    }

    /// A card's picture in a list (the decorate tray): its small copy once made, nil until then. A list of full pictures
    /// left SwiftUI decoding dozens of HEIC files at once, which hung the app on the tray's Shop tab (21 Oct); the
    /// copies are made off the main thread, one at a time (`ArtLibrary.makeThumbnails`, asked for by `cardPictures`).
    static func cardPicture(_ path: String) -> Image? {
        GameWorld.art?.cachedThumbnail(path, pixels: Tuning.Stage.cardPicturePixels).map { Image(decorative: $0, scale: 1) }
    }

    /// Asks for the cards' pictures not made yet; `ready` runs as each few arrive.
    static func cardPictures(_ paths: [String], ready: @escaping @MainActor () -> Void) {
        GameWorld.art?.makeThumbnails(paths, pixels: Tuning.Stage.cardPicturePixels, batch: Tuning.Stage.cardPictureBatch, ready: ready)
    }

    /// The cat sitting with its back to you, looking at what you look at (the homes' ladder), in its look; no outfit.
    static func backView(_ look: CatLook) -> CGImage? {
        guard let catArt = GameWorld.catArt else { return nil }
        return catArt.image(catArt.builder.pose(CatPose.sitBack.rawValue, look: look), look: look)
    }

    /// The cat sitting three-quarter front in its look, wearing what it has on.
    static func portrait(_ look: CatLook, outfit: OutfitsFile.Outfit? = GameSession.shared.wornOutfit) -> CGImage? {
        guard let catArt = GameWorld.catArt else { return nil }
        let sprite = catArt.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look)
        guard let image = catArt.image(sprite, look: look) else { return nil }
        if let outfit, outfit.slot == .body, let art = GameWorld.art,
           let path = OutfitFit.garment(outfit, body: look.body, pose: .sitThreeQuarterFront), art.has(path), let garment = art.image(path)
        {
            let base = "poses/cat_\(look.body)_\(CatPose.sitThreeQuarterFront.rawValue).png"
            let frame = GarmentPlacement.frame(drawn: sprite.path, base: base, catArt: catArt, art: art)
            return OutfitFit.dress(image, garment: garment, frame: frame, clipped: sprite.path != base) ?? image
        }
        guard let outfit, let kind = OutfitFit.kind(outfit), let path = outfit.sprites["tqfront"], let art = GameWorld.art,
              let picture = art.image(path), let shape = OutfitShapes.shape(path, art: art), let face = catArt.face(sprite.path)
        else { return image }
        return OutfitFit.compose(
            image,
            face: face,
            outfit: picture,
            shape: shape,
            kind: kind,
            view: "tqfront",
            size: outfit.fit,
            tallEars: OutfitFit.tallEars(look, wearing: outfit),
            pose: .sitThreeQuarterFront,
            coversEars: OutfitFit.coversEars(outfit)
        )?.image ?? image
    }

    /// The wardrobe's outfits with their pictures, for the cat's profile.
    static func wardrobe() -> [CatProfileView.WardrobeItem] {
        GameSession.shared.wardrobe.map { outfit in
            CatProfileView.WardrobeItem(
                id: outfit.id,
                name: outfit.name,
                image: outfit.sprites["tqfront"].flatMap { GameWorld.art?.image($0) }
            )
        }
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
    @State private var showShop = false
    @State private var showProfile = false
    @State private var showSettings = false
    /// The profile's Reminders button: the settings open once the profile has gone.
    @State private var settingsNext = false
    @State private var showBook = false
    /// The day's streak being cheered (`StreakCelebration`), and the day it last was.
    @State private var celebratingStreak = false
    @AppStorage("streakCelebratedDay") private var streakCelebrated = ""
    /// The house ladder: where you live and the next house up (docs/LADDER.md).
    @State private var showHomes = false
    /// The profile's Next home: the homes open once the profile has gone.
    @State private var homesNext = false
    @State private var choosingGame = false
    @State private var playing: PlayRound?
    /// The Games menu (Play opens it; CLAUDE.md "The Games menu").
    @State private var showGames = false
    @State private var offeringNap = false
    @State private var naps = Naps.shared
    @State private var tour = RoomTour.shared
    @State private var tips = FirstTips.shared
    /// A first-use tip came up at this visit (one a visit, `FirstTips`).
    @State private var tipped = false
    /// The Day 1 card, as the first tour ends (`DayOneCard`).
    @State private var dayOne = false
    @State private var offering = false
    @State private var track: EventDefinition?
    @State private var askingHealth = false
    /// "Help improve HouseCat?" (AnalyticsPromptCard), on the second day of care.
    @State private var askingAnalytics = false
    @State private var askingWidget = false
    @State private var showTogether = false
    /// A present the other owner left, opened at this visit.
    @State private var present: OutfitGift?
    @State private var editing: CatBuilderModel?
    /// The outfit catalogue, trying outfits on the cat in the dressing room.
    @State private var tryingOn: OutfitCatalogueModel?
    @State private var profileVersion = 0
    @State private var shopOpening: ShopView.Section?
    /// The cat's own look, for the player's plaque.
    @State private var portrait: Image?
    @State private var showRoad = false
    @State private var showStreak = false
    @State private var showPass = false
    @State private var showMenu = false
    @State private var showGoals = false
    /// Short of Beans for something in the room: the top-up, then the purchase.
    @State private var topUp: ShopView.TopUpRequest?
    /// The window's size (the room fills it), for the scale of the controls and cards on an iPad.
    @State private var window = CGSize.zero
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.requestReview) private var requestReview

    /// A rating asked for at a happy moment, if one is due (`ReviewPrompt`).
    private func askForReview(after seconds: Double) {
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let today = state.clock.day(of: session.now())
        let together = state.cats.map { $0.togetherDays(on: today) }.max() ?? 0
        guard ReviewPrompt.isDue(daysTogether: together) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            ReviewPrompt.markAsked()
            requestReview()
        }
    }

    /// After the tour (and its Day 1 card): the tutorial ends by moving out of the first house (Josh, 22 Oct: "the
    /// tutorial should get you out of the first house"): the tour's welcome Beans buy the houseboat. The reminders wait.
    private func afterTour() {
        let state = GameSession.shared.state(at: GameSession.shared.now())
        if !tour.skipped, state.rung == 1, HouseLadder.block(above: 1, level: state.level, tasksDone: state.houseTasksDone, beans: state.beans) == nil {
            showHomes = true
        } else if !Reminders.asked {
            visit.askReminders = true
        }
    }

    /// Nothing over the room and nothing being asked: a first-use tip may come up.
    private var quiet: Bool {
        visit.ready && visit.scene is RoomScene && !visit.decorating && visit.previewing == nil && !roomCovered && !showMenu
            && !choosingGame && !offeringNap && !visit.askReminders && !askingHealth && !askingAnalytics && !askingWidget
            && !offering && !dayOne && visit.levelReached == nil && topUp == nil
    }

    /// One first-use tip a visit, once the tour is done and the room has been quiet a while (`FirstTips`).
    private func offerTip() async {
        guard visit.ready, visit.scene is RoomScene, tour.isDone, !tipped, !Self.debugScreenRun else { return }
        try? await Task.sleep(for: .seconds(Tuning.Intro.tipDelay))
        for _ in 0 ..< 12 {
            guard !Task.isCancelled, !tipped else { return }
            if quiet, !tour.isRunning {
                var screen: Set<String> = ["goals", "plaque", "menu", "shop"]
                if visit.canDecorate {
                    screen.formUnion(["play", "nap"])
                }
                tips.showNext(on: screen)
                tipped = true
                return
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

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

    /// Larger controls and cards on an iPad, by the window's size as the shop scales (`Tuning.Stage.hudDesignWidth`),
    /// and on a phone whose screen is at least that big: iPhone Duo unfolded (951 x 669 points, about 1.3), which
    /// changes back as it folds. Never on any other phone (a big iPhone on its side also says its width is regular).
    private var hudScale: CGFloat {
        let fit = min(window.width / Tuning.Stage.hudDesignWidth, window.height / Tuning.Stage.hudDesignHeight)
        // A phone's controls a little smaller than drawn (Josh, 22 Oct: on an iPhone the UI "takes up most of the screen").
        guard UIDevice.current.userInterfaceIdiom == .pad || fit >= 1 else { return CGFloat(Tuning.Stage.phoneHudScale) }
        return (min(Tuning.Stage.hudLargestScale, max(1, fit)) * 20).rounded(.down) / 20
    }

    /// A sheet over the room (the profile, the settings, the book) on an iPad: drawn at the controls' scale, as large
    /// as the window allows. A phone shows the system's own.
    private var sheetSize: CGSize? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return nil }
        let margin = 2 * Tuning.Stage.sheetMargin
        return CGSize(
            width: min(Tuning.Stage.sheetWidth * hudScale, window.width - margin),
            height: min(Tuning.Stage.sheetHeight * hudScale, window.height - margin)
        )
    }

    /// The room sits above the care buttons along the bottom, so the cat coming to greet you is never under them.
    private var restInset: CGFloat {
        CGFloat(Tuning.Stage.careBarInset) * hudScale
    }

    var body: some View {
        screens(progressCards(cards(sheets(hud))))
            .overlay {
                if celebratingStreak {
                    StreakCelebration(catName: visit.catName ?? "Your cat") {
                        withAnimation(.easeOut(duration: 0.25)) { celebratingStreak = false }
                        askForReview(after: 1.2)
                    }
                    .transition(.opacity)
                }
            }
            // The day's streak, cheered on the first visit of the day (not the very first day: the tour has it).
            .task(id: visit.ready) {
                guard visit.ready, visit.scene is RoomScene else { return }
                try? await Task.sleep(for: .seconds(2))
                let info = GameSession.shared.streakInfo
                let today = GameSession.shared.state(at: GameSession.shared.now()).clock.day(of: GameSession.shared.now())
                let key = "\(today.index)"
                guard info.visitedToday, info.current >= 2, streakCelebrated != key, !tour.isRunning else { return }
                streakCelebrated = key
                withAnimation(.easeOut(duration: 0.3)) { celebratingStreak = true }
            }
    }

    /// The room and its controls.
    private var hud: some View {
        RoomView(
            scene: visit.scene,
            label: visit.accessibilityDescription,
            actions: visit.scene is RoomScene ? [
                RoomView.Action("Pet \(visit.catName ?? "your cat")") { visit.petCat() },
                RoomView.Action("Feed \(visit.catName ?? "your cat")") { visit.feed() },
            ] : [RoomView.Action("Go inside") { (visit.scene as? ExteriorScene)?.enter() }]
        ) { visit.sceneIsReady() }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { window = $0 }
            .overlay {
                // What the cat says, in a bubble over its head (it follows the cat); a note over the room up top.
                if visit.scene is RoomScene {
                    speech
                }
            }
            .overlay(alignment: .bottom) {
                if let look = visit.previewing {
                    RoomLookBar(bundle: look, store: store) {
                        visit.addWholeRoom(look)
                    } close: {
                        visit.endPreview()
                    }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                    .zoomed(hudScale)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: visit.previewing?.id)
            .onChange(of: visit.ready && visit.scene is RoomScene, initial: true) { _, inRoom in
                if inRoom, !visit.decorating, visit.previewing == nil {
                    (visit.scene as? RoomScene)?.bottomInset = restInset
                }
            }
            .onChange(of: visit.previewing?.id) { _, look in
                // The room lifts above the bar, as it does for the decorate tray.
                (visit.scene as? RoomScene)?.bottomInset = look == nil ? restInset : RoomLookBar.height * hudScale
            }
            .animation(.easeOut(duration: 0.3), value: visit.greeting)
            .animation(.spring(duration: 0.35), value: visit.toast)
            // The controls, laid out as a builder game lays out its base (Josh, 18 Oct; 19 Oct: out to the edges,
            // as Clash of Clans does, and fewer of them): the player's plaque top left with the one menu under it
            // (the rooms, the map, the book, the pass), the Beans and streak bars top right, the care actions bottom
            // left, Decorate and the Shop bottom right. Nothing halfway down a side, where the Dynamic Island is in
            // landscape.
            .overlay {
                if visit.scene is RoomScene {
                    roomControls
                    roomMenu
                }
            }
            // Outside to look at the house: where it is, and Go in.
            .overlay {
                if visit.outside {
                    outsideControls
                }
            }
            .animation(.easeOut(duration: 0.3), value: visit.outside)
            // Apple Weather's mark wherever its weather is on screen (its attribution rule): under the room's bottom
            // edge, where nothing else sits, while the weather in the windows is Apple's; and on the cold open,
            // top left with the weather, where the town goes once you are outside to look.
            .overlay(alignment: .bottom) {
                if visit.ready, visit.scene is RoomScene, !visit.decorating, visit.previewing == nil, let now = appleWeatherNow {
                    WeatherMark(caption: WeatherMark.caption(now, at: GameSession.shared.now()))
                        .padding(.bottom, Tuning.Stage.hudBottom)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if visit.ready, visit.scene is ExteriorScene, !visit.outside, let now = appleWeatherNow {
                    WeatherMark(caption: WeatherMark.caption(now, at: GameSession.shared.now()))
                        .padding(.leading, Tuning.Stage.hudEdge)
                        .padding(.top, Tuning.Stage.hudTop)
                        .transition(.opacity)
                }
            }
            // The goals: the next one or two always on screen, top middle (Josh, 19 Oct: "dont know what to do";
            // App/Sources/GoalTracker.swift). It celebrates every goal met, so the note that did is gone.
            .overlayPreferenceValue(TourTargets.self) { targets in
                if visit.scene is RoomScene, visit.ready {
                    GoalTrackerLayer(
                        visit: visit,
                        targets: targets,
                        hidden: trackerHidden,
                        open: goal,
                        roomTitle: roomTitle
                    )
                }
            }
            .task(id: [
                AnyHashable(GameSession.shared.cat?.look),
                AnyHashable(GameSession.shared.cat?.outfitID),
                AnyHashable(profileVersion),
            ]) {
                portrait = GameSession.shared.cat.flatMap { CatScreens.headshot($0.look) }.map { Image(decorative: $0, scale: 1) }
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
                        case .shop:
                            if let entry = visit.shopEntries.first(where: { $0.id == id }), case let .needsBeans(price) = entry.status {
                                topUp = ShopView.TopUpRequest(
                                    need: BeanPrices.shortfall(price: price, balance: visit.stats.beans),
                                    purpose: "the \(entry.name.lowercased())"
                                ) { visit.buy(id) }
                            } else {
                                visit.buy(id)
                            }
                        case .walls, .floors: visit.chooseSurface(id)
                        }
                    }
                    .frame(maxWidth: 900 * hudScale)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: visit.decorating)
            .onChange(of: visit.decorating) { _, decorating in
                (visit.scene as? RoomScene)?.bottomInset = decorating ? DecorateTray.height(scale: hudScale) : restInset
                // The shop's pictures are started now, so they are usually here before its tab is opened.
                if decorating {
                    CatScreens.cardPictures(visit.shopEntries.map(\.sprite)) { visit.cardPicturesArrived() }
                }
            }
            .onChange(of: hudScale) {
                // An iPad turned or its window resized: the room lifts to match.
                guard visit.ready, let room = visit.scene as? RoomScene else { return }
                room.bottomInset = visit.decorating ? DecorateTray.height(scale: hudScale)
                    : visit.previewing != nil ? RoomLookBar.height * hudScale : restInset
            }
            .overlay {
                // The launch screen stays up until the first picture is drawn, then lifts.
                if !visit.ready || LaunchFilm.state.holding {
                    LaunchCurtain().transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.45), value: visit.ready)
            .animation(.easeOut(duration: 0.45), value: LaunchFilm.state.holding)
            .environment(\.hudScale, hudScale)
            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }

    private func sheets(_ content: some View) -> some View {
        content
            .alert(item: $visit.roomOffer) { offer in
                roomAlert(offer)
            }
            .fullScreenCover(isPresented: $showShop) {
                ShopView(
                    store: store,
                    content: GameWorld.content,
                    tryLook: { visit.preview($0) },
                    addLook: { visit.addWholeRoom($0) },
                    openPass: { showPass = true },
                    tryOutfits: { tryOutfits($0) },
                    opening: shopOpening
                )
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
            .onChange(of: visit.openGame, initial: true) { _, id in
                guard let id else { return }
                visit.openGame = nil
                if id == "picker" {
                    showGames = true
                } else if let game = GameWorld.content?.minigames.games.first(where: { $0.id == id }) {
                    playing = PlayRound(game: game)
                }
            }
            .onChange(of: visit.openShop, initial: true) { _, open in
                if open {
                    openShop(nil)
                    visit.openShop = false
                }
            }
            .sheet(isPresented: $showProfile, onDismiss: {
                if settingsNext {
                    settingsNext = false
                    showSettings = true
                }
                if homesNext {
                    homesNext = false
                    showHomes = true
                }
            }) {
                if let info = CatScreens.profile() {
                    CatProfileView(
                        profile: info.profile,
                        portrait: CatScreens.portrait(info.profile.look),
                        xp: info.xp,
                        corner: CatScreens.profileCorner(),
                        levelTitle: GameSession.shared.levelInfo.title,
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
                        wardrobe: CatScreens.wardrobe(),
                        worn: GameSession.shared.wornOutfit?.id,
                        wear: { id in
                            GameSession.shared.wear(id)
                            visit.dressCat()
                            profileVersion += 1
                            WidgetBridge.publish()
                        },
                        home: CatScreens.homeLine(),
                        moveHouse: {
                            homesNext = true
                            showProfile = false
                        },
                        settings: {
                            settingsNext = true
                            showProfile = false
                        },
                        close: { showProfile = false }
                    )
                    .id(profileVersion)
                    .zoomedSheet(hudScale, size: sheetSize)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(catName: visit.catName ?? "Your cat", store: store, replayTour: {
                    showSettings = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.6))
                        tour.replay()
                    }
                }) { showSettings = false }
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                    .zoomedSheet(hudScale, size: sheetSize)
            }
    }

    private func cards(_ content: some View) -> some View {
        content
            .overlay {
                if let request = topUp {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { topUp = nil }
                        BeanTopUp(need: request.need, purpose: request.purpose, store: store) { bought in
                            topUp = nil
                            visit.refreshStats()
                            if bought {
                                request.then()
                            }
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                        .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: topUp?.id)
            .overlay {
                if visit.askReminders {
                    ZStack {
                        // Dark enough to read as a question over the room, and a tap outside is Not now (Josh's
                        // iPad, 19 Oct: the room seemed frozen behind a card he hadn't noticed).
                        Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { visit.askReminders = false }
                        RemindersCard(catName: visit.catName ?? "Your cat") { visit.askReminders = false }
                            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                            .padding(24)
                            .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: visit.askReminders)
            .overlay {
                if dayOne {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        DayOneCard(catName: visit.catName ?? "Your cat") {
                            dayOne = false
                            afterTour()
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                        .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: dayOne)
            // The room tour, over everything in the room (Content/intro.json "room").
            .overlayPreferenceValue(TourTargets.self) { targets in
                // Out of the way while what its control opened is up (the games, the nap card, the menu, the shop).
                if tour.isRunning, visit.scene is RoomScene, !showGames, !choosingGame, !offeringNap, !showMenu, !showShop, playing == nil {
                    RoomTourOverlay(
                        tour: tour,
                        catName: visit.catName ?? "Your cat",
                        host: GameWorld.content?.intro.host ?? "Pat",
                        targets: targets,
                        catPoint: { visit.catPoint }
                    )
                    .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                    .environment(\.hudScale, hudScale)
                } else if let tip = tips.current, !tour.isRunning, quiet {
                    FirstTipOverlay(tip: tip, catName: visit.catName ?? "Your cat", host: GameWorld.content?.intro.host ?? "Pat", targets: targets)
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .environment(\.hudScale, hudScale)
                }
            }
            .animation(.easeOut(duration: 0.25), value: tips.current?.id)
            // Once the room itself is up (the cold open comes first on a first arrival).
            .task(id: visit.ready && visit.scene is RoomScene) {
                await startTour()
                await offerTip()
            }
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
                            openShop(nil)
                        } close: {
                            offering = false
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                        .zoomed(hudScale)
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
                        .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: track?.id)
            // Day 3: may the cat notice your steps, sleep and workouts? Then any goal met today.
            .task(id: visit.ready) {
                guard visit.ready, !tour.isRunning else { return }
                let session = GameSession.shared
                var healthDue = HealthLayer.isAvailable && HealthRules.shouldAsk(session.state(at: session.now()), asked: HealthLayer.asked)
                    && !Self.debugScreenRun
                #if DEBUG
                    // HOUSECAT_SCREEN=analytics shows the analytics card even on a save the Health card would take.
                    healthDue = healthDue && ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] != "analytics"
                #endif
                if healthDue {
                    try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds + 2))
                    askingHealth = true
                } else {
                    for goal in await HealthLayer.check() {
                        visit.say(session.line(HealthRules.line(goal)))
                        visit.refreshStats()
                    }
                    // Day 2: may the app count what gets used? (Its own day, apart from the reminders and Health.)
                    var analyticsDue = Analytics.shouldAsk(session.state(at: session.now())) && !Self.debugScreenRun
                    #if DEBUG
                        analyticsDue = analyticsDue || ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "analytics"
                    #endif
                    if analyticsDue {
                        try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds + 2))
                        askingAnalytics = true
                    } else {
                        await askForWidget()
                    }
                }
            }
            .overlay {
                if askingAnalytics {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        AnalyticsPromptCard {
                            askingAnalytics = false
                            Task { await askForWidget() }
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                        .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: askingAnalytics)
            .overlay {
                if askingHealth {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        HealthCard(catName: visit.catName ?? "Your cat") {
                            askingHealth = false
                            Task { await askForWidget() }
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .padding(24)
                        .zoomed(hudScale)
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
            // After the first feed's reminders card: the add-widget card.
            .onChange(of: visit.askReminders) { was, asking in
                if was, !asking {
                    Task { await askForWidget() }
                }
            }
            .onChange(of: tour.isRunning) { was, running in
                // The reminders card waited for the tour.
                if was, !running {
                    visit.refreshStats()
                    // Replayed from Settings: nothing follows.
                    guard !tour.replaying else { return }
                    // Played through: Day 1, and tomorrow (Josh, 25 Oct: the onboarding research), then the move.
                    if !tour.skipped, !DayOneCard.shown {
                        dayOne = true
                    } else {
                        afterTour()
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
                        .zoomed(hudScale)
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
                        .zoomed(hudScale)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if let end = naps.endsAt, !visit.decorating {
                    // Under the goal tracker when it is up (20 Oct: it covered the card's second goal all nap).
                    GeometryReader { geometry in
                        NapBanner(catName: visit.catName ?? "Your cat", endsAt: end) { visit.wakeFromNap() }
                            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                            .zoomed(hudScale)
                            .frame(maxWidth: .infinity)
                            .padding(.top, max(74 * hudScale + 8, belowTracker(in: geometry)))
                    }
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
    }

    private func screens(_ content: some View) -> some View {
        content
            .fullScreenCover(isPresented: $showGames) {
                GamesMenu(catName: visit.catName ?? "Your cat") {
                    showGames = false
                    visit.refreshStats()
                } playQuick: { game in
                    // The menu goes, then the quick game comes up in its place.
                    showGames = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.45))
                        playing = PlayRound(game: game)
                    }
                }
            }
            .fullScreenCover(item: $playing) { round in
                MiniGameView(game: round.game, catName: visit.catName ?? "Your cat") { reward in
                    playing = nil
                    if let reward {
                        visit.played(reward)
                    }
                }
            }
            .fullScreenCover(isPresented: $showHomes) {
                HomesView(catName: visit.catName ?? "Your cat") {
                    showHomes = false
                    // Moved in: the cold open at the new house.
                    restart()
                    askForReview(after: 8)
                } close: {
                    showHomes = false
                }
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
            .sheet(isPresented: $showBook) {
                GiftBookView(entries: CatScreens.book()) { showBook = false }
                    .zoomedSheet(hudScale, size: sheetSize)
            }
            .fullScreenCover(item: $editing) { model in
                CatBuilderView(model: model, cancel: { editing = nil }) { model in
                    GameSession.shared.edit(look: model.look)
                    editing = nil
                    visit.refreshCat()
                }
            }
            .fullScreenCover(item: $tryingOn) { model in
                OutfitCatalogueView(model: model, store: store) {
                    tryingOn = nil
                    // What it now wears (bought and put on in the catalogue), in the room too.
                    visit.dressCat()
                    profileVersion += 1
                }
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
    }

    /// Debug screenshot runs (HOUSECAT_SCREEN) are not interrupted by the day-3 cards.
    private static var debugScreenRun: Bool {
        #if DEBUG
            let screen = ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"]
            return screen != nil && screen != "health" && screen != "addwidget" && screen != "analytics"
        #else
            return false
        #endif
    }

    /// The add-widget card, when it is due and nothing else is on screen (after the first feed, on day 3).
    private func askForWidget() async {
        try? await Task.sleep(for: .seconds(1.2))
        guard !Self.debugScreenRun, visit.ready, visit.scene is RoomScene, !tour.isRunning, !visit.askReminders, !askingHealth,
              !askingAnalytics, !offering, visit.levelReached == nil, !askingWidget else { return }
        let session = GameSession.shared
        if await WidgetPrompt.take(session.state(at: session.now())) != nil {
            askingWidget = true
        }
    }

    /// The room's controls, out at the screen's edges and corners (Tuning.Stage.hud*): see `hud`.
    private var roomControls: some View {
        let edge = CGFloat(Tuning.Stage.hudEdge), top = CGFloat(Tuning.Stage.hudTop), bottom = CGFloat(Tuning.Stage.hudBottom)
        let calm = !visit.decorating && visit.previewing == nil
        return GeometryReader { geometry in
            let tall = geometry.size.height > geometry.size.width
            let camera = CameraClearance(geometry, edge: edge)
            ZStack {
                // Top left: the plaque (or Turn, Store and Done while decorating), the map and the book under it.
                VStack(alignment: .leading, spacing: 12 * hudScale) {
                    if visit.decorating {
                        DecorateBar(
                            decorating: true,
                            hasSelection: visit.selected != nil,
                            canDecorate: visit.canDecorate,
                            toggle: { visit.toggleDecorating() },
                            turn: { visit.turnSelection() },
                            store: { visit.storeSelection() }
                        )
                    } else {
                        PlayerBadge(
                            portrait: portrait,
                            name: visit.catName ?? "Your cat",
                            title: GameSession.shared.levelInfo.title,
                            level: visit.stats.level,
                            progress: visit.stats.progress,
                            onPortrait: { showProfile = true },
                            onLevel: { showRoad = true }
                        )
                        .overlay(alignment: .bottomLeading) {
                            if let gain = visit.xpGain {
                                XPFloat(amount: gain.amount).id(gain.id).offset(x: 64 * hudScale, y: 32 * hudScale).transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.3), value: visit.xpGain)
                        if calm {
                            // One menu for the rooms, the map, the book, the pass and the rest (Josh, 19 Oct: calmer).
                            GameButton("Menu", icon: "house", size: 50, dot: menuWaiting) {
                                tour.heard(.opened("menu"))
                                tips.used("menu")
                                showMenu = true
                            }
                            .tourTarget("menu")
                            .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, edge + camera.topLeading)
                .padding(.top, top)

                // Top right: the Beans and the streak (the season's tiles are in the menu).
                HStack(alignment: .top, spacing: 10 * hudScale) {
                    VStack(alignment: .trailing, spacing: 8 * hudScale) {
                        ResourceBar(
                            icon: "bean_coin",
                            value: visit.stats.beans.formatted(),
                            label: "\(visit.stats.beans) Beans. Get more.",
                            plus: true
                        ) { openShop(.beans) }
                        ResourceBar(
                            icon: "streak_paw_print_with_a_small_flame",
                            value: visit.stats.streak == 1 ? "1 day" : "\(visit.stats.streak) days",
                            label: "\(visit.stats.streak) day streak. Shows the streak."
                        ) { showStreak = true }
                        // The season pass, always on: the tier, the bar to the next one and the next reward (Josh, 19 Oct).
                        if calm, let pass = passBadgeInfo {
                            PassBadge(info: pass) { showPass = true }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, edge + camera.topTrailing)
                .padding(.top, top)

                if calm {
                    // Bottom left: Feed, Play and the nap, with whether each is done today.
                    if visit.canDecorate {
                        let session = GameSession.shared
                        let fed = session.state(at: session.now()).isFedToday(GameSession.catID)
                        let plays = session.playsLeft
                        HStack(alignment: .bottom, spacing: 12 * hudScale) {
                            CareButton("Feed", icon: "feed_bowl", badge: fed ? "✓" : nil, lit: !fed) { visit.feed() }
                                .tourTarget("feed")
                            CareButton("Play", icon: "play_feather", badge: plays > 0 ? "\(plays)" : nil) {
                                tour.heard(.opened("play"))
                                tips.used("play")
                                // Always the Games menu: after the day's five quick plays its quick games say "Just for
                                // fun today", and the rest have their own rules (Josh's iPad, 19 Oct: Play seemed dead,
                                // only a line from the cat once the five were used).
                                showGames = true
                            }
                            .tourTarget("play")
                            CareButton(naps.isNapping ? "Wake" : "Nap", icon: "nap_cat", lit: naps.isNapping) {
                                tour.heard(.opened("nap"))
                                tips.used("nap")
                                if naps.isNapping {
                                    visit.wakeFromNap()
                                } else {
                                    offeringNap = true
                                }
                            }
                            .tourTarget("nap")
                        }
                        .id(visit.stats)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, edge + camera.bottomLeading)
                        .padding(.bottom, bottom)
                        .transition(.opacity)
                    }

                    // Bottom right: Decorate and the Shop.
                    HStack(alignment: .bottom, spacing: 12 * hudScale) {
                        if visit.canDecorate {
                            GameButton("Decorate", icon: "decorate_paintbrush", size: 60) { visit.toggleDecorating() }
                                .tourTarget("decorate")
                        }
                        GameButton("Shop", icon: "shop_bag", style: .gold, size: 72) {
                            tour.heard(.opened("shop"))
                            tips.used("shop")
                            openShop(nil)
                        }
                        .tourTarget("shop")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, edge + camera.bottomTrailing)
                    .padding(.bottom, bottom)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// The home now, when the weather on screen is Apple Weather's (so its mark is due); nil while it is the game's
    /// own (a fixed season, no report yet, the Christmas snow).
    private var appleWeatherNow: HomeNow? {
        let session = GameSession.shared
        let now = GameWorld.now(state: session.state(at: session.now()), at: session.now())
        return now.weatherIsReal ? now : nil
    }

    /// Outside to look at the house (Visit.stepOutside): the home's town top left with the weather under it, Go in
    /// bottom right where the Shop is in the room. A tap on the door goes in too, and one on the cat in its window
    /// gets a slow blink.
    private var outsideControls: some View {
        let edge = CGFloat(Tuning.Stage.hudEdge), top = CGFloat(Tuning.Stage.hudTop), bottom = CGFloat(Tuning.Stage.hudBottom)
        let session = GameSession.shared
        let town = PlaceLabels.town(session.state(at: session.now()).homePlace.name)
        return ZStack {
            VStack(alignment: .leading, spacing: 6 * hudScale) {
                HStack(spacing: 6 * hudScale) {
                    PaintedIcon("map_pin", size: 26 * hudScale)
                    Text(town)
                        .font(Theme.title(17 * hudScale))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                .padding(.leading, 10 * hudScale)
                .padding(.trailing, 16 * hudScale)
                .padding(.vertical, 7 * hudScale)
                .paper(Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your home in \(town)")
                // The weather you are standing in, with Apple's mark when it is Apple's.
                if let now = appleWeatherNow {
                    WeatherMark(caption: WeatherMark.caption(now, at: session.now()))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, edge)
            .padding(.top, top)
            GameButton("Go in", icon: "house", style: .gold, size: 72) { visit.goBackIn() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, edge)
                .padding(.bottom, bottom)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    /// The cat's line in a bubble over its head, following it about the room (top middle when it is out of sight),
    /// and a note ("+10 Beans") up top.
    private var speech: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if let line = visit.greeting {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                        let width = min(300 * hudScale, size.width * 0.42)
                        let head = catHead()
                        // Kept clear of the corners' controls and the screen's edges.
                        let x = min(max(head?.x ?? size.width / 2, width / 2 + 24), size.width - width / 2 - 24)
                        // Its bottom (the tail's tip) just over the head, low enough to clear the top bars.
                        let bottom = max(head.map { $0.y - 6 * hudScale } ?? 170 * hudScale, 160 * hudScale)
                        let room = 320 * hudScale
                        GreetingBubble(line, name: visit.catName, pointsDown: head != nil)
                            .onTapGesture { visit.dismissGreeting() }
                            // The goal tracker fades back while this is under it.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global).integral } action: { visit.greetingFrame = $0 }
                            .onDisappear { visit.greetingFrame = nil }
                            .frame(width: width, height: room, alignment: .bottom)
                            .position(x: x, y: bottom - room / 2)
                    }
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                }
                if let toast = visit.toast {
                    Toast(toast, icon: visit.toastIcon)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        // Under the goal tracker when it is up (20 Oct: "+3 Beans" was hidden behind the card).
                        .padding(.top, max(14, belowTracker(in: geometry)))
                }
            }
        }
        .ignoresSafeArea()
    }

    /// How far down `geometry` a note up top starts to clear the goal tracker's card (0 while the card is hidden).
    private func belowTracker(in geometry: GeometryProxy) -> CGFloat {
        visit.trackerFrame.map { $0.maxY - geometry.frame(in: .global).minY + 8 * hudScale } ?? 0
    }

    /// The top of the cat's head in the view's points, when it is in a room on screen.
    private func catHead() -> CGPoint? {
        guard let scene = visit.scene as? RoomScene, scene.view != nil, let cat = scene.director?.cat, let room = cat.parent,
              room.scene === scene else { return nil }
        let frame = cat.bodyFrame
        return scene.convertPoint(toView: scene.convert(CGPoint(x: frame.midX, y: frame.maxY), from: room))
    }

    /// The menu's rooms: every room of the home, floor by floor, the closed ones bare with their price.
    private var menuRooms: [RoomMenu.Room] {
        guard let house = visit.scene as? RoomScene else { return [] }
        return house.house.rooms.sorted { ($0.storey, $0.id) < ($1.storey, $1.id) }.map { room in
            RoomMenu.Room(
                id: room.id,
                storey: room.storey,
                title: Visit.title(of: room.id, upstairs: room.storey > 0),
                lock: room.lockLabel.map { _ in
                    RoomMenu.Lock(house: HouseLadder.rung(HouseLadder.rung(opening: room.id)).name)
                },
                wall: room.model.wall,
                floor: room.model.floor,
                outdoor: room.outdoor,
                here: room.id == visit.activeRoom,
                catHere: room.id == house.catRoom
            )
        }
    }

    /// The menu's other places: the map, the book, the pass, the gift track while it runs, the together quest.
    private var menuItems: [RoomMenu.Item] {
        let session = GameSession.shared
        let pass = session.passInfo(passes: store?.entitlements.passes ?? [])
        var items: [RoomMenu.Item] = []
        // Out of the front door to look at the house, the cat at a window (Josh, 20 Oct); only once the home's outside
        // paintings are on the device (a home's pack may still be on its way).
        if HomePacks.isReady(GameWorld.style(session.state(at: session.now()))) {
            items.append(RoomMenu.Item(id: "outside", title: "Outside", icon: "house") {
                showMenu = false
                visit.stepOutside()
            })
        }
        items += [
            RoomMenu.Item(
                id: "goals",
                title: "Goals",
                icon: "objectives_clipboard_with_a_tick",
                dot: CatScreens.goalsMet().count > GoalsSeen.count
            ) {
                showMenu = false
                GoalsSeen.count = CatScreens.goalsMet().count
                showGoals = true
            },
            RoomMenu.Item(id: "homes", title: "Homes", icon: "house") {
                showMenu = false
                showHomes = true
            },
            RoomMenu.Item(id: "book", title: "Book", icon: "collection_book") {
                showMenu = false
                showBook = true
            },
        ]
        // The season pass only while a season is on: before the first one, or between seasons, there is nothing to
        // show but a date (App Review 2.1: no "coming soon" screens).
        if let pass {
            items.append(RoomMenu.Item(
                id: "pass",
                title: "Pass",
                icon: "season_pass_ticket",
                dot: !pass.claimableFree.isEmpty || !pass.claimablePaid.isEmpty
            ) {
                showMenu = false
                showPass = true
            })
        }
        if let live = session.liveTrack() {
            items.append(RoomMenu.Item(
                id: "gifts",
                title: "Gifts",
                icon: "gift_box_with_a_ribbon",
                dot: !session.trackProgress(live).waiting.isEmpty
            ) {
                showMenu = false
                track = live
            })
        }
        if session.isCoOwned {
            let quest = session.questProgress
            items.append(RoomMenu.Item(
                id: "together",
                title: "Together",
                icon: "group_of_three_paw_prints",
                dot: quest.map { $0.isComplete && !$0.claimed } ?? false
            ) {
                showMenu = false
                showTogether = true
            })
        }
        return items
    }

    /// The pass for the room's badge (it follows the stats, which change with every event).
    private var passBadgeInfo: GameSession.PassInfo? {
        _ = visit.stats
        let owned = store?.entitlements ?? .none
        return GameSession.shared.passInfo(passes: owned.passes)
    }

    /// Something in the menu waits (a pass reward, a present, the quest's Beans): a dot on its button.
    private var menuWaiting: Bool {
        menuItems.contains(where: \.dot)
    }

    /// The menu over the room, under the player's plaque; a tap outside closes it.
    private var roomMenu: some View {
        ZStack(alignment: .topLeading) {
            if showMenu {
                Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { showMenu = false }
                RoomMenu(catName: visit.catName ?? "Your cat", rooms: menuRooms, items: menuItems) { room in
                    showMenu = false
                    if visit.openRooms.contains(room) {
                        visit.go(to: room)
                    } else {
                        visit.offer(room)
                    }
                } close: {
                    showMenu = false
                }
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                .padding(.leading, CGFloat(Tuning.Stage.hudEdge))
                .padding(.top, CGFloat(Tuning.Stage.hudTop) + 74 * hudScale)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: showMenu)
    }

    /// A tap on a goal in the tracker: where it is done. Places in the menu open as the menu opens them.
    private func goal(_ action: GoalAction) {
        switch action {
        case .play:
            // The Games menu, as the Play button opens it: its games count for the play goals after the day's five
            // quick plays too.
            showGames = true
        case .nap:
            if !naps.isNapping {
                offeringNap = true
            }
        case .wardrobe: showProfile = true
        case .streak: showStreak = true
        case .road: showRoad = true
        case let .decorate(room):
            if let room, room != visit.activeRoom, visit.openRooms.contains(room) {
                visit.go(to: room)
            }
            if !visit.decorating {
                visit.toggleDecorating()
            }
        case let .room(room):
            if visit.openRooms.contains(room) {
                visit.go(to: room)
            } else {
                visit.offer(room)
            }
        case .homes, .book, .pass, .goals:
            let id = switch action {
            case .homes: "homes"
            case .book: "book"
            case .pass: "pass"
            default: "goals"
            }
            if let item = menuItems.first(where: { $0.id == id }) {
                item.action()
            } else {
                showGoals = true
            }
        case .point, .cat:
            break
        }
    }

    /// The goal tracker steps aside while decorating, trying a look, in the menu, under any screen over the room, and
    /// in the tour but for its own step (the tour's card would cover it). A goal met while it is away is cheered when
    /// the room is back, where the player sees it (20 Oct: the map's goal ticked and chimed under the globe).
    private var trackerHidden: Bool {
        visit.decorating || visit.previewing != nil || showMenu || roomCovered
            || (tour.isRunning && tour.step?.reward != true)
    }

    /// A screen, sheet or card is over the room: the Games menu or a game, the shop, the pass, the map, the Goals page,
    /// the book, the profile and its wardrobe, the streak, the road, the settings, or Together.
    private var roomCovered: Bool {
        showGames || playing != nil || showShop || showPass || showGoals || showBook || showHomes || showProfile
            || tryingOn != nil || editing != nil || showStreak || showRoad || showSettings || showTogether
    }

    /// The Goals page, with the cat's name and this home's rooms.
    private func goalsPage(_ board: GoalBoard) -> GoalsView {
        GoalsView(board: board, catName: visit.catName ?? "Your cat", roomTitle: roomTitle) { showGoals = false }
    }

    /// A room's name in this home (a garden upstairs is the balcony).
    private func roomTitle(_ room: RoomID) -> String {
        Visit.title(of: room, upstairs: ((visit.scene as? RoomScene)?.house.room(room)?.storey ?? 0) > 0)
    }

    private func openShop(_ section: ShopView.Section?) {
        shopOpening = section
        showShop = true
    }

    /// The outfit catalogue (the shop's Try them on), on an outfit if one is given. The cover or sheet it is called
    /// from (the shop dismissing itself) is let go first, and gone before the catalogue comes up.
    func tryOutfits(_ outfitID: String?) {
        Task { @MainActor in
            showShop = false
            showProfile = false
            try? await Task.sleep(for: .seconds(0.5))
            tryingOn = OutfitCatalogueModel(opening: outfitID)
        }
    }

    /// A card over the room, dimming it; a tap outside closes it when `close` is given.
    /// Too tall for the screen (large text sizes), it scrolls rather than cut its words short. On an iPad it is drawn
    /// larger as a whole, at the controls' scale.
    private func card(_ shown: Bool, close: (() -> Void)?, @ViewBuilder content: () -> some View) -> some View {
        ZStack {
            if shown {
                Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { close?() }
                let inside = content().environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                ViewThatFits(in: .vertical) {
                    inside.padding(24)
                    ScrollView {
                        inside.padding(24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .zoomed(hudScale)
            }
        }
        .animation(.easeOut(duration: 0.25), value: shown)
    }

    /// The level, road, streak and pass cards.
    private func progressCards(_ content: some View) -> some View {
        content
        #if DEBUG
            // Screenshot runs: HOUSECAT_SCREEN=levelup|road|streak|pass|addwidget|together|reminders|health|trylook|outside.
            .task(id: visit.ready && visit.scene is RoomScene) {
                // HOUSECAT_OUTFIT=<id>: the cat given that outfit and wearing it.
                if visit.ready, let outfit = ProcessInfo.processInfo.environment["HOUSECAT_OUTFIT"] {
                    let session = GameSession.shared
                    if !session.ownedOutfits.contains(outfit) {
                        session.append(
                            .purchaseBeansGranted(transactionID: "debug-outfit-\(outfit)", beans: Tuning.Beans.outfit),
                            at: session.now()
                        )
                        session.buyOutfit(outfit)
                    }
                    session.wear(outfit)
                    visit.dressCat()
                    profileVersion += 1
                }
                guard visit.ready, visit.scene is RoomScene,
                      let wanted = ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] else { return }
                try? await Task.sleep(for: .seconds(3))
                switch wanted {
                case "levelup": visit.levelReached = max(2, visit.stats.level)
                case "road": showRoad = true
                case "streak": showStreak = true
                case "pass": showPass = true
                case "gifts": track = GameSession.shared.liveTrack()
                case "shop": openShop(ProcessInfo.processInfo.environment["HOUSECAT_SHOP"].flatMap(ShopView.Section.init))
                case "addwidget": await askForWidget()
                case "together": showTogether = true
                case "menu": showMenu = true
                // The world map over the room, as the menu's Map opens it.
                case "goals": showGoals = true
                case "homes": showHomes = true
                case "book": showBook = true
                case "profile": showProfile = true
                case "editlook": editing = CatScreens.builder(mode: .edit)
                // HOUSECAT_TRY=<outfit id> opens the catalogue on that outfit.
                case "catalogue": tryOutfits(ProcessInfo.processInfo.environment["HOUSECAT_TRY"])
                case "settings": showSettings = true
                // Out of the front door, the cat at its window (the outfit checks).
                case "outside": visit.stepOutside()
                case "erase": await YourData.deleteEverything()
                case "trylook":
                    // A look for an open room (the bedroom's first, else the living room's).
                    let state = GameSession.shared.state(at: GameSession.shared.now())
                    let looks = GameSession.shared.bundles.filter { state.openedRooms.contains($0.room) }
                    if let look = looks.first(where: { $0.room == .bedroom }) ?? looks.first {
                        visit.preview(look)
                    }
                case "reminders": visit.askReminders = true
                // As a new player meets it: reminders not yet asked for.
                case "dayone":
                    Reminders.asked = false
                    dayOne = true
                // HOUSECAT_TIP=<id>: that first-use tip.
                case "tip":
                    tips.reset()
                    let id = ProcessInfo.processInfo.environment["HOUSECAT_TIP"] ?? "goals"
                    tips.showNext(on: [GameWorld.content?.intro.tips?.first { $0.id == id }?.target ?? "goals"])
                case "health": askingHealth = true
                default: break
                }
            }
        #endif
            .overlay {
                card(visit.levelReached != nil && !tour.isRunning && visit.ready, close: nil) {
                    if let level = visit.levelReached, let stop = GameSession.shared.stop(for: level) {
                        LevelUpCard(stop: stop, next: LevelRoadmap.nextRoomLevel(after: level)) {
                            visit.levelReached = nil
                            showRoad = true
                        } close: {
                            visit.levelReached = nil
                        }
                    }
                }
            }
            // What the other owner left since this phone last looked: a present to open, or paw prints.
            .task(id: visit.ready && visit.scene is RoomScene) {
                guard visit.ready, visit.scene is RoomScene else { return }
                var debugPresent = false
                #if DEBUG
                    debugPresent = ProcessInfo.processInfo.environment["HOUSECAT_SCREEN"] == "present"
                #endif
                guard GameSession.shared.isCoOwned || debugPresent else { return }
                try? await Task.sleep(for: .seconds(Tuning.Care.lineSeconds))
                let seen = Together.take()
                if let gift = seen.gifts.first {
                    present = gift
                } else if let (key, count) = seen.prints.first {
                    let name = GameSession.shared.otherOwnerName(key)
                    visit.notify(
                        count == 1 ? "\(name) left you a paw print" : "\(name) left you \(count) paw prints",
                        icon: "group_of_three_paw_prints"
                    )
                }
            }
            .overlay {
                card(present != nil, close: nil) {
                    if let present {
                        PresentCard(gift: present, catName: visit.catName ?? "Your cat") { self.present = nil }
                    }
                }
            }
            .overlay {
                card(showGoals, close: { showGoals = false }) {
                    if let board = CatScreens.goals() {
                        goalsPage(board)
                    }
                }
            }
            .overlay {
                card(showTogether, close: { showTogether = false }) {
                    TogetherCard(catName: visit.catName ?? "Your cat") {
                        showTogether = false
                        openShop(.outfits)
                    } close: {
                        showTogether = false
                        visit.refreshStats()
                    }
                }
            }
            .overlay {
                card(askingWidget, close: { askingWidget = false }) {
                    WidgetPromptCard(catName: visit.catName ?? "Your cat") { askingWidget = false }
                }
            }
            .overlay {
                card(showRoad, close: { showRoad = false }) {
                    RoadmapView(info: GameSession.shared.levelInfo, stops: GameSession.shared.roadmap()) { showRoad = false }
                }
            }
            .overlay {
                card(showStreak, close: { showStreak = false }) {
                    StreakCard(catName: visit.catName ?? "Your cat") {
                        showStreak = false
                        visit.refreshStats()
                    }
                }
            }
            .overlay {
                // The season pass, the whole screen (App/Sources/PassView.swift).
                ZStack {
                    if showPass {
                        PassView(store: store) { item in
                            showPass = false
                            visit.refreshStats()
                            visit.openTray(on: item)
                        } close: {
                            showPass = false
                            visit.refreshStats()
                        }
                        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: showPass)
            }
    }

    private func trayEntries() -> [DecorateTray.Entry] {
        // Drawn again as the cards' pictures arrive (made off the main thread; a card shows its box until then).
        _ = visit.cardPictures
        let sprites: [String] = switch visit.trayMode {
        case .furniture: visit.inventory.map(\.sprite)
        case .shop: visit.shopEntries.map(\.sprite)
        case .walls, .floors: visit.surfaceOptions.options.map(\.sprite)
        }
        CatScreens.cardPictures(sprites) { visit.cardPicturesArrived() }
        return switch visit.trayMode {
        case .furniture: visit.inventory.map(trayEntry)
        case .shop: visit.shopEntries.map(shopEntry)
        case .walls, .floors: surfaceEntries()
        }
    }

    /// A Bean-shop piece with its price (or the level it needs).
    private func shopEntry(_ entry: GameSession.ShopEntry) -> DecorateTray.Entry {
        let image = CatScreens.cardPicture(entry.sprite)
        let (price, enabled, short) = switch entry.status {
        case let .buyable(price): ("\(price) Beans", true, false)
        // Short of Beans: still tappable, for a top-up (Josh, 18 Oct).
        case let .needsBeans(price): ("\(price) Beans", true, true)
        case let .needsLevel(level): ("Level \(level)", false, false)
        }
        return DecorateTray.Entry(id: entry.id, name: entry.name, count: 1, image: image, price: price, enabled: enabled, short: short)
    }

    /// The room's wallpapers or floors as tray entries, the one up now marked.
    private func surfaceEntries() -> [DecorateTray.Entry] {
        let (options, current) = visit.surfaceOptions
        return options.map { surface in
            let image = CatScreens.cardPicture(surface.sprite)
            return DecorateTray.Entry(id: surface.id, name: surface.name, count: 1, image: image, selected: surface.id == current)
        }
    }

    /// A tray entry with the piece's picture from the app art.
    private func trayEntry(_ entry: GameSession.InventoryEntry) -> DecorateTray.Entry {
        let image = CatScreens.cardPicture(entry.sprite)
        return DecorateTray.Entry(id: entry.id, name: entry.name, count: entry.count, image: image)
    }

    /// Opening a room (SPEC "Home and furniture": every room needs a level and Beans).
    /// A closed room: it comes with a house up the ladder (docs/LADDER.md), so the homes open from here.
    private func roomAlert(_ offer: Visit.RoomOffer) -> Alert {
        let name = Visit.title(of: offer.room, upstairs: false)
        if case .open = offer.availability {
            return Alert(title: Text("The \(name.lowercased()) is open"))
        }
        let rung = HouseLadder.rung(HouseLadder.rung(opening: offer.room))
        return Alert(
            title: Text("The \(name.lowercased())"),
            message: Text("It comes with the \(rung.name.lowercased()) in \(rung.place.name), house \(rung.number) of \(HouseLadder.top)."),
            primaryButton: .default(Text("See your homes")) { showHomes = true },
            secondaryButton: .cancel()
        )
    }
}

/// The launch screen's look (the wordmark on cream, centred on the whole screen as the launch screen draws it), from
/// the app's first frame until the cat has curled up asleep on the letters (`AnimatedLogo`, the launch film; Josh,
/// 19 Oct: the whole animation every launch) and the first scene is drawn. A tap skips to the home.
struct LaunchCurtain: View {
    @Environment(\.colorScheme) private var scheme
    /// The window has come in beside the wordmark (it starts as the launch screen: the wordmark alone, centred).
    @State private var arrived = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.height * 0.42, proxy.size.width * 0.3)
            ZStack {
                Color("LaunchBackground")
                HStack(spacing: side * 0.16) {
                    if arrived, let player = LaunchFilm.player(dark: scheme == .dark) {
                        // The website's window: Midnight jumps up onto the sill, in the app icon's rounded square.
                        LaunchFilmView(player: player)
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(proxy.size.width * 0.42, 420))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(duration: Tuning.Logo.launchArriveSeconds, bounce: 0.25)) { arrived = true }
        }
        // A tap skips the rest of the film.
        .contentShape(Rectangle())
        .onTapGesture { LaunchFilm.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HouseCat")
        .accessibilityAction(named: "Skip") { LaunchFilm.release() }
    }
}
