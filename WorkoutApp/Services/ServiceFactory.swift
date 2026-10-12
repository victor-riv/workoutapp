import Foundation

/// Single switchboard for where workouts come from.
///
/// `useMock = true` while developing (no Google OAuth client needed).
/// Set to `false` once the Google Cloud OAuth client is configured and the
/// Gmail sign-in works — see BUILD_CHECKLIST.md.
enum ServiceFactory {
    static let useMock = true

    static func makeService() -> any WorkoutSource {
        if useMock {
            MockWorkoutSource()
        } else {
            EmailWorkoutSource(gmail: GmailService(tokenProvider: {
                try await GoogleAuthProvider.shared.freshAccessToken()
            }))
        }
    }
}
