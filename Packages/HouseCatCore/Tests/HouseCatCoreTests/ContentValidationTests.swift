import Foundation
@testable import HouseCatCore
import Testing

/// Validates the generated content in `Content/` against docs/CONTENT.md and
/// `assets/manifest.json`: every id referenced exists, every line is 70
/// characters or fewer in British English, and every catalogue item has a
/// footprint, layer, affordances, capacity, motion and pool.
@Suite("Content files")
struct ContentValidationTests {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    let content: ContentBundle
    let manifest: [String: [String: Any]]

    init() throws {
        content = try ContentBundle.load(from: Self.repo.appendingPathComponent("Content"))
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("assets/manifest.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        manifest = try #require(json["files"] as? [String: [String: Any]])
    }

    // MARK: Text rules

    /// American spellings and words; British English is required (CONTENT.md §1).
    static let americanisms = [
        "color", "colors", "colored", "colorful", "favorite", "favorites", "favor", "flavor", "honor", "humor", "neighbor",
        "neighbors", "behavior", "gray", "mom", "mommy", "apartment", "cookie", "cookies", "candy", "sweater", "vacation",
        "flashlight", "pajamas", "sidewalk", "trash", "garbage", "faucet", "diaper", "theater", "center", "jewelry",
        "aluminum", "traveled", "canceled", "fall asleep in the fall", "yard", "cozy", "pants", "zucchini", "eggplant",
        "parking lot", "gotten", "math", "fries", "realize", "organize", "recognize", "apologize", "favorite",
    ]
    /// No alcohol anywhere (Josh, 18 Oct; rated 4+).
    static let alcohol = [
        "wine", "wines", "champagne", "prosecco", "bubbly", "beer", "beers", "lager", "cider", "gin", "rum", "vodka",
        "whisky", "whiskey", "brandy", "sherry", "booze", "boozy", "pub", "pubs", "cocktail", "cocktails", "drunk", "tipsy",
        "hangover", "mulled", "eggnog",
    ]
    static let allowedIze: Set<String> = ["size", "sizes", "sized", "prize", "prizes", "seize", "seized", "capsize", "maize", "resize"]

    static func problems(in text: String, limit: Int, isLine: Bool = false) -> [String] {
        var problems: [String] = []
        if text.count > limit {
            problems.append("over \(limit) characters (\(text.count))")
        }
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("empty")
        }
        let lower = text.lowercased()
        let words = lower.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        for word in americanisms where word.contains(" ") ? lower.contains(word) : words.contains(word) {
            problems.append("American English: \(word)")
        }
        for word in alcohol where words.contains(word) {
            problems.append("alcohol: \(word)")
        }
        for word in words where (word.hasSuffix("ize") || word.hasSuffix("izes") || word.hasSuffix("ized") || word.hasSuffix("izing"))
            && !allowedIze.contains(word)
        {
            problems.append("-ize spelling: \(word)")
        }
        for scalar in text.unicodeScalars where scalar.properties.isEmojiPresentation || (0x1F000 ... 0x1FAFF).contains(scalar.value) {
            problems.append("emoji \(scalar)")
        }
        if isLine {
            for banned in ["£", "$", "purchase", "subscri", "season pass", "cat club"] where lower.contains(banned) {
                problems.append("mentions \(banned)")
            }
            for banned in ["app", "apps", "shop", "buy", "buying", "price", "prices", "screen", "button"] where words.contains(banned) {
                problems.append("mentions \(banned)")
            }
            let placeholders = Set(["{cat}", "{item}", "{weather}", "{temp}", "{place}", "{streak}", "{sitter}", "{together}"])
            var rest = text
            while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                let token = String(rest[open ... close])
                if !placeholders.contains(token) {
                    problems.append("unknown placeholder \(token)")
                }
                rest = String(rest[rest.index(after: close)...])
            }
        }
        return problems
    }

    @Test func linesFollowTheRules() {
        let lines = content.lines
        let contexts = lines.contexts.map(\.id)
        #expect(Set(contexts).count == contexts.count, "duplicate context ids")
        #expect(contexts.count >= 50)
        for line in lines.lines {
            #expect(contexts.contains(line.context), "line for unknown context \(line.context)")
            #expect(line.variants.count >= 3, "\(line.context)/\(line.personality): fewer than three variants")
            for variant in line.variants {
                let problems = Self.problems(in: variant, limit: 70, isLine: true)
                #expect(problems.isEmpty, "\(line.context)/\(line.personality.rawValue): \"\(variant)\" \(problems)")
            }
        }
        for context in contexts {
            for personality in Personality.allCases {
                #expect(
                    lines.lines.count { $0.context == context && $0.personality == personality } == 1,
                    "\(context) needs exactly one entry for \(personality)"
                )
            }
        }
        // The contexts the rules engine asks for exist.
        for needed in [BehaviourTable.emptyRoomLine, WidgetRules.stillWaitingLine, WidgetRules.sulkLine] {
            #expect(contexts.contains(needed), "missing context \(needed)")
        }
    }

    // MARK: Catalogue

    @Test func everyCatalogueItemIsComplete() {
        let items = content.catalogue.items
        #expect(Set(items.map(\.id)).count == items.count, "duplicate item ids")
        let setIDs = Set(content.catalogue.sets.map(\.id))
        for item in items {
            let label = item.id
            #expect(
                item.footprint.w >= 1 && item.footprint.d >= 1 && item.footprint.w <= 3 && item.footprint.d <= 3,
                "\(label): footprint \(item.footprint)"
            )
            #expect(!item.affordances.isEmpty, "\(label): no affordances")
            if item.affordances.contains(.none) {
                #expect(item.affordances == [.none] && item.capacity == 0, "\(label): none must stand alone with capacity 0")
            } else {
                #expect(item.capacity >= 1, "\(label): capacity")
            }
            switch item.motion.type {
            case .static: break
            case .sway, .bob, .spin, .glow:
                #expect(item.motion.pivot?.count == 2 && (item.motion.period ?? 0) > 0, "\(label): motion needs pivot and period")
            case .frames:
                #expect(item.motion.fx != nil && (item.motion.frames ?? 0) > 0, "\(label): frames need fx and frames")
            }
            switch item.pool {
            case .beans:
                // Bean prices run from a 30-Bean floor (Josh, 18 Oct) to 600.
                #expect((30 ... 600).contains(item.beans ?? 0) && item.sku == nil, "\(label): Bean price \(item.beans ?? 0)")
            case .set, .housewarming, .founders:
                #expect(item.sku?.hasPrefix("housecat.") == true && item.beans == nil, "\(label): paid items need a sku")
            case .free, .passFree, .passPaid, .club:
                #expect(item.beans == nil && item.sku == nil, "\(label): \(item.pool) items have no price")
            }
            #expect(item.level >= 1)
            #expect(item.name.count <= 24, "\(label): name too long")
            #expect(Self.problems(in: item.name, limit: 24).isEmpty, "\(label): \(Self.problems(in: item.name, limit: 24))")
            #expect(Self.problems(in: item.description, limit: 90).isEmpty, "\(label): \(Self.problems(in: item.description, limit: 90))")
            #expect(item.sprites.keys.sorted() == ["L", "R"], "\(label): needs R and L sprites")
            for sprite in item.sprites.values {
                #expect(manifest[sprite] != nil, "\(label): sprite \(sprite) not in the manifest")
            }
            // Season-pass, launch-pack and founders items are grouped under their own folder name.
            if let set = item.set {
                #expect(setIDs.contains(set) || set == item.room, "\(label): unknown set \(set)")
            }
            // Carry the manifest's suggested scale.
            let manifestScale = item.sprites["R"].flatMap { manifest[$0]?["suggested_scale"] as? Double }
            #expect(
                item.suggestedScale == manifestScale,
                "\(label): suggestedScale \(String(describing: item.suggestedScale)) ≠ manifest \(String(describing: manifestScale))"
            )
        }
    }

    @Test func catalogueCountsAndPoolsMatchTheDecisions() {
        let rooms: Set = ["living", "bedroom", "kitchen", "garden", "study", "attic"]
        let roomItems = content.catalogue.items.filter { rooms.contains($0.room) }
        #expect(roomItems.count == 80)
        // 113 painted, less the two alcohol items (mulled wine, champagne) excluded on 18 Oct, and the season pass's
        // own sets of 20 Oct: Black Cat's 37 and 31 more for Housewarming.
        #expect(content.catalogue.items.count == 179)
        let excluded = Set((content.catalogue.excluded ?? []).map(\.id))
        #expect(excluded == ["pass_midwinter_mulledwine", "housewarming_pack_champagne"])
        #expect(content.catalogue.items.allSatisfy { !excluded.contains($0.id) })
        #expect(roomItems.count { $0.pool == .free } == 8)
        #expect(roomItems.count { $0.pool == .beans } == 30)
        #expect(roomItems.count { $0.pool == .set } == 42)
        let beanLevels = Dictionary(grouping: roomItems.filter { $0.pool == .beans }, by: \.level).mapValues(\.count)
        #expect(beanLevels == [1: 8, 3: 8, 6: 8, 9: 6])
        #expect(content.catalogue.sets.count == 6)
        for set in content.catalogue.sets {
            #expect(roomItems.count { $0.set == set.id } == 7, "\(set.id) needs 7 items")
        }
        #expect(content.catalogue.items.first { $0.id == "kitchen_bowl" }?.pool == .free)
        // Every manifest furniture item is in the catalogue.
        let manifestItems = Set(manifest.values.compactMap { entry -> String? in
            guard entry["class"] as? String == "furniture", let room = entry["room"] as? String, let item = entry["item"] as? String,
                  entry["variant"] == nil else { return nil }
            return "\(room)_\(item)"
        })
        let missing = manifestItems.subtracting(content.catalogue.items.map(\.id)).subtracting(excluded)
        #expect(missing.isEmpty, "missing: \(missing.sorted())")
    }

    @Test func setsAndSurfacesReferenceRealThings() {
        let outfits = Set(content.outfits.outfits.map(\.id))
        let surfaces = Dictionary(uniqueKeysWithValues: content.catalogue.surfaces.map { ($0.id, $0) })
        #expect(surfaces.count == content.catalogue.surfaces.count, "duplicate surface ids")
        for set in content.catalogue.sets {
            #expect(set.sku == "housecat.set.\(set.id)" && set.bundleSku == "housecat.bundle.\(set.id)")
            #expect(outfits.contains(set.outfit), "\(set.id): unknown outfit \(set.outfit)")
            #expect(surfaces[set.wallpaper]?.kind == .wall, "\(set.id): unknown wallpaper \(set.wallpaper)")
            #expect(surfaces[set.floor]?.kind == .floor, "\(set.id): unknown floor \(set.floor)")
        }
        for surface in content.catalogue.surfaces {
            #expect(manifest[surface.sprite] != nil, "\(surface.id): sprite not in manifest")
        }
        for room in ["living", "bedroom", "kitchen", "garden", "study", "attic"] {
            for kind in [CatalogueFile.Surface.Kind.wall, .floor] {
                let inRoom = content.catalogue.surfaces.filter { $0.room == room && $0.kind == kind }
                #expect(inRoom.count >= 5, "\(room) needs five \(kind)s")
                #expect(inRoom.count { $0.pool == .free } >= 3, "\(room) needs three free \(kind)s")
            }
        }
    }

    // MARK: Gifts, outfits, objectives, seasons, mini-games

    @Test func giftsMatchTheBrief() {
        let gifts = content.gifts.gifts
        #expect(gifts.count == 60)
        #expect(Set(gifts.map(\.id)).count == 60)
        let rarities = Dictionary(grouping: gifts, by: \.rarity).mapValues(\.count)
        #expect(rarities == [.common: 30, .uncommon: 17, .rare: 9, .legendary: 4])
        for gift in gifts {
            #expect(manifest[gift.sprite] != nil, "\(gift.id): sprite not in manifest")
            #expect(gift.months.allSatisfy { (1 ... 12).contains($0) })
            #expect(gift.category == "seasonal" || gift.months.isEmpty, "\(gift.id): only seasonal gifts have months")
            #expect(Self.problems(in: gift.description, limit: 90).isEmpty, "\(gift.id): \(Self.problems(in: gift.description, limit: 90))")
        }
    }

    @Test func outfitsMatchTheBrief() {
        let outfits = content.outfits.outfits
        #expect(outfits.count == 37)
        let pools = Dictionary(grouping: outfits, by: \.pool).mapValues(\.count)
        // The pass's fourteen outfits are its own (Josh, 20 Oct: off sale for Beans), Black Cat's toadstool hat and bat
        // wings among them.
        #expect(pools == [.paid: 19, .earned: 4, .passPaid: 9, .passFree: 5])
        for outfit in outfits {
            for sprite in outfit.sprites.values {
                #expect(manifest[sprite] != nil, "\(outfit.id): sprite \(sprite) not in manifest")
            }
            #expect(Set(outfit.sprites.keys) == Set(outfit.views), "\(outfit.id): a sprite per view")
            if outfit.pool == .paid {
                #expect(outfit.sku == "housecat.outfit.\(outfit.id)")
            }
            if outfit.pool == .earned {
                #expect(outfit.earnedBy != nil)
            }
            // Only a hat covers the ears (glasses, neckwear and garments leave the head as it is).
            if outfit.coversEars == true {
                #expect(outfit.slot == .head && !outfit.id.contains("glasses"), "\(outfit.id): coversEars on a hat only")
            }
        }
    }

    @Test func objectivesMatchTheBrief() {
        let objectives = content.objectives
        #expect(objectives.daily.count == 20)
        #expect(objectives.weekly.count == 12)
        // 60 from the brief and 21 more on 19 Oct (ladders for games, stars, naps, outfits, visits, furnished rooms,
        // the pieces the cat uses, other cats' homes, and level 30).
        #expect(objectives.achievements.count == 81)
        let all = objectives.daily + objectives.weekly + objectives.achievements
        #expect(Set(all.map(\.id)).count == all.count, "duplicate objective ids")
        for objective in objectives.achievements {
            #expect(![.roomPieces, .screenSeen].contains(objective.metric), "\(objective.id): that metric needs a path step's room or screen")
        }
        for objective in objectives.daily + objectives.weekly {
            #expect(!objective.metric.isLifetime, "\(objective.id): daily and weekly objectives count within the period")
        }
        for objective in objectives.achievements {
            #expect(objective.metric.isLifetime, "\(objective.id): achievements use lifetime metrics")
        }
        for objective in all {
            #expect(objective.target >= 1 && objective.beans >= 0 && objective.passPoints >= 0)
            #expect(objective.name.count <= 24, "\(objective.id): name too long")
            #expect(
                Self.problems(in: objective.text, limit: 70).isEmpty,
                "\(objective.id): \(Self.problems(in: objective.text, limit: 70))"
            )
        }
    }

    /// The path (objectives.json `path`): three chapters, every step something the game can count, every reward real.
    @Test func thePathIsWellFormed() {
        let objectives = content.objectives
        let outfits = Set(content.outfits.outfits.map(\.id))
        let items = Set(content.catalogue.items.map(\.id))
        let chapters = objectives.chapters
        #expect(chapters.map(\.name) == ["Moving in", "Getting to know you", "Making it home"])
        let ids = chapters.map(\.id) + chapters.flatMap(\.steps).map(\.id)
        let objectiveIDs = Set((objectives.daily + objectives.weekly + objectives.achievements).map(\.id))
        #expect(Set(ids).count == ids.count, "duplicate path ids")
        #expect(objectiveIDs.isDisjoint(with: ids), "a path id is also an objective's")
        for chapter in chapters {
            #expect(chapter.steps.count >= 5 && chapter.steps.count <= Tuning.Goals.stepsPerChapterMost, "\(chapter.id): \(chapter.steps.count) steps")
            #expect(chapter.beans > 0 && chapter.name.count <= 24)
            #expect(Self.problems(in: chapter.done, limit: 60).isEmpty, "\(chapter.id): \(Self.problems(in: chapter.done, limit: 60))")
            if let outfit = chapter.outfit {
                #expect(outfits.contains(outfit), "\(chapter.id): unknown outfit \(outfit)")
            }
            if let item = chapter.item {
                #expect(items.contains(item), "\(chapter.id): unknown piece \(item)")
            }
            for step in chapter.steps {
                #expect(step.metric.isLifetime, "\(step.id): the path counts lifetime totals")
                #expect(step.target >= 1 && step.beans >= 0 && step.xp >= 0)
                #expect(step.beans + step.xp > 0 || step.outfit != nil, "\(step.id): pays nothing")
                #expect(step.name.count <= 24, "\(step.id): name too long")
                #expect(Self.problems(in: step.text, limit: 60).isEmpty, "\(step.id): \(Self.problems(in: step.text, limit: 60))")
                #expect((step.metric == .roomPieces) == (step.room != nil), "\(step.id): a room is for room_pieces")
                #expect((step.metric == .screenSeen) == (step.screen != nil), "\(step.id): a screen is for screen_seen")
                if let outfit = step.outfit {
                    #expect(outfits.contains(outfit), "\(step.id): unknown outfit \(outfit)")
                }
                if let item = step.item {
                    #expect(items.contains(item), "\(step.id): unknown piece \(item)")
                }
            }
        }
    }

    @Test func seasonsHaveThirtyTiersAndAFreeTrackOfTwenty() throws {
        let items = Set(content.catalogue.items.map(\.id))
        let outfits = Dictionary(uniqueKeysWithValues: content.outfits.outfits.map { ($0.id, $0) })
        let surfaces = Set(content.catalogue.surfaces.map(\.id))
        #expect(content.seasons.tiers == Tuning.Pass.tiers)
        #expect(content.seasons.freeTiers == Tuning.Pass.freeTiers)
        #expect(content.seasons.seasonLengthDays == Tuning.Pass.seasonLengthDays)
        for season in content.seasons.seasons {
            let definition = try season.definition()
            // Every season sits exactly on the calendar; December is the Christmas season.
            let slot = SeasonCalendar.slot(containing: definition.startDay)
            #expect(slot.start == definition.startDay && slot.end == definition.endDay, "\(season.id) is off the season calendar")
            #expect(slot.isChristmas == (season.christmas == true), "\(season.id): Christmas flag")
            #expect(season.sku == "housecat.pass.\(season.id)")
            // A box on every tier, in order; a box may hold more than one reward (Josh, 20 Oct: "more content in them").
            #expect(definition.tiers(.free) == Array(1 ... Tuning.Pass.freeTiers), "\(season.id): free tiers 1–20")
            #expect(definition.tiers(.paid) == Array(1 ... Tuning.Pass.tiers), "\(season.id): premium tiers 1–30")
            #expect(season.freeTrack.map(\.tier) == season.freeTrack.map(\.tier).sorted(), "\(season.id): free track in order")
            #expect(season.paidTrack.map(\.tier) == season.paidTrack.map(\.tier).sorted(), "\(season.id): premium track in order")
            #expect((season.freeTrack + season.paidTrack).allSatisfy { $0.rarity != nil }, "\(season.id): every reward has a rarity")
            for reward in season.freeTrack + season.paidTrack {
                switch reward.kind {
                case .beans: #expect((reward.amount ?? 0) > 0)
                case .item: #expect(reward.id.map(items.contains) == true, "\(season.id): unknown item \(reward.id ?? "nil")")
                case .outfit: #expect(reward.id.flatMap { outfits[$0] } != nil, "\(season.id): unknown outfit \(reward.id ?? "nil")")
                case .surface: #expect(reward.id.map(surfaces.contains) == true, "\(season.id): unknown surface \(reward.id ?? "nil")")
                }
            }
            #expect(definition.reward(track: .free, tier: Tuning.Pass.freeTiers)?.kind == .outfit, "\(season.id): the free track ends with an outfit")
            let capstone = definition.reward(track: .paid, tier: Tuning.Pass.tiers)
            #expect(capstone?.kind == .outfit, "\(season.id): tier 30 of the premium track is the season's outfit")
            #expect(capstone?.id.flatMap { outfits[$0]?.pool } == .passPaid, "\(season.id): the top prize is the season's own")
        }
        let christmas = content.seasons.seasons.filter { $0.christmas == true }
        #expect(christmas.map(\.id) == ["midwinter"])
        #expect(christmas.first?.paidTrack.last?.id == "santahat")
        // Seasons run back to back.
        let ordered = try content.seasons.seasons.map { try $0.definition() }.sorted { $0.startDay < $1.startDay }
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(a.endDay == b.startDay)
        }
    }

    @Test func miniGamesMatchTuning() {
        let games = content.minigames
        #expect(games.games.map(\.id).sorted() == ["hide_and_seek", "knock_it_off", "laser_pointer", "string_chase"])
        #expect(games.playsPerDay == Tuning.MiniGames.playsPerDay)
        #expect(games.starBeans == Tuning.MiniGames.starBeans)
        #expect(games.xpPerPlay == Tuning.XP.play)
        // A play's XP is what it adds to the season pass.
        #expect(games.passPointsPerPlay == Tuning.XP.play)
        for game in games.games {
            #expect(game.stars.count == 3 && game.stars == game.stars.sorted())
        }
    }

    @Test func theIntroReadsWellAndTakesItsCatsFromTheBuilder() throws {
        let intro = content.intro
        let builder = try CatBuilder.load(from: Self.repo.appendingPathComponent("App/Art/cat/custom/builder.json"))
        #expect(Set(intro.stops.map(\.id)).count == intro.stops.count)
        // The tour (Josh, 20 Oct: "just do a couple houses") names stops, each once; the map keeps them all.
        #expect(!intro.tour.isEmpty)
        #expect(Set(intro.tour).count == intro.tour.count)
        #expect(intro.tourStops.map(\.id) == intro.tour, "every tour id is a stop")
        // Every home's painting is in the app (art.json maps each master path to its file).
        let artData = try Data(contentsOf: Self.repo.appendingPathComponent("App/Art/art.json"))
        let art = try #require((try JSONSerialization.jsonObject(with: artData) as? [String: Any])?["files"] as? [String: Any])
        for stop in intro.stops {
            for suffix in [".jpg", "_land.png", "_glass.png"] {
                #expect(art[stop.scene + suffix] != nil, "\(stop.id): \(stop.scene + suffix) not in App/Art")
            }
            #expect(builder.preset(stop.cat.preset) != nil, "\(stop.id): no preset \(stop.cat.preset)")
            #expect(TimeZone(identifier: stop.timeZone) != nil, "\(stop.id): time zone")
            #expect(abs(stop.latitude) <= 90 && abs(stop.longitude) <= 180)
            #expect(Self.problems(in: stop.line, limit: 90).isEmpty, "\(stop.id): \(Self.problems(in: stop.line, limit: 90))")
        }
        for text in intro.hello + [intro.outro, intro.builder, intro.map, intro.homes, intro.tagline] + intro.room.map(\.text) {
            #expect(Self.problems(in: text, limit: 90).isEmpty, "\(text): \(Self.problems(in: text, limit: 90))")
        }
        #expect(intro.room.filter { $0.reward == true }.count == 1)
        #expect(intro.room.last?.reward == true)
    }

    /// Step 9's content bar (SPEC "Build phases": 600 lines loaded, reading right in all four personalities).
    @Test func everyLineContextSpeaksInAllFourPersonalities() {
        let variants = content.lines.lines.reduce(0) { $0 + $1.variants.count }
        #expect(variants >= 600, "\(variants) lines")
        for context in content.lines.contexts {
            let speakers = Set(content.lines.lines.filter { $0.context == context.id }.map(\.personality))
            #expect(speakers.count == Personality.allCases.count, "\(context.id): \(speakers.count) personalities")
        }
        for goal in GameEvent.HealthGoal.allCases {
            #expect(content.lines.contexts.contains { $0.id == HealthRules.line(goal) })
        }
    }

    @Test func theRulesEngineLoadsTheContent() throws {
        let context = try content.rulesContext()
        #expect(context.gifts.count == 60)
        // The named seasons, then runs of them again for years (SeasonSchedule).
        #expect(context.seasons.count > content.seasons.seasons.count)
        #expect(ObjectiveRules.daily(from: context.dailyObjectives, household: 1, day: GameDay(index: 20500)).count == 3)
        #expect(content.affordances["kitchen_bowl"]?.contains(.eat) == true)
    }
}
