import CoreGraphics
import Foundation
@testable import HouseCatGame
import HouseCatCore
import Testing

/// The outfit fit on the shipped art: every hat, glasses and neckwear finds its place on a sitting cat of each
/// standard body, inside the picture's width and above or below the eyes as it should be.
@Suite("Outfits fitted to the cat")
struct OutfitFitTests {
    let art = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../App/Art").standardized

    func face(_ body: String, _ pose: String) throws -> CatFace {
        let path = "poses/cat_\(body)_\(pose).png"
        let alpha = try #require(Raster.read(art.appendingPathComponent("cat/custom/alpha/\(path)")))
        // A pose with no face showing (from behind) has no features mask.
        let features = Raster.read(art.appendingPathComponent("cat/custom/masks/features/\(path)"))
        let planes = features.map { features in
            features.planes.prefix(3).map {
                features.width == alpha.width ? $0 : Raster.scaled($0, from: (features.width, features.height), to: (alpha.width, alpha.height))
            }
        } ?? []
        return OutfitFit.face(features: planes, alpha: alpha.planes[0], width: alpha.width, height: alpha.height)
    }

    func shape(_ outfit: String, _ view: String) throws -> OutfitShape {
        let picture = try #require(Raster.read(art.appendingPathComponent("outfits/outfit_\(outfit)_\(view).png")))
        return OutfitFit.shape(alpha: picture.planes[3], width: picture.width, height: picture.height)
    }

    @Test(arguments: ["short_slim", "short_chunky", "long_slim", "long_chunky"])
    func eachKindSitsWhereItShould(body: String) throws {
        for (pose, view) in [("sit_tqfront", "tqfront"), ("sit_front", "front")] {
            let f = try face(body, pose)
            #expect(f.eyes.count == 2, "\(body) \(pose)")
            let eyeY = f.eyes.map(\.y).reduce(0, +) / 2 * f.size.height
            let hat = try #require(OutfitFit.place(.hat, shape: shape("beanie", view), on: f, view: view))
            #expect(hat.point.y < eyeY, "the rim is above the eyes")
            #expect(hat.width > f.size.width * 0.3 && hat.width < f.size.width * 1.6, "\(body) \(pose) hat \(hat.width)")
            let glasses = try #require(OutfitFit.place(.glasses, shape: shape("roundglasses", view), on: f, view: view))
            #expect(abs(glasses.point.y - eyeY) < f.size.height * 0.03, "the lenses are on the eyes")
            let sunglasses = try #require(OutfitFit.place(.glasses, shape: shape("sunglasses", view), on: f, view: view))
            #expect(abs(sunglasses.point.y - eyeY) < f.size.height * 0.03)
            let scarf = try #require(OutfitFit.place(.neck, shape: shape("scarf", view), on: f, view: view))
            #expect(scarf.point.y > eyeY, "the band is under the chin")
        }
    }

    @Test func aCurledOrStretchingCatWearsNothingAndOneFromBehindKeepsItsHat() throws {
        #expect(OutfitFit.view(for: .sleepCurl) == nil)
        #expect(OutfitFit.view(for: .stretchSide) == nil)
        let back = try face("short_slim", "sit_back")
        #expect(back.eyes.isEmpty)
        let beanie = try shape("beanie", "tqback"), glasses = try shape("roundglasses", "tqback")
        #expect(OutfitFit.place(.hat, shape: beanie, on: back) != nil)
        #expect(OutfitFit.place(.glasses, shape: glasses, on: back) == nil)
    }
}
