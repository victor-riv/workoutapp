import Foundation
import SwiftData

/// What we know about the last time an exercise was performed.
struct WeightSuggestion {
    var weight: Double
    var unit: WeightUnit
    var reps: Int?
    var date: Date
}

/// "Remember the last weight" — derives the suggestion from the most recent
/// completed set logged for the exercise, across all workout days.
///
/// Kept as a query over completed sets (rather than a denormalized column)
/// so the suggestion is always consistent with the log, even if the user
/// edits history.
@MainActor
enum WeightSuggestionService {
    /// Most recent completed set for the exercise, or nil if never logged.
    static func suggestion(for normalizedExerciseName: String, in context: ModelContext) -> WeightSuggestion? {
        let descriptor = FetchDescriptor<WorkoutDay>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let days = try? context.fetch(descriptor) else { return nil }
        for day in days {
            for workoutExercise in day.sortedExercises
                where workoutExercise.exercise?.normalizedName == normalizedExerciseName
            {
                // Latest completed set within this exercise instance.
                if let set = workoutExercise.sortedSets.last(where: { $0.isCompleted && $0.weight != nil }),
                   let weight = set.weight {
                    return WeightSuggestion(
                        weight: weight,
                        unit: set.unit,
                        reps: set.reps,
                        date: day.date
                    )
                }
            }
        }
        return nil
    }

    /// Convenience for views holding an `Exercise`.
    static func suggestion(for exercise: Exercise, in context: ModelContext) -> WeightSuggestion? {
        suggestion(for: exercise.normalizedName, in: context)
    }
}
