import SwiftUI
struct BuildReportComposer: View {
    @Binding var text: String
    let contextLead: String
    let state: BuildIntentState
    let disabledReason: String?
    // A plain request flag, not FocusState: the surface owns no focusable
    // field, and SwiftUI resets an unclaimed FocusState to false — the
    // request would die before ChatComposerBar could consume it.
    @Binding var focus: Bool
    let onSubmit: () -> Void
    let contextStats: ContextStats?
    @State private var contextRingExpanded = false

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .submitting
    }

    init(
        text: Binding<String>,
        contextLead: String,
        state: BuildIntentState,
        disabledReason: String?,
        focus: Binding<Bool>,
        onSubmit: @escaping () -> Void,
        contextStats: ContextStats? = nil
    ) {
        _text = text
        self.contextLead = contextLead
        self.state = state
        self.disabledReason = disabledReason
        _focus = focus
        self.onSubmit = onSubmit
        self.contextStats = contextStats.map(BuildComposerContextStats.forBuild)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.buildComposerRowSpacing) {
            BuildComposerTargetLine(contextLead: contextLead) {
                KStyle.withMotion { contextRingExpanded = true }
            }
                .accessibilityIdentifier("build-composer-target")

            // The chat shell is the grammar owner for attach, multiline input,
            // context ring, and send. Build only supplies its target and submit seam.
            ChatComposerBar(
                text: $text,
                focusRequest: Binding(
                    get: { focus },
                    set: { focus = $0 }
                ),
                state: state == .submitting ? .loading : .resting,
                placeholder: KCopy.chatTrunkPlaceholder,
                contextStats: contextStats,
                onAttach: {},
                onSubmit: {
                    // The daemon status is informational: queueable build intents
                    // remain submit-capable while the connection is dark.
                    if canSubmit { onSubmit() }
                },
                onStop: {},
                contextRingExpanded: $contextRingExpanded,
                contextPanelTarget: contextLead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? KCopy.chatTrunkTarget
                    : contextLead,
                inputAccessibilityIdentifier: "build-composer-input",
                sendAccessibilityIdentifier: "build-composer-send"
            )

            if let inlineStatusText {
                KMonoCaption(inlineStatusText, variant: inlineStatusVariant, state: inlineStatusState)
                    // KMonoCaption owns the visual text, but its HStack can be
                    // flattened by SwiftUI. Make the status itself the queried
                    // semantic element so the dark-daemon contract survives the
                    // shared ChatComposerBar boundary.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(inlineStatusText.lowercased())
                    .accessibilityIdentifier("build-composer-status")
            }
        }
        .padding(.horizontal, KStyle.inputSidePadding)
        .padding(.trailing, KStyle.inputTrailingPadding)
        .padding(.bottom, KStyle.inputBottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-composer")
    }

    private var statusVariant: KMonoCaptionVariant {
        if case .failed = state { return .inlineError }
        return .status
    }

    private var inlineStatusText: String? {
        Self.inlineStatusText(disabledReason: disabledReason, state: state)
    }

    static func inlineStatusText(
        disabledReason: String?,
        state: BuildIntentState
    ) -> String? {
        if let disabledReason {
            return disabledReason
        }
        // A queued receipt belongs to the stream. Do not expose it under the
        // daemon-status identifier or the dark-daemon audit can observe the
        // receipt before the connection state settles.
        if case .failed = state {
            return state.text
        }
        return nil
    }

    private var inlineStatusVariant: KMonoCaptionVariant {
        if case .failed = state { return .inlineError }
        return statusVariant
    }

    private var inlineStatusState: KPrimitiveInteractionState {
        if case .failed = state { return .error }
        if disabledReason != nil { return .offline }
        return .resting
    }

}

private struct BuildComposerTargetLine: View {
    let contextLead: String
    let onOpenContext: () -> Void

    var body: some View {
        Button(action: onOpenContext) {
            Text(contextLead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KCopy.chatTrunkTarget : contextLead.lowercased())
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.trailing, KStyle.inputTrailingPadding + KStyle.inputControlSize + KStyle.inputBarSpacing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KCopy.chatContextNextTurn)
        .accessibilityHint(KCopy.chatContextRingShowHint)
        // The label names the action; the value carries the selected v43
        // thread so audits and assistive tech can verify the active target.
        .accessibilityValue(
            contextLead.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? KCopy.chatTrunkTarget
                : contextLead.lowercased()
        )
    }
}

/// The trunk-and-branch chat that grows in below the report on steer. Reuses the stream
/// line rows so k-answers and you-turns render exactly as on the desk.
struct BuildGrowInChat: View {
    let lines: [BuildStreamLine]
    let onOpenReview: (BuildRecord, BuildRecordSection.Kind) -> Void
    let onPeekLogTail: (BuildRecord) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            if lines.isEmpty {
                Text(KCopy.chatReadyToExplore)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.buildDimOpacity))
            } else {
                ForEach(lines) { line in
                    BuildStreamLineView(
                        line: line,
                        onOpenReview: onOpenReview,
                        onPeekLogTail: onPeekLogTail,
                        isDepthOrigin: isDepthOrigin
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, KStyle.rowSpacing)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.dividerHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-grow-in-chat")
    }
}

/// The rail: recent changelog, then the branch stack (parent trunk first). On the phone it
/// sits below the report/chat as a vertical strip.
