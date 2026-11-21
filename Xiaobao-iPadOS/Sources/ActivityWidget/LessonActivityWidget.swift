import ActivityKit
import SwiftUI
import WidgetKit

@main struct LessonActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            LessonActivityCard(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(context.state.appearance?.background.tint)
                .widgetURL(LessonActivityAttributes.courseLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LessonActivityCard(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                TScheduleMark(size: 16)
            } compactTrailing: {
                if let end = context.state.endsAt, !context.isStale, Date() < end {
                    LessonActivityMinutes(endingAt: end).font(.caption.monospacedDigit())
                        .frame(width: 62, alignment: .trailing)
                } else {
                    Image(systemName: "checkmark")
                }
            } minimal: {
                TScheduleMark(size: 16)
            }
            .widgetURL(LessonActivityAttributes.courseLink)
        }
    }
}
