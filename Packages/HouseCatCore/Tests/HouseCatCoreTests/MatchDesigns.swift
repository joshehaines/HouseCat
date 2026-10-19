import Foundation
@testable import HouseCatCore

/// The 60 Purrfect Match levels as laid out by hand: a room to tidy each, the goals growing from collecting pieces to
/// dust, parcels and tangles. `MatchLevelSearch` sets each level's moves and star scores from many games of
/// `MatchBot` and writes Content/match_levels.json; `MatchLevelTests` checks the file.
enum MatchDesigns {
    struct Draft {
        let title: String
        let layout: [String]
        let kinds: Int
        let goals: [String]
        /// How often the plain bot should win (it plays worse than a person), which sets the moves.
        let target: Double
    }

    static let full8 = Array(repeating: "oooooooo", count: 8)
    static let full7 = Array(repeating: "ooooooo", count: 7)

    static let drafts: [Draft] = [
        // 1–10: collecting, gentle.
        Draft(title: "Tidy the living room", layout: full7, kinds: 4, goals: ["collect:fish:12"], target: 0.98),
        Draft(title: "Toys in the basket", layout: full7, kinds: 4, goals: ["collect:yarn:15"], target: 0.95),
        Draft(title: "Mouse hunt", layout: full8, kinds: 5, goals: ["collect:mouse:18"], target: 0.95),
        Draft(title: "Biscuit tin", layout: full8, kinds: 5, goals: ["collect:biscuit:20"], target: 0.9),
        Draft(title: "Catnip garden", layout: full8, kinds: 5, goals: ["collect:catnip:15", "collect:fish:15"], target: 0.9),
        Draft(title: "Feather duster", layout: ["oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["collect:feather:20", "collect:yarn:20"], target: 0.85),
        Draft(title: "Round the rug", layout: [".oooooo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", ".oooooo."],
              kinds: 5, goals: ["collect:mouse:25"], target: 0.85),
        Draft(title: "Kitchen floor", layout: full8, kinds: 5, goals: ["collect:fish:20", "collect:biscuit:20"], target: 0.85),
        Draft(title: "Laundry day", layout: ["oooooooo", "oooooooo", "oo.oo.oo", "oooooooo", "oooooooo", "oo.oo.oo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["collect:yarn:25"], target: 0.8),
        Draft(title: "Spring clean", layout: full8, kinds: 6, goals: ["collect:catnip:20", "collect:feather:20", "collect:mouse:20"],
              target: 0.8),
        // 11–20: dust.
        Draft(title: "Under the sofa", layout: ["oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "dddddddd", "dddddddd", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.9),
        Draft(title: "Dusty corners", layout: ["ddoooodd", "dooooood", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "dooooood", "ddoooodd"],
              kinds: 5, goals: ["dust"], target: 0.85),
        Draft(title: "Behind the bookcase", layout: ["oooooooo", "oooooooo", "oooDDooo", "ooDDDDoo", "ooDDDDoo", "oooDDooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.85),
        Draft(title: "The attic stairs", layout: ["ooo.....", "oooo....", "ooooo...", "oooooo..", "ddddddd.", "dddddddd", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.8),
        Draft(title: "Rug beating", layout: ["oooooooo", "oddddddo", "odDDDDdo", "odDDDDdo", "oddddddo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.75),
        Draft(title: "Cobweb hunt", layout: ["dddddddd", "dooooood", "dooooood", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["dust", "collect:feather:15"], target: 0.75),
        Draft(title: "Hall table", layout: [".oooooo.", ".oooooo.", "oooooooo", "dddddddd", "dddddddd", "oooooooo", ".oooooo.", ".oooooo."],
              kinds: 5, goals: ["dust"], target: 0.75),
        Draft(title: "Two rugs", layout: ["ddd..ddd", "ddd..ddd", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "ddd..ddd", "ddd..ddd"],
              kinds: 5, goals: ["dust"], target: 0.7),
        Draft(title: "Window sill", layout: ["DDDDDDDD", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust", "collect:fish:20"], target: 0.7),
        Draft(title: "Deep clean", layout: ["dddddddd", "dddddddd", "dddddddd", "oooooooo", "oooooooo", "dddddddd", "dddddddd", "dddddddd"],
              kinds: 5, goals: ["dust"], target: 0.65),
        // 21–30: parcels.
        Draft(title: "Moving day", layout: ["oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "pppooppp", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.9),
        Draft(title: "The post", layout: ["oooooooo", "oooooooo", "oopppppo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.85),
        Draft(title: "Boxes everywhere", layout: ["oooooooo", "oPoooopo", "oooooooo", "ooPooPoo", "oooooooo", "opooooPo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.8),
        Draft(title: "Tied with string", layout: ["oooooooo", "oooooooo", "ooPPPPoo", "ooPPPPoo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.8),
        Draft(title: "A box to sit in", layout: ["oooooooo", "oooooooo", "oooooooo", "ooPPPPoo", "ooPPPPoo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels", "collect:mouse:15"], target: 0.75),
        Draft(title: "Delivery", layout: ["oooooooo", "poooooop", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "poooooop"],
              kinds: 5, goals: ["parcels", "collect:biscuit:20"], target: 0.75),
        Draft(title: "Parcels and dust", layout: ["oooooooo", "oooooooo", "pppppppp", "dddddddd", "dddddddd", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels", "dust"], target: 0.7),
        Draft(title: "Stacked up", layout: ["oooooooo", "oooooooo", "oPPooPPo", "oPPooPPo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.7),
        Draft(title: "The spare room", layout: ["oooooooo", "pooooooP", "oooooooo", "dddddddd", "oooooooo", "Poooooop", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels", "dust"], target: 0.65),
        Draft(title: "Unpacking", layout: ["oooooooo", "oooooooo", "oooooooo", "PPPPPPPP", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.65),
        // 31–40: tangles.
        Draft(title: "Knitting basket", layout: ["oooooooo", "oooooooo", "otttttto", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["collect:yarn:20"], target: 0.85),
        Draft(title: "In a tangle", layout: ["oooooooo", "ottootto", "oooooooo", "oooooooo", "oooooooo", "ottootto", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["collect:fish:20", "collect:yarn:20"], target: 0.8),
        Draft(title: "Wool everywhere", layout: ["toooooot", "otooooto", "ootootoo", "oooooooo", "oooooooo", "ooottooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["collect:catnip:20"], target: 0.75),
        Draft(title: "Dust and wool", layout: ["oooooooo", "otDDDDto", "otDDDDto", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.75),
        Draft(title: "Ball of string", layout: [".oooooo.", "oottttoo", "otooooto", "otooooto", "oottttoo", "oooooooo", "oooooooo", ".oooooo."],
              kinds: 5, goals: ["collect:mouse:25"], target: 0.7),
        Draft(title: "Sewing box", layout: ["oooooooo", "oooooooo", "oooooooo", "tttttttt", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["collect:feather:25"], target: 0.7),
        Draft(title: "Parcel and string", layout: ["oooooooo", "otPootPo", "oooooooo", "oooooooo", "oooooooo", "oPttoPto", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels"], target: 0.7),
        Draft(title: "Cosy corner", layout: ["tttooooo", "tdddoooo", "tdddoooo", "oooooooo", "oooooooo", "oooodddt", "oooodddt", "ooooottt"],
              kinds: 5, goals: ["dust"], target: 0.65),
        Draft(title: "Six of everything", layout: full8, kinds: 6, goals: ["collect:fish:15", "collect:yarn:15", "collect:mouse:15"], target: 0.7),
        Draft(title: "The big tidy", layout: ["oooooooo", "otDDDDto", "oPDDDDPo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust", "parcels"], target: 0.65),
        // 41–60: six kinds and everything at once.
        Draft(title: "Tea party", layout: full8, kinds: 6, goals: ["collect:biscuit:25"], target: 0.75),
        Draft(title: "Book club", layout: ["dddddddd", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "dddddddd"],
              kinds: 6, goals: ["dust"], target: 0.7),
        Draft(title: "Fishmonger", layout: [".oooooo.", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", ".oooooo."],
              kinds: 6, goals: ["collect:fish:30"], target: 0.7),
        Draft(title: "Post office", layout: ["oooooooo", "oooooooo", "PPPPPPPP", "oooooooo", "oooooooo", "pppppppp", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["parcels"], target: 0.7),
        Draft(title: "Rainy afternoon", layout: ["oooooooo", "otddddto", "odDDDDdo", "odDDDDdo", "oddddddo", "otooooto", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["dust"], target: 0.65),
        Draft(title: "Hide and seek", layout: ["oooooooo", "oPooooPo", "oooooooo", "ooDDDDoo", "ooDDDDoo", "oooooooo", "oPooooPo", "oooooooo"],
              kinds: 6, goals: ["parcels", "dust"], target: 0.65),
        Draft(title: "Birthday", layout: full8, kinds: 6, goals: ["collect:yarn:20", "collect:feather:20", "collect:catnip:20"], target: 0.65),
        Draft(title: "The cat flap", layout: ["oooooooo", "oooooooo", "oo....oo", "oo....oo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["collect:mouse:25"], target: 0.65),
        Draft(title: "Sunbeam", layout: ["DDoooooo", "dDDooooo", "ddDDoooo", "oddDDooo", "ooddDDoo", "oooddDDo", "ooooddDD", "oooooddD"],
              kinds: 5, goals: ["dust"], target: 0.6),
        Draft(title: "Crowded shelf", layout: ["oooooooo", "PPPooPPP", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["parcels"], target: 0.6),
        Draft(title: "Midnight feast", layout: full8, kinds: 6, goals: ["collect:fish:25", "collect:biscuit:25"], target: 0.6),
        Draft(title: "Wardrobe", layout: ["ooo..ooo", "ooo..ooo", "ooo..ooo", "oooooooo", "dddddddd", "dddddddd", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.6),
        Draft(title: "Toy box", layout: ["otttttto", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oppppppo"],
              kinds: 6, goals: ["parcels", "collect:mouse:20"], target: 0.6),
        Draft(title: "Lost and found", layout: ["dddddddd", "dpoooopd", "dooooood", "oooooooo", "oooooooo", "dooooood", "dpoooopd", "dddddddd"],
              kinds: 5, goals: ["dust", "parcels"], target: 0.55),
        Draft(title: "Grandma's chair", layout: [".oooooo.", "oottttoo", "oooooooo", "oooooooo", "dddddddd", "dddddddd", "oooooooo", ".oooooo."],
              kinds: 6, goals: ["dust"], target: 0.55),
        Draft(title: "Snow day", layout: ["DDDDDDDD", "DDDDDDDD", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["dust"], target: 0.55),
        Draft(title: "Bedtime story", layout: full8, kinds: 6, goals: ["collect:feather:30", "collect:mouse:30"], target: 0.55),
        Draft(title: "The whole house", layout: ["oooooooo", "otPDDPto", "oooooooo", "oDDooDDo", "oooooooo", "otPDDPto", "oooooooo", "oooooooo"],
              kinds: 6, goals: ["dust", "parcels"], target: 0.5),
        Draft(title: "Housewarming", layout: ["oooooooo", "oooooooo", "PPPPPPPP", "oooooooo", "dddddddd", "dddddddd", "oooooooo", "oooooooo"],
              kinds: 5, goals: ["parcels", "dust"], target: 0.5),
        Draft(title: "Purrfect", layout: ["DDDDDDDD", "dttttttd", "dooooood", "dooooood", "dooooood", "dooooood", "dppppppd", "dddddddd"],
              kinds: 5, goals: ["dust", "parcels"], target: 0.45),
    ]
}
