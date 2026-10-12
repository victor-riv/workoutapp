import XCTest
@testable import WorkoutTracker

/// Unit tests for the TrueCoach email parser.
///
/// `testFullW2D3Body` is a regression fixture using the verbatim body of the
/// real workout email for Sat 2026-10-10 (W2D3). The synthetic W2D1/W2D2
/// bodies reconstruct the real emails' shapes from the parsed fixtures in
/// `EmailImport/workouts-2026-W2.json`, covering the formats those days
/// introduced: ambiguous weight x reps, multi-line back-off sets, embedded
/// exercise names, sub-movement lines, supersets, and intervals.
final class EmailWorkoutParserTests: XCTestCase {

    // MARK: - Subjects

    func testWorkoutSubjectParses() {
        let parsed = EmailWorkoutParser.parseSubject(
            "[TrueCoach] Victor , here's your workout for W2D3 for Saturday Oct 10, 2026"
        )
        XCTAssertFalse(parsed.isMissedReminder)
        XCTAssertEqual(parsed.weekDayCode, "W2D3")
        XCTAssertTrue(dateComponents(of: parsed.date) == (2026, 10, 10))
    }

    func testSubjectWithDoubleSpaceInDayParses() {
        // Real subject: "Tuesday Oct  6, 2026" (two spaces).
        let parsed = EmailWorkoutParser.parseSubject(
            "[TrueCoach] Victor , here's your workout for W2D1 for Tuesday Oct  6, 2026"
        )
        XCTAssertEqual(parsed.weekDayCode, "W2D1")
        XCTAssertTrue(dateComponents(of: parsed.date) == (2026, 10, 6))
    }

    func testMissedWorkoutSubjectIsSkipped() {
        let parsed = EmailWorkoutParser.parseSubject(
            "[TrueCoach] You missed your workout for Saturday Oct 10, 2026"
        )
        XCTAssertTrue(parsed.isMissedReminder)
        XCTAssertNil(EmailWorkoutParser.parseMessage(subject: "[TrueCoach] You missed your workout for Saturday Oct 10, 2026", body: "anything"))
    }

    // MARK: - Prescription formats (one line per case)

    func testSetsReps() {
        let line = parseSingleLine("3 x 15")
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "15")
        XCTAssertFalse(line?.isAmbiguous ?? true)
    }

    func testSetsRepsRIR() {
        let line = parseSingleLine("3 x 10 RIR 2-3")
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "10")
        XCTAssertEqual(line?.rir, "2-3")
    }

    func testPerSide() {
        let line = parseSingleLine("3 x 10/side RIR 2-3")
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "10/side")
        XCTAssertEqual(line?.rir, "2-3")
    }

    func testPerEach() {
        let line = parseSingleLine("3 x 10/ea RIR 2-3")
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "10/ea")
    }

    func testTimeUnderTension() {
        let line = parseSingleLine("3 x 30s")
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "30s")
    }

    func testRepsPerMovement() {
        let line = parseSingleLine("x5-10/movement")
        XCTAssertEqual(line?.sets, 1)
        XCTAssertEqual(line?.reps, "5-10/movement")
    }

    func testWeightSetsReps() {
        let line = parseSingleLine("155 x 2 x 8")
        XCTAssertEqual(line?.weight, 155)
        XCTAssertEqual(line?.sets, 2)
        XCTAssertEqual(line?.reps, "8")
        XCTAssertFalse(line?.isAmbiguous ?? true)
    }

    func testAmbiguousWeightRepsIsFlaggedNotGuessed() {
        // "115 x 3": 115 lb x 3 reps, set count unknown — never guessed.
        let line = parseSingleLine("115 x 3")
        XCTAssertEqual(line?.weight, 115)
        XCTAssertEqual(line?.reps, "3")
        XCTAssertNil(line?.sets)
        XCTAssertTrue(line?.isAmbiguous ?? false)
        XCTAssertEqual(line?.rawText, "115 x 3")
    }

    func testSmallLeadingNumberIsSetsNotWeight() {
        // "3 x 15" must stay sets x reps even though it matches the
        // weight-led shape — the > 12 rule separates the two.
        let line = parseSingleLine("3 x 15")
        XCTAssertNil(line?.weight)
        XCTAssertEqual(line?.sets, 3)
        XCTAssertEqual(line?.reps, "15")
    }

    // MARK: - Multi-line prescriptions (W2D1 shape)

    func testMultiLineBackOffSets() {
        let exercise = parseBody("""
        **W2D1**
        **E) TnG Bench Press**
        115 x 3
        100 x 3 x 5
        """)
        XCTAssertEqual(exercise?.prescriptionLines.count, 2)
        let first = exercise?.prescriptionLines[0]
        XCTAssertTrue(first?.isAmbiguous ?? false)
        XCTAssertNil(first?.sets)
        let second = exercise?.prescriptionLines[1]
        XCTAssertEqual(second?.weight, 100)
        XCTAssertEqual(second?.sets, 3)
        XCTAssertEqual(second?.reps, "5")
    }

    func testAmbiguousFirstLineSurfacedInImportNotes() {
        let exercise = parseBody("""
        **W2D1**
        **E) TnG Bench Press**
        115 x 3
        100 x 3 x 5
        """)
        let workout = ParsedWorkout(weekDayCode: "W2D1", date: nil, exercises: [exercise!], nutrition: nil)
        let imported = workout.toImportedWorkout(messageID: "test")
        let block = imported.blocks.first
        // 3 set rows as a neutral fallback, raw text preserved in the notes.
        XCTAssertEqual(block?.targetSets, 3)
        XCTAssertEqual(block?.targetReps, "3")
        XCTAssertTrue(block?.coachNotes.contains("115 x 3") ?? false)
        XCTAssertTrue(block?.coachNotes.contains("Also: 100 x 3 x 5") ?? false)
    }

    // MARK: - Embedded names, sub-lines, supersets (W2D2 shape)

    func testEmbeddedExerciseName() {
        let exercise = parseBody("""
        **W2D2**
        **B) Upper Back Prep**
        ITYW Raise x 10/ea
        """)
        XCTAssertEqual(exercise?.name, "ITYW Raise")
        XCTAssertEqual(exercise?.prescriptionLines.first?.sets, 1)
        XCTAssertEqual(exercise?.prescriptionLines.first?.reps, "10/ea")
    }

    func testSubMovementLinesBecomeNotes() {
        let exercise = parseBody("""
        **W2D2**
        **E) Dumbbell Shoulder 3-way Raise**
        3 x 10/ea RIR 2-3
        Front
        Lateral
        Rear
        """)
        XCTAssertEqual(exercise?.prescriptionLines.count, 1)
        XCTAssertEqual(exercise?.prescriptionLines.first?.reps, "10/ea")
        XCTAssertEqual(exercise?.notes, ["Front", "Lateral", "Rear"])
    }

    func testSupersetPairingDetected() {
        let workout = EmailWorkoutParser.parseMessage(subject: "x", body: """
        **W2D2**
        **H1) Alternating Dumbbell Curl**
        3 x 10/side RIR 2-3
        **H2) Single-arm Tricep Pushdown**
        3 x 10/side RIR 2-3
        """)
        let labels = workout?.exercises.map(\.label)
        XCTAssertEqual(labels, ["H1", "H2"])
        XCTAssertEqual(workout?.exercises.map(\.supersetGroup), ["H", "H"])
        let imported = workout!.toImportedWorkout(messageID: "test")
        for block in imported.blocks {
            XCTAssertTrue(block.coachNotes.contains("Superset: H1 + H2"))
        }
    }

    // MARK: - Cardio & assessment

    func testCardioDuration() {
        let exercise = parseBody("""
        **W2D3**
        **H) Cardio of Choice**
        20 minutes
        HR 120-140
        """)
        XCTAssertEqual(exercise?.kind, .cardio)
        XCTAssertEqual(exercise?.prescriptionLines.first?.reps, "20 minutes")
        XCTAssertEqual(exercise?.notes, ["HR 120-140"])
    }

    func testIntervalsKeptVerbatim() {
        let exercise = parseBody("""
        **W2D2**
        **I) Run Interval**
        30 seconds sprint, 2:30 minute walk - 5 rounds
        """)
        XCTAssertEqual(exercise?.kind, .cardio)
        XCTAssertEqual(
            exercise?.prescriptionLines.first?.reps,
            "30 seconds sprint, 2:30 minute walk - 5 rounds"
        )
    }

    func testAssessmentBlock() {
        let exercise = parseBody("""
        **W2D1**
        **A) TRAC Report**
        Push: 1 (no soreness) --> 5 (extremely sore)
        Overall Readiness: 1 (fully recovered) --> 5 (no recovery)
        Add all of your scores together and add to the metric
        """)
        XCTAssertEqual(exercise?.kind, .assessment)
        XCTAssertTrue(exercise?.prescriptionLines.isEmpty ?? false)
        XCTAssertEqual(exercise?.notes.count, 3)
    }

    // MARK: - Full W2D3 regression (verbatim real email body)

    func testFullW2D3Body() {
        let workout = EmailWorkoutParser.parseMessage(
            subject: "[TrueCoach] Victor , here's your workout for W2D3 for Saturday Oct 10, 2026",
            body: w2d3Body
        )
        XCTAssertEqual(workout?.weekDayCode, "W2D3")
        XCTAssertTrue(dateComponents(of: workout?.date) == (2026, 10, 10))
        let exercises = workout?.exercises ?? []
        XCTAssertEqual(exercises.map(\.label), ["A", "B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(exercises.map(\.name), [
            "TRAC Report",
            "Lower Body Mobility",
            "Lying Leg Raise",
            "Dumbbell Romanian Deadlift",
            "Single-leg Press",
            "Machine Hip Abduction",
            "Lying Leg Curl",
            "Cardio of Choice",
        ])

        // Spot-check the interesting blocks.
        XCTAssertEqual(exercises[0].kind, .assessment)
        XCTAssertEqual(exercises[1].kind, .mobility)
        XCTAssertEqual(exercises[1].prescriptionLines.first?.reps, "5-10/movement")
        XCTAssertEqual(exercises[3].prescriptionLines.first?.rir, "2-3")
        XCTAssertEqual(exercises[4].prescriptionLines.first?.reps, "10/side")
        XCTAssertEqual(exercises[7].kind, .cardio)

        // Nutrition block.
        XCTAssertEqual(workout?.nutrition?.summary, "P 155g · C 275g · F 65g · 2305 kcal")
    }

    func testW2D3MapsToImportModel() {
        let workout = EmailWorkoutParser.parseMessage(
            subject: "[TrueCoach] Victor , here's your workout for W2D3 for Saturday Oct 10, 2026",
            body: w2d3Body
        )!
        let imported = workout.toImportedWorkout(messageID: "1a1240c656f8292f")
        XCTAssertEqual(imported.sourceID, "W2D3")
        XCTAssertEqual(imported.title, "Workout W2D3")
        XCTAssertEqual(imported.nutritionSummary, "P 155g · C 275g · F 65g · 2305 kcal")
        XCTAssertEqual(imported.blocks.count, 8)
        let deadlift = imported.blocks[3]
        XCTAssertEqual(deadlift.exerciseName, "Dumbbell Romanian Deadlift")
        XCTAssertEqual(deadlift.targetSets, 3)
        XCTAssertEqual(deadlift.targetReps, "10")
        XCTAssertTrue(deadlift.coachNotes.contains("RIR 2-3"))
        let cardio = imported.blocks[7]
        XCTAssertEqual(cardio.kind, .cardio)
        XCTAssertTrue(cardio.coachNotes.contains("HR 120-140"))
    }

    // MARK: - Plain-text paste (no ** markers, no subject, no date)

    /// Victor's actual paste format: plain "B) Name" labels, prescription on
    /// the next line, no email headers. Date comes from the log date, not the text.
    func testPlainTextPasteParses() {
        let body = """
            B) Lower Body Mobility

            x5-10/movement

            C) Lying Leg Raise

            3 x 15

            D) Dumbbell Romanian Deadlift

            3 x 10 RIR 2-3

            E) Single-leg Press

            3 x 10/side RIR 2-3

            F) Machine Hip Abduction

            3 x 15 RIR 2-3

            G) Lying Leg Curl

            3 x 15 RIR 2-3

            H) Cardio of Choice

            20 minutes
            HR 120-140
            """
        let workout = EmailWorkoutParser.parseMessage(subject: "", body: body)!
        XCTAssertEqual(workout.exercises.map(\.label), ["B", "C", "D", "E", "F", "G", "H"])
        XCTAssertEqual(workout.exercises.map(\.name), [
            "Lower Body Mobility",
            "Lying Leg Raise",
            "Dumbbell Romanian Deadlift",
            "Single-leg Press",
            "Machine Hip Abduction",
            "Lying Leg Curl",
            "Cardio of Choice",
        ])
        let mobility = workout.exercises[0]
        XCTAssertEqual(mobility.prescriptionLines.first?.reps, "5-10/movement")
        XCTAssertEqual(mobility.prescriptionLines.first?.sets, 1)
        let deadlift = workout.exercises[2]
        XCTAssertEqual(deadlift.prescriptionLines.first?.sets, 3)
        XCTAssertEqual(deadlift.prescriptionLines.first?.reps, "10")
        XCTAssertEqual(deadlift.prescriptionLines.first?.rir, "2-3")
        let press = workout.exercises[3]
        XCTAssertEqual(press.prescriptionLines.first?.reps, "10/side")
        let cardio = workout.exercises[6]
        XCTAssertEqual(cardio.kind, .cardio)
        // No date in the text — the caller logs it under today.
        XCTAssertNil(workout.date)
        XCTAssertNil(workout.weekDayCode)
    }

    // MARK: - GmailService helpers (no network)

    func testBase64URLDecoding() {
        // "Hello" as base64url, no padding.
        XCTAssertEqual(GmailService.decodeBase64URL("SGVsbG8"), "Hello")
        // URL-safe alphabet (- and _): "?>?>" is Pz4+Pg== in base64.
        XCTAssertEqual(GmailService.decodeBase64URL("Pz4-Pg"), "?>?>")
        XCTAssertNil(GmailService.decodeBase64URL("!!!not-base64!!!"))
    }

    func testStripHTML() {
        let text = GmailService.stripHTML("<p>Hello<br/>World</p>")
        XCTAssertTrue(text.contains("Hello"))
        XCTAssertTrue(text.contains("World"))
        XCTAssertFalse(text.contains("<"))
        XCTAssertEqual(GmailService.stripHTML("Fish &amp; Chips"), "Fish & Chips")
    }

    func testParseEmailDate() {
        let date = GmailService.parseEmailDate("Sat, 10 Oct 2026 04:22:30 +0000")
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        // 04:22 UTC = 00:22 EDT.
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 0)
    }

    // MARK: - Helpers

    /// Parse a single prescription line inside a minimal workout body.
    private func parseSingleLine(_ line: String) -> ParsedPrescriptionLine? {
        parseBody("""
        **W2D3**
        **A) Test Exercise**
        \(line)
        """)?.prescriptionLines.first
    }

    private func parseBody(_ body: String) -> ParsedExercise? {
        EmailWorkoutParser.parseMessage(subject: "test", body: body)?.exercises.first
    }

    private func dateComponents(of date: Date?) -> (Int, Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day], from: date!)
        return (c.year!, c.month!, c.day!)
    }

    /// Verbatim body of the real W2D3 email (Sat 2026-10-10), minus the
    /// SendGrid footer links.
    private var w2d3Body: String {
        """
        TrueCoach Email

        | You've received a workout. |

        | Here's your training |

         Hey Victor ,

         Here's your workout for Saturday, October 10, 2026:

        **W2D3**
        **A) TRAC Report**
        This is an assessment to help gauge your current recovery status between workouts. Be as honest as possible with how you feel for best results!

        Push: 1 (no soreness) --> 5 (extremely sore)

        Legs: 1 (no soreness) --> 5 (extremely sore)

        Pull: 1 (no soreness) --> 5 (extremely sore)

        Overall Readiness: 1 (fully recovered) --> 5 (no recovery)

        Add all of your scores together and add to the metric
        **B) Lower Body Mobility**
        x5-10/movement
        **C) Lying Leg Raise**
        3 x 15
        **D) Dumbbell Romanian Deadlift**
        3 x 10 RIR 2-3
        **E) Single-leg Press**
        3 x 10/side RIR 2-3
        **F) Machine Hip Abduction**
        3 x 15 RIR 2-3
        **G) Lying Leg Curl**
        3 x 15 RIR 2-3
        **H) Cardio of Choice**
        20 minutes

        HR 120-140

         **
         Nutrition
        **
        -
         Protein:
         155
         g

        -
         Carbs:
         275
         g

        -
         Fat:
         65
         g

        -
         Total Calories:
         2305

         - Your Coach,

         Jonathan Renninger
        """
    }
}
