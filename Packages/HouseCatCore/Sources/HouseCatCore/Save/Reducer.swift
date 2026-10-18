import Foundation

/// The fold from events to `HouseholdState`. Events are applied in log order;
/// days are closed as time moves past them, which is where misses, pauses and
/// the Cat Club bonus settle. Invalid events (spending Beans that are not
/// there, claiming a tier not reached) are ignored, never trusted.
extension HouseholdState {
    /// Applies one event. Events must arrive in log order.
    public mutating func apply(_ event: GameEvent, context: RulesContext) {
        if case let .householdCreated(seed, clock) = event.kind, createdOn == nil {
            self.seed = seed
            self.clock = clock
            createdOn = event.day
            beansGranted += Tuning.Beans.housewarmingAllowance
        }
        // A day already closed cannot reopen; late events land on the open day.
        let day = max(event.day, today?.day ?? event.day)
        advance(to: day, context: context)
        lastEventAt = max(lastEventAt ?? event.at, event.at)

        switch event.kind {
        case .householdCreated, .clockChanged, .catAdopted, .catRenamed, .personalityChanged, .catLookSet:
            applyHousehold(event, day: day)
        case .arrived, .fed, .petted, .miniGamePlayed, .giftCollected, .giftSold, .napCompleted, .healthGoalMet, .windowTapped:
            applyCare(event, context: context)
        case .itemBought, .itemGranted, .purchaseBeansGranted, .itemPlaced, .itemMoved, .itemStored, .catUsedNewItem, .roomOpened,
             .roomVisited,
             .surfaceChanged, .outfitWorn, .homeMoved, .seasonModeChanged, .homePlaced, .seasonSet, .homeStyleChosen, .tourFinished:
            applyHome(event, context: context)
        case .pauseStarted, .pauseEnded, .passPurchased, .passTierClaimed, .clubDayRecorded:
            applyStreakAndPass(event, day: day, context: context)
        case .sundayCardShared, .pawPrintSent, .groupJoined, .giftSent, .satForFriend:
            applySocial(event, context: context)
        }

        checkAchievements(on: day, context: context)
    }

    /// Closes every day before `day` and opens `day`. Days with no events are
    /// closed too, which is where a missed day is counted.
    public mutating func advance(to day: GameDay, context: RulesContext) {
        guard let open = today else {
            openDay(day, previousMissed: false, context: context)
            return
        }
        guard day > open.day else { return }
        var current = open.day
        while current < day {
            let missed = closeToday()
            current = current.advanced(by: 1)
            openDay(current, previousMissed: missed, context: context)
        }
    }

    /// A copy with every day before `day` closed: what the app and widget read
    /// for "now".
    public func resolved(through day: GameDay, context: RulesContext) -> HouseholdState {
        var copy = self
        copy.advance(to: day, context: context)
        return copy
    }

    // MARK: Event handlers

    /// The household, its clock and its cats.
    private mutating func applyHousehold(_ event: GameEvent, day: GameDay) {
        switch event.kind {
        case .householdCreated:
            break
        case let .clockChanged(newClock):
            clock = newClock
        case let .catAdopted(catID, name, personality, isKitten):
            guard cat(catID) == nil else { break }
            cats.append(CatState(
                id: catID,
                name: String(name.prefix(Tuning.Cat.nameMaxLength)),
                personality: personality,
                adoptedOn: day,
                isKitten: isKitten
            ))
            lifetime.catsAdopted += 1
        case let .catRenamed(catID, name):
            updateCat(catID) { $0.name = String(name.prefix(Tuning.Cat.nameMaxLength)) }
        case let .personalityChanged(catID, personality):
            updateCat(catID) { $0.personality = personality }
        case let .catLookSet(catID, look):
            updateCat(catID) {
                $0.look = look
                $0.isKitten = look.age.isKitten
            }
        default:
            break
        }
    }

    /// Visits and care: arriving, feeding, petting, play, gifts, naps and health.
    private mutating func applyCare(_ event: GameEvent, context: RulesContext) {
        switch event.kind {
        case .arrived:
            recordVisit(event, context: context)
            warmUpArrivals = min(Tuning.Streak.warmUpArrivals, warmUpArrivals + 1)
            if today?.arrived == false {
                today?.arrived = true
                gainXP(Tuning.XP.arrival)
                earn(Tuning.Beans.dailyArrival)
            }
        case let .fed(catID):
            feed(catID, event: event, context: context)
        case let .petted(catID):
            guard cat(catID) != nil else { break }
            recordVisit(event, context: context)
            let index = today?.pets ?? 0
            today?.pets += 1
            if index < Tuning.XP.pets.count {
                gainXP(Tuning.XP.pets[index])
            }
            lifetime.pets += 1
            bump(.pet, context: context)
        case let .miniGamePlayed(_, stars):
            playMiniGame(stars: stars, context: context)
        case let .giftCollected(catID, giftID, _):
            guard let index = pendingGifts.firstIndex(where: {
                $0.catID == catID && $0.giftID == giftID && $0.dropAt <= event.at
            }) else { break }
            let gift = pendingGifts.remove(at: index)
            earn(gift.rarity.collectBeans)
            gainXP(Tuning.XP.giftCollected)
            giftsCollected[giftID, default: 0] += 1
            lifetime.gifts += 1
            if gift.rarity == .legendary {
                lifetime.legendaryGifts += 1
            }
            bump(.findGift, context: context)
        case let .giftSold(giftID, rarity):
            guard giftsCollected[giftID, default: 0] >= 2 else { break }
            giftsCollected[giftID, default: 0] -= 1
            let known = context.gifts.first { $0.id == giftID }?.rarity ?? rarity
            earn(known.sellBackBeans)
        case .napCompleted:
            guard today?.napped == false else { break }
            today?.napped = true
            gainXP(Tuning.XP.nap)
            lifetime.naps += 1
            bump(.nap, context: context)
        case let .healthGoalMet(goal):
            guard today?.healthGoals.contains(goal) == false else { break }
            today?.healthGoals.insert(goal)
            switch goal {
            case .steps: gainXP(Tuning.XP.stepsGoalMet)
            case .sleep: gainXP(Tuning.XP.sleepGoalMet)
            case .workout: gainXP(Tuning.XP.workoutLogged)
            }
        case .windowTapped:
            bump(.tapWindow, context: context)
        default:
            break
        }
    }

    /// Buying, placing and using furniture; rooms, surfaces, outfits and moving home.
    private mutating func applyHome(_ event: GameEvent, context: RulesContext) {
        switch event.kind {
        case let .itemBought(itemID, price):
            guard price >= 0, beans >= price else { break }
            beansSpent += price
            owned[itemID, default: 0] += 1
            bump(.buyItemBeans, context: context)
        case let .itemGranted(itemID):
            owned[itemID, default: 0] += 1
        case .tourFinished:
            guard !tourRewarded else { break }
            tourRewarded = true
            beansGranted += Tuning.Beans.tourReward
        case let .purchaseBeansGranted(transactionID, amount):
            guard amount > 0, !grantedTransactions.contains(transactionID) else { break }
            grantedTransactions.insert(transactionID)
            beansGranted += amount
        case let .itemPlaced(itemID, room, x, y, facing):
            placeItem(itemID, room: room, x: x, y: y, facing: facing, event: event, context: context)
        case let .itemMoved(placementID, room, x, y, facing):
            guard openedRooms.contains(room), Self.inBounds(x, y),
                  let index = placed.firstIndex(where: { $0.placementID == placementID }) else { break }
            placed[index].room = room
            placed[index].x = x
            placed[index].y = y
            placed[index].facing = facing
            bump(.placeItem, context: context)
        case let .itemStored(placementID):
            placed.removeAll { $0.placementID == placementID }
        case let .catUsedNewItem(_, itemID):
            guard placedCount(of: itemID) > 0, !lifetime.usedItems.contains(itemID) else { break }
            lifetime.usedItems.insert(itemID)
            let headroom = Tuning.XP.catUsedNewFurnitureMaxPerDay - (today?.newFurnitureXP ?? 0)
            let gain = min(Tuning.XP.catUsedNewFurniture, headroom)
            if gain > 0 {
                today?.newFurnitureXP += gain
                gainXP(gain)
            }
        case let .roomOpened(room, price):
            let cost = RoomRules.cost(of: room, clubActive: today?.clubDay ?? false)
            guard !openedRooms.contains(room), level >= room.requiredLevel, price >= cost, beans >= price else { break }
            openedRooms.insert(room)
            beansSpent += price
            bump(.openRoom, context: context)
        case let .roomVisited(room):
            if openedRooms.contains(room) {
                lifetime.roomsVisited.insert(room)
            }
        case let .surfaceChanged(room, surfaceID):
            // Surface ids name their kind (Content: wall_… and floor_…), so a floor never replaces a wallpaper.
            if Self.isFloor(surfaceID) {
                floors[room] = surfaceID
            } else {
                wallpapers[room] = surfaceID
            }
            lifetime.surfacesChanged += 1
            bump(.changeSurface, context: context)
        case let .outfitWorn(catID, outfitID):
            guard cat(catID) != nil else { break }
            updateCat(catID) { $0.outfitID = outfitID }
            lifetime.outfitsWorn += 1
            bump(.wearOutfit, context: context)
        case let .homeMoved(price):
            let free = homeMovesUsed < Tuning.Beans.freeHomeMoves || today?.clubDay == true
            let required = free ? 0 : Tuning.Beans.moveHome
            guard price >= required, beans >= price else { break }
            beansSpent += price
            homeMovesUsed += 1
            lifetime.homeMoves += 1
            home.moving = true
        case .seasonModeChanged:
            lifetime.seasonChanges += 1
        case let .homePlaced(place):
            // The first pin is free; after that a move must have been paid for (or used the free one).
            guard home.place == nil || home.moving else { break }
            home.place = place
            home.moving = false
        case let .homeStyleChosen(style):
            // Chosen with the first pin, or while a move is under way (before the new pin lands).
            guard home.style == nil || home.moving || home.place == nil else { break }
            home.style = style
        case let .seasonSet(setting):
            guard setting != home.season else { break }
            home.season = setting
            lifetime.seasonChanges += 1
        default:
            break
        }
    }

    /// Pause mode, the season pass and Cat Club days.
    private mutating func applyStreakAndPass(_ event: GameEvent, day: GameDay, context: RulesContext) {
        switch event.kind {
        case let .pauseStarted(days):
            // Started after today's visit, the pause covers the days from tomorrow.
            let length = min(max(days, 1), Tuning.Streak.pauseDaysPerQuarter)
            let first = today?.visited == true ? day.advanced(by: 1) : day
            pause.from = first
            pause.until = first.advanced(by: length - 1)
        case .pauseEnded:
            if let from = pause.from, from < day {
                pause.until = day.advanced(by: -1)
            } else {
                pause.from = nil
                pause.until = nil
            }
        case let .passPurchased(seasonID):
            passes[seasonID, default: SeasonProgress()].purchased = true
        case let .passTierClaimed(seasonID, track, tier):
            claimTier(seasonID: seasonID, track: track, tier: tier, day: day, context: context)
        case .clubDayRecorded:
            today?.clubDay = true
        default:
            break
        }
    }

    /// Sharing and groups.
    private mutating func applySocial(_ event: GameEvent, context: RulesContext) {
        switch event.kind {
        case .sundayCardShared:
            guard today?.sundayCard == false else { break }
            today?.sundayCard = true
            addPassPoints(Tuning.Pass.sundayCard, capped: true, context: context)
            lifetime.sundayCards += 1
        case .pawPrintSent:
            lifetime.pawPrintsSent += 1
            bump(.sendPawPrint, context: context)
        case .groupJoined:
            lifetime.groupsJoined += 1
        case .giftSent:
            lifetime.giftsSent += 1
        case .satForFriend:
            guard today?.satForFriend == false else { break }
            today?.satForFriend = true
            lifetime.sittingDays += 1
        default:
            break
        }
    }

    // MARK: Days

    /// Settles the open day. Returns whether it was a missed (unpaused) day.
    private mutating func closeToday() -> Bool {
        guard let tally = today else { return false }
        var missed = false
        if let createdOn, tally.day >= createdOn, !tally.visited {
            if !pause.consume(tally.day) {
                missed = true
                _ = streak.miss(on: tally.day)
                warmUpArrivals = 0
            }
        }
        if let until = pause.until, until <= tally.day {
            pause.from = nil
            pause.until = nil
        }
        beansEarnedClosed += tally.baseBeans + tally.clubBonus
        today = nil
        return missed
    }

    private mutating func openDay(_ day: GameDay, previousMissed: Bool, context: RulesContext) {
        var tally = DayTally(day: day)
        tally.missedYesterday = previousMissed
        tally.objectives = ObjectiveRules.daily(from: context.dailyObjectives.filter(canAttempt), household: seed, day: day).map(\.id)
        today = tally
        if week?.weekStart != day.weekStart {
            week = WeekTally(
                weekStart: day.weekStart,
                objectives: ObjectiveRules.weekly(from: context.weeklyObjectives.filter(canAttempt), household: seed, day: day)
                    .map(\.id)
            )
        }
    }

    // MARK: Care

    private mutating func recordVisit(_ event: GameEvent, context: RulesContext) {
        lifetime.devicesUsed.insert(event.source)
        switch event.source {
        case .widget: bump(.widgetVisit, context: context)
        case .mac: bump(.macVisit, context: context)
        case .watch: bump(.watchVisit, context: context)
        case .app, .siri: break
        }
        guard let tally = today, !tally.visited else { return }
        today?.visited = true
        today?.firstVisitAt = event.at
        lifetime.visits += 1
        for milestone in streak.visit(on: tally.day) {
            earn(StreakState.beans(forMilestone: milestone))
        }
        addPassPoints(Tuning.Pass.visit, capped: true, context: context)
        bump(.visitDay, context: context)
    }

    private mutating func feed(_ catID: String, event: GameEvent, context: RulesContext) {
        guard let index = cats.firstIndex(where: { $0.id == catID }), let tally = today else { return }
        recordVisit(event, context: context)
        guard !tally.fedCats.contains(catID) else { return } // a second bowl: "full"
        let firstFeedToday = tally.fedCats.isEmpty
        today?.fedCats.insert(catID)
        cats[index].careDays += 1
        cats[index].lastFedDay = tally.day
        lifetime.feeds += 1
        bump(.feed, context: context)
        let minutes = clock.localMinutes(of: event.at)
        if minutes >= clock.wakeMinutes, minutes < Tuning.Day.earlyFeedBeforeMinutes {
            bump(.feedBefore9, context: context)
        }
        if firstFeedToday {
            gainXP(Tuning.XP.feed)
            addPassPoints(Tuning.Pass.feed, capped: true, context: context)
        }
        // One gift a day when fed; none the day after a missed day.
        if !tally.missedYesterday {
            pendingGifts.append(GiftRules.draw(
                household: seed,
                catID: catID,
                fedDay: tally.day,
                fedAt: event.at,
                tier: cats[index].trust,
                pool: context.gifts,
                clock: clock
            ))
        }
    }

    private mutating func playMiniGame(stars: Int, context: RulesContext) {
        guard let tally = today, tally.plays < Tuning.MiniGames.playsPerDay else { return }
        today?.plays += 1
        gainXP(Tuning.XP.play)
        let stars = min(max(stars, 0), Tuning.MiniGames.starBeans.count)
        if stars >= 1 {
            earn(Tuning.MiniGames.starBeans[stars - 1])
            lifetime.minigameWins += 1
            bump(.winMinigame, context: context)
        }
        if stars == Tuning.MiniGames.starBeans.count {
            lifetime.threeStarGames += 1
            bump(.threeStarMinigame, context: context)
        }
        addPassPoints(Tuning.Pass.miniGame, capped: true, context: context)
        bump(.playMinigame, context: context)
    }

    // MARK: Home

    static func isFloor(_ surfaceID: String) -> Bool {
        surfaceID.hasPrefix("floor_")
    }

    static func inBounds(_ x: Int, _ y: Int) -> Bool {
        (0 ..< Tuning.Room.gridWidth).contains(x) && (0 ..< Tuning.Room.gridDepth).contains(y)
    }

    private mutating func placeItem(
        _ itemID: String,
        room: RoomID,
        x: Int,
        y: Int,
        facing: GameEvent.Facing,
        event: GameEvent,
        context: RulesContext
    ) {
        let available = owned[itemID, default: 0] + (context.paidItems.contains(itemID) ? 1 : 0)
        guard openedRooms.contains(room), Self.inBounds(x, y), available > placedCount(of: itemID) else { return }
        placed.append(PlacedItem(placementID: event.id, itemID: itemID, room: room, x: x, y: y, facing: facing))
        let headroom = Tuning.XP.furniturePlacedMaxPerDay - (today?.furnitureXP ?? 0)
        let gain = min(Tuning.XP.furniturePlaced, headroom)
        if gain > 0 {
            today?.furnitureXP += gain
            gainXP(gain)
        }
        if today?.placedFurniture == false {
            today?.placedFurniture = true
            addPassPoints(Tuning.Pass.placeFurniture, capped: true, context: context)
        }
        bump(.placeItem, context: context)
    }

    // MARK: Season pass

    private mutating func claimTier(seasonID: String, track: PassTrack, tier: Int, day: GameDay, context: RulesContext) {
        guard let season = context.season(id: seasonID) else { return }
        var progress = passes[seasonID] ?? SeasonProgress()
        let ownsPaid = progress.purchased || today?.clubDay == true
        guard PassRules.canClaim(track: track, tier: tier, progress: progress, season: season, day: day, ownsPaidTrack: ownsPaid)
        else { return }
        switch track {
        case .free: progress.claimedFree.insert(tier)
        case .paid: progress.claimedPaid.insert(tier)
        }
        passes[seasonID] = progress
        lifetime.passTiersClaimed += 1
        guard let reward = season.reward(track: track, tier: tier) else { return }
        switch reward.kind {
        case .beans: earn(reward.amount ?? 0)
        case .item: if let id = reward.id {
                owned[id, default: 0] += 1
            }
        case .outfit: if let id = reward.id {
                ownedOutfits.insert(id)
            }
        case .surface: if let id = reward.id {
                ownedSurfaces.insert(id)
            }
        }
    }

    private mutating func addPassPoints(_ points: Int, capped: Bool, context: RulesContext) {
        guard let tally = today, let season = context.season(on: tally.day) else { return }
        var add = points
        if capped {
            add = min(points, Tuning.Pass.dailyCap - tally.passPoints)
            guard add > 0 else { return }
            today?.passPoints += add
        }
        passes[season.id, default: SeasonProgress()].points += add
    }

    // MARK: Objectives

    private mutating func bump(_ metric: ObjectiveMetric, by amount: Int = 1, context: RulesContext) {
        guard today != nil else { return }
        today?.metrics[metric, default: 0] += amount
        week?.metrics[metric, default: 0] += amount
        for id in today?.objectives ?? [] where today?.completed.contains(id) == false {
            guard let objective = context.dailyObjectives.first(where: { $0.id == id }), objective.metric == metric,
                  (today?.metrics[metric] ?? 0) >= objective.target else { continue }
            today?.completed.insert(id)
            reward(objective, context: context)
        }
        for id in week?.objectives ?? [] where week?.completed.contains(id) == false {
            guard let objective = context.weeklyObjectives.first(where: { $0.id == id }), objective.metric == metric,
                  (week?.metrics[metric] ?? 0) >= objective.target else { continue }
            week?.completed.insert(id)
            reward(objective, context: context)
        }
    }

    private mutating func checkAchievements(on day: GameDay, context: RulesContext) {
        for objective in context.achievements where !completedAchievements.contains(objective.id) {
            guard objective.metric.isLifetime, lifetimeValue(objective.metric, on: day) >= objective.target else { continue }
            completedAchievements.insert(objective.id)
            reward(objective, context: context)
        }
    }

    private mutating func reward(_ objective: ObjectiveDefinition, context: RulesContext) {
        earn(objective.beans)
        // Objective pass points sit on top of the daily cap.
        if objective.passPoints > 0 {
            addPassPoints(objective.passPoints, capped: false, context: context)
        }
    }

    // MARK: XP and Beans

    private mutating func gainXP(_ amount: Int) {
        let before = level
        xp += amount
        let gained = level - before
        if gained > 0 {
            earn(gained * Tuning.Beans.levelUp)
        }
    }

    private mutating func earn(_ amount: Int) {
        guard amount > 0 else { return }
        today?.baseBeans += amount
    }

    private mutating func updateCat(_ id: String, _ change: (inout CatState) -> Void) {
        guard let index = cats.firstIndex(where: { $0.id == id }) else { return }
        change(&cats[index])
    }
}
