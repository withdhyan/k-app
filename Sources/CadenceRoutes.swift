import Foundation
import SwiftUI
import UIKit
enum CadenceWeekLabel {
    // Founder 2026-08-05: "week 3 of november" — ordinal week-of-month + month.
    static func text(forISODate iso: String?) -> String {
        guard let iso = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty,
              let date = isoDate(iso) else { return "this week" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let week = calendar.component(.weekOfMonth, from: date)
        let month = monthName(for: date, calendar: calendar)
        return "week \(week) of \(month)"
    }

    private static func isoDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }

    private static func monthName(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date).lowercased()
    }
}

struct CadenceSecondaryRoutes: View {
    let isSuppressedExpanded: Bool
    let onSuppressed: () -> Void
    let nudges: [CadenceNudge]
    let loadText: String?
    let isLoading: Bool
    let pendingNudgeIDs: Set<String>
    let nudgeErrorTexts: [String: String]
    let onDisposition: (CadenceNudgeDisposition, CadenceNudge) -> Void
    let onRefresh: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: KStyle.gesturePageTransitionOffset))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            KActRow(
                actions: [KActItem(id: "suppressed")],
                variant: .cadence,
                selectedActionIDs: isSuppressedExpanded ? ["suppressed"] : [],
                onSelect: { _ in onSuppressed() }
            )
            .padding(.horizontal, KStyle.inputSidePadding)
            .padding(.bottom, isSuppressedExpanded ? KStyle.smallSpacing : KStyle.inputBottomPadding)

            if isSuppressedExpanded {
                CadenceSuppressedInlineDetail(
                    nudges: nudges,
                    loadText: loadText,
                    isLoading: isLoading,
                    pendingNudgeIDs: pendingNudgeIDs,
                    nudgeErrorTexts: nudgeErrorTexts,
                    onDisposition: onDisposition,
                    onRefresh: onRefresh
                )
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.bottom, KStyle.inputBottomPadding)
                .transition(detailTransition)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-secondary-routes")
    }
}

struct CadenceCapacityDetail: View {
    let entries: [CadenceCapacityEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            KMonoCaption("capacity", variant: .metadata, state: .active)
            if visibleEntries.isEmpty {
                Text("no capacity data")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            } else {
                ForEach(visibleEntries) { entry in
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        KMonoCaption(entry.mode, variant: .metadata)
                        KMonoCaption(detailText(for: entry), variant: .status, state: .active)
                    }
                }
            }
        }
        .padding(.top, KStyle.smallSpacing)
        .padding(.bottom, KStyle.smallSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-capacity-detail")
    }

    private var visibleEntries: [CadenceCapacityEntry] {
        entries.filter { $0.budgetText != nil || $0.remainingText != nil }
    }

    private func detailText(for entry: CadenceCapacityEntry) -> String {
        [
            entry.budgetText.map { "budget \($0)" },
            entry.remainingText.map { "left \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct CadenceSuppressedInlineDetail: View {
    let nudges: [CadenceNudge]
    let loadText: String?
    let isLoading: Bool
    let pendingNudgeIDs: Set<String>
    let nudgeErrorTexts: [String: String]
    let onDisposition: (CadenceNudgeDisposition, CadenceNudge) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            HStack {
                KActRow(
                    actions: [KActItem(id: "refresh")],
                    variant: .cadence,
                    onSelect: { _ in onRefresh() }
                )
                Spacer(minLength: 0)
            }

            if isLoading {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 4,
                    label: "loading suppressed nudges",
                    accessibilityIdentifier: "cadence-suppressed-loading"
                )
            } else if let loadText {
                Text(loadText.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
            } else if nudges.isEmpty {
                Text("no suppressed nudges today")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            } else {
                ForEach(nudges) { nudge in
                    CadenceNudgeCard(
                        nudge: nudge,
                        isPending: pendingNudgeIDs.contains(nudge.id),
                        errorText: nudgeErrorTexts[nudge.id],
                        onDisposition: onDisposition
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-suppressed-detail")
    }
}

struct CadenceWeeklyRetroInlineDetail: View {
    @ObservedObject var model: CadenceWeeklyRetroModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: KStyle.gesturePageTransitionOffset))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.retroDetailSectionSpacing) {
            HStack {
                KActRow(
                    actions: [KActItem(id: "refresh")],
                    variant: .cadence,
                    onSelect: { _ in Task { await model.refresh() } }
                )
                Spacer(minLength: 0)
            }

            if model.isLoading {
                CadenceWeeklyRetroLoadingView(variant: model.retro == nil ? .skeleton : .dot)
            } else if let failureText = model.failureText {
                Text(failureText.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if !model.surfaceWeeks.isEmpty {
                CadenceWeeklyRetroSubpage(weeks: model.surfaceWeeks)
            } else {
                Text("no week detail yet")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    .accessibilityIdentifier("cadence-retro-empty")
            }
        }
        .padding(.top, KStyle.smallSpacing)
        .padding(.bottom, KStyle.smallSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-subpage")
        .transition(detailTransition)
        .onAppear {
            model.loadIfNeeded()
        }
    }
}

private struct CadenceWeeklyRetroLoadingView: View {
    let variant: KLoadingVariant

    var body: some View {
        KLoadingPrimitive(
            variant: variant,
            lineCount: 3,
            label: "loading retro",
            accessibilityIdentifier: "cadence-retro-loading"
        )
    }
}

/// The end-of-week card is a resting origin in the cadence stream. Once opened,
/// it becomes a quiet, marked row while the detail grows in flow beneath it
/// (doctrine: spatial-continuity, recognition-over-recall).
struct CadenceWeeklyRetroFlowView: View {
    let week: CadenceRetroWeek
    let isOriginMarked: Bool
    let onOpen: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        Group {
            if isOriginMarked {
                quietRow
            } else {
                fullCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-card")
    }

    private var fullCard: some View {
        KPaperCard {
            VStack(alignment: .leading, spacing: KStyle.retroCardHeaderSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text("week in review")
                        .kFont(.monoCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    Spacer(minLength: KStyle.smallSpacing)
                    Text(dateRange)
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                }

                if let verdict = week.verdict {
                    Text(verdict)
                        .kFont(.content)
                        .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("cadence-retro-verdict")
                }

                CadenceWeeklyRetroMetricStrip(week: week)

                KActRow(
                    actions: [KActItem(
                        id: "open-week",
                        label: "open the week ›",
                        accessibilityIdentifier: "cadence-retro-open"
                    )],
                    variant: .cadence,
                    onSelect: { _ in onOpen() }
                )
                .padding(.top, KStyle.retroCardActTopSpacing)
            }
            .padding(.horizontal, KStyle.retroCardHorizontalPadding - KStyle.cardPadding)
            .padding(.vertical, KStyle.retroCardVerticalPadding - KStyle.cardPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("week in review, \(dateRange)")
        .accessibilityHint("opens the week")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var quietRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text("week in review")
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
            Text(dateRange)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
            Spacer(minLength: KStyle.smallSpacing)
            Text(scoreText)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
            KActRow(
                actions: [
                    KActItem(
                        id: "close",
                        label: "close",
                        accessibilityIdentifier: "cadence-retro-card-quiet"
                    ),
                ],
                variant: .cadence,
                onSelect: { _ in onCollapse() }
            )
            .accessibilityLabel("week in review, \(dateRange), \(scoreText)")
            .accessibilityHint("collapses the week detail")
            .accessibilityAddTraits(.isSelected)
        }
        .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .opacity(KStyle.secondaryTextOpacity)
    }

    private var dateRange: String {
        CadenceRetroDateFormatter.rangeText(start: week.start, end: week.end) ?? "this week"
    }

    private var scoreText: String {
        CadenceWeeklyRetroText.score(for: week)
    }
}

private struct CadenceWeeklyRetroMetricStrip: View {
    let week: CadenceRetroWeek

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.retroCardMetricSpacing) {
                metrics
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: KStyle.smallSpacing
            ) {
                metrics
            }
        }
        .padding(.vertical, KStyle.retroCardMetricVerticalPadding)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-metrics")
    }

    @ViewBuilder
    private var metrics: some View {
        CadenceWeeklyRetroMetric(label: "on-target days", value: CadenceWeeklyRetroText.score(for: week), identifier: "on-target-days")
        CadenceWeeklyRetroMetric(label: "acts", value: week.acts.map(String.init) ?? "—", identifier: "acts")
        CadenceWeeklyRetroMetric(label: "skips", value: week.skips.map(String.init) ?? "—", identifier: "skips")
        CadenceWeeklyRetroMetric(label: "rca ready", value: week.rcaReadyCount.map(String.init) ?? "—", identifier: "rca-ready")
    }
}

private struct CadenceWeeklyRetroMetric: View {
    let label: String
    let value: String
    let identifier: String

    var body: some View {
        HStack(spacing: .zero) {
            Text("\(label) ")
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
            Text(value)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .bold()
        }
            .lineLimit(KStyle.singleLineLimit)
            .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cadence-retro-metric-\(identifier)")
    }
}

struct CadenceWeeklyRetroSubpage: View {
    let weeks: [CadenceRetroWeek]
    @State private var selectedWeekID: String
    @State private var availableWidth: CGFloat = .zero
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(weeks: [CadenceRetroWeek]) {
        self.weeks = weeks
        _selectedWeekID = State(initialValue: weeks.first?.id ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.retroTabBottomSpacing) {
            KSelectorStrip(
                selection: $selectedWeekID,
                items: weeks.map { week in
                    KSelectorItem(
                        id: week.id,
                        title: CadenceWeeklyRetroText.tabTitle(for: week),
                        accessibilityLabel: CadenceWeeklyRetroText.tabTitle(for: week),
                        accessibilityIdentifier: "cadence-retro-week-\(week.id)"
                    )
                },
                accessibilityIdentifier: "cadence-retro-week-tabs"
            )

            if let week = selectedWeek {
                CadenceWeeklyRetroDetailPaper(week: week, compact: isCompact)
            }
        }
        .frame(maxWidth: KStyle.retroSurfaceMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, isCompact ? KStyle.columnMargin : KStyle.cardPadding)
        .padding(.bottom, KStyle.blockCardVerticalPadding)
        // The cadence stream already owns the vertical scroll. Measuring width in a
        // background preserves the compact handoff without introducing a
        // second vertical scroll view whose unconstrained height can collapse.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: CadenceRetroWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(CadenceRetroWidthPreferenceKey.self) { width in
            availableWidth = width
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-subpage")
        .onChange(of: weeks) { _, values in
            guard values.contains(where: { $0.id == selectedWeekID }) else {
                selectedWeekID = values.first?.id ?? ""
                return
            }
        }
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
            || (availableWidth > .zero && availableWidth <= KStyle.retroCompactWidthThreshold)
    }

    private var selectedWeek: CadenceRetroWeek? {
        weeks.first { $0.id == selectedWeekID } ?? weeks.first
    }
}

private struct CadenceRetroWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CadenceWeeklyRetroDetailPaper: View {
    let week: CadenceRetroWeek
    let compact: Bool

    var body: some View {
        BuildGrammarCardSurface(isExpanded: true) {
            VStack(alignment: .leading, spacing: KStyle.retroDetailSectionSpacing) {
                VStack(alignment: .leading, spacing: KStyle.retroDetailTitleSpacing) {
                    Text(CadenceRetroDateFormatter.heading(start: week.start) ?? "week in review")
                        .kFont(.blockActiveTitle)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    Text(CadenceWeeklyRetroText.subline(for: week))
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cadence-retro-detail-subline")
                }
                .padding(.bottom, KStyle.retroDetailSubtitleBottomSpacing)

                if !week.held.isEmpty {
                    CadenceWeeklyRetroDetailSection(title: "held") {
                        ForEach(week.held) { item in
                            CadenceWeeklyRetroLine(item: item, signal: .live, trailing: item.acts.map { "\($0) acts" })
                        }
                    }
                }

                if !week.slipped.isEmpty {
                    CadenceWeeklyRetroDetailSection(title: "slipped") {
                        ForEach(week.slipped) { item in
                            CadenceWeeklyRetroSlippedLine(item: item)
                        }
                        if let rca = week.rca {
                            CadenceWeeklyRetroRCAView(rca: rca)
                        }
                    }
                }

                if let nextWeek = week.nextWeek,
                   let bet = nextWeek.bet,
                   !bet.isEmpty {
                    CadenceWeeklyRetroDetailSection(title: "next week — one bet") {
                        CadenceWeeklyRetroBetLine(label: "bet", text: bet)
                        if let check = nextWeek.check, !check.isEmpty {
                            CadenceWeeklyRetroBetLine(label: "check", text: check, quiet: true)
                        }
                    }
                }
            }
            // BuildGrammarCardSurface contributes the shared 14pt paper inset;
            // keep the final detail measure at the blessed 30pt/18pt values.
            .padding(
                compact
                    ? KStyle.retroDetailCompactPadding - KStyle.cardLargePadding
                    : KStyle.retroDetailPadding - KStyle.cardLargePadding
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.kInkOnPaper, true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-detail-\(week.id)")
    }
}

private struct CadenceWeeklyRetroDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.retroDetailSectionTitleSpacing) {
            Text(title.uppercased())
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-section-\(title.replacingOccurrences(of: " ", with: "-"))")
    }
}

private struct CadenceWeeklyRetroLine: View {
    let item: CadenceRetroLineItem
    let signal: KSignal
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.retroDetailRowColumnSpacing) {
            Circle()
                .fill(signal.color)
                .frame(width: KStyle.retroDetailDotSize, height: KStyle.retroDetailDotSize)
                .accessibilityHidden(true)
            Text(item.text.lowercased())
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: KStyle.smallSpacing)
            if let trailing {
                KMonoCaption(trailing, variant: .metadata)
            }
        }
        .padding(.vertical, KStyle.retroDetailRowVerticalPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KStyle.nearBlack.opacity(KStyle.retroDetailDividerOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cadence-retro-line-\(item.id)")
    }
}

private struct CadenceWeeklyRetroSlippedLine: View {
    let item: CadenceRetroLineItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.retroDetailRowColumnSpacing) {
            Circle()
                .fill(KStyle.attentionSignal)
                .frame(width: KStyle.retroDetailDotSize, height: KStyle.retroDetailDotSize)
                .accessibilityHidden(true)
            Text(item.text.lowercased())
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: KStyle.smallSpacing)
        }
        .padding(.vertical, KStyle.retroDetailRowVerticalPadding)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KStyle.nearBlack.opacity(KStyle.retroDetailDividerOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-slipped-\(item.id)")
    }
}

private struct CadenceWeeklyRetroRCAView: View {
    let rca: CadenceRetroRCA

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.retroDetailRCASpacing) {
            Text("why · 3 levels")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
            ForEach(Array(rca.why.prefix(3).enumerated()), id: \.offset) { _, line in
                Text(line.lowercased())
                    .kFont(.content)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fixableCause = rca.fixableCause, !fixableCause.isEmpty {
                Text("the fixable cause")
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .padding(.top, KStyle.retroDetailRCASpacing)
                Text(fixableCause.lowercased())
                    .kFont(.content)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cadence-retro-rca-fixable-cause")
            }
        }
        .padding(.leading, KStyle.retroDetailRCAContentPadding)
        .padding(.vertical, KStyle.retroDetailRowVerticalPadding)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(KStyle.nearBlack.opacity(KStyle.retroDetailDividerOpacity))
                .frame(width: KStyle.hairlineWidth)
        }
        .padding(.leading, KStyle.retroDetailRCAIndent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-retro-rca-block")
    }
}

private struct CadenceWeeklyRetroBetLine: View {
    let label: String
    let text: String
    var quiet = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.retroDetailRowColumnSpacing) {
            Text(label)
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                .frame(width: KStyle.retroDetailRCAContentPadding * 3, alignment: .leading)
            Text(text.lowercased())
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(quiet ? KStyle.bioPaperSecondaryOpacity : KStyle.bioPaperPrimaryOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, KStyle.retroDetailRowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cadence-retro-\(label)")
    }
}

private enum CadenceWeeklyRetroText {
    static func score(for week: CadenceRetroWeek) -> String {
        let score = week.normalizedScore
        guard let numerator = score?.numerator else { return "—" }
        return denominatorText(score?.denominator).map { "\(numerator)/\($0)" } ?? String(numerator)
    }

    static func tabTitle(for week: CadenceRetroWeek) -> String {
        "\(CadenceRetroDateFormatter.rangeText(start: week.start, end: week.end) ?? "week") \(score(for: week))"
    }

    static func subline(for week: CadenceRetroWeek) -> String {
        if let subline = week.subline?.trimmingCharacters(in: .whitespacesAndNewlines), !subline.isEmpty {
            return subline.lowercased()
        }
        let score = score(for: week)
        var values = ["\(score) on target"]
        if let acts = week.acts { values.append("\(acts) acts") }
        if let skips = week.skips { values.append("\(skips) skips") }
        if let delta = week.vsLastWeek {
            let signed = delta < 0 ? "−\(abs(delta))" : "+\(delta)"
            values.append("vs last week \(signed)")
        }
        return values.joined(separator: " · ")
    }

    private static func denominatorText(_ denominator: Int?) -> String? {
        guard let denominator else { return nil }
        return String(denominator)
    }
}
