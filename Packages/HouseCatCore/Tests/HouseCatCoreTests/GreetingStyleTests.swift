import Foundation
@testable import HouseCatCore
import Testing

/// Where the cat is when you come home and how it greets you (SPEC "The session loop" 3): personality × trust.
@Suite("Coming home")
struct GreetingStyleTests {
    func context(_ personality: Personality, time: TimeOfDay, available: Set<Affordance> = [.sit, .sleep, .hide, .perch, .watch, .eat, .bat]) -> BehaviourContext {
        BehaviourContext(mood: .content, weather: .cloud, personality: personality, timeOfDay: time, available: available, sunlit: false)
    }

    @Test func eachPersonalityGreetsInItsOwnWay() {
        // A Velcro cat runs to you once it knows you; a newcomer walks.
        #expect(GreetingStyle.style(personality: .velcro, trust: .newcomer, mood: .content, asleep: false) == .walks)
        #expect(GreetingStyle.style(personality: .velcro, trust: .wary, mood: .content, asleep: false) == .runs)
        // An Aloof cat glances up until it is comfortable with you, then only ever walks.
        #expect(GreetingStyle.style(personality: .aloof, trust: .curious, mood: .content, asleep: false) == .glances)
        #expect(GreetingStyle.style(personality: .aloof, trust: .comfortable, mood: .content, asleep: false) == .walks)
        #expect(GreetingStyle.style(personality: .aloof, trust: .soulmate, mood: .content, asleep: false) != .runs)
        // A Gremlin ambushes.
        #expect(GreetingStyle.style(personality: .gremlin, trust: .newcomer, mood: .content, asleep: false) == .ambush)
        // A Loaf asleep lifts its head and goes back to sleep, until it is devoted to you.
        #expect(GreetingStyle.style(personality: .loaf, trust: .bonded, mood: .content, asleep: true) == .dozes)
        #expect(GreetingStyle.style(personality: .loaf, trust: .devoted, mood: .content, asleep: true) == .walks)
        // Sulking after a missed day: no greeting, whoever it is.
        for personality in Personality.allCases {
            #expect(GreetingStyle.style(personality: personality, trust: .soulmate, mood: .sulky, asleep: false) == .ignores)
        }
        #expect(GreetingStyle.ambush.comesToYou && GreetingStyle.runs.comesToYou && !GreetingStyle.dozes.comesToYou)
    }

    @Test func beforeYouCameItWasRestingWhereItsDayPutIt() {
        var asleep = 0, perched = 0
        let start = GameDay(year: 2026, month: 11, day: 2)
        for i in 0 ..< 400 {
            var rng = DaySeed(household: 9, day: start.advanced(by: i), purpose: "rest")
            let night = BehaviourTable.resting(context(.loaf, time: .night), rng: &rng)
            if night.activity == .sleep {
                asleep += 1
            }
            let midday = BehaviourTable.resting(context(.aloof, time: .midday), rng: &rng)
            if midday.activity == .perch {
                perched += 1
            }
            // Only things it settles into: never waiting on you, wandering or tearing about.
            for choice in [night, midday] {
                #expect(![.nearPlayer, .zoomies, .explore, .bowlNag, .knockOff, .scratch].contains(choice.activity))
            }
        }
        #expect(asleep > 280, "a Loaf is mostly asleep at night, got \(asleep)")
        #expect(perched > 150, "an Aloof cat is mostly up high at midday, got \(perched)")
        // With nothing to rest on, the floor.
        var rng = DaySeed(household: 9, day: start, purpose: "rest")
        #expect(BehaviourTable.resting(context(.velcro, time: .evening, available: [.eat]), rng: &rng).activity == .floorLoaf)
    }

    @Test func aWanderSometimesGoesNextDoorAndNeverAtNight() {
        let offers: [RoomID: Set<Affordance>] = [.living: [.sit], .bedroom: [.sleep], .kitchen: [.eat]]
        var elsewhere = 0
        for i in 0 ..< 300 {
            var rng = DaySeed(household: 4, day: GameDay(index: i), purpose: "brain")
            if RoomChoice.room(for: .explore, current: .living, viewing: .living, offers: offers, timeOfDay: .midday, rng: &rng) != .living {
                elsewhere += 1
            }
        }
        #expect(elsewhere > 60 && elsewhere < 190, "\(elsewhere) of 300 next door")
        #expect(!BehaviourTable.options(for: context(.gremlin, time: .night)).contains { $0.0 == .explore })
        #expect(BehaviourTable.options(for: context(.gremlin, time: .midday)).contains { $0.0 == .explore })
    }
}

@Test func pastBedtimeTheCatStaysInBedAndOnlyLooksUp() {
    for personality in Personality.allCases {
        #expect(!GreetingStyle.style(personality: personality, trust: .devoted, mood: .content, asleep: true, lateNight: true).comesToYou)
        #expect(GreetingStyle.style(personality: personality, trust: .devoted, mood: .content, asleep: true, lateNight: true) == .dozes)
        #expect(GreetingStyle.style(personality: personality, trust: .devoted, mood: .content, asleep: false, lateNight: true) == .glances)
    }
}
