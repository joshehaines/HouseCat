@testable import HouseCatCore
import Testing

@Test func roomGridIsTenByTenWithFiveCellWalls() {
    #expect(Tuning.Room.gridWidth == 10)
    #expect(Tuning.Room.gridDepth == 10)
    #expect(Tuning.Room.wallHeightCells == 5)
}
