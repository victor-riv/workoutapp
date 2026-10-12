import Foundation
import SwiftData

/// The user's gym setup: unit system, bar, collars and plate inventory.
/// Stored as a singleton row; the plate list is JSON-encoded so the
/// inventory stays flexible without extra tables.
@Model
final class GymProfile {
    var unitRaw: String
    var barWeight: Double
    /// Weight of one *pair* of collars; 0 when collars aren't used.
    var collarPairWeight: Double
    var inventoryData: Data

    init(
        unit: WeightUnit = .lb,
        barWeight: Double = PlateCalculator.standardBarLB,
        collarPairWeight: Double = 0,
        inventory: [PlateDenomination]? = nil
    ) {
        self.unitRaw = unit.rawValue
        self.barWeight = barWeight
        self.collarPairWeight = collarPairWeight
        let plates = inventory ?? PlateCalculator.defaultInventory(for: unit)
        self.inventoryData = (try? JSONEncoder().encode(plates)) ?? Data()
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: unitRaw) ?? .lb }
        set { unitRaw = newValue.rawValue }
    }

    var inventory: [PlateDenomination] {
        get {
            (try? JSONDecoder().decode([PlateDenomination].self, from: inventoryData))
                ?? PlateCalculator.defaultInventory(for: unit)
        }
        set {
            inventoryData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func makeCalculator() -> PlateCalculator {
        PlateCalculator(
            barWeight: barWeight,
            inventory: inventory,
            collarPairWeight: collarPairWeight
        )
    }

    /// Fetch the singleton, creating it with defaults on first launch.
    static func current(in context: ModelContext) -> GymProfile {
        let descriptor = FetchDescriptor<GymProfile>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = GymProfile()
        context.insert(profile)
        return profile
    }
}
