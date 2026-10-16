import ActivityKit
import Foundation
import UIKit

/// The single rest timer for the whole app. Lives outside any view so the
/// timer keeps running when the user navigates between exercises or tabs.
///
/// Drives the in-app countdown UI, the haptic on completion, and the
/// Live Activity (Dynamic Island + Lock Screen).
@MainActor
@Observable
final class RestTimerManager {
    static let shared = RestTimerManager()

    private(set) var endDate: Date?
    private(set) var isRunning = false
    private(set) var exerciseName = ""
    private(set) var now = Date()
    private(set) var totalDuration: TimeInterval = 90

    private var activity: Activity<RestTimerAttributes>?
    private var ticker: Timer?

    private init() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.checkDone()
            }
        }
    }

    var lastSeconds: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "restTimerLastSeconds")
            return v > 0 ? v : 90
        }
        set { UserDefaults.standard.set(newValue, forKey: "restTimerLastSeconds") }
    }

    var isIdle: Bool { endDate == nil }

    var remaining: Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    func start(seconds: Int, exerciseName: String) {
        guard seconds > 0 else { return }
        lastSeconds = seconds
        self.exerciseName = exerciseName
        self.totalDuration = TimeInterval(seconds)
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        isRunning = true
        startLiveActivity()
    }

    func startWithLast(exerciseName: String) {
        start(seconds: lastSeconds, exerciseName: exerciseName)
    }

    func pause() {
        isRunning = false
        updateLiveActivity()
    }

    func resume() {
        let rem = remaining
        endDate = Date().addingTimeInterval(TimeInterval(rem))
        // For the Live Activity countdown, the display duration is the time left
        totalDuration = TimeInterval(rem)
        isRunning = true
        updateLiveActivity()
    }

    func reset() {
        endDate = nil
        isRunning = false
        endLiveActivity()
    }

    private func checkDone() {
        if isRunning, let end = endDate, now >= end {
            isRunning = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            endLiveActivity()
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard let endDate else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endLiveActivity()
        let attributes = RestTimerAttributes(exerciseName: exerciseName)
        let state = RestTimerAttributes.ContentState(
            endDate: endDate, isPaused: false, pausedRemaining: 0,
            totalDuration: totalDuration
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let state = RestTimerAttributes.ContentState(
            endDate: endDate ?? Date(),
            isPaused: !isRunning,
            pausedRemaining: TimeInterval(remaining),
            totalDuration: totalDuration
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
