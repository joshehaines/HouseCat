#if DEBUG
    import HouseCatCore
    import HouseCatGame
    import HouseCatUI
    import SpriteKit
    import SwiftUI

    /// Debug (HOUSECAT_SCREEN=outfits, HOUSECAT_GALLERY=<body>): the cat in every resting pose wearing each kind of
    /// outfit, drawn with OutfitFit, for checking the fit by eye.
    struct OutfitGallery: View {
        private let outfits = ["beanie", "crown", "roundglasses", "sunglasses", "scarf", "bowtie", "santahat"]
        private let poses: [CatPose] = [
            .sitThreeQuarterFront,
            .sitFront,
            .sitSide,
            .loafThreeQuarterFront,
            .loafSide,
            .stretchSide,
            .sitBack,
        ]
        @State private var rows: [(String, [CGImage])] = []

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.0) { name, images in
                        HStack(spacing: 4) {
                            Text(name).font(.caption2).frame(width: 64, alignment: .leading)
                            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                                    .frame(width: 52, height: 52)
                                    .background(Color.white.opacity(0.25))
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(red: 0.36, green: 0.5, blue: 0.62).ignoresSafeArea())
            .task { rows = build() }
        }

        private func build() -> [(String, [CGImage])] {
            guard let catArt = GameWorld.catArt, let art = GameWorld.art, let content = GameWorld.content else { return [] }
            var look = GameSession.shared.cat?.look ?? .midnight
            if let body = ProcessInfo.processInfo.environment["HOUSECAT_GALLERY"] {
                look.body = body
            }
            return outfits.compactMap { id in
                guard let outfit = content.outfits.outfits.first(where: { $0.id == id }),
                      let kind = OutfitFit.kind(outfit) else { return nil }
                let images = poses.compactMap { pose -> CGImage? in
                    let sprite = catArt.builder.pose(pose.rawValue, look: look)
                    guard let image = catArt.image(sprite, look: look) else { return nil }
                    guard let view = OutfitFit.view(for: pose), let path = outfit.sprites[view], let picture = art.image(path),
                          let shape = OutfitShapes.shape(path, art: art), let face = OutfitFit.restingFace(pose, look: look, catArt: catArt, art: art, for: kind),
                          let dressed = OutfitFit.compose(
                              image,
                              face: face,
                              outfit: picture,
                              shape: shape,
                              kind: kind,
                              view: view,
                              size: outfit.fit,
                              tallEars: OutfitFit.tallEars(look, wearing: outfit),
                              pose: pose,
                              coversEars: OutfitFit.coversEars(outfit)
                          )
                    else { return image }
                    return dressed.image
                }
                return (id, images)
            }
        }
    }

    /// Debug (HOUSECAT_SCREEN=puppets, HOUSECAT_GALLERY_PAGE=<n>, HOUSECAT_GALLERY_KIND=stand|rest,
    /// HOUSECAT_GALLERY=<body>): the room's own puppet cat wearing each wearable outfit, standing in every view
    /// both ways, or in every resting pose that keeps its outfit, three outfits a page, for checking by eye what
    /// the room draws.
    struct PuppetGallery: View {
        var body: some View {
            GeometryReader { geometry in
                SpriteView(scene: Self.scene(size: geometry.size))
            }
            .ignoresSafeArea()
        }

        private static let pageSize = 3

        private static func scene(size: CGSize) -> SKScene {
            let scene = SKScene(size: size)
            scene.backgroundColor = SKColor(red: 0.36, green: 0.5, blue: 0.62, alpha: 1)
            guard let art = GameWorld.art, let rig = GameWorld.rig, let catArt = GameWorld.catArt,
                  let content = GameWorld.content else { return scene }
            let environment = ProcessInfo.processInfo.environment
            var look = GameSession.shared.cat?.look ?? .midnight
            if let body = environment["HOUSECAT_GALLERY"] {
                look.body = body
            }
            let page = environment["HOUSECAT_GALLERY_PAGE"].flatMap(Int.init) ?? 0
            // HOUSECAT_GALLERY_OUTFITS=antlers,scarf: just those, one row each.
            let chosen = environment["HOUSECAT_GALLERY_OUTFITS"]?.split(separator: ",").map(String.init)
            let wearable = content.outfits.outfits.filter(\.wearable)
            let outfits = chosen.map { ids in ids.compactMap { id in wearable.first { $0.id == id } } }
                ?? Array(wearable.dropFirst(page * pageSize).prefix(pageSize))
            let rowsPerPage = max(1, outfits.count)
            let resting = environment["HOUSECAT_GALLERY_KIND"] == "rest"
            let stands: [(CatNode.View, Bool)] = resting ? [] : [(.side, false), (.side, true), (.tqfront, false), (.front, false)]
            let poses: [CatPose] = resting ? [.sitThreeQuarterFront, .sitFront, .sitSide, .loafThreeQuarterFront, .loafSide, .sitBack] : []
            let columns = stands.count + poses.count
            let left: CGFloat = 70
            let cellWidth = (size.width - left) / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rowsPerPage)
            for (row, outfit) in outfits.enumerated() {
                let baseline = size.height - CGFloat(row + 1) * cellHeight + cellHeight * 0.08
                let label = SKLabelNode(text: outfit.id)
                label.fontSize = 13
                label.fontName = "Helvetica-Bold"
                label.horizontalAlignmentMode = .left
                label.position = CGPoint(x: 8, y: baseline + cellHeight * 0.4)
                scene.addChild(label)
                for column in 0 ..< columns {
                    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: cellHeight * (resting ? 0.78 : 0.62))
                    cat.position = CGPoint(x: left + (CGFloat(column) + 0.5) * cellWidth, y: baseline)
                    cat.wear(outfit)
                    scene.addChild(cat)
                    if column < stands.count {
                        cat.show(stands[column].0, facingRight: stands[column].1)
                    } else {
                        cat.show(.tqfront, facingRight: false)
                        cat.settle(into: poses[column - stands.count], duration: 0.01)
                    }
                }
            }
            return scene
        }
    }
#endif
