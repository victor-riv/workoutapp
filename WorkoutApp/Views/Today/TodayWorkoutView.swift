import SwiftUI
import SwiftData

/// The home tab, redesigned: today's date up top, a month grid of
/// workout dots, and the day's exercises as bold cards. Paste-first —
/// no email wording anywhere.
struct TodayWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]

    @State private var showingDeleteConfirm = false
    @State private var selectedDay: Int?
    @State private var showingBuilder = false
    @State private var builderInitialDate = Date()
    @State private var navigatingDay: WorkoutDay?
    @State private var showingDayDetail = false
    @State private var celebratingDay: WorkoutDay?

    private var today: WorkoutDay? {
        days.first { Calendar.current.isDateInToday($0.date) }
    }

    private var monthMarkedDays: Set<Int> {
        let calendar = Calendar.current
        return Set(
            days
                .filter { $0.isCompleted && calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
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
                    .padding(.bottom, 100)
                }
            }
            .workoutTabStyle()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                // One-time backfill: workouts logged before the completion
                // feature existed get marked complete if any set was logged
                // that day, so they keep their calendar dots. Idempotent.
                var changed = false
                for day in days where !day.isCompleted && day.completedSetsCount > 0 {
                    day.isCompleted = true
                    changed = true
                }
                if changed { try? context.save() }
            }
            .overlay {
                if let day = celebratingDay {
                    WorkoutCompleteCelebration(day: day) {
                        celebratingDay = nil
                    }
                }
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
                    builderInitialDate = Calendar.current.startOfDay(for: Date())
                    showingBuilder = true
                } label: {
                    Label("New Workout", systemImage: "plus")
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
            if day.isCompleted {
                Button {
                    day.isCompleted = false
                    try? context.save()
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
                    try? context.save()
                    celebratingDay = day
                } label: {
                    HStack {
                        Image(systemName: "flag.checkered")
                        Text("Finish Workout")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lime)
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
            Text("No workout yet. Create today's workout to get started.")
                .font(.body)
                .foregroundStyle(WorkoutTheme.grayText)
            Button {
                builderInitialDate = Calendar.current.startOfDay(for: Date())
                showingBuilder = true
            } label: {
                Text("Create Workout")
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

/// Full-screen "you did it" moment when a workout is marked complete.
/// Shared by Today and the exercise detail page. Dismisses with one tap.
struct WorkoutCompleteCelebration: View {
    let day: WorkoutDay
    let onDismiss: () -> Void

    @State private var popped = false

    private var volumeText: String {
        let vol = day.workingVolumeLb
        if vol >= 1000 {
            return String(format: "%.1fK lb lifted", vol / 1000)
        }
        return String(format: "%.0f lb lifted", vol)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(WorkoutTheme.lime)
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(.black)
                }
                .scaleEffect(popped ? 1 : 0.4)
                .opacity(popped ? 1 : 0)

                Text("Workout Complete")
                    .font(.poster(38))
                    .foregroundStyle(WorkoutTheme.cream)
                    .textCase(.uppercase)
                    .tracking(-1)
                    .multilineTextAlignment(.center)

                Text("\(day.completedSetsCount) sets · \(volumeText)")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(day.title)
                    .font(.subheadline)
                    .foregroundStyle(WorkoutTheme.grayText)
                    .lineLimit(1)

                Button(action: onDismiss) {
                    Text("Nice")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lime)
                .padding(.top, 8)
            }
            .padding(32)
            .background(WorkoutTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                popped = true
            }
        }
    }
}
