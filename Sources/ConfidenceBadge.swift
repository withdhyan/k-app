import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// Maps a 0-1 confidence value onto KSignal — never a new hue. Web analog:
// kedar/components/provenance/ConfidenceBadge.tsx (same thresholds:
// >= 0.8 high, >= 0.4 medium, else low).

enum KConfidenceLevel: String, CaseIterable, Equatable {
    case low
    case medium
    case high
    case calibrated
    case unknown

    static func forConfidence(_ confidence: Double?) -> KConfidenceLevel {
        guard let confidence else { return .unknown }
        if confidence >= 0.8 { return .high }
        if confidence >= 0.4 { return .medium }
        return .low
    }

    var signal: KSignal {
        switch self {
        case .low:
            return .error
        case .medium:
            return .attention
        case .high, .calibrated:
            return .live
        case .unknown:
            return .idle
        }
    }
}

struct ConfidenceBadge: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "ConfidenceBadge",
        semanticRole: "semantic confidence level badge for k0.claim/k0.eval_score — maps confidence onto KSignal only",
        props: [
            KPrimitivePropDescriptor(name: "level", type: "KConfidenceLevel", required: true),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
        ],
        variants: KConfidenceLevel.allCases.map(\.rawValue),
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use for k0.claim/k0.eval_score confidence display inside A2UIPanel",
        ],
        usageNever: [
            "never introduce a new hue for confidence — resolve through KSignal only",
            "never render a bare numeric percentage without a level label",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .ambient, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let level: KConfidenceLevel
    let state: KPrimitiveInteractionState

    init(level: KConfidenceLevel, state: KPrimitiveInteractionState = .resting) {
        self.level = level
        self.state = state
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            KStatusDot(signal: level.signal, state: state, size: .small)
            KMonoCaption("confidence: \(level.rawValue)", variant: .metadata, state: state)
        }
        .accessibilityElement(children: .combine)
    }
}
