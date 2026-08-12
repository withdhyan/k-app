import SwiftUI

/// The selected build thread is a single card-shaped surface. Its data is only
/// the existing branch/plan projection; no branch wire model is introduced.
struct BuildBranchSurface: View {
    let branch: BuildBranchItem
    let summary: BuildStatusSummary?
    let now: Date
    let isActive: Bool
    @Binding var intentText: String
    let composerState: BuildIntentState
    let composerDisabledReason: String?
    @Binding var composerFocus: Bool
    let composerStageVisible: Bool
    let onSubmitIntent: () -> Void
    let contextStats: ContextStats?
    let onClose: () -> Void
    let onOpenReview: (BuildRecord, BuildRecordSection.Kind) -> Void
    let onPeekLogTail: (BuildRecord) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var detailsExpanded = false
    @State private var showFullLog = false
    @State private var messageStage = 0
    @State private var travelTask: Task<Void, Never>?

    private var reduceMotion: Bool {
        systemReduceMotion || KStyle.auditReduceMotionOverride
    }

    private var units: [BuildRecord] { summary?.units ?? [] }
    private var traces: [BuildRecord] { (summary?.history ?? []) + (summary?.lanes ?? []) }
    private var segments: [BuildSegmentState] {
        let result = units.map { BuildSegmentState.from(unitState: $0.state) }
        return result.isEmpty ? [.pending] : result
    }

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.buildReportSurfaceSpacing) {
                head
                details
                    .opacity(detailsExpanded ? KStyle.fullOpacity : .zero)
                    .frame(height: detailsExpanded ? nil : .zero, alignment: .top)
                    .clipped()
                    .accessibilityHidden(!detailsExpanded)
                    .animation(KStyle.chatThreadDetailMotion(reduceMotion), value: detailsExpanded)
                conversation
                BuildReportComposer(
                    text: $intentText,
                    contextLead: branch.composedTitle,
                    state: composerState,
                    disabledReason: composerDisabledReason,
                    focus: $composerFocus,
                    onSubmit: onSubmitIntent,
                    contextStats: contextStats
                )
                .opacity(composerStageVisible ? KStyle.fullOpacity : .zero)
                .allowsHitTesting(composerStageVisible)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("build-branch-composer-\(branch.id)")
                .animation(
                    KStyle.chatThreadSwapMotion(
                        reduceMotion,
                        phase: composerStageVisible ? .composerEnter : .trunkExit
                    ),
                    value: composerStageVisible
                )
            }
            .padding(KStyle.cardLargePadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-branch-surface-\(branch.id)")
        .onAppear { scheduleMessageTravel() }
        .onChange(of: isActive) { _, _ in scheduleMessageTravel() }
        .onDisappear { travelTask?.cancel() }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(branch.composedTitle.lowercased())
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    .accessibilityIdentifier("build-branch-title-\(branch.id)")
                ZStack(alignment: .leading) {
                    BuildSegmentBar(segments: segments)
                        .accessibilityHidden(true)
                    branchDashSemantics
                }
                Spacer(minLength: KStyle.smallSpacing)
                Button {
                    KStyle.withMotion { detailsExpanded.toggle() }
                } label: {
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                        .font(KStyle.monoCaptionFont)
                        .foregroundStyle(Color.white.opacity(KStyle.buildDimmerOpacity))
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(detailsExpanded ? "collapse branch details" : "expand branch details")
                .accessibilityIdentifier("build-branch-details-toggle-\(branch.id)")

                Button {
                    // The parent owns selection and performs the reversed travel.
                    onClose()
                } label: {
                    Text("✕")
                        .font(KStyle.contentFont)
                        .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("close \(branch.composedTitle.lowercased())")
                .accessibilityIdentifier("build-branch-close-\(branch.id)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("build-branch-head-\(branch.id)")
        }
    }

    private var branchDashSemantics: some View {
        HStack(spacing: KStyle.buildSegmentPillGap) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, state in
                RoundedRectangle(cornerRadius: KStyle.buildSegmentPillRadius, style: .continuous)
                    .fill(Color.clear)
                    .frame(width: KStyle.buildSegmentPillWidth, height: KStyle.buildSegmentPillHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("branch segment \(index + 1)")
                    .accessibilityValue(state.rawValue)
                    .accessibilityIdentifier("build-branch-dash-\(branch.id)-\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-branch-dashes-\(branch.id)")
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            KMonoCaption("sub sections", variant: .metadata, state: .disabled)
                .accessibilityIdentifier("build-branch-subsections-\(branch.id)")
            if units.isEmpty {
                KMonoCaption("no units yet", variant: .metadata)
                    .accessibilityIdentifier("build-branch-units-empty-\(branch.id)")
            } else {
                ForEach(units) { unit in
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        Text(unit.title.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                        BuildSegmentBar(segments: [BuildSegmentState.from(unitState: unit.state)])
                        Text((unit.state ?? "queued").lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                    }
                    .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("build-branch-unit-\(branch.id)-\(unit.id)")
                }
            }

            KMonoCaption("timeline", variant: .metadata, state: .disabled)
                .padding(.top, KStyle.smallSpacing)
                .accessibilityIdentifier("build-branch-timeline-heading-\(branch.id)")
            if traces.isEmpty {
                KMonoCaption("no traces yet", variant: .metadata)
                    .accessibilityIdentifier("build-branch-timeline-empty-\(branch.id)")
            } else {
                ForEach(traces) { trace in
                    traceRow(trace)
                }
            }

            KActRow(
                actions: [KActItem(
                    id: "show-full-log",
                    label: showFullLog ? "hide full log" : "show full log",
                    accessibilityIdentifier: "build-branch-show-full-log-\(branch.id)"
                )],
                variant: .build,
                onSelect: { _ in KStyle.withMotion { showFullLog.toggle() } }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("build-branch-timeline-actions-\(branch.id)")

            if showFullLog {
                Text(traces.compactMap { $0.logTail ?? $0.detail ?? $0.title }.joined(separator: "\n"))
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("build-branch-full-log-\(branch.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-branch-details-\(branch.id)")
    }

    private func traceRow(_ trace: BuildRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            if trace.isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 2.0, paused: false)) { context in
                    Text("·")
                        .foregroundStyle(Color.white.opacity(
                            KStyle.breathOpacity(
                                at: context.date,
                                period: KStyle.buildSegmentBreathPeriod,
                                minimumOpacity: KStyle.buildSegmentBreathMinOpacity
                            )
                        ))
                }
            }
            Text(trace.title.lowercased())
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(trace.isActive ? KStyle.secondaryTextOpacity : KStyle.quaternaryTextOpacity))
            Spacer(minLength: KStyle.smallSpacing)
            if let age = trace.age {
                Text(age.lowercased())
                    .kFont(.monoCaptionDigit)
                    .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("build-branch-trace-\(branch.id)-\(trace.id)")
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("conversation", variant: .metadata, state: .disabled)
                .opacity(messageStage >= 1 ? KStyle.fullOpacity : .zero)
                .animation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .messageFirst), value: messageStage)
                .accessibilityIdentifier("build-branch-conversation-heading-\(branch.id)")
            KStreamRow(role: .runner, accessibilityText: branch.composedTitle.lowercased()) {
                Text("the branch is \((summary?.state ?? "queued").lowercased())")
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(messageStage >= 1 ? KStyle.fullOpacity : .zero)
            .animation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .messageFirst), value: messageStage)
            .accessibilityIdentifier("build-branch-message-\(branch.id)-0")

            if let detail = summary?.detail, !detail.isEmpty {
                KStreamRow(role: .runner, accessibilityText: detail.lowercased()) {
                    Text(detail.lowercased())
                        .font(KStyle.contentFont)
                        .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(messageStage >= 2 ? KStyle.fullOpacity : .zero)
                .animation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .messageSecond), value: messageStage)
                .accessibilityIdentifier("build-branch-message-\(branch.id)-1")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-branch-conversation-\(branch.id)")
    }

    private func scheduleMessageTravel() {
        travelTask?.cancel()
        guard isActive, !reduceMotion else {
            messageStage = isActive ? 2 : 0
            return
        }
        messageStage = 0
        travelTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(KStyle.chatThreadMessageFirstDelay * 1_000_000_000))
            guard !Task.isCancelled, isActive else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(false, phase: .messageFirst)) { messageStage = 1 }
            let remaining = max(0, KStyle.chatThreadMessageSecondDelay - KStyle.chatThreadMessageFirstDelay)
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, isActive else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(false, phase: .messageSecond)) { messageStage = 2 }
        }
    }
}

private extension BuildRecord {
    var isActive: Bool {
        let value = state?.lowercased() ?? ""
        return ["building", "verifying", "integrating", "running", "processing", "deploying"].contains(value)
    }
}
