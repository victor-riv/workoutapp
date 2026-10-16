import ActivityKit
import Foundation

/// Live Activity attributes for the rest timer.
/// This file is a member of BOTH the app target and the widget extension target.
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
