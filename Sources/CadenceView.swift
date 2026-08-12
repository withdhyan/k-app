import Foundation
import SwiftUI
import UIKit

enum CadenceWeeklyRetroLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class CadenceWeeklyRetroModel: ObservableObject {
    static let olderBackendText = "retro unavailable — backend older than app"

    @Published private(set) var retro: CadenceRetro?
    @Published private(set) var loadState: CadenceWeeklyRetroLoadState = .idle
    @Published var baseURL: String

    private let clientFactory: (String) -> AGUIClient
    private let cadenceAuditStateEnabled: Bool
    private let auditState: CadenceWeeklyRetroDemo.AuditState?
    private let fixtureEnabled: Bool
    private var hasLoaded = false

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        fixtureArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        cadenceAuditStateEnabled = fixtureArguments.contains("-w11-cadence-state")
        auditState = CadenceWeeklyRetroDemo.auditState(arguments: fixtureArguments)
        fixtureEnabled = cadenceAuditStateEnabled
            || auditState != nil
            || CadenceWeeklyRetroDemo.isEnabled(arguments: fixtureArguments)
    }

    var isLoading: Bool {
        loadState == .loading
    }

    var failureText: String? {
        if case .failed(let text) = loadState { return text }
        return nil
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        loadState = .loading
        if KLoadingPreview.isEnabled { return }
#if DEBUG
        if cadenceAuditStateEnabled {
            retro = CadenceRetro()
            loadState = .loaded
            return
        }
        if let auditState {
            switch auditState {
            case .empty:
                retro = CadenceRetro()
                loadState = .loaded
            case .error:
                retro = nil
                loadState = .failed(KCopy.answerFailed(reason: "unavailable"))
            }
            return
        }
#endif
        if fixtureEnabled {
            retro = CadenceWeeklyRetroDemo.retro
            loadState = .loaded
            return
        }
        do {
            let response = try await clientFactory(baseURL).cadenceRetro()
            if response.ok == false {
                let reason = response.error?.isEmpty == false ? response.error! : "unknown"
                retro = nil
                loadState = .failed(KCopy.answerFailed(reason: reason))
                return
            }
            retro = response.retro
            loadState = .loaded
        } catch {
            retro = nil
            loadState = .failed(Self.failureText(for: error))
        }
    }

    var surfaceWeeks: [CadenceRetroWeek] {
        retro?.surfaceWeeks ?? []
    }

    var primarySurfaceWeek: CadenceRetroWeek? {
        surfaceWeeks.first
    }

    var hasSurfaceData: Bool {
        !surfaceWeeks.isEmpty
    }

    func shouldShowInCadenceFlow(
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> Bool {
        guard hasSurfaceData else { return false }
        if fixtureEnabled { return true }
        guard let day = CadenceRetroDateFormatter.date(dayDate, calendar: calendar),
              let weekEnd = CadenceRetroDateFormatter.date(primarySurfaceWeek?.end, calendar: calendar)
        else { return false }
        return day >= weekEnd
    }

    static func failureText(for error: Error) -> String {
        if let error = error as? AGUIClientError, error.isHTTP404 {
            return olderBackendText
        }
        return KCopy.answerFailed(reason: error.localizedDescription)
    }
}

enum CadenceCanvasLayout {
    static func columnWidth(in availableWidth: CGFloat) -> CGFloat {
        min(
            KStyle.columnMaxWidth,
            max(.zero, availableWidth - KStyle.columnMargin * 2)
        )
    }
}

struct CadenceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CadenceModel()
    @StateObject private var weeklyRetroModel: CadenceWeeklyRetroModel
    @State private var didOpenWeeklyRetro = false
    @State private var showsCapacityDetail = false
    @State private var showsSuppressedDetail = false
    let buildCardCount: Int
    let unjudgedMindOutputCount: Int
    let onAttentionChange: (Bool) -> Void
    let onStalenessChange: (Bool) -> Void
    let onSelectTab: (KAppTab) -> Void

    init(
        buildCardCount: Int = 0,
        unjudgedMindOutputCount: Int = 0,
        onAttentionChange: @escaping (Bool) -> Void = { _ in },
        onStalenessChange: @escaping (Bool) -> Void = { _ in },
        onSelectTab: @escaping (KAppTab) -> Void = { _ in },
        weeklyRetroModel: CadenceWeeklyRetroModel? = nil
    ) {
        self.buildCardCount = buildCardCount
        self.unjudgedMindOutputCount = unjudgedMindOutputCount
        self.onAttentionChange = onAttentionChange
        self.onStalenessChange = onStalenessChange
        self.onSelectTab = onSelectTab
        _weeklyRetroModel = StateObject(wrappedValue: weeklyRetroModel ?? CadenceWeeklyRetroModel())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                TimelineView(.periodic(from: Date(), by: KStyle.cadenceNowTickInterval)) { context in
                    cadenceSurface(
                        availableWidth: proxy.size.width,
                        now: model.renderNow(fallback: context.date)
                    )
                }
            }
            // NavigationStack's UIKit host paints opaque systemBackground —
            // the ONLY tab-level slab left after the one-haze rule (founder
            // 2026-07-11: "cadence tab still has a solid black bg"). Clear it;
            // the environment haze underneath is the background.
            .kClearNavigationContainer()
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cadence-view")
        .kNavigationTone()
        .onAppear {
            model.loadIfNeeded()
            weeklyRetroModel.loadIfNeeded()
            if let loadingRoute = KLoadingPreview.value(for: "-ui34-loading-route")?.lowercased() {
                switch loadingRoute {
                case "weekly-retro":
                    didOpenWeeklyRetro = true
                case "suppressed":
                    showsSuppressedDetail = true
                    Task { await model.loadSuppressedNudges() }
                default:
                    break
                }
            }
            onAttentionChange(model.needsAttention)
            onStalenessChange(model.isStale)
        }
        .onChange(of: model.needsAttention) { _, value in
            onAttentionChange(value)
        }
        .onChange(of: model.isStale) { _, value in
            onStalenessChange(value)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.enterBackground()
            } else if phase == .active {
                model.enterForeground()
            }
        }
        .kSensoryFeedback(model.feedbackTriggers)
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: KStyle.cadenceRefreshNanoseconds)
                } catch {
                    return
                }
                await model.refresh()
            }
        }
    }

    private func cadenceSurface(availableWidth: CGFloat, now: Date) -> some View {
        let renderedNow = model.renderNow(fallback: now)
        let presentation = model.presentation(now: renderedNow)
        let isOffline = model.connectionState.status == .offlineRetrying
        let primitiveState = cadencePrimitiveState(isOffline: isOffline, isStale: model.isStale)
        return HStack(alignment: .top, spacing: .zero) {
            Spacer(minLength: .zero)
            cadenceColumn(
                width: CadenceCanvasLayout.columnWidth(in: availableWidth),
                presentation: presentation,
                now: renderedNow,
                primitiveState: primitiveState,
                isOffline: isOffline
            )
            Spacer(minLength: .zero)
        }
        // Founder 2026-08-05: centering law — the content column is centred on
        // wide surfaces, never edge-pinned; only the nav rail owns the edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, KStyle.columnMargin)
    }

    private func cadenceColumn(
        width: CGFloat,
        presentation: CadenceDayPresentation,
        now: Date,
        primitiveState: KPrimitiveInteractionState,
        isOffline: Bool
    ) -> some View {
        return VStack(spacing: 0) {
            // Founder 2026-08-05: the waiting-count strip is deleted — the nav
            // dot already carries the same per-lane waiting semantics, and the
            // numbers ("18 build cards · 77 unjudged") break the silence-default
            // no-numbered-badges law.
            if model.isLoading && model.lastSyncAt == nil {
                KLoadingPrimitive(
                    variant: .skeleton,
                    lineCount: 5,
                    label: "loading cadence",
                    accessibilityIdentifier: "cadence-loading"
                )
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.vertical, KStyle.inputBottomPadding)
                // The retro grows in flow, so a loading stream cannot mount
                // its origin card. When the retro is open while the stream
                // loads, its slot keeps the retro's own loading grammar
                // instead of vanishing (loading never reads as empty).
                if didOpenWeeklyRetro {
                    KLoadingPrimitive(
                        variant: .skeleton,
                        lineCount: 3,
                        label: "loading retro",
                        accessibilityIdentifier: "cadence-retro-loading"
                    )
                    .padding(.horizontal, KStyle.inputSidePadding)
                    .padding(.bottom, KStyle.inputBottomPadding)
                }
            } else if isOffline && model.lastSyncAt == nil && !model.hasLocalFixtureContent {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption(KCopy.offlineRetrying, variant: .inlineError, state: .offline)
                    Spacer(minLength: KStyle.smallSpacing)
                    KActRow(
                        actions: [KActItem(id: "retry")],
                        variant: .cadence,
                        onSelect: { _ in Task { await model.refresh() } }
                    )
                }
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.vertical, KStyle.inputBottomPadding)
                .accessibilityIdentifier("cadence-unreachable")
            } else {
                if model.isLoading {
                    KLoadingPrimitive(
                        variant: .dot,
                        label: "loading cadence",
                        accessibilityIdentifier: "cadence-loading"
                    )
                    .padding(.horizontal, KStyle.inputSidePadding)
                    .padding(.vertical, KStyle.inputBottomPadding)
                }
                CadenceTimelineView(
                presentation: presentation,
                now: now,
                primitiveState: primitiveState,
                onRefresh: { await model.refresh() },
                onWakeInit: { model.performWakeInit() },
                onAction: { block, action in model.perform(action, on: block) },
                onChecklistToggle: { item, block in model.toggleChecklistItem(item, in: block) },
                onMealLog: { block, meal in await model.submitMealLog(meal, for: block) },
                onMealPhoto: { block, image, caption in
                    await model.submitMealPhoto(image: image, caption: caption, for: block)
                },
                onDismissReview: model.dismissReviewCard(_:),
                onValueProbeAnswer: model.answerValueProbe(card:probe:option:),
                pendingNudgeIDs: model.pendingNudgeIDs,
                nudgeErrorTexts: model.nudgeErrorTexts,
                onNudgeDisposition: model.setDisposition(_:for:),
                onDismissBodyLive: model.dismissBodyLivePacket(_:),
                onBodyInterventionFeedback: { item, action in
                    Task { await model.submitBodyInterventionFeedback(item, action: action) }
                },
                onShowCapacity: {
                    KStyle.withGesturePageMotion {
                        showsCapacityDetail.toggle()
                    }
                },
                showsInlineCapacity: true,
                isCapacityDetailExpanded: showsCapacityDetail,
                capacityEntries: presentation.capacityEntries,
                membraneCompare: model.membraneCompare(for: presentation),
                membraneEchoTexts: model.membraneEchoTexts,
                membraneVerdictErrorText: model.membraneVerdictErrorText,
                onMembraneVerdict: { compare, better in
                    model.submitMembraneVerdict(compare, better: better)
                },
                weeklyRetroWeek: weeklyRetroModel.shouldShowInCadenceFlow(dayDate: presentation.dateText)
                    ? weeklyRetroModel.primarySurfaceWeek
                    : nil,
                isWeeklyRetroOriginMarked: didOpenWeeklyRetro,
                showsWeeklyRetroDetail: didOpenWeeklyRetro,
                weeklyRetroModel: weeklyRetroModel,
                onOpenWeeklyRetro: {
                    KStyle.withGesturePageMotion {
                        didOpenWeeklyRetro = true
                    }
                },
                onCollapseWeeklyRetro: {
                    KStyle.withGesturePageMotion {
                        didOpenWeeklyRetro = false
                    }
                }
            )
            }

            CadenceSecondaryRoutes(
                isSuppressedExpanded: showsSuppressedDetail,
                onSuppressed: {
                    KStyle.withGesturePageMotion {
                        showsSuppressedDetail.toggle()
                    }
                    if !showsSuppressedDetail {
                        return
                    }
                    Task { await model.loadSuppressedNudges() }
                },
                nudges: model.suppressedNudges,
                loadText: model.suppressedLoadText,
                isLoading: model.isSuppressedLoading,
                pendingNudgeIDs: model.pendingNudgeIDs,
                nudgeErrorTexts: model.nudgeErrorTexts,
                onDisposition: model.setDisposition(_:for:),
                onRefresh: {
                    Task { await model.loadSuppressedNudges() }
                }
            )
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    private func cadencePrimitiveState(isOffline: Bool, isStale: Bool) -> KPrimitiveInteractionState {
        if isOffline { return .offline }
        if isStale { return .stale }
        return .resting
    }
}
