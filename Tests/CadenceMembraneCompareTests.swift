import XCTest
@testable import K

/// The membrane compare surface (challenger-jut) — seam/congruence gating,
/// wire decode, verdict persistence, demo fabrication, and k-copy shape.
final class CadenceMembraneCompareTests: XCTestCase {

    // MARK: - gating

    func testChallengerPresentsAtSeam() throws {
        let presentation = try seamPresentation()
        let model = CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(),
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        )

        let compare = try XCTUnwrap(model)
        XCTAssertEqual(compare.date, "2026-07-06")
        XCTAssertEqual(compare.candidateBlockId, "work-2")
        XCTAssertEqual(compare.incumbentBlockId, "routine-1")
        XCTAssertEqual(compare.challengerTitle, "deep work")
        XCTAssertEqual(compare.deltaText, "+18%")
        // The projected challenger carries the incumbent's slot, not its own.
        XCTAssertEqual(compare.challengerTimeText, "09:00")
        XCTAssertEqual(compare.challengerRing, .core)
        XCTAssertEqual(compare.incumbentTitle, "orient")
    }

    func testMidFlowIsSilent() throws {
        // The incumbent itself started: mid-flow, never a compare.
        let startedIncumbent = try seamPresentation(incumbentActionState: .started)
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(),
            presentation: startedIncumbent,
            localVerdicts: [:],
            calendar: utcCalendar
        ))

        // Any other started block also means mid-flow.
        let startedElsewhere = try seamPresentation(challengerActionState: .started)
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(),
            presentation: startedElsewhere,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    func testIncumbentMismatchIsSilent() throws {
        // The rescore names a different incumbent than the card on screen:
        // a stale rescore never presents as a live one.
        let presentation = try seamPresentation()
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(incumbentBlockId: "some-other-block"),
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    func testDateMismatchIsSilent() throws {
        let presentation = try seamPresentation()
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(date: "2026-07-05"),
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    func testQuietRescoreIsSilent() throws {
        let presentation = try seamPresentation()
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: CadenceRescoreResponse(ok: true, date: "2026-07-06", surface: false),
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: nil,
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    func testAnsweredSeamStaysCollapsed() throws {
        let presentation = try seamPresentation()
        let verdicts = [CadenceMembraneVerdictStore.key(date: "2026-07-06", candidateBlockId: "work-2"): true]
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(),
            presentation: presentation,
            localVerdicts: verdicts,
            calendar: utcCalendar
        ))
    }

    func testNudgeOnIncumbentIsSilent() throws {
        // A resident nudge already owns the card's ask register — the jut
        // never stacks a second one (one-slot in spirit).
        let presentation = try seamPresentation(incumbentNudge: true)
        XCTAssertNil(CadenceMembraneCompareLogic.compareModel(
            rescore: rescore(),
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    // MARK: - wire decode

    func testRescoreResponseDecodesRouteShape() throws {
        let json = """
        {
          "ok": true,
          "date": "2026-07-06",
          "surface": true,
          "reason": "higher_eval",
          "headline": {
            "candidateBlockId": "work-2",
            "incumbentBlockId": "routine-1",
            "evalDelta": 0.18
          },
          "alternativeDay": {
            "date": "2026-07-06",
            "blocks": [
              {"id":"work-2","title":"Deep Work","mode":"converge","type":"work","ring":"core","startAt":"09:00","endAt":"10:00","evalDelta":0.18}
            ]
          },
          "graduation": {"body": {"challengerWins": 0, "threshold": 5, "isDefault": false}}
        }
        """
        let response = try JSONDecoder().decode(CadenceRescoreResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.surface, true)
        XCTAssertEqual(response.headline?.candidateBlockId, "work-2")
        XCTAssertEqual(response.headline?.incumbentBlockId, "routine-1")
        XCTAssertEqual(response.headline?.evalDelta ?? 0, 0.18, accuracy: 0.0001)
        XCTAssertEqual(response.alternativeDay?.resolvedBandish.first?.id, "work-2")
    }

    func testRescoreSilenceShapeDecodes() throws {
        let json = #"{"ok":true,"date":"2026-07-06","surface":false,"reason":"within_noise","headline":null}"#
        let response = try JSONDecoder().decode(CadenceRescoreResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.surface, false)
        XCTAssertNil(response.headline)
    }

    // MARK: - delta copy

    func testDeltaTextFormatting() {
        XCTAssertEqual(CadenceMembraneCopy.deltaText(0.18), "+18%")
        XCTAssertEqual(CadenceMembraneCopy.deltaText(0.12), "+12%")
        XCTAssertEqual(CadenceMembraneCopy.deltaText(0.4), "+40%")
    }

    // MARK: - verdict persistence

    func testVerdictStoreRoundtripAndPrunesOldDays() throws {
        let suiteName = "membrane-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CadenceMembraneVerdictStore(defaults: defaults)

        var verdicts = store.load()
        XCTAssertTrue(verdicts.isEmpty)

        verdicts[CadenceMembraneVerdictStore.key(date: "2026-07-05", candidateBlockId: "old")] = true
        verdicts[CadenceMembraneVerdictStore.key(date: "2026-07-06", candidateBlockId: "work-2")] = false
        store.save(verdicts, date: "2026-07-06")

        let reloaded = store.load()
        XCTAssertEqual(reloaded, ["2026-07-06|work-2": false])
    }

    // MARK: - demo seed

    func testDemoRescoreProjectsChallengerIntoIncumbentSlot() throws {
        let presentation = try seamPresentation()
        let demo = try XCTUnwrap(CadenceMembraneDemo.rescore(for: presentation))
        XCTAssertEqual(demo.surface, true)
        XCTAssertEqual(demo.headline?.incumbentBlockId, "routine-1")
        XCTAssertEqual(demo.headline?.candidateBlockId, "work-2")
        let challenger = try XCTUnwrap(demo.alternativeDay?.resolvedBandish.first)
        // Projected into the incumbent's slot, as the daemon's projection does.
        XCTAssertEqual(challenger.startAt, presentation.nowBlock?.block.startAt)
        XCTAssertEqual(challenger.endAt, presentation.nowBlock?.block.endAt)

        // The demo rescore passes the same gate as a real one.
        XCTAssertNotNil(CadenceMembraneCompareLogic.compareModel(
            rescore: demo,
            presentation: presentation,
            localVerdicts: [:],
            calendar: utcCalendar
        ))
    }

    func testDemoDayCarriesASeamAtAnyHour() throws {
        // The demo day anchors to the clock, so the compare surface is
        // presentable whenever the demo runs — unlike the fixed template,
        // whose between-block gaps hide the seam most hours.
        for hourText in ["00:05", "03:30", "10:15", "16:45", "22:10", "23:55"] {
            let now = try date("2026-07-06T\(hourText):00Z")
            let day = CadenceMembraneDemo.demoDay(now: now, calendar: utcCalendar)
            let presentation = CadenceDayPresentation(day: day, now: now, calendar: utcCalendar)
            let incumbent = try XCTUnwrap(presentation.nowBlock, "no now block at \(hourText)")
            XCTAssertEqual(incumbent.actionState, .available)
            let demo = try XCTUnwrap(CadenceMembraneDemo.rescore(for: presentation))
            XCTAssertNotNil(CadenceMembraneCompareLogic.compareModel(
                rescore: demo,
                presentation: presentation,
                localVerdicts: [:],
                calendar: utcCalendar
            ), "demo compare gate closed at \(hourText)")
        }
    }

    // MARK: - k-copy shape

    func testCopyFollowsKCopyLaw() {
        let strings = [
            CadenceMembraneCopy.basisLine,
            CadenceMembraneCopy.trainsLine,
            CadenceMembraneCopy.takeAct,
            CadenceMembraneCopy.keepAct,
            CadenceMembraneCopy.saveFailed,
            CadenceMembraneCopy.tookEcho("Deep Work"),
            CadenceMembraneCopy.keptEcho("Orient"),
        ]
        for string in strings {
            XCTAssertEqual(string, string.lowercased(), "k copy is lowercase: \(string)")
            XCTAssertFalse(string.contains("-"), "no hyphens in k copy: \(string)")
            XCTAssertFalse(string.contains("—"), "no em dashes in k copy: \(string)")
        }
        XCTAssertTrue(CadenceMembraneCopy.basisLine.contains("·"))
        XCTAssertTrue(CadenceMembraneCopy.trainsLine.contains("·"))
        XCTAssertEqual(CadenceMembraneCopy.tookEcho("Deep Work"), "took · deep work")
        XCTAssertEqual(CadenceMembraneCopy.keptEcho("Orient"), "kept · orient")
    }

    // MARK: - fixtures

    /// A seam: the clock sits inside routine-1's window, nothing started.
    /// work-2 is the later, higher-scoring block the membrane offers.
    private func seamPresentation(
        incumbentActionState: CadenceBlockLifecycleState? = nil,
        challengerActionState: CadenceBlockLifecycleState? = nil,
        incumbentNudge: Bool = false
    ) throws -> CadenceDayPresentation {
        let day = CadenceDayEnvelope(
            date: "2026-07-06",
            bandish: [
                CadenceBlock(
                    id: "routine-1",
                    title: "orient",
                    mode: "restore",
                    type: "routine",
                    ring: .outer,
                    startAt: "09:00",
                    endAt: "10:00",
                    actionState: incumbentActionState,
                    nudges: incumbentNudge
                        ? [CadenceNudge(id: "nudge-1", title: "a nudge", blockId: "routine-1")]
                        : []
                ),
                CadenceBlock(
                    id: "work-2",
                    title: "deep work",
                    mode: "converge",
                    type: "work",
                    ring: .core,
                    startAt: "13:00",
                    endAt: "16:00",
                    actionState: challengerActionState
                ),
            ]
        )
        return CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:10:00Z"),
            calendar: utcCalendar
        )
    }

    private func rescore(
        date: String = "2026-07-06",
        incumbentBlockId: String = "routine-1"
    ) -> CadenceRescoreResponse {
        CadenceRescoreResponse(
            ok: true,
            date: date,
            surface: true,
            reason: "higher_eval",
            headline: CadenceRescoreHeadline(
                candidateBlockId: "work-2",
                incumbentBlockId: incumbentBlockId,
                evalDelta: 0.18
            ),
            alternativeDay: CadenceDayEnvelope(
                date: date,
                bandish: [
                    // The daemon projects the challenger into the incumbent's slot.
                    CadenceBlock(
                        id: "work-2",
                        title: "deep work",
                        mode: "converge",
                        type: "work",
                        ring: .core,
                        startAt: "09:00",
                        endAt: "10:00"
                    ),
                ]
            )
        )
    }

    private func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: text))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
