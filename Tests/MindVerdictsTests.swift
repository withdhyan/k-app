import CoreGraphics
import XCTest
@testable import K

final class MindVerdictsTests: XCTestCase {
    func testMindArtifactsDecodeProjectionShape() throws {
        let response = try decodeMindFixture()

        XCTAssertEqual(response.outputs.count, 2)
        XCTAssertEqual(response.evalDate, "2026-07-04")
        XCTAssertEqual(response.priorVerdicts.map(\.verdict), [.nod])

        let decision = try XCTUnwrap(response.outputs.first { $0.outputId == "decision-1" })
        XCTAssertEqual(decision.outputType, "build_decide")
        XCTAssertEqual(decision.packet.viewType, "k0.decision")
        XCTAssertEqual(decision.verdict, .nod)
        XCTAssertEqual(decision.evidence, ["atom-a", "atom-b"])
        XCTAssertTrue(decision.statement.contains("native Mind verdict surface"))

        let theme = try XCTUnwrap(response.outputs.first { $0.outputId == "theme-1" })
        XCTAssertEqual(theme.outputType, "themes_open_loops")
        XCTAssertEqual(theme.packet.viewType, "loop.evidence")
        XCTAssertEqual(theme.siblings, ["sibling-1", "sibling-2"])
        XCTAssertEqual(theme.considerations.count, 2)
    }

    func testMindOutputDecodesDecisionAnatomyAdditively() throws {
        let packet = ViewPacket(
            id: "mind-anatomy-1",
            viewType: "k0.decision",
            text: "approve the smallest reversible slice",
            fields: [
                "outputId": .string("decision-anatomy"),
                "outputType": .string("build_decide"),
                "statement": .string("approve the smallest reversible slice"),
                "what": .string("plan approval — one build unit is ready"),
                "contrast": .string("k leans approve: the slice is reversible."),
                "stakes": .string("reversible · silence keeps the lane blocked"),
                "evidenceSummary": .object([
                    "conversationCount": .number(2),
                    "latestAt": .string("2026-07-07T08:00:00.000Z"),
                    "topicHints": .array([.string("scope"), .string("cadence")]),
                ]),
                "payload": .object([
                    "signalExplained": .string("fresh scope evidence.")
                ]),
                "options": .array([
                    .object([
                        "id": .string("approve"),
                        "label": .string("approve it"),
                        "consequence": .string("the lane runs."),
                    ]),
                ]),
            ],
            evidence: ["atom-a", "atom-b"]
        )

        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(output.what, "plan approval — one build unit is ready")
        XCTAssertEqual(output.contrast, "k leans approve: the slice is reversible.")
        XCTAssertEqual(output.stakes, "reversible · silence keeps the lane blocked")
        XCTAssertEqual(output.evidenceSummary?.conversationCount, 2)
        XCTAssertEqual(output.evidenceSummary?.topicHints, ["scope", "cadence"])
        XCTAssertEqual(output.signalExplained, "fresh scope evidence.")
        XCTAssertEqual(output.options.map(\.label), ["approve it"])
        XCTAssertEqual(output.options.map(\.consequence), ["the lane runs."])
    }

    func testMindOutputEntityRefsDecodePresentAndAbsent() throws {
        let packet = ViewPacket(
            id: "mind-entity-1",
            viewType: "loop.evidence",
            text: "kedar naming and product alignment is unresolved",
            fields: [
                "outputId": .string("entity-1"),
                "outputType": .string("themes_open_loops"),
                "statement": .string("kedar naming and product alignment is unresolved"),
                "entityRefs": .array([
                    .object([
                        "name": .string("kedar naming and product alignment"),
                        "key": .string("kedar-naming-and-product-alignment"),
                    ]),
                ]),
            ]
        )

        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(output.entityRefs, [
            EntityRef(name: "kedar naming and product alignment", key: "kedar-naming-and-product-alignment"),
        ])

        let absentPacket = ViewPacket(
            id: "mind-entity-absent",
            viewType: "loop.evidence",
            text: "plain output",
            fields: [
                "outputId": .string("entity-absent"),
                "outputType": .string("themes_open_loops"),
                "statement": .string("plain output"),
            ]
        )
        XCTAssertEqual(try XCTUnwrap(MindOutput(packet: absentPacket)).entityRefs, [])
    }

    func testEntityDossierEnvelopeDecodesFullPartialAnd404() throws {
        let full = try JSONDecoder().decode(EntityDossierEnvelope.self, from: Data("""
        {
          "ok": true,
          "entity": {
            "key": "dreaming-edge-convergence",
            "name": "dreaming edge convergence",
            "evidenceIds": ["exp_a", "exp_b"]
          },
          "dossier": {
            "definition": "A derived definition.",
            "timeline": [
              {"date": "2026-01-10", "sourceName": "capture", "gist": "Founder named the product."},
              {"date": "2026-01-11", "sourceName": "chat", "gist": "The open question returned."}
            ],
            "related": ["kedar naming and product alignment"],
            "openQuestion": "what stays unresolved?"
          },
          "generatedAt": "2026-07-11T07:30:00.754Z",
          "source": "cs-k"
        }
        """.utf8))

        XCTAssertEqual(full.ok, true)
        XCTAssertEqual(full.entity?.key, "dreaming-edge-convergence")
        XCTAssertEqual(full.dossier?.definition, "A derived definition.")
        XCTAssertEqual(full.dossier?.timeline.map(\.date), ["2026-01-10", "2026-01-11"])
        XCTAssertEqual(full.dossier?.related, ["kedar naming and product alignment"])
        XCTAssertEqual(full.dossier?.openQuestion, "what stays unresolved?")
        XCTAssertFalse(full.isMissing)

        let partial = try JSONDecoder().decode(EntityDossierEnvelope.self, from: Data("""
        {
          "definition": "A partial direct dossier.",
          "related": ["related edge"],
          "generatedAt": "2026-07-11T07:31:00.000Z"
        }
        """.utf8))

        XCTAssertEqual(partial.dossier?.definition, "A partial direct dossier.")
        XCTAssertEqual(partial.dossier?.timeline, [])
        XCTAssertEqual(partial.dossier?.related, ["related edge"])
        XCTAssertFalse(partial.isMissing)

        let missing = try JSONDecoder().decode(EntityDossierEnvelope.self, from: Data("""
        {"ok":false,"error":"entity_not_found"}
        """.utf8))

        XCTAssertTrue(missing.isMissing)
        XCTAssertNil(missing.dossier)
        XCTAssertEqual(missing.error, "entity_not_found")
    }

    func testEntityDossierPanelNavigationOpensRelatedEntity() {
        var navigation = EntityDossierPanelNavigation(
            selection: EntityDossierSelection(name: "origin entity", key: "origin-key")
        )

        navigation.openRelated(" related entity ")

        XCTAssertEqual(navigation.current, EntityDossierSelection(name: "related entity"))

        navigation.openRelated("   ")

        XCTAssertEqual(navigation.current, EntityDossierSelection(name: "related entity"))
    }

    func testMindOutputDecodesDecisionBriefAndPairsOptionsById() throws {
        let packet = ViewPacket(
            id: "mind-brief-1",
            viewType: "k0.decision",
            text: "old statement",
            fields: [
                "outputId": .string("decision-brief"),
                "outputType": .string("build_decide"),
                "statement": .string("old statement"),
                "brief": .object([
                    "whyNow": .string("the evidence is fresh enough to decide."),
                    "openQuestion": .string("act on the slice or junk it?"),
                    "blocker": .string("needs founder judgment"),
                    "stakes": .string("reversible · silence leaves the slice staged"),
                    "options": .array([
                        .object([
                            "id": .string("act-on"),
                            "whatHappens": .string("k turns this into a build lane."),
                        ]),
                        .object([
                            "id": .string("approve"),
                            "whatHappens": .string("the lane runs."),
                        ]),
                    ]),
                ]),
                "options": .array([
                    .object([
                        "id": .string("approve"),
                        "label": .string("approve it"),
                        "consequence": .string("generic consequence."),
                    ]),
                ]),
            ]
        )

        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(output.brief?.whyNow, "the evidence is fresh enough to decide.")
        XCTAssertEqual(output.brief?.openQuestion, "act on the slice or junk it?")
        XCTAssertEqual(output.brief?.blockerLine, "blocker · needs founder judgment")
        XCTAssertEqual(output.brief?.whatHappens(for: MindVerdict.actOn.rawValue), "k turns this into a build lane.")
        XCTAssertEqual(output.options.map(\.consequence), ["the lane runs."])
    }

    func testEvidencePreviewsFormatRelativeDatesAndSuppressRawIdWalls() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let packet = try JSONDecoder().decode(ViewPacket.self, from: Data("""
        {
          "id": "mind-preview-1",
          "viewType": "loop.evidence",
          "text": "review the desk evidence",
          "fields": {
            "outputType": "themes_open_loops",
            "outputId": "preview-1",
            "statement": "review the desk evidence"
          },
          "evidence": ["exp_a91fd0", "exp_b82ce1"],
          "evidencePreviews": [
            {"label": "Founder launch note", "at": "2026-07-10T09:00:00.000Z"},
            {"label": "Yesterday scope thread", "at": "2026-07-09T23:15:00.000Z"}
          ]
        }
        """.utf8))
        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(output.evidencePreviews.map(\.label), ["Founder launch note", "Yesterday scope thread"])
        XCTAssertEqual(
            DecisionEvidencePreviewFormatter.lines(for: output.evidencePreviews, now: now, calendar: calendar),
            ["founder launch note · today", "yesterday scope thread · yesterday"]
        )
        XCTAssertEqual(
            MindEvidenceDetailFormatter.lines(
                previews: output.evidencePreviews,
                evidence: output.evidence,
                now: now,
                calendar: calendar
            ),
            ["founder launch note · today", "yesterday scope thread · yesterday"]
        )

        let fallback = MindEvidenceDetailFormatter.lines(
            previews: [],
            evidence: ["exp_a91fd0", "exp_b82ce1"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(fallback, ["2 pieces of evidence · details on the desk"])
        XCTAssertFalse(fallback.joined(separator: "\n").contains("exp_"))
    }

    func testMindCardContextPresenterMapsThreadAndInsightRowsAndStaysSilentWhenAbsent() throws {
        let packet = try JSONDecoder().decode(ViewPacket.self, from: Data("""
        {
          "id": "mind-context-1",
          "viewType": "loop.evidence",
          "text": "decide whether this thread matters",
          "fields": {
            "outputType": "themes_open_loops",
            "outputId": "context-1",
            "statement": "decide whether this thread matters",
            "observation": "This keeps returning after launch planning.",
            "considerations": [
              "Keep the first slice reversible.",
              {"text": "The UI work depends on named provenance."},
              {"id": "exp_a91fd0"}
            ]
          },
          "evidencePreviews": [
            {"name": "frontier ui-design agents", "date": "2026-03-31"},
            {"label": "reference · tue"}
          ]
        }
        """.utf8))
        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(
            MindCardContextPresenter.sections(for: output),
            [
                MindCardContextSection(
                    kind: .record,
                    title: "from your record",
                    rows: [
                        MindCardContextRow(primary: "frontier ui-design agents", secondary: "2026-03-31"),
                        MindCardContextRow(primary: "reference · tue", secondary: nil),
                    ]
                ),
                MindCardContextSection(
                    kind: .extracted,
                    title: "what k extracted",
                    rows: [
                        MindCardContextRow(primary: "This keeps returning after launch planning.", secondary: nil),
                        MindCardContextRow(primary: "Keep the first slice reversible.", secondary: nil),
                        MindCardContextRow(primary: "The UI work depends on named provenance.", secondary: nil),
                    ]
                ),
            ]
        )

        let silentPacket = ViewPacket(
            id: "mind-context-empty",
            viewType: "loop.evidence",
            text: "quiet output",
            fields: [
                "outputType": .string("themes_open_loops"),
                "outputId": .string("context-empty"),
                "statement": .string("quiet output"),
            ]
        )
        let silentOutput = try XCTUnwrap(MindOutput(packet: silentPacket))
        XCTAssertEqual(MindCardContextPresenter.sections(for: silentOutput), [])
    }

    func testPinnedOptionsLayoutKeepsVerdictControlsVisibleWhenBodyOverflows() {
        let plan = MindCardPinnedLayoutPolicy.plan(
            viewportHeight: 430,
            bodyContentHeight: 1_200,
            pinnedControlsHeight: 150
        )

        XCTAssertTrue(plan.bodyOverflows)
        XCTAssertTrue(plan.optionsVisible)
        XCTAssertEqual(plan.scrollViewportHeight, 280)
        XCTAssertEqual(plan.pinnedControlsMinY, 280)
        XCTAssertGreaterThan(
            MindCardPinnedLayoutPolicy.pinnedControlsLayoutPriority,
            MindCardPinnedLayoutPolicy.scrollBodyLayoutPriority
        )
    }

    func testVerdictPostBodyShape() async throws {
        let recorder = MindRequestRecorder(postBodies: [
            verdictResponse(outputType: "themes_open_loops", outputId: "theme-1", verdict: .actOn),
        ])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        _ = try await client.recordMindVerdict(
            date: "2026-07-04",
            outputType: "themes_open_loops",
            outputId: "theme-1",
            verdict: .actOn
        )

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/artifacts/mind/verdict")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(json["date"] as? String, "2026-07-04")
        XCTAssertEqual(json["outputType"] as? String, "themes_open_loops")
        XCTAssertEqual(json["outputId"] as? String, "theme-1")
        XCTAssertEqual(json["verdict"] as? String, "act-on")
        XCTAssertNil(json["path"])
    }

    func testNudgeFeedbackPostBodyShape() async throws {
        let recorder = MindRequestRecorder(postBodies: [#"{"ok":true}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        _ = try await client.recordMindFeedback(
            date: "2026-07-04",
            outputType: "nudge_ranked",
            outputId: "nudge-1",
            feedback: .tooNoisy
        )

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/artifacts/mind/verdict")
        XCTAssertEqual(json["date"] as? String, "2026-07-04")
        XCTAssertEqual(json["outputType"] as? String, "nudge_ranked")
        XCTAssertEqual(json["outputId"] as? String, "nudge-1")
        XCTAssertEqual(json["feedback"] as? String, "too_noisy")
        XCTAssertNil(json["verdict"])
    }

    func testNudgeFeedbackEligibilityIsDefensive() throws {
        let grouped = ViewPacket(
            id: "nudge-1",
            viewType: "k0.claim",
            text: "move the call",
            fields: [
                "outputGroup": .string("ranked_nudge"),
                "statement": .string("move the call"),
            ]
        )
        let cued = ViewPacket(
            id: "cue-1",
            viewType: "k0.claim",
            text: "send note",
            fields: [
                "outputType": .string("resurfaced"),
                "statement": .string("send note"),
                "cue": .object(["at": .string("17:00")]),
            ]
        )
        let ordinary = ViewPacket(
            id: "theme-1",
            viewType: "loop.evidence",
            text: "regular output",
            fields: [
                "outputType": .string("themes_open_loops"),
                "statement": .string("regular output"),
            ]
        )

        XCTAssertTrue(try XCTUnwrap(MindOutput(packet: grouped)).supportsNudgeFeedback)
        XCTAssertTrue(try XCTUnwrap(MindOutput(packet: cued)).supportsNudgeFeedback)
        XCTAssertFalse(try XCTUnwrap(MindOutput(packet: ordinary)).supportsNudgeFeedback)
    }

    func testMindVerdictAccessibilityUsesSpokenLabelsAndCardSummary() throws {
        let packet = ViewPacket(
            id: "decision-1",
            viewType: "k0.decision",
            text: "ship the smallest reversible verdict panel",
            fields: [
                "outputType": .string("build_decide"),
                "outputId": .string("decision-1"),
                "label": .string("native Mind verdict surface"),
                "statement": .string("ship verdicts\nwithout new permissions"),
            ],
            evidence: ["atom-a", "atom-b"]
        )
        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(MindVerdictAccessibility.controlLabel(for: .actOn), "act on")
        XCTAssertEqual(MindVerdictAccessibility.controlLabel(for: .nod), "nod")
        XCTAssertEqual(MindVerdictAccessibility.controlLabel(for: .junk), "junk")
        XCTAssertEqual(
            MindVerdictAccessibility.controlHint(for: .actOn, output: output),
            "record act on for native Mind verdict surface"
        )
        XCTAssertEqual(
            MindVerdictAccessibility.cardLabel(for: output),
            "title: native Mind verdict surface. body: ship verdicts. without new permissions. source: build decide, 2 evidence items"
        )
    }

    @MainActor
    func testAdvanceOnVerdictSuccess() async throws {
        let recorder = MindRequestRecorder(
            getBody: try fixtureString("mind-artifacts"),
            postBodies: [
                verdictResponse(outputType: "themes_open_loops", outputId: "theme-1", verdict: .actOn),
            ]
        )
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.load()

        XCTAssertEqual(model.currentOutput?.outputId, "theme-1")
        XCTAssertEqual(model.progressText, "1 of 2")

        let success = await model.submitVerdict(.actOn)

        XCTAssertTrue(success)
        XCTAssertEqual(model.lastSubmitted?.output.outputId, "theme-1")
        XCTAssertEqual(model.currentOutput?.outputId, "decision-1")
        XCTAssertEqual(model.progressText, "2 of 2")
        XCTAssertNil(model.submissionError)
    }

    @MainActor
    func testMindDemoPassLoadsWithoutTransportAndKeepsDepthState() async throws {
        let recorder = MindRequestRecorder(getBody: #"{"unexpected":true}"#)
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            demoResponse: MindDemo.response
        )

        await model.load()

        XCTAssertTrue(model.isDemoPass)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.outputs.map(\.outputId), ["efficiency-jhana", "kedars-name", "morning-light", "standing-desk"])
        XCTAssertEqual(model.currentOutput?.outputId, "efficiency-jhana")
        XCTAssertEqual(model.outputs.first?.artifactSignal, .fresh)
        XCTAssertEqual(model.outputs.first?.useTrail.count, 1)
        XCTAssertEqual(recorder.requests, [])

        let didSubmit = await model.submitVerdict(.actOn)
        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.currentOutput?.outputId, "kedars-name")
        XCTAssertEqual(recorder.requests, [])
    }

    @MainActor
    func testVerdictErrorShowsInlineRetryStateAndRetryAdvances() async throws {
        let recorder = MindRequestRecorder(
            getBody: try fixtureString("mind-artifacts"),
            postBodies: [
                verdictResponse(outputType: "themes_open_loops", outputId: "theme-1", verdict: .junk),
            ],
            postErrors: [
                AGUIClientError.stream("offline"),
            ]
        )
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.load()
        let failed = await model.submitVerdict(.junk)

        XCTAssertFalse(failed)
        XCTAssertEqual(model.currentOutput?.outputId, "theme-1")
        XCTAssertEqual(model.submissionError?.text, "answer failed · retry")
        XCTAssertEqual(model.submissionError?.verdict, .junk)

        let retried = await model.retryVerdict()

        XCTAssertTrue(retried)
        XCTAssertEqual(model.currentOutput?.outputId, "decision-1")
        XCTAssertNil(model.submissionError)
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }

    @MainActor
    func testBrowseChangesIndexWithoutVerdictWrites() async throws {
        let recorder = MindRequestRecorder(getBody: try fixtureString("mind-artifacts"))
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.load()

        XCTAssertEqual(model.currentOutput?.outputId, "theme-1")
        XCTAssertEqual(model.progressText, "1 of 2")

        model.browseNext()

        XCTAssertEqual(model.currentOutput?.outputId, "decision-1")
        XCTAssertEqual(model.progressText, "2 of 2")
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 0)

        model.browsePrevious()

        XCTAssertEqual(model.currentOutput?.outputId, "theme-1")
        XCTAssertEqual(model.progressText, "1 of 2")
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "POST" }.count, 0)
    }

    @MainActor
    func testUndoReturnsToPreviousOutputAndRepostOverwritesThatOutput() async throws {
        let recorder = MindRequestRecorder(
            getBody: try fixtureString("mind-artifacts"),
            postBodies: [
                verdictResponse(outputType: "themes_open_loops", outputId: "theme-1", verdict: .actOn),
                verdictResponse(outputType: "themes_open_loops", outputId: "theme-1", verdict: .junk),
            ]
        )
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.load()
        let firstSubmit = await model.submitVerdict(.actOn)

        XCTAssertTrue(firstSubmit)
        XCTAssertEqual(model.currentOutput?.outputId, "decision-1")

        model.undoLastVerdict()

        XCTAssertEqual(model.currentOutput?.outputId, "theme-1")
        XCTAssertFalse(model.canUndo)
        let secondSubmit = await model.submitVerdict(.junk)

        XCTAssertTrue(secondSubmit)

        let postBodies = try recorder.requests
            .filter { $0.httpMethod == "POST" }
            .map { request -> [String: Any] in
                let body = try XCTUnwrap(request.httpBody)
                return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            }

        XCTAssertEqual(postBodies.map { $0["outputId"] as? String }, ["theme-1", "theme-1"])
        XCTAssertEqual(postBodies.map { $0["verdict"] as? String }, ["act-on", "junk"])
        XCTAssertEqual(model.currentOutput?.outputId, "decision-1")
    }

    @MainActor
    func testEmptyMindArtifactsState() async {
        let recorder = MindRequestRecorder(getBody: """
        {"outputSections":[],"priorVerdicts":[],"evalDate":"2026-07-04","generatedAt":"2026-07-04T07:00:00.000Z","source":"cs-k"}
        """)
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.load()

        XCTAssertEqual(model.outputs, [])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.progressText, "0 of 0")
        XCTAssertEqual(model.emptyText, "no outputs to judge — the mind pass is running")
    }

    @MainActor
    func testInitialLoadIsSkeletonStateDistinctFromEmptyAndUnreachable() async throws {
        // Idle, before any fetch: skeleton, not the earned-silence copy.
        let emptyRecorder = MindRequestRecorder(getBody: """
        {"outputSections":[],"priorVerdicts":[],"evalDate":"2026-07-04"}
        """)
        let emptyModel = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: emptyRecorder.transport) }
        )
        XCTAssertTrue(emptyModel.isInitialLoad)

        await emptyModel.load()

        // Ran and surfaced nothing: loaded + empty, no skeleton, no error.
        XCTAssertFalse(emptyModel.isInitialLoad)
        XCTAssertEqual(emptyModel.loadState, .loaded)
        XCTAssertNil(emptyModel.loadErrorText)
    }

    @MainActor
    func testUnreachableStateIsDistinctFromEarnedSilence() async {
        let transport = AGUIHTTPTransport { request in
            throw AGUIClientError.stream("offline")
        }
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )

        await model.load()

        // Invariant 7: unreachable is failed + empty + error surfaced — never
        // the loaded-empty earned-silence state.
        XCTAssertTrue(model.outputs.isEmpty)
        XCTAssertNotNil(model.loadErrorText)
        XCTAssertFalse(model.isInitialLoad)
        if case .failed = model.loadState {} else {
            XCTFail("expected failed load state, got \(model.loadState)")
        }
    }

    func testCachedMindPassRebuildsOutputsIdenticallyToLiveDecode() throws {
        let live = try decodeMindFixture()
        let cached = CachedMindPass(response: live)

        XCTAssertEqual(cached.version, CachedMindPass.currentVersion)
        XCTAssertEqual(cached.rebuiltOutputs(), live.outputs)
    }

    func testDiskCacheRoundTripsThroughEncodedFile() throws {
        let fileURL = Self.temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let disk = MindPassDiskCache(fileURL: fileURL)
        let pass = CachedMindPass(response: try decodeMindFixture())

        disk.save(pass)
        let reloaded = try XCTUnwrap(disk.load())

        XCTAssertEqual(reloaded, pass)
        XCTAssertEqual(reloaded.rebuiltOutputs(), pass.rebuiltOutputs())
    }

    @MainActor
    func testColdLaunchPrimesFromDiskThenLiveLoadSupersedes() async throws {
        let fileURL = Self.temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let disk = MindPassDiskCache(fileURL: fileURL)

        // First session fetches and persists the pass.
        let writer = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: MindRequestRecorder(getBody: try! fixtureString("mind-artifacts")).transport) },
            cache: disk
        )
        await writer.load()
        XCTAssertFalse(writer.outputs.isEmpty)

        // Cold launch: prime renders the cached cards immediately, marked stale,
        // before any live fetch runs.
        let reader = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: MindRequestRecorder(getBody: try! fixtureString("mind-artifacts")).transport) },
            cache: disk
        )
        XCTAssertTrue(reader.isInitialLoad)
        reader.primeFromCacheIfNeeded()

        XCTAssertFalse(reader.outputs.isEmpty)
        XCTAssertFalse(reader.isInitialLoad)
        XCTAssertTrue(reader.isShowingCachedPass)
        XCTAssertTrue(reader.isStale)

        // Live load supersedes the primed pass and clears the cached/stale marks.
        await reader.load()
        XCTAssertFalse(reader.isShowingCachedPass)
        XCTAssertFalse(reader.isRefreshing)
        XCTAssertFalse(reader.isStale)
        XCTAssertEqual(reader.loadState, .loaded)
    }

    @MainActor
    func testRefreshFailureKeepsCachedCardsAndMarksStale() async throws {
        let fileURL = Self.temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let disk = MindPassDiskCache(fileURL: fileURL)
        disk.save(CachedMindPass(response: try decodeMindFixture()))

        let failing = AGUIHTTPTransport { _ in throw AGUIClientError.stream("offline") }
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: failing) },
            cache: disk
        )
        model.primeFromCacheIfNeeded()
        XCTAssertFalse(model.outputs.isEmpty)

        await model.load()

        // Cards stay on screen; the surface reads stale + unreachable, never a
        // false empty (invariant 7).
        XCTAssertFalse(model.outputs.isEmpty)
        XCTAssertTrue(model.isStale)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.loadErrorText)
    }

    @MainActor
    func testEmptyLivePassClearsDiskCache() async throws {
        let fileURL = Self.temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let disk = MindPassDiskCache(fileURL: fileURL)
        disk.save(CachedMindPass(response: try decodeMindFixture()))
        XCTAssertNotNil(disk.load())

        let emptyRecorder = MindRequestRecorder(getBody: """
        {"outputSections":[],"priorVerdicts":[],"evalDate":"2026-07-05"}
        """)
        let model = MindVerdictsModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: emptyRecorder.transport) },
            cache: disk
        )
        await model.load()

        // Yesterday's cards must not resurrect on the next cold launch.
        XCTAssertNil(disk.load())
    }

    private static func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mind-pass-cache-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func decodeMindFixture() throws -> MindArtifactsResponse {
        try JSONDecoder().decode(MindArtifactsResponse.self, from: Data(try fixtureString("mind-artifacts").utf8))
    }
}

private final class MindRequestRecorder {
    private let getBody: String
    private var postBodies: [String]
    private var postErrors: [Error]
    private(set) var requests: [URLRequest] = []

    init(
        getBody: String = #"{"outputSections":[],"priorVerdicts":[]}"#,
        postBodies: [String] = [#"{"ok":true}"#],
        postErrors: [Error] = []
    ) {
        self.getBody = getBody
        self.postBodies = postBodies
        self.postErrors = postErrors
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.requests.append(request)
            if request.httpMethod == "POST", !self.postErrors.isEmpty {
                throw self.postErrors.removeFirst()
            }

            let body: String
            if request.httpMethod == "GET" {
                body = self.getBody
            } else if self.postBodies.isEmpty {
                body = #"{"ok":true}"#
            } else {
                body = self.postBodies.removeFirst()
            }

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: response, lines: Self.stream(body))
        }
    }

    private static func stream(_ body: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if !body.isEmpty {
                continuation.yield(body)
            }
            continuation.finish()
        }
    }
}

private func verdictResponse(outputType: String, outputId: String, verdict: MindVerdict) -> String {
    """
    {"ok":true,"verdict":{"passId":"2026-07-04","date":"2026-07-04","outputType":"\(outputType)","outputId":"\(outputId)","label":"fixture","verdict":"\(verdict.rawValue)"}}
    """
}

private func fixtureString(_ name: String) throws -> String {
    let bundle = Bundle(for: MindVerdictsTests.self)
    let url = [
        bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        bundle.url(forResource: name, withExtension: "json", subdirectory: "Tests/Fixtures"),
        bundle.url(forResource: name, withExtension: "json"),
    ].compactMap { $0 }.first

    let fixtureURL = try XCTUnwrap(url, "Missing fixture \(name).json")
    return try String(contentsOf: fixtureURL)
}
