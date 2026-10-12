import Foundation
import SwiftData

/// Preloaded workout history from Victor's Brawn CSV export.
/// Format per day: "date|Exercise|w:r,w:r;Exercise|w:r"
@MainActor
enum SeedWorkouts {
    static let data: [String] = [
        "2026-09-19;Feet-Up Barbell Bench Press|65:8,65:8;Chest-Supported Dumbbell Row (Elbows-In)|50:12,60:12;Neutral Close Grip Cable Lat Pulldown|66:12,66:12;Pin-Loaded Machine Preacher Curl|55:12,55:12;Cable Straight Bar Triceps Pushdown|27.5:12,27.5:12",
        "2026-09-20;Goblet Squat|35:12,40:12,40:12;Weighted Roman Chair Back Extension|0:12,10:12,10:12;Leg Extension|30:15,35:15,35:15;Seated Hamstring Curl|60:15,80:15,100:15,100:15;Standing Machine Calf Raise|50:15,90:15,90:15",
        "2026-09-22;Feet-Up Barbell Bench Press|75:6,85:6,95:6,95:6;Wide Grip Cable Row|50:12,60:12,70:12,70:12;Wide Grip Cable Lat Pulldown|66:12,77:12,77:12;Standing Dumbbell Hammer Curl|40:12,40:12;Decline Dumbbell Skullcrusher|12.5:12,12.5:12",
        "2026-09-24;Dumbbell Romanian Deadlift|90:12,90:12;Single Leg Pin-Loaded Leg Press|40:12,40:12;Seated Machine Hip Abduction|90:15,110:15,110:15;Seated Machine Hip Adduction|110:15,110:15;Seated Plate-Loaded Machine Calf Raise|10:15,10:15",
        "2026-09-28;Decline Weighted Sit-Up|10:10,25:10,25:10;Conventional Deadlift|135:6,155:6,155:6,155:6;Barbell Bench Press|115:4,100:5;Hack Squat|25:10,25:10,25:10;Dumbbell Walking Lunge|40:12,40:12,40:12;Lying Hamstring Curl|30:12,30:12,30:12",
        "2026-09-29;45° Incline Barbell Press|65:6,75:6,75:6,75:6;Standing Single Arm Dumbbell Overhead Press|10:10,10:10,10:10;Wide Grip Cable Lat Pulldown|85:10,85:10,85:10;Neutral Grip Pin-Loaded Machine Row|27.5:10,27.5:10,27.5:10;Standing Dumbbell Biceps Curl|25:10,30:10,30:10,30:10;Single Arm Neutral Grip Cable Triceps Pushdown|10:10,15:10,15:10,15:10",
        "2026-09-30;Straight Leg Reverse Crunch|:15,:15,:15;Dumbbell Romanian Deadlift|100:10,100:10,100:10;Single Leg Pin-Loaded Leg Press|45:10,45:10,45:10;Seated Machine Hip Abduction|110:15,110:15,110:15;Lying Hamstring Curl|30:15,30:15,30:15",
        "2026-10-02;Barbell Bench Press|100:6,100:6,100:6;Standing Dumbbell Lateral Raise|20:10,20:10,20:10;Underhand Grip Cable Lat Pulldown|70:10,70:10,70:10;Single Arm Dumbbell Row (Elbow-In)|40:10,40:10,40:10;Alternating Cross-Body Dumbbell Hammer Curl|40:10,40:10,40:10;Dumbbell Skull Crusher|40:10,40:10,40:10",
        "2026-10-06;Decline Weighted Sit-Up|25:10,25:10,25:10;Conventional Deadlift|155:8,155:8;Barbell Bench Press|115:2,100:5,100:5,100:5;Hack Squat|30:10,30:10,30:10;Dumbbell Walking Lunge|40:12,40:12,40:12;Lying Hamstring Curl|30:12,30:12,30:12",
        "2026-10-08;45° Incline Barbell Press|75:6,65:6,65:6;Standing Dumbbell Lateral Raise|20:10,10:10,10:10;Standing Dumbbell Front Raise|20:10,10:10,10:10;Wide Grip Cable Lat Pulldown|85:10,85:10,85:10;Neutral Grip Pin-Loaded Machine Row|35:10,35:10,35:10;Standing Dumbbell Biceps Curl|25:10,35:10,35:10,35:10;Single Arm Neutral Grip Cable Triceps Pushdown|12.5:10,12.5:10,12.5:10",
        "2026-10-10;Double Straight Leg Raise|:15,:15,:15;Dumbbell Romanian Deadlift|100:10,100:10,100:10;Single Leg Pin-Loaded Leg Press|50:10,50:10,50:10;Seated Machine Hip Abduction|120:15,120:15,120:15;Lying Hamstring Curl|35:15,35:15,35:15",
        "2026-10-11;Barbell Bench Press|100:8,100:8;Dumbbell Shoulder 3 Way Raise |5:10,5:10,5:10;Underhand Grip Cable Lat Pulldown|85:10,85:10,85:10;Single Arm Dumbbell Row (Elbow-In)|45:10,45:10,45:10;Standing Dumbbell Hammer Curl|40:10,45:10,45:10;Dumbbell Skull Crusher|45:10,45:10,45:10",
    ]

    static func importIfNeeded(into context: ModelContext) -> (days: Int, exercises: Int, sets: Int) {
        let profile = GymProfile.current(in: context)
        var daysCreated = 0, exercisesCreated = 0, setsCreated = 0
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let tf = DateFormatter()
        tf.dateFormat = "MMMM d, yyyy"

        for line in data {
            let segments = line.split(separator: ";")
            guard segments.count >= 2, let date = df.date(from: String(segments[0])) else { continue }
            let dayStart = Calendar.current.startOfDay(for: date)
            let sourceID = "seed-\(segments[0])"
            let desc = FetchDescriptor<WorkoutDay>(predicate: #Predicate { $0.sourceWorkoutID == sourceID })
            if let _ = try? context.fetch(desc).first { continue }

            let day = WorkoutDay(date: dayStart, title: tf.string(from: dayStart), sourceWorkoutID: sourceID)
            context.insert(day)
            daysCreated += 1

            var order = 0
            for seg in segments.dropFirst() {
                let parts = seg.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let exName = String(parts[0])
                let setStrs = parts[1].split(separator: ",")
                var sets: [(Double?, Int)] = []
                for s in setStrs {
                    let wr = s.split(separator: ":")
                    guard wr.count == 2, let reps = Int(wr[1]) else { continue }
                    let w = Double(wr[0])
                    sets.append((w, reps))
                }
                guard !sets.isEmpty else { continue }
                order += 1

                let exercise = WorkoutImporter.findOrCreateExercise(named: exName, in: context)
                let we = WorkoutExercise(
                    order: order,
                    targetSets: sets.count,
                    targetReps: String(sets[0].1),
                    coachNotes: "",
                    prescribedWeight: sets.first(where: { $0.0 != nil })?.0,
                    exercise: exercise
                )
                we.workoutDay = day
                context.insert(we)
                day.exercises.append(we)
                exercisesCreated += 1

                for (idx, (w, r)) in sets.enumerated() {
                    let set = WorkoutSet(setNumber: idx + 1, targetReps: String(r), unit: profile.unit, weight: w, reps: r)
                    set.isCompleted = true
                    set.workoutExercise = we
                    context.insert(set)
                    setsCreated += 1
                }
            }
        }
        return (daysCreated, exercisesCreated, setsCreated)
    }
}
