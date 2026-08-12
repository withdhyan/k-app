import SwiftUI
struct BuildRecordSection: View {
    enum Kind: Equatable {
        case unit
        case lane
        case history
    }

    let title: String
    let records: [BuildRecord]
    let kind: Kind
    let emptyText: String?
    let relatedCards: (BuildRecord) -> [BuildCard]
    let actionsEnabled: Bool
    let isPending: (BuildCard) -> Bool
    let isConfirming: (BuildCard, BuildCardOption) -> Bool
    let onChoose: (BuildCard, BuildCardOption) -> Void
    let onOpenEntity: (EntityRef) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool

    @State private var selection = BuildCardSelectionState()
    @Namespace private var cardNamespace

    init(
        title: String,
        records: [BuildRecord],
        kind: Kind,
        emptyText: String?,
        relatedCards: @escaping (BuildRecord) -> [BuildCard] = { _ in [] },
        actionsEnabled: Bool = false,
        isPending: @escaping (BuildCard) -> Bool = { _ in false },
        isConfirming: @escaping (BuildCard, BuildCardOption) -> Bool = { _, _ in false },
        onChoose: @escaping (BuildCard, BuildCardOption) -> Void = { _, _ in },
        onOpenEntity: @escaping (EntityRef) -> Void = { _ in },
        isDepthOrigin: @escaping (BuildRecord) -> Bool = { _ in false }
    ) {
        self.title = title
        self.records = records
        self.kind = kind
        self.emptyText = emptyText
        self.relatedCards = relatedCards
        self.actionsEnabled = actionsEnabled
        self.isPending = isPending
        self.isConfirming = isConfirming
        self.onChoose = onChoose
        self.onOpenEntity = onOpenEntity
        self.isDepthOrigin = isDepthOrigin
    }

    var body: some View {
        if !records.isEmpty || emptyText != nil {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard selection.expandedID != nil else { return }
                        KStyle.withMotion {
                            selection.collapse()
                        }
                    }

                VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                    KMonoCaption(title, variant: .metadata, state: .active)
                    if records.isEmpty, let emptyText {
                        KMonoCaption(emptyText, variant: .metadata)
                    } else {
                        ForEach(records) { record in
                            BuildRecordRow(
                                record: record,
                                kind: kind,
                                isExpanded: selection.expandedID == record.id,
                                namespace: cardNamespace,
                                cards: relatedCards(record),
                                actionsEnabled: actionsEnabled,
                                isPending: isPending,
                                isConfirming: isConfirming,
                                onChoose: onChoose,
                                onOpenEntity: onOpenEntity,
                                isDepthOriginMarked: isDepthOrigin(record),
                                onToggle: {
                                    KStyle.withMotion {
                                        selection.toggle(record.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("build-record-section-\(title.lowercased())")
        }
    }
}

private struct BuildRecordOnPaperKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    /// True when a record row renders on the white forward-card (the plan report),
    /// so it drops its own nested card surface and inks dark. False on glass.
    var buildRecordOnPaper: Bool {
        get { self[BuildRecordOnPaperKey.self] }
        set { self[BuildRecordOnPaperKey.self] = newValue }
    }
}

private struct BuildRecordFlatOnGlassKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    /// True when a record row renders inside a glass group card (BuildStatusPacketView,
    /// the chat-stream build-status block) rather than the paper report. It drops the
    /// same nested card surface `buildRecordOnPaper` drops — doctrine bars a card inside
    /// a card — but keeps glass-light ink instead of flipping dark.
    var buildRecordFlatOnGlass: Bool {
        get { self[BuildRecordFlatOnGlassKey.self] }
        set { self[BuildRecordFlatOnGlassKey.self] = newValue }
    }
}

private struct BuildRecordRow: View {
    let record: BuildRecord
    let kind: BuildRecordSection.Kind
    let isExpanded: Bool
    let namespace: Namespace.ID
    let cards: [BuildCard]
    let actionsEnabled: Bool
    let isPending: (BuildCard) -> Bool
    let isConfirming: (BuildCard, BuildCardOption) -> Bool
    let onChoose: (BuildCard, BuildCardOption) -> Void
    let onOpenEntity: (EntityRef) -> Void
    let isDepthOriginMarked: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.buildRecordOnPaper) private var onPaper
    @Environment(\.buildRecordFlatOnGlass) private var flatOnGlass

    /// True whenever the row must drop its own `BuildGrammarCardSurface` — either
    /// because it's on the paper report, or because it's already inside a glass
    /// group card. A card never nests inside another card.
    private var isFlat: Bool { onPaper || flatOnGlass }

    private var presentation: BuildCardGrammarPresentation {
        BuildCardGrammar.presentation(for: record)
    }

    private var primaryInk: Color {
        onPaper
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
            : Color.white.opacity(KStyle.primaryTextOpacity)
    }
    private var secondaryInk: Color {
        onPaper
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.quaternaryTextOpacity)
    }

    /// The expanded-state header ink: dark whenever the row sits on a white
    /// surface — paper, or its own nested mini-card. Glass-light only when
    /// flattened directly onto a glass group card.
    private var expandedPrimaryInk: Color {
        flatOnGlass
            ? Color.white.opacity(KStyle.primaryTextOpacity)
            : KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
    }
    private var expandedSecondaryInk: Color {
        flatOnGlass
            ? Color.white.opacity(KStyle.quaternaryTextOpacity)
            : KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedCard
            } else {
                Button(action: onToggle) {
                    collapsedCard
                }
                .buttonStyle(.plain)
                .accessibilityHint("expand unit details")
            }
        }
        .matchedGeometryEffect(
            id: "build-record-card-\(record.id)",
            in: namespace,
            properties: .frame,
            anchor: .topLeading
        )
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-record-\(record.id)")
        .opacity(isDepthOriginMarked ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
        .accessibilityAddTraits(isDepthOriginMarked ? .isSelected : [])
        .accessibilityHint(isDepthOriginMarked ? "depth reader open from this record" : "expand unit details")
    }

    private var collapsedCard: some View {
        let content = VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            summaryHeader(primaryColor: primaryInk, secondaryColor: secondaryInk)

            if let noteLine = presentation.noteLine {
                quietLine(noteLine, color: secondaryInk)
            } else if let errorLine = presentation.errorLine {
                quietLine(errorLine, color: secondaryInk)
            }
        }
        return Group {
            if isFlat {
                // flat list row on the plan's white card, or inside a glass group
                // card — no nested card surface either way
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, KStyle.smallSpacing)
            } else {
                BuildGrammarCardSurface(isExpanded: false) { content }
            }
        }
    }

    private var expandedCard: some View {
        let content = VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Button(action: onToggle) {
                summaryHeader(
                    primaryColor: expandedPrimaryInk,
                    secondaryColor: expandedSecondaryInk
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("collapse unit details")

            BuildRecordBiography(
                record: record,
                kind: kind,
                presentation: presentation,
                cards: cards,
                actionsEnabled: actionsEnabled,
                isPending: isPending,
                isConfirming: isConfirming,
                onChoose: onChoose,
                onOpenEntity: onOpenEntity,
                inkOnPaper: !flatOnGlass
            )
            .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
        }
        return Group {
            if isFlat {
                // flat detail on the plan's white card, or inside a glass group
                // card — no nested card surface either way
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, KStyle.smallSpacing)
            } else {
                BuildGrammarCardSurface(isExpanded: true) { content }
            }
        }
    }

    private func summaryHeader(primaryColor: Color, secondaryColor: Color) -> some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                BuildCardResultDot(tone: presentation.tone)
                Text(record.title)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(primaryColor)
                    .lineLimit(KStyle.singleLineLimit)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                Spacer(minLength: .zero)
            }

            if let stepLine = presentation.stepLine {
                quietLine(stepLine, color: secondaryColor)
                    .contentTransition(.opacity)
            }
        }
        .contentShape(Rectangle())
    }

    private func quietLine(_ text: String, color: Color) -> some View {
        Text(text.lowercased())
            .kFont(.monoCaption)
            .foregroundStyle(color)
            .lineLimit(KStyle.singleLineLimit)
            .contentTransition(.opacity)
            .animation(KStyle.chatContentSwapMotion(reduceMotion), value: text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BuildRecordBiography: View {
    let record: BuildRecord
    let kind: BuildRecordSection.Kind
    let presentation: BuildCardGrammarPresentation
    let cards: [BuildCard]
    let actionsEnabled: Bool
    let isPending: (BuildCard) -> Bool
    let isConfirming: (BuildCard, BuildCardOption) -> Bool
    let onChoose: (BuildCard, BuildCardOption) -> Void
    let onOpenEntity: (EntityRef) -> Void
    /// True when the enclosing surface is white (paper, or this row's own nested
    /// mini-card) — dark ink. False when flattened directly onto glass — light ink.
    let inkOnPaper: Bool

    private var secondaryColor: Color {
        inkOnPaper
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.quaternaryTextOpacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            switch kind {
            case .unit:
                history
                detailLine("goal", record.goal)
                detailLine("scope", record.scope)
                detailLine("state", record.state)
                detailLine("updated", record.updatedAt ?? record.age)
            case .lane:
                detailLine("state", record.state)
                detailLine("updated", record.updatedAt ?? record.age)
                detailLine("log", record.logTail)
                detailLine("diff", record.diff)
            case .history:
                detailLine("state", record.state)
                detailLine("updated", record.updatedAt ?? record.age)
            }

            if let gateEvidenceLine = presentation.gateEvidenceLine {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text("gate")
                        .kFont(.monoCaption)
                        .foregroundStyle(secondaryColor)
                    Text(gateEvidenceLine)
                        .kFont(.monoCaption)
                        .foregroundStyle(secondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("build-gate-evidence-\(record.id)")
            }

            if !cards.isEmpty {
                BuildUnitDecisionList(
                    cards: cards,
                    actionsEnabled: actionsEnabled,
                    isPending: isPending,
                    isConfirming: isConfirming,
                    onChoose: onChoose,
                    onOpenEntity: onOpenEntity,
                    inkOnPaper: inkOnPaper
                )
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        let historyLines = presentation.stateHistory.isEmpty
            ? [record.state, record.updatedAt ?? record.age].compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            : presentation.stateHistory.map { $0.lowercased() }
        if !historyLines.isEmpty {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                Text("history")
                    .kFont(.monoCaption)
                    .foregroundStyle(secondaryColor)
                ForEach(Array(historyLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .kFont(.monoCaption)
                        .foregroundStyle(secondaryColor)
                        .textSelection(.enabled)
                }
            }
            .accessibilityIdentifier("build-state-history-\(record.id)")
        }
    }

    @ViewBuilder
    private func detailLine(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(label)
                    .kFont(.monoCaption)
                    .foregroundStyle(secondaryColor)
                Text(value.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct BuildUnitDecisionList: View {
    let cards: [BuildCard]
    let actionsEnabled: Bool
    let isPending: (BuildCard) -> Bool
    let isConfirming: (BuildCard, BuildCardOption) -> Bool
    let onChoose: (BuildCard, BuildCardOption) -> Void
    let onOpenEntity: (EntityRef) -> Void
    /// True when the enclosing surface is white (paper, or this row's own nested
    /// mini-card) — dark ink. False when flattened directly onto glass — light ink.
    let inkOnPaper: Bool

    private var paperSecondary: Color {
        inkOnPaper
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.quaternaryTextOpacity)
    }

    private var hairline: Color {
        inkOnPaper
            ? KStyle.nearBlack.opacity(KStyle.hairlineOpacity)
            : Color.white.opacity(KStyle.hairlineOpacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Rectangle()
                .fill(hairline)
                .frame(height: KStyle.hairlineWidth)

            ForEach(cards) { card in
                let pending = isPending(card)
                let presentation = BuildCardPresentation(card: card, isPending: pending)
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    EntityLinkedText(
                        card.voiceTitle,
                        refs: card.entityRefs,
                        fontToken: .blockDefaultTitle,
                        opacity: inkOnPaper ? KStyle.chatThreadPaperPrimaryOpacity : KStyle.primaryTextOpacity,
                        onOpen: onOpenEntity
                    )

                    if let evidenceLine = DecisionEvidenceLineFormatter.line(for: card.evidenceSummary)
                        ?? DecisionEvidencePreviewFormatter.summaryLine(for: card.evidencePreviews) {
                        Text(evidenceLine.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(paperSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    if presentation.isCollapsed {
                        Text(card.historyLine.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(paperSecondary)
                    } else {
                        ForEach(presentation.options, id: \.option.id) { row in
                            HStack(alignment: .center, spacing: KStyle.rowSpacing) {
                                Spacer(minLength: .zero)
                                if !row.consequence.isEmpty {
                                    Text(row.consequence.lowercased())
                                        .kFont(.monoCaption)
                                        .foregroundStyle(paperSecondary)
                                        .multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: KStyle.decisionConsequenceMaxWidth, alignment: .trailing)
                                }
                                KOptionButton(
                                    label: row.option.label,
                                    variant: row.isPrimary ? .primaryFilled : .quietHairline,
                                    isEnabled: actionsEnabled && row.isEnabled,
                                    isPending: pending,
                                    isConfirming: isConfirming(card, row.option),
                                    state: pending ? .loading : .resting,
                                    accessibilityIdentifier: "build-option-\(card.id)-\(row.option.id)",
                                    onSelect: { onChoose(card, row.option) }
                                )
                                .background {
                                    RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                                        .fill(row.isPrimary ? Color.white : KStyle.nearBlack)
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("build-unit-card-\(card.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-unit-cards")
    }
}

struct BuildRecordExpandedDetails: View {
    let record: BuildRecord
    let kind: BuildRecordSection.Kind
    let onOpenReview: () -> Void
    let onPeekLogTail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch kind {
            case .unit:
                detailLine("goal", record.goal)
                detailLine("scope", record.scope)
                detailLine("timeline", record.updatedAt ?? record.age)
            case .lane:
                detailLine("goal", record.goal)
                detailLine("scope", record.scope)
                detailLine("timeline", record.updatedAt ?? record.age)
                detailLine("log", record.logTail)
                detailLine("diff", record.diff)
            case .history:
                detailLine("state", record.state)
                detailLine("timeline", record.updatedAt ?? record.age)
            }

            actionRow
        }
    }

    private var actionRow: some View {
        KActRow(
            actions: detailActions,
            variant: .build,
            onSelect: { item in
                switch item.id {
                case "review":
                    onOpenReview()
                case "peek":
                    onPeekLogTail()
                default:
                    break
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-record-actions-\(record.id)")
    }

    private var detailActions: [KActItem] {
        var actions: [KActItem] = []
        if kind == .unit {
            actions.append(
                KActItem(
                    id: "review",
                    accessibilityIdentifier: "build-review-\(record.id)"
                )
            )
        }
        if record.logTailLaneId != nil {
            actions.append(
                KActItem(
                    id: "peek",
                    accessibilityIdentifier: "build-peek-\(record.id)"
                )
            )
        }
        actions.append(contentsOf: record.legalActions.map { KActItem(id: $0, label: $0.lowercased()) })
        return actions
    }

    @ViewBuilder
    private func detailLine(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                KMonoCaption(label, variant: .metadata)
                Text(value.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .textSelection(.enabled)
            }
        }
    }
}

struct BuildHistorySection: View {
    let records: [BuildRecord]

    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                KMonoCaption("recent history", variant: .metadata, state: .active)
                ForEach(records.prefix(6)) { record in
                    BandishCard(
                        timeText: record.age ?? "",
                        signal: BuildSignal.from(state: record.state).kSignal,
                        title: record.title,
                        variant: .elapsed,
                        clockReferenceDate: .now
                    ) {
                        EmptyView()
                    } footer: {
                        EmptyView()
                    }
                }
            }
        }
    }
}

struct BuildStateBadge: View {
    let state: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            KStatusDot(signal: BuildSignal.from(state: state).kSignal, size: .small)
            KMonoCaption(state, variant: .metadata, state: .active)
        }
        .accessibilityElement(children: .combine)
    }
}
