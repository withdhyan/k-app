import XCTest
@testable import K

final class CadenceViewTests: XCTestCase {
    func testLifecycleAndRecalibrationFieldsDecodeAdditively() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "core-1",
              "title": "Core",
              "mode": "core",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "10:00",
              "actionState": "started",
              "startedAt": "2026-07-06T09:05:00.000Z",
              "completedAt": "2026-07-06T10:05:00.000Z",
              "elapsedMinutes": 24,
              "progress": 0.4,
              "recalibrationChange": {
                "type": "shift",
                "blockId": "core-1",
                "originalStart": "2026-07-06T09:00:00.000Z",
                "newStart": "2026-07-06T09:15:00.000Z",
                "deltaMinutes": 15
              }
            },
            {
              "id": "outer-1",
              "title": "Outer",
              "mode": "restore",
              "ring": "outer",
              "startAt": "11:00",
              "endAt": "11:30"
            }
          ]
        }
        """)

        let lifecycle = try XCTUnwrap(day.bandish.first)
        XCTAssertEqual(lifecycle.actionState, .started)
        XCTAssertEqual(lifecycle.startedAt, "2026-07-06T09:05:00.000Z")
        XCTAssertEqual(lifecycle.completedAt, "2026-07-06T10:05:00.000Z")
        XCTAssertEqual(lifecycle.elapsedMinutes, 24)
        XCTAssertEqual(lifecycle.progress, 0.4)
        XCTAssertEqual(lifecycle.recalibrationChange?.type, .shift)
        XCTAssertEqual(lifecycle.recalibrationChange?.blockId, "core-1")
        XCTAssertEqual(lifecycle.recalibrationChange?.deltaMinutes, 15)

        let absent = try XCTUnwrap(day.bandish.last)
        XCTAssertNil(absent.actionState)
        XCTAssertNil(absent.startedAt)
        XCTAssertNil(absent.completedAt)
        XCTAssertNil(absent.elapsedMinutes)
        XCTAssertNil(absent.progress)
        XCTAssertNil(absent.recalibrationChange)
    }

    func testDayLevelRecalibrationSummaryDecodesAdditively() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "recalibration": {
            "reason": "wake-init",
            "anchorAt": "2026-07-06T08:12:00.000Z",
            "changes": [
              {"blockId":"core-1","type":"protect","deltaMinutes":12}
            ]
          },
          "recalibrationChanges": [
            {"blockId":"core-1","type":"protect","deltaMinutes":12}
          ],
          "bandish": [
            {"id":"core-1","title":"Core","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"}
          ]
        }
        """)

        XCTAssertEqual(day.recalibration?.reason, "wake-init")
        XCTAssertEqual(day.recalibration?.anchorAt, "2026-07-06T08:12:00.000Z")
        XCTAssertEqual(day.recalibration?.changes.first?.type, .protect)
        XCTAssertEqual(day.recalibrationChanges?.first?.blockId, "core-1")
        XCTAssertEqual(
            CadenceRecalibrationSummaryFormatter.line(for: day.recalibration, calendar: utcCalendar),
            "recalibrated · wake-init 08:12"
        )

        let absent = try decodeDay(#"{"date":"2026-07-06","bandish":[]}"#)
        XCTAssertNil(absent.recalibration)
        XCTAssertNil(absent.recalibrationChanges)
    }

    func testLifecyclePresentationLogicLabelsActionsAndElapsedLine() throws {
        let now = try date("2026-07-06T09:24:00Z")

        let available = CadenceLifecyclePresentationLogic.controlModel(
            actionState: nil,
            startedAt: nil,
            elapsedMinutes: nil,
            progress: nil,
            durationMinutes: 60,
            now: now,
            syncedAt: nil,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )
        XCTAssertEqual(available.optionLabel, "start")
        XCTAssertEqual(available.optionAction, .start)
        XCTAssertTrue(available.rowActions.isEmpty)
        XCTAssertNil(available.elapsedLineText)

        let started = CadenceLifecyclePresentationLogic.controlModel(
            actionState: .started,
            startedAt: "2026-07-06T09:00:00Z",
            elapsedMinutes: 0,
            progress: nil,
            durationMinutes: 60,
            now: now,
            syncedAt: nil,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )
        XCTAssertNil(started.optionLabel)
        XCTAssertEqual(started.rowActions, [.complete])
        XCTAssertEqual(started.elapsedLineText, "24m · elapsed")
        XCTAssertEqual(started.elapsedTimerText, "24:00")
        XCTAssertEqual(started.elapsedSeconds, 1_440)
        XCTAssertEqual(started.progressRatio, 0.4)
        XCTAssertTrue(started.isStarted)

        let paused = CadenceLifecyclePresentationLogic.controlModel(
            actionState: .available,
            startedAt: "2026-07-06T09:00:00Z",
            elapsedMinutes: 12,
            progress: nil,
            durationMinutes: 60,
            now: now,
            syncedAt: nil,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )
        XCTAssertEqual(paused.optionLabel, "resume")
        XCTAssertEqual(paused.optionAction, .start)
        XCTAssertTrue(paused.rowActions.isEmpty)

        let completed = CadenceLifecyclePresentationLogic.controlModel(
            actionState: .completed,
            startedAt: "2026-07-06T09:00:00Z",
            completedAt: "2026-07-06T09:45:00Z",
            elapsedMinutes: 60,
            progress: nil,
            durationMinutes: 60,
            now: now,
            syncedAt: nil,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )
        XCTAssertEqual(completed.optionLabel, "resume")
        XCTAssertEqual(completed.optionAction, .start)
        XCTAssertEqual(completed.elapsedSeconds, 2_700)
        XCTAssertEqual(completed.progressRatio, 0.75)
        XCTAssertFalse(completed.isStarted)
    }

    func testCurrentAvailableBlockStartsOnPlainTapWithoutCueModel() throws {
        let availableDay = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"core-1","title":"Core","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"},
            {"id":"future","title":"Future","mode":"middle","ring":"middle","startAt":"10:30","endAt":"11:00"}
          ]
        }
        """)
        let available = CadenceDayPresentation(
            day: availableDay,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        let current = try XCTUnwrap(available.blocks.first { $0.id == "core-1" })
        let future = try XCTUnwrap(available.blocks.first { $0.id == "future" })
        XCTAssertTrue(current.isNow)
        XCTAssertEqual(current.lifecycleControl.optionLabel, "start")
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(
                isCurrent: current.isNow,
                actionState: current.actionState,
                isPending: current.isPending
            ),
            .start
        )
        XCTAssertFalse(future.isNow)

        let startedDay = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"core-1",
              "title":"Core",
              "mode":"core",
              "ring":"core",
              "startAt":"09:00",
              "endAt":"10:00",
              "actionState":"started",
              "startedAt":"2026-07-06T09:00:00.000Z"
            }
          ]
        }
        """)
        let started = CadenceDayPresentation(
            day: startedDay,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        let startedBlock = try XCTUnwrap(started.blocks.first)
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(
                isCurrent: startedBlock.isNow,
                actionState: startedBlock.actionState,
                isPending: startedBlock.isPending
            ),
            .stayInStream
        )
    }

    func testWakeInitAffordanceCondition() throws {
        let now = try date("2026-07-06T09:00:00Z")
        let initBlock = CadenceBlock(
            id: "init",
            title: "init",
            type: "sleep",
            startAt: "2026-07-05T23:00:00Z",
            endAt: "2026-07-06T07:00:00Z"
        )
        let future = CadenceBlock(
            id: "future",
            title: "future",
            startAt: "10:00",
            endAt: "10:30"
        )

        XCTAssertTrue(CadenceWakeInitLogic.isAvailable(
            blocks: [initBlock, future],
            now: now,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))

        var started = initBlock
        started.actionState = .started
        XCTAssertFalse(CadenceWakeInitLogic.isAvailable(
            blocks: [started, future],
            now: now,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))

        var completedFirst = initBlock
        completedFirst.actionState = .completed
        XCTAssertFalse(CadenceWakeInitLogic.isAvailable(
            blocks: [completedFirst, future],
            now: now,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))

        XCTAssertFalse(CadenceWakeInitLogic.isAvailable(
            blocks: [future],
            now: now,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))
    }

    func testElapsedTimeFormatterUsesMinuteSecondGrammar() {
        XCTAssertEqual(CadenceLifecyclePresentationLogic.formatElapsedTime(0), "0:00")
        XCTAssertEqual(CadenceLifecyclePresentationLogic.formatElapsedTime(9), "0:09")
        XCTAssertEqual(CadenceLifecyclePresentationLogic.formatElapsedTime(75), "1:15")
        XCTAssertEqual(CadenceLifecyclePresentationLogic.formatElapsedTime(3_661), "61:01")
    }

    func testStartedCurrentWorkComposesMockTimerAndPhaseTabs() throws {
        let now = try date("2026-07-06T09:00:00Z")
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "work",
              "title": "the draft",
              "type": "work",
              "attentionMode": "converge",
              "ring": "middle",
              "startAt": "09:00",
              "endAt": "10:30",
              "actionState": "started",
              "startedAt": "2026-07-06T09:00:00Z"
            }
          ]
        }
        """)
        let presentation = CadenceDayPresentation(day: day, now: now, calendar: utcCalendar)
        let current = try XCTUnwrap(presentation.nowBlock)
        let instrument = BandishBodyVariantResolver.presentation(
            for: current.block,
            temporal: .current,
            actionState: current.actionState,
            elapsedSeconds: current.lifecycleControl.elapsedSeconds
        )

        XCTAssertEqual(current.actionState, .started)
        XCTAssertEqual(instrument.kind, .workPreparation)
        XCTAssertEqual(instrument.work?.remainingText, "2:00")
        XCTAssertEqual(instrument.work?.phases.map(\.label), ["settle", "focus", "ready"])
        XCTAssertEqual(instrument.work?.phases.map(\.state), [.active, .pending, .pending])
    }

    func testCadenceCanvasUsesSharedColumnMaximumOnIPad() {
        XCTAssertEqual(
            CadenceCanvasLayout.columnWidth(in: 1_024),
            KStyle.columnMaxWidth
        )
    }

    func testCadenceCanvasUsesFullMeasureInsideMarginsOnCompactWidth() {
        XCTAssertEqual(
            CadenceCanvasLayout.columnWidth(in: 375),
            375 - KStyle.columnMargin * 2
        )
    }

    func testRecalibrationDiffLineFormatter() {
        XCTAssertEqual(
            CadenceRecalibrationDiffFormatter.line(
                for: CadenceRecalibrationChange(
                    type: .shift,
                    blockId: "b1",
                    deltaMinutes: 15,
                    originalStart: "2026-07-06T07:30:00.000Z",
                    newStart: "2026-07-06T07:45:00.000Z"
                ),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            ),
            "shifted 07:30 → 07:45"
        )
        XCTAssertEqual(
            CadenceRecalibrationDiffFormatter.line(
                for: CadenceRecalibrationChange(type: .compress, blockId: "b1", deltaMinutes: 15),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            ),
            "compressed −15m"
        )
        XCTAssertEqual(
            CadenceRecalibrationDiffFormatter.line(
                for: CadenceRecalibrationChange(type: .skip, blockId: "b1"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            ),
            "skipped"
        )
        XCTAssertEqual(
            CadenceRecalibrationDiffFormatter.line(
                for: CadenceRecalibrationChange(type: .protect, blockId: "b1"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            ),
            "protected"
        )
    }

    func testRecalibrationGutterStrikesShiftedStartAndCompressedDuration() throws {
        let shifted = CadenceBlock(
            id: "shifted",
            title: "shifted",
            startAt: "07:45",
            endAt: "08:45",
            recalibrationChange: CadenceRecalibrationChange(
                type: .shift,
                blockId: "shifted",
                originalStart: "2026-07-06T07:30:00Z",
                newStart: "2026-07-06T07:45:00Z"
            )
        )
        let shiftedGutter = CadenceRecalibrationGutterFormatter.gutter(
            for: shifted,
            startText: "07:45",
            durationText: "1:00",
            durationMinutes: 60,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )

        XCTAssertEqual(shiftedGutter.struckStartText, "07:30")
        XCTAssertEqual(shiftedGutter.startText, "07:45")
        XCTAssertNil(shiftedGutter.struckDurationText)

        let compressed = CadenceBlock(
            id: "compressed",
            title: "compressed",
            startAt: "09:00",
            endAt: "10:15",
            recalibrationChange: CadenceRecalibrationChange(
                type: .compress,
                blockId: "compressed",
                deltaMinutes: 15
            )
        )
        let compressedGutter = CadenceRecalibrationGutterFormatter.gutter(
            for: compressed,
            startText: "09:00",
            durationText: "1:15",
            durationMinutes: 75,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )

        XCTAssertEqual(compressedGutter.struckDurationText, "1:30")
        XCTAssertEqual(compressedGutter.durationText, "1:15")
    }

    func testRecalibrationGutterUsesWireBoundariesForCompression() throws {
        let compressed = CadenceBlock(
            id: "work-2",
            title: "work 2",
            type: "work",
            startAt: "18:13",
            endAt: "18:45",
            recalibrationChange: CadenceRecalibrationChange(
                type: .compress,
                blockId: "work-2",
                deltaMinutes: 73,
                originalStart: "2026-07-06T18:13:00Z",
                newStart: "2026-07-06T18:13:00Z",
                originalEnd: "2026-07-06T19:58:00Z",
                newEnd: "2026-07-06T18:45:00Z"
            )
        )

        let gutter = CadenceRecalibrationGutterFormatter.gutter(
            for: compressed,
            startText: "18:13",
            durationText: "0:32",
            durationMinutes: 32,
            dayDate: "2026-07-06",
            calendar: utcCalendar
        )

        XCTAssertEqual(gutter.struckDurationText, "1:45")
        XCTAssertEqual(gutter.durationText, "0:32")
        XCTAssertEqual(
            CadenceRecalibrationDiffFormatter.line(for: compressed.recalibrationChange, dayDate: "2026-07-06", calendar: utcCalendar),
            "compressed −73m"
        )
    }

    func testDayParsingAndNowNextPresentation() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "capacityByMode": {"core": "3", "middle": 1.5},
          "nowBlock": "core-1",
          "bandish": [
            {
              "id": "core-1",
              "title": "Core Work",
              "mode": "core",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "11:00",
              "description": "Draft the shape",
              "nudges": [{"id":"n1","title":"Return call","rank":2}]
            },
            {
              "id": "middle-1",
              "mode": "middle",
              "ring": "middle",
              "startAt": "12:00",
              "endAt": "13:00"
            }
          ],
          "caption": "Plan Ready"
        }
        """)
        let now = try date("2026-07-06T09:30:00Z")
        let presentation = CadenceDayPresentation(day: day, now: now, calendar: utcCalendar)

        XCTAssertEqual(day.capacityByMode["core"], 3)
        XCTAssertEqual(day.bandish.map(\.id), ["core-1", "middle-1"])
        XCTAssertEqual(day.bandish.first?.ring, .core)
        XCTAssertEqual(day.bandish.first?.nudges.first?.blockId, "core-1")
        XCTAssertEqual(presentation.blocks.map(\.timeText), ["09:00\n2:00", "12:00\n1:00"])
        XCTAssertEqual(presentation.blocks.map(\.titleText), ["core work", "middle"])
        XCTAssertEqual(presentation.blocks.map(\.isNow), [true, false])
        XCTAssertEqual(presentation.blocks.map(\.isNext), [false, true])
        XCTAssertTrue(presentation.hasUnresolvedNudge)
    }

    func testOpsChecklistDecodesAndPresentationAppliesLocalToggle() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "ops-1",
              "title": "Ops",
              "mode": "ops",
              "ring": "middle",
              "startAt": "12:00",
              "endAt": "13:00",
              "checklist": [
                {"id":"c1","title":"Confirm deploy","done":false},
                {"id":"c2","title":"Close loop","done":"yes"}
              ]
            }
          ]
        }
        """)
        var localState = CadenceLocalActState()
        localState.applyChecklist(blockId: "ops-1", itemId: "c1", done: true)

        let presentation = CadenceDayPresentation(
            day: day,
            localState: localState,
            now: try date("2026-07-06T12:15:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first?.block)

        XCTAssertTrue(block.showsOpsChecklist)
        XCTAssertEqual(day.bandish.first?.checklist.map(\.id), ["c1", "c2"])
        XCTAssertEqual(block.checklist.map(\.done), [true, true])
    }

    func testNowPanelModelUsesRemainingWhyDetailAndEmptyState() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "workout-1",
              "title": "Strength",
              "mode": "physical",
              "type": "workout",
              "why": "Because the body budget matters",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "10:00",
              "detail": {"plan":["squats","carry"]}
            },
            {
              "id": "middle-1",
              "title": "Middle",
              "mode": "middle",
              "ring": "middle",
              "startAt": "12:00",
              "endAt": "13:00"
            }
          ]
        }
        """)

        let active = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        ).nowPanel

        XCTAssertFalse(active.isEmpty)
        XCTAssertEqual(active.title, "strength")
        XCTAssertEqual(active.whyText, "because the body budget matters")
        XCTAssertEqual(active.metaText, "45m left · physical · core · workout")
        XCTAssertNil(active.detailText)
        XCTAssertEqual(active.content?.detailLines, ["squats · carry · 60m"])

        let empty = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T10:30:00Z"),
            calendar: utcCalendar
        ).nowPanel

        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.title, "no active block")
        XCTAssertEqual(empty.whyText, "the day is between blocks.")
        XCTAssertNil(empty.metaText)
        XCTAssertNil(empty.content)
    }

    func testSubtasksDecodeStringsAndObjectsIntoTypedContent() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "routine-1",
              "title": "Routine",
              "mode": "restore",
              "type": "routine",
              "ring": "outer",
              "startAt": "18:00",
              "endAt": "18:30",
              "subtasks": [
                "Clear desk",
                {"id":"journal","text":"Journal", "timeSensitive": true, "done": "yes"}
              ]
            }
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T17:00:00Z"),
            calendar: utcCalendar
        )
        let content = try XCTUnwrap(presentation.blocks.first?.content)

        XCTAssertEqual(day.bandish.first?.subtasks.map(\.text), ["clear desk", "journal"])
        XCTAssertEqual(day.bandish.first?.subtasks.map(\.timeSensitive), [false, true])
        XCTAssertEqual(content.metaSuffix, "1/2")
        XCTAssertEqual(content.checklist?.map(\.text), ["clear desk", "journal"])
        XCTAssertEqual(content.checklist?.map(\.isDone), [false, true])
    }

    func testActiveDayVisibleWindowKeepsCurrentUpcomingAndImmediatePast() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"past","title":"Past","mode":"restore","ring":"outer","startAt":"08:00","endAt":"08:30"},
            {"id":"now","title":"Core","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"},
            {"id":"next","title":"Lunch","mode":"restore","ring":"outer","startAt":"11:00","endAt":"11:30"},
            {"id":"middle","title":"Middle","mode":"middle","ring":"middle","startAt":"13:00","endAt":"14:00"},
            {"id":"reflect","title":"Reflect","mode":"restore","ring":"outer","startAt":"20:00","endAt":"20:30"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(presentation.nextRow?.timeText, "11:00")
        XCTAssertEqual(presentation.nextRow?.titleText, "lunch")
        XCTAssertEqual(presentation.visibleTimelineBlocks.map(\.id), ["past", "now", "next", "middle", "reflect"])
        XCTAssertTrue(presentation.previousTimelineBlocks.isEmpty)
        XCTAssertNil(presentation.previousToggleText)
    }

    func testTemporalCurrentDerivesFromClockWindowBoundaries() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"core","title":"Core","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"}
          ]
        }
        """)

        let before = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T08:59:00Z"),
            calendar: utcCalendar
        )
        let inside = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:00:00Z"),
            calendar: utcCalendar
        )
        let after = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T10:00:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(before.blocks.first?.isNow, false)
        XCTAssertEqual(before.blocks.first?.hasEnded, false)
        XCTAssertEqual(inside.blocks.first?.isNow, true)
        XCTAssertEqual(inside.blocks.first?.hasEnded, false)
        XCTAssertEqual(after.blocks.first?.isNow, false)
        XCTAssertEqual(after.blocks.first?.hasEnded, true)
    }

    func testStartedOverrunCoexistsWithWindowCurrentBlock() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"meditation",
              "title":"Meditation",
              "mode":"restore",
              "type":"meditation",
              "ring":"core",
              "startAt":"09:00",
              "endAt":"10:00",
              "actionState":"started",
              "startedAt":"2026-07-06T09:05:00Z"
            },
            {
              "id":"work",
              "title":"Work",
              "mode":"core",
              "type":"work",
              "ring":"core",
              "startAt":"10:00",
              "endAt":"11:00"
            },
            {"id":"meal","title":"Meal","mode":"restore","ring":"outer","startAt":"12:00","endAt":"12:30"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T10:15:00Z"),
            calendar: utcCalendar
        )
        let overrun = try XCTUnwrap(presentation.blocks.first { $0.id == "meditation" })
        let current = try XCTUnwrap(presentation.blocks.first { $0.id == "work" })

        XCTAssertFalse(overrun.isNow)
        XCTAssertTrue(overrun.hasEnded)
        XCTAssertEqual(overrun.actionState, .started)
        XCTAssertEqual(overrun.lifecycleControl.elapsedTimerText, "55:00")
        XCTAssertEqual(current.isNow, true)
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(
                isCurrent: current.isNow,
                actionState: current.actionState,
                isPending: current.isPending
            ),
            .start
        )
        XCTAssertEqual(presentation.visibleTimelineBlocks.map(\.id), ["meditation", "work", "meal"])
    }

    func testCompletedStatusOverridesStaleStartedStateAndFreezesAtCompletedAt() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"work-2",
              "title":"Work 2",
              "mode":"core",
              "type":"work",
              "ring":"core",
              "startAt":"12:30",
              "endAt":"14:15",
              "status":"completed",
              "actionState":"started",
              "startedAt":"2026-07-06T12:30:00Z",
              "completedAt":"2026-07-06T14:15:00Z",
              "elapsedMinutes":0
            },
            {"id":"meal","title":"Meal","mode":"restore","ring":"outer","startAt":"19:43","endAt":"20:03"}
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T17:31:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first { $0.id == "work-2" })

        XCTAssertEqual(block.block.completedAt, "2026-07-06T14:15:00Z")
        XCTAssertEqual(block.actionState, .completed)
        XCTAssertFalse(block.lifecycleControl.isStarted)
        XCTAssertNil(block.lifecycleControl.elapsedTimerText)
        XCTAssertEqual(block.lifecycleControl.elapsedSeconds, 6_300)
        XCTAssertEqual(block.lifecycleControl.progressRatio, 1.0)
    }

    func testPastStartedOverrunFreezesAtWindowEndInsteadOfTicking() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"meditation",
              "title":"Meditation",
              "mode":"restore",
              "type":"meditation",
              "ring":"core",
              "startAt":"09:00",
              "endAt":"10:00",
              "actionState":"started",
              "startedAt":"2026-07-06T09:05:00Z"
            }
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T12:30:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first)

        XCTAssertTrue(block.hasEnded)
        XCTAssertEqual(block.actionState, .started)
        XCTAssertEqual(block.lifecycleControl.elapsedSeconds, 3_300)
        XCTAssertEqual(block.lifecycleControl.elapsedTimerText, "55:00")
    }

    func testPastStartedOverrunWithoutStartTimeUsesWindowDurationNotWireElapsed() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"work-2",
              "title":"Work 2",
              "mode":"core",
              "type":"work",
              "ring":"core",
              "startAt":"12:30",
              "endAt":"13:30",
              "actionState":"started",
              "elapsedMinutes":1022
            },
            {"id":"active","title":"Active","mode":"restore","ring":"outer","startAt":"18:58","endAt":"19:28"}
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T18:59:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first { $0.id == "work-2" })

        XCTAssertTrue(block.hasEnded)
        XCTAssertEqual(block.actionState, .started)
        XCTAssertEqual(block.lifecycleControl.elapsedSeconds, 3_600)
        XCTAssertEqual(block.lifecycleControl.elapsedTimerText, "60:00")
    }

    func testPastStartedStatusWithoutActionStateUsesWindowDurationNotWireElapsed() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"work-2",
              "title":"Work 2",
              "mode":"core",
              "type":"work",
              "ring":"core",
              "startAt":"12:30",
              "endAt":"14:00",
              "status":"started",
              "elapsedMinutes":1022
            },
            {"id":"active","title":"Active","mode":"restore","ring":"outer","startAt":"18:58","endAt":"19:28"}
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T18:59:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first { $0.id == "work-2" })

        XCTAssertTrue(block.hasEnded)
        XCTAssertEqual(block.actionState, .started)
        XCTAssertEqual(block.lifecycleControl.elapsedSeconds, 5_400)
        XCTAssertEqual(block.lifecycleControl.elapsedTimerText, "90:00")
    }

    func testPastStartedOverrunClampsStaleStartTimeToWindowDuration() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"work-2",
              "title":"Work 2",
              "mode":"core",
              "type":"work",
              "ring":"core",
              "startAt":"12:30",
              "endAt":"13:30",
              "actionState":"started",
              "startedAt":"2026-07-05T20:28:00Z",
              "elapsedMinutes":1022
            },
            {"id":"active","title":"Active","mode":"restore","ring":"outer","startAt":"18:58","endAt":"19:28"}
          ]
        }
        """)

        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T18:59:00Z"),
            calendar: utcCalendar
        )
        let block = try XCTUnwrap(presentation.blocks.first { $0.id == "work-2" })

        XCTAssertTrue(block.hasEnded)
        XCTAssertEqual(block.actionState, .started)
        XCTAssertEqual(block.lifecycleControl.elapsedSeconds, 3_600)
        XCTAssertEqual(block.lifecycleControl.elapsedTimerText, "60:00")
    }

    func testStreamWindowRollsOnInjectedClockTick() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"older","title":"Older","mode":"restore","ring":"outer","startAt":"07:00","endAt":"07:30"},
            {"id":"previous","title":"Previous","mode":"restore","ring":"outer","startAt":"08:00","endAt":"08:30"},
            {"id":"first","title":"First","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"},
            {"id":"second","title":"Second","mode":"core","ring":"core","startAt":"10:00","endAt":"11:00"},
            {"id":"third","title":"Third","mode":"middle","ring":"middle","startAt":"12:00","endAt":"13:00"}
          ]
        }
        """)

        let firstTick = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:30:00Z"),
            calendar: utcCalendar
        )
        let secondTick = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T10:30:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(firstTick.nowBlock?.id, "first")
        XCTAssertEqual(firstTick.visibleTimelineBlocks.map(\.id), ["previous", "first", "second", "third"])
        XCTAssertEqual(firstTick.previousTimelineBlocks.map(\.id), ["older"])
        // The now-block ("first") is lifted to its own card and excluded from the stream.
        XCTAssertEqual(
            CadenceTimelineOrdering.streamBlocks(for: firstTick, showsEarlier: false).map(\.id),
            ["previous", "second", "third"]
        )
        XCTAssertEqual(
            CadenceTimelineOrdering.streamBlocks(for: firstTick, showsEarlier: true).map(\.id),
            ["older", "previous", "second", "third"]
        )
        XCTAssertEqual(secondTick.nowBlock?.id, "second")
        XCTAssertEqual(secondTick.visibleTimelineBlocks.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(secondTick.previousTimelineBlocks.map(\.id), ["older", "previous"])
    }

    func testInitOnlyDayWindowShowsOnlyTopInitSleepBandish() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"init","title":"init","mode":"sleep","type":"sleep","ring":"core","startAt":"2026-07-05T23:00:00Z","endAt":"2026-07-06T07:00:00Z"},
            {"id":"boot","title":"booting","mode":"restore","type":"routine","ring":"core","startAt":"07:00","endAt":"08:30"},
            {"id":"work","title":"work 1","mode":"convergent","type":"work","ring":"middle","startAt":"10:00","endAt":"11:30"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:00:00Z"),
            calendar: utcCalendar
        )

        XCTAssertTrue(presentation.showsWakeInit)
        XCTAssertEqual(presentation.visibleTimelineBlocks.map(\.id), ["init"])
        XCTAssertTrue(presentation.previousTimelineBlocks.isEmpty)
        XCTAssertEqual(presentation.visibleTimelineBlocks.first?.startsDay, true)
        XCTAssertEqual(presentation.visibleTimelineBlocks.first?.actionState, .available)
    }

    func testCapacityLineFormatsRemainingAndOmitsZeroModes() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "capacityByMode": {"converge": 3, "physical": 1.5, "restore": 0.5},
          "remainingCapacity": {"converge": 120, "physical": 60, "restore": 30, "admin": 0},
          "bandish": [
            {"id":"core","title":"Core","mode":"converge","ring":"core","startAt":"09:00","endAt":"10:00"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(
            presentation.capacityLine?.text,
            "left: converge 2h · physical 1h · restore 30m"
        )
        XCTAssertFalse(presentation.capacityLine?.text.contains("admin") ?? true)
        XCTAssertEqual(presentation.capacityEntries.first { $0.mode == "converge" }?.budgetText, "3h")
        XCTAssertEqual(presentation.capacityEntries.first { $0.mode == "converge" }?.remainingText, "2h")
    }

    func testBandishPrimaryTapRoutingKeepsCurrentBlockInStream() {
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: true, actionState: .available, isPending: false),
            .start
        )
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: true, actionState: .completed, isPending: false),
            .resume
        )
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: true, actionState: .started, isPending: false),
            .stayInStream
        )
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: false, actionState: .available, isPending: false),
            .stayInStream
        )
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: false, actionState: .completed, isPending: false),
            .stayInStream
        )
        XCTAssertEqual(
            CadenceBandishTapRouter.primaryRoute(isCurrent: true, actionState: .available, isPending: true),
            .stayInStream
        )
    }

    func testBandishDrillInExpandsOnlyNonCurrentDetailRowsInPlace() {
        XCTAssertEqual(
            CadenceBandishDrillInPolicy.renderedVariant(temporalVariant: .upcoming, isExpanded: true),
            .current
        )
        XCTAssertEqual(
            CadenceBandishDrillInPolicy.renderedVariant(temporalVariant: .elapsed, isExpanded: false),
            .elapsed
        )
        XCTAssertTrue(CadenceBandishDrillInPolicy.canToggleExpansion(
            temporalVariant: .upcoming,
            isPending: false,
            hasDetail: true
        ))
        XCTAssertFalse(CadenceBandishDrillInPolicy.canToggleExpansion(
            temporalVariant: .current,
            isPending: false,
            hasDetail: true
        ))
        XCTAssertFalse(CadenceBandishDrillInPolicy.canToggleExpansion(
            temporalVariant: .elapsed,
            isPending: true,
            hasDetail: true
        ))
        XCTAssertFalse(CadenceBandishDrillInPolicy.canToggleExpansion(
            temporalVariant: .elapsed,
            isPending: false,
            hasDetail: false
        ))
        XCTAssertTrue(CadenceBandishDrillInPolicy.exposesAuditAnchor(temporalVariant: .elapsed, hasDetail: true))
        XCTAssertFalse(CadenceBandishDrillInPolicy.exposesAuditAnchor(temporalVariant: .current, hasDetail: true))
    }

    func testBandishDrillInDetailCueRequiresHeldContent() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id":"meal-detail",
              "title":"Meal",
              "mode":"middle",
              "type":"meal",
              "ring":"middle",
              "startAt":"10:30",
              "endAt":"11:00",
              "detail":{"composition":["Eggs","Rice"],"protein":40}
            },
            {
              "id":"plain",
              "title":"Plain",
              "mode":"outer",
              "ring":"outer",
              "startAt":"11:30",
              "endAt":"12:00"
            }
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )
        let detailBlock = try XCTUnwrap(presentation.blocks.first { $0.id == "meal-detail" })
        let plainBlock = try XCTUnwrap(presentation.blocks.first { $0.id == "plain" })

        XCTAssertTrue(detailBlock.hasDrillInDetail)
        XCTAssertFalse(plainBlock.hasDrillInDetail)
        XCTAssertTrue(CadenceBandishDrillInPolicy.exposesAuditAnchor(
            temporalVariant: .upcoming,
            hasDetail: detailBlock.hasDrillInDetail
        ))
        XCTAssertFalse(CadenceBandishDrillInPolicy.exposesAuditAnchor(
            temporalVariant: .upcoming,
            hasDetail: plainBlock.hasDrillInDetail
        ))
    }

    func testSensesRailFormatsCapacityNutritionLoggedTodayAndOmitsMissingSources() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "capacityByMode": {"converge": 3, "physical": 1.5},
          "remainingCapacity": {"converge": 120, "physical": 60, "admin": 0},
          "bandish": [
            {
              "id":"body",
              "title":"Body",
              "mode":"restore",
              "ring":"outer",
              "startAt":"07:00",
              "endAt":"07:30",
              "detail":{"body":{"hrv":64,"sleep":"7h12","strain":7}}
            },
            {
              "id":"meal-1",
              "title":"Meal 1",
              "mode":"restore",
              "type":"meal",
              "ring":"outer",
              "startAt":"11:30",
              "endAt":"12:00"
            },
            {
              "id":"meal-2",
              "title":"Meal 2",
              "mode":"restore",
              "type":"meal",
              "ring":"outer",
              "startAt":"18:30",
              "endAt":"19:00"
            }
          ]
        }
        """)
        let now = try date("2026-07-06T12:15:00Z")
        let mealLogs = [
            MealLogRecord(
                timestamp: try date("2026-07-06T11:45:00Z"),
                meal: MealMacroMeasurements(calories: 420, protein: 31),
                blockId: "meal-1"
            ),
            MealLogRecord(
                timestamp: try date("2026-07-06T12:05:00Z"),
                meal: MealMacroMeasurements(calories: 300, protein: 14)
            ),
            MealLogRecord(
                timestamp: try date("2026-07-07T00:05:00Z"),
                meal: MealMacroMeasurements(calories: 900, protein: 90)
            ),
        ]
        let bodyCueContext = BodyCueContext(
            baselines: BodyCueBaselines(
                hrv: 43,
                hrvDrift: BodyCueDrift(latest: 44, baseline: 43, direction: "up")
            ),
            zScores: BodyCueZScores(hrv: BodyCueZScore(zScore: 1.0, windowDays: 30))
        )
        let presentation = CadenceDayPresentation(
            day: day,
            bodyCueContext: bodyCueContext,
            mealLogs: mealLogs,
            now: now,
            calendar: utcCalendar
        )
        let rail = try XCTUnwrap(presentation.sensesRail)

        XCTAssertEqual(rail.groups.map(\.id), ["body", "capacity", "nutrition"])
        XCTAssertEqual(rail.groups.first { $0.id == "body" }?.lines, ["hrv 44 · baseline 43 ↑", "z +1.0 · 30d"])
        XCTAssertEqual(rail.groups.first { $0.id == "capacity" }?.lines, ["converge 2h", "physical 1h"])
        XCTAssertEqual(
            rail.groups.first { $0.id == "nutrition" }?.lines,
            ["logged today · 720 kcal · 45g protein"]
        )
        XCTAssertEqual(presentation.blocks.first { $0.id == "meal-1" }?.mealLogEchoText, "logged · 420 kcal · 31g protein")
        XCTAssertEqual(presentation.blocks.first { $0.id == "meal-1" }?.showsMealLogAffordance, false)
        XCTAssertEqual(presentation.blocks.first { $0.id == "meal-2" }?.showsMealLogAffordance, false)
        XCTAssertEqual(presentation.loggedMealTotals, MealMacroMeasurements(calories: 720, protein: 45))
        XCTAssertNil(MealLogAccumulator.total(in: mealLogs, now: try date("2026-07-08T09:00:00Z"), calendar: utcCalendar))

        let duringMeal = CadenceDayPresentation(
            day: day,
            mealLogs: mealLogs,
            now: try date("2026-07-06T11:45:00Z"),
            calendar: utcCalendar
        )
        XCTAssertEqual(duringMeal.blocks.first { $0.id == "meal-1" }?.showsMealLogAffordance, true)
        XCTAssertEqual(duringMeal.blocks.first { $0.id == "meal-2" }?.showsMealLogAffordance, false)

        let empty = CadenceDayPresentation(
            day: try decodeDay(#"{"date":"2026-07-06","bandish":[{"id":"x","title":"x","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"}]}"#),
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )
        XCTAssertNil(empty.sensesRail)
    }

    func testBodyCueContextDecodingFullMinimalAndProtocolIDs() throws {
        let full = try JSONDecoder().decode(BodyCueContext.self, from: Data("""
        {
          "baselines": {
            "hrv": 43,
            "hrvDrift": {"latest":44,"baseline":43,"delta":1,"direction":"up","samples":8},
            "samples": 12
          },
          "zScores": {
            "hrv": {
              "latest": 44,
              "baselineMean": 43,
              "standardDeviation": 1.2,
              "zScore": 1.0,
              "direction": "up",
              "samples": 20,
              "windowDays": 30
            }
          },
          "protocols": [
            {"id":"p1","target":"recovery","action":"prioritize","object":"sleep_duration","basis":"hrv_trend","confidence":0.7},
            {"interventionId":"p2","target":"recovery","action":"protect","object":"nap","basis":"sleep_debt","confidence":"0.6"},
            {"intervention_id":"p3","target":"training","action":"reduce","object":"intensity","basis":"hrv_z","confidence":0.4},
            {"target":"recovery","action":"prioritize","object":"sleep_duration","basis":"hrv_trend","confidence":0.7}
          ],
          "generatedAt": "2026-07-08T08:00:00Z",
          "source": "Body"
        }
        """.utf8))

        XCTAssertEqual(full.baselines?.hrv, 43)
        XCTAssertEqual(full.baselines?.hrvDrift?.latest, 44)
        XCTAssertEqual(full.baselines?.hrvDrift?.direction, "up")
        XCTAssertEqual(full.zScores?.hrv?.zScore, 1.0)
        XCTAssertEqual(full.zScores?.hrv?.windowDays, 30)
        XCTAssertEqual(full.protocols.map(\.id), ["p1", "p2", "p3", "recovery.prioritize.sleep_duration"])
        XCTAssertEqual(full.protocols.last?.confidence, 0.7)
        XCTAssertEqual(full.generatedAt, "2026-07-08T08:00:00Z")
        XCTAssertEqual(full.source, "body")

        let minimal = try JSONDecoder().decode(BodyCueContext.self, from: Data(#"{"generatedAt":"2026-07-08T08:00:00Z"}"#.utf8))
        XCTAssertEqual(minimal.generatedAt, "2026-07-08T08:00:00Z")
        XCTAssertNil(minimal.baselines)
        XCTAssertNil(minimal.zScores)
        XCTAssertTrue(minimal.protocols.isEmpty)
    }

    func testBodyCueContextRailFormatters() {
        let baselines = BodyCueBaselines(
            hrv: 43,
            hrvDrift: BodyCueDrift(latest: 44, baseline: 43, direction: "up")
        )
        let zScore = BodyCueZScore(zScore: 1.0, windowDays: 30)

        XCTAssertEqual(BodyCueContextRailFormatter.hrvLine(from: baselines), "hrv 44 · baseline 43 ↑")
        XCTAssertEqual(BodyCueContextRailFormatter.hrvLine(from: BodyCueBaselines(
            hrvDrift: BodyCueDrift(latest: 41, baseline: 43, direction: "down")
        )), "hrv 41 · baseline 43 ↓")
        XCTAssertEqual(BodyCueContextRailFormatter.hrvLine(from: BodyCueBaselines(
            hrvDrift: BodyCueDrift(latest: 43, baseline: 43, direction: "steady")
        )), "hrv 43 · baseline 43 →")
        XCTAssertEqual(BodyCueContextRailFormatter.zLine(from: zScore), "z +1.0 · 30d")
        XCTAssertNil(BodyCueContextRailFormatter.hrvLine(from: BodyCueBaselines()))
        XCTAssertNil(BodyCueContextRailFormatter.zLine(from: BodyCueZScore(windowDays: 30)))
        XCTAssertTrue(BodyCueContextRailFormatter.lines(from: BodyCueContext(generatedAt: "2026-07-08T08:00:00Z")).isEmpty)
    }

    func testBodyCueProtocolRowFormatterNormalizesUnderscores() {
        let item = BodyCueProtocol(
            target: "recovery",
            action: "prioritize",
            object: "sleep_duration",
            basis: "hrv_trend",
            confidence: 0.7
        )

        XCTAssertEqual(BodyCueProtocolFormatter.line(for: item), "prioritize sleep duration · hrv trend · 0.7")
    }

    func testBioTodayFitnessDecodeIsAdditive() throws {
        let artifact = try JSONDecoder().decode(BioArtifactsResponse.self, from: Data("""
        {
          "ok": true,
          "today": {
            "recovery": 84,
            "strain": {"score": 7.6},
            "sleep": {"score": "92"},
            "workout": {"calories": 512},
            "cycle": {"kcal": "430"}
          }
        }
        """.utf8))

        XCTAssertEqual(artifact.today?.recovery?.primaryValue, 84)
        XCTAssertEqual(artifact.today?.strain?.primaryValue, 7.6)
        XCTAssertEqual(artifact.today?.sleep?.primaryValue, 92)
        XCTAssertEqual(artifact.today?.workout?.calorieValue, 512)
        XCTAssertEqual(artifact.today?.cycle?.calorieValue, 430)
    }

    func testMealTextParserGrammarMatrixAndRejects() {
        XCTAssertEqual(
            MealTextParser.parse("meal 420 kcal 31 protein"),
            MealMacroMeasurements(calories: 420, protein: 31)
        )
        XCTAssertEqual(
            MealTextParser.parse("ate 2 eggs 300 cal"),
            MealMacroMeasurements(calories: 300)
        )
        XCTAssertEqual(
            MealTextParser.parse("protein 31 calories 420"),
            MealMacroMeasurements(calories: 420, protein: 31)
        )
        XCTAssertEqual(
            MealTextParser.parse("31g protein 44g carbs 12g fat 7 fiber 9 sugar"),
            MealMacroMeasurements(protein: 31, carbs: 44, fat: 12, fiber: 7, sugar: 9)
        )
        XCTAssertEqual(
            MealTextParser.parse("p 31 c 44 f 12"),
            MealMacroMeasurements(protein: 31, carbs: 44, fat: 12)
        )
        XCTAssertEqual(
            MealTextParser.parse("calories:420 protein=31"),
            MealMacroMeasurements(calories: 420, protein: 31)
        )
        XCTAssertNil(MealTextParser.parse("let's meet at 4"))
        XCTAssertNil(MealTextParser.parse("ate lunch"))
        XCTAssertNil(MealTextParser.parse("meal"))
    }

    func testOlderPastBlocksFoldBehindPreviousToggle() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {"id":"older","title":"Older","mode":"restore","ring":"outer","startAt":"07:00","endAt":"07:30"},
            {"id":"past","title":"Past","mode":"restore","ring":"outer","startAt":"08:00","endAt":"08:30"},
            {"id":"now","title":"Now","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"},
            {"id":"future","title":"Future","mode":"middle","ring":"middle","startAt":"11:00","endAt":"12:00"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(presentation.previousTimelineBlocks.map(\.id), ["older"])
        XCTAssertEqual(presentation.visibleTimelineBlocks.map(\.id), ["past", "now", "future"])
        XCTAssertEqual(presentation.previousToggleText, "SHOW PREVIOUS (1)")
    }

    @MainActor
    func testActIsOptimisticThenReconcilesWithServerDay() async throws {
        let initialDay = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00"}]}
        """
        let reconciledDay = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00","status":"complete"}]}
        """
        let now = try date("2026-07-06T09:30:00Z")
        let recorder = CadenceRequestRecorder(getBodies: [initialDay])
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            nowProvider: { now },
            calendar: utcCalendar
        )
        await model.refresh()

        let block = try XCTUnwrap(model.day.bandish.first)
        recorder.suspendNextPost = true
        model.perform(.complete, on: block)

        XCTAssertTrue(model.localState.completedBlockIDs.contains("core-1"))
        XCTAssertEqual(model.localState.pendingActions["core-1"], .complete)

        recorder.resumeSuspendedPost(body: #"{"ok":true,"day":\#(reconciledDay)}"#)
        await waitUntil { model.localState.pendingActions["core-1"] == nil }

        XCTAssertEqual(model.presentation.blocks.first?.statusText, "complete")
        XCTAssertNil(model.localState.actionErrors["core-1"])
    }

    @MainActor
    func testClockTickPresentationDoesNotSubmitActs() async throws {
        let day = """
        {"date":"2026-07-06","bandish":[{"id":"first","title":"first","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"},{"id":"second","title":"second","mode":"core","ring":"core","startAt":"10:00","endAt":"11:00"}]}
        """
        let recorder = CadenceRequestRecorder(getBodies: [day])
        let modelNow = try date("2026-07-06T09:30:00Z")
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: tempQueueStore(),
            nowProvider: { modelNow },
            calendar: utcCalendar
        )
        await model.refresh()
        let requestCountAfterRefresh = recorder.requests.count

        let before = model.presentation(now: try date("2026-07-06T09:30:00Z"))
        let after = model.presentation(now: try date("2026-07-06T10:30:00Z"))

        XCTAssertEqual(before.nowBlock?.id, "first")
        XCTAssertEqual(after.nowBlock?.id, "second")
        XCTAssertEqual(recorder.requests.count, requestCountAfterRefresh)
        XCTAssertFalse(recorder.requests.contains { $0.httpMethod == "POST" })
        XCTAssertTrue(model.localState.pendingActions.isEmpty)
        XCTAssertTrue(model.localState.queuedActions.isEmpty)
    }

    func testChecklistActBodyShape() async throws {
        let recorder = CadenceRequestRecorder(postBodies: [#"{"ok":true}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        _ = try await client.recordCadenceChecklistAct(blockId: "ops-1", itemId: "c1", done: true)

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/cadence/acts")
        XCTAssertEqual(json["blockId"] as? String, "ops-1")
        XCTAssertEqual(json["action"] as? String, "checklist")
        XCTAssertEqual(json["itemId"] as? String, "c1")
        XCTAssertEqual(json["done"] as? Bool, true)
    }

    func testWakeInitActBodyShape() async throws {
        let recorder = CadenceRequestRecorder(postBodies: [#"{"ok":true}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        _ = try await client.recordCadenceWakeInit()

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/cadence/acts")
        XCTAssertNil(json["blockId"])
        XCTAssertEqual(json["action"] as? String, "wake_init")
    }

    func testMealLogPostBodyShape() async throws {
        let recorder = CadenceRequestRecorder(postBodies: [#"{"ok":true}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        _ = try await client.recordBodyMeal(
            meal: MealMacroMeasurements(calories: 420, protein: 31, carbs: 44),
            timestamp: try date("2026-07-06T12:00:00Z")
        )

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let meal = try XCTUnwrap(json["meal"] as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/body/meal")
        XCTAssertEqual(json["event_type"] as? String, "nutrition_log")
        XCTAssertEqual(json["source"] as? String, "ios")
        XCTAssertEqual(json["timestamp"] as? String, "2026-07-06T12:00:00Z")
        XCTAssertEqual((meal["calories"] as? NSNumber)?.doubleValue, 420)
        XCTAssertEqual((meal["protein"] as? NSNumber)?.doubleValue, 31)
        XCTAssertEqual((meal["carbs"] as? NSNumber)?.doubleValue, 44)
        XCTAssertNil(meal["protein_grams"])
        XCTAssertNil(meal["carbs_grams"])
    }

    @MainActor
    func testChecklistRejectQueuesSilentlyAndKeepsOptimisticState() async throws {
        let initialDay = """
        {"date":"2026-07-06","bandish":[{"id":"ops-1","title":"ops","mode":"ops","ring":"middle","startAt":"12:00","endAt":"13:00","checklist":[{"id":"c1","title":"confirm deploy","done":false}]}]}
        """
        let now = try date("2026-07-06T12:15:00Z")
        let recorder = CadenceRequestRecorder(
            getBodies: [initialDay],
            postBodies: [#"{"ok":false,"error":"older backend"}"#]
        )
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            nowProvider: { now },
            calendar: utcCalendar
        )
        await model.refresh()

        let block = try XCTUnwrap(model.presentation.blocks.first?.block)
        let item = try XCTUnwrap(block.checklist.first)
        model.toggleChecklistItem(item, in: block)

        await waitUntil { !model.localState.queuedChecklistActs.isEmpty }

        XCTAssertEqual(model.localState.checklistDone(blockId: "ops-1", item: item), true)
        XCTAssertEqual(model.localState.queuedChecklistActs, [
            CadenceQueuedChecklistAct(blockId: "ops-1", itemId: "c1", done: true),
        ])
        XCTAssertNil(model.localState.actionErrors["ops-1"])
    }

    @MainActor
    func testOfflineActQueuesAndRestoresOptimisticState() async throws {
        let initialDay = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00"}]}
        """
        let now = try date("2026-07-06T09:30:00Z")
        let queueStore = tempQueueStore()
        let recorder = CadenceRequestRecorder(
            getBodies: [initialDay],
            postErrors: [AGUIClientError.stream("offline")]
        )
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { now },
            calendar: utcCalendar
        )
        await model.refresh()

        await model.submit(.complete, blockId: "core-1")

        XCTAssertTrue(model.localState.completedBlockIDs.contains("core-1"))
        XCTAssertEqual(model.localState.queuedActions["core-1"], .complete)
        XCTAssertEqual(model.presentation.blocks.first?.actionCaptionText, "queued · will sync")
        XCTAssertEqual(queueStore.load().map(\.blockId), ["core-1"])

        let restored = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { now },
            calendar: utcCalendar
        )

        XCTAssertTrue(restored.localState.completedBlockIDs.contains("core-1"))
        XCTAssertEqual(restored.localState.queuedActions["core-1"], .complete)
    }

    @MainActor
    func testOfflineActsDrainInOriginalOrderWithEventTimes() async throws {
        let day = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00"}]}
        """
        let startAt = try date("2026-07-06T09:05:00Z")
        let completeAt = try date("2026-07-06T10:42:00Z")
        let queueStore = tempQueueStore()
        queueStore.append(CadenceQueuedAct(blockId: "core-1", action: .start, enqueuedAt: startAt))
        queueStore.append(CadenceQueuedAct(blockId: "core-1", action: .complete, enqueuedAt: completeAt))
        let drainNow = try date("2026-07-06T11:00:00Z")
        let recorder = CadenceRequestRecorder(
            getBodies: [day],
            postBodies: [
                #"{"ok":true,"day":\#(day)}"#,
                #"{"ok":true,"day":\#(day)}"#,
            ]
        )
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { drainNow },
            calendar: utcCalendar
        )

        await model.refresh()

        let postBodies = try recorder.requests
            .filter { $0.httpMethod == "POST" }
            .map { request -> [String: Any] in
                let body = try XCTUnwrap(request.httpBody)
                return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            }
        XCTAssertEqual(postBodies.map { $0["blockId"] as? String }, ["core-1", "core-1"])
        XCTAssertEqual(postBodies.map { $0["action"] as? String }, ["start", "complete"])
        XCTAssertEqual(postBodies.map { $0["eventAt"] as? String }, [
            "2026-07-06T09:05:00Z",
            "2026-07-06T10:42:00Z",
        ])
        XCTAssertEqual(postBodies.map { $0["date"] as? String }, ["2026-07-06", "2026-07-06"])
        XCTAssertTrue(queueStore.load().isEmpty)
    }

    @MainActor
    func testWakeInitQueuesOfflineAndDrainsWithEventTime() async throws {
        let day = """
        {"date":"2026-07-06","bandish":[{"id":"init","title":"sleep","mode":"restore","ring":"outer","startAt":"2026-07-05T23:00:00Z","endAt":"2026-07-06T07:00:00Z"}]}
        """
        let wakeAt = try date("2026-07-06T07:12:00Z")
        let queueStore = tempQueueStore()
        let offline = CadenceRequestRecorder(postErrors: [AGUIClientError.stream("offline")])
        let offlineModel = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: offline.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { wakeAt },
            calendar: utcCalendar
        )

        await offlineModel.submitWakeInit()

        XCTAssertEqual(queueStore.load(), [
            CadenceQueuedAct(blockId: CadenceQueuedAct.wakeInitBlockId, action: .wakeInit, enqueuedAt: wakeAt),
        ])

        let drainNow = try date("2026-07-06T08:00:00Z")
        let recorder = CadenceRequestRecorder(
            getBodies: [day],
            postBodies: [#"{"ok":true,"day":\#(day)}"#]
        )
        let onlineModel = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { drainNow },
            calendar: utcCalendar
        )

        await onlineModel.refresh()

        let post = try XCTUnwrap(recorder.requests.first { $0.httpMethod == "POST" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(post.httpBody)) as? [String: Any])
        XCTAssertNil(json["blockId"])
        XCTAssertEqual(json["action"] as? String, "wake_init")
        XCTAssertEqual(json["eventAt"] as? String, "2026-07-06T07:12:00Z")
        XCTAssertEqual(json["date"] as? String, "2026-07-06")
        XCTAssertTrue(queueStore.load().isEmpty)
    }

    @MainActor
    func testActRejectShowsInlineFailureAndDoesNotQueue() async throws {
        let initialDay = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00"}]}
        """
        let now = try date("2026-07-06T09:30:00Z")
        let queueStore = tempQueueStore()
        let recorder = CadenceRequestRecorder(
            getBodies: [initialDay],
            postBodies: [#"{"ok":false,"error":"rejected"}"#]
        )
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { now },
            calendar: utcCalendar
        )
        await model.refresh()

        await model.submit(.complete, blockId: "core-1")

        XCTAssertTrue(queueStore.load().isEmpty)
        XCTAssertFalse(model.localState.completedBlockIDs.contains("core-1"))
        XCTAssertNil(model.localState.queuedActions["core-1"])
        XCTAssertEqual(model.localState.actionErrors["core-1"], "answer failed · retry")
    }

    @MainActor
    func testRefreshDrainsQueuedActAndShowsLosingWriteCaptionOnFirstWriteConflict() async throws {
        let serverTruth = """
        {"date":"2026-07-06","bandish":[{"id":"core-1","title":"core","mode":"core","ring":"core","startAt":"09:00","endAt":"11:00","status":"skipped"}]}
        """
        let now = try date("2026-07-06T09:30:00Z")
        let queueStore = tempQueueStore()
        queueStore.save([
            CadenceQueuedAct(blockId: "core-1", action: .complete, enqueuedAt: now),
        ])
        let recorder = CadenceRequestRecorder(
            getBodies: [serverTruth],
            postBodies: [
                #"{"ok":false,"alreadyActed":{"surface":"watch","action":"skip"},"day":\#(serverTruth)}"#,
            ]
        )
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: queueStore,
            nowProvider: { now },
            calendar: utcCalendar
        )

        await model.refresh()

        XCTAssertEqual(model.presentation.blocks.first?.statusText, "skipped")
        XCTAssertFalse(model.localState.completedBlockIDs.contains("core-1"))
        XCTAssertTrue(queueStore.load().isEmpty)
        XCTAssertEqual(
            model.presentation.blocks.first?.actionCaptionText,
            "answered earlier from watch · kept that answer"
        )
        XCTAssertEqual(model.accessibilityLog.last, "answered earlier from watch · kept that answer")
    }

    @MainActor
    func testCacheFallbackRendersSavedPlanWithOfflineCaption() async throws {
        let cached = try decodeDay("""
        {"date":"2026-07-06","bandish":[{"id":"saved","title":"saved plan","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"}]}
        """)
        let cache = tempCacheStore()
        cache.save(cached, syncedAt: try date("2026-07-06T08:45:00Z"))
        let now = try date("2026-07-06T09:15:00Z")
        let recorder = CadenceRequestRecorder(getErrors: [AGUIClientError.stream("offline")])
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: cache,
            nowProvider: { now },
            calendar: utcCalendar
        )

        await model.refresh()

        XCTAssertEqual(model.day.bandish.map(\.id), ["saved"])
        XCTAssertEqual(model.presentation.caption, "showing saved plan")
        XCTAssertEqual(model.stalenessText, "as of 08:45")
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
    }

    @MainActor
    func testCacheFallbackRejectsDifferentDateAndUsesDefaultTemplateCopy() async throws {
        let cached = try decodeDay("""
        {"date":"2026-07-05","bandish":[{"id":"yesterday","title":"yesterday","mode":"core","ring":"core","startAt":"09:00","endAt":"10:00"}]}
        """)
        let cache = tempCacheStore()
        cache.save(cached, syncedAt: try date("2026-07-05T08:45:00Z"))
        let now = try date("2026-07-06T09:15:00Z")
        let recorder = CadenceRequestRecorder(getErrors: [AGUIClientError.stream("offline")])
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: cache,
            nowProvider: { now },
            calendar: utcCalendar
        )

        await model.refresh()

        XCTAssertEqual(model.day.date, "2026-07-06")
        XCTAssertFalse(model.day.bandish.contains { $0.id == "yesterday" })
        XCTAssertEqual(model.presentation.caption, "your usual rhythm · k hasn't drafted today")
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
    }

    @MainActor
    func testCadenceSceneForegroundReconnectMovesToConnectingWithoutNetwork() async {
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
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: transport) },
            cacheStore: tempCacheStore(),
            actionQueueStore: tempQueueStore(),
            nowProvider: { Date(timeIntervalSince1970: 0) },
            calendar: utcCalendar
        )

        model.enterForeground()
        await waitUntil { model.connectionState.status == .connecting }

        XCTAssertEqual(model.connectionState.status, .connecting)
        model.enterBackground()
    }

    func testRetroDecodesOptionalEvalHealthShape() throws {
        let response = try JSONDecoder().decode(CadenceRetroResponse.self, from: Data("""
        {
          "ok": true,
          "retro": {
            "weekStart": "2026-07-06",
            "tws": {"trend": 0.7, "responseRate": "0.82"},
            "dreaming": {"hitRate": 0.4},
            "decisionSignal": "strong",
            "motionProgress": {"motion": 12, "progress": "0.5"},
            "goals": [{"title":"ship cadence"}],
            "lists": ["ops"]
          }
        }
        """.utf8))

        let retro = try XCTUnwrap(response.retro)
        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(retro.weekStart, "2026-07-06")
        XCTAssertEqual(retro.tws?.trend, "0.7")
        XCTAssertEqual(retro.tws?.responseRate, "0.82")
        XCTAssertEqual(retro.dreaming?.hitRate, "0.4")
        XCTAssertNil(retro.dreaming?.junkRate)
        XCTAssertEqual(retro.motionProgress?.motion, "12")
        XCTAssertEqual(retro.goals, ["ship cadence"])
        XCTAssertEqual(retro.lists, ["ops"])
    }

    func testRetroV3DecodesRichWeeksAdditively() throws {
        let response = try JSONDecoder().decode(CadenceRetroResponse.self, from: Data("""
        {
          "ok": true,
          "retro": {
            "weekStart": "2026-08-04",
            "tws": {"trend": 0.7},
            "weeks": [{
              "id": "2026-08-04",
              "start": "2026-08-04",
              "end": "2026-08-10",
              "verdict": "held the line; embodiment slipped twice.",
              "onTargetDays": 5,
              "totalDays": 7,
              "acts": 23,
              "skips": 2,
              "rcaReadyCount": 1,
              "vsLastWeek": -1,
              "held": [{"what":"deep work", "acts":5}],
              "slipped": ["embodiment"],
              "rca": {"why":["sleep", "late review", "serialized reviews"], "fixableCause":"reviews after 22:00"},
              "nextWeek": {"bet":"close reviews by 21:30", "check":"score it next retro"}
            }]
          }
        }
        """.utf8))

        let retro = try XCTUnwrap(response.retro)
        let week = try XCTUnwrap(retro.surfaceWeeks.first)
        XCTAssertEqual(retro.weekStart, "2026-08-04")
        XCTAssertEqual(retro.tws?.trend, "0.7")
        XCTAssertEqual(week.id, "2026-08-04")
        XCTAssertEqual(week.normalizedScore?.numerator, 5)
        XCTAssertEqual(week.normalizedScore?.denominator, 7)
        XCTAssertEqual(week.held.first?.text, "deep work")
        XCTAssertEqual(week.held.first?.acts, 5)
        XCTAssertEqual(week.slipped.first?.text, "embodiment")
        XCTAssertEqual(week.rca?.why.count, 3)
        XCTAssertEqual(week.rca?.fixableCause, "reviews after 22:00")
        XCTAssertEqual(week.nextWeek?.bet, "close reviews by 21:30")
        XCTAssertEqual(week.nextWeek?.check, "score it next retro")
        XCTAssertEqual(
            CadenceRetroDateFormatter.rangeText(start: week.start, end: week.end),
            "AUG 4–10"
        )
    }

    func testRetroV3DemoIsDeterministicAndHasFourWeeks() {
        let weeks = CadenceWeeklyRetroDemo.retro.surfaceWeeks

        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks.map(\.id), ["2026-08-04", "2026-07-28", "2026-07-21", "2026-07-14"])
        XCTAssertEqual(weeks.first?.normalizedScore?.numerator, 5)
        XCTAssertEqual(weeks.first?.normalizedScore?.denominator, 7)
        XCTAssertEqual(weeks.first?.acts, 23)
        XCTAssertEqual(weeks.first?.skips, 2)
        XCTAssertEqual(weeks.first?.rcaReadyCount, 1)
        XCTAssertEqual(weeks.first?.rca?.why.count, 3)
        XCTAssertEqual(weeks.first?.nextWeek?.bet, "reviews close by 21:30; mobility block moves to 07:30 fixed.")
    }

    @MainActor
    func testRetroCardOnlyAppearsAtOrAfterTheWeekEnd() async throws {
        let recorder = CadenceRequestRecorder(getBodies: ["""
        {"ok":true,"retro":{"weeks":[{
          "id":"2026-08-04","start":"2026-08-04","end":"2026-08-10",
          "verdict":"held","onTargetDays":5,"totalDays":7
        }]}}
        """])
        let model = CadenceWeeklyRetroModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.refresh()

        XCTAssertFalse(model.shouldShowInCadenceFlow(dayDate: "2026-08-09", calendar: utcCalendar))
        XCTAssertTrue(model.shouldShowInCadenceFlow(dayDate: "2026-08-10", calendar: utcCalendar))
    }

    func testRetroRequestPath() async throws {
        let recorder = CadenceRequestRecorder(getBodies: [#"{"ok":true,"retro":{"weekStart":"2026-07-06"}}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        let response = try await client.cadenceRetro()

        XCTAssertEqual(response.retro?.weekStart, "2026-07-06")
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/api/cadence/retro")
    }

    func testBodySummaryRequestPath() async throws {
        let recorder = CadenceRequestRecorder(getBodies: [#"{"globalBodyState":"ready","hrv":{"latest":43}}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        let response = try await client.bodySummary()

        XCTAssertEqual(response.globalBodyState, "ready")
        XCTAssertEqual(response.hrv?.latest, 43)
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/api/body/summary")
    }

    func testBodyCueContextAndFeedbackRequestShape() async throws {
        let recorder = CadenceRequestRecorder(
            getBodies: [#"{"generatedAt":"2026-07-08T08:00:00Z","protocols":[]}"#],
            postBodies: [#"{"ok":true,"record":{"action":"accept"}}"#]
        )
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        let context = try await client.bodyCueContext()
        let response = try await client.recordBodyInterventionFeedback(
            interventionId: "recovery.prioritize.sleep_duration",
            action: .accept,
            packetId: "packet-1",
            timestamp: try date("2026-07-06T09:15:00Z")
        )

        XCTAssertEqual(context.generatedAt, "2026-07-08T08:00:00Z")
        XCTAssertEqual(response.ok, true)
        XCTAssertEqual(response.record?.action, .accept)
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/api/body/cue-context")

        let request = try XCTUnwrap(recorder.requests.last)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/body/interventions/feedback")
        XCTAssertEqual(json["interventionId"] as? String, "recovery.prioritize.sleep_duration")
        XCTAssertEqual(json["action"] as? String, "accept")
        XCTAssertEqual(json["packetId"] as? String, "packet-1")
        XCTAssertEqual(json["timestamp"] as? String, "2026-07-06T09:15:00Z")
        XCTAssertNil(json["intervention_id"])
        XCTAssertNil(json["feedback"])
    }

    @MainActor
    func testRetro404UsesOlderBackendCopy() async {
        let recorder = CadenceRequestRecorder(getErrors: [AGUIClientError.httpStatus(404)])
        let model = CadenceWeeklyRetroModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.refresh()

        XCTAssertEqual(model.failureText, CadenceWeeklyRetroModel.olderBackendText)
        XCTAssertNil(model.retro)
    }

    func testEmptyBandishRendersDefaultTemplateShape() throws {
        let day = try decodeDay(#"{"date":"2026-07-06","bandish":[]}"#)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-06T07:00:00Z"),
            calendar: utcCalendar
        )

        XCTAssertTrue(presentation.isDefaultDay)
        XCTAssertEqual(presentation.caption, CadenceCopy.defaultDayCaption)
        XCTAssertFalse(presentation.blocks.isEmpty)
    }

    func testCadenceDotLogicAndTabOrder() {
        let items = KTabStripModel.items(
            active: .cadence,
            cadenceNeedsAttention: true,
            chatHasUnread: true,
            openBuildCards: 1,
            unjudgedMindOutputs: 1,
            adminDueTodayItems: 0,
            staleTabs: [.cadence]
        )

        XCTAssertEqual(items.map(\.title), ["cadence", "chat", "build", "mind", "bio", "admin"])
        XCTAssertEqual(items.map(\.showsDot), [true, true, true, true, false, false])
        XCTAssertEqual(items.map(\.isActive), [true, false, false, false, false, false])
        XCTAssertEqual(items.first?.dotOpacity, KStyle.primaryTextOpacity * KStyle.staleDotFactor)
    }

    func testWaitingSummarySegmentsOnlyRenderWaitingCounts() {
        XCTAssertEqual(
            KWaitingSummaryModel.segments(buildCards: 2, reviewCards: 1, unjudged: 3).map(\.label),
            ["2 build cards", "1 review card", "3 unjudged"]
        )
        XCTAssertTrue(KWaitingSummaryModel.segments(buildCards: 0, reviewCards: 0, unjudged: 0).isEmpty)
    }

    func testReviewCardSlotTimingAndDismissal() throws {
        let morning = CadenceReviewCard(id: "m", type: "morning-orientation", date: "2026-07-06")
        let evening = CadenceReviewCard(id: "e", type: "evening-reflection", date: "2026-07-06")

        XCTAssertEqual(
            CadenceReviewSlotModel.dueCard(
                from: [morning, evening],
                dismissedIDs: [],
                now: try date("2026-07-06T09:00:00Z"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            )?.id,
            "m"
        )
        XCTAssertNil(CadenceReviewSlotModel.dueCard(
            from: [morning, evening],
            dismissedIDs: [],
            now: try date("2026-07-06T15:00:00Z"),
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))
        XCTAssertNil(CadenceReviewSlotModel.dueCard(
            from: [morning, evening],
            dismissedIDs: ["e"],
            now: try date("2026-07-06T20:00:00Z"),
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))
        XCTAssertEqual(
            CadenceReviewSlotModel.dueCard(
                from: [morning, evening],
                dismissedIDs: [],
                now: try date("2026-07-06T20:00:00Z"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            )?.id,
            "e"
        )
    }

    func testAnsweredValueProbeCardIsNotDueButUnansweredIs() throws {
        func probeCard(answered: Bool) -> CadenceReviewCard {
            let answer: CadenceValueProbeAnswerAnchor? = answered
                ? CadenceValueProbeAnswerAnchor(selectedOptionId: "left", selectedLabel: "say it plainly", selectedValue: "plain")
                : nil
            let probe = CadenceValueProbe(
                id: "vp-1",
                ordinal: 1,
                question: "which is more you?",
                options: [CadenceValueProbeOption(id: "left", label: "say it plainly", value: "plain")],
                answer: answer
            )
            return CadenceReviewCard(
                id: "vp-card",
                type: "value-probe",
                date: "2026-07-06",
                valueProbes: CadenceValueProbeReview(count: 1, probes: [probe])
            )
        }

        XCTAssertEqual(
            CadenceReviewSlotModel.dueCard(
                from: [probeCard(answered: false)],
                dismissedIDs: [],
                now: try date("2026-07-06T09:00:00Z"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            )?.id,
            "vp-card"
        )
        XCTAssertNil(CadenceReviewSlotModel.dueCard(
            from: [probeCard(answered: true)],
            dismissedIDs: [],
            now: try date("2026-07-06T09:00:00Z"),
            dayDate: "2026-07-06",
            calendar: utcCalendar
        ))
    }

    func testValueProbeCardDecodesFullShapeAndAbsentPayloadKeepsExistingBehavior() throws {
        let response = try JSONDecoder().decode(CadenceReviewCardsResponse.self, from: Data("""
        {
          "cards": [
            {
              "id": "review-2026-07-06-value-probe",
              "type": "value-probe",
              "date": "2026-07-06",
              "title": "Value probes",
              "valueProbes": {
                "weekStart": "2026-07-06",
                "weekEnd": "2026-07-12",
                "maxProbes": 3,
                "count": 1,
                "answeredCount": 0,
                "probes": [
                  {
                    "id": "vp-2026-07-06-truth",
                    "ordinal": 1,
                    "axis": "truth",
                    "prompt": "which is more you?",
                    "question": "which is more you?",
                    "shape": "which-is-more-you",
                    "forcedChoice": true,
                    "options": [
                      {"id":"left","label":"Say it plainly","value":"plain","position":"left"},
                      {"id":"right","label":"Keep it smooth","value":"smooth","position":"right"}
                    ],
                    "sourceEvidence": [{"source":"soul"}]
                  }
                ],
                "answerAction": {
                  "method": "POST",
                  "path": "/api/cadence/value-probes/answers",
                  "body": {"cardId":"review-2026-07-06-value-probe","answers":[]}
                }
              }
            },
            {
              "id": "review-m",
              "type": "morning-orientation",
              "date": "2026-07-06",
              "sections": [{"id":"s","title":"shape","body":"Start clean"}]
            }
          ]
        }
        """.utf8))

        let card = try XCTUnwrap(response.cards.first)
        let valueProbes = try XCTUnwrap(card.valueProbes)
        let probe = try XCTUnwrap(valueProbes.probes.first)

        XCTAssertEqual(card.type, "value-probe")
        XCTAssertTrue(card.isValueProbeCard)
        XCTAssertEqual(valueProbes.weekStart, "2026-07-06")
        XCTAssertEqual(valueProbes.weekEnd, "2026-07-12")
        XCTAssertEqual(valueProbes.maxProbes, 3)
        XCTAssertEqual(valueProbes.count, 1)
        XCTAssertEqual(valueProbes.answeredCount, 0)
        XCTAssertEqual(probe.id, "vp-2026-07-06-truth")
        XCTAssertEqual(probe.ordinal, 1)
        XCTAssertEqual(probe.axis, "truth")
        XCTAssertEqual(probe.shape, "which-is-more-you")
        XCTAssertTrue(probe.forcedChoice)
        XCTAssertEqual(probe.options.map(\.position), ["left", "right"])
        XCTAssertEqual(probe.options.map(\.label), ["Say it plainly", "Keep it smooth"])
        XCTAssertEqual(valueProbes.answerAction?.method, "POST")
        XCTAssertEqual(valueProbes.answerAction?.path, "/api/cadence/value-probes/answers")
        XCTAssertEqual(valueProbes.answerAction?.body["cardId"]?.stringValue, "review-2026-07-06-value-probe")

        let generic = try XCTUnwrap(response.cards.last)
        XCTAssertNil(generic.valueProbes)
        XCTAssertEqual(generic.slot, .morning)
        XCTAssertEqual(generic.sections.first?.body, "Start clean")
    }

    func testValueProbeReviewCardIsDueWithoutDailySlot() throws {
        let card = CadenceReviewCard(
            id: "value",
            type: "value-probe",
            date: "2026-07-06",
            valueProbes: CadenceValueProbeReview(
                weekStart: "2026-07-06",
                count: 1,
                probes: [
                    CadenceValueProbe(
                        id: "vp-1",
                        ordinal: 1,
                        question: "which is more you?",
                        options: [
                            CadenceValueProbeOption(id: "left", label: "Left"),
                            CadenceValueProbeOption(id: "right", label: "Right"),
                        ]
                    ),
                ]
            )
        )

        XCTAssertEqual(
            CadenceReviewSlotModel.dueCard(
                from: [card],
                dismissedIDs: [],
                now: try date("2026-07-06T15:00:00Z"),
                dayDate: "2026-07-06",
                calendar: utcCalendar
            ),
            card
        )
    }

    func testValuesV2DemoSeedsAllBlessedStatesDeterministically() throws {
        let ask = CadenceValuesDemo.card(state: .ask)
        let resting = CadenceValuesDemo.card(state: .resting)
        let trail = CadenceValuesDemo.card(state: .trail)
        let attention = CadenceValuesDemo.card(state: .attention)
        let empty = CadenceValuesDemo.card(state: .empty)

        XCTAssertEqual(ask.date, CadenceValuesDemo.date)
        XCTAssertEqual(ask.valueProbes?.probes.first?.question, "did the afternoon hold deep work?")
        XCTAssertEqual(ask.valueProbes?.answerAction?.path, AGUIClient.cadenceValueProbeAnswersPath)
        XCTAssertEqual(resting.valuesCard?.values.count, 4)
        XCTAssertEqual(
            CadenceReviewSlotModel.dueCard(
                from: [resting],
                dismissedIDs: [],
                now: try date("2026-08-10T15:00:00Z"),
                dayDate: CadenceValuesDemo.date,
                calendar: utcCalendar
            )?.id,
            resting.id
        )
        XCTAssertEqual(trail.valuesCard?.initialExpandedValueID, "deep-work")
        XCTAssertEqual(trail.valuesCard?.values.first?.acts.count, 4)
        XCTAssertEqual(attention.valuesCard?.attentionValueID, "embodiment")
        XCTAssertEqual(attention.valuesCard?.values.first?.id, "embodiment")
        XCTAssertEqual(empty.valuesCard?.values.first?.effectiveSignal, CadenceValueSignal.none)
        XCTAssertNil(empty.valuesCard?.values.first?.lastLine)
    }

    @MainActor
    func testWorkoutFixtureKeepsItsDayWhenValuesFixtureIsAlsoPresent() throws {
        let fixtureNow = CadenceValuesDemo.referenceNow
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            cacheStore: tempCacheStore(),
            actionQueueStore: tempQueueStore(),
            nowProvider: { fixtureNow },
            calendar: utcCalendar,
            fixtureArguments: [
                "K",
                "-workoutdemo", "-workoutdemo-state", "mid",
                "-valuesdemo", "-valuesdemo-state", "ask",
            ]
        )

        XCTAssertEqual(model.day.bandish.map(\.id), ["demo-workout-before", "demo-workout", "demo-workout-after"])
        XCTAssertEqual(model.reviewCards.map(\.id), ["review-2026-08-10-value-probe-demo"])
        XCTAssertEqual(model.renderNow(fallback: .distantPast), fixtureNow)
        XCTAssertEqual(model.presentation.nowBlock?.id, "demo-workout")

        model.loadIfNeeded()

        XCTAssertEqual(model.day.bandish.first?.id, "demo-workout-before")
        XCTAssertEqual(model.presentation.nowBlock?.id, "demo-workout")
        XCTAssertEqual(model.reviewCards.map(\.id), ["review-2026-08-10-value-probe-demo"])
        XCTAssertTrue(model.hasLocalFixtureContent)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
    }

    @MainActor
    func testLoadingFixtureOwnsLifecycleWithoutReplacingLocalSeeds() throws {
        let fixtureNow = CadenceValuesDemo.referenceNow
        let model = CadenceModel(
            baseURL: "http://daemon.test",
            cacheStore: tempCacheStore(),
            actionQueueStore: tempQueueStore(),
            nowProvider: { fixtureNow },
            calendar: utcCalendar,
            fixtureArguments: [
                "K",
                "-ui34-loading",
                "-workoutdemo", "-workoutdemo-state", "post",
                "-valuesdemo", "-valuesdemo-state", "trail",
            ]
        )

        XCTAssertEqual(model.day.bandish.map(\.id), ["demo-workout-before", "demo-workout", "demo-workout-after"])
        XCTAssertEqual(model.reviewCards.map(\.id), ["values-demo-trail"])

        model.loadIfNeeded()

        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.connectionState.status, .connecting)
        XCTAssertEqual(model.day.bandish.map(\.id), ["demo-workout-before", "demo-workout", "demo-workout-after"])
        XCTAssertEqual(model.reviewCards.map(\.id), ["values-demo-trail"])

        model.enterBackground()
        model.enterForeground()

        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.connectionState.status, .connecting)
    }

    func testValueProbeProgressionLogic() {
        let probes = [
            CadenceValueProbe(id: "vp-3", ordinal: 3, question: "three"),
            CadenceValueProbe(id: "vp-1", ordinal: 1, question: "one"),
            CadenceValueProbe(id: "vp-2", ordinal: 2, question: "two"),
        ]

        XCTAssertEqual(
            CadenceValueProbeProgression.nextUnansweredOrdinal(
                in: probes,
                answeredProbeIDs: ["vp-1"]
            ),
            2
        )
        XCTAssertEqual(
            CadenceValueProbeProgression.nextUnansweredOrdinal(
                in: probes,
                answeredProbeIDs: ["vp-1", "vp-2", "vp-3"]
            ),
            nil
        )
        XCTAssertEqual(
            CadenceValueProbeProgression.headerCountString(answeredProbeIDs: ["vp-1", "vp-2"], totalCount: 3),
            "2/3 answered"
        )
        XCTAssertEqual(
            CadenceValueProbeProgression.headerCountString(answeredCount: 4, totalCount: 3),
            "3/3 answered"
        )
    }

    func testValueProbeAnswerPostEncodesExactBody() async throws {
        let recorder = CadenceRequestRecorder(postBodies: [#"{"ok":true,"cardId":"card-1"}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)

        let response = try await client.answerCadenceValueProbe(
            cardId: "card-1",
            probeId: "vp-1",
            selectedOptionId: "left"
        )

        XCTAssertEqual(response.ok, true)
        let request = try XCTUnwrap(recorder.requests.last)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let answers = try XCTUnwrap(json["answers"] as? [[String: Any]])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/cadence/value-probes/answers")
        XCTAssertEqual(Set(json.keys), Set(["cardId", "answers"]))
        XCTAssertEqual(json["cardId"] as? String, "card-1")
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers.first?["probeId"] as? String, "vp-1")
        XCTAssertEqual(answers.first?["selectedOptionId"] as? String, "left")
    }

    func testNudgeActDescriptorDecodesAndHelpers() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "core-1",
              "title": "Core",
              "mode": "core",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "10:00",
              "nudges": [
                {
                  "id":"build-card:card-1",
                  "title":"Ship it",
                  "body":"Recommended by build",
                  "what":"plan approval — one build unit is ready",
                  "contrast":"k leans ship: cadence can answer without opening build.",
                  "stakes":"reversible · silence keeps the lane blocked",
                  "evidenceSummary":{
                    "conversationCount":1,
                    "latestAt":"2026-07-06T08:00:00.000Z",
                    "topicHints":["scope"]
                  },
                  "payload":{"signalExplained":"fresh scope evidence."},
                  "blockId":"core-1",
                  "source":"build-card",
                  "category":"build-card",
                  "cardId":"card-1",
                  "optionId":"ship",
                  "buildCard":{
                    "id":"card-1",
                    "optionId":"ship",
                    "what":"plan approval — one build unit is ready",
                    "contrast":"k leans ship: cadence can answer without opening build.",
                    "stakes":"reversible · silence keeps the lane blocked",
                    "brief":{
                      "whyNow":"the block can answer this without opening build.",
                      "openQuestion":"ship it from cadence?",
                      "stakes":"reversible · silence keeps cadence unblocked",
                      "options":[
                        {"id":"ship","whatHappens":"run the lane from cadence."}
                      ]
                    },
                    "options":[
                      {"id":"ship","label":"Ship it","consequence":"run the lane."},
                      {"id":"hold","label":"Hold"}
                    ]
                  },
                  "act":{
                    "method":"POST",
                    "path":"/api/cadence/nudges/disposition",
                    "body":{
                      "date":"2026-07-06",
                      "blockId":"core-1",
                      "nudgeId":"build-card:card-1",
                      "disposition":"act",
                      "cardId":"card-1",
                      "optionId":"ship",
                      "surface":"cadence"
                    }
                  }
                }
              ]
            }
          ]
        }
        """)

        let nudge = try XCTUnwrap(day.bandish.first?.nudges.first)
        XCTAssertEqual(nudge.source, "build-card")
        XCTAssertEqual(nudge.category, "build-card")
        XCTAssertEqual(nudge.buildCardIdFromNudge, "card-1")
        XCTAssertEqual(nudge.recommendedOptionIdFromNudge, "ship")
	        XCTAssertEqual(nudge.recommendedOptionLabel, "Ship it")
	        XCTAssertEqual(nudge.decisionWhat, "plan approval — one build unit is ready")
	        XCTAssertEqual(nudge.decisionContrast, "k leans ship: cadence can answer without opening build.")
	        XCTAssertEqual(nudge.decisionBrief?.openQuestion, "ship it from cadence?")
	        XCTAssertEqual(nudge.decisionBrief?.whatHappens(for: "ship"), "run the lane from cadence.")
	        XCTAssertEqual(nudge.decisionStakes, "reversible · silence keeps cadence unblocked")
        XCTAssertEqual(nudge.decisionEvidenceSummary?.conversationCount, 1)
        XCTAssertEqual(nudge.decisionEvidenceSummary?.topicHints, ["scope"])
        XCTAssertEqual(nudge.decisionSignalExplained, "fresh scope evidence.")
        XCTAssertEqual(nudge.recommendedBuildOption?.consequence, "run the lane.")
        XCTAssertTrue(nudge.isBuildCardActable)
        XCTAssertEqual(nudge.act?.method, "POST")
        XCTAssertEqual(nudge.act?.path, "/api/cadence/nudges/disposition")
        XCTAssertEqual(nudge.act?.body["nudgeId"]?.stringValue, "build-card:card-1")

        let withoutAct = CadenceNudge(id: "n", source: "build-card", cardId: "card-2", optionId: "go")
        XCTAssertFalse(withoutAct.isBuildCardActable)
    }

    func testNudgeActPostUsesEmbeddedDescriptorBody() async throws {
        let recorder = CadenceRequestRecorder(postBodies: [#"{"ok":true}"#])
        let client = AGUIClient(baseURL: "http://daemon.test", transport: recorder.transport)
        let act = CadenceNudgeActDescriptor(
            method: "POST",
            path: "/api/cadence/nudges/disposition",
            body: [
                "date": .string("2026-07-06"),
                "blockId": .string("core-1"),
                "nudgeId": .string("build-card:card-1"),
                "disposition": .string("act"),
                "cardId": .string("card-1"),
                "optionId": .string("ship"),
                "surface": .string("cadence"),
            ]
        )

        let response = try await client.recordCadenceNudgeAct(act)

        XCTAssertEqual(response.ok, true)
        let request = try XCTUnwrap(recorder.requests.last)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/cadence/nudges/disposition")
        XCTAssertEqual(Set(json.keys), Set(["date", "blockId", "nudgeId", "disposition", "cardId", "optionId", "surface"]))
        XCTAssertEqual(json["date"] as? String, "2026-07-06")
        XCTAssertEqual(json["blockId"] as? String, "core-1")
        XCTAssertEqual(json["nudgeId"] as? String, "build-card:card-1")
        XCTAssertEqual(json["disposition"] as? String, "act")
        XCTAssertEqual(json["cardId"] as? String, "card-1")
        XCTAssertEqual(json["optionId"] as? String, "ship")
        XCTAssertEqual(json["surface"] as? String, "cadence")
    }

    func testTopSlotArbiterRanksDueReviewOverNudgeAndQueuesNudge() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "core-1",
              "title": "Core",
              "mode": "core",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "10:00",
              "nudges": [
                {"id":"n1","title":"check posture","blockId":"core-1","rank":1}
              ]
            }
          ]
        }
        """)
        let review = CadenceReviewCard(id: "review-m", type: "morning-orientation", date: "2026-07-06")
        let nudge = try XCTUnwrap(day.bandish.first?.nudges.first)

        let presentation = CadenceDayPresentation(
            day: day,
            reviewCards: [review],
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(presentation.topReviewCard, review)
        XCTAssertEqual(presentation.topNudge, nudge)
        XCTAssertEqual(presentation.topSlot.active, .review(review))
        XCTAssertEqual(presentation.topSlot.queued, .nudge(nudge))

        let afterReviewDismissed = CadenceDayPresentation(
            day: day,
            reviewCards: [review],
            dismissedReviewCardIDs: [review.id],
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertNil(afterReviewDismissed.topReviewCard)
        XCTAssertEqual(afterReviewDismissed.topSlot.active, .nudge(nudge))
        XCTAssertNil(afterReviewDismissed.topSlot.queued)
    }

    func testBodyLivePacketRoutesToExistingTopSlotAndOtherPacketsDoNot() throws {
        let bodyLivePacket = ViewPacket(
            id: "body-live-1",
            viewType: "generic.card",
            text: "ease effort",
            fields: ["interruptionClass": .string("ambient")],
            provenance: ["module": .string("body-live"), "lane": .string("ambient")],
            frontierExcluded: true
        )
        let otherPacket = ViewPacket(
            id: "other-1",
            viewType: "generic.card",
            text: "not body",
            fields: ["interruptionClass": .string("ambient")],
            provenance: ["module": .string("build")],
            frontierExcluded: true
        )
        let day = try decodeDay("""
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "core-1",
              "title": "Core",
              "mode": "core",
              "ring": "core",
              "startAt": "09:00",
              "endAt": "10:00",
              "nudges": [
                {"id":"n1","title":"check posture","blockId":"core-1","rank":1}
              ]
            }
          ]
        }
        """)
        let nudge = try XCTUnwrap(day.bandish.first?.nudges.first)

        XCTAssertEqual(CadenceBodyLivePacketRouter.slotCandidate(from: bodyLivePacket), bodyLivePacket)
        XCTAssertNil(CadenceBodyLivePacketRouter.slotCandidate(from: otherPacket))
        XCTAssertNil(CadenceBodyLivePacketRouter.slotCandidate(from: bodyLivePacket, dismissedIDs: [bodyLivePacket.id]))

        let withoutNudge = CadenceDayPresentation(
            day: try decodeDay(#"{"date":"2026-07-06","bandish":[]}"#),
            bodyLivePacket: bodyLivePacket,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )
        XCTAssertEqual(withoutNudge.topSlot.active, .bodyLive(bodyLivePacket))

        let withNudge = CadenceDayPresentation(
            day: day,
            bodyLivePacket: bodyLivePacket,
            now: try date("2026-07-06T09:15:00Z"),
            calendar: utcCalendar
        )
        XCTAssertEqual(withNudge.topSlot.active, .nudge(nudge))
        XCTAssertEqual(withNudge.topSlot.queued, .bodyLive(bodyLivePacket))
    }

    private func decodeDay(_ json: String) throws -> CadenceDayEnvelope {
        try JSONDecoder().decode(CadenceDayEnvelope.self, from: Data(json.utf8))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func tempCacheStore() -> CadenceDayCacheStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cadence-tests-\(UUID().uuidString).json")
        return CadenceDayCacheStore(fileURL: url)
    }

    private func tempQueueStore() -> CadenceActQueueStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cadence-queue-tests-\(UUID().uuidString).json")
        return CadenceActQueueStore(fileURL: url)
    }

    private func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: text))
        return date
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

private final class CadenceRequestRecorder {
    var getBodies: [String]
    var postBodies: [String]
    var getErrors: [Error]
    var postErrors: [Error]
    var suspendNextPost = false
    private var suspendedPost: CheckedContinuation<AGUILineResponse, Error>?
    private(set) var requests: [URLRequest] = []

    init(
        getBodies: [String] = [],
        postBodies: [String] = [#"{"ok":true}"#],
        getErrors: [Error] = [],
        postErrors: [Error] = []
    ) {
        self.getBodies = getBodies
        self.postBodies = postBodies
        self.getErrors = getErrors
        self.postErrors = postErrors
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.requests.append(request)
            if request.httpMethod == "GET", !self.getErrors.isEmpty {
                throw self.getErrors.removeFirst()
            }
            if request.httpMethod == "POST", !self.postErrors.isEmpty {
                throw self.postErrors.removeFirst()
            }
            if request.httpMethod == "POST", self.suspendNextPost {
                self.suspendNextPost = false
                return try await withCheckedThrowingContinuation { continuation in
                    self.suspendedPost = continuation
                }
            }
            return Self.response(url: try XCTUnwrap(request.url), body: self.body(for: request))
        }
    }

    func resumeSuspendedPost(body: String, status: Int = 200) {
        guard let suspendedPost else { return }
        self.suspendedPost = nil
        suspendedPost.resume(returning: Self.response(url: URL(string: "http://daemon.test")!, status: status, body: body))
    }

    private func body(for request: URLRequest) -> String {
        if request.httpMethod == "GET" {
            return getBodies.isEmpty ? #"{"date":"2026-07-06","bandish":[]}"# : getBodies.removeFirst()
        }
        return postBodies.isEmpty ? #"{"ok":true}"# : postBodies.removeFirst()
    }

    private static func response(url: URL, status: Int = 200, body: String) -> AGUILineResponse {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            if !body.isEmpty {
                continuation.yield(body)
            }
            continuation.finish()
        }
        return AGUILineResponse(response: response, lines: stream)
    }
}
