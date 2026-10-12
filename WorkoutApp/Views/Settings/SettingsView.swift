import SwiftUI
import SwiftData

/// The gym profile (bar, collars, plate inventory).
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [GymProfile]

    @State private var inventory: [PlateDenomination] = []

    private var profile: GymProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                if let profile {
                    gymSection(profile)
                }
            }
            .navigationTitle("Settings")
            .task { ensureProfile() }
        }
    }

    // MARK: - Gym profile

    private func gymSection(_ profile: GymProfile) -> some View {
        @Bindable var profile = profile
        return Group {
            Section("Gym") {
                Picker("Units", selection: $profile.unitRaw) {
                    Text("Pounds (lb)").tag(WeightUnit.lb.rawValue)
                    Text("Kilograms (kg)").tag(WeightUnit.kg.rawValue)
                }
                HStack {
                    Text("Bar weight")
                    Spacer()
                    TextField("45", value: $profile.barWeight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(profile.unit.rawValue)
                        .foregroundStyle(.secondary)
                }
                Toggle("Use collars", isOn: Binding(
                    get: { profile.collarPairWeight > 0 },
                    set: { profile.collarPairWeight = $0 ? (profile.unit == .lb ? 5 : 2.5) : 0 }
                ))
            }
            Section {
                ForEach(inventory.indices, id: \.self) { index in
                    HStack {
                        Text("\(String(format: "%g", inventory[index].weight)) \(profile.unit.rawValue)")
                        Spacer()
                        Stepper("Pairs: \(inventory[index].pairs)", value: $inventory[index].pairs, in: 0 ... 12)
                    }
                }
                .onChange(of: inventory) { _, new in
                    profile.inventory = new
                }
                Button("Reset to gym defaults", role: .destructive) {
                    let defaults = PlateCalculator.defaultInventory(for: profile.unit)
                    inventory = defaults
                    profile.inventory = defaults
                }
            } header: {
                Text("Plate inventory")
            } footer: {
                Text("Pairs available at your gym. The calculator never plans more plates than you have.")
            }
        }
    }

    private func ensureProfile() {
        let profile = GymProfile.current(in: context)
        if inventory.isEmpty {
            inventory = profile.inventory
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: GymProfile.self, inMemory: true)
}
