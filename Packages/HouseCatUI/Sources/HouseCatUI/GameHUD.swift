import SwiftUI

/// The room's controls laid out as a builder game lays out its base (Josh, 18 Oct: the menu): the player's
/// plaque top left, the Beans and the streak as bars top right, the care actions as big round buttons along the
/// bottom, Decorate and the Shop as chunky buttons bottom right. Raised, with a darker lip under each, painted
/// icons, heavy rounded type; cream for most, gold for the shop.
public enum GameHUD {
    public static let gold = Color(red: 1, green: 0.84, blue: 0.42)
    public static let deepGold = Color(red: 0.84, green: 0.56, blue: 0.14)
    public static let green = Color(red: 0.4, green: 0.72, blue: 0.36)
    public static let lip = Color(red: 0.55, green: 0.4, blue: 0.32)
}

/// A raised button: a rounded square with a darker lip, the painted icon big and the word under it.
public struct GameButton: View {
    public enum Style {
        case cream
        case accent
        case gold
    }

    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let title: String
    private let icon: String?
    private let symbol: String?
    private let style: Style
    private let size: CGFloat
    private let badge: String?
    private let dot: Bool
    private let action: () -> Void

    /// `badge` is a small count or mark in the corner ("3", "✓"); `dot` a plain dot (something waits).
    /// `icon` is a painted icon's name; `symbol` an SF Symbol for what has no painting (the stairs).
    public init(
        _ title: String,
        icon: String? = nil,
        symbol: String? = nil,
        style: Style = .cream,
        size: CGFloat = 64,
        badge: String? = nil,
        dot: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.symbol = symbol
        self.style = style
        self.size = size
        self.badge = badge
        self.dot = dot
        self.action = action
    }

    private var fill: (top: Color, bottom: Color, lip: Color, text: Color) {
        switch style {
        case .cream: (Theme.cream, Color(red: 0.95, green: 0.88, blue: 0.78), GameHUD.lip.opacity(0.55), Theme.ink)
        case .accent: (Theme.accent.mix(with: .white, by: 0.2), Theme.accent, Theme.accent.mix(with: .black, by: 0.35), .white)
        case .gold: (
                GameHUD.gold,
                GameHUD.gold.mix(with: GameHUD.deepGold, by: 0.45),
                GameHUD.deepGold.mix(with: .black, by: 0.25),
                Theme.ink
            )
        }
    }

    public var body: some View {
        let s = size * scale
        let shape = RoundedRectangle(cornerRadius: s * 0.3, style: .continuous)
        Button {
            feedback.tap()
            action()
        } label: {
            // The word sits on a little plaque over the button's bottom edge (as the care buttons' do), so a long
            // one ("Decorate", "Upstairs") is never squeezed against the sides.
            VStack(spacing: -7 * scale) {
                Group {
                    if let icon {
                        PaintedIcon(icon, size: s * 0.72)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: s * 0.36, weight: .black))
                            .foregroundStyle(fill.text)
                            .frame(width: s * 0.72, height: s * 0.72)
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1.5)
                .offset(y: -s * 0.04)
                .frame(width: s, height: s)
                .background {
                    ZStack {
                        shape.fill(fill.lip).offset(y: 4 * scale)
                        shape.fill(LinearGradient(colors: [fill.top, fill.bottom], startPoint: .top, endPoint: .bottom))
                        shape.strokeBorder(.white.opacity(0.7), lineWidth: 1.5).padding(2)
                        shape.strokeBorder(GameHUD.lip.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: Theme.shadow, radius: 5 * scale, y: 4 * scale)
                }
                .overlay(alignment: .topTrailing) { corner(badge: badge, dot: dot, size: s) }
                Text(title)
                    .font(.system(size: max(10, min(13, size * 0.2)) * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 1.5 * scale)
                    .background(Capsule().fill(style == .gold ? GameHUD.gold : Theme.cream))
                    .overlay(Capsule().strokeBorder(GameHUD.lip.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.shadow, radius: 2, y: 1)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func corner(badge: String?, dot: Bool, size s: CGFloat) -> some View {
        if let badge {
            Text(badge)
                .font(.system(size: max(10, s * 0.2), weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * scale)
                .frame(minWidth: s * 0.34, minHeight: s * 0.34)
                .background(Capsule().fill(badge == "✓" ? GameHUD.green : Theme.accent))
                .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                .offset(x: s * 0.12, y: -s * 0.12)
        } else if dot {
            Circle().fill(Theme.accent).frame(width: s * 0.24, height: s * 0.24)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .offset(x: s * 0.08, y: -s * 0.08)
        }
    }
}

/// A big round care action (Feed, Play, Nap): a raised disc with the painted icon and its word on a plaque below.
public struct CareButton: View {
    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let title: String
    private let icon: String
    private let badge: String?
    private let lit: Bool
    private let action: () -> Void

    /// `lit` glows the disc (something to do now); `badge` as on `GameButton`.
    public init(_ title: String, icon: String, badge: String? = nil, lit: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.lit = lit
        self.action = action
    }

    public var body: some View {
        let s = 62 * scale
        Button {
            feedback.tap()
            action()
        } label: {
            VStack(spacing: -8 * scale) {
                ZStack {
                    Circle().fill(GameHUD.lip.opacity(0.55)).offset(y: 4 * scale)
                    Circle().fill(LinearGradient(
                        colors: lit ? [GameHUD.gold, GameHUD.gold.mix(with: GameHUD.deepGold, by: 0.4)] :
                            [Theme.cream, Color(red: 0.95, green: 0.88, blue: 0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1.5).padding(2)
                    PaintedIcon(icon, size: s * 0.66).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1.5)
                }
                .frame(width: s, height: s)
                .shadow(color: Theme.shadow, radius: 5 * scale, y: 4 * scale)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22 * scale, minHeight: 22 * scale)
                            .padding(.horizontal, 2)
                            .background(Capsule().fill(badge == "✓" ? GameHUD.green : Theme.accent))
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 4 * scale, y: -2 * scale)
                    }
                }
                Text(title)
                    .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(Theme.cream))
                    .overlay(Capsule().strokeBorder(GameHUD.lip.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.shadow, radius: 2, y: 1)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title + (badge.map { $0 == "✓" ? ", done today" : ", \($0) left" } ?? ""))
    }
}

/// The player's plaque, top left: the cat's head in a ring (its profile), the cat's name and the level's title, and
/// the level on a star with the XP bar (the road ahead), all inside one pill.
public struct PlayerBadge: View {
    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let portrait: Image?
    private let name: String
    private let title: String
    private let level: Int
    private let progress: Double
    private let onPortrait: () -> Void
    private let onLevel: () -> Void

    public init(
        portrait: Image?,
        name: String,
        title: String,
        level: Int,
        progress: Double,
        onPortrait: @escaping () -> Void,
        onLevel: @escaping () -> Void
    ) {
        self.portrait = portrait
        self.name = name
        self.title = title
        self.level = level
        self.progress = progress
        self.onPortrait = onPortrait
        self.onLevel = onLevel
    }

    public var body: some View {
        // One cream pill holding it all (Josh, 19 Oct: the ring and the level spilled over the plaque's edges): the
        // ring sits in its round left end, the name and title, then the level and the XP bar, the same height.
        let ring = 54 * scale
        let bar = 92 * scale
        HStack(spacing: 10 * scale) {
            Button {
                feedback.tap()
                onPortrait()
            } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom))
                    // A pale sky behind the cat, lightest round its head.
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.92, green: 0.96, blue: 0.97), Color(red: 0.76, green: 0.86, blue: 0.9)],
                            center: UnitPoint(x: 0.5, y: 0.35),
                            startRadius: 0,
                            endRadius: ring * 0.55
                        ))
                        .padding(3 * scale)
                    // The cat's head and shoulders (`Headshot`), the ears whole inside the ring.
                    (portrait ?? Image(systemName: "cat"))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: ring - 6 * scale, height: ring - 6 * scale)
                        .clipShape(Circle())
                }
                .frame(width: ring, height: ring)
                .shadow(color: Theme.shadow, radius: 1.5 * scale, y: 1 * scale)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(name), your cat")
            .tourTarget("profile")
            Button {
                feedback.tap()
                onLevel()
            } label: {
                VStack(alignment: .leading, spacing: 5 * scale) {
                    HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                        Text(name).font(.system(size: 16 * scale, weight: .heavy, design: .rounded)).lineLimit(1)
                        Text(title).font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    HStack(spacing: 6 * scale) {
                        // The level: the star and the number on a dark chip, the star inside it.
                        HStack(spacing: 3 * scale) {
                            PaintedIcon("xp_star", size: 15 * scale)
                            Text("\(level)")
                                .font(.system(size: 12 * scale, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .padding(.leading, 3 * scale)
                        .padding(.trailing, 7 * scale)
                        .frame(height: 19 * scale)
                        .background(Capsule().fill(Theme.ink.opacity(0.85)))
                        // The XP bar: how far into this level.
                        Capsule().fill(Theme.ink.opacity(0.12))
                            .frame(width: bar, height: 10 * scale)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(LinearGradient(colors: [GameHUD.gold, GameHUD.deepGold], startPoint: .top, endPoint: .bottom))
                                    .frame(width: bar * max(0.08, min(1, progress)))
                            }
                            .overlay(Capsule().strokeBorder(GameHUD.deepGold.opacity(0.5), lineWidth: 1))
                            .animation(.spring(duration: 0.6), value: progress)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.trailing, 16 * scale)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Level \(level), \(title), \(Int(progress * 100)) percent to the next. Shows the road ahead.")
        }
        .padding(5 * scale)
        .background(Capsule().fill(Theme.cream).shadow(color: Theme.shadow, radius: 4 * scale, y: 2 * scale))
        .overlay(Capsule().strokeBorder(GameHUD.lip.opacity(0.3), lineWidth: 1))
        // The room tour's card keeps below it.
        .tourTarget("plaque")
    }
}

/// A resource bar, top right: the painted icon over the bar's left end, the amount, and a green + when more can
/// be had (Beans).
public struct ResourceBar: View {
    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let icon: String
    private let value: String
    private let label: String
    private let plus: Bool
    private let action: () -> Void

    public init(icon: String, value: String, label: String, plus: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.value = value
        self.label = label
        self.plus = plus
        self.action = action
    }

    public var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            HStack(spacing: 6 * scale) {
                Text(value)
                    .font(.system(size: 16 * scale, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .frame(minWidth: 70 * scale, alignment: .trailing)
                if plus {
                    Image(systemName: "plus")
                        .font(.system(size: 12 * scale, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 22 * scale, height: 22 * scale)
                        .background(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).fill(GameHUD.green))
                        .overlay(RoundedRectangle(cornerRadius: 7 * scale, style: .continuous).strokeBorder(
                            .white.opacity(0.8),
                            lineWidth: 1.5
                        ))
                }
            }
            .padding(.leading, 30 * scale)
            .padding(.trailing, plus ? 4 * scale : 12 * scale)
            .frame(height: 30 * scale)
            .background(Capsule().fill(Theme.cream).shadow(color: Theme.shadow, radius: 3 * scale, y: 2 * scale))
            .overlay(Capsule().strokeBorder(GameHUD.lip.opacity(0.3), lineWidth: 1))
            .overlay(alignment: .leading) {
                PaintedIcon(icon, size: 40 * scale)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1.5)
                    .offset(x: -14 * scale)
            }
            .padding(.leading, 14 * scale)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

public extension View {
    /// Drawn `scale` times larger as a whole (an iPad's `hudScale`): laid out in a space `scale` times smaller, then
    /// enlarged, so a card drawn for a phone on its side keeps its words, pictures, padding and corners in proportion.
    /// The controls inside draw at scale 1 (the zoom enlarges them).
    func zoomed(_ scale: CGFloat) -> some View {
        Zoom(scale: scale) { environment(\.hudScale, 1).scaleEffect(scale) }
    }

    /// A sheet's content `zoomed` and the sheet `size` (an iPad's); without a size the sheet is the system's own.
    @ViewBuilder
    func zoomedSheet(_ scale: CGFloat, size: CGSize?) -> some View {
        if let size {
            zoomed(scale).presentationSizing(SheetSize(size: size))
        } else {
            self
        }
    }
}

/// Lays its content out in a space `scale` times smaller and takes `scale` times its size (the content enlarges itself).
private struct Zoom: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(inside(proposal)) }
        return CGSize(width: (sizes.map(\.width).max() ?? 0) * scale, height: (sizes.map(\.height).max() ?? 0) * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: inside(proposal))
        }
    }

    private func inside(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { $0 / scale }, height: proposal.height.map { $0 / scale })
    }
}

/// A sheet of a set size.
private struct SheetSize: PresentationSizing {
    let size: CGSize

    func proposedSize(for _: PresentationSizingRoot, context _: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(size)
    }
}
