import SwiftUI
import SwiftData

/// Browse any month and year: the dot calendar plus every workout logged
/// that month. Tap a day to see its workout; long-press a workout to delete it.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]

    @State private var visibleMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDay: Int?

    private var monthDays: [WorkoutDay] {
        days.filter { Calendar.current.isDate($0.date, equalTo: visibleMonth, toGranularity: .month) }
    }

    private var markedDays: Set<Int> {
        Set(monthDays.map { Calendar.current.component(.day, from: $0.date) })
    }

    private var selectedWorkout: WorkoutDay? {
        guard let selectedDay else { return nil }
        return monthDays.first { Calendar.current.component(.day, from: $0.date) == selectedDay }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleMonth).uppercased()
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WorkoutTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("History")
                            .font(.poster(42))
                            .foregroundStyle(WorkoutTheme.cream)
                            .textCase(.uppercase)
                            .tracking(-1)
                            .padding(.top, 12)

                        monthNavigator

                        MonthCalendarView(
                            month: visibleMonth,
                            markedDays: markedDays,
                            selection: $selectedDay,
                            showTodayRing: true
                        )

                        selectedDaySection

                        monthListSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .workoutTabStyle()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: visibleMonth) { _, _ in
                selectedDay = nil
            }
        }
    }

    // MARK: - Month navigator

    private var monthNavigator: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WorkoutTheme.cream)
                    .frame(width: 44, height: 44)
                    .background(WorkoutTheme.card)
                    .clipShape(Circle())
            }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .tracking(-0.5)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isCurrentMonth ? WorkoutTheme.grayText : WorkoutTheme.cream)
                    .frame(width: 44, height: 44)
                    .background(WorkoutTheme.card)
                    .clipShape(Circle())
            }
            .disabled(isCurrentMonth)
        }
    }

    private func shiftMonth(by offset: Int) {
        if let shifted = Calendar.current.date(byAdding: .month, value: offset, to: visibleMonth) {
            visibleMonth = shifted
        }
    }

    // MARK: - Selected day

    private var selectedDaySection: some View {
        Group {
            if let day = selectedWorkout {
                NavigationLink {
                    HistoryDayView(day: day)
                } label: {
                    HistoryWorkoutCard(day: day)
                }
                .buttonStyle(.plain)
            } else if selectedDay != nil {
                Text("Rest day — nothing logged.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Month list

    private var monthListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month")
                .font(.poster(24))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .tracking(-0.5)
            if monthDays.isEmpty {
                Text("No workouts logged this month yet.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else {
                ForEach(monthDays) { day in
                    NavigationLink {
                        HistoryDayView(day: day)
                    } label: {
                        HistoryWorkoutCard(day: day)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(day)
                        } label: {
                            Label("Delete Workout", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

/// One workout in the history list: date, title, and set progress.
private struct HistoryWorkoutCard: View {
    let day: WorkoutDay

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day.date).uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
                Text(day.title)
                    .font(.subheadline)
                    .foregroundStyle(WorkoutTheme.grayText)
                    .lineLimit(1)
                Text("\(day.completedSetsCount) of \(day.totalSetsCount) sets")
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
        .padding(14)
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
