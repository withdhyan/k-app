import XCTest
@testable import K

final class DayArcTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testWakingDayMatchesTheV7EightSegmentShapeAndLabels() throws {
        let model = DayArcModel(now: try date("2026-07-20T13:00:00Z"), calendar: calendar)

        XCTAssertEqual(model.segments.count, 8)
        XCTAssertEqual(model.hourLabels, ["6a", "10a", "2p", "6p", "10p"])
        XCTAssertEqual(
            model.segments.map(\.state),
            [.past, .past, .past, .now, .ahead, .ahead, .ahead, .ahead]
        )
        XCTAssertTrue(model.hasCurrentSegment)
        XCTAssertEqual(model.accessibilityLabel, "waking day · 3 past · now · 4 ahead")
    }

    func testClockStateMovesIndependentlyAtWakingDayBoundaries() throws {
        let beforeWakingDay = DayArcModel(
            now: try date("2026-07-20T05:59:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(
            beforeWakingDay.segments.map(\.state),
            Array(repeating: .ahead, count: 8)
        )
        XCTAssertFalse(beforeWakingDay.hasCurrentSegment)
        XCTAssertEqual(
            DayArcModel(now: try date("2026-07-20T06:00:00Z"), calendar: calendar)
                .segments.map(\.state),
            [.now, .ahead, .ahead, .ahead, .ahead, .ahead, .ahead, .ahead]
        )
        XCTAssertEqual(
            DayArcModel(now: try date("2026-07-20T08:00:00Z"), calendar: calendar)
                .segments.map(\.state),
            [.past, .now, .ahead, .ahead, .ahead, .ahead, .ahead, .ahead]
        )
        let afterWakingDay = DayArcModel(
            now: try date("2026-07-20T22:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(
            afterWakingDay.segments.map(\.state),
            Array(repeating: .past, count: 8)
        )
        XCTAssertFalse(afterWakingDay.hasCurrentSegment)
    }

    // Founder 2026-08-05: the day-arc breath matches the build segment-bar spec.
    func testNowBreathMatchesTheBuildSegmentBarCycle() {
        let cycle = DayArcMotionSpec.breathingCycleDuration
        let start = Date(timeIntervalSinceReferenceDate: 0)

        XCTAssertEqual(cycle, KStyle.buildSegmentBreathPeriod)
        XCTAssertEqual(
            KStyle.breathOpacity(
                at: start,
                period: cycle,
                minimumOpacity: KStyle.dayArcNowMinimumOpacity
            ),
            KStyle.dayArcNowMinimumOpacity,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            KStyle.breathOpacity(
                at: start.addingTimeInterval(cycle / 2),
                period: cycle,
                minimumOpacity: KStyle.dayArcNowMinimumOpacity
            ),
            KStyle.fullOpacity,
            accuracy: 0.000_001
        )
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }
}
