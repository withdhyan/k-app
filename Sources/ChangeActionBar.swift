import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// A k0.change packet's before/after diff plus undo/challenge affordances
// (PRD's ChangeLedger + ChallengeAction). Composes KActRow — no raw Button.
// Web analog: kedar/components/provenance/ChangeActionBar.tsx. Buttons are
// display-only in this unit — action-invoke wiring is not named in this
// plan's Implementation Units and is deferred, matching the web component's
// same deferral.

struct ChangeActionBar: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "ChangeActionBar",
        semanticRole: "a k0.change packet's before/after diff plus undo and challenge affordances",
        props: [
            KPrimitivePropDescriptor(name: "beforeText", type: "String?", required: false),
            KPrimitivePropDescriptor(name: "afterText", type: "String?", required: false),
            KPrimitivePropDescriptor(name: "actor", type: "String?", required: false),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
            KPrimitivePropDescriptor(name: "onUndo", type: "() -> Void", required: true),
            KPrimitivePropDescriptor(name: "onChallenge", type: "() -> Void", required: true),
        ],
        variants: ["change"],
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use inside A2UIPanel for k0.change packets",
        ],
        usageNever: [
            "never wire undo/challenge to a destructive action without a confirm step upstream",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .peripheral, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let beforeText: String?
    let afterText: String?
    let actor: String?
    let state: KPrimitiveInteractionState
    let onUndo: () -> Void
    let onChallenge: () -> Void

    init(
        beforeText: String?,
        afterText: String?,
        actor: String? = nil,
        state: KPrimitiveInteractionState = .resting,
        onUndo: @escaping () -> Void = {},
        onChallenge: @escaping () -> Void = {}
    ) {
        self.beforeText = beforeText
        self.afterText = afterText
        self.actor = actor
        self.state = state
        self.onUndo = onUndo
        self.onChallenge = onChallenge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(diffText)
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(state.quietTextOpacity))
                    .textSelection(.enabled)
                if let actor {
                    KMonoCaption(actor, variant: .metadata, state: state)
                }
            }
            KActRow(
                actions: [
                    KActItem(id: "undo", isEnabled: !state.disablesAction),
                    KActItem(id: "challenge", isEnabled: !state.disablesAction),
                ],
                variant: .cadence,
                state: state,
                onSelect: { item in
                    if item.id == "undo" {
                        onUndo()
                    } else if item.id == "challenge" {
                        onChallenge()
                    }
                }
            )
        }
    }

    private var diffText: String {
        "\(beforeText ?? "unset") → \(afterText ?? "unset")"
    }
}
