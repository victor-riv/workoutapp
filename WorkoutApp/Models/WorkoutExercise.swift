import Foundation
import SwiftData

/// One exercise block inside a workout day: the coach's prescription
/// (target sets/reps, notes) plus the user's logged sets.
@Model
final class WorkoutExercise {
    /// Position inside the day (preserves the coach's ordering).
    var order: Int
    var targetSets: Int
    /// Free-form rep target so coaches can write "8", "8-10", "AMRAP", etc.
    var targetReps: String
    /// Coach instructions from the workout email.
    var coachNotes: String
    /// Coach-prescribed weight in lb (from "155 x 2 x 8" style email lines).
    /// Pre-fills set weights when there's no logged history yet.
    var prescribedWeight: Double?
    /// `ExerciseKind` raw value: lift, cardio, assessment, mobility.
    /// Non-lift blocks render as info and don't get set rows.
    var kindRaw: String

    /// Human-readable prescription when the coach programmed multiple waves,
    /// e.g. "3 × 3 @ 120 lb · 3 × 5 @ 105 lb". Nil for single-wave exercises.
    var setWavesSummary: String?

    var exercise: Exercise?
    var workoutDay: WorkoutDay?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet] = []

    init(
        order: Int,
        targetSets: Int,
        targetReps: String,
        coachNotes: String = "",
        prescribedWeight: Double? = nil,
        kind: ExerciseKind = .lift,
        exercise: Exercise? = nil,
        setWavesSummary: String? = nil
    ) {
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.coachNotes = coachNotes
        self.prescribedWeight = prescribedWeight
        self.kindRaw = kind.rawValue
        self.exercise = exercise
        self.setWavesSummary = setWavesSummary
    }

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .lift }
        set { kindRaw = newValue.rawValue }
    }

    var sortedSets: [WorkoutSet] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    /// Pre-fill empty set rows from the prescription.
    /// Extra waves (back-off sets etc.) get their own rows after the first wave.
    func ensureSets(unit: WeightUnit, extraWaves: [PrescriptionWave] = []) {
        guard sets.isEmpty else { return }
        var number = 0
        func addWave(sets count: Int, reps: String) {
            for _ in 1 ... max(count, 1) {
                number += 1
                let set = WorkoutSet(setNumber: number, targetReps: reps, unit: unit)
                set.workoutExercise = self
                sets.append(set)
            }
        }
        addWave(sets: targetSets, reps: targetReps)
        for wave in extraWaves {
            addWave(sets: wave.sets, reps: wave.reps)
        }
    }
}
