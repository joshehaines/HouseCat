import HouseCatCore
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// One option in a drawer: its picture (the cat wearing it) over its name on a paper card; the chosen one is ringed
/// and ticked. A look from the hanger rail hangs from a little wooden hanger.
struct OptionCard<Picture: View>: View {
    let title: String
    let selected: Bool
    var hanger = false
    let s: CGFloat
    let t: CGFloat
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            VStack(spacing: 3 * s) {
                picture()
                    .frame(maxWidth: .infinity)
                Text(title)
                    .font(.system(size: 12.5 * t, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6 * s)
            .padding(.top, (hanger ? 12 : 7) * s)
            .padding(.bottom, 7 * s)
            .frame(maxWidth: .infinity)
            .background(CardBackground(selected: selected, s: s))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16 * s, weight: .bold))
                        .foregroundStyle(.white, Theme.accent)
                        .padding(5 * s)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if hanger {
                    Hanger(s: s).offset(y: -9 * s)
                }
            }
            .padding(.top, hanger ? 9 * s : 0)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(duration: 0.25), value: selected)
    }
}

/// A card's paper: cream to warm paper, a cream edge and a hairline rim; ringed in orange when chosen.
public struct CardBackground: View {
    let selected: Bool
    let s: CGFloat

    public init(selected: Bool, s: CGFloat) {
        self.selected = selected
        self.s = s
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
        shape
            .fill(LinearGradient(
                colors: selected
                    ? [Color(red: 1, green: 0.95, blue: 0.86), Color(red: 0.99, green: 0.86, blue: 0.7)]
                    : [Color.white.opacity(0.85), Theme.paper],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(shape.strokeBorder(Theme.cream, lineWidth: 2.5 * s))
            .overlay(shape.strokeBorder(selected ? Theme.accent : Theme.rim, lineWidth: selected ? 2.5 * s : 1))
            .shadow(color: Theme.shadow.opacity(selected ? 1 : 0.7), radius: (selected ? 6 : 3) * s, y: (selected ? 3 : 2) * s)
    }
}

/// A wooden clothes hanger: its bar along the card's top and a brass hook.
public struct Hanger: View {
    let s: CGFloat

    public init(s: CGFloat) {
        self.s = s
    }

    public var body: some View {
        VStack(spacing: -2 * s) {
            Hook()
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.82, blue: 0.5), Color(red: 0.7, green: 0.5, blue: 0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 2 * s, lineCap: .round)
                )
                .frame(width: 12 * s, height: 11 * s)
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(red: 0.88, green: 0.62, blue: 0.36), Color(red: 0.66, green: 0.42, blue: 0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(Capsule().strokeBorder(Wood.edge, lineWidth: 0.75))
                .frame(width: 56 * s, height: 6 * s)
        }
        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        .accessibilityHidden(true)
    }

    /// The hook: up from the bar's middle, over and down a little.
    private struct Hook: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = rect.width * 0.36
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + radius + 1))
            path.addArc(
                center: CGPoint(x: rect.midX + radius, y: rect.minY + radius + 1),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(20),
                clockwise: false
            )
            return path
        }
    }
}

/// The cat in a look, drawn small for an option (off the main thread; the last picture stays until the next is in).
struct CatPicture: View {
    let model: CatBuilderModel
    let look: CatLook
    let kind: CatBuilderModel.PictureKind
    @State private var image: CGImage?

    private struct Key: Equatable {
        var look: CatLook
        var kind: CatBuilderModel.PictureKind
    }

    var body: some View {
        Group {
            if let image = image ?? model.cachedPicture(of: look, kind) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: Key(look: look, kind: kind)) {
            image = await model.picture(of: look, kind)
        }
        .accessibilityHidden(true)
    }
}

/// A palette of fur swatches in the coat colours, and any other colour from the picker.
struct FurPalette: View {
    let model: CatBuilderModel
    let selected: LookColour?
    let s: CGFloat
    let t: CGFloat
    let choose: (LookColour) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62 * s), spacing: 6 * s, alignment: .top)], spacing: 8 * s) {
            ForEach(model.builder.data.coats) { swatch in
                SwatchButton(
                    label: swatch.label.components(separatedBy: " (").first ?? swatch.label,
                    selected: selected == .named(swatch.id),
                    s: s,
                    t: t
                ) {
                    choose(.named(swatch.id))
                } swatch: {
                    FurSwatch(colour: Color(rgb: swatch.rgb), size: 46 * s)
                }
                .accessibilityLabel(swatch.label)
            }
            anyColour
        }
    }

    /// The system colour picker, under a fur swatch of the picked colour (a paintbrush until one is picked).
    private var anyColour: some View {
        let picked: RGB? = if case let .picked(rgb) = selected {
            rgb
        } else {
            nil
        }
        return VStack(spacing: 3 * s) {
            ZStack {
                Group {
                    if let picked {
                        FurSwatch(colour: Color(rgb: picked), size: 46 * s)
                    } else {
                        Circle().fill(Theme.cream).overlay(Circle().strokeBorder(Theme.rim, lineWidth: 1))
                            .frame(width: 40 * s, height: 40 * s)
                    }
                }
                .overlay(alignment: picked == nil ? .center : .bottomTrailing) {
                    PaintedIcon("decorate_paintbrush", size: (picked == nil ? 30 : 20) * s)
                }
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: picked == nil ? 0 : 3 * s).padding(-3 * s))
                .allowsHitTesting(false)
                ColorPicker("Any colour", selection: Binding(
                    get: { Color(rgb: picked ?? selected.map { model.rgb($0, in: model.builder.data.coats) } ?? RGB(128, 128, 128)) },
                    set: { colour in
                        if let rgb = colour.rgb {
                            choose(.picked(CatBuilder.pickerClamped(rgb)))
                        }
                    }
                ), supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.7 * s)
                    .opacity(0.02)
            }
            .frame(width: 50 * s, height: 50 * s)
            Text("Any colour")
                .font(.system(size: 10.5 * t, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A round swatch over its name; ringed when chosen.
struct SwatchButton<Swatch: View>: View {
    let label: String
    let selected: Bool
    let s: CGFloat
    let t: CGFloat
    let action: () -> Void
    @ViewBuilder let swatch: () -> Swatch
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            VStack(spacing: 3 * s) {
                swatch()
                    .overlay(Circle().strokeBorder(Theme.accent, lineWidth: selected ? 3 * s : 0).padding(-4 * s))
                    .frame(width: 50 * s, height: 50 * s)
                    .scaleEffect(selected ? 1.06 : 1)
                Text(label)
                    .font(.system(size: 10.5 * t, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(duration: 0.25), value: selected)
    }
}

/// A painted pompom of white fur tinted to a coat colour, as the coat recipe tints the white cat.
struct FurSwatch: View {
    let colour: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let fur = Self.fur {
                fur.resizable().interpolation(.high).scaledToFit()
                    .colorMultiply(colour)
                    .overlay {
                        // The warm rim light the recipe keeps on a dark coat.
                        fur.resizable().interpolation(.high).scaledToFit()
                            .colorMultiply(Color(red: 1, green: 0.85, blue: 0.7))
                            .mask(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center))
                            .blendMode(.screen)
                    }
            } else {
                Circle().fill(colour)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.shadow, radius: 2, y: 1)
    }

    @MainActor private static let fur: Image? = {
        #if canImport(UIKit)
            guard let url = Bundle.main.url(forResource: "Art/ui/creator/creator_fur_swatch.png", withExtension: nil),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            return Image(uiImage: image)
        #else
            guard let url = Bundle.main.url(forResource: "Art/ui/creator/creator_fur_swatch.png", withExtension: nil),
                  let image = NSImage(contentsOf: url) else { return nil }
            return Image(nsImage: image)
        #endif
    }()
}

/// A cat's eye in a colour: the iris shading to its rim, a slit pupil and a catchlight.
struct IrisSwatch: View {
    let colour: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [colour.mix(with: .white, by: 0.35), colour, colour.mix(with: .black, by: 0.35)],
                center: UnitPoint(x: 0.45, y: 0.45), startRadius: 0, endRadius: size * 0.55
            ))
            Circle().strokeBorder(colour.mix(with: .black, by: 0.55), lineWidth: size * 0.06)
            Ellipse().fill(Color(red: 0.1, green: 0.07, blue: 0.1)).frame(width: size * 0.14, height: size * 0.6)
            Circle().fill(.white.opacity(0.9)).frame(width: size * 0.12).offset(x: -size * 0.2, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.shadow, radius: 2, y: 1)
    }
}

/// A nose colour on the cat's own coat: a little rounded nose on a fur swatch.
struct NoseSwatch: View {
    let nose: Color
    let coat: Color
    let size: CGFloat

    var body: some View {
        FurSwatch(colour: coat, size: size)
            .overlay {
                NoseShape()
                    .fill(LinearGradient(colors: [nose.mix(with: .white, by: 0.2), nose], startPoint: .top, endPoint: .bottom))
                    .overlay(NoseShape().stroke(nose.mix(with: .black, by: 0.35), lineWidth: 1))
                    .frame(width: size * 0.42, height: size * 0.32)
            }
    }

    /// A cat's nose: wide at the top, rounded to a point below.
    private struct NoseShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.3),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.maxY * 0.85)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.3),
                control: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.maxY * 0.85)
            )
            path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }
}

/// A slider between two words on a paper strip; a drag is one change for Undo.
struct BuilderSlider: View {
    let title: String
    let low: String
    let high: String
    let icon: String?
    @Binding var value: Double
    let model: CatBuilderModel
    let s: CGFloat
    let t: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 6 * s) {
                if let icon {
                    PaintedIcon(icon, size: 22 * s)
                }
                Text(title).font(Theme.title(16 * t))
            }
            HStack(spacing: 8 * s) {
                Text(low).font(.system(size: 12 * t, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Slider(value: $value, in: 0 ... 1) { started in
                    model.adjusting(started)
                }
                .accessibilityLabel(title)
                .accessibilityValue(value < 0.34 ? low : value > 0.66 ? high : "In between")
                Text(high).font(.system(size: 12 * t, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 12 * s)
        .padding(.vertical, 8 * s)
        .paper(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
    }
}

/// A round raised − or + button.
struct RoundStep: View {
    let symbol: String
    let label: String
    let s: CGFloat
    let action: () -> Void
    @Environment(\.controlFeedback) private var feedback
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15 * s, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34 * s, height: 34 * s)
                .background {
                    ZStack {
                        Circle().fill(Theme.accent.mix(with: .black, by: 0.3)).offset(y: 3 * s)
                        Circle().fill(LinearGradient(
                            colors: [Theme.accent.mix(with: .white, by: 0.18), Theme.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                }
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    /// The colour in sRGB, 0–255.
    var rgb: RGB? {
        let resolved = resolve(in: EnvironmentValues())
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let components = resolved.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        func byte(_ v: CGFloat) -> Int {
            Int((min(1, max(0, v)) * 255).rounded())
        }
        return RGB(byte(components[0]), byte(components[1]), byte(components[2]))
    }
}

/// Wraps its children onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
