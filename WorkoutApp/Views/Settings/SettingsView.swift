import SwiftUI
import SwiftData

/// Gmail import sign-in and the gym profile (bar, collars, plate inventory).
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [GymProfile]

    @StateObject private var googleAuth = GoogleAuthProvider.shared
    @State private var isConnecting = false
    @State private var authMessage: String?
    @State private var isBackfilling = false
    @State private var backfillMessage: String?
    @State private var inventory: [PlateDenomination] = []

    private var profile: GymProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                gmailSection
                if let profile {
                    gymSection(profile)
                }
            }
            .navigationTitle("Settings")
            .task { ensureProfile() }
        }
    }

    // MARK: - Gmail import

    private var gmailSection: some View {
        Section {
            if ServiceFactory.useMock {
                Label(
                    "Developer mode: using mock workout data. Set `ServiceFactory.useMock = false` after the Google OAuth client is configured (see BUILD_CHECKLIST.md).",
                    systemImage: "hammer"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if googleAuth.isSignedIn {
                LabeledContent("Gmail account", value: googleAuth.userEmail ?? "")
                Button {
                    backfill()
                } label: {
                    if isBackfilling {
                        ProgressView()
                    } else {
                        Text("Backfill last 30 days")
                    }
                }
                .disabled(isBackfilling)
                if let backfillMessage {
                    Text(backfillMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect Gmail", role: .destructive) {
                    googleAuth.signOut()
                }
            } else {
                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text("Connect Gmail")
                    }
                }
                .disabled(isConnecting)
                if let authMessage {
                    Text(authMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Workout import")
        } footer: {
            Text("WorkoutTracker reads only your TrueCoach workout emails (from swoletron@truecoach.co) to import the day's workout. Requested scope: gmail.readonly. Sign-in happens in Google's own screen — your Google password never touches this app.")
        }
    }

    private func connect() {
        isConnecting = true
        authMessage = nil
        Task {
            do {
                try await googleAuth.signIn()
                authMessage = "Connected. Pull today's workout from the Today tab."
            } catch {
                authMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    /// Import the last 30 days of workout emails so "last weight"
    /// suggestions work from day one.
    private func backfill() {
        isBackfilling = true
        backfillMessage = nil
        Task {
            do {
                let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                let workouts = try await ServiceFactory.makeService().fetchWorkouts(since: since)
                for workout in workouts {
                    WorkoutImporter.importWorkout(workout, into: context)
                }
                backfillMessage = workouts.isEmpty
                    ? "No workout emails found in the last 30 days."
                    : "Imported \(workouts.count) workout\(workouts.count == 1 ? "" : "s")."
            } catch {
                backfillMessage = error.localizedDescription
            }
            isBackfilling = false
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
