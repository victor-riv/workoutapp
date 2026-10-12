import SwiftUI
import SwiftData

/// Set-by-set logging for one exercise. Weight fields come pre-filled with
/// the last-used weight; the user just adjusts and ticks sets off.
struct ExerciseDetailView: View {
    @Bindable var workoutExercise: WorkoutExercise

    var body: some View {
        List {
            if !workoutExercise.coachNotes.isEmpty {
                Section("Coach notes") {
                    Text(workoutExercise.coachNotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let prescribed = workoutExercise.prescribedWeight {
                Section {
                    // Email weights are in lb.
                    Text("Coach prescribed \(String(format: "%g", prescribed)) lb — pre-filled below; adjust to what you actually lift.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sets — \(workoutExercise.targetSets) × \(workoutExercise.targetReps)") {
                ForEach(workoutExercise.sortedSets) { set in
                    SetRowView(set: set)
                }
            }
        }
        .navigationTitle(workoutExercise.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One set row: weight + reps fields, a plate-calculator shortcut, and a
/// done toggle. Edits write straight through to SwiftData.
private struct SetRowView: View {
    @Environment(\.modelContext) private var context
    @Bindable var set: WorkoutSet

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var showingPlates = false

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(set.setNumber)")
                .font(.headline)
                .frame(width: 24)

            TextField("wt", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear(perform: seedFields)
                .onChange(of: weightText) { _, new in
                    set.weight = Double(new.replacingOccurrences(of: ",", with: "."))
                }

            Text(set.unit.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear(perform: seedFields)
                .onChange(of: repsText) { _, new in
                    set.reps = Int(new)
                }

            Spacer()

            Button {
                showingPlates = true
            } label: {
                Image(systemName: "scalemass")
            }
            .buttonStyle(.bordered)
            .disabled(parsedWeight == nil)

            Toggle("", isOn: $set.isCompleted)
                .labelsHidden()
        }
        .sheet(isPresented: $showingPlates) {
            NavigationStack {
                PlateCalculatorView(presetTarget: parsedWeight)
                    .navigationTitle("Plates for \(weightText) \(set.unit.rawValue)")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func seedFields() {
        if weightText.isEmpty, let weight = set.weight {
            weightText = String(format: "%g", weight)
        }
        if repsText.isEmpty, let reps = set.reps {
            repsText = String(reps)
        } else if repsText.isEmpty {
            // Default reps to the target when it's a plain number.
            let digits = set.targetReps.filter(\.isNumber)
            if Int(set.targetReps) != nil { repsText = digits }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: WorkoutExercise.self, WorkoutSet.self, Exercise.self,
        configurations: config
    )
    let exercise = Exercise(name: "Barbell Bench Press")
    let block = WorkoutExercise(order: 0, targetSets: 3, targetReps: "8", exercise: exercise)
    block.ensureSets(unit: .lb)
    return NavigationStack {
        ExerciseDetailView(workoutExercise: block)
    }
    .modelContainer(container)
}
