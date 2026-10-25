import HouseCatCore
import HouseCatGame
import SpriteKit
import SwiftUI

/// The sizes the dressing room's controls are drawn at: the layout's scale (a landscape phone is 1, an iPad up to
/// `Tuning.Builder.largestScale`) and the text's, which grows with the player's text size too.
public struct WardrobeMetrics: Equatable, Sendable {
    public let s: CGFloat
    public let t: CGFloat
}

/// A drawer's picture: one of the painted icons, or a painting from the game's art (an outfit).
public enum DrawerIcon {
    case painted(String)
    case picture(Image?)

    @ViewBuilder
    func view(size: CGFloat) -> some View {
        switch self {
        case let .painted(name): PaintedIcon(name, size: size)
        case let .picture(image):
            Group {
                if let image {
                    image.resizable().interpolation(.high).scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

/// One drawer in the chest down the left.
public struct WardrobeDrawer: Identifiable {
    public let id: String
    public let title: String
    public let icon: DrawerIcon

    public init(id: String, title: String, icon: DrawerIcon) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

/// The dressing room the cat creator and the outfit catalogue share (Josh, 19 Oct): the painted room with the cat on
/// its podium (`DressingRoomScene`) filling the screen, a chest of honey-oak drawers down the left with the open one
/// pulled out, the cat in the middle between a row of controls above it and one below, and the open drawer on the
/// right as a paper card. Drawn for a landscape phone and scaled to the screen like the shop; an iPad held upright
/// has the room on top and the drawers under it. The status bar and home indicator are hidden, as in the room.
public struct DressingRoomLayout<Top: View, Bottom: View, Panel: View, Hint: View>: View {
    private let scene: DressingRoomScene?
    private let sceneLabel: String
    private let drawers: [WardrobeDrawer]
    private let open: String
    private let choose: (String) -> Void
    private let top: (WardrobeMetrics) -> Top
    private let bottom: (WardrobeMetrics) -> Bottom
    private let panel: (WardrobeMetrics) -> Panel
    private let hint: Hint
    @State private var s: CGFloat = 1
    @State private var sceneFrame: CGRect = .zero
    @State private var stageFrame: CGRect = .zero
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 100
    @Environment(\.controlFeedback) private var feedback

    /// `sceneLabel` is the cat in words for VoiceOver (which turns it round the podium with a swipe up or down);
    /// `open` is the open drawer's id; `hint` floats over the top until it is dismissed (the host's line).
    public init(
        scene: DressingRoomScene?,
        sceneLabel: String,
        drawers: [WardrobeDrawer],
        open: String,
        choose: @escaping (String) -> Void,
        @ViewBuilder top: @escaping (WardrobeMetrics) -> Top,
        @ViewBuilder bottom: @escaping (WardrobeMetrics) -> Bottom,
        @ViewBuilder panel: @escaping (WardrobeMetrics) -> Panel,
        @ViewBuilder hint: () -> Hint
    ) {
        self.scene = scene
        self.sceneLabel = sceneLabel
        self.drawers = drawers
        self.open = open
        self.choose = choose
        self.top = top
        self.bottom = bottom
        self.panel = panel
        self.hint = hint()
    }

    public var body: some View {
        GeometryReader { proxy in
            let screen = CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            Group {
                if screen.height > screen.width {
                    uprightLayout(proxy.size)
                } else {
                    landscapeLayout(CameraClearance(proxy, edge: 10 * s))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: screen, initial: true) { _, screen in
                let fit = screen.height > screen.width
                    ? min(screen.width / Tuning.Builder.designUprightWidth, screen.height / (Tuning.Builder.designHeight * 2.2))
                    : min(screen.height / Tuning.Builder.designHeight, screen.width / Tuning.Builder.designWidth)
                s = (min(Tuning.Builder.largestScale, max(1, fit)) * 20).rounded(.down) / 20
            }
        }
        .background(Self.page.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .environment(\.hudScale, s)
        .modifier(FullScreenGame())
        .onChange(of: stageFrame) { _, _ in tellStage() }
        .onChange(of: sceneFrame) { _, _ in tellStage() }
    }

    static var page: LinearGradient {
        LinearGradient(colors: [Theme.paper, Color(red: 0.95, green: 0.84, blue: 0.74)], startPoint: .top, endPoint: .bottom)
    }

    private var metrics: WardrobeMetrics {
        WardrobeMetrics(s: s, t: s * textScale / 100)
    }

    /// The part of the room the controls leave open, for the scene to put the cat in the middle of: measured
    /// against the room's own frame each time either moves (turning an iPad changes both).
    private func tellStage() {
        guard stageFrame.width > 1, sceneFrame.width > 1 else { return }
        scene?.setOpenRect(stageFrame.offsetBy(dx: -sceneFrame.minX, dy: -sceneFrame.minY))
    }

    // MARK: Layouts

    /// Side by side: the drawers, the cat, the open drawer; the room fills the whole screen behind them.
    /// The drawers and the open drawer run the screen's height, so either moves in past a camera at its side (iPhone
    /// Duo's outer screen).
    private func landscapeLayout(_ camera: CameraClearance) -> some View {
        ZStack {
            room.ignoresSafeArea()
            HStack(alignment: .top, spacing: 10 * s) {
                chest
                    .frame(width: 142 * s)
                stage
                panel(metrics)
                    .frame(width: 368 * s)
            }
            .padding(.leading, 10 * s + camera.leading)
            .padding(.trailing, 10 * s + camera.trailing)
            .padding(.vertical, 8 * s)
        }
        // The host's line floats over the top, across the cat and the open drawer, until it is dismissed.
        .overlay(alignment: .top) {
            hint.frame(maxWidth: 400).zoomed(s).padding(.top, 8 * s)
        }
    }

    /// Stacked, for an iPad held upright: the room and the cat on top, the drawers and the open drawer under it.
    private func uprightLayout(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                room
                stage.padding(12 * s)
            }
            .frame(height: size.height * 0.44)
            .clipped()
            .ignoresSafeArea(edges: .top)
            HStack(alignment: .top, spacing: 12 * s) {
                chest
                    .frame(width: 168 * s)
                panel(metrics)
            }
            .padding(12 * s)
        }
        // The host's line on the seam between the room and the drawers, clear of the cat.
        .overlay(alignment: .top) {
            hint.frame(maxWidth: 440).zoomed(s).padding(.top, size.height * 0.44 - 90 * s)
        }
    }

    /// The painted dressing room with the cat on its podium.
    @ViewBuilder
    private var room: some View {
        if let scene {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sceneFrame = $0 }
                .accessibilityElement()
                .accessibilityLabel(sceneLabel)
                .accessibilityHint("Swipe up or down to turn the cat round.")
                .accessibilityAdjustableAction { direction in
                    scene.turn(by: direction == .increment ? 1 : -1)
                }
        } else {
            Self.page
        }
    }

    /// The open space over the podium: a row of controls above the cat and one under it, and the gap between them,
    /// where the scene puts the cat.
    private var stage: some View {
        VStack(spacing: 8 * s) {
            top(metrics)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { stageFrame = $0 }
            bottom(metrics)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The chest of drawers

    /// One drawer for each part; the open one is pulled out.
    private var chest: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4 * s) {
                ForEach(drawers) { drawer in
                    Button {
                        feedback.tap()
                        withAnimation(.spring(duration: 0.3)) { choose(drawer.id) }
                    } label: {
                        front(drawer, open: open == drawer.id)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(drawer.title)
                    .accessibilityAddTraits(open == drawer.id ? .isSelected : [])
                }
            }
            .padding(5 * s)
            .padding(.trailing, 8 * s)
            .background(alignment: .leading) {
                // The chest itself, behind the drawers.
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .fill(Wood.carcass)
                    .overlay(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).strokeBorder(Wood.edge, lineWidth: 1.5))
                    .padding(.trailing, 8 * s)
                    .shadow(color: Theme.shadow, radius: 8 * s, y: 4 * s)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
    }

    private func front(_ drawer: WardrobeDrawer, open: Bool) -> some View {
        HStack(spacing: 6 * s) {
            drawer.icon.view(size: 26 * s)
            Text(drawer.title)
                .font(.system(size: 14 * metrics.t, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(open ? Theme.ink : Wood.label)
                .shadow(color: open ? .clear : .black.opacity(0.3), radius: 0, y: 1)
            Spacer(minLength: 0)
            Wood.knob(size: 8 * s)
        }
        .padding(.leading, 6 * s)
        .padding(.trailing, 8 * s)
        .padding(.vertical, 3 * s)
        .frame(minHeight: 30 * s)
        .background(Wood.front(open: open, corner: 8 * s, scale: s))
        .offset(x: open ? 8 * s : 0)
        .animation(.spring(duration: 0.3), value: open)
    }
}

public extension DressingRoomLayout where Hint == EmptyView {
    init(
        scene: DressingRoomScene?,
        sceneLabel: String,
        drawers: [WardrobeDrawer],
        open: String,
        choose: @escaping (String) -> Void,
        @ViewBuilder top: @escaping (WardrobeMetrics) -> Top,
        @ViewBuilder bottom: @escaping (WardrobeMetrics) -> Bottom,
        @ViewBuilder panel: @escaping (WardrobeMetrics) -> Panel
    ) {
        self.init(
            scene: scene, sceneLabel: sceneLabel, drawers: drawers, open: open, choose: choose,
            top: top, bottom: bottom, panel: panel, hint: { EmptyView() }
        )
    }
}

/// The open drawer: a paper card with its icon, heading and what is chosen (and something at the header's end, such as
/// the Beans), the options scrolling under a hairline, and a row of buttons at its foot.
public struct DrawerPanel<Content: View, Footer: View, Accessory: View, ScrollID: Hashable>: View {
    private let icon: DrawerIcon
    private let heading: String
    private let subtitle: String?
    private let metrics: WardrobeMetrics
    private let scrollID: ScrollID
    private let content: Content
    private let footer: Footer
    private let accessory: Accessory

    /// The options scroll back to the top whenever `scrollID` changes (another drawer opened).
    public init(
        icon: DrawerIcon,
        heading: String,
        subtitle: String?,
        metrics: WardrobeMetrics,
        scrollID: ScrollID,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.heading = heading
        self.subtitle = subtitle
        self.metrics = metrics
        self.scrollID = scrollID
        self.content = content()
        self.footer = footer()
        self.accessory = accessory()
    }

    public var body: some View {
        let s = metrics.s
        let shape = RoundedRectangle(cornerRadius: 20 * s, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 8 * s) {
                icon.view(size: 34 * s)
                VStack(alignment: .leading, spacing: 0) {
                    Text(heading)
                        .font(Theme.title(20 * metrics.t))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12 * metrics.t, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                accessory
            }
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 8 * s)
            Rectangle().fill(Theme.rim).frame(height: 1)
            ScrollViewReader { reader in
                ScrollView {
                    content
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 10 * s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(scrollID)
                }
                .onChange(of: scrollID) { _, id in reader.scrollTo(id, anchor: .top) }
            }
            footer
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10 * s)
                .padding(.vertical, 8 * s)
                .frame(maxWidth: .infinity)
                .background(Theme.paper.opacity(0.6))
        }
        .background(shape.fill(LinearGradient(colors: [Theme.cream, Theme.paper], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(Theme.cream, lineWidth: 3 * s))
        .overlay(shape.strokeBorder(Theme.rim, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: Theme.shadow, radius: 10 * s, y: 5 * s)
    }
}

public extension DrawerPanel where Accessory == EmptyView {
    init(
        icon: DrawerIcon,
        heading: String,
        subtitle: String?,
        metrics: WardrobeMetrics,
        scrollID: ScrollID,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(
            icon: icon, heading: heading, subtitle: subtitle, metrics: metrics, scrollID: scrollID,
            content: content, footer: footer, accessory: { EmptyView() }
        )
    }
}

/// A name on a little paper plaque above the cat, with a smaller line under it.
public struct Nameplate: View {
    private let title: String
    private let subtitle: String?
    private let metrics: WardrobeMetrics

    public init(_ title: String, subtitle: String? = nil, metrics: WardrobeMetrics) {
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Theme.title(17 * metrics.t))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle).font(.system(size: 11 * metrics.t, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
        }
        .padding(.horizontal, 14 * metrics.s)
        .padding(.vertical, 5 * metrics.s)
        .paper(Capsule())
        .accessibilityElement(children: .combine)
        .animation(.easeOut(duration: 0.2), value: title)
    }
}

/// A round paper button with an arrow (Back through the drawers).
public struct RoundPaperButton: View {
    private let symbol: String
    private let label: String
    private let size: CGFloat
    private let action: () -> Void
    @Environment(\.controlFeedback) private var feedback

    public init(symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .paper(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// The status bar and the home indicator hidden, as in the room.
private struct FullScreenGame: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.statusBarHidden().persistentSystemOverlays(.hidden)
        #else
            content
        #endif
    }
}

/// The chest of drawers' honey oak, as in the painted wardrobe.
enum Wood {
    static let carcass = LinearGradient(
        colors: [Color(red: 0.62, green: 0.38, blue: 0.2), Color(red: 0.5, green: 0.29, blue: 0.15)],
        startPoint: .top, endPoint: .bottom
    )
    static let edge = Color(red: 0.36, green: 0.2, blue: 0.1).opacity(0.7)
    static let label = Color(red: 1, green: 0.95, blue: 0.86)

    static func front(open: Bool, corner: CGFloat, scale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let colours = open
            ? [Color(red: 1, green: 0.95, blue: 0.86), Color(red: 0.97, green: 0.88, blue: 0.74)]
            : [Color(red: 0.86, green: 0.6, blue: 0.34), Color(red: 0.74, green: 0.48, blue: 0.25)]
        return shape
            .fill(LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom))
            .overlay(shape.inset(by: 3 * scale).strokeBorder(.white.opacity(open ? 0.5 : 0.18), lineWidth: 1))
            .overlay(shape.strokeBorder(open ? Theme.accent : edge, lineWidth: open ? 2 : 1))
            .shadow(
                color: .black.opacity(open ? 0.28 : 0.18),
                radius: open ? 5 * scale : 1.5 * scale,
                x: open ? 3 * scale : 0,
                y: 2 * scale
            )
    }

    /// A round brass knob.
    static func knob(size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(red: 1, green: 0.92, blue: 0.62), Color(red: 0.78, green: 0.56, blue: 0.2)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7
            ))
            .overlay(Circle().strokeBorder(Color(red: 0.45, green: 0.3, blue: 0.1).opacity(0.6), lineWidth: 0.75))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.5)
    }
}
