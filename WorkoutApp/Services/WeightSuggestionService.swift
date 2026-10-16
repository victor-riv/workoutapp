import Foundation
import SwiftData

/// What we know about the heaviest set logged for an exercise.
struct WeightSuggestion {
    var weight: Double
    var unit: WeightUnit
    var reps: Int?
    var date: Date
}

/// "Remember the heaviest weight" — derives the suggestion from the heaviest
/// completed working set logged for the exercise, across all workout days.
///
/// Kept as a query over completed sets (rather than a denormalized column)
/// so the suggestion is always consistent with the log, even if the user
/// edits history.
@MainActor
enum WeightSuggestionService {
    /// Heaviest completed working set for the exercise, or nil if never logged.
    /// Warm-up sets are excluded. Comparison is in lb so mixed units compare fairly.
    static func suggestion(for normalizedExerciseName: String, in context: ModelContext) -> WeightSuggestion? {
        let descriptor = FetchDescriptor<WorkoutDay>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let days = try? context.fetch(descriptor) else { return nil }
        var bestWeight: Double?
        var bestUnit: WeightUnit = .lb
        var bestReps: Int?
        var bestDate: Date?
        var bestLb = -1.0
        for day in days {
            for workoutExercise in day.sortedExercises
                where workoutExercise.exercise?.normalizedName == normalizedExerciseName
            {
                for set in workoutExercise.sortedSets
                    where set.isCompleted && !set.isWarmup
                {
                    guard let weight = set.weight else { continue }
                    let lb = set.unit == .kg ? weight * 2.20462 : weight
                    if lb > bestLb {
                        bestLb = lb
                        bestWeight = weight
                        bestUnit = set.unit
                        bestReps = set.reps
                        bestDate = day.date
                    }
                }
            }
        }
        guard let bestWeight, let bestDate else { return nil }
        return WeightSuggestion(weight: bestWeight, unit: bestUnit, reps: bestReps, date: bestDate)
    }

    /// Convenience for views holding an `Exercise`.
    static func suggestion(for exercise: Exercise, in context: ModelContext) -> WeightSuggestion? {
        suggestion(for: exercise.normalizedName, in: context)
    }
}
