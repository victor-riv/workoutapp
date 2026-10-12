import SwiftUI

/// Floating rounded tab bar in the app's theme: traditional icon + label
/// tabs inside a floating card, lime for the active tab.
struct ContentView: View {
    @State private var selectedTab: Tab = .today

    enum Tab: Int, CaseIterable {
        case today, history, settings

        var icon: String {
            switch self {
            case .today: "dumbbell.fill"
            case .history: "calendar"
            case .settings: "gearshape.fill"
            }
        }

        var title: String {
            switch self {
            case .today: "Today"
            case .history: "History"
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
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today:
            TodayWorkoutView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
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
        }
        .padding(.horizontal, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
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
