import Foundation
import SwiftUI

enum DayArcSegmentState: Equatable {
    case past
    case now
    case ahead
}

struct DayArcSegment: Identifiable, Equatable {
    let id: Int
    let state: DayArcSegmentState
}

struct DayArcModel: Equatable {
    static let wakingStartHour = 6
    static let wakingEndHour = 22
    static let segmentHourCount = 2
    static let labelHourCount = 4

    let segments: [DayArcSegment]
    let hourLabels: [String]

    var hasCurrentSegment: Bool {
        segments.contains(where: { $0.state == .now })
    }

    init(now: Date, calendar: Calendar = CadenceDateParser.pinnedCalendar) {
        let dayStart = calendar.startOfDay(for: now)
        let wakingStart = calendar.date(
            byAdding: .hour,
            value: Self.wakingStartHour,
            to: dayStart
        ) ?? dayStart
        let segmentCount = (Self.wakingEndHour - Self.wakingStartHour) / Self.segmentHourCount

        segments = (0..<segmentCount).map { index in
            let startOffset = index * Self.segmentHourCount
            let endOffset = startOffset + Self.segmentHourCount
            let start = calendar.date(byAdding: .hour, value: startOffset, to: wakingStart) ?? wakingStart
            let end = calendar.date(byAdding: .hour, value: endOffset, to: wakingStart) ?? start
            let state: DayArcSegmentState
            if now >= end {
                state = .past
            } else if now >= start {
                state = .now
            } else {
                state = .ahead
            }
            return DayArcSegment(id: index, state: state)
        }

        hourLabels = stride(
            from: Self.wakingStartHour,
            through: Self.wakingEndHour,
            by: Self.labelHourCount
        ).map(Self.hourLabel)
    }

    var accessibilityLabel: String {
        let pastCount = segments.filter { $0.state == .past }.count
        let aheadCount = segments.filter { $0.state == .ahead }.count
        var parts = ["waking day"]
        if pastCount > 0 {
            parts.append("\(pastCount) past")
        }
        if hasCurrentSegment {
            parts.append("now")
        }
        if aheadCount > 0 {
            parts.append("\(aheadCount) ahead")
        }
        return parts.joined(separator: " · ")
    }

    private static func hourLabel(_ hour: Int) -> String {
        let suffix = hour < 12 ? "a" : "p"
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelveHour)\(suffix)"
    }
}

enum DayArcMotionSpec {
    // The v7 reference names this slow ambient breath explicitly. Reuse the
    // exact-port cycle and frame cadence instead of creating a second motion grammar.
    // Day-arc ambient now-breath is the cadence-v7 6s cycle (mock-pinned), distinct
    // from the started-dot's doctrine 1.8s breath — decoupled 2026-08-05.
    // Founder 2026-08-05: match the build segment-bar breath (was a stray 6s).
    static let breathingCycleDuration: TimeInterval = KStyle.buildSegmentBreathPeriod
    static let breathingFrameInterval = BandishCardMotionSpec.breathingFrameInterval
}

extension KStyle {
    static let dayArcSegmentHeight: CGFloat = 3 // build segment-bar spec (was 4)
    static let dayArcSegmentCornerRadius: CGFloat = 2
    static let dayArcSegmentSpacing: CGFloat = 3 // build segment-bar spec (was 4)
    static let dayArcLabelSpacing: CGFloat = 8
    static let dayArcTimelineSpacing: CGFloat = 40
    static let dayArcCurrentWidthWeight: CGFloat = 1.6
    static let dayArcRegularWidthWeight: CGFloat = 1
    static let dayArcPastOpacity = 0.55
    static let dayArcNowMinimumOpacity = 0.72
    static let dayArcAheadOpacity = 0.22
}

struct DayArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let now: Date
    var calendar = CadenceDateParser.pinnedCalendar

    var body: some View {
        let model = DayArcModel(now: now, calendar: calendar)
        let pausesBreath = reduceMotion || !model.hasCurrentSegment
        TimelineView(.animation(
            minimumInterval: DayArcMotionSpec.breathingFrameInterval,
            paused: pausesBreath
        )) { context in
            let clockDate = pausesBreath ? now : context.date
            dayArc(model: model, clockDate: clockDate)
        }
    }

    private func dayArc(model: DayArcModel, clockDate: Date) -> some View {
        VStack(alignment: .leading, spacing: KStyle.dayArcLabelSpacing) {
            segmentStrip(model: model, clockDate: clockDate)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.accessibilityLabel)

            HStack(spacing: .zero) {
                ForEach(model.hourLabels.indices, id: \.self) { index in
                    Text(model.hourLabels[index])
                        .kFont(.monoCaption)
                        .foregroundStyle(.white.opacity(KStyle.dayArcAheadOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                        .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                        .accessibilityHidden(true)

                    if index < model.hourLabels.count - 1 {
                        Spacer(minLength: .zero)
                    }
                }
            }
        }
        .padding(.bottom, KStyle.dayArcTimelineSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-day-arc")
    }

    private func segmentStrip(model: DayArcModel, clockDate: Date) -> some View {
        GeometryReader { proxy in
            let totalSpacing = KStyle.dayArcSegmentSpacing * CGFloat(max(0, model.segments.count - 1))
            let totalWidthWeight = model.segments.reduce(CGFloat.zero) { result, segment in
                result + widthWeight(for: segment.state)
            }
            let unitWidth = max(.zero, proxy.size.width - totalSpacing) / max(CGFloat(1), totalWidthWeight)

            HStack(spacing: KStyle.dayArcSegmentSpacing) {
                ForEach(model.segments) { segment in
                    RoundedRectangle(
                        cornerRadius: KStyle.dayArcSegmentCornerRadius,
                        style: .continuous
                    )
                    .fill(color(for: segment.state, at: clockDate))
                    .frame(
                        width: unitWidth * widthWeight(for: segment.state),
                        height: KStyle.dayArcSegmentHeight
                    )
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: KStyle.dayArcSegmentHeight)
    }

    private func widthWeight(for state: DayArcSegmentState) -> CGFloat {
        state == .now ? KStyle.dayArcCurrentWidthWeight : KStyle.dayArcRegularWidthWeight
    }

    private func color(for state: DayArcSegmentState, at date: Date) -> Color {
        switch state {
        case .past:
            return KStyle.liveSignal.opacity(KStyle.dayArcPastOpacity)
        case .now:
            return .white.opacity(KStyle.breathOpacity(
                at: date,
                period: DayArcMotionSpec.breathingCycleDuration,
                minimumOpacity: KStyle.dayArcNowMinimumOpacity
            ))
        case .ahead:
            return .white.opacity(KStyle.dayArcAheadOpacity)
        }
    }
}
