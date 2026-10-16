import ActivityKit
import Foundation

/// Live Activity attributes for the rest timer.
/// Shared definition — must match the app target's version.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest ends. Ignored while paused.
        var endDate: Date
        var isPaused: Bool
        /// Seconds remaining at the moment it was paused.
        var pausedRemaining: TimeInterval
        /// Total duration of the timer (for countdown display).
        var totalDuration: TimeInterval
    }

    var exerciseName: String
}
