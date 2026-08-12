import XCTest
@testable import K

final class JarvisBlocksTests: XCTestCase {
    func testClaimBlockDetectsWarrantFieldTag() {
        let packet = ViewPacket(
            id: "claim-warrant-field",
            viewType: "k0.claim",
            text: "foundational claim",
            fields: ["warrant": .string("source citation")],
            frontierExcluded: false
        )
        let claim = JarvisClaimBlock(packet: packet)

        XCTAssertTrue(claim.isWarrantTagged)
        XCTAssertEqual(claim.title, "foundational claim")
        XCTAssertEqual(claim.warrantText, "source citation")
        XCTAssertEqual(claim.status, .proposed)
        XCTAssertEqual(claim.confidenceLevel, .unknown)
    }

    func testClaimBlockDetectsWarrantTagFromTagsList() {
        let packet = ViewPacket(
            id: "claim-warrant-tags",
            viewType: "k0.claim",
            text: "tagged claim",
            fields: ["tags": .array([.string("analysis"), .string("warrant")])],
            frontierExcluded: false
        )
        let claim = JarvisClaimBlock(packet: packet)

        XCTAssertTrue(claim.isWarrantTagged)
        XCTAssertEqual(claim.title, "tagged claim")
        XCTAssertEqual(claim.collapsedLines, ["warrant tagged"])
    }

    func testClaimBlockDoesNotDetectWarrantTagWhenAbsent() {
        let packet = ViewPacket(
            id: "claim-no-warrant",
            viewType: "k0.claim",
            text: "ordinary claim",
            fields: ["stakes": .string("reversible")],
            frontierExcluded: false
        )
        let claim = JarvisClaimBlock(packet: packet)

        XCTAssertFalse(claim.isWarrantTagged)
        XCTAssertEqual(claim.collapsedLines, ["reversible"])
        XCTAssertTrue(claim.hasExpandableContent)
    }

    func testChartBlockParsesSeriesPointsAndMetadata() {
        let packet = ViewPacket(
            id: "chart-series",
            viewType: "generic.chart",
            text: "performance trend",
            fields: [
                "title": .string("weekly trend"),
                "series": .array([
                    .object([
                        "label": .string("Mon"),
                        "value": .number(4),
                    ]),
                    .object([
                        "name": .string("Tue"),
                        "y": .number(-2),
                    ]),
                ]),
                "subtitle": .string("core metric"),
                "xLabel": .string("day"),
            ],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertEqual(chart.title, "weekly trend")
        XCTAssertEqual(chart.points.map(\.label), ["Mon", "Tue"])
        XCTAssertEqual(chart.points.map { $0.value }, [4.0, -2.0])
        XCTAssertEqual(chart.points.map(\.valueText), ["4", "-2"])
        XCTAssertEqual(chart.points.count, 2)
        XCTAssertEqual(chart.maxValue, 4.0)
        XCTAssertFalse(chart.hasToggleControl)
        XCTAssertEqual(chart.metadataLines, ["core metric", "day"])
    }

    func testChartBlockFallsBackTitleToDisplayText() {
        let packet = ViewPacket(
            id: "chart-fallback",
            viewType: "generic.chart",
            text: "fallback chart title",
            fields: ["series": .array([.number(1), .number(2), .number(3)])],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertEqual(chart.title, "fallback chart title")
        XCTAssertEqual(chart.points.count, 3)
        XCTAssertEqual(chart.points.map(\.label), ["point 1", "point 2", "point 3"])
    }

    // MARK: - Stable identity + parse-once

    func testChartPointIdentityIsStableAcrossReparse() {
        let packet = ViewPacket(
            id: "chart-stable-id",
            viewType: "generic.chart",
            text: "trend",
            fields: [
                "series": .array([
                    .object(["label": .string("Mon"), "value": .number(4)]),
                    .object(["label": .string("Tue"), "value": .number(6)]),
                    .object(["label": .string("Wed"), "value": .number(2)]),
                ]),
            ],
            frontierExcluded: false
        )

        let first = JarvisChartBlock(packet: packet)
        let second = JarvisChartBlock(packet: packet)

        // Parsing the same packet twice yields identical point identities — the
        // precondition for ForEach diffing rows instead of rebuilding them mid-stream.
        XCTAssertEqual(first.points.map(\.id), second.points.map(\.id))
        XCTAssertEqual(first.points.map(\.id), ["0-Mon", "1-Tue", "2-Wed"])
        // Identities are unique within a chart.
        XCTAssertEqual(Set(first.points.map(\.id)).count, first.points.count)
        // No random id: identical inputs produce equal points across parses.
        XCTAssertEqual(first.points, second.points)
    }

    func testChartPointIdentityDisambiguatesDuplicateLabels() {
        let packet = ViewPacket(
            id: "chart-dup-labels",
            viewType: "generic.chart",
            text: "dupes",
            fields: [
                "series": .array([
                    .object(["label": .string("Mon"), "value": .number(1)]),
                    .object(["label": .string("Mon"), "value": .number(2)]),
                ]),
            ],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertEqual(chart.points.map(\.label), ["Mon", "Mon"])
        // Same label, distinct identity — the index keeps duplicate rows addressable.
        XCTAssertEqual(chart.points.map(\.id), ["0-Mon", "1-Mon"])
        XCTAssertNotEqual(chart.points[0].id, chart.points[1].id)
    }

    // MARK: - Stream dispatch

    func testStreamDispatchRoutesGenericChartToNativeChartBlock() {
        let packet = ViewPacket(
            id: "chart-dispatch",
            viewType: "generic.chart",
            text: "trend",
            fields: ["series": .array([.number(1), .number(2)])],
            frontierExcluded: false
        )
        // generic.chart lands on the branch streamContent maps to JarvisChartStreamBlock.
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericChart)
    }

    func testStreamDispatchRendersClaimNativelyOnlyWhenWarrantTagged() {
        let warranted = ViewPacket(
            id: "claim-warranted",
            viewType: "k0.claim",
            text: "warranted claim",
            fields: ["warrant": .string("source citation")],
            frontierExcluded: false
        )
        let unwarranted = ViewPacket(
            id: "claim-unwarranted",
            viewType: "k0.claim",
            text: "plain claim",
            fields: ["stakes": .string("reversible")],
            frontierExcluded: false
        )

        XCTAssertEqual(ViewPacketRenderer.branch(for: warranted), .k0Claim)
        XCTAssertEqual(ViewPacketRenderer.branch(for: unwarranted), .k0Claim)
        // Native JarvisClaimStreamBlock only for the warrant-tagged claim; the
        // unwarranted one falls back to packetInlineView.
        XCTAssertTrue(ViewPacketRenderer.rendersNativeClaimBlock(for: warranted))
        XCTAssertFalse(ViewPacketRenderer.rendersNativeClaimBlock(for: unwarranted))
        // A non-claim packet never takes the native claim path.
        let chart = ViewPacket(id: "not-a-claim", viewType: "generic.chart", text: "x", frontierExcluded: false)
        XCTAssertFalse(ViewPacketRenderer.rendersNativeClaimBlock(for: chart))
    }

    // MARK: - Malformed payloads

    func testChartBlockHandlesNullSeries() {
        let packet = ViewPacket(
            id: "chart-null-series",
            viewType: "generic.chart",
            text: "no data yet",
            fields: ["title": .string("empty chart"), "series": .null],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertTrue(chart.points.isEmpty)
        XCTAssertEqual(chart.title, "empty chart")
        XCTAssertEqual(chart.fallbackText, "no data yet")
        XCTAssertEqual(chart.maxValue, 1)
        XCTAssertFalse(chart.hasToggleControl)
    }

    func testChartBlockHandlesEmptySeries() {
        let packet = ViewPacket(
            id: "chart-empty-series",
            viewType: "generic.chart",
            text: "empty",
            fields: ["series": .array([])],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertTrue(chart.points.isEmpty)
        XCTAssertFalse(chart.hasMorePoints)
    }

    func testChartBlockClampsMismatchedLabelsAndValues() {
        let packet = ViewPacket(
            id: "chart-mismatch",
            viewType: "generic.chart",
            text: "mismatch",
            fields: [
                "series": .object([
                    "labels": .array([.string("a"), .string("b"), .string("c")]),
                    "values": .array([.number(1), .number(2)]),
                ]),
            ],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        // min(labels, values) points, no out-of-bounds read on the longer array.
        XCTAssertEqual(chart.points.map(\.label), ["a", "b"])
        XCTAssertEqual(chart.points.map { $0.value }, [1.0, 2.0])
        XCTAssertEqual(chart.points.map(\.id), ["0-a", "1-b"])
    }

    func testChartBlockHandlesPointsMissingValue() {
        let packet = ViewPacket(
            id: "chart-missing-value",
            viewType: "generic.chart",
            text: "sparse",
            fields: [
                "series": .array([
                    .object(["label": .string("A"), "value": .number(5)]),
                    .object(["label": .string("B")]),
                ]),
            ],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertEqual(chart.points.count, 2)
        XCTAssertEqual(chart.points[0].value, 5.0)
        XCTAssertNil(chart.points[1].value)
        // A point with no numeric value falls back to its label for the value text.
        XCTAssertEqual(chart.points[1].valueText, "B")
        // maxValue ignores the missing point.
        XCTAssertEqual(chart.maxValue, 5.0)
    }

    func testChartBlockParsesNestedChartField() {
        let packet = ViewPacket(
            id: "chart-nested",
            viewType: "generic.chart",
            text: "nested",
            fields: [
                "chart": .object([
                    "series": .array([
                        .object(["label": .string("Q1"), "value": .number(10)]),
                        .object(["label": .string("Q2"), "value": .number(20)]),
                    ]),
                    "subtitle": .string("quarterly"),
                ]),
            ],
            frontierExcluded: false
        )
        let chart = JarvisChartBlock(packet: packet)

        XCTAssertEqual(chart.points.map(\.label), ["Q1", "Q2"])
        XCTAssertEqual(chart.points.map { $0.value }, [10.0, 20.0])
        XCTAssertEqual(chart.metadataLines, ["quarterly"])
    }

    func testClaimBlockFailsClosedOnWrongTypedWarrant() {
        // A warrant must be a genuine non-empty string. bool/number/object payloads
        // are not warrants: the claim is left untagged and falls back to the inline
        // packet view rather than rendering the native warrant block.
        let malformed: [ViewPacketJSONValue] = [
            .bool(true),
            .number(3),
            .object(["source": .string("doi")]),
            .array([.string("doi")]),
        ]
        for warrant in malformed {
            let packet = ViewPacket(
                id: "claim-wrong-warrant",
                viewType: "k0.claim",
                text: "claim",
                fields: ["warrant": warrant],
                frontierExcluded: false
            )
            let claim = JarvisClaimBlock(packet: packet)
            XCTAssertFalse(claim.isWarrantTagged, "warrant \(warrant) must not tag the claim")
            XCTAssertNil(claim.warrantText)
            XCTAssertFalse(ViewPacketRenderer.rendersNativeClaimBlock(for: packet))
        }
    }

    func testClaimBlockRequiresNonEmptyStringWarrant() {
        // Only a non-empty string warrant renders the native claim block; the string
        // is trimmed, and a whitespace-only warrant fails closed to the inline view.
        let valid = ViewPacket(
            id: "claim-valid-warrant",
            viewType: "k0.claim",
            text: "claim",
            fields: ["warrant": .string("  cited source  ")],
            frontierExcluded: false
        )
        let validClaim = JarvisClaimBlock(packet: valid)
        XCTAssertTrue(validClaim.isWarrantTagged)
        XCTAssertEqual(validClaim.warrantText, "cited source")
        XCTAssertTrue(ViewPacketRenderer.rendersNativeClaimBlock(for: valid))

        let empty = ViewPacket(
            id: "claim-empty-warrant",
            viewType: "k0.claim",
            text: "claim",
            fields: ["warrant": .string("   ")],
            frontierExcluded: false
        )
        let emptyClaim = JarvisClaimBlock(packet: empty)
        XCTAssertFalse(emptyClaim.isWarrantTagged)
        XCTAssertNil(emptyClaim.warrantText)
        XCTAssertFalse(ViewPacketRenderer.rendersNativeClaimBlock(for: empty))
    }

    func testClaimBlockHandlesNonArrayTags() {
        // A single-string tag is coerced to a one-element list; a numeric tags
        // payload yields no warrant tag rather than crashing.
        let stringTag = JarvisClaimBlock(packet: ViewPacket(
            id: "claim-string-tag",
            viewType: "k0.claim",
            text: "claim",
            fields: ["tags": .string("warrant")],
            frontierExcluded: false
        ))
        XCTAssertTrue(stringTag.isWarrantTagged)

        let numberTag = JarvisClaimBlock(packet: ViewPacket(
            id: "claim-number-tag",
            viewType: "k0.claim",
            text: "claim",
            fields: ["tags": .number(7)],
            frontierExcluded: false
        ))
        XCTAssertFalse(numberTag.isWarrantTagged)

        let unrelatedStringTag = JarvisClaimBlock(packet: ViewPacket(
            id: "claim-unrelated-tag",
            viewType: "k0.claim",
            text: "claim",
            fields: ["tags": .string("analysis")],
            frontierExcluded: false
        ))
        XCTAssertFalse(unrelatedStringTag.isWarrantTagged)
    }
}
