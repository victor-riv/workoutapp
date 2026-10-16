//
//  TimerLiveActivityLiveActivity.swift
//  TimerLiveActivity
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TimerLiveActivityLiveActivity: Widget {
    private func timeText(_ total: Int) -> String {
        String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock screen UI
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.headline)
                if context.state.isPaused {
                    Text(verbatim: "Paused \u{00B7} \(timeText(Int(context.state.pausedRemaining)))")
                        .font(.headline)
                } else if context.state.endDate < Date() {
                    Text("0:00")
                        .font(.headline)
                } else {
                    let startDate = context.state.endDate.addingTimeInterval(-context.state.totalDuration)
                    Text(timerInterval: startDate...context.state.endDate, countsDown: true)
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
                        if context.state.isPaused {
                            Text(verbatim: "Paused \u{00B7} \(timeText(Int(context.state.pausedRemaining)))")
                                .font(.title2.bold())
                        } else if context.state.endDate < Date() {
                            Text("0:00")
                                .font(.title2.bold())
                        } else {
                            let startDate = context.state.endDate.addingTimeInterval(-context.state.totalDuration)
                            Text(timerInterval: startDate...context.state.endDate, countsDown: true)
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
                    } else if context.state.endDate < Date() {
                        Text("0:00")
                    } else {
                        let startDate = context.state.endDate.addingTimeInterval(-context.state.totalDuration)
                        Text(timerInterval: startDate...context.state.endDate, countsDown: true)
                    }
                }
                .font(.caption2.bold())
                .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
                    .font(.body)
            }
        }
    }
}
