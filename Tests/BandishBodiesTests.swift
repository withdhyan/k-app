import XCTest
@testable import K

final class BandishBodiesTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testFullRemainingDayAndExactPreviousToggleLabels() throws {
        let day = try decodeDay("""
        {
          "date": "2026-07-20",
          "bandish": [
            {"id":"older","title":"older","startAt":"07:00","endAt":"07:30"},
            {"id":"previous","title":"previous","startAt":"08:00","endAt":"08:30"},
            {"id":"current","title":"current","startAt":"09:00","endAt":"10:00"},
            {"id":"one","title":"one","startAt":"10:15","endAt":"10:45"},
            {"id":"two","title":"two","startAt":"11:00","endAt":"11:30"},
            {"id":"three","title":"three","startAt":"12:00","endAt":"12:30"},
            {"id":"four","title":"four","startAt":"14:00","endAt":"14:30"},
            {"id":"five","title":"five","startAt":"16:00","endAt":"16:30"}
          ]
        }
        """)
        let presentation = CadenceDayPresentation(
            day: day,
            now: try date("2026-07-20T09:15:00Z"),
            calendar: utcCalendar
        )

        XCTAssertEqual(
            presentation.visibleTimelineBlocks.map(\.id),
            ["previous", "current", "one", "two", "three", "four", "five"]
        )
        XCTAssertEqual(presentation.previousTimelineBlocks.map(\.id), ["older"])
        XCTAssertEqual(presentation.previousToggleText, "SHOW PREVIOUS (1)")
        XCTAssertEqual(CadencePreviousToggleLabel.text(isExpanded: true, count: 1), "HIDE PREVIOUS")
    }

    func testMealCurrentAnalyzedUsesThreeColumnMacroAndRankedMicroGrid() throws {
        let block = try decodeBlock("""
        {
          "id":"meal-current","title":"meal 2","type":"meal","startAt":"12:00","endAt":"12:30",
          "mealInfo":{
            "name":"salmon bowl","calories":612,"portionSize":"1 bowl (420 g)",
            "protein":42,"carbs":58,"fat":21,"fiber":9,
            "micros":{"iron":3.2,"potassium":780,"vitamin c":44,"calcium":210,"magnesium":96,"zinc":2.5,"b12":4.1,"folate":128,"sodium":520},
            "images":[{"id":"image-1","url":"meal.jpg","isAnalyzed":true}]
          }
        }
        """)

        let result = resolve(block, temporal: .current, actionState: .completed)

        XCTAssertEqual(result.kind, .mealAnalysis)
        XCTAssertEqual(result.title, "meal 2 | salmon bowl")
        XCTAssertEqual(result.secondaryInfo, "612 kcal | 1 bowl | 42g 58g 21g 9g")
        XCTAssertEqual(result.meal?.macroColumn.map(\.label), ["protein", "carbs", "fat", "fiber"])
        XCTAssertEqual(result.meal?.micronutrientColumns.count, 2)
        XCTAssertEqual(result.meal?.micronutrientColumns.flatMap { $0 }.count, 8)
        XCTAssertEqual(result.meal?.micronutrientColumns.first?.first?.label, "potassium")
    }

    func testMealPastStaysCompactButRetainsAnalyzedByline() throws {
        let block = try decodeBlock("""
        {"id":"meal-past","title":"meal 1","type":"meal","startAt":"08:00","endAt":"08:30",
         "mealInfo":{"name":"eggs","calories":360,"portionSize":"2 eggs (180 g)","macros":{"protein":28,"carbs":4,"fat":24,"fiber":0}}}
        """)

        let result = resolve(block, temporal: .past, actionState: .completed)

        XCTAssertEqual(result.kind, .none)
        XCTAssertEqual(result.title, "meal 1 | eggs")
        XCTAssertEqual(result.secondaryInfo, "360 kcal | 2 eggs | 28g 4g 24g 0g")
    }

    func testSleepCurrentRendersStageBarAndMorningOrientation() throws {
        let block = try decodeBlock("""
        {
          "id":"init","title":"init","type":"sleep","startAt":"07:00","endAt":"07:30",
          "sleepInfo":{"deepSleep":96,"remSleep":122,"lightSleep":238,"awakeTime":24,"performance_percentage":91},
          "morningOrientation":{"summary":"protect recovery, then converge","decisions":["keep training light","move review"],"priorities":["ship U2","walk","read"],"complete":true}
        }
        """)

        let result = resolve(block, temporal: .current, actionState: .started)

        XCTAssertEqual(result.kind, .sleepOverview)
        XCTAssertEqual(result.sleep?.stages.map(\.label), ["deep", "rem", "light", "awake"])
        XCTAssertEqual(result.sleep?.stages.map(\.minutes), [96, 122, 238, 24])
        XCTAssertEqual(result.sleep?.orientation?.summary, "protect recovery, then converge")
        XCTAssertEqual(result.sleep?.orientation?.priorities.map(\.title), ["ship u2", "walk", "read"])
        XCTAssertEqual(result.sleep?.orientation?.completionText, "orientation complete")
    }

    func testSleepFutureIsSilenceDefault() throws {
        let block = try decodeBlock("""
        {"id":"sleep-future","title":"sleep","type":"sleep","startAt":"23:00","endAt":"23:30","sleepInfo":{"deepSleep":96,"remSleep":122}}
        """)

        XCTAssertEqual(resolve(block, temporal: .future, actionState: .available).kind, .none)
    }

    func testMeditationCurrentAvailableShowsSelectedProtocol() throws {
        let block = try decodeBlock("""
        {"id":"meditation","title":"meditation","type":"meditation","brainState":"open-monitoring","startAt":"10:00","endAt":"11:00","meditationInfo":{"session_type":"om_v1","technique":"vipassana"}}
        """)

        let result = resolve(block, temporal: .current, actionState: .available)

        XCTAssertEqual(result.kind, .meditationProtocol)
        XCTAssertEqual(result.meditation?.protocolName, "open monitoring")
        XCTAssertEqual(result.meditation?.technique, "vipassanā")
        XCTAssertNil(result.meditation?.phaseName)
    }

    func testMeditationCurrentStartedShowsGuidedPhaseAndInstruction() throws {
        let block = try decodeBlock("""
        {"id":"meditation","title":"meditation","type":"meditation","brainState":"focused-attention","startAt":"10:00","endAt":"11:00"}
        """)

        let result = resolve(block, temporal: .current, actionState: .started, elapsedSeconds: 306)

        XCTAssertEqual(result.kind, .meditationSession)
        XCTAssertEqual(result.meditation?.protocolName, "focused attention")
        XCTAssertEqual(result.meditation?.technique, "ānāpānasati")
        XCTAssertEqual(result.meditation?.phaseName, "practice")
        XCTAssertEqual(result.meditation?.elapsedText, "5:06")
        XCTAssertEqual(result.meditation?.instruction, "maintain continuous attention on breath")
    }

    func testWorkCurrentStartedUsesModeSpecificPrepCountdown() throws {
        let block = try decodeBlock("""
        {"id":"work","title":"build","type":"work","attentionMode":"converge","startAt":"11:00","endAt":"12:00"}
        """)

        let result = resolve(block, temporal: .current, actionState: .started, elapsedSeconds: 10)

        XCTAssertEqual(result.kind, .workPreparation)
        XCTAssertEqual(result.work?.protocolName, "focused attention")
        XCTAssertEqual(result.work?.phaseName, "settle")
        XCTAssertEqual(result.work?.remainingText, "1:50")
        XCTAssertEqual(result.work?.instruction, "close your eyes")
    }

    func testWorkPastConvergentShowsAllSubtasksWithoutPrep() throws {
        let block = try decodeBlock("""
        {"id":"work-past","title":"build","type":"work","brainState":"convergent","startAt":"11:00","endAt":"12:00",
         "subtasks":[{"id":"a","text":"first","done":true},{"id":"b","text":"second"},{"id":"c","text":"third"},{"id":"d","text":"fourth"}]}
        """)

        let result = resolve(block, temporal: .past, actionState: .completed, elapsedSeconds: 500)

        XCTAssertEqual(result.kind, .workSession)
        XCTAssertEqual(result.work?.taskLines.map(\.text), ["first", "second", "third", "fourth"])
        XCTAssertNil(result.work?.remainingText)
    }

    func testWorkoutBodyDecodesWhoopShapeAndResolvesAllThreeDepthStates() throws {
        let block = try decodeBlock("""
        {
          "id":"workout",
          "title":"strength · pull day",
          "type":"workout",
          "startAt":"11:00",
          "endAt":"12:00",
          "workoutInfo":{
            "exercises":[
              {"id":"pull","name":"pull down","setsRepsWeight":"4 × 8 · 60 kg","completed":true}
            ],
            "strain":{"actual":14.2,"target":16},
            "tonnage":{"current":4820,"previous":4520,"change":6.6},
            "heartRateZones":[
              {"zone":1,"minutes":4}, {"zone":2,"minutes":12},
              {"zone":3,"minutes":18}, {"zone":4,"minutes":10}, {"zone":5,"minutes":1}
            ],
            "realTime":{"currentZone":3,"isActive":true,"heartRate":148},
            "calories":412,
            "effortCurve":[0.1,0.4,0.8],
            "recoveryHint":"leave tomorrow's work room",
            "source":"whoop"
          }
        }
        """)

        let pre = resolve(block, temporal: .current, actionState: .available)
        XCTAssertEqual(pre.kind, .workoutLive)
        XCTAssertEqual(pre.workout?.state, .preWorkout)
        XCTAssertEqual(pre.workout?.zones.count, 5)
        XCTAssertEqual(pre.workout?.strainText, "not started")

        let mid = resolve(block, temporal: .current, actionState: .started)
        XCTAssertEqual(mid.kind, .workoutLive)
        XCTAssertEqual(mid.workout?.state, .midWorkout)
        XCTAssertEqual(mid.workout?.currentZoneText, "zone 3")
        XCTAssertEqual(mid.workout?.heartRateText, "148 bpm")
        XCTAssertEqual(mid.workout?.zones.first(where: { $0.isCurrent })?.label, "z3")
        XCTAssertEqual(mid.workout?.effortCurve, [0.1, 0.4, 0.8])

        let detail = resolve(block, temporal: .pastDetail, actionState: .completed)
        XCTAssertEqual(detail.kind, .workoutDetail)
        XCTAssertEqual(detail.title, "strength · pull day | 412 kcal · 14.2 strain")
        XCTAssertEqual(detail.secondaryInfo, "412 kcal · 14.2 strain")
        XCTAssertEqual(detail.workout?.tonnageText, "tonnage 4820 kg · +6.6%")
        XCTAssertEqual(detail.workout?.recoveryHint, "leave tomorrow's work room")
    }

    func testWorkoutDemoFixtureUsesFixedDataForPreMidAndPost() {
        // doctrine: silence-default + staleness-honesty. Captures and tests
        // share one local-noon clock on the opening day rather than reading
        // live device time.
        let calendar = utcCalendar
        let pre = CadenceWorkoutDemo.day(state: .pre, calendar: calendar)
        let mid = CadenceWorkoutDemo.day(state: .mid, calendar: calendar)
        let post = CadenceWorkoutDemo.day(state: .post, calendar: calendar)

        XCTAssertEqual(
            pre.date,
            CadenceDateParser.dayString(for: CadenceWorkoutDemo.fixtureNow, calendar: calendar)
        )
        XCTAssertEqual(pre.bandish.first(where: { $0.type == "workout" })?.actionState, .available)
        XCTAssertEqual(mid.bandish.first(where: { $0.type == "workout" })?.actionState, .started)
        XCTAssertEqual(post.bandish.first(where: { $0.type == "workout" })?.actionState, .completed)
        XCTAssertEqual(
            post.bandish.first(where: { $0.type == "workout" })?.workoutInfo?.calories,
            412
        )
        XCTAssertEqual(
            post.bandish.first(where: { $0.type == "workout" })?.workoutInfo?.strain?.actual,
            14.2
        )
    }

    func testWorkoutDemoOpeningInstantPinsOnlyTheDayAndUsesLocalNoon() throws {
        let openedAt = try date("2031-04-19T23:47:12Z")
        let instant = CadenceWorkoutDemo.openingInstant(openedAt: openedAt, calendar: utcCalendar)
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)

        XCTAssertEqual(components.year, 2031)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, .zero)
        XCTAssertEqual(components.second, .zero)
    }

    func testWorkoutDemoTemporalSourceKeepsLiveStatesCurrentAndPostAsAListRow() throws {
        let instant = CadenceWorkoutDemo.openingInstant(
            openedAt: try date("2031-04-19T23:47:12Z"),
            calendar: utcCalendar
        )

        for state in [CadenceWorkoutDemo.State.pre, .mid] {
            let presentation = CadenceDayPresentation(
                day: CadenceWorkoutDemo.day(state: state, now: instant, calendar: utcCalendar),
                now: instant,
                calendar: utcCalendar
            )
            XCTAssertEqual(presentation.nowBlock?.id, "demo-workout")
            XCTAssertEqual(
                BandishBodyVariantResolver.presentation(
                    for: try XCTUnwrap(presentation.nowBlock?.block),
                    temporal: .current,
                    actionState: state == .pre ? .available : .started
                ).kind,
                .workoutLive
            )
        }

        let post = CadenceDayPresentation(
            day: CadenceWorkoutDemo.day(state: .post, now: instant, calendar: utcCalendar),
            now: instant,
            calendar: utcCalendar
        )
        XCTAssertNil(post.nowBlock)
        XCTAssertTrue(post.visibleTimelineBlocks.contains { $0.id == "demo-workout" })
    }

    private func resolve(
        _ block: CadenceBlock,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState,
        elapsedSeconds: Int = 0
    ) -> BandishBodyPresentation {
        BandishBodyVariantResolver.presentation(
            for: block,
            temporal: temporal,
            actionState: actionState,
            elapsedSeconds: elapsedSeconds
        )
    }

    private func decodeBlock(_ json: String) throws -> CadenceBlock {
        try JSONDecoder().decode(CadenceBlock.self, from: Data(json.utf8))
    }

    private func decodeDay(_ json: String) throws -> CadenceDayEnvelope {
        try JSONDecoder().decode(CadenceDayEnvelope.self, from: Data(json.utf8))
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
