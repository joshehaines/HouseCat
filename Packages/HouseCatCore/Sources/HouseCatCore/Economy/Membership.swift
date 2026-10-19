import Foundation

/// Who looks after the cat (CLAUDE.md "Leaving and removing"): the owner, and co-owners who joined by an invite
/// and have not left or been removed. Leaving takes nothing from the household (the Reducer's `applyMembership`).
public extension HouseholdState {
    /// The co-owners now, by actor key (never the original owner), in a steady order.
    var coOwners: [String] {
        owners.filter { $0 != GameEvent.Actor.owner.key }.sorted()
    }

    /// Whether `key` looks after the cat now. False once they left or were removed: a removed co-owner's phone
    /// learns it from the owner's `coOwnerRemoved`.
    func isMember(_ key: String) -> Bool {
        owners.contains(key) && !formerOwners.contains(key)
    }

    /// Everyone else who looks after the cat, as the phone of `me` sees them.
    func otherOwners(than me: String) -> [String] {
        owners.filter { $0 != me }.sorted()
    }
}

/// A household's reference for a report to safety@: eight characters made from the household's seed, the same
/// on every phone that shares the cat, saying nothing about who anyone is and not giving the seed back.
/// Shown as "HC-K7PQ-3MAC".
public enum HouseholdReference {
    public static func code(seed: UInt64) -> String {
        // SplitMix64's finaliser, so neighbouring seeds give unrelated codes.
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let alphabet = FriendCode.alphabet
        let base = UInt64(alphabet.count)
        var characters: [Character] = []
        for _ in 0 ..< 8 {
            characters.append(alphabet[Int(z % base)])
            z /= base
        }
        return "HC-" + String(characters.prefix(4)) + "-" + String(characters.suffix(4))
    }
}

/// A report about another owner (App Review 1.2: a way to report what one person typed that another sees), sent
/// from the person's own mail app to safety@ with what it is about filled in, so they only add what happened.
/// HouseCat has no server; the household reference lets a reply find nothing more than the report itself.
public struct SafetyReport: Equatable, Sendable {
    public enum About: String, CaseIterable, Sendable {
        /// The name a co-owner chose (the only name of a person that anyone sees).
        case name
        /// The cat's name, which either owner can set.
        case catName
        /// A present one owner gave the cat.
        case present
        case other
    }

    public var about: About
    /// The other owner as this phone knows them: a co-owner's chosen name (even if hidden here), or "the owner".
    public var reported: String
    public var catName: String
    /// The household's reference (`HouseholdReference.code`).
    public var household: String
    /// The present's name, when the report is about one.
    public var present: String?
    public var appVersion: String

    public init(about: About, reported: String, catName: String, household: String, present: String? = nil, appVersion: String) {
        self.about = about
        self.reported = reported
        self.catName = catName
        self.household = household
        self.present = present
        self.appVersion = appVersion
    }

    public var subject: String {
        "HouseCat report (\(household))"
    }

    public var body: String {
        let what = switch about {
        case .name: "Their name"
        case .catName: "The cat's name"
        case .present: "A present" + (present.map { ": \($0)" } ?? "")
        case .other: "Something else"
        }
        return """
        What happened (optional):



        ---
        About: \(what)
        Who: \(reported)
        Cat: \(catName)
        Household: \(household)
        App: HouseCat \(appVersion)
        """
    }

    /// The mail to open: `mailto:` with the subject and body filled in.
    public func mailto(to address: String = Tuning.Store.safetyEmail) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }
}
