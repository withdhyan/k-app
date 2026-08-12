import SwiftUI

// ════════════════════════════════════════════════════════════════════════
// REGION MODEL — SwiftUI twin of kedar/components/design-system.ts
// (`regionNames` / `regionTemplates` / `regionReflow`, KTD-1..KTD-5) and
// kedar/components/RegionShell.tsx. Same finite region contract, same
// single breakpoint, same non-destructive master–detail — rendered in the
// native iOS idiom instead of reimplemented as free layout. See
// docs/plans/2026-07-12-002-feat-design-app-shell-region-system-plan.md, U3.
//
// KRegionShell is new, additive infrastructure. It does not replace
// ChatView/BuildView/MindVerdictsView's existing layouts — a later unit
// wires one real surface onto it, mirroring how the web side kept
// Shell.tsx and added RegionShell.tsx alongside it. Zero new visual
// tokens: every value below is either structural (region names, the
// breakpoint) or reads an existing KStyle token.
// ════════════════════════════════════════════════════════════════════════

/// The five closed-set regions every surface may declare (KTD-1). Mirrors
/// `regionNames` in design-system.ts, in the same canonical order.
enum KRegionName: String, CaseIterable, Equatable {
    case navRail, header, master, detail, intentBar
}

/// Named compositions of regions (KTD-3). Mirrors `RegionTemplateName`.
enum KRegionTemplateName: String, CaseIterable, Equatable {
    case workbench, stream, stack, reading
}

enum KRegionTemplates {
    /// Regions each template declares. Mirrors `regionTemplates` in
    /// design-system.ts — the `tier`/`from` fields there are web-CSS sizing
    /// plumbing (layoutTemplates generalization) with no SwiftUI analogue;
    /// the region *set* is the part both renderers must agree on, and that's
    /// what this mirrors exactly.
    static let declared: [KRegionTemplateName: Set<KRegionName>] = [
        .workbench: [.navRail, .header, .master, .detail, .intentBar],
        .stream: [.navRail, .master],
        .stack: [.navRail, .header, .master],
        .reading: [.navRail, .master],
    ]

    /// Regions a template actually declares, in canonical (`KRegionName.allCases`)
    /// order. Mirrors `activeRegions()` in design-system.ts.
    static func activeRegions(_ template: KRegionTemplateName) -> [KRegionName] {
        let set = declared[template] ?? []
        return KRegionName.allCases.filter { set.contains($0) }
    }
}

// ── RESPONSIVE REFLOW — regular ⇄ compact, one breakpoint (KTD-4) ───────

enum KRegionWidthClass: Equatable {
    case regular, compact
}

enum KRegionNavRailArrangement: Equatable { case rail, bottomBar }
enum KRegionDetailArrangement: Equatable { case inline, pushed }

struct KRegionArrangement: Equatable {
    let navRail: KRegionNavRailArrangement
    let detail: KRegionDetailArrangement
}

enum KRegionReflow {
    /// Single breakpoint (KTD-4) — matches `regionBreakpoint = 900` in
    /// design-system.ts exactly, so web and iOS agree on one width value.
    /// Deliberately kept local rather than added to KStyle.swift: this is a
    /// structural region-contract constant, not a visual token, and adding
    /// it to KStyle would read as a token change (out of scope for U3).
    static let breakpoint: CGFloat = 900

    static let arrangement: [KRegionWidthClass: KRegionArrangement] = [
        .regular: KRegionArrangement(navRail: .rail, detail: .inline),
        .compact: KRegionArrangement(navRail: .bottomBar, detail: .pushed),
    ]

    /// Regular at/above the breakpoint, compact below — mirrors the `>=`
    /// convention already used for the codebase's other width policies
    /// (`CadenceSidebarLayoutPolicy.usesRegularSidebar`,
    /// `BuildWorkerRailLayout.placement`), not web's `max-width` CSS
    /// (`<=`). The two differ only at the exact boundary pixel.
    static func widthClass(availableWidth: CGFloat) -> KRegionWidthClass {
        availableWidth >= breakpoint ? .regular : .compact
    }
}

// ── NON-DESTRUCTIVE MASTER–DETAIL — pure nav-path logic (KTD-5) ─────────
//
// Kept separate from the view so it's testable without hosting SwiftUI —
// mirrors how kedar/lib/region-shell.ts's `focusTargetOnDetailChange` is
// split out from RegionShell.tsx for the same reason.

enum KRegionShellNavigation {
    /// The compact `NavigationStack` path for a given detail selection.
    /// Never more than one element — pushing/popping only grows or shrinks
    /// this path, so `masterContent` (the stack root) is never rebuilt.
    static func compactPath(for detailId: String?) -> [String] {
        guard let detailId, detailId.isEmpty == false else { return [] }
        return [detailId]
    }

    /// Whether `onDismissDetail` should fire because the compact nav stack
    /// was popped by the user (back gesture/button) rather than by the
    /// caller clearing `detailId` itself.
    static func shouldDismiss(currentDetailId: String?, poppedToPath path: [String]) -> Bool {
        path.isEmpty && currentDetailId != nil
    }
}

// ════════════════════════════════════════════════════════════════════════
// KRegionShell — the renderer
// ════════════════════════════════════════════════════════════════════════
//
//   regular width  ->  NavigationSplitView: navRail sidebar, master (+
//                      header/intentBar) as the content column, detail as
//                      the detail column when the template declares one —
//                      matches `regionReflow.regular` (rail + inline detail).
//   compact width  ->  NavigationStack rooted at master (+ header), with
//                      navRail/intentBar pinned to the bottom via
//                      `safeAreaInset` and detail pushed onto the stack —
//                      matches `regionReflow.compact` (bottomBar + pushed
//                      detail). Popping returns to the same master instance,
//                      never a fresh one.
//
// `navRail` is deliberately an opaque slot, exactly like the web contract
// (`navRail?: ReactNode`): KRegionShell places it, it does not know or
// dictate its internal tab structure. That's why compact uses
// `safeAreaInset` to pin it as a bottom bar rather than SwiftUI's native
// `TabView`, which would force navRail's content into per-tab bodies —
// a structural mismatch with the region contract's "regions are opaque,
// the caller owns what's inside" rule (KTD-1). Flagged per the SwiftUI
// idiom note in the U3 brief.
struct KRegionShell<
    NavRailContent: View,
    HeaderContent: View,
    MasterContent: View,
    DetailContent: View,
    IntentBarContent: View
>: View {
    let template: KRegionTemplateName
    /// Identity of the open detail. nil/empty closes it — the single
    /// source of truth for selection, owned by the caller (KTD-5), mirrors
    /// RegionShell.tsx's `detailId` prop.
    let detailId: String?
    var onDismissDetail: (() -> Void)?

    private let navRailContent: () -> NavRailContent
    private let headerContent: () -> HeaderContent
    private let masterContent: () -> MasterContent
    private let detailContent: () -> DetailContent
    private let intentBarContent: () -> IntentBarContent

    @State private var compactPath: [String] = []

    init(
        template: KRegionTemplateName,
        detailId: String? = nil,
        onDismissDetail: (() -> Void)? = nil,
        @ViewBuilder navRailContent: @escaping () -> NavRailContent = { EmptyView() },
        @ViewBuilder headerContent: @escaping () -> HeaderContent = { EmptyView() },
        @ViewBuilder masterContent: @escaping () -> MasterContent,
        @ViewBuilder detailContent: @escaping () -> DetailContent = { EmptyView() },
        @ViewBuilder intentBarContent: @escaping () -> IntentBarContent = { EmptyView() }
    ) {
        self.template = template
        self.detailId = detailId
        self.onDismissDetail = onDismissDetail
        self.navRailContent = navRailContent
        self.headerContent = headerContent
        self.masterContent = masterContent
        self.detailContent = detailContent
        self.intentBarContent = intentBarContent
    }

    private var active: Set<KRegionName> {
        Set(KRegionTemplates.activeRegions(template))
    }

    var body: some View {
        GeometryReader { proxy in
            let widthClass = KRegionReflow.widthClass(availableWidth: proxy.size.width)
            Group {
                if widthClass == .regular {
                    regularBody
                } else {
                    compactBody
                }
            }
            .onAppear {
                syncCompactPath(to: detailId)
            }
            .onChange(of: detailId) { _, newValue in
                syncCompactPath(to: newValue)
            }
            .onChange(of: compactPath) { _, newPath in
                if KRegionShellNavigation.shouldDismiss(currentDetailId: detailId, poppedToPath: newPath) {
                    onDismissDetail?()
                }
            }
        }
    }

    // MARK: - Regular (iPad / wide) — NavigationSplitView

    @ViewBuilder
    private var regularBody: some View {
        if active.contains(.detail) {
            NavigationSplitView {
                navRailIfActive
            } content: {
                masterColumn
            } detail: {
                if let detailId, detailId.isEmpty == false {
                    detailContent()
                } else {
                    EmptyView()
                }
            }
        } else {
            NavigationSplitView {
                navRailIfActive
            } detail: {
                masterColumn
            }
        }
    }

    @ViewBuilder
    private var navRailIfActive: some View {
        if active.contains(.navRail) {
            navRailContent()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var masterColumn: some View {
        VStack(spacing: 0) {
            if active.contains(.header) {
                headerContent()
            }
            masterContent()
            if active.contains(.intentBar) {
                intentBarContent()
            }
        }
    }

    // MARK: - Compact (phone) — NavigationStack + pinned navRail/intentBar

    private var compactBody: some View {
        NavigationStack(path: $compactPath) {
            VStack(spacing: 0) {
                if active.contains(.header) {
                    headerContent()
                }
                masterContent() // stack root — pushing `detail` never rebuilds this (KTD-5)
            }
            .navigationDestination(for: String.self) { _ in
                detailContent()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if active.contains(.intentBar) {
                    intentBarContent()
                }
                if active.contains(.navRail) {
                    navRailContent()
                }
            }
        }
    }

    private func syncCompactPath(to detailId: String?) {
        guard active.contains(.detail) else { return }
        let next = KRegionShellNavigation.compactPath(for: detailId)
        if compactPath != next {
            compactPath = next
        }
    }
}
