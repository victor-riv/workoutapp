import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayWorkoutView()
                .tabItem {
                    Label("Today", systemImage: "dumbbell.fill")
                }
            NavigationStack {
                PlateCalculatorView()
            }
            .tabItem {
                Label("Plates", systemImage: "scalemass.fill")
            }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
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
