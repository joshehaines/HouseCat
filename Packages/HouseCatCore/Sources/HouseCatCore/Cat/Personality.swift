/// The four personalities (SPEC "Personality"). A personality changes lines and
/// behaviour weights only; it never changes economy numbers.
public enum Personality: String, CaseIterable, Codable, Sendable {
    case aloof
    case velcro
    case gremlin
    case loaf

    public struct Sliders: Equatable, Sendable {
        public var affection: Double
        public var energy: Double
        public var mischief: Double
        public var independence: Double
    }

    public var sliders: Sliders {
        let values = switch self {
        case .aloof: Tuning.Personality.aloof
        case .velcro: Tuning.Personality.velcro
        case .gremlin: Tuning.Personality.gremlin
        case .loaf: Tuning.Personality.loaf
        }
        return Sliders(affection: values[0], energy: values[1], mischief: values[2], independence: values[3])
    }

    /// Activities this personality favours (weighted up in the behaviour table).
    public var favourites: Set<Activity> {
        switch self {
        case .loaf: [.sleep, .sunbeamLoaf]
        case .gremlin: [.knockOff, .hide]
        case .velcro: [.nearPlayer]
        case .aloof: [.perch, .windowWatch]
        }
    }

    /// Whether repeated petting makes the cat walk off (never a Velcro cat).
    public func walksOff(afterConsecutivePets taps: Int) -> Bool {
        self != .velcro && taps >= Tuning.Care.overPetTaps
    }
}
