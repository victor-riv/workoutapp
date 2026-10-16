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
                workoutExercise.setWavesSummary = Self.wavesSummary(
                    first: (sets: block.targetSets, reps: block.targetReps, weight: block.prescribedWeight),
                    extra: block.extraWaves
                )
            } else {
                let exercise = findOrCreateExercise(named: block.exerciseName, in: context)
                workoutExercise = WorkoutExercise(
                    order: order,
                    targetSets: block.targetSets,
                    targetReps: block.targetReps,
                    coachNotes: block.coachNotes,
                    prescribedWeight: block.prescribedWeight,
                    kind: block.kind,
                    exercise: exercise,
                    setWavesSummary: Self.wavesSummary(
                        first: (sets: block.targetSets, reps: block.targetReps, weight: block.prescribedWeight),
                        extra: block.extraWaves
                    )
                )
                workoutExercise.workoutDay = day
                context.insert(workoutExercise)
                day.exercises.append(workoutExercise)

                if block.kind == .lift {
                    // Pre-fill the set rows; the user only fills in weights.
                    workoutExercise.ensureSets(unit: profile.unit, extraWaves: block.extraWaves)
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

    /// "3 × 3 @ 120 lb · 3 × 5 @ 105 lb" for multi-wave prescriptions.
    /// Nil when there's only one wave (the header already shows "3 × 8").
    private static func wavesSummary(
        first: (sets: Int, reps: String, weight: Double?),
        extra: [PrescriptionWave]
    ) -> String? {
        guard !extra.isEmpty else { return nil }
        func waveText(sets: Int, reps: String, weight: Double?) -> String {
            var text = "\(sets) × \(reps)"
            if let weight {
                text += " @ \(String(format: "%g", weight)) lb"
            }
            return text
        }
        let parts = [waveText(sets: first.sets, reps: first.reps, weight: first.weight)]
            + extra.map { waveText(sets: $0.sets, reps: $0.reps, weight: $0.weight) }
        return parts.joined(separator: " · ")
    }

    /// Pre-fill empty set weights from the coach's prescribed weight for
    /// each wave, falling back to the heaviest logged weight when the coach
    /// didn't specify one for that wave.
    private static func seedWeights(
        into workoutExercise: WorkoutExercise,
        exercise: Exercise,
        block: ImportedBlock,
        profile: GymProfile,
        in context: ModelContext
    ) {
        let suggestion = WeightSuggestionService.suggestion(for: exercise.normalizedName, in: context)
        let sorted = workoutExercise.sortedSets
        // Wave boundaries: first wave, then each extra wave in order.
        let waves: [(count: Int, weight: Double?)] =
            [(block.targetSets, block.prescribedWeight)] +
            block.extraWaves.map { ($0.sets, $0.weight) }

        var index = 0
        for wave in waves {
            for _ in 0 ..< max(wave.count, 1) {
                guard index < sorted.count else { break }
                let set = sorted[index]
                if set.weight == nil {
                    if let waveWeight = wave.weight {
                        set.weight = waveWeight
                        set.unit = profile.unit
                    } else if let suggestion {
                        set.weight = suggestion.weight
                        set.unit = suggestion.unit
                    }
                }
                index += 1
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
