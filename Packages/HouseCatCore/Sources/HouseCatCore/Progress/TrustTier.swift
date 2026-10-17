/// A cat's trust: the count of days it was fed, in tiers at 3, 7, 14, 30, 60
/// and 100 care days (SPEC "Two progressions"). Trust only ever rises.
public enum TrustTier: Int, CaseIterable, Codable, Comparable, Sendable {
    /// Fewer than three care days (the spec names no tier below Wary).
    case newcomer = 0
    case wary
    case curious
    case comfortable
    case bonded
    case devoted
    case soulmate

    public static func forCareDays(_ days: Int) -> TrustTier {
        let reached = Tuning.Trust.tierCareDays.filter { days >= $0 }.count
        return TrustTier(rawValue: reached) ?? .soulmate
    }

    /// Care days needed for this tier.
    public var careDaysRequired: Int {
        rawValue == 0 ? 0 : Tuning.Trust.tierCareDays[rawValue - 1]
    }

    public static func < (lhs: TrustTier, rhs: TrustTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
