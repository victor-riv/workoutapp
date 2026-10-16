import ActivityKit
import SwiftUI
import WidgetKit

/// Dynamic Island + Lock Screen UI for the rest timer Live Activity.
struct RestTimerWidget: Widget {
    private func timeText(_ total: Int) -> String {
        String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.headline)
                if context.state.isPaused {
                    Text(verbatim: "Paused · \(timeText(Int(context.state.pausedRemaining)))")
                        .font(.headline)
                } else {
                    Text(context.state.endDate, style: .timer)
                        .font(.headline)
                }
                Spacer()
                Text(context.attributes.exerciseName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.attributes.exerciseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if context.state.isPaused {
                            Text(verbatim: "Paused · \(timeText(Int(context.state.pausedRemaining)))")
                                .font(.title2.bold())
                        } else {
                            Text(context.state.endDate, style: .timer)
                                .font(.title2.bold())
                        }
                        Text("Rest Timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Group {
                    if context.state.isPaused {
                        Text(timeText(Int(context.state.pausedRemaining)))
                    } else {
                        Text(context.state.endDate, style: .timer)
                    }
                }
                .font(.caption2.bold())
                .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}
