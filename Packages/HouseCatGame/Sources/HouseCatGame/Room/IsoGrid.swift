import CoreGraphics
import HouseCatCore

/// The 2:1 isometric corner room in room units: one unit is one pixel of the
/// reference room the furniture was painted in, where a floor cell is 144 wide
/// and 72 tall and a wall cell is 72 high. The back corner of the floor is the
/// origin; y points up (SpriteKit). `u` runs down the right wall, `v` down the left.
public struct IsoGrid: Sendable {
    public var cellHalfWidth: CGFloat = 72
    /// The room's floor in cells: along the right wall (u) and the left (v).
    public var cellsU = CGFloat(Tuning.Room.gridWidth)
    public var cellsV = CGFloat(Tuning.Room.gridDepth)
    public var wallCells = CGFloat(Tuning.Room.wallHeightCells)

    public init(_ size: RoomSize = .standard) {
        cellsU = CGFloat(size.u)
        cellsV = CGFloat(size.v)
    }

    public var size: RoomSize {
        RoomSize(u: Int(cellsU), v: Int(cellsV))
    }

    /// One cell of height on a wall.
    public var unit: CGFloat {
        cellHalfWidth
    }

    /// A point on the floor.
    public func floor(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: (u - v) * cellHalfWidth, y: -(u + v) * cellHalfWidth / 2)
    }

    /// A point on the right wall (`along` cells from the back corner, `up` cells high).
    public func rightWall(_ along: CGFloat, up: CGFloat) -> CGPoint {
        let p = floor(along, 0)
        return CGPoint(x: p.x, y: p.y + up * unit)
    }

    /// A point on the left wall.
    public func leftWall(_ along: CGFloat, up: CGFloat) -> CGPoint {
        let p = floor(0, along)
        return CGPoint(x: p.x, y: p.y + up * unit)
    }

    /// The floor position under a screen point (inverse of `floor`).
    public func cell(at point: CGPoint) -> (u: CGFloat, v: CGFloat) {
        let a = point.x / cellHalfWidth
        let b = -2 * point.y / cellHalfWidth
        return ((a + b) / 2, (b - a) / 2)
    }

    /// The whole room's bounds: walls and floor.
    public var bounds: CGRect {
        let left = floor(0, cellsV).x, right = floor(cellsU, 0).x
        let bottom = floor(cellsU, cellsV).y, top = wallCells * unit
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Draw order for something standing at a floor position: further forward draws later.
    public func depth(_ u: CGFloat, _ v: CGFloat) -> CGFloat {
        u + v
    }
}
