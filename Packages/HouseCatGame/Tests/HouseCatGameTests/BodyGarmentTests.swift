import CoreGraphics
import Foundation
import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The body garments (fisherman's jumper to skeleton onesie) on the shipped art: painted for every body over each
/// resting pose a cat is dressed in and over the puppet's torso in each view, at those paintings' sizes, so they
/// are worn wherever the cat is seen.
@MainActor
@Suite("Body garments")
struct BodyGarmentTests {
    let art: ArtLibrary
    let catArt: CatArt
    let garments: [OutfitsFile.Outfit]

    init() throws {
        art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
        catArt = try CatArt(art: art)
        let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        garments = content.outfits.outfits.filter { $0.slot == .body }
    }

    @Test func everyGarmentIsPaintedForEveryBodyAtItsPaintingsSize() throws {
        #expect(garments.count == 9)
        let pad = CGFloat(Tuning.Outfits.torsoPad)
        for outfit in garments {
            for body in catArt.builder.data.bodies.map(\.id) {
                for pose in CatPose.allCases {
                    guard let path = OutfitFit.garment(outfit, body: body, pose: pose) else { continue }
                    #expect(art.has(path), "\(path)")
                    #expect(FileManager.default.fileExists(atPath: art.url(path).path), "\(path) is bundled")
                    // Drawn exactly over the pose's base painting.
                    #expect(art.paintedSize(path) == catArt.paintedSize("poses/cat_\(body)_\(pose.rawValue).png"), "\(path)")
                }
                for view in CatNode.View.allCases {
                    let path = try #require(OutfitFit.garment(outfit, body: body, view: view.rawValue))
                    #expect(art.has(path), "\(path)")
                    let torso = catArt.paintedSize("parts/cat_\(body)_\(view.rawValue)_torso.png")
                    let size = art.paintedSize(path)
                    #expect(abs(size.width - torso.width * (1 + 2 * pad)) <= 2, "\(path) \(size) for a torso \(torso)")
                    #expect(abs(size.height - torso.height * (1 + 2 * pad)) <= 2, "\(path) \(size) for a torso \(torso)")
                }
            }
        }
    }

    @Test func aCurledOrStretchingCatWearsNoGarmentAndNothingElseHasOne() throws {
        let jumper = try #require(garments.first { $0.id == "fisherman" })
        #expect(OutfitFit.garment(jumper, body: "short_slim", pose: .sleepCurl) == nil)
        #expect(OutfitFit.garment(jumper, body: "short_slim", pose: .stretchSide) == nil)
        #expect(OutfitFit.garment(jumper, body: "short_slim", pose: .loafSide) != nil)
        let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
        let beanie = try #require(content.outfits.outfits.first { $0.id == "beanie" })
        #expect(OutfitFit.garment(beanie, body: "short_slim", pose: .sitFront) == nil)
        #expect(OutfitFit.garment(beanie, body: "short_slim", view: "side") == nil)
    }

    @Test func anEarOrTailVariantCarriesTheGarmentWhereItsBasePaintingSits() {
        let base = "poses/cat_short_slim_sit_front.png"
        #expect(GarmentPlacement.frame(drawn: base, base: base, catArt: catArt, art: art) == CGRect(x: 0, y: 0, width: 1, height: 1))
        for variant in ["folded", "tufted", "oriental", "rounded", "bobtail", "tufted_bobtail"] {
            let drawn = "poses/cat_short_slim_sit_front__\(variant).png"
            #expect(catArt.has(drawn), "\(drawn)")
            let frame = GarmentPlacement.frame(drawn: drawn, base: base, catArt: catArt, art: art)
            let d = catArt.paintedSize(drawn), b = catArt.paintedSize(base)
            // The base's size in the variant's units, standing on the same ground and centred on the same cat (its
            // ears may stand above a variant with lower ones: the garment is clear there).
            #expect(abs(frame.width - b.width / d.width) < 0.001 && abs(frame.height - b.height / d.height) < 0.001, "\(variant)")
            #expect(abs(frame.maxY - 1) < 0.03 && abs(frame.midX - 0.5) < 0.05, "\(variant) \(frame)")
        }
        // Tufted ears are taller than the base's: the body sits lower in the picture.
        let tufted = GarmentPlacement.frame(drawn: "poses/cat_short_slim_sit_front__tufted.png", base: base, catArt: catArt, art: art)
        #expect(tufted.minY > 0.05)
    }

    @Test func thePuppetWearsItWalkingAndResting() throws {
        let rig = try art.data("cat/rig.json", as: PuppetRig.self)
        let raincoat = try #require(garments.first { $0.id == "raincoat" })
        for body in ["short_slim", "persian", "mainecoon"] {
            let cat = CatNode(art: art, rig: rig, catArt: catArt, look: catArt.builder.normalized(CatLook(body: body)), height: 150)
            cat.wear(raincoat)
            for view in CatNode.View.allCases {
                let torso = try #require(cat.parts[view]?["torso"])
                let garment = try #require(torso.childNode(withName: "outfit") as? SKSpriteNode, "\(body) \(view)")
                #expect(garment.texture.map { $0.size().width > 1 } == true)
                // Over the torso, under the head that hangs from it.
                let head = try #require(cat.parts[view]?["head"])
                #expect(garment.zPosition > 0)
                if head.parent === torso {
                    #expect(garment.zPosition < head.zPosition, "\(body) \(view)")
                }
            }
            cat.settle(into: .sitThreeQuarterFront, duration: 0)
            let onPose = try #require(cat.poseOutfit as? SKSpriteNode, "\(body) sitting")
            #expect(onPose.size.width > 10 && onPose.size.height > 10)
            cat.settle(into: .sleepCurl, duration: 0)
            #expect(cat.poseOutfit == nil, "\(body) curled up")
            cat.wear(nil)
            #expect(cat.parts[.side]?["torso"]?.childNode(withName: "outfit") == nil)
        }
    }
}
