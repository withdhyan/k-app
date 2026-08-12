import XCTest
@testable import K

final class ChatActionRowTests: XCTestCase {
    func testAbsentPacketFieldsRenderNoRowState() {
        let packet = ViewPacket(id: "silent", viewType: "chat.reply", text: "no action fields")

        XCTAssertEqual(ChatNextActionPacket(packet: packet).actions, [])
        XCTAssertEqual(
            ChatNextActionRowState.resolve(
                actions: ChatNextActionPacket(packet: packet).actions,
                selectedActionID: nil,
                isLatest: true
            ),
            .absent
        )
    }

    func testOnlyLatestReplyIsActive() {
        let old = Message(role: .k, text: "old")
        let latest = Message(role: .k, text: "latest")
        let actions = [ChatNextActionItem(id: "keep", label: "keep it")]

        let latestID = ChatNextActionPolicy.latestKReplyID(in: [old, latest])

        XCTAssertEqual(latestID, latest.id)
        XCTAssertNotEqual(latestID, old.id)
        XCTAssertEqual(
            ChatNextActionRowState.resolve(
                actions: actions,
                selectedActionID: nil,
                isLatest: latestID == latest.id
            ),
            .latestActive
        )
        XCTAssertEqual(
            ChatNextActionRowState.resolve(
                actions: actions,
                selectedActionID: "keep",
                isLatest: latestID == old.id
            ),
            .previousCollapsed
        )
    }

    func testPreviousTurnCollapsesToChosenChipAndLongPressRestores() {
        let actions = [ChatNextActionItem(id: "keep", label: "keep it")]

        XCTAssertTrue(
            ChatNextActionRowState.resolve(
                actions: actions,
                selectedActionID: "keep",
                isLatest: false
            ).showsOnlyChosenChip
        )
        XCTAssertEqual(
            ChatNextActionRowState.resolve(
                actions: actions,
                selectedActionID: "keep",
                isLatest: false,
                isRestored: true
            ),
            .previousRestored
        )
    }

    func testChevronSlidesBetweenActionsAndFollowUps() {
        XCTAssertEqual(ChatActionRowPage.actions.toggled, .followUps)
        XCTAssertEqual(ChatActionRowPage.followUps.toggled, .actions)
    }

    func testTapPayloadContainsOnlyChosenActionID() {
        let command = ChatActionCommand(chosenActionID: "compare-rem")

        XCTAssertEqual(command.payload, ["chosenActionId": "compare-rem"])
        XCTAssertNil(command.payload["label"])
        XCTAssertEqual(command.wirePayload, ["chosenActionId": .string("compare-rem")])
    }

    func testThreadWorthinessUsesExplicitWireSignalAndRejectsWorkers() {
        let worthy = Message(
            role: .k,
            text: "this deserves its own thread",
            packet: ViewPacket(
                id: "worthy",
                viewType: "chat.reply",
                fields: ["threadWorthy": .bool(true)]
            )
        )
        let worker = Message(
            role: .k,
            text: "background result",
            packet: ViewPacket(
                id: "worker",
                viewType: "chat.worker",
                fields: ["threadWorthy": .bool(true)]
            )
        )

        XCTAssertTrue(ChatThreadWorthiness.isWorthy(worthy))
        XCTAssertFalse(ChatThreadWorthiness.isWorthy(worker))
    }

    func testThreadWorthinessScoreNeedsThresholdAndExplicitFalseWins() {
        let below = Message(
            role: .k,
            text: "keep this in the trunk",
            packet: ViewPacket(
                id: "below",
                viewType: "chat.reply",
                fields: ["threadScore": .number(0.69)]
            )
        )
        let suppressed = Message(
            role: .k,
            text: "not a thread",
            packet: ViewPacket(
                id: "suppressed",
                viewType: "chat.reply",
                fields: [
                    "threadScore": .number(0.99),
                    "threadWorthy": .bool(false),
                ]
            )
        )

        XCTAssertFalse(ChatThreadWorthiness.isWorthy(below))
        XCTAssertFalse(ChatThreadWorthiness.isWorthy(suppressed))
    }
}
import XCTest
@testable import K

final class ChatReasoningTraceTests: XCTestCase {
    func testSummaryDerivesDurationAndStepCount() {
        let packet = ViewPacket(
            id: "reply",
            viewType: "chat.worker",
            fields: [
                "taskId": .string("task-1"),
                "durationSeconds": .number(40),
                "steps": .array([
                    .object(["text": .string("read context"), "detail": .string("loaded the thread")]),
                    .object(["text": .string("compare options")]),
                ]),
            ]
        )

        let trace = ChatReasoningTrace.from(packet)

        XCTAssertEqual(trace?.durationSeconds, 40)
        XCTAssertEqual(trace?.steps.count, 2)
        XCTAssertEqual(trace?.summaryLine, "thought for 40s · 2 steps")
        XCTAssertEqual(trace?.steps.first?.detail, "loaded the thread")
    }

    func testSummaryDerivesDurationFromWireTimestamps() {
        let packet = ViewPacket(
            id: "reply",
            viewType: "chat.worker",
            fields: [
                "taskId": .string("task-1"),
                "startedAt": .string("2026-08-08T10:00:00Z"),
                "completedAt": .string("2026-08-08T10:00:40Z"),
                "stepEvents": .array([.string("finish")]),
            ]
        )

        XCTAssertEqual(ChatReasoningTrace.from(packet)?.summaryLine, "thought for 40s · 1 steps")
    }

    func testExpansionStateCollapsesTraceAndTogglesOneStep() {
        var state = ChatReasoningTraceExpansionState()
        XCTAssertFalse(state.isTraceExpanded)
        XCTAssertNil(state.expandedStepID)

        state.toggleTrace()
        state.toggleStep("step-1")
        XCTAssertEqual(state, ChatReasoningTraceExpansionState(isTraceExpanded: true, expandedStepID: "step-1"))

        state.toggleStep("step-1")
        XCTAssertNil(state.expandedStepID)
        state.toggleStep("step-2")
        state.toggleTrace()
        XCTAssertEqual(state, ChatReasoningTraceExpansionState())
    }
}
