import SwiftUI
struct BuildPlanReportRowView: View {
    let row: BuildPlanRow
    let units: [BuildRecord]
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tone: BuildResultTone {
        guard !units.isEmpty else {
            if row.hasBuilding { return .running }
            if row.hasNeedsYou { return .notes }
            return row.segments.allSatisfy { $0 == .done } ? .clean : .notes
        }
        return BuildCardGrammar.tone(for: units)
    }

    private var stepLine: String? {
        guard tone == .running else { return nil }
        return units.lazy
            .map(BuildCardGrammar.presentation(for:))
            .first(where: { $0.tone == .running })?
            .stepLine
    }

    private var resultLine: String? {
        guard tone == .failed || tone == .notes else { return nil }
        return units.lazy
            .map(BuildCardGrammar.presentation(for:))
            .compactMap { presentation in
                presentation.errorLine ?? presentation.noteLine
            }
            .first
    }

    /// Selected reuses the exact paper-ink flip the old expanded card used (Slice A's
    /// dark-on-white fix), so the "clear selected state" is a familiar look, not a new one.
    private var primaryInk: Color {
        isSelected
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
            : Color.white.opacity(KStyle.primaryTextOpacity)
    }
    private var secondaryInk: Color {
        isSelected
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.quaternaryTextOpacity)
    }
    private var fractionInk: Color {
        isSelected
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.buildDimmerOpacity)
    }

    var body: some View {
        Button {
            onSelect()
            onToggle()
        } label: {
            collapsedCard
        }
        .buttonStyle(.plain)
        .accessibilityHint(isSelected ? "close plan detail" : "open plan detail")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Keep the Button as the accessibility element. The label is stamped
        // explicitly below; combining the nested card surface can flatten the
        // control to XCUIElementTypeOther, which leaves the visible row
        // hittable but drops the selection action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.nickname), \(row.fraction)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("build-plan-row-\(row.id)")
    }

    private var collapsedCard: some View {
        Group {
            if isSelected {
                BuildGrammarCardSurface(isExpanded: true) {
                    rowContent
                        .environment(\.kInkOnPaper, true)
                }
            } else {
                rowContent
                    .padding(.vertical, KStyle.buildReportPlanRowVerticalPadding)
            }
        }
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isSelected)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .center, spacing: .zero) {
                Text(row.nickname)
                    .font(KStyle.contentFont)
                    .foregroundStyle(primaryInk)
                    .lineLimit(KStyle.singleLineLimit)
                Spacer(minLength: KStyle.buildReportPlanColumnGap)
                HStack(alignment: .center, spacing: KStyle.buildReportSegmentMetaGap) {
                    BuildSegmentBar(segments: row.segments)
                    Text(row.fraction)
                        .kFont(.monoCaptionDigit)
                        .foregroundStyle(fractionInk)
                        .fixedSize()
                }
            }

            if let stepLine {
                Text(stepLine.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(secondaryInk)
                    .lineLimit(KStyle.singleLineLimit)
                    .contentTransition(.opacity)
                    .animation(KStyle.chatContentSwapMotion(reduceMotion), value: stepLine)
            }

            if let resultLine {
                Text(resultLine.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(KStyle.chatContentSwapMotion(reduceMotion), value: resultLine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The plan's unit biography as the JUT — beside the report (regular width, inside the
/// rail) or over it (compact width, an elevated panel) — never grown in place (#26 slice B).
/// Same white paper card and on-paper flat record rendering the old in-place expanded row
/// used, so Slice A's ink/nesting fixes ride along unchanged; only where it renders moved.
struct BuildPlanDetailPanel: View {
    let row: BuildPlanRow
    let units: [BuildRecord]
    let planDetail: String?
    let cards: [BuildCard]
    let isPending: (BuildCard) -> Bool
    let isConfirming: (BuildCard, BuildCardOption) -> Bool
    let onChoose: (BuildCard, BuildCardOption) -> Void
    let onClose: () -> Void
    let onOpenEntity: (EntityRef) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool

    private var tone: BuildResultTone {
        guard !units.isEmpty else {
            if row.hasBuilding { return .running }
            if row.hasNeedsYou { return .notes }
            return row.segments.allSatisfy { $0 == .done } ? .clean : .notes
        }
        return BuildCardGrammar.tone(for: units)
    }

    var body: some View {
        BuildGrammarCardSurface(isExpanded: true) {
            VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    BuildCardResultDot(tone: tone)
                    Text(row.nickname)
                        .font(KStyle.blockDefaultTitleFont)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                    Spacer(minLength: KStyle.smallSpacing)
                    Text(row.fraction)
                        .kFont(.monoCaptionDigit)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity))
                        .fixedSize()
                    KActRow(
                        actions: [
                            KActItem(
                                id: "close",
                                label: "close",
                                accessibilityIdentifier: "build-plan-detail-close-\(row.id)"
                            ),
                        ],
                        variant: .build,
                        onSelect: { _ in onClose() }
                    )
                    .environment(\.kInkOnPaper, true)
                }
                .accessibilityHint("close plan detail")

                if let planDetail, !planDetail.isEmpty {
                    Text(planDetail.lowercased())
                        .font(KStyle.contentFont)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                BuildRecordSection(
                    title: "units",
                    records: units,
                    kind: .unit,
                    emptyText: nil,
                    relatedCards: { record in
                        BuildCardGrammar.cards(for: record, from: cards)
                    },
                    actionsEnabled: true,
                    isPending: isPending,
                    isConfirming: isConfirming,
                    onChoose: onChoose,
                    onOpenEntity: onOpenEntity,
                    isDepthOrigin: isDepthOrigin
                )
                .environment(\.buildRecordOnPaper, true)
            }
            .environment(\.kInkOnPaper, true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.nickname) detail, \(row.fraction)")
        .accessibilityIdentifier("build-plan-detail-\(row.id)")
    }
}

/// The segment bar: 8×3 pills, sage for done, white for building, amber for needs-you, dim
/// for pending. Building and needs-you pills breathe on the mock's 4s zen cycle; reduced
/// motion holds them still.
struct BuildSegmentBar: View {
    let segments: [BuildSegmentState]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kInkOnPaper) private var inkOnPaper

    var body: some View {
        if reduceMotion {
            bar(breath: KStyle.fullOpacity)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                bar(
                    breath: KStyle.breathOpacity(
                        at: context.date,
                        period: KStyle.buildSegmentBreathPeriod,
                        minimumOpacity: KStyle.buildSegmentBreathMinOpacity
                    )
                )
            }
        }
    }

    private func bar(breath: Double) -> some View {
        HStack(spacing: KStyle.buildSegmentPillGap) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: KStyle.buildSegmentPillRadius, style: .continuous)
                    .fill(Self.resolveColor(segment: segment, inkOnPaper: inkOnPaper))
                    .frame(width: KStyle.buildSegmentPillWidth, height: KStyle.buildSegmentPillHeight)
                    .opacity(breathes(segment) ? breath : KStyle.fullOpacity)
            }
        }
        .accessibilityHidden(true)
    }

    private func breathes(_ segment: BuildSegmentState) -> Bool {
        segment == .building || segment == .needsYou
    }

    /// Pure fill resolution, split out for unit testing without a view host (mirrors
    /// `BuildCardResultDot.resolveColor`). `emphasisInk` (near-white) and the dim-white
    /// pending fill both go invisible on the paper-selected row (#26 slice B) — same
    /// paper-ink flip Slice A already gave the result dot and the mono caption.
    static func resolveColor(segment: BuildSegmentState, inkOnPaper: Bool) -> Color {
        switch segment {
        case .done:
            return KStyle.liveSignal
        case .building:
            return inkOnPaper
                ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
                : KStyle.emphasisInk // mock --ink #f7f7f5
        case .needsYou:
            return KStyle.signalWarning
        case .failed:
            return KStyle.inlineError
        case .pending:
            return inkOnPaper
                ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
                : Color.white.opacity(KStyle.buildDimmerOpacity)
        }
    }
}

/// The always-visible composer: a context-chip row over the attach-free input bar with the
/// round white send control (reused token-for-token from KInputBar's control).
