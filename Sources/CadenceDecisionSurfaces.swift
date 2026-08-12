import Foundation
import SwiftUI
import UIKit
extension KStyle {
    // Membrane challenger-jut geometry. The glass layer tucks under the active
    // bandish card's bottom edge (hiding its rounded corner behind the card)
    // and insets from the card's silhouette on both sides, so incumbent and
    // challenger read as two layered states of one object — a superposition
    // the founder collapses with take/keep.
    static let membraneJutOverlap: CGFloat = activeBandishCornerRadius
    static let membraneJutInset: CGFloat = 12
}

/// The membrane compare surface: the incumbent's own card (the caller's row,
/// unchanged) with the challenger jutting out from underneath it. Composition
/// only — glass card tone, the day-row grammar, KMonoCaption, KActRow.
///
/// Motion: the jut is a spatial explanation — the challenger emerges FROM the
/// block it re-scores — so it rides the chat-v16 register already sanctioned
/// on this surface (day-row expansion, above): layout change on
/// KStyle.chatStructureMotion (0.7s zen). No springs. Reduce Motion resolves
/// the growth to none (the helper returns nil) while the jut keeps an easeFast
/// opacity settle — movement drops, feedback stays.
struct CadenceMembraneCompareSurface<Incumbent: View>: View {
    let compare: CadenceMembraneCompareModel?
    let echoText: String?
    let errorText: String?
    let onVerdict: (CadenceMembraneCompareModel, Bool) -> Void
    let incumbent: Incumbent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        compare: CadenceMembraneCompareModel?,
        echoText: String?,
        errorText: String?,
        onVerdict: @escaping (CadenceMembraneCompareModel, Bool) -> Void,
        @ViewBuilder incumbent: () -> Incumbent
    ) {
        self.compare = compare
        self.echoText = echoText
        self.errorText = errorText
        self.onVerdict = onVerdict
        self.incumbent = incumbent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            incumbent
                .zIndex(1)

            if let compare {
                CadenceMembraneChallengerJut(
                    compare: compare,
                    errorText: errorText,
                    onVerdict: onVerdict
                )
                .zIndex(0)
            } else if let echoText {
                // The collapsed superposition's receipt: one quiet line where
                // the jut was. Session-only; relaunch earns silence.
                KMonoCaption(echoText, variant: .metadata)
                    .padding(.top, KStyle.tightRowSpacing)
                    .padding(.leading, KStyle.membraneJutInset + KStyle.cardLargePadding)
                    .accessibilityIdentifier("cadence-membrane-echo")
            }
        }
        .animation(KStyle.chatStructureMotion(reduceMotion), value: membraneStateKey)
    }

    private var membraneStateKey: String {
        compare.map { "jut-\($0.candidateBlockId)" } ?? echoText.map { "echo-\($0)" } ?? "resting"
    }
}

private struct CadenceMembraneChallengerJut: View {
    let compare: CadenceMembraneCompareModel
    let errorText: String?
    let onVerdict: (CadenceMembraneCompareModel, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Reduce Motion drops the jut's growth entirely; this keeps the doctrine's
    // opacity-feedback channel — an easeFast settle on arrival.
    @State private var hasSettled = false

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                challengerRow

                KMonoCaption(CadenceMembraneCopy.basisLine, variant: .metadata)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorText {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                verdictRow
            }
            // Clear the strip hidden under the incumbent card's bottom edge.
            .padding(.top, KStyle.membraneJutOverlap)
        }
        // Same silhouette family as the active card (overhang + leading shift),
        // inset so the under-layer reads tucked, then pulled up beneath it.
        .padding(.horizontal, KStyle.membraneJutInset)
        .padding(.trailing, -KStyle.activeBandishTrailingOverhang)
        .offset(x: KStyle.activeBandishLeadingOffset)
        .padding(.top, -KStyle.membraneJutOverlap)
        .opacity(!reduceMotion || hasSettled ? KStyle.fullOpacity : .zero)
        .onAppear {
            guard reduceMotion, !hasSettled else { return }
            withAnimation(KStyle.opacityMotion(reduceMotion)) { hasSettled = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-membrane-challenger")
    }

    // The challenger line reuses the day-row grammar (time · dot · what · delta):
    // it IS a block from the founder's own day, offered for this seam.
    private var challengerRow: some View {
        HStack(alignment: .center, spacing: KStyle.smallSpacing) {
            Text(compare.challengerTimeText)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                .frame(width: KStyle.cadenceDayRowTimeWidth, alignment: .leading)

            Circle()
                .fill(compare.challengerRing.color)
                .frame(width: KStyle.bandishStatusDotSize, height: KStyle.bandishStatusDotSize)
                .accessibilityHidden(true)

            Text(compare.challengerTitle)
                .font(KStyle.contentFont)
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .lineLimit(KStyle.singleLineLimit)

            Spacer(minLength: KStyle.smallSpacing)

            Text(compare.deltaText)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
        }
    }

    private var verdictRow: some View {
        HStack(alignment: .center, spacing: KStyle.smallSpacing) {
            KMonoCaption(CadenceMembraneCopy.trainsLine, variant: .metadata)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: KStyle.smallSpacing)

            KActRow(
                actions: [
                    KActItem(
                        id: "take",
                        label: CadenceMembraneCopy.takeAct,
                        accessibilityIdentifier: "cadence-membrane-take"
                    ),
                    KActItem(
                        id: "keep",
                        label: CadenceMembraneCopy.keepAct,
                        accessibilityIdentifier: "cadence-membrane-keep"
                    ),
                ],
                variant: .cadence,
                onSelect: { item in onVerdict(compare, item.id == "take") }
            )
        }
    }
}

struct CadenceNudgeCard: View {
    let nudge: CadenceNudge
    let isPending: Bool
    let errorText: String?
    let onDisposition: (CadenceNudgeDisposition, CadenceNudge) -> Void
    @State private var evidenceExpanded = false

    private var evidenceLine: String? {
        DecisionEvidenceLineFormatter.line(for: nudge.decisionEvidenceSummary)
    }

    var body: some View {
        KPaperCard(state: isPending ? .loading : .resting) {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if nudge.isBuildCardActable {
                    buildCardDecisionBody
                } else {
                    nudgeText

                    HStack(spacing: KStyle.smallSpacing) {
                        Spacer(minLength: 0)
                        KActRow(
                            actions: [
                                KActItem(id: CadenceNudgeDisposition.act.rawValue, label: "act"),
                                KActItem(id: CadenceNudgeDisposition.watch.rawValue, label: "watch"),
                                KActItem(id: CadenceNudgeDisposition.suppress.rawValue, label: "suppress"),
                            ],
                            variant: .cadence,
                            state: isPending ? .loading : .resting,
                            onSelect: { item in
                                if let disposition = CadenceNudgeDisposition(rawValue: item.id) {
                                    onDisposition(disposition, nudge)
                                }
                            }
                        )
                    }
                }

                if let errorText {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if nudge.isBuildCardActable, let stakes = nudge.decisionStakes {
                    KMonoCaption(stakes, variant: .metadata)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var buildCardDecisionBody: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let brief = nudge.decisionBrief {
                decisionBriefBody(brief)
            } else {
                if let what = nudge.decisionWhat {
                    KMonoCaption(what, variant: .metadata)
                }

                nudgeText

                if let contrast = nudge.decisionContrast {
                    Text(contrast.lowercased())
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let evidenceLine {
                    DecisionEvidenceLineButton(
                        line: evidenceLine,
                        isExpanded: evidenceExpanded,
                        onToggle: { evidenceExpanded.toggle() }
                    )
                    if evidenceExpanded, let signalExplained = nudge.decisionSignalExplained {
                        Text(signalExplained.lowercased())
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .transition(.opacity)
                    }
                }
            }

            buildCardOptionArea
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
        }
    }

    @ViewBuilder
    private var buildCardOptionArea: some View {
        if let option = nudge.recommendedBuildOption {
            HStack(alignment: .top, spacing: KStyle.smallSpacing) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    KOptionButton(
                        label: option.label,
                        variant: .quietHairline,
                        isEnabled: !isPending,
                        isPending: isPending,
                        state: isPending ? .loading : .resting,
                        accessibilityIdentifier: "cadence-nudge-\(nudge.id)-act",
                        onSelect: { onDisposition(.act, nudge) }
                    )
                    let consequence = nudge.decisionBrief?.whatHappens(for: option.id) ?? option.consequence
                    if !consequence.isEmpty {
                        Text(consequence.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var nudgeText: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            Text((nudge.title ?? "nudge").lowercased())
                .font(KStyle.blockDefaultTitleFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
            if let body = nudge.body, !body.isEmpty {
                Text(body.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CadenceReviewCardView: View {
    let card: CadenceReviewCard
    let state: KPrimitiveInteractionState
    let onAnswerValueProbe: (CadenceValueProbe, CadenceValueProbeOption) async -> CadenceValueProbeSubmitResult
    let onDismiss: () -> Void

    var body: some View {
        KPaperCard(state: state) {
            if card.isValuesCard {
                CadenceValuesCardContent(
                    card: card,
                    valuesCard: card.valuesCard,
                    onAnswer: onAnswerValueProbe,
                    onDismiss: onDismiss
                )
                .accessibilityIdentifier("cadence-values-card")
            } else {
                CadenceGenericReviewCardContent(card: card, onDismiss: onDismiss)
            }
        }
    }
}

private struct CadenceGenericReviewCardContent: View {
    let card: CadenceReviewCard
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                KMonoCaption(card.type, variant: .metadata)
                Spacer(minLength: KStyle.tightRowSpacing)
                KActRow(
                    actions: [KActItem(id: "dismiss")],
                    variant: .cadence,
                    onSelect: { _ in onDismiss() }
                )
            }

            Text((card.title ?? "review").lowercased())
                .font(KStyle.blockActiveTitleFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            ForEach(card.sections) { section in
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    if let title = section.title {
                        KMonoCaption(title, variant: .metadata)
                    }
                    if let body = section.body {
                        Text(body.lowercased())
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    ForEach(section.items, id: \.self) { item in
                        Text(item.lowercased())
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct CadenceValuesCardContent: View {
    let card: CadenceReviewCard
    let valuesCard: CadenceValuesCard?
    let onAnswer: (CadenceValueProbe, CadenceValueProbeOption) async -> CadenceValueProbeSubmitResult
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedOptionsByProbeID: [String: CadenceValueProbeOption] = [:]
    @State private var pendingProbeIDs: Set<String> = []
    @State private var errorTextByProbeID: [String: String] = [:]
    @State private var localValues: [CadenceValue]
    @State private var expandedValueID: String?

    init(
        card: CadenceReviewCard,
        valuesCard: CadenceValuesCard?,
        onAnswer: @escaping (CadenceValueProbe, CadenceValueProbeOption) async -> CadenceValueProbeSubmitResult,
        onDismiss: @escaping () -> Void
    ) {
        self.card = card
        self.valuesCard = valuesCard
        self.onAnswer = onAnswer
        self.onDismiss = onDismiss

        let seededValues = valuesCard?.values.isEmpty == false
            ? valuesCard?.values ?? []
            : Self.fallbackValues(from: card.valueProbes?.probes ?? [])
        _localValues = State(initialValue: seededValues)
        _expandedValueID = State(
            initialValue: valuesCard?.initialExpandedValueID
                ?? valuesCard?.attentionValueID
                ?? seededValues.first(where: { $0.effectiveSignal == .attention })?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                KMonoCaption("values", variant: .metadata)
                Spacer(minLength: KStyle.tightRowSpacing)
                if let headerSummary {
                    KMonoCaption(headerSummary, variant: .metadata)
                }
                KActRow(
                    actions: [KActItem(id: "dismiss")],
                    variant: .cadence,
                    onSelect: { _ in onDismiss() }
                )
            }

            if let current = focusedProbe {
                ask(current)
            } else {
                signalRows
            }
        }
        .padding(.bottom, KStyle.cardPadding)
        .kAnimated(value: selectedOptionsByProbeID)
        .kAnimated(value: pendingProbeIDs)
        .kAnimated(value: expandedValueID)
        .accessibilityElement(children: .contain)
    }

    private var focusedProbe: CadenceValueProbe? {
        guard card.valueProbes != nil else { return nil }
        return sortedProbes.first { !answeredProbeIDs.contains($0.id) }
    }

    private var sortedProbes: [CadenceValueProbe] {
        (card.valueProbes?.probes ?? []).sorted { left, right in
            if left.ordinal == right.ordinal { return left.id < right.id }
            return left.ordinal < right.ordinal
        }
    }

    private var answeredProbeIDs: Set<String> {
        Set(sortedProbes.compactMap { probe in
            if selectedOptionsByProbeID[probe.id] != nil || probe.answer != nil {
                return probe.id
            }
            return nil
        })
    }

    private var headerSummary: String? {
        if let summary = normalized(valuesCard?.summary), focusedProbe != nil || !summary.contains("probe") {
            return summary
        }
        guard focusedProbe != nil else {
            let held = localValues.filter { $0.effectiveSignal == .held }.count
            let attention = localValues.filter { $0.effectiveSignal == .attention }.count
            let parts = [
                held > 0 ? "\(held) held" : nil,
                attention > 0 ? "\(attention) needs attention" : nil,
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let remaining = max(1, sortedProbes.count - answeredProbeIDs.count)
        return "\(remaining) probe\(remaining == 1 ? "" : "s") · then quiet"
    }

    private func ask(_ probe: CadenceValueProbe) -> some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            Text(probe.question.lowercased())
                .font(KStyle.blockDefaultTitleFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // iPad keeps the two options in one line; compact width stacks the
            // same controls without creating a second probe renderer.
            // (doctrine: quiet-acts, tap-target-floor)
            Group {
                if horizontalSizeClass == .compact {
                    optionButtons(probe, axis: .vertical)
                } else {
                    ViewThatFits(in: .horizontal) {
                        optionButtons(probe, axis: .horizontal)
                        optionButtons(probe, axis: .vertical)
                    }
                }
            }
            .transition(.opacity)

            if let valueName = probeValueName(probe) {
                KMonoCaption(
                    "the answer lands as an act on \(valueName)'s trail",
                    variant: .metadata
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText = errorTextByProbeID[probe.id] {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cadence-value-probe-error-\(probe.id)")
            }
        }
        .transition(.opacity)
    }

    private enum OptionAxis {
        case horizontal
        case vertical
    }

    @ViewBuilder
    private func optionButtons(_ probe: CadenceValueProbe, axis: OptionAxis) -> some View {
        let options = Array(probe.options.prefix(2))
        if axis == .horizontal {
            HStack(spacing: KStyle.verdictButtonSpacing) {
                ForEach(options) { option in optionButton(option, for: probe) }
            }
        } else {
            VStack(spacing: KStyle.smallSpacing) {
                ForEach(options) { option in optionButton(option, for: probe) }
            }
        }
    }

    private func optionButton(_ option: CadenceValueProbeOption, for probe: CadenceValueProbe) -> some View {
        KOptionButton(
            label: option.label,
            variant: .quietHairline,
            isEnabled: !pendingProbeIDs.contains(probe.id),
            isPending: pendingProbeIDs.contains(probe.id) && selectedOptionsByProbeID[probe.id]?.id == option.id,
            state: pendingProbeIDs.contains(probe.id) ? .loading : .resting,
            accessibilityIdentifier: "cadence-value-probe-\(probe.id)-\(option.id)",
            onSelect: { choose(option, for: probe) }
        )
        .frame(maxWidth: .infinity)
    }

    private var signalRows: some View {
        VStack(alignment: .leading, spacing: .zero) {
            ForEach(orderedValues) { value in
                valueRow(value)
            }
        }
    }

    private var orderedValues: [CadenceValue] {
        guard let attentionValueID = valuesCard?.attentionValueID
            ?? localValues.first(where: { $0.effectiveSignal == .attention })?.id,
              let index = localValues.firstIndex(where: { $0.id == attentionValueID })
        else { return localValues }
        var values = localValues
        let attentionValue = values.remove(at: index)
        values.insert(attentionValue, at: .zero)
        return values
    }

    private func valueRow(_ value: CadenceValue) -> some View {
        let isOpen = expandedValueID == value.id
        return Button {
            // Doctrine: spatial-continuity + honest-motion. The trail is
            // inserted under this retained row, so its origin stays marked and
            // neighbors move along one axis; the shared cadence structure token
            // keeps the expansion calm and reversible.
            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                expandedValueID = isOpen ? nil : value.id
            }
        } label: {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KStatusDot(signal: value.effectiveSignal.kSignal, size: .small)
                    Text(value.name.lowercased())
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(isOpen ? KStyle.primaryTextOpacity : KStyle.secondaryTextOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                    Spacer(minLength: KStyle.smallSpacing)
                    signalText(for: value)
                }

                if let lastLine = value.lastLine {
                    Text(lastLine.lowercased())
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, KStyle.cadenceDayRowTimeWidth + KStyle.smallSpacing)
                }

                if isOpen {
                    trail(for: value)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, KStyle.cadenceDayRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isOpen ? "\(value.name.lowercased()), trail open" : value.name.lowercased())
        .accessibilityIdentifier("cadence-values-row-\(value.id)")
    }

    @ViewBuilder
    private func signalText(for value: CadenceValue) -> some View {
        switch value.effectiveSignal {
        case .held:
            if let streakDays = value.streakDays {
                HStack(spacing: KStyle.microSpacing) {
                    Text("held")
                    Text("\(streakDays)d")
                        .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                }
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize()
            } else {
                KMonoCaption("held", variant: .metadata)
            }
        case .attention:
            let count = value.attentionCount ?? 0
            let detail = value.attentionText ?? (count == 1 ? "1 skipped" : "\(count) skipped")
            KMonoCaption("attention · \(detail)", variant: .metadata)
        case .none:
            KMonoCaption("no acts yet", variant: .metadata, state: .empty)
        }
    }

    private func trail(for value: CadenceValue) -> some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            ForEach(value.acts) { act in
                let impactText = act.impact == .fed ? "fed this value" : "cost this value"
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text(act.dateText.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(.white.opacity(KStyle.quaternaryTextOpacity))
                        .frame(width: KStyle.cadenceDayRowTimeWidth, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.microSpacing) {
                        Text(act.text.lowercased())
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        Text("· \(impactText)")
                            .kFont(.monoCaption)
                            .foregroundStyle(
                                (act.impact == .fed ? KStyle.liveSignal : KStyle.attentionSignal)
                                    .opacity(KStyle.secondaryTextOpacity)
                            )
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if value.moreCount > 0 {
                KMonoCaption(
                    "\(value.moreCount) more\(value.moreLabel.map { " · \($0.lowercased())" } ?? "")",
                    variant: .metadata
                )
            }
        }
        .padding(.leading, KStyle.cadenceDayRowTimeWidth + KStyle.smallSpacing)
        .padding(.vertical, KStyle.microSpacing)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(width: KStyle.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-values-trail-\(value.id)")
    }

    private func choose(_ option: CadenceValueProbeOption, for probe: CadenceValueProbe) {
        guard !pendingProbeIDs.contains(probe.id) else { return }
        selectedOptionsByProbeID[probe.id] = option
        pendingProbeIDs.insert(probe.id)
        errorTextByProbeID[probe.id] = nil

        Task {
            let result = await onAnswer(probe, option)
            await MainActor.run {
                pendingProbeIDs.remove(probe.id)
                switch result {
                case .success:
                    appendAct(for: probe, option: option)
                case .failure(let message):
                    selectedOptionsByProbeID.removeValue(forKey: probe.id)
                    errorTextByProbeID[probe.id] = message
                }
            }
        }
    }

    private func appendAct(for probe: CadenceValueProbe, option: CadenceValueProbeOption) {
        let valueID = probe.valueID ?? probe.axis ?? localValues.first?.id
        guard let valueID, let index = localValues.firstIndex(where: { $0.id == valueID }) else { return }
        var value = localValues[index]
        let impact: CadenceValueActImpact = CadenceValueActImpact(rawValue: option.value ?? option.label)
        let actID = "probe-\(probe.id)"
        guard !value.acts.contains(where: { $0.id == actID }) else { return }
        let text = option.label.lowercased()
        value.acts.insert(
            CadenceValueAct(id: actID, dateText: "today", text: text, impact: impact),
            at: .zero
        )
        value.lastActText = text
        value.lastActDateText = "today"
        if impact == .cost {
            value.signal = .attention
            value.attentionCount = (value.attentionCount ?? 0) + 1
        } else {
            value.signal = .held
            value.streakDays = max(1, (value.streakDays ?? 0) + 1)
        }
        localValues[index] = value
    }

    private func probeValueName(_ probe: CadenceValueProbe) -> String? {
        let valueID = probe.valueID ?? probe.axis
        return localValues.first(where: { $0.id == valueID })?.name.lowercased()
    }

    private static func fallbackValues(from probes: [CadenceValueProbe]) -> [CadenceValue] {
        probes.map { probe in
            let id = probe.valueID ?? probe.axis ?? probe.id
            let name = id.replacingOccurrences(of: "_", with: " ")
            return CadenceValue(id: id, name: name)
        }
    }

    private func normalized(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value!.lowercased() : nil
    }
}

private extension CadenceValueSignal {
    var kSignal: KSignal {
        switch self {
        case .held:
            return .live
        case .attention:
            return .attention
        case .none:
            return .idle
        }
    }
}
