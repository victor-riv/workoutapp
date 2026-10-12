import Foundation

/// DEMOTED TO DOCUMENTED FALLBACK (2026-10-10, Victor's decision).
///
/// The app now imports workouts by parsing TrueCoach notification emails
/// from Gmail (`Services/Email/`) — no TrueCoach credentials, no private
/// API. This client is kept as a researched, working fallback: it still
/// conforms to `WorkoutSource` and `ServiceFactory` could select it again,
/// but nothing wires it up today.
///
/// Real TrueCoach client built on the community-documented private client API.
///
/// VERIFY BEFORE SHIPPING: the base host, exact JSON key names and the list
/// of `states` values must be confirmed against a real TrueCoach account
/// (see TRUECOACH_INTEGRATION.md). Everything marked VERIFY below is a
/// best-effort mapping from the community scraper's documentation.
///
/// Auth: OAuth2 password grant with the user's *own* TrueCoach credentials.
/// The password is used once to obtain a token and is never stored; only
/// the access token lives in the Keychain.
final class TrueCoachAPIClient: WorkoutSource, @unchecked Sendable {
    // MARK: - Configuration (VERIFY)

    /// Base host of the TrueCoach web client. The documented paths live
    /// under `/proxy/api` on the web host — confirm the exact host during
    /// integration (see TRUECOACH_INTEGRATION.md step 1).
    var baseURL = URL(string: "https://app.truecoach.co")!

    private var clientID: Int? {
        get { UserDefaults.standard.object(forKey: "truecoach.clientID") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "truecoach.clientID") }
    }

    // MARK: - Auth

    /// Exchange the user's TrueCoach email/password for an access token.
    /// The password is held only for the duration of this call.
    func signIn(email: String, password: String) async throws {
        let url = baseURL.appendingPathComponent("/proxy/api/oauth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "password"),
            URLQueryItem(name: "username", value: email),
            URLQueryItem(name: "password", value: password),
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ImportError.authenticationFailed
        }
        let token = try JSONDecoder().decode(TCTokenResponse.self, from: data)
        KeychainHelper.saveToken(token.accessToken)

        // Resolve the client id from the user record.
        let user = try await fetchUser(userID: token.userID)
        self.clientID = user.clientID
    }

    func signOut() {
        KeychainHelper.deleteToken()
        clientID = nil
    }

    var isSignedIn: Bool {
        KeychainHelper.loadToken() != nil && clientID != nil
    }

    // MARK: - WorkoutSource (fallback)

    func fetchTodaysWorkout() async throws -> ImportedWorkout? {
        // VERIFY: confirm which `states` value lists scheduled/upcoming
        // workouts (community docs only demonstrate `states=completed`).
        let response = try await fetchWorkouts(states: ["scheduled", "upcoming"], page: 1, perPage: 50)
        let today = Calendar.current.startOfDay(for: Date())
        let todays = response.workouts.first { workout in
            guard let due = workout.dueDate,
                  let date = Self.parseDate(due)
            else { return false }
            return Calendar.current.isDate(date, inSameDayAs: today)
        }
        guard let workout = todays else { return nil }
        return Self.importWorkout(
            workout,
            items: response.workoutItems.filter { $0.workoutID == workout.id },
            date: today
        )
    }

    /// Backfill completed workouts on/after `since`, newest first.
    /// Assumes the API returns workouts newest-first; stops paging once a
    /// workout older than `since` appears.
    func fetchWorkouts(since: Date) async throws -> [ImportedWorkout] {
        let start = Calendar.current.startOfDay(for: since)
        var out: [ImportedWorkout] = []
        var page = 1
        while true {
            let response = try await fetchWorkouts(states: ["completed"], page: page, perPage: 50)
            if response.workouts.isEmpty { break }
            var reachedOlder = false
            for workout in response.workouts {
                guard let due = workout.dueDate,
                      let date = Self.parseDate(due)
                else { continue }
                if Calendar.current.startOfDay(for: date) < start {
                    reachedOlder = true
                    continue
                }
                out.append(Self.importWorkout(
                    workout,
                    items: response.workoutItems.filter { $0.workoutID == workout.id },
                    date: Calendar.current.startOfDay(for: date)
                ))
            }
            if reachedOlder || response.workouts.count < 50 { break }
            page += 1
        }
        return out.sorted { $0.date > $1.date }
    }

    func fetchWorkouts(states: [String], page: Int, perPage: Int) async throws -> TCWorkoutResponse {
        guard let token = KeychainHelper.loadToken(), let clientID else {
            throw ImportError.notSignedIn
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/proxy/api/clients/\(clientID)/workouts"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "states", value: states.joined(separator: ",")),
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        guard let url = components?.url else { throw ImportError.invalidResponse }

        var request = URLRequest(url: url)
        // Required headers — without these the workout endpoints 404.
        request.setValue("Client", forHTTPHeaderField: "Role")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ImportError.invalidResponse
        }
        return try JSONDecoder().decode(TCWorkoutResponse.self, from: data)
    }

    // MARK: - Private

    /// VERIFY: response shape of GET /proxy/api/users/{id}.
    private struct TCUserResponse: Codable {
        var clientID: Int?
        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
        }
    }

    private func fetchUser(userID: Int?) async throws -> TCUserResponse {
        guard let token = KeychainHelper.loadToken(), let userID else {
            throw ImportError.authenticationFailed
        }
        // VERIFY: exact path used to resolve the client id from the user id.
        let url = baseURL.appendingPathComponent("/proxy/api/users/\(userID)")
        var request = URLRequest(url: url)
        request.setValue("Client", forHTTPHeaderField: "Role")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ImportError.invalidResponse
        }
        return try JSONDecoder().decode(TCUserResponse.self, from: data)
    }

    /// Map one TrueCoach workout + its items to the app's import model.
    static func importWorkout(_ workout: TCWorkout, items: [TCWorkoutItem], date: Date) -> ImportedWorkout {
        let ordered = items.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        let blocks: [ImportedBlock] = ordered.compactMap { item in
            let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let info = item.info ?? ""
            let parsed = SetRepParser.parse(info)
            return ImportedBlock(
                exerciseName: name,
                coachNotes: info,
                targetSets: parsed.sets,
                targetReps: parsed.reps,
                isCircuitHeader: item.isCircuit ?? false
            )
        }
        return ImportedWorkout(
            title: workout.title ?? "Workout",
            date: date,
            sourceID: "truecoach-\(workout.id)",
            blocks: blocks
        )
    }

    /// VERIFY: the actual date format TrueCoach returns for due dates.
    static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        fallback.timeZone = TimeZone.current
        return fallback.date(from: String(string.prefix(10)))
    }
}
