import SwiftUI
import SwiftData

/// Training numbers: overview cards plus personal records per exercise.
/// Everything is computed from logged sets — no extra bookkeeping.
struct StatsView: View {
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]

    private var totalWorkouts: Int { days.count }

    private var weekStreak: Int {
        let calendar = Calendar.current
        let weeks = Set(days.map { calendar.component(.weekOfYear, from: $0.date) * 100 + calendar.component(.yearForWeekOfYear, from: $0.date) })
        var streak = 0
        var cursor = Date()
        let thisWeekKey = calendar.component(.weekOfYear, from: cursor) * 100 + calendar.component(.yearForWeekOfYear, from: cursor)
        if !weeks.contains(thisWeekKey) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        while true {
            let key = calendar.component(.weekOfYear, from: cursor) * 100 + calendar.component(.yearForWeekOfYear, from: cursor)
            guard weeks.contains(key) else { break }
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    private var totalVolume: Double {
        days.flatMap { $0.exercises }.flatMap { $0.sets }.reduce(0) { total, set in
            guard let weight = set.weight, let reps = set.reps else { return total }
            let lb = set.unit == .kg ? weight * 2.20462 : weight
            return total + lb * Double(reps)
        }
    }

    private var personalRecords: [(name: String, weight: Double, date: Date)] {
        var best: [String: (weight: Double, date: Date, name: String)] = [:]
        for day in days {
            for workoutExercise in day.exercises {
                guard let exercise = workoutExercise.exercise else { continue }
                for set in workoutExercise.sets {
                    guard let weight = set.weight else { continue }
                    let lb = set.unit == .kg ? weight * 2.20462 : weight
                    let key = exercise.normalizedName
                    if lb > (best[key]?.weight ?? 0) {
                        best[key] = (lb, day.date, exercise.name)
                    }
                }
            }
        }
        return best.values
            .map { (name: $0.name, weight: $0.weight, date: $0.date) }
            .sorted { $0.weight > $1.weight }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WorkoutTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Stats")
                            .font(.poster(42))
                            .foregroundStyle(WorkoutTheme.cream)
                            .textCase(.uppercase)
                            .tracking(-1)
                            .padding(.top, 12)
                        overviewCards
                        recordsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
            .workoutTabStyle()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var overviewCards: some View {
        HStack(spacing: 12) {
            statCard(value: "\(totalWorkouts)", label: "Workouts")
            statCard(value: "\(weekStreak)", label: "Week streak")
            statCard(value: formatVolume(totalVolume), label: "Total lb lifted")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(WorkoutTheme.grayText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(WorkoutTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records")
                .font(.poster(24))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .tracking(-0.5)
            if personalRecords.isEmpty {
                Text("Log some sets and your heaviest lifts will show up here.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else {
                ForEach(personalRecords, id: \.name) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(formattedDate(record.date))
                                .font(.caption)
                                .foregroundStyle(WorkoutTheme.grayText)
                        }
                        Spacer()
                        Text("\(String(format: "%g", record.weight)) lb")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(WorkoutTheme.lime)
                            .tracking(-0.5)
                    }
                    .padding(14)
                    .background(WorkoutTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 { return String(format: "%.1fM", volume / 1_000_000) }
        else if volume >= 1_000 { return String(format: "%.1fK", volume / 1_000) }
        else { return String(format: "%g", volume) }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [Exercise.self, WorkoutDay.self, WorkoutExercise.self, WorkoutSet.self, GymProfile.self], inMemory: true)
}
