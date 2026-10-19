import HouseCatCore
import HouseCatUI
import SwiftUI

/// The Games menu's look, shared by its screens (after the shop's: painted paper, the honey-oak plank along the top,
/// cream cards with a gold rim and a coloured band).
@MainActor
enum GamesLook {
    static let zoomies = Color(red: 0.24, green: 0.62, blue: 0.58)
    static let catapult = Color(red: 0.3, green: 0.5, blue: 0.82)
    static let match = Color(red: 0.86, green: 0.42, blue: 0.32)
    static let row = Color(red: 0.52, green: 0.36, blue: 0.7)
    static let puzzle = Color(red: 0.9, green: 0.64, blue: 0.18)
    static let quick = Color(red: 0.88, green: 0.6, blue: 0.2)
    static let green = Color(red: 0.4, green: 0.7, blue: 0.26)

    static func colour(_ game: ArcadeGame) -> Color {
        switch game {
        case .zoomies: zoomies
        case .catapult: catapult
        case .match: match
        case .row: row
        }
    }

    /// Everything is drawn for a phone on its side and scaled to the screen (as the shop is).
    static let designSize = CGSize(width: 780, height: 400)

    static func scale(_ size: CGSize) -> CGFloat {
        let fit = min(size.width / designSize.width, size.height / designSize.height)
        return min(1.6, max(0.78, (fit * 20).rounded(.down) / 20))
    }

    /// A picture from the Games art (or any art) by its master path.
    static func picture(_ path: String) -> Image? {
        CatScreens.picture(path)
    }
}

/// A cream card with a gold rim (the shop's tiles).
struct GoldCard: ViewModifier {
    var corner: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .background(shape.fill(LinearGradient(colors: [Theme.cream, Color(red: 0.97, green: 0.89, blue: 0.76)],
                                                  startPoint: .top, endPoint: .bottom)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(red: 1, green: 0.96, blue: 0.84), lineWidth: 4.5))
            .overlay(shape.strokeBorder(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom),
                                        lineWidth: 3))
            .shadow(color: Color(red: 0.35, green: 0.17, blue: 0.05).opacity(0.3), radius: 7, y: 5)
    }
}

extension View {
    func goldCard(corner: CGFloat = 18) -> some View {
        modifier(GoldCard(corner: corner))
    }
}

/// The painted paper every Games screen is printed on.
struct GamesPaper: View {
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.88, blue: 0.76)
            if let paper = GamesLook.picture("ui/shop/shop_paper.png") {
                paper.resizable(resizingMode: .tile).opacity(0.9)
            }
        }
        .ignoresSafeArea()
    }
}

/// The honey-oak plank along the top: an icon and a title on the left, whatever the screen needs on the right.
struct GamesPlank<Trailing: View>: View {
    let title: String
    let icon: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .paper(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back")
            }
            if let icon = GamesLook.picture(icon) {
                icon.resizable().scaledToFit().frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1.5)
            }
            Text(title)
                .font(Theme.title(28))
                .foregroundStyle(Color(red: 1, green: 0.97, blue: 0.9))
                .shadow(color: Color(red: 0.48, green: 0.25, blue: 0.07), radius: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background {
            ZStack {
                Color(red: 0.86, green: 0.55, blue: 0.24)
                if let plank = GamesLook.picture("ui/shop/shop_plank.png") {
                    plank.resizable()
                }
            }
            .shadow(color: Color(red: 0.32, green: 0.16, blue: 0.04).opacity(0.35), radius: 6, y: 4)
            .ignoresSafeArea(edges: .top)
        }
    }
}

/// A rounded cream pill with an icon and a value (Beans, the puzzle streak).
struct GamesPill: View {
    let icon: String
    let value: String
    var label: String?

    var body: some View {
        HStack(spacing: 5) {
            if let picture = GamesLook.picture(icon) {
                picture.resizable().scaledToFit().frame(width: 28, height: 28)
            }
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit()
            if let label {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .paper(Capsule())
    }
}

/// Stars in a row, the ones not reached faint.
struct StarsRow: View {
    let count: Int
    var of: Int = 3
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: size * 0.08) {
            ForEach(0 ..< of, id: \.self) { index in
                PaintedIcon("xp_star", size: size).opacity(index < count ? 1 : 0.25)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count) of \(of) stars")
    }
}

/// A coloured title band across the top of a card.
struct CardBand: View {
    let title: String
    let colour: Color

    var body: some View {
        Text(title)
            .font(Theme.title(17))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [colour.mix(with: .white, by: 0.12), colour], startPoint: .top, endPoint: .bottom))
    }
}

/// What a game paid, shown at its end: the stars one by one, the words, the Beans and XP, the cat's line, the buttons.
struct GamesResultCard: View {
    let title: String
    var subtitle: String?
    let stars: Int
    var showsStars = true
    let reward: GameSession.ArcadeReward?
    let catName: String
    var lines: [String] = []
    let buttons: [(title: String, prominent: Bool, action: () -> Void)]
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 10) {
            if showsStars {
                HStack(spacing: 6) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        PaintedIcon("xp_star", size: 50)
                            .opacity(shown > index ? 1 : 0.2)
                            .scaleEffect(shown > index ? 1 : 0.8)
                            .animation(.spring(duration: 0.35, bounce: 0.55), value: shown)
                    }
                }
            }
            Text(title).font(Theme.title(28))
            if let subtitle {
                Text(subtitle).font(.headline).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            }
            ForEach(lines, id: \.self) { line in
                Text(line).font(.subheadline).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            }
            if let reward {
                HStack(spacing: 16) {
                    if reward.beans > 0 {
                        Label { Text("+\(reward.beans)") } icon: { PaintedIcon("bean_coin", size: 24) }
                    }
                    if reward.xp > 0 {
                        Label { Text("+\(reward.xp) XP") } icon: { PaintedIcon("xp_star", size: 22) }
                    }
                }
                .font(.headline)
                if !reward.payout.challenges.isEmpty {
                    let words = GameSession.arcadeContent?.file.challenges ?? [:]
                    ForEach(reward.payout.challenges, id: \.self) { id in
                        Label { Text(words[id] ?? id) } icon: { PaintedIcon("objectives_clipboard_with_a_tick", size: 20) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GamesLook.green)
                    }
                }
                if let line = reward.line {
                    GreetingBubble(line, name: catName).frame(maxWidth: 420)
                }
            }
            HStack(spacing: 12) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    if button.prominent {
                        ChunkyButton(button.title, colour: GamesLook.green, action: button.action)
                    } else {
                        HUDButton(button.title, action: button.action)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 500)
        .goldCard(corner: 26)
        .foregroundStyle(Theme.ink)
        .task {
            for index in 0 ..< stars {
                try? await Task.sleep(for: .seconds(0.3))
                shown = index + 1
                Sound.play("ui_bean_chime", volume: Tuning.Sound.levelUp)
            }
            try? await Task.sleep(for: .seconds(0.25))
            Sound.play(stars > 0 ? "ui_streak_milestone" : "cat_meow_soft", volume: Tuning.Sound.levelUp)
        }
    }
}

/// The Games screens' frame: the paper, scaled to the screen, status bar and home indicator hidden.
struct GamesFrame<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = GamesLook.scale(proxy.size)
            ZStack {
                GamesPaper()
                content()
                    .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.controlFeedback, ControlFeedback { Sound.tap() })
    }
}
