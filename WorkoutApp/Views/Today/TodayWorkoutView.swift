import SwiftUI
import SwiftData

/// The home tab, redesigned: today's date up top, a month grid of
/// workout dots, and the day's exercises as bold cards. Paste-first —
/// no email wording anywhere.
struct TodayWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]

    @State private var showingPaste = false
    @State private var showingDeleteConfirm = false
    @State private var selectedDay: Int?
    @State private var showingBuilder = false
    @State private var builderInitialDate = Date()
    @State private var navigatingDay: WorkoutDay?
    @State private var showingDayDetail = false

    private var today: WorkoutDay? {
        days.first { Calendar.current.isDateInToday($0.date) }
    }

    private var monthMarkedDays: Set<Int> {
        let calendar = Calendar.current
        return Set(
            days
                .filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
                .map { calendar.component(.day, from: $0.date) }
        )
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    private var selectedWorkout: WorkoutDay? {
        guard let selectedDay else { return nil }
        return days.first {
            Calendar.current.component(.day, from: $0.date) == selectedDay
                && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }
    }

    private var selectedDate: Date? {
        guard let selectedDay else { return nil }
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.day = selectedDay
        return Calendar.current.date(from: components)
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date()).uppercased()
    }

    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WorkoutTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerRow
                        monthSection
                        if let day = today {
                            workoutSection(day)
                        } else {
                            emptySection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .workoutTabStyle()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPaste) {
                PasteWorkoutView()
            }
            .sheet(isPresented: $showingBuilder) {
                WorkoutBuilderView(initialDate: builderInitialDate)
            }
            .navigationDestination(isPresented: $showingDayDetail) {
                if let day = navigatingDay {
                    HistoryDayView(day: day)
                }
            }
            .onChange(of: selectedDay) { _, _ in
                if let workout = selectedWorkout {
                    navigatingDay = workout
                    showingDayDetail = true
                } else if let date = selectedDate {
                    builderInitialDate = date
                    showingBuilder = true
                }
                selectedDay = nil
            }
            .alert("Delete Workout?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let day = today {
                        context.delete(day)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes today's workout and every set you logged. This can't be undone.")
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayText)
                    .font(.poster(42))
                    .foregroundStyle(WorkoutTheme.cream)
                    .tracking(-1)
                Text(monthDayText)
                    .font(.poster(42))
                    .foregroundStyle(WorkoutTheme.cream)
                    .tracking(-1)
            }
            Spacer()
            Menu {
                Button {
                    showingPaste = true
                } label: {
                    Label("Paste Workout", systemImage: "doc.on.clipboard")
                }
                if today != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                }
            } label: {
                Circle()
                    .fill(WorkoutTheme.card)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(WorkoutTheme.grayText)
                            .font(.title3)
                    }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Month dots

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(monthMarkedDays.count)/\(daysInMonth) days")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
            MonthCalendarView(
                month: Date(),
                markedDays: monthMarkedDays,
                selection: $selectedDay,
                showTodayRing: true
            )
        }
    }

    // MARK: - Workout

    private func workoutSection(_ day: WorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Todays Workout")
                    .font(.poster(28))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(-0.5)
                Text("\(day.completedSetsCount) of \(day.totalSetsCount) sets done")
                    .font(.subheadline)
                    .foregroundStyle(WorkoutTheme.grayText)
            }
            ForEach(day.sortedExercises) { workoutExercise in
                WorkoutExerciseCard(workoutExercise: workoutExercise)
            }
        }
    }

    // MARK: - Empty state

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Todays Workout")
                .font(.poster(28))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .tracking(-0.5)
            Text("No workout yet. Paste today's workout to get started.")
                .font(.body)
                .foregroundStyle(WorkoutTheme.grayText)
            Button {
                showingPaste = true
            } label: {
                Text("Paste Workout")
            }
            .buttonStyle(.lime)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }
}

/// One exercise as a dark card: body-part emoji tile, name, muscle group,
/// prescription, and a chevron into the logging page.
private struct WorkoutExerciseCard: View {
    @Environment(\.modelContext) private var context
    let workoutExercise: WorkoutExercise

    @State private var suggestion: WeightSuggestion?

    private var bodyPart: BodyPart {
        BodyPart.detect(
            name: workoutExercise.exercise?.name ?? "",
            notes: workoutExercise.coachNotes
        )
    }

    private var summaryLine: String {
        var line = "\(workoutExercise.targetSets) sets X \(workoutExercise.targetReps) reps"
        let weight = suggestion?.weight ?? workoutExercise.prescribedWeight
        if let weight {
            line += " X \(String(format: "%g", weight)) lbs"
        }
        return line
    }

    var body: some View {
        NavigationLink {
            ExerciseDetailView(workoutExercise: workoutExercise)
        } label: {
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
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(WorkoutTheme.softText)
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
        .buttonStyle(.plain)
        .task {
            if let name = workoutExercise.exercise?.normalizedName {
                suggestion = WeightSuggestionService.suggestion(for: name, in: context)
            }
        }
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
