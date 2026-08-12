import XCTest
@testable import K

final class ChatThreadStateTests: XCTestCase {
    func testNewerCompletionArchivesOlderButCompletingDoesNotArchiveItself() {
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let first = thread(id: "first", phase: .finished, at: firstDate)
        let second = thread(id: "second", phase: .processing, at: secondDate)
        var threads = [first, second]

        let completedFirst = ChatThreadLifecycle.complete(first, at: secondDate)
        XCTAssertEqual(completedFirst.phase, .finished)

        threads[1] = ChatThreadLifecycle.complete(second, at: secondDate)
        XCTAssertEqual(threads[0].phase, .finished)

        ChatThreadLifecycle.archiveSuperseded(&threads, newerID: "second")

        XCTAssertEqual(threads.map(\.phase), [.archived, .finished])
    }

    func testManualCompleteResolvesOnlyTheSelectedOpenCard() {
        let date = Date(timeIntervalSince1970: 300)
        let open = thread(id: "open", phase: .finished, at: date)
        let other = thread(id: "other", phase: .finished, at: date)

        let completed = ChatThreadLifecycle.manuallyComplete(open, at: date.addingTimeInterval(1))

        XCTAssertEqual(completed.phase, .resolved)
        XCTAssertTrue(completed.phase.isArchived)
        XCTAssertEqual(other.phase, .finished)
    }

    func testFailedThreadRetriesOnceThenParks() throws {
        let date = Date(timeIntervalSince1970: 400)
        let failed = ChatThreadLifecycle.fail(
            thread(id: "failed", phase: .processing, at: date, retryText: "try again"),
            error: "daemon unavailable",
            at: date
        )

        XCTAssertTrue(failed.canRetry)
        let retrying = try XCTUnwrap(ChatThreadLifecycle.retry(failed, at: date.addingTimeInterval(1)))
        XCTAssertEqual(retrying.phase, .processing)
        XCTAssertEqual(retrying.retryCount, 1)

        let parked = ChatThreadLifecycle.fail(
            retrying,
            error: "still unavailable",
            at: date.addingTimeInterval(2)
        )

        XCTAssertFalse(parked.canRetry)
        XCTAssertNil(ChatThreadLifecycle.retry(parked, at: date.addingTimeInterval(3)))
    }

    func testOfflineQueueHasItsOwnStateAndKeepsTheReplyQueued() {
        let queued = ChatThreadLifecycle.queueOffline(
            thread(id: "offline", phase: .processing, at: Date(timeIntervalSince1970: 500), retryText: "send later"),
            at: Date(timeIntervalSince1970: 501)
        )

        XCTAssertEqual(queued.phase, .queuedOffline)
        XCTAssertEqual(queued.visualState, .queuedOffline)
        XCTAssertEqual(queued.statusText, KCopy.queuedWillSync)
        XCTAssertFalse(queued.isCompleted)
        XCTAssertEqual(queued.retryText, "send later")
    }

    func testCompletedCardHasNoStatusLine() {
        let completed = ChatThreadLifecycle.complete(
            thread(id: "done", phase: .processing, at: Date(timeIntervalSince1970: 600)),
            at: Date(timeIntervalSince1970: 601)
        )

        XCTAssertEqual(completed.phase, .finished)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.statusText, "")
        XCTAssertNotNil(completed.resultTone)
    }

    func testSixThreadStatesHaveSixDistinctVisualTreatments() {
        let date = Date(timeIntervalSince1970: 700)
        let threads = [
            thread(id: "building", phase: .processing, at: date),
            thread(id: "done", phase: .finished, at: date),
            thread(id: "staged", phase: .finished, at: date, buildState: .staged),
            thread(id: "resolved", phase: .resolved, at: date),
            thread(id: "queued", phase: .queuedOffline, at: date),
            thread(id: "failed", phase: .failed, at: date, retryText: "retry"),
        ]

        XCTAssertEqual(Set(threads.map(\.visualState)).count, 6)
        XCTAssertEqual(
            Set(threads.map(\.visualState)),
            Set(ChatThreadVisualState.allCases)
        )
    }

    private func thread(
        id: String,
        phase: ChatThreadPhase,
        at date: Date,
        buildState: ChatThreadBuildState = .idle,
        retryText: String? = nil
    ) -> ChatThread {
        ChatThread(
            id: id,
            forkMessageID: "fork-\(id)",
            title: id,
            phase: phase,
            buildState: buildState,
            retryText: retryText,
            createdAt: date,
            updatedAt: date
        )
    }
}
