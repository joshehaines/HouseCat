import Foundation

/// Every tunable constant in HouseCat. Values come from docs/SPEC.md, where each
/// number is a locked decision, and from Josh's answers recorded in CLAUDE.md
/// ("Decisions during milestone 0"). Tune them here and nowhere else.
public enum Tuning {
    /// Room geometry: 2:1 isometric corner rooms (SPEC "Perspective").
    public enum Room {
        public static let gridWidth = 10
        public static let gridDepth = 10
        public static let wallHeightCells = 5
        /// Furniture is drawn this much smaller than it was painted in the grey reference room, so it sits right
        /// beside the cat (Josh, 19 Oct: "the couches look huge as well as the scratching post"). Footprints stay
        /// whole cells: a piece stands in the middle of its cells, its back to a wall it touches.
        public static let furnitureScale = 0.8
        /// A new player's home (Josh, 19 Oct: "it needs to be empty, they should want to decorate"): only these,
        /// where the demo layout puts them.
        public static let firstHome: Set<String> = ["kitchen_bowl", "living_box"]
        /// Waiting in the tray for the tour's Decorate step.
        public static let starterPieces = ["living_sofa"]
    }

    /// The game day and the parts of it (SPEC "Care and the visit streak", "Widgets").
    public enum Day {
        /// A game day starts at the player's wake time.
        public static let defaultWakeMinutes = 6 * 60
        public static let defaultBedtimeMinutes = 23 * 60
        public static let defaultTimeZoneID = "Europe/London"
        /// Time-of-day bands for the cat brain, as local minutes after midnight.
        public static let middayStartMinutes = 11 * 60
        public static let afternoonStartMinutes = 14 * 60
        public static let eveningStartMinutes = 18 * 60
        /// "Feed before 09:00" objective.
        public static let earlyFeedBeforeMinutes = 9 * 60
        /// Greeting lines: an arrival from 23:00 is late, before 06:00 early (Content/lines.json).
        public static let lateNightMinutes = 23 * 60
        public static let earlyMinutes = 6 * 60
    }

    /// Trusted time (CLAUDE.md "Trusted time").
    public enum Time {
        /// A wall clock further than this ahead of the trusted anchor pauses game time.
        public static let maxClockLead: TimeInterval = 24 * 60 * 60
    }

    /// Player XP (SPEC "XP and levels").
    public enum XP {
        public static let arrival = 5
        public static let feed = 10
        /// First pet of the day, then diminishing; further pets give nothing.
        public static let pets = [5, 2, 1]
        public static let play = 5
        public static let giftCollected = 5
        public static let nap = 10
        public static let furniturePlaced = 3
        public static let furniturePlacedMaxPerDay = 9
        public static let catUsedNewFurniture = 3
        public static let catUsedNewFurnitureMaxPerDay = 6
        public static let stepsGoalMet = 10
        public static let sleepGoalMet = 10
        public static let workoutLogged = 10
    }

    /// Health goals (SPEC "Health layer"); rewards only, never a penalty.
    public enum Health {
        public static let stepsGoal = 8000
        public static let sleepGoalHours = 7.0
        /// The health layer is offered on this day of looking after the cat.
        public static let askOnCareDay = 3
    }

    /// Cumulative XP to reach each level (SPEC "XP and levels").
    public enum Levels {
        /// Index 0 is level 1, index 11 is level 12.
        public static let thresholds = [0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700, 3250, 3850]
        public static let xpPerLevelAfterTable = 650
        /// The roadmap shows this many levels ahead.
        public static let roadmapAhead = 8
        /// How long "+12 XP" floats by the level after it is earned.
        public static let floatSeconds = 1.6
    }

    /// Trust: the count of days a cat was fed (SPEC "Two progressions").
    public enum Trust {
        /// Care days for Wary, Curious, Comfortable, Bonded, Devoted, Soulmate.
        public static let tierCareDays = [3, 7, 14, 30, 60, 100]
    }

    /// The visit streak (SPEC "Care and the visit streak").
    public enum Streak {
        public static let graceMissesPerWindow = 1
        public static let graceWindowDays = 7
        public static let pauseDaysPerQuarter = 14
        public static let milestoneDays = [7, 30, 100, 365]
        public static let milestoneBeans = [100, 300, 1000, 3000]
        /// A lost streak can be mended for this many days after the miss, by a day with a visit, a feed and a game.
        public static let repairWindowDays = 3
        /// After a missed day: sulky on the first return visit, thawing on the second, fine from the third.
        public static let warmUpArrivals = 3
        /// A miss this long or longer gets the "week plus" greeting.
        public static let weekMissDays = 7
    }

    /// The co-owners' shared quest (Duolingo's friends quest): days visited between them in a week, each owner
    /// pitching in at least a few, for Beans once a week.
    public enum Coop {
        public static let questVisits = 10
        public static let questMinimumEach = 3
        public static let questBeans = 300
        /// A friend code stands for an invite this long, and has this many characters.
        public static let friendCodeHours = 48
        public static let friendCodeLength = 6
        /// Paw prints a phone can send a day (a nudge, never a nag).
        public static let pawPrintsPerDay = 1
    }

    /// Beans: the one currency, earned in play and sold in packs (Josh, 18 Oct: like a builder game's gems);
    /// they never expire.
    public enum Beans {
        /// A piece from a room look bought alone, by size (one cell or a wall piece, two cells, larger).
        public static let paidPieceSmall = 250
        public static let paidPieceMedium = 400
        public static let paidPieceLarge = 550
        /// A paid outfit, bought with Beans.
        public static let outfit = 450
        /// The Bean packs, smallest to largest (StoreCatalog prices them at £0.99, £1.99, £3.99, £9.99, £19.99:
        /// each bigger pack gives more Beans a pound).
        public static let packs = [500, 1_200, 2_600, 7_000, 15_000]
        /// The once-only starter offer at £1.99 (the pouch's price, more Beans).
        public static let starterPack = 2_000
        public static let housewarmingAllowance = 150
        public static let dailyArrival = 10
        public static let levelUp = 100
        /// Cat Club: +20% on everything earned that day.
        public static let clubBonusPercent = 20
        public static let moveHome = 500
        public static let freeHomeMoves = 1
        /// The welcome at the end of the intro's tour of the room, once.
        public static let tourReward = 100
    }

    /// Room gating: a level AND Beans above the allowance (CLAUDE.md "First arrival").
    public enum Rooms {
        public static let bedroomLevel = 2
        public static let bedroomBeans = 200
        public static let kitchenLevel = 3
        public static let kitchenBeans = 300
        public static let gardenLevel = 6
        public static let gardenBeans = 800
        public static let studyLevel = 9
        public static let studyBeans = 1500
        public static let atticLevel = 12
        public static let atticBeans = 2500
        /// Cat Club halves the Bean cost (never the level).
        public static let clubDiscountPercent = 50
    }

    /// The daily gift (SPEC "Gifts", CONTENT.md §3).
    public enum Gifts {
        /// The gift on the floor, as a fraction of the cat's standing height, and how long after the greeting
        /// starts it lands at the cat's feet.
        public static let dropSize = 0.45
        public static let dropDelay = 1.4
        /// After the cat starts rubbing at your feet.
        public static let rubDropDelay = 0.5
        /// Draw weights in percent: common, uncommon, rare, legendary.
        public static let baseWeights = [60, 28, 10, 2]
        /// Each trust tier moves 3 points from common: +2 to rare and +1 to legendary (Josh, 17 Oct).
        public static let perTierShift = [-3, 0, 2, 1]
        /// Beans paid when a gift is collected, by rarity.
        public static let collectBeans = [5, 10, 25, 100]
        /// Beans paid when a duplicate is sold back, by rarity.
        public static let sellBackBeans = [5, 15, 40, 100]
        /// Earliest drop after feeding.
        public static let earliestAfterFeed: TimeInterval = 60 * 60
        /// Latest drop, local minutes; a gift that would fall later comes next morning.
        public static let latestDropMinutes = 22 * 60
        /// A next-morning drop lands within this many minutes after the wake time.
        public static let morningDropWindowMinutes = 60
    }

    /// Season pass (SPEC "Season pass", CONTENT.md §7).
    public enum Lines {
        /// Days the first arrival greets with their own lines (month-day, the home's local date).
        public static let eventDays = [
            "10-27": "event.black_cat_day",
            "08-17": "event.black_cat_day",
            "10-31": "event.halloween",
            "01-01": "event.new_year",
        ]
    }

    public enum Events {
        /// How many years of a yearly event (the Christmas one) the rules know about ahead.
        public static let yearsAhead = 6
    }

    public enum Pass {
        public static let seasonLengthDays = 28
        /// December is always the Christmas season: four weeks from 1 December (Josh, 18 Oct).
        public static let christmasMonth = 12
        public static let christmasStartDay = 1
        /// Twelve four-week seasons and the Christmas season make a year.
        public static let seasonsPerYear = 13
        public static let tiers = 20
        /// Spec is silent; 50 a tier puts tier 20 at 1,000 points, about day 23 of normal play.
        public static let pointsPerTier = 50
        /// Daily cap on activity points (objective points are on top).
        public static let dailyCap = 60
        public static let visit = 10
        public static let feed = 10
        /// "play" and "mini-game" in SPEC are the same action: 5 a mini-game play (CONTENT.md §6).
        public static let miniGame = 5
        /// Placing furniture pays once a day.
        public static let placeFurniture = 5
        public static let sundayCard = 20
    }

    /// Mini-games (CONTENT.md §6).
    public enum MiniGames {
        public static let playsPerDay = 5
        /// Beans for one, two and three stars (Josh, 17 Oct).
        public static let starBeans = [2, 4, 6]
        /// The floor the cat plays on, in cells.
        public static let arenaWidth = 12.0
        public static let arenaHeight = 6.0
        /// How fast each personality chases, in cells a second (it changes the feel, never the stars).
        public static let chaseSpeed: [String: Double] = ["aloof": 3.0, "velcro": 3.6, "gremlin": 4.0, "loaf": 2.7]
        /// Every game is this long on the clock (Josh, 19 Oct: "very basic right now and too long"), so a round from
        /// the tap to the result is about half a minute; the count before it, a beat at each number.
        public static let roundSeconds = 20.0
        public static let countSeconds = 0.6
        /// Hits in a row make a combo: a hit scores 1, and 1 more for every `comboStep` hits in a row, up to
        /// `comboCap`; the combo lapses after `comboSeconds` without a hit. A golden target scores `goldenTimes`
        /// over; catnip's zoomies double everything for `zoomiesSeconds`.
        public static let comboCap = 5
        public static let comboStep = 2
        public static let comboSeconds = 3.0
        public static let goldenTimes = 3
        public static let zoomiesTimes = 2
        public static let zoomiesSeconds = 4.0
        /// How much faster the cat is by the end of a game than at the start (the ramp).
        public static let rampShare = 0.3
        /// Laser Pointer: a dot slower than this (cells a second) counts as still, and a dot still this long
        /// bores the cat; how quickly the cat turns. Within `pounceRange` after `stalkSeconds` of chase it crouches
        /// for `crouchSeconds` and springs up to `leapCells` at the dot, in the air `leapSeconds`; the dot still
        /// within `catchReach` of where it lands is caught (the reach narrows a little with the combo), and it sits
        /// on its catch for `landSeconds`. The dot turns golden for `goldenSeconds`, twice a game.
        public static let laserMovingSpeed = 0.6
        public static let laserBoredSeconds = 1.6
        public static let laserGrip = 4.0
        public static let pounceRange = 1.9
        public static let stalkSeconds = 0.45
        public static let crouchSeconds = 0.22
        public static let leapSeconds = 0.3
        public static let leapCells = 2.4
        public static let catchReach = 0.95
        public static let catchReachPerCombo = 0.05
        /// A pounce that lands right on the dot (the dot held still) scores `perfectTimes` over.
        public static let perfectReach = 0.35
        public static let perfectTimes = 2
        public static let landSeconds = 0.35
        public static let goldenSeconds = 3.0
        /// Knock It Off: the cat walks the mantel and swipes what is in front of it. Up to `shelfSlots` things
        /// stand on it, `shelfStart` to begin with and another every `spawnSeconds` (from the first to the last
        /// value over the game); it crosses the shelf at `walkShelf` (a share of the shelf a second; a personality's
        /// chase speed scales it), a little faster with each hit; how near it must be (a share of the shelf); a
        /// swipe at nothing rests it a moment. Golden things now and then, and one catnip fish.
        public static let shelfSlots = 6
        public static let shelfStart = 3
        public static let spawnSeconds = [1.1, 0.55]
        public static let walkShelf = 0.42
        public static let pawReach = 0.075
        public static let pawSpeedUp = 1.05
        public static let pawTopSpeed = 1.8
        public static let missRestSeconds = 0.45
        /// String Chase: up to `sparklesAtOnce` sparkles, each lasting `sparkleLife` (from the first to the last value
        /// over the game), a new one `sparkleGap` after one goes, between `sparkleSpacing` cells from the cat (so
        /// every play has runs of about the same length); collected within `sparkleReach`.
        public static let sparklesAtOnce = 3
        public static let sparkleLife = [5.0, 3.2]
        public static let sparkleGap = 0.35
        public static let sparkleSpacing = [2.5, 5.5]
        public static let sparkleReach = 0.8
        /// A string run is mostly distance, so String Chase keeps only this share of a personality's difference
        /// in chase speed (the stars are the same for every cat).
        public static let stringSpeedShare = 0.4
        /// Hide and Seek: the cat hides behind one of `hidePlaces` while the player's eyes are shut
        /// (`hideSeconds`), then peeks out for `peekSeconds` every `peekEvery` (both from the first to the last value
        /// over the game), the first peek `firstPeek` after it hides; found within `quickSeconds` is quick (twice the
        /// points); a wrong place rests the player `missRestSeconds` and makes the cat peek; after `comeOutSeconds`
        /// unfound it comes out by itself. Other places rustle as decoys from `rustleFrom` into the game, the first one
        /// just before the cat's first peek, then every `rustleEvery`. It stays out, found, for `foundSeconds`.
        public static let hidePlaces = 5
        public static let hideSeconds = 0.55
        public static let peekSeconds = [0.55, 0.3]
        public static let peekEvery = [0.9, 1.6]
        public static let firstPeek = 0.35
        public static let quickSeconds = 1.1
        public static let comeOutSeconds = 4.0
        public static let rustleFrom = 0.35
        public static let rustleEvery = 1.1
        public static let foundSeconds = 0.6
        /// Where the cat hides (furniture pictures), and whether it peeks over the top or out at the side.
        public static let hidingPlaces: [(picture: String, side: Bool)] = [
            ("furniture/living/furn_living_box_R", false), ("furniture/living/furn_living_armchair_R", false),
            ("furniture/bedroom/furn_bedroom_laundry_R", false), ("furniture/living/furn_living_sofa_R", false),
            ("furniture/living/furn_living_plant_R", true), ("furniture/living/furn_living_cattree_R", true),
        ]
        /// The scene: the cat this many cells tall, the top of the screen kept for the clock and stars.
        public static let catCells = 2.6
        public static let hudShare = 0.16
        /// What stands on the shelf in Knock It Off (gift pictures), and the catnip fish.
        public static let shelfThings = [
            "gift_keepsakes_little_ceramic_fish", "gift_keepsakes_tiny_silver_bell", "gift_keepsakes_small_seashell",
            "gift_keepsakes_acorn", "gift_keepsakes_marble", "gift_toys_jingle_ball", "gift_toys_cork",
            "gift_toys_ping_pong_ball",
        ]
        public static let catnip = "gift_toys_catnip_fish"
    }

    /// Anonymous usage counts (Shared Analytics): PostHog's EU capture endpoint.
    public enum Analytics {
        public static let endpoint = URL(string: "https://eu.i.posthog.com/capture/")!
    }

    /// The intro (Content/intro.json): how close the globe comes to each home, and the pause before it opens.
    public enum Intro {
        public static let stopZoom = 2.4
        public static let pauseOnArrival = 0.5
        /// The room tour begins this long after the first arrival's room is up (the greeting first).
        public static let tourDelay = 4.0
        /// The globe slides between the landing page's place and the middle in this long.
        public static let globeSlideSeconds = 0.9
    }

    /// The animated logo (HouseCatGame `LogoScene`): Midnight runs in, leaps onto the wordmark and curls up asleep on
    /// it. Lengths are in the pixels of the wordmark's box (assets/brand/logo/wordmark_on_*.png) from its bottom left.
    public enum Logo {
        /// The box: the letters along its bottom, clear room above them for the sleeping cat.
        public static let boxSize = [1647.0, 480.0]
        /// The letters' baseline (the ground the cat runs in on) and the top of the lowercase "ouse" it curls up on.
        public static let baseline = 24.0
        public static let valleyTop = 221.0
        /// The letters' tops, [from x, to x, top]: the H, "ouse", the C, the a, the t (for the shadow).
        public static let tops: [[Double]] = [[20, 300, 292], [310, 1040, 221], [1060, 1290, 300], [1300, 1470, 222], [1480, 1630, 270]]
        /// The cat standing; the curl it ends in is drawn this much bigger, to be about a letter's size.
        public static let catHeight = 560.0
        public static let curlScale = 1.3
        /// Where it leans and grows about, up from its feet (cat heights); how far out of sight it starts.
        public static let pivotHeight = 0.35
        public static let offscreen = 0.8
        /// Where it springs from the ground, lands among the letters (clear of the H), and curls up.
        public static let takeOff = -360.0
        public static let landing = 640.0
        public static let bed = 690.0
        /// The leap: how high its feet go, the crouch on the run and the time in the air (seconds), its squash (on
        /// the puppet's), and how far it leans into the climb and the fall (share of the arc's angle).
        public static let leapTop = 470.0
        public static let crouchSeconds = 0.1
        public static let leapSeconds = 0.55
        public static let leapSquash = 1.5
        public static let lean = 0.3
        /// In the air, how far the front legs reach out ahead and the back legs push out behind (degrees).
        public static let leapReach = 40.0
        public static let leapPush = 50.0
        /// Paces (cat heights a second): running in on the intro, trotting to its spot.
        public static let runSpeed = 3.0
        public static let trotSpeed = 1.4
        /// The launch's pounce from just off the edge (cat heights) straight onto its spot: seconds in the air and how
        /// high its feet go.
        public static let launchOffscreen = 0.6
        public static let launchLeapSeconds = 0.55
        public static let launchLeapTop = 520.0
        /// The intro: the wordmark alone first, then a look round at you before it sleeps. Seconds sitting before it
        /// curls up (intro, launch); the fade from the puppet into sitting, and the cross-fade into the curl.
        public static let introHold = 0.6
        public static let lookSeconds = 1.1
        public static let sitSeconds = 0.7
        public static let launchSitSeconds = 0.25
        public static let sitFadeSeconds = 0.1
        public static let curlSeconds = 0.3
        /// Its soft shadow: width and depth (shares of the cat's width), strength, and least share left in the air.
        public static let shadowWidth = 0.75
        public static let shadowDepth = 0.18
        public static let shadowAlpha = 0.35
        public static let shadowLeast = 0.35
        /// A painted pose's width and middle (cat heights), for the shadow and the light while it rests; the cat
        /// standing side on, where the curl film starts.
        public static let restWidth = 0.45
        public static let restMiddle = 0.25
        public static let standWidth = 0.95
        public static let standMiddle = 0.5
        /// The curl film's frames (tools/asset-pipeline/logo/curlkey.py): their size and the cat's standing height in
        /// them (pixels), its feet at the bottom middle.
        public static let curlFrameSize = [1200.0, 720.0]
        public static let curlFrameCatHeight = 620.0
        /// Over a dark background, a soft light behind the cat: its size (cat heights), strength, and how quickly
        /// it follows the cat (a share of the way a second).
        public static let glowSize = 1.6
        public static let glowAlpha = 0.24
        public static let glowFollow = 6.0
        /// How far the scene reaches above the box (box heights): the cat standing on the letters, its leap.
        public static let headroom = 2.2
        /// The launch's film (the launch telling rendered by tools/app-assets/build_logo_film.sh: it plays while the
        /// app is busy building the home, when a SpriteKit scene would stand still). The box's width in its pixels
        /// (the phone's launch picture at 3x); how far it runs left of the box and right from the box's left edge (box
        /// widths: past the screen's edge on every phone and iPad held sideways) and up (box heights); frames a
        /// second; seconds held after the cat is asleep; quality (0-1, colour and transparency).
        public static let filmBoxWidth = 1200.0
        public static let filmLeft = 0.8
        public static let filmRight = 0.75
        public static let filmHeight = 2.3
        public static let filmFPS = 30
        public static let filmTail = 0.5
        public static let filmQuality = 0.45
        /// The home is built once the film is on screen, or after this long at most (seconds).
        public static let filmWait = 0.03
        /// The whole film plays every launch (Josh, 19 Oct): the home is built this long before it ends (seconds), and
        /// the launch goes on after this long whatever the film is doing.
        public static let launchBuildLead = 1.5
        public static let launchHoldMost = 14.0
    }

    /// The nap (SPEC "Care"): a wind-down timer as a Live Activity.
    public enum Nap {
        public static let minutes = 20.0
        /// A finished nap stays on the Lock Screen this long.
        public static let lingerMinutes = 15.0
    }

    /// Objectives (CONTENT.md §5).
    public enum Objectives {
        public static let dailyCount = 3
        public static let weeklyCount = 3
    }

    /// Care actions (SPEC "The session loop").
    public enum Care {
        /// Taps in a row before the cat walks off (never a Velcro cat).
        public static let overPetTaps = 6
        /// A cat that follows you sets off after you this long after you go to another room.
        public static let followDelaySeconds = 1.2
        /// Pets closer together than this count as in a row.
        /// A note over the room ("+10 Beans", "Level 3") stays this long.
        public static let toastSeconds = 2.4
        public static let petRowSeconds = 3.0
        /// How long a care line stays up.
        public static let lineSeconds = 3.0
        public static let napMinutes = 20
    }

    /// The cat (SPEC "Cat builder", "Age and time together").
    public enum Cat {
        public static let nameMaxLength = 20
        public static let kittenStartAgeDays = 12 * 7
        public static let kittenGrowsUpAtDay = 21
        public static let adultDefaultAgeDays = 2 * 365
        /// Maine Coon is drawn larger.
        public static let maineCoonScale = 1.15
        public static let kittenHeadScale = 1.25
        public static let kittenBodyScale = 0.8
        /// The kitten puppet and poses are drawn this much of the adult's height.
        public static let kittenScale = 0.72
        /// The weight slider (Shorthair and Longhair, 0 slim … 1 chunky): where each set sits, and how much
        /// wider or narrower than painted the torso is drawn at either end of a set.
        public static let slimDefaultWeight = 0.25
        public static let chunkyDefaultWeight = 0.75
        public static let weightStretch = 0.06
        public static let maxAdultYears = 20
        /// Below this coat luminance (0–255) a new pattern defaults to a lighter colour, above it a darker one.
        public static let darkCoatLuminance = 80.0
        /// A picked coat or pattern colour's luminance (0–255) is held inside this range.
        public static let pickerMinLuminance = 40.0
        public static let pickerMaxLuminance = 250.0
        /// Eye size slider: the irises are drawn this much smaller or larger at its ends.
        public static let eyeSizeRange = 0.18
        /// Whisker slider at 0: the whiskers are trimmed to this fraction of their painted reach.
        public static let shortestWhiskers = 0.35
    }

    /// The shop's links (App Review 3.1.2: shown with every subscription; 1.5: a support page), the pages of the
    /// site in website/ (live once the domain is bought and the site uploaded).
    public enum Store {
        /// The starter offer's beanie and armchair (what its picture shows), given with its Beans.
        public static let starterOutfit = "beanie"
        public static let starterPiece = "living_armchair"
        /// The one card that mentions the shop unasked comes when the cat first reaches this trust tier.
        public static let offerTrustTier = TrustTier.wary
        public static let termsURL = URL(string: "https://housecatgame.com/terms/")!
        public static let privacyURL = URL(string: "https://housecatgame.com/privacy/")!
        public static let supportURL = URL(string: "https://housecatgame.com/support/")!
        public static let supportEmail = "support@housecatgame.com"
        /// Where a co-owner's name or presents are reported (App Review 1.2; the Online Safety Act).
        public static let safetyEmail = "safety@housecatgame.com"
        public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
        /// WeatherKit's legal page, until the service gives its own (it needs the capability).
        public static let weatherLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
    }

    /// The shop's layout (App ShopView): drawn for a landscape phone, then scaled up to fill a taller screen.
    public enum Shop {
        /// The screen height (points) the layout is drawn for, a landscape phone's; a taller screen scales
        /// everything up, in steps of 0.05, to `largestScale`.
        public static let designHeight = 402.0
        /// The width inside the safe area (points) the pages are drawn for: the header's six tabs, or the five Bean
        /// packs side by side. A narrower phone draws it all smaller, down to `smallestScale`.
        public static let designWidth = 750.0
        public static let smallestScale = 0.8
        public static let largestScale = 1.6
        /// The honey-oak header with its tabs, one tab's width, and the foot with Restore, Terms and Privacy.
        public static let headerHeight = 62.0
        public static let tabWidth = 74.0
        public static let footerHeight = 26.0
        /// A page's height at scale 1 (the detail panel matches it); on a taller screen (an iPad) a page of tiles
        /// grows to half as tall again and the one-card pages (Cat Club, the pass) a fifth, then they sit in the middle.
        public static let pageHeight = 288.0
        public static let pageGrowth = 1.5
        public static let cardGrowth = 1.2
    }

    /// The weather over the exterior and in the windows (HouseCatGame WeatherLayer).
    public enum Weather {
        /// A wash over the picture: red, green, blue, strength.
        public static let overcastVeil = [0.55, 0.6, 0.7, 0.16]
        public static let rainVeil = [0.32, 0.38, 0.5, 0.26]
        public static let stormVeil = [0.2, 0.22, 0.34, 0.42]
        public static let snowVeil = [0.9, 0.93, 1.0, 0.14]
        public static let fogVeil = [0.86, 0.88, 0.92, 0.22]
        public static let heatVeil = [1.0, 0.82, 0.55, 0.1]
        /// Biomes whose ground lies under snow all winter.
        public static let whiteWinters: Set<String> = ["mountain", "forest"]
        /// A real weather report counts for a pin this close to where it was taken (kilometres).
        public static let reportRadiusKm = 25.0
        /// The app asks WeatherKit again after this long, and the report covers this many hours ahead.
        public static let reportRefreshMinutes = 30.0
        public static let reportHours = 72
        /// How grey the clouds are in each weather (0 white, 1 slate).
        public static let cloudGrey: [String: Double] = ["cloud": 0.3, "rain": 0.55, "storm": 0.8, "snow": 0.2, "wind": 0.15]
        /// About this many seconds between flashes in a storm.
        public static let lightningEvery = 7.0
        /// The size particles are drawn at: a raindrop is about half this long (points over the exterior,
        /// room units in a window).
        public static let exteriorUnit = 24.0
        public static let windowUnit = 14.0
        /// WeatherKit (step 5): how often to ask, and how long an answer is trusted.
        public static let fetchIntervalMinutes = 60
        public static let cacheHours = 3
    }

    /// The world map and places (SPEC "World map, search and seasons").
    public enum World {
        /// A pin this close to a listed city is city (big cities reach further).
        public static let cityRadiusKm = 18.0
        public static let bigCityRadiusKm = 35.0
        /// The map's zoom: fit the world at 1; city names appear from this zoom.
        public static let maxZoom = 12.0
        public static let cityNamesZoom = 3.0
        public static let bigCityNamesZoom = 1.8
        /// A place found by search is shown at this zoom.
        public static let searchZoom = 4.0
        /// The globe: how far it tips towards the poles (degrees), its size at zoom 1 (a fraction of the shorter
        /// side), how far in it zooms, how fast it turns by itself (degrees a second), how long a drag coasts
        /// (seconds to settle) and how long a flight to a place takes.
        public static let globeTiltLimit = 65.0
        public static let globeSize = 0.4
        public static let globeMaxZoom = 7.0
        public static let globeSearchZoom = 3.2
        public static let globeSpin = 7.0
        public static let globeCoast = 0.9
        public static let globeFlightSeconds = 1.8
        /// City names appear on the globe from these zooms, and fade out towards its rim.
        public static let globeBigCityZoom = 1.9
        public static let globeCityZoom = 3.4
        /// Choosing the place (Josh, 19 Oct: "a little glitchy, make it easier"): a flick turns it at most this fast
        /// (degrees a second at zoom 1); a tap this near a city's name (points) picks that city, as does one within
        /// `globeSnapKm` of a listed city (or within a fingertip, if smaller); else the town Apple Maps finds there,
        /// or, out at sea, the nearest listed city within `globeSeaSnapKm`. Then the pin is turned to the middle,
        /// coming in at least this close, in this long. Apple Maps is given this long (seconds) to answer before the
        /// pin is let go as it is.
        public static let globeFlickLimit = 160.0
        public static let globeTapReach = 36.0
        public static let globeSnapKm = 60.0
        public static let globeSeaSnapKm = 400.0
        public static let globeTapZoom = 2.4
        public static let globeTapFlightSeconds = 0.9
        public static let mapsPatience = 6.0
        /// The cities to pick from without searching: this many, up to `suggestedAtHome` from the player's own
        /// country first, then these from round the world.
        public static let suggestedCities = 8
        public static let suggestedAtHome = 3
        public static let suggestedWorld = ["London", "New York", "Paris", "Tokyo", "Sydney", "Toronto", "Cape Town", "São Paulo", "Mumbai", "Berlin"]
    }

    /// Debug launches only (HOUSECAT_HOUSE=full).
    public enum Debug {
        public static let fullHouseDays = 60
        public static let fullHouseBeans = 20000
    }

    /// Which room the cat goes to (RoomChoice).
    public enum CatRooms {
        /// "<affordance>.<time of day>" or "<affordance>" → the room type that is for it.
        public static let preferred: [String: String] = [
            "sleep.night": "bedroom",
            "sleep.afternoon": "bedroom",
            "eat": "kitchen",
            "watch.morning": "garden",
            "watch.midday": "garden",
            "watch.afternoon": "garden",
            "hide.afternoon": "attic",
            "perch.midday": "study",
            "sit.evening": "living",
        ]
        /// The chance the cat goes to that room when it has what it wants, and else stays where it is.
        public static let preferredPercent = 70
        public static let stayPercent = 55
        /// A wander goes into another open room this often (percent).
        public static let exploreElsewherePercent = 40
    }

    /// The cat's own ways (CatIdentity): how likely each favourite spot is by personality, how many quirks, how
    /// likely a night owl, and how much they weigh in what it does.
    public enum Identity {
        public static let spotWeights: [String: [String: Int]] = [
            "aloof": ["high": 4, "window": 4, "hidden": 2, "sunny": 2, "soft": 1, "nearYou": 1],
            "velcro": ["nearYou": 5, "soft": 3, "sunny": 2, "window": 1, "high": 1, "hidden": 1],
            "gremlin": ["hidden": 4, "high": 4, "window": 2, "nearYou": 2, "soft": 1, "sunny": 1],
            "loaf": ["soft": 5, "sunny": 4, "nearYou": 2, "window": 1, "high": 1, "hidden": 1],
        ]
        public static let quirks = 2
        public static let nightOwlPercent: [String: Int] = ["aloof": 55, "velcro": 35, "gremlin": 75, "loaf": 45]
        public static let favouriteSpotMultiplier = 3
        public static let quirkMultiplier = 2
    }

    /// How the cat is doing (Wellbeing): what it cares about having, by personality; today's fuss; the mix; and
    /// where each word starts (Settling in, Comfortable, Happy, Couldn't be happier).
    public enum Wellbeing {
        public static let wantWeight: [String: Double] = [
            "bed": 3, "seat": 2, "scratcher": 2, "hideaway": 1.5, "perch": 1.5, "window": 1.5, "toy": 1.5,
        ]
        public static let personalityWant: [String: [String: Double]] = [
            "loaf": ["bed": 2, "seat": 1.5],
            "gremlin": ["hideaway": 2, "toy": 2, "scratcher": 1.5],
            "aloof": ["perch": 2, "window": 2],
            "velcro": ["seat": 2, "bed": 1.2],
        ]
        public static let favouriteSpotWant = 1.5
        public static let fedCare = 0.5
        public static let strokeCare = 0.3
        public static let playCare = 0.2
        public static let strokesForFullCare = 3.0
        public static let homeShare = 0.5
        public static let careShare = 0.3
        public static let trustShare = 0.2
        public static let levelFrom = [0.0, 0.35, 0.6, 0.82]
        /// While it lacks something, a choice now and then comes with the line about it (percent).
        public static let wantLinePercent = 20
        /// No bed: at night or sleepy, it sleeps on the floor this often (percent) and says so.
        public static let floorSleepPercent = 70
        /// The thought bubble with what it would love: how long it stays and how big it is (room units).
        public static let bubbleSeconds = 6.0
        public static let bubbleSize = 160.0
        /// A line about what it sets off to do, this often (percent; twice for a chatty cat), never closer together
        /// than this (seconds).
        public static let chatterPercent = 30
        public static let chatterSeconds = 40.0
        /// After a visit's greeting, it thinks about what it would love this often (percent), this long after.
        public static let arrivalThoughtPercent = 60
        public static let arrivalThoughtDelay = 3.5
    }

    /// The cat's profile (SPEC "Age and time together").
    public enum Together {
        /// The together-count milestone with its own badge and line (then each year).
        public static let hundredDays = 100
    }

    /// The cat builder's live preview.
    public enum Builder {
        /// The cat's standing height in the preview's units (the room's demo cat is 150).
        public static let catHeight = 150.0
        /// The cat gets up and walks across the rug after this long, then every so often.
        public static let firstStrollSeconds = 3.0
        public static let strollEverySeconds = 14.0
        /// The presets row's thumbnails, in points.
        public static let presetThumbnail = 64.0
        /// The preview redraws this long after the last change (a slider drag redraws as it settles).
        public static let redrawDelay = 0.12

        // The dressing room (HouseCatGame DressingRoomScene, Josh 19 Oct: a wardrobe, not a living room).
        /// The painting, and where its podium's top is: the middle of the top, in the painting's pixels from its
        /// top left, and the top's width.
        public static let roomPainting = "ui/creator/creator_room.jpg"
        public static let podiumTop = [922.0, 1142.0]
        public static let podiumWidth = 805.0
        /// The cat's standing height as a share of the podium's width.
        public static let catOnPodium = 0.46
        /// The room is zoomed so the cat stands this share of the open stage's height, the podium's top this far
        /// up from the stage's bottom.
        public static let catInStage = 0.55
        public static let catInStageWidth = 0.6
        public static let podiumInStage = 0.2
        /// Close on the face for the eyes and the nose: this much nearer, the head's middle this far down the cat.
        public static let faceZoom = 2.1
        public static let faceFromTop = 0.2
        /// A drag this many points across turns the cat one step round the podium.
        public static let turnDragPoints = 46.0
        /// One step of the twirl a preset or a surprise look gets.
        public static let twirlStepSeconds = 0.11
        /// The little bounce at each change, as a share of the cat's height.
        public static let reactSquash = 0.05
        /// A slow blink every so often while it waits.
        public static let slowBlinkSeconds = 5.0 ... 9.0
        /// How many changes Undo can take back.
        public static let undoDepth = 40
        /// The option pictures' height in pixels (drawn from the cat in each option, kept this small).
        public static let thumbnailPixels = 220.0
        /// The creator is laid out for a landscape phone of this size (points) and scaled up to fill bigger
        /// screens, in steps of 0.05, to `largestScale`; upright, for a screen this wide.
        public static let designWidth = 800.0
        public static let designHeight = 402.0
        public static let designUprightWidth = 620.0
        public static let largestScale = 1.6
    }

    /// Personality sliders: affection, energy, mischief, independence (0–1).
    public enum Personality {
        public static let aloof = [0.3, 0.4, 0.3, 0.9]
        public static let velcro = [0.95, 0.6, 0.2, 0.1]
        public static let gremlin = [0.5, 0.9, 0.95, 0.6]
        public static let loaf = [0.6, 0.15, 0.2, 0.5]
        /// Multiplier on a personality's favourite activities in the behaviour table.
        public static let favouriteMultiplier = 2
    }

    /// Behaviour-table weights (higher = more likely).
    public enum Behaviour {
        public static let bowlNag = 100
        public static let sulk = 100
        public static let windowWatchInWeather = 40
        public static let sunbeam = 30
        public static let zoomiesGremlin = 30
        public static let zoomiesOther = 5
        public static let nearPlayerVelcro = 30
        public static let nearPlayerOther = 10
        public static let scheduleFavourite = 25
        public static let scheduleSecond = 15
        public static let background = 5
        /// A wander about the room (or next door): a lively cat (energy 0.6 and up) does it more.
        public static let explore = 8
        public static let exploreLively = 16
    }

    /// The arrival (SPEC "The session loop").
    public enum Arrival {
        public static let exteriorAfterMinutesAway = 60
        public static let exteriorAutoAdvanceSeconds = 2.5
        public static let doorSeconds = 1.2
        public static let greetingMaxSeconds = 3.0
        /// From this trust tier the cat is visible in the window.
        public static let catInWindowFromTier = 3
        /// The room choreography (ASSETS.md "Arrival in the room view"), in seconds and room units.
        public static let noticeDelay = 0.7
        public static let noticeHold = 0.35
        /// The cat comes to the front of its room (cells; u+v near 20 is the corner nearest you) and rubs along it
        /// from left to right while the camera leans in (Tuning.Camera.closeUp), for this long.
        public static let rubFrom = [7.7, 9.6]
        public static let rubTo = [9.6, 7.7]
        public static let greetCloseUpSeconds = 6.0
        /// A Gremlin crouches in ambush this long before it dashes out; a glance up at you holds this long.
        public static let ambushWait = 1.4
        public static let glanceHold = 1.8
        /// Walking off after the rub is a little brisker than an ordinary walk.
        public static let walkOffPace = 1.4
        /// A cat that comes to greet you is waiting on the sofa this often (Josh: it jumps off to come to you).
        public static let onSofaPercent = 55
    }

    /// The cat puppet and how it moves (STYLE.md, ASSETS.md §7). Speeds in room units a second.
    public enum Puppet {
        public static let walkSpeed = 170.0
        public static let runSpeed = 330.0
        public static let rubSpeed = 150.0
        /// Strides a second.
        public static let walkHz = 1.6
        public static let runHz = 3.2
        /// A run swings the legs wider than a walk.
        public static let runSwing = 1.4
        /// Body bob as a fraction of the cat's height.
        public static let walkBob = 0.015
        public static let runBob = 0.03
        /// In the front view legs lift instead of swinging, by this fraction of a leg.
        public static let frontLegLift = 0.08
        /// Jointed legs (CatLimb, Josh 19 Oct): the share of a stride each paw is in the air, how high it lifts and how
        /// much lower the body goes (shares of the cat's height) for a walk, a trot and a run; the rest of the stride
        /// the paw is planted, sliding back under the body as fast as the cat goes forward.
        public static let walkSwing = 0.38
        public static let walkLift = 0.07
        public static let walkCrouch = 0.03
        public static let trotSwing = 0.45
        public static let trotLift = 0.09
        public static let runSwingShare = 0.5
        public static let runLift = 0.12
        public static let runCrouch = 0.04
        /// How much of the floor's slant a paw's path keeps (1: all of it), and the stride coming at a slant (a share
        /// of the side view's).
        public static let pathRise = 0.45
        public static let slantStride = 0.75
        /// The far legs, behind the body, this much darker.
        public static let farLegShade = 0.18
        /// A hind paw (degrees, the heel up): how far it rolls onto its toes as it leaves the floor, over the last
        /// `pawRollShare` of its time there; how far it hangs toes down in the air; and how far its toes tip up
        /// reaching to land. Kept small (Josh, 19 Oct: a front paw folding back at the wrist looked very unnatural;
        /// a front leg is now one piece).
        public static let hindPawRoll = 12.0
        public static let hindPawFold = 18.0
        public static let pawReach = 4.0
        public static let pawRollShare = 0.25
        /// A front leg is one straight piece from the shoulder to the paw: when its paw is further off than the leg
        /// is long, it comes down out of the body by up to this share of its length (the rest of the way, the paw
        /// falls short).
        public static let shoulderDrop = 0.03
        /// A hind leg is jointed at its hock when the painting's hock juts back at least this share of the leg's
        /// length off the line from hip to ankle; and lifting, its hip rides up into the body by this share of the
        /// paw's lift (the knee and hip bending, hidden in the body).
        public static let hockBend = 0.06
        public static let hipRaise = 0.8
        /// How far (degrees) a hind leg's hock folds, at the top of its swing, bringing the paw forward under it.
        public static let hockFold = 30.0
        /// The bodies whose side head is a true profile, which take the profile ears in the side view; the others
        /// keep the cupped ears (the long-haired chunky body's side head looks round at you). A side head painted with
        /// its own ear takes no ear parts over it.
        public static let profileEarBodies: Set<String> = ["short_slim", "short_chunky", "siamese", "sphynx"]
        public static let sideHeadsWithEars: Set<String> = ["long_slim"]
        /// Settling into a painted pose, getting up from one and turning between views (one drawing at a time: the
        /// new one takes over at once, under a squash).
        public static let settleSeconds = 0.35
        public static let riseSeconds = 0.25
        public static let turnSeconds = 0.18
        public static let minMoveSeconds = 0.25
        public static let hopSeconds = 0.3
        public static let hopHeight = 18.0
        /// The cat fades out at the stairs and in on the other storey.
        public static let stairsFadeSeconds = 0.35
        /// Reaction icons over the cat (room units, seconds), and how far round the cat a tap still counts.
        public static let reactionWidth = 60.0
        public static let reactionRise = 70.0
        public static let reactionSeconds = 1.4
        public static let tapPadding = 20.0
        /// Settled this long, the cat picks its next activity from the behaviour table.
        public static let idleSeconds = 25.0
        /// Where the cat sits on furniture, as a fraction of the sprite's height.
        public static let seatHeight = 0.32
        public static let perchHeight = 0.9
        /// Where the cat waits beside furniture it uses from the floor, in cells past its footprint.
        public static let besideGap = 0.4
        public static let besideForward = 0.3
        /// Paces between walk and run (room units a second): an amble about the room and a trot to somewhere it wants.
        public static let strollSpeed = 120.0
        public static let trotSpeed = 250.0
        /// Zoomies are faster than a run.
        public static let dashSpeed = 430.0
        /// One stride covers this many cat heights, by gait, so the feet keep pace with the floor.
        public static let walkStride = 0.62
        public static let trotStride = 0.85
        public static let runStride = 0.95
        /// Getting up to speed and slowing down, at most (seconds).
        public static let accelerateSeconds = 0.28
        public static let slowSeconds = 0.34
        /// A gallop rocks the body this far (degrees) and the tail streams back this far.
        public static let gallopPitch = 3.5
        public static let runTailDrop = 22.0
        /// Before a move the other way, the cat turns through its three-quarter view.
        public static let pivotSeconds = 0.16
        /// Turning to another view, the new one starts this narrow and widens to full over `turnSeconds`.
        public static let turnSquash = 0.82
        /// Sitting down: the puppet lowers this much (share of its height) before the painting takes over.
        public static let sitDownDip = 0.06
        public static let sitDownSeconds = 0.14
        /// A jump: crouch, arc, land (seconds), and how far above the higher end it rises (share of the cat's height).
        public static let crouchSeconds = 0.13
        public static let jumpSeconds = 0.34
        public static let landSeconds = 0.12
        public static let jumpArc = 0.32
        /// Squash at the crouch and the landing (share of height).
        public static let squash = 0.08
        /// Breathing at rest: a share of the cat's height and breaths a second, asleep, loafing, sitting, standing.
        public static let breathSleep = [0.022, 0.2]
        public static let breathLoaf = [0.014, 0.26]
        public static let breathSit = [0.01, 0.3]
        public static let breathStand = [0.008, 0.32]
        /// Blinks: every so often (seconds, the shortest and longest gap), how long the eyes stay shut, and a slow
        /// blink (a cat's "I trust you") when stroked or sitting near you.
        public static let blinkGap = [2.2, 6.5]
        public static let blinkSeconds = 0.13
        public static let slowBlinkSeconds = 0.75
        /// Chance a blink is a double one (percent).
        public static let doubleBlinkPercent = 18
        /// Standing still: the tail sways this far (degrees) this often, the head looks about, an ear twitches.
        public static let idleTailSway = 7.0
        public static let idleTailHz = 0.35
        public static let idleHeadTurn = 5.0
        public static let earTwitch = 14.0
        public static let earTwitchGap = [3.0, 9.0]
        /// The soft shadow under the cat (share of its width and alpha).
        public static let shadowWidth = 0.62
        public static let shadowAlpha = 0.2
        /// Changing from one painting to another (a glance) cross-fades over this long.
        public static let glanceFadeSeconds = 0.28
        /// The cat jumps onto furniture from this far (cells) in front of it.
        public static let jumpFrom = 0.75
        /// Waking from a sleep, it stretches this long before it gets up.
        public static let stretchSeconds = 1.1
        /// A batted or scratched piece rocks this far (degrees).
        public static let wobbleDegrees = 3.5
        /// Scratching a post: up on its hind legs over this long, tipped up this far, the front legs reaching up the
        /// post and raking it this far either way, this many strokes a second; the head stays this much nearer level.
        public static let scratchRiseSeconds = 0.3
        public static let scratchRearDegrees = 52.0
        public static let scratchReachDegrees = 74.0
        public static let scratchRakeDegrees = 16.0
        public static let scratchHz = 2.4
        public static let scratchHeadLevel = 0.55
        /// How long a go at the post lasts, and how far from the post's middle it stands (shares of its height).
        public static let scratchSeconds = 3.2
        public static let scratchStandOff = 0.55
        /// How long the cat keeps at an activity once there (seconds, shortest and longest), by activity; others
        /// take `idleSeconds`.
        public static let hold: [String: [Double]] = [
            "sleep": [70, 160], "sunbeamLoaf": [35, 80], "floorLoaf": [25, 50], "sit": [18, 40], "perch": [20, 45],
            "hide": [22, 50], "windowWatch": [25, 55], "nearPlayer": [14, 28], "bowlNag": [15, 30], "sulk": [30, 60],
            "scratch": [4, 8], "zoomies": [6, 12], "knockOff": [8, 16],
        ]
        /// While settled, a fidget (a glance, a slow blink) every this many seconds.
        public static let fidgetGap = [7.0, 15.0]
        /// A wander stops at this many spots (fewest, most), pausing this long at each (seconds).
        public static let exploreStops = [2, 3]
        public static let explorePause = [0.8, 2.0]
    }

    /// The code-drawn sky over the exterior and the grade on the painted scene (SPEC "World map,
    /// search and seasons": the sky, sun, moon and grading are code). Colours are linear RGB 0–1.
    public enum Sky {
        public static let dawnStartMinutes = 5 * 60
        public static let dayStartMinutes = 8 * 60
        public static let duskStartMinutes = 18 * 60
        public static let nightStartMinutes = 20 * 60 + 30
        /// Top and bottom of the sky gradient.
        public static let top: [SkyPhase: [Double]] = [
            .dawn: [0.47, 0.55, 0.78], .day: [0.36, 0.6, 0.9], .dusk: [0.36, 0.33, 0.6], .night: [0.06, 0.08, 0.2],
        ]
        public static let bottom: [SkyPhase: [Double]] = [
            .dawn: [0.98, 0.78, 0.66], .day: [0.8, 0.89, 0.97], .dusk: [0.98, 0.62, 0.45], .night: [0.18, 0.2, 0.38],
        ]
        /// Multiplies the noon painting.
        public static let grade: [SkyPhase: [Double]] = [
            .dawn: [0.98, 0.9, 0.86], .day: [1, 1, 1], .dusk: [0.95, 0.78, 0.7], .night: [0.36, 0.4, 0.62],
        ]
        /// Lit windows: how strongly the glass glows warm (0 by day).
        public static let windowGlow: [SkyPhase: Double] = [.dawn: 0.35, .day: 0, .dusk: 0.6, .night: 1]
        public static let glassByDay = [0.62, 0.76, 0.86]
        public static let glassLit = [1.0, 0.8, 0.5]
        /// By day, how far the painted glass is cooled towards the sky's colour (0 keeps the painting's glass).
        public static let glassCool = 0.25
        /// The step (a share of the painting's height) for finding how far down its pane a pixel of glass is.
        public static let glassStep = 0.0033
        /// After dark, the lamplight spilling round the windows: its blur (painting pixels) and strength.
        public static let haloBlur = 18.0
        public static let haloAlpha = 0.55
    }

    /// How the exterior painting is framed: it covers the view, except that the house's band in the
    /// middle of the painting (this share of its width and height) is never cropped.
    public enum Exterior {
        public static let focusWidth = 0.42
        public static let focusHeight = 0.8
        /// How far the camera pushes into the door, and when the room starts to fade in.
        public static let pushScale = 3.2
        public static let roomFadeAt = 0.65
        public static let roomFadeSeconds = 0.5
        public static let doorOpenSeconds = 0.3
        /// The room is built this long after the exterior appears, so the first frame is not held up.
        public static let roomBuildDelay = 0.4
        /// The painting is drawn larger than its pixels on a big screen (1.8 times on a 13-inch iPad, 2.4 upright;
        /// 1.4 on a wide phone): past `sharpenFrom` times, it is sharpened this much (contrast-adaptive, 0–1) so
        /// its edges stay crisp. The full-size masters would cost 33 MB more (Josh, 19 Oct: the iPad looked soft).
        public static let sharpenFrom = 1.2
        public static let sharpen = 0.6
    }

    /// The house view: the room you are in with the rest of the home around it (room units unless noted).
    /// The scenery round the house (OutdoorRules): how far out it goes (cells past the plot), how far it keeps
    /// from the rooms, how many pieces at most from how many tries, how far apart (in widths) and how much each
    /// piece's size varies.
    public enum Outdoors {
        public static let reach = 14.0
        public static let margin = 1.5
        public static let sizeVariation = 0.12
        /// The garden's plan (OutdoorPlan, Josh 19 Oct: not at random): the tree lines this far behind the house
        /// (cells, one line each) with trees this far apart; the front border this far out, its plants this far
        /// apart with a gap this wide for the gate; each spot moved up to this far either way, home to home.
        public static let treeRows = [3.2, 6.6]
        public static let treeSpacing = 3.4
        public static let borderDistance = 2.6
        public static let borderSpacing = 1.7
        public static let gateWidth = 3.4
        public static let planJitter = 0.35
        /// A soft shadow under each piece: how dark, and how wide against the piece (a tree's round its trunk,
        /// not its whole crown).
        public static let shadowAlpha = 0.2
        public static let shadowWidth = 0.8
        public static let shadowWidthTall = 0.5
        /// Where a piece's base sits up its picture (the trunk's foot is a little above the bottom edge).
        public static let baseLift = 0.04
        /// The outside moves (Josh, 19 Oct): the wind's strength by weather, and how far a crown sways at the top
        /// of its picture at strength 1 (a share of its width).
        public static let windCalm = 0.5
        public static let windRain = 1.0
        public static let windGusty = 1.6
        public static let windStorm = 2.2
        public static let swayReach = 0.012
        /// Leaves and petals: how many a second from a tree 300 units wide, how fast they fall (units a second),
        /// how big, and how far the wind carries them (units a second squared at strength 1).
        public static let fallRate = 0.5
        public static let fallSpeed = 55.0
        public static let fallSize = 22.0
        public static let fallDrift = 10.0
        /// Cloud shadows on a fine day: how many, how wide (cells), how dark, how fast (cells a second at strength 1).
        public static let cloudShadows = 3
        public static let cloudShadowCells = 16.0
        public static let cloudShadowAlpha = 0.13
        public static let cloudShadowSpeed = 0.6
        /// A few birds fly over about this often by day (seconds, give or take most of it), taking this long to cross.
        public static let birdsEvery = 18.0
        public static let birdSeconds = 7.0
        /// A city's street: the road's asphalt, its stone kerbs (cells wide) and its painted line; a car along it
        /// about this often (seconds, give or take as much again), this long (cells), this fast (cells a second).
        public static let roadColor = [0.42, 0.41, 0.46]
        public static let kerbColor = [0.8, 0.77, 0.72]
        public static let kerbWidth = 0.22
        public static let lineColor = [0.96, 0.94, 0.88]
        public static let trafficEvery = 7.0
        public static let carCells = 1.9
        public static let carSpeed = 2.6
    }

    /// Outfits fitted to the cat (HouseCatGame OutfitFit), from the head's own outline in each sprite: a hat's
    /// rim this far from the eye line up to the crown (a little further on tall ears) and this wide against the
    /// head; glasses' lenses this far apart against the eyes, a profile's lens this wide against the head;
    /// neckwear's band this wide against the neck, its anchor this far down the band; the chin this many eye
    /// spans below the nose (a profile's, against the head's width); a head seen
    /// from behind this far down the sprite; how deep an outfit's top and bottom edges are measured; the smallest
    /// hole that counts as a lens (in half-pixel cells).
    public enum Outfits {
        public static let hatRise = 0.62
        public static let tallEarsLift = 0.15
        public static let tallEars: Set<String> = ["siamese", "sphynx", "mainecoon", "oriental", "tufted"]
        public static let hatWidth = 1.15
        /// The tallest a hat's picture may be, in eye-line-to-crown heights (the others reach about 3, antlers 4).
        public static let hatMaxHeight = 4.3
        /// A hat painted this many times taller than wide is a headband seen side-on (the antlers): its height in
        /// eye-line-to-crown heights, and how far below the eye line its end comes.
        public static let bandAspect = 2.0
        public static let bandHeight = 2.5
        public static let bandDrop = 0.25
        /// A body garment on the puppet: its picture is the torso's with this much of it added on every side (the
        /// garment sheets' TORSO_PAD), drawn over the torso and under the head.
        public static let torsoPad = 0.15
        public static let torsoGarmentZ = 0.0015
        /// The longest neckwear may hang, in head widths (a scarf's tassels reach about 1.5).
        public static let neckMaxHeight = 1.7
        /// A profile's head is at most this many times the eye's distance to the front of the face long (sitting
        /// it is 5 to 6.4; lying down the row runs on into the body, 8 to 11).
        public static let profileHeadToFront = 6.0
        public static let lensFit = 1.0
        public static let profileGlassesWidth = 0.95
        /// Where a profile's lens is on its picture (the front end), and a pair's lenses in each view when the
        /// picture's own cannot be found (measured off the round glasses).
        public static let profileLens = [0.05, 0.5]
        public static let lenses: [String: [[Double]]] = [
            "front": [[0.25, 0.5], [0.75, 0.5]],
            "tqfront": [[0.15, 0.51], [0.48, 0.66]],
        ]
        /// A head no wider than this many eye spans (or eye-to-nose lengths in a profile).
        public static let headToEyes = 2.4
        public static let headToEyeNose = 3.4
        /// A profile's head middle, behind its eye by this much of the head's width; neckwear no wider than this
        /// much of the head.
        public static let profileHeadBack = 0.12
        public static let neckToHead = 0.9
        public static let neckWidth = 1.12
        public static let neckBandDrop = 0.12
        public static let chinDrop = 0.48
        /// A flat face (its nose less than this many eye spans below the eyes) has its chin at least the next
        /// many eye spans below the eyes; two eyes closer than this share of the head's width are a profile with
        /// the far eye peeking.
        public static let flatNose = 0.25
        public static let chinBelowEyes = 0.72
        public static let profileEyeSpan = 0.32
        public static let profileChinDrop = 0.55
        public static let backHeadDrop = 0.12
        /// From behind, the head's row is the first one at least this wide (of the picture), no lower than this.
        public static let backHeadMinWidth = 0.35
        public static let backHeadLowest = 0.4
        /// The edges are measured over the middle of the picture, this far in from each side.
        public static let edgeInset = 0.2
        public static let minimumLensCells = 40
        public static let minimumFeaturePixels = 4
        /// Over the head and its ears.
        public static let zLift = 0.5
    }

    public enum House {
        /// Doorways in the partitions between rooms: halfway along the wall, this many cells wide.
        public static let doorwayAlong = 5.0
        public static let doorwayWidth = 1.8
        /// After the player picks a room, the view stays on it this long before following the cat again.
        public static let roomHoldSeconds = 30.0
        /// The cat steps this far into a room through a doorway, in cells.
        public static let doorwayStep = 0.8
        /// Draw-order bands: below everything (the ground), and per room's distance from the back.
        public static let storeyBand = 200_000.0
        public static let roomBand = 5000.0
        /// Cut-down partitions, in cells, with a darker top so they read as walls seen from above.
        public static let stubHeight = 0.35
        public static let capWidth = 10.0
        public static let capColor = [0.42, 0.36, 0.33]
        /// Garden walls (hedge, fence, brick) stand this many cells high.
        public static let gardenWallHeight = 1.6
        /// A closed room is bare (Josh, 19 Oct): indoors these plain finishes, no furniture, no shading over it.
        public static let bareWall = "wall_attic_rough_plaster"
        public static let bareFloor = "floor_attic_dusty_boards"
        /// A closed room's price label.
        public static let lockFontSize = 34.0
        /// The lock badge's paper and ink (the controls' cream and plum).
        public static let lockPaper = [0.995, 0.97, 0.925]
        public static let lockInk = [0.24, 0.18, 0.22]
        /// Along the axis shared with the room you are in, the badge sits this many cells from the back.
        public static let labelBack = 2.0
        /// …and this high over the floor, in room units.
        public static let labelLift = 170.0
        /// A badge keeps at least this far (points) from the sides of the view.
        public static let badgeMargin = 12.0
        /// A badge's text is this size on screen (points) at any zoom, and the badge keeps out of the controls'
        /// bands this deep along the top and bottom of the view.
        public static let badgePoints = 15.0
        public static let badgeClearTop = 110.0
        public static let badgeClearBottom = 120.0
        /// A closed room's price label leans this many cells from its middle towards the room you are in.
        public static let labelLean = 3.0
        /// On a portrait screen the active room fills this share of the width, the house showing either side.
        public static let portraitFitWidth = 0.92
        /// The staircase runs this many cells along its wall.
        public static let stairsLength = 3.0
        /// The ground runs this many cells out from the house, past any view's edge, a little darker than a room floor.
        public static let groundReach = 40.0
        public static let groundShade = 0.82
        /// A touch that travels less than this (points) is a tap, not a pan.
        public static let tapSlop = 12.0
        /// How long a drag stops the view settling back on the room (the middle of the view stays over the house).
        public static let panHoldSeconds = 4.0
    }

    /// Decorating: picking up, dragging and dropping furniture.
    public enum Decorate {
        public static let liftScale = 1.06
        public static let liftSeconds = 0.12
        /// A piece being dragged draws over its neighbours.
        public static let liftZ = 50.0
        public static let fitColor = [0.35, 0.8, 0.45]
        public static let blockedColor = [0.92, 0.32, 0.3]
        public static let footprintAlpha = 0.4
        /// The ring round a picked-up piece's base (Josh, 18 Oct; Tolan's placement ring): how far it reaches past
        /// the footprint, how much it swells and how fast it breathes.
        public static let ringReach = 0.18
        public static let ringPulse = 1.07
        public static let ringSeconds = 0.7
        /// A room look tried in the room: how see-through its pieces are.
        public static let previewAlpha = 0.72
        public static let gridAlpha = 0.35
        public static let flashSeconds = 0.6
    }

    /// Sound: volumes 0–1 and how long the rub's purr lasts.
    public enum Sound {
        public static let door = 0.7
        public static let meow = 0.8
        public static let purr = 0.6
        public static let purrSeconds = 3.0
        public static let ambience = 0.25
        public static let fire = 0.3
        public static let place = 0.6
        public static let gift = 0.7
        public static let levelUp = 0.7
        public static let tap = 0.35
        /// The intro's tour: the soft meow as each home comes into view.
        public static let introMeow = 0.3
        /// Rain, wind and snow under everything; a storm louder.
        public static let weather = 0.3
        public static let storm = 0.45
        public static let fadeSeconds = 0.8
        /// The background music (Josh, 19 Oct: "quiet cute background music"): about as loud as the dawn birds, the
        /// player's Settings level a share of it, and the slow fade it comes in and goes out with.
        public static let music = 0.35
        public static let musicFadeSeconds = 2.5
    }

    /// How a room is framed on screen.
    /// The room view's camera (Josh, 19 Oct: the cat looked tiny, then swelled up as it came to you). Zooms are
    /// multiples of the whole active room filling the view; the view follows the cat when the room is bigger
    /// than the screen, and leans in for a moment when you greet, stroke or feed the cat.
    public enum Camera {
        /// Where a visit starts: on the cat, about a quarter of the screen's height (Josh, 19 Oct: the cat is the
        /// product; the whole room shows only to decorate). A phone's screen is small, so closer than an iPad's.
        public static let homeZoomPhone = 2.7
        public static let homeZoomPad = 2.1
        /// A pinch goes from the house around the room to a close look at the cat.
        public static let minZoom = 0.6
        public static let maxZoom = 4.5
        /// The close look: this much closer than the zoom you are at, for this long after the last stroke or meal.
        public static let closeUp = 1.35
        public static let closeUpSeconds = 5.0
        /// How quickly the zoom eases to where it is going (per second).
        public static let zoomRate = 2.2
        /// The view keeps the cat this far (a share of the view) from its middle before it moves with it.
        public static let followSlack = 0.12
    }

    public enum Stage {
        /// On an iPad the room's controls and its cards are drawn larger, as a whole, by how much bigger the window is
        /// than this (points; the widest cards need the width), in steps of 0.05 to `hudLargestScale` (the shop's):
        /// 1.6 on a 13-inch iPad on its side, 1.4 held upright. A phone keeps scale 1.
        public static let hudDesignWidth = 720.0
        public static let hudDesignHeight = 500.0
        public static let hudLargestScale = 1.6
        /// A sheet over the room on an iPad (the profile, the settings, the book): this size (points) at the
        /// controls' scale, kept `sheetMargin` inside the window.
        public static let sheetWidth = 700.0
        public static let sheetHeight = 500.0
        public static let sheetMargin = 40.0
        /// The room sits this far above the bottom of the screen (points), clear of the room switcher (the
        /// controls are in the corners, over the room, as a builder game's are).
        public static let careBarInset = 34.0
        /// The controls keep this far from the screen's sides, top and bottom (points): clear of the rounded
        /// corners, inside where the safe area would put them (Josh, 19 Oct: use the screen, as Clash of Clans does).
        public static let hudEdge = 22.0
        public static let hudTop = 10.0
        public static let hudBottom = 8.0
        /// The room slides up over this long when the decorate tray opens.
        public static let insetSeconds = 0.25
        /// The share of the view the room may fill.
        public static let fitWidth = 0.96
        public static let fitHeight = 0.8
        /// Wall items without a height hang this many cells up.
        public static let wallItemHeight = 2.5
        /// On a tall screen the room is zoomed in past its width and the view follows the cat.
        public static let portraitZoom = 1.8
        /// Only screens taller than this (height over width) zoom: phones, not an iPad in portrait.
        public static let portraitZoomAspect = 1.6
        /// How quickly the view catches up with the cat (per second).
        public static let followRate = 2.5
        /// Behind the room, graded with the sky.
        public static let roomBackground = [0.93, 0.91, 0.95]
        /// The next room glimpsed through the door, in shadow.
        public static let doorwayShadow = [0.45, 0.39, 0.5]
        /// Fire drawn a little wider than the opening it sits in, ten frames a second.
        public static let fireWidth = 1.3
        public static let fxFrameSeconds = 0.1
    }

    /// Widgets (SPEC "Widgets, the Duolingo layer").
    /// Local reminders (SPEC "Notifications"), at the player's own times; these are the defaults.
    public enum Reminders {
        public static let breakfastMinutes = 7 * 60 + 30
        public static let eveningMinutes = 19 * 60 + 30
        /// How far ahead they are scheduled (iOS keeps at most 64 pending).
        public static let daysAhead = 7
    }

    public enum Widget {
        public static let entryIntervalMinutes = 30
        public static let entriesPerTimeline = 48
        /// Before a visit: by the door until noon, at the window until 20:00, then "still waiting".
        public static let waitingAtWindowFromMinutes = 12 * 60
        public static let stillWaitingFromMinutes = 20 * 60
        /// After a visit: content for an hour, then loaf, box, sofa, zoomies, asleep.
        public static let contentMinutesAfterVisit = 60
        public static let loafFromMinutes = 10 * 60
        public static let boxFromMinutes = 14 * 60
        public static let sofaFromMinutes = 18 * 60
        public static let zoomiesFromMinutes = 22 * 60
        /// The picture (CLAUDE.md "The widget scene"): a sitting cat this tall as a fraction of the widget,
        /// its feet this far below the glass, the wide window's cat this far across its glass.
        public static let catHeight = 0.5
        public static let catHeightWide = 0.62
        /// The peeking head (the evening's last chance, the Lock Screen circle): the sitting-front picture this
        /// wide for the space, its top this much shown above the bottom edge.
        public static let peekWidth = 1.05
        public static let peekWidthCircular = 0.86
        public static let peekCrop = 0.5
        public static let peekCropCircular = 0.3
        /// The add-widget card's second ask comes on this day of care (the first follows the first feed).
        public static let promptCareDay = 3
        /// Where the cat's feet go on each window (set by eye from the paintings): the sill's top as a fraction of
        /// the frame's height, square then wide.
        public static let sill: [String: [Double]] = [
            "arched": [0.77, 0.78],
            "bay": [0.69, 0.67],
            "cabin": [0.755, 0.745],
            "casement": [0.755, 0.76],
            "picture": [0.745, 0.76],
            "porthole": [0.735, 0.715],
            "sash": [0.765, 0.765],
            "shuttered": [0.755, 0.78],
        ]
        /// The room's light on the frame and the cat by the time of day (the frames are painted in daylight).
        public static let roomGrade: [SkyPhase: [Double]] = [
            .dawn: [0.93, 0.88, 0.9],
            .day: [1, 1, 1],
            .dusk: [0.88, 0.78, 0.76],
            .night: [0.5, 0.47, 0.62],
        ]
        public static let catXWide = 0.42
        /// The terrain behind the glass: wider than the glass by this much, its foot this far below.
        public static let terrainOverhang = 1.12
        public static let terrainDrop = 0.06
        /// The shapes of the painted wide frame and terrain (width over height).
        public static let wideFrameAspect = 2688.0 / 1520.0
        public static let terrainAspect = 672.0 / 380.0
        /// The kit the app makes: the cat's pictures this tall in pixels, and a version to remake it on change.
        public static let catPixels = 420
        public static let kitVersion = "1"
        /// The app writes the widget's snapshot this long after the last change.
        public static let publishDelaySeconds = 1.0
    }

    // Weather (CLAUDE.md "Weather").

    /// The save (CLAUDE.md "Architecture rules").
    public enum Save {
        /// Events older than this are folded into the snapshot.
        public static let compactionHorizonDays = 30
        /// The shape of `HouseholdState` in a stored snapshot. Bump it whenever the state gains, loses or
        /// changes a field: an older snapshot is then ignored and the state refolded from the events, which
        /// are always kept (the snapshot is only a cache).
        public static let snapshotVersion = 10
    }

    /// The stray (SPEC "The stray").
    public enum Stray {
        public static let cadenceDays = 30
        public static let cadenceDaysWithManyCats = 7
        public static let manyCats = 3
    }

    /// Social (SPEC "Groups").
    public enum Social {
        public static let groupMaxMembers = 12
        public static let inviteExpiryHours = 48
        public static let sittingMaxDays = 14
    }
}
