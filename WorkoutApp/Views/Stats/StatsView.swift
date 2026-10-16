import SwiftUI
import SwiftData
import Charts

/// Training numbers: overview cards, body weight trend from Apple Health,
/// muscle balance, weekly volume chart, and personal records.
/// Everything is computed from logged sets — no extra bookkeeping.
struct StatsView: View {
    @Query(sort: \WorkoutDay.date, order: .reverse) private var days: [WorkoutDay]
    @StateObject private var health = HealthKitService.shared
    @State private var showingAllRecords = false

    // MARK: - Computed stats

    private var totalWorkouts: Int { days.count }

    /// Consecutive weeks (ending this week) with at least one workout.
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

    /// Total volume lifted (weight × reps) across all logged sets, in lb.
    /// Warm-up sets don't count.
    private var totalVolume: Double {
        days.flatMap { $0.exercises }.flatMap { $0.sets }.reduce(0) { total, set in
            guard !set.isWarmup, let weight = set.weight, let reps = set.reps else { return total }
            let lb = set.unit == .kg ? weight * 2.20462 : weight
            return total + lb * Double(reps)
        }
    }

    /// Heaviest weight ever logged per exercise, with the date it happened.
    private var personalRecords: [(name: String, weight: Double, date: Date)] {
        var best: [String: (weight: Double, date: Date, name: String)] = [:]
        for day in days {
            for workoutExercise in day.exercises {
                guard let exercise = workoutExercise.exercise else { continue }
                for set in workoutExercise.sets {
                    guard !set.isWarmup, let weight = set.weight else { continue }
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

    /// Sets per muscle group, as a share of all logged sets.
    private var muscleBreakdown: [(part: BodyPart, sets: Int, share: Double)] {
        var counts: [String: (part: BodyPart, sets: Int)] = [:]
        var total = 0
        for day in days {
            for workoutExercise in day.exercises {
                let part = BodyPart.detect(
                    name: workoutExercise.exercise?.name ?? "",
                    notes: workoutExercise.coachNotes
                )
                let n = workoutExercise.sortedSets.filter { $0.isCompleted && !$0.isWarmup }.count
                guard n > 0 else { continue }
                total += n
                if let existing = counts[part.label] {
                    counts[part.label] = (part, existing.sets + n)
                } else {
                    counts[part.label] = (part, n)
                }
            }
        }
        guard total > 0 else { return [] }
        return counts.values
            .map { (part: $0.part, sets: $0.sets, share: Double($0.sets) / Double(total)) }
            .sorted { $0.sets > $1.sets }
    }

    /// Total volume per week for the last 8 weeks, oldest first.
    private var weeklyVolume: [(weekStart: Date, volume: Double)] {
        let calendar = Calendar.current
        var buckets: [Date: Double] = [:]
        for day in days {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day.date)
            guard let weekStart = calendar.date(from: comps) else { continue }
            let vol = day.exercises.flatMap { $0.sets }.reduce(0.0) { total, set in
                guard !set.isWarmup, let weight = set.weight, let reps = set.reps else { return total }
                let lb = set.unit == .kg ? weight * 2.20462 : weight
                return total + lb * Double(reps)
            }
            buckets[weekStart, default: 0] += vol
        }
        let now = Date()
        return (0..<8).compactMap { weeksAgo in
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear, value: -weeksAgo,
                to: calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            ) else { return nil }
            return (weekStart: weekStart, volume: buckets[weekStart] ?? 0)
        }.reversed()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                WorkoutTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Stats")
                            .font(.poster(42))
                            .foregroundStyle(WorkoutTheme.cream)
                            .textCase(.uppercase)
                            .tracking(-1)
                            .padding(.top, 12)

                        overviewCards
                        // weightSection — Apple Health integration scrapped for now (2026-10-13).
                        // The HealthKitService and weightSection code are intact; re-add this line to restore.
                        muscleSection
                        volumeSection
                        recordsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .padding(.bottom, 100)
                }
            }
            .workoutTabStyle()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await health.checkAuthorization()
            }
        }
    }

    // MARK: - Sections

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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.poster(24))
            .foregroundStyle(.white)
            .textCase(.uppercase)
            .tracking(-0.5)
    }

    // MARK: - Body weight

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Body Weight")

            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else if !health.isAuthorized {
                Button {
                    Task { await health.requestAuthorization() }
                } label: {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(WorkoutTheme.lime)
                        Text("Connect Apple Health")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(WorkoutTheme.grayText)
                    }
                    .padding(16)
                    .background(WorkoutTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                Text("Pulls your daily weigh-ins to track your trend. Make sure Weight is toggled on in the Apple popup.")
                    .font(.caption)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else if let latest = health.latestWeight {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(String(format: "%.1f", latest.weightLb))")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(.white)
                            .tracking(-1)
                        Text("lb")
                            .font(.headline)
                            .foregroundStyle(WorkoutTheme.grayText)
                        Spacer()
                        if let change = health.weekChange {
                            weekChangeBadge(change)
                        }
                    }

                    if health.weightHistory.count >= 2 {
                        Chart(health.weightHistory.suffix(30)) { sample in
                            LineMark(
                                x: .value("Date", sample.date),
                                y: .value("Weight", sample.weightLb)
                            )
                            .foregroundStyle(WorkoutTheme.lime)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            AreaMark(
                                x: .value("Date", sample.date),
                                y: .value("Weight", sample.weightLb)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [WorkoutTheme.lime.opacity(0.25), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .trailing) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(String(format: "%.0f", v))")
                                            .font(.caption2)
                                            .foregroundStyle(WorkoutTheme.grayText)
                                    }
                                }
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.white.opacity(0.08))
                            }
                        }
                        .frame(height: 140)
                    } else {
                        Text("Weigh in a few more times to see your trend.")
                            .font(.caption)
                            .foregroundStyle(WorkoutTheme.grayText)
                    }
                }
                .padding(16)
                .background(WorkoutTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Text("No weigh-ins found in Apple Health yet.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            }
        }
    }

    private func weekChangeBadge(_ change: Double) -> some View {
        let isDown = change < -0.05
        let isUp = change > 0.05
        let text: String
        let color: Color
        let icon: String
        if isDown {
            text = String(format: "%.1f", abs(change))
            color = WorkoutTheme.lime
            icon = "arrow.down.right"
        } else if isUp {
            text = String(format: "+%.1f", change)
            color = .orange
            icon = "arrow.up.right"
        } else {
            text = "steady"
            color = WorkoutTheme.grayText
            icon = "minus"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.bold())
            Text(text)
                .font(.subheadline.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Muscle balance

    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Muscle Balance")
            if muscleBreakdown.isEmpty {
                Text("Log some sets and your muscle split will show up here.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else {
                VStack(spacing: 10) {
                    ForEach(muscleBreakdown, id: \.part.label) { entry in
                        HStack(spacing: 12) {
                            Text(entry.part.emoji)
                                .font(.system(size: 24))
                                .frame(width: 36)
                            Text(entry.part.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 80, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(WorkoutTheme.lime)
                                        .frame(width: geo.size.width * CGFloat(entry.share))
                                }
                            }
                            .frame(height: 10)
                            Text("\(Int(entry.share * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(WorkoutTheme.grayText)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(WorkoutTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    // MARK: - Volume trend

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Weekly Volume")
            let data = weeklyVolume
            if data.allSatisfy({ $0.volume == 0 }) {
                Text("Log some sets and your weekly volume will show up here.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else {
                Chart(data, id: \.weekStart) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Volume", week.volume)
                    )
                    .foregroundStyle(WorkoutTheme.lime.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(WorkoutTheme.grayText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatVolume(v))
                                    .font(.caption2)
                                    .foregroundStyle(WorkoutTheme.grayText)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(16)
                .background(WorkoutTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    // MARK: - Personal records

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Personal Records")

            if personalRecords.isEmpty {
                Text("Log some sets and your heaviest lifts will show up here.")
                    .font(.body)
                    .foregroundStyle(WorkoutTheme.grayText)
            } else {
                let shown = showingAllRecords ? personalRecords : Array(personalRecords.prefix(5))
                ForEach(shown, id: \.name) { record in
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
                if personalRecords.count > 5 {
                    Button {
                        withAnimation { showingAllRecords.toggle() }
                    } label: {
                        Text(showingAllRecords ? "Show less" : "Show all \(personalRecords.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WorkoutTheme.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(WorkoutTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Formatting

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.1fK", volume / 1_000)
        } else {
            return String(format: "%g", volume)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ], inMemory: true)
}
