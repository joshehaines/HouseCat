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
        // Someone who left or was removed counts for nothing (an offline visit, a purchase) until they join again.
        if formerOwners.contains(event.actor.key) {
            guard case .coOwnerJoined = event.kind else { return }
        }
        // A day already closed cannot reopen; late events land on the open day.
        let day = max(event.day, today?.day ?? event.day)
        advance(to: day, context: context)
        lastEventAt = max(lastEventAt ?? event.at, event.at)
        if case .sitter = event.actor {} else {
            owners.insert(event.actor.key)
        }

        switch event.kind {
        case .householdCreated, .clockChanged, .catAdopted, .catRenamed, .personalityChanged, .catLookSet:
            applyHousehold(event, day: day)
        case .arrived, .fed, .petted, .miniGamePlayed, .giftCollected, .giftSold, .napCompleted, .healthGoalMet, .windowTapped:
            applyCare(event, context: context)
        case .itemBought, .itemGranted, .purchaseBeansGranted, .itemPlaced, .itemMoved, .itemStored, .catUsedNewItem, .roomOpened,
             .roomVisited,
             .surfaceChanged, .outfitWorn, .outfitTakenOff, .homeMoved, .seasonModeChanged, .homePlaced, .seasonSet, .homeStyleChosen, .houseBought, .tourFinished,
             .bundleGranted, .outfitBought, .screenSeen:
            applyHome(event, context: context)
        case .pauseStarted, .pauseEnded, .passPurchased, .passTierClaimed, .clubDayRecorded, .eventRewardClaimed, .streakRepaired,
             .questClaimed:
            applyStreakAndPass(event, day: day, context: context)
        case .sundayCardShared, .pawPrintSent, .groupJoined, .giftSent, .satForFriend:
            applySocial(event, context: context)
        case .coOwnerJoined, .coOwnerLeft, .coOwnerRemoved:
            applyMembership(event)
        case .arcadePlayed, .puzzleSolved:
            applyArcade(event, day: day, context: context)
        }

        checkPath(on: day, context: context)
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
                gainXP(Tuning.XP.arrival, context: context)
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
                gainXP(Tuning.XP.pets[index], context: context)
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
            gainXP(Tuning.XP.giftCollected, context: context)
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
            gainXP(Tuning.XP.nap, context: context)
            lifetime.naps += 1
            bump(.nap, context: context)
        case let .healthGoalMet(goal):
            guard today?.healthGoals.contains(goal) == false else { break }
            today?.healthGoals.insert(goal)
            switch goal {
            case .steps: gainXP(Tuning.XP.stepsGoalMet, context: context)
            case .sleep: gainXP(Tuning.XP.sleepGoalMet, context: context)
            case .workout: gainXP(Tuning.XP.workoutLogged, context: context)
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
        case let .bundleGranted(bundleID, transactionID):
            guard grantedBundles[transactionID] == nil, let bundle = context.bundles[bundleID] else { break }
            grantedBundles[transactionID] = bundleID
            for item in bundle.items {
                owned[item, default: 0] += 1
            }
            ownedSurfaces.formUnion(bundle.surfaces)
        case let .outfitBought(outfitID, price, gift):
            guard price >= 0, beans >= price, !ownedOutfits.contains(outfitID) else { break }
            beansSpent += price
            ownedOutfits.insert(outfitID)
            if gift {
                outfitGifts.append(OutfitGift(outfitID: outfitID, from: event.actor.key, at: event.at))
            }
        case let .screenSeen(screen):
            lifetime.screensSeen.insert(screen)
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
                  let index = placed.firstIndex(where: { $0.placementID == placementID }),
                  fits(placed[index].itemID, placementID: placementID, room: room, x: x, y: y, facing: facing, context: context)
            else { break }
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
                gainXP(gain, context: context)
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
            // Only what the household owns.
            guard cat(catID) != nil, ownedOutfits.contains(outfitID) else { break }
            updateCat(catID) { $0.outfitID = outfitID }
            if lifetime.outfitsTried.insert(outfitID).inserted {
                lifetime.outfitsWorn += 1
            }
            bump(.wearOutfit, context: context)
        case let .outfitTakenOff(catID):
            updateCat(catID) { $0.outfitID = nil }
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
        case let .houseBought(number, price):
            let current = rung
            guard number == current + 1, price >= HouseLadder.rung(number).price,
                  HouseLadder.block(above: current, level: level, tasksDone: houseTasksDone, beans: beans) == nil
            else { break }
            let bought = HouseLadder.rung(number)
            beansSpent += price
            home.rung = number
            // The new house's tasks count from today.
            home.movedIn = Dictionary(
                (Tuning.Ladder.houseTasks[number] ?? []).map { ($0.metric.rawValue, lifetimeValue($0.metric, on: event.day)) },
                uniquingKeysWith: { first, _ in first }
            )
            home.style = bought.style
            home.place = bought.place
            home.moving = false
            // Every room up to this rung, so a pre-ladder save that skipped one doesn't lose it.
            for room in HouseLadder.rungs.prefix(number).compactMap(\.room) {
                openedRooms.insert(room)
            }
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
        case .streakRepaired:
            guard StreakRepair.canRepair(self, on: day) else { break }
            for milestone in streak.repair() {
                reachStreak(milestone, context: context)
            }
        case .questClaimed:
            guard let progress = CoopQuest.progress(self), progress.isComplete, !progress.claimed else { break }
            week?.questClaimed = true
            earn(Tuning.Coop.questBeans)
        case let .eventRewardClaimed(eventID, rewardDay):
            guard let event = context.events.first(where: { $0.id == eventID }),
                  EventRules.claimable(event, state: self, on: day).contains(rewardDay),
                  let reward = event.rewards.first(where: { $0.day == rewardDay })
            else { break }
            eventClaims[eventID, default: []].insert(rewardDay)
            if let beans = reward.beans {
                beansGranted += beans
            }
            if let item = reward.item {
                owned[item, default: 0] += 1
            }
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
            addPassPoints(Tuning.Pass.sundayCard, capped: false, context: context)
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

    /// Who looks after the cat. Leaving or being removed takes nothing away: the household keeps the streak, the
    /// Beans, the furniture and the presents, and the visits already made still count. Only what comes after does not.
    private mutating func applyMembership(_ event: GameEvent) {
        switch event.kind {
        case .coOwnerJoined:
            formerOwners.remove(event.actor.key)
        case .coOwnerLeft:
            guard case .coOwner = event.actor else { break }
            owners.remove(event.actor.key)
            formerOwners.insert(event.actor.key)
        case let .coOwnerRemoved(key):
            guard event.actor == .owner, key != GameEvent.Actor.owner.key else { break }
            owners.remove(key)
            formerOwners.insert(key)
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
        streak.forgetBreak(before: day)
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
        if today?.visitors.contains(event.actor.key) == false {
            today?.visitors.insert(event.actor.key)
            if case .sitter = event.actor {} else {
                week?.visitsByOwner[event.actor.key, default: 0] += 1
            }
        }
        guard let tally = today, !tally.visited else { return }
        today?.visited = true
        today?.firstVisitAt = event.at
        lifetime.visits += 1
        for milestone in streak.visit(on: tally.day) {
            reachStreak(milestone, context: context)
        }
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
            gainXP(Tuning.XP.feed, context: context)
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
        lifetime.minigamesPlayed += 1
        gainXP(Tuning.XP.play, context: context)
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
        bump(.playMinigame, context: context)
    }

    // MARK: Home

    static func isFloor(_ surfaceID: String) -> Bool {
        surfaceID.hasPrefix("floor_")
    }

    static func inBounds(_ x: Int, _ y: Int) -> Bool {
        (0 ..< Tuning.Room.gridWidth).contains(x) && (0 ..< Tuning.Room.gridDepth).contains(y)
    }

    /// Whether a piece fits where an event puts it, among the room's other pieces (the co-owning merge rule:
    /// whoever placed second, in the log's order, finds the cells taken and the piece stays in the inventory).
    private func fits(
        _ itemID: String,
        placementID: UUID,
        room: RoomID,
        x: Int,
        y: Int,
        facing: GameEvent.Facing,
        context: RulesContext
    ) -> Bool {
        guard let piece = context.piece(itemID, placementID: placementID, x: x, y: y, facing: facing) else { return true }
        let others = placed.filter { $0.room == room && $0.placementID != placementID }.compactMap(context.piece)
        return PlacementRules.fits(piece, among: others)
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
        guard openedRooms.contains(room), Self.inBounds(x, y), available > placedCount(of: itemID),
              fits(itemID, placementID: event.id, room: room, x: x, y: y, facing: facing, context: context)
        else { return }
        placed.append(PlacedItem(placementID: event.id, itemID: itemID, room: room, x: x, y: y, facing: facing))
        let headroom = Tuning.XP.furniturePlacedMaxPerDay - (today?.furnitureXP ?? 0)
        let gain = min(Tuning.XP.furniturePlaced, headroom)
        if gain > 0 {
            today?.furnitureXP += gain
            gainXP(gain, context: context)
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
        // Everything in the tier's box, together.
        for reward in season.rewards(track: track, tier: tier) {
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
    }

    /// Pass XP for the season running today: the XP play earns (`capped`, up to `Tuning.Pass.dailyCap` a day) and
    /// the goals' bonus pass XP on top.
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

    /// A streak milestone: its Beans, and the outfit it earns, if any (the hoodie at 30 days, the bow tie at 100).
    private mutating func reachStreak(_ days: Int, context: RulesContext) {
        earn(StreakState.beans(forMilestone: days))
        if let outfit = context.streakOutfits[days] {
            ownedOutfits.insert(outfit)
        }
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

    /// The path (`PathRules`): each step of the open chapters met pays once; a chapter whose steps are all done pays
    /// its own reward and opens the next. Over again until nothing changes, as one step's XP can meet a level step.
    private mutating func checkPath(on day: GameDay, context: RulesContext) {
        var changed = true
        while changed {
            changed = false
            for chapter in context.path {
                for step in chapter.steps where !pathDone.contains(step.id) && PathRules.met(step, in: self, on: day) {
                    pathDone.insert(step.id)
                    rewardPath(
                        beans: step.beans, xp: step.xp, passPoints: step.passPoints, outfit: step.outfit, item: step.item, context: context
                    )
                    changed = true
                }
                guard !pathDone.contains(chapter.id) else { continue }
                // Later chapters stay closed until this one is done.
                guard PathRules.isComplete(chapter, done: pathDone) else { break }
                pathDone.insert(chapter.id)
                rewardPath(beans: chapter.beans, xp: chapter.xp, passPoints: 0, outfit: chapter.outfit, item: chapter.item, context: context)
                changed = true
            }
        }
    }

    private mutating func rewardPath(beans: Int, xp: Int, passPoints: Int, outfit: String?, item: String?, context: RulesContext) {
        earn(beans)
        if passPoints > 0 {
            addPassPoints(passPoints, capped: false, context: context)
        }
        if let outfit {
            ownedOutfits.insert(outfit)
        }
        if let item {
            owned[item, default: 0] += 1
        }
        if xp > 0 {
            gainXP(xp, context: context)
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

    /// XP climbs the level and, while a season runs (always), the season pass.
    private mutating func gainXP(_ amount: Int, context: RulesContext) {
        addPassPoints(amount, capped: true, context: context)
        let before = level
        xp += amount
        guard level > before else { return }
        for reached in before + 1 ... level {
            // Each level's Beans and any piece it gives (levels.json); rule tests without content pay the flat amount.
            if let reward = context.levels?.reward(for: reached) {
                earn(reward.beans)
                if let item = reward.item {
                    owned[item, default: 0] += 1
                }
            } else {
                earn(Tuning.Beans.levelUp)
            }
        }
    }

    // MARK: The Games menu

    /// A game from the Games menu or the daily puzzle: `ArcadeState` keeps the scores, stars and streak and says what
    /// it pays; a game that paid counts for the goals as a quick game does (`countArcadeGame`).
    private mutating func applyArcade(_ event: GameEvent, day: GameDay, context: RulesContext) {
        let payout: ArcadePayout
        switch event.kind {
        case let .arcadePlayed(result):
            payout = arcade.record(result, on: day, seed: seed)
            countArcadeGame(result, payout: payout, context: context)
        case let .puzzleSolved(solve):
            payout = arcade.record(solve, on: day)
        default:
            return
        }
        earn(payout.beans)
        if payout.xp > 0 {
            gainXP(payout.xp, context: context)
        }
    }

    /// A Games-menu game counts as a game played with the cat (today's and this week's goals, the lifetime games, wins
    /// and three-star games the path and the milestones count, and the day's play for the cat's care and a streak's
    /// mending) only when it paid: one of a score game's paid plays, or a level's new stars, so goals cannot be met by
    /// playing on for nothing. Two players at Cats in a Row never count (whoever goes first takes the stars), nor a
    /// cat the game does not have, and there a draw is not a win.
    private mutating func countArcadeGame(_ result: ArcadeResult, payout: ArcadePayout, context: RulesContext) {
        if result.game == .row, !ArcadeOpponents.ids.contains(result.opponent ?? "") {
            return
        }
        guard result.game.hasLevels ? payout.newStars > 0 : payout.paidPlay != nil else { return }
        today?.arcadePlays += 1
        lifetime.minigamesPlayed += 1
        bump(.playMinigame, context: context)
        let won = result.game == .row ? result.won : result.stars >= 1
        guard won else { return }
        lifetime.minigameWins += 1
        bump(.winMinigame, context: context)
        if result.stars >= 3 {
            lifetime.threeStarGames += 1
            bump(.threeStarMinigame, context: context)
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
