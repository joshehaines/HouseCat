import HouseCatCore
import HouseCatGame
import HouseCatUI
import SpriteKit
import SwiftUI

/// The opening cutscene, after the cat is made (docs/LADDER.md; Josh, 22 Oct: "a run down house in the rain and your
/// cat comes to the door to meet you. Then into a scene showing the bottom tier house and then the top tier house all
/// the way up"): the first house in Puddlebury in the rain, your cat at its door, then the ladder climbed bottom to
/// top, ending on London. Then home.
struct Cutscene: View {
    let catName: String
    let done: () -> Void

    private enum Phase: Equatable {
        case door
        case ladder
    }

    @State private var phase = Phase.door
    @State private var scene: ExteriorScene?
    @State private var greeted = false
    @State private var shownRung = 1
    @State private var climbed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .door: door
            case .ladder: ladder
            }
        }
        .overlay(alignment: .topTrailing) {
            if !climbed {
                Button("Skip") { done() }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(20)
            }
        }
    }

    // MARK: The door

    private var door: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if let scene {
                    SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                        .allowsHitTesting(false)
                } else {
                    Color.clear.onAppear { start(size: proxy.size) }
                }
            }
            .ignoresSafeArea()
            VStack(spacing: 14) {
                Text(greeted ? "But someone's waiting for you." : "Puddlebury. Raining, again.")
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .contentTransition(.opacity)
                if greeted {
                    Text("\(catName) found this little house first. It isn't much yet.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.cream.opacity(0.9))
                        .shadow(color: .black.opacity(0.6), radius: 6)
                    ChunkyButton("Next") { toLadder() }
                        .frame(maxWidth: 220)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .animation(.easeInOut(duration: 0.5), value: greeted)
        }
    }

    private func start(size: CGSize) {
        guard scene == nil, size.width > 0 else { return }
        let made = GameWorld.cutsceneScene(size: size)
        scene = made
        Music.play(for: .dusk)
        let session = GameSession.shared
        let state = session.state(at: session.now())
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tuning.Cutscene.doorOpensAfter))
            guard phase == .door, let made, let cat = GameWorld.playerCat(state: state, at: session.now()) else { return }
            made.onDoorOpens = { Sound.play("door_open", volume: Tuning.Sound.door) }
            made.greet(cat)
            try? await Task.sleep(for: .seconds(Tuning.Exterior.doorOpenSeconds + Tuning.Cutscene.walkSeconds))
            greeted = true
            // On by itself after a moment (Next goes sooner).
            try? await Task.sleep(for: .seconds(Tuning.Cutscene.ladderAfter))
            toLadder()
        }
    }

    private func toLadder() {
        guard phase == .door else { return }
        withAnimation(.easeInOut(duration: 0.6)) { phase = .ladder }
        climb()
    }

    // MARK: The ladder

    /// Every house bottom to top, the camera climbing from the first to London.
    private var ladder: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    ForEach(HouseLadder.rungs.reversed()) { rung in
                        card(rung).id(rung.number)
                    }
                }
                .padding(.vertical, 120)
                .padding(.horizontal, 24)
            }
            .scrollDisabled(true)
            .onAppear { reader.scrollTo(1, anchor: .center) }
            .onChange(of: shownRung) { _, rung in
                withAnimation(.easeInOut(duration: Tuning.Cutscene.rungSeconds * 0.8)) {
                    reader.scrollTo(rung, anchor: .center)
                }
            }
            .onChange(of: climbed) { _, climbed in
                // Room under London for the last line and the button.
                guard climbed else { return }
                withAnimation(.easeInOut(duration: 0.6)) { reader.scrollTo(HouseLadder.top, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.4), Color(red: 0.96, green: 0.7, blue: 0.5)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if climbed {
                VStack(spacing: 12) {
                    Text("From Puddlebury to London, one house at a time.")
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                    ChunkyButton("Take \(catName) home") { done() }
                        .frame(maxWidth: 260)
                        .accessibilityIdentifier("cutsceneDone")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
                .transition(.opacity)
            }
        }
    }

    private func climb() {
        Task { @MainActor in
            for number in 2 ... HouseLadder.top {
                try? await Task.sleep(for: .seconds(Tuning.Cutscene.rungSeconds))
                shownRung = number
            }
            try? await Task.sleep(for: .seconds(Tuning.Cutscene.topSeconds))
            withAnimation(.easeInOut(duration: 0.5)) { climbed = true }
        }
    }

    private func card(_ rung: Rung) -> some View {
        let here = rung.number == shownRung
        return VStack(spacing: 8) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.78, blue: 0.93), Color(red: 0.95, green: 0.9, blue: 0.82)],
                               startPoint: .top, endPoint: .bottom)
                if let picture = Self.picture(rung) {
                    picture.resizable().scaledToFill()
                        .mask {
                            if let land = CatScreens.picture(Self.landPath(rung)) {
                                land.resizable().scaledToFill().luminanceToAlpha()
                            } else {
                                Rectangle()
                            }
                        }
                }
            }
            .frame(maxWidth: 400)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cream, lineWidth: here ? 4 : 2))
            HStack(spacing: 8) {
                Text(rung.number == 1 ? "Your first house" : rung.number == HouseLadder.top ? "One day" : "House \(rung.number)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Theme.cream.opacity(0.8))
                Text("\(rung.name) · \(rung.place.name)")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.cream)
            }
            .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .scaleEffect(here ? 1 : 0.86)
        .opacity(here ? 1 : climbed ? 0 : 0.55)
        .animation(.easeInOut(duration: 0.5), value: shownRung)
        .accessibilityElement(children: .combine)
    }

    private static func previewPath(_ rung: Rung) -> String {
        "world/previews/\(rung.style.rawValue)_\(rung.place.biome.rawValue)"
    }

    /// The picture's sky mask.
    private static func landPath(_ rung: Rung) -> String {
        rung.number == 1 ? "world/scenes/\(Tuning.Cutscene.firstHouseScene)_city_autumn_land.png" : previewPath(rung) + "_land.png"
    }

    /// The first house is the run-down painting; the others their small built-in previews (their full exteriors are
    /// download packs).
    private static func picture(_ rung: Rung) -> Image? {
        if rung.number == 1 {
            return CatScreens.picture("world/scenes/\(Tuning.Cutscene.firstHouseScene)_city_autumn.jpg")
        }
        return CatScreens.picture(previewPath(rung) + ".jpg")
    }
}
