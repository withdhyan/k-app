import XCTest
@testable import K

// Design system plan 003 U5 — the provenance/accountability catalog:
// A2UIPanel/ProvenanceCard/EvidenceRow/ConfidenceBadge/ClaimStatus/
// ChangeActionBar. SwiftUI view bodies aren't snapshotted here (no
// ViewInspector dependency in this project) — these tests cover the pure
// dispatch and normalization logic each component's body reads from,
// mirroring how ViewPacketTests.swift already tests
// ViewPacketRenderer.branch/visibleTextSequence rather than rendered output.
final class ProvenanceCatalogTests: XCTestCase {
    func testCatalogRegistersAllSixProvenanceComponentsInOrder() {
        let names = KPrimitiveRegistry.components.map(\.name)
        let tail = names.suffix(6)

        XCTAssertEqual(tail, ["A2UIPanel", "ProvenanceCard", "EvidenceRow", "ConfidenceBadge", "ClaimStatus", "ChangeActionBar"])
        for name in tail {
            XCTAssertTrue(names.filter { $0 == name }.count == 1, "\(name) must be registered exactly once")
        }
    }

    func testEveryProvenanceComponentDeclaresAnInterruptionClass() {
        let provenanceNames: Set<String> = ["A2UIPanel", "ProvenanceCard", "EvidenceRow", "ConfidenceBadge", "ClaimStatus", "ChangeActionBar"]
        for descriptor in KPrimitiveRegistry.components where provenanceNames.contains(descriptor.name) {
            XCTAssertTrue([.ambient, .peripheral, .focal].contains(descriptor.calmTech.interruptionClass), descriptor.name)
            XCTAssertGreaterThan(descriptor.calmTech.maxSimultaneousCues ?? 0, 0, descriptor.name)
        }
    }

    // The five differentiated k0.* branches (k0.decision excluded — it is
    // not one of the 6 provenance-catalog viewTypes) must resolve to
    // A2UIPanelViewType, and k0.decision must not.
    func testA2UIPanelViewTypeMatchesExactlyTheSixProvenanceViewTypes() {
        let provenance = ["k0.provenance", "k0.claim", "k0.change", "k0.eval_score", "k0.evolve_report", "loop.evidence"]
        for viewType in provenance {
            XCTAssertNotNil(A2UIPanelViewType(rawValue: viewType), viewType)
        }
        XCTAssertNil(A2UIPanelViewType(rawValue: "k0.decision"))
        XCTAssertNil(A2UIPanelViewType(rawValue: "preview.web"))
        XCTAssertNil(A2UIPanelViewType(rawValue: "build.status"))
    }

    func testFixturePacketPerViewTypeDispatchesAwayFromTheGenericFallback() {
        let cases: [(String, ViewPacketRenderBranch)] = [
            ("k0.provenance", .k0Provenance),
            ("k0.claim", .k0Claim),
            ("k0.change", .k0Change),
            ("k0.eval_score", .k0EvalScore),
            ("k0.evolve_report", .k0EvolveReport),
        ]
        for (viewType, expectedBranch) in cases {
            let packet = ViewPacket(id: String(repeating: "a", count: 24), viewType: viewType, frontierExcluded: false)
            XCTAssertEqual(ViewPacketRenderer.branch(for: packet), expectedBranch, viewType)
            XCTAssertNotEqual(ViewPacketRenderer.branch(for: packet), .genericText, viewType)
        }
    }

    func testConfidenceLevelThresholdsMatchTheWebComponent() {
        // Mirrors kedar/components/provenance/ConfidenceBadge.tsx's confidenceTone thresholds.
        XCTAssertEqual(KConfidenceLevel.forConfidence(0.2), .low)
        XCTAssertEqual(KConfidenceLevel.forConfidence(0.6), .medium)
        XCTAssertEqual(KConfidenceLevel.forConfidence(0.9), .high)
        XCTAssertEqual(KConfidenceLevel.forConfidence(nil), .unknown)
        XCTAssertEqual(KConfidenceLevel.forConfidence(0.8), .high, "boundary is inclusive")
        XCTAssertEqual(KConfidenceLevel.forConfidence(0.4), .medium, "boundary is inclusive")
    }

    func testConfidenceLevelSignalsResolveThroughKSignalOnly() {
        XCTAssertEqual(KConfidenceLevel.low.signal, .error)
        XCTAssertEqual(KConfidenceLevel.medium.signal, .attention)
        XCTAssertEqual(KConfidenceLevel.high.signal, .live)
        XCTAssertEqual(KConfidenceLevel.calibrated.signal, .live)
        XCTAssertEqual(KConfidenceLevel.unknown.signal, .idle)
    }

    func testClaimLifecycleStatusSignals() {
        XCTAssertEqual(KClaimLifecycleStatus.proposed.signal, .idle)
        XCTAssertEqual(KClaimLifecycleStatus.promoted.signal, .live)
        XCTAssertEqual(KClaimLifecycleStatus.challenged.signal, .attention)
        XCTAssertEqual(KClaimLifecycleStatus.rejected.signal, .error)
    }

    func testEvidenceEntryFieldsNormalizesBareStringRefs() {
        let value = ViewPacketJSONValue.array([.string("exp_123"), .string("exp_456")])
        let entries = KEvidenceEntryFields.entries(from: value)

        XCTAssertEqual(entries.map(\.id), ["exp_123", "exp_456"])
        XCTAssertEqual(entries.map(\.label), ["exp_123", "exp_456"])
        XCTAssertTrue(entries.allSatisfy { $0.meta == nil })
    }

    func testEvidenceEntryFieldsNormalizesExposureObjects() {
        let value = ViewPacketJSONValue.array([
            .object([
                "id": .string("exp_1"),
                "statement": .string("hrv dropped after 9pm coffee"),
                "surface": .string("body"),
                "eventAt": .string("2026-07-11T21:00:00Z"),
            ]),
        ])
        let entries = KEvidenceEntryFields.entries(from: value)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "exp_1")
        XCTAssertEqual(entries[0].label, "hrv dropped after 9pm coffee")
        XCTAssertEqual(entries[0].meta, "body · 2026-07-11T21:00:00Z")
    }

    func testEvidenceEntryFieldsReturnsEmptyForMissingOrNonArrayFields() {
        XCTAssertEqual(KEvidenceEntryFields.entries(from: nil), [])
        XCTAssertEqual(KEvidenceEntryFields.entries(from: .string("not an array")), [])
    }

    func testA2UIPanelFieldsStringifyHandlesNilNullAndValues() {
        XCTAssertNil(A2UIPanelFields.stringify(nil))
        XCTAssertNil(A2UIPanelFields.stringify(.null))
        XCTAssertEqual(A2UIPanelFields.stringify(.string("lowered")), "lowered")
        XCTAssertEqual(A2UIPanelFields.stringify(.number(3)), "3")
    }

    func testViewPacketJSONValueDoubleValueReadsNumbers() {
        XCTAssertEqual(ViewPacketJSONValue.number(0.82).doubleValue, 0.82)
        XCTAssertNil(ViewPacketJSONValue.string("0.82").doubleValue)
    }
}
