import Foundation
@testable import HouseCatCore
import Testing

@Suite("Real weather")
struct RealWeatherTests {
    let tables = WeatherFile(tables: [:])

    func report(at place: HomePlace, from start: Date, _ weather: Weather) -> WeatherReport {
        WeatherReport(
            latitude: place.latitude,
            longitude: place.longitude,
            fetchedAt: start,
            hours: (0 ..< 24).map { .init(start: start.addingTimeInterval(Double($0) * 3600), weather: weather, temperatureC: 9) }
        )
    }

    @Test func weatherKitConditionsBecomeTheGamesWeather() {
        #expect(WeatherRules.weather(condition: "mostlyClear") == .sun)
        #expect(WeatherRules.weather(condition: "partlyCloudy") == .cloud)
        #expect(WeatherRules.weather(condition: "drizzle") == .rain)
        #expect(WeatherRules.weather(condition: "isolatedThunderstorms") == .storm)
        #expect(WeatherRules.weather(condition: "wintryMix") == .snow)
        #expect(WeatherRules.weather(condition: "haze") == .fog)
        #expect(WeatherRules.weather(condition: "breezy") == .wind)
        #expect(WeatherRules.weather(condition: "hot") == .heat)
        #expect(WeatherRules.weather(condition: "somethingNew") == nil)
    }

    @Test func onAutoTheReportForThePlaceDrivesTheHome() {
        var f = Fixture()
        f.add(.homePlaced(.london), day: 0)
        let noon = f.at(1, 12)
        let snow = report(at: .london, from: f.at(1, 6), .snow)
        #expect(f.state.homeNow(at: noon, weather: tables, report: snow).weather == .snow)
        // Beyond the report, or with no report, the simulation is back.
        let simulated = f.state.homeNow(at: noon, weather: tables).weather
        #expect(f.state.homeNow(at: f.at(3, 12), weather: tables, report: snow).weather
            == f.state.homeNow(at: f.at(3, 12), weather: tables).weather)
        #expect(simulated == f.state.homeNow(at: noon, weather: tables, report: nil).weather)
    }

    /// The Apple Weather mark goes only where Apple's weather is on screen: a report for this place and hour on
    /// Auto, not the simulation, not a fixed season's weather, not another town's report.
    @Test func theHomeKnowsWhenItsWeatherIsApplesForTheMark() {
        var f = Fixture()
        f.add(.homePlaced(.london), day: 0)
        let noon = f.at(1, 12)
        let rain = report(at: .london, from: f.at(1, 6), .rain)
        #expect(f.state.homeNow(at: noon, weather: tables, report: rain).weatherIsReal)
        #expect(!f.state.homeNow(at: noon, weather: tables, report: nil).weatherIsReal)
        // Past the report's hours: the simulation, so no mark.
        #expect(!f.state.homeNow(at: f.at(3, 12), weather: tables, report: rain).weatherIsReal)
        // A report taken somewhere else is not this home's weather.
        let elsewhere = HomePlace(name: "Leeds", latitude: 53.8, longitude: -1.55, timeZoneID: "Europe/London", biome: .city)
        #expect(!f.state.homeNow(at: noon, weather: tables, report: report(at: elsewhere, from: f.at(1, 6), .rain)).weatherIsReal)
        // A fixed season keeps the simulation whatever the report says.
        f.add(.seasonSet(.fixed(.winter)), day: 1)
        #expect(!f.state.homeNow(at: f.at(1, 13), weather: tables, report: rain).weatherIsReal)
    }

    @Test func theWidgetSceneCarriesWhetherItsWeatherIsApples() {
        var f = Fixture()
        f.add(.homePlaced(.london), day: 0)
        let noon = f.at(1, 12)
        let rain = report(at: .london, from: f.at(1, 6), .rain)
        let state = WidgetRules.state(at: noon, save: f.state, context: .empty)
        #expect(WidgetRules.scene(for: state, save: f.state, weather: tables, report: rain).weatherIsReal)
        #expect(!WidgetRules.scene(for: state, save: f.state, weather: tables, report: nil).weatherIsReal)
    }

    @Test func aFixedSeasonOrAnotherPlaceKeepsTheSimulation() {
        var f = Fixture()
        f.add(.homePlaced(.london), day: 0)
        let noon = f.at(1, 12)
        let simulated = f.state.homeNow(at: noon, weather: tables).weather
        let elsewhere = HomePlace(name: "Lisbon", latitude: 38.72, longitude: -9.14, timeZoneID: "Europe/Lisbon", biome: .coast)
        let farAway = report(at: elsewhere, from: f.at(1, 6), .heat)
        #expect(f.state.homeNow(at: noon, weather: tables, report: farAway).weather == simulated)
        f.add(.seasonSet(.fixed(.winter)), day: 0, hour: 10)
        let fixed = f.state.homeNow(at: noon, weather: tables).weather
        let here = report(at: .london, from: f.at(1, 6), .heat)
        #expect(f.state.homeNow(at: noon, weather: tables, report: here).weather == fixed)
    }

    @Test func aReportIsAskedForAgainWhenOldOrRunningOut() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let report = WeatherReport(
            latitude: 51.5,
            longitude: -0.1,
            fetchedAt: start,
            hours: (0 ..< 72).map { .init(start: start.addingTimeInterval(Double($0) * 3600), weather: .sun, temperatureC: 20) }
        )
        #expect(!report.needsRefresh(at: start.addingTimeInterval(600)))
        #expect(report.needsRefresh(at: start.addingTimeInterval(Tuning.Weather.reportRefreshMinutes * 60 + 1)))
        #expect(report.needsRefresh(at: start.addingTimeInterval(60 * 3600)))
    }
}

@Suite("Widget scenes")
struct WidgetSceneTests {
    let tables = WeatherFile(tables: [:])

    @Test func everyHomeHasItsWindowAndEveryPoseItsPainting() {
        #expect(Set(HouseStyle.allCases.map(\.widgetFrame)).count == HouseStyle.allCases.count)
        #expect(HouseStyle.londonTerrace.widgetFrame == "sash")
        #expect(HouseStyle.houseboat.widgetFrame == "porthole")
        #expect(WidgetPose.lookingOutWindow.catPose == .sitBack)
        #expect(WidgetPose.asleep.catPose == .sleepCurl)
        #expect(WidgetPose.stillWaiting.catPose == .sitFront)
    }

    @Test func aSceneShowsTheHomesWindowAndWhatIsOutside() {
        var f = Fixture()
        f.add(.homePlaced(.london), day: 0)
        f.add(.homeStyleChosen(.cottage), day: 0)
        f.visit(days: [0])
        let state = WidgetRules.state(at: f.at(1, 21), save: f.state, context: f.context)
        let scene = WidgetRules.scene(for: state, save: f.state, weather: tables, report: nil)
        #expect(scene.frame == "casement")
        #expect(scene.sky == .night)
        #expect(scene.catPose == .sitFront)
        #expect(scene.temperatureC == nil)
        let report = WeatherReport(
            latitude: HomePlace.london.latitude,
            longitude: HomePlace.london.longitude,
            fetchedAt: f.at(1, 6),
            hours: (0 ..< 24).map { .init(start: f.at(1, 6).addingTimeInterval(Double($0) * 3600), weather: .rain, temperatureC: 7) }
        )
        let real = WidgetRules.scene(for: state, save: f.state, weather: tables, report: report)
        #expect(real.weather == .rain)
        #expect(real.temperatureC == 7)
    }

    /// The step's exit test on a test clock: two days of half-hour entries, the first day visited only from
    /// the widget, the second not at all, each entry as the app would compute it.
    @Test func fortyEightHoursOfWidgetAreRight() throws {
        var f = Fixture()
        f.visit(days: [0])
        f.collectGifts(day: 0, hour: 23)
        let morning = WidgetRules.timeline(from: f.at(1, 6), save: f.state, context: f.context)
        #expect(morning.first?.pose == .waitingByDoor)
        #expect(morning.first { $0.date == f.at(1, 12) }?.pose == .lookingOutWindow)
        // Fed from the widget at 13:00: that is the day's visit.
        let kind = WidgetRules.event(for: .feed, at: f.at(1, 13), save: f.state, context: f.context)
        #expect(kind == .fed(catID: f.cat))
        try f.add(#require(kind), day: 1, hour: 13, source: .widget)
        #expect(WidgetRules.event(for: .feed, at: f.at(1, 13, 5), save: f.state, context: f.context) == nil)
        f.collectGifts(day: 1, hour: 5, minute: 50) // the end of game day 1, after midnight
        let day1 = WidgetRules.timeline(from: f.at(1, 13, 1), save: f.state, context: f.context)
        let day2 = WidgetRules.timeline(from: f.at(2, 6), save: f.state, context: f.context)
        let entries = day1 + day2
        #expect(day1.count == 48 && day2.count == 48)
        func pose(_ day: Int, _ hour: Int, _ minute: Int = 0) -> WidgetPose? {
            entries.first { $0.date == f.at(day, hour, minute) }?.pose
        }
        #expect(pose(1, 13, 30) == .content)
        #expect(pose(1, 15) == .box)
        #expect(pose(1, 19) == .sofa)
        #expect(pose(1, 22) == .zoomies)
        #expect(pose(1, 23, 30) == .asleep)
        #expect(pose(2, 7) == .waitingByDoor)
        #expect(pose(2, 13) == .lookingOutWindow)
        #expect(pose(2, 20, 30) == .stillWaiting)
        #expect(entries.allSatisfy { $0.streak == 2 })
        #expect(entries.filter { f.clock.day(of: $0.date) == f.day(1) }.allSatisfy { $0.visitedToday && $0.fedToday })
        #expect(entries.filter { f.clock.day(of: $0.date) == f.day(2) }.allSatisfy { !$0.visitedToday })
        for entry in entries {
            #expect(entry == WidgetRules.state(at: entry.date, save: f.state, context: f.context))
        }
        // The morning after the missed day, a sulk; the streak is graced.
        let day3 = WidgetRules.state(at: f.at(3, 8), save: f.state, context: f.context)
        #expect(day3.pose == .sulk)
        #expect(day3.streak == 2)
    }

    @Test func petAlwaysCountsAndNoCatMeansNothingToDo() {
        var f = Fixture()
        #expect(WidgetRules.event(for: .pet, at: f.at(0, 10), save: f.state, context: f.context) == .petted(catID: f.cat))
        f = Fixture(created: false)
        f.add(.householdCreated(seed: f.seed, clock: f.clock), day: 0, hour: 7)
        #expect(WidgetRules.event(for: .feed, at: f.at(0, 10), save: f.state, context: f.context) == nil)
    }
}

@Suite("Reminders")
struct ReminderTests {
    @Test func breakfastIsAtTheChosenTimeUnlessTheCatIsFed() {
        var f = Fixture()
        f.visit(days: [0])
        let plan = ReminderRules.plan(from: f.at(1, 7), save: f.state(through: 1), settings: ReminderSettings())
        let breakfasts = plan.filter { $0.kind == .breakfast }
        #expect(breakfasts.count == Tuning.Reminders.daysAhead)
        #expect(breakfasts.first?.at == f.at(1, 7, 30))
        #expect(breakfasts.first?.lineContext == "feed.nag_morning")
        #expect(breakfasts.map(\.id).count == Set(breakfasts.map(\.id)).count)
        f.add(.fed(catID: f.cat), day: 1, hour: 7, minute: 10)
        let after = ReminderRules.plan(from: f.at(1, 7, 15), save: f.state, settings: ReminderSettings())
        #expect(after.first { $0.kind == .breakfast }?.at == f.at(2, 7, 30))
    }

    @Test func theEveningNudgeIsOptionalAndSkippedOnceVisited() {
        var f = Fixture()
        f.visit(days: [0])
        #expect(ReminderRules.plan(from: f.at(1, 9), save: f.state(through: 1), settings: ReminderSettings())
            .allSatisfy { $0.kind != .evening })
        var settings = ReminderSettings()
        settings.evening = true
        let unvisited = ReminderRules.plan(from: f.at(1, 9), save: f.state(through: 1), settings: settings)
        #expect(unvisited.first { $0.kind == .evening }?.at == f.at(1, 19, 30))
        f.add(.arrived, day: 1, hour: 9)
        let visited = ReminderRules.plan(from: f.at(1, 9, 5), save: f.state, settings: settings)
        #expect(visited.first { $0.kind == .evening }?.at == f.at(2, 19, 30))
    }

    @Test func aGiftDropGetsItsOwnReminder() {
        var f = Fixture()
        f.add(.arrived, day: 0, hour: 8)
        f.add(.fed(catID: f.cat), day: 0, hour: 8)
        let drop = f.state.pendingGifts[0].dropAt
        let plan = ReminderRules.plan(from: f.at(0, 8, 1), save: f.state, settings: ReminderSettings())
        let gift = plan.first { $0.kind == .gift }
        #expect(gift?.at == drop)
        #expect(gift?.lineContext.hasPrefix("gift.") == true)
        var off = ReminderSettings()
        off.gifts = false
        #expect(ReminderRules.plan(from: f.at(0, 8, 1), save: f.state, settings: off).allSatisfy { $0.kind != .gift })
    }

    @Test func pausedDaysAreQuiet() {
        var f = Fixture()
        f.visit(days: [0])
        f.add(.pauseStarted(days: 3), day: 0, hour: 20)
        let plan = ReminderRules.plan(from: f.at(1, 7), save: f.state(through: 1), settings: ReminderSettings())
        let days = Set(plan.filter { $0.kind == .breakfast }.map { f.clock.day(of: $0.at) })
        #expect(!days.contains(f.day(1)))
        #expect(days.contains(f.day(5)))
    }
}
