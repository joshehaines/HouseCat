import HouseCatCore
import HouseCatGame
import HouseCatStore
import HouseCatUI
import SwiftUI

/// The outfit catalogue (Josh, 19 Oct: "so the user can see the cat with the items on when selecting which ones to
/// buy, similar room to the character creation"): the player's own cat on the dressing room's podium wearing
/// whatever is picked, the outfits in drawers by kind, each with its price, Owned, or what it comes from (a streak,
/// the season pass, Cat Club's track, its season). Trying on is free and records nothing; Buy spends Beans there
/// and then (a top-up when they fall short), Put it on dresses the cat in the room.
@MainActor
@Observable
final class OutfitCatalogueModel: Identifiable {
    enum Drawer: String, CaseIterable, Identifiable {
        case all, hats, glasses, neck, clothes, mine

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .all: "Everything"
            case .hats: "Hats"
            case .glasses: "Glasses"
            case .neck: "Neck"
            case .clothes: "Clothes"
            case .mine: "Mine"
            }
        }

        var heading: String {
            switch self {
            case .all: "Every outfit"
            case .hats: "Hats"
            case .glasses: "Glasses"
            case .neck: "Collars and scarves"
            case .clothes: "Jumpers and coats"
            case .mine: "Your cat's wardrobe"
            }
        }

        /// The outfit whose picture is on the drawer (the painted hanger for everything, the cat for its own).
        var pictureOutfit: String? {
            switch self {
            case .all, .mine: nil
            case .hats: "beanie"
            case .glasses: "roundglasses"
            case .neck: "scarf"
            case .clothes: "raincoat"
            }
        }

        /// How the cat stands while this drawer is open: close on the face for glasses, facing you for the neck.
        var presentation: DressingRoomScene.Presentation {
            switch self {
            case .glasses: .init(angle: .front, face: true)
            case .neck: .init(angle: .front)
            case .all, .hats, .clothes, .mine: .init(angle: .threeQuarterLeft)
            }
        }

        func holds(_ outfit: OutfitsFile.Outfit, owned: Set<String>) -> Bool {
            switch self {
            case .all: true
            case .hats: outfit.slot == .head && !OutfitCatalogueModel.isGlasses(outfit)
            case .glasses: outfit.slot == .head && OutfitCatalogueModel.isGlasses(outfit)
            case .neck: outfit.slot == .neck
            case .clothes: outfit.slot == .body
            case .mine: owned.contains(outfit.id)
            }
        }
    }

    nonisolated static func isGlasses(_ outfit: OutfitsFile.Outfit) -> Bool {
        outfit.id.contains("glasses")
    }

    let scene: DressingRoomScene?
    let outfits: [OutfitsFile.Outfit]
    var drawer: Drawer = .all {
        didSet {
            scene?.present(drawer.presentation)
        }
    }

    /// What is being tried on (nil: nothing).
    private(set) var trying: String?
    private(set) var owned: Set<String> = []
    private(set) var worn: String?
    private(set) var beans = 0
    /// Bought here this visit, for its celebration.
    private(set) var justBought: String?

    /// `opening` is an outfit to try on first (from the shop's Try them on).
    init?(opening: String? = nil) {
        let session = GameSession.shared
        guard let art = GameWorld.art, let catArt = GameWorld.catArt, let rig = GameWorld.rig, let cat = session.cat else { return nil }
        // Only what can be had: nothing shown that cannot work yet (an outfit for inviting a friend, say).
        let owned = session.ownedOutfits
        outfits = (session.content?.outfits.outfits ?? []).filter { $0.wearable && OutfitAvailability.isShown($0, owned: owned) }
        scene = DressingRoomScene(size: CGSize(width: 800, height: 400), art: art, catArt: catArt, rig: rig, look: cat.look)
        refresh()
        let start = opening.flatMap { id in outfits.first { $0.id == id } } ?? outfits.first { $0.id == worn }
        trying = start?.id
        scene?.dress(start, react: false)
        if let start, let first = Drawer.allCases.dropFirst().first(where: { $0 != .mine && $0.holds(start, owned: owned) }),
           opening != nil
        {
            drawer = first
        }
    }

    func refresh() {
        let session = GameSession.shared
        owned = session.ownedOutfits
        worn = session.wornOutfit?.id
        beans = session.beans
    }

    func outfit(_ id: String?) -> OutfitsFile.Outfit? {
        id.flatMap { id in outfits.first { $0.id == id } }
    }

    /// The open drawer's outfits: worn and owned first, then what can be bought, then the rest.
    var shown: [OutfitsFile.Outfit] {
        outfits.enumerated()
            .filter { drawer.holds($0.element, owned: owned) }
            .sorted { a, b in
                let (x, y) = (status(of: a.element).rank, status(of: b.element).rank)
                return x == y ? a.offset < b.offset : x < y
            }
            .map(\.element)
    }

    func count(in drawer: Drawer) -> Int {
        outfits.count { drawer.holds($0, owned: owned) }
    }

    func status(of outfit: OutfitsFile.Outfit) -> OutfitAvailability {
        OutfitAvailability.of(outfit, owned: owned, worn: worn, on: DayClock().day(of: .now))
    }

    // MARK: Trying on, buying, wearing

    func tryOn(_ id: String?) {
        guard id != trying else { return }
        trying = id
        justBought = nil
        scene?.dress(outfit(id))
    }

    /// Something the cat does not have on yet, at random.
    func surprise() {
        let others = shown.filter { $0.id != trying }
        tryOn((others.isEmpty ? outfits : others).randomElement()?.id)
    }

    /// Beans still needed to buy what is being tried on (0 when there are enough).
    var shortfall: Int {
        BeanPrices.shortfall(price: Tuning.Beans.outfit, balance: beans)
    }

    /// Buys what is being tried on with Beans; false when Beans fall short (or it is not for sale).
    @discardableResult
    func buy() -> Bool {
        guard let id = trying, let outfit = outfit(id), case .forSale = status(of: outfit),
              GameSession.shared.buyOutfit(id) else { return false }
        refresh()
        justBought = id
        scene?.twirl()
        return true
    }

    /// Puts what is being tried on on the cat for good (it then wears it in the room), or takes it off.
    func wear() {
        GameSession.shared.wear(trying)
        refresh()
    }

    func takeOff() {
        GameSession.shared.wear(nil)
        refresh()
    }
}

/// The catalogue's screen, in the creator's dressing room (`DressingRoomLayout`).
struct OutfitCatalogueView: View {
    @Bindable var model: OutfitCatalogueModel
    let store: (any EntitlementService)?
    let close: () -> Void
    @State private var prices = StorePrices.shared
    @State private var toppingUp = false
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        ZStack {
            DressingRoomLayout(
                scene: model.scene,
                sceneLabel: sceneLabel,
                drawers: OutfitCatalogueModel.Drawer.allCases.map { drawer in
                    WardrobeDrawer(id: drawer.rawValue, title: drawer.title, icon: icon(drawer))
                },
                open: model.drawer.rawValue,
                choose: { id in
                    if let drawer = OutfitCatalogueModel.Drawer(rawValue: id) {
                        model.drawer = drawer
                    }
                },
                top: { m in top(m) },
                bottom: { m in
                    // The short words when the space over the cat is narrow (a phone).
                    ViewThatFits(in: .horizontal) {
                        buttons(nothing: "Nothing on", surprise: "Surprise me", m)
                        buttons(nothing: "Nothing", surprise: "Surprise", m)
                    }
                },
                panel: { m in
                    DrawerPanel(
                        icon: icon(model.drawer),
                        heading: model.drawer.heading,
                        subtitle: subtitle,
                        metrics: m,
                        scrollID: model.drawer
                    ) {
                        grid(m)
                    } footer: {
                        footer(m)
                    } accessory: {
                        balance(m)
                    }
                }
            )
            if toppingUp, let outfit = model.outfit(model.trying) {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { toppingUp = false }
                    BeanTopUp(need: model.shortfall, purpose: "the \(outfit.name)", store: store) { bought in
                        toppingUp = false
                        model.refresh()
                        if bought {
                            model.buy()
                        }
                    }
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: toppingUp)
        .task {
            model.refresh()
            if prices.products.isEmpty {
                await prices.load(store: store, content: GameWorld.content)
            }
        }
    }

    private func icon(_ drawer: OutfitCatalogueModel.Drawer) -> DrawerIcon {
        if let id = drawer.pictureOutfit, let path = model.outfit(id)?.sprites["tqfront"] {
            return .picture(CatScreens.picture(path))
        }
        return .painted(drawer == .mine ? "cat_face" : "creator_hanger")
    }

    private var sceneLabel: String {
        let name = GameSession.shared.cat?.name ?? "Your cat"
        if let outfit = model.outfit(model.trying) {
            return "\(name) on the podium, trying on the \(outfit.name)"
        }
        return "\(name) on the podium, with nothing on"
    }

    private var subtitle: String {
        let count = model.count(in: model.drawer)
        if model.drawer == .mine {
            return count == 0 ? "Nothing yet: buy one, or earn one in play" : "\(count) to wear, free to change"
        }
        return "\(count) \(count == 1 ? "outfit" : "outfits"), \(Tuning.Beans.outfit) Beans each"
    }

    private func buttons(nothing: String, surprise: String, _ m: WardrobeMetrics) -> some View {
        HStack(spacing: 8 * m.s) {
            HUDButton(nothing, symbol: "xmark") { model.tryOn(nil) }
                .disabled(model.trying == nil)
                .opacity(model.trying == nil ? 0.45 : 1)
                .accessibilityLabel("Nothing on")
            HUDButton(surprise, icon: "creator_dice") { model.surprise() }
                .accessibilityLabel("Surprise me")
        }
        .fixedSize()
    }

    // MARK: Above the cat: Close and what is on (the Beans are on the open drawer)

    private func top(_ m: WardrobeMetrics) -> some View {
        HStack(alignment: .top, spacing: 8 * m.s) {
            CloseButton(action: close)
                .scaleEffect(m.s, anchor: .topLeading)
                .frame(width: 36 * m.s, height: 36 * m.s, alignment: .topLeading)
            Spacer(minLength: 0)
            Nameplate(model.outfit(model.trying)?.name ?? "Nothing on", subtitle: model.outfit(model.trying).map(plateLine), metrics: m)
            Spacer(minLength: 0)
            Color.clear.frame(width: 36 * m.s, height: 1)
        }
    }

    private func balance(_ m: WardrobeMetrics) -> some View {
        HStack(spacing: 4 * m.s) {
            PaintedIcon("bean_coin", size: 22 * m.s)
            Text(model.beans.formatted())
                .font(.system(size: 15 * m.s, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.leading, 8 * m.s)
        .padding(.trailing, 12 * m.s)
        .padding(.vertical, 5 * m.s)
        .paper(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.beans) Beans")
        .animation(.spring(duration: 0.4), value: model.beans)
    }

    // MARK: The open drawer

    private func grid(_ m: WardrobeMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100 * m.s), spacing: 10 * m.s, alignment: .top)], spacing: 10 * m.s) {
            ForEach(model.shown, id: \.id) { outfit in
                card(outfit, m)
            }
        }
    }

    /// An outfit hanging on its hanger: its picture, its name and a tag with its price, Owned, or what it comes from.
    private func card(_ outfit: OutfitsFile.Outfit, _ m: WardrobeMetrics) -> some View {
        let chosen = model.trying == outfit.id
        let status = model.status(of: outfit)
        return Button {
            feedback.tap()
            model.tryOn(chosen ? nil : outfit.id)
        } label: {
            VStack(spacing: 4 * m.s) {
                Group {
                    if let path = outfit.sprites["tqfront"], let picture = CatScreens.picture(path) {
                        picture.resizable().interpolation(.high).scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 56 * m.s)
                .frame(maxWidth: .infinity)
                Text(outfit.name)
                    .font(.system(size: 12.5 * m.t, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                tag(status, m)
            }
            .padding(.horizontal, 6 * m.s)
            .padding(.top, 12 * m.s)
            .padding(.bottom, 7 * m.s)
            .frame(maxWidth: .infinity)
            .background(CardBackground(selected: chosen, s: m.s))
            .overlay(alignment: .top) { Hanger(s: m.s).offset(y: -9 * m.s) }
            .padding(.top, 9 * m.s)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(outfit.name), \(statusLine(outfit))")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .animation(.spring(duration: 0.25), value: chosen)
    }

    @ViewBuilder
    private func tag(_ status: OutfitAvailability, _ m: WardrobeMetrics) -> some View {
        let font = Font.system(size: 11.5 * m.t, weight: .heavy, design: .rounded)
        switch status {
        case .wearing:
            Label("Wearing", systemImage: "checkmark.circle.fill").font(font).foregroundStyle(Theme.accent)
        case .owned:
            Label("Owned", systemImage: "checkmark").font(font).foregroundStyle(Theme.inkSoft)
        case let .forSale(beans: price):
            HStack(spacing: 3 * m.s) {
                PaintedIcon("bean_coin", size: 15 * m.s)
                Text(price.formatted()).font(font).monospacedDigit()
            }
            .padding(.horizontal, 8 * m.s)
            .padding(.vertical, 2 * m.s)
            .background(Capsule().fill(Theme.accent.opacity(0.16)))
        default:
            Label(shortLock(status), systemImage: "lock.fill").font(font).foregroundStyle(Theme.inkSoft).lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// A locked outfit's tag, in a word or two.
    private func shortLock(_ status: OutfitAvailability) -> String {
        switch status {
        case let .outOfSeason(months): months.first.map(Self.month) ?? "Seasonal"
        case let .pass(premium): premium ? "Premium pass" : "Season pass"
        case let .earned(source): Self.earning(source, short: true)
        case .wearing, .owned, .forSale: ""
        }
    }

    /// What an outfit is, in a word or two, under its name above the cat (the whole phrase is at the drawer's foot).
    private func plateLine(_ outfit: OutfitsFile.Outfit) -> String {
        let status = model.status(of: outfit)
        switch status {
        case .wearing: return "Wearing it"
        case .owned: return "Owned"
        case let .forSale(beans: price): return "\(price) Beans"
        case .outOfSeason, .pass, .earned: return shortLock(status)
        }
    }

    /// What an outfit is for this household, in a phrase (the drawer's foot, VoiceOver).
    private func statusLine(_ outfit: OutfitsFile.Outfit) -> String {
        switch model.status(of: outfit) {
        case .wearing: "Your cat is wearing it"
        case .owned: "In your cat's wardrobe"
        case let .forSale(beans: price): "\(price) Beans"
        case let .outOfSeason(months): "On sale in \(months.map(Self.month).formatted(.list(type: .or)))"
        case let .pass(premium): premium ? "A reward on a season's premium track" : "A season pass reward"
        case let .earned(source): Self.earning(source, short: false)
        }
    }

    static func month(_ month: Int) -> String {
        DateFormatter().standaloneMonthSymbols[(month - 1 + 12) % 12]
    }

    /// How an earned outfit is earned (outfits.json `earnedBy`).
    static func earning(_ source: String, short: Bool) -> String {
        if source.hasPrefix("streak_"), let days = Int(source.dropFirst("streak_".count)) {
            return short ? "\(days)-day streak" : "Earned with a \(days)-day streak"
        }
        if source.hasPrefix("level_"), let level = Int(source.dropFirst("level_".count)) {
            return short ? "Level \(level)" : "Earned at level \(level)"
        }
        return short ? "Earned" : "Earned in play"
    }

    // MARK: The foot: buy, put on, take off, or what unlocks it

    @ViewBuilder
    private func footer(_ m: WardrobeMetrics) -> some View {
        if let outfit = model.outfit(model.trying) {
            HStack(spacing: 10 * m.s) {
                VStack(alignment: .leading, spacing: 1 * m.s) {
                    Text(outfit.name).font(Theme.title(16 * m.t)).lineLimit(1)
                    Text(footNote(outfit))
                        .font(.system(size: 11.5 * m.t, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                action(outfit, m)
            }
        } else {
            Text("Pick an outfit to try it on.")
                .font(.system(size: 13 * m.t, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.vertical, 10 * m.s)
        }
    }

    private func footNote(_ outfit: OutfitsFile.Outfit) -> String {
        switch model.status(of: outfit) {
        case let .forSale(beans: price):
            // The money a Bean price comes to, beside it (EU CPC principles on in-game currencies).
            if let money = prices.value(ofBeans: price) {
                return "\(price) Beans, about \(money). Fits every cat."
            }
            return "\(price) Beans. Fits every cat."
        case .owned where model.justBought == outfit.id: return "It's yours. Put it on now, or any time."
        default: return statusLine(outfit)
        }
    }

    @ViewBuilder
    private func action(_ outfit: OutfitsFile.Outfit, _ m: WardrobeMetrics) -> some View {
        switch model.status(of: outfit) {
        case .wearing:
            HUDButton("Take it off", symbol: "xmark") { model.takeOff() }
        case .owned:
            ChunkyButton("Put it on") { model.wear() }.fixedSize()
        case .forSale:
            if model.shortfall > 0 {
                ChunkyButton("Top up", colour: Color(red: 0.36, green: 0.6, blue: 0.42)) { toppingUp = true }.fixedSize()
            } else {
                ChunkyButton("Buy") { model.buy() }.fixedSize()
            }
        case .outOfSeason, .pass, .earned:
            Image(systemName: "lock.fill")
                .font(.system(size: 18 * m.s, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 40 * m.s, height: 40 * m.s)
                .paper(Circle())
                .accessibilityHidden(true)
        }
    }
}
