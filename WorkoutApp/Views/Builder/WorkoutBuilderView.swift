import SwiftUI
import SwiftData
import PhotosUI
struct WorkoutBuilderView: View {
@Environment(\.modelContext) private var context
@Environment(\.dismiss) private var dismiss
private let editingDay: WorkoutDay?
private let editingSourceID: String?
@State private var selectedDate: Date
@State private var exercises: [BuilderExercise]
@State private var showingPaste = false
@State private var showingDatePicker = false
@State private var pastedText = ""
@State private var parseError: String?
@State private var exerciseSheet: ExerciseSheetState?
@State private var selectedPhoto: PhotosPickerItem?
@State private var isScanning = false
@State private var activeImportMethod: ImportMethod?
private enum ImportMethod { case paste, scan }
struct BuilderExercise: Identifiable {
let id = UUID(); var name: String; var targetSets: Int; var targetReps: String; var prescribedWeight: Double?; var coachNotes: String
}
enum ExerciseSheetState: Identifiable {
case add; case edit(BuilderExercise)
var id: String { switch self { case .add: "add"; case .edit(let ex): ex.id.uuidString } }
}
init(initialDate: Date) {
self.editingDay = nil; self.editingSourceID = nil
_selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
_exercises = State(initialValue: [])
}
init(editing day: WorkoutDay) {
self.editingDay = day; self.editingSourceID = day.sourceWorkoutID
_selectedDate = State(initialValue: day.date)
_exercises = State(initialValue: day.sortedExercises.map {
BuilderExercise(name: $0.exercise?.name ?? "Exercise", targetSets: $0.targetSets, targetReps: $0.targetReps, prescribedWeight: $0.prescribedWeight, coachNotes: $0.coachNotes)
})
}
private var isEditing: Bool { editingDay != nil }
var body: some View {
NavigationStack {
ZStack {
WorkoutTheme.background.ignoresSafeArea()
ScrollView {
VStack(alignment: .leading, spacing: 16) {
Text(isEditing ? "Edit Workout" : "New Workout").font(.poster(34)).foregroundStyle(WorkoutTheme.cream).textCase(.uppercase).tracking(-0.5).padding(.top, 8)
Button { if !isEditing { showingDatePicker = true } } label: {
HStack {
VStack(alignment: .leading, spacing: 2) {
Text("Date").font(.caption).foregroundStyle(WorkoutTheme.grayText).textCase(.uppercase)
Text(formattedDate(selectedDate)).font(.headline).foregroundStyle(.white)
}
Spacer()
if !isEditing { Image(systemName: "chevron.right").font(.caption).foregroundStyle(WorkoutTheme.grayText) }
}.padding(16).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
}.buttonStyle(.plain).disabled(isEditing)
HStack(spacing: 12) {
Button { withAnimation { showingPaste.toggle(); if showingPaste { activeImportMethod = .paste } } } label: {
VStack(spacing: 6) {
Image(systemName: "doc.on.clipboard").font(.title2).foregroundStyle(WorkoutTheme.lime)
Text("Paste").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
Text("From coach text").font(.caption).foregroundStyle(WorkoutTheme.grayText).lineLimit(1).minimumScaleFactor(0.8)
}.frame(maxWidth: .infinity, minHeight: 108).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
.overlay { if showingPaste && activeImportMethod == .paste { RoundedRectangle(cornerRadius: 20).stroke(WorkoutTheme.lime, lineWidth: 1.5) } }
}.buttonStyle(.plain)
PhotosPicker(selection: $selectedPhoto, matching: .images) {
VStack(spacing: 6) {
if isScanning {
ProgressView().tint(WorkoutTheme.lime)
} else {
Image(systemName: "text.viewfinder").font(.title2).foregroundStyle(WorkoutTheme.lime)
}
Text("Scan").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
Text("From screenshot").font(.caption).foregroundStyle(WorkoutTheme.grayText).lineLimit(1).minimumScaleFactor(0.8)
}.frame(maxWidth: .infinity, minHeight: 108).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
.overlay { if showingPaste && activeImportMethod == .scan { RoundedRectangle(cornerRadius: 20).stroke(WorkoutTheme.lime, lineWidth: 1.5) } }
}.buttonStyle(.plain).disabled(isScanning)
Button { exerciseSheet = .add } label: {
VStack(spacing: 6) {
Image(systemName: "plus").font(.title2).foregroundStyle(WorkoutTheme.lime)
Text("Add").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
Text("Build manually").font(.caption).foregroundStyle(WorkoutTheme.grayText).lineLimit(1).minimumScaleFactor(0.8)
}.frame(maxWidth: .infinity, minHeight: 108).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
}.buttonStyle(.plain)
}
.onChange(of: selectedPhoto) { _, newPhoto in
guard let newPhoto else { return }
Task { await scanPhoto(newPhoto) }
}
if showingPaste {
VStack(alignment: .leading, spacing: 12) {
TextEditor(text: $pastedText).frame(minHeight: 140).font(.body.monospaced()).foregroundStyle(.white).scrollContentBackground(.hidden).padding(8).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12))
Button(action: importPasted) { Text("Import into builder").frame(maxWidth: .infinity) }.buttonStyle(.lime).disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
if let parseError { Text(parseError).foregroundStyle(.red).font(.caption) }
Text("Paste the workout text, starting around the A) / B) lines.").font(.caption).foregroundStyle(WorkoutTheme.grayText)
}.padding(16).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
}
if !exercises.isEmpty {
VStack(alignment: .leading, spacing: 12) {
Text("Exercises \(exercises.count)").font(.poster(24)).foregroundStyle(.white).textCase(.uppercase).tracking(-0.5)
List {
ForEach(exercises) { exercise in
Button { exerciseSheet = .edit(exercise) } label: {
HStack(spacing: 12) {
VStack(alignment: .leading, spacing: 2) {
Text(exercise.name).font(.headline).foregroundStyle(.white)
Text("\(exercise.targetSets) x \(exercise.targetReps)").font(.caption).foregroundStyle(WorkoutTheme.grayText)
}
Spacer()
Image(systemName: "chevron.right").font(.caption).foregroundStyle(WorkoutTheme.grayText)
}.padding(14).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
}.buttonStyle(.plain)
.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)).listRowSeparator(.hidden)
}
.onDelete(perform: deleteExercises).onMove(perform: moveExercises)
}
.listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(true).frame(height: CGFloat(exercises.count) * 92)
}
}
if !exercises.isEmpty {
Button(isEditing ? "Save Changes" : "Save Workout") { save() }.buttonStyle(.lime).frame(maxWidth: .infinity)
}
}
.padding(.horizontal, 20).padding(.vertical, 12)
}
}
.toolbar {
ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(WorkoutTheme.cream) }
if !exercises.isEmpty { ToolbarItem(placement: .primaryAction) { EditButton().foregroundStyle(WorkoutTheme.cream) } }
}
.sheet(isPresented: $showingDatePicker) {
NavigationStack {
ZStack {
WorkoutTheme.background.ignoresSafeArea()
VStack {
DatePicker("Workout date", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical).colorScheme(.dark).tint(WorkoutTheme.lime).padding()
Spacer()
}
}
.navigationTitle("Pick a date").navigationBarTitleDisplayMode(.inline)
.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDatePicker = false }.foregroundStyle(WorkoutTheme.lime) } }
}
.presentationDetents([.medium])
}
.sheet(item: $exerciseSheet) { state in
switch state {
case .add: ExerciseFormView { newExercise in exercises.append(newExercise) }
case .edit(let exercise): ExerciseFormView(exercise: exercise) { updated in
if let index = exercises.firstIndex(where: { $0.id == exercise.id }) { exercises[index] = updated }
}
}
}
}
}
private func formattedDate(_ date: Date) -> String {
let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMM d"; return formatter.string(from: date)
}
private func scanPhoto(_ item: PhotosPickerItem) async {
isScanning = true
defer { isScanning = false; selectedPhoto = nil }
guard let data = try? await item.loadTransferable(type: Data.self),
let image = UIImage(data: data),
let text = await WorkoutTextRecognizer.recognizeText(in: image) else {
parseError = "Couldn't read any text from that image. Try a clearer screenshot."
withAnimation { showingPaste = true }
return
}
pastedText = text
parseError = nil
activeImportMethod = .scan
withAnimation { showingPaste = true }
}
private func importPasted() {
parseError = nil
guard let parsed = EmailWorkoutParser.parseMessage(subject: "", body: pastedText) else {
parseError = "Couldn't find a workout in that text. Make sure you pasted the exercises, starting around the A) / B) lines."; return
}
guard !parsed.exercises.isEmpty else { parseError = "No exercises found — try pasting more of the workout text."; return }
let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
var imported = parsed.toImportedWorkout(messageID: "builder-\(formatter.string(from: selectedDate))")
imported.date = selectedDate
let newExercises = imported.blocks.map {
BuilderExercise(name: $0.exerciseName, targetSets: $0.targetSets, targetReps: $0.targetReps, prescribedWeight: $0.prescribedWeight, coachNotes: $0.coachNotes)
}
exercises.append(contentsOf: newExercises); pastedText = ""
withAnimation { showingPaste = false }
}
private func deleteExercises(at offsets: IndexSet) { exercises.remove(atOffsets: offsets) }
private func moveExercises(from source: IndexSet, to destination: Int) { exercises.move(fromOffsets: source, toOffset: destination) }
private func save() {
let blocks = exercises.map {
ImportedBlock(exerciseName: $0.name, coachNotes: $0.coachNotes, targetSets: $0.targetSets, targetReps: $0.targetReps, prescribedWeight: $0.prescribedWeight)
}
let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
let dateString = formatter.string(from: selectedDate)
let sourceID = editingSourceID ?? "manual-\(dateString)"
let imported = ImportedWorkout(title: editingDay?.title ?? "Custom Workout", date: selectedDate, sourceID: sourceID, nutritionSummary: nil, blocks: blocks)
WorkoutImporter.importWorkout(imported, into: context)
dismiss()
}
}
private struct ExerciseFormView: View {
@Environment(\.dismiss) private var dismiss
@Query(sort: \Exercise.name) private var loggedExercises: [Exercise]
@Query(sort: \WorkoutDay.date, order: .reverse) private var recentDays: [WorkoutDay]
let existing: WorkoutBuilderView.BuilderExercise?
let onSave: (WorkoutBuilderView.BuilderExercise) -> Void
@State private var name: String
@State private var setsText: String
@State private var repsText: String
@State private var weightText: String
@State private var notes: String
init(exercise: WorkoutBuilderView.BuilderExercise? = nil, onSave: @escaping (WorkoutBuilderView.BuilderExercise) -> Void) {
self.existing = exercise; self.onSave = onSave
_name = State(initialValue: exercise?.name ?? "")
_setsText = State(initialValue: exercise.map { String($0.targetSets) } ?? "3")
_repsText = State(initialValue: exercise?.targetReps ?? "10")
_weightText = State(initialValue: exercise?.prescribedWeight.map { String(format: "%g", $0) } ?? "")
_notes = State(initialValue: exercise?.coachNotes ?? "")
}
private var isValid: Bool {
!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Int(setsText) ?? 0) > 0 && !repsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
private var allExerciseNames: [String] {
var seen = Set<String>()
var result: [String] = []
for n in loggedExercises.map(\.name) + ExerciseLibrary.all {
let key = Exercise.normalize(n)
if seen.insert(key).inserted { result.append(n) }
}
return result.sorted()
}
private var suggestions: [String] {
let q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
guard !q.isEmpty else { return [] }
return Array(allExerciseNames.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(5))
}
private func lastSetsReps(for exerciseName: String) -> String? {
let key = Exercise.normalize(exerciseName)
for day in recentDays {
if let we = day.exercises.first(where: { $0.exercise?.normalizedName == key }) {
return "\(we.targetSets) x \(we.targetReps)"
}
}
return nil
}
private func selectExercise(_ exerciseName: String) {
name = exerciseName
let key = Exercise.normalize(exerciseName)
for day in recentDays {
if let we = day.exercises.first(where: { $0.exercise?.normalizedName == key }) {
setsText = String(we.targetSets)
repsText = we.targetReps
if let w = we.prescribedWeight { weightText = String(format: "%g", w) }
break
}
}
}
var body: some View {
NavigationStack {
ZStack {
WorkoutTheme.background.ignoresSafeArea()
ScrollView {
VStack(spacing: 16) {
VStack(spacing: 0) {
TextField("Search or type exercise name", text: $name).foregroundStyle(.white).padding(14).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12))
if !suggestions.isEmpty {
VStack(spacing: 0) {
ForEach(suggestions, id: \.self) { suggestion in
Button { selectExercise(suggestion) } label: {
HStack {
Text(suggestion).foregroundStyle(.white).font(.subheadline)
Spacer()
if let last = lastSetsReps(for: suggestion) {
Text(last).font(.caption).foregroundStyle(WorkoutTheme.grayText)
}
}.padding(.vertical, 10).padding(.horizontal, 14)
}.buttonStyle(.plain)
}
}.background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.top, 8)
}
HStack {
Text("Sets").foregroundStyle(WorkoutTheme.softText); Spacer()
TextField("3", text: $setsText).keyboardType(.numberPad).multilineTextAlignment(.center).foregroundStyle(.white).frame(width: 64).padding(8).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12))
}.padding(.top, 12)
HStack {
Text("Reps").foregroundStyle(WorkoutTheme.softText); Spacer()
TextField("10", text: $repsText).multilineTextAlignment(.center).foregroundStyle(.white).frame(width: 80).padding(8).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12))
}.padding(.top, 12)
HStack {
Text("Weight (lb)").foregroundStyle(WorkoutTheme.softText); Spacer()
TextField("Optional", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.center).foregroundStyle(.white).frame(width: 100).padding(8).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12))
}.padding(.top, 12)
TextField("Coach notes (optional)", text: $notes, axis: .vertical).foregroundStyle(.white).padding(14).background(WorkoutTheme.tile).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.top, 12)
}
.padding(16).background(WorkoutTheme.card).clipShape(RoundedRectangle(cornerRadius: 20))
Button("Save Exercise") {
let exercise = WorkoutBuilderView.BuilderExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines), targetSets: Int(setsText) ?? 3, targetReps: repsText.trimmingCharacters(in: .whitespacesAndNewlines), prescribedWeight: Double(weightText.replacingOccurrences(of: ",", with: ".")), coachNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
onSave(exercise); dismiss()
}.buttonStyle(.lime).disabled(!isValid).frame(maxWidth: .infinity)
}
.padding(.horizontal, 20).padding(.vertical, 12)
}
}
.navigationTitle(existing == nil ? "Add Exercise" : "Edit Exercise").navigationBarTitleDisplayMode(.inline)
.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(WorkoutTheme.cream) } }
}
}
}
#Preview {
WorkoutBuilderView(initialDate: Date())
.modelContainer(for: [Exercise.self, WorkoutDay.self, WorkoutExercise.self, WorkoutSet.self, GymProfile.self], inMemory: true)
}
