import XCTest
@testable import WorkoutTracker

/// Unit tests for the plate-loading solver.
///
/// Expectations were cross-checked against an independent Python prototype
/// of the same algorithm before being encoded here.
final class PlateCalculatorTests: XCTestCase {
    private var lb: PlateCalculator {
        PlateCalculator(
            barWeight: PlateCalculator.standardBarLB,
            inventory: PlateCalculator.defaultInventory(for: .lb)
        )
    }

    private var kg: PlateCalculator {
        PlateCalculator(
            barWeight: PlateCalculator.olympicBarKG,
            inventory: PlateCalculator.defaultInventory(for: .kg)
        )
    }

    // MARK: - Exact loads

    func testTwoPlates() {
        let result = lb.plates(for: 225)
        XCTAssertEqual(result.platesPerSide, [45, 45])
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.achievedWeight, 225, accuracy: 0.001)
    }

    func testOnePlate() {
        let result = lb.plates(for: 135)
        XCTAssertEqual(result.platesPerSide, [45])
        XCTAssertTrue(result.isExact)
    }

    func testMixedPlates() {
        // 185 = 45 bar + 2 × (45 + 25)
        let result = lb.plates(for: 185)
        XCTAssertEqual(result.platesPerSide, [45, 25])
        XCTAssertTrue(result.isExact)
    }

    func testKilograms() {
        // 100 = 20 bar + 2 × (25 + 15)
        let result = kg.plates(for: 100)
        XCTAssertEqual(result.platesPerSide, [25, 15])
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.achievedWeight, 100, accuracy: 0.001)
    }

    func testKilogramsSmall() {
        // 60 = 20 bar + 2 × 20
        let result = kg.plates(for: 60)
        XCTAssertEqual(result.platesPerSide, [20])
        XCTAssertTrue(result.isExact)
    }

    // MARK: - Inexact targets floor below, never above

    func testUnachievableFloorsBelowTarget() {
        // 137.5 needs 1.25 lb plates, which the default lb set lacks.
        let result = lb.plates(for: 137.5)
        XCTAssertEqual(result.platesPerSide, [45])
        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.achievedWeight, 135, accuracy: 0.001)
        XCTAssertEqual(result.shortfall, 2.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(result.achievedWeight, 137.5)
    }

    func testTargetBelowBarLoadsNothing() {
        let result = lb.plates(for: 40)
        XCTAssertTrue(result.platesPerSide.isEmpty)
        XCTAssertEqual(result.achievedWeight, 45, accuracy: 0.001)
    }

    // MARK: - Inventory limits are respected

    func testLimitedInventory() {
        let limited = PlateCalculator(
            barWeight: 45,
            inventory: [
                PlateDenomination(weight: 45, pairs: 1),
                PlateDenomination(weight: 35, pairs: 2),
                PlateDenomination(weight: 25, pairs: 2),
                PlateDenomination(weight: 10, pairs: 2),
                PlateDenomination(weight: 5, pairs: 2),
                PlateDenomination(weight: 2.5, pairs: 2),
            ]
        )
        // 315 = 45 + 2 × (45 + 35 + 35 + 10 + 10)
        let result = limited.plates(for: 315)
        XCTAssertEqual(result.platesPerSide, [45, 35, 35, 10, 10])
        XCTAssertTrue(result.isExact)
    }

    func testRunsOutOfBigPlates() {
        let scarce = PlateCalculator(
            barWeight: 45,
            inventory: [PlateDenomination(weight: 45, pairs: 1)]
        )
        // 225 wants 2×45 per side but only one pair exists → floors to 135.
        let result = scarce.plates(for: 225)
        XCTAssertEqual(result.platesPerSide, [45])
        XCTAssertEqual(result.achievedWeight, 135, accuracy: 0.001)
    }

    // MARK: - Collars

    func testCollarsCountTowardTotal() {
        let withCollars = PlateCalculator(
            barWeight: 45,
            inventory: PlateCalculator.defaultInventory(for: .lb),
            collarPairWeight: 5 // pair of 2.5 lb collars
        )
        // 137.5 − 45 − 5 = 87.5 → 43.75/side → 35 + 5 + 2.5 = 42.5/side
        let result = withCollars.plates(for: 137.5)
        XCTAssertEqual(result.platesPerSide, [35, 5, 2.5])
        XCTAssertEqual(result.achievedWeight, 135, accuracy: 0.001)
        XCTAssertEqual(result.collarPairWeight, 5, accuracy: 0.001)
    }

    // MARK: - Loading order & grouping

    func testPlatesAreHeaviestFirst() {
        let result = lb.plates(for: 225)
        XCTAssertEqual(result.platesPerSide, result.platesPerSide.sorted(by: >))
    }

    func testGroupedPlates() {
        let result = lb.plates(for: 225)
        let groups = result.groupedPlates
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].weight, 45, accuracy: 0.001)
        XCTAssertEqual(groups[0].count, 2)
    }
}
