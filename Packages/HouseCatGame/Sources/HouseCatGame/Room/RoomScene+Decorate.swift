import HouseCatCore
import SpriteKit

/// Decorating (SPEC "The session loop" 7), moved the way a base is laid out in a builder game: press a
/// piece to pick it up, the room's grid shows, drag and it snaps cell by cell with its footprint green
/// where it fits and red where it does not, let go to put it down (or it springs back). Turn and store
/// act on the piece picked up. Whether a spot fits is HouseCatCore's `PlacementRules`; the app records
/// each change as an event.
public extension RoomScene {
    /// A change the player made, for the app to append to the save.
    enum DecorateChange: Equatable, Sendable {
        case moved(placementID: UUID, x: Int, y: Int, facing: GameEvent.Facing)
        case stored(placementID: UUID)
    }

    /// Turns decorate mode on or off: the grid, and touches that move furniture rather than pan.
    func setDecorating(_ on: Bool) {
        // Furniture is moved in the active room only, so only on its storey.
        decorating = on && storey == house.storey
        deselect()
        decorateGrid?.removeFromParent()
        decorateGrid = nil
        guard on, let room = activeRoom else { return }
        let grid = gridLines(in: room)
        room.addChild(grid)
        decorateGrid = grid
    }

    /// The piece picked up, if any.
    var selectedPlacement: UUID? {
        selection?.placementID
    }

    /// Turns the picked-up piece to face the other wall, if it fits that way (a wall item moves to the other wall).
    func turnSelection() {
        guard let selection, let room = activeRoom, let item = items[selection.placement.id] else { return }
        var piece = selection.piece.turned()
        if piece.onWall {
            // Keep its place along the wall it moves to.
            piece = PlacementRules.snap(piece, centreU: Double(selection.piece.y), centreV: Double(selection.piece.x))
        }
        guard PlacementRules.fits(piece, among: others(than: selection.placementID, in: room)) else {
            flash(fits: false, piece: piece, item: item, in: room)
            return
        }
        commit(piece, for: selection, in: room)
    }

    /// Every piece in the active room as the placement rules see them (for finding room for a new one).
    func pieces() -> [PlacementRules.Piece] {
        guard let room = activeRoom else { return [] }
        return room.model.items.compactMap { placement in
            guard let item = items[placement.id] else { return nil }
            return PlacementRules.Piece(
                item,
                placementID: placement.placementID,
                x: Int(placement.u.rounded()),
                y: Int(placement.v.rounded()),
                facing: placement.facing == "L" ? .left : .right
            )
        }
    }

    /// Puts a piece from the inventory into the active room and picks it up, ready to drag.
    func place(_ placement: RoomModel.Placement) {
        guard let room = activeRoom else { return }
        room.add(placement)
        guard decorating, let sprite = room.placements[placement.placementID ?? UUID()] else { return }
        let point = convert(CGPoint(x: sprite.position.x, y: sprite.position.y + sprite.size.height * 0.3), from: room)
        if beginDecorating(point) {
            dragging = false
        }
    }

    /// Puts the picked-up piece away in the inventory.
    func storeSelection() {
        guard let selection, let room = activeRoom else { return }
        deselect()
        room.remove(selection.placementID)
        onDecorate?(.stored(placementID: selection.placementID))
    }

    /// Picks up a piece by item id without a touch (screenshots and previews).
    func selectForScreenshot(_ itemID: String) {
        guard decorating, let room = activeRoom, let sprite = room.furniture[itemID] else { return }
        let point = convert(CGPoint(x: sprite.position.x, y: sprite.position.y + sprite.size.height * 0.3), from: room)
        if beginDecorating(point) {
            dragging = false
        }
    }

    // MARK: Touches

    /// Picks up the piece under a touch (scene coordinates). Returns false when there is none, so the touch pans.
    internal func beginDecorating(_ point: CGPoint) -> Bool {
        guard let room = activeRoom else { return false }
        let local = convert(point, to: room)
        let hit = room.nodes(at: local)
            .compactMap { node -> (SKSpriteNode, RoomModel.Placement)? in
                guard let sprite = node as? SKSpriteNode, let placement = room.placement(of: sprite) else { return nil }
                return (sprite, placement)
            }
            .max { $0.0.zPosition < $1.0.zPosition }
        guard let (sprite, placement) = hit, let id = placement.placementID, let item = items[placement.id] else {
            deselect()
            return false
        }
        if selection?.placementID != id {
            deselect()
            let facing: GameEvent.Facing = placement.facing == "L" ? .left : .right
            let piece = PlacementRules.Piece(
                item,
                placementID: id,
                x: Int(placement.u.rounded()),
                y: Int(placement.v.rounded()),
                facing: facing
            )
            selection = Selection(placementID: id, placement: placement, piece: piece, original: piece, sprite: sprite)
            sprite.run(.scale(to: CGFloat(Tuning.Decorate.liftScale), duration: Tuning.Decorate.liftSeconds))
            showFootprint(piece, fits: true, item: item, in: room)
        }
        // Hold the piece by where it was touched, so it does not jump to the finger.
        let cell = grid.cell(at: local)
        if let piece = selection?.piece {
            let (eu, ev) = piece.extent
            grabOffset = CGVector(dx: Double(piece.x) + Double(eu) / 2 - cell.u, dy: Double(piece.y) + Double(ev) / 2 - cell.v)
        }
        dragging = true
        return true
    }

    internal func dragDecorating(to point: CGPoint) {
        guard var current = selection, let room = activeRoom, let item = items[current.placement.id] else { return }
        let cell = grid.cell(at: convert(point, to: room))
        let piece = PlacementRules.snap(current.piece, centreU: cell.u + grabOffset.dx, centreV: cell.v + grabOffset.dy)
        guard piece != current.piece else { return }
        current.piece = piece
        selection = current
        room.position(current.sprite, item: item, placement: placement(current.placement, at: piece))
        current.sprite.zPosition += CGFloat(Tuning.Decorate.liftZ)
        showFootprint(piece, fits: PlacementRules.fits(piece, among: others(than: current.placementID, in: room)), item: item, in: room)
    }

    internal func endDecorating(at _: CGPoint) {
        dragging = false
        guard let current = selection, let room = activeRoom, let item = items[current.placement.id] else { return }
        if current.piece == current.original {
            room.position(current.sprite, item: item, placement: current.placement)
            return
        }
        if PlacementRules.fits(current.piece, among: others(than: current.placementID, in: room)) {
            commit(current.piece, for: current, in: room)
        } else {
            cancelDrag()
        }
    }

    /// Springs the picked-up piece back to where it was.
    internal func cancelDrag() {
        dragging = false
        guard var current = selection, let room = activeRoom, let item = items[current.placement.id] else { return }
        current.piece = current.original
        selection = current
        room.position(current.sprite, item: item, placement: current.placement)
        showFootprint(current.original, fits: true, item: item, in: room)
    }

    // MARK: Helpers

    private func placement(_ placement: RoomModel.Placement, at piece: PlacementRules.Piece) -> RoomModel.Placement {
        var moved = placement
        moved.u = Double(piece.x)
        moved.v = Double(piece.y)
        moved.facing = piece.facing == .left ? "L" : "R"
        return moved
    }

    private func commit(_ piece: PlacementRules.Piece, for current: Selection, in room: RoomNode) {
        let moved = placement(current.placement, at: piece)
        room.replace(moved)
        onDecorate?(.moved(placementID: current.placementID, x: piece.x, y: piece.y, facing: piece.facing))
        // Stay picked up in the new place, like a builder game: the player can keep nudging it.
        guard let sprite = room.placements[current.placementID], let item = items[moved.id] else {
            deselect()
            return
        }
        sprite.setScale(CGFloat(Tuning.Decorate.liftScale))
        selection = Selection(placementID: current.placementID, placement: moved, piece: piece, original: piece, sprite: sprite)
        showFootprint(piece, fits: true, item: item, in: room)
    }

    private func deselect() {
        selection?.sprite.run(.scale(to: 1, duration: Tuning.Decorate.liftSeconds))
        selection = nil
        footprintNode?.removeFromParent()
        footprintNode = nil
        dragging = false
    }

    /// Every other piece in the room, as the rules see them.
    private func others(than placementID: UUID, in room: RoomNode) -> [PlacementRules.Piece] {
        room.model.items.compactMap { placement in
            guard placement.placementID != placementID, let item = items[placement.id] else { return nil }
            return PlacementRules.Piece(
                item,
                placementID: placement.placementID,
                x: Int(placement.u.rounded()),
                y: Int(placement.v.rounded()),
                facing: placement.facing == "L" ? .left : .right
            )
        }
    }

    /// The footprint on the floor (a wall item's strip along its wall), green where it fits, red where not.
    private func showFootprint(_ piece: PlacementRules.Piece, fits: Bool, item _: CatalogueFile.Item, in room: RoomNode) {
        footprintNode?.removeFromParent()
        let (eu, ev) = piece.extent
        let x = CGFloat(piece.x), y = CGFloat(piece.y), u = CGFloat(eu), v = CGFloat(ev)
        let path = CGMutablePath()
        path.move(to: grid.floor(x, y))
        path.addLine(to: grid.floor(x + u, y))
        path.addLine(to: grid.floor(x + u, y + v))
        path.addLine(to: grid.floor(x, y + v))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        let c = fits ? Tuning.Decorate.fitColor : Tuning.Decorate.blockedColor
        shape.fillColor = SKColor(red: c[0], green: c[1], blue: c[2], alpha: CGFloat(Tuning.Decorate.footprintAlpha))
        shape.strokeColor = SKColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
        shape.lineWidth = 4
        shape.zPosition = RoomNode.Layer.decals + 2
        room.addChild(shape)
        footprintNode = shape
    }

    private func flash(fits: Bool, piece: PlacementRules.Piece, item: CatalogueFile.Item, in room: RoomNode) {
        showFootprint(piece, fits: fits, item: item, in: room)
        footprintNode?.run(.sequence([.wait(forDuration: Tuning.Decorate.flashSeconds), .removeFromParent()]))
        if let selection {
            run(.sequence([.wait(forDuration: Tuning.Decorate.flashSeconds), .run { [weak self] in
                guard let self, let room = activeRoom, let item = items[selection.placement.id] else { return }
                showFootprint(selection.piece, fits: true, item: item, in: room)
            }]))
        }
    }

    /// The floor grid, shown while decorating.
    private func gridLines(in _: RoomNode) -> SKShapeNode {
        let n = Int(grid.cells), path = CGMutablePath()
        for i in 0 ... n {
            let k = CGFloat(i)
            path.move(to: grid.floor(k, 0))
            path.addLine(to: grid.floor(k, grid.cells))
            path.move(to: grid.floor(0, k))
            path.addLine(to: grid.floor(grid.cells, k))
        }
        let lines = SKShapeNode(path: path)
        lines.strokeColor = SKColor(white: 1, alpha: CGFloat(Tuning.Decorate.gridAlpha))
        lines.lineWidth = 3
        lines.zPosition = RoomNode.Layer.decals + 1
        lines.name = "decorate.grid"
        return lines
    }
}

/// The piece being moved while decorating.
struct Selection {
    var placementID: UUID
    var placement: RoomModel.Placement
    var piece: PlacementRules.Piece
    var original: PlacementRules.Piece
    var sprite: SKSpriteNode
}
