import SwiftUI
import SwiftData
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Handles the OAuth redirect back from Google Sign-In.
/// Requires the reversed client ID as a URL scheme in Info.plist
/// (see BUILD_CHECKLIST.md).
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }
}

@main
struct WorkoutTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ])
    }
}
