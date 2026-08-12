import Foundation
import SwiftUI

enum ChatThreadPhase: String, Codable, Equatable, Sendable {
    case processing
    case finished
    case queuedOffline
    case resolved
    case archived
    case failed

    var isProcessing: Bool { self == .processing }
    var isArchived: Bool { self == .resolved || self == .archived }
}

enum ChatThreadBuildState: String, Codable, Equatable, Sendable {
    case idle
    case staging
    case staged
    case failed
}

/// Typed boundary used by another surface to open or continue one of Chat's
/// durable side threads. The sender owns the anchor/context; Chat owns branch
/// creation, history, queueing, and the eventual composer target.
struct ChatThreadHandoff: Equatable, Sendable {
    let anchorID: String
    let anchorText: String
    let entities: [ViewPacketJSONValue]
    let initialComment: String?
}

struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var branch: CSKChatBranch?
    var forkMessageID: String
    var title: String
    var statusText: String
    var phase: ChatThreadPhase
    var history: [Message]
    var actionPacket: ViewPacket?
    var buildState: ChatThreadBuildState
    var errorText: String?
    var stepEvents: [ChatThreadStep]
    var retryCount: Int?
    var retryText: String?
    var createdAt: Date
    /// The moment a completed result landed. Later metadata must not restart this clock.
    var landedAt: Date?
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case branch
        case forkMessageID
        case title
        case statusText
        case phase
        case history
        case actionPacket
        case buildState
        case errorText
        case stepEvents
        case retryCount
        case retryText
        case createdAt
        case landedAt
        case updatedAt
    }

    init(
        id: String,
        branch: CSKChatBranch? = nil,
        forkMessageID: String,
        title: String,
        statusText: String = KCopy.chatReadyToExplore,
        phase: ChatThreadPhase = .finished,
        history: [Message] = [],
        actionPacket: ViewPacket? = nil,
        buildState: ChatThreadBuildState = .idle,
        errorText: String? = nil,
        stepEvents: [ChatThreadStep] = [],
        retryCount: Int? = nil,
        retryText: String? = nil,
        createdAt: Date = Date(),
        landedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.branch = branch
        self.forkMessageID = forkMessageID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.statusText = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.phase = phase
        self.history = history
        self.actionPacket = actionPacket
        self.buildState = buildState
        self.errorText = errorText
        self.stepEvents = stepEvents
        self.retryCount = retryCount
        self.retryText = retryText
        self.createdAt = createdAt
        self.landedAt = landedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        branch = try container.decodeIfPresent(CSKChatBranch.self, forKey: .branch)
        forkMessageID = try container.decode(String.self, forKey: .forkMessageID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText) ?? KCopy.chatReadyToExplore
        phase = try container.decodeIfPresent(ChatThreadPhase.self, forKey: .phase) ?? .finished
        history = try container.decodeIfPresent([Message].self, forKey: .history) ?? []
        actionPacket = try container.decodeIfPresent(ViewPacket.self, forKey: .actionPacket)
        buildState = try container.decodeIfPresent(ChatThreadBuildState.self, forKey: .buildState) ?? .idle
        errorText = try container.decodeIfPresent(String.self, forKey: .errorText)
        stepEvents = try container.decodeIfPresent([ChatThreadStep].self, forKey: .stepEvents) ?? []
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount)
        retryText = try container.decodeIfPresent(String.self, forKey: .retryText)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: .zero)
        landedAt = try container.decodeIfPresent(Date.self, forKey: .landedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    init(branch: CSKChatBranch, anchor: Message? = nil, now: Date = Date()) {
        let forkMessage = branch.contextCapsule?.forkMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = forkMessage?.isEmpty == false ? forkMessage! : (anchor?.text ?? KCopy.chatReadyToExplore)
        let createdAt = Self.date(branch.createdAt) ?? now
        let phase: ChatThreadPhase
        switch branch.state?.lowercased() {
        case "kept":
            phase = .resolved
        case "discarded", "expired":
            phase = .archived
        default:
            phase = .processing
        }
        self.init(
            id: branch.id,
            branch: branch,
            forkMessageID: branch.forkMessageId ?? anchor?.id.uuidString ?? branch.id,
            title: title,
            statusText: phase == .resolved
                ? KCopy.chatResolved
                : (phase == .archived ? KCopy.chatArchived : (phase == .processing ? KCopy.chatThinking : KCopy.chatReadyToExplore)),
            phase: phase,
            history: anchor.map { [$0] } ?? [],
            createdAt: createdAt,
            updatedAt: Self.date(branch.updatedAt) ?? createdAt
        )
        if phase == .resolved || phase == .archived {
            landedAt = Self.date(branch.updatedAt) ?? createdAt
        }
    }

    // Founder ruling 2026-08-04: a completed card carries its result as hue
    // on one minimal check mark — white clean (founder: completed stays quiet), yellow with-notes, red failed.
    enum ResultTone { case clean, notes, failed }
    var resultTone: ResultTone? {
        switch phase {
        case .failed: return .failed
        case .finished, .resolved, .archived:
            return (errorText?.isEmpty == false) ? .notes : .clean
        case .processing, .queuedOffline: return nil
        }
    }

    var isCompleted: Bool { resultTone != nil }

    var isConcluded: Bool {
        [.finished, .resolved, .archived].contains(phase)
    }

    var canRetry: Bool {
        phase == .failed && (retryCount ?? .zero) < 1 && retryText?.isEmpty == false
    }

    var isOpen: Bool {
        guard !phase.isArchived else { return false }
        return branch?.state == nil || branch?.isOpen == true
    }

    var usesPaperTone: Bool {
        phase == .finished || buildState == .staging || buildState == .staged
    }

    var visualState: ChatThreadVisualState {
        switch phase {
        case .processing: return .building
        case .finished:
            return buildState == .staging || buildState == .staged ? .staged : .done
        case .resolved, .archived: return .resolved
        case .queuedOffline: return .queuedOffline
        case .failed: return .failed
        }
    }

    mutating func reconcile(branch: CSKChatBranch, now: Date = Date()) {
        self.branch = branch
        if let message = branch.contextCapsule?.forkMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            title = message
        }
        updatedAt = Self.date(branch.updatedAt) ?? now
        switch branch.state?.lowercased() {
        case "kept":
            phase = .resolved
            statusText = KCopy.chatResolved
            if landedAt == nil { landedAt = updatedAt }
        case "discarded", "expired":
            phase = .archived
            statusText = KCopy.chatArchived
            if landedAt == nil { landedAt = updatedAt }
        default:
            break
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encode(forkMessageID, forKey: .forkMessageID)
        try container.encode(title, forKey: .title)
        try container.encode(statusText, forKey: .statusText)
        try container.encode(phase, forKey: .phase)
        try container.encode(history, forKey: .history)
        try container.encodeIfPresent(actionPacket, forKey: .actionPacket)
        try container.encode(buildState, forKey: .buildState)
        try container.encodeIfPresent(errorText, forKey: .errorText)
        try container.encode(stepEvents, forKey: .stepEvents)
        try container.encodeIfPresent(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(retryText, forKey: .retryText)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(landedAt, forKey: .landedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Deterministic, local-only chat state for the motion audit walk. It gives the
/// capture rig a real trunk anchor and an open branch without a daemon request.
/// The fixture is opt-in through a launch argument and never participates in
/// normal app state.
enum ChatBranchMotionFixture {
    static let launchArgument = "-chat-branch-motion-fixture"
    static let branchID = "motion-demo-branch"
    static let anchorID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let replyID = UUID(uuidString: "12121212-1212-4121-8121-121212121212")!
    static let answerID = UUID(uuidString: "13131313-1313-4131-8131-131313131313")!
    static let fixtureNow = ISO8601DateFormatter.fixtureDate("2026-08-10T07:00:00Z")

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    static func snapshot(now: Date = fixtureNow) -> (messages: [Message], threads: [ChatThread]) {
        let anchor = Message(
            id: anchorID,
            role: .k,
            text: "trace this side path",
            createdAt: now
        )
        let reply = Message(
            id: replyID,
            role: .you,
            text: "keep the origin in view",
            createdAt: now
        )
        let answer = Message(
            id: answerID,
            role: .k,
            text: "the path is open from its rail",
            createdAt: now
        )
        let stamp = ISO8601DateFormatter().string(from: now)
        let branch = CSKChatBranch(
            id: branchID,
            trunkThreadId: "motion-demo-trunk",
            forkMessageId: anchor.id.uuidString,
            contextCapsule: .init(forkMessage: anchor.text, entities: nil),
            state: "open",
            createdAt: stamp,
            updatedAt: stamp
        )
        var thread = ChatThread(branch: branch, anchor: anchor, now: now)
        thread.phase = .finished
        thread.statusText = ""
        thread.history = [anchor, reply, answer]
        thread.landedAt = now
        thread.updatedAt = now
        return (messages: [anchor], threads: [thread])
    }
}

/// A deterministic trunk-plus-branch story for the chat audit walk. It keeps
/// the existing branch-motion IDs and thread presentation, while adding enough
/// trunk history for the cold and composed captures to read as a real thread.
/// The fixture is opt-in and never participates in normal chat state.
/// Doctrine: recognition-over-recall, silence-default, staleness-honesty.
enum ChatDemoFixture {
    static let launchArgument = "-chatdemo"

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        if arguments.contains(launchArgument) {
            return true
        }

        // The loading walk asks the chat surface to hold its first-fetch state
        // without adding another daemon seam. If the harness drops the optional
        // chatdemo marker, the chat route still receives the same local story.
        guard arguments.contains(KLoadingPreview.launchArgument) else { return false }
        var requestedChatRoute = false
        for (index, argument) in arguments.enumerated() {
            if argument == "-tab", arguments.indices.contains(index + 1) {
                requestedChatRoute = requestedChatRoute
                    || arguments[index + 1].lowercased() == KAppTab.chat.rawValue
            }
            if argument.hasPrefix("-tab=") {
                requestedChatRoute = requestedChatRoute
                    || String(argument.dropFirst("-tab=".count)).lowercased() == KAppTab.chat.rawValue
            }
        }
        return requestedChatRoute
    }

    static func snapshot(now: Date = ChatBranchMotionFixture.fixtureNow) -> (messages: [Message], threads: [ChatThread]) {
        let branchFixture = ChatBranchMotionFixture.snapshot(now: now)
        let anchor = branchFixture.messages[0]
        let earlierFounder = Message(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            role: .you,
            text: "the morning keeps slipping",
            createdAt: now.addingTimeInterval(-900)
        )
        let earlierReply = Message(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            role: .k,
            text: "sleep and the first block are drifting together",
            createdAt: now.addingTimeInterval(-840)
        )
        let latestFounder = Message(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            role: .you,
            text: "where should i start?",
            createdAt: now.addingTimeInterval(-120)
        )
        return (
            messages: [earlierFounder, earlierReply, latestFounder, anchor],
            threads: branchFixture.threads
        )
    }
}

private extension ISO8601DateFormatter {
    static func fixtureDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}

enum ChatThreadVisualState: String, CaseIterable, Hashable, Sendable {
    case building
    case done
    case staged
    case resolved
    case queuedOffline
    case failed
}

enum ChatThreadCopy {
    static let forkedFromTrunk = "forked from trunk"
    static let stagedToBuild = "staged to build"
    static let traceComplete = "trace complete · verdict waits on you"
    static let junk = "junk"
    static let later = "later"
    static let stageToBuild = "stage to build"
    static let retry = "retry"
    static let parked = "parked"
    static let approveInBuild = "approve in build"
    static let buildGateMissing = "build gate missing · nothing staged"

    static func stageQuestion(for title: String) -> String {
        "stage this as a build: \(title)?"
    }

    static func completedSteps(_ count: Int) -> String {
        "✓ \(count) steps"
    }
}

enum ChatThreadPacketFields {
    static func note(in packet: ViewPacket?) -> String? {
        string(
            in: packet,
            keys: ["note", "notes", "resultNote", "result_note"]
        )
    }

    static func nextAction(in packet: ViewPacket?) -> String? {
        if let direct = string(
            in: packet,
            keys: ["nextAction", "next_action", "nextActionText", "next_action_text"]
        ) {
            return direct
        }
        return packet
            .map { ChatNextActionPacket(packet: $0).actions.first?.label }
            .flatMap(normalized)
    }

    static func research(in packet: ViewPacket?) -> ChatThreadResearchSummary? {
        guard let packet else { return nil }
        let fields = packet.fields ?? [:]
        let stage = string(in: fields, packet: packet, keys: ["stage", "researchStage", "research_stage"])
        let sourceCount = string(in: fields, packet: packet, keys: ["sourceCount", "source_count", "sources"])
        let minutes = string(in: fields, packet: packet, keys: ["minutes", "durationMinutes", "duration_minutes"])
        guard stage != nil || sourceCount != nil || minutes != nil else { return nil }
        return ChatThreadResearchSummary(stage: stage, sourceCount: sourceCount, minutes: minutes)
    }

    private static func string(in packet: ViewPacket?, keys: [String]) -> String? {
        guard let packet else { return nil }
        return string(in: packet.fields ?? [:], packet: packet, keys: keys)
    }

    private static func string(
        in fields: [String: ViewPacketJSONValue],
        packet: ViewPacket,
        keys: [String]
    ) -> String? {
        for key in keys {
            let value = fields[key] ?? packet.provenance[key]
            let text = value?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if text?.isEmpty == false { return text }
        }
        return nil
    }

    private static func normalized(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct ChatThreadResearchSummary: Equatable, Sendable {
    let stage: String?
    let sourceCount: String?
    let minutes: String?

    var line: String {
        [
            stage,
            sourceCount.map { "\($0) sources" },
            minutes.map { "\($0)m" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

extension ChatThread {
    var noteText: String? {
        ChatThreadPacketFields.note(in: actionPacket)
    }

    var nextActionText: String? {
        ChatThreadPacketFields.nextAction(in: actionPacket)
    }

    var researchSummary: ChatThreadResearchSummary? {
        ChatThreadPacketFields.research(in: actionPacket)
    }

    var detail: ChatThreadDetail {
        ChatThreadDetail(thread: self)
    }
}

struct ChatThreadDetail: Equatable, Sendable {
    struct Source: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let isLive: Bool
    }

    let bornAt: Date
    let origin: String
    let turnCount: Int
    let verdictLine: String
    let sources: [Source]

    init(thread: ChatThread) {
        bornAt = thread.createdAt
        let forkText = thread.branch?.contextCapsule?.forkMessage
            ?? thread.history.first(where: { $0.role == .you })?.text
            ?? thread.title
        let firstLine = forkText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? KCopy.chatReadyToExplore
        let normalizedOrigin = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        origin = normalizedOrigin.isEmpty ? KCopy.chatReadyToExplore : normalizedOrigin
        turnCount = thread.history.count

        switch thread.threadStackState {
        case .needsYou:
            verdictLine = "verdict waiting on you"
        case .processing:
            verdictLine = "trace in progress"
        case .failed:
            verdictLine = "trace failed"
        case .completed:
            verdictLine = "trace complete"
        }

        let labels = thread.actionPacket
            .map { ChatNextActionPacket(packet: $0).sources }
            ?? []
        let isLive = thread.phase == .processing || thread.buildState == .staging
        sources = labels.enumerated().map { index, label in
            let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let carriesLiveTrace = normalized.hasPrefix("reading ") || normalized.contains("in progress")
            return Source(
                id: "\(thread.id)-source-\(index)",
                label: label,
                isLive: carriesLiveTrace || (isLive && index == labels.count - 1)
            )
        }
    }
}

enum ChatThreadVerdictActions {
    static func items(for packet: ViewPacket) -> [ChatNextActionItem] {
        let emitted = ChatNextActionPacket(packet: packet).actions
        guard !emitted.isEmpty else {
            // A human-gated build packet has no advisory next-action payload. These
            // three verdicts are the packet's explicit branch disposition grammar.
            return [
                // The visible verdict says "junk"; the stable id remains
                // `archive` so existing audit clients keep their action hook.
                ChatNextActionItem(id: "archive", label: ChatThreadCopy.junk),
                ChatNextActionItem(id: "later", label: ChatThreadCopy.later),
                // The label is the frozen v21 verdict; `build` preserves the
                // pre-U2 `chat-thread-build-<id>` accessibility hook.
                ChatNextActionItem(id: "build", label: ChatThreadCopy.stageToBuild),
            ]
        }
        return emitted
    }
}

enum ChatThreadLifecycle {
    static func complete(
        _ thread: ChatThread,
        note: String? = nil,
        at date: Date
    ) -> ChatThread {
        var completed = thread
        completed.phase = .finished
        completed.statusText = ""
        completed.errorText = normalized(note)
        completed.retryText = nil
        completed.retryCount = nil
        completed.landedAt = date
        completed.updatedAt = date
        return completed
    }

    static func manuallyComplete(_ thread: ChatThread, at date: Date) -> ChatThread {
        var completed = thread
        completed.phase = .resolved
        completed.statusText = KCopy.chatResolved
        completed.errorText = nil
        completed.retryText = nil
        completed.retryCount = nil
        completed.landedAt = date
        completed.updatedAt = date
        return completed
    }

    static func queueOffline(_ thread: ChatThread, at date: Date) -> ChatThread {
        var queued = thread
        queued.phase = .queuedOffline
        queued.statusText = KCopy.queuedWillSync
        queued.errorText = nil
        queued.updatedAt = date
        return queued
    }

    static func fail(_ thread: ChatThread, error: String?, at date: Date) -> ChatThread {
        var failed = thread
        failed.phase = .failed
        failed.statusText = ""
        failed.errorText = normalized(error)
        failed.updatedAt = date
        return failed
    }

    static func retry(_ thread: ChatThread, at date: Date) -> ChatThread? {
        guard canRetry(thread) else { return nil }
        var retrying = thread
        retrying.phase = .processing
        retrying.statusText = KCopy.chatThinking
        retrying.errorText = nil
        retrying.stepEvents = []
        retrying.retryCount = 1
        retrying.updatedAt = date
        return retrying
    }

    static func canRetry(_ thread: ChatThread) -> Bool {
        thread.canRetry
    }

    static func archiveSuperseded(_ threads: inout [ChatThread], newerID: String) {
        guard let newer = threads.first(where: { $0.id == newerID }), newer.phase == .finished else { return }
        for index in threads.indices {
            guard threads[index].id != newerID,
                  threads[index].phase == .finished,
                  threads[index].updatedAt < newer.updatedAt
            else { continue }
            threads[index].phase = .archived
            threads[index].statusText = KCopy.chatArchived
            if threads[index].landedAt == nil {
                threads[index].landedAt = threads[index].updatedAt
            }
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

struct ChatBranchThreadStore {
    static let defaultLimit = 80

    private struct StoredThreads: Codable {
        var version: Int
        var threads: [ChatThread]
    }

    private let fileURL: URL
    private let limit: Int
    private let fileManager: FileManager

    init(
        fileURL: URL = ChatBranchThreadStore.defaultFileURL(),
        limit: Int = ChatBranchThreadStore.defaultLimit,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.limit = max(0, limit)
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("chat-branch-threads.json", isDirectory: false)
    }

    func load() -> [ChatThread] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredThreads.self, from: data),
              stored.version == 1
        else { return [] }
        return Array(stored.threads.suffix(limit))
    }

    func save(_ threads: [ChatThread]) {
        guard !threads.isEmpty else {
            clear()
            return
        }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stored = StoredThreads(version: 1, threads: Array(threads.suffix(limit)))
            try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] chat branch thread save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }
}

struct ChatTrunkIdentityStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "chat.trunkIdentity.v1",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func loadOrCreate() -> String {
        if let existing = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        return rotate()
    }

    @discardableResult
    func rotate() -> String {
        let value = "trunk_\(UUID().uuidString.lowercased())"
        defaults.set(value, forKey: key)
        return value
    }
}

/// The rail's four-state projection. These are presentation states, not new
/// lifecycle phases: staged and queued work remain processing until K lands a
/// result, while a landed result with an available action waits in needs-you.
enum ThreadStackState: String, CaseIterable, Equatable, Sendable {
    case completed
    case processing
    case needsYou = "needs-you"
    case failed

    fileprivate var sortRank: Int {
        switch self {
        case .completed: return 0
        case .processing: return 1
        case .needsYou: return 2
        case .failed: return 3
        }
    }
}

extension ChatThread {
    var threadStackState: ThreadStackState {
        if phase == .failed || buildState == .failed {
            return .failed
        }
        switch phase {
        case .failed:
            return .failed
        case .processing, .queuedOffline:
            return .processing
        case .finished:
            if buildState == .staging || buildState == .staged {
                return .processing
            }
            return actionPacket != nil && isOpen ? .needsYou : .completed
        case .resolved, .archived:
            return .completed
        }
    }

    // Named aliases keep the projection easy to consume at other seams without
    // asking those seams to know which field combination defines needs-you.
    var railState: ThreadStackState { threadStackState }
}

enum ThreadStackAging {
    static let retention: TimeInterval = 3 * 24 * 60 * 60
    static let day: TimeInterval = 24 * 60 * 60

    static func landedAt(for thread: ChatThread) -> Date? {
        guard thread.threadStackState == .completed else { return nil }
        // updatedAt is the safe migration fallback for rows persisted before
        // landedAt existed. New completions always carry the explicit anchor.
        return thread.landedAt ?? thread.updatedAt
    }

    static func isExpired(_ thread: ChatThread, now: Date) -> Bool {
        guard let landedAt = landedAt(for: thread) else { return false }
        return now.timeIntervalSince(landedAt) >= retention
    }

    static func label(for thread: ChatThread, now: Date) -> String? {
        guard let landedAt = landedAt(for: thread) else { return nil }
        let remaining = retention - now.timeIntervalSince(landedAt)
        guard remaining > .zero, remaining < retention else { return nil }
        let days = max(1, Int(ceil(remaining / day)))
        return "leaves in \(days)d"
    }

    static func isAging(_ thread: ChatThread, now: Date) -> Bool {
        label(for: thread, now: now) != nil
    }
}

enum ThreadStackOrdering {
    static func ordered(_ threads: [ChatThread], now: Date? = nil) -> [ChatThread] {
        threads.sorted { left, right in
            let leftState = left.threadStackState
            let rightState = right.threadStackState
            if leftState.sortRank != rightState.sortRank {
                return leftState.sortRank < rightState.sortRank
            }
            if leftState == .completed, let now {
                let leftAging = ThreadStackAging.isAging(left, now: now)
                let rightAging = ThreadStackAging.isAging(right, now: now)
                if leftAging != rightAging {
                    return !leftAging
                }
            }
            if left.updatedAt != right.updatedAt {
                return left.updatedAt > right.updatedAt
            }
            if left.createdAt != right.createdAt {
                return left.createdAt > right.createdAt
            }
            return left.id < right.id
        }
    }

    static func visible(_ threads: [ChatThread], now: Date) -> [ChatThread] {
        ordered(threads, now: now).filter { !ThreadStackAging.isExpired($0, now: now) }
    }

    static func active(_ threads: [ChatThread]) -> [ChatThread] {
        ordered(threads).filter { !$0.phase.isArchived }
    }

    static func archived(_ threads: [ChatThread]) -> [ChatThread] {
        ordered(threads).filter(\.phase.isArchived)
    }
}

struct ThreadStackPage: Equatable {
    let index: Int
    let pageCount: Int
    let rows: [ChatThread]
    let earlierCount: Int
    let moreCount: Int

    var hasEarlier: Bool { earlierCount > .zero }
    var hasMore: Bool { moreCount > .zero }
}

enum ThreadStackPaging {
    static let pageSize = 7

    static func page(
        _ threads: [ChatThread],
        at requestedIndex: Int,
        pageSize: Int = pageSize
    ) -> ThreadStackPage {
        let size = max(1, pageSize)
        let pageCount = max(1, Int(ceil(Double(threads.count) / Double(size))))
        let index = min(max(0, requestedIndex), pageCount - 1)
        let start = min(index * size, threads.count)
        let end = min(start + size, threads.count)
        return ThreadStackPage(
            index: index,
            pageCount: pageCount,
            rows: Array(threads[start..<end]),
            earlierCount: start,
            moreCount: max(0, threads.count - end)
        )
    }

    static func pages(_ threads: [ChatThread], pageSize: Int = pageSize) -> [ThreadStackPage] {
        let count = max(1, Int(ceil(Double(threads.count) / Double(max(1, pageSize)))))
        return (0..<count).map { page(threads, at: $0, pageSize: pageSize) }
    }
}

struct ThreadStackSelectionState: Equatable {
    private(set) var expandedThreadID: String?

    mutating func open(_ threadID: String) {
        expandedThreadID = threadID
    }

    mutating func toggle(_ threadID: String) {
        expandedThreadID = expandedThreadID == threadID ? nil : threadID
    }

    mutating func collapse() {
        expandedThreadID = nil
    }
}

enum ThreadStackLayoutPolicy {
    static func isCompact(availableWidth: CGFloat) -> Bool {
        availableWidth < KStyle.chatRegularLayoutMinimumWidth
    }
}

enum ChatComposerSurface: Equatable {
    case compactOverlay
    case regularWidth
}

enum ChatComposerSlot: Equatable {
    case trunk
    case branch(String)
}

enum ChatComposerKeyboardAnchor: Equatable {
    case bottom
}

enum ChatComposerSlotPolicy {
    static func resolve(
        expandedThreadID: String?,
        surface: ChatComposerSurface
    ) -> ChatComposerSlot {
        guard let expandedThreadID = expandedThreadID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !expandedThreadID.isEmpty
        else { return .trunk }

        switch surface {
        case .compactOverlay, .regularWidth:
            return .branch(expandedThreadID)
        }
    }

    static func usesBottomSafeAreaInset(for surface: ChatComposerSurface) -> Bool {
        switch surface {
        case .compactOverlay, .regularWidth:
            return true
        }
    }

    static func hardwareKeyboardAnchor(for surface: ChatComposerSurface) -> ChatComposerKeyboardAnchor {
        switch surface {
        case .compactOverlay, .regularWidth:
            return .bottom
        }
    }
}

struct ChatShellLayoutMetrics: Equatable {
    var contentWidth: CGFloat
    var trunkWidth: CGFloat

    static func resolve(availableWidth: CGFloat) -> ChatShellLayoutMetrics {
        let contentWidth = max(.zero, availableWidth - KStyle.columnMargin * 2)
        let reserved = KStyle.chatReservedLeadingWidth
            + KStyle.chatThreadStackWidth
            + KStyle.chatShellColumnGap * 2
        let trunkWidth = min(
            KStyle.readingMeasureMaxWidth,
            max(KStyle.columnMinWidth, contentWidth - reserved)
        )
        return ChatShellLayoutMetrics(contentWidth: contentWidth, trunkWidth: trunkWidth)
    }
}

enum ThreadStackHistoryAudit {
    static func appendedMessageIDs(before: [Message], after: [Message]) -> [UUID]? {
        guard after.count >= before.count,
              Array(after.prefix(before.count)).map(\.id) == before.map(\.id)
        else { return nil }
        return Array(after.dropFirst(before.count)).map(\.id)
    }
}

enum ChatThreadActionGate {
    static func governedBuildPacket(for thread: ChatThread) -> ViewPacket? {
        guard thread.phase == .finished,
              let packet = thread.actionPacket,
              let action = packet.action,
              action.tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "[gate:human]"
        else { return nil }
        let type = [action.kind, action.intent]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        return type.contains("build") ? packet : nil
    }
}

enum ChatThreadCloseComposer {
    static func why(for verdict: CSKChatBranchVerdict, thread: ChatThread) -> String {
        if verdict == .keep,
           let conclusion = thread.history.last(where: { $0.role == .k && !$0.text.isEmpty })?.text {
            let oneLine = conclusion
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !oneLine.isEmpty { return String(oneLine.prefix(240)) }
        }
        return verdict == .keep
            ? "the founder resolved this thread in chat."
            : "the founder archived this thread from chat."
    }

    static func transcript(for thread: ChatThread) -> [CSKChatBranchTranscriptTurn] {
        thread.history.map { message in
            CSKChatBranchTranscriptTurn(
                id: message.id.uuidString,
                role: message.role == .you ? "user" : "assistant",
                content: message.text,
                eventAt: ISO8601DateFormatter().string(from: message.createdAt)
            )
        }
    }
}

enum ChatThreadStatusComposer {
    static func finished(_ text: String) -> String {
        let oneLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine?.isEmpty == false ? oneLine! : KCopy.chatReadyToExplore
    }
}

enum ChatThreadActionError: LocalizedError, Equatable {
    case missingHumanGate

    var errorDescription: String? {
        ChatThreadCopy.buildGateMissing
    }
}

struct ThreadStack: View {
    let threads: [ChatThread]
    /// Audit fixtures provide a seed anchor. Live chat leaves this nil so the
    /// timeline can age rows against the wall clock.
    let now: Date? = nil
    let queuedMessages: [QueuedChatMessage]
    let pendingCloseThreadIDs: Set<String>
    @Binding var expandedThreadID: String?
    let isCompact: Bool
    let archiveConfirmationID: String?
    let onResolve: (ChatThread) -> Void
    let onLater: (ChatThread) -> Void
    let onArchive: (ChatThread) -> Void
    let onBuild: (ChatThread, ViewPacket) -> Void
    let onBuildHandoff: () -> Void
    let onDropQueued: (UUID) -> Void
    let onRetry: (ChatThread) -> Void
    /// The selected branch carries its composer with the reading surface.
    /// The trunk keeps the shell's safe-area composer.
    let branchComposer: AnyView?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }
    @State private var pageIndex = 0

    private var fixedFixtureNow: Date? {
        if W31ChatThreadFixture.isEnabled() {
            return W31ChatThreadFixture.referenceNow
        }
        if W30ChatRailFixture.isEnabled() {
            return W30ChatRailFixture.referenceNow
        }
        if ChatDemoFixture.isEnabled() || ChatBranchMotionFixture.isEnabled() {
            return ChatBranchMotionFixture.fixtureNow
        }
        return nil
    }

    var body: some View {
        VStack(spacing: .zero) {
            timelineContent
                .animation(
                    KStyle.chatStructureMotion(reduceMotion),
                    value: threads.map {
                        "\($0.id):\($0.phase.rawValue):\($0.buildState.rawValue):\($0.stepEvents.map(\.id).joined(separator: ","))"
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat-thread-stack")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-rail")
    }

    @ViewBuilder
    private var timelineContent: some View {
        if let fixedNow = now ?? fixedFixtureNow {
            stackContent(now: fixedNow)
        } else {
            TimelineView(.periodic(from: Date(), by: KStyle.cadenceNowTickInterval)) { context in
                stackContent(now: context.date)
            }
        }
    }

    @ViewBuilder
    private func stackContent(now: Date) -> some View {
        let visible = ThreadStackOrdering.visible(threads, now: now)
        if isCompact {
            compactStack(threads: visible, now: now)
        } else {
            regularStack(threads: visible, now: now)
        }
    }

    private func regularStack(threads: [ChatThread], now: Date) -> some View {
        let page = ThreadStackPaging.page(threads, at: pageIndex)
        return VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            stackHeading(KCopy.chatThreadsHeading)
            if threads.isEmpty {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("chat-thread-rail-empty")
            }
            if page.hasEarlier {
                pageCounter("+\(page.earlierCount) earlier", direction: .earlier, targetPage: page.index - 1)
            }
            pageRows(page.rows, compact: false, now: now)
            if page.hasMore {
                pageCounter("+\(page.moreCount) more", direction: .more, targetPage: page.index + 1)
            }
        }
        .frame(width: KStyle.chatThreadStackWidth, alignment: .topTrailing)
    }

    private func compactStack(threads: [ChatThread], now: Date) -> some View {
        let page = ThreadStackPaging.page(threads, at: pageIndex)
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: KStyle.smallSpacing) {
                if threads.isEmpty {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("chat-thread-rail-empty")
                }
                if page.hasEarlier {
                    pageCounter("+\(page.earlierCount) earlier", direction: .earlier, targetPage: page.index - 1)
                }
                ForEach(page.rows) { thread in
                    RailRowProjection(
                        thread: thread,
                        ageNote: ThreadStackAging.label(for: thread, now: now),
                        onToggle: {
                            guard !thread.phase.isArchived else { return }
                            withAnimation(KStyle.chatThreadSwapMotion(reduceMotion, phase: .threadEnter)) {
                                expandedThreadID = thread.id
                            }
                        }
                    )
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("chat-thread-rail-row-\(thread.id)")
                }
                if page.hasMore {
                    pageCounter("+\(page.moreCount) more", direction: .more, targetPage: page.index + 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, KStyle.columnMargin)
            .padding(.trailing, KStyle.columnMargin)

            if expandedThreadID != nil {
                compactSheet(now: now)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    @ViewBuilder
    private func compactSheet(now: Date) -> some View {
        if let id = expandedThreadID,
           let thread = threads.first(where: { $0.id == id }) {
            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(KStyle.chatThreadSwapMotion(reduceMotion, phase: .trunkExit)) {
                            expandedThreadID = nil
                        }
                    }

                ChatThreadCard(
                    thread: thread,
                    queuedMessages: queuedMessages.filter { $0.branchID == thread.id },
                    branchComposer: branchComposer,
                    expanded: true,
                    ageNote: ThreadStackAging.label(for: thread, now: now),
                    closePending: pendingCloseThreadIDs.contains(thread.id),
                    archiveConfirming: archiveConfirmationID == thread.id,
                    onToggle: {
                        withAnimation(KStyle.chatThreadSwapMotion(reduceMotion, phase: .trunkExit)) {
                            expandedThreadID = nil
                        }
                    },
                    onResolve: { onResolve(thread) },
                    onLater: { onLater(thread) },
                    onArchive: { onArchive(thread) },
                    onBuild: { packet in onBuild(thread, packet) },
                    onBuildHandoff: onBuildHandoff,
                    onDropQueued: onDropQueued,
                    onRetry: { onRetry(thread) }
                )
                .id(ChatScrollAnchorLogic.context(for: thread.id))
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(KStyle.columnMargin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .preferredColorScheme(.dark)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func stackHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .kFont(.monoCaption)
            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
            .accessibilityAddTraits(.isHeader)
    }

    private func pageRows(_ threads: [ChatThread], compact: Bool, now: Date) -> some View {
        ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
            card(thread, compact: compact, now: now)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat-thread-rail-row-\(thread.id)")
                .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                .animation(
                    reduceMotion
                        ? nil
                        : KStyle.chatStructureMotion(reduceMotion)?.delay(Double(index) * KStyle.chatThreadPageStaggerInterval),
                    value: pageIndex
                )
        }
    }

    private enum PageDirection { case more, earlier }

    private func pageCounter(_ title: String, direction: PageDirection, targetPage: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : KStyle.gesturePageTransitionMotion(false)) {
                pageIndex = targetPage
            }
        } label: {
            Text(title)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(direction == .more ? "chat-thread-rail-more" : "chat-thread-rail-earlier")
    }

    @ViewBuilder
    private func card(_ thread: ChatThread, compact: Bool, now: Date) -> some View {
        let expanded = expandedThreadID == thread.id
        let width = compact
            ? (expanded ? KStyle.chatThreadExpandedWidth : KStyle.chatCompactThreadWidth)
            : (expanded ? KStyle.chatThreadExpandedWidth : KStyle.chatThreadStackWidth)
        ZStack(alignment: .trailing) {
            Group {
                if expanded {
                    ChatThreadCard(
                    thread: thread,
                    queuedMessages: queuedMessages.filter { $0.branchID == thread.id },
                    branchComposer: branchComposer,
                    expanded: true,
                    ageNote: ThreadStackAging.label(for: thread, now: now),
                    closePending: pendingCloseThreadIDs.contains(thread.id),
                    archiveConfirming: archiveConfirmationID == thread.id,
                    onToggle: {
                        guard !thread.phase.isArchived else { return }
                        withAnimation(KStyle.chatThreadSwapMotion(reduceMotion, phase: .trunkExit)) {
                            expandedThreadID = nil
                        }
                    },
                    onResolve: { onResolve(thread) },
                    onLater: { onLater(thread) },
                    onArchive: { onArchive(thread) },
                    onBuild: { packet in onBuild(thread, packet) },
                    onBuildHandoff: onBuildHandoff,
                    onDropQueued: onDropQueued,
                    onRetry: { onRetry(thread) }
                    )
                } else {
                    RailRowProjection(
                        thread: thread,
                        ageNote: ThreadStackAging.label(for: thread, now: now),
                        onToggle: {
                            guard !thread.phase.isArchived else { return }
                            withAnimation(KStyle.chatThreadSwapMotion(reduceMotion, phase: .threadEnter)) {
                                expandedThreadID = thread.id
                            }
                        }
                    )
                }
            }
            // Keep the v21 row hit floor after removing row-level text acts;
            // resolve belongs to the verdict row, not this name-plus-dot rail.
            .frame(minHeight: KStyle.minimumTapTarget, alignment: .trailing)
            .frame(width: width, alignment: .trailing)

            if !compact, expanded {
                // Doctrine spatial-continuity: the selected origin keeps its
                // title and state dot while the dark branch surface travels.
                ThreadRailOrigin(
                    thread: thread,
                    ageNote: ThreadStackAging.label(for: thread, now: now),
                    accessibilityIdentifier: "chat-thread-origin-\(thread.id)"
                )
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
        .id(ChatScrollAnchorLogic.context(for: thread.id))
        .frame(width: width, alignment: .trailing)
        .offset(x: !compact && expanded ? -(KStyle.chatThreadExpandedWidth - KStyle.chatThreadStackWidth) : .zero)
        .zIndex(expanded ? 1 : 0)
        // v21 travel owns the selected card's staged enter/exit; paging keeps its
        // own gesture motion above, but selection never falls back to 400 ms.
        .animation(
            KStyle.chatThreadSwapMotion(
                reduceMotion,
                phase: expanded ? .threadEnter : .trunkExit
            ),
            value: expanded
        )
    }
}

/// The resting rail projection: a quiet name, optional expiry note, and one
/// four-state dot. Lifecycle copy and acts belong to the expanded thread.
private struct RailRowProjection: View {
    let thread: ChatThread
    let ageNote: String?
    let onToggle: () -> Void

    private var stateDotColor: Color {
        switch thread.threadStackState {
        case .completed, .processing:
            return KStyle.liveSignal
        case .needsYou:
            return KStyle.signalWarning
        case .failed:
            return KStyle.signalFailure
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                Text(thread.title)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .lineLimit(KStyle.singleLineLimit)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)

                if let ageNote {
                    Text(ageNote)
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ageNote)
                        .accessibilityIdentifier("chat-thread-rail-aging-\(thread.id)")
                }

                Spacer(minLength: KStyle.smallSpacing)

                ThreadStatusDot(
                    processing: thread.threadStackState == .processing || thread.threadStackState == .needsYou,
                    color: stateDotColor
                )
                .accessibilityHidden(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("thread status")
                .accessibilityValue(thread.threadStackState.rawValue)
                .accessibilityIdentifier("chat-thread-rail-status-\(thread.id)")
            }
            .padding(.horizontal, KStyle.smallSpacing)
            .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(thread.phase.isArchived ? [] : .isButton)
        .accessibilityHint(KCopy.chatExpandThreadHint)
        .accessibilityIdentifier("chat-thread-collapse-\(thread.id)")
        .opacity(ageNote != nil || thread.visualState == .resolved
            ? KStyle.secondaryTextOpacity
            : KStyle.fullOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-\(thread.id)")
    }
}

private struct ThreadRailOrigin: View {
    let thread: ChatThread
    let ageNote: String?
    let accessibilityIdentifier: String

    private var stateDotColor: Color {
        switch thread.threadStackState {
        case .completed, .processing:
            return KStyle.liveSignal
        case .needsYou:
            return KStyle.signalWarning
        case .failed:
            return KStyle.signalFailure
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: KStyle.smallSpacing) {
            Text(thread.title)
                .font(KStyle.blockDefaultTitleFont)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity))
                .lineLimit(KStyle.singleLineLimit)
                .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)

            if let ageNote {
                Text(ageNote)
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity))
                    .lineLimit(KStyle.singleLineLimit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ageNote)
                    .accessibilityIdentifier("chat-thread-rail-aging-\(thread.id)")
            }

            Spacer(minLength: KStyle.smallSpacing)

            ThreadStatusDot(
                processing: thread.threadStackState == .processing || thread.threadStackState == .needsYou,
                color: stateDotColor
            )
            .accessibilityHidden(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("thread status")
            .accessibilityValue(thread.threadStackState.rawValue)
            .accessibilityIdentifier("chat-thread-origin-status-\(thread.id)")
        }
        .padding(.horizontal, KStyle.smallSpacing)
        .frame(width: KStyle.chatThreadStackWidth, alignment: .leading)
        .frame(minHeight: KStyle.minimumTapTarget)
        .kPaperCardTone()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ChatThreadCard: View {
    let thread: ChatThread
    let queuedMessages: [QueuedChatMessage]
    let branchComposer: AnyView?
    let expanded: Bool
    let ageNote: String?
    let closePending: Bool
    let archiveConfirming: Bool
    let onToggle: () -> Void
    let onResolve: () -> Void
    let onLater: () -> Void
    let onArchive: () -> Void
    let onBuild: (ViewPacket) -> Void
    let onBuildHandoff: () -> Void
    let onDropQueued: (UUID) -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }
    @State private var historyContentHeight: CGFloat = .zero
    @State private var historyHasAnchored = false
    @State private var isDetailExpanded = false
    @State private var messageStage = 2
    @State private var messageTravelTask: Task<Void, Never>?

    private var usesPaperTone: Bool {
        !expanded && thread.usesPaperTone
    }

    private var primaryColor: Color {
        usesPaperTone
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
            : Color.white.opacity(KStyle.primaryTextOpacity)
    }

    private var secondaryColor: Color {
        usesPaperTone
            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
            : Color.white.opacity(KStyle.quaternaryTextOpacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            summary

            if expanded {
                history
                    .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))

                if let branchComposer {
                    branchComposer
                        .padding(.top, KStyle.smallSpacing)
                        .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("chat-branch-composer-\(thread.id)")
                }
            }
        }
        .padding(KStyle.cardLargePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .shadow(
            color: Color.black.opacity(expanded ? KStyle.chatThreadCardShadowOpacity : .zero),
            radius: expanded ? KStyle.chatThreadCardShadowRadius : .zero,
            y: expanded ? KStyle.chatThreadCardShadowY : .zero
        )
        .opacity(ageNote != nil || thread.visualState == .resolved
            ? KStyle.secondaryTextOpacity
            : KStyle.fullOpacity)
        .contentShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
        // Doctrine spatial-continuity + honest-motion: the card and its history
        // resolve through the same anchored branch transition.
        .animation(
            KStyle.chatThreadSwapMotion(
                reduceMotion,
                phase: expanded ? .threadEnter : .trunkExit
            ),
            value: expanded
        )
        .animation(KStyle.chatStructureMotion(reduceMotion), value: thread.phase)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded { isDetailExpanded = false }
            scheduleMessageTravel()
        }
        .onAppear {
            scheduleMessageTravel()
        }
        .onDisappear {
            messageTravelTask?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-\(thread.id)")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            head

            if thread.isOpen, let nextAction = thread.nextActionText {
                KMonoCaption(nextAction, variant: .metadata)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(KStyle.singleLineLimit)
                    .accessibilityIdentifier("chat-thread-next-action-\(thread.id)")
            }

            stateSummary

            if expanded {
                detailDisclosure
            }
        }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text(thread.title)
                        .font(KStyle.blockDefaultTitleFont)
                        .foregroundStyle(primaryColor)
                        .lineLimit(KStyle.singleLineLimit)
                        .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)

                    if let ageNote {
                        Text(ageNote)
                            .kFont(.monoCaption)
                            .foregroundStyle(secondaryColor)
                            // The rail walk verifies this copy as its own child,
                            // rather than relying on a parent row label.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ageNote)
                            .accessibilityIdentifier("chat-thread-rail-aging-\(thread.id)")
                    }

                    ThreadStatusDot(
                        processing: thread.threadStackState == .processing || thread.threadStackState == .needsYou,
                        color: expanded ? primaryColor : stateDotColor
                    )
                    // ThreadStatusDot hides its decorative shape by default. This
                    // rail projection is the semantic status child, so explicitly
                    // re-enable it before assigning the state contract.
                    .accessibilityHidden(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("thread status")
                    .accessibilityValue(thread.threadStackState.rawValue)
                    .accessibilityIdentifier("chat-thread-rail-status-\(thread.id)")
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: KStyle.minimumTapTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(thread.phase.isArchived ? [] : .isButton)
            .accessibilityHint(
                expanded ? KCopy.chatExpandedThreadHint : KCopy.chatExpandThreadHint
            )
            .accessibilityIdentifier("chat-thread-collapse-\(thread.id)")

            Spacer(minLength: KStyle.smallSpacing)

            if expanded {
                Button {
                    withAnimation(KStyle.chatThreadDetailMotion(reduceMotion)) {
                        isDetailExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(KStyle.monoCaptionFont)
                        .foregroundStyle(secondaryColor)
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDetailExpanded ? "collapse thread details" : "expand thread details")
                .accessibilityIdentifier("chat-thread-details-toggle-\(thread.id)")

                Button(action: onToggle) {
                    Text("✕")
                        .font(KStyle.monoCaptionFont)
                        .foregroundStyle(secondaryColor)
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KCopy.chatCollapse)
                .accessibilityIdentifier("chat-thread-close-\(thread.id)")
            }
        }
    }

    @ViewBuilder
    private var detailDisclosure: some View {
        let detail = thread.detail
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                ThreadMonoLine(
                    text: "born \(ChatTimestampFormatter.text(for: detail.bornAt)) · from trunk, \(detail.origin)",
                    color: secondaryColor
                )
                .accessibilityIdentifier("chat-thread-detail-born-\(thread.id)")
                ThreadMonoLine(
                    text: "\(detail.turnCount) turns · \(detail.verdictLine)",
                    color: secondaryColor
                )
                .accessibilityIdentifier("chat-thread-detail-turns-\(thread.id)")

                if !detail.sources.isEmpty {
                    Text("sources")
                        .kFont(.monoCaption)
                        .foregroundStyle(secondaryColor.opacity(KStyle.quaternaryTextOpacity))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("chat-thread-detail-sources-\(thread.id)")
                    ForEach(detail.sources) { source in
                        ThreadSourceTrace(source: source, color: secondaryColor)
                    }
                }
            }
            // The mock's disclosure is a real 0fr → 1fr track: keep the
            // receipt tree mounted, clip the collapsed track, and let the
            // shared zen motion resolve its height and opacity together.
            .frame(maxHeight: isDetailExpanded ? .infinity : .zero, alignment: .top)
            .opacity(isDetailExpanded ? KStyle.fullOpacity : .zero)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(KStyle.chatThreadDetailMotion(reduceMotion), value: isDetailExpanded)
        .accessibilityHidden(!isDetailExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-detail-\(thread.id)")
    }

    private var stateDotColor: Color {
        switch thread.threadStackState {
        case .completed, .processing:
            return KStyle.liveSignal
        case .needsYou:
            return KStyle.signalWarning
        case .failed:
            return KStyle.signalFailure
        }
    }

    @ViewBuilder
    private var stateSummary: some View {
        switch thread.visualState {
        case .building:
            if !thread.stepEvents.isEmpty {
                ThreadProcessingLine(
                    steps: thread.stepEvents,
                    processing: true,
                    showsDot: false,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    research: thread.researchSummary
                )
            }
        case .done:
            if let note = thread.errorText {
                ThreadMonoLine(text: note, color: secondaryColor)
            }
        case .staged:
            ThreadMonoLine(
                text: thread.buildState == .staging ? KCopy.chatBuildStaging : KCopy.chatBuildStaged,
                color: secondaryColor
            )
        case .resolved:
            EmptyView()
        case .queuedOffline:
            ThreadMonoLine(text: KCopy.queuedWillSync, color: secondaryColor)
        case .failed:
            if let errorText = thread.errorText {
                ThreadMonoLine(text: errorText, color: secondaryColor)
            }
            KActRow(
                actions: [
                    KActItem(
                        id: "retry",
                        label: thread.canRetry ? ChatThreadCopy.retry : ChatThreadCopy.parked,
                        isEnabled: thread.canRetry && !closePending,
                        accessibilityIdentifier: "chat-thread-retry-\(thread.id)"
                    ),
                ],
                variant: .admin,
                state: closePending ? .loading : .resting,
                onSelect: { _ in onRetry() }
            )
            .environment(\.kInkOnPaper, usesPaperTone)
        }
    }

    private var history: some View {
        let latestTarget = ChatScrollAnchorLogic.latestTarget(
            messages: thread.history,
            queuedMessages: queuedMessages
        )

        return VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            Rectangle()
                .fill(secondaryColor.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.hairlineWidth)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: .zero) {
                        historyEntries

                        if thread.buildState == .staged {
                            ThreadLifecycleEvent(text: ChatThreadCopy.stagedToBuild, color: secondaryColor)
                                .opacity(messageStage >= 2 ? KStyle.fullOpacity : .zero)
                                .animation(
                                    KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .messageSecond),
                                    value: messageStage
                                )
                        }

                        ForEach(queuedMessages) { item in
                            KStreamRow(role: .founder, accessibilityText: item.text) {
                                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                                    Text(item.text)
                                        .font(KStyle.contentFont)
                                        .foregroundStyle(secondaryColor)
                                        .fixedSize(horizontal: false, vertical: true)
                                    KActRow(
                                        actions: [
                                            KActItem(
                                                id: "drop",
                                                label: "drop",
                                                accessibilityIdentifier: "chat-thread-drop-queued-\(item.id.uuidString)"
                                            ),
                                        ],
                                        variant: .admin,
                                        onSelect: { _ in onDropQueued(item.id) }
                                    )
                                    .environment(\.kInkOnPaper, usesPaperTone)
                                    .accessibilityLabel(KCopy.chatDropQueuedReply)
                                }
                            }
                            .id(ChatScrollTarget.queued(item.id))
                            .accessibilityIdentifier("chat-thread-queued-\(item.id.uuidString)")
                        }

                        if thread.isConcluded,
                           let packet = ChatThreadActionGate.governedBuildPacket(for: thread) {
                            verdictRow(packet: packet)
                                .opacity(messageStage >= 2 ? KStyle.fullOpacity : .zero)
                                .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                                .animation(
                                    KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .messageSecond),
                                    value: messageStage
                                )
                        }

                        Color.clear
                            .frame(height: KStyle.hairlineWidth)
                            .id(ChatScrollTarget.bottom)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        historyContentHeight = height
                    }
                }
                .containerRelativeFrame(.vertical) { length, _ in
                    min(max(historyContentHeight, KStyle.hairlineWidth), length * KStyle.chatThreadHistoryMaxFraction)
                }
                .defaultScrollAnchor(.bottom)
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    anchorHistoryIfNeeded(using: proxy, target: latestTarget)
                }
                .onChange(of: historyContentHeight) { _, _ in
                    anchorHistoryIfNeeded(using: proxy, target: latestTarget)
                }
                .onChange(of: thread.history.map(\.id)) { _, _ in
                    historyHasAnchored = false
                }
                .onChange(of: queuedMessages.map(\.id)) { _, _ in
                    historyHasAnchored = false
                }
                .onDisappear {
                    historyHasAnchored = false
                }
            }
        }
        .animation(KStyle.chatHistoryAppendMotion(reduceMotion), value: thread.history.map(\.id))
        .animation(KStyle.chatChromeMotion(reduceMotion), value: thread.buildState)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-history-\(thread.id)")
    }

    private func anchorHistoryIfNeeded(using proxy: ScrollViewProxy, target: ChatScrollTarget) {
        guard !historyHasAnchored, historyContentHeight > .zero else { return }
        historyHasAnchored = true
        proxy.scrollTo(target, anchor: .bottom)
    }

    private func scheduleMessageTravel() {
        messageTravelTask?.cancel()

        guard expanded, !reduceMotion else {
            messageStage = 2
            return
        }

        // The two message reveals are absolute from the selection edge, not
        // delays relative to one another: 1050ms, then 1200ms.
        messageStage = .zero
        messageTravelTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(KStyle.chatThreadMessageFirstDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(false, phase: .messageFirst)) {
                messageStage = 1
            }

            let remaining = max(
                .zero,
                KStyle.chatThreadMessageSecondDelay - KStyle.chatThreadMessageFirstDelay
            )
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(false, phase: .messageSecond)) {
                messageStage = 2
            }
        }
    }

    private var historyEntries: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            ThreadLifecycleEvent(text: ChatThreadCopy.forkedFromTrunk, color: secondaryColor)

            ForEach(Array(thread.history.enumerated()), id: \.element.id) { index, message in
                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let stage = index == .zero ? 1 : 2
                    ThreadHistoryEntry(
                        message: message,
                        isFocused: isFocusedKMessage(index: index, message: message),
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor
                    )
                    .id(ChatScrollTarget.message(message.id))
                    .opacity(messageStage >= stage ? KStyle.fullOpacity : .zero)
                    .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                    .animation(
                        KStyle.chatThreadSwapSettledMotion(
                            reduceMotion,
                            phase: stage == 1 ? .messageFirst : .messageSecond
                        ),
                        value: messageStage
                    )
                }
            }

            if thread.phase == .processing || !thread.stepEvents.isEmpty {
                ThreadProcessingLine(
                    steps: thread.stepEvents,
                    processing: thread.phase == .processing,
                    showsDot: true,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    research: thread.researchSummary
                )
                .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
            } else if let research = thread.researchSummary {
                ThreadMonoLine(text: research.line, color: secondaryColor)
            }
        }
    }

    @ViewBuilder
    private func verdictRow(packet: ViewPacket) -> some View {
        if thread.buildState == .staged {
            HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                ThreadMonoLine(text: KCopy.chatBuildStaged, color: secondaryColor)
                Spacer(minLength: KStyle.smallSpacing)
                KOptionButton(
                    label: ChatThreadCopy.approveInBuild,
                    variant: .primaryFilled,
                    isEnabled: !closePending,
                    state: closePending ? .loading : .resting,
                    accessibilityIdentifier: "chat-thread-approve-\(thread.id)",
                    onSelect: { onBuild(packet) }
                )
                .environment(\.kInkOnPaper, usesPaperTone)

                resolveAction
            }
        } else {
            // KChatActionRow owns the visual grammar. Suffixing the emitted
            // action IDs keeps the pre-U2 per-thread accessibility hooks while
            // still letting packet-provided action IDs route through the same
            // canonical row.
            let actionSuffix = "-\(thread.id)"
            let actions = ChatThreadVerdictActions.items(for: packet).map { item in
                ChatNextActionItem(
                    id: item.id.hasSuffix(actionSuffix) ? item.id : item.id + actionSuffix,
                    label: item.label
                )
            }
            VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                KGlassCard(state: closePending ? .loading : .resting) {
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        KMonoCaption(ChatThreadCopy.traceComplete, variant: .metadata)
                            .foregroundStyle(secondaryColor)
                            .accessibilityIdentifier("chat-thread-verdict-anchor-\(thread.id)")
                        Text(ChatThreadCopy.stageQuestion(for: thread.title))
                            .font(KStyle.contentFont)
                            .foregroundStyle(primaryColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("chat-thread-verdict-question-\(thread.id)")
                    }
                }
                .frame(maxWidth: KStyle.readingMeasureMaxWidth, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat-thread-verdict-card-\(thread.id)")

                KChatActionRow(
                    actions: actions,
                    isActive: thread.buildState == .idle,
                    state: closePending ? .loading : .resting,
                    // Keep the legacy action identifiers (`chat-thread-build`,
                    // `chat-thread-later`, `chat-thread-archive`) on the
                    // canonical row's actual buttons.
                    accessibilityPrefix: "chat-thread",
                    onSelect: { item in
                        let actionID = item.id.hasSuffix(actionSuffix)
                            ? String(item.id.dropLast(actionSuffix.count))
                            : item.id
                        switch actionID {
                        case "junk", "archive":
                            onArchive()
                        case "later":
                            onLater()
                        case "stage-to-build", "build", "approve-in-build":
                            onBuild(packet)
                            onBuildHandoff()
                        default:
                            onBuild(packet)
                        }
                    }
                )
                .disabled(closePending)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat-thread-verdict-actions-\(thread.id)")

                resolveAction

                if let errorText = thread.errorText, thread.buildState == .failed {
                    ThreadMonoLine(text: errorText, color: secondaryColor)
                }
            }
        }
    }

    private var resolveAction: some View {
        KActRow(
            actions: [
                KActItem(
                    id: "resolve",
                    label: KCopy.chatResolve,
                    isEnabled: !closePending,
                    accessibilityIdentifier: "chat-thread-resolve-\(thread.id)"
                ),
            ],
            variant: .admin,
            state: closePending ? .loading : .resting,
            onSelect: { _ in onResolve() }
        )
        .environment(\.kInkOnPaper, usesPaperTone)
    }

    private var cardBackground: some View {
        let fill: Color
        let stroke: Color
        switch thread.visualState {
        case .building:
            fill = Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity)
            stroke = Color.white.opacity(KStyle.hairlineOpacity)
        case .done:
            fill = Color.white.opacity(KStyle.chatThreadFinishedFillOpacity)
            stroke = Color.white.opacity(KStyle.chatThreadFinishedFillOpacity)
        case .staged:
            fill = Color.white.opacity(KStyle.chatThreadFinishedFillOpacity)
            stroke = KStyle.nearBlack.opacity(KStyle.hairlineStrongOpacity)
        case .resolved:
            fill = Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity)
            stroke = Color.white.opacity(KStyle.hairlineOpacity)
        case .queuedOffline:
            fill = Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity)
            stroke = Color.white.opacity(KStyle.hairlineStrongOpacity)
        case .failed:
            fill = Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity)
            stroke = Color.white.opacity(KStyle.secondaryTextOpacity)
        }

        let expandedFill = expanded
            ? Color.black.opacity(KStyle.glassStrongOpacity)
            : fill
        let expandedStroke = expanded
            ? Color.white.opacity(KStyle.hairlineOpacity)
            : stroke

        return RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
            .fill(expandedFill.opacity(KStyle.fullOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(expandedStroke, lineWidth: KStyle.hairlineWidth)
            }
    }

    private func isFocusedKMessage(index: Int, message: Message) -> Bool {
        guard message.role == .k else { return false }
        return thread.history[index...].dropFirst().allSatisfy { $0.role != .k }
    }
}

private struct ThreadHistoryEntry: View {
    let message: Message
    let isFocused: Bool
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        KStreamRow(
            role: message.role == .you ? .founder : .k,
            accessibilityText: ChatMessageAccessibility.label(for: message)
        ) {
            if message.role == .you {
                Text(message.text)
                    .font(KStyle.contentFont)
                    .foregroundStyle(primaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                ThreadReplyText(
                    text: message.text,
                    primaryColor: isFocused
                        ? primaryColor.opacity(KStyle.chatThreadHistoryFocusOpacity)
                        : secondaryColor.opacity(KStyle.chatThreadHistoryDimOpacity),
                    secondaryColor: secondaryColor.opacity(KStyle.chatThreadHistoryDimOpacity)
                )
            }
        }
        .transition(.opacity)
    }
}

private struct ThreadReplyText: View {
    let text: String
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        let parts = ChatThreadReplyTextPresentation.split(text)
        return VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            Text(parts.lead)
                .font(KStyle.contentFont)
                .foregroundStyle(primaryColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let support = parts.support {
                Text(support)
                    .font(KStyle.contentFont)
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

private enum ChatThreadReplyTextPresentation {
    static func split(_ text: String) -> (lead: String, support: String?) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return ("", nil) }
        if let lineBreak = normalized.firstIndex(of: "\n") {
            let lead = normalized[..<lineBreak].trimmingCharacters(in: .whitespacesAndNewlines)
            let next = normalized.index(after: lineBreak)
            let support = normalized[next...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(lead), support.isEmpty ? nil : String(support))
        }
        for index in normalized.indices {
            guard ".?!".contains(normalized[index]),
                  index != normalized.index(before: normalized.endIndex)
            else { continue }
            let next = normalized.index(after: index)
            guard normalized[next].isWhitespace else { continue }
            let lead = normalized[..<next].trimmingCharacters(in: .whitespacesAndNewlines)
            let support = normalized[next...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(lead), support.isEmpty ? nil : String(support))
        }
        return (normalized, nil)
    }
}

private struct ThreadProcessingLine: View {
    let steps: [ChatThreadStep]
    let processing: Bool
    let showsDot: Bool
    let primaryColor: Color
    let secondaryColor: Color
    let research: ChatThreadResearchSummary?

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if !steps.isEmpty {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        if showsDot {
                            ThreadStatusDot(processing: processing, color: primaryColor)
                        }
                        Text(processing ? steps.last!.text : ChatThreadCopy.completedSteps(steps.count))
                            .kFont(.monoCaption)
                            .foregroundStyle(secondaryColor)
                            .lineLimit(KStyle.singleLineLimit)
                            .contentTransition(.opacity)
                            .id(steps.last!.id)
                        Spacer(minLength: KStyle.smallSpacing)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(KStyle.monoCaptionFont)
                            .foregroundStyle(secondaryColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "collapse steps" : "expand steps")
                .accessibilityIdentifier("chat-thread-steps")

                if isExpanded {
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        ForEach(steps) { step in
                            ThreadMonoLine(text: step.text, color: secondaryColor)
                        }
                    }
                    .padding(.leading, showsDot ? KStyle.chatThreadStatusDotSize + KStyle.smallSpacing : .zero)
                    .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                }
            } else if processing, showsDot {
                ThreadStatusDot(processing: true, color: primaryColor)
            }

            if let research {
                ThreadMonoLine(text: research.line, color: secondaryColor)
            }
        }
        .animation(KStyle.chatContentSwapMotion(reduceMotion), value: steps.map(\.id))
        .animation(KStyle.chatChromeMotion(reduceMotion), value: isExpanded)
    }
}

private struct ThreadLifecycleEvent: View {
    let text: String
    let color: Color

    var body: some View {
        ThreadMonoLine(text: text, color: color)
    }
}

private struct ThreadMonoLine: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.lowercased())
            .kFont(.monoCaption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .contentTransition(.opacity)
    }
}

private struct ThreadSourceTrace: View {
    let source: ChatThreadDetail.Source
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            if source.isLive {
                ThreadStatusDot(processing: true, color: color)
                    .frame(
                        width: KStyle.chatThreadStatusDotSize,
                        height: KStyle.chatThreadStatusDotSize
                    )
            }
            Text(source.label)
                .kFont(.monoCaption)
                .foregroundStyle(source.isLive ? color : color.opacity(KStyle.quaternaryTextOpacity))
                .lineLimit(KStyle.singleLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(source.label)
        .accessibilityValue(source.isLive ? "live" : "pulled")
        .accessibilityIdentifier("chat-thread-detail-source-\(source.id)")
    }
}

private struct ThreadStatusDot: View {
    let processing: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: KStyle.easeFastDuration)) { context in
            Circle()
                .fill(color)
                .transaction { transaction in transaction.animation = nil }
                .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
                .opacity(reduceMotion ? KStyle.fullOpacity : opacity(at: context.date))
        }
        .accessibilityHidden(true)
    }

    private func opacity(at date: Date) -> Double {
        guard processing else { return KStyle.fullOpacity }
        return KStyle.breathOpacity(
            at: date,
            period: KStyle.connectionSignalPeriod,
            minimumOpacity: KStyle.chatThreadDotMinimumOpacity
        )
    }
}
