import CoreGraphics
import Foundation
import HouseCatCore
import HouseCatGame
import Observation
import SpriteKit

/// The cat creator's state (SPEC "Cat builder"; Josh, 19 Oct: a wardrobe, every part in its own drawer): the look
/// being made, the drawer open, what Undo can take back, and in adoption the name and personality. Every choice
/// goes through HouseCatCore's `CatBuilder`, so the look is always valid; the cat on the podium redraws a moment
/// after the last change (a slider drag stays smooth) and is shown sitting, standing or close up for the drawer.
@MainActor
@Observable
public final class CatBuilderModel: Identifiable {
    public enum Mode: Sendable {
        /// Onboarding: the look, then the name and personality.
        case adopt
        /// From the profile: the look only.
        case edit
    }

    /// The wardrobe's drawers, in the order they are worked through.
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case looks, body, coat, pattern, white, eyes, nose, earsTail, age, name

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .looks: "Looks"
            case .body: "Body"
            case .coat: "Coat"
            case .pattern: "Pattern"
            case .white: "White"
            case .eyes: "Eyes"
            case .nose: "Nose"
            case .earsTail: "Ears & tail"
            case .age: "Age"
            case .name: "Name"
            }
        }

        /// The drawer's heading.
        public var heading: String {
            switch self {
            case .looks: "Start from a look"
            case .body: "Body"
            case .coat: "Coat colour"
            case .pattern: "Pattern"
            case .white: "White markings"
            case .eyes: "Eyes"
            case .nose: "Nose and whiskers"
            case .earsTail: "Ears and tail"
            case .age: "Age"
            case .name: "Name and personality"
            }
        }

        /// Its painted icon (App/Art/ui/icon_<name>.png).
        public var icon: String {
            switch self {
            case .looks: "creator_hanger"
            case .body: "creator_tape_measure"
            case .coat: "creator_yarn"
            case .pattern: "creator_tabby_fabric"
            case .white: "creator_mittens"
            case .eyes: "creator_marbles"
            case .nose: "creator_nose_whiskers"
            case .earsTail: "creator_cat_ears"
            case .age: "creator_cupcake"
            case .name: "creator_name_tag"
            }
        }

        /// How the cat stands on the podium while this drawer is open: standing side on for the body, a pattern
        /// and the ears and tail, facing you for the white, close on the face for the eyes and nose.
        public var presentation: DressingRoomScene.Presentation {
            switch self {
            case .body, .pattern, .earsTail: .init(standing: true, angle: .sideLeft)
            case .white: .init(angle: .front)
            case .eyes, .nose: .init(angle: .front, face: true)
            case .looks, .coat, .age, .name: .init(angle: .threeQuarterLeft)
            }
        }
    }

    /// How an option's picture is drawn from the cat wearing it.
    public enum PictureKind: Hashable, Sendable {
        /// Sitting three-quarter front, the presets' pose.
        case sitting
        /// Sitting side on: a pattern along the flank, the tail.
        case side
        /// Sitting facing you: bibs and mitts.
        case front
        /// The head and shoulders: ears.
        case head
    }

    public let mode: Mode
    public let builder: CatBuilder
    @ObservationIgnored public let catArt: CatArt
    @ObservationIgnored private let filter: NameFilter
    @ObservationIgnored public let preview: DressingRoomScene?

    public private(set) var look: CatLook
    public var section: Section = .looks {
        didSet {
            preview?.present(section.presentation)
        }
    }

    public var name = ""
    /// What the cat calls the player (adopting; optional).
    public var ownerName = ""
    public var personality: Personality = .velcro
    /// The preset the look came from, until a field is changed.
    public private(set) var presetID: String?
    public private(set) var suggestions: [String] = []
    /// Looks Undo can go back to, the latest last.
    public private(set) var history: [CatLook] = []
    @ObservationIgnored private var shuffles = 0
    @ObservationIgnored private let seed = UInt64.random(in: 1 ... UInt64.max)
    @ObservationIgnored private var redraw: Task<Void, Never>?
    @ObservationIgnored private var pictures: [PictureKey: CGImage] = [:]
    @ObservationIgnored private var adjusting = false

    public init(
        mode: Mode,
        look: CatLook = .midnight,
        name: String = "",
        personality: Personality = .velcro,
        art: ArtLibrary,
        catArt: CatArt,
        rig: PuppetRig?,
        names: NameFilter
    ) {
        self.mode = mode
        builder = catArt.builder
        self.catArt = catArt
        filter = names
        let start = catArt.builder.normalized(look)
        self.look = start
        self.name = name
        self.personality = personality
        presetID = catArt.builder.data.presets.first { catArt.builder.normalized($0.look) == start }?.id
        preview = rig.map {
            DressingRoomScene(size: CGSize(width: 800, height: 400), art: art, catArt: catArt, rig: $0, look: start)
        }
        suggestions = CatNames.suggestions(from: builder.data.nameSuggestions, seed: seed)
    }

    public var sections: [Section] {
        mode == .adopt ? Section.allCases : Section.allCases.filter { $0 != .name }
    }

    public var nextSection: Section? {
        let all = sections
        return all.firstIndex(of: section).flatMap { $0 + 1 < all.count ? all[$0 + 1] : nil }
    }

    public var previousSection: Section? {
        let all = sections
        return all.firstIndex(of: section).flatMap { $0 > 0 ? all[$0 - 1] : nil }
    }

    // MARK: Changing the look

    /// Applies a change through the builder's rules; Undo can take it back.
    public func change(_ edit: (inout CatLook) -> Void) {
        var next = look
        edit(&next)
        set(builder.normalized(next), preset: nil)
    }

    /// A slider's drag is one change for Undo: the look before it is kept when the drag starts.
    public func adjusting(_ started: Bool) {
        if started {
            remember()
        }
        adjusting = started
    }

    public func choose(preset id: String) {
        guard let preset = builder.preset(id) else { return }
        var next = preset.look
        // A preset sets the look, not the age the player chose.
        next.age = look.age
        set(builder.normalized(next), preset: id, twirl: true)
    }

    public func choose(kind: CatBuilder.BodyKind) {
        set(builder.choosing(kind, for: look), preset: nil)
    }

    public func weigh(_ weight: Double) {
        set(builder.weighing(weight, for: look), preset: nil)
    }

    /// A cat made up at random from every option (keeping the age): sometimes a preset with a change or two,
    /// mostly a mix of its own.
    public func surprise() {
        var next = Self.randomLook(builder, keeping: look.age)
        if next == look {
            next = Self.randomLook(builder, keeping: look.age)
        }
        set(next, preset: nil, twirl: true)
    }

    public var canUndo: Bool {
        !history.isEmpty
    }

    public func undo() {
        guard let last = history.popLast() else { return }
        set(last, preset: nil, record: false)
    }

    private func remember() {
        if history.last != look {
            history.append(look)
        }
        if history.count > Tuning.Builder.undoDepth {
            history.removeFirst(history.count - Tuning.Builder.undoDepth)
        }
    }

    private func set(_ next: CatLook, preset: String?, record: Bool = true, twirl: Bool = false) {
        guard next != look else { return }
        if record, !adjusting {
            remember()
        }
        look = next
        presetID = preset ?? builder.data.presets.first { builder.normalized($0.look) == next }?.id
        redraw?.cancel()
        redraw = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Builder.redrawDelay))
            guard !Task.isCancelled, let self else { return }
            preview?.show(look, react: !twirl)
            if twirl {
                preview?.twirl()
            }
        }
    }

    public var kind: CatBuilder.BodyKind? {
        builder.kind(of: look)
    }

    public var body: CatBuilderData.Body? {
        builder.body(look.body)
    }

    /// The colour of a palette swatch or picked colour.
    public func rgb(_ colour: LookColour, in palette: [CatBuilderData.Swatch]) -> RGB {
        builder.rgb(colour, in: palette)
    }

    static func randomLook(_ builder: CatBuilder, keeping age: CatAge) -> CatLook {
        let data = builder.data
        if Double.random(in: 0 ..< 1) < 0.25, var preset = data.presets.randomElement()?.look {
            // A preset, with a different coat or eyes.
            preset.age = age
            if Bool.random(), let coat = data.coats.randomElement() {
                preset.coat = .named(coat.id)
                preset.patternColour = nil
            } else if let eye = data.eyes.randomElement() {
                preset.eyeLeft = .named(eye.id)
                preset.eyeRight = .named(eye.id)
            }
            return builder.normalized(preset)
        }
        let kinds = builder.bodyKinds
        let standard = kinds.filter(\.hasWeight)
        let kind = (Double.random(in: 0 ..< 1) < 0.7 ? standard.randomElement() : kinds.randomElement()) ?? kinds[0]
        var look = CatLook(body: kind.slim)
        look.weight = Double.random(in: 0 ... 1)
        look.age = age
        if builder.body(kind.slim)?.earSwaps == true, Double.random(in: 0 ..< 1) < 0.3 {
            look.ears = data.ears.filter { $0.id != "own" }.randomElement()?.id ?? "own"
        }
        if builder.body(kind.slim)?.tailSwaps == true, Double.random(in: 0 ..< 1) < 0.15 {
            look.tail = "bobtail"
        }
        // Rose is bare skin: a Sphynx's colour.
        let coats = data.coats.filter { builder.body(kind.slim)?.fur == "none" || $0.id != "rose" }
        look.coat = .named(coats.randomElement()?.id ?? "black")
        if Double.random(in: 0 ..< 1) < 0.6 {
            look.pattern = data.patterns.filter { $0.id != "none" }.randomElement()?.id
        }
        if Double.random(in: 0 ..< 1) < 0.4 {
            look.white = data.whites.filter { $0.id != "none" }.randomElement()?.id
        }
        let eye = LookColour.named(data.eyes.randomElement()?.id ?? "amber")
        look.eyeLeft = eye
        look.eyeRight = Double.random(in: 0 ..< 1) < 0.08 ? .named(data.eyes.randomElement()?.id ?? "blue") : eye
        look.nose = .named(data.noses.randomElement()?.id ?? "pink")
        look.eyeSize = Double.random(in: 0.3 ... 0.7)
        look.whiskerLength = Double.random(in: 0.6 ... 1)
        return builder.normalized(look)
    }

    // MARK: Pictures

    private struct PictureKey: Hashable {
        var look: CatLook
        var kind: PictureKind
    }

    private struct Picture: @unchecked Sendable {
        var image: CGImage?
    }

    /// An option's picture if it is drawn already.
    public func cachedPicture(of look: CatLook, _ kind: PictureKind) -> CGImage? {
        pictures[PictureKey(look: look, kind: kind)]
    }

    /// The cat in a look, drawn small off the main thread (the coat recipe takes a few milliseconds a pose).
    public func picture(of look: CatLook, _ kind: PictureKind) async -> CGImage? {
        let key = PictureKey(look: look, kind: kind)
        if let cached = pictures[key] {
            return cached
        }
        let catArt = catArt
        let drawn = await Task.detached(priority: .userInitiated) {
            Picture(image: Self.draw(look, kind, catArt: catArt))
        }.value
        if pictures.count > 400 {
            pictures.removeAll()
        }
        pictures[key] = drawn.image
        return drawn.image
    }

    private nonisolated static func draw(_ look: CatLook, _ kind: PictureKind, catArt: CatArt) -> CGImage? {
        let pose: CatPose = switch kind {
        case .sitting, .head: .sitThreeQuarterFront
        case .side: .sitSide
        case .front: .sitFront
        }
        let sprite = catArt.builder.pose(pose.rawValue, look: look)
        guard let image = catArt.render(sprite, look: look)?.cgImage else { return nil }
        if kind == .head {
            return Headshot.cut(image, face: catArt.face(sprite.path), size: Int(Tuning.Builder.thumbnailPixels))
        }
        return shrink(image, height: Int(Tuning.Builder.thumbnailPixels))
    }

    private nonisolated static func shrink(_ image: CGImage, height: Int) -> CGImage? {
        guard image.height > height else { return image }
        let width = max(1, Int((Double(image.width) * Double(height) / Double(image.height)).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The look as it sits, for the profile and the share card.
    public func portrait() -> CGImage? {
        catArt.image(builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look), look: look)
    }

    // MARK: Name

    public var nameCheck: CatNames.Check {
        CatNames.check(name, filter: filter)
    }

    public var nameProblem: String? {
        switch nameCheck {
        case .ok: nil
        case .empty: name.isEmpty ? nil : "A name needs a letter or two."
        case .tooLong: "Up to \(Tuning.Cat.nameMaxLength) characters."
        case .blocked: "Try another name."
        }
    }

    public func shuffleNames() {
        shuffles += 1
        suggestions = CatNames.suggestions(from: builder.data.nameSuggestions, seed: seed, shuffle: shuffles)
    }

    /// Whether the adoption can go ahead: a good name.
    public var canAdopt: Bool {
        if case .ok = nameCheck {
            return true
        }
        return false
    }

    public var checkedName: String? {
        if case let .ok(name) = nameCheck {
            return name
        }
        return nil
    }

    /// The player's name, if they gave one that passes the same checks as a cat's.
    public var checkedOwnerName: String? {
        if case let .ok(name) = CatNames.check(ownerName, filter: filter) {
            return name
        }
        return nil
    }
}
