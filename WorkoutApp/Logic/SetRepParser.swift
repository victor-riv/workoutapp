import Foundation

/// Parses a coach's set/rep prescription from TrueCoach's free-text `info`
/// field into a structured (sets, reps) pair.
///
/// Handles the formats coaches actually write:
/// - "4x8", "4 x 8", "5×5"
/// - "3 sets of 10", "3 sets x 8-10"
/// - "3 x 10/side", "3 x 8-12/leg", "3 x 10/ea" (per-side prescriptions keep their suffix)
/// - "x5-10/movement" (leading-x per-unit prescriptions)
/// - "20 minutes", "10 min", "30 sec" (timed blocks get one set)
/// - "AMRAP", "3 x AMRAP"
///
/// Falls back to 3 sets with the raw text as the rep target so nothing
/// the coach wrote is ever lost.
public enum SetRepParser {
    public static func parse(_ text: String) -> (sets: Int, reps: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (3, "—") }

        // "x5-10/movement", "x10/side" — per-unit prescriptions with no set count.
        if let match = firstMatch(pattern: #"(?i)^\s*x\s*(\d+(?:\s*-\s*\d+)?(?:\s*/\s*\w+)?)"#, in: trimmed) {
            return (1, match[0])
        }

        // "20 minutes", "10 min", "30 sec", "20:00" — timed blocks get one set.
        if let match = firstMatch(pattern: #"(?i)^\s*(\d{1,3}:\d{2}|\d+\s*(?:min(?:ute)?s?|sec(?:ond)?s?|hrs?|hours?))\b"#, in: trimmed) {
            return (1, match[0])
        }

        // "4x8", "4 x 8-10", "3 x 10/side", "3 x 10/ea", "3 x 30s", "5×5 @ RPE 8"
        // (firstMatch returns capture groups only, so group 1 is match[0])
        if let match = firstMatch(pattern: #"(?i)(\d+)\s*[x×]\s*(\d+(?:\s*s(?:ec(?:ond)?s?)?)?(?:\s*-\s*\d+)?(?:\s*/\s*(?:side|leg|arm|each|ea))?|amrap)"#, in: trimmed),
           let sets = Int(match[0]) {
            return (sets, canonicalReps(match[1]))
        }

        // "3 sets of 10", "4 sets x 12"
        if let match = firstMatch(pattern: #"(?i)(\d+)\s+sets?\s+(?:of\s+|x\s*)?(\d+(?:\s*-\s*\d+)?|amrap)"#, in: trimmed),
           let sets = Int(match[0]) {
            return (sets, canonicalReps(match[1]))
        }

        // Bare "AMRAP"
        if trimmed.range(of: #"(?i)\bamrap\b"#, options: .regularExpression) != nil {
            return (1, "AMRAP")
        }

        return (3, trimmed)
    }

    /// AMRAP is the only rep token we normalize to uppercase; everything else
    /// keeps the coach's original casing (e.g. "10/side", not "10/SIDE"),
    /// with whitespace around "/" collapsed.
    private static func canonicalReps(_ raw: String) -> String {
        if raw.lowercased() == "amrap" { return "AMRAP" }
        return raw.replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
    }

    /// Returns capture groups (excluding group 0) for the first match, or nil.
    private static func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1 ..< match.numberOfRanges).map { group in
            let range = match.range(at: group)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: text)
            else { return "" }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
        }
    }
}
