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
        // Bundled as HEIC with its transparency (build_app_art.py).
        let picture = try #require(Raster.read(art.appendingPathComponent("outfits/outfit_\(outfit)_\(view).heic")))
        try #require(picture.planes.count == 4)
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

    /// The puppet's own heads (what the room draws while the cat walks).
    func headFace(_ body: String, _ view: String) throws -> CatFace {
        let path = "parts/cat_\(body)_\(view)_head.png"
        let alpha = try #require(Raster.read(art.appendingPathComponent("cat/custom/alpha/\(path)")))
        let features = Raster.read(art.appendingPathComponent("cat/custom/masks/features/\(path)"))
        let planes = features.map { features in
            features.planes.prefix(3).map {
                features.width == alpha.width ? $0 : Raster.scaled($0, from: (features.width, features.height), to: (alpha.width, alpha.height))
            }
        } ?? []
        return OutfitFit.face(features: planes, alpha: alpha.planes[0], width: alpha.width, height: alpha.height, headOnly: true)
    }

    @Test(arguments: ["short_slim", "short_chunky", "long_slim", "long_chunky", "persian", "siamese", "sphynx", "mainecoon"])
    func everyPuppetViewWearsEveryKind(body: String) throws {
        for view in ["side", "tqfront", "front"] {
            let f = try headFace(body, view)
            let beanie = try shape("beanie", view), scarf = try shape("scarf", view), glasses = try shape("roundglasses", view)
            #expect(OutfitFit.place(.hat, shape: beanie, on: f, view: view) != nil, "\(body) \(view) hat")
            #expect(OutfitFit.place(.neck, shape: scarf, on: f, view: view) != nil, "\(body) \(view) scarf (the neck is below the head's picture)")
            #expect(OutfitFit.place(.glasses, shape: glasses, on: f, view: view) != nil, "\(body) \(view) glasses")
            if view == "front", f.eyes.count == 2, let head = f.head {
                // Both eyes found on the face (a features mask once took the fur's edge for one).
                let middle = (head.left + head.right) / 2
                #expect(f.eyes[0].x < middle && f.eyes[1].x > middle, "\(body) front eyes either side of the middle")
                #expect(abs(f.eyes[1].y - f.eyes[0].y) < 0.08, "\(body) front eyes level")
            }
        }
    }

    /// Side-on a headband is as tall as the head is long allows (not the ears' height, which flaps as the cat runs),
    /// and no taller than a hat can be.
    @Test func aSideOnHeadbandIsNoTallerThanAHat() throws {
        let f = try headFace("short_slim", "side")
        let antlers = try shape("antlers", "side")
        let fit = try #require(OutfitFit.place(.hat, shape: antlers, on: f, view: "side", size: 1.35))
        let head = try #require(f.head), crown = try #require(f.crown)
        let lift = (head.y - crown.y) * f.size.height
        let (left, right) = try #require(OutfitFit.headSpan(f, eyes: OutfitFit.profileEyes(f, view: "side"), w: f.size.width, h: f.size.height))
        let height = fit.width * antlers.size.height / antlers.size.width
        #expect(abs(height - (right - left) * Tuning.Outfits.bandLift * Tuning.Outfits.bandHeight) < 1)
        #expect(height <= lift * Tuning.Outfits.hatMaxHeight)
    }

    @Test(arguments: ["short_slim", "short_chunky", "long_slim", "persian", "mainecoon"])
    func lyingDownTheGlassesFitTheHeadNotTheBody(body: String) throws {
        let sitting = try face(body, "sit_side"), lying = try face(body, "loaf_side")
        let glasses = try shape("roundglasses", "side")
        let a = try #require(OutfitFit.place(.glasses, shape: glasses, on: sitting, view: "side"))
        let b = try #require(OutfitFit.place(.glasses, shape: glasses, on: lying, view: "side"))
        // Against the eye's distance to the front of the face (the same head, whatever the picture's size).
        func front(_ f: CatFace) -> CGFloat {
            let eye = f.eyes[0].x * f.size.width, head = f.head!
            return min(eye - head.left * f.size.width, head.right * f.size.width - eye)
        }
        #expect(b.width / front(lying) < a.width / front(sitting) * 1.6, "\(body)")
        #expect(OutfitFit.tucksNeckwear(.loafSide) && !OutfitFit.tucksNeckwear(.sitSide))
    }

    @Test func aFlatFaceInProfileStillWearsAHat() throws {
        let f = try face("persian", "sit_side")
        let hat = try #require(OutfitFit.place(.hat, shape: shape("beanie", "side"), on: f, view: "side"))
        let head = try #require(f.head)
        #expect(hat.width > (head.right - head.left) * f.size.width * 0.5)
    }

    @Test func fromBehindATallEaredCatsHatIsHeadSized() throws {
        let f = try face("mainecoon", "sit_back")
        let head = try #require(f.head)
        #expect((head.right - head.left) >= Tuning.Outfits.backHeadMinWidth)
    }
}

