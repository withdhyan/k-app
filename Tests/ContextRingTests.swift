import XCTest
@testable import K

final class ContextRingTests: XCTestCase {
    func testTypicalFixtureMatchesTheWireShape() {
        let stats = ContextStatsFixtures.typical

        XCTAssertEqual(stats.fullness, 0.34, accuracy: 0.0001)
        XCTAssertEqual(stats.breakup.map(\.id), ["self-model", "history", "senses"])
        XCTAssertEqual(stats.breakup.map(\.fraction), [0.12, 0.15, 0.07])
        XCTAssertFalse(stats.isNearFull)
    }

    func testNearFullFixtureUsesTheQuietNearFullTreatment() {
        let stats = ContextStatsFixtures.nearFull

        XCTAssertEqual(stats.fullness, 0.91, accuracy: 0.0001)
        XCTAssertTrue(stats.isNearFull)
        XCTAssertEqual(stats.percentText, "91%")
        XCTAssertEqual(stats.ringPercentText, "91")
    }

    func testAbsentFixtureKeepsTheRingSilent() {
        XCTAssertNil(ContextStatsFixtures.stats(for: .absent))
        XCTAssertNil(FixtureContextStatsSource(fixture: .absent).stats(for: .trunk))
        XCTAssertNil(EmptyContextStatsSource().stats(for: .thread(id: "branch-1", title: "topic")))
    }

    func testFixtureSourceIsTargetAgnosticUntilTheWireSeamExists() {
        let source = FixtureContextStatsSource(fixture: .typical)

        XCTAssertEqual(
            source.stats(for: .trunk),
            source.stats(for: .thread(id: "branch-1", title: "topic"))
        )
    }

    func testFixtureArgumentsResolveTypicalNearFullAndAbsent() {
        XCTAssertEqual(
            ContextStatsSourceFactory.fixture(from: ["app", "-chat-context-stats-fixture", "typical"]),
            .typical
        )
        XCTAssertEqual(
            ContextStatsSourceFactory.fixture(from: ["app", "-chat-context-stats=near-full"]),
            .nearFull
        )
        XCTAssertEqual(
            ContextStatsSourceFactory.fixture(from: ["app", "-ui57-context-ring"]),
            .typical
        )
        XCTAssertEqual(
            ContextStatsSourceFactory.fixture(from: ["app", "-chat-context-stats-fixture", "absent"]),
            .absent
        )
        XCTAssertNil(ContextStatsSourceFactory.fixture(from: ["app"]))
    }

    func testChatFixturesDefaultToVisibleComposerStatsWhenNoOverrideIsPassed() {
        let source = ContextStatsSourceFactory.source(arguments: [
            "app",
            W31ChatThreadFixture.launchArgument,
            W31ChatThreadFixture.stateArgument,
            W31ChatThreadFixture.State.populated.rawValue,
        ])

        XCTAssertEqual(
            source.stats(for: .trunk),
            ContextStatsFixtures.typical
        )
        XCTAssertNil(
            ContextStatsSourceFactory.source(arguments: [
                "app",
                W31ChatThreadFixture.launchArgument,
                W31ChatThreadFixture.stateArgument,
                W31ChatThreadFixture.State.edge.rawValue,
                "-chat-context-stats-fixture",
                ContextStatsFixture.absent.rawValue,
            ]).stats(for: .trunk)
        )
    }

    func testBreakupFractionTextAndRelativeBarFractionStayBounded() {
        let row = ContextBreakup(id: "history", label: "history", fraction: 0.15)

        XCTAssertEqual(row.percentText, "15%")
        XCTAssertEqual(row.barFraction(in: 0.34), CGFloat(0.15 / 0.34), accuracy: 0.0001)
        XCTAssertEqual(row.barFraction(in: 0), .zero)
        XCTAssertEqual(
            ContextBreakup(id: "over", label: "over", fraction: 4).fraction,
            1
        )
        XCTAssertEqual(
            ContextBreakup(id: "under", label: "under", fraction: -1).fraction,
            0
        )
    }

    func testContextRingMotionUsesNamedTokensAndKeepsFillFeedbackOnReduceMotion() {
        XCTAssertEqual(KStyle.contextRingExpansionDuration, KStyle.chatStructureDuration)
        XCTAssertEqual(KStyle.contextRingFillDuration, 1.0)
        XCTAssertEqual(
            KStyle.contextRingExpansionMotionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.contextRingExpansionDuration
            )
        )
        XCTAssertEqual(
            KStyle.contextRingExpansionMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
        XCTAssertEqual(
            KStyle.contextRingFillMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }
}
