import XCTest
@testable import K

final class BuildReportSurfaceTests: XCTestCase {
    func testBuildAuditFixtureAssemblesPlansGroupsAndDetailRecords() throws {
        XCTAssertTrue(BuildAuditFixture.isEnabled(arguments: ["Kedar", "-builddemo"]))
        XCTAssertFalse(BuildAuditFixture.isEnabled(arguments: ["Kedar"]))

        let statusPackets = BuildAuditFixture.packets.filter(\.isBuildStatusPacket)
        XCTAssertEqual(statusPackets.count, 21)
        XCTAssertEqual(statusPackets.prefix(4).map(\.id), [
            "build-status-plan-bio-workout-archive",
            "build-status-build-demo-plan-rig",
            "build-status-build-demo-plan-attention",
            "build-status-build-demo-plan-landed",
        ])
        XCTAssertEqual(statusPackets.last?.id, "build-status-build-demo-plan-next")

        let surface = BuildReportSurface.make(packets: BuildAuditFixture.packets, openCardCount: 9)
        XCTAssertEqual(surface.rows.map(\.id), [
            "build-demo-plan-attention",
            "plan-bio-workout-archive",
            "build-demo-plan-rig",
            "build-demo-plan-landed",
        ])
        XCTAssertEqual(surface.branches.dropFirst().count, 21)
        XCTAssertEqual(
            Array(surface.branches.dropFirst().prefix(5)).map(\.id),
            [
                "plan-bio-workout-archive",
                "build-demo-plan-rig",
                "build-demo-plan-attention",
                "build-demo-plan-landed",
                "build-demo-plan-next",
            ]
        )

        let rigPacket = try XCTUnwrap(statusPackets.first(where: { $0.id.hasSuffix("plan-rig") }))
        let rig = BuildStatusSummary(packet: rigPacket)
        XCTAssertEqual(rig.units.map(\.id), [
            "build-demo-unit-seed",
            "build-demo-unit-rail",
            "build-demo-unit-capture",
        ])
        XCTAssertEqual(rig.history.map(\.id), [
            "build-demo-history-rig",
            "build-demo-history-rail",
        ])
        XCTAssertEqual(rig.detail, "the selected plan stays visible while its units move through the factory.")
    }

    @MainActor
    func testBuildAuditFixtureModelStartsLiveWithoutCacheOrReport() {
        let model = BuildModel(
            baseURL: "http://daemon.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            arguments: ["Kedar", "-builddemo"]
        )

        model.start()

        XCTAssertEqual(model.statusPacket?.id, "build-status-build-demo-plan-next")
        XCTAssertEqual(model.connectionState.status, .live)
        XCTAssertFalse(model.isStale)
        XCTAssertNil(model.report)
    }

    func testNeedsYouRowsSortOldestStuckFirstAndUseQuietClassWords() {
        let now = ISO8601DateFormatter().date(from: "2026-08-08T00:00:00Z")!
        let rows = [
            BuildNeedsYouList.row(
                id: "aug-06", title: "infra hold", raisedAt: "2026-08-06t09:40:17.046z", status: "raised", now: now
            ),
            BuildNeedsYouList.row(
                id: "jul-24", title: "old blocker", raisedAt: "2026-07-24T12:00:00Z", status: "blocked", now: now
            ),
            BuildNeedsYouList.row(
                id: "jul-26", title: "review", raisedAt: "2026-07-26T12:00:00Z", status: "needs-decision", now: now
            ),
        ]

        let ordered = BuildNeedsYouList.ordered(rows)
        XCTAssertEqual(ordered.map(\.id), ["jul-24", "jul-26", "aug-06"])
        XCTAssertEqual(ordered[0].classWord, "blocked")
        XCTAssertEqual(ordered[1].classWord, "awaiting")
        XCTAssertEqual(ordered[2].timeAgo, "1d ago")
        XCTAssertEqual(ordered[2].line, "1d ago · infra hold · awaiting")
        XCTAssertFalse(ordered[2].line.contains("needs you"))
    }

    func testNeedsYouRowsFallBackToPlanSlugWhenTitleIsMissing() {
        let row = BuildNeedsYouList.row(
            id: "missing-title",
            planID: "plan-2026-08-06-infra-hold",
            title: nil,
            raisedAt: nil,
            status: "held"
        )

        XCTAssertEqual(row.title, "infra-hold")
        XCTAssertEqual(row.planDisplayTitle, "infra-hold")
        XCTAssertFalse(row.planDisplayTitle?.contains("plan-2026") == true)
        XCTAssertFalse(row.line.contains("  ·"))
    }

    func testNeedsYouRowsPreferHumanPlanTitleAndNeverRenderPlanSlug() {
        let row = BuildNeedsYouList.row(
            id: "human-title",
            planID: "plan-2026-08-10-004-feat-build-copy",
            planTitle: "Build copy for founder decisions",
            title: "Plan approval",
            raisedAt: nil,
            status: "raised",
            kind: "plan-approval"
        )

        XCTAssertEqual(row.planDisplayTitle, "build copy for founder decisions")
        XCTAssertFalse(row.planDisplayTitle?.contains("plan-") == true)
    }

    func testNeedsYouRowsChunkByPlanOnlyAfterTenRows() {
        let rows = (0..<11).map { index in
            BuildNeedsYouList.row(
                id: "card-\(index)",
                planID: index < 6 ? "alpha" : "beta",
                planTitle: index < 6 ? "alpha" : "beta",
                title: "decision \(index)",
                raisedAt: nil,
                status: "held"
            )
        }

        let groups = BuildNeedsYouList.groups(rows)
        XCTAssertEqual(groups.map(\.title), ["alpha", "beta"])
        XCTAssertEqual(groups.map { $0.rows.count }, [6, 5])
    }

    func testNeedsYouRowsPrioritizeCriticalKindsBeforeInfraAndBound() {
        let now = ISO8601DateFormatter().date(from: "2026-08-08T00:00:00Z")!
        let rows = [
            BuildNeedsYouList.row(
                id: "bound", title: "Retry limit reached", raisedAt: "2026-07-01T00:00:00Z",
                status: "raised", kind: "bound", now: now
            ),
            BuildNeedsYouList.row(
                id: "line-stop", title: "Verification gate failed", raisedAt: "2026-08-07T00:00:00Z",
                status: "raised", kind: "line-stop", now: now
            ),
            BuildNeedsYouList.row(
                id: "infra", title: "Held unit needs a decision", raisedAt: "2026-07-02T00:00:00Z",
                status: "raised", kind: "infra", now: now
            ),
            BuildNeedsYouList.row(
                id: "safety", title: "Safety floor hold", raisedAt: "2026-08-06T00:00:00Z",
                status: "raised", kind: "safety-floor", now: now
            ),
        ]

        let ordered = BuildNeedsYouList.ordered(rows)
        XCTAssertEqual(ordered.map(\.id), ["safety", "line-stop", "infra", "bound"])
        XCTAssertEqual(ordered.map(\.title), [
            "a protected rule changes — your call",
            "checks failed — what now?",
            "stuck on setup — what now?",
            "out of retries — what now?",
        ])
    }

    func testNeedsYouFoldKeepsCriticalFirstRowsVisible() {
        let rows = (0..<8).map { index in
            BuildNeedsYouList.row(
                id: "card-\(index)",
                title: "decision \(index)",
                raisedAt: nil,
                status: "held",
                kind: index == 7 ? "safety-floor" : "infra"
            )
        }

        let fold = BuildNeedsYouList.fold(rows)
        XCTAssertEqual(fold.visibleRows.count, KStyle.buildNeedsYouVisibleRowLimit)
        XCTAssertEqual(fold.quieterCount, 3)
        XCTAssertEqual(fold.visibleRows.first?.kind, "safety-floor")
        XCTAssertEqual(fold.visibleRows.map(\.id), ["card-7", "card-0", "card-1", "card-2", "card-3"])
    }

    func testEveryKnownBuildCardKindHasFounderVoice() {
        XCTAssertEqual(KCopy.buildCardKinds.count, 9)
        for kind in KCopy.buildCardKinds {
            let mapped = KCopy.buildCardVoiceByKind[kind]
            XCTAssertNotNil(mapped, "missing build voice for \(kind)")
            XCTAssertFalse(mapped?.isEmpty == true, "empty build voice for \(kind)")
            XCTAssertEqual(KCopy.buildCardTitle(kind: kind, rawTitle: ""), mapped)
        }
    }

    func testKnownRunnerPhrasesUseExactFounderVoice() {
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "safety-floor", rawTitle: "Safety floor hold"),
            "a protected rule changes — your call"
        )
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "infra", rawTitle: "Held unit needs a decision"),
            "stuck on setup — what now?"
        )
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "bound", rawTitle: "Retry limit reached"),
            "out of retries — what now?"
        )
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "line-stop", rawTitle: "Verification gate failed"),
            "checks failed — what now?"
        )
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "line-stop", rawTitle: "Runner-core needs hand-harvest"),
            "needs a hand finish — yours or mine"
        )
        XCTAssertEqual(
            KCopy.buildCardTitle(kind: "plan-approval", rawTitle: "Plan approval: ship it"),
            "start this plan?"
        )
    }

    // MARK: state → segment class

    func testSegmentStateMapsUnitStatesToTheFourClasses() {
        // needs-you wins: held and review states pull the founder's eye first.
        XCTAssertEqual(BuildSegmentState.from(unitState: "failed"), .failed)
        XCTAssertEqual(BuildSegmentState.from(unitState: "failed_closed"), .failed)
        XCTAssertEqual(BuildSegmentState.from(unitState: "quarantined"), .failed)
        XCTAssertEqual(BuildSegmentState.from(unitState: "held"), .needsYou)
        XCTAssertEqual(BuildSegmentState.from(unitState: "blocked"), .needsYou)
        XCTAssertEqual(BuildSegmentState.from(unitState: "review_pending"), .needsYou)
        XCTAssertEqual(BuildSegmentState.from(unitState: "gate-human"), .needsYou)

        // done: past-tense completion.
        XCTAssertEqual(BuildSegmentState.from(unitState: "integrated"), .done)
        XCTAssertEqual(BuildSegmentState.from(unitState: "deployed"), .done)
        XCTAssertEqual(BuildSegmentState.from(unitState: "delivered"), .done)
        XCTAssertEqual(BuildSegmentState.from(unitState: "GREEN"), .done)

        // building: in-flight motion, including the -ing forms.
        XCTAssertEqual(BuildSegmentState.from(unitState: "building"), .building)
        XCTAssertEqual(BuildSegmentState.from(unitState: "integrating"), .building)
        XCTAssertEqual(BuildSegmentState.from(unitState: "recovering"), .building)

        // pending / unknown / empty all fall through to dim.
        XCTAssertEqual(BuildSegmentState.from(unitState: "queued"), .pending)
        XCTAssertEqual(BuildSegmentState.from(unitState: "planned"), .pending)
        XCTAssertEqual(BuildSegmentState.from(unitState: "totally-unknown"), .pending)
        XCTAssertEqual(BuildSegmentState.from(unitState: ""), .pending)
        XCTAssertEqual(BuildSegmentState.from(unitState: nil), .pending)
    }

    func testPlanRowSegmentsAndFractionCountDoneOverTotal() {
        let row = BuildPlanRow(
            summary: statusSummary(
                planId: "plan-x",
                title: "membrane",
                units: [("U1", "integrated"), ("U2", "integrated"), ("U3", "held"), ("U4", "queued")]
            )
        )
        XCTAssertEqual(row.segments, [.done, .done, .needsYou, .pending])
        XCTAssertEqual(row.doneCount, 2)
        XCTAssertEqual(row.totalCount, 4)
        XCTAssertEqual(row.fraction, "2/4")
        XCTAssertTrue(row.hasNeedsYou)
        XCTAssertEqual(row.needsYouCount, 1)
    }

    // MARK: nickname

    func testNicknameDistillsAShortSlug() {
        XCTAssertEqual(
            BuildPlanRow.nickname(planId: "plan-2026-07-23-001-feat-build-k-isolated-orchestrator", title: nil),
            "build-k-isolated-orchestrator"
        )
        XCTAssertEqual(
            BuildPlanRow.nickname(planId: "2026-07-23-002-fix-rescue-tag", title: nil),
            "rescue-tag"
        )
        XCTAssertEqual(BuildPlanRow.nickname(planId: "plan-a", title: "Native Build tab"), "native build tab")
        XCTAssertEqual(BuildPlanRow.nickname(planId: nil, title: nil), "plan")
    }

    func testNicknameStripsConventionalCommitPrefixFromSpacedTitles() {
        // "feat:/fix:" is pipeline vocabulary — it must not reach the founder surface.
        XCTAssertEqual(
            BuildPlanRow.nickname(planId: "plan-a", title: "feat: generative blocks labor-0"),
            "generative blocks labor-0"
        )
        XCTAssertEqual(
            BuildPlanRow.nickname(planId: "plan-b", title: "fix: produce ordinary factory releases"),
            "produce ordinary factory releases"
        )
        // The colon is the commit marker: a prose title that merely opens with a
        // type word ("build") is left whole, never clipped to "the membrane".
        XCTAssertEqual(BuildPlanRow.nickname(planId: "plan-c", title: "build the membrane"), "build the membrane")
        XCTAssertEqual(BuildPlanRow.nickname(planId: "plan-d", title: "Native Build tab"), "native build tab")
    }

    // MARK: report-first ordering

    func testReportOrdersNeedsYouFirstThenBuildingThenQuiet() {
        let surface = BuildReportSurface.make(
            packets: [
                statusPacket(planId: "a-building", units: [("U1", "building"), ("U2", "queued")]),
                statusPacket(planId: "b-needs-you", units: [("U1", "held")]),
                statusPacket(planId: "c-done", units: [("U1", "integrated")]),
            ],
            openCardCount: 0
        )
        XCTAssertEqual(surface.rows.map(\.id), ["b-needs-you", "a-building", "c-done"])
    }

    func testReportLeadsWithPlanRowsAndKeepsCardsSeparate() {
        // A build-card packet in the stream must not become a plan row — the report leads
        // with plans; decisions are a separate, collapsed count.
        let surface = BuildReportSurface.make(
            packets: [
                statusPacket(planId: "plan-1", units: [("U1", "building")]),
                cardPacket(id: "card-1"),
            ],
            openCardCount: 3
        )
        XCTAssertEqual(surface.rows.map(\.id), ["plan-1"])
        XCTAssertEqual(surface.waiting, 3)
    }

    // MARK: parked summary

    func testParkedLineFormatsBuildingOverflowAndWaiting() {
        XCTAssertEqual(
            BuildReportSurface.parkedLine(building: 2, waiting: 46),
            "+2 building · 46 waiting on decisions"
        )
        XCTAssertEqual(BuildReportSurface.parkedLine(building: 0, waiting: 46), "46 waiting on decisions")
        XCTAssertEqual(BuildReportSurface.parkedLine(building: 3, waiting: 0), "+3 building")
        XCTAssertNil(BuildReportSurface.parkedLine(building: 0, waiting: 0))
    }

    func testOverflowPlansRollIntoTheParkedBuildingCount() {
        // Five building plans: four surface as rows, the fifth's building unit parks.
        let packets = (1...5).map { statusPacket(planId: "plan-\($0)", units: [("U1", "building")]) }
        let surface = BuildReportSurface.make(packets: packets, openCardCount: 12)

        XCTAssertEqual(surface.rows.count, BuildReportSurface.maxVisiblePlanRows)
        XCTAssertEqual(surface.parkedBuilding, 1)
        XCTAssertEqual(surface.parkedLine, "+1 building · 12 waiting on decisions")
    }

    // MARK: branches

    func testBranchRailLeadsWithTrunkThenPlans() {
        let surface = BuildReportSurface.make(
            packets: [
                statusPacket(planId: "membrane", units: [("U1", "building"), ("U2", "queued")]),
                statusPacket(planId: "mentra", units: [("U1", "held")]),
            ],
            openCardCount: 0
        )
        XCTAssertEqual(surface.branches.first?.id, "trunk")
        XCTAssertTrue(surface.branches.first?.isTrunk == true)
        let mentra = surface.branches.first { $0.id == "mentra" }
        XCTAssertEqual(mentra?.status, "held · needs your 1")
        let membrane = surface.branches.first { $0.id == "membrane" }
        XCTAssertEqual(membrane?.status, "u1 building · 0/2")
        XCTAssertTrue(membrane?.isBuilding == true)
    }

    // MARK: branch grouping (classified from structured unit state, not the display string)

    /// Group of the single non-trunk plan built from these unit states.
    private func groupFor(_ unitStates: [String]) -> BuildBranchGroup? {
        let units = unitStates.enumerated().map { ("u\($0.offset)", $0.element) }
        let surface = BuildReportSurface.make(
            packets: [statusPacket(planId: "p", units: units)],
            openCardCount: 0
        )
        return surface.branches.first { !$0.isTrunk }?.group
    }

    func testBranchGroupHeldIsNeedsYou() {
        XCTAssertEqual(groupFor(["held", "building"]), .needsYou)
    }

    func testBranchGroupFailedIsNeedsYou() {
        // a red plan must never be buried under queued (a red foundation stops the line)
        XCTAssertEqual(groupFor(["failed", "done"]), .needsYou)
    }

    func testBranchGroupBuildingIsBuilding() {
        XCTAssertEqual(groupFor(["building", "queued"]), .building)
    }

    func testBranchGroupCompleteIsDone() {
        XCTAssertEqual(groupFor(["integrated", "deployed"]), .done)
    }

    func testBranchGroupQueuedIsQueued() {
        XCTAssertEqual(groupFor(["queued", "queued"]), .queued)
    }

    func testTrunkHasNoGroup() {
        XCTAssertNil(BuildBranchItem.trunk.group)
    }

    func testRailGroupsCollapseEmptyCategories() {
        let surface = BuildReportSurface.make(
            packets: [
                statusPacket(planId: "building-only", units: [("U1", "building"), ("U2", "queued")]),
                statusPacket(planId: "queued-only", units: [("U1", "queued")]),
            ],
            openCardCount: 0
        )
        let nonTrunk = surface.branches.filter { !$0.isTrunk }
        let groups = Set(nonTrunk.compactMap(\.group))
        XCTAssertEqual(groups, [.building, .queued])
        XCTAssertFalse(groups.contains(.needsYou))
        XCTAssertFalse(groups.contains(.done))
    }

    // MARK: composed title

    func testComposeTitleCapsAtFiveWords() {
        let title = BuildBranchItem.composeTitle("build the membrane with generative blocks and rescue tags")
        XCTAssertLessThanOrEqual(title.split(separator: " ").count, 5)
        XCTAssertEqual(title, "build the membrane with generative")
    }

    func testComposeTitleReplacesHyphensWithSpaces() {
        let title = BuildBranchItem.composeTitle("fix-rescue-tag-on-membrane")
        XCTAssertFalse(title.contains("-"))
        XCTAssertEqual(title, "fix rescue tag on membrane")
    }

    func testComposeTitleIsLowercased() {
        XCTAssertEqual(BuildBranchItem.composeTitle("Native Build tab"), "native build tab")
    }

    func testComposedTitleStoredOnItem() {
        let item = BuildBranchItem(
            id: "t", title: "my-very-long-plan-name-with-seven-words",
            status: "1/3", isTrunk: false, isBuilding: false
        )
        XCTAssertEqual(item.composedTitle, "my very long plan name")
    }

    func testTrunkComposedTitleUncomposed() {
        XCTAssertEqual(BuildBranchItem.trunk.composedTitle, BuildBranchItem.trunk.title)
    }


    // MARK: plan detail jut routing (#26 slice B)
    //
    // iPad (regular, wide enough for the side rail) is the only finalized target: a
    // selection there routes to the rail. iPhone (compact) has no finalized jut design
    // yet, so it stays a plain, safe fallback — absent, same as no selection at all.

    func testPlanDetailRoutesToTheRailOnlyAtRegularWidthWithASelection() {
        XCTAssertEqual(
            BuildPlanDetailLayout.placement(showsSideRail: true, selectedPlanID: "plan-a"),
            .rail
        )
        XCTAssertEqual(
            BuildPlanDetailLayout.placement(showsSideRail: false, selectedPlanID: "plan-a"),
            .absent
        )
    }

    func testPlanDetailIsAbsentWithNoSelectionRegardlessOfWidth() {
        XCTAssertEqual(
            BuildPlanDetailLayout.placement(showsSideRail: true, selectedPlanID: nil),
            .absent
        )
        XCTAssertEqual(
            BuildPlanDetailLayout.placement(showsSideRail: false, selectedPlanID: nil),
            .absent
        )
    }

    // MARK: helpers

    private func statusSummary(
        planId: String,
        title: String,
        units: [(String, String)]
    ) -> BuildStatusSummary {
        BuildStatusSummary(packet: statusPacket(planId: planId, title: title, units: units))
    }

    private func statusPacket(
        planId: String,
        title: String? = nil,
        units: [(String, String)]
    ) -> ViewPacket {
        let unitJSON = units
            .map { #"{"id":"\#($0.0)","state":"\#($0.1)"}"# }
            .joined(separator: ",")
        let titleJSON = title.map { #""title":"\#($0)","# } ?? ""
        let json = #"""
        {
          "id": "status-\#(planId)",
          "viewType": "build.status",
          "text": "\#(planId)",
          "fields": {
            "plan": {"id": "\#(planId)", \#(titleJSON)"state": "building"},
            "units": [\#(unitJSON)]
          }
        }
        """#
        return decodePacket(json)
    }

    private func cardPacket(id: String) -> ViewPacket {
        decodePacket(#"""
        {
          "id": "\#(id)",
          "viewType": "build.card",
          "text": "decide",
          "fields": {"card": {"id": "\#(id)", "title": "decide", "status": "raised", "options": []}}
        }
        """#)
    }

    private func decodePacket(_ json: String) -> ViewPacket {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(ViewPacket.self, from: Data(json.utf8))
    }
}
