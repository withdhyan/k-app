import XCTest
@testable import K

final class BandishCardTests: XCTestCase {
    func testStartedCurrentClockCountsUpOncePerSecondFromFakeReferenceDate() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let clock = BandishCardElapsedClock(
            baselineElapsedSeconds: 58,
            referenceDate: referenceDate,
            isRunning: true
        )

        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate), 58)
        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate.addingTimeInterval(1)), 59)
        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate.addingTimeInterval(2)), 60)
        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate.addingTimeInterval(2.99)), 60)
        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate.addingTimeInterval(-10)), 58)
    }

    func testOptimisticStartCountsFromActionTimestampInsteadOfEarlierSnapshot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let snapshotDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-18T09:00:00Z")
        )
        let actionDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-18T09:15:30Z")
        )
        // CadenceView's outer clock intentionally refreshes by the minute. A tap
        // can therefore arrive after the latest render context.
        let renderDate = actionDate.addingTimeInterval(-30)
        let day = CadenceDayEnvelope(
            date: "2026-07-18",
            bandish: [
                CadenceBlock(
                    id: "current",
                    title: "current",
                    startAt: "09:00",
                    endAt: "10:00"
                ),
            ]
        )
        var localState = CadenceLocalActState()
        localState.apply(blockId: "current", action: .start, at: actionDate)

        let presentation = CadenceDayPresentation(
            day: day,
            localState: localState,
            now: renderDate,
            snapshotSyncedAt: snapshotDate,
            calendar: calendar
        )

        let current = try XCTUnwrap(presentation.blocks.first)
        XCTAssertEqual(current.actionState, .started)
        XCTAssertEqual(current.lifecycleControl.elapsedSeconds, 0)
        XCTAssertEqual(current.clockReferenceDate, actionDate)
        let clock = BandishCardElapsedClock(
            baselineElapsedSeconds: current.lifecycleControl.elapsedSeconds,
            referenceDate: current.clockReferenceDate,
            isRunning: true
        )
        XCTAssertEqual(clock.elapsedSeconds(at: actionDate.addingTimeInterval(5)), 5)
    }

    func testClockFreezesOutsideStartedCurrentState() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 2_000)
        let clock = BandishCardElapsedClock(
            baselineElapsedSeconds: 71,
            referenceDate: referenceDate,
            isRunning: false
        )

        XCTAssertEqual(clock.elapsedSeconds(at: referenceDate.addingTimeInterval(120)), 71)
    }

    func testElapsedFormatterUsesUnpaddedMinutesAndTwoDigitSeconds() {
        XCTAssertEqual(BandishCardElapsedClock.format(0), "0:00")
        XCTAssertEqual(BandishCardElapsedClock.format(59), "0:59")
        XCTAssertEqual(BandishCardElapsedClock.format(60), "1:00")
        XCTAssertEqual(BandishCardElapsedClock.format(3_661), "61:01")
    }

    func testStartedProgressHasTenPercentFloorAndTracksLiveClock() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 3_000)
        let clock = BandishCardElapsedClock(
            baselineElapsedSeconds: 0,
            referenceDate: referenceDate,
            isRunning: true
        )

        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: 0), 0.10, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: 0.01), 0.11, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: 0.5), 0.55, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: 1), 1, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: -1), 0.10, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardProgress.visibleRatio(rawRatio: 2), 1, accuracy: 0.000_1)
        XCTAssertEqual(
            clock.visibleProgressRatio(
                at: referenceDate.addingTimeInterval(30),
                durationSeconds: 60,
                fallbackRawRatio: nil
            ),
            0.55,
            accuracy: 0.000_1
        )
    }

    func testAutoRunAdvancesStepsFromClockWithoutAUserAct() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 4_000)
        var machine = BandishAutoRunStateMachine(
            steps: [
                BandishAutoRunStep(id: "one", text: "one"),
                BandishAutoRunStep(id: "two", text: "two"),
                BandishAutoRunStep(id: "three", text: "three"),
            ],
            stepDuration: 10
        )

        machine.start(at: referenceDate)

        XCTAssertEqual(machine.state, .running)
        XCTAssertEqual(machine.currentStep?.id, "one")
        XCTAssertFalse(machine.advance(to: referenceDate.addingTimeInterval(9)))
        XCTAssertTrue(machine.advance(to: referenceDate.addingTimeInterval(19)))
        XCTAssertEqual(machine.currentStep?.id, "two")
        XCTAssertTrue(machine.advance(by: 20))
        XCTAssertEqual(machine.currentStep?.id, "three")
        XCTAssertEqual(machine.progressRatio, 1, accuracy: 0.000_1)
    }

    func testAutoRunPausesWhileExpandedAndResumesWhenCollapsed() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 5_000)
        var machine = BandishAutoRunStateMachine(
            steps: [
                BandishAutoRunStep(id: "one", text: "one"),
                BandishAutoRunStep(id: "two", text: "two"),
            ],
            stepDuration: 10
        )

        machine.start(at: referenceDate)
        _ = machine.advance(to: referenceDate.addingTimeInterval(4))
        machine.setExpanded(true, at: referenceDate.addingTimeInterval(4))

        XCTAssertEqual(machine.state, .paused)
        XCTAssertEqual(machine.elapsedSeconds, 4, accuracy: 0.000_1)
        XCTAssertFalse(machine.advance(to: referenceDate.addingTimeInterval(20)))
        XCTAssertEqual(machine.elapsedSeconds, 4, accuracy: 0.000_1)

        machine.setExpanded(false, at: referenceDate.addingTimeInterval(20))
        XCTAssertEqual(machine.state, .running)
        XCTAssertTrue(machine.advance(to: referenceDate.addingTimeInterval(30)))
        XCTAssertEqual(machine.currentStep?.id, "two")
    }

    func testAutoRunCompletesAndResetsToTheFirstStep() {
        var machine = BandishAutoRunStateMachine(
            steps: [BandishAutoRunStep(id: "one", text: "one")],
            stepDuration: 10
        )

        machine.start()
        XCTAssertTrue(machine.complete())
        XCTAssertEqual(machine.state, .completed)
        XCTAssertFalse(machine.advance(by: 10))

        machine.reset()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.currentStepIndex, 0)
        XCTAssertEqual(machine.elapsedSeconds, 0, accuracy: 0.000_1)
    }

    func testAutoRunUsesEqualSlicesOfTheBandishDuration() {
        let machine = BandishAutoRunStateMachine(
            steps: [
                BandishAutoRunStep(id: "one", text: "one"),
                BandishAutoRunStep(id: "two", text: "two"),
            ],
            totalDuration: 20
        )

        XCTAssertEqual(machine.stepDuration, 10, accuracy: 0.000_1)
    }

    func testTypographySnapshotIsTheWebQuietRegularHierarchy() {
        XCTAssertEqual(
            BandishCardTypography.snapshot,
            [
                BandishCardTypeMetric(role: .time, pointSize: 14, isRegular: true, usesTabularDigits: true, usesMonospace: true),
                BandishCardTypeMetric(role: .title, pointSize: 14, isRegular: true, usesTabularDigits: false),
                BandishCardTypeMetric(role: .duration, pointSize: 12, isRegular: true, usesTabularDigits: false, usesMonospace: true),
                BandishCardTypeMetric(role: .elapsed, pointSize: 12, isRegular: true, usesTabularDigits: true, usesMonospace: true, minimumWidth: 52),
                BandishCardTypeMetric(role: .secondaryInfo, pointSize: 12, isRegular: true, usesTabularDigits: false),
                BandishCardTypeMetric(role: .workSubtype, pointSize: 12, isRegular: true, usesTabularDigits: false),
            ]
        )
        XCTAssertTrue(BandishCardTypography.snapshot.allSatisfy(\.isRegular))
    }

    func testMotionSnapshotUsesExactPortTimingCurvesAndNoSpringFamily() {
        XCTAssertEqual(BandishCardMotionSpec.timerTickInterval, 1)
        XCTAssertEqual(BandishCardMotionSpec.breathingCycleDuration, 4, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardMotionSpec.staggerInterval, 0.1)
        XCTAssertEqual(BandishCardMotionSpec.maxStaggerSteps, 6)
        XCTAssertEqual(BandishCardMotionSpec.staggerDelay(for: -1), 0)
        XCTAssertEqual(BandishCardMotionSpec.staggerDelay(for: 6), 0.6, accuracy: 0.000_1)
        XCTAssertEqual(BandishCardMotionSpec.staggerDelay(for: 25), 0.6, accuracy: 0.000_1)
        XCTAssertEqual(
            BandishCardMotionSpec.tokens,
            [
                BandishCardMotionToken(name: .colorFlood, duration: 1.0, curve: .zen),
                BandishCardMotionToken(name: .textColor, duration: 0.7, curve: .zen),
                BandishCardMotionToken(name: .progress, duration: 0.5, curve: .standard),
                BandishCardMotionToken(name: .geometry, duration: 0.8, curve: .zen),
                BandishCardMotionToken(name: .entranceOffset, duration: 0.8, curve: .entranceOut),
                BandishCardMotionToken(name: .entranceOpacity, duration: 0.6, curve: .native),
            ]
        )
        XCTAssertEqual(Set(BandishCardMotionSpec.tokens.map(\.family)), [.timingCurve])
    }

    // Doctrine (founder ruling 2026-08-05): the started-dot standard is a 4s
    // numeric breath — was a stray 6s web-port cycle; doctrine bumped to 4s.
    func testBreathingDotUsesDoctrine4sWhiteToGraySineCycle() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

        XCTAssertEqual(
            BandishCardBreathing.intensity255(at: referenceDate, referenceDate: referenceDate),
            255,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            BandishCardBreathing.intensity255(
                at: referenceDate.addingTimeInterval(2),
                referenceDate: referenceDate
            ),
            200,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            BandishCardBreathing.intensity255(
                at: referenceDate.addingTimeInterval(4),
                referenceDate: referenceDate
            ),
            255,
            accuracy: 0.000_1
        )
        XCTAssertEqual(BandishCardBreathing.opacity, 0.8)
    }
}
