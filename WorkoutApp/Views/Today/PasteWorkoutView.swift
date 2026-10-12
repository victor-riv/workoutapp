import SwiftUI
import SwiftData

/// Paste-first import: copy the workout text and paste it here.
/// The workout is logged under today's date — no subject, no sign-in.
/// Pasting again the same day updates the workout.
struct PasteWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var preview: ParsedWorkout?
    @State private var parseError: String?

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 280)
                        .font(.body.monospaced())
                } header: {
                    Text("Workout text")
                } footer: {
                    Text("Paste the workout text, starting around the A) / B) lines. It's logged under today.")
                }

                Section {
                    Button("Import Workout") { importWorkout() }
                        .buttonStyle(.lime)
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let preview {
                    Section("Preview — \(preview.exercises.count) exercises") {
                        ForEach(preview.exercises, id: \.label) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(exercise.label)) \(exercise.name)")
                                    .font(.headline)
                                Text(exercise.prescriptionLines.map(\.rawText).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section {
                        Button("Save Workout") { save(preview) }
                            .buttonStyle(.lime)
                    } footer: {
                        Text("Saving again today replaces the workout — your logged sets are kept.")
                    }
                }

                if let parseError {
                    Section {
                        Text(parseError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Paste Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Import & save

    private func importWorkout() {
        parseError = nil
        preview = nil
        guard let parsed = EmailWorkoutParser.parseMessage(subject: "", body: pastedText) else {
            parseError = "Couldn't find a workout in that text. Make sure you pasted the exercises, starting around the A) / B) lines."
            return
        }
        guard !parsed.exercises.isEmpty else {
            parseError = "No exercises found — try pasting more of the workout text."
            return
        }
        preview = parsed
    }

    private func save(_ parsed: ParsedWorkout) {
        // Logged under today, always. The date-based ID means re-pasting
        // the same day updates the workout instead of duplicating it.
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
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ], inMemory: true)
}
