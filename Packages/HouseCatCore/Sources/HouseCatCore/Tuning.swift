/// Every tunable constant in HouseCat. Values come from docs/SPEC.md, where each
/// number is a locked decision; tune them here and nowhere else.
public enum Tuning {
    /// Room geometry: 2:1 isometric corner rooms (SPEC "Perspective").
    public enum Room {
        public static let gridWidth = 10
        public static let gridDepth = 10
        public static let wallHeightCells = 5
    }
}
