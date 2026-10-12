import XCTest
@testable import WorkoutTracker

final class BodyPartTests: XCTestCase {
    func testChest() {
        XCTAssertEqual(BodyPart.detect(name: "Barbell Bench Press").label, "Chest")
        XCTAssertEqual(BodyPart.detect(name: "Push-Up").label, "Chest")
        XCTAssertEqual(BodyPart.detect(name: "Cable Fly").label, "Chest")
    }

    func testBack() {
        XCTAssertEqual(BodyPart.detect(name: "Barbell Row").label, "Back")
        XCTAssertEqual(BodyPart.detect(name: "Pull-Up").label, "Back")
        XCTAssertEqual(BodyPart.detect(name: "Deadlift").label, "Back")
    }

    func testLegs() {
        XCTAssertEqual(BodyPart.detect(name: "Back Squat").label, "Legs")
        XCTAssertEqual(BodyPart.detect(name: "Leg Press").label, "Legs")
        XCTAssertEqual(BodyPart.detect(name: "Romanian Deadlift", notes: "hamstrings").label, "Legs")
    }

    func testShouldersBeforeGenericPress() {
        XCTAssertEqual(BodyPart.detect(name: "Overhead Press").label, "Shoulders")
        XCTAssertEqual(BodyPart.detect(name: "Lateral Raise").label, "Shoulders")
        // "Bench Press" must stay Chest even though it contains "press".
        XCTAssertEqual(BodyPart.detect(name: "Bench Press").label, "Chest")
    }

    func testArms() {
        XCTAssertEqual(BodyPart.detect(name: "Dumbbell Curl").label, "Arms")
        XCTAssertEqual(BodyPart.detect(name: "Tricep Pushdown").label, "Arms")
    }

    func testCore() {
        XCTAssertEqual(BodyPart.detect(name: "Hanging Leg Raise").label, "Core")
        XCTAssertEqual(BodyPart.detect(name: "Plank").label, "Core")
    }

    func testCardio() {
        XCTAssertEqual(BodyPart.detect(name: "Assault Bike", notes: "HR 120-140").label, "Cardio")
    }

    func testMobility() {
        XCTAssertEqual(BodyPart.detect(name: "Lower Body Mobility").label, "Mobility")
    }

    func testFullBody() {
        XCTAssertEqual(BodyPart.detect(name: "Power Clean").label, "Full Body")
    }

    func testDefault() {
        let part = BodyPart.detect(name: "Something Weird")
        XCTAssertEqual(part.label, "Workout")
        XCTAssertFalse(part.emoji.isEmpty)
    }

    func testNotesHelpDisambiguate() {
        // "Cable" alone would be ambiguous; the note clarifies.
        XCTAssertEqual(BodyPart.detect(name: "Cable Work", notes: "face pull").label, "Shoulders")
    }
}
