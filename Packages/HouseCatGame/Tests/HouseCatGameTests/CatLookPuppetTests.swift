import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Step 2's exit test: build any cat and it walks. Every preset (and the swap ears and the bobtail) gets a
/// puppet in every view with every part drawn, its legs swing when it walks, and it settles into its poses.
@MainActor
@Test func everyPresetBuildsAPuppetThatWalks() throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    var looks = catArt.builder.data.presets.map { ($0.id, $0.look) }
    for ears in ["rounded", "folded", "tufted", "oriental"] {
        looks.append(("ears \(ears)", catArt.builder.normalized(CatLook(ears: ears, tail: "bobtail"))))
    }
    for (name, look) in looks {
        let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
        for view in CatNode.View.allCases {
            let parts = try #require(rig.sets[look.body]?[view.rawValue]?.parts)
            #expect(Set(cat.parts[view]?.keys.map(\.self) ?? []) == Set(parts.keys), "\(name) \(view): every part")
            cat.show(view, facingRight: false)
            cat.walk()
            let leg = try #require(cat.parts[view]?["leg_front_near"])
            let rest = leg.zRotation
            cat.step(0.15)
            if view != .front {
                #expect(leg.zRotation != rest, "\(name) \(view): the legs swing")
            }
            for (part, node) in cat.parts[view] ?? [:] {
                #expect(node.texture.map { $0.size().width > 1 } == true, "\(name) \(view) \(part) has its painting")
            }
            cat.stopCycle()
        }
        for pose in CatPose.allCases {
            #expect(catArt.has(catArt.builder.pose(pose.rawValue, look: look).path), "\(name) \(pose)")
        }
        cat.settle(into: .sitThreeQuarterFront, duration: 0)
        #expect(cat.pose == .sitThreeQuarterFront)
    }
}

@MainActor
@Test func aMaineCoonIsBiggerAndAKittenSmaller() throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let coon = CatNode(art: art, rig: rig, catArt: catArt, look: CatLook(body: "mainecoon"), height: 150)
    #expect(abs(coon.height - 150 * 1.15) < 0.01)
    let kitten = CatNode(art: art, rig: rig, catArt: catArt, look: .midnight, isKitten: true, height: 150)
    #expect(abs(kitten.height - 150 * Tuning.Cat.kittenScale) < 0.01)
    // A new look redraws the same node.
    kitten.apply(look: CatLook(body: "sphynx"), isKitten: false)
    #expect(kitten.body == "sphynx")
    #expect(abs(kitten.height - 150) < 0.01)
}
