import Foundation

/// Where furniture may go when decorating (SPEC "The session loop" 7): on the room's grid, inside the
/// room, never overlapping another standing piece; rugs and mats lie under anything but not on each
/// other; wall items hang on the wall they face (R on the right wall, L on the left) and never overlap
/// along it. The scene snaps a drag to a cell and colours the footprint by `fits`.
public enum PlacementRules {
    /// One placed (or to-be-placed) piece on a room's grid.
    public struct Piece: Equatable, Sendable {
        public var placementID: UUID?
        public var x: Int
        public var y: Int
        /// Cells along u and v when facing R; a piece turned to face L swaps them.
        public var width: Int
        public var depth: Int
        public var facing: GameEvent.Facing
        public var onWall: Bool
        public var decal: Bool

        public init(placementID: UUID? = nil, x: Int, y: Int, width: Int, depth: Int, facing: GameEvent.Facing, onWall: Bool, decal: Bool) {
            self.placementID = placementID
            self.x = x
            self.y = y
            self.width = width
            self.depth = depth
            self.facing = facing
            self.onWall = onWall
            self.decal = decal
        }

        public init(_ item: CatalogueFile.Item, placementID: UUID? = nil, x: Int, y: Int, facing: GameEvent.Facing) {
            self.init(
                placementID: placementID,
                x: x,
                y: y,
                width: item.footprint.w,
                depth: item.footprint.d,
                facing: facing,
                onWall: item.layer == .wall,
                decal: item.decal
            )
        }

        /// Cells taken along u and v.
        public var extent: (u: Int, v: Int) {
            facing == .left ? (depth, width) : (width, depth)
        }

        /// The cells it covers on the floor (for a wall item, the strip of floor under it along its wall).
        var cells: Set<Int> {
            let (eu, ev) = extent
            var out = Set<Int>()
            for u in x ..< x + eu {
                for v in y ..< y + ev {
                    out.insert(u * 1000 + v)
                }
            }
            return out
        }

        public func turned() -> Piece {
            var piece = self
            piece.facing = facing == .left ? .right : .left
            return piece
        }
    }

    /// Whether a piece can stand where it is, among the others in the room (its own old self excluded).
    public static func fits(_ piece: Piece, among others: [Piece], roomCells: Int = Tuning.Room.gridWidth) -> Bool {
        let (eu, ev) = piece.extent
        guard piece.x >= 0, piece.y >= 0, piece.x + eu <= roomCells, piece.y + ev <= roomCells else { return false }
        if piece.onWall {
            // Against its wall: the right wall is v = 0, the left wall u = 0.
            guard piece.facing == .right ? piece.y == 0 : piece.x == 0 else { return false }
        }
        let mine = piece.cells
        for other in others where other.placementID == nil || other.placementID != piece.placementID {
            // Wall items only meet wall items on the same wall; rugs only meet rugs; the rest meet the rest.
            guard other.onWall == piece.onWall, other.decal == piece.decal else { continue }
            if piece.onWall, other.facing != piece.facing {
                continue
            }
            if !mine.isDisjoint(with: other.cells) {
                return false
            }
        }
        return true
    }

    /// The cell a piece snaps to when its footprint's centre is dragged to a floor point (in cells); wall
    /// items slide along their wall.
    public static func snap(_ piece: Piece, centreU: Double, centreV: Double, roomCells: Int = Tuning.Room.gridWidth) -> Piece {
        var snapped = piece
        let (eu, ev) = piece.extent
        snapped.x = min(max(Int((centreU - Double(eu) / 2).rounded()), 0), roomCells - eu)
        snapped.y = min(max(Int((centreV - Double(ev) / 2).rounded()), 0), roomCells - ev)
        if piece.onWall {
            if piece.facing == .right {
                snapped.y = 0
            } else {
                snapped.x = 0
            }
        }
        return snapped
    }
}
