import XCTest
@testable import K

final class BuildTrunkThreadWindowTests: XCTestCase {
    func testDateSeparatorsUseHumanizedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-12T12:00:00Z")!

        XCTAssertEqual(
            BuildTrunkDateSeparator.text(for: "2026-08-12", now: now, calendar: calendar),
            "today"
        )
        XCTAssertEqual(
            BuildTrunkDateSeparator.text(for: "2026-08-11", now: now, calendar: calendar),
            "yesterday"
        )
        XCTAssertEqual(
            BuildTrunkDateSeparator.text(for: "2026-08-09", now: now, calendar: calendar),
            "3 days ago"
        )
        XCTAssertEqual(
            BuildTrunkDateSeparator.text(for: "34m ago", now: now, calendar: calendar),
            "today"
        )
        XCTAssertEqual(
            BuildTrunkDateSeparator.text(for: "3d ago", now: now, calendar: calendar),
            "3 days ago"
        )
        XCTAssertNil(BuildTrunkDateSeparator.text(for: "sometime", now: now, calendar: calendar))
    }

    func testDashLanguageCoversHeldExternalAndFailureWithoutNewWireKinds() {
        XCTAssertEqual(BuildThreadDashState.allCases.count, 9)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "integrated"), .landed)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "building"), .building)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "needs_founder"), .needsYou)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "queued"), .queued)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "held_external"), .heldExternal)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "failed"), .failed)
        XCTAssertEqual(BuildThreadDashState.from(rawState: ""), .unknown)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "future-wire-state"), .unknown)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "done"), .done)
        XCTAssertEqual(BuildThreadDashState.from(rawState: "stale"), .stale)
    }

    func testThreadProjectionUsesExistingBranchesAndAddsDoneAgingLabel() {
        let surface = BuildReportSurface.make(
            packets: BuildAuditFixture.packets,
            openCardCount: 0
        )
        let summaries = BuildAuditFixture.packets
            .filter(\.isBuildStatusPacket)
            .map(BuildStatusSummary.init(packet:))

        let threads = BuildThreadProjection.make(
            branches: surface.branches,
            summaries: summaries,
            isStale: false
        )

        XCTAssertFalse(threads.contains(where: { $0.id == "trunk" }))
        XCTAssertNotEqual(threads.first?.id, "trunk")
        XCTAssertTrue(threads.contains(where: { $0.title == "land the quiet slice" && $0.isDone }))
        XCTAssertEqual(
            threads.first(where: { $0.title == "land the quiet slice" })?.doneAgingLabel,
            "done · aging out"
        )
        XCTAssertEqual(
            threads.first(where: { $0.title == "keep the attention lane" })?.stateLabel,
            "needs you"
        )
    }

    func testStaleProjectionNamesStalenessAndKeepsDashShape() {
        let branch = BuildBranchItem(
            id: "stale-plan",
            title: "stale plan",
            status: "queued",
            isTrunk: false,
            isBuilding: false
        )
        let summary = BuildStatusSummary(
            packet: ViewPacket(
                id: "stale-status",
                viewType: "build.status",
                text: "stale plan",
                fields: [
                    "plan": .object(["id": .string("stale-plan"), "title": .string("stale plan")]),
                    "units": .array([.object(["id": .string("unit"), "state": .string("queued")])]),
                ]
            )
        )
        let projection = try! XCTUnwrap(
            BuildThreadProjection.make(branches: [branch], summaries: [summary], isStale: true).first
        )

        XCTAssertTrue(projection.isStale)
        XCTAssertEqual(projection.stateLabel, "stale")
        XCTAssertEqual(projection.dashes, [.queued])
    }

    func testPagingReplacesExactlySevenRowsInBothDirections() {
        let items = Array(0..<22)
        XCTAssertEqual(Array(BuildThreadPaging.window(items: items, start: 0)), Array(0..<7))
        XCTAssertEqual(Array(BuildThreadPaging.window(items: items, start: 7)), Array(7..<14))
        XCTAssertEqual(Array(BuildThreadPaging.window(items: items, start: 14)), Array(14..<21))
        XCTAssertEqual(BuildThreadPaging.earlierCount(itemCount: items.count, start: 14), 14)
        XCTAssertEqual(BuildThreadPaging.laterCount(itemCount: items.count, start: 14), 1)
        XCTAssertEqual(BuildThreadPaging.start(itemCount: items.count, proposed: 99), 15)
    }

    func testAuditFixtureSuppliesArchiveTailWithoutAddingItToTrunkStream() {
        let surface = BuildReportSurface.make(
            packets: BuildAuditFixture.packets,
            openCardCount: 0
        )
        let summaries = BuildAuditFixture.packets
            .filter(\.isBuildStatusPacket)
            .map(BuildStatusSummary.init(packet:))
        let threads = BuildThreadProjection.make(
            branches: surface.branches,
            summaries: summaries,
            isStale: false
        )

        XCTAssertEqual(threads.count, 21)
        XCTAssertEqual(
            Array(BuildThreadPaging.window(items: threads, start: 0)).map(\.title),
            [
                "bio workout archive",
                "keep the attention lane",
                "build the walk rig",
                "stage the next pass",
                "lab ingest apply",
                "answer the proof gate",
                "land the quiet slice",
            ]
        )
        XCTAssertEqual(
            Array(BuildThreadPaging.window(items: threads, start: 7)).map(\.title),
            [
                "holon landing",
                "retro capture matrix",
                "iphone compact pass",
                "meal photo backfill",
                "values card sweep",
                "dossier polish",
                "nav dot audit",
            ]
        )
        XCTAssertEqual(BuildThreadPaging.laterCount(itemCount: threads.count, start: 0), 14)
        XCTAssertEqual(BuildThreadPaging.earlierCount(itemCount: threads.count, start: 7), 7)
        XCTAssertEqual(BuildThreadPaging.laterCount(itemCount: threads.count, start: 7), 7)
        XCTAssertTrue(threads.contains { $0.title == "holon landing" && $0.isStale })
        XCTAssertNil(threads.first { $0.title == "nav dot audit" }?.doneAgingLabel)

        let lines = BuildStreamComposer.lines(
            packets: BuildAuditFixture.packets,
            localCards: [:],
            connectionState: KConnectionStateModel()
        )
        XCTAssertFalse(lines.contains { $0.text.contains("holon landing") })
    }

    func testProposalBranchNameProjectsThroughExistingPlanContext() {
        let card = BuildCard(
            id: "proposal",
            planId: "plan-2026-08-12-quiet-slice",
            title: "raw title",
            what: "Build the quiet slice"
        )

        XCTAssertEqual(BuildTrunkBranchName.from(card: card), "quiet-slice")
    }
}
