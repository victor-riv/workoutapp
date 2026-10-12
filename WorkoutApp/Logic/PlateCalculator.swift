import Foundation

/// Unit system for all weights in the calculator.
public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}

/// One plate denomination in the gym's inventory.
///
/// `pairs` is the number of *pairs* available. Plates are always loaded
/// symmetrically, so the solver consumes them one pair at a time
/// (one plate per side).
public struct PlateDenomination: Codable, Hashable, Sendable {
    public var weight: Double
    public var pairs: Int

    public init(weight: Double, pairs: Int) {
        self.weight = weight
        self.pairs = pairs
    }
}

/// The outcome of a plate calculation.
public struct PlateResult: Sendable {
    /// Plates loaded on ONE side, heaviest first (i.e. loading order).
    public let platesPerSide: [Double]
    /// Total weight actually achieved: bar + collars + both sides.
    public let achievedWeight: Double
    /// The target the user asked for.
    public let targetWeight: Double
    /// Weight of one pair of collars that was included, 0 when unused.
    public let collarPairWeight: Double

    /// True when the target was hit exactly (within rounding dust).
    public var isExact: Bool {
        abs(achievedWeight - targetWeight) < 0.005
    }

    /// `target - achieved`. Positive means we floored below the target
    /// because it wasn't exactly achievable; negative means the target
    /// was below the empty bar.
    public var shortfall: Double {
        targetWeight - achievedWeight
    }

    /// Plates grouped for display, e.g. [(45.0, 2), (25.0, 1)].
    public var groupedPlates: [(weight: Double, count: Int)] {
        var groups: [(Double, Int)] = []
        for plate in platesPerSide {
            if let last = groups.last, abs(last.0 - plate) < 0.0001 {
                groups[groups.count - 1].1 += 1
            } else {
                groups.append((plate, 1))
            }
        }
        return groups
    }
}

/// Computes which plates to load on each side of a barbell.
///
/// Policy: the solver **never exceeds the target** — when a target isn't
/// exactly achievable with the available plates it floors to the heaviest
/// load at or below the target and reports the shortfall. Plates are always
/// used in pairs (one per side) and larger denominations are preferred so
/// the bar carries as few plates as possible.
public struct PlateCalculator: Sendable {
    public var barWeight: Double
    public var inventory: [PlateDenomination]
    /// Weight of one *pair* of collars. 0 means collars are not used.
    /// Common: 5.0 lb for a pair of 2.5 lb collars.
    public var collarPairWeight: Double

    public init(
        barWeight: Double,
        inventory: [PlateDenomination],
        collarPairWeight: Double = 0
    ) {
        self.barWeight = barWeight
        self.inventory = inventory
        self.collarPairWeight = collarPairWeight
    }

    /// Solve for the given total target weight (bar included).
    public func plates(for targetWeight: Double) -> PlateResult {
        // Work in integer hundredths to avoid floating-point drift
        // (covers 2.5 lb, 1.25 kg and any custom plate).
        let scale = 100

        let perSide = (targetWeight - barWeight - collarPairWeight) / 2.0
        guard perSide >= 0 else {
            // Target is lighter than the empty bar: nothing to load.
            return PlateResult(
                platesPerSide: [],
                achievedWeight: barWeight,
                targetWeight: targetWeight,
                collarPairWeight: collarPairWeight
            )
        }

        let capacity = Int((perSide * Double(scale)).rounded())
        let denoms = inventory
            .filter { $0.weight > 0 && $0.pairs > 0 }
            .map { (weight: Int(($0.weight * Double(scale)).rounded()), pairs: $0.pairs) }
            .sorted { $0.weight > $1.weight }

        // Bounded knapsack: max plate weight per side within capacity,
        // respecting available pair counts. Memoized DFS is tiny here
        // (a handful of denominations), so this is effectively instant.
        struct MemoKey: Hashable {
            let index: Int
            let remaining: Int
        }
        var memo: [MemoKey: Int] = [:]

        func best(_ i: Int, _ remaining: Int) -> Int {
            if i >= denoms.count || remaining <= 0 { return 0 }
            let key = MemoKey(index: i, remaining: remaining)
            if let cached = memo[key] { return cached }
            let (weight, pairs) = denoms[i]
            var bestSum = best(i + 1, remaining) // take none of this denomination
            let maxTake = min(pairs, remaining / weight)
            var take = 1
            while take <= maxTake {
                let candidate = take * weight + best(i + 1, remaining - take * weight)
                if candidate > bestSum { bestSum = candidate }
                take += 1
            }
            memo[key] = bestSum
            return bestSum
        }

        // Reconstruct the choice, preferring the largest take of each
        // denomination that still achieves the optimum (fewer, bigger plates).
        var chosen: [Int] = []
        var remaining = capacity
        for i in denoms.indices {
            let (weight, pairs) = denoms[i]
            let maxTake = min(pairs, remaining / weight)
            var picked = 0
            var take = maxTake
            while take >= 0 {
                if take * weight + best(i + 1, remaining - take * weight) == best(i, remaining) {
                    picked = take
                    break
                }
                take -= 1
            }
            for _ in 0 ..< picked { chosen.append(weight) }
            remaining -= picked * weight
        }

        let platesPerSide = chosen
            .sorted(by: >)
            .map { Double($0) / Double(scale) }
        let loadedPerSide = platesPerSide.reduce(0.0, +)
        let achieved = ((barWeight + collarPairWeight + 2 * loadedPerSide) * Double(scale)).rounded()
            / Double(scale)

        return PlateResult(
            platesPerSide: platesPerSide,
            achievedWeight: achieved,
            targetWeight: targetWeight,
            collarPairWeight: collarPairWeight
        )
    }
}

// MARK: - Defaults

public extension PlateCalculator {
    /// Standard 45 lb Olympic bar.
    static var standardBarLB: Double { 45 }
    /// Standard 20 kg Olympic bar.
    static var olympicBarKG: Double { 20 }

    /// Sensible default inventory for a commercial gym.
    static func defaultInventory(for unit: WeightUnit, pairsPerDenomination: Int = 8) -> [PlateDenomination] {
        let denominations: [Double]
        switch unit {
        case .lb:
            denominations = [45, 35, 25, 10, 5, 2.5]
        case .kg:
            denominations = [25, 20, 15, 10, 5, 2.5, 1.25]
        }
        return denominations.map { PlateDenomination(weight: $0, pairs: pairsPerDenomination) }
    }
}
