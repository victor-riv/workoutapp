import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayWorkoutView()
                .tabItem {
                    Label("Today", systemImage: "dumbbell.fill")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(WorkoutTheme.lime)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Exercise.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            WorkoutSet.self,
            GymProfile.self,
        ], inMemory: true)
}
