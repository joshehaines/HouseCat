/// Deterministic randomness for a game day. The app, the widget, the Watch and
/// the Mac draw the same numbers from the same household seed, day and purpose,
/// so they agree without talking. Uses its own generator and range reduction
/// (not the standard library's) so results never change with a Swift version.
public struct DaySeed: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// - Parameters:
    ///   - household: the save's random seed, fixed when the household is created.
    ///   - day: the game day.
    ///   - purpose: what the numbers are for ("gift", "objectives.daily", …).
    ///   - salt: anything else that must vary the draw (a cat id).
    public init(household: UInt64, day: GameDay, purpose: String, salt: String = "") {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ bytes: some Sequence<UInt8>) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01B3
            }
        }
        withUnsafeBytes(of: household.littleEndian) { mix($0) }
        withUnsafeBytes(of: Int64(day.index).littleEndian) { mix($0) }
        mix(purpose.utf8)
        mix([0])
        mix(salt.utf8)
        state = hash
    }

    /// SplitMix64.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform integer in 0 ..< bound, by rejection sampling.
    public mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0)
        let range = UInt64(bound)
        let limit = UInt64.max - UInt64.max % range
        while true {
            let value = next()
            if value < limit {
                return Int(value % range)
            }
        }
    }

    /// Picks an index with probability proportional to its weight. Zero and
    /// negative weights are never picked; returns nil if nothing can be.
    public mutating func pick(weights: [Int]) -> Int? {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return nil }
        var roll = below(total)
        for (index, weight) in weights.enumerated() where weight > 0 {
            if roll < weight {
                return index
            }
            roll -= weight
        }
        return nil
    }

    /// A deterministic shuffle (Fisher–Yates).
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var items = items
        guard items.count > 1 else { return items }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, below(i + 1))
        }
        return items
    }
}
