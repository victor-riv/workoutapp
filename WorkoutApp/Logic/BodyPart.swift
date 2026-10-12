import Foundation

/// A muscle group with the emoji used in its place on workout cards.
///
/// Detection is a keyword heuristic over the exercise name + coach notes —
/// good enough for a training log, and easy to extend as new movements
/// show up in the program.
struct BodyPart: Equatable {
    let label: String
    let emoji: String

    static func detect(name: String, notes: String = "") -> BodyPart {
        let text = (name + " " + notes).lowercased()
        let words = Set(
            text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        func hasWord(_ word: String) -> Bool { words.contains(word) }
        func hasPhrase(_ phrase: String) -> Bool { text.contains(phrase) }
        func hasAny(_ candidates: [String]) -> Bool {
            candidates.contains { candidate in
                // Short single words match whole-word only: "lat" must not
                // hit "lateral", "row" must not hit "narrow", "ab" must not
                // hit "cable". Multi-word and hyphenated phrases ("leg press",
                // "push-up") match as substrings.
                if candidate.allSatisfy(\.isLetter), candidate.count <= 4 {
                    hasWord(candidate)
                } else {
                    hasWord(candidate) || hasPhrase(candidate)
                }
            }
        }

        // Order matters: check the most specific compounds first.
        if hasAny(["stretch", "mobility", "yoga", "foam roll", "foam roller", "breathing"]) {
            return BodyPart(label: "Mobility", emoji: "🧘")
        }
        if hasAny(["assault bike", "bike", "cycling", "run", "running", "sprint",
                   "ski erg", "jump rope", "cardio", "hr ", "treadmill", "stairmaster"]) {
            return BodyPart(label: "Cardio", emoji: "🏃")
        }
        if hasAny(["squat", "lunge", "leg press", "leg extension", "leg curl",
                   "quad", "hamstring", "glute", "calf", "calves", "hip thrust",
                   "step-up", "step up", "bulgarian", "adductor", "abductor"]) {
            return BodyPart(label: "Legs", emoji: "🦵")
        }
        if hasAny(["row", "pull-up", "pullup", "pull up", "pulldown", "chin-up", "chinup", "chin up",
                   "lat", "deadlift", "back extension", "good morning", "superman"]) {
            return BodyPart(label: "Back", emoji: "🚣")
        }
        if hasAny(["bench", "chest", "pec", "push-up", "pushup", "push up",
                   "fly", "flies", "dip", "dips", "pullover"]) {
            return BodyPart(label: "Chest", emoji: "🏋️")
        }
        if hasAny(["shoulder", "overhead press", "military press", "arnold",
                   "lateral raise", "front raise", "rear delt", "shrug", "delt",
                   "face pull"]) {
            return BodyPart(label: "Shoulders", emoji: "🤾")
        }
        if hasAny(["curl", "biceps", "bicep", "triceps", "tricep", "hammer",
                   "skullcrusher", "kickback"]) {
            return BodyPart(label: "Arms", emoji: "💪")
        }
        if hasAny(["ab", "abs", "core", "plank", "crunch", "sit-up", "situp", "sit up",
                   "hollow", "dead bug", "russian twist", "leg raise"]) {
            return BodyPart(label: "Core", emoji: "🧱")
        }
        if hasAny(["clean", "snatch", "jerk", "thruster", "burpee", "man maker",
                   "turkish get-up", "turkish getup"]) {
            return BodyPart(label: "Full Body", emoji: "🤸")
        }
        return BodyPart(label: "Workout", emoji: "🏋️")
    }
}
