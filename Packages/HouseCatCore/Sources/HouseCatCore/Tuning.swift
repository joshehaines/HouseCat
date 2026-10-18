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
    }

    /// Cumulative XP to reach each level (SPEC "XP and levels").
    public enum Levels {
        /// Index 0 is level 1, index 11 is level 12.
        public static let thresholds = [0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700, 3250, 3850]
        public static let xpPerLevelAfterTable = 650
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
        /// After a missed day: sulky on the first return visit, thawing on the second, fine from the third.
        public static let warmUpArrivals = 3
        /// A miss this long or longer gets the "week plus" greeting.
        public static let weekMissDays = 7
    }

    /// Beans: earned only, never sold, never expire (SPEC "Economy").
    public enum Beans {
        public static let housewarmingAllowance = 150
        public static let dailyArrival = 10
        public static let levelUp = 100
        /// Cat Club: +20% on everything earned that day.
        public static let clubBonusPercent = 20
        public static let moveHome = 500
        public static let freeHomeMoves = 1
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
        /// Pets closer together than this count as in a row.
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
        /// A picked coat or pattern colour's luminance (0–255) is held inside this range.
        public static let pickerMinLuminance = 40.0
        public static let pickerMaxLuminance = 250.0
        /// Eye size slider: the irises are drawn this much smaller or larger at its ends.
        public static let eyeSizeRange = 0.18
        /// Whisker slider at 0: the whiskers are trimmed to this fraction of their painted reach.
        public static let shortestWhiskers = 0.35
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
        /// How much bigger the cat is at the camera than across the room.
        public static let nearScale = 2.3
        /// The rub runs left to right just above the room's front corner.
        public static let rubStartX = -150.0
        public static let rubEndX = 210.0
        public static let rubStartDrop = 20.0
        public static let rubEndDrop = 30.0
        /// Walking off after the rub is a little brisker than an ordinary walk.
        public static let walkOffPace = 1.4
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
        /// Cross-fades: into a painted pose, back to the puppet, and between views.
        public static let settleSeconds = 0.35
        public static let riseSeconds = 0.25
        public static let turnSeconds = 0.18
        /// How much of a cross-fade each side takes: the incoming picture fades in first and
        /// the outgoing one fades out under it after, so the cat is never see-through halfway.
        public static let fadeOverlap = 0.6
        public static let minMoveSeconds = 0.25
        public static let hopSeconds = 0.3
        public static let hopHeight = 18.0
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
        /// Scaled past this, the cat is at the camera and draws over everything.
        public static let nearCameraScale = 1.2
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
    }

    /// The house view: the room you are in with the rest of the home around it (room units unless noted).
    public enum House {
        /// Draw-order bands: below everything (the ground), and per room's distance from the back.
        public static let storeyBand = 200_000.0
        public static let roomBand = 5000.0
        /// Cut-down partitions, in cells, with a darker top so they read as walls seen from above.
        public static let stubHeight = 0.35
        public static let capWidth = 10.0
        public static let capColor = [0.42, 0.36, 0.33]
        /// Garden walls (hedge, fence, brick) stand this many cells high.
        public static let gardenWallHeight = 1.6
        /// A closed room's veil and its price label.
        public static let veilColor = [0.12, 0.12, 0.2]
        public static let veilAlpha = 0.55
        public static let lockFontSize = 64.0
        /// A closed room's price label leans this many cells from its middle towards the room you are in.
        public static let labelLean = 3.0
        /// On a portrait screen the active room fills this share of the width, the house showing either side.
        public static let portraitFitWidth = 0.7
        /// The staircase runs this many cells along its wall.
        public static let stairsLength = 3.0
        /// The ground runs this many cells out from the house, past any view's edge, a little darker than a room floor.
        public static let groundReach = 40.0
        public static let groundShade = 0.82
        /// A touch that travels less than this (points) is a tap, not a pan.
        public static let tapSlop = 12.0
        /// How far the view may pan past the house, and how long a drag stops it following the cat.
        public static let margin = 200.0
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
        public static let fadeSeconds = 0.8
    }

    /// How a room is framed on screen.
    public enum Stage {
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
    }

    /// Weather (CLAUDE.md "Weather").
    public enum Weather {
        public static let fetchIntervalMinutes = 60
        public static let cacheHours = 3
    }

    /// The save (CLAUDE.md "Architecture rules").
    public enum Save {
        /// Events older than this are folded into the snapshot.
        public static let compactionHorizonDays = 30
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
