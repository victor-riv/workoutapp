import Foundation
import SwiftData

/// One training day: the workout as programmed (imported or manual) plus
/// the sets the user actually logged.
@Model
final class WorkoutDay {
    /// Calendar day this workout belongs to (stored as start-of-day).
    var date: Date
    var title: String
    /// Stable id of the source this day was imported from, if any —
    /// the email's week/day code ("W2D3").
    var sourceWorkoutID: String?
    var importedAt: Date?
    var isCompleted: Bool = false
    /// "P 155g · C 275g · F 65g · 2305 kcal", from the email's nutrition block.
    var nutritionSummary: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workoutDay)
    var exercises: [WorkoutExercise] = []

    init(date: Date = Date(), title: String, sourceWorkoutID: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.title = title
        self.sourceWorkoutID = sourceWorkoutID
        self.importedAt = sourceWorkoutID == nil ? nil : Date()
    }

    var sortedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var completedSetsCount: Int {
        exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        exercises.flatMap(\.sets).count
    }

    /// True when every set has been checked off.
    var allSetsDone: Bool {
        let sets = exercises.flatMap(\.sets)
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    /// Marks the workout complete if every set is done.
    /// Returns true if this call just completed it.
    @discardableResult
    func checkAutoComplete() -> Bool {
        guard !isCompleted, allSetsDone else { return false }
        isCompleted = true
        return true
    }

    /// Total volume of working sets (weight × reps), in lb. For the finisher card.
    var workingVolumeLb: Double {
        exercises.flatMap(\.sets).reduce(0) { total, set in
            guard !set.isWarmup, let weight = set.weight, let reps = set.reps else { return total }
            let lb = set.unit == .kg ? weight * 2.20462 : weight
            return total + lb * Double(reps)
        }
    }
}
