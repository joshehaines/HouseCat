import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI

/// The intro (a builder game's first minutes, in the house style; Content/intro.json): the logo over a turning
/// globe, the host saying hello, then a flight round the world to a few homes, each painted where it is with a
/// cat living in it, before the player makes their own cat. Skip is always there.
struct IntroView: View {
    let intro: IntroFile
    let done: () -> Void

    private enum Phase: Equatable {
        case landing
        case hello(Int)
        case flying(Int)
        case visiting(Int)
        case outro
    }

    @State private var phase = Phase.landing
    @State private var camera = GlobeCamera(latitude: 30, longitude: -10, zoom: 1, spins: true)
    @State private var scene: ExteriorScene?
    @State private var portrait: CGImage?
    @State private var logoShown = false

    var body: some View {
        ZStack {
            SpinningGlobe(camera: camera, markers: markers, interactive: phase == .landing || phase == .outro, shift: globeShift)
            switch phase {
            case .landing:
                landing
            case let .visiting(index):
                visit(intro.stops[index])
                    .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity), removal: .opacity))
            default:
                EmptyView()
            }
            VStack {
                HStack {
                    Spacer()
                    if phase != .landing {
                        HUDButton("Skip", symbol: "forward.end") {
                            Analytics.track(.introSkipped)
                            done()
                        }
                    }
                }
                Spacer()
                bubble
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .animation(.spring(duration: 0.6), value: phase)
        #if DEBUG
            // Screenshot runs: HOUSECAT_AUTOPLAY=1 steps through on its own.
            .task(id: phase) {
                guard ProcessInfo.processInfo.environment["HOUSECAT_AUTOPLAY"] != nil else { return }
                // A cancelled wait (the phase moved on) does nothing.
                guard await (try? Task.sleep(for: .seconds(4))) != nil else { return }
                switch phase {
                case .landing: phase = .hello(0)
                case let .hello(index): index + 1 < intro.hello.count ? (phase = .hello(index + 1)) : fly(to: 0)
                case let .visiting(index): leave(index)
                case .flying, .outro: break
                }
            }
        #endif
            .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
            .statusBarHidden()
            .onAppear {
                let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                Music.play(for: SkyPhase.at(localMinutes: (now.hour ?? 12) * 60 + (now.minute ?? 0)))
            }
    }

    private var globeShift: CGFloat {
        phase == .landing ? 0.18 : 0
    }

    private var markers: [GlobeMarker] {
        let current: Int? = switch phase {
        case let .flying(i), let .visiting(i): i
        default: nil
        }
        return intro.stops.enumerated().map { index, stop in
            GlobeMarker(
                id: stop.id,
                latitude: stop.latitude,
                longitude: stop.longitude,
                title: index == current ? stop.place : nil,
                kind: .home(icon: "house"),
                highlighted: index == current
            )
        }
    }

    // MARK: The landing page

    private var landing: some View {
        HStack {
            VStack(spacing: 14) {
                if let logo = CatScreens.picture("brand/logo/wordmark_on_dark.png") {
                    // The wordmark, with Midnight running in from the edge and curling up asleep on it.
                    AnimatedLogo(act: .intro, ink: .dark) {
                        logo.resizable().scaledToFit()
                    }
                    .frame(width: 330)
                    .opacity(logoShown ? 1 : 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("HouseCat")
                    .accessibilityAddTraits(.isImage)
                }
                Text(intro.tagline)
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.cream)
                    .multilineTextAlignment(.center)
                    .opacity(logoShown ? 1 : 0)
                ChunkyButton("Begin") {
                    Analytics.track(.introStarted)
                    phase = .hello(0)
                    camera.spins = true
                }
                .opacity(logoShown ? 1 : 0)
            }
            .frame(maxWidth: 380)
            Spacer()
        }
        .padding(.leading, 40)
        .onAppear {
            withAnimation(.spring(duration: 1.1, bounce: 0.35).delay(0.3)) { logoShown = true }
        }
    }

    // MARK: The host

    @ViewBuilder
    private var bubble: some View {
        switch phase {
        case .landing:
            EmptyView()
        case let .hello(index):
            HostBubble(name: intro.host, text: intro.hello[index], button: "Next") {
                if index + 1 < intro.hello.count {
                    phase = .hello(index + 1)
                } else {
                    fly(to: 0)
                }
            }
            .id("hello\(index)")
        case let .flying(index):
            HostBubble(name: intro.host, text: "Off to \(intro.stops[index].place)…")
                .id("fly\(index)")
        case let .visiting(index):
            HostBubble(name: intro.host, text: intro.stops[index].line, button: index + 1 < intro.stops.count ? "Next home" : "Next") {
                leave(index)
            }
            .id("visit\(index)")
        case .outro:
            HostBubble(name: intro.host, text: intro.outro, button: "Make my cat") {
                Analytics.track(.introFinished)
                done()
            }
            .id("outro")
        }
    }

    // MARK: The tour of homes

    private func fly(to index: Int) {
        let stop = intro.stops[index]
        scene = nil
        portrait = nil
        camera.spins = false
        camera.fly(to: stop.latitude, stop.longitude, zoom: Tuning.Intro.stopZoom)
        phase = .flying(index)
        prepare(stop)
        Task {
            try? await Task.sleep(for: .seconds(Tuning.World.globeFlightSeconds + Tuning.Intro.pauseOnArrival))
            if phase == .flying(index) {
                // A light meow as each home comes into view (Josh, 19 Oct: the door was loud and strange).
                Sound.play("cat_meow_soft", volume: Tuning.Sound.introMeow)
                phase = .visiting(index)
            }
        }
    }

    private func leave(_ index: Int) {
        if index + 1 < intro.stops.count {
            fly(to: index + 1)
        } else {
            scene = nil
            camera.fly(to: 25, intro.stops[index].longitude, zoom: 1)
            camera.spins = true
            phase = .outro
        }
    }

    /// The home's painting and its cat, made while the globe flies.
    private func prepare(_ stop: IntroFile.Stop) {
        guard let art = GameWorld.art else { return }
        let name = String(stop.scene.split(separator: "/").last ?? "")
        let door = GameWorld.door(for: name)
        let model = ExteriorScene.Model(
            scene: stop.scene,
            sky: stop.sky(at: Date()),
            door: door,
            weather: stop.weather,
            season: stop.season
        )
        let made = ExteriorScene(size: CGSize(width: 1024, height: 600), art: art, model: model)
        made.showcase = true
        scene = made
        if let look = GameWorld.catArt?.builder.preset(stop.cat.preset)?.look {
            portrait = CatScreens.portrait(look)
        }
    }

    private func visit(_ stop: IntroFile.Stop) -> some View {
        ZStack {
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack {
                HStack(alignment: .top) {
                    caption(stop)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    catCard(stop)
                }
                .padding(.bottom, 96)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func caption(_ stop: IntroFile.Stop) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(stop.home) in \(stop.place)").font(Theme.title(22))
            HStack(spacing: 10) {
                Label(stop.country, systemImage: "mappin.and.ellipse")
                Label(WorldMapView.weatherName(stop.weather), systemImage: WorldMapView.weatherIcon(stop.weather))
                if let zone = TimeZone(identifier: stop.timeZone) {
                    Label(
                        "\(Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) there",
                        systemImage: "clock"
                    )
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func catCard(_ stop: IntroFile.Stop) -> some View {
        HStack(spacing: 10) {
            if let portrait {
                Image(decorative: portrait, scale: 1).resizable().scaledToFit().frame(width: 74, height: 96)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.cat.name).font(Theme.title(20))
                Text(GameWorld.catArt?.builder.preset(stop.cat.preset)?.name ?? "").font(.subheadline).foregroundStyle(Theme.inkSoft)
                Text(stop.cat.personality.rawValue.capitalized).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .foregroundStyle(Theme.ink)
        .paper(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
