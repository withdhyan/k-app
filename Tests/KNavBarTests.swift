import Foundation
import XCTest
import SwiftUI
@testable import K

final class KNavBarTests: XCTestCase {
    private let viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)

    // MARK: - Icons: one glyph per tab, drawn and bounded

    func testEveryTabRendersANonEmptyGlyph() {
        for tab in KAppTab.allCases {
            let path = KNavIconShape(tab: tab).path(in: viewBox)
            XCTAssertFalse(path.isEmpty, "\(tab.rawValue) glyph is empty")
        }
    }

    func testGlyphStaysInsideItsFrame() {
        let tolerance: CGFloat = 0.001
        for tab in KAppTab.allCases {
            let bounds = KNavIconShape(tab: tab).path(in: viewBox).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, -tolerance, "\(tab.rawValue) overflows left")
            XCTAssertGreaterThanOrEqual(bounds.minY, -tolerance, "\(tab.rawValue) overflows top")
            XCTAssertLessThanOrEqual(bounds.maxX, viewBox.width + tolerance, "\(tab.rawValue) overflows right")
            XCTAssertLessThanOrEqual(bounds.maxY, viewBox.height + tolerance, "\(tab.rawValue) overflows bottom")
        }
    }

    func testGlyphScalesWithFrame() {
        let small = KNavIconShape(tab: .bio).path(in: viewBox).boundingRect
        let large = KNavIconShape(tab: .bio).path(in: CGRect(x: 0, y: 0, width: 48, height: 48)).boundingRect
        XCTAssertEqual(large.width, small.width * 2, accuracy: 0.01)
        XCTAssertEqual(large.height, small.height * 2, accuracy: 0.01)
    }

    func testStrokeWeightHoldsAsIconScales() {
        // 1.4 in the 24-unit viewBox, kept proportional as the glyph shrinks.
        XCTAssertEqual(KStyle.navIconStrokeWidth(iconSize: 24), 1.4, accuracy: 0.0001)
        XCTAssertEqual(
            KStyle.navIconStrokeWidth(iconSize: KStyle.navCompactIconSize),
            KStyle.navCompactIconSize / 24 * 1.4,
            accuracy: 0.0001
        )
        XCTAssertLessThan(
            KStyle.navIconStrokeWidth(iconSize: KStyle.navCompactIconSize),
            KStyle.navIconStrokeWidth(iconSize: KStyle.navRegularIconSize)
        )
    }

    // MARK: - Selection + unread dots come from the shared tab model

    func testNavItemsFollowTabOrderAndSelection() {
        let items = KTabStripModel.items(active: .bio)
        XCTAssertEqual(items.map(\.tab), KAppTab.allCases)
        XCTAssertEqual(
            items.filter(\.isActive).map(\.tab),
            [.bio],
            "exactly the selected tab is active"
        )
    }

    func testUnreadDotsTrackWaitingSources() {
        let items = KTabStripModel.items(
            active: .cadence,
            chatHasUnread: true,
            openBuildCards: 1,
            adminDueTodayItems: 0
        )
        let dotted = Set(items.filter(\.showsDot).map(\.tab))
        XCTAssertEqual(dotted, [.chat, .build])
    }

    func testAllTabDotsUseTheCadenceTreatmentAndUnifiedRows() throws {
        let notifications = FixtureNotificationsDataSource.navDot.items
        let items = KTabStripModel.items(active: .cadence, notificationItems: notifications)
        let dotted = Set(items.filter(\.showsDot).map(\.tab))

        XCTAssertEqual(dotted, Set(KAppTab.allCases), "the seeded mixed state gives every tab one model-backed status")
        XCTAssertEqual(KNavStatusDotLogic.size, KStyle.navStatusDotSize)
        XCTAssertEqual(KStyle.navStatusDotSize, KStyle.notifStatusDotSize)
        XCTAssertEqual(KStyle.navStatusDotOffsetX, .zero)
        XCTAssertEqual(KStyle.navStatusDotOffsetY, .zero)
        XCTAssertEqual(KStyle.navStatusDotOpacity, KStyle.notifStatusDotOpacity, accuracy: 0.0001)
        XCTAssertEqual(KStyle.navStatusDotMinimumOpacity, KStyle.notifStatusDotMinimumOpacity, accuracy: 0.0001)
        XCTAssertEqual(KStyle.navStatusDotPeriod, KStyle.notifStatusDotPeriod, accuracy: 0.0001)

        let bio = try XCTUnwrap(items.first { $0.tab == .bio })
        XCTAssertEqual(
            bio.dotOpacity,
            KStyle.navStatusDotOpacity * KStyle.staleDotFactor,
            accuracy: 0.0001,
            "staleness dims the same dot instead of introducing a second indicator"
        )
    }

    func testUnifiedNotificationKindsRouteEachRequestedSource() {
        XCTAssertEqual(KNotificationKind.buildCards.homeTab, .build)
        XCTAssertEqual(KNotificationKind.mindUnjudged.homeTab, .mind)
        XCTAssertEqual(KNotificationKind.adminDue.homeTab, .admin)
        XCTAssertEqual(KNotificationKind.cadenceAttention.homeTab, .cadence)
        XCTAssertEqual(KNotificationKind.chatUnread.homeTab, .chat)
        XCTAssertEqual(KNotificationKind.staleness(.bio).homeTab, .bio)
        XCTAssertTrue(KNotificationKind.staleness(.bio).isStaleness)
    }

    func testStaleNavTabsStillReceiveAQuietStatusDot() throws {
        let items = KTabStripModel.items(active: .cadence, staleTabs: [.bio])
        let bio = try XCTUnwrap(items.first { $0.tab == .bio })

        XCTAssertFalse(bio.showsDot, "the shared tab model has no waiting source for bio")
        XCTAssertTrue(KNavStatusDotLogic.isShown(for: bio, staleTabs: [.bio]))
        XCTAssertEqual(
            KNavStatusDotLogic.opacityScale(for: bio, staleTabs: [.bio]),
            KStyle.staleDotFactor,
            accuracy: 0.0001
        )
        XCTAssertEqual(KNavStatusDotLogic.size, KStyle.navUnreadDotSize)
        XCTAssertEqual(
            KNavStatusDotLogic.opacity(
                at: Date(timeIntervalSinceReferenceDate: .zero),
                reduceMotion: true,
                scale: KStyle.staleDotFactor
            ),
            KStyle.notifStatusDotOpacity * KStyle.staleDotFactor,
            accuracy: 0.0001
        )
    }

    func testNavStatusDotPulseHasOneReducedMotionBranch() {
        let minimumDate = Date(timeIntervalSinceReferenceDate: .zero)
        let maximumDate = minimumDate.addingTimeInterval(KStyle.notifStatusDotPeriod / 2)

        XCTAssertEqual(
            KNavStatusDotLogic.opacity(at: minimumDate, reduceMotion: false),
            KStyle.notifStatusDotMinimumOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KNavStatusDotLogic.opacity(at: maximumDate, reduceMotion: false),
            KStyle.notifStatusDotOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KNavStatusDotLogic.opacity(at: minimumDate, reduceMotion: true),
            KStyle.notifStatusDotOpacity,
            accuracy: 0.0001
        )
    }

    // MARK: - Quiet selection: brighter glyph + a ring, never a fill

    func testSelectionIsBrighterGlyphPlusHairlineRing() {
        XCTAssertGreaterThan(KStyle.navSelectedIconOpacity, KStyle.navIdleIconOpacity)
        XCTAssertGreaterThan(KStyle.navSelectedRingOpacity, 0)
        XCTAssertLessThan(KStyle.navSelectedRingOpacity, 0.5, "the ring is a hairline, not a fill")
    }

    // MARK: - Geometry: rail reads larger than the phone bar

    func testRailGeometryIsLargerThanBottomBar() {
        XCTAssertGreaterThan(KStyle.navRegularItemSize, KStyle.navCompactItemSize)
        XCTAssertGreaterThan(KStyle.navRegularIconSize, KStyle.navCompactIconSize)
    }

    // MARK: - Clearance: scrolling content never hides under the floating nav

    func testBottomBarClearanceClearsTheCapsule() {
        let barExtent = KStyle.navCompactItemSize
            + KStyle.navCompactVerticalPadding * 2
            + KStyle.navBottomInset
        XCTAssertGreaterThanOrEqual(KStyle.navCompactContentClearance, barExtent)
    }

    func testSideRailClearanceClearsTheCapsule() {
        let railExtent = KStyle.navRegularItemSize
            + KStyle.navRegularHorizontalPadding * 2
            + KStyle.navTrailingInset
        XCTAssertGreaterThanOrEqual(KStyle.navRegularContentClearance, railExtent)
    }

    // MARK: - Notifications: read projection, reduction, and local seen overlay

    func testNotificationFixtureDecodesAttentionAndEmptyCases() async throws {
        let attention = try await FixtureNotificationsDataSource.attention.fetchNotifications()
        XCTAssertEqual(attention.count, 3)
        XCTAssertEqual(attention.first?.kind, .cardRaised)
        XCTAssertEqual(attention.filter { !$0.seen }.count, 2)

        let empty = try await FixtureNotificationsDataSource.empty.fetchNotifications()
        XCTAssertTrue(empty.isEmpty)
    }

    func testNotificationWireDecodeDefaultsMissingItemsToEmptyAndKeepsUnknownKinds() throws {
        let data = Data(#"{"items":[{"id":"n1","kind":"future-kind","title":"a future signal","detail":"","at":"2026-08-09T00:00:00Z","seen":false}]}"#.utf8)
        let envelope = try NotificationsWireDecoder.decode(data)

        XCTAssertEqual(envelope.items.count, 1)
        XCTAssertEqual(envelope.items[0].kind, .unknown("future-kind"))
        XCTAssertEqual(try NotificationsWireDecoder.decode(Data(#"{}"#.utf8)).items, [])
    }

    func testNotificationSeenReductionAndHomeRouting() {
        let now = Date(timeIntervalSince1970: 10_000)
        let items = [
            KNotification(id: "unseen", kind: .cardRaised, title: "choose", at: now, seen: false),
            KNotification(id: "seen", kind: .andon, title: "look", at: now, seen: true),
        ]

        XCTAssertEqual(KNotificationViewLogic.unseen(items).map(\.id), ["unseen"])
        XCTAssertTrue(KNotificationViewLogic.hasUnseen(items))
        XCTAssertEqual(KNotificationViewLogic.markSeen(id: "unseen", in: items).filter { !$0.seen }, [])
        XCTAssertEqual(KNotificationKind.cardRaised.homeTab, .build)
        XCTAssertNil(KNotificationKind.andon.homeTab)
    }

    @MainActor
    func testUnifiedModelClearsOneTabDotWhenItsNotificationIsSeen() async throws {
        let model = NotificationsViewModel(dataSource: FixtureNotificationsDataSource.navDot)
        await model.refreshNow()

        XCTAssertTrue(model.status(for: .build).hasUnseen)
        XCTAssertTrue(model.status(for: .bio).isStale)
        XCTAssertNotNil(model.select(id: "fixture-build-card"))
        XCTAssertFalse(model.status(for: .build).hasUnseen, "selecting the row clears the source dot")
        XCTAssertTrue(model.hasUnseen, "other source rows remain available")
        XCTAssertTrue(model.hasStatus, "the seen staleness row keeps its quiet dimmer")
    }

    @MainActor
    func testNotificationModelKeepsOptimisticSeenAcrossReadRefresh() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let source = FixtureNotificationsDataSource(items: [
            KNotification(id: "n1", kind: .cardRaised, title: "choose", at: now),
        ])
        let model = NotificationsViewModel(dataSource: source)

        await model.refreshNow()
        XCTAssertTrue(model.hasUnseen)
        model.markSeen(id: "n1")
        XCTAssertFalse(model.hasUnseen)

        await model.refreshNow()
        XCTAssertFalse(model.hasUnseen, "a later read must retain the local optimistic seen overlay")
        XCTAssertTrue(model.items.first?.seen == true)
    }

    @MainActor
    func testNotificationEmptyUnfurlIsQuietAndTestable() async {
        let model = NotificationsViewModel(dataSource: FixtureNotificationsDataSource.empty)
        await model.refreshNow()

        XCTAssertFalse(model.hasUnseen)
        model.toggleExpanded()
        XCTAssertTrue(model.showsEmptyState)
        XCTAssertEqual(KCopy.notificationsEmpty, "nothing needs you")
    }

    func testNotificationRelativeTimeUsesTerseRelativeUnits() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(KNotificationRelativeTime.text(from: now, now: now), "now")
        XCTAssertEqual(KNotificationRelativeTime.text(from: now.addingTimeInterval(-120), now: now), "2m")
        XCTAssertEqual(KNotificationRelativeTime.text(from: now.addingTimeInterval(-3_600), now: now), "1h")
        XCTAssertEqual(KNotificationRelativeTime.text(from: now.addingTimeInterval(-86_400), now: now), "yesterday")
        XCTAssertEqual(KNotificationRelativeTime.text(from: now.addingTimeInterval(60), now: now), "soon")
    }

    func testNotificationMotionAndPulseHaveReducedMotionVariants() {
        let date = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(
            KStyle.notifPulseOpacity(at: date, reduceMotion: true),
            KStyle.notifStatusDotOpacity,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            KStyle.notifUnfurlMotionResolution(true),
            .easeOut(duration: KStyle.notifReducedMotionDuration)
        )
        XCTAssertEqual(
            KStyle.notifUnfurlMotionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.notifUnfurlDuration
            )
        )
    }
}
