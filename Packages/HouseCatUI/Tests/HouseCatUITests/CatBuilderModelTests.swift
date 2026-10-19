import Foundation
import HouseCatCore
import HouseCatGame
@testable import HouseCatUI
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

@MainActor
private func creator(_ mode: CatBuilderModel.Mode = .adopt, look: CatLook = .midnight) throws -> CatBuilderModel {
    let art = try ArtLibrary(root: repo.appendingPathComponent("App/Art"))
    let catArt = try CatArt(art: art)
    return CatBuilderModel(mode: mode, look: look, art: art, catArt: catArt, rig: nil, names: NameFilter())
}

/// Every preset, and a cat already made (a picked coat colour, odd eyes, a kitten), comes into the creator as it is.
@MainActor
@Test func everyLookLoadsIntoTheCreatorUnchanged() throws {
    let model = try creator()
    for preset in model.builder.data.presets {
        let opened = try creator(.edit, look: preset.look)
        #expect(opened.look == model.builder.normalized(preset.look), "\(preset.id)")
        #expect(opened.presetID == preset.id, "\(preset.id) is named as its preset")
    }
    var own = CatLook(body: "long_chunky", ears: "tufted", tail: "bobtail", coat: LookColour("#b05a2e"), pattern: "spotted")
    own.eyeLeft = .named("green")
    own.eyeRight = .named("blue")
    own.age = .kitten
    let opened = try creator(.edit, look: own)
    #expect(opened.look == model.builder.normalized(own))
    #expect(opened.look.coat == LookColour("#b05a2e"))
    #expect(opened.look.hasOddEyes && opened.look.age.isKitten)
    #expect(opened.presetID == nil)
}

/// Undo takes changes back one at a time; a slider's whole drag is one change.
@MainActor
@Test func undoTakesChangesBack() throws {
    let model = try creator()
    let start = model.look
    #expect(!model.canUndo)
    model.change { $0.coat = .named("ginger") }
    model.change { $0.pattern = "tabby_mackerel" }
    model.adjusting(true)
    for weight in stride(from: 0.4, through: 0.9, by: 0.1) {
        model.weigh(weight)
    }
    model.adjusting(false)
    #expect(model.look.body == "short_chunky")
    model.undo()
    #expect(model.look.body == "short_slim" && model.look.pattern == "tabby_mackerel", "the drag is undone in one")
    model.undo()
    #expect(model.look.pattern == nil && model.look.coat == .named("ginger"))
    model.undo()
    #expect(model.look == start)
    #expect(!model.canUndo)
    model.choose(preset: "calico")
    #expect(model.presetID == "calico")
    model.undo()
    #expect(model.look == start && model.presetID == "midnight")
}

/// Surprise me always makes a look the builder allows, and keeps the age the player chose.
@MainActor
@Test func surpriseMakesValidLooks() throws {
    let model = try creator()
    model.change { $0.age = .kitten }
    var bodies = Set<String>()
    for _ in 0 ..< 200 {
        model.surprise()
        #expect(model.look == model.builder.normalized(model.look))
        #expect(model.look.age == .kitten)
        bodies.insert(model.look.body)
    }
    #expect(bodies.count >= 4, "a mix of bodies")
}

/// The drawers in order; adopting ends on the name, editing has none.
@MainActor
@Test func theDrawersInOrder() throws {
    let adopt = try creator(.adopt)
    #expect(adopt.sections.first == .looks && adopt.sections.last == .name)
    #expect(adopt.section == .looks && adopt.nextSection == .body && adopt.previousSection == nil)
    let edit = try creator(.edit)
    #expect(!edit.sections.contains(.name) && edit.sections.last == .age)
    for section in CatBuilderModel.Section.allCases {
        #expect(!section.title.isEmpty && !section.icon.isEmpty)
        #expect(
            FileManager.default.fileExists(atPath: repo.appendingPathComponent("App/Art/ui/icon_\(section.icon).png").path),
            "\(section) has its painted icon"
        )
    }
}

/// An option's picture is drawn from the cat in that look.
@MainActor
@Test func optionPicturesAreDrawn() async throws {
    let model = try creator()
    for kind in [CatBuilderModel.PictureKind.sitting, .side, .front, .head] {
        let picture = await model.picture(of: model.look, kind)
        #expect(picture != nil, "\(kind)")
        #expect((picture?.height ?? 0) <= Int(Tuning.Builder.thumbnailPixels))
    }
}
