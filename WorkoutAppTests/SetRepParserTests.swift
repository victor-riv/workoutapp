import XCTest
@testable import WorkoutTracker

/// Unit tests for the coach-text set/rep parser.
///
/// `testTodaysW2D3Lines` is a regression fixture taken verbatim from the real
/// TrueCoach workout email for Sat 2026-10-10 (W2D3): it covers the mobility
/// ("x5-10/movement"), per-side ("3 x 10/side"), and timed ("20 minutes")
/// formats the parser previously mishandled.
final class SetRepParserTests: XCTestCase {

    // MARK: - Standard formats (existing behavior)

    func testSimpleSetRep() {
        assertParse("4x8", sets: 4, reps: "8")
        assertParse("4 x 8", sets: 4, reps: "8")
        assertParse("5×5", sets: 5, reps: "5")
    }

    func testRepRangeAndModifiers() {
        assertParse("4 x 8-10", sets: 4, reps: "8-10")
        assertParse("5×5 @ RPE 8", sets: 5, reps: "5")
        assertParse("3 x 10 RIR 2-3", sets: 3, reps: "10")
    }

    func testSetsOfFormat() {
        assertParse("3 sets of 10", sets: 3, reps: "10")
        assertParse("4 sets x 12", sets: 4, reps: "12")
    }

    func testAmrap() {
        assertParse("3 x AMRAP", sets: 3, reps: "AMRAP")
        assertParse("3 x amrap", sets: 3, reps: "AMRAP")
        assertParse("AMRAP", sets: 1, reps: "AMRAP")
    }

    // MARK: - Formats from the real coach email

    func testPerSideSuffixIsKept() {
        assertParse("3 x 10/side RIR 2-3", sets: 3, reps: "10/side")
        assertParse("3 x 8-12/leg", sets: 3, reps: "8-12/leg")
        assertParse("3 x 10 / side", sets: 3, reps: "10/side")
    }

    func testLeadingXPerUnitPrescription() {
        assertParse("x5-10/movement", sets: 1, reps: "5-10/movement")
        assertParse("x10/side", sets: 1, reps: "10/side")
    }

    func testTimedPrescriptionsGetOneSet() {
        assertParse("20 minutes", sets: 1, reps: "20 minutes")
        assertParse("10 min", sets: 1, reps: "10 min")
        assertParse("30 sec", sets: 1, reps: "30 sec")
        assertParse("20:00", sets: 1, reps: "20:00")
    }

    func testTimedDoesNotSwallowSetFormats() {
        // "10 x 5" starts with a digit too, but the "x" rules it out as timed.
        assertParse("10 x 5", sets: 10, reps: "5")
    }

    // MARK: - Regression fixture: real W2D3 email, Sat 2026-10-10

    func testTodaysW2D3Lines() {
        let cases: [(input: String, sets: Int, reps: String)] = [
            ("x5-10/movement", 1, "5-10/movement"),   // B) Lower Body Mobility
            ("3 x 15", 3, "15"),                      // C) Lying Leg Raise
            ("3 x 10 RIR 2-3", 3, "10"),              // D) Dumbbell Romanian Deadlift
            ("3 x 10/side RIR 2-3", 3, "10/side"),    // E) Single-leg Press
            ("3 x 15 RIR 2-3", 3, "15"),              // F) Machine Hip Abduction
            ("3 x 15 RIR 2-3", 3, "15"),              // G) Lying Leg Curl
            ("20 minutes", 1, "20 minutes"),          // H) Cardio of Choice
        ]
        for item in cases {
            assertParse(item.input, sets: item.sets, reps: item.reps)
        }
    }

    // MARK: - Fallback

    func testFallbackKeepsRawText() {
        assertParse("Pyramid up in weight", sets: 3, reps: "Pyramid up in weight")
    }

    func testEmpty() {
        assertParse("", sets: 3, reps: "—")
        assertParse("   ", sets: 3, reps: "—")
    }

    // MARK: - Helper

    private func assertParse(_ input: String, sets: Int, reps: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let parsed = SetRepParser.parse(input)
        XCTAssertEqual(parsed.sets, sets, "sets for '\(input)'", file: file, line: line)
        XCTAssertEqual(parsed.reps, reps, "reps for '\(input)'", file: file, line: line)
    }
}
