import SwiftUI

struct BuildNeedsYouCard: View {
    let rows: [BuildNeedsYouRow]
    let oldestStuck: String?
    let selectedRowID: String?
    let approveAllState: BuildApproveAllState
    let errorText: (String) -> String?
    let isDepthOrigin: (BuildNeedsYouRow) -> Bool
    let onSelect: (BuildNeedsYouRow) -> Void
    let onApproveAllConfirm: () -> Void
    let onApproveAllCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingQuieter = false

    init(
        rows: [BuildNeedsYouRow],
        oldestStuck: String?,
        selectedRowID: String?,
        approveAllState: BuildApproveAllState = .idle,
        errorText: @escaping (String) -> String? = { _ in nil },
        isDepthOrigin: @escaping (BuildNeedsYouRow) -> Bool = { _ in false },
        onSelect: @escaping (BuildNeedsYouRow) -> Void,
        onApproveAllConfirm: @escaping () -> Void = {},
        onApproveAllCancel: @escaping () -> Void = {}
    ) {
        self.rows = rows
        self.oldestStuck = oldestStuck
        self.selectedRowID = selectedRowID
        self.approveAllState = approveAllState
        self.errorText = errorText
        self.isDepthOrigin = isDepthOrigin
        self.onSelect = onSelect
        self.onApproveAllConfirm = onApproveAllConfirm
        self.onApproveAllCancel = onApproveAllCancel
    }

    private var fold: BuildNeedsYouFold {
        BuildNeedsYouList.fold(rows)
    }

    private var displayedRows: [BuildNeedsYouRow] {
        showingQuieter ? BuildNeedsYouList.ordered(rows) : fold.visibleRows
    }

    private var groups: [BuildNeedsYouGroup] {
        BuildNeedsYouList.groups(displayedRows)
    }

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                header
                approveAllStateBody
                if rows.isEmpty {
                    Text("no active decisions")
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                } else {
                    rowsBody
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-needs-you-card")
        .onChange(of: rows) { _, _ in
            showingQuieter = false
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            KMonoCaption("needs you", variant: .metadata, state: .active)
            if let oldestStuck, !oldestStuck.isEmpty {
                KMonoCaption("· oldest stuck \(oldestStuck)", variant: .staleness)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var approveAllStateBody: some View {
        switch approveAllState {
        case .idle:
            EmptyView()
        case .disclosure(let disclosure):
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                KMonoCaption(KCopy.buildApproveAllAct, variant: .metadata, state: .active)
                    .accessibilityIdentifier("build-needs-you-approve-all-disclosure")

                ForEach(disclosure.summary.kinds) { kind in
                    KMonoCaption("\(kind.countLine) · \(kind.lean)", variant: .metadata)
                }

                if let stakes = disclosure.summary.hardestStakes {
                    KMonoCaption(stakes, variant: .metadata)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build-needs-you-approve-all-stakes")
                }

                if disclosure.summary.skippedCount > 0 {
                    KMonoCaption(
                        "\(disclosure.summary.skippedCount) waiting their turn",
                        variant: .staleness
                    )
                }

                KActRow(
                    actions: [
                        KActItem(
                            id: "confirm",
                            label: KCopy.buildApproveAllConfirm,
                            accessibilityIdentifier: "build-needs-you-approve-all-confirm"
                        ),
                        KActItem(
                            id: "cancel",
                            label: KCopy.buildApproveAllCancel,
                            accessibilityIdentifier: "build-needs-you-approve-all-cancel"
                        ),
                    ],
                    variant: .build,
                    onSelect: { action in
                        if action.id == "confirm" {
                            onApproveAllConfirm()
                        } else {
                            onApproveAllCancel()
                        }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("build-needs-you-approve-all-actions")
            }
            .accessibilityElement(children: .contain)
        case .running(let progress):
            KMonoCaption(progress.line, variant: .status, state: .loading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("build-needs-you-approve-all-progress")
        case .finished(let result):
            KMonoCaption(result.line, variant: result.failed > 0 ? .inlineError : .status, state: result.failed > 0 ? .error : .active)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("build-needs-you-approve-all-summary")
        }
    }

    private var rowsBody: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            ForEach(groups) { group in
                if let title = group.title {
                    KMonoCaption(title, variant: .metadata)
                }
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    ForEach(group.rows) { row in
                        BuildNeedsYouRowView(
                            row: row,
                            isSelected: selectedRowID == row.id,
                            isDepthOriginMarked: isDepthOrigin(row),
                            errorText: errorText(row.id),
                            onSelect: { onSelect(row) }
                        )
                    }
                }
            }

            if fold.quieterCount > 0 {
                KActRow(
                    actions: [
                        KActItem(
                            id: "quieter",
                            label: KCopy.buildNeedsYouQuieter(fold.quieterCount),
                            accessibilityIdentifier: "build-needs-you-fold"
                        )
                    ],
                    variant: .build,
                    selectedActionIDs: showingQuieter ? ["quieter"] : [],
                    onSelect: { _ in
                        KStyle.withMotion {
                            showingQuieter.toggle()
                        }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    showingQuieter
                        ? "show fewer needs you rows"
                        : KCopy.buildNeedsYouQuieter(fold.quieterCount)
                )
            }
        }
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: showingQuieter)
    }
}

private struct BuildNeedsYouRowView: View {
    let row: BuildNeedsYouRow
    let isSelected: Bool
    let isDepthOriginMarked: Bool
    let errorText: String?
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            Group {
                if isSelected {
                    BuildGrammarCardSurface(isExpanded: true) {
                        rowContent
                            .environment(\.kInkOnPaper, true)
                    }
                } else {
                    rowContent
                        .padding(.vertical, KStyle.smallSpacing)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(isDepthOriginMarked ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
        .accessibilityAddTraits(isDepthOriginMarked ? .isSelected : [])
        .accessibilityHint(
            isDepthOriginMarked
                ? "depth reader open from this act"
                : (isSelected ? "close needs you detail" : "open needs you detail")
        )
        .accessibilityIdentifier("build-needs-you-row-\(row.id)")
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isSelected)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: KStyle.smallSpacing) {
            KMonoCaption(row.timeAgo, variant: .staleness)
                .frame(width: KStyle.buildNeedsYouGutterWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                Text(row.title.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(
                        isSelected
                            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
                            : KStyle.emphasisInk.opacity(KStyle.primaryTextOpacity)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption(row.classWord, variant: .metadata)
                    if let planTitle = row.planDisplayTitle {
                        KMonoCaption(planTitle, variant: .metadata)
                            .lineLimit(KStyle.singleLineLimit)
                            .truncationMode(.tail)
                    }
                }
                if let receipt = row.receipt {
                    KMonoCaption(receipt, variant: .status, state: .active)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build-needs-you-row-receipt-\(row.id)")
                }
                if let errorText {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build-needs-you-row-error-\(row.id)")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, KStyle.microSpacing)
    }
}

/// The selected needs-you card is a paper-ink detail in the iPad rail. The face is
/// content-only: no old KPaperCard is nested inside the expanded surface.
struct BuildNeedsYouDetailPanel: View {
    let card: BuildCard
    let isPending: Bool
    let errorText: String?
    let captionText: String?
    let disabledReason: String?
    let isConfirming: (BuildCardOption) -> Bool
    let onChoose: (BuildCardOption) -> Void
    let onClose: () -> Void
    let onOpenReview: () -> Void
    let onOpenEntity: (EntityRef) -> Void

    @State private var evidenceExpanded = false

    private var presentation: BuildCardPresentation {
        BuildCardPresentation(card: card, isPending: isPending, disabledReason: disabledReason)
    }

    var body: some View {
        BuildGrammarCardSurface(isExpanded: true) {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption(card.voiceTitle, variant: .metadata, state: .active)
                    Spacer(minLength: KStyle.smallSpacing)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "close",
                                label: "close",
                                accessibilityIdentifier: "build-needs-you-close-\(card.id)"
                            ),
                        ],
                        variant: .build,
                        onSelect: { _ in onClose() }
                    )
                    .environment(\.kInkOnPaper, true)
                }
                .accessibilityHint("close needs you detail")

                if let planTitle = card.planDisplayTitle {
                    KMonoCaption(planTitle, variant: .metadata)
                        .lineLimit(KStyle.singleLineLimit)
                        .truncationMode(.tail)
                }

                detailBody
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("build-card-\(card.id)")

                if let captionText {
                    KMonoCaption(captionText, variant: .status, state: .active)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorText {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .environment(\.kInkOnPaper, true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.voiceTitle) detail")
        .accessibilityIdentifier("build-needs-you-detail-\(card.id)")
    }

    @ViewBuilder
    private var detailBody: some View {
        if let brief = card.brief {
            if let whyNow = brief.whyNow {
                paperLinkedText(whyNow, font: .content, opacity: KStyle.chatThreadPaperSecondaryOpacity)
            }
            if let openQuestion = brief.openQuestion {
                paperLinkedText(openQuestion, font: .blockActiveTitle, opacity: KStyle.chatThreadPaperPrimaryOpacity)
            }
            KMonoCaption(brief.blockerLine, variant: .metadata)
            if let stakes = brief.stakes {
                KMonoCaption(stakes, variant: .metadata)
            }
        } else {
            if let what = card.what {
                KMonoCaption(what, variant: .metadata)
            }
            paperLinkedText(card.voiceTitle, font: .blockActiveTitle, opacity: KStyle.chatThreadPaperPrimaryOpacity)
            if let body = card.body, !body.isEmpty {
                paperLinkedText(body, font: .content, opacity: KStyle.chatThreadPaperSecondaryOpacity)
            }
            if let contrast = card.contrast, !contrast.isEmpty {
                paperLinkedText(contrast.lowercased(), font: .content, opacity: KStyle.chatThreadPaperSecondaryOpacity)
            }
            if let stakes = card.stakes {
                KMonoCaption(stakes, variant: .metadata)
            }
        }

        if !presentation.options.isEmpty {
            VStack(alignment: .trailing, spacing: KStyle.optionButtonSpacing) {
                ForEach(presentation.options, id: \.option.id) { option in
                    HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                        Spacer(minLength: 0)
                        if !option.consequence.isEmpty {
                            paperText(
                                option.consequence.lowercased(),
                                font: .monoCaption,
                                opacity: KStyle.chatThreadPaperSecondaryOpacity
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: KStyle.decisionConsequenceMaxWidth, alignment: .trailing)
                        }
                        KOptionButton(
                            label: option.option.label,
                            variant: option.isPrimary ? .primaryFilled : .quietHairline,
                            isEnabled: option.isEnabled,
                            isPending: isPending,
                            isConfirming: isConfirming(option.option),
                            state: isPending ? .loading : .resting,
                            accessibilityIdentifier: "build-option-\(card.id)-\(option.option.id)",
                            onSelect: { onChoose(option.option) }
                        )
                    }
                }
            }
        }

        if let evidenceLine = DecisionEvidenceLineFormatter.line(for: card.evidenceSummary)
            ?? DecisionEvidencePreviewFormatter.summaryLine(for: card.evidencePreviews) {
            KActRow(
                actions: [KActItem(id: "evidence", label: evidenceLine)],
                variant: .build,
                selectedActionIDs: evidenceExpanded ? ["evidence"] : [],
                onSelect: { _ in evidenceExpanded.toggle() }
            )
            if evidenceExpanded {
                ForEach(DecisionEvidencePreviewFormatter.lines(for: card.evidencePreviews), id: \.self) { line in
                    KMonoCaption(line, variant: .metadata)
                }
            }
        } else if card.hasReviewDepth {
            KActRow(
                actions: [KActItem(id: "review")],
                variant: .build,
                onSelect: { _ in onOpenReview() }
            )
        }
    }

    private func paperText(
        _ text: String?,
        font: KFontToken,
        opacity: Double
    ) -> some View {
        Text(text ?? "")
            .kFont(font)
            .foregroundStyle(KStyle.nearBlack.opacity(opacity))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func paperLinkedText(
        _ text: String,
        font: KFontToken,
        opacity: Double
    ) -> some View {
        EntityLinkedText(
            text,
            refs: card.entityRefs,
            fontToken: font,
            opacity: opacity,
            onOpen: onOpenEntity
        )
    }
}
