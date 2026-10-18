import CoreGraphics
import Foundation
import HouseCatCore
import HouseCatGame
import Observation
import SpriteKit

/// The cat builder's state (SPEC "Cat builder"): the look being built, and in adoption the name and
/// personality. Every choice goes through HouseCatCore's `CatBuilder`, so the look is always valid; the
/// preview redraws a moment after the last change, so dragging a slider stays smooth.
@MainActor
@Observable
public final class CatBuilderModel: Identifiable {
    public enum Mode: Sendable {
        /// Onboarding: the builder, then name and personality.
        case adopt
        /// From the profile: the look only.
        case edit
    }

    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case body = "Body"
        case coat = "Coat"
        case markings = "Markings"
        case eyes = "Eyes"
        case age = "Age"
        case name = "Name"

        public var id: String {
            rawValue
        }
    }

    public let mode: Mode
    public let builder: CatBuilder
    @ObservationIgnored public let catArt: CatArt
    @ObservationIgnored private let filter: NameFilter
    @ObservationIgnored public let preview: CatPreviewScene?

    public private(set) var look: CatLook
    public var section: Section = .body
    public var name = ""
    public var personality: Personality = .velcro
    /// The preset the look came from, until a field is changed.
    public private(set) var presetID: String?
    public private(set) var suggestions: [String] = []
    @ObservationIgnored private var shuffles = 0
    @ObservationIgnored private let seed = UInt64.random(in: 1 ... UInt64.max)
    @ObservationIgnored private var redraw: Task<Void, Never>?
    @ObservationIgnored private var thumbnails: [String: CGImage] = [:]

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
        preview = rig.map { CatPreviewScene(size: CGSize(width: 600, height: 500), art: art, catArt: catArt, rig: $0, look: start) }
        suggestions = CatNames.suggestions(from: builder.data.nameSuggestions, seed: seed)
    }

    public var sections: [Section] {
        mode == .adopt ? Section.allCases : Section.allCases.filter { $0 != .name }
    }

    // MARK: Changing the look

    /// Applies a change through the builder's rules and redraws the preview shortly after.
    public func change(_ edit: (inout CatLook) -> Void) {
        var next = look
        edit(&next)
        set(builder.normalized(next), preset: nil)
    }

    public func choose(preset id: String) {
        guard let preset = builder.preset(id) else { return }
        var next = preset.look
        // A preset sets the look, not the age the player chose.
        next.age = look.age
        set(builder.normalized(next), preset: id)
    }

    public func choose(kind: CatBuilder.BodyKind) {
        set(builder.choosing(kind, for: look), preset: nil)
    }

    public func weigh(_ weight: Double) {
        set(builder.weighing(weight, for: look), preset: nil)
    }

    private func set(_ next: CatLook, preset: String?) {
        guard next != look else { return }
        look = next
        presetID = preset ?? builder.data.presets.first { builder.normalized($0.look) == next }?.id
        redraw?.cancel()
        redraw = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.Builder.redrawDelay))
            guard !Task.isCancelled, let self else { return }
            preview?.show(look)
        }
    }

    public var kind: CatBuilder.BodyKind? {
        builder.kind(of: look)
    }

    public var body: CatBuilderData.Body? {
        builder.body(look.body)
    }

    // MARK: Pictures

    /// A preset as it sits (presetsheet.py's pose), for the presets row.
    public func thumbnail(_ preset: CatBuilderData.Preset) -> CGImage? {
        if let cached = thumbnails[preset.id] {
            return cached
        }
        let image = catArt.image(builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: preset.look), look: preset.look)
        thumbnails[preset.id] = image
        return image
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
}
