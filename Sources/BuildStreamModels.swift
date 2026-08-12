import SwiftUI
enum BuildIntentState: Equatable {
    case idle
    case submitting
    case drafting(String)
    case queued
    case notYet
    case failed(String)

    var text: String? {
        switch self {
        case .idle:
            return nil
        case .submitting:
            return KCopy.drafting
        case .drafting(let message):
            return message
        case .queued:
            return KCopy.queuedWillSync
        case .notYet:
            return "dormant · request endpoint not live"
        case .failed(let message):
            return KCopy.answerFailed(reason: message)
        }
    }

    var isDormant: Bool {
        if case .notYet = self { return true }
        return false
    }

    var isQueued: Bool {
        if case .queued = self { return true }
        return false
    }

    var feedbackErrorText: String? {
        if case .failed(let message) = self {
            return KCopy.answerFailed(reason: message)
        }
        return nil
    }
}

/// A build intent waiting for the daemon. The creation date is part of the
/// receipt so an offline request never looks like a fresh live write later.
struct QueuedBuildIntent: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }
}

struct BuildInputQueueState: Equatable, Codable, Sendable {
    private(set) var items: [QueuedBuildIntent]

    init(items: [QueuedBuildIntent] = []) {
        self.items = items.filter { !$0.text.isEmpty }
    }

    @discardableResult
    mutating func enqueue(
        _ text: String,
        now: Date = Date()
    ) -> QueuedBuildIntent? {
        let item = QueuedBuildIntent(text: text, createdAt: now)
        guard !item.text.isEmpty else { return nil }
        items.append(item)
        return item
    }

    mutating func nextForDispatch() -> QueuedBuildIntent? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func append(_ item: QueuedBuildIntent) {
        guard !item.text.isEmpty else { return }
        items.append(item)
    }
}

struct BuildInputQueueStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "build.inputQueue.v1",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> BuildInputQueueState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(BuildInputQueueState.self, from: data)
        else { return BuildInputQueueState() }
        return state
    }

    /// Returns false when the queue could not be durably encoded. The caller
    /// keeps the in-memory item and surfaces a caption rather than dropping it.
    @discardableResult
    func save(_ state: BuildInputQueueState) -> Bool {
        guard !state.items.isEmpty else {
            clear()
            return true
        }
        guard let data = try? JSONEncoder().encode(state) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct BuildPendingCardAnswer: Equatable, Sendable {
    var cardId: String
    var optionId: String
}

enum BuildAnswerStartResult: Equatable {
    case submitted
    case confirmationRequired
}

enum BuildCardAnswerOutcome: Equatable, Sendable {
    case answered
    case failed
    case skipped
}

struct BuildCardOptionPresentation: Equatable {
    var option: BuildCardOption
    var isEnabled: Bool
    var isPrimary: Bool
    var consequence: String
    var requiresConfirmation: Bool
    var disabledReason: String?
}

struct BuildCardPresentation: Equatable {
    var card: BuildCard
    var options: [BuildCardOptionPresentation]
    var note: String?
    var isCollapsed: Bool

    init(card: BuildCard, isPending: Bool = false, disabledReason: String? = nil) {
        self.card = card
        isCollapsed = card.isAnswered
        note = disabledReason ?? (card.isLoopbackOnly && card.isOpen ? "pinned to the mac" : nil)
        let primaryOptionID = Self.primaryOptionID(for: card)
        options = card.options.map { option in
            let optionDisabledReason = Self.disabledReason(for: card, isPending: isPending)
            return BuildCardOptionPresentation(
                option: option,
                isEnabled: optionDisabledReason == nil,
                isPrimary: option.id == primaryOptionID,
                consequence: card.brief?.whatHappens(for: option.id) ?? option.consequence,
                requiresConfirmation: option.requiresConfirmation,
                disabledReason: optionDisabledReason
            )
        }
    }

    private static func disabledReason(for card: BuildCard, isPending: Bool) -> String? {
        if !card.isOpen { return "answered" }
        if card.isLoopbackOnly { return "pinned to the mac" }
        if isPending { return KCopy.answerPending }
        return nil
    }

    private static func primaryOptionID(for card: BuildCard) -> String? {
        let recommendation = card.recommendation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let recommendation, !recommendation.isEmpty {
            if let recommended = card.options.first(where: { option in
                option.id.lowercased() == recommendation || option.label.lowercased() == recommendation
            }) {
                return recommended.id
            }
        }
        return card.options.first?.id
    }
}

enum BuildStreamRole: Equatable {
    case runner
    case founder
    case system
}

enum BuildStreamAnchor: String, CaseIterable, Equatable, Hashable {
    case stream
    case cards
    case plan
}

struct BuildStreamLine: Identifiable, Equatable {
    var id: String
    var role: BuildStreamRole
    var text: String
    var termAnnotations: [TermAnnotation]? = nil
    var meta: String?
    /// K replies carry their provenance receipt with the line. Absence stays
    /// silent so build packets cannot invent chat chrome.
    var receipt: ChatReceipt? = nil
    var anchor: BuildStreamAnchor
    var record: BuildRecord? = nil
    var recordKind: BuildRecordSection.Kind? = nil
}

struct BuildMissionPresentation: Equatable {
    var title: String
    var progressText: String
    var progressRatio: Double
    var detail: String?

    init(statusPacket: ViewPacket?, connectionState: KConnectionStateModel) {
        guard let statusPacket else {
            title = connectionState.status.text
            progressText = "0 of 0"
            progressRatio = 0
            detail = nil
            return
        }

        let summary = BuildStatusSummary(packet: statusPacket)
        let completed = summary.units.filter { record in
            Self.isCompleteState(record.state)
        }.count
        let total = summary.units.count

        title = summary.title
        progressText = total > 0 ? "\(completed) of \(total)" : (summary.state ?? connectionState.status.text)
        progressRatio = total > 0 ? Double(completed) / Double(total) : 0
        detail = summary.detail
    }

    private static func isCompleteState(_ state: String?) -> Bool {
        let value = state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return [
            "integrated",
            "complete",
            "completed",
            "done",
            "green",
            "verified",
            "deployed",
        ].contains(value)
    }
}

enum BuildWorkerRailPlacement: Equatable {
    case absent
    case regularRail
    case compactSection
}

enum BuildWorkerRailLayout {
    static func placement(availableWidth: CGFloat, items: [BuildWorkerRailItem]) -> BuildWorkerRailPlacement {
        guard !items.isEmpty else { return .absent }
        return availableWidth >= KStyle.buildWorkerRegularRailMinimumWidth ? .regularRail : .compactSection
    }
}

struct BuildWorkerRailItem: Identifiable, Equatable {
    var planId: String
    var unitId: String
    var planTitle: String?
    var unitTitle: String?
    var state: String
    var startedAt: String?
    var elapsedFallback: String?
    var holdReason: String?
    var laneId: String?

    init(
        planId: String,
        unitId: String,
        state: String,
        startedAt: String? = nil,
        elapsedFallback: String? = nil,
        holdReason: String? = nil,
        laneId: String? = nil,
        planTitle: String? = nil,
        unitTitle: String? = nil
    ) {
        self.planId = planId
        self.unitId = unitId
        self.state = state
        self.startedAt = startedAt
        self.elapsedFallback = elapsedFallback
        self.holdReason = holdReason
        self.laneId = laneId
        self.planTitle = planTitle
        self.unitTitle = unitTitle
    }

    var id: String {
        "\(planId)-\(unitId)"
    }

    var accessibilityIdentifier: String {
        "build-worker-\(unitId)"
    }

    var isHeld: Bool {
        state == "held"
    }

    func summaryLine(now: Date) -> String {
        [
            BuildPlanRow.nickname(planId: planId, title: planTitle),
            unitTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            state,
            elapsedText(now: now),
        ]
            .compactMap(Self.normalized)
            .joined(separator: " · ")
            .lowercased()
    }

    func elapsedText(now: Date) -> String? {
        if let startedAt, let started = Self.date(from: startedAt) {
            return Self.elapsedText(since: started, now: now)
        }
        return Self.normalized(elapsedFallback)?.lowercased()
    }

    static func items(from packets: [ViewPacket]) -> [BuildWorkerRailItem] {
        var seenIDs: Set<String> = []
        var output: [BuildWorkerRailItem] = []

        for packet in packets where packet.isBuildStatusPacket {
            let summary = BuildStatusSummary(packet: packet)
            for item in items(from: summary) where !seenIDs.contains(item.id) {
                seenIDs.insert(item.id)
                output.append(item)
            }
        }

        return output
    }

    private static func items(from summary: BuildStatusSummary) -> [BuildWorkerRailItem] {
        summary.units.compactMap { unit in
            let unitId = scalar(unit.unitId ?? unit.id)
            let lane = matchingLane(for: unit, unitId: unitId, lanes: summary.lanes)
            let state = normalizedState(unit.state ?? lane?.state)
            guard let unitId, let state, activeStates.contains(state) else { return nil }

            let planId = scalar(unit.planId ?? lane?.planId ?? summary.planId)
                ?? "plan"
            let holdReason = state == "held"
                ? scalar(unit.holdReason ?? unit.detail ?? lane?.holdReason ?? lane?.detail)
                : nil

            return BuildWorkerRailItem(
                planId: planId,
                unitId: unitId,
                state: state,
                startedAt: lane?.startedAt ?? unit.startedAt,
                elapsedFallback: lane?.age ?? unit.age,
                holdReason: holdReason,
                laneId: lane?.laneId ?? lane?.id ?? unit.laneId,
                planTitle: summary.title,
                unitTitle: unit.title
            )
        }
    }

    private static let activeStates: Set<String> = [
        "building",
        "verifying",
        "held",
        "deploying",
        "review-pending",
    ]

    private static func matchingLane(
        for unit: BuildRecord,
        unitId: String?,
        lanes: [BuildRecord]
    ) -> BuildRecord? {
        lanes.first { lane in
            if let unitId, normalized(lane.unitId) == normalized(unitId) { return true }
            if let unitLaneId = normalized(unit.laneId) {
                return normalized(lane.id) == unitLaneId || normalized(lane.laneId) == unitLaneId
            }
            return false
        }
    }

    private static func normalizedState(_ value: String?) -> String? {
        normalized(value)?
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }

    private static func scalar(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        return internet.date(from: trimmed)
    }

    static func elapsedText(since startedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

enum BuildDepthSurface: Equatable {
    case desk
    case review
    case learned
    case trust
    case logTail
}

/// The resting desk element that opened a depth reader. Keeping this identity
/// separate from the reader surface lets the desk remain rendered underneath and
/// visibly mark the origin while the reader is elevated above it.
enum BuildDepthOrigin: Equatable {
    case record(String)
    case branch(String)
    case needsYou(String)
}

struct BuildReviewTarget: Equatable, Sendable {
    var id: String
    var title: String
    var unitId: String?
    var cardId: String?
    var laneId: String?
    var diffId: String?
    var docPaths: [String]

    init(
        id: String,
        title: String,
        unitId: String? = nil,
        cardId: String? = nil,
        laneId: String? = nil,
        diffId: String? = nil,
        docPaths: [String] = []
    ) {
        self.id = id
        self.title = title
        self.unitId = unitId
        self.cardId = cardId
        self.laneId = laneId
        self.diffId = diffId
        self.docPaths = BuildPayload.unique(docPaths)
    }
}

struct BuildReviewState: Equatable, Sendable {
    var target: BuildReviewTarget?
    var isLoading = false
    var evidence: [BuildEvidenceEntry] = []
    var diffs: [BuildDiffResponse] = []
    var documents: [BuildDocumentResponse] = []
    var error: String?

    var evidencePresentations: [BuildEvidenceEntryPresentation] {
        evidence.map(BuildEvidenceEntryPresentation.init)
    }

    var isEmpty: Bool {
        evidence.isEmpty && diffs.isEmpty && documents.isEmpty
    }
}

struct BuildLearnedState: Equatable, Sendable {
    var isLoading = false
    var feed = BuildLearnedFeed()
    var pendingDecisionIDs: Set<String> = []
    var error: String?
}

struct BuildTrustState: Equatable, Sendable {
    var isLoading = false
    var response = BuildTrustResponse()
    var error: String?
}

struct BuildLogTailTarget: Equatable, Sendable {
    var laneId: String
    var title: String
}

struct BuildLogTailState: Equatable, Sendable {
    var target: BuildLogTailTarget?
    var isLoading = false
    var response: BuildLaneLogTailResponse?
    var error: String?
}

enum BuildStreamComposer {
    static func lines(
        packets: [ViewPacket],
        localCards: [String: BuildCard],
        connectionState: KConnectionStateModel
    ) -> [BuildStreamLine] {
        var lines: [BuildStreamLine] = []
        var seenCards: Set<String> = []

        for packet in packets {
            if packet.isBuildStatusPacket {
                // Archive rows can participate in the THREADS projection
                // without becoming trunk conversation. This keeps the seven
                // row replacement window reachable without flooding the
                // founder-facing stream with parked history.
                if packet.fields?["sidebarOnly"]?.boolValue == true { continue }
                lines.append(contentsOf: statusLines(from: packet))
                continue
            }

            if let packetCard = BuildCard(packet: packet) {
                let card = localCards[packetCard.id] ?? packetCard
                seenCards.insert(card.id)
                if let line = answeredLine(from: card) {
                    lines.append(line)
                }
                continue
            }

            if packet.viewType.hasPrefix("build.") {
                let text = packet.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    lines.append(BuildStreamLine(
                        id: "packet-\(packet.id)",
                        role: .runner,
                        text: text.lowercased(),
                        termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields),
                        meta: meta(from: packet),
                        receipt: receipt(from: packet),
                        anchor: .stream
                    ))
                }
            }
        }

        for card in localCards.values.sorted(by: { $0.id < $1.id }) where !seenCards.contains(card.id) {
            if let line = answeredLine(from: card) {
                lines.append(line)
            }
        }

        if lines.isEmpty {
            lines.append(BuildStreamLine(
                id: "connection-\(connectionState.status.text)",
                role: .system,
                text: connectionStateLine(connectionState),
                meta: nil,
                anchor: .stream
            ))
        }

        return lines
    }

    private static func statusLines(from packet: ViewPacket) -> [BuildStreamLine] {
        let summary = BuildStatusSummary(packet: packet)
        let receipt = receipt(from: packet)
        var lines: [BuildStreamLine] = []

        lines.append(contentsOf: summary.history.map { originalRecord in
            var record = originalRecord
            if record.planId == nil {
                record.planId = summary.planId ?? summary.title
            }
            return BuildStreamLine(
                id: "\(packet.id)-history-\(record.id)",
                role: .runner,
                text: record.title.lowercased(),
                meta: record.age?.lowercased() ?? record.updatedAt?.lowercased(),
                receipt: receipt,
                anchor: .stream,
                record: record,
                recordKind: .history
            )
        })

        lines.append(contentsOf: summary.units.compactMap { record in
            stateLine(record, packetID: packet.id, prefix: "unit", kind: .unit, receipt: receipt)
        })
        lines.append(contentsOf: summary.lanes.compactMap { record in
            stateLine(record, packetID: packet.id, prefix: "lane", kind: .lane, receipt: receipt)
        })

        return lines
    }

    private static func stateLine(
        _ record: BuildRecord,
        packetID: String,
        prefix: String,
        kind: BuildRecordSection.Kind,
        receipt: ChatReceipt?
    ) -> BuildStreamLine? {
        guard let state = record.state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty else {
            return nil
        }

        var text = "\(record.title) \(state)"
        let detail = record.goal ?? record.detail ?? record.scope ?? record.logTail ?? record.diff
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += " · \(detail)"
        }

        return BuildStreamLine(
            id: "\(packetID)-\(prefix)-\(record.id)",
            role: .runner,
            text: text.lowercased(),
            meta: record.age?.lowercased() ?? record.updatedAt?.lowercased(),
            receipt: receipt,
            anchor: .plan,
            record: record,
            recordKind: kind
        )
    }

    private static func answeredLine(from card: BuildCard) -> BuildStreamLine? {
        guard card.isAnswered else { return nil }
        let optionText = card.answerOption.flatMap { optionID in
            card.options.first(where: { $0.id == optionID })?.label ?? optionID
        } ?? "answered"
        let meta = card.answeredAt ?? card.answeredBy ?? card.answerSurface
        return BuildStreamLine(
            id: "answered-\(card.id)",
            role: .founder,
            text: "\(card.voiceTitle) · \(optionText)".lowercased(),
            meta: meta?.lowercased(),
            anchor: .cards
        )
    }

    private static func meta(from packet: ViewPacket) -> String? {
        let fields = packet.fields ?? [:]
        return (fields["age"] ?? fields["updatedAt"] ?? fields["at"])?.description.lowercased()
    }

    private static func receipt(from packet: ViewPacket) -> ChatReceipt? {
        let receipt = ChatNextActionPacket(packet: packet).receipt
        return receipt.text == nil ? nil : receipt
    }

    private static func connectionStateLine(_ state: KConnectionStateModel) -> String {
        switch state.status {
        case .idle:
            return "stream idle"
        case .connecting:
            return KCopy.connecting
        case .live:
            return "stream live"
        case .reconnecting:
            return KCopy.reconnecting
        case .offlineRetrying:
            return KCopy.offlineRetrying
        case .tailnetNeeded:
            return KCopy.tailnetNeeded
        }
    }
}

struct BuildSnapshotCacheStore {
    private struct StoredSnapshot: Codable {
        var version: Int
        var packets: [ViewPacket]
        var savedAt: Date?
    }

    struct CachedSnapshot: Equatable {
        var packets: [ViewPacket]
        var savedAt: Date
    }

    let fileURL: URL
    let fileManager: FileManager

    init(
        fileURL: URL = BuildSnapshotCacheStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("build-snapshot.json", isDirectory: false)
    }

    func load() -> [ViewPacket] {
        loadEntry()?.packets ?? []
    }

    func loadEntry() -> CachedSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            // v3 invalidates every earlier cache: pre-v3 snapshots predate the
            // on-you card-packet filter and can carry stale on-me cards that no
            // server refresh removes (their close events are now filtered out).
            // Discard them rather than resurrect them via a version-agnostic decode.
            guard let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
                  stored.version >= 3 else {
                return nil
            }
            return CachedSnapshot(packets: stored.packets, savedAt: stored.savedAt ?? fileModifiedAt())
        } catch {
            NSLog("[K] build snapshot cache load failed at %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    func save(_ packets: [ViewPacket], syncedAt: Date = Date()) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(StoredSnapshot(version: 3, packets: packets, savedAt: syncedAt))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] build snapshot cache save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func fileModifiedAt() -> Date {
        ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date) ?? Date(timeIntervalSince1970: 0)
    }
}
