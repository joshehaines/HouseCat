import CoreGraphics
import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The cat's ears (Josh, 20 Oct: "The ears on the cats need to be looked at, they are very buggy and show two sets of
/// ears"): one pair, the same size standing as sitting, wherever the cat is drawn.
@MainActor
@Suite("One pair of ears")
struct CatEarsTests {
    let art: ArtLibrary
    let catArt: CatArt
    let rig: PuppetRig

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        catArt = try CatArt(art: art)
        rig = try art.data("cat/rig.json", as: PuppetRig.self)
    }

    /// A swapped ear stands its shape's share of the body's own ear (measured off the sitting paintings, which have
    /// every shape painted in), so the ears keep their size as the cat sits down; they were drawn half as big again.
    @Test(arguments: ["short_slim", "short_chunky", "long_slim", "long_chunky"])
    func swappedEarsAreTheSizeTheSittingPaintingsShow(body: String) throws {
        let own = CatNode(art: art, rig: rig, catArt: catArt, look: catArt.builder.normalized(CatLook(body: body)), height: 150)
        for (shape, share) in Tuning.Puppet.swapEarLength {
            let look = catArt.builder.normalized(CatLook(body: body, ears: shape))
            let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
            for view in [CatNode.View.tqfront, .front] {
                for ear in ["ear_near", "ear_far"] {
                    let swapped = try #require(cat.parts[view]?[ear]), mine = try #require(own.parts[view]?[ear])
                    let ratio = swapped.size.height / mine.size.height
                    #expect(abs(ratio - CGFloat(share)) < 0.01, "\(body) \(shape) \(view) \(ear): \(ratio)")
                }
            }
        }
    }

    /// The long-haired slim body's side head is painted with its own ear; with swapped ears it is its painting with
    /// none, so the swapped pair is the only one.
    @Test func swappedEarsGoOnASideHeadWithNoneOfItsOwn() throws {
        let look = catArt.builder.normalized(CatLook(body: "long_slim", ears: "rounded"))
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
        let head = try #require(cat.parts[.side]?["head"])
        let earless = CatBuilder.Sprite(path: "parts/cat_long_slim_side_head_noears.png", takesWhite: true)
        #expect(catArt.has(earless.path))
        #expect(head.texture === catArt.texture(earless, look: look))
        #expect(cat.parts[.side]?["ear_near"] != nil && cat.parts[.side]?["ear_far"] != nil)
        // Its own ears: the painted one, no ear parts.
        let own = CatNode(art: art, rig: rig, catArt: catArt, look: catArt.builder.normalized(CatLook(body: "long_slim")), height: 150)
        #expect(own.parts[.side]?["ear_near"] == nil)
    }

    /// Walking with swapped ears, the film's own are cut out with nothing left beside the swapped pair: no fur of
    /// the film's ears outside its head (the ears' mask lags the ear, and the head's mask kept an ear's edge).
    @Test(arguments: ["short_slim", "short_chunky", "long_chunky", "sphynx"])
    func aFilmsOwnEarsAreCutCleanly(body: String) throws {
        let look = catArt.builder.normalized(CatLook(body: body, ears: body == "sphynx" ? "own" : "folded"))
        for view in ["side", "tqfront"] {
            let film = try #require(catArt.film(body: body, view: view, gait: "walk"))
            for path in film.frames.prefix(6) {
                let frame = try #require(catArt.filmFrame(path, look: look, cutting: ["ears"]))
                let alpha = try #require(Raster(frame)).planes[3]
                let size = (frame.width, frame.height)
                func plane(_ name: String) throws -> [UInt8] {
                    let raster = try #require(Raster.read(catArt.root.appendingPathComponent("masks/\(name)/\(path)")))
                    return Raster.scaled(raster.planes[0], from: (raster.width, raster.height), to: size)
                }
                // Outside the head (and a margin round it), where the film's ears were or a little beyond (their mask
                // lags them: the old cut left their rims there).
                let head = Raster.widened(try plane("head"), width: size.0, height: size.1, by: max(2, size.1 / 50))
                let ears = Raster.widened(try plane("ears"), width: size.0, height: size.1, by: max(2, size.1 / 40))
                var left = 0
                for index in alpha.indices where ears[index] > 128 && head[index] < 128 && alpha[index] > 96 {
                    left += 1
                }
                #expect(left == 0, "\(path): \(left) pixels of the film's ears left")
            }
        }
    }

    /// A hat the ears go under hides them on the puppet (the ear parts and any painted on the head) and on the
    /// painting, and the still pictures are cleared above its rim; a crown leaves them out.
    @Test func aHatTheEarsGoUnderHidesThem() throws {
        let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let outfits = Dictionary(uniqueKeysWithValues: content.outfits.outfits.map { ($0.id, $0) })
        let beanie = try #require(outfits["beanie"]), crown = try #require(outfits["crown"])
        #expect(OutfitFit.coversEars(beanie) && !OutfitFit.coversEars(crown))
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: .midnight, height: 150)
        cat.wear(beanie)
        for view in CatNode.View.allCases {
            #expect(cat.parts[view]?["ear_near"]?.isHidden == true, "\(view)")
            #expect(cat.parts[view]?["head"]?.shader != nil, "\(view)")
        }
        cat.settle(into: .sitThreeQuarterFront, duration: 0)
        #expect(cat.poseCovered)
        cat.wear(crown)
        #expect(!cat.poseCovered)
        for view in CatNode.View.allCases {
            #expect(cat.parts[view]?["ear_near"]?.isHidden == false, "\(view)")
            #expect(cat.parts[view]?["head"]?.shader == nil, "\(view)")
        }
        // A tall-eared cat's hat is not lifted when its ears go under it.
        let oriental = catArt.builder.normalized(CatLook(ears: "oriental"))
        #expect(OutfitFit.tallEars(oriental) && !OutfitFit.tallEars(oriental, wearing: beanie))
    }

    /// The still pictures (the plaque, the profile, the widget's poses): above a covering hat's rim the cat is cleared,
    /// so fewer of its pixels show there than with the ears left out.
    @Test(arguments: ["short_slim", "siamese", "mainecoon"])
    func aStillPictureUnderAHatHasNoEarsAboveIt(body: String) throws {
        let look = catArt.builder.normalized(CatLook(body: body))
        let sprite = catArt.builder.pose(CatPose.sitThreeQuarterFront.rawValue, look: look)
        let image = try #require(catArt.image(sprite, look: look))
        let face = try #require(catArt.face(sprite.path))
        let picture = try #require(art.image("outfits/outfit_beanie_tqfront.png"))
        let shape = try #require(OutfitShapes.shape("outfits/outfit_beanie_tqfront.png", art: art))
        func compose(_ covers: Bool) throws -> (CGImage, Int) {
            let made = try #require(OutfitFit.compose(
                image, face: face, outfit: picture, shape: shape, kind: .hat, view: "tqfront", size: 1.15,
                tallEars: false, pose: .sitThreeQuarterFront, coversEars: covers
            ))
            return (made.image, made.extra)
        }
        var scaled = face
        scaled.size = CGSize(width: image.width, height: image.height)
        let fit = try #require(OutfitFit.place(.hat, shape: shape, on: scaled, view: "tqfront", size: 1.15))
        let cover = try #require(OutfitFit.earCover(fit, shape: shape, on: scaled))
        func shown(_ made: (CGImage, Int)) throws -> Int {
            let alpha = try #require(Raster(made.0)).planes[3]
            var count = 0
            for y in stride(from: 0, to: image.height, by: 2) {
                for x in stride(from: 0, to: image.width, by: 2) where cover.hides(CGPoint(x: x, y: y)) > 0.99 {
                    count += alpha[(y + made.1) * made.0.width + x] > 128 ? 1 : 0
                }
            }
            return count
        }
        #expect(try shown(compose(true)) < shown(compose(false)), "\(body)")
    }
}
