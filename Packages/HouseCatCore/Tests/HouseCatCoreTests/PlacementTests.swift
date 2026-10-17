import Foundation
@testable import HouseCatCore
import Testing

private func piece(
    _ x: Int,
    _ y: Int,
    _ w: Int = 1,
    _ d: Int = 1,
    facing: GameEvent.Facing = .right,
    wall: Bool = false,
    decal: Bool = false,
    id: UUID? = UUID()
) -> PlacementRules.Piece {
    PlacementRules.Piece(placementID: id, x: x, y: y, width: w, depth: d, facing: facing, onWall: wall, decal: decal)
}

@Test func piecesStayInsideTheRoom() {
    #expect(PlacementRules.fits(piece(0, 0, 3, 1), among: []))
    #expect(PlacementRules.fits(piece(7, 9, 3, 1), among: []))
    #expect(!PlacementRules.fits(piece(8, 0, 3, 1), among: []))
    #expect(!PlacementRules.fits(piece(-1, 0), among: []))
    // Turned to face L, a 3 × 1 sofa runs along v.
    #expect(PlacementRules.fits(piece(0, 7, 3, 1, facing: .left), among: []))
    #expect(!PlacementRules.fits(piece(0, 8, 3, 1, facing: .left), among: []))
}

@Test func standingPiecesNeverOverlapButRugsLieUnderThem() {
    let sofa = piece(2, 2, 3, 1)
    #expect(!PlacementRules.fits(piece(4, 2), among: [sofa]))
    #expect(PlacementRules.fits(piece(5, 2), among: [sofa]))
    #expect(PlacementRules.fits(piece(2, 2, 3, 2, decal: true), among: [sofa]))
    let rug = piece(2, 2, 3, 2, decal: true)
    #expect(!PlacementRules.fits(piece(3, 3, 2, 2, decal: true), among: [rug]))
}

@Test func aPieceDoesNotCollideWithItsOwnOldPlace() {
    let id = UUID()
    let old = piece(2, 2, 3, 1, id: id)
    #expect(PlacementRules.fits(piece(3, 2, 3, 1, id: id), among: [old]))
}

@Test func wallItemsHangOnTheWallTheyFaceAndOnlyMeetEachOther() {
    #expect(PlacementRules.fits(piece(4, 0, wall: true), among: []))
    #expect(!PlacementRules.fits(piece(4, 1, wall: true), among: []))
    #expect(PlacementRules.fits(piece(0, 4, facing: .left, wall: true), among: []))
    #expect(!PlacementRules.fits(piece(1, 4, facing: .left, wall: true), among: []))
    let picture = piece(4, 0, wall: true)
    #expect(!PlacementRules.fits(piece(4, 0, wall: true), among: [picture]))
    // A sofa against the wall does not stop a picture above it, and a picture on the other wall never meets it.
    #expect(PlacementRules.fits(piece(4, 0, wall: true), among: [piece(3, 0, 3, 1)]))
    #expect(PlacementRules.fits(piece(0, 0, facing: .left, wall: true), among: [piece(0, 0, wall: true)]))
}

@Test func dragsSnapToTheNearestCellAndWallItemsSlideAlongTheirWall() {
    let sofa = piece(0, 0, 3, 1)
    let snapped = PlacementRules.snap(sofa, centreU: 5.4, centreV: 6.6)
    #expect(snapped.x == 4 && snapped.y == 6)
    let edge = PlacementRules.snap(sofa, centreU: 9.9, centreV: 9.9)
    #expect(edge.x == 7 && edge.y == 9)
    let picture = PlacementRules.snap(piece(0, 0, wall: true), centreU: 6.2, centreV: 5)
    #expect(picture.x == 6 && picture.y == 0)
    let leftPicture = PlacementRules.snap(piece(0, 0, facing: .left, wall: true), centreU: 4, centreV: 3.3)
    #expect(leftPicture.x == 0 && leftPicture.y == 3)
}

@Test func turningSwapsTheFootprint() {
    let sofa = piece(0, 0, 3, 1)
    #expect(sofa.extent == (3, 1))
    #expect(sofa.turned().extent == (1, 3))
    #expect(sofa.turned().turned() == sofa)
}

@Test func everyRoomStartsWithAFreeWallpaperAndFloor() throws {
    let content = try ContentBundle.load(from: ContentValidationTests.repo.appendingPathComponent("Content"))
    for room in RoomID.allCases {
        for kind in [CatalogueFile.Surface.Kind.wall, .floor] {
            let surface = try #require(content.catalogue.defaultSurface(kind, in: room), "\(room) \(kind)")
            #expect(surface.pool == .free && surface.room == room.rawValue)
        }
    }
}
