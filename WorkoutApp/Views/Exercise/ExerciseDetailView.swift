import SwiftUI
import SwiftData
import UIKit

/// Set-by-set logging for one exercise. Weight fields come pre-filled with
/// the last-used weight; the user just adjusts and ticks sets off.
///
/// Barbell lifts get a plate-calculator shortcut under the header.
/// Styled to match the Today tab: dark cards, cream poster header.
struct ExerciseDetailView: View {
    @Bindable var workoutExercise: WorkoutExercise
    @Environment(\.modelContext) private var context

    /// When true, this is a read-only history view: no rest timer or plates
    /// button — those are for actively doing the workout.
    let isHistory: Bool

    init(workoutExercise: WorkoutExercise, isHistory: Bool = false) {
        self.workoutExercise = workoutExercise
        self.isHistory = isHistory
    }

    @State private var showingPlates = false
    @State private var celebratingDay: WorkoutDay?
    @State private var restTimerTrigger = 0
    @State private var navigateToNext = false

    /// The next exercise in this workout day, if any.
    private var nextExercise: WorkoutExercise? {
        guard let day = workoutExercise.workoutDay else { return nil }
        let sorted = day.sortedExercises
        guard let idx = sorted.firstIndex(where: { $0 === workoutExercise }),
              idx + 1 < sorted.count else { return nil }
        return sorted[idx + 1]
    }

    private var allSetsInExerciseDone: Bool {
        let sets = workoutExercise.sortedSets
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    private var exerciseName: String {
        workoutExercise.exercise?.name ?? "Exercise"
    }

    /// Barbell heuristic: only show the plate calculator for lifts that
    /// are actually done with a barbell. Opt-in, not opt-out — a plain
    /// "Lying Leg Raise" must not get a Plates button.
    private var usesBarbell: Bool {
        let lower = exerciseName.lowercased()
        let notBarbell = ["dumbbell", "kettlebell", "machine", "cable", "smith",
                          "band", "bodyweight", "trx", "leg press"]
        if notBarbell.contains(where: lower.contains) { return false }
        if lower.contains("barbell") { return true }
        let barbellLifts = ["squat", "deadlift", "bench press", "overhead press",
                            "military press", "push press", "strict press",
                            "pendlay row", "clean", "snatch", "jerk",
                            "hip thrust", "good morning", "zercher"]
        return barbellLifts.contains(where: lower.contains)
    }

    private var platesPreset: Double? {
        workoutExercise.sortedSets.compactMap(\.weight).first
            ?? workoutExercise.prescribedWeight
    }

    /// Drops the keyboard when the user taps outside a text field.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// Appends a blank set row, copying the last set's weight and rep target
    /// so extra/back-off sets are one tap away.
    private func addSet() {
        let sorted = workoutExercise.sortedSets
        let nextNumber = (sorted.map(\.setNumber).max() ?? 0) + 1
        let last = sorted.last
        let profile = GymProfile.current(in: context)
        let newSet = WorkoutSet(
            setNumber: nextNumber,
            targetReps: last?.targetReps ?? workoutExercise.targetReps,
            unit: last?.unit ?? profile.unit,
            weight: last?.weight
        )
        newSet.workoutExercise = workoutExercise
        context.insert(newSet)
        workoutExercise.sets.append(newSet)
    }

    /// Removes a set and renumbers the ones after it.
    private func deleteSet(_ set: WorkoutSet) {
        withAnimation {
            workoutExercise.sets.removeAll { $0.id == set.id }
            context.delete(set)
            for (index, remaining) in workoutExercise.sortedSets.enumerated() {
                remaining.setNumber = index + 1
            }
            try? context.save()
        }
    }

    /// Moves a set up (-1) or down (+1) by swapping set numbers.
    private func moveSet(_ set: WorkoutSet, direction: Int) {
        let sorted = workoutExercise.sortedSets
        guard let index = sorted.firstIndex(where: { $0.id == set.id }) else { return }
        let target = index + direction
        guard target >= 0, target < sorted.count else { return }
        withAnimation {
            let other = sorted[target]
            let temp = set.setNumber
            set.setNumber = other.setNumber
            other.setNumber = temp
            try? context.save()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(exerciseName)
                        .font(.poster(34))
                        .foregroundStyle(WorkoutTheme.cream)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                    if usesBarbell && !isHistory {
                        Button {
                            showingPlates = true
                        } label: {
                            Text("Plates")
                        }
                        .buttonStyle(.lime)
                    }
                }
                .padding(.top, 8)

                if !workoutExercise.coachNotes.isEmpty {
                    Text(workoutExercise.coachNotes)
                        .font(.body)
                        .foregroundStyle(WorkoutTheme.softText)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                if let prescribed = workoutExercise.prescribedWeight {
                    Text("Coach prescribed \(String(format: "%g", prescribed)) lb — pre-filled below; adjust to what you actually lift.")
                        .font(.subheadline)
                        .foregroundStyle(WorkoutTheme.grayText)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                if let waves = workoutExercise.setWavesSummary {
                    Text("Sets — \(waves)")
                        .font(.poster(20))
                        .foregroundStyle(.white)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                        .padding(.top, 4)
                } else {
                    Text("Sets — \(workoutExercise.targetSets) × \(workoutExercise.targetReps)")
                        .font(.poster(24))
                        .foregroundStyle(.white)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                        .padding(.top, 4)
                }

                if !isHistory {
                    RestTimerView(
                        exerciseName: workoutExercise.exercise?.name ?? "Exercise",
                        startTrigger: $restTimerTrigger
                    )
                    .padding(.top, 4)
                }

                ForEach(workoutExercise.sortedSets) { set in
                    SetCardView(
                        set: set,
                        onMoveUp: { moveSet(set, direction: -1) },
                        onMoveDown: { moveSet(set, direction: 1) },
                        onSetToggled: {
                            if set.isCompleted && !isHistory {
                                restTimerTrigger += 1
                                if allSetsInExerciseDone, nextExercise != nil {
                                    navigateToNext = true
                                }
                            }
                            if set.workoutExercise?.workoutDay?.checkAutoComplete() == true {
                                try? context.save()
                                celebratingDay = set.workoutExercise?.workoutDay
                            }
                        }
                    )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSet(set)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WorkoutTheme.lime)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WorkoutTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .padding(.bottom, 100)
        }
        .workoutTabStyle()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToNext) {
            if let next = nextExercise {
                ExerciseDetailView(workoutExercise: next, isHistory: isHistory)
            }
        }
        .overlay {
            if let day = celebratingDay {
                WorkoutCompleteCelebration(day: day) {
                    celebratingDay = nil
                }
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
        .sheet(isPresented: $showingPlates) {
            NavigationStack {
                PlateCalculatorView(presetTarget: platesPreset)
                    .navigationTitle("Plates")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Rest timer for timing between sets. Pick minutes + seconds or tap a preset,
/// then start. Uses an end-date so the countdown stays right even if the
/// phone locks or you leave the page.
private struct RestTimerView: View {
    let exerciseName: String
    @Binding var startTrigger: Int

    @State private var timer = RestTimerManager.shared
    @State private var minutes: Int
    @State private var seconds: Int

    private let presets: [(Int, Int)] = [(0, 30), (1, 0), (1, 30), (2, 0), (3, 0)]

    init(exerciseName: String, startTrigger: Binding<Int>) {
        self.exerciseName = exerciseName
        _startTrigger = startTrigger
        let total = RestTimerManager.shared.lastSeconds
        _minutes = State(initialValue: total / 60)
        _seconds = State(initialValue: total % 60)
    }

    private var totalSeconds: Int { minutes * 60 + seconds }

    private func timeText(_ total: Int) -> String {
        String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rest Timer")
                    .font(.poster(20))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(-0.5)
                Spacer()
                if !timer.isIdle {
                    Text(timer.exerciseName)
                        .font(.caption)
                        .foregroundStyle(WorkoutTheme.grayText)
                        .lineLimit(1)
                }
            }

            if timer.isIdle {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.0) { min, sec in
                            Button {
                                minutes = min; seconds = sec
                            } label: {
                                Text(timeText(min * 60 + sec))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(minutes == min && seconds == sec ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(minutes == min && seconds == sec ? WorkoutTheme.lime : WorkoutTheme.tile)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<11) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    Picker("Seconds", selection: $seconds) {
                        ForEach([0, 15, 30, 45], id: \.self) { Text("\($0) sec").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 110)

                Button {
                    timer.start(seconds: totalSeconds, exerciseName: exerciseName)
                } label: {
                    Text("Start Rest")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lime)
                .disabled(totalSeconds == 0)
            } else {
                Text(timeText(timer.remaining))
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(timer.remaining == 0 ? WorkoutTheme.lime : .white)
                    .tracking(-1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())

                HStack(spacing: 12) {
                    if timer.isRunning {
                        Button {
                            timer.pause()
                        } label: {
                            Text("Pause").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.lime)
                    } else if timer.remaining > 0 {
                        Button {
                            timer.resume()
                        } label: {
                            Text("Resume").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.lime)
                    }
                    Button {
                        timer.reset()
                    } label: {
                        Text(timer.remaining == 0 ? "Done" : "Reset")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(WorkoutTheme.tile)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(WorkoutTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onChange(of: startTrigger) { _, _ in
            timer.startWithLast(exerciseName: exerciseName)
        }
    }
}

/// One set as a dark card: reorder, number, warm-up toggle, weight + reps fields, done toggle.
/// Edits write straight through to SwiftData.
private struct SetCardView: View {
    @Bindable var set: WorkoutSet
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSetToggled: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var showingTypePicker = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WorkoutTheme.grayText)
                        .frame(width: 20, height: 16)
                }
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WorkoutTheme.grayText)
                        .frame(width: 20, height: 16)
                }
            }

            Button {
                showingTypePicker = true
            } label: {
                Text(set.isWarmup ? "W" : "\(set.setNumber)")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(set.isWarmup ? WorkoutTheme.orange : .white)
                    .frame(width: 32, height: 32)
                    .background(set.isWarmup ? WorkoutTheme.orange.opacity(0.18) : WorkoutTheme.tile)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingTypePicker) {
                SetTypePicker(isWarmup: $set.isWarmup)
                    .presentationDetents([.height(250)])
            }

            TextField("wt", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .padding(8)
                .background(WorkoutTheme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onAppear(perform: seedFields)
                .onChange(of: weightText) { _, new in
                    set.weight = Double(new.replacingOccurrences(of: ",", with: "."))
                }

            Text(set.unit.rawValue)
                .font(.caption)
                .foregroundStyle(WorkoutTheme.grayText)

            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(8)
                .background(WorkoutTheme.tile)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onAppear(perform: seedFields)
                .onChange(of: repsText) { _, new in
                    set.reps = Int(new)
                }

            Spacer()

            Toggle("", isOn: $set.isCompleted)
                .labelsHidden()
                .tint(WorkoutTheme.lime)
                .onChange(of: set.isCompleted) { _, _ in onSetToggled() }
        }
        .padding(14)
        .background(WorkoutTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func seedFields() {
        if weightText.isEmpty, let weight = set.weight {
            weightText = String(format: "%g", weight)
        }
        if repsText.isEmpty, let reps = set.reps {
            repsText = String(reps)
        } else if repsText.isEmpty {
            let digits = set.targetReps.filter(\.isNumber)
            if Int(set.targetReps) != nil { repsText = digits }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: WorkoutExercise.self, WorkoutSet.self, Exercise.self,
        configurations: config
    )
    let exercise = Exercise(name: "Barbell Bench Press")
    let block = WorkoutExercise(order: 0, targetSets: 3, targetReps: "8", exercise: exercise)
    block.ensureSets(unit: .lb)
    return NavigationStack {
        ExerciseDetailView(workoutExercise: block)
    }
    .modelContainer(container)
}

/// Chooser opened by tapping a set's W/number indicator.
/// Matches the app's dark card aesthetic.
struct SetTypePicker: View {
    @Binding var isWarmup: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Set Type")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 8)

            typeRow(
                title: "Warm-up",
                subtitle: "Doesn't count toward volume or PRs",
                indicator: "W",
                indicatorColor: WorkoutTheme.orange,
                selected: isWarmup
            ) {
                isWarmup = true
                dismiss()
            }

            typeRow(
                title: "Working set",
                subtitle: "Counts toward volume and PRs",
                indicator: "#",
                indicatorColor: .white,
                selected: !isWarmup
            ) {
                isWarmup = false
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(WorkoutTheme.background)
    }

    private func typeRow(
        title: String,
        subtitle: String,
        indicator: String,
        indicatorColor: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(indicator)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(indicatorColor)
                    .frame(width: 36, height: 36)
                    .background(indicatorColor.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WorkoutTheme.grayText)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WorkoutTheme.lime)
                }
            }
            .padding(14)
            .background(WorkoutTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
