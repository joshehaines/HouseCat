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
        /// Where the cat sits on furniture, as a fraction of the sprite's height.
        public static let seatHeight = 0.32
        public static let perchHeight = 0.9
        /// Where the cat waits beside furniture it uses from the floor, in cells past its footprint.
        public static let besideGap = 0.4
        public static let besideForward = 0.3
        /// Scaled past this, the cat is at the camera and draws over everything.
        public static let nearCameraScale = 1.2
    }

    /// How a room is framed on screen.
    public enum Stage {
        /// The share of the view the room may fill.
        public static let fitWidth = 0.96
        public static let fitHeight = 0.9
        /// Wall items without a height hang this many cells up.
        public static let wallItemHeight = 2.5
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
