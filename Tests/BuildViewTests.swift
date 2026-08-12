import XCTest
import UIKit
@testable import K

final class BuildViewTests: XCTestCase {
    @MainActor
    func testBuildAuditFixtureWinsOverLoadingPreview() {
        let model = BuildModel(
            baseURL: "http://daemon.test",
            arguments: ["Kedar", KLoadingPreview.launchArgument, BuildAuditFixture.launchArgument]
        )

        model.start()

        XCTAssertTrue(model.packets.contains(where: \.isBuildStatusPacket))
        XCTAssertFalse(model.packets.isEmpty)
        let surface = BuildReportSurface.make(packets: model.packets, openCardCount: model.openCards.count)
        XCTAssertGreaterThan(surface.branches.filter { !$0.isTrunk }.count, 0)
        XCTAssertFalse(model.isLoading)
    }

    func testBuildStatusPacketDecodesAndUsesBuildRenderBranch() throws {
        let packet = try decodeFixture("build-status")
        let summary = BuildStatusSummary(packet: packet)

        XCTAssertEqual(packet.viewType, "build.status")
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .buildStatus)
        XCTAssertEqual(summary.title, "Native Build tab")
        XCTAssertEqual(summary.state, "building")
        XCTAssertEqual(summary.units.map(\.state), ["integrated", "building", "held"])
        XCTAssertEqual(summary.lanes.map(\.age), ["48s", "4m"])
    }

    func testBuildStatusFallsBackToPlanNicknameNotPlanSlug() {
        let summary = BuildStatusSummary(
            packet: ViewPacket(
                id: "status-plan-2026-08-10-004",
                viewType: "build.status",
                text: "plan-2026-08-10-004-feat-build-copy",
                fields: [
                    "plan": .object([
                        "id": .string("plan-2026-08-10-004-feat-build-copy"),
                        "state": .string("building"),
                    ])
                ]
            )
        )

        XCTAssertEqual(summary.title, "build-copy")
        XCTAssertFalse(summary.title.contains("plan-"))
    }

    func testBuildCardPacketDecodesAndUsesBuildRenderBranch() throws {
        let packet = try decodeFixture("build-card")
        let summary = BuildCardSummary(packet: packet)

        XCTAssertEqual(packet.viewType, "build.card")
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .buildCard)
        XCTAssertEqual(summary.title, "Approve U4 visual polish")
        XCTAssertTrue(packet.isOpenBuildCard)
        XCTAssertTrue(ViewPacketRenderer.exposesActionAffordance(for: packet))
        XCTAssertEqual(summary.options.map(\.id), ["approve", "reject"])
        XCTAssertEqual(summary.options.map(\.consequence), [
            "Allow the plan to run.",
            "Stop this draft and keep the runner idle.",
        ])
    }

    func testBuildCardOptionsRenderButtonsWithConsequences() throws {
        let packet = try decodeFixture("build-card")
        let card = try XCTUnwrap(BuildCard(packet: packet))
        let presentation = BuildCardPresentation(card: card)

        XCTAssertFalse(presentation.isCollapsed)
        XCTAssertEqual(presentation.options.map(\.option.label), ["Approve", "Reject"])
        XCTAssertEqual(presentation.options.map(\.consequence), [
            "Allow the plan to run.",
            "Stop this draft and keep the runner idle.",
        ])
        XCTAssertEqual(presentation.options.map(\.isEnabled), [true, true])
        XCTAssertEqual(presentation.options.map(\.isPrimary), [true, false])
    }

    func testDisconnectedBuildOptionTapAffordanceStaysEnabledWithReasonNote() throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let presentation = BuildCardPresentation(card: card, disabledReason: "offline")

        XCTAssertEqual(presentation.note, "offline")
        XCTAssertEqual(presentation.options.map(\.isEnabled), [true, true])
        XCTAssertEqual(presentation.options.map(\.disabledReason), [nil, nil])
    }

    func testBuildOptionDisablementAlwaysCarriesReason() throws {
        let openCard = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let pending = BuildCardPresentation(card: openCard, isPending: true)

        XCTAssertEqual(pending.options.map(\.isEnabled), [false, false])
        XCTAssertEqual(pending.options.map(\.disabledReason), [KCopy.answerPending, KCopy.answerPending])

        let loopback = BuildCard(
            id: "loopback",
            tier: "loopback",
            title: "mac approval",
            options: [
                BuildCardOption(id: "approve", label: "approve"),
                BuildCardOption(id: "hold", label: "hold"),
            ]
        )
        let loopbackPresentation = BuildCardPresentation(card: loopback)
        XCTAssertEqual(loopbackPresentation.options.map(\.isEnabled), [false, false])
        XCTAssertEqual(loopbackPresentation.options.map(\.disabledReason), ["pinned to the mac", "pinned to the mac"])
    }

    func testBuildCardDecodesDecisionAnatomyAdditively() throws {
        let packet = ViewPacket(
            id: "build-card-anatomy",
            viewType: "build.card",
            text: "approve the slice",
            fields: [
                "title": .string("approve the slice"),
                "body": .string("the smallest slice is staged."),
                "what": .string("plan approval — one build unit is ready"),
                "contrast": .string("k leans approve: the slice is reversible."),
                "stakes": .string("reversible · silence keeps the lane blocked"),
                "evidenceSummary": .object([
                    "conversationCount": .number(3),
                    "atomCount": .number(7),
                    "latestAt": .string("2026-07-07T08:00:00.000Z"),
                    "topicHints": .array([.string("naming"), .string("positioning")]),
                ]),
                "payload": .object([
                    "signalExplained": .string("convergence is high and fresh.")
                ]),
                "options": .array([
                    .object([
                        "id": .string("approve"),
                        "label": .string("approve the slice"),
                        "consequence": .string("the lane runs."),
                    ]),
                    .object([
                        "id": .string("hold"),
                        "label": .string("hold for review"),
                        "consequence": .string("the lane stays staged."),
                    ]),
                ]),
            ]
        )

        let card = try XCTUnwrap(BuildCard(packet: packet))

        XCTAssertEqual(card.what, "plan approval — one build unit is ready")
        XCTAssertEqual(card.contrast, "k leans approve: the slice is reversible.")
        XCTAssertEqual(card.stakes, "reversible · silence keeps the lane blocked")
        XCTAssertEqual(card.evidenceSummary?.conversationCount, 3)
        XCTAssertEqual(card.evidenceSummary?.atomCount, 7)
        XCTAssertEqual(card.evidenceSummary?.topicHints, ["naming", "positioning"])
        XCTAssertEqual(card.signalExplained, "convergence is high and fresh.")
        XCTAssertEqual(card.options.map(\.label), ["approve the slice", "hold for review"])
        XCTAssertEqual(card.options.map(\.consequence), ["the lane runs.", "the lane stays staged."])
    }

    func testBuildCardEntityRefsDecodePresentAndAbsent() throws {
        let packet = ViewPacket(
            id: "build-card-entity",
            viewType: "build.card",
            text: "kedar naming and product alignment",
            fields: [
                "title": .string("kedar naming and product alignment"),
                "body": .string("the kedar naming and product alignment edge is open."),
                "entityRefs": .array([
                    .object([
                        "name": .string("kedar naming and product alignment"),
                        "key": .string("kedar-naming-and-product-alignment"),
                    ]),
                ]),
            ]
        )

        let card = try XCTUnwrap(BuildCard(packet: packet))

        XCTAssertEqual(card.entityRefs, [
            EntityRef(name: "kedar naming and product alignment", key: "kedar-naming-and-product-alignment"),
        ])
        XCTAssertEqual(BuildCard(id: "absent", title: "plain card").entityRefs, [])
    }

    func testEntitySpanMatcherMatchesWholeNamesOnly() {
        let refs = [
            EntityRef(name: "kedar"),
            EntityRef(name: "kedar naming", key: "kedar-naming"),
        ]
        let text = "kedar naming came up; kedar stayed open; kedarish did not."

        let matches = EntitySpanMatcher.matches(in: text, refs: refs)

        XCTAssertEqual(matches.map { String(text[$0.range]) }, ["kedar naming", "kedar"])
        XCTAssertEqual(matches.map(\.ref.key), ["kedar-naming", nil])
    }

    func testDecisionBriefDecodesFullAbsentAndPartial() throws {
        let full = try JSONDecoder().decode(DecisionBrief.self, from: Data("""
        {
          "whyNow": "the lane is paused on one reversible call.",
          "openQuestion": "continue the lane or hold it?",
          "blocker": "scope moved past the declared file",
          "stakes": "reversible · silence keeps the lane blocked",
          "options": [
            {"id": "continue", "whatHappens": "the lane runs with the scope call attached."},
            {"id": "hold", "what_happens": "the lane stays staged for review."}
          ]
        }
        """.utf8))

        XCTAssertEqual(full.whyNow, "the lane is paused on one reversible call.")
        XCTAssertEqual(full.openQuestion, "continue the lane or hold it?")
        XCTAssertEqual(full.blockerLine, "blocker · scope moved past the declared file")
        XCTAssertEqual(full.stakes, "reversible · silence keeps the lane blocked")
        XCTAssertEqual(full.whatHappens(for: "continue"), "the lane runs with the scope call attached.")
        XCTAssertEqual(full.whatHappens(for: "hold"), "the lane stays staged for review.")

        let absent = BuildCard(id: "card-absent", title: "plain card")
        XCTAssertNil(absent.brief)

        let partial = try JSONDecoder().decode(DecisionBrief.self, from: Data("""
        {
          "open_question": "hold or continue?",
          "options": [
            {"id": "continue", "whatHappens": "the lane moves."}
          ]
        }
        """.utf8))
        XCTAssertNil(partial.whyNow)
        XCTAssertEqual(partial.openQuestion, "hold or continue?")
        XCTAssertEqual(partial.blockerLine, "ready to decide")
        XCTAssertNil(partial.stakes)
        XCTAssertEqual(partial.whatHappens(for: "continue"), "the lane moves.")
    }

    func testBuildCardBriefPairsWhatHappensToOptionsById() throws {
        let packet = ViewPacket(
            id: "build-card-brief",
            viewType: "build.card",
            text: "old body",
            fields: [
                "title": .string("scope drift hold"),
                "body": .string("old consequence body"),
                "decisionBrief": .object([
                    "whyNow": .string("the lane is paused on one reversible call."),
                    "openQuestion": .string("continue the lane or hold it?"),
                    "options": .array([
                        .object([
                            "id": .string("hold"),
                            "whatHappens": .string("the lane stays staged for review."),
                        ]),
                        .object([
                            "id": .string("continue"),
                            "whatHappens": .string("the lane runs with the scope call attached."),
                        ]),
                    ]),
                    "stakes": .string("reversible · silence keeps the lane blocked"),
                ]),
                "options": .array([
                    .object([
                        "id": .string("continue"),
                        "label": .string("continue the lane"),
                        "consequence": .string("generic continue consequence."),
                    ]),
                    .object([
                        "id": .string("hold"),
                        "label": .string("hold for review"),
                        "consequence": .string("generic hold consequence."),
                    ]),
                ]),
            ]
        )

        let card = try XCTUnwrap(BuildCard(packet: packet))
        let presentation = BuildCardPresentation(card: card)

        XCTAssertEqual(card.brief?.whyNow, "the lane is paused on one reversible call.")
        XCTAssertEqual(card.brief?.openQuestion, "continue the lane or hold it?")
        XCTAssertEqual(presentation.options.map(\.option.label), ["continue the lane", "hold for review"])
        XCTAssertEqual(presentation.options.map(\.consequence), [
            "the lane runs with the scope call attached.",
            "the lane stays staged for review.",
        ])
    }

    func testDecisionEvidenceLineFormatterUsesRelativeDayHintsAndPlurality() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))

        XCTAssertEqual(
            DecisionEvidenceLineFormatter.line(
                for: DecisionEvidenceSummary(
                    conversationCount: 3,
                    atomCount: 7,
                    latestAt: "2026-07-07T08:00:00.000Z",
                    topicHints: ["Naming", "positioning"]
                ),
                now: now,
                calendar: calendar
            ),
            "3 conversations · latest tue · naming, positioning"
        )
        XCTAssertEqual(
            DecisionEvidenceLineFormatter.line(
                for: DecisionEvidenceSummary(conversationCount: 1, latestAt: "2026-07-10T08:00:00Z"),
                now: now,
                calendar: calendar
            ),
            "1 conversation · latest today"
        )
        XCTAssertEqual(
            DecisionEvidenceLineFormatter.line(
                for: DecisionEvidenceSummary(atomCount: 1, topicHints: ["scope"]),
                now: now,
                calendar: calendar
            ),
            "1 atom · scope"
        )
    }

    func testLoopbackBuildCardDisablesAnswerAffordance() throws {
        let packet = try decodeFixture("build-card-loopback")

        XCTAssertTrue(packet.isLoopbackOnlyBuildCard)
        XCTAssertTrue(packet.isOpenBuildCard)
        XCTAssertEqual(
            ViewPacketRenderer.actionAffordance(for: packet),
            .disabled(reason: "answer from the mac")
        )
        XCTAssertFalse(ViewPacketRenderer.exposesActionAffordance(for: packet))

        let card = try XCTUnwrap(BuildCard(packet: packet))
        let presentation = BuildCardPresentation(card: card)
        XCTAssertEqual(presentation.note, "pinned to the mac")
    }

    @MainActor
    func testAnswerSuccessCollapsesCard() async throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let option = try XCTUnwrap(card.options.first)
        let transport = jsonTransport(body: answerBody(card: card.answeredCopy(option: option)))
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )
        model.apply(.snapshot([card.packet]))

        await model.submitAnswer(card: card, option: option)

        let row = try XCTUnwrap(model.cardRows.first)
        XCTAssertTrue(row.isAnswered)
        XCTAssertEqual(row.historyLine, "answered by founder")
        XCTAssertTrue(model.openCards.isEmpty)
        XCTAssertNil(model.cardErrorText(for: card))
        XCTAssertEqual(model.streamLines.map(\.text), ["approve u4 visual polish · approve"])
        XCTAssertEqual(model.streamLines.map(\.role), [.founder])
    }

    @MainActor
    func testAnswerFailureShowsInlineError() async throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let option = try XCTUnwrap(card.options.first)
        let transport = AGUIHTTPTransport { _ in
            throw AGUIClientError.stream("offline")
        }
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )
        model.apply(.snapshot([card.packet]))

        await model.submitAnswer(card: card, option: option)

        XCTAssertEqual(
            model.cardErrorText(for: card),
            "answer failed · retry"
        )
        XCTAssertEqual(model.openCards.map(\.id), [card.id])
    }

    @MainActor
    func testAlreadyAnsweredStateRendersAnsweredBy() async throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let option = try XCTUnwrap(card.options.first)
        let keptOption = try XCTUnwrap(card.options.last)
        let responseCard = card.answeredCopy(
            option: keptOption,
            alreadyAnswered: BuildAlreadyAnswered(by: "loopback", at: "2026-07-04T00:00:00.000Z", optionId: keptOption.id)
        )
        let transport = jsonTransport(
            body: """
            {"ok":true,"alreadyAnswered":{"by":"loopback","at":"2026-07-04T00:00:00.000Z","optionId":"\(keptOption.id)"},"card":\(cardJSON(responseCard))}
            """
        )
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )
        model.apply(.snapshot([card.packet]))

        await model.submitAnswer(card: card, option: option)

        XCTAssertEqual(model.cardRows.first?.historyLine, "answered on the mac")
        XCTAssertEqual(model.cardRows.first?.answerOption, keptOption.id)
        XCTAssertEqual(model.cardCaptionText(for: card), "answered earlier from loopback · kept that answer")
        XCTAssertEqual(model.accessibilityLog.last, "answered earlier from loopback · kept that answer")
        XCTAssertTrue(model.openCards.isEmpty)
    }

    @MainActor
    func testAnswerResponseWithStaleOpenPacketDoesNotReopenCard() async throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let option = try XCTUnwrap(card.options.first)
        let keptOption = try XCTUnwrap(card.options.last)
        let responseCard = card.answeredCopy(
            option: keptOption,
            alreadyAnswered: BuildAlreadyAnswered(by: "loopback", at: "2026-07-04T00:00:00.000Z", optionId: keptOption.id)
        )
        let transport = jsonTransport(
            body: """
            {"ok":true,"alreadyAnswered":{"by":"loopback","at":"2026-07-04T00:00:00.000Z","optionId":"\(keptOption.id)"},"card":\(cardJSON(responseCard)),"packets":[\(packetJSON(card.packet))]}
            """
        )
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )
        model.apply(.snapshot([card.packet]))

        await model.submitAnswer(card: card, option: option)

        let row = try XCTUnwrap(model.workingCards.first)
        XCTAssertTrue(row.isAnswered)
        XCTAssertEqual(row.historyLine, "answered on the mac")
        XCTAssertTrue(model.openCards.isEmpty)
        XCTAssertTrue(BuildCardPresentation(card: row).isCollapsed)
    }

    @MainActor
    func testLaterAnsweredBuildCardPacketOverridesOpenSnapshotCard() throws {
        let card = try XCTUnwrap(BuildCard(packet: decodeFixture("build-card")))
        let option = try XCTUnwrap(card.options.first)
        var answeredPacket = card.answeredCopy(option: option).packet
        answeredPacket.id = "answered-event-\(card.id)"
        let model = BuildModel(baseURL: "http://daemon.test")

        model.apply(.snapshot([card.packet]))
        model.apply(.packet(answeredPacket))

        let row = try XCTUnwrap(model.cardRows.first)
        XCTAssertTrue(row.isAnswered)
        XCTAssertEqual(row.answerOption, option.id)
        XCTAssertTrue(model.openCards.isEmpty)
        XCTAssertEqual(model.cardRows.map(\.id), [card.id])
        XCTAssertTrue(BuildCardPresentation(card: row).isCollapsed)
    }

    @MainActor
    func testBuildSnapshotCacheLoadsAsStaleAndClearsOnSync() throws {
        let cachedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T08:45:00Z"))
        let syncedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T09:00:00Z"))
        let status = try decodeFixture("build-status")
        let store = tempSnapshotStore()
        store.save([status], syncedAt: cachedAt)
        let model = BuildModel(
            baseURL: "http://daemon.test",
            cacheStore: store,
            now: { syncedAt }
        )

        XCTAssertTrue(model.loadCachedSnapshot())
        XCTAssertEqual(model.packets.map(\.id), [status.id])
        XCTAssertTrue(model.isStale)

        model.apply(.snapshot([status]))

        XCTAssertFalse(model.isStale)
        XCTAssertEqual(store.loadEntry()?.savedAt, syncedAt)
    }

    @MainActor
    func testIntent404RendersDormantState() async {
        let transport = jsonTransport(status: 404, body: #"{"ok":false,"error":"not_found"}"#)
        let queueStore = tempInputQueueStore()
        defer { queueStore.clear() }
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) },
            inputQueueStore: queueStore,
            now: { createdAt }
        )

        await model.submitIntent("add weekly build summary")

        XCTAssertEqual(model.intentState, .notYet)
        XCTAssertTrue(model.intentState.isDormant)
        XCTAssertEqual(model.intentState.text, "dormant · request endpoint not live")
        XCTAssertEqual(model.inputQueue.items.map(\.text), ["add weekly build summary"])
        XCTAssertEqual(model.inputQueue.items.first?.createdAt, createdAt)
        XCTAssertEqual(model.intentAcknowledgementLines.last?.text, KCopy.queuedWillSync)
        XCTAssertEqual(
            model.intentAcknowledgementLines.last?.meta,
            KTimestampFormatter.hourMinute(createdAt)
        )
    }

    func testWorkerRailItemsUseActiveUnitsFromSnapshotFixture() throws {
        let status = try decodeFixture("build-status")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))

        let items = BuildWorkerRailItem.items(from: [status])

        XCTAssertEqual(items.map(\.unitId), ["U4", "U5"])
        XCTAssertEqual(items.map(\.state), ["building", "held"])
        XCTAssertEqual(items.map(\.accessibilityIdentifier), ["build-worker-U4", "build-worker-U5"])
        XCTAssertEqual(items[0].summaryLine(now: now), "native build tab · cs-ios native build tab · building · 4m")
        XCTAssertEqual(items[1].elapsedText(now: now), "1m")
        XCTAssertEqual(items[1].holdReason, "waiting on founder")
    }

    func testWorkerRailIsAbsentWhenSnapshotHasNoActiveUnits() {
        let packet = buildStatusPacket(units: [
            .object(["id": .string("u1"), "state": .string("integrated")]),
            .object(["id": .string("u2"), "state": .string("failed")]),
        ])

        let items = BuildWorkerRailItem.items(from: [packet])

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(BuildWorkerRailLayout.placement(availableWidth: 1024, items: items), .absent)
    }

    func testWorkerRailActiveStateFilterIncludesReviewPendingForms() {
        let packet = buildStatusPacket(units: [
            .object(["id": .string("u1"), "state": .string("integrated")]),
            .object(["id": .string("u2"), "state": .string("verifying")]),
            .object(["id": .string("u3"), "state": .string("review_pending")]),
            .object(["id": .string("u4"), "state": .string("deploying")]),
            .object(["id": .string("u5"), "state": .string("recovering")]),
        ])

        let items = BuildWorkerRailItem.items(from: [packet])

        XCTAssertEqual(items.map(\.unitId), ["u2", "u3", "u4"])
        XCTAssertEqual(items.map(\.state), ["verifying", "review-pending", "deploying"])
    }

    func testWorkerElapsedFormatting() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))

        XCTAssertEqual(
            BuildWorkerRailItem.elapsedText(since: now.addingTimeInterval(-48), now: now),
            "48s"
        )
        XCTAssertEqual(
            BuildWorkerRailItem.elapsedText(since: now.addingTimeInterval(-4 * 60), now: now),
            "4m"
        )
        XCTAssertEqual(
            BuildWorkerRailItem.elapsedText(since: now.addingTimeInterval(-2 * 60 * 60), now: now),
            "2h"
        )
    }

    func testWorkerRailPlacementUsesCompactFallback() {
        let items = [
            BuildWorkerRailItem(planId: "plan-a", unitId: "u1", state: "building")
        ]
        let threshold = KStyle.buildWorkerRegularRailMinimumWidth

        XCTAssertEqual(BuildWorkerRailLayout.placement(availableWidth: threshold - 1, items: items), .compactSection)
        XCTAssertEqual(BuildWorkerRailLayout.placement(availableWidth: threshold, items: items), .regularRail)
        XCTAssertEqual(BuildWorkerRailLayout.placement(availableWidth: threshold, items: []), .absent)
    }

    func testBuildSnapshotPlansUnitsAndLanesFeedWorkerRail() throws {
        let frame = """
        event: build_snapshot
        data: {"generatedAt":"2026-07-04T10:00:00Z","plans":[{"id":"plan-wire","title":"wire build","status":"building","units":[{"unitId":"unit-wire","title":"ios rail","status":"review_pending"},{"id":"unit-done","title":"done","status":"integrated"}]}],"lanes":[{"id":"lane-wire","planId":"plan-wire","unitId":"unit-wire","state":"verifying","startedAt":"2026-07-04T09:58:00Z"}]}
        """
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))

        let event = try AGUIClient.decodeSSEFrame(frame)

        guard case .snapshot(let packets) = event else {
            return XCTFail("expected build snapshot")
        }
        let items = BuildWorkerRailItem.items(from: packets)
        XCTAssertEqual(items.map(\.unitId), ["unit-wire"])
        XCTAssertEqual(items.first?.summaryLine(now: now), "wire build · ios rail · review-pending · 2m")
    }

    @MainActor
    func testSubmitIntentAddsStreamAcknowledgement() async {
        let transport = jsonTransport(body: #"{"ok":true,"message":"drafting"}"#)
        let queueStore = tempInputQueueStore()
        defer { queueStore.clear() }
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) },
            inputQueueStore: queueStore
        )

        await model.submitIntent("add weekly build summary")

        XCTAssertEqual(model.intentAcknowledgementLines.map(\.text), [KCopy.buildIntentAcknowledgment])
        XCTAssertTrue(model.streamLines.map(\.text).contains(KCopy.buildIntentAcknowledgment))
    }

    func testBuildIntentPlaceholderNamesCreatePath() {
        XCTAssertEqual(KCopy.buildIntentPlaceholder, "describe what k should build…")
    }

    @MainActor
    func testStreamLinesRenderHistoryAndStatusPacketsInModelOrder() throws {
        let status = try decodeFixture("build-status")
        let model = BuildModel(baseURL: "http://daemon.test")

        model.apply(.snapshot([status]))

        XCTAssertEqual(model.streamLines.map(\.text), [
            "snapshot emitted on connect",
            "u4 lane entered build",
            "u1 integrated · green",
            "u4 building · active lane",
            "u5 held · waiting on founder",
            "lane-a building · codex",
            "lane-b recovering · backoff",
        ])
        XCTAssertEqual(model.streamLines.map(\.anchor), [
            .stream,
            .stream,
            .plan,
            .plan,
            .plan,
            .plan,
            .plan,
        ])
    }

    @MainActor
    func testWorkingAreaUsesOldestOpenCardAndMarksPrimaryOption() throws {
        let older = BuildCard(
            id: "card-older",
            kind: "scope",
            title: "Choose scope",
            options: [
                BuildCardOption(id: "narrow", label: "Narrow"),
                BuildCardOption(id: "wide", label: "Wide"),
            ],
            recommendation: "wide"
        )
        let newer = BuildCard(
            id: "card-newer",
            kind: "review",
            title: "Choose review depth",
            options: [
                BuildCardOption(id: "light", label: "Light"),
                BuildCardOption(id: "deep", label: "Deep"),
            ]
        )
        let model = BuildModel(baseURL: "http://daemon.test")

        model.apply(.snapshot([older.packet, newer.packet]))

        XCTAssertEqual(model.workingCards.map(\.id), ["card-older", "card-newer"])
        let presentation = BuildCardPresentation(card: try XCTUnwrap(model.workingCards.first))
        XCTAssertEqual(presentation.options.map(\.isPrimary), [false, true])
    }

    @MainActor
    func testKillOptionRequiresConfirmationBeforeSubmitting() throws {
        let card = BuildCard(
            id: "card-kill",
            title: "Stop lane",
            options: [
                BuildCardOption(id: "kill", label: "Kill", consequence: "Stop the lane."),
            ]
        )
        let recorder = RequestRecorder()
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport(body: #"{"ok":true}"#)) }
        )

        let result = model.choose(option: try XCTUnwrap(card.options.first), for: card)

        XCTAssertEqual(result, .confirmationRequired)
        XCTAssertEqual(model.pendingConfirmation, BuildPendingCardAnswer(cardId: "card-kill", optionId: "kill"))
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    @MainActor
    func testBuildSceneForegroundReconnectMovesToConnectingWithoutNetwork() {
        let transport = AGUIHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let stream = AsyncThrowingStream<String, Error> { _ in }
            return AGUILineResponse(response: response, lines: stream)
        }
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )

        model.enterForeground()

        XCTAssertEqual(model.connectionState.status, .connecting)
        model.stop()
    }

    @MainActor
    func testCameraPermissionDeniedModelStateUsesFallbackBackground() async {
        let model = CameraBackgroundModel(permissions: CameraPermissionClient(
            currentStatus: { .denied },
            requestAccess: { .authorized }
        ))

        XCTAssertTrue(model.fallbackBackgroundVisible)
        let directive = await model.tabAppeared()
        XCTAssertEqual(directive, .stop)
        XCTAssertTrue(model.isVisible)
        XCTAssertTrue(model.fallbackBackgroundVisible)
    }

    @MainActor
    func testSnapshotThenLiveOrderingAppliedByBuildModel() throws {
        let status = try decodeFixture("build-status")
        let card = try decodeFixture("build-card")
        let loopback = try decodeFixture("build-card-loopback")
        let model = BuildModel(baseURL: "http://daemon.test")

        model.apply(.packet(status))
        XCTAssertEqual(model.packets.map(\.id), ["build-status-1"])
        XCTAssertTrue(model.openCards.isEmpty)

        model.apply(.snapshot([status, card]))
        XCTAssertEqual(model.packets.map(\.id), ["build-status-1", "build-card-1"])
        XCTAssertEqual(model.openCards.map(\.id), ["build-card-1"])

        model.apply(.packet(loopback))
        XCTAssertEqual(model.packets.map(\.id), ["build-status-1", "build-card-1", "build-card-loopback-1"])
        XCTAssertEqual(model.openCards.map(\.id), ["build-card-1", "build-card-loopback-1"])
    }

    func testUnknownBuildFieldsAreTolerated() throws {
        let status = try decodeFixture("build-status")
        let card = try decodeFixture("build-card")
        let statusSummary = BuildStatusSummary(packet: status)
        let cardSummary = BuildCardSummary(packet: card)

        XCTAssertEqual(status.fields?["futureNestedBuildField"]?.objectValue?["ignoredByOldClients"], .bool(true))
        XCTAssertEqual(card.fields?["futureCardField"]?.objectValue?["safeToIgnore"], .bool(true))
        XCTAssertEqual(statusSummary.extraFields["futureNestedBuildField"]?.objectValue?["ignoredByOldClients"], .bool(true))
        XCTAssertEqual(cardSummary.extraFields["futureCardField"]?.objectValue?["safeToIgnore"], .bool(true))
    }

    func testEvidenceKindRenderingTable() {
        let entries = [
            BuildEvidenceEntry(id: "gate", kind: "gate-output", title: "Gate", text: "xcodebuild test"),
            BuildEvidenceEntry(id: "text", kind: "text", title: "Note", text: "reviewed docs"),
            BuildEvidenceEntry(id: "transcript", kind: "transcript", title: "Transcript", text: "k: done"),
            BuildEvidenceEntry(id: "image", kind: "image", title: "Screenshot", imageReference: "/proof.png"),
        ]

        let presentations = entries.map(BuildEvidenceEntryPresentation.init)

        XCTAssertEqual(presentations.map(\.renderKind), [.gateOutput, .text, .transcript, .image])
        XCTAssertEqual(presentations.map(\.usesMonospacedBody), [true, false, false, false])
        XCTAssertEqual(presentations.map(\.title), ["gate", "note", "transcript", "screenshot"])
    }

    func testExpandedBuildCopyNeverUsesPayloadIdentifiersAsFallbacks() {
        let entry = BuildEvidenceEntry(
            id: "unit-2026-08-10-build-copy",
            kind: "line-stop",
            title: nil,
            path: "plan-2026-08-10-build-copy.md"
        )
        let presentation = BuildEvidenceEntryPresentation(entry: entry)
        XCTAssertEqual(presentation.title, "evidence")
        XCTAssertEqual(presentation.body, "")
        XCTAssertNil(presentation.metadata)

        let trust = BuildTrustPairPresentation(
            pair: BuildTrustPair(
                id: "lane-2026-08-10-build-copy",
                verdict: "lane-2026-08-10-build-copy",
                decision: "unit-2026-08-10-build-copy",
                source: "plan-2026-08-10-build-copy"
            )
        )
        XCTAssertEqual(trust.verdictText, "verification")
        XCTAssertEqual(trust.decisionText, "no decision")
        XCTAssertNil(trust.metaText)
    }

    @MainActor
    func testLearnedDecisionFlowApprovesPendingEntry() async throws {
        let recorder = RequestRecorder()
        let transport = recorder.transport(responses: [
            (200, #"{"pending":[{"id":"learned-1","text":"prefer quiet proof readers"}],"approved":[]}"#),
            (200, #"{"ok":true,"entry":{"id":"learned-1","text":"prefer quiet proof readers","status":"approved"}}"#),
        ])
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) }
        )

        await model.loadLearned()
        let pending = try XCTUnwrap(model.learnedState.feed.nextPending)

        await model.submitLearnedDecision(entry: pending, decision: .approve)

        XCTAssertTrue(model.learnedState.feed.pending.isEmpty)
        XCTAssertEqual(model.learnedState.feed.approved.map(\.id), ["learned-1"])
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/api/build/learned", "/api/build/learned/decision"])
        let body = try XCTUnwrap(recorder.requests.last?.httpBody)
        let bodyText = String(data: body, encoding: .utf8)
        XCTAssertTrue(bodyText?.contains(#""id":"learned-1""#) == true)
        XCTAssertTrue(bodyText?.contains(#""decision":"approve""#) == true)
    }

    func testTrustPairProjection() throws {
        let data = Data("""
        {
          "decisionSignalCount": 4,
          "pairs": [
            {
              "id": "pair-1",
              "verdict": "likely green",
              "decision": "approved",
              "signal": "match",
              "unitId": "i2"
            },
            {
              "id": "pair-2",
              "verdict": "risky",
              "decision": "discarded",
              "signal": "miss"
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(BuildTrustResponse.self, from: data)
        let rows = response.presentations

        XCTAssertEqual(response.decisionSignalCount, 4)
        XCTAssertEqual(rows.map(\.verdictText), ["likely green", "risky"])
        XCTAssertEqual(rows.map(\.decisionText), ["approved", "discarded"])
        XCTAssertEqual(rows.first?.metaText, "match · i2")
    }

    func testBuildSnapshotSSEFrameDecodes() throws {
        let frame = """
        event: snapshot
        data: {"packets":[{"id":"build-status-inline","viewType":"build.status","text":"Inline","provenance":{"surface":"build"},"frontierExcluded":false}]}
        """

        let event = try AGUIClient.decodeSSEFrame(frame)

        guard case .snapshot(let packets) = event else {
            return XCTFail("expected snapshot, got \(String(describing: event))")
        }
        XCTAssertEqual(packets.map(\.id), ["build-status-inline"])
    }

    func testApproveAllDisclosureSummarizesAnswerableKindsAndHardestStakes() throws {
        let cards = BuildNeedsYouFixture.packets(for: .mixed).compactMap(BuildCard.init(packet:))
        let summary = BuildApproveAllSummary(cards: cards)

        XCTAssertEqual(summary.answerableCount, 7)
        XCTAssertEqual(summary.skippedCount, 2)
        XCTAssertEqual(
            summary.countLine,
            "3 × a protected rule changes — your call · 1 × start this plan? · 2 × stuck on setup — what now? · 1 × checks failed — what now?"
        )
        XCTAssertEqual(summary.kinds.map(\.lean), [
            "k leans keep the floor",
            "k leans start the plan",
            "k leans continue setup",
            "k leans inspect the checks",
        ])
        XCTAssertEqual(summary.hardestStakes, "hard to undo after integration")
    }

    func testApproveAllUsesFounderAcceptLanguage() {
        XCTAssertEqual(KCopy.buildApproveAllAct, "accept all · k's lean")
        XCTAssertEqual(KCopy.buildApproveAllConfirm, "accept all")
        XCTAssertEqual(
            KCopy.buildApproveAllResult(answered: 7, skipped: 2, failed: 0),
            "7 accepted · 2 waiting their turn"
        )
    }

    @MainActor
    func testBuildComposerStatusNamesUnreachableDaemon() {
        let connection = KConnectionStateModel(status: .offlineRetrying)

        XCTAssertEqual(
            BuildModel.composerStatusText(for: connection, isStale: false, stalenessText: nil),
            "daemon unreachable · tailnet needed"
        )
    }

    func testBuildComposerDoesNotAliasQueuedReceiptAsDaemonStatus() {
        XCTAssertNil(
            BuildReportComposer.inlineStatusText(disabledReason: nil, state: .queued)
        )
        XCTAssertEqual(
            BuildReportComposer.inlineStatusText(
                disabledReason: KCopy.tailnetNeeded,
                state: .queued
            ),
            KCopy.tailnetNeeded
        )
        XCTAssertEqual(
            BuildReportComposer.inlineStatusText(disabledReason: nil, state: .failed("offline")),
            "answer failed · retry"
        )
    }

    @MainActor
    func testApproveAllAnswersRecommendationsSeriallyWithAnswerText() async throws {
        let cards = BuildNeedsYouFixture.packets(for: .mixed).compactMap(BuildCard.init(packet:))
        let answerable = cards.filter(\.isBulkAnswerable)
        let recorder = RequestRecorder(
            responses: Array(repeating: (200, #"{"ok":true}"#), count: answerable.count)
        )
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            arguments: ["K"]
        )
        model.apply(.snapshot(cards.map(\.packet)))

        model.beginApproveAll()
        await model.confirmApproveAll()

        guard case .finished(let result) = model.approveAllState else {
            return XCTFail("bulk act did not finish")
        }
        XCTAssertEqual(result, BuildApproveAllResult(answered: 7, skipped: 2, failed: 0))
        XCTAssertEqual(recorder.requests.count, answerable.count)
        XCTAssertEqual(
            recorder.requests.map { $0.url?.path },
            Array(repeating: AGUIClient.buildCardAnswerPath, count: answerable.count)
        )

        for (request, card) in zip(recorder.requests, answerable) {
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(object["cardId"] as? String, card.id)
            XCTAssertEqual(object["optionId"] as? String, card.recommendation)
            XCTAssertEqual(object["answerText"] as? String, BuildNeedsYouFixture.answerText)
        }
    }

    @MainActor
    func testFixtureFailureStaysOnCardAndRetryCanAnswerRemainder() async throws {
        let model = BuildModel(
            baseURL: "http://127.0.0.1:9",
            arguments: ["K", BuildNeedsYouFixture.launchArgument, "failure"]
        )
        model.start()
        let card = try XCTUnwrap(model.openCards.first)

        model.beginApproveAll()
        await model.confirmApproveAll()
        XCTAssertEqual(model.cardErrorText(for: card), "answer failed · retry")
        XCTAssertTrue(model.openCards.contains(where: { $0.id == card.id }))

        model.beginApproveAll()
        await model.confirmApproveAll()
        XCTAssertTrue(model.openCards.isEmpty)
    }

    private func decodeFixture(_ name: String) throws -> ViewPacket {
        let bundle = Bundle(for: Self.self)
        let url = [
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Tests/Fixtures"),
            bundle.url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }.first

        let fixtureURL = try XCTUnwrap(url, "Missing fixture \(name).json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(ViewPacket.self, from: data)
    }

    private func answerBody(card: BuildCard) -> String {
        #"{"ok":true,"card":\#(cardJSON(card))}"#
    }

    private func cardJSON(_ card: BuildCard) -> String {
        let data = try! JSONEncoder().encode(card)
        return String(data: data, encoding: .utf8)!
    }

    private func packetJSON(_ packet: ViewPacket) -> String {
        let data = try! JSONEncoder().encode(packet)
        return String(data: data, encoding: .utf8)!
    }

    private func buildStatusPacket(
        units: [ViewPacketJSONValue],
        lanes: [ViewPacketJSONValue] = []
    ) -> ViewPacket {
        ViewPacket(
            id: "build-status-test-\(UUID().uuidString)",
            viewType: "build.status",
            text: "test build",
            fields: [
                "plan": .object(["id": .string("plan-test"), "title": .string("test build")]),
                "units": .array(units),
                "lanes": .array(lanes),
            ],
            provenance: ["surface": .string("build")],
            frontierExcluded: true
        )
    }

    private func jsonTransport(status: Int = 200, body: String) -> AGUIHTTPTransport {
        RequestRecorder().transport(status: status, body: body)
    }

    private func tempSnapshotStore() -> BuildSnapshotCacheStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("build-snapshot-\(UUID().uuidString).json")
        return BuildSnapshotCacheStore(fileURL: url)
    }

    private func tempInputQueueStore() -> BuildInputQueueStore {
        BuildInputQueueStore(key: "build-input-\(UUID().uuidString)")
    }
}

final class KTabShellTests: XCTestCase {
    func testTabStripModelUsesLowercaseTitlesAndActiveOpacity() {
        let items = KTabStripModel.items(active: .build)

        XCTAssertEqual(items.map(\.title), ["cadence", "chat", "build", "mind", "bio", "admin"])
        XCTAssertEqual(items.map(\.isActive), [false, false, true, false, false, false])
        XCTAssertEqual(items.map(\.showsDot), [false, false, false, false, false, false])
        XCTAssertEqual(items.map(\.textOpacity), [
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.primaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
        ])
    }

    func testLaunchArgumentSelectsInitialTab() {
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K", "-tab", "build"], environment: [:]),
            .build
        )
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K", "-tab=mind"], environment: [:]),
            .mind
        )
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K", "-tab=bio"], environment: [:]),
            .bio
        )
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K", "-tab=admin"], environment: [:]),
            .admin
        )
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K"], environment: ["K_TAB": "chat"]),
            .chat
        )
        XCTAssertEqual(
            KInitialTabSelection.resolve(arguments: ["K"], environment: [:]),
            .cadence
        )
    }

#if DEBUG
    func testLaunchArgumentSelectsHiddenShowcaseRoute() {
        XCTAssertEqual(
            KInitialTabSelection.resolveRoute(arguments: ["K", "-tab", "showcase"], environment: [:]),
            .showcase
        )
        XCTAssertEqual(
            KInitialTabSelection.resolveRoute(arguments: ["K", "-tab=showcase"], environment: [:]),
            .showcase
        )
    }
#endif

    func testShowcaseIsAbsentFromVisibleTabStripItems() {
        let items = KTabStripModel.items(active: .cadence)

        XCTAssertEqual(items.map(\.title), ["cadence", "chat", "build", "mind", "bio", "admin"])
        XCTAssertFalse(items.map(\.title).contains("showcase"))
        XCTAssertFalse(KAppTab.allCases.map(\.rawValue).contains("showcase"))
    }

    func testTabStripFitsIPhone15WidthAtDynamicTypeExtraLarge() {
        let availableWidth: CGFloat = 393
        let items = KTabStripModel.items(
            active: .cadence,
            cadenceNeedsAttention: true,
            chatHasUnread: true,
            openBuildCards: 1,
            unjudgedMindOutputs: 1,
            adminDueTodayItems: 1
        )
        let requiredWidth = KTabStripLayout.requiredWidth(
            for: items,
            availableWidth: availableWidth,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraLarge)
        )
        let metrics = KStyle.tabStripMetrics(availableWidth: availableWidth)

        XCTAssertLessThanOrEqual(requiredWidth, availableWidth)
        XCTAssertEqual(metrics.itemSpacing, KStyle.tabCompactItemSpacing)
        XCTAssertEqual(metrics.horizontalPadding, KStyle.tabCompactHorizontalPadding)
        XCTAssertEqual(metrics.labelTracking, KStyle.tabCompactTracking)
        XCTAssertEqual(metrics.labelMinimumScaleFactor, KStyle.tabLabelMinimumScaleFactor)
    }
}

final class ChatCompositionTests: XCTestCase {
    func testEmptyStateCopyIsInKLanguage() {
        XCTAssertEqual(
            ChatEmptyStatePresentation.text,
            "k knows you.\nask what is open, what matters, what to attend to."
        )
    }

    func testStreamLineAlignmentModelSeparatesKAndFounder() throws {
        let date = Date(timeIntervalSince1970: 3_600)
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let k = ChatMessagePresentation(message: Message(role: .k, text: "focus", createdAt: date))
        let founder = ChatMessagePresentation(message: Message(role: .you, text: "what now", createdAt: date))

        XCTAssertEqual(k.speaker, "k")
        XCTAssertEqual(k.alignment, .leading)
        XCTAssertEqual(k.textOpacity, KStyle.primaryTextOpacity)
        XCTAssertEqual(k.timestampText(timeZone: timeZone), "01:00")

        XCTAssertEqual(founder.speaker, "founder")
        XCTAssertEqual(founder.alignment, .trailing)
        // Mock v35 contrast law: the founder bubble carries bright lead ink.
        XCTAssertEqual(founder.textOpacity, KStyle.chatLeadOpacity)
        XCTAssertEqual(founder.timestampText(timeZone: timeZone), "01:00")
    }

    func testChatUnreadUsesLatestKnownKMessageTimestamp() throws {
        let old = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T08:00:00Z"))
        let latest = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T09:00:00Z"))
        let messages = [
            Message(role: .you, text: "ignore founder timestamp", createdAt: latest.addingTimeInterval(60)),
            Message(role: .k, text: "seen", createdAt: old),
            Message(role: .k, text: "new", createdAt: latest),
        ]

        XCTAssertEqual(ChatUnreadLogic.latestKMessageTimestamp(in: messages), latest)
        XCTAssertTrue(ChatUnreadLogic.hasUnread(messages: messages, lastSeen: old))
        XCTAssertFalse(ChatUnreadLogic.hasUnread(messages: messages, lastSeen: latest))
    }

    func testChatMessageAccessibilityCombinesSenderAndSpokenText() {
        XCTAssertEqual(
            ChatMessageAccessibility.label(speaker: "founder", text: "what now\nnext line"),
            "founder, what now. next line"
        )
        XCTAssertEqual(
            ChatMessageAccessibility.label(speaker: "k", text: " \n "),
            "k, answer pending"
        )
    }
}

private final class RequestRecorder {
    private(set) var requests: [URLRequest] = []
    private let configuredResponses: [(Int, String)]

    init(responses: [(Int, String)] = []) {
        configuredResponses = responses
    }

    var transport: AGUIHTTPTransport {
        transport(responses: configuredResponses)
    }

    func transport(status: Int = 200, body: String) -> AGUIHTTPTransport {
        transport(responses: [(status, body)])
    }

    func transport(responses: [(Int, String)]) -> AGUIHTTPTransport {
        var remaining = responses
        return AGUIHTTPTransport { request in
            self.requests.append(request)
            let next = remaining.isEmpty ? (200, "") : remaining.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: next.0,
                httpVersion: nil,
                headerFields: nil
            )!
            let stream = AsyncThrowingStream<String, Error> { continuation in
                if !next.1.isEmpty {
                    for line in next.1.split(separator: "\n", omittingEmptySubsequences: false) {
                        continuation.yield(String(line))
                    }
                }
                continuation.finish()
            }
            return AGUILineResponse(response: response, lines: stream)
        }
    }
}
