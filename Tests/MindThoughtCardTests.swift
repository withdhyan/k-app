import XCTest
@testable import K

final class MindThoughtCardTests: XCTestCase {
    func testTypographyKeepsEntityClaimAndReferenceHierarchy() {
        XCTAssertEqual(MindThoughtTypography.metric(for: .entity).pointSize, 16)
        XCTAssertEqual(MindThoughtTypography.metric(for: .claim).pointSize, 14)
        XCTAssertEqual(MindThoughtTypography.metric(for: .reference).pointSize, 11)
        XCTAssertEqual(MindThoughtTypography.snapshot.map(\.role), [.entity, .claim, .reference])
    }

    func testPresentationAssignsEachCurrentFactToOneLine() throws {
        let output = try makeOutput(
            label: "efficiency jhana",
            statement: "efficiency jhana — 3 pieces of evidence — decide what changes next.",
            fields: [
                "observation": .string("the measurement question is resolved — one reversible step remains."),
                "evidenceSummary": .object([
                    "conversationCount": .number(3),
                    "latestAt": .string("2026-07-19T08:00:00Z"),
                ]),
            ],
            previews: [
                DecisionEvidencePreview(
                    label: "measurement settled · chat",
                    at: "2026-07-19T08:00:00Z"
                ),
            ]
        )

        let presentation = MindThoughtPresentation(
            output: output,
            now: try date("2026-07-19T12:00:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(presentation.entity, "efficiency jhana")
        XCTAssertEqual(presentation.claim, "the measurement question is resolved — one reversible step remains.")
        XCTAssertEqual(presentation.evidenceLine, "3 conversations · latest today")
        XCTAssertEqual(presentation.evidenceReferences, ["measurement settled · chat · today"])
        XCTAssertTrue(presentation.canDrillIntoEvidence)
        XCTAssertFalse(presentation.accessibilityLabel.contains("decide what changes next"))
    }

    func testBoundedEvidenceCountDoesNotPretendAllEvidenceIsLoaded() throws {
        let output = try makeOutput(
            fields: [
                "evidenceCount": .object([
                    "shown": .number(8),
                    "total": .number(83),
                ]),
            ],
            previews: [
                DecisionEvidencePreview(label: "founder correction · chat", at: "2026-07-18")
            ]
        )

        XCTAssertEqual(
            MindThoughtEvidenceLineFormatter.line(
                for: output,
                now: try date("2026-07-19T12:00:00Z"),
                calendar: utcCalendar
            ),
            "8 of 83 pieces of evidence · latest yesterday"
        )
    }

    func testRawEvidenceIdentifiersRenderAsCountWithoutDeadDrillIn() throws {
        let output = try makeOutput(evidence: ["exp_alpha", "atom_beta"])
        let presentation = MindThoughtPresentation(output: output)

        XCTAssertEqual(presentation.evidenceLine, "2 pieces of evidence")
        XCTAssertEqual(presentation.evidenceReferences, [])
        XCTAssertFalse(presentation.canDrillIntoEvidence)
    }

    func testLegacyStructuredStatementExtractsOnlyItsObservation() throws {
        let output = try makeOutput(
            label: "native Mind verdict surface",
            statement: "state: native Mind verdict surface. context: 2 source atoms. observation: staged for founder decision. consider: decide whether the iPad is the right lane.",
            evidence: ["atom-a", "atom-b"]
        )

        let presentation = MindThoughtPresentation(output: output)

        XCTAssertEqual(presentation.entity, "native Mind verdict surface")
        XCTAssertEqual(presentation.claim, "staged for founder decision")
        XCTAssertEqual(presentation.evidenceLine, "2 pieces of evidence")
        XCTAssertFalse(presentation.accessibilityLabel.contains("2 source atoms"))
    }

    func testAbsentFutureContractFieldsStaySilent() throws {
        let output = try makeOutput(fields: [
            "useTrail": .string("in use · cadence shaping"),
            "ledger": .string("three thoughts survived the pass"),
            "judgedLean": .string("act-on"),
            "resolvedThreadReceipt": .string("folded into the trail"),
        ])
        let presentation = MindThoughtPresentation(output: output)

        XCTAssertEqual(presentation.entity, "a live thought")
        XCTAssertEqual(presentation.claim, "a claim worth holding")
        XCTAssertNil(presentation.evidenceLine)
        XCTAssertEqual(presentation.evidenceReferences, [])
        XCTAssertEqual(presentation.accessibilityLabel, "a live thought. a claim worth holding")
        XCTAssertEqual(output.artifactSignal, .none)
        XCTAssertEqual(output.useTrail, [])
        XCTAssertNil(output.commentThread)
        XCTAssertEqual(output.verdictConsequences, [:])
    }

    func testMindV18DepthProjectionKeepsSignalsTrailConsequencesAndThreadTyped() throws {
        let fresh = try XCTUnwrap(MindDemo.response.outputs.first { $0.outputId == MindDemo.freshOutputID })
        let acted = try XCTUnwrap(MindDemo.response.outputs.first { $0.outputId == MindDemo.actedOutputID })

        XCTAssertEqual(fresh.artifactSignal, .fresh)
        XCTAssertEqual(fresh.useTrail.map(\.text), ["staged for today's deep block"])
        XCTAssertEqual(fresh.useTrail.first?.at, "today")
        XCTAssertEqual(fresh.verdictConsequences[.actOn], "starts the next sit protocol in today's deep block")
        XCTAssertEqual(fresh.verdictConsequences[.nod], "waits for new evidence before it returns")
        XCTAssertEqual(fresh.verdictConsequences[.junk], "removes it from the active mind pass")
        XCTAssertEqual(fresh.commentThread?.comments.map(\.role), ["founder", "k"])
        XCTAssertNil(fresh.commentThread?.receipt)

        XCTAssertEqual(acted.artifactSignal, .acted)
        XCTAssertEqual(acted.useTrail.count, 1)
        XCTAssertTrue(acted.useTrail[0].text.contains("moved your two deep blocks"))
        XCTAssertEqual(
            MindCommentReceipt(who: "you", at: "today", change: "folded into the use trail").displayText,
            "resolved · you · today · folded into the use trail"
        )
    }

    func testArchivedThoughtsLeaveTheActiveList() throws {
        let active = try makeOutput(outputID: "active")
        let archived = try makeOutput(outputID: "archived", verdict: .junk)

        let state = MindThoughtListState(outputs: [active, archived])

        XCTAssertEqual(state.active.map(\.outputId), ["active"])
        XCTAssertEqual(state.archived.map(\.outputId), ["archived"])
        XCTAssertEqual(KCopy.mindArchivedCount(1, isExpanded: false), "show archived (1)")
        XCTAssertEqual(KCopy.mindArchivedCount(1, isExpanded: true), "hide archived (1)")
    }

    func testVerdictGrammarPreservesWireEnumsAndVisualOrder() {
        let actions = MindThoughtVerdictPresenter.actions

        XCTAssertEqual(actions.map(\.verdict), [.actOn, .nod, .junk])
        XCTAssertEqual(actions.map(\.label), ["act on", "later", "archive"])
        XCTAssertEqual(actions.map(\.iconName), ["arrow.up", "clock", "trash"])
        XCTAssertEqual(actions.map(\.showsLabel), [true, false, false])
        XCTAssertEqual(actions.map(\.verdict.rawValue), ["act-on", "nod", "junk"])
    }

    func testSelectionUsesZenTimingCurveWithoutSpringFamily() {
        let selection = MindThoughtMotionSpec.token(named: .selectionFlood)
        let text = MindThoughtMotionSpec.token(named: .textColor)

        XCTAssertEqual(selection.duration, 1)
        XCTAssertEqual(selection.controlPoints, [0.15, 0, 0.15, 1])
        XCTAssertEqual(text.duration, 0.7)
        XCTAssertEqual(Set(MindThoughtMotionSpec.tokens.map(\.family)), [.timingCurve])
    }

    func testSilentDayUsesCanonicalCopy() {
        XCTAssertEqual(
            KCopy.mindSilentDay,
            "the mind surfaced nothing today — evidence was thin, and silence beats a stretch."
        )
    }

    func testMindCommentHandoffUsesTypedChatAnchorAndRealEntityContext() throws {
        let output = try makeOutput(
            outputID: "thought-anchored",
            label: "efficiency jhana",
            statement: "one reversible step remains"
        )

        let handoff = MindChatThreadHandoffComposer.handoff(
            for: output,
            comment: "  what changes first?  "
        )

        XCTAssertEqual(handoff.anchorID, "thought-anchored")
        XCTAssertEqual(handoff.anchorText, "efficiency jhana — one reversible step remains")
        XCTAssertEqual(handoff.entities, [])
        XCTAssertEqual(handoff.initialComment, "what changes first?")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: text))
    }

    private func makeOutput(
        outputID: String = "thought-1",
        label: String = "a live thought",
        statement: String = "a claim worth holding",
        fields extraFields: [String: ViewPacketJSONValue] = [:],
        previews: [DecisionEvidencePreview] = [],
        evidence: [String] = [],
        verdict: MindVerdict? = nil
    ) throws -> MindOutput {
        var fields: [String: ViewPacketJSONValue] = [
            "outputId": .string(outputID),
            "outputType": .string("themes_open_loops"),
            "label": .string(label),
            "statement": .string(statement),
        ]
        fields.merge(extraFields) { _, new in new }
        let packet = ViewPacket(
            id: outputID,
            viewType: "loop.evidence",
            text: statement,
            fields: fields,
            evidence: evidence,
            evidencePreviews: previews
        )
        return try XCTUnwrap(MindOutput(packet: packet, verdict: verdict))
    }
}
