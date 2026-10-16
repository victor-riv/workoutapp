import Foundation
import HealthKit

/// Reads body weight from Apple Health.
/// All HealthKit access is on-device; nothing leaves the phone.
@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    @Published private(set) var isAuthorized = false
    @Published private(set) var weightHistory: [WeightSample] = []

    struct WeightSample: Identifiable {
        let id = UUID()
        let date: Date
        let weightLb: Double
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var bodyMassType: HKQuantityType {
        HKQuantityType(.bodyMass)
    }

    /// Requests read access to body weight. Call once; the system remembers.
    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMassType])
            // The request doesn't throw when the user denies or skips the
            // toggle — verify what iOS actually granted.
            await checkAuthorization()
        } catch {
            isAuthorized = false
        }
    }

    /// Checks current authorization without prompting.
    func checkAuthorization() async {
        guard isAvailable else { return }
        let status = store.authorizationStatus(for: bodyMassType)
        isAuthorized = (status == .sharingAuthorized)
        if isAuthorized {
            await refreshWeights()
        }
    }

    /// Pulls the last 90 days of weight samples, one per day (latest wins).
    func refreshWeights() async {
        guard isAvailable, isAuthorized else { return }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        // One entry per day — keep the latest reading of each day.
        var byDay: [Date: HKQuantitySample] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            if byDay[day] == nil {
                byDay[day] = sample
            }
        }

        let unit = HKUnit.pound()
        weightHistory = byDay
            .map { day, sample in
                WeightSample(date: day, weightLb: sample.quantity.doubleValue(for: unit))
            }
            .sorted { $0.date < $1.date }
    }

    /// Most recent weight, if any.
    var latestWeight: WeightSample? {
        weightHistory.last
    }

    /// Change vs 7 days ago (positive = gained).
    var weekChange: Double? {
        guard let latest = latestWeight else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: latest.date) ?? latest.date
        guard let past = weightHistory.last(where: { $0.date <= weekAgo }) else { return nil }
        return latest.weightLb - past.weightLb
    }
}
