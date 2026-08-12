import XCTest
@testable import K

final class ThreadStackTests: XCTestCase {
    func testOrderingFloatsNewestActiveThreadsAboveArchive() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let threads = [
            thread(id: "archived-new", phase: .archived, updatedAt: new),
            thread(id: "finished-old", phase: .finished, updatedAt: old),
            thread(id: "processing-new", phase: .processing, updatedAt: new),
        ]

        XCTAssertEqual(
            ThreadStackOrdering.ordered(threads).map(\.id),
            ["archived-new", "finished-old", "processing-new"]
        )
        XCTAssertEqual(ThreadStackOrdering.active(threads).map(\.id), ["finished-old", "processing-new"])
        XCTAssertEqual(ThreadStackOrdering.archived(threads).map(\.id), ["archived-new"])
    }

    func testRailProjectsFourStatesAndFoldsQueuedAndStagedIntoProcessing() {
        let date = Date(timeIntervalSince1970: 200)
        let packet = ViewPacket(id: "needs", viewType: "chat.reply")
        let threads = [
            thread(id: "failed", phase: .failed, updatedAt: date),
            thread(id: "needs", phase: .finished, updatedAt: date, actionPacket: packet),
            thread(id: "queued", phase: .queuedOffline, updatedAt: date),
            thread(id: "staged", phase: .finished, updatedAt: date, buildState: .staged),
            thread(id: "done", phase: .finished, updatedAt: date),
        ]

        XCTAssertEqual(
            ThreadStackOrdering.ordered(threads).map(\.id),
            ["done", "queued", "staged", "needs", "failed"]
        )
        XCTAssertEqual(threads.map(\.threadStackState), [.failed, .needsYou, .processing, .processing, .completed])
    }

    func testCompletedThreadsCarryLandingAndExpireAfterThreeDays() {
        let landed = Date(timeIntervalSince1970: 1_000)
        let thread = ChatThreadLifecycle.complete(
            thread(id: "done", phase: .processing, updatedAt: landed.addingTimeInterval(-10)),
            at: landed
        )

        XCTAssertEqual(thread.landedAt, landed)
        XCTAssertEqual(ThreadStackAging.label(for: thread, now: landed.addingTimeInterval(86_400)), "leaves in 2d")
        XCTAssertFalse(ThreadStackAging.isExpired(thread, now: landed.addingTimeInterval(3 * 86_400 - 1)))
        XCTAssertTrue(ThreadStackAging.isExpired(thread, now: landed.addingTimeInterval(3 * 86_400)))
        XCTAssertTrue(ThreadStackOrdering.visible([thread], now: landed.addingTimeInterval(3 * 86_400)).isEmpty)
    }

    func testPagingUsesSevenRowReplacementWindowsAndDirectionalCounts() {
        let date = Date(timeIntervalSince1970: 200)
        let threads = (0..<15).map { thread(id: "thread-\($0)", phase: .processing, updatedAt: date.addingTimeInterval(TimeInterval($0))) }

        let first = ThreadStackPaging.page(threads, at: 0)
        XCTAssertEqual(first.rows.count, 7)
        XCTAssertEqual(first.earlierCount, 0)
        XCTAssertEqual(first.moreCount, 8)

        let second = ThreadStackPaging.page(threads, at: 1)
        XCTAssertEqual(second.rows.count, 7)
        XCTAssertEqual(second.earlierCount, 7)
        XCTAssertEqual(second.moreCount, 1)

        let last = ThreadStackPaging.page(threads, at: 2)
        XCTAssertEqual(last.rows.count, 1)
        XCTAssertEqual(last.earlierCount, 14)
        XCTAssertEqual(last.moreCount, 0)
    }

    func testOpeningAnotherCardCollapsesTheFirstSelection() {
        var state = ThreadStackSelectionState()

        state.open("one")
        XCTAssertEqual(state.expandedThreadID, "one")
        state.open("two")
        XCTAssertEqual(state.expandedThreadID, "two")
        state.toggle("two")
        XCTAssertNil(state.expandedThreadID)
    }

    func testBranchMotionFixtureKeepsARealAnchorAndOpenRailOrigin() throws {
        let fixture = ChatBranchMotionFixture.snapshot(now: Date(timeIntervalSince1970: 1_000))
        let anchor = try XCTUnwrap(fixture.messages.first)
        let thread = try XCTUnwrap(fixture.threads.first)

        XCTAssertEqual(thread.id, ChatBranchMotionFixture.branchID)
        XCTAssertEqual(thread.forkMessageID, anchor.id.uuidString)
        XCTAssertTrue(thread.isOpen)
        XCTAssertEqual(thread.phase, .finished)
        XCTAssertEqual(thread.history.first?.id, anchor.id)
    }

    func testChatDemoFixtureSeedsDeterministicTrunkAndOneBranch() throws {
        let first = ChatDemoFixture.snapshot()
        let second = ChatDemoFixture.snapshot()
        let thread = try XCTUnwrap(first.threads.first)

        XCTAssertEqual(first.messages, second.messages)
        XCTAssertEqual(first.threads, second.threads)
        XCTAssertEqual(first.messages.map(\.id.uuidString), [
            "22222222-2222-4222-8222-222222222222",
            "33333333-3333-4333-8333-333333333333",
            "44444444-4444-4444-8444-444444444444",
            ChatBranchMotionFixture.anchorID.uuidString,
        ])
        XCTAssertEqual(first.threads.map(\.id), [ChatBranchMotionFixture.branchID])
        XCTAssertEqual(thread.forkMessageID, ChatBranchMotionFixture.anchorID.uuidString)
        XCTAssertTrue(thread.isOpen)
        XCTAssertEqual(thread.history.count, 3)
    }

    func testLoadingChatRouteActivatesTheSeededFixtureWithoutOptionalMarker() {
        XCTAssertTrue(
            ChatDemoFixture.isEnabled(arguments: ["Kedar", "-ui34-loading", "-tab", "chat"])
        )
        XCTAssertTrue(
            ChatDemoFixture.isEnabled(arguments: ["Kedar", "-ui34-loading", "-tab", "cadence", "-tab", "chat"])
        )
        XCTAssertFalse(
            ChatDemoFixture.isEnabled(arguments: ["Kedar", "-ui34-loading", "-tab", "build"])
        )
    }

    func testLayoutPolicyKeepsRegularTrunkAndReservedLeadingSpace() {
        XCTAssertTrue(ThreadStackLayoutPolicy.isCompact(availableWidth: KStyle.chatRegularLayoutMinimumWidth - 1))
        XCTAssertFalse(ThreadStackLayoutPolicy.isCompact(availableWidth: KStyle.chatRegularLayoutMinimumWidth))

        let metrics = ChatShellLayoutMetrics.resolve(availableWidth: 1_366)
        XCTAssertGreaterThanOrEqual(metrics.trunkWidth, KStyle.columnMinWidth)
        XCTAssertLessThanOrEqual(metrics.trunkWidth, KStyle.readingMeasureMaxWidth)
        XCTAssertGreaterThan(KStyle.chatReservedLeadingWidth, .zero)
    }

    func testChatScrollAnchorChoosesNewestQueuedItemBeforeMessages() {
        let message = Message(role: .k, text: "latest reply")
        let queued = QueuedChatMessage(text: "waiting to send")

        XCTAssertEqual(
            ChatScrollAnchorLogic.latestTarget(
                messages: [message],
                queuedMessages: [queued]
            ),
            .queued(queued.id)
        )
    }

    func testChatScrollAnchorChoosesNewestMessageOrEmptyBottom() {
        let first = Message(role: .you, text: "first")
        let latest = Message(role: .k, text: "latest")

        XCTAssertEqual(
            ChatScrollAnchorLogic.latestTarget(messages: [first, latest], queuedMessages: []),
            .message(latest.id)
        )
        XCTAssertEqual(
            ChatScrollAnchorLogic.latestTarget(messages: [], queuedMessages: []),
            .bottom
        )
    }

    func testChatScrollContextChangesAcrossTrunkAndBranch() {
        XCTAssertEqual(ChatScrollAnchorLogic.context(for: nil), .trunk)
        XCTAssertEqual(ChatScrollAnchorLogic.context(for: "branch-1"), .branch("branch-1"))
        XCTAssertNotEqual(
            ChatScrollAnchorLogic.context(for: nil),
            ChatScrollAnchorLogic.context(for: "branch-1")
        )
    }

    func testBranchScrollAnchorUsesTheSharedLatestDecisionForHistoryAndQueue() {
        let first = Message(role: .you, text: "first")
        let latest = Message(role: .k, text: "latest branch reply")
        let queued = QueuedChatMessage(text: "queued branch follow up", branchID: "branch-1")

        XCTAssertEqual(
            ChatScrollAnchorLogic.latestTarget(messages: [first, latest], queuedMessages: []),
            .message(latest.id)
        )
        XCTAssertEqual(
            ChatScrollAnchorLogic.latestTarget(messages: [first, latest], queuedMessages: [queued]),
            .queued(queued.id)
        )
        XCTAssertNotEqual(
            ChatScrollAnchorLogic.context(for: "branch-1"),
            ChatScrollAnchorLogic.context(for: "branch-2")
        )
    }

    func testComposerSlotKeepsCompactAndRegularBranchesOnTheBottomSafeArea() {
        let compact = ChatComposerSlotPolicy.resolve(
            expandedThreadID: " branch-1 ",
            surface: .compactOverlay
        )
        let regular = ChatComposerSlotPolicy.resolve(
            expandedThreadID: "branch-2",
            surface: .regularWidth
        )

        XCTAssertEqual(compact, .branch("branch-1"))
        XCTAssertEqual(regular, .branch("branch-2"))
        XCTAssertEqual(
            ChatComposerSlotPolicy.resolve(expandedThreadID: nil, surface: .compactOverlay),
            .trunk
        )
        XCTAssertTrue(ChatComposerSlotPolicy.usesBottomSafeAreaInset(for: .compactOverlay))
        XCTAssertTrue(ChatComposerSlotPolicy.usesBottomSafeAreaInset(for: .regularWidth))
        XCTAssertEqual(
            ChatComposerSlotPolicy.hardwareKeyboardAnchor(for: .compactOverlay),
            .bottom
        )
        XCTAssertEqual(
            ChatComposerSlotPolicy.hardwareKeyboardAnchor(for: .regularWidth),
            .bottom
        )
    }

    func testHistoryAppendAuditRejectsReplacementOrReordering() {
        let first = Message(id: UUID(), role: .you, text: "first")
        let second = Message(id: UUID(), role: .k, text: "second")
        let third = Message(id: UUID(), role: .you, text: "third")

        XCTAssertEqual(
            ThreadStackHistoryAudit.appendedMessageIDs(before: [first, second], after: [first, second, third]),
            [third.id]
        )
        XCTAssertNil(ThreadStackHistoryAudit.appendedMessageIDs(before: [first, second], after: [second, first]))
        XCTAssertNil(ThreadStackHistoryAudit.appendedMessageIDs(before: [first], after: [third]))
    }

    func testBuildRowRequiresFinishedTypedBuildActionBehindHumanGate() {
        let governed = ViewPacket(
            id: "build-card",
            viewType: "build-card",
            action: ViewPacketAction(
                kind: "action-invoke",
                target: "build.request",
                tag: "[gate:human]",
                intent: "build_request"
            )
        )
        var value = thread(id: "one", phase: .finished, updatedAt: Date())

        value.actionPacket = governed
        XCTAssertEqual(ChatThreadActionGate.governedBuildPacket(for: value)?.id, governed.id)

        value.phase = .processing
        XCTAssertNil(ChatThreadActionGate.governedBuildPacket(for: value))
        value.phase = .finished
        value.actionPacket?.action?.tag = nil
        XCTAssertNil(ChatThreadActionGate.governedBuildPacket(for: value))
        value.actionPacket = nil
        XCTAssertNil(ChatThreadActionGate.governedBuildPacket(for: value))
    }

    func testContextSummaryUsesOnlyRealContextAndKeepsAttachmentHonest() {
        let packet = ViewPacket(
            id: "packet",
            viewType: "generic-text",
            fields: ["senses": .string("ambient audio")],
            evidence: ["ref-a", "ref-b"],
            provenance: ["self": .string("values-v4")]
        )
        let attachment = ChatAttachmentMetadata(
            filename: "Founder Brief.pdf",
            bookmarkData: Data([1, 2]),
            securityScopedAccessGranted: true
        )
        let snapshot = ChatContextComposer.snapshot(
            target: .thread(id: "branch-1", title: "Explore memory"),
            messages: [Message(role: .k, text: "answer", packet: packet)],
            attachment: attachment
        )

        XCTAssertEqual(snapshot.targetText, "thread · explore memory")
        XCTAssertEqual(snapshot.refsText, "2 refs")
        XCTAssertEqual(snapshot.sensesText, "ambient audio")
        XCTAssertEqual(snapshot.selfText, "values-v4")
        XCTAssertEqual(snapshot.attachmentText, "selected · founder brief.pdf")
        XCTAssertEqual(snapshot.summaryItems.count, 5)
        XCTAssertEqual(KCopy.chatAttachmentLocalOnly, "selected locally · not sent to k")
    }

    func testBranchThreadStoreRoundTripsDurableHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thread-stack-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("branches.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatBranchThreadStore(fileURL: url)
        let value = ChatThread(
            id: "branch-1",
            forkMessageID: "message-1",
            title: "durable branch",
            history: [Message(role: .you, text: "keep this")]
        )

        store.save([value])

        XCTAssertEqual(store.load(), [value])
    }

    func testTrunkIdentityIsStableUntilRotated() {
        let suite = "thread-stack-trunk-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ChatTrunkIdentityStore(key: "trunk", defaults: defaults)

        let first = store.loadOrCreate()
        XCTAssertEqual(store.loadOrCreate(), first)
        XCTAssertNotEqual(store.rotate(), first)
    }

    func testForkClientUsesDurableDaemonContract() async throws {
        let recorder = RequestRecorder()
        let client = CSKChat(
            baseURL: "http://100.64.0.2:3003/",
            transport: transport(recorder: recorder, lines: [
                #"{"branch":{"id":"branch-1","state":"open","trunkThreadId":"trunk-1","forkMessageId":"message-1"}}"#,
            ])
        )

        let branch = try await client.fork(
            trunkThreadId: "trunk-1",
            forkMessageId: "message-1",
            forkMessage: "Explore this"
        )
        let recordedRequest = await recorder.last()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])

        XCTAssertEqual(branch.id, "branch-1")
        XCTAssertEqual(request.url?.path, CSKChat.branchForkPath)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body["trunkThreadId"] as? String, "trunk-1")
        XCTAssertEqual(body["forkMessageId"] as? String, "message-1")
        XCTAssertEqual(body["forkMessage"] as? String, "Explore this")
    }

    func testBranchSendCarriesBranchID() async throws {
        let recorder = RequestRecorder()
        let client = CSKChat(
            baseURL: "http://100.64.0.2:3003",
            transport: transport(recorder: recorder, lines: [
                "event: done",
                #"data: {"content":"answer","lane":"sovereign","sovereign":true,"held":[],"viewPacket":{"id":"build-card","viewType":"build-card","action":{"kind":"action-invoke","target":"build.request","tag":"[gate:human]","intent":"build_request"}}}"#,
            ])
        )

        let outcome = try await client.send(message: "follow up", branchId: "branch-1") { _ in }
        let recordedRequest = await recorder.last()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])

        XCTAssertEqual(outcome.content, "answer")
        XCTAssertEqual(outcome.packet?.id, "build-card")
        XCTAssertEqual(outcome.packet?.action?.tag, "[gate:human]")
        XCTAssertEqual(request.url?.path, CSKChat.chatPath)
        XCTAssertEqual(body["branchId"] as? String, "branch-1")
    }

    @MainActor
    func testExpandedThreadComposerRoutesWithoutAppendingToTrunk() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("branch-model-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "thread-stack-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let branchStore = ChatBranchThreadStore(
            fileURL: directory.appendingPathComponent("branches.json")
        )
        branchStore.save([
            ChatThread(
                id: "branch-1",
                forkMessageID: "fork-1",
                title: "branch topic",
                history: [Message(role: .k, text: "anchor")]
            ),
        ])
        let recorder = RequestRecorder()
        let branchTransport = transport(recorder: recorder, lines: [
            "event: token",
            #"data: {"text":"thread answer"}"#,
            "event: done",
            #"data: {"content":"thread answer","lane":"sovereign","sovereign":true,"held":[]}"#,
        ])
        let model = ChatModel(
            threadStore: ChatThreadStore(fileURL: directory.appendingPathComponent("trunk.json")),
            unreadStore: ChatUnreadStore(key: "unread", defaults: defaults),
            inputQueueStore: ChatInputQueueStore(key: "queue", defaults: defaults),
            branchThreadStore: branchStore,
            trunkIdentityStore: ChatTrunkIdentityStore(key: "trunk-id", defaults: defaults),
            attachmentStore: ChatAttachmentStore(key: "attachment", defaults: defaults),
            chatClientFactory: { CSKChat(baseURL: $0, transport: branchTransport) }
        )
        model.draft = "follow this branch"

        model.send(targetBranchID: "branch-1")
        await waitUntil { !model.sending }

        XCTAssertTrue(model.messages.isEmpty)
        let history = try XCTUnwrap(model.threads.first(where: { $0.id == "branch-1" })?.history)
        XCTAssertEqual(history.map(\.role), [.k, .you, .k])
        XCTAssertEqual(history.map(\.text), ["anchor", "follow this branch", "thread answer"])
        XCTAssertEqual(model.threads.first?.phase, .finished)
        let recordedRequest = await recorder.last()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["branchId"] as? String, "branch-1")
    }

    func testCloseAndListClientsUseDaemonBranchLifecycleContract() async throws {
        let recorder = RequestRecorder()
        let client = CSKChat(
            baseURL: "http://100.64.0.2:3003",
            transport: transport(recorder: recorder, responses: [
                [#"{"branches":[{"id":"branch-1","state":"open"}]}"#],
                [#"{"branch":{"id":"branch-1","state":"discarded","verdict":"discard"}}"#],
            ])
        )

        let listed = try await client.listBranches(trunkThreadId: "trunk-1")
        let recordedListRequest = await recorder.request(at: 0)
        let listRequest = try XCTUnwrap(recordedListRequest)
        XCTAssertEqual(listed.map(\.id), ["branch-1"])
        XCTAssertEqual(listRequest.url?.path, CSKChat.branchListPath)
        XCTAssertEqual(URLComponents(url: listRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "trunk-1")

        let closed = try await client.closeBranch(
            branchId: "branch-1",
            verdict: .discard,
            why: "founder archived it"
        )
        let recordedCloseRequest = await recorder.request(at: 1)
        let closeRequest = try XCTUnwrap(recordedCloseRequest)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: closeRequest.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(closed.state, "discarded")
        XCTAssertEqual(closeRequest.url?.path, CSKChat.branchClosePath)
        XCTAssertEqual(body["branchId"] as? String, "branch-1")
        XCTAssertEqual(body["verdict"] as? String, "discard")
    }

    func testW31FixtureCarriesReceiptsSourcesAndHumanGatedVerdict() throws {
        let fixture = W31ChatThreadFixture.snapshot(state: .populated)
        let thread = try XCTUnwrap(fixture.threads.first)
        let packet = try XCTUnwrap(thread.actionPacket)

        XCTAssertEqual(thread.id, W31ChatThreadFixture.threadID)
        XCTAssertEqual(thread.threadStackState, .completed)
        XCTAssertEqual(thread.detail.turnCount, 3)
        XCTAssertEqual(thread.detail.sources.map(\.label), [
            "reading tariff filings · third of three",
            "grid-rates api · pulled",
            "solar-brief.pdf · read, 4 claims held",
        ])
        XCTAssertEqual(ChatThreadActionGate.governedBuildPacket(for: thread)?.id, packet.id)
        XCTAssertEqual(
            ChatThreadVerdictActions.items(for: packet).map(\.id),
            ["archive", "later", "build"]
        )
    }

    func testW31StagedProjectionStaysProcessingAndDoesNotStartAgingClock() throws {
        var thread = try XCTUnwrap(W31ChatThreadFixture.snapshot(state: .populated).threads.first)
        thread.buildState = .staged

        XCTAssertEqual(thread.threadStackState, .processing)
        XCTAssertNil(ThreadStackAging.label(for: thread, now: W31ChatThreadFixture.referenceNow))
        XCTAssertEqual(thread.landedAt, W31ChatThreadFixture.referenceNow.addingTimeInterval(-600))
    }

    func testW31TravelTokensMatchTheFrozenSwapAndReduceMotionCollapses() {
        XCTAssertEqual(KStyle.chatThreadTrunkFadeDuration, 0.5)
        XCTAssertEqual(KStyle.chatThreadGroundDuration, 0.6)
        XCTAssertEqual(KStyle.chatThreadMessageDuration, 0.3)
        XCTAssertEqual(KStyle.chatThreadComposerDuration, 0.5)
        XCTAssertEqual(KStyle.chatThreadGroundDelay, 0.5)
        XCTAssertEqual(KStyle.chatThreadMessageFirstDelay, 1.05)
        XCTAssertEqual(KStyle.chatThreadMessageSecondDelay, 1.2)
        XCTAssertEqual(KStyle.chatThreadComposerDelay, 1.3)
        XCTAssertEqual(KStyle.chatThreadTrunkReturnDelay, 0.55)
        XCTAssertNil(KStyle.chatThreadSwapMotion(true, phase: .threadEnter))
        XCTAssertNil(KStyle.chatThreadSwapMotion(true, phase: .trunkReturn))
        XCTAssertEqual(KStyle.chatThreadDetailMotionResolution(true), .none)
    }

    private func thread(
        id: String,
        phase: ChatThreadPhase,
        updatedAt: Date,
        actionPacket: ViewPacket? = nil,
        buildState: ChatThreadBuildState = .idle
    ) -> ChatThread {
        ChatThread(
            id: id,
            forkMessageID: "message-\(id)",
            title: id,
            phase: phase,
            actionPacket: actionPacket,
            buildState: buildState,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func transport(
        recorder: RequestRecorder,
        lines: [String]
    ) -> AGUIHTTPTransport {
        transport(recorder: recorder, responses: [lines])
    }

    private func transport(
        recorder: RequestRecorder,
        responses: [[String]]
    ) -> AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            let index = await recorder.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let selected = responses[min(index, responses.count - 1)]
            let stream = AsyncThrowingStream<String, Error> { continuation in
                for line in selected { continuation.yield(line) }
                continuation.finish()
            }
            return AGUILineResponse(response: response, lines: stream)
        }
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for chat model")
    }
}

private actor RequestRecorder {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) -> Int {
        requests.append(request)
        return requests.count - 1
    }

    func last() -> URLRequest? { requests.last }

    func request(at index: Int) -> URLRequest? {
        requests.indices.contains(index) ? requests[index] : nil
    }
}
