import Foundation
@testable import HouseCatCore
import Testing

private let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// The word filter as it ships (Content/names.json), on names a player might really type.
@Suite("The name filter")
struct CatNameFilterTests {
    let filter: NameFilter

    init() throws {
        filter = try ContentBundle.load(from: repo.appendingPathComponent("Content")).names
    }

    /// Cat names, people's names and places with a rude word inside an innocent one (the Scunthorpe problem),
    /// two words that only run together into one, and plain popular cat names.
    @Test(arguments: [
        "Cassie", "Cassius", "Lassie", "Sassy", "Classy", "Bassett", "Assisi", "Arsenal",
        "Dickens", "Dickie", "Hitchcock", "Hancock", "Peacock", "Cockatoo", "Cocker", "Shuttlecock",
        "Sussex", "Essex", "Middlesex", "Sexton",
        "Shitake", "Shiitake", "Ishita", "Yamashita", "Kinoshita", "Matsushita",
        "Titus", "Titan", "Titch", "Prickles", "Swanky", "Scrappy", "Grape", "Drape", "Torpedo", "Therapist",
        "Pissarro", "Penistone", "Clitheroe", "Cumbria", "Cucumber", "Uranus", "Spicy", "Japan", "Pakistan",
        "Nazir", "Pornthip", "Niggles", "Woggle", "Maine Coon", "Pussycat", "Fanny", "Butterscotch",
        "Rabbit Chaser", "Bit Chunky", "Stewart Watson", "Sir Pounce", "Mr Whiskers", "Lady Grey", "Kitty Kat",
        "Luna", "Bella", "Oliver", "Leo", "Milo", "Charlie", "Simba", "Nala", "Cleo", "Smokey", "Tiger", "Jasper",
        "Oscar", "Poppy", "Willow", "Shadow", "Ginger", "Mittens", "Socks", "Felix", "Salem", "Binx", "Mochi",
        "Midnight", "Pip", "Zzz", "Brrr",
    ])
    func innocentNamesPass(_ name: String) {
        #expect(CatNames.check(name, filter: filter) == .ok(name))
    }

    /// Swearing, sexual words, slurs and hate words, as typed and as dressed up to get past a filter.
    @Test(arguments: [
        "Shit", "Sh1t", "ShIt", "Sh!t", "Shiiiit", "Little Shit", "LittleShit", "Bullshit", "Shithead", "Shitty Cat",
        "Fuck", "F.u.c.k", "F U C K", "Fu ck", "Fuuuck", "Motherfucker", "MrFuckles", "Phuck", "Fvck",
        "Cunt", "Bigcunt", "Bitch", "Bit ch", "Biiitch", "Son of a Bitch", "Bastard", "Bollocks",
        "Dick", "BigDick", "Dickhead", "D i c k", "Di ck", "Cock", "Cocksucker", "Prick", "Twat", "Wank", "Wanker",
        "Ass", "A55", "Asss", "Jackass", "Asshole", "Arse", "Arsehole", "Tits", "Titties", "Boobs", "Penis",
        "Piss", "Pissed", "Pisshead", "Crap", "Turd", "Whore", "Slut", "Slag", "Dildo", "Porn", "Sex", "Cum", "Jizz",
        "Rape", "Rapist", "Paedo", "Pedo", "Nonce",
        "Nigger", "N1gga", "Faggot", "Fag", "Dyke", "Tranny", "Paki", "Chink", "Spic", "Kike", "Wog", "Pikey",
        "Retard", "Retarded", "Spaz", "Spastic", "Nazi", "Hitler", "Kkk",
    ])
    func rudeNamesAreTurnedDown(_ name: String) {
        #expect(CatNames.check(name, filter: filter) == .blocked)
    }

    /// The one innocent name caught, on purpose: "cunt" is looked for inside names (names.json's note).
    @Test func scunthorpeIsThePriceOfCatchingTheWorstWord() {
        #expect(CatNames.check("Scunthorpe", filter: filter) == .blocked)
    }

    /// Every list entry is one lower-case word, listed once, and catches itself.
    @Test func everyEntryIsOneWordAndCatchesItself() {
        for entry in filter.words + filter.anywhere {
            #expect(entry == entry.lowercased() && entry.allSatisfy(\.isLetter), "\(entry)")
            #expect(CatNames.check(entry.capitalized, filter: filter) == .blocked, "\(entry)")
        }
        #expect(Set(filter.words).count == filter.words.count)
        #expect(Set(filter.anywhere).count == filter.anywhere.count)
        #expect(Set(filter.words).isDisjoint(with: filter.anywhere))
    }
}
