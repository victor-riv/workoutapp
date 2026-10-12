import Foundation

// MARK: - Parsed model (pure value types, UI-agnostic)

/// One prescription line from the email, e.g. "3 x 10 RIR 2-3".
struct ParsedPrescriptionLine: Sendable {
    /// Parsed set count. Nil when the coach's text doesn't state one —
    /// e.g. "115 x 3" (weight x reps); the parser never guesses.
    var sets: Int?
    /// Rep target text, e.g. "10/side", "20 minutes".
    var reps: String
    /// Coach-prescribed weight in lb, e.g. 155 from "155 x 2 x 8".
    var weight: Double?
    /// Reps-in-reserve note, e.g. "2-3".
    var rir: String?
    var isAmbiguous: Bool
    var rawText: String
    /// When the prescription line names its own movement
    /// ("ITYW Raise x 10/ea"), this is that movement's name.
    var embeddedExerciseName: String?
}

struct ParsedExercise: Sendable {
    /// Email label: "A", "H1" …
    var label: String
    /// "H" when the label is a superset pair (H1/H2), else nil.
    var supersetGroup: String?
    var name: String
    var kind: ExerciseKind
    var prescriptionLines: [ParsedPrescriptionLine]
    /// Lines that aren't prescriptions: sub-movements ("Front"),
    /// HR zones, TRAC scales, etc.
    var notes: [String]
}

struct ParsedNutrition: Sendable {
    var proteinG: Int?
    var carbsG: Int?
    var fatG: Int?
    var calories: Int?

    var summary: String? {
        var parts: [String] = []
        if let proteinG { parts.append("P \(proteinG)g") }
        if let carbsG { parts.append("C \(carbsG)g") }
        if let fatG { parts.append("F \(fatG)g") }
        if let calories { parts.append("\(calories) kcal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The subject line of a workout email: week/day code + date.
/// `isMissedReminder` marks "You missed your workout" emails, which the
/// importer skips entirely.
struct ParsedSubject: Sendable {
    var weekDayCode: String?
    var date: Date?
    var isMissedReminder: Bool
}

struct ParsedWorkout: Sendable {
    var weekDayCode: String?
    var date: Date?
    var exercises: [ParsedExercise]
    var nutrition: ParsedNutrition?
}

// MARK: - Parser

/// Parses TrueCoach workout notification emails (see
/// `EmailImport/EMAIL_FORMAT_SPEC.md`) into structured workouts.
///
/// Pure string-in/string-out — no network, no SwiftData — so it's fully
/// unit-testable. Ambiguous prescriptions are flagged, never reinterpreted.
enum EmailWorkoutParser {

    // MARK: Subject

    /// "[TrueCoach] Victor , here's your workout for W2D3 for Saturday Oct 10, 2026"
    /// Note the stray space before the comma and the occasional double
    /// space in the day ("Oct  6") — both are normalized.
    static func parseSubject(_ subject: String) -> ParsedSubject {
        if firstMatch(#"^\[TrueCoach\]\s+You missed your workout for\b"#, in: subject) != nil {
            return ParsedSubject(weekDayCode: nil, date: nil, isMissedReminder: true)
        }
        guard let (groups, _) = matchGroups(
            #"^\[TrueCoach\]\s+.+?\s*,\s*here['’]s your workout for\s+(\S+)\s+for\s+(.+?)\s*$"#,
            in: subject
        ) else {
            return ParsedSubject(weekDayCode: nil, date: nil, isMissedReminder: false)
        }
        let code = groups[0].isEmpty ? nil : groups[0]
        let date = parseDate(groups[1], format: "EEEE MMM d, yyyy")
        return ParsedSubject(weekDayCode: code, date: date, isMissedReminder: false)
    }

    // MARK: Body

    /// Returns nil for "You missed your workout" reminders (nothing to import).
    static func parseMessage(subject: String, body: String) -> ParsedWorkout? {
        let parsedSubject = parseSubject(subject)
        guard !parsedSubject.isMissedReminder else { return nil }

        let date = extractBodyDate(from: body) ?? parsedSubject.date

        var exercises: [ParsedExercise] = []
        var currentLabel: String?
        var currentName = ""
        var currentLines: [String] = []

        func flush() {
            if let label = currentLabel {
                exercises.append(buildExercise(label: label, name: currentName, lines: currentLines))
            }
            currentLabel = nil
            currentName = ""
            currentLines = []
        }

        var inFooter = false
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if inFooter { continue }
            if line.isEmpty { continue }
            if isFooterStart(line) {
                flush()
                inFooter = true
                continue
            }
            if let (label, name) = parseLabel(line) {
                flush()
                currentLabel = label
                currentName = name
                continue
            }
            // Week/day marker ("**W2D3**") and other lone bold lines: ignore.
            if firstMatch(#"^\*\*.+\*\*$"#, in: line) != nil { continue }
            if currentLabel != nil {
                currentLines.append(line)
            }
            // Anything before the first exercise label is header boilerplate.
        }
        flush()

        return ParsedWorkout(
            weekDayCode: parsedSubject.weekDayCode,
            date: date,
            exercises: exercises,
            nutrition: parseNutrition(from: body)
        )
    }

    // MARK: - Exercise blocks

    /// "**A) TRAC Report**" / "B) Lower Body Mobility" / "**H1) Alternating Dumbbell Curl**"
    /// (the ** markers are optional — pasted text often loses them)
    private static func parseLabel(_ line: String) -> (label: String, name: String)? {
        guard let (groups, _) = matchGroups(
            #"^(?:\*\*)?\s*([A-Z]{1,2}\d{0,2})\)\s*(.+?)\s*(?:\*\*)?$"#,
            in: line
        ) else { return nil }
        return (groups[0], groups[1])
    }

    private static func buildExercise(label: String, name: String, lines: [String]) -> ParsedExercise {
        let kind = classify(name: name)
        let letters = String(label.prefix(while: { $0.isLetter }))
        let digits = label.dropFirst(letters.count)
        let supersetGroup = digits.isEmpty ? nil : letters

        var prescriptions: [ParsedPrescriptionLine] = []
        var notes: [String] = []

        switch kind {
        case .assessment:
            // TRAC scales etc. — informational, not a prescription.
            notes = lines
        case .cardio:
            // First line is the prescription, kept verbatim
            // ("20 minutes", "30 seconds sprint, 2:30 minute walk - 5 rounds").
            if let first = lines.first {
                prescriptions.append(ParsedPrescriptionLine(
                    sets: 1, reps: first, weight: nil, rir: nil,
                    isAmbiguous: false, rawText: first
                ))
                notes = Array(lines.dropFirst())
            }
        case .lift, .mobility:
            for line in lines {
                if isPrescriptionLine(line) {
                    prescriptions.append(parsePrescriptionLine(line))
                } else {
                    notes.append(line)
                }
            }
        }

        // "ITYW Raise x 10/ea" — the line names the real movement, which is
        // what weight history should be tracked against.
        var finalName = name
        if let embedded = prescriptions.first?.embeddedExerciseName, !embedded.isEmpty {
            finalName = embedded
        }

        return ParsedExercise(
            label: label,
            supersetGroup: supersetGroup,
            name: finalName,
            kind: kind,
            prescriptionLines: prescriptions,
            notes: notes
        )
    }

    private static func classify(name: String) -> ExerciseKind {
        let lower = name.lowercased()
        if lower.contains("trac") { return .assessment }
        if lower.contains("mobility") { return .mobility }
        if lower.contains("cardio")
            || firstMatch(#"\b(run|interval|sprint)\b"#, in: lower) != nil {
            return .cardio
        }
        return .lift
    }

    /// A line is a prescription if it starts with a number ("3 x 15",
    /// "20 minutes"), a leading-x scheme ("x5-10/movement"), or names its
    /// own movement ("ITYW Raise x 10/ea"). Everything else ("Front",
    /// "HR 120-140") is a note.
    private static func isPrescriptionLine(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return false }
        if first.isNumber { return true }
        if first == "x" || first == "X" {
            return text.dropFirst().first?.isNumber == true
        }
        return firstMatch(#"^[A-Za-z][A-Za-z'\s/\-]*?\s+[x×]\s*\d"#, in: text) != nil
    }

    // MARK: - Prescription lines

    private static func parsePrescriptionLine(_ line: String) -> ParsedPrescriptionLine {
        let raw = line.trimmingCharacters(in: .whitespaces)
        var text = raw
        var rir: String?

        // RIR annotations ("RIR 2-3") are intensity notes, not set/rep data.
        if let (groups, range) = matchGroups(#"(?i)(?:^|\s)RIR\s+(\d+(?:\s*[–-]\s*\d+)?)\s*$"#, in: text),
           let swiftRange = Range(range, in: text) {
            rir = groups[0].replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            text = text.replacingCharacters(in: swiftRange, with: "").trimmingCharacters(in: .whitespaces)
        }

        // Weight-led three-part: "155 x 2 x 8" → 155 lb, 2 sets, 8 reps.
        // The > 12 rule separates weights from set counts ("3 x 15" is sets
        // x reps; "155 x 2 x 8" is weight-led). Documented assumption: this
        // coach never programs more than 12 sets of anything.
        if let (groups, _) = matchGroups(
            #"^(\d+(?:\.\d+)?)\s*[x×]\s*(\d+)\s*[x×]\s*(\d+(?:\s*[–-]\s*\d+)?(?:\s*/\s*[A-Za-z]+)?)\s*$"#,
            in: text
        ), let leading = Double(groups[0]), leading > 12, let sets = Int(groups[1]) {
            return ParsedPrescriptionLine(
                sets: sets, reps: groups[2], weight: leading, rir: rir,
                isAmbiguous: false, rawText: raw
            )
        }

        // Weight-led two-part: "115 x 3" → 115 lb x 3 reps, sets unknown.
        // Flagged ambiguous and never guessed at.
        if let (groups, _) = matchGroups(
            #"^(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\s*[–-]\s*\d+)?(?:\s*/\s*[A-Za-z]+)?)\s*$"#,
            in: text
        ), let leading = Double(groups[0]), leading > 12 {
            return ParsedPrescriptionLine(
                sets: nil, reps: groups[1], weight: leading, rir: rir,
                isAmbiguous: true, rawText: raw
            )
        }

        // Embedded exercise name: "ITYW Raise x 10/ea".
        if let (groups, _) = matchGroups(
            #"^([A-Za-z][A-Za-z'\s/\-]*?)\s+[x×]\s*(\d.*)$"#,
            in: text
        ) {
            let reparsed = SetRepParser.parse("1 x " + groups[1])
            return ParsedPrescriptionLine(
                sets: reparsed.sets, reps: reparsed.reps, weight: nil, rir: rir,
                isAmbiguous: false, rawText: raw,
                embeddedExerciseName: groups[0].trimmingCharacters(in: .whitespaces)
            )
        }

        // Everything else goes through the existing set/rep parser.
        let parsed = SetRepParser.parse(text)
        return ParsedPrescriptionLine(
            sets: parsed.sets, reps: parsed.reps, weight: nil, rir: rir,
            isAmbiguous: false, rawText: raw
        )
    }

    // MARK: - Header / footer / nutrition

    /// "Here's your workout for Saturday, October 10, 2026:" — the canonical date.
    private static func extractBodyDate(from body: String) -> Date? {
        guard let (groups, _) = matchGroups(
            #"Here['’]s your workout for\s+([A-Za-z]+,\s+[A-Za-z]+\s+\d{1,2},\s+\d{4})"#,
            in: body
        ) else { return nil }
        return parseDate(groups[0], format: "EEEE, MMMM d, yyyy")
    }

    /// Lines that end the exercise section: nutrition block, sign-off, footer.
    ///
    /// Note: the TrueCoach template also uses "| ..." lines in the *header*
    /// boilerplate ("| You've received a workout. |"), so a bare "| " prefix
    /// must NOT be treated as the footer — those lines are simply ignored
    /// as header boilerplate before the first exercise label.
    private static func isFooterStart(_ line: String) -> Bool {
        line == "**"
            || line.lowercased() == "nutrition"
            || line.hasPrefix("- Your Coach,")
            || line.hasPrefix("[Open in TrueCoach]")
    }

    private static func parseNutrition(from body: String) -> ParsedNutrition? {
        func int(_ pattern: String) -> Int? {
            guard let (groups, _) = matchGroups(pattern, in: body) else { return nil }
            return Int(groups[0])
        }
        // \s spans the newlines in the raw block ("Protein:\n 155\n g").
        let nutrition = ParsedNutrition(
            proteinG: int(#"(?i)Protein:\s*(\d+)"#),
            carbsG: int(#"(?i)Carbs:\s*(\d+)"#),
            fatG: int(#"(?i)Fat:\s*(\d+)"#),
            calories: int(#"(?i)Total Calories:\s*(\d+)"#)
        )
        if nutrition.proteinG == nil, nutrition.carbsG == nil,
           nutrition.fatG == nil, nutrition.calories == nil {
            return nil
        }
        return nutrition
    }

    // MARK: - Regex / date helpers

    /// Capture groups (excluding group 0) for the first match, plus the
    /// full match range. Nil when there's no match.
    private static func matchGroups(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> (groups: [String], range: NSRange)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let groups = (1 ..< match.numberOfRanges).map { index -> String in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: text)
            else { return "" }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
        }
        return (groups, match.range)
    }

    private static func firstMatch(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func parseDate(_ string: String, format: String) -> Date? {
        let normalized = string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter.date(from: normalized)
    }
}
