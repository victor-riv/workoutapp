import SwiftUI
import SwiftData

/// A past workout day, styled like the rest of the app: big cream poster
/// date, total sets underneath, and emoji exercise cards like Today.
struct HistoryDayView: View {
    @Bindable var day: WorkoutDay

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day.date)
    }

    private var totalSets: Int {
        day.sortedExercises.reduce(0) { $0 + $1.sortedSets.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.poster(34))
                        .foregroundStyle(WorkoutTheme.cream)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                    Text("\(totalSets) sets")
                        .font(.subheadline)
                        .foregroundStyle(WorkoutTheme.grayText)
                }
                .padding(.top, 8)

                if day.isCompleted {
                    Button {
                        day.isCompleted = false
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(WorkoutTheme.lime)
                            Text("Completed")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundStyle(WorkoutTheme.grayText)
                        }
                        .padding(16)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        day.isCompleted = true
                    } label: {
                        HStack {
                            Image(systemName: "flag.checkered")
                            Text("Finish Workout")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lime)
                }

                ForEach(day.sortedExercises) { workoutExercise in
                    NavigationLink {
                        ExerciseDetailView(workoutExercise: workoutExercise, isHistory: true)
                    } label: {
                        HistoryExerciseCard(workoutExercise: workoutExercise)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .workoutTabStyle()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One logged exercise as a dark card: body-part emoji tile, name, muscle
/// group, and the actual logged weights/reps.
private struct HistoryExerciseCard: View {
    let workoutExercise: WorkoutExercise

    private var bodyPart: BodyPart {
        BodyPart.detect(
            name: workoutExercise.exercise?.name ?? "",
            notes: workoutExercise.coachNotes
        )
    }

    private var loggedSummary: String {
        let done = workoutExercise.sortedSets.filter(\.isCompleted)
        guard !done.isEmpty else { return "Not logged" }
        let setStrs = done.map { set -> String in
            var s = ""
            if let w = set.weight { s += "\(String(format: "%g", w)) lbs × " }
            s += "\(set.reps ?? 0)"
            return s
        }
        return setStrs.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(WorkoutTheme.tile)
                .frame(width: 64, height: 64)
                .overlay {
                    Text(bodyPart.emoji)
                        .font(.system(size: 30))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutExercise.exercise?.name ?? "Exercise")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .lineLimit(2)
                Text(bodyPart.label)
                    .font(.subheadline)
                    .foregroundStyle(WorkoutTheme.grayText)
                Text(loggedSummary)
                    .font(.subheadline)
                    .foregroundStyle(WorkoutTheme.softText)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Circle()
                .fill(Color(white: 0.06))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(WorkoutTheme.cream)
                        .font(.headline.weight(.bold))
                }
        }
        .padding(12)
        .background(WorkoutTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
