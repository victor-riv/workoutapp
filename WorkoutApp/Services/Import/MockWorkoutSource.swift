import Foundation

/// Deterministic stand-in for the real workout source. Used for development,
/// SwiftUI previews and the simulator — no Google sign-in needed.
final class MockWorkoutSource: WorkoutSource, Sendable {
    func fetchTodaysWorkout() async throws -> ImportedWorkout? {
        // Simulate a little latency.
        try await Task.sleep(nanoseconds: 400_000_000)
        return ImportedWorkout(
            title: "Workout (mock)",
            date: Calendar.current.startOfDay(for: Date()),
            sourceID: "mock-today",
            nutritionSummary: "P 155g · C 275g · F 65g · 2305 kcal",
            blocks: [
                ImportedBlock(
                    exerciseName: "Barbell Bench Press",
                    coachNotes: "4x8 @ RPE 8, rest 2-3 min between sets",
                    targetSets: 4,
                    targetReps: "8"
                ),
                ImportedBlock(
                    exerciseName: "Seated Dumbbell Shoulder Press",
                    coachNotes: "3x10, controlled tempo",
                    targetSets: 3,
                    targetReps: "10"
                ),
                ImportedBlock(
                    exerciseName: "Chest-Supported Row",
                    coachNotes: "3 sets of 12, squeeze at the top",
                    targetSets: 3,
                    targetReps: "12"
                ),
                ImportedBlock(
                    exerciseName: "Triceps Rope Pushdown",
                    coachNotes: "3x12-15",
                    targetSets: 3,
                    targetReps: "12-15"
                ),
                ImportedBlock(
                    exerciseName: "Face Pull",
                    coachNotes: "2x20, light, burn out",
                    targetSets: 2,
                    targetReps: "20"
                ),
            ]
        )
    }

    func fetchWorkouts(since: Date) async throws -> [ImportedWorkout] {
        []
    }
}
