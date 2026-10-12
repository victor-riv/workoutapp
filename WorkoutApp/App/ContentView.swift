import SwiftUI

/// Floating rounded tab bar in the app's theme: traditional icon + label
/// tabs inside a floating card, lime for the active tab, with a centered
/// lime + button that opens the workout builder from anywhere.
struct ContentView: View {
    @State private var selectedTab: Tab = .today
    @State private var showingBuilder = false
    @State private var builderDate = Date()

    enum Tab: Int, CaseIterable {
        case today, history, stats, settings

        var icon: String {
            switch self {
            case .today: "dumbbell.fill"
            case .history: "calendar"
            case .stats: "chart.bar.fill"
            case .settings: "gearshape.fill"
            }
        }

        var title: String {
            switch self {
            case .today: "Today"
            case .history: "History"
            case .stats: "Stats"
            case .settings: "Settings"
            }
        }
    }

    var body: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                tabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, -14)
            }
            .workoutTabStyle()
            .sheet(isPresented: $showingBuilder) {
                WorkoutBuilderView(initialDate: builderDate)
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today:
            TodayWorkoutView()
        case .history:
            HistoryView(onCreateWorkout: { date in
                builderDate = date
                showingBuilder = true
            })
        case .stats:
            StatsView()
        case .settings:
            SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.history)
            plusButton
            tabButton(.stats)
            tabButton(.settings)
        }
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tab ? WorkoutTheme.lime : WorkoutTheme.grayText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var plusButton: some View {
        Button {
            builderDate = Date()
            showingBuilder = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(WorkoutTheme.lime)
                .clipShape(Circle())
                .shadow(color: WorkoutTheme.lime.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
