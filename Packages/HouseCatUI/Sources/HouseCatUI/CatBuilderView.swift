import HouseCatCore
import HouseCatGame
import SpriteKit
import SwiftUI

/// The cat creator (SPEC "Cat builder"; onboarding's cat, and Edit look from the profile), a dressing room (Josh,
/// 19 Oct: "a design wardrobe kind of creation"): the cat on a podium in front of an open wardrobe, a chest of
/// painted drawers down the left (one for each part of the look), and the open drawer on the right with the
/// options, each drawn from the cat itself. Undo and Surprise me sit under the cat. Landscape on a phone, scaled up
/// to fill an iPad, and stacked on an iPad held upright.
public struct CatBuilderView<Hint: View>: View {
    @Bindable private var model: CatBuilderModel
    private let hint: Hint
    private let done: (CatBuilderModel) -> Void
    private let cancel: (() -> Void)?
    /// Laid out for a landscape phone and scaled to the screen, like the shop.
    @State private var s: CGFloat = 1
    @State private var sceneOrigin: CGPoint = .zero
    @State private var stageFrame: CGRect = .zero
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 100
    @Environment(\.controlFeedback) private var feedback

    /// `hint` floats over the top of the screen (the host's line during the intro).
    public init(
        model: CatBuilderModel,
        cancel: (() -> Void)? = nil,
        @ViewBuilder hint: () -> Hint,
        done: @escaping (CatBuilderModel) -> Void
    ) {
        self.model = model
        self.cancel = cancel
        self.hint = hint()
        self.done = done
    }

    public var body: some View {
        GeometryReader { proxy in
            let screen = CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            let upright = screen.height > screen.width
            Group {
                if upright {
                    uprightLayout(proxy.size)
                } else {
                    landscapeLayout
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
        .background(page.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .environment(\.hudScale, s)
        .modifier(FullScreenGame())
        .onChange(of: stageFrame) { _, _ in tellStage() }
        .onChange(of: sceneOrigin) { _, _ in tellStage() }
    }

    private var page: LinearGradient {
        LinearGradient(colors: [Theme.paper, Color(red: 0.95, green: 0.84, blue: 0.74)], startPoint: .top, endPoint: .bottom)
    }

    /// Text sizes grow with the player's text size.
    private var t: CGFloat {
        s * textScale / 100
    }

    /// The part of the room the controls leave open, for the scene to put the cat in the middle of.
    private func tellStage() {
        guard stageFrame.width > 1 else { return }
        model.preview?.setOpenRect(stageFrame.offsetBy(dx: -sceneOrigin.x, dy: -sceneOrigin.y))
    }

    // MARK: Layouts

    /// Side by side: the drawers, the cat, the open drawer; the room fills the whole screen behind them.
    private var landscapeLayout: some View {
        ZStack {
            room.ignoresSafeArea()
            HStack(alignment: .top, spacing: 10 * s) {
                drawers
                    .frame(width: 142 * s)
                stage
                panel
                    .frame(width: 368 * s)
            }
            .padding(.horizontal, 10 * s)
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
                drawers
                    .frame(width: 168 * s)
                panel
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
        if let scene = model.preview {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { sceneOrigin = $0 }
                .accessibilityElement()
                .accessibilityLabel(lookDescription)
                .accessibilityHint("Swipe up or down to turn the cat round.")
                .accessibilityAdjustableAction { direction in
                    model.preview?.turn(by: direction == .increment ? 1 : -1)
                }
        } else {
            page
        }
    }

    /// The open space over the podium: the look's name above the cat, Undo and Surprise me under it, and the gap
    /// between them, where the scene puts the cat.
    private var stage: some View {
        VStack(spacing: 8 * s) {
            HStack(alignment: .top, spacing: 8 * s) {
                if let cancel {
                    CloseButton(action: cancel)
                        .scaleEffect(s, anchor: .topLeading)
                        .frame(width: 36 * s, height: 36 * s, alignment: .topLeading)
                }
                Spacer(minLength: 0)
                nameplate
                Spacer(minLength: 0)
                if cancel != nil {
                    Color.clear.frame(width: 36 * s, height: 1)
                }
            }
            // The gap the cat stands in, between the nameplate and the buttons.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { stageFrame = $0 }
            HStack(spacing: 8 * s) {
                HUDButton("Undo", symbol: "arrow.uturn.backward") { model.undo() }
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.45)
                HUDButton("Surprise me", icon: "creator_dice") { model.surprise() }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The look's name on a little paper plaque: the preset it is, or the player's own.
    private var nameplate: some View {
        let preset = model.presetID.flatMap(model.builder.preset)?.name
        let named = model.mode == .adopt ? model.checkedName : nil
        return VStack(spacing: 0) {
            Text(named ?? preset ?? "Your own look")
                .font(Theme.title(17 * t))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if named != nil, let preset {
                Text(preset).font(.system(size: 11 * t, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 5 * s)
        .paper(Capsule())
        .accessibilityElement(children: .combine)
        .animation(.easeOut(duration: 0.2), value: model.presetID)
    }

    // MARK: The drawers

    /// A chest of drawers, one for each part of the look; the open one is pulled out.
    private var drawers: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4 * s) {
                ForEach(model.sections) { section in
                    Button {
                        feedback.tap()
                        withAnimation(.spring(duration: 0.3)) { model.section = section }
                    } label: {
                        drawer(section, open: model.section == section)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(section.title)
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
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

    private func drawer(_ section: CatBuilderModel.Section, open: Bool) -> some View {
        HStack(spacing: 6 * s) {
            PaintedIcon(section.icon, size: 26 * s)
            Text(section.title)
                .font(.system(size: 14 * t, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.55)
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

    // MARK: The open drawer

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8 * s) {
                PaintedIcon(model.section.icon, size: 34 * s)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.section.heading)
                        .font(Theme.title(20 * t))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12 * t, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 8 * s)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Theme.rim).frame(height: 1)
            ScrollViewReader { reader in
                ScrollView {
                    CatBuilderDrawer(model: model, s: s, t: t)
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 10 * s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(model.section)
                }
                .onChange(of: model.section) { _, section in reader.scrollTo(section, anchor: .top) }
            }
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 20 * s, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cream, Theme.paper], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).strokeBorder(Theme.cream, lineWidth: 3 * s))
        .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .continuous))
        .shadow(color: Theme.shadow, radius: 10 * s, y: 5 * s)
    }

    /// What the open drawer has chosen, under its heading.
    private var subtitle: String? {
        let data = model.builder.data
        let look = model.look
        func label(_ colour: LookColour, _ palette: [CatBuilderData.Swatch]) -> String {
            if case let .named(id) = colour {
                return palette.first { $0.id == id }?.label ?? id
            }
            return "Your own colour"
        }
        switch model.section {
        case .looks: return "\(data.presets.count) looks to start from, every one free"
        case .body: return model.kind
            .map { kind in kind.hasWeight ? "\(kind.label), \(look.weight < 0.5 ? "slim" : "chunky")" : kind.label }
        case .coat: return label(look.coat, data.coats)
        case .pattern:
            guard let pattern = look.pattern else { return "Solid" }
            let name = data.patterns.first { $0.id == pattern }?.label ?? pattern
            return look.patternColour.map { "\(name) in \(label($0, data.coats).lowercased())" } ?? name
        case .white: return data.whites.first { $0.id == (look.white ?? "none") }?.label
        case .eyes:
            return look.hasOddEyes
                ? "\(label(look.eyeLeft, data.eyes)) and \(label(look.eyeRight, data.eyes).lowercased())"
                : label(look.eyeLeft, data.eyes)
        case .nose: return label(look.nose, data.noses)
        case .earsTail:
            guard model.body?.earSwaps == true || model.body?.tailSwaps == true else { return "A breed keeps its own" }
            let ears = look.ears == "own" ? "Pointed ears" : (data.ears.first { $0.id == look.ears }?.label ?? look.ears)
            return look.tail == "bobtail" ? "\(ears), bobtail" : ears
        case .age:
            if case let .adult(years) = look.age {
                return "\(years) \(years == 1 ? "year" : "years") old"
            }
            return "A kitten"
        case .name: return model.checkedName.map { "\($0), \(ProfileText.personality(model.personality).lowercased())" }
        }
    }

    /// Back and Next through the drawers, and Done (or, adopting, bringing the cat home from the last one).
    private var footer: some View {
        HStack(spacing: 8 * s) {
            if let previous = model.previousSection {
                Button {
                    feedback.tap()
                    withAnimation(.spring(duration: 0.3)) { model.section = previous }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16 * s, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40 * s, height: 40 * s)
                        .paper(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back: \(previous.title)")
            }
            Spacer(minLength: 0)
            if let next = model.nextSection {
                HUDButton("Next: \(next.title)", symbol: "chevron.right") {
                    withAnimation(.spring(duration: 0.3)) { model.section = next }
                }
            }
            if model.mode == .edit {
                ChunkyButton("Done") { done(model) }
                    .fixedSize()
            } else if model.section == .name {
                ChunkyButton(model.checkedName.map { "Bring \($0) home" } ?? "Bring them home") { done(model) }
                    .fixedSize()
                    .disabled(!model.canAdopt)
                    .opacity(model.canAdopt ? 1 : 0.5)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 10 * s)
        .padding(.vertical, 8 * s)
        .background(Theme.paper.opacity(0.6))
    }

    /// The look in words, for VoiceOver.
    private var lookDescription: String {
        let data = model.builder.data
        let look = model.look
        func label(_ colour: LookColour, _ palette: [CatBuilderData.Swatch]) -> String {
            if case let .named(id) = colour {
                return (palette.first { $0.id == id }?.label ?? id).lowercased()
            }
            return "own colour"
        }
        var words = [label(look.coat, data.coats)]
        if let pattern = look.pattern, let name = data.patterns.first(where: { $0.id == pattern })?.label {
            words.append(name.lowercased())
        }
        words.append(model.kind?.label.lowercased() ?? "cat")
        var text = words.joined(separator: " ")
        if let white = look.white, let name = data.whites.first(where: { $0.id == white })?.label {
            text += ", white: \(name.lowercased())"
        }
        text += look.hasOddEyes
            ? ", odd eyes, \(label(look.eyeLeft, data.eyes)) and \(label(look.eyeRight, data.eyes))"
            : ", \(label(look.eyeLeft, data.eyes)) eyes"
        if look.age.isKitten {
            text = "Kitten, " + text
        }
        return "Your cat on the podium: " + text
    }
}

public extension CatBuilderView where Hint == EmptyView {
    init(model: CatBuilderModel, cancel: (() -> Void)? = nil, done: @escaping (CatBuilderModel) -> Void) {
        self.init(model: model, cancel: cancel, hint: { EmptyView() }, done: done)
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
