import Foundation
import SwiftUI

// MARK: - Workout projection

/// The archive owns a read-only projection of completed workout records. The
/// cadence workout model remains the source for live work; this wrapper adds the
/// identity and date needed to understand past sessions in bio.
struct BioWorkoutSession: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let date: Date
    let durationMinutes: Int
    let info: BandishWorkoutInfo
    let muscleGroups: [String]
    let trendNote: String?

    var source: String? { info.source }

    var railMetaText: String {
        "\(BioDateParser.weekdayDate(date)) · \(durationMinutes) min"
    }

    var metaLine: String {
        var parts = [BioDateParser.weekdayDate(date), "\(durationMinutes) min"]
        if let calories = info.calories {
            parts.append("\(BioNumberText.grouped(calories)) kcal")
        }
        if let heartRate = info.realTime?.heartRate {
            parts.append("avg hr \(heartRate)")
        }
        if let actual = info.strain?.actual {
            let target = info.strain?.target.map(BioNumberText.oneDecimal)
            parts.append("strain \(BioNumberText.oneDecimal(actual))\(target.map { " of \($0)" } ?? "")")
        }
        if let source {
            parts.append(source)
        }
        return parts.joined(separator: " · ")
    }
}

extension BioModel {
    /// W20 is deliberately demo-only until the daemon's workout projection is
    /// part of the bio contract. The empty audit fixture must stay empty.
    var workoutSessions: [BioWorkoutSession] {
        guard BioDemo.enabled, BioDemo.auditState != .empty else { return [] }
        return BioDemo.workouts
    }
}

extension BioAccessibility {
    static let workoutArchive = "bio-workouts-archive"
    static let workoutRail = "bio-workouts-rail"
    static let workoutTrend = "bio-workouts-trend"
    static let workoutEmpty = "bio-workouts-empty"

    static func workout(_ id: String) -> String {
        "bio-workout-\(id)"
    }
}

// Extend the bio formatters instead of introducing a second number/date
// vocabulary for the archive's exact mock register.
extension BioDateParser {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }

    static func weekdayDate(_ date: Date) -> String {
        formatter("EEE MMM d").string(from: date).lowercased()
    }

    static func shortDate(_ date: Date) -> String {
        formatter("MMM d").string(from: date).lowercased()
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

extension BioNumberText {
    static func grouped(_ value: Double) -> String {
        workoutFormatter(maximumFractionDigits: 0).string(from: NSNumber(value: value)) ?? ""
    }

    static func oneDecimal(_ value: Double) -> String {
        workoutFormatter(maximumFractionDigits: 1).string(from: NSNumber(value: value)) ?? ""
    }

    private static func workoutFormatter(maximumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter
    }
}

// MARK: - Archive surface

struct BioWorkoutArchive: View {
    let sessions: [BioWorkoutSession]
    let isLoading: Bool
    @Binding var selectedID: String?
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedSession: BioWorkoutSession? {
        sessions.first { $0.id == selectedID } ?? sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            archiveAddress
            if isLoading {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 4,
                    label: "loading workouts",
                    accessibilityIdentifier: "bio-loading-workouts"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if sessions.isEmpty {
                BioWorkoutEmptyState()
            } else {
                BioRailDetail(hasDetail: selectedSession != nil) {
                    BioWorkoutSessionsRail(sessions: sessions, selectedID: $selectedID)
                } detail: {
                    if let selectedSession {
                        BioWorkoutSessionDetail(session: selectedSession, sessions: sessions)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .simultaneousGesture(backGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(BioAccessibility.workoutArchive)
        .accessibilityAction(.escape) {
            KStyle.withGesturePageMotion(reduceMotion: reduceMotion) { onBack() }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: sessions) { _, _ in selectFirstIfNeeded() }
    }

    private var archiveAddress: some View {
        HStack(spacing: KStyle.microSpacing) {
            Text("muscles")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
            Text("·")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
            Text("workout archive")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("muscles · workout archive")
    }

    private var backGesture: some Gesture {
        DragGesture(minimumDistance: KStyle.bioWorkoutBackGestureThreshold / 2)
            .onEnded { value in
                guard value.translation.width > KStyle.bioWorkoutBackGestureThreshold,
                      value.translation.width > abs(value.translation.height)
                else { return }
                KStyle.withGesturePageMotion(reduceMotion: reduceMotion) { onBack() }
            }
    }

    private func selectFirstIfNeeded() {
        guard selectedID == nil || !sessions.contains(where: { $0.id == selectedID }) else { return }
        guard let first = sessions.first else { return }
        selectedID = first.id
    }
}

private struct BioWorkoutEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("empty workout archive")
                .accessibilityIdentifier(BioAccessibility.workoutEmpty)
            Text("no workouts recorded yet · finished cadence blocks land here")
                .kFont(.content)
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BioWorkoutSessionsRail: View {
    let sessions: [BioWorkoutSession]
    @Binding var selectedID: String?

    private var selectedSession: BioWorkoutSession? {
        sessions.first { $0.id == selectedID } ?? sessions.first
    }

    private var footerText: String? {
        let dates = sessions.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let sources = Array(Set(sessions.compactMap(\.source))).sorted().joined(separator: " · ")
        let parts = [
            "\(sessions.count) sessions",
            "\(BioDateParser.shortDate(first)) to \(BioDateParser.shortDate(last))",
            sources,
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("workout archive rail")
                .accessibilityIdentifier(BioAccessibility.workoutRail)
            Text("sessions".uppercased())
                .kFont(.monoCaption)
                .tracking(KStyle.tracking(for: .monoCaption))
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
                .padding(.horizontal, KStyle.bioWorkoutRailHorizontalPadding)

            ForEach(sessions) { session in
                BioWorkoutSessionRailRow(
                    session: session,
                    isSelected: selectedSession?.id == session.id,
                    onTap: {
                        KStyle.withMotion { selectedID = session.id }
                    }
                )
            }

            if let footerText {
                Text(footerText)
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
                    .padding(.horizontal, KStyle.bioWorkoutRailHorizontalPadding)
                    .padding(.top, KStyle.bioWorkoutRailFooterTopSpacing)
            }
        }
        .padding(.vertical, KStyle.bioResearchRailVerticalPadding)
        .padding(.trailing, KStyle.bioDetailOverlap)
        .padding(.bottom, KStyle.bioSystemGridSpacing)
        .background {
            RoundedRectangle(cornerRadius: KStyle.bioResearchRailCornerRadius, style: .continuous)
                .fill(KStyle.emphasisInk.opacity(KStyle.bioResearchRailSurfaceOpacity))
        }
        // No .contain here: it creates a PlatformGroupContainer that owns
        // hitTest for the whole rail block and swallows row-Button taps. The
        // 1x1 rail marker carries the group identifier instead.
    }
}

private struct BioWorkoutSessionRailRow: View {
    let session: BioWorkoutSession
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("workout \(session.name)")
                .accessibilityIdentifier(BioAccessibility.workout(session.id))

            Button(action: onTap) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.bioResearchRailRowSpacing) {
                    Text(session.name)
                        .kFont(.content)
                        .foregroundStyle(isSelected
                            ? KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity)
                            : KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity))
                        .lineLimit(1)
                    Spacer(minLength: KStyle.smallSpacing)
                    Text(session.railMetaText)
                        .kFont(.monoCaption)
                        .foregroundStyle(isSelected
                            ? KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity)
                            : KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                        .lineLimit(1)
                }
                .padding(.vertical, KStyle.bioWorkoutRailRowVerticalPadding)
                .padding(.horizontal, KStyle.bioWorkoutRailHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                            .fill(KStyle.emphasisInk)
                    }
                }
                .padding(.trailing, isSelected
                    ? -KStyle.bioResearchRailSelectionOverhang
                    : KStyle.bioResearchInactiveSelectionOverhang)
                .shadow(
                    color: KStyle.nearBlack.opacity(isSelected ? KStyle.bioResearchActiveShadowOpacity : KStyle.bioResearchInactiveShadowOpacity),
                    radius: KStyle.bioResearchActiveShadowRadius,
                    y: KStyle.bioResearchActiveShadowY
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bio-workout-row-\(session.id)")
            .accessibilityLabel(session.name)
            .accessibilityValue(session.railMetaText)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .zIndex(isSelected ? KStyle.bioRailSelectedItemZIndex : KStyle.bioRailUnselectedItemZIndex)
    }
}

private struct BioWorkoutSessionDetail: View {
    let session: BioWorkoutSession
    let sessions: [BioWorkoutSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.name)
                .kFont(.nowTitle)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
            Text(session.metaLine)
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                .padding(.top, KStyle.bioResearchDetailTitleSpacing)
                .padding(.bottom, KStyle.bioWorkoutDetailMetaBottomSpacing)

            HStack(alignment: .top, spacing: KStyle.bioWorkoutDetailColumnSpacing) {
                BioWorkoutWorkColumn(session: session, sessions: sessions)
                BioWorkoutTrendColumn(session: session, sessions: sessions)
            }
        }
        .frame(minHeight: KStyle.bioResearchDetailMinimumHeight, alignment: .topLeading)
        .environment(\.kInkOnPaper, true)
        .accessibilityElement(children: .contain)
    }
}

private struct BioWorkoutWorkColumn: View {
    let session: BioWorkoutSession
    let sessions: [BioWorkoutSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BioWorkoutSectionLabel(text: "work")
            ForEach(session.info.exercises) { exercise in
                HStack(alignment: .firstTextBaseline, spacing: KStyle.bioResearchRailRowSpacing) {
                    Text(exercise.name)
                        .kFont(.content)
                        .foregroundStyle(exercise.completed
                            ? KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity)
                            : KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
                        .lineLimit(1)
                    Spacer(minLength: KStyle.smallSpacing)
                    if let setsRepsWeight = exercise.setsRepsWeight {
                        Text(setsRepsWeight + (exercise.completed ? "" : " · skipped"))
                            .kFont(.monoCaption)
                            .foregroundStyle(exercise.completed
                                ? KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity)
                                : KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, KStyle.bioWorkoutExerciseRowVerticalPadding)
            }

            if let tonnageText {
                Text(tonnageText)
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .padding(.top, KStyle.smallSpacing)
            }

            if !session.info.heartRateZones.isEmpty {
                BioWorkoutSectionLabel(text: "zones")
                    .padding(.top, KStyle.bioWorkoutDetailSectionLaterSpacing)
                BioWorkoutZones(info: session.info)
            }

            if !session.muscleGroups.isEmpty {
                BioWorkoutSectionLabel(text: "muscles")
                    .padding(.top, KStyle.bioWorkoutDetailSectionLaterSpacing)
                Text(session.muscleGroups.joined(separator: " · "))
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .padding(.top, KStyle.microSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tonnageText: String? {
        guard let current = session.info.tonnage?.current else { return nil }
        var text = "tonnage \(BioNumberText.grouped(current)) kg"
        if let change = session.info.tonnage?.change,
           let previous = sessions
            .filter({ $0.name == session.name && $0.date < session.date })
            .max(by: { $0.date < $1.date }) {
            let direction = change >= 0 ? "up" : "down"
            text += " · \(direction) \(BioNumberText.oneDecimal(abs(change)))% on \(BioDateParser.shortDate(previous.date))"
        }
        return text
    }
}

private struct BioWorkoutSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .kFont(.monoCaption)
            .tracking(KStyle.tracking(for: .monoCaption))
            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
    }
}

private struct BioWorkoutZones: View {
    let info: BandishWorkoutInfo

    private var zones: [BandishWorkoutZone] {
        let supplied = info.heartRateZones.reduce(into: [Int: BandishWorkoutZone]()) { result, zone in
            result[zone.zone] = zone
        }
        return (1...5).map { supplied[$0] ?? BandishWorkoutZone(zone: $0) }
    }

    private var maximumMinutes: Double {
        max(zones.map(\.minutes).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(zones, id: \.zone) { zone in
                HStack(alignment: .center, spacing: KStyle.bioWorkoutZoneSpacing) {
                    Text("z\(zone.zone)")
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                        .frame(width: KStyle.bioWorkoutZoneLabelWidth, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: KStyle.bioWorkoutZoneBarCornerRadius, style: .continuous)
                            .fill(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                            .frame(width: proxy.size.width * CGFloat(zone.minutes / maximumMinutes), height: KStyle.bioWorkoutZoneBarHeight)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: KStyle.bioWorkoutZoneBarHeight)
                    Text(BioNumberText.grouped(zone.minutes))
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                        .frame(width: KStyle.bioWorkoutZoneMinutesWidth, alignment: .trailing)
                }
                .frame(minHeight: KStyle.bioWorkoutZoneBarHeight)
            }
        }
    }
}

private struct BioWorkoutTrendColumn: View {
    let session: BioWorkoutSession
    let sessions: [BioWorkoutSession]

    private var trendSessions: [BioWorkoutSession] {
        sessions
            .filter { $0.name == session.name && $0.info.tonnage?.current != nil }
            .sorted { $0.date < $1.date }
    }

    private var trendValues: [Double] {
        trendSessions.compactMap { $0.info.tonnage?.current }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("workout trend")
                .accessibilityIdentifier(BioAccessibility.workoutTrend)
            if trendValues.count >= 3 {
                BioWorkoutSectionLabel(text: "trend · \(session.name) · \(trendValues.count) sessions")
                BioWorkoutTrendChart(sessions: trendSessions)
                if let trendNote = session.trendNote {
                    Text(trendNote)
                        .kFont(.content)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let sessionCount = sessions.filter { $0.name == session.name }.count
                let sessionText = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
                Text("\(session.name) · \(sessionText) · trend appears at 3")
                    .kFont(.content)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hint = session.info.recoveryHint {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.bioWorkoutHintLabelSpacing) {
                    Text("recorded hint".uppercased())
                        .kFont(.monoCaption)
                        .tracking(KStyle.tracking(for: .monoCaption))
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
                    Text(hint)
                        .kFont(.content)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                }
                .padding(.top, KStyle.bioWorkoutHintTopSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct BioWorkoutTrendChart: View {
    let sessions: [BioWorkoutSession]

    private var values: [Double] { sessions.compactMap { $0.info.tonnage?.current } }

    var body: some View {
        GeometryReader { proxy in
            let plotHeight = max(proxy.size.height - KStyle.bioWorkoutTrendBottomLabelOffset, 1)
            let points = BioSparklineMath.points(
                values,
                width: proxy.size.width,
                height: plotHeight,
                maximumPoints: values.count
            )
            ZStack(alignment: .topLeading) {
                if let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: plotHeight))
                        path.addLine(to: CGPoint(x: first.x, y: plotHeight))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [
                            KStyle.nearBlack.opacity(KStyle.bioHistoryAreaTopOpacity),
                            KStyle.nearBlack.opacity(KStyle.bioHistoryAreaBottomOpacity),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))

                    Path { path in
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(
                        KStyle.nearBlack.opacity(KStyle.bioHistoryLineOpacity),
                        lineWidth: KStyle.bioHistoryLineWidth
                    )
                }

                ForEach(points.indices, id: \.self) { index in
                    let point = points[index]
                    Circle()
                        .fill(KStyle.nearBlack.opacity(index == points.count - 1
                            ? KStyle.bioPaperPrimaryOpacity
                            : KStyle.bioHistoryLineOpacity))
                        .frame(
                            width: index == points.count - 1 ? KStyle.bioHistoryEndDotSize : KStyle.bioWorkoutTrendPointDotSize,
                            height: index == points.count - 1 ? KStyle.bioHistoryEndDotSize : KStyle.bioWorkoutTrendPointDotSize
                        )
                        .position(point)
                    Text(BioNumberText.grouped(values[index]))
                        .kFont(.monoCaptionDigit)
                        .foregroundStyle(KStyle.nearBlack.opacity(index == points.count - 1
                            ? KStyle.bioPaperPrimaryOpacity
                            : KStyle.bioPaperTertiaryOpacity))
                        .position(
                            x: min(max(point.x, KStyle.bioWorkoutTrendValueOffset), max(proxy.size.width - KStyle.bioWorkoutTrendValueOffset, KStyle.bioWorkoutTrendValueOffset)),
                            y: max(
                                min(point.y + (index == points.count - 1 ? -KStyle.bioWorkoutTrendValueOffset : KStyle.bioWorkoutTrendValueOffset), plotHeight),
                                KStyle.bioWorkoutTrendValueOffset
                            )
                        )
                }

                ForEach(sessions.indices, id: \.self) { index in
                    let point = points[index]
                    Text(BioDateParser.shortDate(sessions[index].date))
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioHistoryLabelOpacity))
                        .position(
                            x: min(max(point.x, KStyle.bioWorkoutTrendValueOffset), max(proxy.size.width - KStyle.bioWorkoutTrendValueOffset, KStyle.bioWorkoutTrendValueOffset)),
                            y: proxy.size.height - KStyle.microSpacing
                        )
                }
            }
        }
        .frame(height: KStyle.bioWorkoutTrendHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("tonnage across sessions")
        .accessibilityValue(sessions.map { "\(BioDateParser.shortDate($0.date)) \(BioNumberText.grouped($0.info.tonnage?.current ?? 0))" }.joined(separator: " · "))
    }
}
