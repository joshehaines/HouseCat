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
        DressingRoomLayout(
            scene: model.preview,
            sceneLabel: lookDescription,
            drawers: model.sections.map { WardrobeDrawer(id: $0.rawValue, title: $0.title, icon: .painted($0.icon)) },
            open: model.section.rawValue,
            choose: { id in
                if let section = CatBuilderModel.Section(rawValue: id) {
                    model.section = section
                }
            },
            top: { m in
                HStack(alignment: .top, spacing: 8 * m.s) {
                    if let cancel {
                        CloseButton(scale: m.s, action: cancel)
                            .frame(width: 36 * m.s, height: 36 * m.s, alignment: .topLeading)
                    }
                    Spacer(minLength: 0)
                    nameplate(m)
                    Spacer(minLength: 0)
                    if cancel != nil {
                        Color.clear.frame(width: 36 * m.s, height: 1)
                    }
                }
            },
            bottom: { m in
                // Under a narrow stage (iPhone Duo folded) Surprise me is its dice alone rather than cut off.
                ViewThatFits(in: .horizontal) {
                    undoAndSurprise(m, surprise: "Surprise me")
                    undoAndSurprise(m, surprise: "")
                }
            },
            panel: { m in
                DrawerPanel(
                    icon: .painted(model.section.icon),
                    heading: model.section.heading,
                    subtitle: subtitle,
                    metrics: m,
                    scrollID: model.section
                ) {
                    CatBuilderDrawer(model: model, s: m.s, t: m.t)
                } footer: {
                    footer(m)
                }
            },
            hint: { hint }
        )
    }

    private func undoAndSurprise(_ m: WardrobeMetrics, surprise: String) -> some View {
        HStack(spacing: 8 * m.s) {
            HUDButton("Undo", symbol: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.45)
            HUDButton(surprise, icon: "creator_dice") { model.surprise() }
                .accessibilityLabel("Surprise me")
        }
    }

    /// The look's name on a little paper plaque: the preset it is, or the player's own (and, adopting, the cat's name).
    private func nameplate(_ m: WardrobeMetrics) -> some View {
        let preset = model.presetID.flatMap(model.builder.preset)?.name
        let named = model.mode == .adopt ? model.checkedName : nil
        return Nameplate(named ?? preset ?? "Your own look", subtitle: named != nil ? preset : nil, metrics: m)
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
    private func footer(_ m: WardrobeMetrics) -> some View {
        HStack(spacing: 8 * m.s) {
            if let previous = model.previousSection {
                RoundPaperButton(symbol: "chevron.left", label: "Back: \(previous.title)", size: 40 * m.s) {
                    withAnimation(.spring(duration: 0.3)) { model.section = previous }
                }
            }
            Spacer(minLength: 0)
            // Adopting, the name is never ten drawers away: a look and a name will do (Josh, 25 Oct: the onboarding
            // research, Finch has your pet home in two screens).
            if model.mode == .adopt, model.section != .name {
                HUDButton("Skip to name", symbol: "forward.end") {
                    withAnimation(.spring(duration: 0.3)) { model.section = .name }
                }
            }
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
