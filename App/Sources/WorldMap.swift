import HouseCatCore
import HouseCatGame
import HouseCatUI
import MapKit
import Observation
import SwiftUI

/// The world map (SPEC "World map, search and seasons"): search for a town, pick one of a few cities, or spin the
/// painted globe and tap, which snaps to the nearest named place. The pin decides the biome (the painted mask, or
/// city near a listed city), the sky's local time and the hemisphere's season, which can also be fixed. No device
/// location is read.
@MainActor
@Observable
final class WorldMapModel: Identifiable {
    enum Mode {
        /// Onboarding: where you live, after the cat.
        case first
        /// Choosing a new place to move to (free once, then Beans), asked about before it happens.
        case move
        /// The world map from the menu (Josh, 19 Oct): your home with Move house, and from a level the other cats'
        /// homes to visit.
        case world
    }

    /// A suggestion as you type: a listed city (at once, and without a connection) or one of Apple Maps'.
    enum Suggestion: Identifiable, Hashable {
        case city(CitiesFile.City)
        case place(MKLocalSearchCompletion)

        var id: String {
            "\(title)|\(subtitle)"
        }

        var title: String {
            switch self {
            case let .city(city): city.name
            case let .place(completion): completion.title
            }
        }

        var subtitle: String {
            switch self {
            case let .city(city): city.country
            case let .place(completion): completion.subtitle
            }
        }
    }

    /// The globe goes to the pin each time it moves: arriving at `zoom`, or (nil) only coming in as far as
    /// `Tuning.World.globeTapZoom`, for a tap.
    struct Flight: Equatable {
        var count = 0
        var zoom: Double?
    }

    private(set) var mode: Mode
    /// Moving began on the world map, so cancelling it goes back there rather than closing the map.
    private(set) var movingFromWorld = false
    var pin: (latitude: Double, longitude: Double)?
    var placeName = ""
    var timeZone: TimeZone?
    var biome: Biome?
    var season: SeasonSetting
    var query = "" {
        didSet {
            search.query(query)
        }
    }

    /// What is being found while the pin waits for it ("Manchester", "the nearest town").
    private(set) var finding: String?
    /// The pin is named but its time zone is still on its way.
    private(set) var settling = false
    /// Why the last search came to nothing, until the next choice.
    private(set) var problem: String?
    private(set) var flight = Flight()
    /// When the pin last moved: it drops in.
    private(set) var placed = Date.distantPast
    let search = PlaceSearch()
    /// The cities to pick from without searching: the player's own country's first.
    let suggestions: [CitiesFile.City]
    @ObservationIgnored private let mask: Raster?
    @ObservationIgnored let cities: CitiesFile?
    /// The home as it is (before any move), and its look.
    let home: HomePlace?
    @ObservationIgnored private(set) var homeSeason: SeasonSetting
    let homeStyle: HouseStyle
    /// Other cats' homes (the intro's tour), the one tapped, the level they open at and the player's, and the
    /// ones visited.
    let homes: [IntroFile.Stop]
    var selectedHome: IntroFile.Stop?
    let unlockLevel: Int
    let level: Int
    let xpToUnlock: Int
    var visited: Set<String>
    /// Each choice asks Apple Maps afresh; an answer to an older one is dropped.
    @ObservationIgnored private var asking = 0

    init(mode: Mode, current: HouseholdState) {
        self.mode = mode
        season = current.home.season
        homeSeason = current.home.season
        // A save that never pinned its home is in London, as the game shows it.
        home = current.home.place ?? (mode == .first ? nil : .london)
        homeStyle = GameWorld.style(current)
        homes = GameWorld.content?.intro.stops ?? []
        unlockLevel = Tuning.Goals.homesLevel
        level = current.level
        xpToUnlock = max(0, LevelCurve.threshold(for: Tuning.Goals.homesLevel) - current.xp)
        // A visit is saved as the screen "home.<id>" seen (`GameSession.saw`), once each.
        visited = Set(current.lifetime.screensSeen.filter { $0.hasPrefix("home.") }.map { String($0.dropFirst("home.".count)) })
        let root = Bundle.main.url(forResource: "Art", withExtension: nil)
        mask = root.flatMap { Raster.read($0.appendingPathComponent("world/map/map_biome.png")) }
        cities = root.flatMap { try? JSONDecoder().decode(
            CitiesFile.self,
            from: Data(contentsOf: $0.appendingPathComponent("world/map/cities.json"))
        ) }
        // The country the phone is set to (its region setting, not where it is), by its English name as the list
        // has it.
        let country = Locale.current.region.flatMap { Locale(identifier: "en_GB").localizedString(forRegionCode: $0.identifier) }
        suggestions = cities?.suggestions(country: country) ?? []
        if let place = home {
            pin = (place.latitude, place.longitude)
            placeName = place.name
            timeZone = place.timeZone
            biome = place.biome
        }
    }

    var resolving: Bool {
        finding != nil || settling
    }

    /// Other cats' homes can be visited.
    var unlocked: Bool {
        level >= unlockLevel
    }

    /// The world map's Move house: the same map, now choosing a new place.
    func startMove() {
        selectedHome = nil
        movingFromWorld = mode == .world
        mode = .move
    }

    /// Back to the world map, the pin home again.
    func cancelMove() {
        _ = begin()
        mode = .world
        movingFromWorld = false
        if let home {
            put(latitude: home.latitude, longitude: home.longitude, name: home.name, zoom: nil)
            timeZone = home.timeZone
            biome = home.biome
        }
        season = homeSeason
    }

    /// The season set on the world map is the home's at once (no move).
    func seasonSaved() {
        homeSeason = season
    }

    func select(_ id: String) {
        selectedHome = homes.first { $0.id == id }
    }

    /// Something to confirm: a move needs a new place (the season alone is changed on the world map's home card,
    /// at once and free).
    var changed: Bool {
        guard mode == .move, let home else { return true }
        guard let pin else { return false }
        return abs(pin.latitude - home.latitude) > 1e-6 || abs(pin.longitude - home.longitude) > 1e-6
    }

    /// What the search box suggests: Apple Maps' towns once it answers, the listed cities until then (or when it
    /// cannot be reached).
    var matches: [Suggestion] {
        if !search.results.isEmpty {
            return search.results.map(Suggestion.place)
        }
        return (cities?.matching(query, limit: 4) ?? []).map(Suggestion.city)
    }

    func isPinned(at city: CitiesFile.City) -> Bool {
        guard let pin else { return false }
        return abs(pin.latitude - city.latitude) < 1e-6 && abs(pin.longitude - city.longitude) < 1e-6
    }

    /// The biome under a coordinate: city near a listed city, else the painted mask.
    func biome(latitude: Double, longitude: Double) -> Biome {
        let inCity = cities?.city(near: latitude, longitude) != nil
        guard let mask, let plane = mask.planes.first else { return BiomeRules.biome(maskIndex: 2, inCity: inCity) }
        let p = WorldMap.point(latitude: latitude, longitude: longitude, width: Double(mask.width), height: Double(mask.height))
        let x = min(mask.width - 1, max(0, Int(p.x))), y = min(mask.height - 1, max(0, Int(p.y)))
        return BiomeRules.biome(maskIndex: Int(plane[y * mask.width + x]), inCity: inCity)
    }

    func choose(_ suggestion: Suggestion) {
        switch suggestion {
        case let .city(city): pick(city)
        case let .place(completion): choose(completion)
        }
    }

    /// A listed city (from the short list, the search or a tap): the pin goes there at once, and Apple Maps is asked
    /// only for its time zone. `zoom` as for `Flight`.
    func pick(_ city: CitiesFile.City, zoom: Double? = Tuning.World.globeSearchZoom) {
        let mine = begin()
        put(latitude: city.latitude, longitude: city.longitude, name: "\(city.name), \(city.country)", zoom: zoom)
        settling = true
        Task {
            let zone = await PlaceSearch.timeZone(latitude: city.latitude, longitude: city.longitude)
            guard asking == mine else { return }
            timeZone = zone ?? timeZone
            settling = false
        }
        giveUp(on: mine)
    }

    /// A tap on the globe snaps to a named place: the city whose name it was on, or a listed city close by; else
    /// the pin goes down where the finger was while Apple Maps finds the town there, and then moves onto it. Out
    /// at sea, the nearest listed city within `globeSeaSnapKm` (the coast was missed), else the sea's own name.
    func drop(_ tap: GlobeTap) {
        let near = min(tap.reachKm, Tuning.World.globeSnapKm)
        if let city = tap.city ?? cities?.nearest(to: tap.latitude, tap.longitude, within: near) {
            pick(city, zoom: nil)
            return
        }
        let mine = begin()
        put(latitude: tap.latitude, longitude: tap.longitude, name: Self.coordinateName(tap.latitude, tap.longitude), zoom: nil)
        finding = "the nearest town"
        Task {
            let found = await PlaceSearch.town(near: tap.latitude, tap.longitude, within: max(tap.reachKm, 25))
            guard asking == mine else { return }
            finding = nil
            if let found, found.town {
                if found.latitude != tap.latitude || found.longitude != tap.longitude {
                    put(latitude: found.latitude, longitude: found.longitude, name: found.name, zoom: nil)
                }
                placeName = found.name
                timeZone = found.timeZone ?? timeZone
            } else if let city = cities?.nearest(to: tap.latitude, tap.longitude, within: max(tap.reachKm, Tuning.World.globeSeaSnapKm)) {
                pick(city, zoom: nil)
            } else if let found {
                placeName = found.name
                timeZone = found.timeZone ?? timeZone
            }
        }
        giveUp(on: mine)
    }

    /// One of Apple Maps' suggestions chosen: found, then the pin goes there.
    func choose(_ completion: MKLocalSearchCompletion) {
        let mine = begin()
        finding = completion.title
        Task {
            let found = await PlaceSearch.resolve(completion)
            guard asking == mine else { return }
            finding = nil
            guard let found else {
                problem = "Apple Maps couldn't find \(completion.title) just now."
                return
            }
            put(latitude: found.latitude, longitude: found.longitude, name: found.name, zoom: Tuning.World.globeSearchZoom)
            timeZone = found.timeZone ?? timeZone
        }
        giveUp(on: mine, saying: "Apple Maps can't be reached just now. Pick a city, or tap the globe.")
    }

    /// A new choice: the last one's question to Apple Maps is forgotten, and the search box cleared.
    private func begin() -> Int {
        asking += 1
        finding = nil
        settling = false
        problem = nil
        query = ""
        return asking
    }

    /// Offline, Apple Maps may not answer: after a few seconds the pin keeps the name it has and the time zone
    /// from its longitude, and can be confirmed.
    private func giveUp(on mine: Int, saying problem: String? = nil) {
        Task {
            try? await Task.sleep(for: .seconds(Tuning.World.mapsPatience))
            guard asking == mine, resolving else { return }
            if finding != nil, let problem {
                self.problem = problem
            }
            finding = nil
            settling = false
        }
    }

    private func put(latitude: Double, longitude: Double, name: String, zoom: Double?) {
        pin = (latitude, longitude)
        biome = biome(latitude: latitude, longitude: longitude)
        placeName = name
        timeZone = TimeZone(secondsFromGMT: HomePlace.roughOffset(longitude: longitude))
        problem = nil
        placed = Date()
        flight = Flight(count: flight.count + 1, zoom: zoom)
    }

    /// The pin as a home place.
    var place: HomePlace? {
        guard let pin, let biome else { return nil }
        let zone = timeZone ?? TimeZone(secondsFromGMT: HomePlace.roughOffset(longitude: pin.longitude)) ?? .gmt
        return HomePlace(name: placeName, latitude: pin.latitude, longitude: pin.longitude, timeZoneID: zone.identifier, biome: biome)
    }

    static func coordinateName(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.1f°%@, %.1f°%@", abs(latitude), latitude >= 0 ? "N" : "S", abs(longitude), longitude >= 0 ? "E" : "W")
    }

    /// The time at the pin now ("14:05").
    var localTime: String? {
        guard let timeZone else { return nil }
        let format = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        return Date().formatted(format)
    }
}

/// MapKit's place search (SPEC: "MapKit local search resolves it"): towns and postcodes suggested as you type, a
/// chosen one resolved to coordinates, and a tapped coordinate named after its town.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    /// Apple Maps has answered the text as it is now (with nothing, perhaps).
    private(set) var answered = false
    /// Apple Maps could not be reached.
    private(set) var failed = false
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// False once the text is cleared, so a late answer to what was typed cannot bring the list back.
    @ObservationIgnored private var active = false

    override init() {
        super.init()
        completer.delegate = self
        // Towns, districts and postcodes: where a home is, not a shop, a station or a street address.
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: [.locality, .subLocality, .subAdministrativeArea, .postalCode])
    }

    func query(_ text: String) {
        answered = false
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            active = false
            completer.cancel()
            results = []
        } else {
            active = true
            completer.queryFragment = text
        }
    }

    /// MapKit calls back on the main thread.
    nonisolated func completerDidUpdateResults(_: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            guard active else { return }
            failed = false
            answered = true
            results = Array(completer.results.prefix(6))
        }
    }

    nonisolated func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        MainActor.assumeIsolated {
            guard active else { return }
            failed = true
            answered = true
            results = []
        }
    }

    struct Found: Sendable {
        var name: String
        var latitude: Double
        var longitude: Double
        var timeZone: TimeZone?
        /// Named after a town (not the sea or a region).
        var town = true
    }

    static func resolve(_ completion: MKLocalSearchCompletion) async -> Found? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        // "Manchester, England"; a postcode is named after its town, not kept as the home's name.
        var label = completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle.split(separator: ",").first.map(String.init) ?? "")"
        if completion.title.contains(where: \.isNumber), let town = item.addressRepresentations?.cityWithContext, !town.isEmpty {
            label = town
        }
        return Found(name: label, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: item.timeZone)
    }

    /// The town nearest a coordinate, as Apple Maps names it ("Truro, England"), and where it is: its own middle
    /// when that is within `km`, else the coordinate. Off any town (the sea, the desert), whatever Maps calls the
    /// place; nil when it has no name for it.
    static func town(near latitude: Double, _ longitude: Double, within km: Double) async -> Found? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
              let item = try? await request.mapItems.first else { return nil }
        let places = item.addressRepresentations
        guard let town = [places?.cityWithContext, places?.cityName].compactMap(\.self).first(where: { !$0.isEmpty }) else {
            let name = tidy([item.name, places?.regionName])
            return name.isEmpty ? nil : Found(name: name, latitude: latitude, longitude: longitude, timeZone: item.timeZone, town: false)
        }
        var at = (latitude: latitude, longitude: longitude)
        if let ask = MKGeocodingRequest(addressString: town) {
            ask.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                latitudinalMeters: km * 4000,
                longitudinalMeters: km * 4000
            )
            if let middle = try? await ask.mapItems.first?.location.coordinate,
               WorldMap.distance(at, (middle.latitude, middle.longitude)) <= km
            {
                at = (middle.latitude, middle.longitude)
            }
        }
        return Found(name: town, latitude: at.latitude, longitude: at.longitude, timeZone: item.timeZone)
    }

    /// A coordinate's time zone, as Apple Maps has it.
    static func timeZone(latitude: Double, longitude: Double) async -> TimeZone? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else { return nil }
        return try? await request.mapItems.first?.timeZone
    }

    /// "Djado" and "Djado, Niger" read as "Djado, Niger", not "Djado, Djado, Niger"; bare numbers (a postcode,
    /// or the coordinates Maps gives a spot at sea) are left out.
    private static func tidy(_ names: [String?]) -> String {
        var parts: [String] = []
        let pieces = names.compactMap(\.self).flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains(where: \.isLetter) }
        for part in pieces where !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            parts.append(part)
        }
        return parts.joined(separator: ", ")
    }
}

/// The map screen: the world as a globe to spin, the search above it, a few cities to pick and the place you chose
/// below, with the button that confirms it.
struct WorldMapView: View {
    @Bindable var model: WorldMapModel
    /// What a move costs (0: free), shown on the button.
    let cost: Int
    let canAfford: Bool
    let cancel: (() -> Void)?
    /// The world map: the home's season changed on its card (saved at once; it is not a move).
    var seasonChanged: ((SeasonSetting) -> Void)?
    /// The world map: one of the other cats' homes visited.
    var onVisit: ((String) -> Void)?
    /// The place chosen and confirmed, its season, and (moving) a different home for it.
    let done: (HomePlace, SeasonSetting, HouseStyle?) -> Void

    @State private var camera = GlobeCamera()
    @FocusState private var searching: Bool
    /// The finger now on the globe closed the keyboard: its tap drops no pin.
    @State private var closedKeyboard = false
    /// Moving: the "Move to …?" card, the home chosen on it, and the homes to choose from.
    @State private var confirmingMove = false
    @State private var newStyle: HouseStyle?
    @State private var choosingStyle = false
    @State private var visiting: Visiting?
    @Environment(\.verticalSizeClass) private var verticalSize

    private struct Visiting: Identifiable {
        var stop: IntroFile.Stop
        var id: String {
            stop.id
        }
    }

    private var compact: Bool {
        verticalSize == .compact
    }

    var body: some View {
        ZStack(alignment: .top) {
            SpinningGlobe(
                camera: camera,
                markers: markers,
                cities: model.cities?.cities ?? [],
                lift: 0.04,
                onTouch: {
                    // A finger on the globe: it stops turning by itself, and the keyboard goes.
                    closedKeyboard = searching
                    searching = false
                    camera.spins = false
                },
                onTap: { tap in
                    if model.mode == .world {
                        withAnimation(.spring(duration: 0.3)) { model.selectedHome = nil }
                    } else if !closedKeyboard {
                        model.drop(tap)
                    }
                },
                onMarker: model.mode == .world ? { id in choose(home: id) } : nil
            )
            VStack(spacing: 10) {
                header
                if model.mode == .world, !model.unlocked, !model.homes.isEmpty {
                    lockBanner
                }
                Spacer(minLength: 0)
                if model.mode == .world {
                    if let stop = model.selectedHome {
                        homeCard(stop)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    yourHome
                } else {
                    if !searching {
                        picks
                    }
                    card
                }
            }
            .padding(16)
            // Exactly the height there is, the search at the top: on a landscape phone the suggestions and the card
            // are taller than the space above the keyboard, and the whole screen was moved 53 points to fit them,
            // leaving a white band over the globe.
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            if confirmingMove {
                moveConfirm
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        // The keyboard covers the card while you type; nothing moves.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.spring(duration: 0.3), value: model.mode)
        .onChange(of: model.flight) { _, flight in fly(flight) }
        .onChange(of: model.season) { _, season in
            if model.mode == .world {
                seasonChanged?(season)
                model.seasonSaved()
            }
        }
        .onAppear {
            // Moving home or the world map: start over the home you have.
            if let pin = model.pin {
                camera.spins = false
                let zoom = model.mode == .world ? Tuning.World.globeWorldZoom : Tuning.World.globeSearchZoom * 0.8
                camera.fly(to: pin.latitude, pin.longitude, zoom: zoom, seconds: 0.01)
            }
        }
        .fullScreenCover(item: $visiting) { visit in
            HomeVisitView(stop: visit.stop, visited: model.visited.count, total: model.homes.count) { visiting = nil }
        }
        .fullScreenCover(isPresented: $choosingStyle) {
            if let place = model.place {
                HomePicker(
                    biome: place.biome,
                    place: place.name,
                    home: place,
                    season: model.season,
                    confirmTitle: "Choose this home",
                    cancel: { choosingStyle = false }
                ) { style in
                    newStyle = style
                    choosingStyle = false
                }
                .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            }
        }
    }

    private var markers: [GlobeMarker] {
        var markers: [GlobeMarker] = []
        if model.mode == .world {
            markers = model.homes.map { stop in
                GlobeMarker(
                    id: stop.id,
                    latitude: stop.latitude,
                    longitude: stop.longitude,
                    title: stop.cat.name,
                    kind: .home(icon: "house"),
                    highlighted: model.selectedHome?.id == stop.id,
                    badge: !model.unlocked ? .locked : model.visited.contains(stop.id) ? .visited : nil
                )
            }
        }
        if let pin = model.pin {
            markers.append(GlobeMarker(id: "pin", latitude: pin.latitude, longitude: pin.longitude, kind: .pin, placed: model.placed))
        }
        return markers
    }

    /// The globe turns the pin to the middle: in close after a search or a pick, only a little after a tap.
    private func fly(_ flight: WorldMapModel.Flight) {
        guard let pin = model.pin else { return }
        camera.spins = false
        if let zoom = flight.zoom {
            camera.fly(to: pin.latitude, pin.longitude, zoom: zoom)
        } else {
            let zoom = max(camera.pose(at: Date()).zoom, Tuning.World.globeTapZoom)
            camera.fly(to: pin.latitude, pin.longitude, zoom: zoom, seconds: Tuning.World.globeTapFlightSeconds)
        }
    }

    /// A home tapped on the world map: its card comes up and the globe turns it to the middle.
    private func choose(home id: String) {
        withAnimation(.spring(duration: 0.3)) { model.select(id) }
        guard let stop = model.selectedHome else { return }
        let zoom = max(camera.pose(at: Date()).zoom, Tuning.World.globeWorldZoom)
        camera.fly(to: stop.latitude, stop.longitude, zoom: zoom, seconds: Tuning.World.globeTapFlightSeconds)
    }

    // MARK: The world map

    private var lockBanner: some View {
        HStack(spacing: 10) {
            PaintedIcon("padlock", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Other cats' homes open at level \(model.unlockLevel)").font(Theme.title(19))
                Text("You're level \(model.level): \(model.xpToUnlock) XP to go")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One of the other cats' homes: whose, where, its season, weather and time, and Visit.
    private func homeCard(_ stop: IntroFile.Stop) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stop.cat.name)'s \(Self.homeWord(stop.home))").font(Theme.title(22)).lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(stop.place), \(stop.country)", systemImage: "mappin.and.ellipse")
                    Label(Self.weatherName(stop.weather), systemImage: Self.weatherIcon(stop.weather))
                    if let zone = TimeZone(identifier: stop.timeZone) {
                        Label(
                            "\(Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) there",
                            systemImage: "clock"
                        )
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.unlocked {
                ChunkyButton("Visit") {
                    model.visited.insert(stop.id)
                    onVisit?(stop.id)
                    visiting = Visiting(stop: stop)
                }
            } else {
                HStack(spacing: 6) {
                    PaintedIcon("padlock", size: 26)
                    Text("Opens at level \(model.unlockLevel)").font(.system(size: 16, weight: .semibold))
                }
            }
            Button {
                withAnimation(.spring(duration: 0.3)) { model.selectedHome = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "cabin" from "A cabin".
    static func homeWord(_ home: String) -> String {
        home.replacingOccurrences(of: "^(A|An) ", with: "", options: .regularExpression)
    }

    /// The home you have: where, which home, the time there, its season (changed here at once), and Move house.
    private var yourHome: some View {
        HStack(spacing: 14) {
            PaintedIcon("house", size: 30)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.cream))
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR HOME").font(.system(size: 12, weight: .heavy)).tracking(0.6).foregroundStyle(Theme.inkSoft)
                Text(model.home?.name ?? model.placeName).font(Theme.title(22)).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("homeName")
                HStack(spacing: 10) {
                    Text(model.homeStyle.name)
                    if let time = model.localTime {
                        Label("\(time) there", systemImage: "clock")
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            seasonMenu
            ChunkyButton("Move house") {
                withAnimation(.spring(duration: 0.3)) { model.startMove() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: The search

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // On a landscape phone the title makes room for the suggestions above the keyboard.
                if !(searching && compact) {
                    HStack(spacing: 6) {
                        PaintedIcon("map_pin", size: 30)
                        Text(title)
                            .font(Theme.title(22))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 4)
                    .paper(Capsule())
                }
                if model.mode == .world {
                    if model.unlocked, !model.homes.isEmpty {
                        HStack(spacing: 6) {
                            PaintedIcon("house", size: 26)
                            Text("Homes visited: \(model.visited.count) of \(model.homes.count)")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 16)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.ink)
                        .paper(Capsule())
                    }
                } else {
                    searchField
                    if searching, !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestions
                    }
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
            Spacer(minLength: 0)
            if model.movingFromWorld {
                // Back to the world map, the home where it was.
                HUDButton("Back", symbol: "chevron.left") {
                    searching = false
                    withAnimation(.spring(duration: 0.3)) { model.cancelMove() }
                }
            } else if let cancel {
                CloseButton(action: cancel)
            }
        }
    }

    private var title: String {
        switch model.mode {
        case .first: "Where do you live?"
        case .move: "Move home"
        case .world: "The world"
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            TextField("Search for your town or postcode", text: $model.query)
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($searching)
                .submitLabel(.search)
                .onSubmit {
                    if let first = model.matches.first {
                        model.choose(first)
                    }
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 50)
        .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Suggestions as you type, two lines each and a finger high; a tap flies there and pins it.
    private var suggestions: some View {
        let rows = Array(model.matches.prefix(compact ? 3 : 5))
        return VStack(spacing: 0) {
            if rows.isEmpty {
                Text(model.search.failed ? "Apple Maps can't be reached just now." : model.search.answered ? "No town found by that name." : "Looking…")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                Button {
                    searching = false
                    model.choose(row)
                } label: {
                    HStack(spacing: 12) {
                        PaintedIcon("map_pin", size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            if !row.subtitle.isEmpty {
                                Text(row.subtitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: compact ? 48 : 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.subtitle.isEmpty ? row.title : "\(row.title), \(row.subtitle)")
            }
        }
        .paper(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: The cities to pick, and the card

    /// For someone who would rather not search: a few cities, the player's own country's first.
    private var picks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Or pick:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .padding(.trailing, 2)
                ForEach(model.suggestions, id: \.self) { city in
                    let chosen = model.isPinned(at: city)
                    Button {
                        model.pick(city)
                    } label: {
                        Text(city.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(chosen ? Color.white : Theme.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .paper(Capsule(), fill: chosen ? Theme.accent : Theme.cream)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                summary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            seasonMenu
            let ready = model.place != nil && !model.resolving && canAfford && model.changed
            ChunkyButton(model.mode == .first ? "Live here" : "Move here", subtitle: cost > 0 ? "\(cost) Beans" : nil) {
                guard let place = model.place else { return }
                if model.mode == .move {
                    // Moving is asked about first: what comes, what changes, what it costs.
                    newStyle = nil
                    withAnimation(.spring(duration: 0.3)) { confirmingMove = true }
                } else {
                    done(place, model.season, nil)
                }
            }
            .disabled(!ready)
            .opacity(ready ? 1 : 0.45)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: $model.season) {
                Text("Auto (the real season there)").tag(SeasonSetting.auto)
                ForEach(NatureSeason.allCases, id: \.self) { season in
                    Text("Always \(season.rawValue)").tag(SeasonSetting.fixed(season))
                }
            }
        } label: {
            HStack(spacing: 4) {
                PaintedIcon("weather_sun_and_cloud", size: 26)
                Text(seasonTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(minHeight: 44)
            .paper(Capsule())
        }
    }

    // MARK: Moving

    /// "Move to Lyon?": what comes with you, what changes (the outside, its weather, seasons and time), the cost.
    private var moveConfirm: some View {
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let from = Self.town(model.home?.name ?? "")
        let to = Self.town(model.placeName)
        let style = newStyle ?? model.homeStyle
        let zone = model.timeZone ?? .gmt
        let southern = (model.pin?.latitude ?? 0) < 0
        let seasonThere = model.season.season(at: Date(), timeZone: zone, southernHemisphere: southern)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: Date())
        let sky = SkyPhase.at(localMinutes: (parts.hour ?? 12) * 60 + (parts.minute ?? 0))
        let firstMove = state.lifetime.homeMoves < Tuning.Beans.freeHomeMoves
        let costLine = cost == 0 ? (firstMove ? "Free: your first move" : "Free today with Cat Club") : "Moving costs \(cost) Beans"
        return ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(duration: 0.3)) { confirmingMove = false } }
            VStack(alignment: .leading, spacing: compact ? 8 : 14) {
                HStack(spacing: 8) {
                    PaintedIcon("house", size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Move to \(to)?").font(Theme.title(compact ? 24 : 30))
                        if !from.isEmpty {
                            Text("From \(model.home?.name ?? from)").font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                        heading("Coming with you")
                        item("cat_face", "\(session.cat?.name ?? "Your cat"),", "of course")
                        item("sofa_for_furniture", "Every room", "and all \(state.placed.count) pieces, just where you put them")
                        item("bean_coin", "Your \(state.beans.formatted()) Beans", "")
                        if !compact {
                            item("collection_book", "Your book,", "outfits and season pass")
                        }
                        item("streak_paw_print_with_a_small_flame", "Your \(state.streak.current)-day streak", "and level \(state.level)")
                    }
                    .padding(compact ? 10 : 14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
                    VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                        heading("What changes")
                        HStack(alignment: .center, spacing: 10) {
                            HomePicker.painting(style: style, biome: model.biome ?? .city, sky: sky)
                                .frame(width: compact ? 110 : 150, height: compact ? 62 : 85)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Text("The outside:").bold()) your \(style.name), painted for \(to)")
                                    .font(.system(size: 16))
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Choose another home") { choosingStyle = true }
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        item("weather_sun_and_cloud", "Weather and seasons:", "\(to)'s. \(seasonThere.rawValue.capitalized) there now")
                        item("clock", "Time of day:", "\(to)'s sky. \(model.localTime ?? "") there")
                    }
                    .padding(compact ? 10 : 14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
                }
                HStack(spacing: 12) {
                    PaintedIcon("bean_coin", size: 24)
                    Text(costLine).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 8)
                    HUDButton(from.isEmpty ? "Not yet" : "Stay in \(from)") {
                        withAnimation(.spring(duration: 0.3)) { confirmingMove = false }
                    }
                    ChunkyButton("Move to \(to)", subtitle: cost > 0 ? "\(cost) Beans" : nil) {
                        if let place = model.place {
                            confirmingMove = false
                            done(place, model.season, newStyle == model.homeStyle ? nil : newStyle)
                        }
                    }
                }
            }
            .padding(compact ? 14 : 24)
            .frame(maxWidth: 880)
            .foregroundStyle(Theme.ink)
            .paper(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(compact ? 8 : 24)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(0.7).foregroundStyle(Theme.inkSoft)
    }

    private func item(_ icon: String, _ bold: String, _ rest: String) -> some View {
        HStack(spacing: 10) {
            PaintedIcon(icon, size: compact ? 26 : 32)
            Text("\(Text(bold).bold())\(rest.isEmpty ? "" : " \(rest)")")
                .font(.system(size: compact ? 14 : 16))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Lyon" from "Lyon, France", and "Haqil" from an older save's "49944, Haqil, Saudi Arabia".
    static func town(_ name: String) -> String {
        let parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first { $0.contains(where: \.isLetter) } ?? parts.first ?? name
    }

    @ViewBuilder private var summary: some View {
        if let finding = model.finding {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding \(finding)…").font(Theme.title(21)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Apple Maps is looking.").font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
        } else if model.pin == nil {
            Text("Search, pick a city or tap the globe.").font(Theme.title(21)).lineLimit(2).minimumScaleFactor(0.7)
            Text(model.problem ?? "Tap near a city's name to choose it.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
        } else {
            HStack(spacing: 8) {
                Text(model.placeName).font(Theme.title(22)).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("placeName")
                if model.settling {
                    ProgressView().controlSize(.small)
                }
            }
            if let problem = model.problem {
                Text(problem).font(.system(size: 15)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            } else if !canAfford {
                Text("Moving costs \(cost) Beans.").font(.system(size: 15)).foregroundStyle(Theme.inkSoft)
            } else {
                HStack(spacing: 12) {
                    if let biome = model.biome {
                        Label(Self.biomeName(biome), systemImage: Self.biomeIcon(biome))
                    }
                    if let time = model.localTime {
                        Label("\(time) there", systemImage: "clock")
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            }
        }
    }

    private var seasonTitle: String {
        switch model.season {
        case .auto: "Season: Auto"
        case let .fixed(season): "Always \(season.rawValue)"
        }
    }

    static func biomeName(_ biome: Biome) -> String {
        switch biome {
        case .city: "City"
        case .coast: "Coast"
        case .countryside: "Countryside"
        case .mountain: "Mountains"
        case .forest: "Forest"
        case .desert: "Desert"
        case .tropical: "Tropical"
        case .snow: "Snow"
        }
    }

    static func weatherName(_ weather: Weather) -> String {
        switch weather {
        case .sun: "Sunny"
        case .cloud: "Cloudy"
        case .rain: "Raining"
        case .storm: "Stormy"
        case .snow: "Snowing"
        case .fog: "Foggy"
        case .wind: "Windy"
        case .heat: "Hot"
        }
    }

    static func weatherIcon(_ weather: Weather) -> String {
        switch weather {
        case .sun: "sun.max"
        case .cloud: "cloud"
        case .rain: "cloud.rain"
        case .storm: "cloud.bolt.rain"
        case .snow: "snowflake"
        case .fog: "cloud.fog"
        case .wind: "wind"
        case .heat: "thermometer.sun"
        }
    }

    static func biomeIcon(_ biome: Biome) -> String {
        switch biome {
        case .city: "building.2"
        case .coast: "water.waves"
        case .countryside: "leaf"
        case .mountain: "mountain.2"
        case .forest: "tree"
        case .desert: "sun.max"
        case .tropical: "beach.umbrella"
        case .snow: "snowflake"
        }
    }
}

extension CatScreens {
    /// The home in a line for the profile: "Manchester · London terrace" (London until a home is pinned).
    static func homeLine() -> String {
        let session = GameSession.shared
        let state = session.state(at: session.now())
        let place = state.home.place ?? .london
        return "\(WorldMapView.town(place.name)) · \(GameWorld.style(state).name)"
    }
}
