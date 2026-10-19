import Foundation
@testable import HouseCatCore
import Testing

/// Who looks after the cat, and what leaving does (CLAUDE.md "Leaving and removing"): the household keeps
/// everything it has (the streak, the Beans, the furniture, the presents, the visits already made); the one who
/// left counts for nothing afterwards, until a new invite brings them back.
@Suite("Co-owners joining, leaving and being removed")
struct MembershipTests {
    let sam = GameEvent.Actor.coOwner("Sam")

    /// Pip's household with Sam in it: both visit on days 0-3, and Sam spends some of the household's Beans.
    func shared() -> Fixture {
        var f = Fixture()
        f.add(.purchaseBeansGranted(transactionID: "t1", beans: 1000), day: 0, hour: 8)
        f.add(.coOwnerJoined, day: 0, hour: 9, actor: sam)
        for day in 0 ... 3 {
            f.add(.arrived, day: day, hour: 8)
            f.add(.arrived, day: day, hour: 18, actor: sam)
        }
        f.add(.outfitBought(outfitID: "beanie", beans: Tuning.Beans.outfit, gift: true), day: 2, hour: 19, actor: sam)
        return f
    }

    @Test func joiningMakesACoOwnerAndTheQuestAppears() {
        let f = shared()
        #expect(f.state.owners == ["owner", "co:Sam"])
        #expect(f.state.coOwners == ["co:Sam"])
        #expect(f.state.isMember("co:Sam"))
        #expect(f.state.otherOwners(than: "owner") == ["co:Sam"])
        #expect(f.state.otherOwners(than: "co:Sam") == ["owner"])
        #expect(CoopQuest.progress(f.state) != nil)
    }

    @Test func leavingTakesNothingFromTheHousehold() {
        var f = shared()
        let before = f.state(through: 4)
        f.add(.coOwnerLeft, day: 3, hour: 20, actor: sam)
        let after = f.state(through: 4)
        #expect(after.owners == ["owner"])
        #expect(!after.isMember("co:Sam"))
        #expect(after.formerOwners == ["co:Sam"])
        // The streak, the Beans, the present and the time together are as they were.
        #expect(after.streak == before.streak)
        #expect(after.beans == before.beans)
        #expect(after.ownedOutfits.contains("beanie"))
        #expect(after.outfitGifts.map(\.from) == ["co:Sam"])
        #expect(after.lifetime.visits == before.lifetime.visits)
        // The shared quest is for two: it goes.
        #expect(CoopQuest.progress(after) == nil)
    }

    @Test func whatALeaverDoesAfterwardsCountsForNothing() {
        var f = shared()
        f.add(.coOwnerLeft, day: 3, hour: 20, actor: sam)
        let beans = f.state.beans
        // Day 4: only Sam's old phone, offline, "visits" and buys: no visit for the streak, no Beans spent.
        f.add(.arrived, day: 4, hour: 9, actor: sam)
        f.add(.fed(catID: f.cat), day: 4, hour: 9, minute: 1, actor: sam)
        f.add(.outfitBought(outfitID: "raincoat", beans: Tuning.Beans.outfit, gift: true), day: 4, hour: 9, minute: 2, actor: sam)
        #expect(f.state.beans == beans)
        #expect(!f.state.ownedOutfits.contains("raincoat"))
        #expect(f.state.owners == ["owner"])
        // Day 4 has no visit: Sam no longer keeps the streak (the week's free miss covers it this once).
        #expect(f.state(through: 4).today?.visited == false)
        #expect(f.state.lifetime.visits == 4)
        #expect(f.state.lifetime.feeds == 0)
        #expect(f.state(through: 5).streak.lastVisitDay == f.day(3))
    }

    @Test func onlyTheOwnerRemovesAndTheOwnerCannotBeRemovedOrLeave() {
        var f = shared()
        f.add(.coOwnerRemoved(key: "owner"), day: 3, hour: 20, actor: sam)
        f.add(.coOwnerRemoved(key: "owner"), day: 3, hour: 20, minute: 1)
        f.add(.coOwnerLeft, day: 3, hour: 20, minute: 2)
        #expect(f.state.owners == ["owner", "co:Sam"])
        #expect(f.state.formerOwners.isEmpty)
        f.add(.coOwnerRemoved(key: "co:Sam"), day: 3, hour: 21)
        #expect(f.state.owners == ["owner"])
        #expect(!f.state.isMember("co:Sam"))
    }

    @Test func aRemovedCoOwnerCountsAgainOnlyAfterANewInvite() {
        var f = shared()
        f.add(.coOwnerRemoved(key: "co:Sam"), day: 3, hour: 21)
        f.add(.arrived, day: 4, hour: 9, actor: sam)
        #expect(f.state.lifetime.visits == 4) // visit days: 0-3
        #expect(f.state(through: 4).today?.visited == false)
        f.add(.coOwnerJoined, day: 4, hour: 10, actor: sam)
        f.add(.arrived, day: 4, hour: 11, actor: sam)
        #expect(f.state.isMember("co:Sam"))
        #expect(f.state.lifetime.visits == 5)
    }

    /// What was done before the removal still counts however late it syncs; what was done after never does.
    /// Both phones end with the same household whatever order the events arrive in.
    @Test func aRemovalSettlesTheSameWayOnBothPhonesInAnyOrder() {
        var owner = Fixture()
        owner.add(.coOwnerJoined, day: 0, hour: 9, actor: sam)
        var samsPhone = SaveLog(events: owner.log.events)
        // Sam visits offline on day 1 morning; the owner removes Sam at noon; Sam (still offline) visits at 18:00.
        let early = GameEvent(at: owner.at(1, 8), day: owner.day(1), actor: sam, kind: .arrived)
        owner.add(.coOwnerRemoved(key: "co:Sam"), day: 1, hour: 12)
        let late = GameEvent(at: owner.at(1, 18), day: owner.day(1), actor: sam, kind: .fed(catID: owner.cat))
        samsPhone.append(early)
        samsPhone.append(late)
        samsPhone.merge(owner.log.events.shuffled())
        owner.log.merge([late, early])
        let a = owner.log.derive(context: owner.context)
        let b = samsPhone.derive(context: owner.context)
        #expect(a == b)
        #expect(a.lifetime.visits == 1) // the morning visit
        #expect(a.lifetime.feeds == 0) // the evening feed came after the removal
        // Sam's phone sees that Sam is no longer in the household (and goes back to Sam's own cat).
        #expect(!b.isMember("co:Sam"))
    }

    @Test func aHiddenNameShowsAsTheOtherOwner() {
        #expect(OwnerName.display("co:Sam", otherwise: "Pip's other owner") == "Sam")
        #expect(OwnerName.display("co:Sam", otherwise: "Pip's other owner", hidden: ["co:Sam"]) == "Pip's other owner")
        #expect(OwnerName.display("co:Alex", otherwise: "Pip's other owner", hidden: ["co:Sam"]) == "Alex")
    }

    @Test func aReportIsAMailToSafetyWithTheHouseholdAndNameFilledIn() throws {
        let household = HouseholdReference.code(seed: 0x5EED)
        let report = SafetyReport(about: .name, reported: "Sam", catName: "Pip", household: household, appVersion: "1.1")
        let url = try #require(report.mailto())
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:safety@housecatgame.com?subject="))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = try #require(items.first { $0.name == "body" }?.value)
        #expect(body.contains("About: Their name"))
        #expect(body.contains("Who: Sam"))
        #expect(body.contains("Cat: Pip"))
        #expect(body.contains("Household: \(household)"))
        #expect(items.first { $0.name == "subject" }?.value == "HouseCat report (\(household))")
        // Nothing in the address is left unescaped.
        #expect(!url.absoluteString.contains(" "))
        #expect(!url.absoluteString.contains("\n"))
        let present = SafetyReport(about: .present, reported: "the owner", catName: "Pip", household: household, present: "Raincoat", appVersion: "1.1")
        #expect(present.body.contains("About: A present: Raincoat"))
    }

    @Test func aHouseholdReferenceIsSteadyAndSaysNothingOfTheSeed() {
        let code = HouseholdReference.code(seed: 0x5EED)
        #expect(code == HouseholdReference.code(seed: 0x5EED))
        #expect(code != HouseholdReference.code(seed: 0x5EEE))
        #expect(code.count == 12)
        #expect(code.hasPrefix("HC-"))
        let letters = code.dropFirst(3).filter { $0 != "-" }
        #expect(letters.count == 8)
        #expect(letters.allSatisfy(FriendCode.alphabet.contains))
        #expect(!code.contains(String(0x5EED, radix: 16, uppercase: true)))
    }
}
