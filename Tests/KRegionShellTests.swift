import XCTest
@testable import K

final class KRegionShellTests: XCTestCase {
    // MARK: - Region closed set (KTD-1) — parity with design-system.ts `regionNames`

    func testRegionNamesMatchTheSharedClosedSetInCanonicalOrder() {
        XCTAssertEqual(
            KRegionName.allCases.map(\.rawValue),
            ["navRail", "header", "master", "detail", "intentBar"]
        )
    }

    // MARK: - Region templates (KTD-3) — parity with design-system.ts `regionTemplates`

    func testRegionTemplatesMatchTheSharedContractsRegionSets() {
        XCTAssertEqual(KRegionTemplates.declared[.workbench], [.navRail, .header, .master, .detail, .intentBar])
        XCTAssertEqual(KRegionTemplates.declared[.stream], [.navRail, .master])
        XCTAssertEqual(KRegionTemplates.declared[.stack], [.navRail, .header, .master])
        XCTAssertEqual(KRegionTemplates.declared[.reading], [.navRail, .master])
    }

    func testActiveRegionsReturnsOnlyDeclaredRegionsInCanonicalOrder() {
        XCTAssertEqual(KRegionTemplates.activeRegions(.workbench), [.navRail, .header, .master, .detail, .intentBar])
        XCTAssertEqual(KRegionTemplates.activeRegions(.stream), [.navRail, .master])
        XCTAssertEqual(KRegionTemplates.activeRegions(.stack), [.navRail, .header, .master])
        XCTAssertEqual(KRegionTemplates.activeRegions(.reading), [.navRail, .master])
    }

    func testEveryRegionTemplateDeclaresMasterAndNavRail() {
        for template in KRegionTemplateName.allCases {
            let regions = KRegionTemplates.declared[template] ?? []
            XCTAssertTrue(regions.contains(.master), "\(template) must declare master")
            XCTAssertTrue(regions.contains(.navRail), "\(template) must declare navRail")
        }
    }

    func testOnlyWorkbenchDeclaresDetailAndIntentBar() {
        // Mirrors design-system.ts: `workbench` is the only template with a
        // detail pane / intent bar (the Build decision-desk, U4's target).
        for template in KRegionTemplateName.allCases where template != .workbench {
            let regions = KRegionTemplates.declared[template] ?? []
            XCTAssertFalse(regions.contains(.detail), "\(template) must not declare detail")
            XCTAssertFalse(regions.contains(.intentBar), "\(template) must not declare intentBar")
        }
        XCTAssertTrue(KRegionTemplates.declared[.workbench]?.contains(.detail) ?? false)
        XCTAssertTrue(KRegionTemplates.declared[.workbench]?.contains(.intentBar) ?? false)
    }

    // MARK: - Reflow breakpoint (KTD-4) — mirrors design-system.ts `regionBreakpoint = 900`

    func testReflowBreakpointMatchesTheSharedValue() {
        XCTAssertEqual(KRegionReflow.breakpoint, 900)
    }

    func testWidthClassCrossesAtTheSharedBreakpoint() {
        XCTAssertEqual(KRegionReflow.widthClass(availableWidth: 320), .compact)
        XCTAssertEqual(KRegionReflow.widthClass(availableWidth: 899), .compact)
        XCTAssertEqual(KRegionReflow.widthClass(availableWidth: 900), .regular)
        XCTAssertEqual(KRegionReflow.widthClass(availableWidth: 1200), .regular)
    }

    func testReflowArrangementMatchesTheSharedContract() {
        XCTAssertEqual(KRegionReflow.arrangement[.regular], KRegionArrangement(navRail: .rail, detail: .inline))
        XCTAssertEqual(KRegionReflow.arrangement[.compact], KRegionArrangement(navRail: .bottomBar, detail: .pushed))
    }

    // MARK: - Non-destructive master–detail (KTD-5) — pure nav-path logic,
    // mirrors kedar/lib/region-shell.ts's split-out `focusTargetOnDetailChange`.

    func testCompactPathOpensOnlyWhenDetailIdIsNonEmpty() {
        XCTAssertEqual(KRegionShellNavigation.compactPath(for: nil), [])
        XCTAssertEqual(KRegionShellNavigation.compactPath(for: ""), [])
        XCTAssertEqual(KRegionShellNavigation.compactPath(for: "card-1"), ["card-1"])
    }

    func testCompactPathNeverHoldsMoreThanOneElement() {
        // The path only ever encodes "which single detail is open" — it is
        // never grown by re-selection, matching KTD-5's single-detail model.
        XCTAssertEqual(KRegionShellNavigation.compactPath(for: "card-1").count, 1)
        XCTAssertEqual(KRegionShellNavigation.compactPath(for: "card-2"), ["card-2"])
    }

    func testShouldDismissOnlyWhenPathPoppedWhileCallerStillThinksDetailIsOpen() {
        XCTAssertTrue(KRegionShellNavigation.shouldDismiss(currentDetailId: "card-1", poppedToPath: []))
        XCTAssertFalse(KRegionShellNavigation.shouldDismiss(currentDetailId: nil, poppedToPath: []))
        XCTAssertFalse(KRegionShellNavigation.shouldDismiss(currentDetailId: "card-1", poppedToPath: ["card-1"]))
    }
}
