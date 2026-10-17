import HouseCatCore
import SpriteKit

/// The room view: a 2:1 isometric corner room (two walls meeting at the back,
/// a 10 × 10 floor). Milestone 0 draws placeholder shapes with the right
/// footprints; milestone 1 swaps in the projected tiles, light maps, furniture
/// sprites and the cat puppet.
public final class RoomScene: SKScene {
    /// A placeholder item: a coloured block standing on its floor footprint.
    struct PlaceholderItem {
        let cell: (x: Int, y: Int)
        let footprint: (w: Int, d: Int)
        let height: CGFloat
        let color: SKColor
        let name: String
    }

    private let items: [PlaceholderItem] = [
        PlaceholderItem(
            cell: (1, 6),
            footprint: (3, 1),
            height: 0.9,
            color: .init(red: 0.36, green: 0.62, blue: 0.62, alpha: 1),
            name: "Sofa"
        ),
        PlaceholderItem(
            cell: (6, 1),
            footprint: (1, 1),
            height: 0.7,
            color: .init(red: 0.80, green: 0.62, blue: 0.40, alpha: 1),
            name: "Box"
        ),
        PlaceholderItem(
            cell: (4, 3),
            footprint: (2, 2),
            height: 0.05,
            color: .init(red: 0.93, green: 0.66, blue: 0.56, alpha: 1),
            name: "Rug"
        ),
    ]

    override public init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func didMove(to _: SKView) {
        layoutRoom()
    }

    override public func didChangeSize(_: CGSize) {
        layoutRoom()
    }

    // MARK: Projection

    private var tileWidth: CGFloat = 64
    private var origin: CGPoint = .zero

    private var tileHeight: CGFloat {
        tileWidth / 2
    }

    /// Screen point of a floor grid corner; (0, 0) is the back corner, x runs
    /// down the right wall and y down the left wall.
    private func floorPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + (x - y) * tileWidth / 2,
            y: origin.y - (x + y) * tileHeight / 2
        )
    }

    private func raised(_ point: CGPoint, by cells: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y + cells * tileHeight * 1.6)
    }

    private func polygon(_ points: [CGPoint], fill: SKColor, stroke: SKColor? = nil) -> SKShapeNode {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke ?? .clear
        node.lineWidth = stroke == nil ? 0 : 1
        node.isAntialiased = true
        return node
    }

    // MARK: Layout

    private func layoutRoom() {
        removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }

        let gridW = CGFloat(Tuning.Room.gridWidth)
        let gridD = CGFloat(Tuning.Room.gridDepth)
        let wallH = CGFloat(Tuning.Room.wallHeightCells)

        // Fit the room (floor plus walls) inside the scene with a margin.
        let roomWidthTiles = (gridW + gridD) / 2
        let roomHeightTiles = (gridW + gridD) / 4 + wallH * 0.8
        tileWidth = min(size.width * 0.9 / roomWidthTiles, size.height * 0.8 / roomHeightTiles)
        let roomHeight = roomHeightTiles * tileWidth
        origin = CGPoint(
            x: size.width / 2,
            y: size.height / 2 + roomHeight / 2 - wallH * tileHeight * 1.6
        )

        let back = floorPoint(0, 0)
        let right = floorPoint(gridW, 0)
        let left = floorPoint(0, gridD)
        let front = floorPoint(gridW, gridD)

        // Walls: left in a warm peach, right in a cooler mint (Mediterranean palette).
        addChild(polygon(
            [back, left, raised(left, by: wallH), raised(back, by: wallH)],
            fill: SKColor(red: 0.96, green: 0.78, blue: 0.66, alpha: 1)
        ))
        addChild(polygon(
            [back, right, raised(right, by: wallH), raised(back, by: wallH)],
            fill: SKColor(red: 0.70, green: 0.88, blue: 0.82, alpha: 1)
        ))

        // Window on the right wall, door on the left wall.
        addChild(polygon(
            [
                raised(floorPoint(4, 0), by: 1.8),
                raised(floorPoint(7, 0), by: 1.8),
                raised(floorPoint(7, 0), by: 4.0),
                raised(floorPoint(4, 0), by: 4.0),
            ],
            fill: SKColor(red: 0.55, green: 0.76, blue: 0.96, alpha: 1)
        ))
        addChild(polygon(
            [floorPoint(0, 6), floorPoint(0, 8), raised(floorPoint(0, 8), by: 3.4), raised(floorPoint(0, 6), by: 3.4)],
            fill: SKColor(red: 0.42, green: 0.32, blue: 0.40, alpha: 1)
        ))

        // Floor with its 10 × 10 grid.
        addChild(polygon([back, right, front, left], fill: SKColor(red: 0.90, green: 0.80, blue: 0.62, alpha: 1)))
        let grid = CGMutablePath()
        for i in 0 ... Tuning.Room.gridWidth {
            grid.move(to: floorPoint(CGFloat(i), 0))
            grid.addLine(to: floorPoint(CGFloat(i), gridD))
        }
        for j in 0 ... Tuning.Room.gridDepth {
            grid.move(to: floorPoint(0, CGFloat(j)))
            grid.addLine(to: floorPoint(gridW, CGFloat(j)))
        }
        let gridNode = SKShapeNode(path: grid)
        gridNode.strokeColor = SKColor(white: 0.3, alpha: 0.18)
        gridNode.lineWidth = 1
        addChild(gridNode)

        // Placeholder furniture: floor decals (rugs) first, then back to front by floor anchor.
        let drawOrder = items.sorted {
            ($0.height > 0.1 ? 1 : 0, $0.cell.x + $0.cell.y) < ($1.height > 0.1 ? 1 : 0, $1.cell.x + $1.cell.y)
        }
        for item in drawOrder {
            addChild(block(for: item))
        }

        addChild(placeholderCat(at: floorPoint(6.5, 5.5)))

        let label = SKLabelNode(text: "Placeholder room")
        label.fontName = "Georgia-Bold"
        label.fontSize = max(14, tileWidth * 0.35)
        label.fontColor = SKColor(red: 0.27, green: 0.20, blue: 0.27, alpha: 0.8)
        label.position = CGPoint(x: size.width / 2, y: max(24, front.y - tileWidth * 0.9))
        addChild(label)
    }

    private func block(for item: PlaceholderItem) -> SKNode {
        let x0 = CGFloat(item.cell.x), y0 = CGFloat(item.cell.y)
        let x1 = x0 + CGFloat(item.footprint.w), y1 = y0 + CGFloat(item.footprint.d)
        let base = [floorPoint(x0, y0), floorPoint(x1, y0), floorPoint(x1, y1), floorPoint(x0, y1)]
        let top = base.map { raised($0, by: item.height) }
        let node = SKNode()
        node.name = item.name
        let darker = item.color.darkened(by: 0.25)
        let darkest = item.color.darkened(by: 0.4)
        node.addChild(polygon([base[1], base[2], top[2], top[1]], fill: darker))
        node.addChild(polygon([base[2], base[3], top[3], top[2]], fill: darkest))
        node.addChild(polygon(top, fill: item.color))
        return node
    }

    private func placeholderCat(at point: CGPoint) -> SKNode {
        let fur = SKColor(red: 0.15, green: 0.14, blue: 0.19, alpha: 1)
        let cat = SKNode()
        cat.name = "Cat"
        let unit = tileWidth
        let body = SKShapeNode(ellipseOf: CGSize(width: unit * 0.9, height: unit * 0.55))
        body.fillColor = fur
        body.strokeColor = SKColor(red: 0.95, green: 0.62, blue: 0.30, alpha: 0.9)
        body.lineWidth = 1.5
        body.position = CGPoint(x: point.x, y: point.y + unit * 0.3)
        let head = SKShapeNode(circleOfRadius: unit * 0.26)
        head.fillColor = fur
        head.strokeColor = body.strokeColor
        head.lineWidth = 1.5
        head.position = CGPoint(x: point.x - unit * 0.35, y: point.y + unit * 0.68)
        for dx in [-0.1, 0.1] {
            let eye = SKShapeNode(circleOfRadius: unit * 0.05)
            eye.fillColor = SKColor(red: 0.98, green: 0.72, blue: 0.20, alpha: 1)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: dx * unit, y: unit * 0.02)
            head.addChild(eye)
        }
        cat.addChild(body)
        cat.addChild(head)
        return cat
    }
}

private extension SKColor {
    /// Mixes the colour towards black; placeholder shading for block sides.
    func darkened(by amount: CGFloat) -> SKColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let keep = 1 - amount
        return SKColor(red: red * keep, green: green * keep, blue: blue * keep, alpha: alpha)
    }
}
