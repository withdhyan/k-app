import SwiftUI
@MainActor
final class BuildModel: ObservableObject {
    @Published private(set) var packets: [ViewPacket] = []
    @Published private(set) var connectionState = KConnectionStateModel()
    @Published private(set) var footer = ""
    @Published private(set) var pendingCardAnswerIDs: Set<String> = []
    @Published private(set) var cardErrors: [String: String] = [:]
    @Published private(set) var cardCaptionTexts: [String: String] = [:]
    @Published private(set) var accessibilityLog: [String] = []
    @Published private(set) var localCards: [String: BuildCard] = [:]
    @Published private(set) var pendingConfirmation: BuildPendingCardAnswer?
    @Published private(set) var approveAllState: BuildApproveAllState = .idle
    @Published private(set) var intentState: BuildIntentState = .idle
    @Published private(set) var intentAcknowledgementLines: [BuildStreamLine] = []
    @Published private(set) var inputQueue: BuildInputQueueState
    @Published private(set) var recentlyCollapsedCardIDs: Set<String> = []
    @Published var actionErrorTexts: [String: String] = [:]
    @Published var pendingActionPacketIDs: Set<String> = []
    @Published var baseURL: String
    @Published private(set) var depthSurface: BuildDepthSurface = .desk
    @Published private(set) var depthOrigin: BuildDepthOrigin?
    @Published private(set) var reviewState = BuildReviewState()
    @Published private(set) var learnedState = BuildLearnedState()
    @Published private(set) var trustState = BuildTrustState()
    @Published private(set) var logTailState = BuildLogTailState()
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var feedbackTriggers = KFeedbackTriggers()
    @Published private(set) var report: BuildReport?
    @Published private(set) var isLoading = false

    private let clientFactory: (String) -> AGUIClient
    private let cacheStore: BuildSnapshotCacheStore
    private let inputQueueStore: BuildInputQueueStore
    private let now: () -> Date
    private let needsYouFixtureMode: BuildNeedsYouFixtureMode?
    private let buildAuditFixtureEnabled: Bool
    private let censusFixtureEnabled: Bool
    private var streamTask: Task<Void, Never>?
    private var reportTask: Task<Void, Never>?
    private var logTailTask: Task<Void, Never>?
    private var confirmationModel = KSecondTapConfirmationModel<BuildPendingCardAnswer>()
    private var confirmationExpiryTask: Task<Void, Never>?
    private var cardCaptionExpiryTasks: [String: Task<Void, Never>] = [:]
    private var reconnectAttempt = 0
    private var lastBuildEventID: String?
    private var intentAcknowledgementCount = 0
    private var isDispatchingQueuedIntent = false
    private var fixtureFailedCardIDs: Set<String> = []

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        cacheStore: BuildSnapshotCacheStore = BuildSnapshotCacheStore(),
        inputQueueStore: BuildInputQueueStore = BuildInputQueueStore(),
        now: @escaping () -> Date = Date.init,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.cacheStore = cacheStore
        self.inputQueueStore = inputQueueStore
        self.now = now
        needsYouFixtureMode = BuildNeedsYouFixture.mode(from: arguments)
        buildAuditFixtureEnabled = BuildAuditFixture.isEnabled(arguments: arguments)
        censusFixtureEnabled = CensusRemainderFixture.isEnabled(arguments: arguments)
        inputQueue = inputQueueStore.load()
    }

    var statusPacket: ViewPacket? {
        packets.last { $0.isBuildStatusPacket }
    }

    var cardRows: [BuildCard] {
        var orderedIDs: [String] = []
        var cardsByID: [String: BuildCard] = [:]

        for packet in packets {
            guard let packetCard = BuildCard(packet: packet) else { continue }
            let card = localCards[packetCard.id] ?? packetCard
            if cardsByID[card.id] == nil {
                orderedIDs.append(card.id)
            }
            cardsByID[card.id] = card
        }

        for card in localCards.values.sorted(by: { $0.id < $1.id }) where cardsByID[card.id] == nil {
            orderedIDs.append(card.id)
            cardsByID[card.id] = card
        }

        var rows: [BuildCard] = []
        for id in orderedIDs {
            guard let card = cardsByID[id] else { continue }
            if card.isOpen || card.isAnswered {
                rows.append(card)
            }
        }

        return rows
    }

    var openCards: [BuildCard] {
        cardRows.filter(\.isOpen)
    }

    var workingCards: [BuildCard] {
        cardRows.filter { card in
            card.isOpen || recentlyCollapsedCardIDs.contains(card.id)
        }
    }

    var streamLines: [BuildStreamLine] {
        BuildStreamComposer.lines(
            packets: packets,
            localCards: localCards,
            connectionState: connectionState
        ) + intentAcknowledgementLines
    }

    var mission: BuildMissionPresentation {
        BuildMissionPresentation(statusPacket: statusPacket, connectionState: connectionState)
    }

    var stalenessText: String? {
        guard isStale, let lastSyncAt else { return nil }
        return KTimestampFormatter.asOf(lastSyncAt)
    }

    var inputDisabledReason: String? {
        connectionState.presentation().inputsDisabledReason
    }

    /// Composer status is visible at the act boundary. It carries the same
    /// KCopy connection register as the header dot and declares cached age in
    /// the same slot, so a saved report never reads as live truth.
    var composerStatusText: String? {
        Self.composerStatusText(
            for: connectionState,
            isStale: isStale,
            stalenessText: stalenessText
        )
    }

    static func composerStatusText(
        for connectionState: KConnectionStateModel,
        isStale: Bool,
        stalenessText: String?
    ) -> String? {
        var parts: [String] = []
        switch connectionState.status {
        case .idle, .connecting, .reconnecting, .offlineRetrying, .tailnetNeeded:
            // The build composer names the failed dependency, not only the
            // transport state. The status is present for every non-live state,
            // including the dark launch's initial connecting/reconnecting
            // window, so the act boundary never implies a live daemon.
            parts.append(KCopy.tailnetNeeded)
        case .live:
            break
        }
        if let stalenessText {
            parts.append(stalenessText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var fixtureReferenceNow: Date? {
        if needsYouFixtureMode != nil {
            return BuildNeedsYouFixture.referenceNow
        }
        if censusFixtureEnabled {
            return CensusRemainderFixture.referenceNow
        }
        return nil
    }

    var supplementalPackets: [ViewPacket] {
        packets.filter { packet in
            packet.viewType.hasPrefix("build.")
                && !packet.isBuildStatusPacket
                && !packet.isBuildCardPacket
        }
    }

    func start() {
        guard streamTask == nil else { return }
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        // Audit fixtures own the whole initial state. Resolve them before the
        // app-wide loading preview so a harness that carries both arguments
        // cannot fall through to an empty fetch placeholder.
        if buildAuditFixtureEnabled {
            loadBuildAuditFixture()
            return
        }
        if censusFixtureEnabled {
            loadCensusFixture()
            return
        }
        if KLoadingPreview.isEnabled {
            packets = []
            report = nil
            lastSyncAt = nil
            isStale = false
            isLoading = true
            connectionState.transition(to: .connecting)
            return
        }
        if let needsYouFixtureMode {
            loadNeedsYouFixture(needsYouFixtureMode)
            return
        }
        loadCachedSnapshot()
        isLoading = packets.isEmpty && report == nil
        refreshReport()
        connectionState.transition(to: packets.isEmpty ? .connecting : .reconnecting)
        streamTask = Task { [weak self] in
            await self?.connectLoop()
        }
    }

    func enterBackground() {
        streamTask?.cancel()
        streamTask = nil
        if connectionState.status != .idle {
            connectionState.transition(to: .reconnecting)
            footer = KCopy.reconnecting
        }
    }

    func enterForeground() {
        reconnect(refetchSnapshot: true)
    }

    func reconnect(refetchSnapshot: Bool = false) {
        if buildAuditFixtureEnabled {
            loadBuildAuditFixture()
            return
        }
        if censusFixtureEnabled {
            loadCensusFixture()
            return
        }
        if let needsYouFixtureMode {
            loadNeedsYouFixture(needsYouFixtureMode)
            return
        }
        streamTask?.cancel()
        streamTask = nil
        reconnectAttempt = 0
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        if KLoadingPreview.isEnabled {
            packets = []
            report = nil
            lastSyncAt = nil
            isStale = false
            isLoading = true
            connectionState.transition(to: .connecting)
            footer = KCopy.connecting
            return
        }
        loadCachedSnapshot()
        isStale = !packets.isEmpty || report != nil
        isLoading = packets.isEmpty && report == nil
        refreshReport()
        connectionState.transition(to: .connecting)
        footer = KCopy.connecting
        streamTask = Task { [weak self] in
            guard let self else { return }
            if refetchSnapshot {
                await self.refreshBuildSnapshotForReconnect()
            }
            await self.connectLoop()
        }
    }

    @discardableResult
    func loadCachedSnapshot() -> Bool {
        guard !KLoadingPreview.isEnabled else { return false }
        guard packets.isEmpty, let cached = cacheStore.loadEntry() else { return false }
        packets = Self.normalizedBuildPackets(cached.packets)
        lastSyncAt = cached.savedAt
        isStale = true
        footer = "showing saved snapshot"
        return true
    }

    private func loadNeedsYouFixture(_ mode: BuildNeedsYouFixtureMode) {
        streamTask?.cancel()
        streamTask = nil
        reportTask?.cancel()
        reportTask = nil
        packets = Self.normalizedBuildPackets(BuildNeedsYouFixture.packets(for: mode))
        localCards.removeAll()
        recentlyCollapsedCardIDs.removeAll()
        cardErrors.removeAll()
        cardCaptionTexts.removeAll()
        pendingCardAnswerIDs.removeAll()
        pendingActionPacketIDs.removeAll()
        actionErrorTexts.removeAll()
        pendingConfirmation = nil
        approveAllState = .idle
        inputQueue = BuildInputQueueState()
        inputQueueStore.clear()
        intentAcknowledgementLines.removeAll()
        intentState = .idle
        lastSyncAt = BuildNeedsYouFixture.referenceNow
        isStale = false
        connectionState.transition(to: .live)
        footer = packets.isEmpty ? "no active build snapshot" : KCopy.snapshotSynced
    }

    private func loadBuildAuditFixture() {
        streamTask?.cancel()
        streamTask = nil
        reportTask?.cancel()
        reportTask = nil
        packets = Self.normalizedBuildPackets(BuildAuditFixture.packets)
        report = nil
        localCards.removeAll()
        recentlyCollapsedCardIDs.removeAll()
        cardErrors.removeAll()
        cardCaptionTexts.removeAll()
        pendingCardAnswerIDs.removeAll()
        pendingActionPacketIDs.removeAll()
        actionErrorTexts.removeAll()
        pendingConfirmation = nil
        approveAllState = .idle
        inputQueue = BuildInputQueueState()
        inputQueueStore.clear()
        intentAcknowledgementLines.removeAll()
        intentState = .idle
        lastSyncAt = now()
        isStale = false
        isLoading = false
        connectionState.transition(to: .live)
        footer = KCopy.snapshotSynced
    }

    private func loadCensusFixture() {
        streamTask?.cancel()
        streamTask = nil
        reportTask?.cancel()
        reportTask = nil
        logTailTask?.cancel()
        logTailTask = nil
        packets = Self.normalizedBuildPackets(CensusRemainderFixture.buildPackets)
        localCards.removeAll()
        recentlyCollapsedCardIDs.removeAll()
        cardErrors.removeAll()
        cardCaptionTexts.removeAll()
        pendingCardAnswerIDs.removeAll()
        pendingActionPacketIDs.removeAll()
        actionErrorTexts.removeAll()
        pendingConfirmation = nil
        approveAllState = .idle
        inputQueue = BuildInputQueueState()
        inputQueueStore.clear()
        intentAcknowledgementLines.removeAll()
        intentState = .idle
        report = CensusRemainderFixture.buildReport
        lastSyncAt = CensusRemainderFixture.referenceNow
        isStale = false
        isLoading = false
        connectionState.transition(to: .live)
        footer = KCopy.snapshotSynced
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        reportTask?.cancel()
        reportTask = nil
        logTailTask?.cancel()
        logTailTask = nil
        connectionState.transition(to: .idle)
    }

    func loadReport() async {
        if censusFixtureEnabled {
            report = CensusRemainderFixture.buildReport
            lastSyncAt = CensusRemainderFixture.referenceNow
            isStale = false
            isLoading = false
            return
        }
        do {
            let report = try await clientFactory(baseURL).buildReport()
            guard !Task.isCancelled else { return }
            self.report = report
            isStale = false
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            // #22: a failed refresh keeps the last good report but must DECLARE it —
            // kept-without-declared is the dishonesty the old nil-guard prevented.
            isStale = report != nil
            isLoading = packets.isEmpty && report == nil
        }
    }

    private func refreshReport(clearCurrent: Bool = false) {
        reportTask?.cancel()
        if clearCurrent {
            report = nil
        }
        reportTask = Task { [weak self] in
            await self?.loadReport()
        }
    }

    func apply(_ event: AGUIStreamEvent) {
        switch event {
        case .snapshot(let snapshotPackets):
            packets = Self.normalizedBuildPackets(snapshotPackets)
            reconcileLocalCards(with: snapshotPackets)
            markSyncedAndCache()
            reconnectAttempt = 0
            connectionState.transition(to: .live)
            footer = snapshotPackets.isEmpty ? "no active build snapshot" : KCopy.snapshotSynced
            isLoading = false
        case .packet(let packet):
            upsert(packet)
            reconcileLocalCards(with: [packet])
            updateIntentProgress(from: packet)
            markSyncedAndCache()
            connectionState.transition(to: .live)
            footer = KCopy.liveBuildUpdate
            isLoading = false
        case .patch(let patch):
            applyPatch(patch)
            markSyncedAndCache()
            connectionState.transition(to: .live)
            footer = KCopy.buildUpdatePatched
            isLoading = false
        }

        // Stream mutations can change every aggregate in /build/report. Keep the
        // last measurement only while its replacement is in flight; failed
        // refreshes resolve to silence instead of presenting stale truth.
        if streamTask != nil {
            refreshReport(clearCurrent: false)
        }
        drainQueuedIntentsIfPossible()
    }

    @discardableResult
    func choose(option: BuildCardOption, for card: BuildCard, now: Date = Date()) -> BuildAnswerStartResult {
        guard !card.isLoopbackOnly, card.isOpen else { return .submitted }
        if let reason = inputDisabledReason {
            setCardError(Self.answerFailureText(reason: reason), for: card.id)
            reconnect(refetchSnapshot: true)
            return .submitted
        }

        if option.requiresConfirmation {
            let key = BuildPendingCardAnswer(cardId: card.id, optionId: option.id)
            if confirmationModel.tap(key, now: now) {
                pendingConfirmation = nil
            } else {
                pendingConfirmation = confirmationModel.pendingKey
                scheduleConfirmationExpiry(for: key)
                return .confirmationRequired
            }
        }
        Task { await submitAnswer(card: card, option: option) }
        return .submitted
    }

    func confirmPendingAnswer() {
        guard
            let pendingConfirmation,
            let card = cardRows.first(where: { $0.id == pendingConfirmation.cardId }),
            let option = card.options.first(where: { $0.id == pendingConfirmation.optionId })
        else {
            self.pendingConfirmation = nil
            return
        }

        self.pendingConfirmation = nil
        confirmationModel.cancel()
        Task { await submitAnswer(card: card, option: option) }
    }

    func cancelPendingAnswer() {
        pendingConfirmation = nil
        confirmationModel.cancel()
    }

    func beginApproveAll() {
        guard !approveAllState.isRunning else { return }
        let cards = openCards
        guard !cards.isEmpty else {
            approveAllState = .idle
            return
        }
        approveAllState = .disclosure(BuildApproveAllDisclosure(cards: cards))
    }

    func cancelApproveAll() {
        guard !approveAllState.isRunning else { return }
        approveAllState = .idle
    }

    func confirmApproveAll() async {
        guard case .disclosure(let disclosure) = approveAllState else { return }

        let answerable = disclosure.cards.filter(\.isBulkAnswerable)
        var answered = 0
        var skipped = disclosure.summary.skippedCount
        var failed = 0

        approveAllState = .running(BuildApproveAllProgress(
            answered: answered,
            total: answerable.count,
            skipped: skipped,
            failed: failed,
            currentCardID: answerable.first?.id
        ))

        for card in answerable {
            guard let current = cardRows.first(where: { $0.id == card.id }),
                  current.isBulkAnswerable,
                  let option = current.bulkRecommendationOption
            else {
                skipped += 1
                approveAllState = .running(BuildApproveAllProgress(
                    answered: answered,
                    total: answerable.count,
                    skipped: skipped,
                    failed: failed,
                    currentCardID: nil
                ))
                continue
            }

            approveAllState = .running(BuildApproveAllProgress(
                answered: answered,
                total: answerable.count,
                skipped: skipped,
                failed: failed,
                currentCardID: current.id
            ))
            let outcome = await submitAnswer(
                card: current,
                option: option,
                answerText: KCopy.buildApproveAllAnswerText
            )
            switch outcome {
            case .answered:
                answered += 1
            case .failed:
                failed += 1
            case .skipped:
                skipped += 1
            }
            approveAllState = .running(BuildApproveAllProgress(
                answered: answered,
                total: answerable.count,
                skipped: skipped,
                failed: failed,
                currentCardID: nil
            ))
        }

        approveAllState = .finished(BuildApproveAllResult(
            answered: answered,
            skipped: skipped,
            failed: failed
        ))
    }

    @discardableResult
    func submitAnswer(
        card: BuildCard,
        option: BuildCardOption,
        answerText: String? = nil
    ) async -> BuildCardAnswerOutcome {
        guard !pendingCardAnswerIDs.contains(card.id), !card.isLoopbackOnly else {
            return .skipped
        }
        if let reason = inputDisabledReason {
            setCardError(Self.answerFailureText(reason: reason), for: card.id)
            return .failed
        }
        if needsYouFixtureMode != nil || buildAuditFixtureEnabled || censusFixtureEnabled {
            return await submitFixtureAnswer(card: card, option: option, isBulk: answerText != nil)
        }
        pendingCardAnswerIDs.insert(card.id)
        defer { pendingCardAnswerIDs.remove(card.id) }
        setCardError(nil, for: card.id)
        let optimistic = card.answeredCopy(option: option)
        localCards[card.id] = optimistic
        recentlyCollapsedCardIDs.insert(card.id)
        footer = optimistic.historyLine

        let client = clientFactory(baseURL)
        do {
            let response = try await client.answerBuildCard(
                cardId: card.id,
                optionId: option.id,
                answerText: answerText,
                surface: "tailnet",
                actor: "founder"
            )
            guard response.ok else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                localCards[card.id] = card
                recentlyCollapsedCardIDs.remove(card.id)
                setCardError(
                    Self.answerFailureText(reason: reason?.isEmpty == false ? reason! : "unknown"),
                    for: card.id
                )
                if answerText == nil {
                    footer = cardErrors[card.id] ?? Self.answerFailureText(reason: "unknown")
                }
                return .failed
            }

            let collapsed = (response.card ?? card).answeredCopy(
                option: option,
                alreadyAnswered: response.alreadyAnswered
            )
            localCards[card.id] = collapsed
            recentlyCollapsedCardIDs.insert(card.id)
            recordFeedback(KFeedbackPolicy.buildAnswerEvent(before: card, after: collapsed))
            if let surface = Self.losingSurface(
                attemptedOption: option,
                response: response,
                reconciledCard: collapsed
            ) {
                showTransientCardCaption(KCopy.answeredEarlier(surface: surface), cardID: card.id)
                // Bulk audits walk a stable snapshot of needs-you rows. Keep a
                // bulk answer inline until the next snapshot instead of removing
                // its row while the serial run is still in flight.
                if answerText == nil {
                    scheduleCollapsedCardRemoval(card.id, delayNanoseconds: 5_000_000_000)
                }
            } else if answerText == nil {
                scheduleCollapsedCardRemoval(card.id)
            }
            footer = collapsed.historyLine

            for packet in response.packets ?? [] {
                apply(.packet(packet))
            }
            if let packet = response.packet {
                apply(.packet(packet))
            }
            return .answered
        } catch {
            localCards[card.id] = card
            recentlyCollapsedCardIDs.remove(card.id)
            setCardError(Self.answerFailureText(reason: error.localizedDescription), for: card.id)
            if answerText == nil {
                footer = cardErrors[card.id] ?? Self.answerFailureText(reason: "unknown")
            }
            return .failed
        }
    }

    private func submitFixtureAnswer(
        card: BuildCard,
        option: BuildCardOption,
        isBulk: Bool
    ) async -> BuildCardAnswerOutcome {
        pendingCardAnswerIDs.insert(card.id)
        defer { pendingCardAnswerIDs.remove(card.id) }
        setCardError(nil, for: card.id)
        let optimistic = card.answeredCopy(option: option)
        localCards[card.id] = optimistic
        recentlyCollapsedCardIDs.insert(card.id)
        footer = optimistic.historyLine

        do {
            try await Task.sleep(nanoseconds: BuildNeedsYouFixture.answerDelayNanoseconds)
        } catch {
            return .failed
        }

        if needsYouFixtureMode == .failure,
           card.id == BuildNeedsYouFixture.failureCardID,
           fixtureFailedCardIDs.insert(card.id).inserted {
            localCards[card.id] = card
            recentlyCollapsedCardIDs.remove(card.id)
            setCardError(Self.answerFailureText(reason: "fixture"), for: card.id)
            if !isBulk {
                footer = cardErrors[card.id] ?? Self.answerFailureText(reason: "fixture")
            }
            return .failed
        }

        let collapsed = optimistic
        localCards[card.id] = collapsed
        recentlyCollapsedCardIDs.insert(card.id)
        recordFeedback(KFeedbackPolicy.buildAnswerEvent(before: card, after: collapsed))
        // A bulk run owns a stable needs-you row list. Its answered receipt stays
        // inline for the completed run; individual answers retain the transient
        // collapse behavior.
        if !isBulk {
            scheduleCollapsedCardRemoval(card.id)
        }
        footer = collapsed.historyLine
        return .answered
    }

    func submitIntent(_ input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if buildAuditFixtureEnabled {
            setIntentState(.notYet)
            return
        }

        let createdAt = now()
        // A dark daemon is a queueing condition, never an input lock. Keep the
        // founder's text in the durable queue and show the receipt immediately.
        if inputDisabledReason != nil || !inputQueue.items.isEmpty {
            _ = enqueueIntent(trimmed, createdAt: createdAt)
            drainQueuedIntentsIfPossible()
            return
        }

        await sendIntent(trimmed, createdAt: createdAt, wasQueued: false)
    }

    private func sendIntent(
        _ input: String,
        createdAt: Date,
        wasQueued: Bool
    ) async {
        if !wasQueued {
            appendIntentAcknowledgement()
        }
        setIntentState(.submitting)
        let client = clientFactory(baseURL)
        do {
            let response = try await client.requestBuild(input: input, actor: "founder")
            guard response.ok != false else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = requeueIntentIfNeeded(
                    text: input,
                    createdAt: createdAt,
                    wasQueued: wasQueued
                )
                setIntentState(.failed(reason?.isEmpty == false ? reason! : "unknown"))
                return
            }

            for packet in response.packets ?? [] {
                apply(.packet(packet))
            }
            if let packet = response.packet {
                apply(.packet(packet))
            }
            setIntentState(.drafting(response.progressText))
        } catch let error as AGUIClientError {
            if error.isHTTP404 {
                connectionState.transition(to: .offlineRetrying)
                footer = KCopy.offlineRetrying
                let requeued = requeueIntentIfNeeded(
                    text: input,
                    createdAt: createdAt,
                    wasQueued: wasQueued
                )
                if requeued {
                    setIntentState(.notYet)
                }
            } else {
                let requeued = requeueIntentIfNeeded(
                    text: input,
                    createdAt: createdAt,
                    wasQueued: wasQueued
                )
                if requeued {
                    setIntentState(.failed(error.localizedDescription))
                }
            }
        } catch {
            let isOffline = Self.isOfflineError(error)
            if isOffline {
                connectionState.transition(to: .offlineRetrying)
                footer = KCopy.offlineRetrying
            }
            let requeued = requeueIntentIfNeeded(
                text: input,
                createdAt: createdAt,
                wasQueued: wasQueued
            )
            if requeued {
                setIntentState(isOffline ? .queued : .failed(error.localizedDescription))
            }
        }
    }

    @discardableResult
    private func enqueueIntent(_ text: String, createdAt: Date) -> Bool {
        guard inputQueue.enqueue(text, now: createdAt) != nil else { return false }
        appendIntentAcknowledgement(
            text: KCopy.queuedWillSync,
            createdAt: createdAt,
            idPrefix: "intent-queued"
        )
        setIntentState(.queued)
        guard persistInputQueue() else {
            setIntentState(.failed(KCopy.answerFailed(reason: "queue")))
            footer = KCopy.answerFailed(reason: "queue")
            return false
        }
        footer = KCopy.queuedWillSync
        return true
    }

    @discardableResult
    private func requeueIntentIfNeeded(
        text: String,
        createdAt: Date,
        wasQueued: Bool
    ) -> Bool {
        if wasQueued {
            let item = QueuedBuildIntent(text: text, createdAt: createdAt)
            inputQueue.append(item)
            guard persistInputQueue() else {
                setIntentState(.failed(KCopy.answerFailed(reason: "queue")))
                footer = KCopy.answerFailed(reason: "queue")
                return false
            }
            setIntentState(.queued)
            footer = KCopy.queuedWillSync
            return true
        }
        return enqueueIntent(text, createdAt: createdAt)
    }

    private func appendIntentAcknowledgement(
        text: String = KCopy.buildIntentAcknowledgment,
        createdAt: Date? = nil,
        idPrefix: String = "intent-ack"
    ) {
        intentAcknowledgementCount += 1
        intentAcknowledgementLines.append(BuildStreamLine(
            id: "\(idPrefix)-\(intentAcknowledgementCount)",
            role: .runner,
            text: text,
            meta: createdAt.map { KTimestampFormatter.hourMinute($0) },
            anchor: .stream
        ))
        if intentAcknowledgementLines.count > 5 {
            intentAcknowledgementLines.removeFirst(intentAcknowledgementLines.count - 5)
        }
    }

    private func drainQueuedIntentsIfPossible() {
        guard !isDispatchingQueuedIntent,
              connectionState.status == .live,
              inputDisabledReason == nil,
              let next = inputQueue.nextForDispatch()
        else { return }

        isDispatchingQueuedIntent = true
        guard persistInputQueue() else {
            inputQueue.append(next)
            isDispatchingQueuedIntent = false
            setIntentState(.failed(KCopy.answerFailed(reason: "queue")))
            footer = KCopy.answerFailed(reason: "queue")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.sendIntent(next.text, createdAt: next.createdAt, wasQueued: true)
            self.isDispatchingQueuedIntent = false
            self.drainQueuedIntentsIfPossible()
        }
    }

    func closeDepth() {
        depthSurface = .desk
        depthOrigin = nil
        logTailTask?.cancel()
        logTailTask = nil
    }

    func openReview(for card: BuildCard) {
        openReview(BuildReviewTarget(
            id: "card-\(card.id)",
            title: card.voiceTitle,
            unitId: card.unitId,
            cardId: card.id,
            laneId: card.laneId
        ), origin: .needsYou(card.id))
    }

    func openReview(for record: BuildRecord, kind: BuildRecordSection.Kind) {
        openReview(BuildReviewTarget(
            id: "record-\(record.id)",
            title: record.title,
            unitId: kind == .unit ? (record.unitId ?? record.id) : record.unitId,
            laneId: record.laneId ?? (kind == .lane ? record.id : nil),
            diffId: record.diffId,
            docPaths: record.docPaths
        ), origin: .record(record.id))
    }

    func openReview(_ target: BuildReviewTarget) {
        openReview(target, origin: nil)
    }

    private func openReview(_ target: BuildReviewTarget, origin: BuildDepthOrigin?) {
        logTailTask?.cancel()
        logTailTask = nil
        depthSurface = .review
        depthOrigin = origin
        reviewState = BuildReviewState(target: target, isLoading: true)
        Task { await loadReview(target) }
    }

    func loadReview(_ target: BuildReviewTarget) async {
        if KLoadingPreview.isEnabled {
            return
        }
        if censusFixtureEnabled {
            guard reviewState.target?.id == target.id else { return }
            reviewState = BuildReviewState(
                target: target,
                isLoading: false,
                evidence: CensusRemainderFixture.reviewEvidence,
                diffs: CensusRemainderFixture.reviewDiffs,
                documents: CensusRemainderFixture.reviewDocuments,
                error: nil
            )
            return
        }
        let client = clientFactory(baseURL)
        var evidence: [BuildEvidenceEntry] = []
        var diffs: [BuildDiffResponse] = []
        var documents: [BuildDocumentResponse] = []
        var diffIds = target.diffId.map { [$0] } ?? []
        var docPaths = target.docPaths
        var errors: [String] = []

        do {
            let response = try await client.buildEvidence(
                unitId: target.unitId,
                cardId: target.cardId,
                laneId: target.laneId
            )
            evidence = response.entries
            diffIds.append(contentsOf: response.entries.compactMap(\.diffId))
            docPaths.append(contentsOf: response.entries.compactMap(\.docPath))
        } catch {
            errors.append("evidence: \(error.localizedDescription)")
        }

        for diffId in BuildPayload.unique(diffIds) {
            do {
                let diff = try await client.buildDiff(id: diffId)
                diffs.append(diff)
                docPaths.append(contentsOf: diff.docPaths)
            } catch {
                errors.append("diff: \(error.localizedDescription)")
            }
        }

        for path in BuildPayload.unique(docPaths).compactMap(BuildPayload.documentPath) {
            do {
                documents.append(try await client.buildDocument(path: path))
            } catch {
                errors.append("doc: \(error.localizedDescription)")
            }
        }

        guard reviewState.target?.id == target.id else { return }
        reviewState = BuildReviewState(
            target: target,
            isLoading: false,
            evidence: evidence,
            diffs: diffs,
            documents: documents,
            error: errors.isEmpty ? nil : errors.joined(separator: " · ")
        )
    }

    func openLearned() {
        logTailTask?.cancel()
        logTailTask = nil
        depthSurface = .learned
        depthOrigin = .branch("learned")
        Task { await loadLearned() }
    }

    func loadLearned() async {
        learnedState.isLoading = true
        learnedState.error = nil
        if KLoadingPreview.isEnabled {
            return
        }
        if censusFixtureEnabled {
            learnedState.feed = CensusRemainderFixture.learnedFeed
            learnedState.isLoading = false
            return
        }
        let client = clientFactory(baseURL)
        do {
            let response = try await client.buildLearned()
            guard response.ok else {
                learnedState.error = response.error ?? "unknown"
                learnedState.isLoading = false
                return
            }
            learnedState.feed = response.feed
        } catch {
            learnedState.error = error.localizedDescription
        }
        learnedState.isLoading = false
    }

    func submitLearnedDecision(_ decision: BuildLearnedDecision) async {
        guard let entry = learnedState.feed.nextPending else { return }
        await submitLearnedDecision(entry: entry, decision: decision)
    }

    func submitLearnedDecision(entry: BuildLearnedEntry, decision: BuildLearnedDecision) async {
        guard !learnedState.pendingDecisionIDs.contains(entry.id) else { return }
        learnedState.pendingDecisionIDs.insert(entry.id)
        learnedState.error = nil

        let client = clientFactory(baseURL)
        do {
            let response = try await client.decideBuildLearned(id: entry.id, decision: decision)
            guard response.ok else {
                learnedState.error = response.error ?? "unknown"
                learnedState.pendingDecisionIDs.remove(entry.id)
                return
            }
            if let feed = response.feed {
                learnedState.feed = feed
            } else {
                let responseEntry = response.entry ?? entry
                learnedState.feed = learnedState.feed.applying(entry: responseEntry, decision: decision)
            }
        } catch {
            learnedState.error = error.localizedDescription
        }

        learnedState.pendingDecisionIDs.remove(entry.id)
    }

    func openTrust() {
        logTailTask?.cancel()
        logTailTask = nil
        depthSurface = .trust
        depthOrigin = .branch("trust")
        Task { await loadTrust() }
    }

    func loadTrust() async {
        trustState.isLoading = true
        trustState.error = nil
        if KLoadingPreview.isEnabled {
            return
        }
        if censusFixtureEnabled {
            trustState.response = CensusRemainderFixture.trustResponse
            trustState.isLoading = false
            return
        }
        let client = clientFactory(baseURL)
        do {
            trustState.response = try await client.buildTrustPairs()
        } catch {
            trustState.error = error.localizedDescription
        }
        trustState.isLoading = false
    }

    func openLogTail(for record: BuildRecord) {
        guard let laneId = record.logTailLaneId else { return }
        openLogTail(target: BuildLogTailTarget(laneId: laneId, title: record.title), origin: .record(record.id))
    }

    func openLogTail(target: BuildLogTailTarget) {
        openLogTail(target: target, origin: nil)
    }

    private func openLogTail(target: BuildLogTailTarget, origin: BuildDepthOrigin?) {
        depthSurface = .logTail
        depthOrigin = origin
        logTailState = BuildLogTailState(target: target, isLoading: true)
        logTailTask?.cancel()
        logTailTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLogTail(target: target)
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func isDepthOrigin(record: BuildRecord) -> Bool {
        guard case .record(let id) = depthOrigin else { return false }
        return id == record.id
    }

    func isDepthOrigin(needsYouCard card: BuildCard) -> Bool {
        guard case .needsYou(let id) = depthOrigin else { return false }
        return id == card.id
    }

    func isDepthOrigin(branchID: String) -> Bool {
        guard case .branch(let id) = depthOrigin else { return false }
        return id == branchID
    }

    func refreshLogTail(target: BuildLogTailTarget) async {
        if KLoadingPreview.isEnabled {
            return
        }
        if censusFixtureEnabled {
            guard logTailState.target == target else { return }
            logTailState.response = CensusRemainderFixture.logTailResponse
            logTailState.error = nil
            logTailState.isLoading = false
            return
        }
        let client = clientFactory(baseURL)
        do {
            let response = try await client.buildLaneLogTail(laneId: target.laneId)
            guard logTailState.target == target else { return }
            logTailState.response = response
            logTailState.error = nil
        } catch {
            guard logTailState.target == target else { return }
            logTailState.error = error.localizedDescription
        }
        logTailState.isLoading = false
    }

    func cardErrorText(for card: BuildCard) -> String? {
        cardErrors[card.id]
    }

    func cardCaptionText(for card: BuildCard) -> String? {
        cardCaptionTexts[card.id]
    }

    func isAnswerPending(for card: BuildCard) -> Bool {
        pendingCardAnswerIDs.contains(card.id)
    }

    func isConfirming(card: BuildCard, option: BuildCardOption, now: Date = Date()) -> Bool {
        let key = BuildPendingCardAnswer(cardId: card.id, optionId: option.id)
        return pendingConfirmation == key && confirmationModel.isPending(key, now: now)
    }

    func invokeAction(from packet: ViewPacket) {
        guard
            ViewPacketRenderer.exposesActionAffordance(for: packet),
            !pendingActionPacketIDs.contains(packet.id)
        else { return }

        pendingActionPacketIDs.insert(packet.id)
        actionErrorTexts[packet.id] = nil
        footer = KCopy.answerPending

        let client = clientFactory(baseURL)
        Task {
            do {
                let outcome = try await client.invokeAction(packet: packet, onEvent: { [weak self] event in
                    self?.apply(event)
                })
                if let result = outcome.packet {
                    apply(.packet(result))
                }
                actionErrorTexts[packet.id] = nil
                footer = statusLine(outcome)
            } catch {
                let text = Self.answerFailureText(reason: error.localizedDescription)
                actionErrorTexts[packet.id] = text
                footer = text
            }

            pendingActionPacketIDs.remove(packet.id)
        }
    }

    private func connectLoop() async {
        while !Task.isCancelled {
            do {
                let client = clientFactory(baseURL)
                try await client.subscribeBuildEvents(
                    lastEventID: lastBuildEventID,
                    onEvent: { [weak self] event in
                        self?.apply(event)
                    },
                    onEventID: { [weak self] eventID in
                        self?.lastBuildEventID = eventID
                    }
                )
                guard !Task.isCancelled else { return }
                connectionState.transition(to: .reconnecting)
                footer = KCopy.reconnecting
            } catch is CancellationError {
                return
            } catch let error as AGUIClientError {
                guard !Task.isCancelled else { return }
                if case .httpStatus(404) = error {
                    connectionState.transition(to: .offlineRetrying)
                    footer = KCopy.offlineRetrying
                } else {
                    connectionState.transition(to: packets.isEmpty ? .offlineRetrying : .reconnecting)
                    footer = packets.isEmpty ? Self.answerFailureText(reason: error.localizedDescription) : KCopy.reconnecting
                }
            } catch {
                guard !Task.isCancelled else { return }
                connectionState.transition(to: packets.isEmpty ? .offlineRetrying : .reconnecting)
                footer = packets.isEmpty ? Self.answerFailureText(reason: error.localizedDescription) : KCopy.reconnecting
            }

            let delay = Self.retryDelayNanoseconds(attempt: reconnectAttempt)
            reconnectAttempt += 1
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
        }
    }

    private func refreshBuildSnapshotForReconnect() async {
        do {
            let packets = try await clientFactory(baseURL).buildSnapshotOnce()
            guard !Task.isCancelled else { return }
            apply(.snapshot(packets))
        } catch {
            guard !Task.isCancelled else { return }
            if self.packets.isEmpty {
                connectionState.transition(to: .offlineRetrying)
                footer = Self.answerFailureText(reason: error.localizedDescription)
            } else {
                connectionState.transition(to: .reconnecting)
                footer = KCopy.reconnecting
            }
        }
    }

    private func upsert(_ packet: ViewPacket) {
        guard packet.viewType.hasPrefix("build.") else { return }
        if let index = packets.firstIndex(where: { $0.id == packet.id }) {
            packets[index] = packet
        } else {
            packets.append(packet)
        }
    }

    private func applyPatch(_ patch: ViewPacketPatch) {
        let root = ViewPacket(
            id: "build-root",
            viewType: "build.root",
            children: packets,
            frontierExcluded: false
        )
        let patched = applyPacketPatch(patch, to: root)
        packets = patched.children.filter { $0.viewType.hasPrefix("build.") }
    }

    private func reconcileLocalCards(with packets: [ViewPacket]) {
        for packet in packets {
            guard let card = BuildCard(packet: packet) else { continue }
            setCardError(nil, for: card.id)
            if let localCard = localCards[card.id] {
                if localCard.isAnswered && !card.isAnswered {
                    continue
                }
                if let surface = Self.losingSurface(localCard: localCard, serverCard: card) {
                    recentlyCollapsedCardIDs.insert(card.id)
                    showTransientCardCaption(KCopy.answeredEarlier(surface: surface), cardID: card.id)
                    scheduleCollapsedCardRemoval(card.id, delayNanoseconds: 5_000_000_000)
                }
                localCards.removeValue(forKey: card.id)
            }
        }
    }

    private func markSyncedAndCache() {
        let syncedAt = now()
        lastSyncAt = syncedAt
        isStale = false
        cacheStore.save(packets, syncedAt: syncedAt)
    }

    private func updateIntentProgress(from packet: ViewPacket) {
        let fields = packet.fields ?? [:]
        let eventKind = fields["eventKind"]?.description.lowercased() ?? ""
        let status = fields["status"]?.description ?? fields["state"]?.description
        guard eventKind.contains("draft") || eventKind.contains("request") else { return }
        intentState = .drafting(packet.displayText.isEmpty ? (status ?? "drafting") : packet.displayText)
    }

    private func scheduleConfirmationExpiry(for key: BuildPendingCardAnswer) {
        confirmationExpiryTask?.cancel()
        confirmationExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.confirmationModel.clearExpired()
            if self.pendingConfirmation == key {
                self.pendingConfirmation = nil
            }
        }
    }

    private func scheduleCollapsedCardRemoval(_ cardID: String, delayNanoseconds: UInt64 = 3_000_000_000) {
        Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard let self else { return }
            self.recentlyCollapsedCardIDs.remove(cardID)
        }
    }

    private func showTransientCardCaption(_ caption: String, cardID: String) {
        cardCaptionTexts[cardID] = caption
        accessibilityLog.append(caption)
        cardCaptionExpiryTasks[cardID]?.cancel()
        cardCaptionExpiryTasks[cardID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.cardCaptionTexts[cardID] == caption else { return }
                self.cardCaptionTexts.removeValue(forKey: cardID)
                self.cardCaptionExpiryTasks.removeValue(forKey: cardID)
            }
        }
    }

    private static func losingSurface(
        attemptedOption: BuildCardOption,
        response: BuildCardAnswerResponse,
        reconciledCard: BuildCard
    ) -> String? {
        guard let alreadyAnswered = response.alreadyAnswered else { return nil }
        let answeredOption = alreadyAnswered.optionId ?? reconciledCard.answerOption
        let surface = alreadyAnswered.by ?? reconciledCard.answerSurface ?? reconciledCard.answeredBy
        if answeredOption != nil, answeredOption == attemptedOption.id, surface?.lowercased() == "founder" {
            return nil
        }
        return surface?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? surface : alreadyAnswered.by
    }

    private static func losingSurface(localCard: BuildCard, serverCard: BuildCard) -> String? {
        guard serverCard.isAnswered else { return nil }
        let localSurface = localCard.answeredBy ?? localCard.answerSurface
        let serverSurface = serverCard.answerSurface ?? serverCard.answeredBy
        if localCard.answerOption == serverCard.answerOption,
           localSurface?.lowercased() == serverSurface?.lowercased() {
            return nil
        }
        return serverSurface?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? serverSurface : serverCard.answeredBy
    }

    private func statusLine(_ outcome: AGUIOutcome) -> String {
        var parts: [String] = []
        if let lane = outcome.lane { parts.append(lane) }
        if let sensitivity = outcome.sensitivity { parts.append(sensitivity) }
        if outcome.held { parts.append("held") }
        if outcome.packet != nil { parts.append("packet") }
        return parts.isEmpty ? "answer applied" : parts.joined(separator: " · ").lowercased()
    }

    private static func normalizedBuildPackets(_ packets: [ViewPacket]) -> [ViewPacket] {
        var seen: Set<String> = []
        var normalized: [ViewPacket] = []
        for packet in packets where packet.viewType.hasPrefix("build.") {
            guard seen.insert(packet.id).inserted else { continue }
            normalized.append(packet)
        }
        return normalized
    }

    private static func answerFailureText(reason: String) -> String {
        KCopy.answerFailed(reason: reason)
    }

    private static func isOfflineError(_ error: Error) -> Bool {
        if error is URLError { return true }
        let description = error.localizedDescription.lowercased()
        return ["offline", "network", "not connected", "unreachable", "timed out", "timeout"]
            .contains { description.contains($0) }
    }

    private func setCardError(_ text: String?, for cardID: String) {
        let previous = cardErrors[cardID]
        cardErrors[cardID] = text
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
    }

    private func setIntentState(_ state: BuildIntentState) {
        let previous = intentState.feedbackErrorText
        intentState = state
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: state.feedbackErrorText))
    }

    @discardableResult
    private func persistInputQueue() -> Bool {
        inputQueueStore.save(inputQueue)
    }

    private func recordFeedback(_ event: KFeedbackEvent?) {
        var triggers = feedbackTriggers
        triggers.record(event)
        feedbackTriggers = triggers
    }

    static func retryDelayNanoseconds(attempt: Int) -> UInt64 {
        let seconds = min(30.0, pow(2.0, Double(max(0, attempt))))
        return UInt64(seconds * 1_000_000_000)
    }
}
