import SwiftUI
import UIKit

extension KStyle {
    // The pager's touch count is an interaction token, kept in this file so the
    // UI45C change stays within its allowed source touch set.
    static let gesturePageTouchCount = 3
}

/// The two axes in the founder-ratified app gesture grammar.
struct GestureRouter: Equatable, Sendable {
    enum Axis: Equatable, Sendable {
        case horizontal
        case vertical
    }

    enum Direction: Equatable, Sendable {
        case forward
        case backward

        static var next: Self { .forward }
        static var previous: Self { .backward }
    }

    struct Position: Equatable, Sendable {
        let page: Int
        let subPage: Int

        init(page: Int, subPage: Int = .zero) {
            self.page = page
            self.subPage = subPage
        }
    }

    let pageCount: Int
    let subPageCounts: [Int]
    let wraps: Bool

    init(pageCount: Int, subPageCounts: [Int], wraps: Bool = false) {
        let safePageCount = max(.zero, pageCount)
        self.pageCount = safePageCount
        self.subPageCounts = (0..<safePageCount).map { index in
            max(1, subPageCounts.indices.contains(index) ? subPageCounts[index] : 1)
        }
        self.wraps = wraps
    }

    func target(
        axis: Axis,
        direction: Direction,
        currentPosition: Position
    ) -> Position? {
        guard pageCount > .zero,
              currentPosition.page >= .zero,
              currentPosition.page < pageCount
        else { return nil }

        switch axis {
        case .horizontal:
            guard let page = moved(
                currentPosition.page,
                direction: direction,
                count: pageCount
            ) else { return nil }
            return Position(page: page)
        case .vertical:
            let subPageCount = subPageCounts[currentPosition.page]
            guard let subPage = moved(
                currentPosition.subPage,
                direction: direction,
                count: subPageCount
            ) else { return nil }
            return Position(page: currentPosition.page, subPage: subPage)
        }
    }

    func target(
        axis: Axis,
        direction: Direction,
        current: Position
    ) -> Position? {
        target(axis: axis, direction: direction, currentPosition: current)
    }

    private func moved(
        _ current: Int,
        direction: Direction,
        count: Int
    ) -> Int? {
        guard count > 1, current >= .zero, current < count else { return nil }
        let delta = direction == .forward ? 1 : -1
        let candidate = current + delta
        if candidate >= .zero, candidate < count {
            return candidate
        }
        guard wraps else { return nil }
        return candidate < .zero ? count - 1 : .zero
    }
}

enum KPagerGestureSuppression {
    static func isSuppressed(textInputIsFirstResponder: Bool) -> Bool {
        textInputIsFirstResponder
    }
}

private enum KTextInputFirstResponder {
    static func isActive(in view: UIView?) -> Bool {
        guard let responder = view?.kFirstResponder else { return false }
        return responder is UITextField || responder is UITextView
    }
}

private extension UIView {
    var kFirstResponder: UIResponder? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let responder = subview.kFirstResponder {
                return responder
            }
        }
        return nil
    }
}

private final class KThreeFingerSwipeRecognizer: UIPanGestureRecognizer {
    var onSwipe: ((GestureRouter.Axis, GestureRouter.Direction) -> Void)?
    private var didEmit = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        minimumNumberOfTouches = KStyle.gesturePageTouchCount
        maximumNumberOfTouches = KStyle.gesturePageTouchCount
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) {
        super.init(target: nil, action: nil)
        minimumNumberOfTouches = KStyle.gesturePageTouchCount
        maximumNumberOfTouches = KStyle.gesturePageTouchCount
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func reset() {
        didEmit = false
        super.reset()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        emitIfNeeded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        emitIfNeeded()
    }

    private func emitIfNeeded() {
        guard state == .ended, !didEmit, let view else { return }
        guard !KTextInputFirstResponder.isActive(in: view.window) else { return }
        let translation = translation(in: view)
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)
        guard max(horizontal, vertical) >= KStyle.gesturePageSwipeMinimumDistance else { return }

        let axis: GestureRouter.Axis
        let signedDistance: CGFloat
        if horizontal >= vertical * KStyle.gesturePageAxisDominanceRatio {
            axis = .horizontal
            signedDistance = translation.x
        } else if vertical >= horizontal * KStyle.gesturePageAxisDominanceRatio {
            axis = .vertical
            signedDistance = translation.y
        } else {
            return
        }

        didEmit = true
        // A left/up swipe advances; a right/down swipe returns.
        onSwipe?(axis, signedDistance < .zero ? .forward : .backward)
    }
}

private final class KThreeFingerGestureHostView: UIView {
    private var recognizer: KThreeFingerSwipeRecognizer?
    private weak var attachedView: UIView?

    var onSwipe: ((GestureRouter.Axis, GestureRouter.Direction) -> Void)? {
        didSet { recognizer?.onSwipe = onSwipe }
    }

    func install(_ recognizer: KThreeFingerSwipeRecognizer) {
        self.recognizer = recognizer
        recognizer.onSwipe = onSwipe
        attachIfPossible()
    }

    func uninstall() {
        if let attachedView, let recognizer {
            attachedView.removeGestureRecognizer(recognizer)
        }
        attachedView = nil
        recognizer = nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachIfPossible()
    }

    // The representable is a gesture host only. It must never become the hit-test
    // view, otherwise it would sit above buttons and ScrollViews in the shell.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    private func attachIfPossible() {
        guard let superview, let recognizer else { return }
        if attachedView !== superview {
            attachedView?.removeGestureRecognizer(recognizer)
            superview.isMultipleTouchEnabled = true
            superview.addGestureRecognizer(recognizer)
            attachedView = superview
        }
    }
}

private struct KThreeFingerSwipeCapture: UIViewRepresentable {
    let onSwipe: (GestureRouter.Axis, GestureRouter.Direction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KThreeFingerGestureHostView {
        let view = KThreeFingerGestureHostView(frame: .zero)
        let recognizer = KThreeFingerSwipeRecognizer(target: nil, action: nil)
        recognizer.delegate = context.coordinator
        view.onSwipe = onSwipe
        view.install(recognizer)
        return view
    }

    func updateUIView(_ uiView: KThreeFingerGestureHostView, context: Context) {
        uiView.onSwipe = onSwipe
    }

    static func dismantleUIView(_ uiView: KThreeFingerGestureHostView, coordinator: Coordinator) {
        uiView.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // UIKit asks this before the completed swipe has accumulated its
            // threshold. Distance and axis filtering happen when touches end.
            guard gestureRecognizer is KThreeFingerSwipeRecognizer else { return false }
            return !KPagerGestureSuppression.isSuppressed(
                textInputIsFirstResponder: KTextInputFirstResponder.isActive(
                    in: gestureRecognizer.view?.window
                )
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is KThreeFingerSwipeRecognizer
                && !(otherGestureRecognizer is UIPinchGestureRecognizer)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is KThreeFingerSwipeRecognizer
                && otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

enum KAppTab: String, CaseIterable, Identifiable, Equatable {
    case cadence
    case chat
    case build
    case mind
    case bio
    case admin

    var id: String { rawValue }
    var title: String { rawValue }
}

enum KAppRoute: Equatable {
    case tab(KAppTab)
#if DEBUG
    case showcase
#endif

    var visibleTab: KAppTab? {
        switch self {
        case .tab(let tab):
            return tab
#if DEBUG
        case .showcase:
            return nil
#endif
        }
    }
}

struct KTabStripItem: Identifiable, Equatable {
    let tab: KAppTab
    let title: String
    let isActive: Bool
    let textOpacity: Double
    let showsDot: Bool
    let dotOpacity: Double

    var id: KAppTab { tab }
}

struct KWaitingSummarySegment: Identifiable, Equatable {
    let id: String
    let label: String
    let tab: KAppTab
}

struct KRootGlanceCounts: Equatable {
    var openBuildCards: Int = 0
    var unjudgedMindOutputs: Int = 0
    var adminDueTodayItems: Int = 0
}

struct KRootGlanceProvider {
    var cachedCounts: @MainActor () -> KRootGlanceCounts
    var freshCounts: @MainActor () async -> KRootGlanceCounts

    static func live(
        baseURL: @escaping () -> String = {
            UserDefaults.standard.string(forKey: "cskBaseURL") ?? "http://127.0.0.1:3003"
        },
        buildCacheStore: BuildSnapshotCacheStore = BuildSnapshotCacheStore(),
        adminStore: AdminBandishStore = AdminBandishStore(),
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> KRootGlanceProvider {
        KRootGlanceProvider(
            cachedCounts: {
                KRootGlanceCounts(
                    openBuildCards: KRootGlanceCounter.openBuildCardCount(in: buildCacheStore.load()),
                    unjudgedMindOutputs: .zero,
                    adminDueTodayItems: adminStore.load().map {
                        AdminTabDotLogic.dueTodayCount(records: $0.records, now: now(), calendar: calendar)
                    } ?? .zero
                )
            },
            freshCounts: {
                let client = clientFactory(baseURL())
                async let openBuildCards = KRootGlanceCounter.fetchOpenBuildCardCount(
                    client: client,
                    fallbackStore: buildCacheStore
                )
                async let unjudgedMindOutputs = KRootGlanceCounter.fetchUnjudgedMindOutputCount(client: client)
                async let adminDueTodayItems = KRootGlanceCounter.fetchAdminDueTodayCount(
                    client: client,
                    fallbackStore: adminStore,
                    now: now(),
                    calendar: calendar
                )
                return await KRootGlanceCounts(
                    openBuildCards: openBuildCards,
                    unjudgedMindOutputs: unjudgedMindOutputs,
                    adminDueTodayItems: adminDueTodayItems
                )
            }
        )
    }
}

enum KRootGlanceCounter {
    static func openBuildCardCount(in packets: [ViewPacket]) -> Int {
        packets.compactMap(BuildCard.init(packet:)).filter(\.isOpen).count
    }

    static func unjudgedMindOutputCount(in response: MindArtifactsResponse) -> Int {
        response.outputs.filter { $0.verdict == nil }.count
    }

    static func fetchOpenBuildCardCount(
        client: AGUIClient,
        fallbackStore: BuildSnapshotCacheStore
    ) async -> Int {
        do {
            return openBuildCardCount(in: try await client.buildSnapshotOnce())
        } catch {
            return openBuildCardCount(in: fallbackStore.load())
        }
    }

    static func fetchUnjudgedMindOutputCount(client: AGUIClient) async -> Int {
        do {
            return unjudgedMindOutputCount(in: try await client.mindArtifacts())
        } catch {
            return .zero
        }
    }

    static func fetchAdminDueTodayCount(
        client: AGUIClient,
        fallbackStore: AdminBandishStore,
        now: Date,
        calendar: Calendar
    ) async -> Int {
        do {
            return AdminTabDotLogic.dueTodayCount(
                records: try await client.adminBandish().records,
                now: now,
                calendar: calendar
            )
        } catch {
            do {
                return AdminTabDotLogic.dueTodayCount(
                    records: try await client.adminItems().records,
                    now: now,
                    calendar: calendar
                )
            } catch {
                return fallbackStore.load().map {
                    AdminTabDotLogic.dueTodayCount(records: $0.records, now: now, calendar: calendar)
                } ?? .zero
            }
        }
    }
}

@MainActor
final class KRootGlanceModel: ObservableObject {
    @Published private(set) var counts: KRootGlanceCounts
    @Published private(set) var isLoading = false

    private let provider: KRootGlanceProvider
    private var refreshTask: Task<Void, Never>?

    init(provider: KRootGlanceProvider = .live()) {
        self.provider = provider
        counts = provider.cachedCounts()
    }

    func loadCachedCounts() {
        counts = provider.cachedCounts()
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        if KLoadingPreview.isEnabled { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let freshCounts = await provider.freshCounts()
            guard !Task.isCancelled else { return }
            counts = freshCounts
            isLoading = false
        }
    }

    func refreshNow() async {
        isLoading = true
        if KLoadingPreview.isEnabled { return }
        counts = await provider.freshCounts()
        isLoading = false
    }

    func setOpenBuildCards(_ count: Int) {
        counts.openBuildCards = max(.zero, count)
    }

    func setUnjudgedMindOutputs(_ count: Int) {
        counts.unjudgedMindOutputs = max(.zero, count)
    }

    func setAdminDueTodayItems(_ count: Int) {
        counts.adminDueTodayItems = max(.zero, count)
    }
}

enum KWaitingSummaryModel {
    static func segments(
        buildCards: Int,
        reviewCards: Int,
        unjudged: Int
    ) -> [KWaitingSummarySegment] {
        var rows: [KWaitingSummarySegment] = []
        if buildCards > 0 {
            rows.append(KWaitingSummarySegment(
                id: "build",
                label: "\(buildCards) build \(buildCards == 1 ? "card" : "cards")",
                tab: .build
            ))
        }
        if reviewCards > 0 {
            rows.append(KWaitingSummarySegment(
                id: "review",
                label: "\(reviewCards) review \(reviewCards == 1 ? "card" : "cards")",
                tab: .cadence
            ))
        }
        if unjudged > 0 {
            rows.append(KWaitingSummarySegment(
                id: "mind",
                label: "\(unjudged) unjudged",
                tab: .mind
            ))
        }
        return rows
    }
}

enum KTabStripModel {
    static func items(
        active activeTab: KAppTab,
        cadenceNeedsAttention: Bool = false,
        chatHasUnread: Bool = false,
        openBuildCards: Int = 0,
        unjudgedMindOutputs: Int = 0,
        adminDueTodayItems: Int = 0,
        staleTabs: Set<KAppTab> = [],
        notificationItems: [KNotification] = []
    ) -> [KTabStripItem] {
        KAppTab.allCases.map { tab in
            let status: KTabNotificationStatus
            if notificationItems.isEmpty {
                // Compatibility projection for callers that have not mounted
                // the root notification model yet. KRootView passes the
                // unified items as soon as its model is seeded.
                let waiting = showsDot(
                    for: tab,
                    cadenceNeedsAttention: cadenceNeedsAttention,
                    chatHasUnread: chatHasUnread,
                    openBuildCards: openBuildCards,
                    unjudgedMindOutputs: unjudgedMindOutputs,
                    adminDueTodayItems: adminDueTodayItems
                )
                status = KTabNotificationStatus(
                    hasUnseen: waiting,
                    isStale: staleTabs.contains(tab)
                )
            } else {
                status = KNotificationViewLogic.status(for: tab, in: notificationItems)
            }

            let showsDot = notificationItems.isEmpty
                ? status.hasUnseen
                : status.showsDot
            let opacityScale = notificationItems.isEmpty
                ? (staleTabs.contains(tab) ? KStyle.staleDotFactor : KStyle.fullOpacity)
                : status.opacityScale
            return KTabStripItem(
                tab: tab,
                title: tab.title,
                isActive: tab == activeTab,
                textOpacity: tab == activeTab ? KStyle.primaryTextOpacity : KStyle.quaternaryTextOpacity,
                showsDot: showsDot,
                dotOpacity: showsDot
                    ? KStyle.navStatusDotOpacity * opacityScale
                    : .zero
            )
        }
    }

    private static func showsDot(
        for tab: KAppTab,
        cadenceNeedsAttention: Bool,
        chatHasUnread: Bool,
        openBuildCards: Int,
        unjudgedMindOutputs: Int,
        adminDueTodayItems: Int
    ) -> Bool {
        switch tab {
        case .cadence:
            return cadenceNeedsAttention
        case .chat:
            return chatHasUnread
        case .build:
            return openBuildCards > 0
        case .mind:
            return unjudgedMindOutputs > 0
        case .bio:
            return false
        case .admin:
            return adminDueTodayItems > 0
        }
    }
}

enum KInitialTabSelection {
    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KAppTab {
        switch resolveRoute(arguments: arguments, environment: environment) {
        case .tab(let tab):
            return tab
#if DEBUG
        case .showcase:
            return .cadence
#endif
        }
    }

    static func resolveRoute(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KAppRoute {
        if let route = routeValue(from: arguments) {
            return route
        }
        if let envValue = environment["K_TAB"] ?? environment["K_INITIAL_TAB"],
           let route = route(from: envValue) {
            return route
        }
        return .tab(.cadence)
    }

    private static func routeValue(from arguments: [String]) -> KAppRoute? {
        var resolvedRoute: KAppRoute?
        for (index, argument) in arguments.enumerated() {
            if argument == "-tab", arguments.indices.contains(index + 1) {
                resolvedRoute = route(from: arguments[index + 1]) ?? resolvedRoute
            }
            if argument.hasPrefix("-tab=") {
                let value = String(argument.dropFirst("-tab=".count))
                resolvedRoute = route(from: value) ?? resolvedRoute
            }
        }
        return resolvedRoute
    }

    private static func route(from value: String) -> KAppRoute? {
        let normalized = value.lowercased()
#if DEBUG
        if normalized == "showcase" {
            return .showcase
        }
#endif
        if let tab = KAppTab(rawValue: normalized) {
            return .tab(tab)
        }
        return nil
    }
}

@main
struct KApp: App {
    var body: some Scene {
        WindowGroup {
            KRootView()
        }
    }
}

struct KRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: KAppTab
    @State private var isShowingShowcase: Bool
    @State private var pageTransitionDirection: GestureRouter.Direction = .forward
    @State private var bioPagerState: BioState = BioInitialState.resolve()
    @State private var bioStageRevealRequested = false
    @StateObject private var glanceModel: KRootGlanceModel
    @StateObject private var onboardingModel: OnboardingModel
    @State private var cadenceNeedsAttention = false
    @State private var chatHasUnread = ChatUnreadLogic.hasUnread(
        messages: ChatThreadStore().load(),
        lastSeen: ChatUnreadStore().load()
    )
    @State private var staleTabs: Set<KAppTab> = []
    @State private var pendingChatHandoff: ChatThreadHandoff?
    @StateObject private var notificationsModel: NotificationsViewModel
    @StateObject private var tailnetReachabilityModel: TailnetReachabilityModel

    @MainActor
    init(
        initialRoute: KAppRoute = KInitialTabSelection.resolveRoute(),
        glanceModel: KRootGlanceModel? = nil,
        notificationsDataSource: NotificationsDataSource? = nil,
        tailnetReachabilityModel: TailnetReachabilityModel? = nil
    ) {
        _selectedTab = State(initialValue: initialRoute.visibleTab ?? .cadence)
        _glanceModel = StateObject(wrappedValue: glanceModel ?? KRootGlanceModel())
        _onboardingModel = StateObject(wrappedValue: OnboardingModel())
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(
                dataSource: notificationsDataSource ?? FixtureNotificationsDataSource.launchDefault
            )
        )
        _tailnetReachabilityModel = StateObject(wrappedValue: tailnetReachabilityModel ?? TailnetReachabilityModel())
#if DEBUG
        _isShowingShowcase = State(initialValue: initialRoute == .showcase)
#else
        _isShowingShowcase = State(initialValue: false)
#endif
    }

    @MainActor
    init(
        initialTab: KAppTab,
        glanceModel: KRootGlanceModel? = nil,
        notificationsDataSource: NotificationsDataSource? = nil,
        tailnetReachabilityModel: TailnetReachabilityModel? = nil
    ) {
        _selectedTab = State(initialValue: initialTab)
        _glanceModel = StateObject(wrappedValue: glanceModel ?? KRootGlanceModel())
        _onboardingModel = StateObject(wrappedValue: OnboardingModel())
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(
                dataSource: notificationsDataSource ?? FixtureNotificationsDataSource.launchDefault
            )
        )
        _tailnetReachabilityModel = StateObject(wrappedValue: tailnetReachabilityModel ?? TailnetReachabilityModel())
        _isShowingShowcase = State(initialValue: false)
    }

    var body: some View {
        ZStack {
            if isShowingShowcase {
                KStyle.nearBlack
                    .ignoresSafeArea()
            } else {
                // The shell owns the complete environment layer. Bio asks this owner to
                // reveal its nutrition stage; no surface mounts a camera layer itself.
                CameraBackground(
                    cameraPromptAllowed: !CensusRemainderFixture.isOnboardingEnabled(),
                    stageRevealRequested: $bioStageRevealRequested,
                    showsGlobalEnvironment: false
                )
            }

#if DEBUG
            if isShowingShowcase {
                ShowcaseView()
            } else {
                tabShell
            }
#else
            tabShell
#endif

            if onboardingModel.isVisible {
                OnboardingView(
                    selectedTab: selectedTab,
                    permissionStates: onboardingModel.permissionStates,
                    onLater: {
                        onboardingModel.dismiss(.laterTapped)
                    },
                    onCompleted: {
                        onboardingModel.dismiss(.completed)
                    },
                    onCameraAllow: {
                        handleOnboardingCameraAllow()
                    }
                )
                .zIndex(1)
                .onAppear {
                    onboardingModel.overlayAppeared()
                }
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .kAnimated(value: isShowingShowcase)
        .kAnimated(value: onboardingModel.isVisible)
        .onAppear {
            CrashSignals.shared.register()
            if CensusRemainderFixture.isEnabled() || CensusRemainderFixture.isOnboardingEnabled() {
                glanceModel.setOpenBuildCards(0)
                glanceModel.setUnjudgedMindOutputs(0)
                glanceModel.setAdminDueTodayItems(0)
                chatHasUnread = false
                cadenceNeedsAttention = false
                staleTabs = []
            } else {
                glanceModel.loadCachedCounts()
            }
            // Mind-v18 audit mode is a sealed local pass. Do not let the root
            // glance or tailnet status quietly open a network request around it.
            if !MindDemo.enabled && !isLocalAudit {
                tailnetReachabilityModel.refresh()
                glanceModel.refresh()
            }
            if !isLocalAudit {
                notificationsModel.refresh()
            }
            syncNotificationStatuses()
            onboardingModel.refreshPermissionStates()
        }
        .onChange(of: glanceModel.counts) { _, _ in
            syncNotificationStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !MindDemo.enabled && !isLocalAudit {
                    tailnetReachabilityModel.refresh()
                    glanceModel.refresh()
                }
                if !isLocalAudit {
                    notificationsModel.refresh()
                }
                onboardingModel.refreshPermissionStates()
            }
        }
    }

    private var tabSelection: Binding<KAppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                selectTab(tab)
            }
        )
    }

    private static let pagerPages: [KAppTab] = [.chat, .build, .bio, .cadence]

    private var pagerPosition: GestureRouter.Position? {
        guard let page = Self.pagerPages.firstIndex(of: selectedTab) else { return nil }
        let subPage = selectedTab == .bio
            ? (BioState.allCases.firstIndex(of: bioPagerState) ?? .zero)
            : .zero
        return GestureRouter.Position(page: page, subPage: subPage)
    }

    private var pagerRouter: GestureRouter {
        GestureRouter(
            pageCount: Self.pagerPages.count,
            subPageCounts: [1, 1, BioState.allCases.count, 1]
        )
    }

    private var resolvedHorizontalSizeClass: UserInterfaceSizeClass? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-w11-compact-width") {
            return .compact
        }
#endif
        return horizontalSizeClass
    }

    private var isLocalAudit: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let sealedArguments = [
            "-chat-branch-motion-fixture",
            "-biodemo",
            "-minddemo",
            "-ui36-needsyou-fixture",
            "-w3retro",
            "-w3-retro",
            "-retro-demo",
            "-valuesdemo",
            "-values-demo",
            "-values-v2-demo",
            "-cadence-values-demo",
            "-workoutdemo",
        ]
        return CensusRemainderFixture.isEnabled()
            || CensusRemainderFixture.isOnboardingEnabled()
            || arguments.contains { $0.hasPrefix("-w11-") || sealedArguments.contains($0) }
#else
        false
#endif
    }

    // Hermetic look fixtures already have their own local state. The glance
    // fetch has no useful surface there, and its standalone loading dot floats
    // beside the nav capsule in the blessed compositions. Keep the dot for the
    // explicit loading audit, where it is a tested loading treatment.
    private var showsRootGlanceLoading: Bool {
        glanceModel.isLoading && (!isHermeticFixtureCapture || KLoadingPreview.isEnabled)
    }

    private var isHermeticFixtureCapture: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(ChatDemoFixture.launchArgument)
            || arguments.contains(ChatBranchMotionFixture.launchArgument)
            || arguments.contains(W30ChatRailFixture.launchArgument)
            || arguments.contains(W31ChatThreadFixture.launchArgument)
            || arguments.contains(BuildAuditFixture.launchArgument)
            || arguments.contains(BuildAuditFixture.alternateLaunchArgument)
            || arguments.contains(BuildNeedsYouFixture.launchArgument)
#else
        return false
#endif
    }

    /// Regular width (iPad, large landscape) gets the right side rail; compact
    /// (iPhone) gets the floating bottom bar — the blessed nav ruling.
    private var usesSideRail: Bool { resolvedHorizontalSizeClass == .regular }

    private var tabShell: some View {
        ZStack(alignment: usesSideRail ? .trailing : .bottom) {
            contentColumn
            rootNav
            KThreeFingerSwipeCapture(onSwipe: handleThreeFingerSwipe)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .environment(\.horizontalSizeClass, resolvedHorizontalSizeClass)
    }

    @ViewBuilder
    private var rootNav: some View {
        if usesSideRail {
            HStack(alignment: .center, spacing: KStyle.notifNavGap) {
                if showsRootGlanceLoading {
                    KLoadingPrimitive(
                        variant: .dot,
                        label: "loading glance",
                        accessibilityIdentifier: "root-glance-loading"
                    )
                }
                if (!isHermeticFixtureCapture || KLoadingPreview.isEnabled),
                   notificationsModel.hasStatus || notificationsModel.isExpanded || notificationsModel.isLoading {
                    NotificationsNavControl(
                        model: notificationsModel,
                        axis: .vertical,
                        onNavigate: selectTab
                    )
                }
                navBar(axis: .vertical)
            }
            .padding(.trailing, KStyle.navTrailingInset)
        } else {
            HStack(alignment: .bottom, spacing: KStyle.notifNavGap) {
                if showsRootGlanceLoading {
                    KLoadingPrimitive(
                        variant: .dot,
                        label: "loading glance",
                        accessibilityIdentifier: "root-glance-loading"
                    )
                }
                if (!isHermeticFixtureCapture || KLoadingPreview.isEnabled),
                   notificationsModel.hasStatus || notificationsModel.isExpanded || notificationsModel.isLoading {
                    NotificationsNavControl(
                        model: notificationsModel,
                        axis: .horizontal,
                        onNavigate: selectTab
                    )
                }
                navBar(axis: .horizontal)
            }
            .padding(.bottom, KStyle.navBottomInset)
        }
    }

    private func navBar(axis: Axis) -> some View {
        KNavBar(
            selection: tabSelection,
            axis: axis,
            cadenceNeedsAttention: cadenceNeedsAttention,
            chatHasUnread: chatHasUnread,
            openBuildCards: glanceModel.counts.openBuildCards,
            unjudgedMindOutputs: glanceModel.counts.unjudgedMindOutputs,
            adminDueTodayItems: glanceModel.counts.adminDueTodayItems,
            staleTabs: staleTabs,
            notificationItems: notificationsModel.items
        )
    }

    private func syncNotificationStatuses() {
        // The capture fixture is the complete mixed-state source. Do not let
        // a developer's cached glance counts duplicate or mask its rows.
        guard !KNavDotDemo.isEnabled else { return }
        notificationsModel.setStatus(
            .buildCards,
            active: glanceModel.counts.openBuildCards > 0,
            count: glanceModel.counts.openBuildCards
        )
        notificationsModel.setStatus(
            .mindUnjudged,
            active: glanceModel.counts.unjudgedMindOutputs > 0,
            count: glanceModel.counts.unjudgedMindOutputs
        )
        notificationsModel.setStatus(
            .adminDue,
            active: glanceModel.counts.adminDueTodayItems > 0,
            count: glanceModel.counts.adminDueTodayItems
        )
    }

    @ViewBuilder
    private var contentColumn: some View {
        let column = VStack(spacing: 0) {
            if let statusLine = tailnetReachabilityModel.statusLine {
                HStack {
                    KMonoCaption(statusLine, variant: .metadata, state: .disabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KStyle.columnMargin)
                .padding(.vertical, 8)
                .transition(.opacity)
            }

            ZStack {
                tabContent
                    .id(selectedTab.rawValue)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                KStyle.gesturePageTransitionMotion(reduceMotion),
                value: selectedTab
            )
        }

        // Reserve clearance so scrolling content never hides under the floating
        // nav — bottom clearance for the phone bar, trailing for the iPad rail.
        if usesSideRail {
            column.safeAreaInset(edge: .trailing, spacing: 0) {
                Color.clear.frame(width: KStyle.navRegularContentClearance)
            }
        } else {
            column.safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: KStyle.navCompactContentClearance)
            }
        }
    }

    private func selectTab(_ tab: KAppTab) {
        guard selectedTab != tab else {
            isShowingShowcase = false
            return
        }
        pageTransitionDirection = pageDirection(from: selectedTab, to: tab)
        selectedTab = tab
        isShowingShowcase = false
    }

    private func pageDirection(from: KAppTab, to: KAppTab) -> GestureRouter.Direction {
        guard let fromIndex = Self.pagerPages.firstIndex(of: from),
              let toIndex = Self.pagerPages.firstIndex(of: to)
        else { return .forward }
        return toIndex >= fromIndex ? .forward : .backward
    }

    private func handleThreeFingerSwipe(
        axis: GestureRouter.Axis,
        direction: GestureRouter.Direction
    ) {
        guard !onboardingModel.isVisible, let current = pagerPosition,
              let target = pagerRouter.target(
                  axis: axis,
                  direction: direction,
                  currentPosition: current
              )
        else { return }

        switch axis {
        case .horizontal:
            guard Self.pagerPages.indices.contains(target.page) else { return }
            let tab = Self.pagerPages[target.page]
            if tab == .bio, BioState.allCases.indices.contains(target.subPage) {
                bioPagerState = BioState.allCases[target.subPage]
            }
            selectTab(tab)
        case .vertical:
            guard selectedTab == .bio,
                  BioState.allCases.indices.contains(target.subPage)
            else { return }
            bioPagerState = BioState.allCases[target.subPage]
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let incoming = pageTransitionDirection == .forward
            ? KStyle.gesturePageTransitionOffset
            : -KStyle.gesturePageTransitionOffset
        return .asymmetric(
            insertion: .offset(x: incoming).combined(with: .opacity),
            removal: .offset(x: -incoming).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .cadence:
            CadenceView(
                buildCardCount: glanceModel.counts.openBuildCards,
                unjudgedMindOutputCount: glanceModel.counts.unjudgedMindOutputs,
                onAttentionChange: {
                    cadenceNeedsAttention = $0
                    notificationsModel.setStatus(.cadenceAttention, active: $0)
                },
                onStalenessChange: { setStale(.cadence, $0) },
                onSelectTab: { selectTab($0) }
            )
        case .chat:
            ChatView(
                handoff: pendingChatHandoff,
                onUnreadChange: {
                    chatHasUnread = $0
                    notificationsModel.setStatus(.chatUnread, active: $0)
                },
                onStalenessChange: { setStale(.chat, $0) },
                onHandoffConsumed: { pendingChatHandoff = nil },
                onBuildHandoff: { selectTab(.build) }
            )
        case .build:
            BuildView(
                onOpenCardCountChange: {
                    glanceModel.setOpenBuildCards($0)
                    notificationsModel.setStatus(.buildCards, active: $0 > 0, count: $0)
                },
                onStalenessChange: { setStale(.build, $0) }
            )
        case .mind:
            MindVerdictsView(
                onUnjudgedCountChange: {
                    glanceModel.setUnjudgedMindOutputs($0)
                    notificationsModel.setStatus(.mindUnjudged, active: $0 > 0, count: $0)
                },
                onStalenessChange: { setStale(.mind, $0) },
                onHandoffToChat: { handoff in
                    pendingChatHandoff = handoff
                    selectTab(.chat)
                }
            )
        case .bio:
            BioView(
                pagerSelection: $bioPagerState,
                stageRevealRequested: $bioStageRevealRequested
            )
        case .admin:
            AdminView(
                onDueTodayCountChange: {
                    glanceModel.setAdminDueTodayItems($0)
                    notificationsModel.setStatus(.adminDue, active: $0 > 0, count: $0)
                },
                onStalenessChange: { setStale(.admin, $0) }
            )
        }
    }

    private func setStale(_ tab: KAppTab, _ isStale: Bool) {
        if isStale {
            staleTabs.insert(tab)
        } else {
            staleTabs.remove(tab)
        }
        if !KNavDotDemo.isEnabled {
            notificationsModel.setStale(tab, isStale: isStale)
        }
    }

    private func handleOnboardingCameraAllow() {
        if !OnboardingChecklist.cameraPromptAllowed(selectedTab: selectedTab) {
            selectTab(.build)
        }
        scheduleOnboardingPermissionRefresh()
    }

    private func scheduleOnboardingPermissionRefresh() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onboardingModel.refreshPermissionStates()
        }
    }
}
