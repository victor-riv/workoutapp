import SwiftUI
import SwiftData

struct PasteWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pastedText = ""
    @State private var parseError: String?
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pastedText).frame(minHeight: 280).font(.body.monospaced())
                } header: { Text("Workout text") } footer: {
                    Text("Paste the workout text, starting around the A) / B) lines. It's logged under today.")
                }
                Section {
                    Button("Import Workout") { importAndSave() }
                        .buttonStyle(.lime)
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Importing again today replaces the workout — your logged sets are kept.")
                }
                if let parseError {
                    Section { Text(parseError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Paste Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
    private func importAndSave() {
        parseError = nil
        guard let parsed = EmailWorkoutParser.parseMessage(subject: "", body: pastedText) else {
            parseError = "Couldn't find a workout in that text. Make sure you pasted the exercises, starting around the A) / B) lines."
            return
        }
        guard !parsed.exercises.isEmpty else {
            parseError = "No exercises found — try pasting more of the workout text."
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var imported = parsed.toImportedWorkout(messageID: "paste-\(formatter.string(from: today))")
        imported.date = today
        WorkoutImporter.importWorkout(imported, into: context)
        dismiss()
    }
}

#Preview {
    PasteWorkoutView()
        .modelContainer(for: [Exercise.self, WorkoutDay.self, WorkoutExercise.self, WorkoutSet.self, GymProfile.self], inMemory: true)
}
