import CoreGraphics
import HouseCatCore
import SwiftUI

/// The words the profile and builder use for the cat's numbers and nature.
public enum ProfileText {
    public static func personality(_ p: Personality) -> String {
        switch p {
        case .aloof: "Aloof"
        case .velcro: "Velcro"
        case .gremlin: "Gremlin"
        case .loaf: "Loaf"
        }
    }

    public static func personalityBlurb(_ p: Personality) -> String {
        switch p {
        case .aloof: "Fond of you, on its own terms."
        case .velcro: "Never more than a metre away."
        case .gremlin: "Chaos first, then a nap."
        case .loaf: "Asleep, mostly. Beautifully."
        }
    }

    public static func trust(_ tier: TrustTier) -> String {
        switch tier {
        case .newcomer: "New here"
        case .wary: "Wary"
        case .curious: "Curious"
        case .comfortable: "Comfortable"
        case .bonded: "Bonded"
        case .devoted: "Devoted"
        case .soulmate: "Soulmate"
        }
    }

    /// "Together 43 days", "Together 1 year, 12 days".
    public static func together(_ days: Int) -> String {
        if days == 0 {
            return "Together since today"
        }
        let years = days / 365, rest = days % 365
        guard years > 0 else {
            return "Together \(days) \(days == 1 ? "day" : "days")"
        }
        let y = "\(years) \(years == 1 ? "year" : "years")"
        return rest == 0 ? "Together \(y)" : "Together \(y), \(rest) \(rest == 1 ? "day" : "days")"
    }

    /// "14 weeks old", "5 months old", "2 years, 3 months old".
    public static func age(_ days: Int) -> String {
        let years = days / 365, months = (days % 365) / 30
        if years == 0 {
            if days < 26 * 7 {
                let weeks = days / 7
                return "\(weeks) \(weeks == 1 ? "week" : "weeks") old"
            }
            return "\(months) \(months == 1 ? "month" : "months") old"
        }
        let y = "\(years) \(years == 1 ? "year" : "years")"
        return months == 0 ? "\(y) old" : "\(y), \(months) \(months == 1 ? "month" : "months") old"
    }

    public static func badge(_ badge: CatProfile.Badge) -> String {
        switch badge {
        case .hundredDays: "100 days"
        case let .years(n): n == 1 ? "1 year" : "\(n) years"
        }
    }
}

/// The corner the cat sits in on its profile: a painting, where on it the cat sits and how tall it is there.
public struct ProfileCorner: @unchecked Sendable {
    public var image: CGImage
    /// Where the cat's paws go: the middle of the cushion's top, in the painting's pixels.
    public var perch: CGPoint
    /// The cat's height as a fraction of the painting's.
    public var catHeight: CGFloat

    public init(image: CGImage, perch: CGPoint, catHeight: CGFloat) {
        self.image = image
        self.perch = perch
        self.catHeight = catHeight
    }
}

/// The cat's profile (SPEC "Age and time together"): its picture, how long you have had it and its age,
/// its trust, badges and lifetime stats; Edit look, Rename and Personality change it again, free.
/// Redrawn (Josh, 19 Oct: "a plain white background right now and the qualities etc are a mess") as a builder game's
/// profile with the cat as the star: it sits large on a cushion in a painted corner of a home (`ProfileCorner`: the
/// sunny window by day, the fireside from dusk), Edit look under it and Settings over it; beside it a painted card
/// with its level on the star, its name and age on the warm band, and three tabs: About (trust and level as meters,
/// how it is, its ways each with a painted picture, its personality), Wardrobe and Stats.
public struct CatProfileView: View {
    /// An outfit in the wardrobe: its name and picture.
    public struct WardrobeItem: Identifiable, Sendable {
        public var id: String
        public var name: String
        public var image: CGImage?

        public init(id: String, name: String, image: CGImage?) {
            self.id = id
            self.name = name
            self.image = image
        }
    }

    enum Tab: String, CaseIterable {
        case about = "About"
        case wardrobe = "Wardrobe"
        case stats = "Stats"

        var icon: String {
            switch self {
            case .about: "cat_face"
            case .wardrobe: "creator_hanger"
            case .stats: "xp_star"
            }
        }
    }

    /// The tab it opens on: About, or in a debug run HOUSECAT_PROFILE_TAB=wardrobe or stats (screenshots).
    static var firstTab: Tab {
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["HOUSECAT_PROFILE_TAB"],
               let tab = Tab.allCases.first(where: { $0.rawValue.lowercased() == name })
            {
                return tab
            }
        #endif
        return .about
    }

    let profile: CatProfile
    let wardrobe: [WardrobeItem]
    let worn: String?
    let wear: ((String?) -> Void)?
    private let portrait: CGImage?
    private let corner: ProfileCorner?
    let levelTitle: String?
    let level: (level: Int, intoLevel: Int, toNext: Int)
    private let editLook: () -> Void
    private let rename: (String) -> String?
    let setPersonality: (Personality) -> Void
    private let settings: (() -> Void)?
    private let close: () -> Void
    @State var tab = CatProfileView.firstTab
    @State private var naming = false
    @State private var newName = ""
    @State private var nameProblem: String?
    @State private var breathing = false
    @Environment(\.controlFeedback) var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) var typeSize

    /// `rename` returns a problem with the name, or nil when it was taken.
    public init(
        profile: CatProfile,
        portrait: CGImage?,
        xp: Int,
        corner: ProfileCorner? = nil,
        levelTitle: String? = nil,
        editLook: @escaping () -> Void,
        rename: @escaping (String) -> String?,
        setPersonality: @escaping (Personality) -> Void,
        wardrobe: [WardrobeItem] = [],
        worn: String? = nil,
        wear: ((String?) -> Void)? = nil,
        settings: (() -> Void)? = nil,
        close: @escaping () -> Void
    ) {
        self.wardrobe = wardrobe
        self.worn = worn
        self.wear = wear
        self.settings = settings
        self.profile = profile
        self.portrait = portrait
        self.corner = corner
        self.levelTitle = levelTitle
        level = LevelCurve.progress(xp: xp)
        self.editLook = editLook
        self.rename = rename
        self.setPersonality = setPersonality
        self.close = close
    }

    public var body: some View {
        GeometryReader { proxy in
            // The whole screen, with the safe area's insets kept for the controls and the card (the painting runs
            // under them).
            let insets = proxy.safeAreaInsets
            let size = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            // The card on the right, the stage for the cat on the left. The card may run over the home indicator.
            let panelWidth = min(470, max(392, (size.width - insets.leading - insets.trailing) * 0.56))
            let panelLeft = size.width - insets.trailing - 10 - panelWidth
            let stage = Stage(size: size, insets: insets, middle: (insets.leading + panelLeft) / 2, corner: corner)
            ZStack(alignment: .topLeading) {
                scene(stage)
                controls(stage, insets: insets)
                card
                    .frame(width: panelWidth, height: size.height - insets.top - 24)
                    .offset(x: panelLeft, y: insets.top + 12)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .offset(x: -insets.leading, y: -insets.top)
        }
        .foregroundStyle(Theme.ink)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathing = true }
            }
        }
    }

    // MARK: The cat's corner

    /// Where the painting and the cat go: the painting fills the screen with the cushion under the middle of the
    /// stage as far as it can, never showing past its edges.
    struct Stage {
        var size: CGSize
        var painting: CGRect
        /// The cushion's top on the screen, where the cat's paws go.
        var perch: CGPoint
        var catHeight: CGFloat

        init(size: CGSize, insets: EdgeInsets, middle: CGFloat, corner: ProfileCorner?) {
            self.size = size
            guard let corner else {
                painting = CGRect(origin: .zero, size: size)
                perch = CGPoint(x: middle, y: size.height * 0.82)
                catHeight = size.height * 0.6
                return
            }
            let width = CGFloat(corner.image.width), height = CGFloat(corner.image.height)
            // A little larger than filling, so the cushion can move under the stage.
            let fill = max(size.width / width, size.height / height) * 1.08
            let shown = CGSize(width: width * fill, height: height * fill)
            let x = min(0, max(size.width - shown.width, middle - corner.perch.x * fill))
            let y = min(0, max(size.height - shown.height, size.height * 0.8 - corner.perch.y * fill))
            painting = CGRect(origin: CGPoint(x: x, y: y), size: shown)
            perch = CGPoint(x: x + corner.perch.x * fill, y: y + corner.perch.y * fill)
            // As tall as the painting has it, its ears clear of Settings and the together note.
            catHeight = min(height * corner.catHeight * fill, perch.y - insets.top - 64)
        }
    }

    private func scene(_ stage: Stage) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let corner {
                    Image(decorative: corner.image, scale: 1).resizable().interpolation(.high)
                } else {
                    LinearGradient(colors: [Theme.paper, Color(red: 0.95, green: 0.84, blue: 0.74)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: stage.painting.width, height: stage.painting.height)
            .offset(x: stage.painting.minX, y: stage.painting.minY)
            .accessibilityHidden(true)
            let catWidth = portrait.map { stage.catHeight * CGFloat($0.width) / CGFloat($0.height) } ?? stage.catHeight * 0.6
            // A soft shadow on the cushion under the cat.
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: catWidth * 0.5))
                .frame(width: catWidth * 1.0, height: catWidth * 0.22)
                .offset(x: stage.perch.x - catWidth * 0.5, y: stage.perch.y - catWidth * 0.12)
                .accessibilityHidden(true)
            Group {
                if let portrait {
                    Image(decorative: portrait, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "cat").resizable().scaledToFit().foregroundStyle(Theme.ink)
                }
            }
            .frame(width: catWidth, height: stage.catHeight)
            .scaleEffect(x: 1, y: breathing ? 1.012 : 1, anchor: .bottom)
            .shadow(color: Color(red: 0.16, green: 0.08, blue: 0.04).opacity(0.35), radius: 8, y: 6)
            .offset(x: stage.perch.x - catWidth / 2, y: stage.perch.y - stage.catHeight * 0.985)
            .accessibilityLabel(profile.name)
            .accessibilityAddTraits(.isImage)
        }
    }

    /// Settings and how long you have been together over the corner, Edit look on the rug under the cat.
    private func controls(_ stage: Stage, insets: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 10) {
                if let settings {
                    Button {
                        feedback.tap()
                        settings()
                    } label: {
                        VStack(spacing: 1) {
                            PaintedIcon("settings_cog", size: 34)
                                .frame(width: 50, height: 50)
                                .paper(Circle())
                            Text("Settings")
                                .font(.system(.caption, design: .rounded, weight: .heavy))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Settings")
                }
                HStack(spacing: 6) {
                    PaintedIcon("calendar", size: 26)
                    Text(ProfileText.together(profile.togetherDays))
                        .font(.system(.subheadline, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .padding(.vertical, 5)
                .paper(Capsule(), fill: Theme.cream.opacity(0.94))
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
            }
            .offset(x: insets.leading + 14, y: insets.top + 12)
            EditLookButton(action: editLook)
                .fixedSize()
                .position(x: stage.perch.x, y: min(stage.perch.y + 44, stage.size.height - insets.bottom - 30))
        }
    }

    // MARK: The card

    private var card: some View {
        PaintedPanel(corner: 26) {
            header
        } content: {
            VStack(spacing: 0) {
                tabs.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
                ScrollView {
                    Group {
                        switch tab {
                        case .about: about
                        case .wardrobe: wardrobeView
                        case .stats: stats
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// The level on the star, the name (tap the pencil to rename) and the age and personality, on the warm band.
    private var header: some View {
        HStack(spacing: 10) {
            LevelStar(level: level.level)
            VStack(alignment: .leading, spacing: 3) {
                if naming {
                    HStack(spacing: 6) {
                        TextField("Name", text: $newName)
                            .font(.system(.title3, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cream))
                            .foregroundStyle(Theme.ink)
                            .onSubmit(commitName)
                            .submitLabel(.done)
                        Button("Save", action: commitName)
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(GameHUD.gold))
                            .buttonStyle(PressStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.system(.title, design: .serif, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .shadow(color: Color(red: 0.47, green: 0.24, blue: 0.04).opacity(0.35), radius: 0, y: 2)
                            .accessibilityAddTraits(.isHeader)
                        Button {
                            feedback.tap()
                            newName = profile.name
                            naming = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .heavy))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.white.opacity(0.25)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Rename")
                    }
                }
                Text(nameProblem ?? subtitle)
                    .font(.system(.subheadline, weight: .semibold))
                    .opacity(0.95)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            CloseButton(action: close)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    /// "Velcro · 2 years, 2 months old", "Kitten · 14 weeks old".
    private var subtitle: String {
        ProfileText.personality(profile.personality) + " · " + (profile.isKitten ? "Kitten, " : "") + ProfileText.age(profile.ageDays)
    }

    private func commitName() {
        nameProblem = rename(newName)
        if nameProblem == nil {
            naming = false
        }
    }

    /// About, Wardrobe (when the cat can wear things) and Stats, as chunky pills.
    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases.filter { $0 != .wardrobe || wear != nil }, id: \.self) { item in
                let chosen = item == tab
                Button {
                    feedback.tap()
                    tab = item
                } label: {
                    HStack(spacing: 5) {
                        PaintedIcon(item.icon, size: 20)
                        Text(item.rawValue)
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(chosen ? .white : Theme.ink)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if chosen {
                            ZStack {
                                Capsule().fill(Theme.accent.mix(with: .black, by: 0.3)).offset(y: 2.5)
                                Capsule().fill(LinearGradient(
                                    colors: [Theme.accent.mix(with: .white, by: 0.18), Theme.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                            }
                        } else {
                            Capsule().fill(.white.opacity(0.55)).overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

/// The level on a painted star, as a builder game shows the player's level by their name.
private struct LevelStar: View {
    let level: Int

    var body: some View {
        ZStack {
            PaintedIcon("xp_star", size: 54)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 2)
            Text("\(level)")
                .font(.system(size: level >= 100 ? 15 : 19, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.54, green: 0.3, blue: 0.07), radius: 0, x: 1.2, y: 1.2)
                .shadow(color: Color(red: 0.54, green: 0.3, blue: 0.07), radius: 0, x: -1.2, y: -1.2)
                .shadow(color: Color(red: 0.54, green: 0.3, blue: 0.07), radius: 0, x: 1.2, y: -1.2)
                .shadow(color: Color(red: 0.54, green: 0.3, blue: 0.07), radius: 0, x: -1.2, y: 1.2)
                .offset(y: 3)
        }
        .frame(width: 54, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level)")
    }
}

/// Edit look, gold, with the paintbrush: a raised capsule on its darker lip.
private struct EditLookButton: View {
    @Environment(\.controlFeedback) var feedback
    let action: () -> Void

    var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                PaintedIcon("decorate_paintbrush", size: 26)
                Text("Edit look").font(.system(.headline, design: .rounded, weight: .heavy))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .padding(.leading, 14)
            .padding(.trailing, 20)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    Capsule().fill(GameHUD.deepGold.mix(with: .black, by: 0.3)).offset(y: 4)
                    Capsule().fill(LinearGradient(
                        colors: [GameHUD.deepGold.mix(with: .white, by: 0.25), GameHUD.deepGold],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(1)
                }
                .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
            }
        }
        .buttonStyle(PressStyle())
    }
}

/// The collection book (SPEC "Gifts"): every gift the cat can bring, found ones in colour with their count.
public struct GiftBookView: View {
    public struct Entry: Identifiable {
        public var id: String
        public var name: String
        public var description: String
        public var rarity: GiftRarity
        public var count: Int
        public var image: CGImage?

        public init(id: String, name: String, description: String, rarity: GiftRarity, count: Int, image: CGImage?) {
            self.id = id
            self.name = name
            self.description = description
            self.rarity = rarity
            self.count = count
            self.image = image
        }
    }

    private let entries: [Entry]
    private let close: () -> Void
    @State private var chosen: String?

    public init(entries: [Entry], close: @escaping () -> Void) {
        self.entries = entries
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PaintedIcon("collection_book", size: 40)
                Text("The book").font(Theme.title(34))
                Text("\(entries.filter { $0.count > 0 }.count) of \(entries.count) found").foregroundStyle(Theme.inkSoft)
                Spacer()
                CloseButton(action: close)
            }
            if let entry = entries.first(where: { $0.id == chosen }), entry.count > 0 {
                HStack {
                    Text(entry.name).font(.headline)
                    Text(entry.description).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(entries) { entry in
                        Button {
                            chosen = entry.id
                        } label: {
                            VStack(spacing: 2) {
                                Group {
                                    if let image = entry.image {
                                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "gift").resizable().scaledToFit().padding(14)
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .saturation(entry.count > 0 ? 1 : 0)
                                .brightness(entry.count > 0 ? 0 : -0.6)
                                .opacity(entry.count > 0 ? 1 : 0.35)
                                Text(entry.count > 0 ? entry.name : "?").font(.caption2).lineLimit(1)
                                if entry.count > 1 {
                                    Text("×\(entry.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .frame(width: 84, height: 100)
                            .background(
                                rarityColour(entry.rarity).opacity(entry.count > 0 ? 0.18 : 0.06),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
    }

    private func rarityColour(_ rarity: GiftRarity) -> Color {
        switch rarity {
        case .common: .gray
        case .uncommon: .green
        case .rare: .blue
        case .legendary: .orange
        }
    }
}
