import Foundation
import HouseCatCore
#if canImport(HealthKit) && os(iOS)
    import HealthKit
#endif

/// The health layer (SPEC "Health layer"): read-only HealthKit for today's steps, last night's sleep and today's
/// workouts, asked for on day 3 with the benefit stated; each goal met pays XP and the cat's line once a day
/// (HouseCatCore's HealthRules and the reducer). Nothing is ever written to Health, nothing leaves the phone,
/// and a goal missed costs nothing.
@MainActor
enum HealthLayer {
    private static let defaults = UserDefaults(suiteName: WidgetFiles.appGroup) ?? .standard

    static var asked: Bool {
        get { defaults.bool(forKey: "health.asked") }
        set { defaults.set(newValue, forKey: "health.asked") }
    }

    /// The player said yes on the card (iOS keeps the real permission; this is whether to read at all).
    static var on: Bool {
        get { defaults.bool(forKey: "health.on") }
        set { defaults.set(newValue, forKey: "health.on") }
    }

    static var isAvailable: Bool {
        #if canImport(HealthKit) && os(iOS)
            HKHealthStore.isHealthDataAvailable()
        #else
            false
        #endif
    }

    #if canImport(HealthKit) && os(iOS)
        private static let store = HKHealthStore()
        private static var types: Set<HKObjectType> {
            [HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        }
    #endif

    /// The card's yes: iOS's own question for read access, then today's goals.
    static func ask() async {
        asked = true
        #if canImport(HealthKit) && os(iOS)
            guard isAvailable else { return }
            do {
                try await store.requestAuthorization(toShare: [], read: types)
                on = true
                await check()
            } catch {
                on = false
            }
        #endif
    }

    /// Reads today's numbers and records any goal newly met. Returns the goals met now, for their lines.
    @discardableResult
    static func check() async -> [GameEvent.HealthGoal] {
        #if canImport(HealthKit) && os(iOS)
            guard on, isAvailable else { return [] }
            let session = GameSession.shared
            let now = session.now()
            let state = session.state(at: now)
            let dayStart = state.clock.start(of: state.clock.day(of: now))
            let steps = await sum(.stepCount, unit: .count(), from: dayStart, to: now)
            // Last night: from the evening before the day began.
            let sleep = await sleepHours(from: dayStart.addingTimeInterval(-12 * 3600), to: now)
            let workouts = await workoutCount(from: dayStart, to: now)
            let already = state.today?.healthGoals ?? []
            let met = HealthRules.goalsMet(steps: steps, sleepHours: sleep, workouts: workouts).filter { !already.contains($0) }
            for goal in met {
                session.append(.healthGoalMet(goal), at: session.now())
            }
            return met
        #else
            return []
        #endif
    }

    #if canImport(HealthKit) && os(iOS)
        private static func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
                options: .cumulativeSum
            )
            return await (try? descriptor.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
        }

        private static func sleepHours(from start: Date, to end: Date) async -> Double {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                sortDescriptors: []
            )
            let asleep: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            ]
            let samples = await (try? descriptor.result(for: store)) ?? []
            let seconds = samples.filter { asleep.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return seconds / 3600
        }

        private static func workoutCount(from start: Date, to end: Date) async -> Int {
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
            return await (try? descriptor.result(for: store))?.count ?? 0
        }
    #endif
}
