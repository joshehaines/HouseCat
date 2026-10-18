import HouseCatCore
import HouseCatGame
import HouseCatUI
import Observation
import SpriteKit
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// How the globe is turned and how far in it is, as a function of time, so the view only reads it: turning by
/// itself, coasting after a flick, held by a finger, or flying to a place (out a little and in again).
@MainActor
@Observable
final class GlobeCamera {
    enum Motion {
        case still
        case coast(latitude: Double, longitude: Double)
        case flight(from: GlobeOrientation, fromZoom: Double, to: GlobeOrientation, toZoom: Double, seconds: Double)
    }

    private(set) var rest: GlobeOrientation
    private(set) var restZoom: Double
    private(set) var since = Date()
    private(set) var motion: Motion = .still
    /// Turns slowly by itself when nobody is holding it (the landing page, the map before a pin).
    var spins: Bool
    private var held = false
    /// Where the disc sits (fractions of the view: right, and up from the middle), easing when it moves.
    private var placement = (from: CGPoint.zero, to: CGPoint.zero, since: Date.distantPast)
    private var placed = false

    /// The first placement is where it starts; later ones slide there.
    func place(shift: CGFloat, lift: CGFloat) {
        let target = CGPoint(x: shift, y: lift)
        guard !placed || target != placement.to else { return }
        let now = Date()
        placement = placed ? (offset(at: now), target, now) : (target, target, .distantPast)
        placed = true
    }

    func offset(at date: Date) -> CGPoint {
        let e = min(1, max(0, date.timeIntervalSince(placement.since) / Tuning.Intro.globeSlideSeconds))
        let eased = e * e * (3 - 2 * e)
        return CGPoint(
            x: placement.from.x + (placement.to.x - placement.from.x) * eased,
            y: placement.from.y + (placement.to.y - placement.from.y) * eased
        )
    }

    init(latitude: Double = 25, longitude: Double = 0, zoom: Double = 1, spins: Bool = true) {
        rest = GlobeOrientation(latitude: latitude, longitude: longitude)
        restZoom = zoom
        self.spins = spins
    }

    func pose(at date: Date) -> (orientation: GlobeOrientation, zoom: Double) {
        let t = max(0, date.timeIntervalSince(since))
        var orientation = rest
        var zoom = restZoom
        switch motion {
        case .still:
            break
        case let .coast(vLat, vLon):
            let tau = Tuning.World.globeCoast, k = tau * (1 - exp(-t / tau))
            orientation = GlobeOrientation(latitude: rest.latitude, longitude: rest.longitude)
                .dragged(dx: -vLon * k * .pi / 180, dy: vLat * k * .pi / 180)
        case let .flight(from, fromZoom, to, toZoom, seconds):
            let e = min(1, t / seconds)
            let eased = e * e * (3 - 2 * e)
            orientation = from.blended(to: to, by: eased)
            // A long way round goes out a little and comes in again.
            let distance = WorldMap.distance((from.latitude, from.longitude), (to.latitude, to.longitude))
            let hop = min(0.55, distance / 12000) * min(fromZoom, toZoom)
            zoom = fromZoom + (toZoom - fromZoom) * eased - hop * sin(.pi * eased)
        }
        // The spin starts from rest: after a flight, from when it lands.
        var spinTime = t
        if case let .flight(_, _, _, _, seconds) = motion {
            spinTime = max(0, t - seconds)
        }
        if spins, !held, spinTime > 0 {
            orientation = orientation.dragged(dx: -Tuning.World.globeSpin * spinTime * .pi / 180, dy: 0)
        }
        return (orientation, max(0.6, zoom))
    }

    func isFlying(at date: Date) -> Bool {
        if case let .flight(_, _, _, _, seconds) = motion {
            return date.timeIntervalSince(since) < seconds
        }
        return false
    }

    /// A finger comes down: the globe stops where it is.
    func hold(at date: Date = Date()) {
        let now = pose(at: date)
        held = true
        rest = now.orientation
        restZoom = now.zoom
        since = date
        motion = .still
    }

    /// Held and turned to here (a drag in progress).
    func set(_ orientation: GlobeOrientation, zoom: Double? = nil) {
        rest = orientation
        if let zoom {
            restZoom = min(Tuning.World.globeMaxZoom, max(1, zoom))
        }
        since = Date()
    }

    /// Let go, still moving (degrees a second).
    func release(latitudeSpeed: Double = 0, longitudeSpeed: Double = 0) {
        held = false
        since = Date()
        motion = abs(latitudeSpeed) + abs(longitudeSpeed) > 2 ? .coast(latitude: latitudeSpeed, longitude: longitudeSpeed) : .still
    }

    /// Off to a place, arriving at `zoom`.
    func fly(to latitude: Double, _ longitude: Double, zoom: Double, seconds: Double = Tuning.World.globeFlightSeconds) {
        let now = pose(at: Date())
        let limit = Tuning.World.globeTiltLimit
        let target = GlobeOrientation(latitude: min(limit, max(-limit, latitude)), longitude: longitude)
        rest = target
        restZoom = zoom
        since = Date()
        held = false
        motion = .flight(from: now.orientation, fromZoom: now.zoom, to: target, toZoom: zoom, seconds: seconds)
    }
}

/// Something marked on the globe: the player's pin, an example home, a friend's house.
struct GlobeMarker: Identifiable, Equatable {
    enum Kind: Equatable {
        case pin
        case home(icon: String)
    }

    var id: String
    var latitude: Double
    var longitude: Double
    var title: String?
    var kind: Kind
    var highlighted = false
}

/// The painted map for the globe, loaded once.
@MainActor
enum GlobeTextures {
    static let map: CGImage? = {
        #if canImport(UIKit)
            guard let url = GameWorld.art?.url("world/map/map_painted.png") else { return nil }
            return UIImage(contentsOfFile: url.path)?.cgImage
        #else
            return nil
        #endif
    }()
}

/// The world as a painted globe in a night sky: it turns by itself, a drag spins it (and it coasts), a pinch
/// zooms, a tap gives the place under the finger. Markers and city names ride on it, hidden round the back.
struct SpinningGlobe: View {
    let camera: GlobeCamera
    var markers: [GlobeMarker] = []
    var cities: [CitiesFile.City] = []
    var interactive = true
    /// Moves the globe up (a fraction of the view's height) to leave room below it.
    var lift: CGFloat = 0
    /// Moves the globe right (a fraction of the view's width) to leave room on the left.
    var shift: CGFloat = 0
    var onTap: ((Double, Double) -> Void)?

    @State private var scene: GlobeScene?
    @State private var dragStart: GlobeOrientation?
    @State private var pinchStart: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(paused: reduceMotion && !camera.isFlying(at: Date()))) { timeline in
                let pose = camera.pose(at: timeline.date)
                let size = geometry.size
                let radius = min(size.width, size.height) * Tuning.World.globeSize * pose.zoom
                let offset = camera.offset(at: timeline.date)
                let centre = CGPoint(x: size.width * (0.5 + offset.x), y: size.height * (0.5 - offset.y))
                ZStack {
                    SpaceSky(time: timeline.date.timeIntervalSinceReferenceDate)
                    // The glow of the air round it.
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.55, green: 0.75, blue: 1).opacity(0.5), .clear],
                            center: .center,
                            startRadius: radius * 0.95,
                            endRadius: radius * 1.18
                        ))
                        .frame(width: radius * 2.4, height: radius * 2.4)
                        .position(centre)
                    if let scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .allowsHitTesting(false)
                    }
                    labels(pose: pose, centre: centre, radius: radius)
                    marks(pose: pose, centre: centre, radius: radius, time: timeline.date)
                }
                .contentShape(Rectangle())
                .gesture(interactive ? drag(radius: radius) : nil)
                .simultaneousGesture(interactive ? pinch : nil)
                .simultaneousGesture(interactive ? tap(pose: pose, centre: centre, radius: radius) : nil)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // The first placement is where it starts; later ones slide.
            camera.place(shift: shift, lift: lift)
            makeScene()
        }
        .onChange(of: shift) { _, shift in camera.place(shift: shift, lift: lift) }
        .onChange(of: lift) { _, lift in camera.place(shift: shift, lift: lift) }
        .accessibilityElement()
        .accessibilityLabel("The world. Drag to spin it, pinch to zoom, tap to choose a place.")
    }

    /// The disc the scene draws, in its own points (y up), from the same pose as the marks.
    private func makeScene() {
        guard scene == nil, let map = GlobeTextures.map else { return }
        let made = GlobeScene(size: CGSize(width: 800, height: 600), map: map)
        let camera = camera
        made.pose = { size in
            let pose = camera.pose(at: Date())
            let radius = min(size.width, size.height) * Tuning.World.globeSize * pose.zoom
            let offset = camera.offset(at: Date())
            return (CGPoint(x: size.width * (0.5 + offset.x), y: size.height * (0.5 + offset.y)), radius, pose.orientation)
        }
        scene = made
    }

    private func point(_ p: (x: Double, y: Double, depth: Double), centre: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + CGFloat(p.x) * radius, y: centre.y - CGFloat(p.y) * radius)
    }

    private func labels(pose: (orientation: GlobeOrientation, zoom: Double), centre: CGPoint, radius: CGFloat) -> some View {
        // Big cities first; a name too close to one already placed is left out, so they never pile up.
        let candidates = cities
            .filter { pose.zoom >= ($0.big ? Tuning.World.globeBigCityZoom : Tuning.World.globeCityZoom) }
            .sorted { $0.big && !$1.big }
        var placed: [(city: CitiesFile.City, at: CGPoint, depth: Double)] = []
        for city in candidates {
            let p = pose.orientation.project(latitude: city.latitude, longitude: city.longitude)
            guard p.depth > 0.2 else { continue }
            let at = point(p, centre: centre, radius: radius)
            if placed.allSatisfy({ abs($0.at.x - at.x) > 70 || abs($0.at.y - at.y) > 22 }) {
                placed.append((city, at, p.depth))
            }
        }
        return ForEach(placed, id: \.city) { label in
            VStack(spacing: 1) {
                Circle().fill(.white).frame(width: 4, height: 4)
                Text(label.city.name)
                    .font(.system(size: label.city.big ? 12 : 10.5, weight: label.city.big ? .semibold : .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .fixedSize()
            }
            .opacity(min(1, (label.depth - 0.2) * 3))
            .position(x: label.at.x, y: label.at.y + 7)
            .allowsHitTesting(false)
        }
    }

    private func marks(pose: (orientation: GlobeOrientation, zoom: Double), centre: CGPoint, radius: CGFloat, time: Date) -> some View {
        ForEach(markers) { marker in
            let p = pose.orientation.project(latitude: marker.latitude, longitude: marker.longitude)
            if p.depth > 0.05 {
                let at = point(p, centre: centre, radius: radius)
                Group {
                    switch marker.kind {
                    case .pin:
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white, Theme.accent)
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                            .offset(y: -16)
                    case let .home(icon):
                        let pulse = 1 + 0.12 * sin(time.timeIntervalSinceReferenceDate * 3)
                        VStack(spacing: 2) {
                            // Small from afar (they crowd), bigger closer in.
                            PaintedIcon(icon, size: marker.highlighted ? 40 : min(28, 14 + 6 * pose.zoom))
                                .padding(4)
                                .background(Circle().fill(Theme.cream))
                                .overlay(Circle().strokeBorder(
                                    marker.highlighted ? Theme.accent : Theme.rim,
                                    lineWidth: marker.highlighted ? 3 : 1
                                ))
                                .scaleEffect(marker.highlighted ? pulse : 1)
                                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                            if let title = marker.title {
                                Text(title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 2)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .opacity(min(1, p.depth * 5))
                .position(at)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Gestures

    private func drag(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart == nil {
                    camera.hold()
                    dragStart = camera.rest
                }
                guard let start = dragStart else { return }
                camera.set(start.dragged(dx: Double(value.translation.width / radius), dy: Double(value.translation.height / radius)))
            }
            .onEnded { value in
                dragStart = nil
                let degrees = 180 / Double.pi
                camera.release(
                    latitudeSpeed: Double(value.velocity.height / radius) * degrees,
                    longitudeSpeed: -Double(value.velocity.width / radius) * degrees
                )
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil {
                    camera.hold()
                    pinchStart = camera.restZoom
                }
                camera.set(camera.rest, zoom: (pinchStart ?? 1) * value.magnification)
            }
            .onEnded { _ in
                pinchStart = nil
                camera.release()
            }
    }

    private func tap(pose: (orientation: GlobeOrientation, zoom: Double), centre: CGPoint, radius: CGFloat) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let x = Double((value.location.x - centre.x) / radius), y = Double(-(value.location.y - centre.y) / radius)
            if let place = pose.orientation.place(x: x, y: y) {
                onTap?(place.latitude, place.longitude)
            }
        }
    }
}

/// A night sky: deep blue to violet with stars that twinkle, the same stars every time.
struct SpaceSky: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.2), Color(red: 0.17, green: 0.12, blue: 0.3)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width * 0.3, y: size.height)
                )
            )
            for i in 0 ..< 180 {
                let x = Double((i * 7919) % 1000) / 1000 * size.width
                let y = Double((i * 3571) % 1000) / 1000 * size.height
                let r = 0.5 + Double((i * 104_729) % 100) / 100 * 1.3
                let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * (0.6 + Double(i % 7) * 0.25) + Double(i)))
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(twinkle * 0.85)))
            }
        }
    }
}
