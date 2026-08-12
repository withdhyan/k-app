import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// One observed/proposed/changed provenance snapshot (PRD's ProvenanceCard).
// Composes EvidenceRow for its sourceRefs. Web analog:
// kedar/components/provenance/ProvenanceCard.tsx.

struct ProvenanceCard: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "ProvenanceCard",
        semanticRole: "one observed/proposed/changed provenance snapshot — subject, as-of time, and source evidence",
        props: [
            KPrimitivePropDescriptor(name: "subject", type: "String?", required: false),
            KPrimitivePropDescriptor(name: "asOf", type: "String?", required: false),
            KPrimitivePropDescriptor(name: "sourceRefs", type: "[KEvidenceEntry]", required: false),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
        ],
        variants: ["provenance"],
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use inside A2UIPanel for k0.provenance packets",
        ],
        usageNever: [
            "never render provenance as a bespoke route dashboard — always through A2UIPanel",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .peripheral, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let subject: String?
    let asOf: String?
    let sourceRefs: [KEvidenceEntry]
    let state: KPrimitiveInteractionState

    init(
        subject: String? = nil,
        asOf: String? = nil,
        sourceRefs: [KEvidenceEntry] = [],
        state: KPrimitiveInteractionState = .resting
    ) {
        self.subject = subject
        self.asOf = asOf
        self.sourceRefs = sourceRefs
        self.state = state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let subject {
                Text(subject)
                    .kFont(.blockDefaultTitle)
                    .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    .textSelection(.enabled)
            }
            if let asOf {
                KMonoCaption("as of \(asOf)", variant: .metadata, state: state)
            }
            ForEach(sourceRefs) { entry in
                EvidenceRow(entry: entry, state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
