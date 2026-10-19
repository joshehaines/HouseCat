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
    // The puppet's own walk (moving, the cat is a film: CatFilmTests).
    CatNode.films = false
    defer { CatNode.films = true }
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
            var parts = try #require(rig.sets[look.body]?[view.rawValue]?.parts)
            if view == .side, Tuning.Puppet.sideHeadsWithEars.contains(look.body), look.ears == "own" {
                // Its side head is painted with its own ear: no ear parts over it.
                parts = parts.filter { !$0.key.hasPrefix("ear_") }
            }
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

/// The legs bend at the hock and the wrist and a planted paw stays put (Josh, 19 Oct: the back legs looked strange
/// going sideways; then the front legs had no joints): the cat walks across the floor at its own pace, and while a
/// paw is down it moves less than a whisker; between plants it lifts clear of the floor. Every leg, on every kind of
/// body: short and slim, short and chunky, oriental, long-haired and slim (its single legs), Maine Coon.
@MainActor
@Test(arguments: ["midnight", "british_blue", "oriental", "turkish_van", "maine_coon"])
func aPlantedPawStaysPutAsTheCatWalks(preset: String) throws {
    // The puppet's own walk (in a look without its film: a body garment, swapped ears).
    CatNode.films = false
    defer { CatNode.films = true }
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let look = try #require(catArt.builder.data.presets.first { $0.id == preset }?.look)
    let scene = SKScene(size: CGSize(width: 2000, height: 600))
    let height: CGFloat = 300
    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: height)
    scene.addChild(cat)
    cat.position = CGPoint(x: 1600, y: 100)
    cat.show(.side, facingRight: false)
    cat.walk()
    let speed = CGFloat(Tuning.Puppet.walkSpeed) * height / 420
    cat.moveSpeed = speed
    cat.moveDirection = CGVector(dx: -1, dy: 0)
    let legs = ["leg_back_near", "leg_front_near", "leg_back_far", "leg_front_far"]
    var tracks: [String: [CGPoint]] = [:]
    for _ in 0 ..< 120 {
        let dt = 1.0 / 60
        cat.position.x -= speed * CGFloat(dt)
        cat.step(dt)
        for name in legs {
            try tracks[name, default: []].append(#require(cat.paw(name), "\(preset): \(name) is jointed"))
        }
    }
    for (name, track) in tracks {
        let ground = track.map(\.y).min() ?? 0
        // Runs of frames with the paw on the floor: within each, it barely moves along the floor.
        var run: [CGPoint] = [], worst: CGFloat = 0, lifted: CGFloat = 0
        for point in track {
            lifted = max(lifted, point.y - ground)
            if point.y - ground < height * 0.004 {
                run.append(point)
            } else {
                if let first = run.first, let last = run.last, run.count > 4 {
                    worst = max(worst, abs(last.x - first.x))
                }
                run = []
            }
        }
        #expect(worst < height * 0.02, "\(preset): \(name)'s planted paw slid \(worst)")
        #expect(lifted > height * 0.03, "\(preset): \(name)'s paw lifts between plants (\(lifted))")
    }
}
