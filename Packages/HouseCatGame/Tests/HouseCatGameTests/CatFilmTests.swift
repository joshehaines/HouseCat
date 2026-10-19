import HouseCatCore
@testable import HouseCatGame
import SpriteKit
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Walking and running, the cat is a film (Josh, 19 Oct: "B is the best by far"): every body has its walk and its run
/// filmed from the side and at three-quarters, each frame a sprite tinted into the look like the puppet's parts, and
/// the cat shows the film, and only the film, while it moves; standing, the puppet again.
@MainActor
@Test(arguments: ["midnight", "british_blue", "turkish_van", "ragdoll", "white_persian", "seal_point", "maine_coon", "sphynx"])
func everyBodyWalksAndRunsAsAFilm(preset: String) throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    var look = try #require(catArt.builder.data.presets.first { $0.id == preset }?.look)
    // The film is the body's own ears and tail.
    look.ears = "own"
    look.tail = "own"
    for view in ["side", "tqfront"] {
        for gait in ["walk", "run"] {
            let film = try #require(catArt.film(body: look.body, view: view, gait: gait), "\(look.body) \(view) \(gait)")
            #expect(film.frames.count >= 6, "\(look.body) \(view) \(gait): a stride of frames")
            // A whole stride, not half of one (the near and far legs swapped at the loop) or two.
            let stride = gait == "run" ? 1.0...3.75 : 0.55...1.75
            #expect(stride.contains(film.seconds), "\(look.body) \(view) \(gait): a stride lasts \(film.seconds) s")
            for frame in film.frames {
                #expect(catArt.has(frame), "\(frame)")
            }
        }
    }
    let scene = SKScene(size: CGSize(width: 800, height: 600))
    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
    scene.addChild(cat)
    cat.loadFilmsNow()
    for view in [CatNode.View.side, .tqfront] {
        for gait in [CatNode.Gait.walk, .trot, .run] {
            #expect(cat.hasFilm(view, gait), "\(preset) \(view) \(gait)")
            cat.show(view, facingRight: view == .tqfront)
            cat.move(gait)
            cat.moveSpeed = 170
            cat.step(1.0 / 30)
            #expect(cat.isFilming, "\(preset) \(view) \(gait): the film")
            #expect(cat.drawingsOnShow == 1, "\(preset) \(view) \(gait): one cat")
            cat.stopCycle()
            #expect(!cat.isFilming, "\(preset) \(view): standing, the puppet")
            #expect(cat.drawingsOnShow == 1)
        }
    }
    // Coming straight at you, the puppet (there is no film from the front).
    cat.show(.front, facingRight: false)
    cat.walk()
    cat.step(1.0 / 30)
    #expect(!cat.isFilming)
    cat.stopCycle()
    // Sitting down from the film: the film through the dip, then the painting alone.
    cat.show(.side, facingRight: false)
    cat.walk()
    cat.step(1.0 / 30)
    cat.settle(into: .sitSide)
    #expect(cat.drawingsOnShow == 1, "\(preset): sitting down from the film")
}

/// Swapped ears and a bobtail go on the film (the film's own cut out, the look's own pieces on the followed points); a
/// body garment walks as the rebuilt puppet (the films have none).
@MainActor
@Test func swappedEarsAndABobtailWalkAsTheFilmAGarmentAsThePuppet() throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let look = catArt.builder.normalized(CatLook(ears: "folded", tail: "bobtail"))
    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
    cat.loadFilmsNow()
    for view in [CatNode.View.side, .tqfront] {
        cat.show(view, facingRight: false)
        cat.walk()
        cat.step(1.0 / 30)
        #expect(cat.isFilming, "\(view): the film")
        #expect(cat.drawingsOnShow == 1)
        let pieces = cat.childNode(withName: "//piece").map { _ in true } ?? false
        #expect(pieces, "\(view): the swapped ears and the bobtail on it")
        cat.stopCycle()
    }
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    if let jumper = content.outfits.outfits.first(where: { $0.slot == .body }) {
        cat.wear(jumper)
        cat.show(.side, facingRight: false)
        cat.walk()
        cat.step(1.0 / 30)
        #expect(!cat.isFilming, "in a garment, the puppet")
        #expect(cat.drawingsOnShow == 1)
    }
}
