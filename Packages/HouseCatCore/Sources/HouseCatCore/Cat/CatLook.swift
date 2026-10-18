import Foundation

/// An sRGB colour, 0–255 a channel.
public struct RGB: Codable, Hashable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From "#rrggbb".
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }

    /// The coat recipe's luminance weights (SPEC "Coat recipe").
    public var luminance: Double {
        0.3 * Double(r) + 0.55 * Double(g) + 0.15 * Double(b)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try self.init(container.decode(Int.self), container.decode(Int.self), container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(r)
        try container.encode(g)
        try container.encode(b)
    }
}

/// A colour in a look: a palette colour by name ("ginger"), or one from the free picker ("#d6682e").
/// Stored as that one string, so a look stays readable in the save and in a group's profile card.
public enum LookColour: Codable, Hashable, Sendable {
    case named(String)
    case picked(RGB)

    public init(_ string: String) {
        if string.hasPrefix("#"), let rgb = RGB(hex: string) {
            self = .picked(rgb)
        } else {
            self = .named(string)
        }
    }

    public var string: String {
        switch self {
        case let .named(name): name
        case let .picked(rgb): rgb.hex
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// The cat's age when it comes home: a kitten (12 weeks, grown at day 21) or an adult of some years.
public enum CatAge: Codable, Hashable, Sendable {
    case kitten
    case adult(years: Int)

    public static let defaultAdult = CatAge.adult(years: Tuning.Cat.adultDefaultAgeDays / 365)

    public var isKitten: Bool {
        self == .kitten
    }

    /// Days old on the day it comes home.
    public var startDays: Int {
        switch self {
        case .kitten: Tuning.Cat.kittenStartAgeDays
        case let .adult(years): max(1, years) * 365
        }
    }

    /// "kitten", or "adult:<years>".
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        if string == "kitten" {
            self = .kitten
        } else if let years = Int(string.split(separator: ":").last ?? ""), string.hasPrefix("adult:") {
            self = .adult(years: years)
        } else {
            self = .defaultAdult
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .kitten: try container.encode("kitten")
        case let .adult(years): try container.encode("adult:\(years)")
        }
    }
}

/// What a cat looks like (SPEC "Cat builder"): the fields of catbuilder.json's `look_fields`, in the same
/// names, plus the weight slider. Every option is a catbuilder.json id; colours are palette names or picked
/// colours. Groups, co-owning and the stray share this, so it is small and plain.
public struct CatLook: Codable, Hashable, Sendable {
    /// A body set: "short_slim", "short_chunky", "long_slim", "long_chunky" or a breed.
    public var body: String
    /// Shorthair and Longhair only: 0 slim … 1 chunky. Past the midpoint the chunky set is drawn;
    /// within a set the torso widens with it (`Tuning.Cat.weightStretch`).
    public var weight: Double
    /// "own" or a swap ear (rounded, folded, tufted, oriental); breeds keep their own.
    public var ears: String
    /// "own" or "bobtail"; breeds keep their own.
    public var tail: String
    public var coat: LookColour
    /// A pattern mask id, or nil for solid.
    public var pattern: String?
    public var patternColour: LookColour?
    /// A white-marking mask id, or nil.
    public var white: String?
    /// The eye on the left of the image, and the other one (odd eyes when they differ).
    public var eyeLeft: LookColour
    public var eyeRight: LookColour
    public var nose: LookColour
    /// 0 … 1; 0.5 is the eyes as painted.
    public var eyeSize: Double
    /// 0 … 1; 1 is the whiskers as painted, shorter below.
    public var whiskerLength: Double
    public var age: CatAge

    public init(
        body: String = "short_slim",
        weight: Double? = nil,
        ears: String = "own",
        tail: String = "own",
        coat: LookColour = .named("black"),
        pattern: String? = nil,
        patternColour: LookColour? = nil,
        white: String? = nil,
        eyeLeft: LookColour = .named("amber"),
        eyeRight: LookColour? = nil,
        nose: LookColour = .named("black"),
        eyeSize: Double = 0.5,
        whiskerLength: Double = 1,
        age: CatAge = .defaultAdult
    ) {
        self.body = body
        self.weight = weight ?? (body.hasSuffix("_chunky") ? Tuning.Cat.chunkyDefaultWeight : Tuning.Cat.slimDefaultWeight)
        self.ears = ears
        self.tail = tail
        self.coat = coat
        self.pattern = pattern
        self.patternColour = patternColour
        self.white = white
        self.eyeLeft = eyeLeft
        self.eyeRight = eyeRight ?? eyeLeft
        self.nose = nose
        self.eyeSize = eyeSize
        self.whiskerLength = whiskerLength
        self.age = age
    }

    /// Midnight, the mascot: the default cat and the first preset.
    public static let midnight = CatLook()

    enum CodingKeys: String, CodingKey {
        case body, weight, ears, tail, coat, pattern, white, nose, age
        case patternColour = "pattern_colour"
        case eyeLeft = "eye_left"
        case eyeRight = "eye_right"
        case eyeSize = "eye_size"
        case whiskerLength = "whisker_length"
    }

    /// Missing fields take the defaults, so presets (which leave out the sliders) and older looks decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let body = try c.decodeIfPresent(String.self, forKey: .body) ?? "short_slim"
        let eyeLeft = try c.decodeIfPresent(LookColour.self, forKey: .eyeLeft) ?? .named("amber")
        try self.init(
            body: body,
            weight: c.decodeIfPresent(Double.self, forKey: .weight),
            ears: c.decodeIfPresent(String.self, forKey: .ears) ?? "own",
            tail: c.decodeIfPresent(String.self, forKey: .tail) ?? "own",
            coat: c.decodeIfPresent(LookColour.self, forKey: .coat) ?? .named("black"),
            pattern: c.decodeIfPresent(String.self, forKey: .pattern),
            patternColour: c.decodeIfPresent(LookColour.self, forKey: .patternColour),
            white: c.decodeIfPresent(String.self, forKey: .white),
            eyeLeft: eyeLeft,
            eyeRight: c.decodeIfPresent(LookColour.self, forKey: .eyeRight) ?? eyeLeft,
            nose: c.decodeIfPresent(LookColour.self, forKey: .nose) ?? .named("black"),
            eyeSize: c.decodeIfPresent(Double.self, forKey: .eyeSize) ?? 0.5,
            whiskerLength: c.decodeIfPresent(Double.self, forKey: .whiskerLength) ?? 1,
            age: c.decodeIfPresent(CatAge.self, forKey: .age) ?? .defaultAdult
        )
    }

    public var hasOddEyes: Bool {
        eyeLeft != eyeRight
    }
}
