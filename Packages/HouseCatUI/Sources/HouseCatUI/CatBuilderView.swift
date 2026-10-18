import HouseCatCore
import HouseCatGame
import SpriteKit
import SwiftUI

/// The cat builder (SPEC "Cat builder"; onboarding's second screen, and Edit look from the profile): the cat
/// live on the left with the presets under it, the fields on the right in builder order, then, when adopting,
/// the cat's own name and its personality. Landscape, like the game.
public struct CatBuilderView: View {
    @Bindable private var model: CatBuilderModel
    private let done: (CatBuilderModel) -> Void
    private let cancel: (() -> Void)?

    public init(model: CatBuilderModel, cancel: (() -> Void)? = nil, done: @escaping (CatBuilderModel) -> Void) {
        self.model = model
        self.cancel = cancel
        self.done = done
    }

    public var body: some View {
        GeometryReader { geometry in
            // Side by side in landscape (the game's way round); stacked on an iPad held upright.
            if geometry.size.height > geometry.size.width {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        preview
                        presets
                    }
                    .padding(.vertical, 12)
                    .frame(height: geometry.size.height * 0.48)
                    panel
                }
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 10) {
                        preview
                        presets
                    }
                    .padding(.vertical, 12)
                    .frame(width: geometry.size.width * 0.46)
                    panel
                }
            }
        }
        .background(Color(red: 0.95, green: 0.9, blue: 0.86).ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                fields
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(Theme.paper)
    }

    // MARK: Left: the cat and the presets

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            if let scene = model.preview {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                RoundedRectangle(cornerRadius: 22).fill(.quaternary)
            }
            if let preset = model.presetID.flatMap(model.builder.preset) {
                Text(preset.name)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .padding(.horizontal, 12)
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(model.builder.data.presets) { preset in
                    Button {
                        model.choose(preset: preset.id)
                    } label: {
                        VStack(spacing: 2) {
                            Group {
                                if let image = model.thumbnail(preset) {
                                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: Tuning.Builder.presetThumbnail, height: Tuning.Builder.presetThumbnail)
                            Text(preset.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: Tuning.Builder.presetThumbnail + 10)
                        }
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(model.presetID == preset.id ? Theme.accent.opacity(0.18) : Color.white.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: Tuning.Builder.presetThumbnail + 30)
    }

    // MARK: Right: the fields

    private var header: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.sections) { section in
                    Button(section.rawValue) {
                        model.section = section
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.section == section ? Theme.ink : Theme.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(model.section == section ? Theme.cream : Color.clear))
                    .overlay(Capsule().strokeBorder(model.section == section ? Theme.rim : .clear, lineWidth: 1))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch model.section {
        case .body: bodyFields
        case .coat: coatFields
        case .markings: markingFields
        case .eyes: eyeFields
        case .age: ageFields
        case .name: nameFields
        }
    }

    private var bodyFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Body") {
                chips(model.builder.bodyKinds.map { ($0.id, $0.label) }, selected: model.kind?.id) { id in
                    if let kind = model.builder.bodyKinds.first(where: { $0.id == id }) {
                        model.choose(kind: kind)
                    }
                }
            }
            if model.kind?.hasWeight == true {
                row("Weight") {
                    HStack {
                        Text("Slim").font(.caption)
                        Slider(value: Binding(get: { model.look.weight }, set: { model.weigh($0) }), in: 0 ... 1)
                        Text("Chunky").font(.caption)
                    }
                }
            } else if let body = model.body {
                Text(body.fur == "none" ? "Hairless: the coat colour is the skin colour." : "Breeds keep their own ears and tail.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.body?.earSwaps == true {
                row("Ears") {
                    chips(model.builder.data.ears.map { ($0.id, $0.id == "own" ? "Pointed" : $0.label) }, selected: model.look.ears) { id in
                        model.change { $0.ears = id }
                    }
                }
            }
            if model.body?.tailSwaps == true {
                row("Tail") {
                    chips(model.builder.data.tails.map { ($0.id, $0.id == "own" ? "Long" : $0.label) }, selected: model.look.tail) { id in
                        model.change { $0.tail = id }
                    }
                }
            }
            row("Whiskers") {
                HStack {
                    Text("Short").font(.caption)
                    Slider(
                        value: Binding(get: { model.look.whiskerLength }, set: { v in model.change { $0.whiskerLength = v } }),
                        in: 0 ... 1
                    )
                    Text("Long").font(.caption)
                }
            }
        }
    }

    private var coatFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Coat colour") {
                swatches(model.builder.data.coats, selected: model.look.coat, picker: true) { colour in
                    model.change { $0.coat = colour }
                }
            }
            row("Pattern") {
                chips(model.builder.data.patterns.map { ($0.id, $0.label) }, selected: model.look.pattern ?? "none") { id in
                    model.change { $0.pattern = id == "none" ? nil : id }
                }
            }
            if model.look.pattern != nil {
                row("Pattern colour") {
                    swatches(model.builder.data.coats, selected: model.look.patternColour, picker: true) { colour in
                        model.change { $0.patternColour = colour }
                    }
                }
            }
        }
    }

    private var markingFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("White markings") {
                chips(model.builder.data.whites.map { ($0.id, $0.label) }, selected: model.look.white ?? "none") { id in
                    model.change { $0.white = id == "none" ? nil : id }
                }
            }
            Text("Patterns and white combine: tortoiseshell with bicolour is a calico, colourpoint with mitts a ragdoll.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var eyeFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Odd eyes", isOn: Binding(get: { model.look.hasOddEyes }, set: { odd in
                model.change { look in
                    look.eyeRight = odd ? (look.eyeLeft == .named("blue") ? .named("amber") : .named("blue")) : look.eyeLeft
                }
            }))
            row(model.look.hasOddEyes ? "Left eye" : "Eyes") {
                swatches(model.builder.data.eyes, selected: model.look.eyeLeft, picker: false) { colour in
                    model.change { look in
                        let same = !look.hasOddEyes
                        look.eyeLeft = colour
                        if same {
                            look.eyeRight = colour
                        }
                    }
                }
            }
            if model.look.hasOddEyes {
                row("Right eye") {
                    swatches(model.builder.data.eyes, selected: model.look.eyeRight, picker: false) { colour in
                        model.change { $0.eyeRight = colour }
                    }
                }
            }
            row("Eye size") {
                HStack {
                    Text("Small").font(.caption)
                    Slider(value: Binding(get: { model.look.eyeSize }, set: { v in model.change { $0.eyeSize = v } }), in: 0 ... 1)
                    Text("Big").font(.caption)
                }
            }
            row("Nose") {
                swatches(model.builder.data.noses, selected: model.look.nose, picker: false) { colour in
                    model.change { $0.nose = colour }
                }
            }
        }
    }

    private var ageFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Age") {
                chips([("kitten", "Kitten"), ("adult", "Adult")], selected: model.look.age.isKitten ? "kitten" : "adult") { id in
                    model.change { $0.age = id == "kitten" ? .kitten : .defaultAdult }
                }
            }
            if case let .adult(years) = model.look.age {
                Stepper(
                    "\(years) \(years == 1 ? "year" : "years") old",
                    value: Binding(get: { years }, set: { v in model.change { $0.age = .adult(years: v) } }),
                    in: 1 ... Tuning.Cat.maxAdultYears
                )
            } else {
                Text("Twelve weeks old; grown up after three weeks together.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nameFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Name") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Your cat's name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                    if let problem = model.nameProblem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                    HStack(spacing: 6) {
                        ForEach(model.suggestions, id: \.self) { name in
                            Button(name) {
                                model.name = name
                            }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                        }
                        Button {
                            model.shuffleNames()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("More names")
                    }
                }
            }
            row("Personality") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Personality.allCases, id: \.self) { personality in
                        Button {
                            model.personality = personality
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ProfileText.personality(personality)).font(.subheadline.weight(.semibold))
                                Text(ProfileText.personalityBlurb(personality)).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(model.personality == personality ? Theme.accent.opacity(0.18) : Color.white.opacity(0.4))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let cancel {
                HUDButton("Cancel", symbol: "xmark", action: cancel)
            }
            Spacer()
            let sections = model.sections
            let index = sections.firstIndex(of: model.section) ?? 0
            if index + 1 < sections.count {
                HUDButton("Next: \(sections[index + 1].rawValue)", symbol: "arrow.right") {
                    model.section = sections[index + 1]
                }
            }
            if model.mode == .edit {
                HUDButton("Done", symbol: "checkmark", prominent: true) {
                    done(model)
                }
            } else if model.section == .name {
                HUDButton(model.checkedName.map { "Bring \($0) home" } ?? "Bring them home", icon: "house", prominent: true) {
                    done(model)
                }
                .disabled(!model.canAdopt)
                .opacity(model.canAdopt ? 1 : 0.5)
            }
        }
        .padding(12)
    }

    // MARK: Pieces

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.title(17))
            content()
        }
    }

    private func chips(_ options: [(String, String)], selected: String?, choose: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.0) { id, label in
                Button(label) {
                    choose(id)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected == id ? Theme.cream : Theme.ink.opacity(0.05)))
                .overlay(Capsule().strokeBorder(selected == id ? Theme.accent : .clear, lineWidth: 2))
                .buttonStyle(.plain)
            }
        }
    }

    private func swatches(
        _ palette: [CatBuilderData.Swatch],
        selected: LookColour?,
        picker: Bool,
        choose: @escaping (LookColour) -> Void
    ) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(palette) { swatch in
                Button {
                    choose(.named(swatch.id))
                } label: {
                    Circle()
                        .fill(Color(rgb: swatch.rgb))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: selected == .named(swatch.id) ? 3 : 0).padding(-4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.label)
            }
            if picker {
                ColorPicker("Any colour", selection: Binding(
                    get: {
                        if case let .picked(rgb) = selected {
                            return Color(rgb: rgb)
                        }
                        return Color(rgb: selected.map { model.builder.rgb($0, in: palette) } ?? RGB(128, 128, 128))
                    },
                    set: { colour in
                        if let rgb = colour.rgb {
                            choose(.picked(CatBuilder.pickerClamped(rgb)))
                        }
                    }
                ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Theme.accent, lineWidth: {
                        if case .picked = selected {
                            return 3
                        }
                        return 0
                    }()).padding(-4))
            }
        }
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
