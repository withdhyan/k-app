import Foundation
import SwiftUI
import UIKit

private enum CadenceSiblingAuditState: String, Equatable {
    case empty
    case error

    static func value(arguments: [String]) -> Self? {
#if DEBUG
        guard let index = arguments.firstIndex(of: "-w11-cadence-state"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return Self(rawValue: arguments[index + 1].lowercased())
#else
        return nil
#endif
    }
}

/// The cadence fixtures are orthogonal inputs. A workout owns the day seed,
/// values owns the review slot, weekly retro owns its flow card, and loading
/// owns the first-fetch state. Resolve them once per model so a later lifecycle
/// callback cannot let one fixture replace another fixture's walk.
private struct CadenceFixtureSelection: Equatable {
    let isLoading: Bool
    let workoutState: CadenceWorkoutDemo.State?
    let valuesState: CadenceValuesDemo.State?
    let valuesAnswerState: CadenceValuesDemo.AuditAnswerState?
    let showsWeeklyRetro: Bool
    let membraneDay: Bool
    let resetsMembraneVerdicts: Bool
    let auditState: CadenceSiblingAuditState?

    init(arguments: [String]) {
        isLoading = arguments.contains(KLoadingPreview.launchArgument)
        workoutState = CadenceWorkoutDemo.state(arguments: arguments)
        valuesState = CadenceValuesDemo.enabled(arguments: arguments)
            ? CadenceValuesDemo.state(arguments: arguments)
            : nil
        valuesAnswerState = CadenceValuesDemo.auditAnswerState(arguments: arguments)
        showsWeeklyRetro = CadenceWeeklyRetroDemo.isEnabled(arguments: arguments)
        membraneDay = CadenceMembraneDemo.showsDemoDay
        // W26's evidence walk owns a fresh verdict domain per launch; normal
        // launches never opt into this reset.
        resetsMembraneVerdicts = arguments.contains("-w26-membrane-hermetic")
        auditState = CadenceSiblingAuditState.value(arguments: arguments)
    }

    var hasLocalContent: Bool {
        !isLoading && (auditState == .empty || workoutState != nil || valuesState != nil || showsWeeklyRetro || membraneDay)
    }
}

@MainActor
final class CadenceModel: ObservableObject {
    @Published private(set) var day: CadenceDayEnvelope
    @Published private(set) var bodySummary: BodySummary?
    @Published private(set) var bodyCueContext: BodyCueContext?
    @Published private(set) var dismissedBodyProtocolIDs: Set<String> = []
    @Published private(set) var bodyInterventionPendingIDs: Set<String> = []
    @Published private(set) var bodyInterventionErrorText: String?
    @Published private(set) var reviewCards: [CadenceReviewCard] = []
    @Published private(set) var dismissedReviewCardIDs: Set<String> = []
    @Published private(set) var suppressedNudges: [CadenceNudge] = []
    @Published private(set) var suppressedLoadText: String?
    @Published private(set) var isSuppressedLoading = false
    @Published private(set) var pendingNudgeIDs: Set<String> = []
    @Published private(set) var nudgeErrorTexts: [String: String] = [:]
    @Published private(set) var bodyLivePacket: ViewPacket?
    @Published private(set) var dismissedBodyLivePacketIDs: Set<String> = []
    @Published private(set) var mealLogs: [MealLogRecord] = []
    @Published private(set) var membraneRescore: CadenceRescoreResponse?
    @Published private(set) var membraneLocalVerdicts: [String: Bool] = [:]
    @Published private(set) var membraneEchoTexts: [String: String] = [:]
    @Published private(set) var membraneVerdictErrorText: String?
    @Published private(set) var captionOverride: String?
    @Published private(set) var localState = CadenceLocalActState()
    @Published private(set) var actionCaptionTexts: [String: String] = [:]
    @Published private(set) var accessibilityLog: [String] = []
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var isLoading = false
    @Published private(set) var connectionState = KConnectionStateModel()
    @Published private(set) var feedbackTriggers = KFeedbackTriggers()
    @Published var baseURL: String

    private let clientFactory: (String) -> AGUIClient
    private let cacheStore: CadenceDayCacheStore
    private let actionQueueStore: CadenceActQueueStore
    private let mealLogStore: MealLogLocalStore
    private let mealPhotoQueueStore: MealPhotoQueueStore
    private let membraneVerdictStore: CadenceMembraneVerdictStore
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private let fixture: CadenceFixtureSelection
    private var captionExpiryTasks: [String: Task<Void, Never>] = [:]
    private var bodyLiveTask: Task<Void, Never>?
    private var lastBodyLiveEventID: String?
    private var mealLogObserver: NSObjectProtocol?
    private var hasLoaded = false

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        cacheStore: CadenceDayCacheStore = CadenceDayCacheStore(),
        actionQueueStore: CadenceActQueueStore = CadenceActQueueStore(),
        mealLogStore: MealLogLocalStore = MealLogLocalStore(),
        mealPhotoQueueStore: MealPhotoQueueStore = MealPhotoQueueStore(),
        membraneVerdictStore: CadenceMembraneVerdictStore = CadenceMembraneVerdictStore(),
        nowProvider: @escaping () -> Date = CadenceDemoClock.now,
        calendar: Calendar = CadenceDateParser.pinnedCalendar,
        fixtureArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.cacheStore = cacheStore
        self.actionQueueStore = actionQueueStore
        self.mealLogStore = mealLogStore
        self.mealPhotoQueueStore = mealPhotoQueueStore
        self.membraneVerdictStore = membraneVerdictStore
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.fixture = CadenceFixtureSelection(arguments: fixtureArguments)
        if fixture.resetsMembraneVerdicts {
            membraneVerdictStore.reset()
        }
        let initialNow = fixture.workoutState != nil
            ? nowProvider()
            : (fixture.valuesState != nil || fixture.auditState != nil ? CadenceValuesDemo.referenceNow : nowProvider())
        if fixture.auditState == .empty || fixture.auditState == .error {
            day = CadenceDayEnvelope(
                date: CadenceDateParser.dayString(for: initialNow, calendar: calendar),
                caption: nil
            )
        } else if let workoutState = fixture.workoutState {
            day = CadenceWorkoutDemo.day(state: workoutState, now: initialNow, calendar: calendar)
        } else if fixture.membraneDay {
            day = CadenceMembraneDemo.demoDay(now: initialNow, calendar: calendar)
        } else {
            day = CadenceDayEnvelope.defaultTemplate(date: initialNow, calendar: calendar)
        }
        if let valuesState = fixture.valuesState {
            reviewCards = [CadenceValuesDemo.card(state: valuesState)]
        }
        if fixture.auditState == nil {
            membraneLocalVerdicts = membraneVerdictStore.load()
            mealLogs = mealLogStore.load()
            restoreQueuedActs()
        } else {
            membraneLocalVerdicts = [:]
            mealLogs = []
            actionQueueStore.save([])
            mealLogStore.save([], now: CadenceValuesDemo.referenceNow)
        }
        mealLogObserver = NotificationCenter.default.addObserver(
            forName: MealLogLocalStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadMealLogs()
            }
        }
    }

    deinit {
        bodyLiveTask?.cancel()
        if let mealLogObserver {
            NotificationCenter.default.removeObserver(mealLogObserver)
        }
    }

    var presentation: CadenceDayPresentation {
        presentation(now: renderNow(fallback: nowProvider()))
    }

    /// The demo owns a stable local-noon clock. Keeping this seam in the model
    /// lets the surface use one temporal source for the seed, current block,
    /// and timeline rather than mixing it with TimelineView's wall clock.
    func renderNow(fallback: Date) -> Date {
        if fixture.workoutState != nil || fixture.membraneDay {
            return nowProvider()
        }
        if fixture.valuesState != nil || fixture.auditState != nil {
            return CadenceValuesDemo.referenceNow
        }
        return fallback
    }

    /// Demo content is still local truth while the connection indicator stays
    /// honest. The surface must not replace a seeded walk with offline chrome.
    var hasLocalFixtureContent: Bool {
        fixture.hasLocalContent
    }

    func presentation(now: Date) -> CadenceDayPresentation {
        CadenceDayPresentation(
            day: day,
            bodySummary: bodySummary,
            bodyCueContext: bodyCueContext,
            dismissedBodyProtocolIDs: dismissedBodyProtocolIDs,
            bodyInterventionPendingIDs: bodyInterventionPendingIDs,
            bodyInterventionErrorText: bodyInterventionErrorText,
            localState: localState,
            reviewCards: reviewCards,
            dismissedReviewCardIDs: dismissedReviewCardIDs,
            bodyLivePacket: bodyLivePacket,
            dismissedBodyLivePacketIDs: dismissedBodyLivePacketIDs,
            mealLogs: mealLogs,
            actionCaptionTexts: actionCaptionTexts,
            captionOverride: captionOverride,
            now: now,
            snapshotSyncedAt: lastSyncAt,
            calendar: calendar
        )
    }

    var stalenessText: String? {
        guard isStale, let lastSyncAt else { return nil }
        return KTimestampFormatter.asOf(lastSyncAt, timeZone: calendar.timeZone)
    }

    var needsAttention: Bool {
        let presentation = presentation
        return presentation.topSlot.active != nil || presentation.topSlot.queued != nil
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if fixture.isLoading {
            isLoading = true
            connectionState.transition(to: .connecting)
            return
        }
        // doctrine: silence-default + optimism-with-proof. Capture fixtures
        // own their state and never open the daemon/SSE path.
        if fixture.workoutState != nil {
            applyWorkoutDemo()
            return
        }
        if fixture.auditState != nil {
            applyAuditState()
            return
        }
        if fixture.membraneDay {
            applyMembraneDemo()
            return
        }
        if fixture.valuesState != nil {
            applyValuesDemo()
            return
        }
        startBodyLiveStream()
        Task { await refresh() }
    }

    func enterBackground() {
        bodyLiveTask?.cancel()
        bodyLiveTask = nil
        connectionState.transition(to: .reconnecting)
    }

    func enterForeground() {
        if fixture.isLoading {
            isLoading = true
            connectionState.transition(to: .connecting)
            return
        }
        if fixture.workoutState != nil {
            applyWorkoutDemo()
            return
        }
        if fixture.auditState != nil {
            applyAuditState()
            return
        }
        if fixture.membraneDay {
            applyMembraneDemo()
            return
        }
        if fixture.valuesState != nil {
            applyValuesDemo()
            return
        }
        startBodyLiveStream()
        Task { await refresh() }
    }

    func refresh() async {
        if fixture.isLoading {
            isLoading = true
            connectionState.transition(to: .connecting)
            return
        }
        if fixture.workoutState != nil {
            applyWorkoutDemo()
            return
        }
        if fixture.auditState != nil {
            applyAuditState()
            return
        }
        if fixture.membraneDay {
            applyMembraneDemo()
            return
        }
        if fixture.valuesState != nil {
            applyValuesDemo()
            return
        }
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        isStale = lastSyncAt != nil
        isLoading = true
        connectionState.transition(to: .connecting)
        do {
            let client = clientFactory(baseURL)
            let loadedDay = try await client.cadenceDay()
            applySyncedDay(loadedDay)
            bodySummary = try? await client.bodySummary()
            bodyCueContext = try? await client.bodyCueContext()
            connectionState.transition(to: .live)
            await drainQueuedActs()
            await loadReviewCards()
            await loadMembraneRescore()
            await flushQueuedChecklistActs()
            await drainMealPhotoQueue()
            isLoading = false
        } catch {
            let today = CadenceDateParser.dayString(for: nowProvider(), calendar: calendar)
            if let cached = cacheStore.loadEntry(), cached.date == today {
                day = cached.day
                lastSyncAt = cached.savedAt
                isStale = true
                captionOverride = CadenceCopy.offlineSavedPlan
            } else {
                day = CadenceDayEnvelope.defaultTemplate(date: nowProvider(), calendar: calendar)
                lastSyncAt = nil
                isStale = false
                captionOverride = CadenceCopy.defaultDayCaption
            }
            connectionState.transition(to: .offlineRetrying)
            isLoading = false
        }
    }

    func perform(_ action: CadenceBlockAction, on block: CadenceBlock) {
        guard fixture.workoutState == nil, fixture.auditState == nil, !fixture.membraneDay else { return }
        let previous = localState
        localState.apply(blockId: block.id, action: action, at: nowProvider())
        recordFeedback(KFeedbackPolicy.cadenceBlockEvent(for: action))
        Task { await submit(action, blockId: block.id, previous: previous) }
    }

    func performWakeInit() {
        Task { await submitWakeInit() }
    }

    func toggleChecklistItem(_ item: CadenceChecklistItem, in block: CadenceBlock) {
        let done = !localState.checklistDone(blockId: block.id, item: item)
        localState.applyChecklist(blockId: block.id, itemId: item.id, done: done)
        Task { await submitChecklist(blockId: block.id, itemId: item.id, done: done) }
    }

    func submitMealLog(_ meal: MealMacroMeasurements, for block: CadenceBlock) async -> CadenceMealLogSubmitResult {
        let timestamp = nowProvider()
        do {
            let response = try await clientFactory(baseURL).recordBodyMeal(meal: meal, timestamp: timestamp)
            guard response.ok else {
                return .failure(KCopy.answerFailed(reason: response.error ?? "unknown"))
            }
            let record = MealLogRecord(timestamp: timestamp, meal: meal, blockId: block.id)
            mealLogStore.append(record, now: timestamp, calendar: calendar)
            reloadMealLogs()
            return .success(meal.summaryText(prefix: "logged") ?? "logged")
        } catch {
            return .failure(KCopy.answerFailed(reason: error.localizedDescription))
        }
    }

    func submitMealPhoto(image: UIImage, caption: String?, for block: CadenceBlock) async -> CadenceMealLogSubmitResult {
        do {
            let payload = try MealPhotoEncoder.encode(image)
            return await submitMealPhotoPayload(payload, caption: caption, for: block)
        } catch {
            return .failure(BioCopy.mealPhotoFailed(reason: error.localizedDescription))
        }
    }

    func submitMealPhotoPayload(
        _ payload: MealPhotoEncodedImage,
        caption: String?,
        for block: CadenceBlock
    ) async -> CadenceMealLogSubmitResult {
        let timestamp = nowProvider()
        let item = QueuedMealPhoto(
            imageBase64: payload.imageBase64,
            caption: caption,
            enqueuedAt: timestamp,
            blockId: block.id
        )
        mealPhotoQueueStore.append(item)
        return await submitQueuedMealPhoto(item, block: block)
    }

    func dismissBodyLivePacket(_ packet: ViewPacket) {
        dismissedBodyLivePacketIDs.insert(packet.id)
        if bodyLivePacket?.id == packet.id {
            bodyLivePacket = nil
        }
    }

    func submitBodyInterventionFeedback(
        _ item: BodyCueProtocol,
        action: BodyInterventionFeedbackAction
    ) async {
        guard !bodyInterventionPendingIDs.contains(item.id) else { return }
        bodyInterventionPendingIDs.insert(item.id)
        setBodyInterventionErrorText(nil)

        do {
            let response = try await clientFactory(baseURL).recordBodyInterventionFeedback(
                interventionId: item.id,
                action: action,
                packetId: item.packetId,
                timestamp: nowProvider()
            )
            guard response.ok != false else {
                setBodyInterventionErrorText(KCopy.answerFailed(reason: response.error ?? "unknown"))
                bodyInterventionPendingIDs.remove(item.id)
                return
            }
            dismissedBodyProtocolIDs.insert(item.id)
            bodyInterventionPendingIDs.remove(item.id)
        } catch {
            setBodyInterventionErrorText(KCopy.answerFailed(reason: error.localizedDescription))
            bodyInterventionPendingIDs.remove(item.id)
        }
    }

    func submit(_ action: CadenceBlockAction, blockId: String, previous: CadenceLocalActState? = nil) async {
        let submittedAt = nowProvider()
        let previousState = previous ?? localState
        if localState.pendingActions[blockId] == nil {
            localState.apply(blockId: blockId, action: action, at: submittedAt)
        }

        do {
            let response = try await clientFactory(baseURL).recordCadenceAct(blockId: blockId, action: action)
            if response.isFirstWriteConflict {
                await reconcileLosingAct(response: response, blockId: blockId)
                return
            }

            if response.ok == false {
                localState.fail(blockId: blockId, previous: previousState, reason: response.error ?? "unknown")
                actionCaptionTexts[blockId] = nil
                return
            }

            if let responseDay = response.day {
                applySyncedDay(responseDay)
            } else {
                await refreshDayAfterAct()
            }
            localState.confirm(blockId: blockId)
        } catch {
            queue(action: action, blockId: blockId, enqueuedAt: submittedAt)
        }
    }

    func submitWakeInit() async {
        let eventAt = nowProvider()
        do {
            let response = try await clientFactory(baseURL).recordCadenceWakeInit()
            guard response.ok != false else {
                connectionState.transition(to: .live)
                return
            }
            if let responseDay = response.day {
                applySyncedDay(responseDay)
            } else {
                await refreshDayAfterAct()
            }
            connectionState.transition(to: .live)
        } catch {
            queueWakeInit(enqueuedAt: eventAt)
            connectionState.transition(to: .offlineRetrying)
        }
    }

    func submitChecklist(blockId: String, itemId: String, done: Bool) async {
        let act = CadenceQueuedChecklistAct(blockId: blockId, itemId: itemId, done: done)
        do {
            let response = try await clientFactory(baseURL).recordCadenceChecklistAct(
                blockId: blockId,
                itemId: itemId,
                done: done
            )
            if response.ok == false {
                localState.queueChecklistAct(act)
                return
            }

            if let responseDay = response.day {
                applySyncedDay(responseDay)
            }
        } catch {
            localState.queueChecklistAct(act)
        }
    }

    func dismissReviewCard(_ card: CadenceReviewCard) {
        dismissedReviewCardIDs.insert(card.id)
        Task {
            _ = try? await clientFactory(baseURL).answerCadenceReviewCard(cardId: card.id)
        }
    }

    /// A failed rescore load is earned silence (invariant 7): no compare, no
    /// error card — the day simply renders without a challenger.
    func loadMembraneRescore() async {
        if CadenceMembraneDemo.showsDemoDay {
            membraneRescore = nil
            return
        }
        membraneRescore = try? await clientFactory(baseURL).cadenceRescore()
    }

    func membraneCompare(for presentation: CadenceDayPresentation) -> CadenceMembraneCompareModel? {
        let rescore = membraneRescore
            ?? (CadenceMembraneDemo.enabled ? CadenceMembraneDemo.rescore(for: presentation) : nil)
        return CadenceMembraneCompareLogic.compareModel(
            rescore: rescore,
            presentation: presentation,
            localVerdicts: membraneLocalVerdicts,
            calendar: calendar
        )
    }

    /// take/keep on the challenger jut. Optimistic local collapse; the daemon
    /// verdict rides behind. A losing write reverts the collapse and surfaces
    /// a caption (optimism-with-proof). Demo verdicts never post — synthetic
    /// better:true writes would graduate the real membrane (GRADUATION_N=5).
    func submitMembraneVerdict(_ compare: CadenceMembraneCompareModel, better: Bool) {
        let key = CadenceMembraneVerdictStore.key(
            date: compare.date,
            candidateBlockId: compare.candidateBlockId
        )
        membraneLocalVerdicts[key] = better
        membraneVerdictStore.save(membraneLocalVerdicts, date: compare.date)
        membraneEchoTexts[compare.incumbentBlockId] = better
            ? CadenceMembraneCopy.tookEcho(compare.challengerTitle)
            : CadenceMembraneCopy.keptEcho(compare.incumbentTitle)
        membraneVerdictErrorText = nil

        guard !CadenceMembraneDemo.enabled || membraneRescore != nil else { return }

        Task {
            do {
                let response = try await clientFactory(baseURL).recordCadenceRescoreCompare(
                    date: compare.date,
                    blockId: compare.candidateBlockId,
                    better: better
                )
                guard response.ok != false else {
                    revertMembraneVerdict(key: key, compare: compare)
                    return
                }
            } catch {
                revertMembraneVerdict(key: key, compare: compare)
            }
        }
    }

    private func revertMembraneVerdict(key: String, compare: CadenceMembraneCompareModel) {
        membraneLocalVerdicts[key] = nil
        membraneVerdictStore.save(membraneLocalVerdicts, date: compare.date)
        membraneEchoTexts[compare.incumbentBlockId] = nil
        membraneVerdictErrorText = CadenceMembraneCopy.saveFailed
    }

    func answerValueProbe(
        card: CadenceReviewCard,
        probe: CadenceValueProbe,
        option: CadenceValueProbeOption
    ) async -> CadenceValueProbeSubmitResult {
        // The demo has no daemon by design. Keep the same answer path in the
        // payload, but let the seeded card exercise its real optimistic UI.
        if fixture.valuesState != nil {
            if fixture.valuesAnswerState == .error {
                return .failure(KCopy.answerFailed(reason: "unavailable"))
            }
            if fixture.valuesAnswerState == .pending {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            return .success
        }
        do {
            let response = try await clientFactory(baseURL).answerCadenceValueProbe(
                cardId: card.id,
                probeId: probe.id,
                selectedOptionId: option.id
            )
            guard response.ok != false else {
                return .failure(KCopy.answerFailed(reason: response.error ?? "unknown"))
            }
            return .success
        } catch {
            return .failure(KCopy.answerFailed(reason: error.localizedDescription))
        }
    }

    func loadSuppressedNudges() async {
        isSuppressedLoading = true
        setSuppressedLoadText(nil)
        if fixture.isLoading { return }
        do {
            suppressedNudges = try await clientFactory(baseURL).suppressedCadenceNudgesToday().nudges
            isSuppressedLoading = false
        } catch {
            setSuppressedLoadText(KCopy.answerFailed(reason: error.localizedDescription))
            isSuppressedLoading = false
        }
    }

    func setDisposition(_ disposition: CadenceNudgeDisposition, for nudge: CadenceNudge) {
        guard !pendingNudgeIDs.contains(nudge.id) else { return }
        pendingNudgeIDs.insert(nudge.id)
        setNudgeErrorText(nil, for: nudge.id)
        Task { await submitDisposition(disposition, for: nudge) }
    }

    private func submitDisposition(_ disposition: CadenceNudgeDisposition, for nudge: CadenceNudge) async {
        do {
            let response: CadenceNudgeDispositionResponse
            if disposition == .act, nudge.isBuildCardActable, let act = nudge.act {
                response = try await clientFactory(baseURL).recordCadenceNudgeAct(act)
            } else {
                response = try await clientFactory(baseURL).recordCadenceNudgeDisposition(
                    id: nudge.id,
                    disposition: disposition
                )
            }
            guard response.ok != false else {
                pendingNudgeIDs.remove(nudge.id)
                setNudgeErrorText(KCopy.answerFailed(reason: response.error ?? "unknown"), for: nudge.id)
                return
            }
            pendingNudgeIDs.remove(nudge.id)
            setNudgeErrorText(nil, for: nudge.id)
            localState.disposedNudgeIDs.insert(nudge.id)
            suppressedNudges.removeAll { $0.id == nudge.id }
        } catch {
            pendingNudgeIDs.remove(nudge.id)
            setNudgeErrorText(KCopy.answerFailed(reason: error.localizedDescription), for: nudge.id)
        }
    }

    private func reloadMealLogs() {
        mealLogs = mealLogStore.load()
    }

    private func drainMealPhotoQueue() async {
        for item in mealPhotoQueueStore.load() {
            _ = await submitQueuedMealPhoto(item, block: nil)
        }
    }

    private func submitQueuedMealPhoto(
        _ item: QueuedMealPhoto,
        block: CadenceBlock?
    ) async -> CadenceMealLogSubmitResult {
        do {
            let response = try await clientFactory(baseURL).recordBodyMealPhoto(
                imageBase64: item.imageBase64,
                caption: item.caption
            )
            guard response.ok else {
                let message = BioCopy.mealPhotoFailed(reason: response.error ?? "unknown")
                mealPhotoQueueStore.update(item.withLastError(response.error ?? "unknown"))
                return .failure(message)
            }

            mealPhotoQueueStore.remove(id: item.id)
            if let macros = response.entry?.mealMacros, macros.hasMeasurement {
                let blockId = block?.id ?? item.blockId
                mealLogStore.append(
                    MealLogRecord(timestamp: item.enqueuedAt, meal: macros, blockId: blockId),
                    now: nowProvider(),
                    calendar: calendar
                )
                reloadMealLogs()
            }

            if let entry = response.entry, entry.analysisDone {
                return .success(entry.macroLine ?? entry.displayText)
            }
            return .success(KCopy.mealPhotoReading)
        } catch {
            mealPhotoQueueStore.update(item.withLastError(nil))
            connectionState.transition(to: .offlineRetrying)
            return .success(KCopy.queuedWillSync)
        }
    }

    private func setBodyInterventionErrorText(_ text: String?) {
        let previous = bodyInterventionErrorText
        bodyInterventionErrorText = text
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
    }

    private func setSuppressedLoadText(_ text: String?) {
        let previous = suppressedLoadText
        suppressedLoadText = text
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
    }

    private func setNudgeErrorText(_ text: String?, for nudgeID: String) {
        let previous = nudgeErrorTexts[nudgeID]
        nudgeErrorTexts[nudgeID] = text
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
    }

    private func recordFeedback(_ event: KFeedbackEvent?) {
        var triggers = feedbackTriggers
        triggers.record(event)
        feedbackTriggers = triggers
    }

    private func startBodyLiveStream() {
        guard !fixture.isLoading else { return }
        guard bodyLiveTask == nil,
              fixture.workoutState == nil,
              fixture.valuesState == nil,
              fixture.auditState == nil,
              !fixture.membraneDay
        else { return }
        bodyLiveTask = Task { [weak self] in
            await self?.bodyLiveConnectLoop()
        }
    }

    private func applyWorkoutDemo() {
        guard let workoutState = fixture.workoutState else { return }
        // doctrine: staleness-honesty. The seeded clock is explicit and the
        // offline state cannot present itself as a live sync.
        day = CadenceWorkoutDemo.day(state: workoutState, now: nowProvider(), calendar: calendar)
        bodySummary = nil
        bodyCueContext = nil
        reviewCards = []
        dismissedReviewCardIDs = []
        bodyLivePacket = nil
        captionOverride = day.caption
        lastSyncAt = nil
        isStale = false
        connectionState.transition(to: .offlineRetrying)
        applyValuesDemoIfNeeded()
    }

    private func applyAuditState() {
        guard let auditState = fixture.auditState else { return }
        day = CadenceDayEnvelope(
            date: CadenceDateParser.dayString(for: CadenceValuesDemo.referenceNow, calendar: calendar),
            caption: nil
        )
        bodySummary = nil
        bodyCueContext = nil
        reviewCards = []
        dismissedReviewCardIDs = []
        bodyLivePacket = nil
        dismissedBodyLivePacketIDs = []
        captionOverride = nil
        lastSyncAt = auditState == .empty ? CadenceValuesDemo.referenceNow : nil
        isStale = false
        isLoading = false
        connectionState.transition(to: auditState == .empty ? .live : .offlineRetrying)
    }

    private func applyValuesDemo() {
        guard fixture.workoutState == nil else { return }
        applyValuesDemoIfNeeded()
        isLoading = false
        connectionState.transition(to: .live)
    }

    private func applyValuesDemoIfNeeded() {
        guard let valuesState = fixture.valuesState else { return }
        reviewCards = [CadenceValuesDemo.card(state: valuesState)]
    }

    private func applyMembraneDemo() {
        // doctrine: silence-default + staleness-honesty. The compare walk is
        // local fixture content; it never opens the daemon or body stream.
        day = CadenceMembraneDemo.demoDay(now: nowProvider(), calendar: calendar)
        bodySummary = nil
        bodyCueContext = nil
        reviewCards = []
        dismissedReviewCardIDs = []
        bodyLivePacket = nil
        captionOverride = day.caption
        lastSyncAt = nil
        isStale = false
        isLoading = false
        connectionState.transition(to: .offlineRetrying)
    }

    private func bodyLiveConnectLoop() async {
        while !Task.isCancelled {
            do {
                let client = clientFactory(baseURL)
                try await client.subscribeAGUIEvents(
                    lastEventID: lastBodyLiveEventID,
                    onEvent: { [weak self] event in
                        self?.applyBodyLiveEvent(event)
                    },
                    onEventID: { [weak self] eventID in
                        self?.lastBodyLiveEventID = eventID
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                connectionState.transition(to: .reconnecting)
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func applyBodyLiveEvent(_ event: AGUIStreamEvent) {
        connectionState.transition(to: .live)
        switch event {
        case .snapshot(let packets):
            for packet in packets {
                upsertBodyLivePacket(packet)
            }
        case .packet(let packet):
            upsertBodyLivePacket(packet)
        case .patch(let patch):
            guard let bodyLivePacket, patch.targetId == bodyLivePacket.id else { return }
            upsertBodyLivePacket(applyPacketPatch(patch, to: bodyLivePacket))
        }
    }

    private func upsertBodyLivePacket(_ packet: ViewPacket) {
        guard let candidate = CadenceBodyLivePacketRouter.slotCandidate(
            from: packet,
            dismissedIDs: dismissedBodyLivePacketIDs
        ) else { return }
        bodyLivePacket = candidate
    }

    private func loadReviewCards() async {
        if fixture.valuesState != nil {
            applyValuesDemoIfNeeded()
            return
        }
        do {
            reviewCards = try await clientFactory(baseURL).cadenceReviewCards().cards
        } catch {
            reviewCards = []
        }
    }

    private func refreshDayAfterAct() async {
        do {
            let client = clientFactory(baseURL)
            let loadedDay = try await client.cadenceDay()
            applySyncedDay(loadedDay)
            bodySummary = try? await client.bodySummary()
            bodyCueContext = try? await client.bodyCueContext()
            connectionState.transition(to: .live)
        } catch {
            connectionState.transition(to: .reconnecting)
        }
    }

    private func applySyncedDay(_ loadedDay: CadenceDayEnvelope) {
        let syncedAt = nowProvider()
        day = loadedDay
        captionOverride = loadedDay.bandish.isEmpty ? CadenceCopy.defaultDayCaption : nil
        lastSyncAt = syncedAt
        isStale = false
        cacheStore.save(loadedDay, syncedAt: syncedAt)
    }

    private func restoreQueuedActs() {
        for queued in actionQueueStore.load() {
            guard !queued.isWakeInit else { continue }
            localState.apply(blockId: queued.blockId, action: queued.action, at: queued.enqueuedAt)
            localState.markQueued(blockId: queued.blockId, action: queued.action, at: queued.enqueuedAt)
        }
    }

    private func queue(action: CadenceBlockAction, blockId: String, enqueuedAt: Date) {
        localState.markQueued(blockId: blockId, action: action, at: enqueuedAt)
        actionCaptionTexts[blockId] = nil
        actionQueueStore.append(CadenceQueuedAct(blockId: blockId, action: action, enqueuedAt: enqueuedAt))
    }

    private func queueWakeInit(enqueuedAt: Date) {
        actionQueueStore.append(CadenceQueuedAct(
            blockId: CadenceQueuedAct.wakeInitBlockId,
            action: .wakeInit,
            enqueuedAt: enqueuedAt
        ))
    }

    private func drainQueuedActs() async {
        let queuedActions = actionQueueStore.load()
        guard !queuedActions.isEmpty else { return }

        for queued in queuedActions {
            do {
                let eventDate = CadenceDateParser.dayString(for: queued.enqueuedAt, calendar: calendar)
                let client = clientFactory(baseURL)
                let response = queued.isWakeInit
                    ? try await client.recordCadenceWakeInit(eventAt: queued.enqueuedAt, date: eventDate)
                    : try await client.recordCadenceAct(
                        blockId: queued.blockId,
                        action: queued.action,
                        eventAt: queued.enqueuedAt,
                        date: eventDate
                    )
                if response.isFirstWriteConflict {
                    if !queued.isWakeInit {
                        await reconcileLosingAct(response: response, blockId: queued.blockId, queuedAct: queued)
                    } else {
                        actionQueueStore.remove(queued)
                    }
                    continue
                }
                guard response.ok != false else {
                    actionQueueStore.remove(queued)
                    if !queued.isWakeInit {
                        localState.failQueued(blockId: queued.blockId, reason: response.error ?? "unknown")
                    }
                    continue
                }

                if let responseDay = response.day {
                    applySyncedDay(responseDay)
                } else {
                    await refreshDayAfterAct()
                }
                if !queued.isWakeInit {
                    localState.confirm(blockId: queued.blockId)
                }
                actionQueueStore.remove(queued)
            } catch {
                if !queued.isWakeInit {
                    localState.markQueued(blockId: queued.blockId, action: queued.action, at: queued.enqueuedAt)
                }
                connectionState.transition(to: .reconnecting)
                return
            }
        }
    }

    private func reconcileLosingAct(
        response: CadenceActResponse,
        blockId: String,
        queuedAct: CadenceQueuedAct? = nil
    ) async {
        if let responseDay = response.day {
            applySyncedDay(responseDay)
        } else {
            await refreshDayAfterAct()
        }
        localState.removeLocalAct(blockId: blockId)
        if let queuedAct {
            actionQueueStore.remove(queuedAct)
        }
        showTransientCaption(KCopy.answeredEarlier(surface: response.firstWriteSurface ?? "another surface"), for: blockId)
    }

    private func showTransientCaption(_ caption: String, for blockId: String) {
        actionCaptionTexts[blockId] = caption
        accessibilityLog.append(caption)
        captionExpiryTasks[blockId]?.cancel()
        captionExpiryTasks[blockId] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.actionCaptionTexts[blockId] == caption else { return }
                self.actionCaptionTexts.removeValue(forKey: blockId)
                self.captionExpiryTasks.removeValue(forKey: blockId)
            }
        }
    }

    private func flushQueuedChecklistActs() async {
        let queued = localState.queuedChecklistActs
        guard !queued.isEmpty else { return }
        for act in queued {
            do {
                let response = try await clientFactory(baseURL).recordCadenceChecklistAct(
                    blockId: act.blockId,
                    itemId: act.itemId,
                    done: act.done
                )
                if response.ok == false {
                    continue
                }
                localState.removeQueuedChecklistAct(act)
                if let responseDay = response.day {
                    applySyncedDay(responseDay)
                }
            } catch {
                continue
            }
        }
    }
}
