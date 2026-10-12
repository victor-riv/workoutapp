import Foundation
import SwiftData
enum CSVWorkoutImporter {
struct Result {
let days: Int
let exercises: Int
let sets: Int
}
enum ImportError: LocalizedError {
case emptyFile
case missingColumns(String)
case noValidRows(String)
var errorDescription: String? {
switch self {
case .emptyFile: return "That file is empty."
case .missingColumns(let cols): return "Couldn't find these columns: \(cols). Need at least Date, Exercise, and Reps (or Duration)."
case .noValidRows(let detail): return "No valid workout rows found. \(detail)"
}
}
}
private struct SetRow {
let date: Date
let exerciseName: String
let weight: Double?
let reps: Int
}
@MainActor static func importCSV(_ csvText: String, into context: ModelContext) throws -> Result {
let rows = try parse(csvText)
guard !rows.isEmpty else { throw ImportError.noValidRows("Parsed 0 rows from the file.") }
let profile = GymProfile.current(in: context)
var daysCreated = 0
var exercisesCreated = 0
var setsCreated = 0
let byDay = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.date) }
for (dayStart, dayRows) in byDay.sorted(by: { $0.key < $1.key }) {
let sourceID = "csv-\(ISO8601DateFormatter().string(from: dayStart))"
let descriptor = FetchDescriptor<WorkoutDay>(predicate: #Predicate { $0.sourceWorkoutID == sourceID && $0.date == dayStart })
if let _ = try? context.fetch(descriptor).first { continue }
let formatter = DateFormatter()
formatter.dateFormat = "MMMM d, yyyy"
let day = WorkoutDay(date: dayStart, title: formatter.string(from: dayStart), sourceWorkoutID: sourceID)
context.insert(day)
daysCreated += 1
var exerciseOrder: [String] = []
var setsByExercise: [String: [SetRow]] = [:]
for row in dayRows {
let key = Exercise.normalize(row.exerciseName)
if setsByExercise[key] == nil { exerciseOrder.append(key); setsByExercise[key] = [] }
setsByExercise[key]?.append(row)
}
var order = 0
for key in exerciseOrder {
guard let exSets = setsByExercise[key], let first = exSets.first else { continue }
order += 1
let firstWeight = exSets.first(where: { $0.weight != nil })?.weight
let exercise = WorkoutImporter.findOrCreateExercise(named: first.exerciseName, in: context)
let workoutExercise = WorkoutExercise(order: order, targetSets: exSets.count, targetReps: String(first.reps), coachNotes: "", prescribedWeight: firstWeight, exercise: exercise)
workoutExercise.workoutDay = day
context.insert(workoutExercise)
day.exercises.append(workoutExercise)
exercisesCreated += 1
for (idx, setRow) in exSets.enumerated() {
let set = WorkoutSet(setNumber: idx + 1, targetReps: String(setRow.reps), unit: profile.unit, weight: setRow.weight, reps: setRow.reps)
set.isCompleted = true
set.workoutExercise = workoutExercise
context.insert(set)
setsCreated += 1
}
}
}
return Result(days: daysCreated, exercises: exercisesCreated, sets: setsCreated)
}
private static func normHeader(_ h: String) -> String {
var s = h.trimmingCharacters(in: .whitespaces).lowercased()
if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]).trimmingCharacters(in: .whitespaces) }
return s
}
private static func parse(_ text: String) throws -> [SetRow] {
let lines = splitLines(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
guard !lines.isEmpty else { throw ImportError.emptyFile }
let headers = parseLine(lines[0]).map(normHeader)
func col(_ names: String...) -> Int? {
for n in names { if let i = headers.firstIndex(of: n) { return i } }
return nil
}
guard let dateIdx = col("date"), let exerciseIdx = col("exercise", "exercise name", "movement", "lift"), let repsIdx = col("reps", "rep") else {
var missing: [String] = []
if col("date") == nil { missing.append("Date") }
if col("exercise", "exercise name", "movement", "lift") == nil { missing.append("Exercise") }
if col("reps", "rep") == nil { missing.append("Reps") }
throw ImportError.missingColumns(missing.joined(separator: ", "))
}
let setTypeIdx = col("set type", "type")
let weightIdx = headers.firstIndex(of: "weight") ?? col("lbs", "load", "kg")
var rows: [SetRow] = []
var skippedType = 0
var skippedDate = 0
var skippedReps = 0
var firstDateSample = ""
for line in lines.dropFirst() {
let fields = parseLine(line)
func field(_ idx: Int?) -> String {
guard let idx, idx < fields.count else { return "" }
return fields[idx].trimmingCharacters(in: .whitespaces)
}
let setType = field(setTypeIdx).lowercased()
guard setType.contains("standard") else { skippedType += 1; continue }
let dateStr = field(dateIdx)
if firstDateSample.isEmpty { firstDateSample = dateStr }
guard let date = parseDate(dateStr) else { skippedDate += 1; continue }
let exerciseName = field(exerciseIdx)
guard !exerciseName.isEmpty else { continue }
guard let reps = Int(field(repsIdx)) else { skippedReps += 1; continue }
let weight = Double(field(weightIdx))
rows.append(SetRow(date: date, exerciseName: exerciseName, weight: weight, reps: reps))
}
if rows.isEmpty {
throw ImportError.noValidRows("Checked \(lines.count - 1) rows: \(skippedType) weren't standard sets, \(skippedDate) had unparseable dates (e.g. '\(firstDateSample)'), \(skippedReps) had bad reps.")
}
return rows
}
private static func parseDate(_ string: String) -> Date? {
let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "yyyy/MM/dd", "d-MMM-yyyy", "dd-MMM-yyyy", "MMM d, yyyy", "MMMM d, yyyy", "M-d-yyyy", "d/M/yyyy"]
for format in formats {
let formatter = DateFormatter()
formatter.dateFormat = format
formatter.locale = Locale(identifier: "en_US_POSIX")
if let date = formatter.date(from: string) { return date }
}
return nil
}
private static func splitLines(_ text: String) -> [String] {
var lines: [String] = []
var current = ""
var inQuotes = false
var i = text.startIndex
while i < text.endIndex {
let char = text[i]
if char == "\"" { inQuotes.toggle(); current.append(char) }
else if !inQuotes && (char == "\n" || char == "\r") {
lines.append(current); current = ""
let next = text.index(after: i)
if char == "\r" && next < text.endIndex && text[next] == "\n" { i = next }
} else { current.append(char) }
i = text.index(after: i)
}
if !current.isEmpty { lines.append(current) }
return lines
}
private static func parseLine(_ line: String) -> [String] {
var fields: [String] = []
var current = ""
var inQuotes = false
var i = line.startIndex
while i < line.endIndex {
let char = line[i]
if char == "\"" {
let next = line.index(after: i)
if inQuotes && next < line.endIndex && line[next] == "\"" { current.append("\""); i = line.index(after: next); continue }
inQuotes.toggle()
} else if char == "," && !inQuotes {
fields.append(current); current = ""
} else {
current.append(char)
}
i = line.index(after: i)
}
fields.append(current)
return fields
}
}
