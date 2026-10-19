import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The game's painted card (Josh, 19 Oct: the room menu and the cat's profile were plain next to the shop's Cat Club
/// page and the reminders card): cream paper with a painted grain, a gold rim, and a warm header band with the
/// card's badge and its title in the serif. The room menu and the profile are drawn on it.
public struct PaintedPanel<Header: View, Content: View>: View {
    private let corner: CGFloat
    private let header: Header
    private let content: Content

    public init(corner: CGFloat = 26, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PanelBand())
            content
        }
        .background(PanelPaper())
        .clipShape(shape)
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom),
            lineWidth: 4
        ))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

/// The warm band across a panel's top: terracotta into gold, with the paper's grain through it.
public struct PanelBand: View {
    public init() {}

    public var body: some View {
        LinearGradient(colors: [Theme.accent, GameHUD.deepGold], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay { PanelPaper().blendMode(.multiply).opacity(0.35) }
    }
}

/// The cream paper the panels are printed on (assets/ui/profile/panel_paper.jpg): a soft painted grain, never a
/// flat white.
public struct PanelPaper: View {
    public init() {}

    public var body: some View {
        if let paper = Self.image {
            paper.resizable().interpolation(.medium).scaledToFill()
        } else {
            Theme.cream
        }
    }

    @MainActor private static let image: Image? = {
        guard let url = Bundle.main.url(forResource: "Art/ui/profile/panel_paper.jpg", withExtension: nil) else { return nil }
        #if canImport(UIKit)
            return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #else
            return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #endif
    }()
}

/// A chunky square button, as a builder game lays out its menu: a cream tile on a darker lip, a big painted icon, the
/// word under it, and a red mark when something waits there.
public struct ChunkyTile: View {
    @Environment(\.controlFeedback) private var feedback
    private let title: String
    private let icon: String
    private let waiting: Bool
    private let action: () -> Void

    public init(_ title: String, icon: String, waiting: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.waiting = waiting
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button {
            feedback.tap()
            action()
        } label: {
            VStack(spacing: 1) {
                PaintedIcon(icon, size: 42)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1.5)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
            .frame(width: 80, height: 76)
            .background {
                ZStack {
                    shape.fill(Color(red: 0.79, green: 0.65, blue: 0.49)).offset(y: 4)
                    shape.fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.99, blue: 0.97), Color(red: 0.96, green: 0.9, blue: 0.81)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    shape.strokeBorder(Theme.rim, lineWidth: 1)
                }
                .shadow(color: Theme.shadow, radius: 4, y: 4)
            }
            .overlay(alignment: .topTrailing) {
                if waiting {
                    WaitingMark().offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title + (waiting ? ", something waiting" : ""))
    }
}

/// The red "!" on a control with something waiting behind it.
public struct WaitingMark: View {
    public init() {}

    public var body: some View {
        Text("!")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(red: 0.9, green: 0.33, blue: 0.23)))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}
