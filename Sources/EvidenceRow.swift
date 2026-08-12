import SwiftUI

// K provenance/accountability catalog (Design System Phase 2, plan 003 U5).
// Compact linked evidence rows (PRD's EvidenceList) — generalizes the
// existing loop.evidence render path (RenderViewPacket.swift's evidenceView/
// KEvidenceBlock) into a reusable per-item row rather than one big joined
// text block. Web analog: kedar/components/provenance/EvidenceRow.tsx.

struct KEvidenceEntry: Identifiable, Equatable {
    let id: String
    let label: String
    let meta: String?
}

/// Normalizes loop.evidence exposures/citations or bare sourceRef ids
/// (k0.provenance) into KEvidenceEntry rows.
enum KEvidenceEntryFields {
    static func entries(from value: ViewPacketJSONValue?) -> [KEvidenceEntry] {
        guard let items = value?.arrayValue else { return [] }
        return items.enumerated().compactMap { index, item in
            if let text = item.stringValue, !text.isEmpty {
                return KEvidenceEntry(id: text, label: text, meta: nil)
            }
            guard let object = item.objectValue else { return nil }
            let id = object["id"]?.stringValue ?? object["sourceId"]?.stringValue ?? "evidence-\(index)"
            let label = object["statement"]?.stringValue
                ?? object["id"]?.stringValue
                ?? object["sourceId"]?.stringValue
                ?? "evidence \(index + 1)"
            let metaParts = [object["surface"]?.stringValue, object["eventAt"]?.stringValue].compactMap { $0 }
            return KEvidenceEntry(id: id, label: label, meta: metaParts.isEmpty ? nil : metaParts.joined(separator: " · "))
        }
    }
}

struct EvidenceRow: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "EvidenceRow",
        semanticRole: "one compact linked evidence row — statement plus optional surface/timestamp meta",
        props: [
            KPrimitivePropDescriptor(name: "entry", type: "KEvidenceEntry", required: true),
            KPrimitivePropDescriptor(name: "state", type: "KPrimitiveInteractionState", required: false),
        ],
        variants: ["evidence-row"],
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use for loop.evidence exposures and k0.provenance sourceRefs inside A2UIPanel",
            "use to generalize the existing loop.evidence render path — never duplicate it",
        ],
        usageNever: [
            "never use for the full evidence/diff/log block — that stays KEvidenceBlock",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .peripheral, maxSimultaneousCues: 1),
        usesTokenOnlyStyling: true
    )

    let entry: KEvidenceEntry
    let state: KPrimitiveInteractionState

    init(entry: KEvidenceEntry, state: KPrimitiveInteractionState = .resting) {
        self.entry = entry
        self.state = state
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(entry.label)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(state.quietTextOpacity))
                .textSelection(.enabled)
            if let meta = entry.meta {
                KMonoCaption(meta, variant: .metadata, state: state)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
