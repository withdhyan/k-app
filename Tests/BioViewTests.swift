import XCTest
import UIKit
@testable import K

final class BioViewTests: XCTestCase {
    func testMealCaptureGestureSelectsPhotoForTapAndVideoForHold() {
        var tap = MealCaptureGestureStateMachine()
        XCTAssertEqual(tap.intentAfterRelease(), .photo)

        var hold = MealCaptureGestureStateMachine()
        hold.pressing(true)
        XCTAssertEqual(hold.intentAfterRelease(), .video)
    }

    func testMealCaptureGestureResetsAfterRelease() {
        var machine = MealCaptureGestureStateMachine()
        machine.pressing(true)
        XCTAssertEqual(machine.intentAfterRelease(), .video)
        XCTAssertEqual(machine.intentAfterRelease(), .photo)
    }

    func testInterventionPhaseStatusDerivesDaemonLifecycle() {
        XCTAssertEqual(BioInterventionPhaseStatus.derive(actionState: "available"), .planned)
        XCTAssertEqual(BioInterventionPhaseStatus.derive(actionState: "active"), .active)
        XCTAssertEqual(BioInterventionPhaseStatus.derive(actionState: "paused"), .washout)
        XCTAssertEqual(BioInterventionPhaseStatus.derive(actionState: "completed"), .done)
        XCTAssertEqual(BioInterventionPhaseStatus.derive(actionState: nil), .planned)
    }

    func testInterventionProjectionDecodesOptionalLifecycleFields() throws {
        let intervention = try JSONDecoder().decode(
            BioInterventionProjection.self,
            from: Data(#"{"id":"i-1","title":"sleep","actionState":"active","currentPhase":2}"#.utf8)
        )

        XCTAssertEqual(intervention.phaseText, "active")
        XCTAssertEqual(intervention.currentPhase, 2)
    }

    func testInterventionStopHoldStateMachineRequiresDeliberateHold() {
        var machine = BioHoldToStopStateMachine()
        XCTAssertFalse(machine.complete())
        machine.pressing(true)
        XCTAssertTrue(machine.complete())
        XCTAssertFalse(machine.complete())
        machine.pressing(false)
        XCTAssertEqual(machine.state, .committed)
    }

    func testCalendarWeekSliceUsesReferenceWeekAndExpandsToMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthAnchor = date("2026-08-08", calendar: calendar)
        let referenceDate = date("2026-08-08", calendar: calendar)

        let weeks = BioCalendarWeekSlice.monthWeeks(for: monthAnchor, calendar: calendar)

        XCTAssertEqual(weeks.count, 6)
        XCTAssertEqual(
            BioCalendarWeekSlice.visibleWeekIndices(
                in: weeks,
                isExpanded: false,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            [1]
        )
        XCTAssertEqual(
            BioCalendarWeekSlice.visibleWeekIndices(
                in: weeks,
                isExpanded: true,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            Array(weeks.indices)
        )
    }

    func testCalendarRevealGestureUsesNamedExpandAndCollapseThresholds() {
        XCTAssertEqual(
            BioCalendarRevealGesture.nextState(
                isExpanded: false,
                magnification: KStyle.bioCalendarPinchExpandThreshold + 0.01
            ),
            true
        )
        XCTAssertEqual(
            BioCalendarRevealGesture.nextState(
                isExpanded: true,
                magnification: KStyle.bioCalendarPinchCollapseThreshold - 0.01
            ),
            false
        )
        XCTAssertNil(BioCalendarRevealGesture.nextState(isExpanded: false, magnification: 1))
        XCTAssertNil(BioCalendarRevealGesture.nextState(isExpanded: true, magnification: 1))
    }

    func testPlannedMealWireFieldIsAdditiveAndDefaultsToLogged() throws {
        let planned = try decodeArtifact("""
        {"log":[{"id":"future","at":"2026-08-05T12:30:00Z","kind":"meal","text":"dinner — photo when it happens","planned":true}]}
        """).log[0]

        XCTAssertTrue(planned.isPlanned)
        XCTAssertFalse(planned.mealMacros?.hasMeasurement == true)

        let existing = try decodeArtifact(
            #"{"log":[{"id":"logged","at":"2026-08-05T12:30:00Z","kind":"meal","text":"dinner"}]}"#
        ).log[0]
        XCTAssertFalse(existing.isPlanned)
    }

    func testBioDemoNutritionSeedMatchesMockDayGrammar() throws {
        let days = Dictionary(grouping: BioDemo.meals) { entry in
            Calendar.current.startOfDay(for: entry.sortDate ?? .distantPast)
        }
        let selectedDay = try XCTUnwrap(days.values.max(by: { lhs, rhs in
            (lhs.first?.sortDate ?? .distantPast) < (rhs.first?.sortDate ?? .distantPast)
        }))

        XCTAssertEqual(selectedDay.filter { !$0.isPlanned }.count, 2)
        XCTAssertEqual(selectedDay.filter(\.isPlanned).count, 1)
        XCTAssertEqual(
            Int(selectedDay.reduce(0) { $0 + ($1.mealMacros?.calories ?? 0) }.rounded()),
            850
        )
        XCTAssertEqual(
            selectedDay.first(where: \.isPlanned)?.displayText,
            "dinner — photo when it happens"
        )
    }

    func testMealMicronutrientFixturesDecodeTypicalSparseAndEmpty() throws {
        let typical = FixtureMealMicronutrientsSource.typical
        XCTAssertEqual(typical.values.count, 5)
        XCTAssertEqual(typical.values.first, MealMicronutrient(
            id: "iron",
            label: "iron",
            amount: 4.2,
            unit: "mg",
            confidence: 0.7
        ))

        let sparse = FixtureMealMicronutrientsSource.sparse
        XCTAssertEqual(sparse.values.count, 1)
        XCTAssertEqual(sparse.values.first?.id, "iron")

        let empty = FixtureMealMicronutrientsSource.empty
        XCTAssertTrue(empty.values.isEmpty)

        let artifact = try decodeArtifact("""
        {
          "log": [
            {
              "id": "meal-1",
              "at": "2026-08-09T02:00:00Z",
              "kind": "meal",
              "text": "plate",
              "micronutrients": [
                {"id":"iron","label":"iron","amount":4.2,"unit":"mg","confidence":0.7}
              ]
            }
          ]
        }
        """)
        XCTAssertEqual(artifact.log.first?.micronutrients?.first?.amount, 4.2)
        XCTAssertEqual(artifact.log.first?.micronutrients?.first?.unit, "mg")
        XCTAssertEqual(artifact.log.first?.micronutrients?.first?.confidence, 0.7)

        let absent = try decodeArtifact("""
        {"log":[{"id":"meal-absent","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate"}]}
        """)
        XCTAssertNil(absent.log.first?.micronutrients)

        let explicitlyEmpty = try decodeArtifact("""
        {"log":[{"id":"meal-empty","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate","micronutrients":[]}]}
        """)
        XCTAssertEqual(explicitlyEmpty.log.first?.micronutrients, [])

        let explicitlyNull = try decodeArtifact("""
        {"log":[{"id":"meal-null","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate","micronutrients":null}]}
        """)
        XCTAssertNil(explicitlyNull.log.first?.micronutrients)

        let projected = BioLogEntry(
            id: "meal-projected",
            at: "2026-08-09T02:00:00Z",
            kind: .meal,
            text: "plate",
            micronutrients: typical.values
        )
        XCTAssertEqual(FixtureMealMicronutrientsSource.empty.micronutrients(for: projected), typical.values)
    }

    @MainActor
    func testRealBodyLogMealMicronutrientsReachModelAndCompactRow() async throws {
        let recorder = BioHTTPRecorder(body: """
        {
          "entries": [
            {
              "id": "meal-real-1",
              "at": "2026-08-09T02:00:00Z",
              "kind": "meal",
              "text": "salmon bowl",
              "macros": {"calories": 620, "protein": 38},
              "micronutrients": [
                {"id":"iron","label":"iron","amount":"4.2","unit":"mg","confidence":"0.7"},
                {"key":"b12","name":"b12","value":2.4,"units":"mcg","confidenceScore":0.5}
              ]
            }
          ]
        }
        """)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            nowProvider: { Date(timeIntervalSince1970: 1_786_000_000) }
        )

        await model.load()

        let meal = try XCTUnwrap(model.nutritionEntries.first { $0.id == "meal-real-1" })
        XCTAssertEqual(meal.micronutrients?.map(\.id), ["iron", "b12"])
        XCTAssertEqual(
            FixtureMealMicronutrientsSource.empty.micronutrients(for: meal).map(\.id),
            ["iron", "b12"]
        )
        XCTAssertEqual(
            MealMicronutrientText.compactLine(for: meal.micronutrients ?? []),
            "iron 4.2 mg · b12 2.4 mcg"
        )
    }

    func testMealMicronutrientNestedPayloadAndNullStayAdditive() throws {
        let analysis = try decodeArtifact("""
        {"log":[{"id":"meal-analysis","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate",
          "analysis":{"micronutrients":[{"id":"iron","label":"iron","amount":4.2,"unit":"mg","confidence":0.7}]}}]}
        """)
        XCTAssertEqual(analysis.log.first?.micronutrients?.first?.id, "iron")

        let mealInfo = try decodeArtifact("""
        {"log":[{"id":"meal-info","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate",
          "mealInfo":{"micros":{"iron":{"amount":4.2,"unit":"mg","confidence":0.7}}}}]}
        """)
        XCTAssertEqual(mealInfo.log.first?.micronutrients?.first?.id, "iron")

        let explicitlyNull = try decodeArtifact(
            #"{"log":[{"id":"meal-null","at":"2026-08-09T02:00:00Z","kind":"meal","text":"plate","micronutrients":null}]}"#
        )
        XCTAssertNil(explicitlyNull.log.first?.micronutrients)
    }

    func testMealMicronutrientsSortByAmountAndCollapseToKStyleCount() {
        let nutrients = [
            MealMicronutrient(id: "zinc", label: "zinc", amount: 3.1, unit: "mg", confidence: 0.6),
            MealMicronutrient(id: "potassium", label: "potassium", amount: 320, unit: "mg", confidence: 0.9),
            MealMicronutrient(id: "iron", label: "iron", amount: 4.2, unit: "mg", confidence: 0.7),
            MealMicronutrient(id: "vitamin c", label: "vitamin c", amount: 32, unit: "mg", confidence: 0.8),
            MealMicronutrient(id: "b12", label: "b12", amount: 2.4, unit: "mcg", confidence: 0.5),
        ]

        let presentation = MealMicronutrientsPresentation(nutrients: nutrients)

        XCTAssertEqual(
            presentation.ordered.map(\.id),
            ["potassium", "vitamin c", "iron", "zinc", "b12"]
        )
        XCTAssertEqual(
            presentation.collapsed.map(\.id),
            ["potassium", "vitamin c", "iron"]
        )
        XCTAssertEqual(presentation.collapsed.count, KStyle.microCollapsedCount)
        XCTAssertEqual(presentation.visibleNutrients(isExpanded: false), presentation.collapsed)
        XCTAssertEqual(presentation.visibleNutrients(isExpanded: true), presentation.ordered)
    }

    func testEmptyMealMicronutrientsStayAbsent() {
        let presentation = MealMicronutrientsPresentation(
            nutrients: FixtureMealMicronutrientsSource.empty.micronutrients(for: "meal-1")
        )

        XCTAssertFalse(presentation.isVisible)
        XCTAssertTrue(presentation.ordered.isEmpty)
        XCTAssertTrue(presentation.collapsed.isEmpty)
        XCTAssertTrue(presentation.visibleNutrients(isExpanded: true).isEmpty)
    }

    func testMealMicronutrientRevealAndConfidenceUseNamedTokens() {
        XCTAssertEqual(
            MealMicronutrientsRevealGesture.nextState(
                isExpanded: false,
                magnification: KStyle.microPinchExpandThreshold + 0.01
            ),
            true
        )
        XCTAssertEqual(
            MealMicronutrientsRevealGesture.nextState(
                isExpanded: true,
                magnification: KStyle.microPinchCollapseThreshold - 0.01
            ),
            false
        )
        XCTAssertEqual(
            KStyle.microConfidenceOpacity(0),
            KStyle.microConfidenceMinimumOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KStyle.microConfidenceOpacity(1),
            KStyle.microConfidenceMaximumOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(KStyle.microRevealMotionResolution(true), .none)
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    func testBioArtifactsDecodeFullPartialAndAbsentSections() throws {
        let full = try decodeArtifact("""
        {
          "today": {
            "recovery": {
              "value": 83.951,
              "baseline": 68.3,
              "deltaPct": 22.991,
              "driftDirection": "up",
              "label": "23% over your 30-day baseline · 6/30 samples"
            }
          },
          "flags": ["recovery 43% under your baseline · 6/30 samples"],
          "trend": {
            "recovery": [
              {"date":"2026-07-09","value":39,"baseline":68.3,"deltaPct":-42.9,"driftDirection":"down"}
            ],
            "sleep": [],
            "hrv": [
              {"date":"2026-07-09","value":56.7,"baseline":66.3,"deltaPct":-14.48,"driftDirection":"down"}
            ]
          },
          "log": [
            {"id":"foot_1","at":"2026-07-10T20:04:27.978Z","kind":"meal","text":"eggs","read":"protein-forward"}
          ],
          "generatedAt":"2026-07-10T20:04:28.540Z",
          "source":"cs-k"
        }
        """)

        XCTAssertEqual(full.today?.recovery?.value, 83.951)
        XCTAssertNil(full.today?.recovery?.source)
        XCTAssertEqual(full.flags, ["recovery 43% under your baseline · 6/30 samples"])
        XCTAssertEqual(full.trend?.recovery.count, 1)
        XCTAssertEqual(full.trend?.hrv.first?.value, 56.7)
        XCTAssertNil(full.trend?.hrv.first?.source)
        XCTAssertEqual(full.log.first?.kind, .meal)
        XCTAssertEqual(full.log.first?.read, "protein-forward")
        XCTAssertEqual(full.generatedAt, "2026-07-10T20:04:28.540Z")

        let partial = try decodeArtifact("""
        {
          "trend": {
            "hrv": [
              {"date":"2026-07-09","value":"56.7","baseline":"66.3","deltaPct":"-14.48","driftDirection":"down"}
            ]
          },
          "generatedAt":"2026-07-10T20:04:28.540Z",
          "source":"cs-k"
        }
        """)

        XCTAssertNil(partial.today)
        XCTAssertTrue(partial.flags.isEmpty)
        XCTAssertEqual(partial.trend?.recovery, [])
        XCTAssertEqual(partial.trend?.hrv.first?.deltaPct, -14.48)
        XCTAssertTrue(partial.log.isEmpty)

        let absent = try decodeArtifact("""
        {"generatedAt":"2026-07-10T20:04:28.540Z","source":"cs-k"}
        """)

        XCTAssertNil(absent.today)
        XCTAssertNil(absent.trend)
        XCTAssertTrue(absent.flags.isEmpty)
        XCTAssertTrue(absent.log.isEmpty)
    }

    func testBioResearchArtifactSectionsDecodeAdditively() throws {
        let artifact = try decodeArtifact("""
        {
          "biomarkers": [
            {
              "id": "ferritin",
              "name": "ferritin",
              "current": "38",
              "unit": "ng/mL",
              "subtitle": "38 ng/mL · panel jul 6",
              "range": {"lower":15,"upper":400,"optimal":{"lower":50,"upper":150}},
              "history": [{"label":"jul","value":38}],
              "documents": [{"text":"source: panel jul 6 · pdf"}]
            }
          ],
          "nextTests": [{"id":"full-panel","name":"full panel","status":"due","date":"oct"}],
          "reports": [{"id":"blood-panel","name":"blood panel","date":"jul 6","glyph":"document"}],
          "protocols": [{
            "id":"baseline",
            "name":"baseline",
            "subtitle":"quarterly",
            "tested":22,
            "total":24,
            "coverage":0.92,
            "coverageLine":"22 of 24 markers tested · 2 due",
            "categories":[{"name":"metabolic","count":5,"signal":"ok"}],
            "dueTests":["iron panel"],
            "note":"testing only"
          }],
          "meditationLibrary": [{
            "id":"jhana",
            "name":"jhana",
            "group":"active",
            "railStatus":"day 34 · ph 2",
            "subtitle":"the 8 absorptions",
            "evidenceLabel":"Level IV",
            "phases":["access concentration","first jhana entry"],
            "currentPhaseIndex":1,
            "focus":"let absorption arrive",
            "methodNow":["breath-nimitta"],
            "indications":[{"name":"concentration","evidence":"trad","outcome":"deeper samādhi"}],
            "safety":[{"text":"screen first","absolute":true}],
            "note":"reference"
          }]
        }
        """)

        XCTAssertEqual(artifact.biomarkers.first?.value, 38)
        XCTAssertEqual(artifact.biomarkers.first?.range?.optimalLabel, "optimal 50–150")
        XCTAssertEqual(artifact.biomarkers.first?.history.first?.label, "jul")
        XCTAssertEqual(artifact.nextTests.first?.status, "due")
        XCTAssertEqual(artifact.reports.first?.glyph, .document)
        XCTAssertEqual(artifact.protocols.first?.coverageFraction ?? 0, 0.92, accuracy: 0.0001)
        XCTAssertEqual(artifact.meditationLibrary.first?.currentPhaseIndex, 1)
        XCTAssertTrue(artifact.interventions.isEmpty)
    }

    func testBioDemoOverlayKeepsRealRecordsAndFillsMissingResearchSlots() {
        let realMarker = BioBiomarkerRecord(
            id: "ferritin",
            name: "ferritin",
            value: 90,
            unit: "ng/mL"
        )
        let realProtocol = BioTestingProtocolProjection(
            id: "baseline",
            name: "baseline",
            subtitle: "wire",
            tested: 1,
            total: 1,
            coveragePercent: 100,
            coverageLine: "wire",
            categories: [],
            dueTests: [],
            note: "wire"
        )

        let result = BioDemo.overlay(
            onto: BioArtifactsResponse(biomarkers: [realMarker], protocols: [realProtocol])
        )

        XCTAssertEqual(result.biomarkers.first(where: { $0.id == "ferritin" })?.value, 90)
        XCTAssertNotNil(result.biomarkers.first(where: { $0.id == "vitamin-d" }))
        XCTAssertEqual(result.protocols.first(where: { $0.id == "baseline" })?.subtitle, "wire")
        XCTAssertNotNil(result.protocols.first(where: { $0.id == "blueprint" }))
        XCTAssertEqual(result.nextTests.map(\.id), BioDemo.nextTests.map(\.id))
        XCTAssertEqual(result.meditationLibrary.map(\.id), BioDemo.meditationLibrary.map(\.id))
        XCTAssertEqual(result.today?.recovery?.value, BioDemo.today.recovery?.value)
        XCTAssertEqual(result.today?.sleep?.value, BioDemo.today.sleep?.value)
        XCTAssertEqual(result.flags, BioDemo.flags)
        XCTAssertEqual(result.interventions.first?.phaseStatus, .active)
        XCTAssertTrue(result.interventions.contains { $0.phaseStatus == .active })
    }

    func testBioDemoOverlayPreservesRealTodayFieldsAndFlags() {
        let real = BioArtifactsResponse(
            flags: ["wire flag"],
            today: BioToday(
                recovery: BioTodayMetric(value: 88, label: "today", source: "wire")
            )
        )

        let result = BioDemo.overlay(onto: real)

        XCTAssertEqual(result.today?.recovery?.value, 88)
        XCTAssertEqual(result.today?.recovery?.source, "wire")
        XCTAssertEqual(result.today?.sleep?.value, BioDemo.today.sleep?.value)
        XCTAssertEqual(result.flags, ["wire flag"])
    }

    func testBioFeelingScaleMathClampsAndRoundsToTheNinePointScale() {
        XCTAssertEqual(BioFeelingScaleMath.value(atX: -10, width: 100, count: 9), 1)
        XCTAssertEqual(BioFeelingScaleMath.value(atX: 0, width: 100, count: 9), 1)
        XCTAssertEqual(BioFeelingScaleMath.value(atX: 50, width: 100, count: 9), 5)
        XCTAssertEqual(BioFeelingScaleMath.value(atX: 100, width: 100, count: 9), 9)
        XCTAssertEqual(BioFeelingScaleMath.value(atX: 200, width: 100, count: 9), 9)
        XCTAssertEqual(BioFeelingScaleMath.value(atX: 50, width: 0, count: 9), 1)
    }

    func testBioDemoOverlayAddsPlannedMealWhenLogAlreadyHasEntries() {
        let realMeal = BioLogEntry(
            id: "real-meal",
            at: "2026-08-05T06:10:00Z",
            kind: .meal,
            text: "wire meal"
        )

        let result = BioDemo.overlay(onto: BioArtifactsResponse(log: [realMeal]))

        XCTAssertTrue(result.log.contains(where: { $0.id == realMeal.id }))
        XCTAssertTrue(
            result.log.contains(where: { $0.id == "demo-meal-d0503" && $0.isPlanned }),
            "demo overlay must retain the planned meal when the log is non-empty"
        )
    }

    func testBioResearchPresentationMath() {
        XCTAssertEqual(BioRangeBandMath.position(value: 38, lower: 0, upper: 100), 0.38, accuracy: 0.0001)
        XCTAssertEqual(BioRangeBandMath.position(value: -1, lower: 0, upper: 100), 0)
        XCTAssertEqual(BioRangeBandMath.position(value: 101, lower: 0, upper: 100), 1)
        XCTAssertEqual(BioCoverageRingMath.fraction(tested: 22, total: 24), 22.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(BioCoverageRingMath.fraction(tested: nil, total: nil, coveragePercent: 45), 0.45, accuracy: 0.0001)
        XCTAssertEqual(BioSparklineMath.reduce([0, 1, 2, 3, 4], maximumPoints: 3), [0, 2, 4])
        XCTAssertEqual(BioSparklineMath.reduce([0, 1, 2], maximumPoints: 8), [0, 1, 2])
    }

    func testBioHistoryPointMappingHasNonZeroSpreadForDemoSeries() throws {
        let record = try XCTUnwrap(BioDemo.biomarkers.first(where: { $0.id == "vitamin-d" }))
        let points = BioSparklineMath.points(
            record.history.map(\.value),
            width: KStyle.bioHistoryMaximumWidth,
            height: KStyle.bioHistoryHeight - KStyle.bioHistoryBottomLabelOffset,
            maximumPoints: 9
        )

        XCTAssertEqual(points.count, record.history.count)
        let yValues = points.map(\.y)
        XCTAssertGreaterThan((yValues.max() ?? 0) - (yValues.min() ?? 0), 0)
    }

    func testBioMetricSourcesDecodeAdditivelyIntoQuietChipCopy() throws {
        let artifact = try decodeArtifact("""
        {
          "today": {
            "recovery": {"value": 77, "source": "whoop-api"},
            "sleep": {"value": 7.4, "source": "whoop-ble"},
            "hrv": {"value": 51, "source": "healthkit"}
          },
          "trend": {
            "recovery": [
              {"date":"2026-07-08","value":61,"source":"healthkit"},
              {"date":"2026-07-09","value":77,"source":"whoop-api"}
            ],
            "sleep": [
              {"date":"2026-07-09","value":7.4,"source":"whoop-ble"}
            ]
          }
        }
        """)

        XCTAssertEqual(artifact.today?.recovery?.source, "whoop-api")
        XCTAssertEqual(artifact.today?.sleep?.source, "whoop-ble")
        XCTAssertEqual(artifact.today?.hrv?.source, "healthkit")
        XCTAssertEqual(artifact.trend?.recovery.map(\.source), ["healthkit", "whoop-api"])
        XCTAssertEqual(artifact.trend?.sleep.first?.source, "whoop-ble")

        XCTAssertEqual(BioMetricSource(wireValue: artifact.today?.recovery?.source), .whoopAPI)
        XCTAssertEqual(BioMetricSource(wireValue: artifact.today?.sleep?.source), .whoopBLE)
        XCTAssertEqual(BioMetricSource(wireValue: artifact.today?.hrv?.source), .healthKit)
        XCTAssertEqual(BioMetricSource.whoopAPI.chipText, "whoop api")
        XCTAssertEqual(BioMetricSource.whoopBLE.chipText, "whoop ble")
        XCTAssertEqual(BioMetricSource.healthKit.chipText, "healthkit")

        let recoveryLine = try XCTUnwrap(artifact.today?.recovery.flatMap {
            BioTodayLineFormatter.line(marker: .recovery, metric: $0)
        })
        let sleepLine = try XCTUnwrap(artifact.today?.sleep.flatMap {
            BioTodayLineFormatter.line(marker: .sleep, metric: $0)
        })
        let hrvLine = try XCTUnwrap(artifact.today?.hrv.flatMap {
            BioTodayLineFormatter.line(marker: .hrv, metric: $0)
        })
        XCTAssertEqual(recoveryLine.plainText, "recovery 77 · whoop api")
        XCTAssertEqual(sleepLine.plainText, "sleep 7.4 · whoop ble")
        XCTAssertEqual(hrvLine.plainText, "hrv 51 · healthkit")
    }

    func testUnknownAndMissingBioMetricSourcesRenderSilently() throws {
        let artifact = try decodeArtifact("""
        {
          "today": {
            "recovery": {
              "value": 39,
              "deltaPct": -42.9,
              "source": "future-sensor"
            },
            "sleep": {
              "value": 7.4,
              "deltaPct": 2.1
            }
          }
        }
        """)

        let recoveryMetric = try XCTUnwrap(artifact.today?.recovery)
        let recoveryLine = try XCTUnwrap(BioTodayLineFormatter.line(
            marker: .recovery,
            metric: recoveryMetric
        ))
        XCTAssertEqual(recoveryMetric.value, 39)
        XCTAssertEqual(recoveryMetric.source, "future-sensor")
        XCTAssertNil(recoveryLine.source)
        XCTAssertEqual(
            recoveryLine.plainText,
            "recovery 39 · 43% under your baseline"
        )

        let sleepMetric = try XCTUnwrap(artifact.today?.sleep)
        let sleepLine = try XCTUnwrap(BioTodayLineFormatter.line(marker: .sleep, metric: sleepMetric))
        XCTAssertEqual(sleepMetric.value, 7.4)
        XCTAssertNil(sleepMetric.source)
        XCTAssertNil(sleepLine.source)
        XCTAssertEqual(sleepLine.plainText, "sleep 7.4 · 2.1% over your baseline")
    }

    func testTodayLinePreservesServerWinningValueAndSourceWithoutClientPrecedence() throws {
        let artifact = try decodeArtifact("""
        {
          "today": {
            "recovery": {
              "value": 39,
              "deltaPct": -42.9,
              "source": "healthkit"
            }
          },
          "trend": {
            "recovery": [
              {"date":"2026-07-09","value":77,"source":"whoop-api"}
            ]
          }
        }
        """)

        let metric = try XCTUnwrap(artifact.today?.recovery)
        let line = try XCTUnwrap(BioTodayLineFormatter.line(marker: .recovery, metric: metric))

        XCTAssertEqual(line.valueText, "39")
        XCTAssertEqual(line.source, .healthKit)
        XCTAssertEqual(line.plainText, "recovery 39 · 43% under your baseline · healthkit")
    }

    func testBioArtifactDecodesU1InterventionProjectionAdditively() throws {
        let artifact = try decodeArtifact("""
        {
          "interventions": [
            {
              "id": "intervention:iron-recovery",
              "title": "Iron and recovery reset",
              "rationale": "Track the confirmed iron lever against the next panel.",
              "category": "nutrition",
              "startPolicy": "founder-confirmed",
              "phases": [
                {
                  "name": "Foundation",
                  "order": 1,
                  "durationDays": 28,
                  "targetBiomarkers": [
                    {"domain":"blood","id":"hs_crp","frontierExcluded":true}
                  ]
                }
              ],
              "supplements": [
                {"name":"Iron bisglycinate","dose":"25 mg","timing":"morning","withFood":true}
              ],
              "targetBiomarkers": [
                {"domain":"blood","id":"ferritin","frontierExcluded":true},
                {"domain":"wearable","id":"hrv","frontierExcluded":true}
              ],
              "eventAt": "2026-07-19T08:00:00.000Z",
              "futureField": {"ignored": true}
            },
            {"id":"empty-projection"}
          ]
        }
        """)

        XCTAssertEqual(artifact.interventions.count, 2)
        let intervention = try XCTUnwrap(artifact.interventions.first)
        XCTAssertEqual(intervention.id, "intervention:iron-recovery")
        XCTAssertEqual(intervention.title, "Iron and recovery reset")
        XCTAssertEqual(intervention.phases.first?.summaryText, "foundation · 28d")
        XCTAssertEqual(intervention.phases.first?.targetsText, "hs crp · blood")
        XCTAssertEqual(intervention.supplements.first?.summaryText, "iron bisglycinate · 25 mg · morning · with food")
        XCTAssertEqual(intervention.targetsText, "ferritin · blood · hrv · wearable")
        XCTAssertTrue(intervention.metadataText?.contains("founder confirmed") == true)
        XCTAssertEqual(intervention.targetBiomarkers.first?.frontierExcluded, true)
        XCTAssertTrue(intervention.hasDisplayContent)
        XCTAssertFalse(artifact.interventions[1].hasDisplayContent)
    }

    func testBioRegisterAlwaysShowsAllFiveTabsAndDefaultsToNutrition() {
        // Founder ruling 2026-08-04: gating and the protocols hard-off are retired —
        // all five tabs always render; bio opens on nutrition.
        XCTAssertEqual(BioState.allCases, [
            .overview,
            .biomarkers,
            .protocols,
            .interventions,
            .nutrition,
        ])
        XCTAssertEqual(BioStateAvailability.allStates, BioState.allCases)
        XCTAssertTrue(BioStateAvailability.allStates.contains(.protocols))
        XCTAssertEqual(BioStateAvailability.defaultState, .nutrition)

        XCTAssertEqual(BioInitialState.resolve(arguments: []), .nutrition)
        XCTAssertEqual(BioInitialState.resolve(arguments: ["-biotab", "overview"]), .overview)
        XCTAssertEqual(BioInitialState.resolve(arguments: ["-biotab", "protocols"]), .protocols)
        XCTAssertEqual(BioInitialState.resolve(arguments: ["-biotab", "garbage"]), .nutrition)
    }

    func testBioCameraStageRequestOnlyFollowsNutrition() {
        XCTAssertTrue(BioCameraStageRequest.isRequested(for: .nutrition))
        for state in BioState.allCases where state != .nutrition {
            XCTAssertFalse(BioCameraStageRequest.isRequested(for: state), "\(state)")
        }
    }

    func testBioSystemGridPopulatesRealMetricsAndPendsWithoutData() {
        let recovery = BioTodayMetric(value: 54, deltaPct: -10.89, label: "9d ago", source: "whoop-api")
        let hrv = BioTodayMetric(value: 76.87, deltaPct: -0.04, label: "9d ago", source: "whoop-api")
        let heart = BioSystemCard.make(.heart, metric: recovery, secondary: ("hrv", hrv))
        XCTAssertTrue(heart.hasData)
        XCTAssertEqual(heart.scoreText, "54")
        XCTAssertEqual(heart.tone, .steady) // |−10.89| < 12
        XCTAssertTrue(heart.freshnessText.contains("whoop api"))
        XCTAssertTrue(heart.freshnessText.contains("9d ago"))
        XCTAssertTrue(heart.isStale) // 9d ≥ 2d → age-fade
        XCTAssertTrue(heart.provenanceText.contains("hrv"))

        let sleep = BioSystemCard.make(
            .sleep,
            metric: BioTodayMetric(value: 7.24, deltaPct: 14.92, label: "9d ago", source: "whoop-api")
        )
        XCTAssertEqual(sleep.tone, .watch) // |14.92| ≥ 12

        let blood = BioSystemCard.pending(.blood)
        XCTAssertFalse(blood.hasData)
        XCTAssertEqual(blood.scoreText, "—")
        XCTAssertEqual(blood.tone, .pending)
        XCTAssertEqual(blood.freshnessText, "no data yet")
        XCTAssertTrue(blood.provenanceText.contains("silence beats a fabricated number"))

        // Absent metric → pending, never a fabricated number.
        XCTAssertFalse(BioSystemCard.make(.heart, metric: nil).hasData)
        XCTAssertEqual(BioSystemCard.make(.sleep, metric: BioTodayMetric()).scoreText, "—")
    }

    func testSystemToneDerivesFromBaselineDistance() {
        XCTAssertEqual(BioSystemTone.derive(deltaPct: nil), .steady)
        XCTAssertEqual(BioSystemTone.derive(deltaPct: 5), .steady)
        XCTAssertEqual(BioSystemTone.derive(deltaPct: -11.9), .steady)
        XCTAssertEqual(BioSystemTone.derive(deltaPct: 12), .watch)
        XCTAssertEqual(BioSystemTone.derive(deltaPct: -20), .watch)
        XCTAssertEqual(BioSystemTone.steady.word, "steady")
        XCTAssertEqual(BioSystemTone.watch.word, "watch")
        XCTAssertEqual(BioSystemTone.pending.word, "baseline pending")
    }

    func testBioRecencyParsesAgeAndFlagsStale() {
        XCTAssertEqual(BioRecency.ageDays(from: "today"), 0)
        XCTAssertEqual(BioRecency.ageDays(from: "9d ago"), 9)
        XCTAssertEqual(BioRecency.ageDays(from: "2w ago"), 14)
        XCTAssertEqual(try XCTUnwrap(BioRecency.ageDays(from: "6h ago")), 0.25, accuracy: 0.0001)
        XCTAssertNil(BioRecency.ageDays(from: "whenever"))
        XCTAssertFalse(BioRecency.isStale(label: "today"))
        XCTAssertFalse(BioRecency.isStale(label: "6h ago"))
        XCTAssertTrue(BioRecency.isStale(label: "9d ago"))
        XCTAssertFalse(BioRecency.isStale(label: nil)) // unparseable → fresh, never a false stale claim
    }

    @MainActor
    func testOverviewGridAlwaysRendersSixSystemsAndAllTabsWithoutData() {
        // Preload/no-spinner guarantee: the grid renders all six systems (each honest
        // pending) and all five tabs before any fetch — nothing is gated on a load.
        let model = BioModel(baseURL: "http://daemon.test", clientFactory: { AGUIClient(baseURL: $0) })
        XCTAssertEqual(model.systemCards.count, 6)
        XCTAssertEqual(model.systemCards.map(\.system), BioSystem.allCases)
        XCTAssertTrue(model.systemCards.allSatisfy { !$0.hasData })
        XCTAssertEqual(model.availableStates, BioState.allCases)
        XCTAssertNil(model.overviewAlert)
    }

    @MainActor
    func testReconnectKeepsLastGoodBioContentAndMarksItStale() async throws {
        let syncedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let recorder = BioSequenceRecorder(responses: [
            (200, #"{"generatedAt":"2026-07-10T20:04:27.978Z","today":{"recovery":{"value":83}}}"#),
            (200, #"{"entries":[]}"#),
            (503, #"{"ok":false,"error":"offline"}"#),
            (503, #"{"ok":false,"error":"offline"}"#)
        ])
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            nowProvider: { syncedAt }
        )

        await model.load()
        let lastGoodArtifact = model.artifact
        XCTAssertFalse(model.isStale)

        await model.load()

        XCTAssertEqual(model.artifact, lastGoodArtifact)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
    }

    @MainActor
    func testNutritionTimelineShowsOptimisticMealImmediately() async {
        // The capture control id is stable, and a just-captured (still-local) meal
        // appears on the nutrition timeline at once — the client-side fix for the
        // "meal tracking doesn't work" report (daemon write path verified healthy).
        XCTAssertEqual(BioAccessibility.mealCapture, "bio-meal-capture")

        let recorder = BioHTTPRecorder(body: #"{"ok":false,"error":"offline"}"#, delayNanoseconds: 200_000_000)
        let defaults = tempDefaults()
        let queueStore = MealPhotoQueueStore(key: "meal-photo.\(UUID().uuidString)", defaults: defaults)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            mealPhotoQueueStore: queueStore,
            nowProvider: { Date(timeIntervalSince1970: 1_789_000_000) }
        )

        let task = Task { try await model.submitMealPhotoPayload(testEncodedMealPhoto(), caption: "dinner") }
        await Task.yield()

        XCTAssertEqual(model.nutritionEntries.count, 1)
        XCTAssertEqual(model.nutritionEntries.first?.kind, .meal)
        XCTAssertTrue(model.nutritionEntries.first?.status.isLocal == true)

        _ = try? await task.value
    }

    func testTodayLineCopyRoundsAndPreservesServerDenominatorLanguage() throws {
        let metric = BioTodayMetric(
            value: 83.951,
            baseline: 68.3,
            deltaPct: 22.991,
            driftDirection: "up",
            label: "23% over your 30-day baseline · 6/30 samples"
        )
        let line = try XCTUnwrap(BioTodayLineFormatter.line(marker: .recovery, metric: metric))

        XCTAssertEqual(
            line.plainText,
            "recovery 84 · 23% over your 30-day baseline · 6/30 samples · drifting up"
        )
        XCTAssertFalse(line.plainText.contains("83.951"))
        XCTAssertTrue(line.plainText.contains("6/30 samples"))

        let sleep = try XCTUnwrap(BioTodayLineFormatter.line(
            marker: .sleep,
            metric: BioTodayMetric(value: 6.714, deltaPct: -11.61, driftDirection: "down")
        ))

        XCTAssertEqual(sleep.plainText, "sleep 6.7 · 12% under your baseline · drifting down")
    }

    @MainActor
    func testBodyLogPostOptimisticallyAppendsThenReconcilesSavedEntry() async throws {
        let recorder = BioHTTPRecorder(body: """
        {
          "ok": true,
          "entry": {
            "id": "foot_saved",
            "at": "2026-07-10T20:04:27.978Z",
            "kind": "meal",
            "text": "eggs and rice",
            "read": "protein-forward"
          },
          "generatedAt": "2026-07-10T20:04:27.982Z",
          "source": "cs-k"
        }
        """, delayNanoseconds: 150_000_000)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            nowProvider: { now }
        )

        let task = Task { await model.submitLog(kind: .meal, text: " eggs and rice ") }
        await Task.yield()

        XCTAssertEqual(model.logEntries.count, 1)
        XCTAssertEqual(model.logEntries.first?.kind, .meal)
        XCTAssertEqual(model.logEntries.first?.text, "eggs and rice")
        XCTAssertEqual(model.logEntries.first?.status, .pending)

        let didSubmit = await task.value

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(model.logEntries.map(\.id), ["foot_saved"])
        XCTAssertEqual(model.logEntries.first?.readLine, "protein-forward")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/api/body/log")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try bodyObject(from: request)
        XCTAssertEqual(body["kind"] as? String, "meal")
        XCTAssertEqual(body["text"] as? String, "eggs and rice")
        XCTAssertNotNil(body["at"] as? String)
    }

    @MainActor
    func testBodyLogPostFailureKeepsOptimisticEntryWithFlatErrorLine() async {
        let recorder = BioHTTPRecorder(body: #"{"ok":false,"error":"not_found"}"#)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            nowProvider: { Date(timeIntervalSince1970: 1_789_000_000) }
        )

        let didSubmit = await model.submitLog(kind: .note, text: "headache after lunch")

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(model.logEntries.count, 1)
        XCTAssertEqual(model.logEntries.first?.kind, .note)
        XCTAssertEqual(model.logEntries.first?.readLine, "log failed · not_found")
        XCTAssertEqual(model.logErrorText, "log failed · not_found")
    }

    func testMealPhotoEncoderDownscalesAndEncodesJpegBounds() throws {
        let image = testImage(size: CGSize(width: 2_400, height: 1_200))

        let encoded = try MealPhotoEncoder.encode(image)

        XCTAssertEqual(encoded.pixelWidth, 1_600)
        XCTAssertEqual(encoded.pixelHeight, 800)
        XCTAssertLessThanOrEqual(encoded.longestSide, 1_600)
        XCTAssertFalse(encoded.imageBase64.isEmpty)
        let decodedData = try XCTUnwrap(Data(base64Encoded: encoded.imageBase64))
        XCTAssertEqual(decodedData, encoded.jpegData)
        let decodedImage = try XCTUnwrap(UIImage(data: decodedData))
        XCTAssertLessThanOrEqual(max(decodedImage.size.width, decodedImage.size.height), 1_600)
    }

    @MainActor
    func testMealPhotoPostOptimisticallyAppendsThenReconcilesDoneAnalysis() async throws {
        let recorder = BioHTTPRecorder(body: """
        {
          "ok": true,
          "entry": {
            "id": "meal_photo_saved",
            "at": "2026-07-10T20:04:27.978Z",
            "kind": "meal",
            "text": "dinner plate",
            "imageRef": "img_meal_1",
            "analysis": {
              "status": "done",
              "name": "chicken rice",
              "macros": {"calories": 620, "protein": 38},
              "read": "protein-forward"
            }
          }
        }
        """, delayNanoseconds: 150_000_000)
        let defaults = tempDefaults()
        let queueStore = MealPhotoQueueStore(key: "meal-photo.\(UUID().uuidString)", defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            mealPhotoQueueStore: queueStore,
            nowProvider: { now }
        )

        let task = Task {
            try await model.submitMealPhotoPayload(testEncodedMealPhoto(), caption: " dinner plate ")
        }
        await Task.yield()

        XCTAssertEqual(model.logEntries.count, 1)
        XCTAssertEqual(model.logEntries.first?.kind, .meal)
        XCTAssertEqual(model.logEntries.first?.text, "dinner plate")
        XCTAssertEqual(model.logEntries.first?.status, .pending)
        XCTAssertEqual(model.logEntries.first?.readLine, KCopy.mealPhotoReading)
        XCTAssertEqual(queueStore.load().count, 1)

        let didSubmit = try await task.value

        XCTAssertTrue(didSubmit)
        XCTAssertTrue(queueStore.load().isEmpty)
        XCTAssertEqual(model.logEntries.map(\.id), ["meal_photo_saved"])
        XCTAssertEqual(model.logEntries.first?.displayText, "chicken rice")
        XCTAssertEqual(model.logEntries.first?.macroLine, "~620 kcal · 38g protein")
        XCTAssertEqual(model.logEntries.first?.readLine, "protein-forward")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/api/body/meal-photo")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try bodyObject(from: request)
        XCTAssertEqual(body["imageBase64"] as? String, "bWVhbC1qcGVn")
        XCTAssertEqual(body["caption"] as? String, "dinner plate")
        XCTAssertNil(body["timestamp"])
    }

    @MainActor
    func testMealPhotoOfflineQueueKeepsNewestThreeAndDrainsOnLoad() async throws {
        let defaults = tempDefaults()
        let queueStore = MealPhotoQueueStore(key: "meal-photo.\(UUID().uuidString)", defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        for offset in 0..<4 {
            queueStore.append(QueuedMealPhoto(
                id: "photo-\(offset)",
                imageBase64: "payload-\(offset)",
                enqueuedAt: start.addingTimeInterval(TimeInterval(offset))
            ))
        }

        XCTAssertEqual(queueStore.load().map(\.id), ["photo-1", "photo-2", "photo-3"])

        let recorder = BioRouteRecorder(postBody: """
        {
          "ok": true,
          "entry": {
            "id": "photo-drained",
            "at": "2026-07-10T20:04:27.978Z",
            "kind": "meal",
            "text": "meal photo",
            "imageRef": "img_drained",
            "analysis": "pending"
          }
        }
        """)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            mealPhotoQueueStore: queueStore,
            nowProvider: { start }
        )

        XCTAssertEqual(model.logEntries.map(\.id), ["photo-3", "photo-2", "photo-1"])

        await model.load()

        XCTAssertTrue(queueStore.load().isEmpty)
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/api/body/meal-photo" }.count, 3)
        XCTAssertTrue(model.logEntries.contains { $0.id == "photo-drained" })
    }

    @MainActor
    func testMealPhotoServerErrorKeepsRetryableFlatErrorLine() async throws {
        let recorder = BioHTTPRecorder(body: #"{"ok":false,"error":"vision_offline"}"#)
        let defaults = tempDefaults()
        let queueStore = MealPhotoQueueStore(key: "meal-photo.\(UUID().uuidString)", defaults: defaults)
        let model = BioModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            mealPhotoQueueStore: queueStore,
            nowProvider: { Date(timeIntervalSince1970: 1_789_000_000) }
        )

        let didSubmit = try await model.submitMealPhotoPayload(testEncodedMealPhoto(), caption: nil)

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(model.logEntries.count, 1)
        XCTAssertEqual(model.logEntries.first?.readLine, "photo failed · vision_offline — tap to retry")
        XCTAssertEqual(model.logEntries.first?.canRetryMealPhoto, true)
        XCTAssertEqual(model.logErrorText, "photo failed · vision_offline — tap to retry")
        XCTAssertEqual(queueStore.load().count, 1)
        XCTAssertEqual(queueStore.load().first?.lastError, "vision_offline")
    }

    func testBioTabPresenceAndAccessibilityIdentifiers() {
        let items = KTabStripModel.items(active: .bio)

        XCTAssertEqual(items.map(\.title), ["cadence", "chat", "build", "mind", "bio", "admin"])
        XCTAssertEqual(items.first { $0.tab == .bio }?.isActive, true)
        XCTAssertEqual(items.first { $0.tab == .bio }?.textOpacity, KStyle.primaryTextOpacity)
        XCTAssertEqual(BioAccessibility.view, "bio-view")
        XCTAssertEqual(BioAccessibility.stateSelector, "bio-state-selector")
        XCTAssertEqual(BioAccessibility.stateSelectorItem(.interventions), "bio-state-interventions")
        XCTAssertEqual(BioAccessibility.stateContent(.nutrition), "bio-state-content-nutrition")
        XCTAssertEqual(BioAccessibility.logSubmit, "bio-log-submit")
        XCTAssertEqual(BioAccessibility.mealMicronutrients, "bio-meal-micronutrients")
        XCTAssertEqual(BioAccessibility.biomarkerDetail, "bio-biomarker-detail")
        XCTAssertEqual(BioAccessibility.biomarkerRangeBand, "bio-biomarker-range-band")
        XCTAssertEqual(BioAccessibility.protocolCoverageRing, "bio-protocol-coverage-ring")
        XCTAssertEqual(BioAccessibility.testingProtocol("baseline"), "bio-testing-protocol-baseline")
        XCTAssertEqual(BioAccessibility.meditationProtocol("jhana"), "bio-meditation-protocol-jhana")
    }

    func testBioSubTabGrammarUsesTheSharedCadenceTabMetrics() {
        let compact = KStyle.tabStripMetrics(availableWidth: KStyle.tabCompactWidthThreshold)
        XCTAssertEqual(compact.itemSpacing, KStyle.tabCompactItemSpacing)
        XCTAssertEqual(compact.horizontalPadding, KStyle.tabCompactHorizontalPadding)
        XCTAssertEqual(compact.labelTracking, KStyle.tabCompactTracking)
        XCTAssertEqual(compact.labelMinimumScaleFactor, KStyle.tabLabelMinimumScaleFactor)

        let regular = KStyle.tabStripMetrics(availableWidth: KStyle.tabCompactWidthThreshold + 1)
        XCTAssertEqual(regular.itemSpacing, KStyle.tabItemSpacing)
        XCTAssertEqual(regular.horizontalPadding, KStyle.tabHorizontalPadding)
        XCTAssertEqual(regular.labelTracking, KStyle.tracking(for: .tab))
        XCTAssertEqual(regular.labelMinimumScaleFactor, KStyle.fullOpacity)
    }

    func testBodyLogEnvelopeDecodesProdShape() throws {
        let response = try JSONDecoder().decode(BioLogEnvelope.self, from: Data("""
        {
          "entries": [
            {"id":"foot_1","at":"2026-07-10T20:04:27.978Z","kind":"note","text":"bio2 envelope check"}
          ],
          "days": 7,
          "generatedAt": "2026-07-10T20:04:16.845Z",
          "source": "cs-k"
        }
        """.utf8))

        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries.first?.kind, .note)
        XCTAssertEqual(response.days, 7)
        XCTAssertFalse(response.isFailure)
    }

    private func decodeArtifact(_ json: String) throws -> BioArtifactsResponse {
        try JSONDecoder().decode(BioArtifactsResponse.self, from: Data(json.utf8))
    }

    private func bodyObject(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func testImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.12, green: 0.18, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: size.width * 0.25, y: size.height * 0.25, width: size.width * 0.5, height: size.height * 0.5))
        }
    }

    private func testEncodedMealPhoto() -> MealPhotoEncodedImage {
        let data = Data("meal-jpeg".utf8)
        return MealPhotoEncodedImage(
            imageBase64: data.base64EncodedString(),
            jpegData: data,
            pixelWidth: 10,
            pixelHeight: 10
        )
    }

    private func tempDefaults() -> UserDefaults {
        let suite = "bio.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class BioHTTPRecorder: @unchecked Sendable {
    private let body: String
    private let status: Int
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    init(body: String, status: Int = 200, delayNanoseconds: UInt64 = 0) {
        self.body = body
        self.status = status
        self.delayNanoseconds = delayNanoseconds
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.lock.lock()
            self.capturedRequests.append(request)
            self.lock.unlock()

            if self.delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: self.delayNanoseconds)
            }

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://daemon.test")!,
                statusCode: self.status,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: response, lines: Self.stream(self.body))
        }
    }

    private static func stream(_ body: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if !body.isEmpty {
                continuation.yield(body)
            }
            continuation.finish()
        }
    }
}

private final class BioSequenceRecorder: @unchecked Sendable {
    private var responses: [(Int, String)]
    private let lock = NSLock()

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.lock.lock()
            let response = self.responses.isEmpty ? (503, #"{"ok":false,"error":"offline"}"#) : self.responses.removeFirst()
            self.lock.unlock()

            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "http://daemon.test")!,
                statusCode: response.0,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: httpResponse, lines: AsyncThrowingStream { continuation in
                continuation.yield(response.1)
                continuation.finish()
            })
        }
    }
}

private final class BioRouteRecorder: @unchecked Sendable {
    private let postBody: String
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []

    init(postBody: String) {
        self.postBody = postBody
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.lock.lock()
            self.capturedRequests.append(request)
            self.lock.unlock()

            let body: String
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/artifacts/bio"):
                body = #"{"generatedAt":"2026-07-10T20:04:27.978Z","source":"cs-k"}"#
            case ("GET", "/api/body/log"):
                body = #"{"entries":[],"days":7,"source":"cs-k"}"#
            case ("POST", "/api/body/meal-photo"):
                body = self.postBody
            default:
                body = #"{"ok":true}"#
            }

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://daemon.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: response, lines: Self.stream(body))
        }
    }

    private static func stream(_ body: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(body)
            continuation.finish()
        }
    }
}
