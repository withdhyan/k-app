import XCTest
@testable import K

final class ViewPacketTests: XCTestCase {
    func testGenericTextDecodesAndRenders() throws {
        let packet = try decodeFixture("generic-text")

        XCTAssertEqual(packet.viewType, "generic.text")
        XCTAssertEqual(packet.text, "Hello from a ViewPacket.")
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericText)
        XCTAssertEqual(ViewPacketRenderer.visibleTextSequence(for: packet), ["Hello from a ViewPacket."])
    }

    func testGenericTableRenders() throws {
        let packet = try decodeFixture("generic-table")
        let table = ViewPacketTable(packet: packet)

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericTable)
        XCTAssertEqual(table.columns, ["Name", "Status"])
        XCTAssertEqual(table.rows, [
            ["ViewPacket", "ready"],
            ["Renderer", "native"],
        ])
        XCTAssertTrue(ViewPacketRenderer.visibleTextSequence(for: packet).contains("native"))
    }

    func testUnknownViewTypeFallsBackToText() throws {
        let packet = try decodeFixture("unknown-view-type")

        XCTAssertEqual(packet.viewType, "future.panel")
        XCTAssertEqual(packet.text, "Fallback body.")
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericText)
        XCTAssertEqual(ViewPacketRenderer.visibleTextSequence(for: packet), ["Fallback body."])
    }

    func testTreeRendersChildrenNestedInOrder() throws {
        let packet = try decodeFixture("tree")

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericCard)
        XCTAssertEqual(packet.children.map(\.text), ["First child", "Second child"])
        XCTAssertEqual(packet.children.map { ViewPacketRenderer.branch(for: $0) }, [.genericText, .loopEvidence])
        XCTAssertEqual(
            ViewPacketRenderer.visibleTextSequence(for: packet),
            ["Parent packet", "First child", "Second child", "2 pieces of evidence · details on the desk"]
        )
    }

    func testHeldPacketRespectsSurfaceDecision() throws {
        let packet = try decodeFixture("held")
        let visible = ViewPacketRenderer.visibleTextSequence(for: packet).joined(separator: "\n")

        XCTAssertTrue(packet.frontierExcluded)
        XCTAssertTrue(packet.shouldRenderHeldState)
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .held)
        XCTAssertTrue(visible.contains("surface held"))
        XCTAssertFalse(visible.contains("Raw held content"))
    }

    func testPacketWithActionExposesAffordanceFlag() throws {
        let packet = ViewPacket(
            id: "action-source",
            viewType: "preview.tool",
            text: "Read focus memory",
            action: ViewPacketAction(
                kind: "memory.read",
                target: "read-focus",
                id: "read-focus",
                intent: "memory.read",
                args: ["key": .string("focus")]
            ),
            provenance: ["surface": .string("tool"), "lane": .string("deliberate")],
            frontierExcluded: false
        )

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .preview)
        XCTAssertTrue(ViewPacketRenderer.exposesActionAffordance(for: packet))
        XCTAssertEqual(packet.action?.invokeActionId, "read-focus")
        XCTAssertEqual(packet.action?.invokeIntent, "memory.read")
        XCTAssertEqual(packet.action?.invokeArgs["key"], .string("focus"))
    }

    func testHeldActionResultPacketRendersHeldState() throws {
        let packet = try JSONDecoder().decode(ViewPacket.self, from: Data("""
        {
          "id": "held-action-result",
          "viewType": "preview.tool",
          "text": "I'm holding 1 action for your review (memory.write).",
          "fields": {
            "status": "held",
            "packetId": "action-source",
            "actionId": "write-memory",
            "intent": "memory.write",
            "held": [{ "id": "memory.write", "reason": "irreversible" }],
            "reason": "irreversible"
          },
          "provenance": {
            "surface": "tool",
            "lane": "deliberate",
            "plane": "agent",
            "module": "agui-action"
          },
          "frontierExcluded": false
        }
        """.utf8))
        let visible = ViewPacketRenderer.visibleTextSequence(for: packet).joined(separator: "\n")

        XCTAssertTrue(packet.shouldRenderHeldState)
        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .held)
        XCTAssertFalse(ViewPacketRenderer.exposesActionAffordance(for: packet))
        XCTAssertTrue(visible.contains("surface held"))
        XCTAssertTrue(visible.contains("I'm holding 1 action for your review (memory.write)."))
    }

    func testPacketWithoutActionKeepsRenderModelUnchanged() throws {
        let packet = try decodeFixture("generic-text")

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericText)
        XCTAssertEqual(ViewPacketRenderer.visibleTextSequence(for: packet), ["Hello from a ViewPacket."])
        XCTAssertFalse(ViewPacketRenderer.exposesActionAffordance(for: packet))
    }

    func testRendererClampsRequestedFocalInterruptionToPeripheral() {
        let packet = ViewPacket(
            id: "focal-build-status",
            viewType: "build.status",
            text: "Build wants focus",
            provenance: ["interruptionClass": .string("focal")],
            frontierExcluded: false
        )

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .buildStatus)
        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: packet), .peripheral)
    }

    func testRendererKeepsAmbientCatalogCeilingForGenericText() {
        let packet = ViewPacket(
            id: "focal-generic-text",
            viewType: "generic.text",
            text: "Ambient text",
            fields: ["interruptionClass": .string("focal")],
            frontierExcluded: false
        )

        XCTAssertEqual(ViewPacketRenderer.branch(for: packet), .genericText)
        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: packet), .ambient)
    }

    func testRenderPolicyDiffersForAmbientAndPeripheralPackets() {
        let ambient = ViewPacket(
            id: "ambient-text",
            viewType: "generic.text",
            text: "Ambient text",
            provenance: ["interruptionClass": .string("peripheral")],
            frontierExcluded: false
        )
        let peripheral = ViewPacket(
            id: "peripheral-build-status",
            viewType: "build.status",
            text: "Runner active",
            provenance: ["interruptionClass": .string("peripheral")],
            frontierExcluded: false
        )

        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: ambient), .ambient)
        XCTAssertEqual(
            ViewPacketRenderer.renderPolicy(for: ambient),
            ViewPacketRenderPolicy(
                interruptionClass: .ambient,
                usesFadeTransition: false,
                animatesChanges: false,
                dimsSiblings: false
            )
        )
        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: peripheral), .peripheral)
        XCTAssertEqual(
            ViewPacketRenderer.renderPolicy(for: peripheral),
            ViewPacketRenderPolicy(
                interruptionClass: .peripheral,
                usesFadeTransition: true,
                animatesChanges: true,
                dimsSiblings: true
            )
        )
    }

    func testChatWorkerPacketDecodesFullAbsentAndPartialShapes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let full = ViewPacket(
            id: "worker-1",
            viewType: "chat.worker",
            fields: [
                "taskId": .string("task-1"),
                "label": .string("researching pricing"),
                "state": .string("running"),
                "stepText": .string("reading source notes"),
                "startedAt": .string("2026-07-10T11:58:00Z"),
                "branchId": .string("branch-1"),
            ],
            provenance: ["surface": .string("chat")],
            frontierExcluded: false
        )
        let partial = ViewPacket(
            id: "worker-2",
            viewType: "chat.worker",
            fields: ["taskId": .string("task-2")],
            frontierExcluded: false
        )
        let absent = ViewPacket(id: "text", viewType: "generic.text", text: "ordinary", frontierExcluded: false)

        let worker = try XCTUnwrap(ChatWorkerPacket(full))
        XCTAssertEqual(worker.taskId, "task-1")
        XCTAssertEqual(worker.stateLine(now: now), "k is researching pricing · started 2m ago")
        XCTAssertEqual(worker.stepText, "reading source notes")
        XCTAssertEqual(worker.branchID, "branch-1")
        XCTAssertEqual(ViewPacketRenderer.branch(for: full), .chatWorker)
        XCTAssertTrue(ViewPacketRenderer.visibleTextSequence(for: full).contains("reading source notes"))

        let partialWorker = try XCTUnwrap(ChatWorkerPacket(partial))
        XCTAssertEqual(partialWorker.label, "background work")
        XCTAssertEqual(partialWorker.state, "working")
        XCTAssertNil(partialWorker.stepText)
        XCTAssertNil(ChatWorkerPacket(absent))
    }

    func testChatWorkerPacketUpdatesInPlaceByTaskId() throws {
        var messages = [
            Message(role: .you, text: "go research this"),
            Message(role: .k, text: ""),
        ]
        let first = ViewPacket(
            id: "worker-first",
            viewType: "chat.worker",
            fields: [
                "taskId": .string("task-same"),
                "label": .string("researching the market"),
                "state": .string("running"),
                "stepText": .string("starting"),
            ],
            frontierExcluded: false
        )
        let second = ViewPacket(
            id: "worker-second",
            viewType: "chat.worker",
            fields: [
                "taskId": .string("task-same"),
                "label": .string("researching the market"),
                "state": .string("running"),
                "stepText": .string("reading sources"),
            ],
            frontierExcluded: false
        )

        XCTAssertEqual(ChatWorkerThreadReducer.upsert(first, in: &messages, preferredIndex: 1), 1)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].packet?.id, "worker-first")

        XCTAssertEqual(ChatWorkerThreadReducer.upsert(second, in: &messages, preferredIndex: nil), 1)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].packet?.id, "worker-second")
        XCTAssertTrue(messages[1].text.contains("reading sources"))
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
}

final class ChatThreadStoreTests: XCTestCase {
    func testSaveLoadRoundTripPreservesRolesTextAndOrder() throws {
        let (store, _) = try makeStore()
        let syncedAt = Date(timeIntervalSince1970: 2_345)
        let messages = [
            Message(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), role: .you, text: "What am I focused on?"),
            Message(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
                role: .k,
                text: "You are focused on founder-felt memory.",
                packet: ViewPacket(
                    id: "packet-1",
                    viewType: "generic.text",
                    text: "You are focused on founder-felt memory.",
                    provenance: ["surface": .string("sovereign")],
                    frontierExcluded: false
                )
            ),
        ]

        store.save(messages, syncedAt: syncedAt)
        let loaded = store.load()
        let entry = try XCTUnwrap(store.loadEntry())

        XCTAssertEqual(loaded, messages)
        XCTAssertEqual(loaded.map(\.role), [.you, .k])
        XCTAssertEqual(loaded.map(\.text), messages.map(\.text))
        XCTAssertEqual(entry.lastSyncedAt, syncedAt)
    }

    func testCorruptFileLoadsEmptyWithoutThrowing() throws {
        let (store, fileURL) = try makeStore()
        try Data("this is not a stored thread".utf8).write(to: fileURL)

        XCTAssertEqual(store.load(), [])
    }

    func testSaveEnforcesNewestMessageCap() throws {
        let (store, _) = try makeStore(limit: 5)
        let messages = (0..<12).map { index in
            Message(role: index.isMultiple(of: 2) ? .you : .k, text: "message-\(index)")
        }

        store.save(messages)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.map(\.text), messages.suffix(5).map(\.text))
    }

    private func makeStore(limit: Int = ChatThreadStore.defaultLimit) throws -> (ChatThreadStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KedarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("chat-thread.json", isDirectory: false)
        return (ChatThreadStore(fileURL: fileURL, limit: limit), fileURL)
    }
}

final class ViewPacketPatchTests: XCTestCase {
    private func decodePacket(_ json: String) throws -> ViewPacket {
        try JSONDecoder().decode(ViewPacket.self, from: Data(json.utf8))
    }

    private func decodePatch(_ json: String) throws -> ViewPacketPatch {
        try JSONDecoder().decode(ViewPacketPatch.self, from: Data(json.utf8))
    }

    private var basePacketJSON: String {
        """
        {"id":"p1","viewType":"generic.text","text":"Answer",
         "fields":{"subject":"old subject"},
         "children":[{"id":"c1","viewType":"generic.text","text":"Existing child",
                      "provenance":{"surface":"public"},"frontierExcluded":false}],
         "provenance":{"surface":"public"},"frontierExcluded":false}
        """
    }

    func testSetPatchUpdatesOnlyTargetField() throws {
        let packet = try decodePacket(basePacketJSON)
        let patch = try decodePatch(
            #"{"targetId":"p1","ops":[{"op":"set","field":"fields.subject","value":"new subject"}]}"#
        )

        let patched = applyPacketPatch(patch, to: packet)

        XCTAssertEqual(patched.fields?["subject"]?.stringValue, "new subject")
        XCTAssertEqual(patched.text, "Answer")
        XCTAssertEqual(patched.children.map(\.text), ["Existing child"])
        XCTAssertEqual(patched.viewType, "generic.text")
    }

    func testAppendChildPatchAddsInOrderAndIsIdempotent() throws {
        let packet = try decodePacket(basePacketJSON)
        let patch = try decodePatch(
            """
            {"targetId":"p1","ops":[{"op":"append_child","child":
              {"id":"c2","viewType":"preview.web","text":"Primary source",
               "provenance":{"surface":"web"},"frontierExcluded":false}}]}
            """
        )

        let patched = applyPacketPatch(patch, to: packet)
        let patchedAgain = applyPacketPatch(patch, to: patched)

        XCTAssertEqual(patched.children.map(\.text), ["Existing child", "Primary source"])
        XCTAssertEqual(patchedAgain, patched)
    }

    func testPatchToUnknownPacketIdIsIgnored() throws {
        let packet = try decodePacket(basePacketJSON)
        let patch = try decodePatch(
            #"{"targetId":"nope","ops":[{"op":"set","field":"text","value":"hijacked"}]}"#
        )
        var logged: [String] = []

        let patched = applyPacketPatch(patch, to: packet, logger: { logged.append($0) })

        XCTAssertEqual(patched, packet)
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("unknown packet id nope"))
    }

    func testUnknownOpDecodesWithoutThrowingAndAppliesAsNoOp() throws {
        let packet = try decodePacket(basePacketJSON)
        let patch = try decodePatch(
            #"{"targetId":"p1","ops":[{"op":"explode","field":"text","value":"boom"}]}"#
        )

        let patched = applyPacketPatch(patch, to: packet)

        XCTAssertEqual(patched, packet)
    }

    func testSSEFrameDecodesPacketPatchEvent() throws {
        let frame = "event: packet_patch\ndata: {\"targetId\":\"p1\",\"ops\":[{\"op\":\"set\",\"field\":\"text\",\"value\":\"filled\"}]}"

        let event = try AGUIClient.decodeSSEFrame(frame)

        guard case .patch(let patch) = event else {
            return XCTFail("expected .patch, got \(String(describing: event))")
        }
        XCTAssertEqual(patch.targetId, "p1")
        let packet = try decodePacket(basePacketJSON)
        XCTAssertEqual(applyPacketPatch(patch, to: packet).text, "filled")
    }
}

final class AGUIClientActionInvokeTests: XCTestCase {
    func testInvokeActionPostsDaemonPayloadShape() async throws {
        let source = ViewPacket(
            id: "action-source",
            viewType: "preview.tool",
            text: "Read focus memory",
            action: ViewPacketAction(
                kind: "memory.read",
                target: "read-focus",
                id: "read-focus",
                intent: "memory.read",
                args: ["key": .string("focus")]
            ),
            provenance: ["surface": .string("tool"), "lane": .string("deliberate")],
            frontierExcluded: false
        )
        var capturedRequest: URLRequest?
        let transport = AGUIHTTPTransport { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: response, lines: Self.stream(lines: [
                "event: done",
                #"data: {"ok":true,"status":"ok","packetId":"result","action":{"packetId":"action-source","actionId":"read-focus","intent":"memory.read"},"steps":1,"held":[],"executed":[]}"#,
                "",
            ]))
        }

        let client = AGUIClient(baseURL: "http://daemon.test", transport: transport)
        let outcome = try await client.invokeAction(packet: source, onEvent: { _ in })
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let action = try XCTUnwrap(json["action"] as? [String: Any])
        let args = try XCTUnwrap(action["args"] as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/agui/message")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(json["type"] as? String, "action-invoke")
        XCTAssertEqual(json["packetId"] as? String, "action-source")
        XCTAssertNil(json["message"])
        XCTAssertEqual(action["id"] as? String, "read-focus")
        XCTAssertEqual(action["intent"] as? String, "memory.read")
        XCTAssertEqual(args["key"] as? String, "focus")
        XCTAssertEqual(outcome.packetId, "result")
        XCTAssertFalse(outcome.held)
    }

    private static func stream(lines: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}

extension ViewPacketPatchTests {
    func testChainedPatchesApplyAcrossResultIdReKeying() throws {
        let packet = try JSONDecoder().decode(ViewPacket.self, from: Data("""
        {"id":"aaaaaaaaaaaaaaaaaaaaaaaa","viewType":"generic.text","text":"You",
         "provenance":{"surface":"verbatim-chat"},"frontierExcluded":true}
        """.utf8))
        let patch1 = try JSONDecoder().decode(ViewPacketPatch.self, from: Data(
            #"{"targetId":"aaaaaaaaaaaaaaaaaaaaaaaa","resultId":"bbbbbbbbbbbbbbbbbbbbbbbb","ops":[{"op":"set","field":"text","value":"You're"}]}"#.utf8))
        let patch2 = try JSONDecoder().decode(ViewPacketPatch.self, from: Data(
            #"{"targetId":"bbbbbbbbbbbbbbbbbbbbbbbb","resultId":"cccccccccccccccccccccccc","ops":[{"op":"set","field":"text","value":"You're preoccupied"}]}"#.utf8))

        let once = applyPacketPatch(patch1, to: packet)
        let twice = applyPacketPatch(patch2, to: once)

        XCTAssertEqual(once.id, "bbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertEqual(twice.id, "cccccccccccccccccccccccc")
        XCTAssertEqual(twice.text, "You're preoccupied")
    }
}

extension ViewPacketTests {
    func testMentraCardViewTypesDispatchToDistinctBranches() {
        let packets = [
            mentraCardPacket(viewType: "card.cue"),
            mentraCardPacket(viewType: "card.body"),
            mentraCardPacket(viewType: "card.translation"),
        ]

        XCTAssertEqual(
            packets.map { ViewPacketRenderer.branch(for: $0) },
            [.cardCue, .cardBody, .cardTranslation]
        )
    }

    func testMentraCardPresentationReadsFaceDisclosureActionsAndQueuedCount() throws {
        var packet = mentraCardPacket(viewType: "card.cue")
        packet.fields?["queuedCueCount"] = .number(2)
        let card = try XCTUnwrap(ViewPacketCardPresentation(packet: packet))

        XCTAssertFalse(card.usesFallbackFace)
        XCTAssertTrue(card.announcesArrival)
        XCTAssertEqual(card.face.anchor.displayText, "from jul 11 · calling it K")
        XCTAssertEqual(card.face.ask, "keep this cue?")
        XCTAssertEqual(card.queuedCueCount, 2)
        XCTAssertEqual(card.disclosure.brief?.whyNow, "the name keeps returning")
        XCTAssertEqual(card.disclosure.evidenceLines, ["naming decision"])
        XCTAssertEqual(card.accept.consequence, "records the cue as useful")
        XCTAssertEqual(card.dismiss.consequence, "records the cue as not useful")

        let accepted = try XCTUnwrap(card.selectedPacket(.accept, from: packet))
        let dismissed = try XCTUnwrap(card.selectedPacket(.dismiss, from: packet))
        XCTAssertEqual(accepted.action?.invokeActionId, "keep-card")
        XCTAssertEqual(accepted.action?.invokeArgs["disposition"], .string("accepted"))
        XCTAssertEqual(dismissed.action?.invokeActionId, "dismiss-card")
        XCTAssertEqual(dismissed.action?.invokeArgs["disposition"], .string("dismissed"))

        packet.fields?["queuedCueCount"] = .number(2.5)
        XCTAssertNil(ViewPacketCardPresentation(packet: packet)?.queuedCueCount)

        packet.fields?["status"] = .string("pending")
        XCTAssertFalse(ViewPacketCardPresentation(packet: packet)?.announcesArrival ?? true)
    }

    func testMentraCardFaceBudgetIsStrictlyUnder120CharactersAndNeverTruncates() throws {
        let valid = CardFace(
            anchor: CardFaceAnchor(style: "words", text: String(repeating: "a", count: 118)),
            ask: "b"
        )
        let invalid = CardFace(
            anchor: CardFaceAnchor(style: "words", text: String(repeating: "a", count: 119)),
            ask: "b"
        )
        XCTAssertTrue(ViewPacketCardPresentation.isWithinGlanceableBudget(valid))
        XCTAssertFalse(ViewPacketCardPresentation.isWithinGlanceableBudget(invalid))

        var packet = mentraCardPacket(viewType: "card.body")
        packet.text = "the body signal from this morning"
        packet.fields?["face"] = invalid.jsonValue
        let card = try XCTUnwrap(ViewPacketCardPresentation(packet: packet))

        XCTAssertTrue(card.usesFallbackFace)
        XCTAssertEqual(card.face.anchor.text, "the body signal from this morning")
        XCTAssertEqual(card.face.ask, "details available")
        XCTAssertFalse(card.face.anchor.text.contains("…"))
        XCTAssertTrue(ViewPacketCardPresentation.isWithinGlanceableBudget(card.face))
    }

    func testMentraCardCollapsedTextKeepsDisclosureOneTapAway() throws {
        var packet = mentraCardPacket(viewType: "card.translation")
        packet.evidence = ["raw-packet-evidence-id"]
        let card = try XCTUnwrap(ViewPacketCardPresentation(packet: packet))
        let visible = ViewPacketRenderer.visibleTextSequence(for: packet)

        XCTAssertEqual(visible, card.collapsedVisibleText)
        XCTAssertTrue(visible.contains("details ›"))
        XCTAssertFalse(visible.contains("the name keeps returning"))
        XCTAssertFalse(visible.contains("raw-packet-evidence-id"))
        XCTAssertTrue(card.disclosure.visibleLines.contains("the name keeps returning"))
    }

    func testMentraSuppressedCardRendersNothing() {
        var packet = mentraCardPacket(viewType: "card.cue")
        packet.fields?["status"] = .string("suppressed-not-rendered")

        XCTAssertFalse(ViewPacketRenderer.shouldRender(packet))
        XCTAssertEqual(ViewPacketRenderer.visibleTextSequence(for: packet), [])
    }

    func testMentraCardsRespectAmbientPeripheralAndFocalClampPolicies() {
        var ambient = mentraCardPacket(viewType: "card.cue")
        ambient.fields?["interruptionClass"] = .string("ambient")
        var peripheral = mentraCardPacket(viewType: "card.body")
        peripheral.fields?["interruptionClass"] = .string("peripheral")
        var focal = mentraCardPacket(viewType: "card.translation")
        focal.fields?["interruptionClass"] = .string("focal")

        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: ambient), .ambient)
        XCTAssertFalse(ViewPacketRenderer.renderPolicy(for: ambient).usesFadeTransition)
        XCTAssertFalse(ViewPacketRenderer.renderPolicy(for: ambient).animatesChanges)
        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: peripheral), .peripheral)
        XCTAssertTrue(ViewPacketRenderer.renderPolicy(for: peripheral).usesFadeTransition)
        XCTAssertTrue(ViewPacketRenderer.renderPolicy(for: peripheral).animatesChanges)
        XCTAssertEqual(ViewPacketRenderer.renderedInterruptionClass(for: focal), .peripheral)
    }

    func testBuildSnapshotEventNameMatchesServer() throws {
        let frame = "event: build_snapshot\ndata: {\"generatedAt\":\"2026-07-04T10:00:00Z\",\"seq\":3,\"plans\":[],\"packets\":[{\"id\":\"aaaaaaaaaaaaaaaaaaaaaaaa\",\"viewType\":\"build.status\",\"text\":\"plan building\",\"provenance\":{\"surface\":\"build\"},\"frontierExcluded\":true}]}"
        let event = try AGUIClient.decodeSSEFrame(frame)
        guard case .snapshot(let packets) = event else {
            return XCTFail("expected .snapshot, got \(String(describing: event))")
        }
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].viewType, "build.status")
    }

    func testBareChatWorkerEventDecodesAsWorkerPacket() throws {
        let frame = "event: chat.worker\ndata: {\"taskId\":\"task-bare\",\"label\":\"researching memory\",\"state\":\"running\",\"stepText\":\"reading\"}"
        let event = try AGUIClient.decodeSSEFrame(frame)
        guard case .packet(let packet) = event else {
            return XCTFail("expected .packet, got \(String(describing: event))")
        }

        XCTAssertEqual(packet.viewType, "chat.worker")
        XCTAssertEqual(ChatWorkerPacket(packet)?.taskId, "task-bare")
        XCTAssertEqual(ChatWorkerPacket(packet)?.stepText, "reading")
    }

    // Design system plan 003 U3 — RenderViewPacket.swift's k0.* branch used to
    // collapse all five (now six, with k0.evolve_report) k0.* viewTypes into
    // one undifferentiated `.k0` case. This asserts the six fixture packets
    // that previously all resolved to `.k0` now dispatch to six distinct
    // branch cases.
    func testK0ViewTypesDispatchToDistinctBranches() {
        let viewTypes = ["k0.decision", "k0.provenance", "k0.claim", "k0.change", "k0.eval_score", "k0.evolve_report"]
        let branches = viewTypes.map { viewType in
            ViewPacketRenderer.branch(for: k0Fixture(viewType: viewType))
        }

        XCTAssertEqual(branches, [.k0Decision, .k0Provenance, .k0Claim, .k0Change, .k0EvalScore, .k0EvolveReport])
        XCTAssertEqual(Set(branches).count, viewTypes.count, "all six k0.* viewTypes must dispatch to distinct branch cases")
    }

    private func k0Fixture(viewType: String) -> ViewPacket {
        ViewPacket(
            id: String(repeating: "a", count: 24),
            viewType: viewType,
            text: "k0 fixture",
            provenance: ["surface": .string("public")],
            frontierExcluded: false
        )
    }

    private func mentraCardPacket(viewType: String) -> ViewPacket {
        let face = CardFace(
            anchor: CardFaceAnchor(style: "words", text: "calling it K", date: "2026-07-11"),
            ask: "keep this cue?"
        )
        return ViewPacket(
            id: "mentra-\(viewType)",
            viewType: viewType,
            text: "calling it K",
            fields: [
                "status": .string("fired"),
                "interruptionClass": .string("ambient"),
                "maxSimultaneousCues": .number(1),
                "face": face.jsonValue,
                "disclosure": .object([
                    "brief": .object([
                        "whyNow": .string("the name keeps returning"),
                        "openQuestion": .string("keep this cue?"),
                        "blocker": .string("nothing"),
                        "stakes": .string("reversible"),
                    ]),
                    "evidence": .array([
                        .object([
                            "label": .string("naming decision"),
                        ]),
                    ]),
                ]),
                "actions": .object([
                    "accept": mentraAction(
                        id: "keep-card",
                        disposition: "accepted",
                        consequence: "records the cue as useful"
                    ),
                    "dismiss": mentraAction(
                        id: "dismiss-card",
                        disposition: "dismissed",
                        consequence: "records the cue as not useful"
                    ),
                ]),
            ],
            provenance: ["surface": .string("conversation"), "lane": .string("sovereign")],
            frontierExcluded: true
        )
    }

    private func mentraAction(
        id: String,
        disposition: String,
        consequence: String
    ) -> ViewPacketJSONValue {
        .object([
            "action": .object([
                "kind": .string("decision-card.answer"),
                "target": .string(id),
                "id": .string(id),
                "intent": .string("decision-card.answer"),
                "args": .object(["disposition": .string(disposition)]),
            ]),
            "consequence": .string(consequence),
        ])
    }
}
