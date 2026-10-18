#if DEBUG
    import HouseCatCore
    import HouseCatGame
    import HouseCatUI
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
                          let shape = OutfitShapes.shape(path, art: art), let face = catArt.face(sprite.path),
                          let dressed = OutfitFit.compose(
                              image,
                              face: face,
                              outfit: picture,
                              shape: shape,
                              kind: kind,
                              view: view,
                              size: outfit.fit,
                              tallEars: OutfitFit.tallEars(look)
                          )
                    else { return image }
                    return dressed.image
                }
                return (id, images)
            }
        }
    }
#endif
