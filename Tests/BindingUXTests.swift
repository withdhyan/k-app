import XCTest
@testable import K

final class BindingUXTests: XCTestCase {
    func testConnectionStateVocabularyAndWordFadeWindows() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = KConnectionStateModel(status: .connecting, changedAt: start)

        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(1)).word, "connecting…")
        XCTAssertNil(state.presentation(now: start.addingTimeInterval(2.1)).word)

        state.transition(to: .live, now: start.addingTimeInterval(3))
        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(5.9)).word, "live")
        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(5.9)).signal, .live)
        XCTAssertNil(state.presentation(now: start.addingTimeInterval(6.1)).word)
        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(6.1)).signal, .live)

        state.transition(to: .reconnecting, now: start.addingTimeInterval(7))
        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(10)).word, "reconnecting…")
        XCTAssertEqual(state.presentation(now: start.addingTimeInterval(10)).signal, .reconnecting)

        state.transition(to: .offlineRetrying, now: start.addingTimeInterval(11))
        let offline = state.presentation(now: start.addingTimeInterval(12))
        XCTAssertEqual(offline.word, "offline · retrying")
        XCTAssertEqual(offline.signal, .offline)
        XCTAssertEqual(offline.inputsDisabledReason, "offline")
    }

    func testConnectionSignalDerivesConditionColorAndBreathing() {
        XCTAssertEqual(KConnectionSignal.live.condition, .live)
        XCTAssertFalse(KConnectionSignal.live.breathes)
        XCTAssertNil(KConnectionSignal.live.colorHex)
        XCTAssertEqual(KConnectionSignal.live.accessibilityLabel, "connection live, tap to retry")

        XCTAssertEqual(KConnectionSignal.reconnecting.condition, .degraded)
        XCTAssertTrue(KConnectionSignal.reconnecting.breathes)
        XCTAssertEqual(KConnectionSignal.reconnecting.colorHex, "#fabb00")
        XCTAssertEqual(KConnectionSignal.reconnecting.accessibilityLabel, "connection degraded, tap to retry")

        XCTAssertEqual(KConnectionSignal.offline.condition, .down)
        XCTAssertTrue(KConnectionSignal.offline.breathes)
        XCTAssertEqual(KConnectionSignal.offline.colorHex, "#e15554")
        XCTAssertEqual(KConnectionSignal.offline.accessibilityLabel, "connection down, tap to retry")
    }

    func testScrollPinningShowsNewBelowOnlyWhenScrolledUp() {
        var model = KScrollPinningModel()

        XCTAssertTrue(model.contentDidAppend())
        XCTAssertFalse(model.showsNewBelow)

        model.updateAtBottom(false)
        XCTAssertFalse(model.contentDidAppend())
        XCTAssertTrue(model.showsNewBelow)

        model.jumpToBottom()
        XCTAssertTrue(model.isAtBottom)
        XCTAssertFalse(model.showsNewBelow)
    }

    func testScrollPinningBreaksFollowAfterFounderScrollAndResumesFromPill() {
        var model = KScrollPinningModel()

        model.beginProgrammaticScroll()
        model.updateDistanceFromBottom(
            KScrollPinningModel.followBreakDistance + 1,
            scrollPositionViewID: model.geometryScrollPositionViewID
        )
        XCTAssertTrue(model.isFollowing)
        XCTAssertFalse(model.showsLatestPill)
        XCTAssertTrue(model.isProgrammaticallyScrolling)

        model.founderDragDidBegin()
        model.updateDistanceFromBottom(
            KScrollPinningModel.followBreakDistance + 1,
            scrollPositionViewID: model.geometryScrollPositionViewID
        )

        XCTAssertFalse(model.isFollowing)
        XCTAssertTrue(model.showsLatestPill)
        XCTAssertFalse(model.isProgrammaticallyScrolling)
        XCTAssertFalse(model.contentDidAppend())

        model.resumeFollowing()

        XCTAssertTrue(model.isFollowing)
        XCTAssertFalse(model.showsLatestPill)
        XCTAssertTrue(model.contentDidAppend())
    }

    func testInputQueuePreservesFIFOAndSupportsEditDrop() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        var queue = ChatInputQueueState()
        let first = try XCTUnwrap(queue.enqueue("first during stream", now: start))
        let second = try XCTUnwrap(queue.enqueue("second during stream", now: start.addingTimeInterval(1)))

        XCTAssertEqual(queue.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(queue.nextForDispatch()?.id, first.id)
        XCTAssertEqual(queue.takeForEdit(id: second.id), "second during stream")
        XCTAssertTrue(queue.items.isEmpty)

        let dropped = try XCTUnwrap(queue.enqueue("drop me", now: start.addingTimeInterval(2)))
        queue.drop(id: dropped.id)
        XCTAssertTrue(queue.items.isEmpty)
    }

    @MainActor
    func testFirstOfflineChatMessageMovesIntoInputQueue() async {
        let defaults = tempDefaults()
        let model = ChatModel(
            threadStore: tempChatThreadStore(),
            unreadStore: ChatUnreadStore(key: "chat.unread.\(UUID().uuidString)", defaults: defaults),
            inputQueueStore: ChatInputQueueStore(key: "chat.queue.\(UUID().uuidString)", defaults: defaults),
            clientFactory: { AGUIClient(baseURL: $0, transport: Self.throwingTransport()) },
            legacySender: { _, _, _, _ in throw CSKChatError.stream("offline") }
        )
        model.draft = "first offline message"

        model.send()
        await waitUntil { !model.sending }

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(model.queuedMessages.map(\.text), ["first offline message"])
        XCTAssertEqual(model.footer, KCopy.queuedWillSync)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
    }

    @MainActor
    func testPersistedChatQueueDrainsWhenIdle() async {
        let defaults = tempDefaults()
        let queueStore = ChatInputQueueStore(key: "chat.queue.\(UUID().uuidString)", defaults: defaults)
        let queuedAt = Date(timeIntervalSince1970: 4_321)
        queueStore.save(ChatInputQueueState(items: [
            QueuedChatMessage(text: "queued after relaunch", createdAt: queuedAt),
        ]))
        let model = ChatModel(
            threadStore: tempChatThreadStore(),
            unreadStore: ChatUnreadStore(key: "chat.unread.\(UUID().uuidString)", defaults: defaults),
            inputQueueStore: queueStore,
            clientFactory: { AGUIClient(baseURL: $0, transport: Self.chatPacketTransport()) },
            legacySender: { _, _, _, _ in throw CSKChatError.stream("legacy should not run") }
        )

        XCTAssertEqual(model.queuedMessages.map(\.text), ["queued after relaunch"])

        model.drainInputQueueIfIdle()
        await waitUntil { !model.sending && model.queuedMessages.isEmpty && model.messages.count == 2 }

        XCTAssertTrue(model.queuedMessages.isEmpty)
        XCTAssertEqual(model.messages.map(\.role), [.you, .k])
        XCTAssertEqual(model.messages.first?.text, "queued after relaunch")
        XCTAssertEqual(model.messages.first?.createdAt, queuedAt)
        XCTAssertEqual(model.connectionState.status, .live)
    }

    @MainActor
    func testUserCancelReturnsConnectionToLive() async {
        let defaults = tempDefaults()
        let model = ChatModel(
            threadStore: tempChatThreadStore(),
            unreadStore: ChatUnreadStore(key: "chat.unread.\(UUID().uuidString)", defaults: defaults),
            inputQueueStore: ChatInputQueueStore(key: "chat.queue.\(UUID().uuidString)", defaults: defaults),
            clientFactory: { AGUIClient(baseURL: $0, transport: Self.suspendedTransport()) },
            legacySender: { _, _, _, _ in throw CSKChatError.stream("legacy should not run") }
        )
        model.draft = "stop this stream"

        model.send()
        await waitUntil { model.sending }
        model.stopStreaming()
        await waitUntil { !model.sending }

        XCTAssertEqual(model.footer, KCopy.stopped)
        XCTAssertEqual(model.connectionState.status, .live)
    }

    func testDeltaCoalescingCapsFlushesToHundredMillisecondWindows() {
        let start = Date(timeIntervalSince1970: 4_000)
        var planner = ChatDeltaFlushPlanner()
        var flushCount = 0
        let deltaTimes = (0..<20).map { TimeInterval($0) * 0.02 }

        for offset in deltaTimes {
            if planner.shouldFlush(after: "x", at: start.addingTimeInterval(offset)) {
                flushCount += 1
            }
        }

        XCTAssertLessThanOrEqual(
            flushCount,
            ChatDeltaFlushPlanner.maximumFlushes(forDuration: deltaTimes.last ?? 0)
        )
    }

    @MainActor
    func testKillConfirmUsesSecondTapWithinThreeSecondWindow() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let card = BuildCard(
            id: "card-kill",
            title: "stop lane",
            options: [
                BuildCardOption(id: "kill", label: "kill", consequence: "stop the lane"),
            ]
        )
        let option = try XCTUnwrap(card.options.first)
        let model = BuildModel(baseURL: "http://daemon.test")

        let first = model.choose(option: option, for: card, now: start)

        XCTAssertEqual(first, .confirmationRequired)
        XCTAssertTrue(model.isConfirming(card: card, option: option, now: start.addingTimeInterval(2.9)))
        XCTAssertFalse(model.isConfirming(card: card, option: option, now: start.addingTimeInterval(3.1)))
    }

    func testVerdictButtonOrderIsSpecOrder() {
        XCTAssertEqual(MindVerdict.buttonOrder.map(\.rawValue), ["junk", "nod", "act-on"])
    }

    func testTabDotLogicTracksShellTabSignals() {
        let items = KTabStripModel.items(
            active: .chat,
            cadenceNeedsAttention: true,
            chatHasUnread: true,
            openBuildCards: 2,
            unjudgedMindOutputs: 1,
            adminDueTodayItems: 1,
            staleTabs: [.build]
        )

        XCTAssertEqual(items.map(\.title), ["cadence", "chat", "build", "mind", "bio", "admin"])
        XCTAssertEqual(items.map(\.showsDot), [true, true, true, true, false, true])
        XCTAssertEqual(items.first { $0.tab == .build }?.dotOpacity, KStyle.primaryTextOpacity * KStyle.staleDotFactor)
        XCTAssertEqual(items.map(\.textOpacity), [
            KStyle.quaternaryTextOpacity,
            KStyle.primaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
            KStyle.quaternaryTextOpacity,
        ])
    }

    func testOptimisticPostRevertsToInlineFailureText() {
        var model = KOptimisticPostModel()

        model.begin()
        XCTAssertEqual(model.state, .pending)
        XCTAssertTrue(model.state.isOptimistic)

        model.fail(reason: "offline")
        XCTAssertEqual(model.state.inlineErrorText, "answer failed · retry")
    }

    @MainActor
    func testRootGlanceModelLoadsCachedCountsThenRefreshesFreshCounts() async {
        let cached = KRootGlanceCounts(openBuildCards: 2, unjudgedMindOutputs: 3, adminDueTodayItems: 1)
        let fresh = KRootGlanceCounts(openBuildCards: 1, unjudgedMindOutputs: 0, adminDueTodayItems: 4)
        var refreshCount = 0
        let model = KRootGlanceModel(provider: KRootGlanceProvider(
            cachedCounts: { cached },
            freshCounts: {
                refreshCount += 1
                return fresh
            }
        ))

        XCTAssertEqual(model.counts, cached)

        model.setOpenBuildCards(-1)
        model.setUnjudgedMindOutputs(5)
        model.setAdminDueTodayItems(6)
        XCTAssertEqual(model.counts, KRootGlanceCounts(openBuildCards: 0, unjudgedMindOutputs: 5, adminDueTodayItems: 6))

        model.loadCachedCounts()
        XCTAssertEqual(model.counts, cached)

        await model.refreshNow()
        XCTAssertEqual(model.counts, fresh)
        XCTAssertEqual(refreshCount, 1)
    }

    func testOnboardingChecklistDerivesCameraOnlyAndStaysWithinSixSteps() {
        let steps = OnboardingChecklist.steps(
            permissionStates: OnboardingPermissionStates(camera: .notDetermined),
            selectedTab: .cadence
        )
        let rows = steps.flatMap(\.permissionRows)

        XCTAssertLessThanOrEqual(steps.count, OnboardingChecklist.maxStepCount)
        XCTAssertEqual(steps.map(\.id), ["plain-ink", "permissions"])
        XCTAssertEqual(rows.map(\.kind), [.camera])
        XCTAssertEqual(rows.first?.line, "camera")
        XCTAssertEqual(rows.first?.action, .allow)
        XCTAssertEqual(rows.first?.isDone, false)
        XCTAssertEqual(
            rows.first?.reason,
            "camera asks when build or mind opens; cadence stays plain ink."
        )
    }

    func testOnboardingCameraGatingTextFollowsBuildMindPromptGate() {
        XCTAssertFalse(OnboardingChecklist.cameraPromptAllowed(selectedTab: .cadence))
        XCTAssertFalse(OnboardingChecklist.cameraPromptAllowed(selectedTab: .chat))
        XCTAssertTrue(OnboardingChecklist.cameraPromptAllowed(selectedTab: .build))
        XCTAssertTrue(OnboardingChecklist.cameraPromptAllowed(selectedTab: .mind))

        XCTAssertEqual(
            OnboardingChecklist.cameraAskGatingText(cameraState: .notDetermined, selectedTab: .build),
            KCopy.cameraPrePermission
        )
        XCTAssertEqual(
            OnboardingChecklist.cameraAskGatingText(cameraState: .notDetermined, selectedTab: .mind),
            KCopy.cameraPrePermission
        )
    }

    func testOnboardingCameraRowsReflectGrantedAndBlockedStates() {
        let granted = OnboardingChecklist.permissionRows(
            permissionStates: OnboardingPermissionStates(camera: .authorized),
            selectedTab: .cadence
        )
        let denied = OnboardingChecklist.permissionRows(
            permissionStates: OnboardingPermissionStates(camera: .denied),
            selectedTab: .build
        )
        let restricted = OnboardingChecklist.permissionRows(
            permissionStates: OnboardingPermissionStates(camera: .restricted),
            selectedTab: .mind
        )

        XCTAssertEqual(granted.first?.isDone, true)
        XCTAssertNil(granted.first?.action)
        XCTAssertEqual(granted.first?.reason, "camera stage is ready across all tabs.")
        XCTAssertEqual(denied.first?.action, .openSettings)
        XCTAssertEqual(restricted.first?.action, .openSettings)
    }

    func testOnboardingSeenTransitionsPersistFirstRunOnly() {
        let unseen = OnboardingSeenState(hasSeenFirstRun: false)

        XCTAssertTrue(OnboardingSeenLogic.shouldPresent(unseen))
        XCTAssertFalse(OnboardingSeenLogic.shouldPresent(
            OnboardingSeenLogic.reduce(unseen, event: .overlayAppeared)
        ))
        XCTAssertEqual(
            OnboardingSeenLogic.reduce(unseen, event: .laterTapped),
            OnboardingSeenState(hasSeenFirstRun: true)
        )
        XCTAssertEqual(
            OnboardingSeenLogic.reduce(unseen, event: .completed),
            OnboardingSeenState(hasSeenFirstRun: true)
        )
        XCTAssertEqual(OnboardingSeenLogic.firstRunSeenKey, "k.onboarding.first_run.seen")
    }

    private func tempDefaults() -> UserDefaults {
        let suiteName = "BindingUXTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func tempChatThreadStore() -> ChatThreadStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chat-thread-\(UUID().uuidString).json")
        return ChatThreadStore(fileURL: url)
    }

    private static func throwingTransport() -> AGUIHTTPTransport {
        AGUIHTTPTransport { _ in
            throw AGUIClientError.stream("offline")
        }
    }

    private static func suspendedTransport() -> AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return lineResponse(
                url: request.url!,
                lines: [
                    #"event: done"#,
                    #"data: {"packetId":"late"}"#,
                ]
            )
        }
    }

    private static func chatPacketTransport() -> AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            lineResponse(
                url: request.url!,
                lines: [
                    #"event: packet"#,
                    #"data: {"id":"reply","viewType":"generic.text","text":"queued answer","provenance":{"surface":"test"}}"#,
                    #"event: done"#,
                    #"data: {"packetId":"reply"}"#,
                ]
            )
        }
    }

    private static func lineResponse(url: URL, lines: [String]) -> AGUILineResponse {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return AGUILineResponse(response: response, lines: stream)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
