#if DEBUG
import SwiftUI

struct ShowcasePrimitiveSpec: Identifiable, Equatable {
    let componentName: String
    let variant: String
    let state: KPrimitiveInteractionState

    var id: String {
        "\(componentName)-\(variant)-\(state.rawValue)"
    }

    var label: String {
        "\(componentName) · \(variant) · \(state.rawValue)"
    }
}

struct ShowcaseComponentGroup: Identifiable, Equatable {
    let component: KPrimitiveComponentDescriptor
    let specimens: [ShowcasePrimitiveSpec]

    var id: String { component.name }
}

enum ShowcaseCatalogModel {
    static let groups: [ShowcaseComponentGroup] = KPrimitiveRegistry.components
        .filter { !$0.isDeprecated }
        .map { component in
            ShowcaseComponentGroup(
                component: component,
                specimens: component.variants.flatMap { variant in
                    component.interactionStates.map { stateName in
                        ShowcasePrimitiveSpec(
                            componentName: component.name,
                            variant: variant,
                            state: KPrimitiveInteractionState(rawValue: stateName) ?? .resting
                        )
                    }
                }
            )
        }
}

struct ShowcaseView: View {
    private let groups = ShowcaseCatalogModel.groups
    @State private var selectedTab = KAppTab.build
    @State private var selectedSelector = "biology"

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(groups) { group in
                        componentSection(group)
                    }
                    chatGrammarSection
                    cardPacketSection
                    chatBlockSection
                    if CensusRemainderFixture.isEnabled() {
                        censusProvenanceSection
                    }
                    activeCadenceSection
                    typedBandishSection
                }
                .frame(width: KStyle.columnWidth(in: proxy.size.width), alignment: .leading)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-view")
    }

    private func componentSection(_ group: ShowcaseComponentGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            KMonoCaption(group.component.name, variant: .status, state: .active)

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(group.specimens) { specimen in
                    VStack(alignment: .leading, spacing: 8) {
                        KMonoCaption(specimen.label, variant: .metadata, state: specimen.state)
                        primitive(for: specimen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("showcase-\(specimen.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-component-\(group.component.name)")
    }

    private var typedBandishSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KMonoCaption("typed bandish", variant: .status, state: .active)

            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(TypedBandishFixture.all) { fixture in
                    VStack(alignment: .leading, spacing: 8) {
                        KMonoCaption(fixture.label, variant: .metadata)
                        typedBandishPrimitive(fixture)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("showcase-typed-bandish-\(fixture.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-typed-bandish")
    }

    private var cardPacketSection: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("card packets", variant: .status, state: .active)

            LazyVStack(alignment: .leading, spacing: KStyle.cardPadding) {
                ForEach(ViewPacketCardFixture.all) { fixture in
                    VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                        KMonoCaption(fixture.label, variant: .metadata)
                        RenderViewPacket(packet: fixture.packet)
                        if fixture.isSuppressed {
                            KMonoCaption("suppressed · no card rendered", variant: .metadata, state: .disabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("showcase-card-packet-\(fixture.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-card-packets")
    }

    private var chatGrammarSection: some View {
        let actions = [
            ChatNextActionItem(id: "watch", label: "watch it a week"),
            ChatNextActionItem(id: "compare", label: "compare rem"),
            ChatNextActionItem(id: "pin", label: "pin to bio"),
        ]
        let followUps = [
            ChatNextActionItem(id: "variance", label: "inside variance?"),
            ChatNextActionItem(id: "training", label: "training days?"),
            ChatNextActionItem(id: "rem", label: "does rem move too?"),
        ]

        return VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("chat surface grammar", variant: .status, state: .active)

            KChatVerbDrawer(
                isOpen: true,
                receipt: ChatReceipt(soulVersion: "values-model v2", refCount: 5),
                messageID: "showcase",
                onSelect: { _ in }
            )

            KChatActionRow(
                actions: actions,
                followUps: followUps,
                isActive: true,
                isFollowUpPage: false,
                accessibilityPrefix: "showcase-chat-next-actions",
                onSelect: { _ in },
                onFollowUp: { _ in },
                onPageChange: { _ in }
            )

            KChatActionRow(
                actions: actions,
                selectedActionID: "compare",
                isActive: false,
                accessibilityPrefix: "showcase-chat-next-actions-previous",
                onSelect: { _ in }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-chat-surface-grammar")
    }

    private var chatBlockSection: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("chat blocks", variant: .status, state: .active)

            LazyVStack(alignment: .leading, spacing: KStyle.cardPadding) {
                ForEach(JarvisBlockFixture.all) { fixture in
                    VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                        KMonoCaption(fixture.label, variant: .metadata)
                        RenderViewPacket(packet: fixture.packet, context: .chatStream)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("showcase-chat-block-\(fixture.id)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-chat-blocks")
    }

    private var activeCadenceSection: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("active cadence", variant: .status, state: .active)

            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                KMonoCaption("CadenceActiveWorkRow · current · available · work", variant: .metadata)
                CadenceShowcaseActiveWorkRow()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("showcase-cadence-active-work")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-active-cadence")
    }

    private var censusProvenanceSection: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            KMonoCaption("census provenance", variant: .status, state: .active)

            ForEach(CensusRemainderFixture.provenancePackets) { packet in
                A2UIPanel(packet: packet)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("showcase-census-provenance-\(packet.id)")
            }

            // The current HEAD retired the standalone report rail in favor of
            // the mounted report sentence; keep the census specimen on that
            // surface instead of reviving the stale component.
            BuildReportCompactSentence(report: CensusRemainderFixture.buildReport)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("showcase-census-report-rail")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase-census-provenance")
    }

    @ViewBuilder
    private func typedBandishPrimitive(_ fixture: TypedBandishFixture) -> some View {
        BandishCard(
            timeText: fixture.timeText,
            signal: fixture.signal,
            title: fixture.title,
            detail: fixture.detail,
            why: fixture.why,
            typeLabel: fixture.type,
            content: fixture.content,
            variant: fixture.variant,
            isTemporalCurrent: fixture.variant == .current,
            actionState: fixture.variant == .current ? .started : .available,
            clockReferenceDate: .now,
            state: .resting
        ) {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func primitive(for specimen: ShowcasePrimitiveSpec) -> some View {
        switch specimen.componentName {
        case "KBlockDetail":
            KBlockDetail(
                title: "core work",
                timeText: "09:00 · 1:30",
                why: "because the edge needs a clean proof",
                meta: "core · core · work · convergent",
                sections: sampleDetailSections,
                state: specimen.state
            ) {
                KActRow(
                    actions: sampleActions,
                    variant: .cadence,
                    state: specimen.state,
                    onSelect: { _ in }
                )
            }
        case "KSensesRail":
            KSensesRail(
                groups: specimen.state == .empty ? [] : sampleSensesGroups,
                state: specimen.state,
                onSelectGroup: { _ in }
            )
        case "KNextRow":
            KNextRow(
                timeText: specimen.state == .empty ? nil : "13:00",
                title: specimen.state == .empty ? nil : "middle",
                state: specimen.state
            )
        case "KRestStrip":
            KRestStrip(
                text: specimen.state == .empty ? nil : "15:00 physical · 20:00 reflect",
                state: specimen.state
            )
        case "KCapacityLine":
            KCapacityLine(
                text: specimen.state == .empty ? nil : "left: converge 2h · physical 1h · restore 30m",
                state: specimen.state,
                onSelect: {}
            )
        case "KPaperCard":
            KPaperCard(state: specimen.state) {
                cardBody(title: "\(specimen.variant) paper", state: specimen.state)
            }
        case "KGlassCard":
            KGlassCard(state: specimen.state) {
                cardBody(title: "\(specimen.variant) glass", state: specimen.state)
            }
        case "KColumnPanel":
            KColumnPanel(state: specimen.state) {
                cardBody(title: "\(specimen.variant) column", state: specimen.state)
                    .padding(KStyle.cardPadding)
            }
        case "KActRow":
            KActRow(
                actions: sampleActions,
                variant: KActRowVariant(rawValue: specimen.variant) ?? .cadence,
                state: specimen.state,
                onSelect: { _ in }
            )
        case "KOptionButton":
            KOptionButton(
                label: specimen.state == .error ? "sure?" : specimen.variant,
                variant: KOptionButtonVariant(rawValue: specimen.variant) ?? .quietHairline,
                isEnabled: !specimen.state.disablesAction,
                isPending: specimen.state == .loading,
                isConfirming: specimen.state == .error,
                state: specimen.state,
                onSelect: {}
            )
        case "KMonoCaption":
            KMonoCaption(
                captionText(for: specimen),
                variant: KMonoCaptionVariant(rawValue: specimen.variant) ?? .status,
                state: specimen.state
            )
        case "KStatusDot":
            KStatusDot(
                signal: KSignal(rawValue: specimen.variant) ?? .idle,
                state: specimen.state,
                size: .regular
            )
            .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        case "KLoadingPrimitive":
            KLoadingPrimitive(
                variant: KLoadingVariant(rawValue: specimen.variant) ?? .skeleton,
                lineCount: 3,
                label: "loading",
                accessibilityIdentifier: "showcase-loading"
            )
        case "KTabStrip":
            KTabStrip(
                selection: $selectedTab,
                cadenceNeedsAttention: specimen.variant == "attention-dot",
                chatHasUnread: specimen.variant == "attention-dot",
                openBuildCards: specimen.variant == "root" ? 0 : 1,
                unjudgedMindOutputs: specimen.variant == "root" ? 0 : 2,
                adminDueTodayItems: specimen.variant == "attention-dot" ? 1 : 0,
                staleTabs: specimen.variant == "stale-dot" ? [.build, .mind] : [],
                state: specimen.state
            )
        case "KSelectorStrip":
            KSelectorStrip(
                selection: $selectedSelector,
                items: [
                    KSelectorItem(id: "biology", title: "biology", accessibilityIdentifier: "showcase-selector-biology"),
                    KSelectorItem(id: "meditation", title: "meditation", accessibilityIdentifier: "showcase-selector-meditation"),
                    KSelectorItem(id: "nutrition", title: "nutrition", accessibilityIdentifier: "showcase-selector-nutrition"),
                ],
                state: specimen.state,
                accessibilityIdentifier: "showcase-selector-strip"
            )
        case "KNavBar":
            KNavBar(
                selection: $selectedTab,
                axis: specimen.variant == "side-rail" ? .vertical : .horizontal,
                cadenceNeedsAttention: true,
                chatHasUnread: true,
                openBuildCards: 1,
                unjudgedMindOutputs: 2,
                adminDueTodayItems: 1,
                staleTabs: [.build],
                state: specimen.state
            )
        case "KStreamRow":
            KStreamRow(
                role: KStreamRowRole(rawValue: specimen.variant) ?? .k,
                meta: "09:30",
                state: specimen.state,
                accessibilityText: specimen.label
            ) {
                Text("\(specimen.variant) stream line")
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case "KProgressStrip":
            KProgressStrip(
                title: "\(specimen.variant) mission",
                progressText: "2 of 5",
                progressRatio: specimen.state == .disabled ? KStyle.zeroProgressRatio : KStyle.sampleProgressRatio,
                variant: KProgressStripVariant(rawValue: specimen.variant) ?? .buildMission,
                state: specimen.state
            )
        case "KInputBar":
            KInputBar(
                text: Binding.constant(inputText(for: specimen)),
                mode: KInputBarMode(rawValue: specimen.variant) ?? .chat,
                state: specimen.state,
                statusText: inputStatusText(for: specimen.state),
                disabledReason: specimen.state == .disabled ? "disabled" : nil,
                onSubmit: {},
                onStop: {}
            )
        case "KChecklistRow":
            KChecklistRow(
                title: specimen.variant == "done" ? "done checklist item" : "open checklist item",
                isDone: specimen.variant == "done",
                state: specimen.state,
                onToggle: {}
            )
        case "KVerdictBar":
            KVerdictBar(
                pendingVerdict: pendingVerdict(for: specimen.state),
                state: specimen.state,
                errorText: specimen.state == .error ? KCopy.answerFailed(reason: "network") : nil,
                onVerdict: { _ in },
                onRetry: {}
            )
        case "KEvidenceBlock":
            KEvidenceBlock(
                text: evidenceText(for: specimen),
                variant: KEvidenceBlockVariant(rawValue: specimen.variant) ?? .mono,
                state: specimen.state
            )
        case "KSummaryStrip":
            KSummaryStrip(
                segments: sampleSummarySegments,
                state: specimen.state,
                onSelect: { selectedTab = $0 }
            )
        default:
            KMonoCaption("missing showcase renderer", variant: .inlineError, state: .error)
        }
    }

    private func cardBody(title: String, state: KPrimitiveInteractionState) -> some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            Text(title.lowercased())
                .font(KStyle.blockDefaultTitleFont)
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
            KMonoCaption("state \(state.rawValue)", variant: .metadata, state: state)
        }
    }

    private var sampleActions: [KActItem] {
        [
            KActItem(id: "complete"),
            KActItem(id: "skip"),
            KActItem(id: "retry"),
        ]
    }

    private var sampleSummarySegments: [KWaitingSummarySegment] {
        [
            KWaitingSummarySegment(id: "build", label: "1 build card", tab: .build),
            KWaitingSummarySegment(id: "review", label: "1 review card", tab: .cadence),
            KWaitingSummarySegment(id: "mind", label: "2 unjudged", tab: .mind),
        ]
    }

    private var sampleDetailSections: [DetailSection] {
        [
            DetailSection(
                header: "subtasks",
                checklist: [
                    ChecklistItem(id: "one", text: "write the single aim"),
                    ChecklistItem(id: "two", text: "capture proof", isDone: true),
                ]
            ),
            DetailSection(
                header: "prep arc",
                lines: ["prime", "practice · current", "close"]
            ),
        ]
    }

    private var sampleSensesGroups: [KSensesRailGroup] {
        [
            KSensesRailGroup(id: "body", title: "body", source: "body", lines: ["hrv 64", "sleep 7h12", "strain 7"]),
            KSensesRailGroup(id: "capacity", title: "capacity", source: "cadence", lines: ["core 2h", "physical 1h"]),
            KSensesRailGroup(id: "nutrition", title: "nutrition", source: "meals", lines: ["calories 620 kcal", "protein 40g"]),
        ]
    }

    private func blockBadge(for specimen: ShowcasePrimitiveSpec) -> String? {
        switch specimen.variant {
        case "current":
            return "now"
        case "upcoming":
            return "next"
        default:
            return specimen.state == .loading ? "loading" : nil
        }
    }

    private func signal(for specimen: ShowcasePrimitiveSpec) -> KSignal {
        switch specimen.state {
        case .error:
            return .error
        case .offline:
            return .offline
        case .loading:
            return .attention
        case .active:
            return .live
        case .disabled:
            return .idle
        case .empty, .stale:
            return .idle
        case .resting:
            return specimen.variant == "elapsed" ? .idle : .live
        }
    }

    private func captionText(for specimen: ShowcasePrimitiveSpec) -> String {
        switch specimen.variant {
        case "inline-error":
            return KCopy.answerFailed(reason: "network")
        case "staleness":
            return "as of 09:30"
        case "footer":
            return "snapshot synced"
        case "metadata":
            return "unit 4 · runner"
        default:
            return specimen.state == .offline ? KCopy.offlineRetrying : "live"
        }
    }

    private func inputText(for specimen: ShowcasePrimitiveSpec) -> String {
        specimen.state == .loading ? "draft next intent" : "ship quiet coverage"
    }

    private func inputStatusText(for state: KPrimitiveInteractionState) -> String? {
        switch state {
        case .loading:
            return KCopy.drafting
        case .error:
            return KCopy.answerFailed(reason: "network")
        case .offline:
            return KCopy.offlineRetrying
        case .active:
            return KCopy.answerPending
        case .resting, .disabled, .empty, .stale:
            return nil
        }
    }

    private func pendingVerdict(for state: KPrimitiveInteractionState) -> MindVerdict? {
        state == .active || state == .loading ? .nod : nil
    }

    private func evidenceText(for specimen: ShowcasePrimitiveSpec) -> String {
        switch specimen.state {
        case .loading, .error, .offline:
            return ""
        default:
            switch specimen.variant {
            case "diff":
                return "- old line\n+ new line"
            case "gate-output":
                return "test gate passed\ncoverage checked"
            case "log-tail":
                return "runner: synced\nrunner: idle"
            default:
                return "evidence id: build.unit.42"
            }
        }
    }
}

private struct ViewPacketCardFixture: Identifiable {
    let id: String
    let label: String
    let packet: ViewPacket

    var isSuppressed: Bool {
        !ViewPacketRenderer.shouldRender(packet)
    }

    static let all: [ViewPacketCardFixture] = [
        fixture(.cue, state: "pending", anchor: "the corpus blocks translation", ask: "hold this cue for now?"),
        fixture(.cue, state: "fired", anchor: "the corpus blocks translation", ask: "keep this dependency cue?", interruption: .peripheral, queuedCueCount: 2),
        fixture(.cue, state: "suppressed-not-rendered", anchor: "a low-value aside", ask: "surface this now?"),
        fixture(.cue, state: "pre-permission", anchor: "conversation cues are off", ask: "allow them when you’re ready?"),
        fixture(.cue, state: "pending-sensor", anchor: "listening for a useful moment", ask: "stay quiet for now?"),
        fixture(.cue, state: "daemon-unreachable", anchor: "cue judgment is offline", ask: "leave this quiet?"),

        fixture(.body, state: "still-learning", anchor: "three mornings of hrv", ask: "keep the next move small?"),
        fixture(.body, state: "typical", anchor: "your usual morning range", ask: "keep today’s cadence?"),
        fixture(.body, state: "outlier", anchor: "hrv sits below your range", ask: "lower today’s load?", interruption: .peripheral),
        fixture(.body, state: "low-confidence", anchor: "sleep data is incomplete", ask: "wait for a clearer signal?"),
        fixture(.body, state: "pre-permission", anchor: "body sensing is off", ask: "connect it when you’re ready?"),
        fixture(.body, state: "pending-sensor", anchor: "body signals are still arriving", ask: "wait before changing cadence?"),
        fixture(.body, state: "daemon-unreachable", anchor: "body judgment is offline", ask: "keep the current cadence?"),

        fixture(.translation, state: "partial", anchor: "the hindi reply is still forming", ask: "keep this draft?"),
        fixture(.translation, state: "final", anchor: "train 12952 stays unchanged", ask: "keep this translation?", interruption: .peripheral),
        fixture(.translation, state: "degraded-to-clean-transcript", anchor: "translation paused on a name", ask: "keep the clean transcript?"),
        fixture(.translation, state: "pre-permission", anchor: "translation listening is off", ask: "allow it for this session?"),
        fixture(.translation, state: "pending-sensor", anchor: "waiting for clear speech", ask: "keep listening?"),
        fixture(.translation, state: "daemon-unreachable", anchor: "translation judgment is offline", ask: "keep the clean transcript?"),
    ]

    private static func fixture(
        _ kind: ViewPacketCardKind,
        state: String,
        anchor: String,
        ask: String,
        interruption: KPrimitiveInterruptionClass = .ambient,
        queuedCueCount: Int? = nil
    ) -> ViewPacketCardFixture {
        let id = "\(kind.rawValue.replacingOccurrences(of: ".", with: "-"))-\(state)"
        let briefContext: (whyNow: String, blocker: String) = {
            switch state {
            case "pre-permission":
                return ("This source stays off until permission is granted.", "permission is not granted")
            case "pending-sensor":
                return ("No complete source reading is available yet.", "the source reading is incomplete")
            case "daemon-unreachable":
                return ("No fresh judgment is available while the daemon is unreachable.", "the daemon is unreachable")
            default:
                return ("The current signal stays inspectable.", "nothing — ready to decide")
            }
        }()
        var fields: [String: ViewPacketJSONValue] = [
            "status": .string(state),
            "interruptionClass": .string(interruption.rawValue),
            "maxSimultaneousCues": .number(1),
            "face": CardFace(
                anchor: CardFaceAnchor(style: "restatement", text: anchor),
                ask: ask
            ).jsonValue,
            "disclosure": .object([
                "brief": .object([
                    "whyNow": .string(briefContext.whyNow),
                    "openQuestion": .string(ask),
                    "blocker": .string(briefContext.blocker),
                    "stakes": .string("reversible · silence leaves the current path unchanged"),
                ]),
                "evidence": .array([
                    .object([
                        "label": .string("one sovereign-derived source"),
                        "at": .string("2026-07-22"),
                    ]),
                ]),
            ]),
            "actions": .object([
                "accept": wrappedAction(
                    id: "\(id)-keep",
                    disposition: "accepted",
                    consequence: "keeps the card and records it as useful"
                ),
                "dismiss": wrappedAction(
                    id: "\(id)-dismiss",
                    disposition: "dismissed",
                    consequence: "closes the card and records it as not useful"
                ),
            ]),
        ]
        if let queuedCueCount {
            fields["queuedCueCount"] = .number(Double(queuedCueCount))
        }
        let surface: String
        switch kind {
        case .cue:
            surface = "conversation"
        case .body:
            surface = "body"
        case .translation:
            surface = "translation"
        }
        let packet = ViewPacket(
            id: id,
            viewType: kind.rawValue,
            text: "\(anchor). \(ask)",
            fields: fields,
            provenance: [
                "surface": .string(surface),
                "lane": .string("sovereign"),
            ],
            frontierExcluded: true
        )
        return ViewPacketCardFixture(
            id: id,
            label: "\(kind.rawValue) · \(state) · \(interruption.rawValue)",
            packet: packet
        )
    }

    private static func wrappedAction(
        id: String,
        disposition: String,
        consequence: String
    ) -> ViewPacketJSONValue {
        .object([
            "action": .object([
                "kind": .string("decision-card.answer"),
                "target": .string(id),
                "id": .string(id),
                "intent": .string("decision-card.answer"),
                "args": .object(["disposition": .string(disposition)]),
            ]),
            "consequence": .string(consequence),
        ])
    }
}

/// Fixture ViewPackets for the native chat blocks, rendered through the real
/// `.chatStream` dispatch so visual review sees exactly what production streams:
/// a warrant-tagged claim renders the native `JarvisClaimStreamBlock`, an
/// unwarranted claim falls back to the inline packet view, and `generic.chart`
/// packets render `JarvisChartStreamBlock`. Payload shapes mirror the JSON the
/// `JarvisBlocksTests` parser fixtures use (warrant string, series of label/value
/// objects, subtitle/axis metadata).
private struct JarvisBlockFixture: Identifiable {
    let id: String
    let label: String
    let packet: ViewPacket

    static let all: [JarvisBlockFixture] = [
        JarvisBlockFixture(
            id: "claim-warranted",
            label: "JarvisClaimBlock · warrant-tagged",
            packet: ViewPacket(
                id: "showcase-claim-warranted",
                viewType: "k0.claim",
                text: "morning hrv tracks your convergent-work capacity",
                fields: [
                    "claimText": .string("morning hrv tracks your convergent-work capacity"),
                    "body": .string("across 21 logged mornings, higher overnight hrv preceded longer unbroken focus blocks."),
                    "warrant": .string("holon corpus · 21 sovereign mornings · 2026-06-14 – 2026-07-05"),
                    "status": .string("promoted"),
                    "confidence": .number(0.82),
                    "why": .string("the pattern held after dropping the three lowest-sleep days"),
                    "stakes": .string("reversible · informs cadence, not a medical claim"),
                    "evidence": .array([
                        .object([
                            "label": .string("hrv 64ms → 92m unbroken focus"),
                            "at": .string("2026-07-05"),
                        ]),
                        .object([
                            "label": .string("hrv 48ms → 41m focus, 2 breaks"),
                            "at": .string("2026-07-02"),
                        ]),
                    ]),
                ],
                confidence: 0.82,
                frontierExcluded: true
            )
        ),
        JarvisBlockFixture(
            id: "claim-unwarranted",
            label: "JarvisClaimBlockUnwarranted · inline fallback",
            packet: ViewPacket(
                id: "showcase-claim-unwarranted",
                viewType: "k0.claim",
                text: "you tend to schedule deep work right after a workout",
                fields: [
                    "claimText": .string("you tend to schedule deep work right after a workout"),
                    "stakes": .string("reversible · a pattern, not yet warranted"),
                    "confidence": .number(0.4),
                ],
                confidence: 0.4,
                frontierExcluded: true
            )
        ),
        JarvisBlockFixture(
            id: "chart-stream",
            label: "JarvisChartStreamBlock · 7 points + metadata",
            packet: ViewPacket(
                id: "showcase-chart-stream",
                viewType: "generic.chart",
                text: "overnight hrv · last 7 days",
                fields: [
                    "title": .string("overnight hrv · last 7 days"),
                    "series": .array([
                        .object(["label": .string("Mon"), "value": .number(62)]),
                        .object(["label": .string("Tue"), "value": .number(58)]),
                        .object(["label": .string("Wed"), "value": .number(71)]),
                        .object(["label": .string("Thu"), "value": .number(49)]),
                        .object(["label": .string("Fri"), "value": .number(66)]),
                        .object(["label": .string("Sat"), "value": .number(74)]),
                        .object(["label": .string("Sun"), "value": .number(69)]),
                    ]),
                    "subtitle": .string("milliseconds · higher is more recovered"),
                    "xLabel": .string("day"),
                    "yLabel": .string("hrv (ms)"),
                ],
                frontierExcluded: true
            )
        ),
        JarvisBlockFixture(
            id: "chart-compact",
            label: "JarvisChartBlockCompact · 4 points, no toggle",
            packet: ViewPacket(
                id: "showcase-chart-compact",
                viewType: "generic.chart",
                text: "focus blocks · this week",
                fields: [
                    "title": .string("focus blocks · this week"),
                    "series": .array([
                        .object(["label": .string("core"), "value": .number(4)]),
                        .object(["label": .string("physical"), "value": .number(2)]),
                        .object(["label": .string("restore"), "value": .number(3)]),
                        .object(["label": .string("ops"), "value": .number(1)]),
                    ]),
                    "subtitle": .string("blocks completed"),
                    "xLabel": .string("kind"),
                ],
                frontierExcluded: true
            )
        ),
    ]
}

private struct TypedBandishFixture: Identifiable {
    let id: String
    let type: String
    let timeText: String
    let title: String
    let detail: String?
    let why: String?
    let meta: String?
    let variant: KBlockRowVariant
    let signal: KSignal
    let content: BlockContent

    var label: String {
        "\(type) · \(variant.rawValue)"
    }

    static let all: [TypedBandishFixture] = [
        TypedBandishFixture(
            id: "work",
            type: "work",
            timeText: "09:00\n1:30",
            title: "core draft",
            detail: nil,
            why: "set the edge before calls",
            meta: "85m left · core · work",
            variant: .current,
            signal: .live,
            content: KBlockTypeContent.content(
                type: "work",
                detail: object(["brainState": .string("convergent")]),
                subtasks: [
                    Subtask(id: "work-aim", text: "write the single aim"),
                    Subtask(id: "work-proof", text: "capture proof"),
                ],
                temporal: .now,
                health: nil,
                blockDurationMinutes: 90,
                elapsedMinutes: 5
            )
        ),
        TypedBandishFixture(
            id: "meal",
            type: "meal",
            timeText: "11:30\n0:30",
            title: "lunch",
            detail: nil,
            why: "restore without drift",
            meta: nil,
            variant: .upcoming,
            signal: .idle,
            content: KBlockTypeContent.content(
                type: "meal",
                detail: object([
                    "composition": .array([.string("rice"), .string("dal"), .string("greens")]),
                    "protein": .number(40),
                    "calories": .number(620),
                ]),
                subtasks: nil,
                temporal: .upcoming,
                health: nil,
                blockDurationMinutes: 30,
                elapsedMinutes: nil
            )
        ),
        TypedBandishFixture(
            id: "meditation",
            type: "meditation",
            timeText: "12:15\n0:25",
            title: "sit",
            detail: nil,
            why: "lower the noise floor",
            meta: "13m left · restore · meditation",
            variant: .current,
            signal: .live,
            content: KBlockTypeContent.content(
                type: "meditation",
                detail: object([
                    "practice": .string("breath"),
                    "phase": .number(2),
                    "method": .string("open monitoring"),
                ]),
                subtasks: nil,
                temporal: .now,
                health: nil,
                blockDurationMinutes: 25,
                elapsedMinutes: 12
            )
        ),
        TypedBandishFixture(
            id: "workout",
            type: "workout",
            timeText: "07:00\n0:45",
            title: "strength",
            detail: nil,
            why: "keep the body budget honest",
            meta: nil,
            variant: .elapsed,
            signal: .idle,
            content: KBlockTypeContent.content(
                type: "workout",
                detail: object(["plan": .array([.string("squats"), .string("carry")])]),
                subtasks: nil,
                temporal: .elapsed,
                health: HealthSummary(strain: "7", avgHeartRate: "142"),
                blockDurationMinutes: 45,
                elapsedMinutes: 45
            )
        ),
        TypedBandishFixture(
            id: "sleep",
            type: "sleep",
            timeText: "22:30\n7:12",
            title: "sleep",
            detail: nil,
            why: nil,
            meta: nil,
            variant: .elapsed,
            signal: .idle,
            content: KBlockTypeContent.content(
                type: "sleep",
                detail: object([
                    "phases": object([
                        "deep": .number(80),
                        "rem": .number(92),
                        "light": .number(240),
                        "awake": .number(20),
                    ]),
                ]),
                subtasks: nil,
                temporal: .elapsed,
                health: nil,
                blockDurationMinutes: 432,
                elapsedMinutes: 432
            )
        ),
        TypedBandishFixture(
            id: "routine",
            type: "routine",
            timeText: "18:00\n0:30",
            title: "shutdown",
            detail: nil,
            why: "close loops cleanly",
            meta: nil,
            variant: .upcoming,
            signal: .idle,
            content: KBlockTypeContent.content(
                type: "routine",
                detail: nil,
                subtasks: [
                    Subtask(id: "routine-1", text: "clear desk", done: true),
                    Subtask(id: "routine-2", text: "write tomorrow", done: true),
                    Subtask(id: "routine-3", text: "file notes"),
                    Subtask(id: "routine-4", text: "set bag"),
                    Subtask(id: "routine-5", text: "lights low"),
                ],
                temporal: .upcoming,
                health: nil,
                blockDurationMinutes: 30,
                elapsedMinutes: nil
            )
        ),
        TypedBandishFixture(
            id: "ops",
            type: "ops",
            timeText: "15:00\n0:30",
            title: "ops",
            detail: nil,
            why: "keep the runway clear",
            meta: nil,
            variant: .upcoming,
            signal: .attention,
            content: KBlockTypeContent.content(
                type: "ops",
                detail: nil,
                subtasks: [
                    Subtask(id: "ops-tax", text: "send tax form", timeSensitive: true),
                    Subtask(id: "ops-email", text: "close vendor thread"),
                ],
                temporal: .upcoming,
                health: nil,
                blockDurationMinutes: 30,
                elapsedMinutes: nil
            )
        ),
    ]

    private static func object(_ fields: [String: ViewPacketJSONValue]) -> ViewPacketJSONValue {
        .object(fields)
    }
}
#endif
