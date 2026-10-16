import Foundation

/// The primary workout source: TrueCoach notification emails fetched from
/// the user's Gmail via the Gmail REST API (scope: `gmail.readonly`).
///
/// One email per training day, sent ~00:20 ET the morning of the workout.
/// See `EmailImport/EMAIL_FORMAT_SPEC.md` for the exact email format and
/// `EmailWorkoutParser` for the parsing rules.
final class EmailWorkoutSource: WorkoutSource, Sendable {
    private let gmail: GmailService

    init(gmail: GmailService) {
        self.gmail = gmail
    }

    func fetchTodaysWorkout() async throws -> ImportedWorkout? {
        let today = Calendar.current.startOfDay(for: Date())
        for candidate in try await workoutCandidates() {
            let date = try await resolveDate(candidate)
            if let date, Calendar.current.isDate(date, inSameDayAs: today) {
                return try await importMessage(candidate.summary)
            }
        }
        return nil
    }

    func fetchWorkouts(since: Date) async throws -> [ImportedWorkout] {
        let start = Calendar.current.startOfDay(for: since)
        var out: [ImportedWorkout] = []
        for candidate in try await workoutCandidates() {
            let date = try? await resolveDate(candidate)
            guard let date, date >= start else { continue }
            if let workout = try? await importMessage(candidate.summary) {
                out.append(workout)
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    // MARK: - Private

    private struct Candidate: Sendable {
        var summary: GmailService.MessageSummary
        var subject: ParsedSubject
    }

    /// Recent workout emails with subjects parsed (cheap: no body fetch).
    /// "You missed your workout" reminders are skipped here.
    private func workoutCandidates() async throws -> [Candidate] {
        let summaries = try await gmail.listWorkoutMessages()
        return summaries.compactMap { summary in
            let parsed = EmailWorkoutParser.parseSubject(summary.subject)
            guard !parsed.isMissedReminder,
                  parsed.weekDayCode != nil || parsed.date != nil
            else { return nil }
            return Candidate(summary: summary, subject: parsed)
        }
    }

    /// Workout date: the subject line usually has it; fall back to the
    /// body ("Here's your workout for …"), then the Gmail internal date.
    private func resolveDate(_ candidate: Candidate) async throws -> Date? {
        if let date = candidate.subject.date {
            return Calendar.current.startOfDay(for: date)
        }
        let message = try await gmail.fetchBody(messageID: candidate.summary.id)
        if let parsed = EmailWorkoutParser.parseMessage(subject: message.subject, body: message.body),
           let date = parsed.date {
            return Calendar.current.startOfDay(for: date)
        }
        return candidate.summary.internalDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private func importMessage(_ summary: GmailService.MessageSummary) async throws -> ImportedWorkout? {
        let message = try await gmail.fetchBody(messageID: summary.id)
        guard let parsed = EmailWorkoutParser.parseMessage(subject: message.subject, body: message.body) else {
            return nil
        }
        return parsed.toImportedWorkout(messageID: summary.id)
    }
}

// MARK: - ParsedWorkout → ImportedWorkout

extension ParsedWorkout {
    func toImportedWorkout(messageID: String) -> ImportedWorkout {
        // Superset notes, e.g. "Superset: H1 + H2".
        var supersetNotes: [String: String] = [:]
        let grouped = Dictionary(grouping: exercises, by: { $0.supersetGroup ?? "" })
        for (group, members) in grouped where !group.isEmpty && members.count > 1 {
            let labels = members.map(\.label).sorted().joined(separator: " + ")
            for member in members {
                supersetNotes[member.label] = "Superset: \(labels)"
            }
        }

        let blocks: [ImportedBlock] = exercises.map { exercise in
            let first = exercise.prescriptionLines.first
            var notes: [String] = []
            if let superset = supersetNotes[exercise.label] {
                notes.append(superset)
            }
            if let rir = first?.rir {
                notes.append("RIR \(rir)")
            }
            if first?.isAmbiguous == true, let raw = first?.rawText {
                notes.append("Coach didn't specify sets — showing 3 set rows (raw: \(raw))")
            }
            if !exercise.notes.isEmpty {
                notes.append(exercise.notes.joined(separator: " · "))
            }
            // Extra prescription lines (back-off sets like "100 x 3 x 5")
            // become their own set rows, not notes.
            let extraWaves: [PrescriptionWave] = exercise.prescriptionLines.dropFirst().map { extra in
                PrescriptionWave(
                    sets: extra.sets ?? 3,
                    reps: extra.reps.isEmpty ? "—" : extra.reps,
                    weight: extra.weight
                )
            }
            return ImportedBlock(
                exerciseName: exercise.name,
                coachNotes: notes.joined(separator: "\n"),
                targetSets: first?.sets ?? 3,
                targetReps: first.map(\.reps).flatMap { $0.isEmpty ? nil : $0 } ?? "—",
                prescribedWeight: first?.weight,
                kind: exercise.kind,
                supersetGroup: exercise.supersetGroup,
                extraWaves: extraWaves
            )
        }

        return ImportedWorkout(
            title: weekDayCode.map { "Workout \($0)" } ?? "Workout",
            date: date ?? Date(),
            sourceID: weekDayCode ?? "email-\(messageID)",
            nutritionSummary: nutrition?.summary,
            blocks: blocks
        )
    }
}
