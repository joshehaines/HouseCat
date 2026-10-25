import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// The look of the game's controls (STYLE.md: painterly, warm, adult; no bubble fonts, no stickers): cream
/// paper controls with a soft shadow over the painted world, plum-brown ink, the painted icons from
/// assets/ui, a serif for titles.
public enum Theme {
    public static let cream = Color(red: 0.995, green: 0.97, blue: 0.925)
    public static let paper = Color(red: 0.975, green: 0.935, blue: 0.87)
    public static let ink = Color(red: 0.24, green: 0.18, blue: 0.22)
    public static let inkSoft = Color(red: 0.24, green: 0.18, blue: 0.22).opacity(0.62)
    public static let accent = Color(red: 0.89, green: 0.5, blue: 0.2)
    public static let rim = Color(red: 0.6, green: 0.45, blue: 0.38).opacity(0.22)
    public static let shadow = Color(red: 0.25, green: 0.12, blue: 0.08).opacity(0.22)

    /// Titles: the serif, bold.
    public static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

public extension EnvironmentValues {
    @Entry var hudScale: CGFloat = 1
}

/// What a control does when pressed, besides its action (the app plays a tap and a haptic tick).
public struct ControlFeedback: Sendable {
    public var tap: @MainActor @Sendable () -> Void

    public init(tap: @escaping @MainActor @Sendable () -> Void) {
        self.tap = tap
    }
}

public extension EnvironmentValues {
    @Entry var controlFeedback: ControlFeedback = ControlFeedback {}
}

/// One of the painted icons (App/Art/ui/icon_<name>.png): "feed_bowl", "shop_bag", "xp_star"...
public struct PaintedIcon: View {
    private let name: String
    private let size: CGFloat

    public init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = Self.image(name) {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: Image] = [:]

    @MainActor static func image(_ name: String) -> Image? {
        if let cached = cache[name] {
            return cached
        }
        #if canImport(UIKit)
            guard let url = Bundle.main.url(forResource: "Art/ui/icon_\(name).png", withExtension: nil),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            let loaded = Image(uiImage: image)
        #else
            guard let url = Bundle.main.url(forResource: "Art/ui/icon_\(name).png", withExtension: nil),
                  let image = NSImage(contentsOf: url) else { return nil }
            let loaded = Image(nsImage: image)
        #endif
        cache[name] = loaded
        return loaded
    }
}

/// The paper behind a control: cream, a hairline rim, a soft warm shadow.
struct PaperBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill = Theme.cream

    func body(content: Content) -> some View {
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.rim, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 6, y: 3)
    }
}

public extension View {
    /// A control's cream paper in a capsule, a circle or a rounded rectangle.
    func paper(_ shape: some InsettableShape, fill: Color = Theme.cream) -> some View {
        modifier(PaperBackground(shape: shape, fill: fill))
    }
}

/// A capsule control: a painted icon (or a symbol) and a word.
public struct HUDButton: View {
    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let title: String
    private let icon: String?
    private let symbol: String?
    private let prominent: Bool
    private let action: () -> Void

    /// `icon` is a painted icon's name; `symbol` an SF Symbol for the actions with no painting (Turn, Done). An empty
    /// `title` draws the picture alone (give it an accessibility label).
    public init(_ title: String, icon: String? = nil, symbol: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.symbol = symbol
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            HStack(spacing: 6 * scale) {
                if let icon {
                    PaintedIcon(icon, size: 30 * scale)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17 * scale, weight: .bold))
                        .frame(width: 24 * scale, height: 30 * scale)
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 16 * scale, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(prominent ? Color.white : Theme.ink)
            .padding(.leading, (icon == nil ? 14 : 8) * scale)
            .padding(.trailing, (title.isEmpty ? 8 : 16) * scale)
            .padding(.vertical, 5 * scale)
            .paper(Capsule(), fill: prominent ? Theme.accent : Theme.cream)
        }
        .buttonStyle(PressStyle())
    }
}

/// Controls sink a little when pressed.
public struct PressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// A short note over the room ("Jingle ball · +20 Beans", "Level 3"), with its painted icon.
public struct Toast: View {
    @Environment(\.hudScale) private var scale
    private let text: String
    private let icon: String?

    public init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 8 * scale) {
            if let icon {
                PaintedIcon(icon, size: 30 * scale)
            }
            Text(text).font(.system(size: 17 * scale, weight: .bold)).foregroundStyle(Theme.ink)
        }
        .padding(.leading, (icon == nil ? 18 : 10) * scale)
        .padding(.trailing, 18 * scale)
        .padding(.vertical, 7 * scale)
        .paper(Capsule())
    }
}

/// Closes a sheet: a cream disc with a cross.
public struct CloseButton: View {
    @Environment(\.controlFeedback) private var feedback
    private let scale: CGFloat
    private let action: () -> Void

    /// `scale` draws it that much larger with real metrics (the cross's font and the disc), never a stretched layer.
    public init(scale: CGFloat = 1, action: @escaping () -> Void) {
        self.scale = scale
        self.action = action
    }

    public var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36 * scale, height: 36 * scale)
                .paper(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close")
    }
}

/// A chunky shop button, as in a builder game's shop: a raised capsule with a darker lip under it.
public struct ChunkyButton: View {
    @Environment(\.hudScale) private var scale
    @Environment(\.controlFeedback) private var feedback
    private let title: String
    private let subtitle: String?
    private let colour: Color
    private let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, colour: Color = Theme.accent, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.colour = colour
        self.action = action
    }

    public var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 18 * scale, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11 * scale, weight: .bold, design: .rounded)).opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .padding(.horizontal, 22 * scale)
            .padding(.vertical, (subtitle == nil ? 11 : 7) * scale)
            .frame(minWidth: 120 * scale)
            .background {
                ZStack {
                    Capsule().fill(colour.mix(with: .black, by: 0.3)).offset(y: 4 * scale)
                    Capsule().fill(LinearGradient(
                        colors: [colour.mix(with: .white, by: 0.18), colour],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(1)
                }
            }
        }
        .buttonStyle(PressStyle())
    }
}

/// A ribbon across a tile's corner ("Best value", "Once only"): only ever true things, never a countdown.
public struct Ribbon: View {
    @Environment(\.hudScale) private var scale
    private let text: String
    private let colour: Color

    public init(_ text: String, colour: Color = Color(red: 0.92, green: 0.68, blue: 0.18)) {
        self.text = text
        self.colour = colour
    }

    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 4 * scale)
            .background(Capsule().fill(colour))
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}
