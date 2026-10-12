import SwiftUI
import SwiftData
import UIKit

/// Set-by-set logging for one exercise. Weight fields come pre-filled with
/// the last-used weight; the user just adjusts and ticks sets off.
///
/// Barbell lifts get a plate-calculator shortcut under the header.
/// Styled to match the Today tab: dark cards, cream poster header.
struct ExerciseDetailView: View {
    @Bindable var workoutExercise: WorkoutExercise

    @State private var showingPlates = false

    private var exerciseName: String {
        workoutExercise.exercise?.name ?? "Exercise"
    }

    /// Barbell heuristic: only show the plate calculator for lifts that
    /// are actually done with a barbell. Opt-in, not opt-out — a plain
    /// "Lying Leg Raise" must not get a Plates button.
    private var usesBarbell: Bool {
        let lower = exerciseName.lowercased()
        let notBarbell = ["dumbbell", "kettlebell", "machine", "cable", "smith",
                          "band", "bodyweight", "trx", "leg press"]
        if notBarbell.contains(where: lower.contains) { return false }
        if lower.contains("barbell") { return true }
        let barbellLifts = ["squat", "deadlift", "bench press", "overhead press",
                            "military press", "push press", "strict press",
                            "pendlay row", "clean", "snatch", "jerk",
                            "hip thrust", "good morning", "zercher"]
        return barbellLifts.contains(where: lower.contains)
    }

    private var platesPreset: Double? {
        // Prefer a weight already typed into a set, else the coach's prescription.
        workoutExercise.sortedSets.compactMap(\.weight).first
            ?? workoutExercise.prescribedWeight
    }

    /// Drops the keyboard when the user taps outside a text field.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(exerciseName)
                        .font(.poster(34))
                        .foregroundStyle(WorkoutTheme.cream)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                    if usesBarbell {
                        Button {
                            showingPlates = true
                        } label: {
                            Text("Plates")
                        }
                        .buttonStyle(.lime)
                    }
                }
                .padding(.top, 8)

                if !workoutExercise.coachNotes.isEmpty {
                    Text(workoutExercise.coachNotes)
                        .font(.body)
                        .foregroundStyle(WorkoutTheme.softText)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                if let prescribed = workoutExercise.prescribedWeight {
                    // Coach weights are in lb.
                    Text("Coach prescribed \(String(format: "%g", prescribed)) lb — pre-filled below; adjust to what you actually lift.")
                        .font(.subheadline)
                        .foregroundStyle(WorkoutTheme.grayText)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                Text("Sets — \(workoutExercise.targetSets) × \(workoutExercise.targetReps)")
                    .font(.poster(24))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(-0.5)
                    .padding(.top, 4)

                ForEach(workoutExercise.sortedSets) { set in
                    SetCardView(set: set)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .workoutTabStyle()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            // Tapping outside a field drops the keyboard.
            hideKeyboard()
        }
        .sheet(isPresented: $showingPlates) {
            NavigationStack {
                PlateCalculatorView(presetTarget: platesPreset)
                    .navigationTitle("Plates")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// One set as a dark card: number, weight + reps fields, done toggle.
/// Edits write straight through to SwiftData.
private struct SetCardView: View {
    @Bindable var set: WorkoutSet

    @State private var weightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Text("\(set.setNumber)")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 28)

            TextField("wt", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .padding(8)
                .background(WorkoutTheme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onAppear(perform: seedFields)
                .onChange(of: weightText) { _, new in
                    set.weight = Double(new.replacingOccurrences(of: ",", with: "."))
                }

            Text(set.unit.rawValue)
                .font(.caption)
                .foregroundStyle(WorkoutTheme.grayText)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(8)
                .background(WorkoutTheme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onAppear(perform: seedFields)
                .onChange(of: repsText) { _, new in
                    set.reps = Int(new)
                }

            Spacer()

            Toggle("", isOn: $set.isCompleted)
                .labelsHidden()
                .tint(WorkoutTheme.lime)
        }
        .padding(14)
        .background(WorkoutTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
