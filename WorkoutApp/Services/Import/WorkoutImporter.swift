import Foundation
import SwiftData

/// Turns an `ImportedWorkout` into SwiftData rows, reusing existing
/// `Exercise` records (matched by normalized name) so weight history
/// accumulates across imports.
///
/// Re-import semantics (per the email spec): the same `sourceID` + date
/// updates the *prescription* in place and never clobbers logged sets.
/// Blocks that disappeared from the latest import are removed only when
/// they carry no logged data — the user's log is never deleted for them.
@MainActor
enum WorkoutImporter {
    @discardableResult
    static func importWorkout(_ imported: ImportedWorkout, into context: ModelContext) -> WorkoutDay {
        let dayStart = Calendar.current.startOfDay(for: imported.date)
        let sourceID = imported.sourceID
        let descriptor = FetchDescriptor<WorkoutDay>(
            predicate: #Predicate { $0.sourceWorkoutID == sourceID && $0.date == dayStart }
        )

        let day: WorkoutDay
        if let existing = try? context.fetch(descriptor).first {
            day = existing
            day.title = imported.title
            day.nutritionSummary = imported.nutritionSummary
            day.importedAt = Date()
        } else {
            day = WorkoutDay(date: imported.date, title: imported.title, sourceWorkoutID: sourceID)
            day.nutritionSummary = imported.nutritionSummary
            context.insert(day)
        }

        let profile = GymProfile.current(in: context)
        var seenNames = Set<String>()
        var order = 0

        for block in imported.blocks {
            order += 1
            let normalized = Exercise.normalize(block.exerciseName)
            seenNames.insert(normalized)

            let workoutExercise: WorkoutExercise
            if let existing = day.exercises.first(where: { $0.exercise?.normalizedName == normalized }) {
                // Re-import: update the prescription, leave logged sets alone.
                workoutExercise = existing
                workoutExercise.order = order
                workoutExercise.targetSets = block.targetSets
                workoutExercise.targetReps = block.targetReps
                workoutExercise.coachNotes = block.coachNotes
                workoutExercise.prescribedWeight = block.prescribedWeight
                workoutExercise.kind = block.kind
            } else {
                let exercise = findOrCreateExercise(named: block.exerciseName, in: context)
                workoutExercise = WorkoutExercise(
                    order: order,
                    targetSets: block.targetSets,
                    targetReps: block.targetReps,
                    coachNotes: block.coachNotes,
                    prescribedWeight: block.prescribedWeight,
                    kind: block.kind,
                    exercise: exercise
                )
                workoutExercise.workoutDay = day
                context.insert(workoutExercise)
                day.exercises.append(workoutExercise)

                if block.kind == .lift {
                    // Pre-fill the set rows; the user only fills in weights.
                    workoutExercise.ensureSets(unit: profile.unit)
                    seedWeights(into: workoutExercise, exercise: exercise, block: block, profile: profile, in: context)
                }
            }
        }

        // Drop blocks that vanished from the latest import — but only when
        // they carry no logged data. Never delete the user's log.
        for stale in day.exercises {
            if let normalized = stale.exercise?.normalizedName,
               seenNames.contains(normalized) {
                continue
            }
            let hasLoggedData = stale.sets.contains { $0.weight != nil || $0.reps != nil || $0.isCompleted }
            if !hasLoggedData {
                context.delete(stale)
            }
        }

        return day
    }

    /// Pre-fill empty set weights: last-used weight first, falling back to
    /// the coach's prescribed weight when there's no history yet.
    private static func seedWeights(
        into workoutExercise: WorkoutExercise,
        exercise: Exercise,
        block: ImportedBlock,
        profile: GymProfile,
        in context: ModelContext
    ) {
        if let suggestion = WeightSuggestionService.suggestion(for: exercise.normalizedName, in: context) {
            for set in workoutExercise.sets where set.weight == nil {
                set.weight = suggestion.weight
                set.unit = suggestion.unit
            }
        } else if let prescribed = block.prescribedWeight {
            // No history yet — the coach's programmed weight is the best
            // starting point (email weights are in lb).
            for set in workoutExercise.sets where set.weight == nil {
                set.weight = prescribed
                set.unit = profile.unit
            }
        }
    }

    static func findOrCreateExercise(named name: String, in context: ModelContext) -> Exercise {
        let normalized = Exercise.normalize(name)
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let exercise = Exercise(name: name)
        context.insert(exercise)
        return exercise
    }
}
