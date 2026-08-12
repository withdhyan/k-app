import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// The one shared composition all 6 provenance-catalog viewTypes render
// through (KTD-5) — k0.provenance/claim/change/eval_score/evolve_report +
// loop.evidence. Web analog: kedar/components/provenance/A2UIPanel.tsx.
//
// RenderViewPacket.swift's k0.decision branch stays on the existing k0View
// (k0.decision is not one of the 6 provenance-catalog types, matching the
// web renderer's own scope). The existing loop.evidence branch keeps its
// DecisionBrief-preview precedence (mind/think output group[1] carries a
// decision brief in fields) — A2UIPanel only takes over loop.evidence
// packets that carry plain evidence, not a decision brief, so no existing
// tested behavior regresses.

enum A2UIPanelViewType: String, CaseIterable, Equatable {
    case k0Provenance = "k0.provenance"
    case k0Claim = "k0.claim"
    case k0Change = "k0.change"
    case k0EvalScore = "k0.eval_score"
    case k0EvolveReport = "k0.evolve_report"
    case loopEvidence = "loop.evidence"
}

/// Field readers shared by A2UIPanel's per-viewType branches.
enum A2UIPanelFields {
    static func stringify(_ value: ViewPacketJSONValue?) -> String? {
        guard let value else { return nil }
        if case .null = value { return nil }
        let text = value.description
        return text.isEmpty ? nil : text
    }
}

struct A2UIPanel: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "A2UIPanel",
        semanticRole: "the one shared composition every provenance-catalog viewType renders through",
        props: [
            KPrimitivePropDescriptor(name: "packet", type: "ViewPacket", required: true),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
            KPrimitivePropDescriptor(name: "onUndo", type: "() -> Void", required: false),
            KPrimitivePropDescriptor(name: "onChallenge", type: "() -> Void", required: false),
        ],
        variants: ["provenance-panel"],
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use for every k0.provenance/claim/change/eval_score/evolve_report and loop.evidence packet — one shared wrapper, never five bespoke views",
        ],
        usageNever: [
            "never bypass A2UIPanel to render a provenance viewType directly",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .peripheral, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let packet: ViewPacket
    let state: KPrimitiveInteractionState
    let onUndo: () -> Void
    let onChallenge: () -> Void

    init(
        packet: ViewPacket,
        state: KPrimitiveInteractionState = .resting,
        onUndo: @escaping () -> Void = {},
        onChallenge: @escaping () -> Void = {}
    ) {
        self.packet = packet
        self.state = state
        self.onUndo = onUndo
        self.onChallenge = onChallenge
    }

    var body: some View {
        KGlassCard(state: state) {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                KMonoCaption(packet.viewType, variant: .metadata, state: state)
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch A2UIPanelViewType(rawValue: packet.viewType) {
        case .k0Provenance:
            ProvenanceCard(
                subject: packet.fields?["subject"]?.stringValue,
                asOf: packet.fields?["asOf"]?.stringValue,
                sourceRefs: KEvidenceEntryFields.entries(from: packet.fields?["sourceRefs"]),
                state: state
            )
        case .k0Claim:
            claimContent
        case .k0Change:
            ChangeActionBar(
                beforeText: A2UIPanelFields.stringify(packet.fields?["before"]),
                afterText: A2UIPanelFields.stringify(packet.fields?["after"]),
                actor: packet.fields?["actor"]?.stringValue,
                state: state,
                onUndo: onUndo,
                onChallenge: onChallenge
            )
        case .k0EvalScore:
            evalScoreContent
        case .k0EvolveReport:
            KMonoCaption(evolveReportSummary, variant: .metadata, state: state)
        case .loopEvidence:
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                let entries = KEvidenceEntryFields.entries(from: packet.fields?["exposures"] ?? packet.fields?["citations"])
                ForEach(entries) { entry in
                    EvidenceRow(entry: entry, state: state)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private var claimContent: some View {
        let text = packet.displayText.isEmpty ? (packet.fields?["claimText"]?.stringValue ?? "") : packet.displayText
        return VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if !text.isEmpty {
                Text(text)
                    .kFont(.blockDefaultTitle)
                    .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    .textSelection(.enabled)
            }
            ClaimStatus(
                status: KClaimLifecycleStatus(rawValue: packet.fields?["status"]?.stringValue ?? "") ?? .proposed,
                state: state
            )
            ConfidenceBadge(
                level: KConfidenceLevel.forConfidence(packet.fields?["confidence"]?.doubleValue ?? packet.confidence),
                state: state
            )
        }
    }

    private var evalScoreContent: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let metric = packet.fields?["metric"]?.stringValue {
                KMonoCaption(metric, variant: .metadata, state: state)
            }
            ConfidenceBadge(
                level: KConfidenceLevel.forConfidence(packet.fields?["score"]?.doubleValue ?? packet.score),
                state: state
            )
            if let rationale = packet.fields?["rationale"]?.stringValue {
                Text(rationale)
                    .kFont(.content)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .textSelection(.enabled)
            }
        }
    }

    private var evolveReportSummary: String {
        let start = packet.fields?["periodStart"]?.stringValue ?? "?"
        let end = packet.fields?["periodEnd"]?.stringValue ?? "?"
        var text = "\(start) · \(end)"
        if let count = packet.fields?["changeCount"]?.doubleValue {
            text += " · \(Int(count)) changes"
        }
        return text
    }
}
