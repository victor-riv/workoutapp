import Foundation

/// What kind of block an exercise is. Non-lift blocks render as info in
/// the UI and don't get empty set rows.
enum ExerciseKind: String, Sendable, Codable {
    case lift
    case cardio
    case assessment
    case mobility
}

// MARK: - App-facing import model (source-agnostic)

/// One exercise block ready to become a WorkoutExercise.
struct ImportedBlock {
    var exerciseName: String
    var coachNotes: String
    var targetSets: Int
    var targetReps: String
    /// Coach-prescribed weight in lb (from "155 x 2 x 8" style email lines).
    /// Pre-fills set weights when there's no logged history yet.
    var prescribedWeight: Double?
    var kind: ExerciseKind = .lift
    /// "H" when the email labels a superset pair H1/H2.
    var supersetGroup: String?
    /// API-fallback only: TrueCoach block headers ("WARM UP", "METCON").
    var isCircuitHeader: Bool = false
}

/// A full workout day ready to become a WorkoutDay.
struct ImportedWorkout {
    var title: String
    var date: Date
    /// Stable id used to dedupe re-imports: the email's week/day code
    /// ("W2D3"), or the TrueCoach workout id for the API fallback.
    var sourceID: String
    var nutritionSummary: String?
    var blocks: [ImportedBlock]
}

// MARK: - Service protocol

/// Abstraction over where workouts come from. The app talks only to this
/// protocol, so the Gmail importer, the mock, and the (demoted) TrueCoach
/// API client are interchangeable.
protocol WorkoutSource: Sendable {
    /// The workout programmed for today, or nil when the coach hasn't
    /// programmed one / there's no connection.
    func fetchTodaysWorkout() async throws -> ImportedWorkout?

    /// Workouts programmed on/after `since`, newest first. Used to backfill
    /// history so "last weight" suggestions work from day one.
    func fetchWorkouts(since: Date) async throws -> [ImportedWorkout]
}

enum ImportError: LocalizedError {
    case notSignedIn
    case authenticationFailed
    case networkError(String)
    case gmailError(String)
    case invalidResponse
    case noWorkoutToday

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Connect your Gmail in Settings first."
        case .authenticationFailed:
            return "Sign-in failed. Check your credentials and try again."
        case .networkError(let message):
            return "Network error: \(message)"
        case .gmailError(let message):
            return "Gmail error: \(message)"
        case .invalidResponse:
            return "The workout email wasn't in the expected format."
        case .noWorkoutToday:
            return "No workout found for today."
        }
    }
}
