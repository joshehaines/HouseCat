import HouseCatCore
import SwiftUI

/// What is in the open drawer: every option of one part of the look, each shown on the cat itself (a pattern on
/// its flank, a white marking on its bib, the ears on its head) or as a swatch in its real colour.
struct CatBuilderDrawer: View {
    @Bindable var model: CatBuilderModel
    /// The layout's scale, and the text's (it grows with the player's text size too).
    let s: CGFloat
    let t: CGFloat
    @Environment(\.controlFeedback) private var feedback

    var body: some View {
        switch model.section {
        case .looks: looks
        case .body: bodyDrawer
        case .coat: coat
        case .pattern: pattern
        case .white: white
        case .eyes: eyes
        case .nose: nose
        case .earsTail: earsAndTail
        case .age: age
        case .name: nameDrawer
        }
    }

    private var data: CatBuilderData {
        model.builder.data
    }

    private var look: CatLook {
        model.look
    }

    // MARK: Looks

    private var looks: some View {
        grid(minimum: 96) {
            ForEach(data.presets) { preset in
                OptionCard(title: preset.name, selected: model.presetID == preset.id, hanger: true, s: s, t: t) {
                    model.choose(preset: preset.id)
                } picture: {
                    CatPicture(model: model, look: preset.look, kind: .sitting)
                        .frame(height: 78 * s)
                }
            }
        }
    }

    // MARK: Body

    private var bodyDrawer: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            grid(minimum: 104) {
                ForEach(model.builder.bodyKinds) { kind in
                    OptionCard(title: kind.label, selected: model.kind?.id == kind.id, s: s, t: t) {
                        model.choose(kind: kind)
                    } picture: {
                        CatPicture(model: model, look: model.builder.choosing(kind, for: look), kind: .sitting)
                            .frame(height: 78 * s)
                    }
                }
            }
            if model.kind?.hasWeight == true {
                BuilderSlider(
                    title: "Weight", low: "Slim", high: "Chunky", icon: "creator_tape_measure",
                    value: Binding(get: { look.weight }, set: { model.weigh($0) }),
                    model: model, s: s, t: t
                )
            } else if let body = model.body {
                note(body.fur == "none"
                    ? "Hairless: the coat colour is the skin's colour."
                    : "\(body.label) has one build, its own ears and its own tail.")
            }
        }
    }

    // MARK: Coat and pattern

    private var coat: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            FurPalette(model: model, selected: look.coat, s: s, t: t) { colour in
                model.change { $0.coat = colour }
            }
            if model.body?.fur == "none" {
                note("A Sphynx has no fur: this is the colour of its skin. Rose is bare pink skin.")
            }
        }
    }

    private var pattern: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            grid(minimum: 104) {
                ForEach(data.patterns) { option in
                    let id = option.id == "none" ? nil : option.id
                    OptionCard(title: option.label, selected: look.pattern == id, s: s, t: t) {
                        model.change { $0.pattern = id }
                    } picture: {
                        CatPicture(model: model, look: variant { $0.pattern = id }, kind: .side)
                            .frame(height: 74 * s)
                    }
                }
            }
            if look.pattern != nil {
                subheading("Pattern colour", icon: "creator_yarn")
                FurPalette(model: model, selected: look.patternColour, s: s, t: t) { colour in
                    model.change { $0.patternColour = colour }
                }
            }
        }
    }

    private var white: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            grid(minimum: 104) {
                ForEach(data.whites) { option in
                    let id = option.id == "none" ? nil : option.id
                    OptionCard(title: shortLabel(option), selected: look.white == id, s: s, t: t) {
                        model.change { $0.white = id }
                    } picture: {
                        CatPicture(model: model, look: variant { $0.white = id }, kind: .front)
                            .frame(height: 78 * s)
                    }
                    .accessibilityHint(option.label)
                }
            }
            note("Patterns and white go together: a tortoiseshell with bicolour is a calico, a colourpoint with mitts a ragdoll.")
        }
    }

    /// "Tuxedo (bib, paws, chin)" as "Tuxedo"; the whole label is the hint.
    private func shortLabel(_ option: CatBuilderData.Option) -> String {
        option.label.components(separatedBy: " (").first ?? option.label
    }

    // MARK: Eyes and nose

    private var eyes: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            HStack(spacing: 6 * s) {
                ForEach([false, true], id: \.self) { odd in
                    let chosen = look.hasOddEyes == odd
                    Button {
                        feedback.tap()
                        model.change { look in
                            look.eyeRight = odd ? (look.eyeLeft == .named("blue") ? .named("amber") : .named("blue")) : look.eyeLeft
                        }
                    } label: {
                        Text(odd ? "Odd eyes" : "Both alike")
                            .font(.system(size: 14 * t, weight: .bold, design: .rounded))
                            .foregroundStyle(chosen ? Theme.ink : Theme.inkSoft)
                            .padding(.horizontal, 14 * s)
                            .padding(.vertical, 6 * s)
                            .paper(Capsule(), fill: chosen ? Color(red: 1, green: 0.9, blue: 0.76) : Theme.cream)
                            .overlay(Capsule().strokeBorder(chosen ? Theme.accent : .clear, lineWidth: 2 * s))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            subheading(look.hasOddEyes ? "Left eye" : "Eye colour", icon: "creator_marbles")
            eyePalette(selected: look.eyeLeft) { colour in
                model.change { look in
                    let alike = !look.hasOddEyes
                    look.eyeLeft = colour
                    if alike {
                        look.eyeRight = colour
                    }
                }
            }
            if look.hasOddEyes {
                subheading("Right eye", icon: "creator_marbles")
                eyePalette(selected: look.eyeRight) { colour in
                    model.change { $0.eyeRight = colour }
                }
            }
            BuilderSlider(
                title: "Eye size", low: "Small", high: "Big", icon: nil,
                value: Binding(get: { look.eyeSize }, set: { v in model.change { $0.eyeSize = v } }),
                model: model, s: s, t: t
            )
        }
    }

    private func eyePalette(selected: LookColour, choose: @escaping (LookColour) -> Void) -> some View {
        grid(minimum: 62, spacing: 6) {
            ForEach(data.eyes) { swatch in
                SwatchButton(label: swatch.label, selected: selected == .named(swatch.id), s: s, t: t) {
                    choose(.named(swatch.id))
                } swatch: {
                    IrisSwatch(colour: Color(rgb: swatch.rgb), size: 44 * s)
                }
            }
        }
    }

    private var nose: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            grid(minimum: 62, spacing: 6) {
                ForEach(data.noses) { swatch in
                    SwatchButton(label: swatch.label, selected: look.nose == .named(swatch.id), s: s, t: t) {
                        model.change { $0.nose = .named(swatch.id) }
                    } swatch: {
                        NoseSwatch(nose: Color(rgb: swatch.rgb), coat: Color(rgb: model.rgb(look.coat, in: data.coats)), size: 44 * s)
                    }
                }
            }
            BuilderSlider(
                title: "Whiskers", low: "Short", high: "Long", icon: "creator_nose_whiskers",
                value: Binding(get: { look.whiskerLength }, set: { v in model.change { $0.whiskerLength = v } }),
                model: model, s: s, t: t
            )
        }
    }

    // MARK: Ears and tail

    private var earsAndTail: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            subheading("Ears", icon: "creator_cat_ears")
            if model.body?.earSwaps == true {
                grid(minimum: 96) {
                    ForEach(data.ears) { option in
                        OptionCard(
                            title: option.id == "own" ? "Pointed" : shortLabel(option),
                            selected: look.ears == option.id,
                            s: s,
                            t: t
                        ) {
                            model.change { $0.ears = option.id }
                        } picture: {
                            CatPicture(model: model, look: variant { $0.ears = option.id }, kind: .head)
                                .frame(height: 70 * s)
                        }
                        .accessibilityHint(option.id == "own" ? "Pointed" : option.label)
                    }
                }
            } else {
                note("\(model.body?.label ?? "This breed") keeps its own ears. Shorthair and Longhair can wear any.")
            }
            subheading("Tail", icon: "creator_tail")
            if model.body?.tailSwaps == true {
                grid(minimum: 104) {
                    ForEach(data.tails) { option in
                        OptionCard(title: option.id == "own" ? "Long" : option.label, selected: look.tail == option.id, s: s, t: t) {
                            model.change { $0.tail = option.id }
                        } picture: {
                            CatPicture(model: model, look: variant { $0.tail = option.id }, kind: .side)
                                .frame(height: 74 * s)
                        }
                    }
                }
            } else {
                note("\(model.body?.label ?? "This breed") keeps its own tail.")
            }
        }
    }

    // MARK: Age

    private var age: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            grid(minimum: 120) {
                OptionCard(title: "Kitten", selected: look.age.isKitten, s: s, t: t) {
                    model.change { $0.age = .kitten }
                } picture: {
                    CatPicture(model: model, look: variant { $0.age = .kitten }, kind: .sitting)
                        .frame(height: 78 * s * CGFloat(Tuning.Cat.kittenScale))
                        .frame(height: 78 * s, alignment: .bottom)
                }
                OptionCard(title: "Grown up", selected: !look.age.isKitten, s: s, t: t) {
                    model.change { $0.age = look.age.isKitten ? .defaultAdult : $0.age }
                } picture: {
                    CatPicture(model: model, look: variant { $0.age = .defaultAdult }, kind: .sitting)
                        .frame(height: 78 * s)
                }
            }
            if case let .adult(years) = look.age {
                HStack(spacing: 10 * s) {
                    PaintedIcon("creator_cupcake", size: 30 * s)
                    Text("\(years) \(years == 1 ? "year" : "years") old")
                        .font(Theme.title(18 * t))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    RoundStep(symbol: "minus", label: "Younger", s: s) {
                        model.change { $0.age = .adult(years: years - 1) }
                    }
                    .disabled(years <= 1)
                    RoundStep(symbol: "plus", label: "Older", s: s) {
                        model.change { $0.age = .adult(years: years + 1) }
                    }
                    .disabled(years >= Tuning.Cat.maxAdultYears)
                }
                .padding(10 * s)
                .paper(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(years) \(years == 1 ? "year" : "years") old")
                .accessibilityAdjustableAction { direction in
                    let next = direction == .increment ? years + 1 : years - 1
                    model.change { $0.age = .adult(years: next) }
                }
                .animation(.snappy, value: years)
            } else {
                note("Twelve weeks old, and grown up after three weeks together.")
            }
        }
    }

    // MARK: Name and personality

    private var nameDrawer: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            HStack(spacing: 10 * s) {
                PaintedIcon("creator_name_tag", size: 40 * s)
                TextField("Your cat's name", text: $model.name)
                    .font(Theme.title(22 * t))
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 12 * s)
                    .padding(.vertical, 8 * s)
                    .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(.white.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).strokeBorder(
                        Theme.accent.opacity(0.6),
                        lineWidth: 1.5
                    ))
            }
            if let problem = model.nameProblem {
                Text(problem).font(.system(size: 13 * t, weight: .semibold)).foregroundStyle(Color(red: 0.75, green: 0.2, blue: 0.15))
            }
            FlowLayout(spacing: 6 * s) {
                ForEach(model.suggestions, id: \.self) { name in
                    Button {
                        feedback.tap()
                        model.name = name
                    } label: {
                        Text(name)
                            .font(.system(size: 14 * t, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12 * s)
                            .padding(.vertical, 6 * s)
                            .paper(Capsule(), fill: model.name == name ? Theme.accent.opacity(0.2) : Theme.cream)
                    }
                    .buttonStyle(PressStyle())
                }
                Button {
                    feedback.tap()
                    model.shuffleNames()
                } label: {
                    PaintedIcon("creator_dice", size: 26 * s)
                        .padding(.horizontal, 8 * s)
                        .padding(.vertical, 2 * s)
                        .paper(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("More names")
            }
            subheading("Personality", icon: "trust_heart_with_a_paw_print")
            grid(minimum: 150) {
                ForEach(Personality.allCases, id: \.self) { personality in
                    Button {
                        feedback.tap()
                        model.personality = personality
                    } label: {
                        HStack(alignment: .top, spacing: 8 * s) {
                            PaintedIcon(Self.icon(personality), size: 28 * s)
                            VStack(alignment: .leading, spacing: 2 * s) {
                                Text(ProfileText.personality(personality)).font(.system(size: 15 * t, weight: .bold, design: .rounded))
                                Text(ProfileText.personalityBlurb(personality))
                                    .font(.system(size: 12 * t))
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10 * s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(CardBackground(selected: model.personality == personality, s: s))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(model.personality == personality ? .isSelected : [])
                }
            }
        }
    }

    static func icon(_ personality: Personality) -> String {
        switch personality {
        case .aloof: "cat_face"
        case .velcro: "trust_heart_with_a_paw_print"
        case .gremlin: "play_laser_dot"
        case .loaf: "nap_moon"
        }
    }

    // MARK: Pieces

    /// The look with one thing changed, made valid, for an option's picture.
    private func variant(_ edit: (inout CatLook) -> Void) -> CatLook {
        var next = look
        edit(&next)
        return model.builder.normalized(next)
    }

    private func grid(minimum: CGFloat, spacing: CGFloat = 10, @ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum * s), spacing: spacing * s, alignment: .top)], spacing: spacing * s) {
            content()
        }
    }

    private func subheading(_ text: String, icon: String) -> some View {
        HStack(spacing: 6 * s) {
            PaintedIcon(icon, size: 22 * s)
            Text(text).font(Theme.title(16 * t))
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12 * t))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}
