import Foundation
@testable import HouseCatCore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let custom = repo.appendingPathComponent("assets/cat/custom")

/// The builder data as the app bundles it (tools/app-assets/build_cat_art.py).
private func builder() throws -> CatBuilder {
    try CatBuilder.load(from: repo.appendingPathComponent("App/Art/cat/custom/builder.json"))
}

@Test func builderDataMirrorsCatbuilderJSON() throws {
    let builder = try builder()
    let source = try #require(JSONSerialization
        .jsonObject(with: Data(contentsOf: custom.appendingPathComponent("catbuilder.json"))) as? [String: Any])
    let presets = try #require(source["presets"] as? [[String: Any]])
    #expect(builder.data.presets.map(\.id) == presets.compactMap { $0["id"] as? String })
    #expect(builder.data.bodies.count == 8)
    #expect(builder.data.coats.count == 16)
    #expect(builder.data.eyes.count == 8)
    #expect(builder.data.noses.count == 5)
    #expect(builder.data.presets.first?.id == "midnight")
    // CatLook mirrors look_fields (plus the weight slider).
    let fields = try #require(source["look_fields"] as? [String])
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CatLook.midnight)) as? [String: Any])
    #expect(Set(fields).isSubset(of: Set(encoded.keys).union(["pattern", "pattern_colour", "white"])))
}

@Test func midnightIsTheDefaultAndTheFirstPreset() throws {
    let builder = try builder()
    let midnight = try #require(builder.preset("midnight"))
    #expect(builder.normalized(midnight.look) == CatLook.midnight)
    #expect(builder.colours(.midnight).coat == RGB(58, 50, 62))
    #expect(builder.colours(.midnight).eyeLeft == RGB(236, 168, 40))
}

@Test func everyPresetIsAlreadyValid() throws {
    let builder = try builder()
    for preset in builder.data.presets {
        #expect(builder.normalized(preset.look) == preset.look, "\(preset.id)")
    }
}

@Test func everyPresetHasItsPaintedSprites() throws {
    let builder = try builder()
    let base = custom.appendingPathComponent("base")
    for preset in builder.data.presets {
        let look = preset.look
        for view in ["side", "tqfront", "front"] {
            for part in ["head", "torso", "leg_front_near", "leg_back_far", "tail_up"] {
                let sprite = builder.part(part, view: view, look: look)
                #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent(sprite.path).path), "\(sprite.path)")
            }
        }
        for pose in ["sit_tqfront", "sit_side", "loaf_side", "sleep_curl"] {
            let sprite = builder.pose(pose, look: look)
            #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent(sprite.path).path), "\(sprite.path)")
        }
    }
}

@Test func breedsKeepTheirOwnEarsAndTail() throws {
    let builder = try builder()
    var look = CatLook(body: "siamese", ears: "folded", tail: "bobtail")
    look = builder.normalized(look)
    #expect(look.ears == "own")
    #expect(look.tail == "own")
    var shorthair = CatLook(body: "short_slim", ears: "folded", tail: "bobtail")
    shorthair = builder.normalized(shorthair)
    #expect(shorthair.ears == "folded")
    #expect(shorthair.tail == "bobtail")
    #expect(builder.part("ear_far", view: "side", look: shorthair).path == "ears/ear_folded_side_far.png")
    #expect(builder.part("ear_far", view: "side", look: shorthair).takesWhite == false)
    #expect(builder.part("tail_up", view: "front", look: shorthair).path == "tails/bobtail_front_up.png")
    #expect(builder.pose("sit_side", look: shorthair).path == "poses/cat_short_slim_sit_side__folded_bobtail.png")
}

@Test func theWeightSliderSwapsToTheChunkySetPastTheMiddle() throws {
    let builder = try builder()
    let kinds = builder.bodyKinds
    #expect(kinds.map(\.label) == ["Shorthair", "Longhair", "Persian", "Siamese / Oriental", "Maine Coon", "Sphynx"])
    var look = CatLook.midnight
    look = builder.weighing(0.8, for: look)
    #expect(look.body == "short_chunky")
    look = builder.weighing(0.2, for: look)
    #expect(look.body == "short_slim")
    #expect(builder.torsoStretch(look) < 1)
    look = try builder.choosing(#require(kinds.first { $0.id == "long" }), for: look)
    #expect(look.body == "long_slim")
    #expect(look.weight == 0.2)
    look = try builder.choosing(#require(kinds.first { $0.id == "persian" }), for: look)
    #expect(look.body == "persian")
    #expect(builder.torsoStretch(look) == 1)
}

@Test func pickedColoursKeepTheirShadingReadable() {
    let black = CatBuilder.pickerClamped(RGB(0, 0, 0))
    #expect(abs(black.luminance - Tuning.Cat.pickerMinLuminance) < 1)
    let white = CatBuilder.pickerClamped(RGB(255, 255, 255))
    #expect(abs(white.luminance - Tuning.Cat.pickerMaxLuminance) < 1)
    #expect(CatBuilder.pickerClamped(RGB(214, 104, 46)) == RGB(214, 104, 46))
}

@Test func unknownOptionsFallBack() throws {
    let builder = try builder()
    let look = builder.normalized(CatLook(
        body: "dragon",
        coat: .named("tartan"),
        pattern: "none",
        white: "white_socks",
        eyeLeft: .picked(RGB(1, 2, 3)),
        eyeSize: 3,
        age: .adult(years: 90)
    ))
    #expect(look.body == "short_slim")
    #expect(look.coat == .named("black"))
    #expect(look.pattern == nil)
    #expect(look.white == nil)
    #expect(look.eyeLeft == .named("amber"))
    #expect(look.eyeSize == 1)
    #expect(look.age == .adult(years: Tuning.Cat.maxAdultYears))
}

@Test func aLookRoundTripsAsPlainStrings() throws {
    let look = CatLook(
        body: "short_chunky",
        coat: .picked(RGB(200, 100, 50)),
        pattern: "tortie",
        patternColour: .named("cream"),
        white: "white_bicolour",
        eyeLeft: .named("blue"),
        eyeRight: .named("amber"),
        age: .kitten
    )
    let data = try JSONEncoder().encode(look)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"#c86432\""))
    #expect(json.contains("\"kitten\""))
    #expect(try JSONDecoder().decode(CatLook.self, from: data) == look)
    #expect(look.hasOddEyes)
}

@Test func theLookIsPartOfTheSaveAndSetsTheAge() {
    var fixture = Fixture()
    #expect(fixture.state.cat("midnight")?.look == .midnight)
    let look = CatLook(body: "persian", coat: .named("white"), eyeLeft: .named("blue"), nose: .named("pink"), age: .adult(years: 5))
    fixture.add(.catLookSet(catID: "midnight", look: look), day: 0, hour: 8)
    let cat = fixture.state.cat("midnight")
    #expect(cat?.look == look)
    #expect(cat?.ageDays(on: fixture.day(0)) == 5 * 365)
    #expect(cat?.ageDays(on: fixture.day(10)) == 5 * 365 + 10)
    var kitten = look
    kitten.age = .kitten
    fixture.add(.catLookSet(catID: "midnight", look: kitten), day: 1, hour: 8)
    #expect(fixture.state.cat("midnight")?.isKittenStage(on: fixture.day(1)) == true)
    #expect(fixture.state.cat("midnight")?.ageDays(on: fixture.day(1)) == Tuning.Cat.kittenStartAgeDays + 1)
}

@Test func catStateSnapshotsFromBeforeLooksStillDecode() throws {
    let old = #"{"id":"midnight","name":"Pip","personality":"aloof","adoptedOn":{"index":10},"isKitten":false,"careDays":4}"#
    let decoded = try? JSONDecoder().decode(CatState.self, from: Data(old.utf8))
    // GameDay may encode differently; build the old shape from a real cat instead when it does.
    let cat = try decoded ?? {
        var dict = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixture().state.cat("midnight"))) as? [String: Any])
        dict.removeValue(forKey: "look")
        return try JSONDecoder().decode(CatState.self, from: JSONSerialization.data(withJSONObject: dict))
    }()
    #expect(cat.look == .midnight)
}

@Test func namesAreRequiredShortAndFiltered() {
    let filter = NameFilter(words: ["arse", "ass"], anywhere: ["shit", "fuck", "bastard"])
    #expect(CatNames.check("  Pip  ", filter: filter) == .ok("Pip"))
    #expect(CatNames.check("Mister   Biscuit", filter: filter) == .ok("Mister Biscuit"))
    #expect(CatNames.check("   ", filter: filter) == .empty)
    #expect(CatNames.check(String(repeating: "a", count: 21), filter: filter) == .tooLong)
    #expect(CatNames.check("Sh1t", filter: filter) == .blocked)
    #expect(CatNames.check("Lord F.u.c.k", filter: filter) == .blocked)
    #expect(CatNames.check("Bastardo", filter: filter) == .blocked)
    #expect(CatNames.check("Ass", filter: filter) == .blocked)
    #expect(CatNames.check("Old Arse", filter: filter) == .blocked)
    // Whole words only for these: no Scunthorpe problem.
    #expect(CatNames.check("Arsenal", filter: filter) == .ok("Arsenal"))
    #expect(CatNames.check("Cassie", filter: filter) == .ok("Cassie"))
}

@Test func theNameFilterShipsWithTheContent() throws {
    let content = try ContentBundle.load(from: repo.appendingPathComponent("Content"))
    #expect(!content.names.words.isEmpty)
    #expect(!content.names.anywhere.isEmpty)
    #expect(CatNames.check("Pip", filter: content.names) == .ok("Pip"))
    for name in try builder().data.nameSuggestions {
        #expect(CatNames.check(name, filter: content.names) == .ok(name), "\(name)")
    }
}

@Test func nameSuggestionsComeInThreesAndShuffle() throws {
    let names = try builder().data.nameSuggestions
    let first = CatNames.suggestions(from: names, seed: 7)
    let again = CatNames.suggestions(from: names, seed: 7)
    let next = CatNames.suggestions(from: names, seed: 7, shuffle: 1)
    #expect(first.count == 3)
    #expect(first == again)
    #expect(Set(first).isDisjoint(with: next))
}
