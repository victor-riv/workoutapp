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
}
