import SwiftUI
import SwiftData

/// A past workout day: its exercises with what was actually logged.
/// Tapping an exercise opens the same logging page used from Today.
struct HistoryDayView: View {
    @Bindable var day: WorkoutDay

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day.date)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title)
                        .font(.title2.bold())
                    Text("\(day.completedSetsCount) of \(day.totalSetsCount) sets done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Exercises") {
                ForEach(day.sortedExercises) { workoutExercise in
                    NavigationLink {
                        ExerciseDetailView(workoutExercise: workoutExercise)
                    } label: {
                        HistoryExerciseRow(workoutExercise: workoutExercise)
                    }
                }
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Exercise row showing the logged weights instead of the prescription.
private struct HistoryExerciseRow: View {
    let workoutExercise: WorkoutExercise

    private var loggedSummary: String {
        let done = workoutExercise.sortedSets.filter(\.isCompleted)
        guard !done.isEmpty else {
            return "Not logged"
        }
        let weights = done.compactMap(\.weight).map { String(format: "%g", $0) }
        let reps = done.compactMap(\.reps).map(String.init)
        if let unit = done.first?.unit {
            return "\(done.count) sets · \(weights.joined(separator: "/")) \(unit.rawValue) · \(reps.joined(separator: "/")) reps"
        }
        return "\(done.count) sets logged"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workoutExercise.exercise?.name ?? "Exercise")
                .font(.headline)
            Text(loggedSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ], inMemory: true)
}
