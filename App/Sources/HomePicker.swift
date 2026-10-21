import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// Onboarding's house step (SPEC "The session loop": cat, geography, house, first arrival): the eight homes,
/// each painted where you pinned yours, a summer picture. The London terrace's exteriors are in the app; the
/// others arrive as a download (HomePacks), and until then the visit simply starts inside. Choosing one of those says
/// how big the download is on the "Before you move in" card (on an iPad too) before it is asked for.
///
/// Josh, 19 Oct: "put a bigger warning when choosing a house, they should understand that the colours etc will be
/// different based on season etc." So the home you pick can be seen at four times of day, and through the year when
/// its season paintings are in the app, with the season and the time there now: beside the home on an iPad, and as
/// a "Before you move in" card when you confirm on a phone.
///
/// Josh, 20 Oct (on his iPad): "the which home section needs a re-do in terms of UI, the make it home needs to be
/// bigger". Redrawn as a builder game's pick screen: the chosen home large, with what it is (its kind, its words,
/// its floors and rooms) and a big Make it home beside it; all eight homes as a roster under it (a row to scroll on a
/// phone, two rows of four on an iPad) to compare at a glance.
struct HomePicker: View {
    let biome: Biome
    let place: String
    /// Where the home will be, and its season setting; nil reads both from the save (the first pin is saved
    /// before this step). Moving house passes the new place before it is saved.
    var home: HomePlace?
    var season: SeasonSetting?
    var confirmTitle = "Make it home"
    var cancel: (() -> Void)?
    let done: (HouseStyle) -> Void
    @State private var chosen: HouseStyle = .londonTerrace
    @State private var confirming = false
    /// The time of day and the season the big painting shows (afternoon in summer until one is picked).
    @State private var shownSky: SkyPhase = .day
    @State private var shownSeason: NatureSeason?
    @Environment(\.controlFeedback) private var feedback
    @Environment(\.verticalSizeClass) private var verticalSize

    /// A phone on its side: the warning waits for the "Before you move in" card.
    private var compact: Bool {
        verticalSize == .compact
    }

    var body: some View {
        GeometryReader { proxy in
            // Drawn for a landscape phone and enlarged on an iPad, as the room's controls are.
            let s = min(1.5, max(1, min(proxy.size.width / 820, proxy.size.height / 520)))
            let inner = CGSize(width: proxy.size.width - 48 * s, height: proxy.size.height - (compact ? 20 : 36) * s)
            Group {
                if proxy.size.width > proxy.size.height * 1.15 {
                    sideBySide(s, in: inner)
                } else {
                    stacked(s, in: inner)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .overlay {
            if confirming {
                beforeYouMoveIn
            }
        }
        .onAppear {
            // Moving house starts on the home you have.
            if home != nil, let current = GameSession.shared.state(at: GameSession.shared.now()).home.style {
                chosen = current
            }
            // So the download note can say whether it would come over mobile data.
            HomePacks.watchNetwork()
            #if DEBUG
                // Screenshot runs: HOUSECAT_HOME=<style> starts on that home, HOUSECAT_HOME_CONFIRM=1 on its card.
                let environment = ProcessInfo.processInfo.environment
                if let name = environment["HOUSECAT_HOME"], let style = HouseStyle(rawValue: name) {
                    chosen = style
                }
                if environment["HOUSECAT_HOME_CONFIRM"] == "1" {
                    confirming = true
                }
            #endif
        }
        .onChange(of: chosen) { _, _ in
            if seasonPaintings == nil {
                shownSeason = nil
            }
        }
    }

    /// Landscape: the home and the roster on the left, what it is and Make it home down the right, the button's
    /// foot level with the roster's.
    private func sideBySide(_ s: CGFloat, in size: CGSize) -> some View {
        let column = (compact ? 250 : 300) * s, gap = 22 * s, between = (compact ? 10 : 18) * s
        let left = size.width - column - gap
        let rosterTall = rosterHeight(width: left, s)
        let heroHeight = min(left * 9 / 16, size.height - rosterTall - between)
        let height = compact ? size.height : min(size.height, heroHeight + between + rosterTall)
        return HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .leading, spacing: between) {
                hero(s)
                    .frame(width: heroHeight * 16 / 9, height: heroHeight)
                    .frame(maxWidth: .infinity)
                roster(s)
                    .frame(width: left, height: rosterTall)
            }
            .frame(width: left)
            VStack(alignment: .leading, spacing: (compact ? 8 : 16) * s) {
                titleRow(s)
                details(s)
                if !compact {
                    warning(s)
                }
                Spacer(minLength: 0)
                makeItHome(s)
            }
            .frame(width: column)
        }
        .frame(width: size.width, height: height)
    }

    /// Upright (an iPad held so): the home across the top, the roster, then what it is with Make it home beside it.
    private func stacked(_ s: CGFloat, in size: CGSize) -> some View {
        let heroHeight = min(size.width * 9 / 16, size.height * 0.4)
        return VStack(alignment: .leading, spacing: 16 * s) {
            titleRow(s)
            hero(s)
                .frame(width: heroHeight * 16 / 9, height: heroHeight)
                .frame(maxWidth: .infinity)
            roster(s)
                .frame(height: rosterHeight(width: size.width, s))
            HStack(alignment: .bottom, spacing: 24 * s) {
                VStack(alignment: .leading, spacing: 14 * s) {
                    details(s)
                    warning(s)
                }
                makeItHome(s)
                    .frame(width: 300 * s)
            }
        }
        .frame(width: size.width)
    }

    /// The roster's height across `width`: one row of named thumbnails on a phone, two rows of four on an iPad.
    private func rosterHeight(width: CGFloat, _ s: CGFloat) -> CGFloat {
        if compact {
            return 112 * 9 / 16 + 3 + 16 + 10
        }
        let thumb = (width - 3 * 12 * s) / 4
        return 2 * (thumb * 9 / 16 + 3 * s + 19 * s) + 10 * s
    }

    // MARK: The parts

    private func titleRow(_ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            if let cancel {
                HUDButton("Back", symbol: "chevron.left", action: cancel)
            }
            PaintedIcon("house", size: 34 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text("Which home?").font(Theme.title(25 * s))
                // Where it is, and the host's word on what the choice means.
                Text(GameWorld.content.map { "\(place) · \($0.intro.homes)" } ?? place)
                    .font(.system(size: 12.5 * s))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The chosen home, large: the arrows and a swipe go through the eight, the chips show it at another time of day
    /// (and season, when its paintings are in the app).
    private func hero(_ s: CGFloat) -> some View {
        heroPicture
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22 * s, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 3 * s))
            .shadow(color: .black.opacity(0.18), radius: 10 * s, y: 5 * s)
            .overlay(alignment: .bottomLeading) { skyChips(s).padding(10 * s) }
            .overlay(alignment: .topTrailing) {
                if let seasons = seasonPaintings {
                    seasonChips(seasons.map(\.0), s).padding(10 * s)
                }
            }
            .overlay(alignment: .leading) { arrow("chevron.left", by: -1, s).padding(.leading, 10 * s) }
            .overlay(alignment: .trailing) { arrow("chevron.right", by: 1, s).padding(.trailing, 10 * s) }
            .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
                if abs(drag.translation.width) > 50, abs(drag.translation.width) > abs(drag.translation.height) {
                    step(by: drag.translation.width < 0 ? 1 : -1)
                }
            })
            .animation(.easeInOut(duration: 0.25), value: chosen)
    }

    /// The full summer scene where the app has it (sharper drawn this large, above all on an iPad), else the preview.
    private var heroPicture: some View {
        let summer = HouseBuilder.scene(chosen, biome, .summer)
        let full = GameWorld.art.map { $0.has("\(summer).jpg") && $0.has("\(summer)_land.png") } ?? false
        return ZStack {
            if let shownSeason, let path = seasonPaintings?.first(where: { $0.0 == shownSeason })?.1 {
                Self.picture(path: path, sky: shownSky)
            } else if full {
                Self.picture(path: summer, sky: shownSky)
            } else {
                Self.painting(style: chosen, biome: biome, sky: shownSky)
            }
        }
        .id("\(chosen.rawValue).\(shownSky.rawValue).\(shownSeason?.rawValue ?? "")")
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chosen.name) in the \(Self.skyName(shownSky).lowercased())")
        .accessibilityAddTraits(.isImage)
    }

    private func arrow(_ symbol: String, by offset: Int, _ s: CGFloat) -> some View {
        Button {
            feedback.tap()
            step(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17 * s, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 40 * s, height: 40 * s)
                .background(Circle().fill(Theme.cream.opacity(0.92)))
                .shadow(color: .black.opacity(0.25), radius: 4 * s, y: 2 * s)
        }
        .buttonStyle(PressStyle())
        // Named for what they do (a chevron alone reads as "Back", which is the "Before you move in" card's button).
        .accessibilityLabel(offset < 0 ? "Show the home before" : "Show the home after")
    }

    private func step(by offset: Int) {
        let all = HouseStyle.allCases
        guard let index = all.firstIndex(of: chosen) else { return }
        withAnimation(.spring(duration: 0.3)) {
            chosen = all[(index + offset + all.count) % all.count]
        }
    }

    private func skyChips(_ s: CGFloat) -> some View {
        HStack(spacing: 5 * s) {
            ForEach(SkyPhase.allCases, id: \.self) { sky in
                chip(Self.skyName(sky), on: sky == shownSky, now: sky == now.sky, s) {
                    shownSky = sky
                }
            }
        }
    }

    private func seasonChips(_ seasons: [NatureSeason], _ s: CGFloat) -> some View {
        HStack(spacing: 5 * s) {
            ForEach(seasons, id: \.self) { season in
                chip(season.rawValue.capitalized, on: season == (shownSeason ?? .summer), now: season == now.season, s) {
                    shownSeason = season
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, now: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            feedback.tap()
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            HStack(spacing: 4 * s) {
                Text(title)
                if now {
                    Text("NOW")
                        .font(.system(size: 9 * s, weight: .black))
                        .padding(.horizontal, 4 * s)
                        .padding(.vertical, 1 * s)
                        .background(Capsule().fill(on ? .white.opacity(0.3) : Theme.accent))
                }
            }
            .font(.system(size: 12 * s, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9 * s)
            .padding(.vertical, 5 * s)
            .background(Capsule().fill(on ? Theme.accent : .black.opacity(0.42)))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The eight homes, named, the chosen one ringed: a row to scroll on a phone, two rows of four on an iPad.
    @ViewBuilder
    private func roster(_ s: CGFloat) -> some View {
        if compact {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HouseStyle.allCases) { style in
                            thumbnail(style, s).frame(width: 112).id(style)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 4)
                }
                .onChange(of: chosen) { _, style in
                    withAnimation { reader.scrollTo(style, anchor: .center) }
                }
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12 * s), count: 4), spacing: 10 * s) {
                ForEach(HouseStyle.allCases) { style in
                    thumbnail(style, s)
                }
            }
        }
    }

    private func thumbnail(_ style: HouseStyle, _ s: CGFloat) -> some View {
        let selected = style == chosen
        let corner = (compact ? 10 : 12) * s
        return Button {
            feedback.tap()
            withAnimation(.spring(duration: 0.3)) { chosen = style }
        } label: {
            VStack(spacing: 3 * s) {
                Self.painting(style: style, biome: biome, sky: .day)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : .white.opacity(0.6), lineWidth: (selected ? 3.5 : 1.5) * s))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10 * s, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 20 * s, height: 20 * s)
                                .background(Circle().fill(Theme.accent))
                                .padding(4 * s)
                        }
                    }
                Text(style.name)
                    .font(.system(size: (compact ? 11.5 : 13) * s, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(style.name)
        .accessibilityHint(style.blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the chosen home is: its kind, its name, its words, and its floors and rooms (from the home's plan).
    private func details(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            Text(chosen.kind.uppercased())
                .font(.system(size: 11.5 * s, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.accent)
            Text(chosen.name)
                .font(Theme.title((compact ? 27 : 30) * s))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(chosen.blurb)
                .font(.system(size: (compact ? 14.5 : 16) * s))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let plan = Self.plans[chosen] {
                HStack(spacing: 6 * s) {
                    fact("sofa_for_furniture", "\(plan.rooms) rooms", s)
                    fact("level_up_arrow", plan.floors == 1 ? "1 floor" : "\(plan.floors) floors", s)
                }
                .padding(.top, 3 * s)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chosen)
    }

    private func fact(_ icon: String, _ text: String, _ s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            PaintedIcon(icon, size: 18 * s)
            Text(text).font(.system(size: 12.5 * s, weight: .bold))
        }
        .padding(.leading, 5 * s)
        .padding(.trailing, 9 * s)
        .padding(.vertical, 3 * s)
        .background(Capsule().fill(Theme.cream))
        .overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 1))
    }

    /// The big button: the house, Make it home, and which home where.
    private func makeItHome(_ s: CGFloat) -> some View {
        let colour = Theme.accent
        let corner = 22 * s
        return Button {
            feedback.tap()
            // A phone confirms on the card; so does any home whose exteriors are a download, for the note on its size.
            if compact || HomePacks.needsDownload(chosen) {
                withAnimation(.spring(duration: 0.3)) { confirming = true }
            } else {
                done(chosen)
            }
        } label: {
            HStack(spacing: 10 * s) {
                PaintedIcon("house", size: 46 * s)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(confirmTitle)
                        .font(.system(size: 25 * s, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Your \(chosen.inSentence) in \(town)")
                        .font(.system(size: 12.5 * s, weight: .bold, design: .rounded))
                        .opacity(0.92)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20 * s, weight: .black))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 12 * s)
            .frame(maxWidth: .infinity, minHeight: (compact ? 70 : 84) * s)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(colour.mix(with: .black, by: 0.3)).offset(y: 5 * s)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [colour.mix(with: .white, by: 0.2), colour], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 2).padding(1.5)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(confirmTitle)
        .accessibilityHint("Your \(chosen.inSentence) in \(town)")
    }

    static func colour(_ rgb: [Double]?) -> Color {
        let c = rgb ?? [1, 1, 1]
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    /// A home's summer picture for a biome, its painted sky cut out and the game's own sky drawn behind it, the
    /// painting multiplied by the light of that time of day (`Tuning.Sky`), as the outside is drawn.
    static func painting(style: HouseStyle, biome: Biome, sky: SkyPhase) -> some View {
        picture(path: "world/previews/\(style.rawValue)_\(biome.rawValue)", sky: sky)
    }

    /// A painting and its land mask (`<path>.jpg`, `<path>_land.png`) under the sky of a time of day.
    static func picture(path: String, sky: SkyPhase) -> some View {
        ZStack {
            LinearGradient(colors: [colour(Tuning.Sky.top[sky]), colour(Tuning.Sky.bottom[sky])], startPoint: .top, endPoint: .bottom)
            if let picture = CatScreens.picture("\(path).jpg"), let land = CatScreens.picture("\(path)_land.png") {
                picture.resizable().interpolation(.high).scaledToFill()
                    .colorMultiply(colour(Tuning.Sky.grade[sky]))
                    .mask { land.resizable().scaledToFill().luminanceToAlpha() }
            }
        }
    }

    /// Each home's floors and rooms, from its plan (assets/rooms/houses.json).
    private static let plans: [HouseStyle: (rooms: Int, floors: Int)] = {
        guard let plans = try? GameWorld.art?.data("rooms/houses.json", as: HousePlans.self) else { return [:] }
        var found: [HouseStyle: (rooms: Int, floors: Int)] = [:]
        for style in HouseStyle.allCases {
            if let plan = plans.houses[style.rawValue] {
                found[style] = (plan.rooms.count, Set(plan.rooms.map(\.storey)).count)
            }
        }
        return found
    }()

    // MARK: The warning

    /// The season and the time of day where the home will be, now.
    private var now: (season: NatureSeason, sky: SkyPhase, time: String, fixed: Bool) {
        let session = GameSession.shared
        let date = session.now()
        let state = session.state(at: date)
        let place = home ?? state.home.place ?? .london
        let setting = season ?? state.home.season
        let zone = place.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        let season = setting.season(at: date, timeZone: zone, southernHemisphere: place.southernHemisphere)
        var fixed = false
        if case .fixed = setting {
            fixed = true
        }
        return (season, .at(localMinutes: (parts.hour ?? 12) * 60 + (parts.minute ?? 0)), time, fixed)
    }

    /// "Manchester" from "Manchester, England".
    private var town: String {
        WorldMapView.town(place)
    }

    private var nowLine: String {
        let now = now
        let arrival = switch now.sky {
        case .dawn: "you'll arrive early in the morning"
        case .day: "you'll arrive in daylight"
        case .dusk: "you'll arrive in the evening"
        case .night: "you'll arrive after dark"
        }
        if now.fixed {
            return "It's always \(now.season.rawValue) at your home (you chose that on the map), and \(now.time) in \(town) now: \(arrival)."
        }
        return "In \(town) it's \(now.season.rawValue), and \(now.time) now: \(arrival)."
    }

    /// The four seasons' paintings of the chosen home here, when they are in the app (the London terrace, or a home
    /// whose pack has arrived).
    private var seasonPaintings: [(NatureSeason, String)]? {
        let paths = NatureSeason.allCases.map { ($0, HouseBuilder.scene(chosen, biome, $0)) }
        guard let art = GameWorld.art, paths.allSatisfy({ art.has("\($0.1).jpg") && art.has("\($0.1)_land.png") }) else { return nil }
        return paths
    }

    /// Beside the home on an iPad: it looks different through the day and the year (the chips on the painting show
    /// how), and what it will be when you arrive.
    private func warning(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 6 * s) {
                PaintedIcon("weather_sun_and_cloud", size: 24 * s)
                Text("It changes with the real world").font(.system(size: 13.5 * s, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 6 * s)
            .padding(.trailing, 12 * s)
            .padding(.vertical, 3 * s)
            .background(Capsule().fill(Theme.accent))
            Text(
                "Its colours, its light and the garden follow \(town)'s real seasons, weather and time of day. Rainy days are grey, and nights are dark. Try the times on the picture."
            )
            .font(.system(size: 14 * s))
            .fixedSize(horizontal: false, vertical: true)
            Text(nowLine)
                .font(.system(size: 14 * s, weight: .semibold))
                .padding(10 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Theme.accent.opacity(0.12)))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeWarning")
    }

    private struct Tile: Identifiable {
        var id: String
        var label: String
        var now: Bool
        var picture: () -> AnyView
    }

    private func strip(_ title: String, tiles: [Tile], width: CGFloat = 196) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                ForEach(tiles) { tile in
                    tile.picture()
                        .frame(width: width, height: width * 0.57)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text(tile.label)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.8), radius: 3)
                                .padding(8)
                        }
                        .overlay(alignment: .topTrailing) {
                            if tile.now {
                                Text("NOW")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent))
                                    .padding(6)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                            Theme.accent,
                            lineWidth: tile.now ? 4 : 0
                        ))
                }
            }
        }
    }

    static func skyName(_ sky: SkyPhase) -> String {
        switch sky {
        case .dawn: "Morning"
        case .day: "Afternoon"
        case .dusk: "Evening"
        case .night: "Night"
        }
    }

    /// On a phone: the warning as a card when the home is confirmed, with Back to choose again.
    private var beforeYouMoveIn: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(duration: 0.3)) { confirming = false } }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PaintedIcon("weather_sun_and_cloud", size: 30)
                    Text("Before you move in").font(Theme.title(24))
                }
                Text(
                    "Your \(chosen.inSentence) is painted for \(place). Its colours, light and garden follow the real seasons, weather and time of day there."
                )
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
                // A home whose exteriors are a download says how big before it is asked for (App Review 4.2.3).
                if let note = HomePacks.downloadNote(for: chosen) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("downloadNote")
                }
                strip("Through the day", tiles: SkyPhase.allCases.map { sky in
                    Tile(id: sky.rawValue, label: Self.skyName(sky), now: sky == now.sky) {
                        AnyView(Self.painting(style: chosen, biome: biome, sky: sky))
                    }
                }, width: 150)
                HStack(spacing: 14) {
                    Text(nowLine)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.12)))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HUDButton("Back") {
                        withAnimation(.spring(duration: 0.3)) { confirming = false }
                    }
                    ChunkyButton(confirmTitle) { done(chosen) }
                        .accessibilityIdentifier("confirmHome")
                }
            }
            .padding(18)
            .frame(maxWidth: 700)
            .foregroundStyle(Theme.ink)
            .paper(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(16)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }
}

/// The house step's words for each home, beside its name and blurb.
private extension HouseStyle {
    /// What kind of home it is.
    var kind: String {
        switch self {
        case .londonTerrace: "Terraced house"
        case .mansionFlat: "Period flat"
        case .cottage: "Country cottage"
        case .georgianTownhouse: "Tall townhouse"
        case .newbuildBalcony: "Modern flat"
        case .houseboat: "Boat on the water"
        case .mediterraneanRooftop: "Top-floor flat"
        case .woodlandCabin: "Log cabin"
        }
    }

    /// Its name inside a sentence ("Your cottage in Leeds", "Your London terrace in Leeds").
    var inSentence: String {
        switch self {
        case .londonTerrace, .georgianTownhouse: name
        default: name.prefix(1).lowercased() + name.dropFirst()
        }
    }
}
