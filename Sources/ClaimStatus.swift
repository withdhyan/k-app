import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// A k0.claim packet's lifecycle status. Web analog:
// kedar/components/provenance/ClaimStatus.tsx.

enum KClaimLifecycleStatus: String, CaseIterable, Equatable {
    case proposed
    case promoted
    case challenged
    case rejected

    var signal: KSignal {
        switch self {
        case .proposed:
            return .idle
        case .promoted:
            return .live
        case .challenged:
            return .attention
        case .rejected:
            return .error
        }
    }
}

struct ClaimStatus: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "ClaimStatus",
        semanticRole: "a k0.claim packet's lifecycle status — proposed, promoted, challenged, or rejected",
        props: [
            KPrimitivePropDescriptor(name: "status", type: "KClaimLifecycleStatus", required: true),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
        ],
        variants: KClaimLifecycleStatus.allCases.map(\.rawValue),
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use inside A2UIPanel to show a k0.claim's lifecycle state next to its ConfidenceBadge",
        ],
        usageNever: [
            "never invent a fifth lifecycle state — proposed/promoted/challenged/rejected is the closed set",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .ambient, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let status: KClaimLifecycleStatus
    let state: KPrimitiveInteractionState

    init(status: KClaimLifecycleStatus, state: KPrimitiveInteractionState = .resting) {
        self.status = status
        self.state = state
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            KStatusDot(signal: status.signal, state: state, size: .small)
            KMonoCaption(status.rawValue, variant: .status, state: state)
        }
        .accessibilityElement(children: .combine)
    }
}
