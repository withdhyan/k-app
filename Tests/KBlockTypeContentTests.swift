import XCTest
@testable import K

final class KBlockTypeContentTests: XCTestCase {
    func testWorkContentAcrossTemporalStates() {
        let detail = object(["brainState": .string("Convergent")])
        let subtasks = [
            Subtask(id: "aim", text: "Set aim"),
            Subtask(id: "proof", text: "Capture proof", done: true),
        ]

        let early = content(type: "work", detail: detail, subtasks: subtasks, temporal: .now, duration: 100, elapsed: 10, isStarted: true)
        XCTAssertEqual(early.metaSuffix, "convergent")
        XCTAssertEqual(early.checklist, [
            ChecklistItem(id: "aim", text: "set aim"),
            ChecklistItem(id: "proof", text: "capture proof", isDone: true),
        ])
        // Founder 2026-08-05: work is the 3 mode tabs, no instruction line.
        XCTAssertNil(early.liveLine)
        XCTAssertNil(content(type: "work", detail: detail, subtasks: subtasks, temporal: .now, duration: 100, elapsed: 50, isStarted: true).liveLine)
        XCTAssertNil(content(type: "work", detail: detail, subtasks: subtasks, temporal: .elapsed).liveLine)
        XCTAssertNil(content(type: "work", detail: detail, subtasks: subtasks, temporal: .upcoming).liveLine)
    }

    func testMealContentAcrossTemporalStates() {
        let detail = object([
            "composition": .array([.string("Eggs"), .string("Rice"), .string("Greens")]),
            "protein": .number(40),
            "calories": .number(620),
        ])

        for temporal in allTemporalStates {
            let result = content(type: "meal", detail: detail, temporal: temporal)
            XCTAssertEqual(result.detailLines, ["eggs · rice · greens", "40g protein · 620 kcal"], "\(temporal)")
            XCTAssertNil(result.metaSuffix)
            XCTAssertNil(result.checklist)
            XCTAssertNil(result.liveLine)
        }
    }

    func testMeditationContentAcrossTemporalStates() {
        let detail = object([
            "practice": .string("Breath"),
            "phase": .number(2),
            "method": .string("Open monitoring"),
        ])

        let now = content(type: "meditation", detail: detail, temporal: .now, duration: 25, elapsed: 12)
        XCTAssertEqual(now.detailLines, ["breath · 25m", "phase 2 · open monitoring"])
        XCTAssertEqual(now.liveLine, "breath: follow the exhale to its end")

        for temporal in [BlockTemporal.elapsed, .upcoming] {
            let result = content(type: "meditation", detail: detail, temporal: temporal, duration: 25, elapsed: 12)
            XCTAssertEqual(result.detailLines, ["breath · 25m", "phase 2 · open monitoring"], "\(temporal)")
            XCTAssertNil(result.liveLine)
        }
    }

    func testWorkoutContentAcrossTemporalStates() {
        let detail = object(["plan": .array([.string("Squats"), .string("Carry")])])

        XCTAssertEqual(
            content(type: "workout", detail: detail, temporal: .now, duration: 45).detailLines,
            ["squats · carry · 45m"]
        )
        XCTAssertEqual(
            content(type: "workout", detail: detail, temporal: .upcoming, duration: 45).detailLines,
            ["squats · carry · 45m"]
        )
        XCTAssertEqual(
            content(
                type: "workout",
                detail: detail,
                temporal: .elapsed,
                health: HealthSummary(strain: "7", avgHeartRate: "142"),
                duration: 45
            ).detailLines,
            ["squats · carry · 45m", "strain 7 · avg hr 142"]
        )
        XCTAssertEqual(
            content(
                type: "workout",
                detail: detail,
                temporal: .elapsed,
                health: HealthSummary(strain: nil, avgHeartRate: "140"),
                duration: 45
            ).detailLines,
            ["squats · carry · 45m", "avg hr 140"]
        )
    }

    func testSleepContentAcrossTemporalStates() {
        let detail = object([
            "phases": object([
                "deep": .number(80),
                "rem": .number(92),
                "light": .number(240),
                "awake": .number(20),
            ]),
        ])

        XCTAssertEqual(content(type: "sleep", detail: detail, temporal: .now, duration: 480).detailLines, ["sleep · 8h"])
        XCTAssertEqual(content(type: "sleep", detail: detail, temporal: .upcoming, duration: 480).detailLines, ["sleep · 8h"])
        XCTAssertEqual(content(type: "sleep", detail: detail, temporal: .upcoming).detailLines, [])
        XCTAssertEqual(
            content(type: "sleep", detail: detail, temporal: .elapsed).detailLines,
            ["7h12 · deep 1h20 · rem 1h32", "slept 7h 12m · ready"]
        )
        XCTAssertEqual(
            content(
                type: "sleep",
                detail: detail,
                temporal: .elapsed,
                bodySummary: BodySummary(hrv: BodySummaryMetric(low: true))
            ).detailLines,
            [
                "7h12 · deep 1h20 · rem 1h32",
                "needs attention · hrv low",
                "slept 7h 12m · hrv low · gentle day",
            ]
        )
    }

    func testSleepReadinessLineRules() {
        let ready = BodySummary(
            hrv: BodySummaryMetric(driftDirection: "steady", low: false),
            sleep: BodySummaryMetric(low: false)
        )
        XCTAssertEqual(
            KBlockTypeContent.sleepReadinessLine(totalSleepMinutes: 460, bodySummary: ready),
            "slept 7h 40m · hrv steady · ready"
        )

        let gentle = BodySummary(hrv: BodySummaryMetric(low: true))
        XCTAssertEqual(
            KBlockTypeContent.sleepReadinessLine(totalSleepMinutes: 310, bodySummary: gentle),
            "slept 5h 10m · hrv low · gentle day"
        )

        XCTAssertEqual(
            KBlockTypeContent.sleepReadinessLine(
                totalSleepMinutes: nil,
                bodySummary: BodySummary(sleep: BodySummaryMetric(latestHours: 6.5))
            ),
            "slept 6h 30m · ready"
        )
        XCTAssertEqual(
            KBlockTypeContent.sleepReadinessLine(totalSleepMinutes: 80, bodySummary: nil),
            "slept 1h 20m · ready"
        )
        XCTAssertNil(KBlockTypeContent.sleepReadinessLine(totalSleepMinutes: nil, bodySummary: nil))
        XCTAssertNil(KBlockTypeContent.sleepReadinessLine(
            totalSleepMinutes: nil,
            bodySummary: BodySummary(globalBodyState: "ready")
        ))
    }

    func testSleepNeedsAttentionLineRules() {
        XCTAssertEqual(
            KBlockTypeContent.sleepNeedsAttentionLine(bodySummary: BodySummary(hrv: BodySummaryMetric(low: true))),
            "needs attention · hrv low"
        )
        XCTAssertEqual(
            KBlockTypeContent.sleepNeedsAttentionLine(bodySummary: BodySummary(sleep: BodySummaryMetric(low: true))),
            "needs attention · sleep low"
        )
        XCTAssertEqual(
            KBlockTypeContent.sleepNeedsAttentionLine(bodySummary: BodySummary(
                hrv: BodySummaryMetric(low: true),
                sleep: BodySummaryMetric(low: true)
            )),
            "needs attention · hrv low · sleep low"
        )
        XCTAssertNil(KBlockTypeContent.sleepNeedsAttentionLine(bodySummary: BodySummary(
            hrv: BodySummaryMetric(low: false),
            sleep: BodySummaryMetric(low: false)
        )))
    }

    func testBodySummaryDecodingFullMinimalAndAbsentFields() throws {
        let full = try decodeBodySummary("""
        {
          "globalBodyState": "strained",
          "generatedAt": "2026-07-08T02:00:00Z",
          "source": "body-v2",
          "hrv": {
            "latest": 43,
            "recentMean": 47,
            "drift": -4,
            "driftDirection": "steady",
            "count": 7,
            "zScore": -1.2,
            "zScoreDirection": "low",
            "zScoreSamples": 6,
            "low": true
          },
          "sleep": {
            "latestHours": 5.17,
            "recentMeanHours": 7.4,
            "trendDeltaHours": -2.2,
            "trendDirection": "down",
            "count": 8,
            "zScore": -2.1,
            "zScoreUnavailableReason": "none",
            "low": false
          }
        }
        """)

        XCTAssertEqual(full.globalBodyState, "strained")
        XCTAssertEqual(full.generatedAt, "2026-07-08T02:00:00Z")
        XCTAssertEqual(full.source, "body-v2")
        XCTAssertEqual(full.hrv?.latest, 43)
        XCTAssertEqual(full.hrv?.recentMean, 47)
        XCTAssertEqual(full.hrv?.drift, -4)
        XCTAssertEqual(full.hrv?.driftDirection, "steady")
        XCTAssertEqual(full.hrv?.count, 7)
        XCTAssertEqual(full.hrv?.zScore, -1.2)
        XCTAssertEqual(full.hrv?.zScoreDirection, "low")
        XCTAssertEqual(full.hrv?.zScoreSamples, 6)
        XCTAssertEqual(full.hrv?.low, true)
        XCTAssertEqual(full.sleep?.latestHours, 5.17)
        XCTAssertEqual(full.sleep?.recentMeanHours, 7.4)
        XCTAssertEqual(full.sleep?.trendDeltaHours, -2.2)
        XCTAssertEqual(full.sleep?.trendDirection, "down")
        XCTAssertEqual(full.sleep?.count, 8)
        XCTAssertEqual(full.sleep?.zScore, -2.1)
        XCTAssertEqual(full.sleep?.zScoreUnavailableReason, "none")
        XCTAssertEqual(full.sleep?.low, false)

        let minimal = try decodeBodySummary(#"{"globalBodyState":"ready"}"#)
        XCTAssertEqual(minimal.globalBodyState, "ready")
        XCTAssertNil(minimal.generatedAt)
        XCTAssertNil(minimal.source)
        XCTAssertNil(minimal.hrv)
        XCTAssertNil(minimal.sleep)

        let absentFields = try decodeBodySummary(#"{"globalBodyState":"ready","hrv":{},"sleep":{}}"#)
        XCTAssertNil(absentFields.hrv?.latest)
        XCTAssertNil(absentFields.hrv?.zScore)
        XCTAssertNil(absentFields.hrv?.low)
        XCTAssertNil(absentFields.sleep?.latestHours)
        XCTAssertNil(absentFields.sleep?.low)
    }

    func testSleepPhaseTypographyFormatter() {
        let detail = object([
            "phases": object([
                "deep": .number(100),
                "rem": .number(115),
                "light": .number(185),
                "awake": .number(22),
            ]),
        ])

        XCTAssertEqual(KBlockTypeContent.sleepPhaseTypographyLines(detail: detail), [
            "deep   1h40  24%",
            "rem    1h55  27%",
            "light  3h05  44%",
            "awake   22m   5%",
        ])
    }

    func testRoutineContentAcrossTemporalStates() {
        let subtasks = [
            Subtask(id: "one", text: "One", done: true),
            Subtask(id: "two", text: "Two", done: true),
            Subtask(id: "three", text: "Three"),
            Subtask(id: "four", text: "Four"),
            Subtask(id: "five", text: "Five"),
        ]

        for temporal in allTemporalStates {
            let result = content(type: "routine", subtasks: subtasks, temporal: temporal)
            XCTAssertEqual(result.metaSuffix, "2/5", "\(temporal)")
            XCTAssertEqual(result.checklist?.map(\.text), ["one", "two", "three", "four", "five"], "\(temporal)")
            XCTAssertEqual(result.checklist?.map(\.isDone), [true, true, false, false, false], "\(temporal)")
            XCTAssertTrue(result.detailLines.isEmpty)
            XCTAssertNil(result.liveLine)
        }
    }

    func testOpsContentAcrossTemporalStates() {
        let subtasks = [
            Subtask(id: "tax", text: "Send tax form", timeSensitive: true),
            Subtask(id: "vendor", text: "Close vendor thread", done: true),
        ]

        for temporal in allTemporalStates {
            let result = content(type: "ops", subtasks: subtasks, temporal: temporal)
            XCTAssertEqual(result.metaSuffix, "1/2", "\(temporal)")
            XCTAssertEqual(result.checklist?.map(\.text), ["send tax form · due today", "close vendor thread"], "\(temporal)")
            XCTAssertEqual(result.checklist?.map(\.isDone), [false, true], "\(temporal)")
            XCTAssertTrue(result.detailLines.isEmpty)
            XCTAssertNil(result.liveLine)
        }
    }

    func testNilUnknownAndMalformedDetailsAreDefensive() {
        XCTAssertEqual(content(type: nil, subtasks: [Subtask(id: "x", text: "x")], temporal: .now), .empty)
        XCTAssertEqual(content(type: "unknown", detail: object(["plan": .string("x")]), temporal: .now), .empty)
        XCTAssertEqual(content(type: "meal", detail: .string("bad"), temporal: .now).detailLines, [])
        XCTAssertEqual(content(type: "meditation", detail: nil, temporal: .now).detailLines, [])
        XCTAssertNil(content(type: "meditation", detail: nil, temporal: .now).liveLine)
        XCTAssertEqual(content(type: "workout", detail: object(["plan": .object([:])]), temporal: .upcoming).detailLines, [])
        XCTAssertEqual(content(type: "sleep", detail: object(["phases": .array([])]), temporal: .elapsed), .empty)
        XCTAssertEqual(content(type: "routine", subtasks: nil, temporal: .elapsed), .empty)
        XCTAssertEqual(content(type: "ops", subtasks: [], temporal: .upcoming), .empty)
    }

    func testDetailSectionsFormatWorkMeditationAndMeal() {
        let work = detail(
            type: "work",
            detail: object(["brainState": .string("Convergent")]),
            subtasks: [
                Subtask(id: "aim", text: "Set aim"),
                Subtask(id: "proof", text: "Capture proof", done: true),
            ],
            temporal: .now,
            duration: 100,
            elapsed: 50
        )
        XCTAssertEqual(work, [
            DetailSection(
                header: "subtasks",
                checklist: [
                    ChecklistItem(id: "aim", text: "set aim"),
                    ChecklistItem(id: "proof", text: "capture proof", isDone: true),
                ]
            ),
            DetailSection(header: "prep arc", lines: ["prime", "practice · current", "close"]),
            DetailSection(header: "brain state", lines: ["convergent"]),
        ])

        let meditation = detail(
            type: "meditation",
            detail: object([
                "practice": .string("Breath"),
                "phase": .number(2),
                "method": .string("Open monitoring"),
            ]),
            temporal: .now,
            duration: 25,
            elapsed: 12
        )
        XCTAssertEqual(meditation, [
            DetailSection(header: "practice", lines: ["breath · 25m"]),
            DetailSection(header: "protocol", lines: ["phase 2 · open monitoring"]),
            DetailSection(header: "elapsed", lines: ["12m in"]),
            DetailSection(header: "session notes", lines: ["notes land here after the session"]),
        ])

        let meal = detail(
            type: "meal",
            detail: object([
                "composition": .array([.string("Eggs"), .string("Rice")]),
                "protein": .number(40),
                "calories": .number(620),
                "carbs": .number(55),
                "fat": .number(18),
                "fiber": .number(8),
            ]),
            temporal: .upcoming
        )
        XCTAssertEqual(meal, [
            DetailSection(header: "composition", lines: ["eggs", "rice"]),
            DetailSection(header: "macros", lines: ["40g protein · 620 kcal · 55g carbs · 18g fat · 8g fibre"]),
        ])
    }

    func testDetailSectionsFormatWorkoutSleepRoutineAndOps() {
        let workout = detail(
            type: "workout",
            detail: object([
                "plan": .array([.string("Squats"), .string("Carry")]),
                "exercises": .array([.string("Back squat"), .string("Loaded carry")]),
            ]),
            temporal: .elapsed,
            health: HealthSummary(strain: "7", avgHeartRate: "142"),
            duration: 45
        )
        XCTAssertEqual(workout, [
            DetailSection(header: "plan", lines: ["squats", "carry"]),
            DetailSection(header: "exercises", lines: ["back squat", "loaded carry"]),
            DetailSection(header: "body", lines: ["elapsed 45m · strain 7 · avg hr 142"]),
        ])

        let sleep = detail(
            type: "sleep",
            detail: object([
                "phases": object([
                    "deep": .number(100),
                    "rem": .number(115),
                    "light": .number(185),
                    "awake": .number(22),
                ]),
                "vitals": object([
                    "hrv": .number(64),
                    "rhr": .number(51),
                    "spo2": .number(98),
                ]),
            ]),
            temporal: .elapsed
        )
        XCTAssertEqual(sleep, [
            DetailSection(header: "phases", lines: [
                "deep   1h40  24%",
                "rem    1h55  27%",
                "light  3h05  44%",
                "awake   22m   5%",
            ]),
            DetailSection(header: "vitals", lines: ["hrv 64", "rhr 51", "spo2 98"]),
        ])

        let sleepWithBodySummary = detail(
            type: "sleep",
            detail: object([
                "phases": object([
                    "deep": .number(70),
                    "rem": .number(90),
                    "light": .number(280),
                    "awake": .number(20),
                ]),
                "vitals": object([
                    "rhr": .number(51),
                ]),
            ]),
            temporal: .elapsed,
            bodySummary: BodySummary(hrv: BodySummaryMetric(latest: 43, recentMean: 47, zScore: -1.2))
        )
        XCTAssertEqual(sleepWithBodySummary.last?.lines, ["rhr 51", "hrv 43 · baseline 47 · z −1.2"])

        let subtasks = [
            Subtask(id: "one", text: "One", timeSensitive: true),
            Subtask(id: "two", text: "Two", done: true),
        ]
        let expectedChecklist = [
            DetailSection(
                header: "checklist",
                checklist: [
                    ChecklistItem(id: "one", text: "one · due today"),
                    ChecklistItem(id: "two", text: "two", isDone: true),
                ]
            ),
        ]
        XCTAssertEqual(detail(type: "routine", subtasks: subtasks, temporal: .upcoming), expectedChecklist)
        XCTAssertEqual(detail(type: "ops", subtasks: subtasks, temporal: .upcoming), expectedChecklist)
    }

    func testDetailSectionsOmitAbsentDataDefensively() {
        XCTAssertEqual(detail(type: nil, temporal: .now), [])
        XCTAssertEqual(detail(type: "unknown", detail: object(["plan": .string("x")]), temporal: .now), [])
        XCTAssertEqual(detail(type: "meal", detail: nil, temporal: .now), [])
        XCTAssertEqual(detail(type: "workout", detail: object(["plan": .object([:])]), temporal: .upcoming), [])
        XCTAssertEqual(detail(type: "sleep", detail: object(["phases": .array([])]), temporal: .elapsed), [])
        XCTAssertEqual(detail(type: "routine", subtasks: [], temporal: .elapsed), [])
    }

    private var allTemporalStates: [BlockTemporal] {
        [.elapsed, .now, .upcoming]
    }

    private func content(
        type: String?,
        detail: ViewPacketJSONValue? = nil,
        subtasks: [Subtask]? = nil,
        temporal: BlockTemporal,
        health: HealthSummary? = nil,
        duration: Int? = nil,
        elapsed: Int? = nil,
        bodySummary: BodySummary? = nil,
        isStarted: Bool = false
    ) -> BlockContent {
        KBlockTypeContent.content(
            type: type,
            detail: detail,
            subtasks: subtasks,
            temporal: temporal,
            health: health,
            blockDurationMinutes: duration,
            elapsedMinutes: elapsed,
            bodySummary: bodySummary,
            isStarted: isStarted
        )
    }

    private func detail(
        type: String?,
        detail: ViewPacketJSONValue? = nil,
        subtasks: [Subtask]? = nil,
        temporal: BlockTemporal,
        health: HealthSummary? = nil,
        duration: Int? = nil,
        elapsed: Int? = nil,
        bodySummary: BodySummary? = nil
    ) -> [DetailSection] {
        KBlockTypeContent.detail(
            type: type,
            detail: detail,
            subtasks: subtasks,
            temporal: temporal,
            health: health,
            blockDurationMinutes: duration,
            elapsedMinutes: elapsed,
            bodySummary: bodySummary
        )
    }

    private func object(_ fields: [String: ViewPacketJSONValue]) -> ViewPacketJSONValue {
        .object(fields)
    }

    private func decodeBodySummary(_ json: String) throws -> BodySummary {
        try JSONDecoder().decode(BodySummary.self, from: Data(json.utf8))
    }
}
