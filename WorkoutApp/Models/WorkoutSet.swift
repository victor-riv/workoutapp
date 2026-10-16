import Foundation
import SwiftData

/// A single set: the prescription plus what the user actually did.
@Model
final class WorkoutSet {
    var setNumber: Int
    var targetReps: String

    /// What the user logged. Nil until they type it in.
    var weight: Double?
    var reps: Int?
    var isCompleted: Bool = false

    /// Warm-up sets don't count toward volume stats or personal records.
    var isWarmup: Bool = false

    /// "lb" or "kg" — the unit the weight was logged in.
    var unitRaw: String

    var workoutExercise: WorkoutExercise?

    init(setNumber: Int, targetReps: String, unit: WeightUnit, weight: Double? = nil, reps: Int? = nil) {
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.unitRaw = unit.rawValue
        self.weight = weight
        self.reps = reps
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: unitRaw) ?? .lb }
        set { unitRaw = newValue.rawValue }
    }
}
