import Foundation
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum GoogleAuthError: LocalizedError {
    case sdkNotAdded
    case noPresentingViewController
    case signInFailed(String)
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .sdkNotAdded:
            return "Add the GoogleSignIn Swift package (https://github.com/google/GoogleSignIn-iOS), then rebuild."
        case .noPresentingViewController:
            return "Couldn't find a window to present Google sign-in."
        case .signInFailed(let message):
            return message
        case .noSignedInUser:
            return "Connect your Gmail in Settings first."
        }
    }
}

/// Google Sign-In wrapper — the only place the app touches OAuth.
///
/// The app never sees the user's Google password: sign-in happens in
/// Google's own screen, and the SDK keeps the tokens in the Keychain.
/// Only one scope is ever requested: `gmail.readonly`.
///
/// Requires the GoogleSignIn Swift package
/// (https://github.com/google/GoogleSignIn-iOS). If the package isn't
/// added yet, every method throws `GoogleAuthError.sdkNotAdded` instead of
/// failing to compile — see BUILD_CHECKLIST.md.
final class GoogleAuthProvider: NSObject, ObservableObject {
    static let shared = GoogleAuthProvider()

    /// The only Google scope the app requests: read-only Gmail access.
    /// This is a Google "restricted" scope — fine for personal use with the
    /// OAuth app in Testing mode (see BUILD_CHECKLIST.md), but publishing
    /// to the App Store would require Google's verification.
    static let gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly"

    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?

    private override init() {
        super.init()
        #if canImport(GoogleSignIn)
        // The SDK persists the last signed-in user across launches.
        if let user = GIDSignIn.sharedInstance.currentUser {
            self.isSignedIn = true
            self.userEmail = user.profile?.email
        }
        #endif
    }

    /// Sign in, then request the Gmail scope incrementally so the consent
    /// screen states exactly what the app needs it for. Presents UI — call
    /// from the main thread.
    @MainActor
    func signIn() async throws {
        #if canImport(GoogleSignIn)
        guard let presenter = Self.topViewController() else {
            throw GoogleAuthError.noPresentingViewController
        }
        do {
            let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: GoogleAuthError.signInFailed("Unknown sign-in error."))
                    }
                }
            }
            if !(result.user.grantedScopes?.contains(Self.gmailReadonlyScope) ?? false) {
                _ = try await result.user.addScopes([Self.gmailReadonlyScope], presenting: presenter)
            }
            self.isSignedIn = true
            self.userEmail = result.user.profile?.email
        } catch {
            throw GoogleAuthError.signInFailed(error.localizedDescription)
        }
        #else
        throw GoogleAuthError.sdkNotAdded
        #endif
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        Task { @MainActor in
            self.isSignedIn = false
            self.userEmail = nil
        }
    }

    /// A fresh access token for Gmail API calls, refreshing when expired.
    /// Safe to call from any thread.
    func freshAccessToken() async throws -> String {
        #if canImport(GoogleSignIn)
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.noSignedInUser
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
        #else
        throw GoogleAuthError.sdkNotAdded
        #endif
    }

    // MARK: - Private

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }),
               var top = window.rootViewController {
                while let presented = top.presentedViewController {
                    top = presented
                }
                return top
            }
        }
        return scenes.first?.windows.first?.rootViewController
    }
}
