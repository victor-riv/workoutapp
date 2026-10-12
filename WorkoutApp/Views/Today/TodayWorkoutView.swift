import SwiftUI
import SwiftData

/// The home tab: today's programmed workout, imported from the coach's
/// TrueCoach email via Gmail. The user only fills in weights — everything
/// else is pre-populated.
struct TodayWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]

    @State private var isImporting = false
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var showingPaste = false

    private var today: WorkoutDay? {
        days.first { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let day = today {
                    workoutList(day)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: importToday) {
                        if isImporting {
                            ProgressView()
                        } else {
                            Label("Import", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isImporting)
                }
            }
            .alert("Import failed", isPresented: $showingImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error.")
            }
            .sheet(isPresented: $showingPaste) {
                PasteWorkoutView()
            }
        }
    }

    // MARK: - Workout list

    private func workoutList(_ day: WorkoutDay) -> some View {
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
                        ExerciseRowView(workoutExercise: workoutExercise)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No workout yet", systemImage: "dumbbell")
        } description: {
            Text("Paste today's TrueCoach email and the app will parse it into a workout.")
        } actions: {
            Button("Paste workout email") {
                showingPaste = true
            }
            .buttonStyle(.borderedProminent)
            Button(action: importToday) {
                if isImporting {
                    ProgressView()
                } else {
                    Text("Import from Gmail")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isImporting)
        }
    }

    // MARK: - Import

    private func importToday() {
        isImporting = true
        Task {
            do {
                let service = ServiceFactory.makeService()
                if let workout = try await service.fetchTodaysWorkout() {
                    WorkoutImporter.importWorkout(workout, into: context)
                } else {
                    importError = ImportError.noWorkoutToday.localizedDescription
                    showingImportError = true
                }
            } catch {
                // ImportError.notSignedIn already reads
                // "Connect your Gmail in Settings first."
                importError = error.localizedDescription
                showingImportError = true
            }
            isImporting = false
        }
    }
}

/// One row in the workout list: name, prescription, and the last-weight chip.
private struct ExerciseRowView: View {
    @Environment(\.modelContext) private var context
    let workoutExercise: WorkoutExercise

    @State private var suggestion: WeightSuggestion?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workoutExercise.exercise?.name ?? "Exercise")
                .font(.headline)
            HStack {
                Text("\(workoutExercise.targetSets) × \(workoutExercise.targetReps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let suggestion {
                    Text("Last: \(formatWeight(suggestion.weight)) \(suggestion.unit.rawValue)")
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            let done = workoutExercise.sets.filter(\.isCompleted).count
            if done > 0 {
                Text("\(done)/\(workoutExercise.sets.count) sets logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task {
            if let name = workoutExercise.exercise?.normalizedName {
                suggestion = WeightSuggestionService.suggestion(for: name, in: context)
            }
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        String(format: "%g", weight)
    }
}

#Preview {
    TodayWorkoutView()
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ], inMemory: true)
}
