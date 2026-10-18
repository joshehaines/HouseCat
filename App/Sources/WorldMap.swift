import HouseCatCore
import HouseCatGame
import HouseCatUI
import MapKit
import Observation
import SwiftUI

/// The world map (SPEC "World map, search and seasons"): search for any place or tap the painted map to drop
/// the pin; the pin decides the biome (the painted mask, or city near a listed city), the sky's local time and
/// the hemisphere's season, which can also be fixed. No device location is read.
@MainActor
@Observable
final class WorldMapModel: Identifiable {
    enum Mode {
        /// Onboarding: where you live, after the cat.
        case first
        /// Moving home later (free once, then Beans).
        case move
    }

    let mode: Mode
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

    private(set) var resolving = false
    /// Counts places chosen from the search, so the map can fly to each.
    private(set) var searchedTo = 0
    let search = PlaceSearch()
    @ObservationIgnored private let mask: Raster?
    @ObservationIgnored let cities: CitiesFile?

    init(mode: Mode, current: HouseholdState) {
        self.mode = mode
        season = current.home.season
        let root = Bundle.main.url(forResource: "Art", withExtension: nil)
        mask = root.flatMap { Raster.read($0.appendingPathComponent("world/map/map_biome.png")) }
        cities = root.flatMap { try? JSONDecoder().decode(
            CitiesFile.self,
            from: Data(contentsOf: $0.appendingPathComponent("world/map/cities.json"))
        ) }
        if let place = current.home.place {
            pin = (place.latitude, place.longitude)
            placeName = place.name
            timeZone = place.timeZone
            biome = place.biome
        }
    }

    /// The biome under a coordinate: city near a listed city, else the painted mask.
    func biome(latitude: Double, longitude: Double) -> Biome {
        let inCity = cities?.city(near: latitude, longitude) != nil
        guard let mask, let plane = mask.planes.first else { return BiomeRules.biome(maskIndex: 2, inCity: inCity) }
        let p = WorldMap.point(latitude: latitude, longitude: longitude, width: Double(mask.width), height: Double(mask.height))
        let x = min(mask.width - 1, max(0, Int(p.x))), y = min(mask.height - 1, max(0, Int(p.y)))
        return BiomeRules.biome(maskIndex: Int(plane[y * mask.width + x]), inCity: inCity)
    }

    /// A tap on the map: the pin lands there and the place is named (or given as coordinates).
    func drop(latitude: Double, longitude: Double) {
        pin = (latitude, longitude)
        biome = biome(latitude: latitude, longitude: longitude)
        placeName = Self.coordinateName(latitude, longitude)
        timeZone = TimeZone(secondsFromGMT: HomePlace.roughOffset(longitude: longitude))
        resolving = true
        Task {
            let named = await PlaceSearch.name(latitude: latitude, longitude: longitude)
            guard let pin, pin.latitude == latitude, pin.longitude == longitude else { return }
            if let named {
                placeName = named.name
                timeZone = named.timeZone ?? timeZone
            } else if let city = cities?.city(near: latitude, longitude) {
                placeName = "Near \(city.name)"
            }
            resolving = false
        }
    }

    /// A search result chosen: the pin goes there.
    func choose(_ completion: MKLocalSearchCompletion) {
        query = ""
        resolving = true
        Task {
            guard let found = await PlaceSearch.resolve(completion) else {
                resolving = false
                return
            }
            pin = (found.latitude, found.longitude)
            biome = biome(latitude: found.latitude, longitude: found.longitude)
            placeName = found.name
            timeZone = found.timeZone ?? TimeZone(secondsFromGMT: HomePlace.roughOffset(longitude: found.longitude))
            resolving = false
            searchedTo += 1
        }
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

/// MapKit's place search (SPEC: "MapKit local search resolves it"): suggestions as you type, a chosen
/// suggestion resolved to coordinates, and a tapped coordinate named.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func query(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
        } else {
            completer.queryFragment = text
        }
    }

    /// MapKit calls back on the main thread.
    nonisolated func completerDidUpdateResults(_: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = Array(completer.results.prefix(6))
        }
    }

    nonisolated func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        MainActor.assumeIsolated {
            results = []
        }
    }

    struct Found: Sendable {
        var name: String
        var latitude: Double
        var longitude: Double
        var timeZone: TimeZone?
    }

    static func resolve(_ completion: MKLocalSearchCompletion) async -> Found? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        let label = completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle.split(separator: ",").first.map(String.init) ?? "")"
        return Found(name: label, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: item.timeZone)
    }

    static func name(latitude: Double, longitude: Double) async -> (name: String, timeZone: TimeZone?)? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
              let item = try? await request.mapItems.first else { return nil }
        let city = item.addressRepresentations?.cityWithContext
        // "Djado" and "Djado, Niger" read as "Djado, Niger", not "Djado, Djado, Niger".
        var parts: [String] = []
        let pieces = [item.name, city].compactMap(\.self).flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for part in pieces where !part.isEmpty && !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            parts.append(part)
        }
        return (parts.isEmpty ? WorldMapModel.coordinateName(latitude, longitude) : parts.joined(separator: ", "), item.timeZone)
    }
}

/// The map screen.
struct WorldMapView: View {
    @Bindable var model: WorldMapModel
    /// What a move costs (0: free), shown on the button.
    let cost: Int
    let canAfford: Bool
    let cancel: (() -> Void)?
    let done: (HomePlace, SeasonSetting) -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @FocusState private var searching: Bool
    @State private var viewSize: CGSize = .zero
    private let image: UIImage? = GameWorld.art.flatMap { UIImage(contentsOfFile: $0.url("world/map/map_painted.png").path) }

    var body: some View {
        ZStack {
            // The map fills the whole screen, under the notch and the home bar.
            GeometryReader { geometry in
                map(fit: fitted(in: geometry.size), in: geometry.size)
                    .onAppear { viewSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewSize = size }
            }
            .ignoresSafeArea()
            .background(Color(red: 0.47, green: 0.72, blue: 0.88))
            VStack(spacing: 0) {
                header
                Spacer()
                card
            }
            .padding(16)
        }
        // The keyboard covers the card while you type; nothing moves.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: model.searchedTo) { _, _ in focusOnPin() }
    }

    /// After a search, the map flies in to the place.
    private func focusOnPin() {
        guard let pin = model.pin, viewSize.width > 0 else { return }
        let fit = fitted(in: viewSize)
        let p = WorldMap.point(latitude: pin.latitude, longitude: pin.longitude, width: fit.width, height: fit.height)
        let target = CGFloat(Tuning.World.searchZoom)
        withAnimation(.easeInOut(duration: 0.6)) {
            zoom = target
            settledZoom = target
            offset = clamped(CGSize(width: (fit.width / 2 - p.x) * target, height: (fit.height / 2 - p.y) * target), fit: fit, in: viewSize)
            settledOffset = offset
        }
    }

    // MARK: The map

    /// The map's size at zoom 1: the whole world in the view.
    private func fitted(in size: CGSize) -> CGSize {
        let scale = max(size.width / 2, size.height) // 2:1, covering the view
        return CGSize(width: scale * 2, height: scale)
    }

    private func map(fit: CGSize, in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
            }
            cityLabels(fit: fit)
            if let pin = model.pin {
                let p = WorldMap.point(latitude: pin.latitude, longitude: pin.longitude, width: fit.width, height: fit.height)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34 / zoom))
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(radius: 2 / zoom)
                    .position(x: p.x, y: p.y - 14 / zoom)
            }
        }
        .frame(width: fit.width, height: fit.height)
        .scaleEffect(zoom)
        .offset(offset)
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(CGFloat(Tuning.World.maxZoom), max(1, settledZoom * value.magnification))
                        offset = clamped(settledOffset, fit: fit, in: size)
                    }
                    .onEnded { _ in
                        settledZoom = zoom
                        settledOffset = clamped(offset, fit: fit, in: size)
                        offset = settledOffset
                    },
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        offset = clamped(
                            CGSize(
                                width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height
                            ),
                            fit: fit,
                            in: size
                        )
                    }
                    .onEnded { _ in settledOffset = offset }
            )
        )
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                // The tap in map units: undo the offset and the zoom about the view's centre.
                let x = (value.location.x - size.width / 2 - offset.width) / zoom + fit.width / 2
                let y = (value.location.y - size.height / 2 - offset.height) / zoom + fit.height / 2
                guard y >= 0, y <= fit.height else { return }
                let c = WorldMap.coordinate(x: x, y: y, width: fit.width, height: fit.height)
                model.drop(latitude: c.latitude, longitude: c.longitude)
            }
        )
    }

    /// Keeps the map covering the view.
    private func clamped(_ proposed: CGSize, fit: CGSize, in size: CGSize) -> CGSize {
        let spareX = max(0, (fit.width * zoom - size.width) / 2), spareY = max(0, (fit.height * zoom - size.height) / 2)
        return CGSize(width: min(spareX, max(-spareX, proposed.width)), height: min(spareY, max(-spareY, proposed.height)))
    }

    /// City names drawn by code as you zoom in: the big ones first.
    private func cityLabels(fit: CGSize) -> some View {
        let shown = (model.cities?.cities ?? []).filter {
            zoom >= CGFloat($0.big ? Tuning.World.bigCityNamesZoom : Tuning.World.cityNamesZoom)
        }
        return ForEach(shown, id: \.self) { city in
            let p = WorldMap.point(latitude: city.latitude, longitude: city.longitude, width: fit.width, height: fit.height)
            VStack(spacing: 1 / zoom) {
                Circle().fill(Color(white: 0.25)).frame(width: 4 / zoom, height: 4 / zoom)
                Text(city.name)
                    .font(.system(size: 11 / zoom, weight: city.big ? .semibold : .regular))
                    .foregroundStyle(Color(white: 0.2))
                    .fixedSize()
            }
            .position(x: p.x, y: p.y + 6 / zoom)
            .allowsHitTesting(false)
        }
    }

    // MARK: Search and the card

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if !searching {
                    HStack(spacing: 6) {
                        PaintedIcon("map_pin", size: 30)
                        Text(model.mode == .first || cost == 0 && model.pin == nil ? "Where do you live?" : "Move home")
                            .font(Theme.title(22))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 4)
                    .paper(Capsule())
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("A city, a street, a postcode", text: $model.query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($searching)
                        .submitLabel(.search)
                        .onSubmit {
                            if let first = model.search.results.first {
                                model.choose(first)
                            }
                        }
                }
                .padding(10)
                .frame(maxWidth: 380)
                .paper(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if !model.search.results.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.search.results.prefix(4), id: \.self) { result in
                            Button {
                                searching = false
                                model.choose(result)
                            } label: {
                                // One line a result, so four fit above the keyboard.
                                (Text(result.title).font(.subheadline.weight(.semibold))
                                    + Text(result.subtitle.isEmpty ? "" : "  \(result.subtitle)").font(.caption)
                                    .foregroundStyle(.secondary))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .frame(maxWidth: 380)
                    .paper(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Spacer()
            if let cancel {
                CloseButton(action: cancel)
            }
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if model.pin == nil {
                    Text("Search, or tap the map to drop your pin.").font(.headline)
                } else {
                    HStack(spacing: 6) {
                        Text(model.placeName).font(.headline).lineLimit(1)
                        if model.resolving {
                            ProgressView().controlSize(.small)
                        }
                    }
                    HStack(spacing: 8) {
                        if let biome = model.biome {
                            Label(Self.biomeName(biome), systemImage: Self.biomeIcon(biome))
                        }
                        if let time = model.localTime {
                            Label("\(time) there", systemImage: "clock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Picker("Season", selection: $model.season) {
                    Text("Auto (the real season there)").tag(SeasonSetting.auto)
                    ForEach(NatureSeason.allCases, id: \.self) { season in
                        Text("Always \(season.rawValue)").tag(SeasonSetting.fixed(season))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    PaintedIcon("weather_sun_and_cloud", size: 24)
                    Text(seasonTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .paper(Capsule())
            }
            HUDButton(buttonTitle, icon: "house", prominent: true) {
                if let place = model.place {
                    done(place, model.season)
                }
            }
            .disabled(model.place == nil || model.resolving || !canAfford)
            .opacity(model.place == nil || model.resolving || !canAfford ? 0.5 : 1)
        }
        .padding(14)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var buttonTitle: String {
        switch model.mode {
        case .first: "Live here"
        case .move: cost == 0 ? "Move here" : "Move here · \(cost) Beans"
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
