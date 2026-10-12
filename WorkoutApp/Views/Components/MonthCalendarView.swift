import SwiftUI

/// Month grid: each day is a circle with its date number.
/// Pink = a workout was logged that day, dim = rest.
/// Used on Today (current month, indicators only) and in History (any
/// month, tappable days — the selection gets a lime ring).
struct MonthCalendarView: View {
    /// Any date inside the month to render.
    let month: Date
    /// Day-of-month numbers (1...) that have a workout.
    let markedDays: Set<Int>
    /// When non-nil, days are tappable and the selection gets a pink ring.
    var selection: Binding<Int?>? = nil
    /// Draw a white ring around today (only meaningful for the current month).
    var showTodayRing: Bool = false

    private var cells: [Int?] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) ?? month
        let dayCount = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let leadingBlanks = (calendar.component(.weekday, from: startOfMonth) - 1 + 7) % 7
        return Array(repeating: nil, count: leadingBlanks) + (1 ... dayCount).map { Optional($0) }
    }

    private var todayDay: Int? {
        guard showTodayRing,
              Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
        else { return nil }
        return Calendar.current.component(.day, from: Date())
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 7),
            spacing: 12
        ) {
            ForEach(cells.indices, id: \.self) { index in
                if let day = cells[index] {
                    dayDot(day)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func dayDot(_ day: Int) -> some View {
        let isMarked = markedDays.contains(day)
        let circle = Circle()
            .fill(isMarked ? WorkoutTheme.pink : WorkoutTheme.dotEmpty)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text("\(day)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isMarked ? .black : WorkoutTheme.grayText)
            }
            .overlay {
                if todayDay == day {
                    Circle().stroke(.white, lineWidth: 2)
                } else if selection?.wrappedValue == day {
                    Circle().stroke(WorkoutTheme.lime, lineWidth: 2)
                }
            }
        if let selection {
            Button { selection.wrappedValue = day } label: { circle }
                .buttonStyle(.plain)
        } else {
            circle
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        MonthCalendarView(
            month: Date(),
            markedDays: [1, 2, 5, 8, 12],
            showTodayRing: true
        )
    }
    .padding()
    .workoutTabStyle()
}
