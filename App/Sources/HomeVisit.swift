import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI

/// A visit to another cat's home from the world map (Josh, 19 Oct: "see other example locations with other cats"):
/// the intro's stop again, at its own local time and weather, with its cat and the host's line, and Back to the
/// map. Opens from `Tuning.Goals.homesLevel`.
struct HomeVisitView: View {
    let stop: IntroFile.Stop
    /// Homes visited, this one counted, and how many there are.
    let visited: Int
    let total: Int
    let close: () -> Void

    @State private var scene: ExteriorScene?
    @State private var portrait: CGImage?

    var body: some View {
        ZStack {
            SpaceSky(time: 0).ignoresSafeArea()
            if let scene {
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    caption
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        PaintedIcon("house", size: 24)
                        Text("\(visited) of \(total) homes visited").font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.ink)
                    .paper(Capsule())
                    CloseButton(action: close)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    catCard
                }
                HostBubble(name: GameWorld.content?.intro.host ?? "Pat", text: stop.line, button: "Back to the map", action: close)
                    .frame(maxWidth: 760)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .statusBarHidden()
        .onAppear(perform: prepare)
    }

    /// The home's painting at its local sky, and its cat.
    private func prepare() {
        guard scene == nil, let art = GameWorld.art else { return }
        let name = String(stop.scene.split(separator: "/").last ?? "")
        let model = ExteriorScene.Model(
            scene: stop.scene,
            sky: stop.sky(at: Date()),
            door: GameWorld.door(for: name),
            weather: stop.weather,
            season: stop.season
        )
        let made = ExteriorScene(size: CGSize(width: 1024, height: 600), art: art, model: model)
        made.showcase = true
        scene = made
        if let look = GameWorld.catArt?.builder.preset(stop.cat.preset)?.look {
            portrait = CatScreens.portrait(look, outfit: nil)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(stop.cat.name)'s \(WorldMapView.homeWord(stop.home)) in \(stop.place)").font(Theme.title(22))
            HStack(spacing: 10) {
                Label(stop.country, systemImage: "mappin.and.ellipse")
                let sky = stop.sky(at: Date())
                Label(WorldMapView.weatherName(stop.weather, sky: sky), systemImage: WorldMapView.weatherIcon(stop.weather, sky: sky))
                if let zone = TimeZone(identifier: stop.timeZone) {
                    Label("\(Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))) there", systemImage: "clock")
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

    private var catCard: some View {
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
        .accessibilityElement(children: .combine)
    }
}
