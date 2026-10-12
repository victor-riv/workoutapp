import Foundation
import SwiftData

/// A distinct exercise (e.g. "Barbell Bench Press").
///
/// Exercises are de-duplicated by `normalizedName` so that imports from
/// TrueCoach and manually created entries resolve to the same record.
/// Weight history is derived from the completed sets of this exercise's
/// usages, which is what powers the "last weight" suggestion.
@Model
final class Exercise {
    var name: String
    var normalizedName: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var usages: [WorkoutExercise] = []

    init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed
        self.normalizedName = Self.normalize(trimmed)
        self.createdAt = Date()
    }

    /// Canonical key used to match exercises across imports.
    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
