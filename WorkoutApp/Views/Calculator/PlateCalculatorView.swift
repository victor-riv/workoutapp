import SwiftUI
import SwiftData

/// "What do I load for X?" — target weight in, per-side plates out.
/// Defaults come from the gym profile; everything is adjustable inline.
struct PlateCalculatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var targetText: String
    @State private var unit: WeightUnit = .lb
    @State private var barWeight: Double = PlateCalculator.standardBarLB
    @State private var useCollars = false
    @State private var inventory: [PlateDenomination] = []

    init(presetTarget: Double? = nil) {
        _targetText = State(initialValue: presetTarget.map { String(format: "%g", $0) } ?? "")
    }

    private var target: Double {
        Double(targetText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var collarPairWeight: Double {
        guard useCollars else { return 0 }
        return unit == .lb ? 5 : 2.5
    }

    private var calculator: PlateCalculator {
        PlateCalculator(
            barWeight: barWeight,
            inventory: inventory,
            collarPairWeight: collarPairWeight
        )
    }

    private var result: PlateResult? {
        guard target > 0 else { return nil }
        return calculator.plates(for: target)
    }

    var body: some View {
        Form {
            Section("Target") {
                HStack {
                    TextField("Weight", text: $targetText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                    Picker("Unit", selection: $unit) {
                        Text("lb").tag(WeightUnit.lb)
                        Text("kg").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }

            Section("Bar") {
                Picker("Bar weight", selection: $barWeight) {
                    Text("45 lb").tag(45.0)
                    Text("20 kg").tag(20.0)
                    Text("35 lb").tag(35.0)
                    Text("15 kg").tag(15.0)
                }
                .pickerStyle(.segmented)
                Toggle("Collars", isOn: $useCollars)
            }

            if let result {
                resultSection(result)
            } else {
                Section {
                    Text("Enter a target weight to see the plates.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Plate Calculator")
        .task { loadProfile() }
        .onChange(of: unit) { _, _ in applyUnitDefaults() }
    }

    // MARK: - Result

    private func resultSection(_ result: PlateResult) -> some View {
        Section("Load per side") {
            if result.platesPerSide.isEmpty {
                Text("Just the bar — target is at or below bar weight.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.groupedPlates, id: \.weight) { group in
                    HStack {
                        PlateChip(weight: group.weight, unit: unit)
                        Spacer()
                        Text("× \(group.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("Total")
                Spacer()
                Text("\(format(result.achievedWeight)) \(unit.rawValue)")
                    .font(.headline)
            }

            if !result.isExact {
                if result.shortfall > 0 {
                    Label(
                        "Not exactly achievable — closest below target is \(format(result.achievedWeight)) \(unit.rawValue) (\(format(result.shortfall)) under).",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.footnote)
                } else {
                    Label("Target is below the empty bar.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            } else {
                Label("Exact — load it up.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }
        }
    }

    // MARK: - Profile

    private func loadProfile() {
        let profile = GymProfile.current(in: context)
        unit = profile.unit
        barWeight = profile.barWeight
        inventory = profile.inventory
        useCollars = profile.collarPairWeight > 0
    }

    /// When the user flips units, swap to that unit's bar + plates.
    private func applyUnitDefaults() {
        barWeight = unit == .lb ? PlateCalculator.standardBarLB : PlateCalculator.olympicBarKG
        inventory = PlateCalculator.defaultInventory(for: unit)
    }

    private func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

/// A little plate badge, e.g. "45".
private struct PlateChip: View {
    var weight: Double
    var unit: WeightUnit

    var body: some View {
        Text("\(String(format: "%g", weight))")
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.14))
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        PlateCalculatorView(presetTarget: 225)
    }
    .modelContainer(for: GymProfile.self, inMemory: true)
}
