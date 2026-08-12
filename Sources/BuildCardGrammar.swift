import SwiftUI
struct BuildGlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        KGlassCard {
            content
        }
    }
}

enum BuildSignal: Equatable {
    case processing
    case recovering
    case error
    case idle

    var kSignal: KSignal {
        switch self {
        case .processing:
            return .live
        case .recovering:
            return .attention
        case .error:
            return .error
        case .idle:
            return .idle
        }
    }

    var color: Color {
        switch self {
        case .processing:
            return KStyle.liveSignal
        case .recovering:
            return KStyle.attentionSignal
        case .error:
            return KStyle.errorSignal
        case .idle:
            return Color.white.opacity(KStyle.idleSignalOpacity)
        }
    }

    static func from(state: String?) -> BuildSignal {
        let value = state?.lowercased() ?? ""
        if ["failed", "error", "killed", "orphaned", "rolled-back", "quarantined"].contains(value) {
            return .error
        }
        if ["recovering", "held", "queued", "cancelled", "blocked"].contains(value) {
            return .recovering
        }
        if ["building", "verifying", "integrating", "integrated", "deploying", "deployed", "processing", "running", "live"].contains(value) {
            return .processing
        }
        return value.isEmpty ? .idle : .recovering
    }
}

enum BuildResultTone: String, Equatable, Sendable {
    case running
    case clean
    case notes
    case failed

    var isProcessing: Bool {
        self == .running
    }
}

struct BuildCardSelectionState: Equatable, Sendable {
    private(set) var expandedID: String?

    mutating func select(_ id: String) {
        expandedID = id
    }

    mutating func toggle(_ id: String) {
        expandedID = expandedID == id ? nil : id
    }

    mutating func collapse() {
        expandedID = nil
    }
}

struct BuildCardGrammarPresentation: Equatable, Sendable {
    let tone: BuildResultTone
    let stepLine: String?
    let noteLine: String?
    let errorLine: String?
    let gateEvidenceLine: String?
    let stateHistory: [String]
}

enum BuildCardGrammar {
    private static let runningStates: Set<String> = [
        "building", "verifying", "integrating", "running", "processing",
        "deploying", "reviewing", "planning",
    ]

    private static let cleanStates: Set<String> = [
        "integrated", "complete", "completed", "done", "green", "verified",
        "deployed", "delivered", "landed", "passed", "merged", "shipped",
    ]

    private static let failureStates: Set<String> = [
        "failed", "error", "killed", "orphaned", "rolled-back", "quarantined",
        "line-stop", "line-stopped", "stopped",
    ]

    static func presentation(for record: BuildRecord) -> BuildCardGrammarPresentation {
        let tone = tone(
            for: record.state,
            note: record.resultNote,
            failureReason: record.failureReason ?? record.holdReason
        )
        let stepLine = tone == .running
            ? normalized(record.currentStep ?? record.detail)
            : nil
        let noteLine = tone == .notes
            ? normalized(record.resultNote ?? record.holdReason ?? record.detail)
            : nil
        let errorLine = tone == .failed
            ? normalized(record.failureReason ?? record.holdReason ?? record.detail)
            : nil
        let gateEvidenceLine = normalized(record.gateEvidence ?? (
            tone == .failed ? nil : record.detail
        ))

        return BuildCardGrammarPresentation(
            tone: tone,
            stepLine: stepLine,
            noteLine: noteLine,
            errorLine: errorLine,
            gateEvidenceLine: gateEvidenceLine,
            stateHistory: record.stateHistory
        )
    }

    static func tone(
        for state: String?,
        note: String? = nil,
        failureReason: String? = nil
    ) -> BuildResultTone {
        let value = normalized(state)?
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-") ?? ""
        if failureStates.contains(value)
            || value.hasPrefix("line-stop")
            || value.hasPrefix("failed")
            || value.hasPrefix("error") {
            return .failed
        }
        if hasNoteMarker(value) {
            return .notes
        }
        if runningStates.contains(value) {
            return .running
        }
        if cleanStates.contains(value) {
            return normalized(note)?.isEmpty == false || normalized(failureReason)?.isEmpty == false
                ? .notes
                : .clean
        }
        return .notes
    }

    static func tone(for records: [BuildRecord]) -> BuildResultTone {
        guard !records.isEmpty else { return .notes }
        if records.contains(where: {
            tone(for: $0.state, note: $0.resultNote, failureReason: $0.failureReason ?? $0.holdReason) == .failed
        }) {
            return .failed
        }
        if records.contains(where: {
            tone(for: $0.state, note: $0.resultNote, failureReason: $0.failureReason ?? $0.holdReason) == .running
        }) {
            return .running
        }
        if records.contains(where: {
            tone(for: $0.state, note: $0.resultNote, failureReason: $0.failureReason ?? $0.holdReason) == .notes
        }) {
            return .notes
        }
        return .clean
    }

    static func cards(for record: BuildRecord, from cards: [BuildCard]) -> [BuildCard] {
        let key = normalized(record.unitId ?? record.id)
        guard let key else { return [] }
        return cards.filter { normalized($0.unitId) == key }
    }

    private static func hasNoteMarker(_ value: String) -> Bool {
        value.contains("note") || value.contains("warning") || value.contains("retry")
            || value == "held" || value == "blocked" || value == "queued"
            || value == "recovering" || value == "cancelled"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text.lowercased()
    }
}

struct BuildStatusDot: View {
    let signal: BuildSignal

    var body: some View {
        KStatusDot(signal: signal.kSignal, size: .regular)
    }
}

struct BuildCardResultDot: View {
    let tone: BuildResultTone

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kInkOnPaper) private var inkOnPaper

    var body: some View {
        if tone.isProcessing, !reduceMotion {
            TimelineView(.periodic(from: Date(), by: KStyle.easeFastDuration)) { context in
                dot
                    .transaction { transaction in transaction.animation = nil }
                    .opacity(
                        KStyle.breathOpacity(
                            at: context.date,
                            period: KStyle.connectionSignalPeriod,
                            minimumOpacity: KStyle.chatThreadDotMinimumOpacity
                        )
                    )
            }
        } else {
            dot
        }
    }

    private var dot: some View {
        Circle()
            .fill(color)
            .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
            .accessibilityHidden(true)
    }

    private var color: Color {
        Self.resolveColor(tone: tone, inkOnPaper: inkOnPaper)
    }

    /// Pure fill resolution, split out for unit testing without a view host.
    static func resolveColor(tone: BuildResultTone, inkOnPaper: Bool) -> Color {
        switch tone {
        case .running, .clean:
            return inkOnPaper
                ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
                : Color.white.opacity(KStyle.primaryTextOpacity)
        case .notes:
            return KStyle.resultNotes
        case .failed:
            return KStyle.inlineError
        }
    }
}

struct BuildStatusPacketView: View {
    let packet: ViewPacket

    private var summary: BuildStatusSummary {
        BuildStatusSummary(packet: packet)
    }

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                HStack(alignment: .top, spacing: KStyle.rowSpacing) {
                    BuildStatusDot(signal: BuildSignal.from(state: summary.state))
                        .padding(.top, KStyle.blockDotTopPadding)
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        Text(summary.title)
                            .font(KStyle.blockDefaultTitleFont)
                        if let detail = summary.detail {
                            Text(detail)
                                .font(KStyle.contentFont)
                                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        }
                    }
                    Spacer(minLength: KStyle.tightRowSpacing)
                    if let state = summary.state {
                        BuildStateBadge(state: state)
                    }
                }

                BuildRecordSection(title: "units", records: summary.units, kind: .unit, emptyText: nil)
                    .environment(\.buildRecordFlatOnGlass, true)
                BuildRecordSection(title: "lanes", records: summary.lanes, kind: .lane, emptyText: nil)
                    .environment(\.buildRecordFlatOnGlass, true)
                BuildHistorySection(records: summary.history)

                if !summary.extraFields.isEmpty {
                    FieldList(fields: summary.extraFields)
                        .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                }
            }
        }
    }
}

struct BuildCardPacketView: View {
    let packet: ViewPacket

    private var summary: BuildCardSummary {
        BuildCardSummary(packet: packet)
    }

    var body: some View {
        KPaperCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if let brief = summary.brief {
                    decisionBriefBody(brief)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                        Text(summary.voiceTitle)
                            .font(KStyle.blockDefaultTitleFont)
                            .textSelection(.enabled)
                        Spacer(minLength: KStyle.tightRowSpacing)
                        if packet.isLoopbackOnlyBuildCard {
                            KMonoCaption("mac only", variant: .metadata)
                        } else if let state = summary.state {
                            BuildStateBadge(state: state)
                        }
                    }

                    if let body = summary.body {
                        Text(body)
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .textSelection(.enabled)
                    }

                    if !summary.extraFields.isEmpty {
                        FieldList(fields: summary.extraFields)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    }
                }
            }
        }
    }

    private func decisionBriefBody(_ brief: DecisionBrief) -> some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let whyNow = brief.whyNow {
                Text(whyNow)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let openQuestion = brief.openQuestion {
                Text(openQuestion)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            KMonoCaption(brief.blockerLine, variant: .metadata)
                .textSelection(.enabled)
            if let stakes = brief.stakes {
                KMonoCaption(stakes, variant: .metadata)
                    .textSelection(.enabled)
            }
        }
    }
}

struct BuildGrammarCardSurface<Content: View>: View {
    let isExpanded: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        content
            .padding(KStyle.cardLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(
                        isExpanded
                            ? Color.white.opacity(KStyle.chatThreadFinishedFillOpacity)
                            : Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            isExpanded ? KStyle.chatThreadFinishedFillOpacity : KStyle.hairlineOpacity
                        ),
                        lineWidth: KStyle.hairlineWidth
                    )
            }
            .shadow(
                color: Color.black.opacity(isExpanded ? KStyle.chatThreadCardShadowOpacity : .zero),
                radius: isExpanded ? KStyle.chatThreadCardShadowRadius : .zero,
                y: isExpanded ? KStyle.chatThreadCardShadowY : .zero
            )
            .contentShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
            .animation(KStyle.chatExpansionMotion(reduceMotion), value: isExpanded)
    }
}
