import Foundation
import SwiftUI
import UIKit

private struct CadenceWaitingSummaryStrip: View {
    let segments: [KWaitingSummarySegment]
    let onSelect: (KAppTab) -> Void

    var body: some View {
        KSummaryStrip(segments: segments, state: .active, onSelect: onSelect)
    }
}

enum CadenceBandishPrimaryTapRoute: Equatable {
    case start
    case resume
    case stayInStream
}

enum CadenceBandishTapRouter {
    static func primaryRoute(
        isCurrent: Bool,
        actionState: KBlockActionState,
        isPending: Bool
    ) -> CadenceBandishPrimaryTapRoute {
        guard isCurrent, !isPending else { return .stayInStream }
        switch actionState {
        case .available:
            return .start
        case .completed:
            return .resume
        case .started:
            return .stayInStream
        }
    }
}

enum CadenceBandishDrillInPolicy {
    static func temporalVariant(isCurrent: Bool, startsDay: Bool, hasEnded: Bool) -> KBlockRowVariant {
        if isCurrent || startsDay { return .current }
        return hasEnded ? .elapsed : .upcoming
    }

    static func renderedVariant(temporalVariant: KBlockRowVariant, isExpanded: Bool) -> KBlockRowVariant {
        isExpanded ? .current : temporalVariant
    }

    static func canToggleExpansion(
        temporalVariant: KBlockRowVariant,
        isPending: Bool,
        hasDetail: Bool
    ) -> Bool {
        temporalVariant != .current && !isPending && hasDetail
    }

    static func exposesAuditAnchor(temporalVariant: KBlockRowVariant, hasDetail: Bool) -> Bool {
        temporalVariant != .current && hasDetail
    }
}

struct CadenceTimelineView: View {
    let presentation: CadenceDayPresentation
    let now: Date
    let primitiveState: KPrimitiveInteractionState
    let onRefresh: () async -> Void
    let onWakeInit: () -> Void
    let onAction: (CadenceBlock, CadenceBlockAction) -> Void
    let onChecklistToggle: (CadenceChecklistItem, CadenceBlock) -> Void
    let onMealLog: (CadenceBlock, MealMacroMeasurements) async -> CadenceMealLogSubmitResult
    let onMealPhoto: (CadenceBlock, UIImage, String?) async -> CadenceMealLogSubmitResult
    let onDismissReview: (CadenceReviewCard) -> Void
    let onValueProbeAnswer: (CadenceReviewCard, CadenceValueProbe, CadenceValueProbeOption) async -> CadenceValueProbeSubmitResult
    let pendingNudgeIDs: Set<String>
    let nudgeErrorTexts: [String: String]
    let onNudgeDisposition: (CadenceNudgeDisposition, CadenceNudge) -> Void
    let onDismissBodyLive: (ViewPacket) -> Void
    let onBodyInterventionFeedback: (BodyCueProtocol, BodyInterventionFeedbackAction) -> Void
    let onShowCapacity: () -> Void
    let showsInlineCapacity: Bool
    let isCapacityDetailExpanded: Bool
    let capacityEntries: [CadenceCapacityEntry]
    let membraneCompare: CadenceMembraneCompareModel?
    let membraneEchoTexts: [String: String]
    let membraneVerdictErrorText: String?
    let onMembraneVerdict: (CadenceMembraneCompareModel, Bool) -> Void
    let weeklyRetroWeek: CadenceRetroWeek?
    let isWeeklyRetroOriginMarked: Bool
    let showsWeeklyRetroDetail: Bool
    let weeklyRetroModel: CadenceWeeklyRetroModel
    let onOpenWeeklyRetro: () -> Void
    let onCollapseWeeklyRetro: () -> Void
    @State private var showsEarlier = false
    @State private var expandedBlockID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: KStyle.gesturePageTransitionOffset))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KStyle.cadenceStreamPanelRowSpacing) {
                DayArc(now: now)
                    .padding(.top, KStyle.cadenceArcTopSpace)
                    .padding(.bottom, KStyle.cadenceArcBottomSpace)

                if let weeklyRetroWeek {
                    CadenceWeeklyRetroFlowView(
                        week: weeklyRetroWeek,
                        isOriginMarked: isWeeklyRetroOriginMarked,
                        onOpen: onOpenWeeklyRetro,
                        onCollapse: onCollapseWeeklyRetro
                    )
                    .padding(.bottom, KStyle.retroFlowBottomSpacing)
                }

                if showsWeeklyRetroDetail {
                    CadenceWeeklyRetroInlineDetail(model: weeklyRetroModel)
                        .padding(.bottom, KStyle.retroFlowBottomSpacing)
                }

                topSlotCueView(presentation.topSlot.active)

                if showsInlineCapacity, let capacityLine = presentation.capacityLine {
                    KCapacityLine(
                        text: capacityLine.text,
                        state: primitiveState,
                        onSelect: onShowCapacity
                    )
                    .opacity(isCapacityDetailExpanded ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
                    .accessibilityAddTraits(isCapacityDetailExpanded ? .isSelected : [])
                    .transition(.opacity)
                    .accessibilityHint(isCapacityDetailExpanded ? "capacity detail expanded below" : "shows capacity detail below")
                    if isCapacityDetailExpanded {
                        CadenceCapacityDetail(entries: capacityEntries)
                            .padding(.horizontal, KStyle.inputSidePadding)
                            .transition(detailTransition)
                    }
                }

                if let bodyInterventions = presentation.bodyInterventions {
                    CadenceBodyInterventionsChecklist(
                        model: bodyInterventions,
                        state: primitiveState,
                        onFeedback: onBodyInterventionFeedback
                    )
                    .transition(.opacity)
                }

                if let nowBlock = presentation.nowBlock {
                    CadenceMembraneCompareSurface(
                        compare: membraneCompareModel(for: nowBlock),
                        echoText: membraneEchoTexts[nowBlock.id],
                        errorText: membraneVerdictErrorText,
                        onVerdict: onMembraneVerdict
                    ) {
                        cadenceBlockRow(nowBlock)
                    }
                    .bandishCardEntrance(index: 0)
                }

                if presentation.previousToggleText != nil,
                   let previousToggleText = CadencePreviousToggleLabel.text(
                       isExpanded: showsEarlier,
                       count: presentation.previousTimelineBlocks.count
                   ) {
                    HStack {
                        Spacer(minLength: KStyle.tightRowSpacing)

                        KActRow(
                            actions: [
                                KActItem(
                                    id: "previous",
                                    label: previousToggleText,
                                    isEnabled: !primitiveState.disablesAction,
                                    accessibilityIdentifier: "k-act-previous"
                                ),
                            ],
                            variant: .cadence,
                            selectedActionIDs: showsEarlier ? ["previous"] : [],
                            state: primitiveState,
                            onSelect: { _ in
                                withAnimation(KStyle.bandishAnimation(.geometry, reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
                                    showsEarlier.toggle()
                                }
                            }
                        )
                    }
                    .padding(.top, KStyle.cadenceStreamPreviousTopPadding)
                    .padding(.bottom, KStyle.cadenceStreamPreviousBottomPadding)
                    .transition(.opacity)
                }

                ForEach(
                    Array(CadenceTimelineOrdering.streamBlocks(
                        for: presentation,
                        showsEarlier: showsEarlier
                    ).enumerated()),
                    id: \.element.id
                ) { indexedBlock in
                    Group {
                        if expandedBlockID == indexedBlock.element.id {
                            cadenceBlockRow(indexedBlock.element)
                        } else {
                            CadenceDayListRow(presentation: indexedBlock.element) {
                                withAnimation(KStyle.chatStructureMotion(UIAccessibility.isReduceMotionEnabled)) {
                                    expandedBlockID = indexedBlock.element.id
                                }
                            }
                        }
                    }
                    .bandishCardEntrance(index: indexedBlock.offset)
                }

                if presentation.visibleTimelineBlocks.isEmpty,
                   (!showsEarlier || presentation.previousTimelineBlocks.isEmpty) {
                    KMonoCaption("no active block · the day is between blocks.", variant: .metadata, state: .empty)
                        .padding(.top, KStyle.rowSpacing)
                        .accessibilityIdentifier("cadence-empty-state")
                }
            }
            .padding(.horizontal, KStyle.cadenceStreamPanelHorizontalPadding)
            .padding(.top, KStyle.cadenceStreamPanelTopPadding)
            .padding(.bottom, KStyle.cadenceStreamPanelBottomPadding)
            .padding(.horizontal, KStyle.columnMargin)
            .padding(.top, KStyle.inputSidePadding)
            .padding(.trailing, KStyle.inputTrailingPadding)
            .padding(.bottom, KStyle.inputSidePadding)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await onRefresh()
        }
    }

    private func membraneCompareModel(for block: CadenceBlockPresentation) -> CadenceMembraneCompareModel? {
        guard let membraneCompare, membraneCompare.incumbentBlockId == block.id else { return nil }
        return membraneCompare
    }

    private func cadenceBlockRow(_ block: CadenceBlockPresentation) -> some View {
        CadenceBlockRow(
            presentation: block,
            onStart: {
                if block.startsDay {
                    onWakeInit()
                } else {
                    onAction(block.block, .start)
                }
            },
            onComplete: {
                onAction(block.block, .complete)
            },
            onResume: {
                onAction(block.block, .start)
            },
            onChecklistToggle: { item in onChecklistToggle(item, block.block) },
            onMealLog: { meal in await onMealLog(block.block, meal) },
            onMealPhoto: { image, caption in await onMealPhoto(block.block, image, caption) },
            isExpanded: expandedBlockID == block.id,
            onToggleExpansion: {
                expandedBlockID = expandedBlockID == block.id ? nil : block.id
            }
        )
    }

    @ViewBuilder
    private func topSlotCueView(_ cue: CadenceTopSlotCue?) -> some View {
        switch cue {
        case .review(let card):
            CadenceReviewCardView(
                card: card,
                state: primitiveState,
                onAnswerValueProbe: { probe, option in
                    await onValueProbeAnswer(card, probe, option)
                }
            ) {
                onDismissReview(card)
            }
            .transition(.opacity)
        case .nudge(let nudge):
            CadenceNudgeCard(
                nudge: nudge,
                isPending: pendingNudgeIDs.contains(nudge.id),
                errorText: nudgeErrorTexts[nudge.id],
                onDisposition: onNudgeDisposition
            )
                .transition(.opacity)
        case .bodyLive(let packet):
            CadenceBodyLivePacketCard(packet: packet) {
                onDismissBodyLive(packet)
            }
            .transition(.opacity)
        case nil:
            EmptyView()
        }
    }
}

/// A compact schedule row: time | what | type (mock cadence-v7 day list).
/// No status dot, no duration under the time; taps expand to the full card.
private struct CadenceDayListRow: View {
    let presentation: CadenceBlockPresentation
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(presentation.startTimeText)
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                    .frame(width: KStyle.cadenceDayRowTimeWidth, alignment: .leading)

                Text(presentation.titleText.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .lineLimit(KStyle.singleLineLimit)

                Spacer(minLength: KStyle.smallSpacing)

                if let typeLabel = presentation.typeLabel {
                    Text(typeLabel)
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                        .fixedSize()
                }
            }
            .padding(.vertical, KStyle.cadenceDayRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(KStyle.hairlineOpacity))
                    .frame(height: KStyle.hairlineWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cadence-day-row-\(presentation.id)")
    }
}

struct CadenceBlockRow: View {
    let presentation: CadenceBlockPresentation
    let onStart: () -> Void
    let onComplete: () -> Void
    let onResume: () -> Void
    let onChecklistToggle: (CadenceChecklistItem) -> Void
    let onMealLog: (MealMacroMeasurements) async -> CadenceMealLogSubmitResult
    let onMealPhoto: (UIImage, String?) async -> CadenceMealLogSubmitResult
    let isExpanded: Bool
    let onToggleExpansion: () -> Void

    var body: some View {
        BandishCard(
            timeText: presentation.timeText,
            signal: presentation.block.ring.kSignal,
            title: presentation.titleText,
            detail: showsInlineBody && !usesWorkInlineAffordance ? presentation.detailText : nil,
            why: showsInlineBody && !usesWorkInlineAffordance ? presentation.whyText : nil,
            typeLabel: presentation.typeLabel,
            titleSuffix: presentation.titleSuffixText,
            badge: badgeText,
            content: blockContentForRow,
            timeGutter: presentation.timeGutter,
            dotColor: rowDotColor,
            activeFillColor: presentation.block.ring.color,
            variant: rowVariant,
            isTemporalCurrent: temporalRowVariant == .current,
            actionState: presentation.actionState,
            baselineElapsedSeconds: presentation.lifecycleControl.elapsedSeconds,
            clockReferenceDate: presentation.clockReferenceDate,
            durationSeconds: presentation.durationSeconds,
            fallbackProgressRatio: presentation.lifecycleControl.progressRatio,
            state: presentation.isPending ? .loading : .resting,
            accessibilityIdentifier: rowAccessibilityIdentifier,
            onChecklistToggle: { item in
                onChecklistToggle(CadenceChecklistItem(item))
            },
            onStart: primaryTapRoute == .start ? onStart : nil,
            onComplete: onComplete,
            onResume: primaryTapRoute == .resume ? onResume : nil,
            onTap: nil
        ) {
            rowAccessory
        } footer: {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if presentation.block.normalizedTypeText == "work",
                   rowVariant == .current,
                   presentation.actionState == .available {
                    CadenceWorkModeChips(
                        currentMode: presentation.block.brainState ?? presentation.content.metaSuffix,
                        foregroundColor: textBaseColor
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsBandishBody {
                    BandishBodiesView(
                        block: presentation.block,
                        temporal: bandishBodyTemporalVariant,
                        actionState: presentation.actionState,
                        baselineElapsedSeconds: presentation.lifecycleControl.elapsedSeconds ?? 0,
                        clockReferenceDate: presentation.clockReferenceDate,
                        isRunning: temporalRowVariant == .current && presentation.actionState == .started,
                        foregroundColor: textBaseColor,
                        usesPaperTone: usesPaperText,
                        onSubtaskToggle: { item in
                            onChecklistToggle(CadenceChecklistItem(item))
                        }
                    )
                    .transition(.opacity)
                }

                if usesWorkInlineAffordance, let text = workInlineAffordanceText {
                    HStack {
                        Spacer(minLength: KStyle.tightRowSpacing)
                        CadenceWorkInlineAffordance(text: text, foregroundColor: textBaseColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !presentation.showsMealLogAffordance, let mealLogEchoText = presentation.mealLogEchoText {
                    CadenceBandishFooterCaption(text: mealLogEchoText, isPaper: usesPaperText)
                }

                if let statusText = statusCaptionText {
                    CadenceBandishFooterCaption(text: statusText, isPaper: usesPaperText)
                }

                if presentation.content.checklist == nil, presentation.block.showsOpsChecklist {
                    CadenceChecklistRows(
                        items: presentation.block.checklist,
                        foregroundColor: textBaseColor,
                        onToggle: onChecklistToggle
                    )
                    .transition(.opacity)
                }

                if let actionErrorText = presentation.actionErrorText {
                    CadenceBandishFooterCaption(
                        text: actionErrorText,
                        isPaper: usesPaperText,
                        isError: true
                    )
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let actionCaptionText = presentation.actionCaptionText {
                    CadenceBandishFooterCaption(text: actionCaptionText, isPaper: usesPaperText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityLabel(actionCaptionText.lowercased())
                }

                if presentation.isStartedOverrun {
                    CadenceOverrunCompleteButton(
                        isEnabled: !presentation.isPending,
                        isPaper: usesPaperText,
                        onSelect: onComplete
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if exposesDrillInAuditAnchor {
                // The audit walker locates a drillable row through this stable
                // identifier, but the blessed mocks carry no visual chevron.
                Color.clear
                    .frame(width: KStyle.hairlineWidth, height: KStyle.hairlineWidth)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isExpanded ? "collapse" : "expand")
                    .accessibilityIdentifier("\(rowAccessibilityIdentifier)-drill-in-cue")
            }
        }
        .gesture(
            MagnifyGesture()
                .onEnded { value in
                    // Pinch-out opens the detail, pinch-in closes it. Two-finger, so it
                    // never competes with one-finger scroll or the tap/long-press paths.
                    if value.magnification > KStyle.bandishPinchExpandThreshold, !isExpanded {
                        toggleExpansionIfAvailable()
                    } else if value.magnification < KStyle.bandishPinchCollapseThreshold, isExpanded {
                        toggleExpansionIfAvailable()
                    }
                }
        )
    }

    @ViewBuilder
    private var rowAccessory: some View {
        VStack(alignment: .trailing, spacing: KStyle.microSpacing) {
            if presentation.showsMealLogAffordance {
                CadenceMealLogInlineEntry(
                    state: presentation.isPending ? .loading : .resting,
                    echoText: presentation.mealLogEchoText,
                    alignment: .trailing,
                    foregroundColor: textBaseColor,
                    onSubmit: onMealLog,
                    onPhoto: onMealPhoto
                )
            }

        }
    }

    private var rowVariant: KBlockRowVariant {
        CadenceBandishDrillInPolicy.renderedVariant(
            temporalVariant: temporalRowVariant,
            isExpanded: isExpanded
        )
    }

    private var temporalRowVariant: KBlockRowVariant {
        CadenceBandishDrillInPolicy.temporalVariant(
            isCurrent: presentation.isNow,
            startsDay: presentation.startsDay,
            hasEnded: presentation.hasEnded
        )
    }

    private var primaryTapRoute: CadenceBandishPrimaryTapRoute {
        CadenceBandishTapRouter.primaryRoute(
            isCurrent: temporalRowVariant == .current,
            actionState: presentation.actionState,
            isPending: presentation.isPending
        )
    }

    private var rowAccessibilityIdentifier: String {
        if presentation.isNow || presentation.startsDay {
            return "cadence-block-current"
        }
        if presentation.hasEnded {
            return "cadence-block-previous-\(presentation.id)"
        }
        return "cadence-block-\(presentation.id)"
    }

    private var badgeText: String? {
        nil
    }

    private var usesPaperText: Bool {
        rowVariant == .current && presentation.actionState != .started
    }

    private var showsInlineBody: Bool {
        rowVariant == .current || isExpanded
    }

    private var showsBandishBody: Bool {
        guard richBodyPresentation.kind != .none else { return false }
        if showsInlineBody { return true }
        return richBodyPresentation.kind == .workSession
    }

    private var bandishBodyTemporalVariant: BandishBodyTemporalVariant {
        if isExpanded { return .pastDetail }
        switch temporalRowVariant {
        case .current:
            return .current
        case .elapsed:
            return .past
        case .upcoming:
            return .future
        }
    }

    private var richBodyPresentation: BandishBodyPresentation {
        BandishBodyVariantResolver.presentation(
            for: presentation.block,
            temporal: bandishBodyTemporalVariant,
            actionState: presentation.actionState,
            elapsedSeconds: presentation.lifecycleControl.elapsedSeconds
        )
    }

    private var usesWorkInlineAffordance: Bool {
        presentation.block.normalizedTypeText == "work"
            && rowVariant == .current
            && richBodyPresentation.kind == .none
    }

    private var textBaseColor: Color {
        usesPaperText ? KStyle.nearBlack : .white
    }

    private var blockContentForRow: BlockContent? {
        if !showsInlineBody {
            guard let secondaryInfoText = presentation.secondaryInfoText else { return nil }
            return BlockContent(detailLines: [secondaryInfoText])
        }
        if richBodyPresentation.kind != .none {
            return nil
        }
        let content = usesWorkInlineAffordance
            ? BlockContent(
                metaSuffix: presentation.content.metaSuffix,
                detailLines: presentation.content.detailLines,
                checklist: presentation.content.checklist,
                liveLine: nil
            )
            : presentation.content
        return content.isEmpty ? nil : content
    }

    private var rowDotColor: Color {
        if temporalRowVariant == .elapsed, rowVariant != .current, presentation.actionState != .completed {
            return .white
        }
        return presentation.block.ring.color
    }

    private var exposesDrillInAuditAnchor: Bool {
        CadenceBandishDrillInPolicy.exposesAuditAnchor(
            temporalVariant: temporalRowVariant,
            hasDetail: presentation.hasDrillInDetail
        )
    }

    private var statusCaptionText: String? {
        let text = presentation.statusText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let text, !text.isEmpty else { return nil }
        return ["complete", "completed", "done"].contains(text) ? nil : text
    }

    private var workInlineAffordanceText: String? {
        let candidates = [
            presentation.detailText,
            presentation.content.liveLine,
            presentation.whyText,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }
    }

    private func toggleExpansionIfAvailable() {
        guard CadenceBandishDrillInPolicy.canToggleExpansion(
            temporalVariant: temporalRowVariant,
            isPending: presentation.isPending,
            hasDetail: presentation.hasDrillInDetail
        ) else { return }
        onToggleExpansion()
    }

}
