import SwiftUI
import UIKit

struct TScheduleMark: View {
    let size: CGFloat

    var body: some View {
        Image("TScheduleMark").renderingMode(.original).resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}

struct LessonActivityMinutes: View {
    let endingAt: Date
    var previewDate: Date? = nil

    var body: some View {
        // DateOffset floors to whole minutes. Shift the formatting anchor by
        // the remaining fraction of a minute so the last minute reads 1, not 0.
        // ActivityKit's stale date and the controller still use the real end.
        let style = SystemFormatStyle.DateOffset(to: endingAt.addingTimeInterval(59.999),
            allowedFields: [.minute], maxFieldCount: 1, sign: .never).locale(AppLanguage.locale)
        Group {
            if let previewDate { Text(style.format(previewDate)) }
            else { Text(.currentDate, format: style) }
        }
        .lineLimit(1)
    }
}

/// The Lock Screen and in-app preview use the same hierarchy and truncation.
struct LessonActivityCard: View {
    let state: LessonActivityAttributes.ContentState
    let isStale: Bool
    var previewDate: Date? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    private var countdownHeading: String {
        #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
        if state.isDemo { return String(localized: "演示 · 距离下课") }
        #endif
        return String(localized: "距离下课")
    }

    var body: some View {
        Group {
            if !isStale, let start = state.startsAt, let end = state.endsAt, start < end, (previewDate ?? Date()) < end {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            TScheduleMark(size: 18)
                            Text(countdownHeading)
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        LessonActivityMinutes(endingAt: end, previewDate: previewDate)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.leading)
                    }
                    // The encoded system clock text needs a finite layout lane;
                    // its intrinsic size otherwise leaves no room for the title.
                    .frame(width: typeSize.isAccessibilitySize ? 156 : 118, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(verbatim: state.appearance?.nextHeading ?? String(localized: "下一节课"))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        Text(verbatim: state.nextLesson ?? String(localized: "暂无下一节课"))
                            .font(.title2.weight(.semibold))
                            .lineLimit(1).truncationMode(.tail)
                            .multilineTextAlignment(.trailing)
                            .privacySensitive()
                            .accessibilityHint(previewDate != nil || state.nextLesson == nil ? "" : String(localized: "打开课表查看完整课名"))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 6) {
                    TScheduleMark(size: 18)
                    Text(previewDate == nil ? String(localized: "课表活动已结束") : String(localized: "暂无进行中的课程")).font(.subheadline)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 84)
    }
}

extension LessonActivityAppearance.Background {
    /// Local to the activity card, never a tint for controls or academic data.
    var tint: Color? {
        switch self {
        case .system: nil
        case .campusBlue: Color(uiColor: .systemBackground).mix(with: Color(uiColor: .systemBlue), by: 0.16)
        case .softGray: Color(uiColor: .secondarySystemBackground)
        }
    }
}
