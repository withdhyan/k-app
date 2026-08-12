import SwiftUI

struct BuildView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = BuildModel()
    @State private var intentText = ""
    @State private var streamTarget: BuildStreamAnchor?
    @State private var entityDossierSelection: EntityDossierSelection?
    let onOpenCardCountChange: (Int) -> Void
    let onStalenessChange: (Bool) -> Void

    init(
        onOpenCardCountChange: @escaping (Int) -> Void = { _ in },
        onStalenessChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onOpenCardCountChange = onOpenCardCountChange
        self.onStalenessChange = onStalenessChange
    }

    private var elevatedDetailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(x: KStyle.gesturePageTransitionOffset))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                // The branch rail shows on any wide regular surface, independent of
                // whether the report summary has content (there is always at least
                // the parent-trunk branch). Mock build-k-v3: report + branch rail.
                let showsBranchRail = horizontalSizeClass == .regular
                    && proxy.size.width > KStyle.buildReportCompactMaxWidth
                let resolvedColumnWidth = columnWidth(
                    in: proxy.size.width,
                    showsSideRail: showsBranchRail
                )
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)
                    buildColumn(width: resolvedColumnWidth, showsSideRail: showsBranchRail)
                    Spacer(minLength: 0)
                }
                // Founder ruling 2026-08-03: content column is CENTERED on wide
                // surfaces, never edge-pinned — only the nav rail owns the edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, KStyle.columnMargin)

            }

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("build")
                .accessibilityIdentifier("build-view")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-view")
        .preferredColorScheme(.dark)
        .onAppear {
            model.start()
            if let loadingDepth = KLoadingPreview.value(for: "-ui34-loading-depth") {
                switch loadingDepth.lowercased() {
                case "review":
                    model.openReview(BuildReviewTarget(id: "ui34-review", title: "review"))
                case "image":
                    model.openReview(BuildReviewTarget(id: "ui34-image", title: "evidence image"))
                case "learned":
                    model.openLearned()
                case "trust":
                    model.openTrust()
                case "log-tail":
                    model.openLogTail(target: BuildLogTailTarget(laneId: "ui34-lane", title: "log tail"))
                default:
                    break
                }
            }
            if KLoadingPreview.hasFlag("-ui34-loading-dossier") {
                entityDossierSelection = EntityDossierSelection(name: "ui34 entity")
            }
            onOpenCardCountChange(model.openCards.count)
            onStalenessChange(model.isStale)
        }
        .onDisappear(perform: model.stop)
        .onChange(of: model.openCards.count) { _, count in
            onOpenCardCountChange(count)
        }
        .onChange(of: model.isStale) { _, isStale in
            onStalenessChange(isStale)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.enterBackground()
            } else if phase == .active {
                model.enterForeground()
            }
        }
        .kSensoryFeedback(model.feedbackTriggers)
    }

    private func columnWidth(
        in availableWidth: CGFloat,
        showsSideRail: Bool
    ) -> CGFloat {
        // The branch rail now lives INSIDE the surface (mock build-k-v3: report
        // main + changelog/branches rail beside it). On regular width the group
        // is the reading column plus the rail; on compact it is the column alone
        // and branches stack inline.
        let mainColumn = min(
            KStyle.columnMaxWidth,
            max(KStyle.columnMinWidth, availableWidth - KStyle.columnMargin * 2)
        )
        guard showsSideRail else { return mainColumn }
        let railBudget = KStyle.buildReportRailWidth + KStyle.buildReportRailGap
        let cappedMain = min(mainColumn, KStyle.columnMaxWidth)
        return min(availableWidth - KStyle.columnMargin * 2, cappedMain + railBudget)
    }

    private func buildColumn(width: CGFloat, showsSideRail: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            BuildReportSurfaceView(
                model: model,
                intentText: $intentText,
                showsSideRail: showsSideRail,
                onSubmitIntent: submitIntent,
                onOpenReview: { card in
                    KStyle.withGesturePageMotion { model.openReview(for: card) }
                },
                onOpenEntity: openEntityDossier(_:)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.kSelectedEntityID, entityDossierSelection?.id)

            if model.depthSurface != .desk {
                KColumnPanel {
                    BuildDepthReader(model: model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(elevatedDetailTransition)
                .zIndex(KStyle.bioRailDetailZIndex)
            }

            if let entityDossierSelection {
                EntityDossierPanel(
                    baseURL: model.baseURL,
                    selection: entityDossierSelection,
                    onDismiss: dismissEntityDossier
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(elevatedDetailTransition)
                .zIndex(KStyle.bioRailSelectedItemZIndex)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .kAnimated(value: model.packets)
        .kAnimated(value: model.workingCards)
    }

    private func submitIntent() {
        let text = intentText
        Task {
            await model.submitIntent(text)
        }
    }

    private func openEntityDossier(_ ref: EntityRef) {
        KStyle.withGesturePageMotion {
            entityDossierSelection = EntityDossierSelection(ref: ref)
        }
    }

    private func dismissEntityDossier() {
        KStyle.withGesturePageMotion {
            entityDossierSelection = nil
        }
    }
}
