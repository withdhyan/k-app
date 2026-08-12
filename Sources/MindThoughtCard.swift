import SwiftUI
import UIKit

enum MindThoughtTextRole: String, CaseIterable, Equatable {
    case entity
    case claim
    case reference
}

struct MindThoughtTypeMetric: Equatable {
    let role: MindThoughtTextRole
    let pointSize: CGFloat
    let textStyle: UIFont.TextStyle
}

enum MindThoughtTypography {
    static let snapshot: [MindThoughtTypeMetric] = [
        MindThoughtTypeMetric(role: .entity, pointSize: 16, textStyle: .callout),
        MindThoughtTypeMetric(role: .claim, pointSize: 14, textStyle: .subheadline),
        MindThoughtTypeMetric(role: .reference, pointSize: 11, textStyle: .caption1),
    ]

    static func metric(for role: MindThoughtTextRole) -> MindThoughtTypeMetric {
        snapshot.first { $0.role == role }!
    }
}

enum MindThoughtMotionFamily: String, Hashable {
    case timingCurve
}

enum MindThoughtMotionName: String, CaseIterable {
    case selectionFlood
    case textColor
    case evidenceReveal
}

struct MindThoughtMotionToken: Equatable {
    let name: MindThoughtMotionName
    let duration: Double
    let controlPoints: [Double]

    var family: MindThoughtMotionFamily { .timingCurve }
}

enum MindThoughtMotionSpec {
    // The one-second selection flood is a named founder exception to the
    // sub-300ms UI rule. It explains the primary-card state change and is
    // deliberately tweened: springs, bounce, and overshoot are forbidden.
    static let tokens: [MindThoughtMotionToken] = [
        MindThoughtMotionToken(
            name: .selectionFlood,
            duration: KStyle.mindThoughtSelectionDuration,
            controlPoints: KStyle.mindThoughtZenControlPoints
        ),
        MindThoughtMotionToken(
            name: .textColor,
            duration: KStyle.mindThoughtTextDuration,
            controlPoints: KStyle.mindThoughtZenControlPoints
        ),
        MindThoughtMotionToken(
            name: .evidenceReveal,
            duration: KStyle.mindThoughtRevealDuration,
            controlPoints: KStyle.mindThoughtDefaultControlPoints
        ),
    ]

    static func token(named name: MindThoughtMotionName) -> MindThoughtMotionToken {
        tokens.first { $0.name == name }!
    }
}

extension KStyle {
    static let mindThoughtSelectedPadding: CGFloat = 24
    static let mindThoughtRowVerticalPadding: CGFloat = 16
    static let mindThoughtArchivedTopPadding: CGFloat = 40
    static let mindThoughtSilentDayTopPadding: CGFloat = 64
    static let mindThoughtClaimTopPadding: CGFloat = 4
    static let mindThoughtEvidenceTopPadding: CGFloat = 8
    static let mindThoughtExpansionSpacing: CGFloat = 16
    static let mindThoughtReferenceIndent: CGFloat = 16
    static let mindThoughtSelectedPrimaryOpacity = KStyle.primaryTextOpacity
    static let mindThoughtSelectedSecondaryOpacity = KStyle.secondaryTextOpacity
    static let mindThoughtSelectedMetadataOpacity = KStyle.tertiaryTextOpacity
    static let mindThoughtSelectedHairlineOpacity = KStyle.hairlineOpacity
    static let mindThoughtSelectedBackground = Color.white
    static let mindThoughtSelectedInk = Color.black
    static let mindThoughtUnselectedInk = Color.white
    static let mindThoughtCommentFieldOpacity = 0.04

    // Named v18 founder exception: the white-card flood and coordinated ink
    // change are deliberately slow enough to explain the primary-state change.
    static let mindThoughtSelectionDuration = 1.0
    static let mindThoughtTextDuration = 0.7
    static let mindThoughtRevealDuration = 0.5
    static let mindThoughtZenControlPoints = [0.15, 0.0, 0.15, 1.0]
    static let mindThoughtDefaultControlPoints = [0.25, 0.1, 0.25, 1.0]

    static func mindThoughtFont(_ role: MindThoughtTextRole) -> Font {
        let metric = MindThoughtTypography.metric(for: role)
        let base = UIFont.systemFont(ofSize: metric.pointSize, weight: .regular)
        let scaled = UIFontMetrics(forTextStyle: metric.textStyle).scaledFont(for: base)
        return Font(scaled)
    }

    static func mindThoughtAnimation(
        _ name: MindThoughtMotionName,
        reduceMotion: Bool
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let token = MindThoughtMotionSpec.token(named: name)
        return .timingCurve(
            token.controlPoints[0],
            token.controlPoints[1],
            token.controlPoints[2],
            token.controlPoints[3],
            duration: token.duration
        )
    }
}

extension KCopy {
    static let mindSilentDay = "the mind surfaced nothing today — evidence was thin, and silence beats a stretch."
    static let mindLoading = "reading the mind pass"
    static let mindUnreachable = "k is unreachable"
    static let mindRefreshing = "refreshing"
    static let mindActOn = "act on"
    static let mindLater = "later"
    static let mindArchive = "archive"
    static let mindRetry = "retry"
    static let mindShowEvidence = "show evidence"
    static let mindHideEvidence = "hide evidence"
    static let mindCommentPlaceholder = "comment — the thread syncs with chat"
    static let mindCommentSend = "send comment"
    static let mindContinueInChat = "continue in chat →"
    static let mindResolveComment = "resolve"
    static let mindCommentResolved = "resolved"
    static let mindUseTrailPrefix = "used →"
    static let mindActedPrefix = "acted"
    static let mindArchivedPrefix = "archived"

    static func mindWeekLine(active: Int, unjudged: Int, archived: Int) -> String? {
        guard active > 0 || archived > 0 else { return nil }
        var parts = ["\(active) surfaced"]
        if unjudged > 0 { parts.append("\(unjudged) unjudged") }
        if archived > 0 { parts.append("\(archived) archived") }
        return parts.joined(separator: " · ")
    }

    static func mindArchivedCount(_ count: Int, isExpanded: Bool) -> String {
        "\(isExpanded ? "hide" : "show") archived (\(count))"
    }

    static func mindEvidenceCount(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 piece of evidence" : "\(count) pieces of evidence"
    }

    static func mindEvidenceCount(shown: Int, total: Int) -> String? {
        guard shown > 0, total > 0 else { return nil }
        let boundedShown = min(shown, total)
        if boundedShown == total {
            return mindEvidenceCount(total)
        }
        return "\(boundedShown) of \(total) pieces of evidence"
    }

    static func mindVerdictHint(action: String, subject: String) -> String {
        "record \(action) for \(subject)"
    }

    static func mindLatest(_ relativeDay: String) -> String {
        "latest \(relativeDay)"
    }
}

/// A small, additive state marker for the mind-v18 card grammar. Unknown or
/// missing wire values remain `.none` so a live packet never looks fresher than
/// the daemon proved it to be.
enum MindArtifactSignal: String, Codable, Equatable, Sendable {
    case none
    case fresh
    case acted
}

struct MindUseTrailEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var at: String?

    init(id: String, text: String, at: String? = nil) {
        self.id = id
        self.text = Self.normalized(text) ?? text
        self.at = Self.normalized(at)
    }

    var displayText: String {
        guard let at, !at.isEmpty else { return text }
        return "\(text) · \(at)"
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct MindCommentTurn: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var role: String
    var text: String
    var at: String?

    init(id: String, role: String, text: String, at: String? = nil) {
        self.id = id
        self.role = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.at = at?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFounder: Bool {
        ["founder", "you", "user"].contains(role)
    }
}

struct MindCommentReceipt: Codable, Equatable, Sendable {
    var who: String
    var at: String
    var change: String

    init(who: String = "you", at: String = "today", change: String) {
        self.who = who.trimmingCharacters(in: .whitespacesAndNewlines)
        self.at = at.trimmingCharacters(in: .whitespacesAndNewlines)
        self.change = change.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayText: String {
        [KCopy.mindCommentResolved, who, at, change]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct MindCommentThread: Codable, Equatable, Sendable {
    var comments: [MindCommentTurn]
    var receipt: MindCommentReceipt?

    init(comments: [MindCommentTurn] = [], receipt: MindCommentReceipt? = nil) {
        self.comments = comments
        self.receipt = receipt
    }

    var isResolved: Bool { receipt != nil }
    var hasContent: Bool { !comments.isEmpty || receipt != nil }
}

struct MindThoughtPresentation: Equatable {
    let entity: String?
    let claim: String
    let evidenceLine: String?
    let evidenceReferences: [String]
    let isArchived: Bool
    let signal: MindArtifactSignal
    let useTrail: [MindUseTrailEntry]
    let commentThread: MindCommentThread?
    let verdictConsequences: [MindVerdict: String]

    init(
        output: MindOutput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        // Depth facts are additive and optional. A live packet without the
        // typed v18 fields stays quiet; only explicit wire values reach the
        // card so a use trail or thread never looks server-owned by inference.
        let entity = Self.oneLine(output.label)
        let claim = Self.oneLine(output.observation)
            ?? Self.oneLine(output.what)
            ?? Self.oneLine(output.brief?.openQuestion)
            ?? Self.embeddedObservation(in: output.statement)
            ?? Self.oneLine(output.nextAction)
            ?? Self.oneLine(output.statement)
            ?? ""
        self.entity = entity?.caseInsensitiveCompare(claim) == .orderedSame ? nil : entity
        self.claim = claim
        evidenceLine = MindThoughtEvidenceLineFormatter.line(
            for: output,
            now: now,
            calendar: calendar
        )
        evidenceReferences = MindEvidenceDetailFormatter.lines(
            previews: output.evidencePreviews,
            evidence: output.evidence,
            now: now,
            calendar: calendar
        ).filter { line in
            !line.hasSuffix("details on the desk")
        }
        isArchived = output.verdict == .junk
        signal = output.artifactSignal
        useTrail = output.useTrail
        commentThread = output.commentThread
        verdictConsequences = output.verdictConsequences
    }

    var canDrillIntoEvidence: Bool {
        !evidenceReferences.isEmpty
    }

    var accessibilityLabel: String {
        [entity, claim, evidenceLine]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private static func oneLine(_ value: String?) -> String? {
        let text = (value ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func embeddedObservation(in value: String) -> String? {
        let marker = "observation:"
        guard let markerRange = value.range(of: marker, options: .caseInsensitive) else { return nil }
        let remainder = String(value[markerRange.upperBound...])
        let end = remainder.range(of: "consider:", options: .caseInsensitive)?.lowerBound
            ?? remainder.endIndex
        return oneLine(
            String(remainder[..<end])
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        )
    }
}

enum MindChatThreadHandoffComposer {
    static func handoff(
        for output: MindOutput,
        comment: String? = nil
    ) -> ChatThreadHandoff {
        let presentation = MindThoughtPresentation(output: output)
        let anchorText = [presentation.entity, presentation.claim]
            .compactMap { value in
                let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized?.isEmpty == false ? normalized : nil
            }
            .joined(separator: " — ")
        let normalizedComment = comment?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ChatThreadHandoff(
            anchorID: output.outputId,
            anchorText: anchorText,
            entities: EntityRef.unique(output.entityRefs).map(\.jsonValue),
            initialComment: normalizedComment?.isEmpty == false ? normalizedComment : nil
        )
    }
}

enum MindThoughtEvidenceLineFormatter {
    static func line(
        for output: MindOutput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        if let boundedCount = boundedEvidenceCount(in: output.packet.fields ?? [:]) {
            var parts = [KCopy.mindEvidenceCount(shown: boundedCount.shown, total: boundedCount.total)]
                .compactMap { $0 }
            if let latest = latestDate(for: output, calendar: calendar) {
                parts.append(KCopy.mindLatest(
                    DecisionEvidenceLineFormatter.relativeDay(for: latest, now: now, calendar: calendar)
                ))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ").lowercased()
        }

        if let summary = DecisionEvidenceLineFormatter.line(
            for: output.evidenceSummary,
            now: now,
            calendar: calendar
        ) {
            return summary
        }

        if let previewSummary = DecisionEvidencePreviewFormatter.summaryLine(
            for: output.evidencePreviews,
            now: now,
            calendar: calendar
        ) {
            return previewSummary
        }

        return KCopy.mindEvidenceCount(output.evidence.count)
    }

    private static func boundedEvidenceCount(
        in fields: [String: ViewPacketJSONValue]
    ) -> (shown: Int, total: Int)? {
        let candidates = [fields["evidenceCount"], fields["evidence_count"]]
        for candidate in candidates {
            guard let object = candidate?.objectValue,
                  let shown = integer(object["shown"]),
                  let total = integer(object["total"]),
                  shown > 0,
                  total > 0
            else { continue }
            return (shown, total)
        }
        return nil
    }

    private static func latestDate(
        for output: MindOutput,
        calendar: Calendar
    ) -> Date? {
        let summaryDate = output.evidenceSummary?.latestAt.flatMap {
            DecisionEvidenceLineFormatter.date(from: $0, calendar: calendar)
        }
        let previewDate = output.evidencePreviews.compactMap { preview in
            preview.at.flatMap {
                DecisionEvidenceLineFormatter.date(from: $0, calendar: calendar)
            }
        }.max()
        return [summaryDate, previewDate].compactMap { $0 }.max()
    }

    private static func integer(_ value: ViewPacketJSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .number(let number) where number.isFinite:
            return Int(number.rounded(.down))
        case .string(let string):
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

struct MindThoughtListState: Equatable {
    let active: [MindOutput]
    let archived: [MindOutput]

    init(outputs: [MindOutput]) {
        active = outputs.filter { $0.verdict != .junk }
        archived = outputs.filter { $0.verdict == .junk }
    }
}

struct MindThoughtVerdictAction: Identifiable, Equatable {
    enum Tone: Equatable, Hashable {
        case primary
        case secondary
        case naked
    }

    let verdict: MindVerdict
    let label: String
    let iconName: String
    let showsLabel: Bool
    let tone: Tone

    var id: String { verdict.rawValue }
}

enum MindThoughtVerdictPresenter {
    static let actions: [MindThoughtVerdictAction] = [
        MindThoughtVerdictAction(
            verdict: .actOn,
            label: KCopy.mindActOn,
            iconName: "arrow.up",
            showsLabel: true,
            tone: .primary
        ),
        MindThoughtVerdictAction(
            verdict: .nod,
            label: KCopy.mindLater,
            iconName: "clock",
            showsLabel: false,
            tone: .secondary
        ),
        MindThoughtVerdictAction(
            verdict: .junk,
            label: KCopy.mindArchive,
            iconName: "trash",
            showsLabel: false,
            tone: .naked
        ),
    ]
}

struct MindThoughtCard: View {
    let output: MindOutput
    let isSelected: Bool
    let pendingVerdict: MindVerdict?
    let actionsDisabled: Bool
    let submissionErrorText: String?
    let preservesLegacyCardIdentifier: Bool
    let onSelect: () -> Void
    let onOpenEntity: (EntityRef) -> Void
    let onVerdict: (MindVerdict) -> Void
    let onRetry: () -> Void
    let onComment: ((String) -> Void)?
    let onContinueInChat: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var evidenceExpanded = false
    @State private var trailExpanded = false
    @State private var commentText = ""
    @State private var trailEntries: [MindUseTrailEntry]
    @State private var commentThread: MindCommentThread

    init(
        output: MindOutput,
        isSelected: Bool,
        pendingVerdict: MindVerdict? = nil,
        actionsDisabled: Bool = false,
        submissionErrorText: String? = nil,
        preservesLegacyCardIdentifier: Bool = false,
        onSelect: @escaping () -> Void,
        onOpenEntity: @escaping (EntityRef) -> Void = { _ in },
        onVerdict: @escaping (MindVerdict) -> Void,
        onRetry: @escaping () -> Void,
        onComment: ((String) -> Void)? = nil,
        onContinueInChat: (() -> Void)? = nil
    ) {
        self.output = output
        self.isSelected = isSelected
        self.pendingVerdict = pendingVerdict
        self.actionsDisabled = actionsDisabled
        self.submissionErrorText = submissionErrorText
        self.preservesLegacyCardIdentifier = preservesLegacyCardIdentifier
        self.onSelect = onSelect
        self.onOpenEntity = onOpenEntity
        self.onVerdict = onVerdict
        self.onRetry = onRetry
        self.onComment = onComment
        self.onContinueInChat = onContinueInChat
        _trailEntries = State(initialValue: output.useTrail)
        _commentThread = State(initialValue: output.commentThread ?? MindCommentThread())
    }

    private var presentation: MindThoughtPresentation {
        MindThoughtPresentation(output: output)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thoughtText
                .animation(
                    KStyle.mindThoughtAnimation(.textColor, reduceMotion: reduceMotion),
                    value: isSelected
                )
            evidence
                .animation(
                    KStyle.mindThoughtAnimation(.textColor, reduceMotion: reduceMotion),
                    value: isSelected
                )

            useTrail

            if isSelected {
                verdicts
                    .padding(.top, KStyle.mindThoughtExpansionSpacing)

                if let submissionErrorText {
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        KMonoCaption(submissionErrorText, variant: .inlineError, state: .error)
                        KActRow(
                            actions: [
                                KActItem(
                                    id: "retry",
                                    label: KCopy.mindRetry,
                                    accessibilityIdentifier: "mind-verdict-retry"
                                ),
                            ],
                            variant: .mindFeedback,
                            onSelect: { _ in onRetry() }
                        )
                    }
                    .environment(\.kInkOnPaper, true)
                }

                if commentThread.hasContent {
                    commentThreadView
                        .padding(.top, KStyle.mindThoughtExpansionSpacing)
                }

                // The anchored thread affordance — input truly last (v18 law):
                // typing here IS starting the thread; it lands in chat with the
                // entity + claim as anchor, nothing duplicated.
                if onComment != nil {
                    commentRow
                        .padding(.top, KStyle.mindThoughtExpansionSpacing)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            preservesLegacyCardIdentifier
                ? "mind-output-card"
                : "mind-thought-\(output.id)-body"
        )
        .padding(.horizontal, isSelected ? KStyle.mindThoughtSelectedPadding : 0)
        .padding(.vertical, isSelected ? KStyle.mindThoughtSelectedPadding : KStyle.mindThoughtRowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(KStyle.mindThoughtSelectedBackground)
            }
        }
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(KStyle.mindThoughtUnselectedInk.opacity(KStyle.hairlineOpacity))
                    .frame(height: KStyle.hairlineWidth)
            }
        }
        .shadow(
            color: Color.black.opacity(isSelected ? KStyle.activeBandishShadowOpacity : 0),
            radius: isSelected ? KStyle.activeBandishShadowRadius : 0,
            y: isSelected ? KStyle.activeBandishShadowY : 0
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(
            KStyle.mindThoughtAnimation(.selectionFlood, reduceMotion: reduceMotion),
            value: isSelected
        )
        .opacity(presentation.isArchived ? KStyle.tertiaryTextOpacity : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("mind-thought-\(output.id)")
    }

    @ViewBuilder
    private var thoughtText: some View {
        if let entity = presentation.entity {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                linkedText(
                    entity,
                    font: KStyle.mindThoughtFont(.entity),
                    opacity: isSelected
                        ? KStyle.mindThoughtSelectedPrimaryOpacity
                        : presentation.signal == .acted
                        ? KStyle.tertiaryTextOpacity
                        : KStyle.primaryTextOpacity
                )

                if presentation.signal == .fresh {
                    KStatusDot(signal: .idle, state: .active, size: .small)
                        .environment(\.kInkOnPaper, isSelected)
                        .accessibilityHidden(false)
                        .accessibilityLabel("fresh")
                        .accessibilityIdentifier("mind-fresh-marker-\(output.outputId)")
                }
            }
        }

        linkedText(
            presentation.claim,
            font: KStyle.mindThoughtFont(.claim),
            opacity: isSelected
                ? KStyle.mindThoughtSelectedSecondaryOpacity
                : presentation.signal == .acted
                ? KStyle.tertiaryTextOpacity
                : KStyle.secondaryTextOpacity
        )
        .padding(.top, presentation.entity == nil ? 0 : KStyle.mindThoughtClaimTopPadding)
    }

    @ViewBuilder
    private var evidence: some View {
        if let evidenceLine = presentation.evidenceLine {
            VStack(alignment: .leading, spacing: 0) {
                let renderedEvidenceLine: String = {
                    if presentation.isArchived {
                        return "\(KCopy.mindArchivedPrefix) · \(evidenceLine)"
                    }
                    if presentation.signal == .acted {
                        return "\(KCopy.mindActedPrefix) · \(evidenceLine)"
                    }
                    return evidenceLine
                }()
                if presentation.canDrillIntoEvidence {
                    Button {
                        withAnimation(KStyle.mindThoughtAnimation(.evidenceReveal, reduceMotion: reduceMotion)) {
                            evidenceExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                            Text(renderedEvidenceLine)
                                .font(KStyle.mindThoughtFont(.reference))
                            Image(systemName: evidenceExpanded ? "chevron.down" : "chevron.right")
                                .font(KStyle.mindThoughtFont(.reference))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ink(metadataOpacity))
                    .padding(.top, KStyle.mindThoughtEvidenceTopPadding)
                    .accessibilityLabel(evidenceExpanded ? KCopy.mindHideEvidence : KCopy.mindShowEvidence)
                    .accessibilityIdentifier("mind-details-toggle")
                } else {
                    Text(renderedEvidenceLine)
                        .font(KStyle.mindThoughtFont(.reference))
                        .foregroundStyle(ink(metadataOpacity))
                        .padding(.top, KStyle.mindThoughtEvidenceTopPadding)
                }

                if evidenceExpanded, presentation.canDrillIntoEvidence {
                    evidenceReferences
                        .transition(.opacity.combined(with: .offset(y: KStyle.microSpacing)))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                presentation.signal == .acted
                    ? "mind-acted-marker-\(output.outputId)"
                    : "mind-evidence-\(output.outputId)"
            )
        }
    }

    private var evidenceReferences: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            ForEach(presentation.evidenceReferences, id: \.self) { reference in
                Text(reference)
                    .font(KStyle.mindThoughtFont(.reference))
                    .foregroundStyle(ink(secondaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, KStyle.mindThoughtReferenceIndent)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ink(KStyle.mindThoughtSelectedHairlineOpacity))
                .frame(width: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mind-evidence-references")
    }

    @ViewBuilder
    private var useTrail: some View {
        if !trailEntries.isEmpty {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                Button {
                    guard trailEntries.count > 1 else { return }
                    withAnimation(KStyle.mindThoughtAnimation(.evidenceReveal, reduceMotion: reduceMotion)) {
                        trailExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        Text(KCopy.mindUseTrailPrefix)
                            .font(KStyle.mindThoughtFont(.reference))
                            .foregroundStyle(ink(metadataOpacity))
                        Text(trailEntries[0].displayText)
                            .font(KStyle.mindThoughtFont(.reference))
                            .foregroundStyle(ink(secondaryOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                        if trailEntries.count > 1 {
                            Image(systemName: trailExpanded ? "chevron.down" : "chevron.right")
                                .font(KStyle.mindThoughtFont(.reference))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if trailExpanded {
                    ForEach(Array(trailEntries.dropFirst())) { entry in
                        Text(entry.displayText)
                            .font(KStyle.mindThoughtFont(.reference))
                            .foregroundStyle(ink(secondaryOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, KStyle.mindThoughtReferenceIndent)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(isSelected ? "mind-use-trail-open" : "mind-use-trail")
        }
    }

    private var commentThreadView: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            if let receipt = commentThread.receipt {
                KMonoCaption(receipt.displayText, variant: .metadata)
                    .foregroundStyle(ink(metadataOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mind-comment-receipt")
            } else {
                ForEach(commentThread.comments) { comment in
                    Text(comment.text)
                        .font(KStyle.mindThoughtFont(.claim))
                        .foregroundStyle(ink(comment.isFounder ? KStyle.mindThoughtSelectedPrimaryOpacity : KStyle.mindThoughtSelectedSecondaryOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                KActRow(
                    actions: [
                        KActItem(
                            id: "continue-in-chat",
                            label: KCopy.mindContinueInChat,
                            accessibilityIdentifier: "mind-comment-continue"
                        ),
                        KActItem(
                            id: "resolve",
                            label: KCopy.mindResolveComment,
                            accessibilityIdentifier: "mind-comment-resolve"
                        ),
                    ],
                    variant: .mindFeedback,
                    onSelect: { item in
                        switch item.id {
                        case "continue-in-chat":
                            onContinueInChat?()
                        case "resolve":
                            resolveComment()
                        default:
                            break
                        }
                    }
                )
                .environment(\.kInkOnPaper, true)
            }
        }
        .padding(.leading, KStyle.mindThoughtReferenceIndent)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ink(KStyle.mindThoughtSelectedHairlineOpacity))
                .frame(width: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mind-comment-thread")
    }

    private func resolveComment() {
        let receipt = MindCommentReceipt(
            who: "you",
            at: "today",
            change: "folded into the use trail"
        )
        commentThread.receipt = receipt
        trailEntries.append(
            MindUseTrailEntry(
                id: "comment-receipt",
                text: receipt.displayText
            )
        )
    }

    private var verdicts: some View {
        HStack(alignment: .top, spacing: KStyle.verdictButtonSpacing) {
            ForEach(MindThoughtVerdictPresenter.actions) { action in
                VStack(alignment: .center, spacing: KStyle.microSpacing) {
                    verdictButton(action)
                    if let consequence = presentation.verdictConsequences[action.verdict] {
                        Text(consequence.lowercased())
                            .font(KStyle.mindThoughtFont(.reference))
                            .foregroundStyle(
                                KStyle.mindThoughtSelectedInk.opacity(KStyle.tertiaryTextOpacity)
                            )
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: KStyle.decisionConsequenceMaxWidth)
                            .accessibilityIdentifier(
                                "mind-verdict-consequence-\(action.verdict.rawValue)"
                            )
                    }
                }
                if action.tone == .secondary {
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func verdictButton(_ action: MindThoughtVerdictAction) -> some View {
        Button {
            onVerdict(action.verdict)
        } label: {
            HStack(spacing: KStyle.smallSpacing) {
                Image(systemName: action.iconName)
                    .accessibilityHidden(true)
                if action.showsLabel {
                    Text(action.label)
                }
            }
            .font(KStyle.mindThoughtFont(.claim))
            .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
            .padding(.horizontal, action.showsLabel ? KStyle.cardPadding : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(actionsDisabled)
        .foregroundStyle(verdictForeground(action))
        .background {
            if action.tone == .primary {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(KStyle.mindThoughtSelectedInk)
            }
        }
        .overlay {
            if action.tone == .secondary {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(
                        KStyle.mindThoughtSelectedInk.opacity(KStyle.mindThoughtSelectedHairlineOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
            }
        }
        .opacity(pendingVerdict == nil || pendingVerdict == action.verdict ? 1 : KStyle.quaternaryTextOpacity)
        .accessibilityLabel(action.label)
        .accessibilityHint(KCopy.mindVerdictHint(action: action.label, subject: presentation.entity ?? presentation.claim))
        .accessibilityIdentifier("mind-verdict-\(action.verdict.rawValue)")
    }

    private var commentRow: some View {
        HStack(alignment: .center, spacing: KStyle.smallSpacing) {
            TextField(
                KCopy.mindCommentPlaceholder,
                text: $commentText,
                axis: .vertical
            )
            .font(KStyle.mindThoughtFont(.claim))
            .foregroundStyle(ink(KStyle.mindThoughtSelectedPrimaryOpacity))
            .tint(ink(KStyle.mindThoughtSelectedPrimaryOpacity))
            .padding(KStyle.cardPadding)
            .frame(minHeight: KStyle.minimumTapTarget)
            .background {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(KStyle.mindThoughtSelectedInk.opacity(KStyle.mindThoughtCommentFieldOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(
                        KStyle.mindThoughtSelectedInk.opacity(KStyle.mindThoughtSelectedHairlineOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
            }
            .onSubmit(sendComment)
            .accessibilityIdentifier("mind-comment-input")

            Button(action: sendComment) {
                Image(systemName: "arrow.up")
                    .font(KStyle.mindThoughtFont(.claim))
                    .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(KStyle.mindThoughtUnselectedInk)
            .background(Circle().fill(KStyle.mindThoughtSelectedInk))
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(
                commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? KStyle.quaternaryTextOpacity
                    : 1
            )
            .accessibilityLabel(KCopy.mindCommentSend)
            .accessibilityIdentifier("mind-comment-send")
        }
    }

    private func sendComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commentText = ""
        commentThread.comments.append(
            MindCommentTurn(
                id: "comment-\(commentThread.comments.count)",
                role: "founder",
                text: text
            )
        )
        commentThread.comments.append(
            MindCommentTurn(
                id: "comment-\(commentThread.comments.count)",
                role: "k",
                text: "noted · folded into the thread; the receipt updates when it changes anything."
            )
        )
        onComment?(text)
    }

    private var metadataOpacity: Double {
        isSelected ? KStyle.mindThoughtSelectedMetadataOpacity : KStyle.quaternaryTextOpacity
    }

    private var secondaryOpacity: Double {
        isSelected ? KStyle.mindThoughtSelectedSecondaryOpacity : KStyle.secondaryTextOpacity
    }

    private func verdictForeground(_ action: MindThoughtVerdictAction) -> Color {
        action.tone == .primary
            ? KStyle.mindThoughtUnselectedInk
            : KStyle.mindThoughtSelectedInk.opacity(KStyle.secondaryTextOpacity)
    }

    private func ink(_ opacity: Double) -> Color {
        (isSelected ? KStyle.mindThoughtSelectedInk : KStyle.mindThoughtUnselectedInk)
            .opacity(opacity)
    }

    private func linkedText(_ text: String, font: Font, opacity: Double) -> some View {
        MindThoughtLinkedText(
            text: text,
            refs: output.entityRefs,
            font: font,
            color: ink(opacity),
            onOpen: onOpenEntity
        )
    }
}

private struct MindThoughtLinkedText: View {
    let text: String
    let refs: [EntityRef]
    let font: Font
    let color: Color
    let onOpen: (EntityRef) -> Void

    var body: some View {
        Text(attributedText)
            .font(font)
            .foregroundStyle(color)
            .tint(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "kentity",
                      let indexText = url.pathComponents.last,
                      let index = Int(indexText),
                      matches.indices.contains(index)
                else { return .discarded }
                onOpen(matches[index].ref)
                return .handled
            })
    }

    private var matches: [EntityTextMatch] {
        EntitySpanMatcher.matches(in: text, refs: refs)
    }

    private var attributedText: AttributedString {
        let matches = matches
        guard !matches.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        var cursor = text.startIndex
        for (index, match) in matches.enumerated() {
            if cursor < match.range.lowerBound {
                result += AttributedString(String(text[cursor..<match.range.lowerBound]))
            }
            var linked = AttributedString(String(text[match.range]))
            linked.link = URL(string: "kentity://open/\(index)")
            result += linked

            var marker = AttributedString("°")
            marker.link = URL(string: "kentity://open/\(index)")
            result += marker
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor..<text.endIndex]))
        }
        return result
    }
}
