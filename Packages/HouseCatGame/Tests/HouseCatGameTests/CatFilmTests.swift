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
            // Standing still: the walk film's standing picture, held (21 Oct), never the puppet popping in between.
            for _ in 0 ..< 30 {
                cat.step(1.0 / 30)
            }
            #expect(cat.isFilming, "\(preset) \(view): standing, the film's standing picture")
            #expect(cat.drawingsOnShow == 1)
        }
    }
    // Coming straight at you: the front film where the body has one (short_slim first, 21 Oct), else the puppet.
    cat.show(.front, facingRight: false)
    cat.walk()
    cat.step(1.0 / 30)
    let front = catArt.film(body: look.body, view: "front", gait: "walk") != nil
    #expect(cat.isFilming == front, "\(preset): coming at you, \(front ? "the film" : "the puppet")")
    #expect(cat.drawingsOnShow == 1)
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
        cat.loadFilmsNow()
        cat.show(.side, facingRight: false)
        cat.walk()
        cat.step(1.0 / 30)
        // In a garment, the film with the garment drawn into its frames where it carries the torso's map (21 Oct);
        // on a film without the map, the puppet.
        let mapped = catArt.film(body: look.body, view: "side", gait: "walk").map { catArt.filmTakesGarments($0) } ?? false
        #expect(cat.isFilming == mapped, "in a garment, \(mapped ? "the film" : "the puppet")")
        #expect(cat.filmGarmentOn == mapped)
        #expect(cat.drawingsOnShow == 1)
    }
}

/// Scratching and sitting down are films where the body has them (21 Oct, Midnight's body first): the scratch film
/// rises and rakes round its loop until the cat is told to stop, then comes down the way it went up; the sit-down film
/// plays once, forwards, and the painting takes over on its last picture; getting up plays it backwards. Standing in
/// between, the walk film's standing picture; one drawing of the cat throughout.
@MainActor
@Test func scratchingAndSittingDownAreFilms() throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let look = catArt.builder.normalized(CatLook(body: "short_slim"))
    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
    let scene = SKScene(size: CGSize(width: 800, height: 600))
    scene.addChild(cat)
    cat.loadFilmsNow()
    cat.show(.side, facingRight: false)
    cat.step(1.0 / 30)
    #expect(cat.isFilming, "standing: the walk film's standing picture")
    cat.scratch()
    for _ in 0 ..< 60 {
        cat.step(1.0 / 30)
        #expect(cat.drawingsOnShow == 1)
    }
    #expect(cat.isScratching)
    #expect(cat.isFilming, "scratching on the film")
    let fall = cat.stopScratching()
    #expect(fall > 0, "down off the post takes time on the film")
    for _ in 0 ..< Int(fall * 30) + 3 {
        cat.step(1.0 / 30)
        #expect(cat.drawingsOnShow == 1)
    }
    #expect(!cat.isScratching)
    #expect(cat.isFilming, "standing again on the film")
    let sits = cat.settle(into: .sitSide)
    #expect(sits >= Tuning.Puppet.filmSitSeconds, "the sit-down film plays")
    for _ in 0 ..< Int(sits * 30) - 2 {
        cat.step(1.0 / 30)
        #expect(cat.drawingsOnShow == 1)
        #expect(cat.isFilming, "sitting down on the film")
    }
    for _ in 0 ..< 6 {
        cat.step(1.0 / 30)
    }
    #expect(cat.pose == .sitSide)
    #expect(!cat.isFilming, "sat: the painting")
    #expect(cat.drawingsOnShow == 1)
    let rises = cat.rise(to: .side, facingRight: false)
    #expect(rises >= Tuning.Puppet.filmRiseSeconds, "getting up plays the film backwards")
    for _ in 0 ..< Int(rises * 30) + 3 {
        cat.step(1.0 / 30)
        #expect(cat.drawingsOnShow == 1)
    }
    #expect(cat.pose == nil)
    #expect(cat.isFilming, "up: the walk film's standing picture")
    // In a jump, the run film's stretched picture; landed, standing.
    cat.leap(true)
    #expect(cat.isFilming)
    cat.leap(false)
    #expect(cat.isFilming)
    #expect(cat.drawingsOnShow == 1)
}

/// Jumping and walking away are films too (21 Oct, Josh's full set): a jump up or down plays the body's jump film
/// over the jump's time, each picture about its own origin; walking away, the cat is seen from behind on the film
/// (a view with no puppet), which the director picks only when that film is ready for the cat as it is (a cat with
/// swapped ears, whose ears the film cannot follow, keeps to the side view).
@MainActor
@Test func jumpingAndWalkingAwayAreFilms() throws {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    let rig = try art.data("cat/rig.json", as: PuppetRig.self)
    let look = catArt.builder.normalized(CatLook(body: "short_slim"))
    let cat = CatNode(art: art, rig: rig, catArt: catArt, look: look, height: 150)
    let scene = SKScene(size: CGSize(width: 800, height: 600))
    scene.addChild(cat)
    cat.loadFilmsNow()
    cat.show(.side, facingRight: false)
    cat.step(1.0 / 30)
    for up in [true, false] {
        let plays = cat.jump(up: up, seconds: 0.6)
        #expect(plays, up ? "jumping up on the film" : "jumping down on the film")
        #expect(cat.jumpingOnFilm && cat.isFilming)
        for _ in 0 ..< 20 {
            cat.step(1.0 / 30)
            #expect(cat.drawingsOnShow == 1)
        }
        #expect(!cat.jumpingOnFilm, "landed")
        #expect(cat.isFilming, "standing on the film again")
    }
    #expect(cat.filmReady(.tqback, .walk), "walking away from behind")
    #expect(!cat.filmReady(.tqback, .run), "no run from behind: side on")
    cat.show(.tqback, facingRight: true)
    cat.walk()
    cat.step(1.0 / 30)
    #expect(cat.isFilming && cat.drawingsOnShow == 1, "walking away as the film")
    cat.stopCycle()
    #expect(cat.isFilming, "standing seen from behind: the film's standing picture")
    // The director sends it away from behind, and towards you at three-quarters.
    let director = CatDirector(cat: cat, grid: IsoGrid())
    let grid = IsoGrid()
    director.place(at: grid.floor(5, 5))
    #expect(director.heading(to: grid.floor(8, 8), gait: .walk).view == .tqback)
    #expect(director.heading(to: grid.floor(8, 8), gait: .run).view == .side)
    #expect(director.heading(to: grid.floor(2, 2), gait: .walk).view == .tqfront)
    // Swapped ears the film from behind cannot follow: the side view.
    let folded = CatNode(art: art, rig: rig, catArt: catArt, look: catArt.builder.normalized(CatLook(body: "short_slim", ears: "folded")), height: 150)
    folded.loadFilmsNow()
    #expect(!folded.filmReady(.tqback, .walk))
}
