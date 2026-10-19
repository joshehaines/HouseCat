import HouseCatCore
import HouseCatGame
import HouseCatUI
import SwiftUI

/// Onboarding's house step (SPEC "The session loop": cat, geography, house, first arrival): the eight homes,
/// each painted where you pinned yours, a summer picture. The London terrace's exteriors are in the app; the
/// others arrive as a download (HomePacks), and until then the visit simply starts inside.
///
/// Josh, 19 Oct: "put a bigger warning when choosing a house, they should understand that the colours etc will be
/// different based on season etc." So the home you pick is shown at four times of day, and through the year when
/// its season paintings are in the app, with the season and the time there now: under the homes on an iPad, and as
/// a "Before you move in" card when you confirm on a phone, where the homes fill the screen.
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
    @Environment(\.controlFeedback) private var feedback
    @Environment(\.verticalSizeClass) private var verticalSize

    private var compact: Bool {
        verticalSize == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PaintedIcon("house", size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Which home?").font(Theme.title(30))
                    // Where it is, and the host's word on what the choice means.
                    Text(GameWorld.content.map { "\(place) · \($0.intro.homes)" } ?? place)
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if let cancel {
                    HUDButton("Back", symbol: "chevron.left", action: cancel)
                }
                HUDButton(confirmTitle, icon: "house", prominent: true) {
                    if compact {
                        withAnimation(.spring(duration: 0.3)) { confirming = true }
                    } else {
                        done(chosen)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(HouseStyle.allCases) { style in
                        card(style)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
            if !compact {
                warning
                    .padding(22)
                    .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .overlay {
            if confirming {
                beforeYouMoveIn
            }
        }
    }

    static func colour(_ rgb: [Double]?) -> Color {
        let c = rgb ?? [1, 1, 1]
        return Color(red: c[0], green: c[1], blue: c[2])
    }

    private func card(_ style: HouseStyle) -> some View {
        let selected = style == chosen
        return Button {
            feedback.tap()
            withAnimation(.spring(duration: 0.3)) { chosen = style }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Self.painting(style: style, biome: biome, sky: .day)
                    .frame(width: 300, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(style.name).font(Theme.title(19))
                Text(style.blurb).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(width: 320, alignment: .leading)
            .paper(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent, lineWidth: selected ? 4 : 0))
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    /// Side by side when there is room (an iPad on its side), else the words above the pictures (upright).
    private var warning: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 30) {
                warningWords.frame(width: 380)
                warningPictures
            }
            VStack(alignment: .leading, spacing: 18) {
                warningWords.frame(maxWidth: 820, alignment: .leading)
                warningPictures
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeWarning")
    }

    private var warningWords: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                PaintedIcon("weather_sun_and_cloud", size: 26)
                Text("It changes with the real world").font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent))
            Text("Your home will look different through the day and the year")
                .font(Theme.title(28))
                .fixedSize(horizontal: false, vertical: true)
            Text("Its colours, its light and the garden follow \(town)'s real seasons, weather and time of day. Rainy days are grey, and nights are dark.")
                .font(.system(size: 17))
                .fixedSize(horizontal: false, vertical: true)
            Text(nowLine)
                .font(.system(size: 16, weight: .semibold))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.12)))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var warningPictures: some View {
        VStack(alignment: .leading, spacing: 14) {
            strip("Through the day", tiles: SkyPhase.allCases.map { sky in
                Tile(id: sky.rawValue, label: Self.skyName(sky), now: sky == now.sky) {
                    AnyView(Self.painting(style: chosen, biome: biome, sky: sky))
                }
            })
            if let seasons = seasonPaintings {
                strip("Through the year", tiles: seasons.map { season, path in
                    Tile(id: season.rawValue, label: season.rawValue.capitalized, now: season == now.season) {
                        AnyView(Self.picture(path: path, sky: .day))
                    }
                })
            }
        }
        .fixedSize()
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
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent, lineWidth: tile.now ? 4 : 0))
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
                Text("Your \(chosen.name) is painted for \(place). Its colours, light and garden follow the real seasons, weather and time of day there.")
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
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
