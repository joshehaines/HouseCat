/// The player's level from cumulative XP (SPEC "XP and levels"). Levels only rise.
public enum LevelCurve {
    /// Cumulative XP needed to reach a level; level 1 needs 0.
    public static func threshold(for level: Int) -> Int {
        let table = Tuning.Levels.thresholds
        guard level > 1 else { return 0 }
        if level <= table.count {
            return table[level - 1]
        }
        return table[table.count - 1] + (level - table.count) * Tuning.Levels.xpPerLevelAfterTable
    }

    public static func level(forXP xp: Int) -> Int {
        let table = Tuning.Levels.thresholds
        if xp >= table[table.count - 1] {
            return table.count + (xp - table[table.count - 1]) / Tuning.Levels.xpPerLevelAfterTable
        }
        return table.lastIndex { $0 <= xp }.map { $0 + 1 } ?? 1
    }

    /// XP gained inside the current level and XP still needed for the next.
    public static func progress(xp: Int) -> (level: Int, intoLevel: Int, toNext: Int) {
        let level = level(forXP: xp)
        let start = threshold(for: level)
        return (level, xp - start, threshold(for: level + 1) - xp)
    }
}
