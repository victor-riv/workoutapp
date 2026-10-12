import Foundation

// MARK: - TrueCoach API data transfer objects
//
// These mirror the *compound document* returned by the TrueCoach client API
// (see TRUECOACH_INTEGRATION.md). Fields marked VERIFY need to be confirmed
// against a real account during integration — key names come from
// community documentation of the private client API, not an official spec.

/// Top-level response: three parallel arrays joined by workout id.
struct TCWorkoutResponse: Codable {
    var workouts: [TCWorkout]
    var workoutItems: [TCWorkoutItem]
    var comments: [TCComment]
    var meta: TCMeta

    enum CodingKeys: String, CodingKey {
        case workouts
        case workoutItems = "workout_items"
        case comments
        case meta
    }
}

struct TCWorkout: Codable, Identifiable {
    var id: Int
    var title: String?
    /// VERIFY: exact key name and date format ("due_date"? ISO-8601?).
    var dueDate: String?
    /// e.g. "completed", "scheduled"/"upcoming" — VERIFY the full list of states.
    var state: String?
    var warmup: String?
    var cooldown: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate = "due_date"
        case state
        case warmup
        case cooldown
    }
}

/// The real unit of work: one exercise entry inside a workout.
struct TCWorkoutItem: Codable, Identifiable {
    var id: Int
    /// VERIFY: exact key linking the item to its workout ("workout_id"?).
    var workoutID: Int?
    /// Exercise name, e.g. "Barbell Back Squat".
    var name: String?
    /// Coach instructions, e.g. "4x8 @ RPE 8, rest 2-3 min".
    var info: String?
    /// What the athlete previously logged for this item.
    var result: String?
    /// True for block headers ("WARM UP", "METCON") — these still carry
    /// real info/result in circuit-style workouts.
    var isCircuit: Bool?
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutID = "workout_id"
        case name
        case info
        case result
        case isCircuit = "is_circuit"
        case position
    }
}

struct TCComment: Codable, Identifiable {
    var id: Int
    var workoutID: Int?
    /// "client" or "trainer".
    var commenterType: String?
    var body: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutID = "workout_id"
        case commenterType = "commenter_type"
        case body
    }
}

struct TCMeta: Codable {
    var page: Int?
    var totalPages: Int?
    var perPage: Int?
    var totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case totalPages = "total_pages"
        case perPage = "per_page"
        case totalCount = "total_count"
    }
}

/// Token response from the OAuth2 password grant.
struct TCTokenResponse: Codable {
    var accessToken: String
    var userID: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userID = "user_id"
    }
}
