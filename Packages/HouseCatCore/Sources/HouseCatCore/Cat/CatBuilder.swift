import Foundation

/// The cat builder's options, presets and name suggestions, in builder order: App/Art/cat/custom/builder.json,
/// written from assets/cat/custom/catbuilder.json by tools/app-assets/build_cat_art.py (JSON objects keep no
/// order once decoded, so the build writes them as lists).
public struct CatBuilderData: Codable, Sendable {
    public struct Body: Codable, Sendable, Identifiable {
        public var id: String
        public var label: String
        /// "short", "long" or "none" (sphynx).
        public var fur: String
        public var build: String
        /// Drawn larger (Maine Coon 1.15).
        public var scale: Double
        public var earSwaps: Bool
        public var tailSwaps: Bool
        /// The expression-head set (`expr/head_<set>_<view>_<expression>.png`).
        public var expressionHeads: String
        /// The other end of the weight slider (slim ↔ chunky), for Shorthair and Longhair.
        public var weightPair: String?
    }

    public struct Option: Codable, Sendable, Identifiable {
        public var id: String
        public var label: String
    }

    public struct Swatch: Codable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var rgb: RGB
    }

    public struct Preset: Codable, Sendable, Identifiable {
        public var id: String
        /// Names the look, never the cat.
        public var name: String
        public var look: CatLook
    }

    public var bodies: [Body]
    public var ears: [Option]
    public var tails: [Option]
    /// "none" first (solid).
    public var patterns: [Option]
    /// "none" first.
    public var whites: [Option]
    public var coats: [Swatch]
    public var eyes: [Swatch]
    public var noses: [Swatch]
    public var presets: [Preset]
    public var nameSuggestions: [String]
}

/// The builder's rules (SPEC "Cat builder"): which options a body allows, the weight slider, the colours a
/// look resolves to, and which painted sprites draw it. Every option is free at launch.
public struct CatBuilder: Sendable {
    public let data: CatBuilderData
    private let bodiesByID: [String: CatBuilderData.Body]

    public init(data: CatBuilderData) {
        self.data = data
        bodiesByID = Dictionary(data.bodies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public static func load(from url: URL) throws -> CatBuilder {
        try CatBuilder(data: JSONDecoder().decode(CatBuilderData.self, from: Data(contentsOf: url)))
    }

    public func body(_ id: String) -> CatBuilderData.Body? {
        bodiesByID[id]
    }

    public func preset(_ id: String) -> CatBuilderData.Preset? {
        data.presets.first { $0.id == id }
    }

    // MARK: Body kinds and the weight slider

    /// What the Body row offers: Shorthair and Longhair (each a slim and a chunky set on the weight slider)
    /// and each breed.
    public struct BodyKind: Hashable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var slim: String
        public var chunky: String?

        public var hasWeight: Bool {
            chunky != nil
        }
    }

    public var bodyKinds: [BodyKind] {
        var kinds: [BodyKind] = []
        for body in data.bodies {
            if let pair = body.weightPair {
                guard body.build == "slim" else { continue }
                let label = body.fur == "long" ? "Longhair" : "Shorthair"
                kinds.append(BodyKind(id: body.fur, label: label, slim: body.id, chunky: pair))
            } else {
                kinds.append(BodyKind(id: body.id, label: body.label, slim: body.id, chunky: nil))
            }
        }
        return kinds
    }

    public func kind(of look: CatLook) -> BodyKind? {
        bodyKinds.first { $0.slim == look.body || $0.chunky == look.body }
    }

    /// The look on another body kind, keeping its weight where the kind has one.
    public func choosing(_ kind: BodyKind, for look: CatLook) -> CatLook {
        var look = look
        look.body = kind.slim
        return normalized(look)
    }

    /// The look at another weight: past the midpoint the chunky set.
    public func weighing(_ weight: Double, for look: CatLook) -> CatLook {
        var look = look
        look.weight = min(1, max(0, weight))
        return normalized(look)
    }

    /// How much wider than painted the torso is drawn: the weight within its set, about the set's centre.
    public func torsoStretch(_ look: CatLook) -> Double {
        guard kind(of: look)?.hasWeight == true else { return 1 }
        let within = look.weight < 0.5 ? look.weight * 2 : look.weight * 2 - 1
        return 1 + Tuning.Cat.weightStretch * (within * 2 - 1)
    }

    /// The look made valid: a known body (the weight choosing between slim and chunky), breeds with their own
    /// ears and tail, known options, sliders in range, a pattern colour when there is a pattern.
    public func normalized(_ look: CatLook) -> CatLook {
        var look = look
        if body(look.body) == nil {
            look.body = CatLook.midnight.body
        }
        look.weight = min(1, max(0, look.weight))
        if let kind = kind(of: look), let chunky = kind.chunky {
            look.body = look.weight < 0.5 ? kind.slim : chunky
        }
        let body = body(look.body)
        if body?.earSwaps != true || !data.ears.contains(where: { $0.id == look.ears }) {
            look.ears = "own"
        }
        if body?.tailSwaps != true || !data.tails.contains(where: { $0.id == look.tail }) {
            look.tail = "own"
        }
        if let pattern = look.pattern, pattern == "none" || !data.patterns.contains(where: { $0.id == pattern }) {
            look.pattern = nil
        }
        if let white = look.white, white == "none" || !data.whites.contains(where: { $0.id == white }) {
            look.white = nil
        }
        if look.pattern == nil {
            look.patternColour = nil
        } else if look.patternColour == nil {
            look.patternColour = defaultPatternColour(for: look.coat)
        }
        look.coat = valid(look.coat, in: data.coats, fallback: CatLook.midnight.coat, picked: true)
        look.patternColour = look.patternColour.map { valid($0, in: data.coats, fallback: look.coat, picked: true) }
        look.eyeLeft = valid(look.eyeLeft, in: data.eyes, fallback: CatLook.midnight.eyeLeft, picked: false)
        look.eyeRight = valid(look.eyeRight, in: data.eyes, fallback: look.eyeLeft, picked: false)
        look.nose = valid(look.nose, in: data.noses, fallback: CatLook.midnight.nose, picked: false)
        look.eyeSize = min(1, max(0, look.eyeSize))
        look.whiskerLength = min(1, max(0, look.whiskerLength))
        if case let .adult(years) = look.age {
            look.age = .adult(years: min(Tuning.Cat.maxAdultYears, max(1, years)))
        }
        return look
    }

    private func valid(
        _ colour: LookColour,
        in palette: [CatBuilderData.Swatch],
        fallback: LookColour,
        picked allowed: Bool
    ) -> LookColour {
        switch colour {
        case let .named(name): palette.contains { $0.id == name } ? colour : fallback
        case let .picked(rgb): allowed ? .picked(Self.pickerClamped(rgb)) : fallback
        }
    }

    // MARK: Colours

    /// A pattern colour that shows on the coat: the palette colour nearest a darker shade of it (a lighter one
    /// on a dark coat), never the coat itself.
    public func defaultPatternColour(for coat: LookColour) -> LookColour {
        let base = rgb(coat, in: data.coats)
        let factor = base.luminance < Tuning.Cat.darkCoatLuminance ? 1.8 : 0.55
        let target = (Double(base.r) * factor, Double(base.g) * factor, Double(base.b) * factor)
        let nearest = data.coats.filter { LookColour.named($0.id) != coat }.min { a, b in
            func distance(_ c: RGB) -> Double {
                let dr = Double(c.r) - target.0, dg = Double(c.g) - target.1, db = Double(c.b) - target.2
                return dr * dr + dg * dg + db * db
            }
            return distance(a.rgb) < distance(b.rgb)
        }
        return nearest.map { .named($0.id) } ?? coat
    }

    /// A picked coat or pattern colour, its luminance held to 40–250 so the painted shading still reads.
    public static func pickerClamped(_ rgb: RGB) -> RGB {
        let lum = rgb.luminance
        let target = min(Tuning.Cat.pickerMaxLuminance, max(Tuning.Cat.pickerMinLuminance, lum))
        guard abs(target - lum) > 0.01 else { return rgb }
        let shift = Int((target - lum).rounded())
        func clamp(_ v: Int) -> Int {
            min(255, max(0, v + shift))
        }
        return RGB(clamp(rgb.r), clamp(rgb.g), clamp(rgb.b))
    }

    public func rgb(_ colour: LookColour, in palette: [CatBuilderData.Swatch]) -> RGB {
        switch colour {
        case let .named(name): palette.first { $0.id == name }?.rgb ?? palette.first?.rgb ?? RGB(0, 0, 0)
        case let .picked(rgb): rgb
        }
    }

    /// The colours the coat recipe takes for a look.
    public struct Colours: Hashable, Sendable {
        public var coat: RGB
        public var pattern: RGB?
        public var eyeLeft: RGB
        public var eyeRight: RGB
        public var nose: RGB
    }

    public func colours(_ look: CatLook) -> Colours {
        Colours(
            coat: rgb(look.coat, in: data.coats),
            pattern: look.pattern == nil ? nil : rgb(look.patternColour ?? look.coat, in: data.coats),
            eyeLeft: rgb(look.eyeLeft, in: data.eyes),
            eyeRight: rgb(look.eyeRight, in: data.eyes),
            nose: rgb(look.nose, in: data.noses)
        )
    }

    // MARK: Sprites

    /// One painted sprite of a look, relative to cat/custom/base (its masks sit at the same path under
    /// cat/custom/masks/<mask>/). Swap ears and the bobtail take the pattern but never white markings.
    public struct Sprite: Hashable, Sendable {
        public var path: String
        public var takesWhite: Bool
    }

    /// A puppet part in a view ("side", "tqfront", "front", "tqback").
    public func part(_ name: String, view: String, look: CatLook) -> Sprite {
        if name.hasPrefix("ear_"), look.ears != "own" {
            let side = name == "ear_far" ? "far" : "near"
            return Sprite(path: "ears/ear_\(look.ears)_\(view)_\(side).png", takesWhite: false)
        }
        if name.hasPrefix("tail_"), look.tail == "bobtail" {
            let pose = name.dropFirst("tail_".count)
            return Sprite(path: "tails/bobtail_\(view)_\(pose).png", takesWhite: false)
        }
        return Sprite(path: "parts/cat_\(look.body)_\(view)_\(name).png", takesWhite: true)
    }

    /// A painted resting pose ("sit_side", "loaf_tqfront", "sleep_curl"...), with the look's ears and tail
    /// painted in for the standard bodies.
    public func pose(_ pose: String, look: CatLook) -> Sprite {
        var variant: [String] = []
        if look.ears != "own" {
            variant.append(look.ears)
        }
        if look.tail != "own" {
            variant.append(look.tail)
        }
        let suffix = variant.isEmpty ? "" : "__" + variant.joined(separator: "_")
        return Sprite(path: "poses/cat_\(look.body)_\(pose)\(suffix).png", takesWhite: true)
    }

    /// A head with an expression ("calm", "slowblink", "content", "surprised", "sleepy", "squint").
    public func expressionHead(_ expression: String, view: String, look: CatLook) -> Sprite {
        let set = body(look.body)?.expressionHeads ?? "stdnoear"
        return Sprite(path: "expr/head_\(set)_\(view)_\(expression).png", takesWhite: true)
    }
}

/// The word filter for names (Content/names.json): `words` are caught as whole words, `anywhere` inside
/// a name too, after spacing and look-alike characters are taken out ("F.u.c.k", "Sh1t").
public struct NameFilter: Codable, Sendable {
    public var words: [String]
    public var anywhere: [String]

    public init(words: [String] = [], anywhere: [String] = []) {
        self.words = words
        self.anywhere = anywhere
    }
}

/// The cat's own name (SPEC "Cat builder"): required, up to 20 characters, through the word filter
/// because groups show it; three suggestions and a shuffle.
public enum CatNames {
    public enum Check: Equatable, Sendable {
        case ok(String)
        case empty
        case tooLong
        case blocked
    }

    public static func check(_ name: String, filter: NameFilter) -> Check {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if trimmed.isEmpty {
            return .empty
        }
        if trimmed.count > Tuning.Cat.nameMaxLength {
            return .tooLong
        }
        return isBlocked(trimmed, filter: filter) ? .blocked : .ok(trimmed)
    }

    static func isBlocked(_ name: String, filter: NameFilter) -> Bool {
        let plain = normalised(name)
        let words = Set(plain.split(separator: " ").map(String.init))
        let squashed = plain.replacingOccurrences(of: " ", with: "")
        func key(_ word: String) -> String {
            normalised(word).replacingOccurrences(of: " ", with: "")
        }
        if filter.words.map(key).contains(where: { !$0.isEmpty && (words.contains($0) || squashed == $0) }) {
            return true
        }
        return filter.anywhere.map(key).contains { !$0.isEmpty && squashed.contains($0) }
    }

    private static func normalised(_ text: String) -> String {
        let swaps: [Character: Character] = [
            "0": "o",
            "1": "i",
            "3": "e",
            "4": "a",
            "5": "s",
            "7": "t",
            "8": "b",
            "@": "a",
            "$": "s",
            "!": "i",
        ]
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let mapped = folded.map { swaps[$0] ?? $0 }.map { $0.isLetter ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Three suggestions; each shuffle moves on to the next three, in an order fixed by the seed.
    public static func suggestions(from names: [String], seed: UInt64, shuffle: Int = 0) -> [String] {
        guard !names.isEmpty else { return [] }
        var rng = DaySeed(household: seed, day: GameDay(year: 2026, month: 1, day: 1), purpose: "names")
        let order = rng.shuffled(Array(names.indices))
        let start = shuffle * 3
        return (0 ..< min(3, names.count)).map { names[order[(start + $0) % names.count]] }
    }
}
