import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Message: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case you, k }
    let id: UUID
    let role: Role
    var text: String
    var packet: ViewPacket?
    var termAnnotations: [TermAnnotation]?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case packet
        case termAnnotations
        case createdAt
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        packet: ViewPacket? = nil,
        termAnnotations: [TermAnnotation]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.packet = packet
        self.termAnnotations = termAnnotations
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        packet = try container.decodeIfPresent(ViewPacket.self, forKey: .packet)
        termAnnotations = try container.decodeIfPresent([TermAnnotation].self, forKey: .termAnnotations)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
    }
}

struct ChatThreadStore {
    static let defaultLimit = 200

    private struct StoredThread: Codable {
        var version: Int
        var messages: [Message]
        var lastSyncedAt: Date?
    }

    struct CachedThread: Equatable {
        var messages: [Message]
        var lastSyncedAt: Date
    }

    private let fileURL: URL
    private let limit: Int
    private let fileManager: FileManager

    init(
        fileURL: URL = ChatThreadStore.defaultFileURL(),
        limit: Int = ChatThreadStore.defaultLimit,
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
        return directory.appendingPathComponent("chat-thread.json", isDirectory: false)
    }

    func load() -> [Message] {
        loadEntry()?.messages ?? []
    }

    func loadEntry() -> CachedThread? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try JSONDecoder().decode(StoredThread.self, from: data)
            guard stored.version == 1 || stored.version == 2 else {
                NSLog("[K] chat thread unsupported version %d at %@", stored.version, fileURL.path)
                return nil
            }
            return CachedThread(
                messages: capped(stored.messages.map(ChatThoughtScrubber.scrubbed)),
                lastSyncedAt: stored.lastSyncedAt ?? fileModifiedAt()
            )
        } catch {
            NSLog("[K] chat thread load failed at %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    func save(_ messages: [Message], syncedAt: Date? = nil) {
        guard !messages.isEmpty else {
            clear()
            return
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stored = StoredThread(version: 2, messages: capped(messages), lastSyncedAt: syncedAt)
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] chat thread save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            NSLog("[K] chat thread clear failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func capped(_ messages: [Message]) -> [Message] {
        Array(messages.suffix(limit))
    }

    private func fileModifiedAt() -> Date {
        ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date) ?? Date(timeIntervalSince1970: 0)
    }
}

struct ChatUnreadStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "chat.lastSeenMessageTimestamp",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    func save(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct QueuedChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String
    var createdAt: Date
    var branchID: String?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), branchID: String? = nil) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        let normalizedBranchID = branchID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.branchID = normalizedBranchID?.isEmpty == false ? normalizedBranchID : nil
    }
}

struct ChatInputQueueState: Equatable, Codable, Sendable {
    private(set) var items: [QueuedChatMessage]

    init(items: [QueuedChatMessage] = []) {
        self.items = items.filter { !$0.text.isEmpty }
    }

    @discardableResult
    mutating func enqueue(
        _ text: String,
        branchID: String? = nil,
        now: Date = Date()
    ) -> QueuedChatMessage? {
        let item = QueuedChatMessage(text: text, createdAt: now, branchID: branchID)
        guard !item.text.isEmpty else { return nil }
        items.append(item)
        return item
    }

    mutating func nextForDispatch() -> QueuedChatMessage? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func drop(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func takeForEdit(id: UUID) -> String? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index).text
    }
}

struct ChatInputQueueStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "chat.inputQueue.v1",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> ChatInputQueueState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(ChatInputQueueState.self, from: data)
        else { return ChatInputQueueState() }
        return state
    }

    func save(_ state: ChatInputQueueState) {
        guard !state.items.isEmpty else {
            clear()
            return
        }
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

enum ChatUnreadLogic {
    static func latestKMessageTimestamp(in messages: [Message]) -> Date? {
        messages
            .filter { message in
                guard message.role == .k else { return false }
                return message.packet != nil || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map(\.createdAt)
            .max()
    }

    static func hasUnread(messages: [Message], lastSeen: Date?) -> Bool {
        guard let latest = latestKMessageTimestamp(in: messages) else { return false }
        guard let lastSeen else { return true }
        return latest > lastSeen
    }
}

struct ChatThreadStep: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let text: String
    let detail: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case detail
    }

    init(id: String? = nil, text: String, detail: String? = nil) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = normalized
        let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = normalizedDetail?.isEmpty == false ? normalizedDetail : nil
        if let id {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.id = trimmedID.isEmpty ? normalized : trimmedID
        } else {
            self.id = normalized
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            text: try container.decode(String.self, forKey: .text),
            detail: try container.decodeIfPresent(String.self, forKey: .detail)
        )
    }
}

struct ChatReasoningTrace: Equatable, Sendable {
    let durationSeconds: Int?
    let steps: [ChatThreadStep]

    var summaryLine: String {
        let duration = durationSeconds.map { "thought for \($0)s" }
        let count = "\(steps.count) steps"
        return (duration ?? "thought") + " · " + count
    }

    static func from(_ packet: ViewPacket) -> ChatReasoningTrace? {
        let fields = packet.fields ?? [:]
        let steps = ChatWorkerPacket.steps(in: fields, packet: packet)
        guard !steps.isEmpty else { return nil }
        let duration = ChatWorkerPacket.durationSeconds(in: fields, packet: packet)
        return ChatReasoningTrace(durationSeconds: duration, steps: steps)
    }
}

struct ChatReasoningTraceExpansionState: Equatable, Sendable {
    var isTraceExpanded = false
    var expandedStepID: String?

    mutating func toggleTrace() {
        isTraceExpanded.toggle()
        if !isTraceExpanded { expandedStepID = nil }
    }

    mutating func toggleStep(_ id: String) {
        expandedStepID = expandedStepID == id ? nil : id
    }
}

struct ChatWorkerPacket: Equatable, Sendable {
    let taskId: String
    let label: String
    let state: String
    let stepText: String?
    let stepEvents: [ChatThreadStep]
    let startedAt: String?
    let resultText: String?
    let noteText: String?
    let errorText: String?
    let branchID: String?

    init?(_ packet: ViewPacket) {
        guard packet.viewType == "chat.worker" else { return nil }
        let fields = packet.fields ?? [:]
        guard let taskId = Self.string(in: fields, packet: packet, keys: ["taskId", "task_id", "id"]) else {
            return nil
        }
        self.taskId = taskId
        label = Self.string(in: fields, packet: packet, keys: ["label", "title", "topic"])
            ?? packet.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "background work"
        state = Self.string(in: fields, packet: packet, keys: ["state", "status"]) ?? "working"
        stepText = Self.string(in: fields, packet: packet, keys: ["stepText", "step_text", "step"])
        stepEvents = Self.steps(in: fields, packet: packet)
        startedAt = Self.string(in: fields, packet: packet, keys: ["startedAt", "started_at"])
        resultText = Self.string(in: fields, packet: packet, keys: ["resultText", "result", "answer", "content"])
        noteText = Self.string(in: fields, packet: packet, keys: ["note", "notes", "resultNote", "result_note"])
        errorText = Self.string(
            in: fields,
            packet: packet,
            keys: ["errorText", "error_text", "error", "failure", "failureReason", "failure_reason"]
        )
        branchID = Self.string(in: fields, packet: packet, keys: ["branchId", "branch_id"])
    }

    var isTerminal: Bool {
        ["done", "complete", "completed", "failed", "failure", "error", "cancelled", "canceled"].contains(normalizedState)
    }

    var isFailed: Bool {
        ["failed", "failure", "error", "cancelled", "canceled"].contains(normalizedState)
    }

    func stateLine(now: Date = Date()) -> String {
        [labelPhrase, startedAgo(now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    var historyText: String {
        [stateLine(), stepText].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.joined(separator: "\n")
    }

    private var normalizedState: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var labelPhrase: String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "k is working" }
        if value.hasPrefix("k ") { return value }
        if value.hasPrefix("researching")
            || value.hasPrefix("building")
            || value.hasPrefix("checking")
            || value.hasPrefix("reading")
            || value.hasPrefix("writing") {
            return "k is \(value)"
        }
        return "k is working on \(value)"
    }

    private func startedAgo(now: Date) -> String? {
        guard let startedAt, let started = Self.date(from: startedAt) else {
            return startedAt == nil ? nil : "started"
        }
        let seconds = max(0, now.timeIntervalSince(started))
        if seconds < 60 { return "started now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "started \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "started \(hours)h ago" }
        return "started \(hours / 24)d ago"
    }

    private static func string(
        in fields: [String: ViewPacketJSONValue],
        packet: ViewPacket,
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = fields[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            if let value = packet.provenance[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    fileprivate static func steps(
        in fields: [String: ViewPacketJSONValue],
        packet: ViewPacket
    ) -> [ChatThreadStep] {
        let values = ["stepEvents", "step_events", "steps"].compactMap { key in
            fields[key] ?? packet.provenance[key]
        }
        for value in values {
            let events = value.arrayValue
                ?? value.objectValue?["events"]?.arrayValue
                ?? value.objectValue?["steps"]?.arrayValue
                ?? []
            let parsed = events.enumerated().compactMap { index, value -> ChatThreadStep? in
                if let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return ChatThreadStep(id: "step-\(index)", text: text)
                }
                guard let object = value.objectValue else { return nil }
                let text = ["text", "step", "label", "name", "title"]
                    .compactMap { object[$0]?.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                guard let text else { return nil }
                let id = ["id", "stepId", "step_id"]
                    .compactMap { object[$0]?.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                let detail = ["detail", "description", "content", "body"]
                    .compactMap { object[$0]?.description.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                return ChatThreadStep(id: id ?? "step-\(index)", text: text, detail: detail)
            }
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    fileprivate static func durationSeconds(
        in fields: [String: ViewPacketJSONValue],
        packet: ViewPacket
    ) -> Int? {
        let values = ["durationSeconds", "duration_seconds", "elapsedSeconds", "elapsed_seconds", "duration"]
            .compactMap { fields[$0] ?? packet.provenance[$0] }
        if let value = values.first, let seconds = value.doubleValue {
            return max(0, Int(seconds.rounded()))
        }
        let started = ["startedAt", "started_at"].compactMap { fields[$0] ?? packet.provenance[$0] }
            .compactMap { $0.stringValue }
            .compactMap(Self.date(from:))
            .first
        let finished = ["finishedAt", "finished_at", "completedAt", "completed_at", "endedAt", "ended_at"]
            .compactMap { fields[$0] ?? packet.provenance[$0] }
            .compactMap { $0.stringValue }
            .compactMap(Self.date(from:))
            .first
        guard let started, let finished else { return nil }
        return max(0, Int(finished.timeIntervalSince(started).rounded()))
    }

    private static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

enum ChatWorkerThreadReducer {
    @discardableResult
    static func upsert(
        _ packet: ViewPacket,
        in messages: inout [Message],
        preferredIndex: Int? = nil
    ) -> Int? {
        guard let worker = ChatWorkerPacket(packet) else { return nil }
        if let index = messages.firstIndex(where: { message in
            guard let packet = message.packet, let existing = ChatWorkerPacket(packet) else { return false }
            return existing.taskId == worker.taskId
        }) {
            messages[index].packet = packet
            messages[index].text = worker.historyText
            if let annotations = TermAnnotationsWireDecoder.annotations(from: packet.fields) {
                messages[index].termAnnotations = annotations
            }
            return index
        }

        if let preferredIndex,
           messages.indices.contains(preferredIndex),
           messages[preferredIndex].role == .k,
           messages[preferredIndex].packet == nil,
           messages[preferredIndex].text.isEmpty {
            messages[preferredIndex].packet = packet
            messages[preferredIndex].text = worker.historyText
            messages[preferredIndex].termAnnotations = TermAnnotationsWireDecoder.annotations(from: packet.fields)
            return preferredIndex
        }

        messages.append(Message(
            role: .k,
            text: worker.historyText,
            packet: packet,
            termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields)
        ))
        return messages.index(before: messages.endIndex)
    }

    @discardableResult
    static func applyPatch(_ patch: ViewPacketPatch, in messages: inout [Message]) -> Bool {
        for index in messages.indices {
            guard let packet = messages[index].packet else { continue }
            let patched = applyPacketPatch(patch, to: packet, logger: { _ in })
            guard patched != packet else { continue }
            messages[index].packet = patched
            if let worker = ChatWorkerPacket(patched) {
                messages[index].text = worker.historyText
            } else {
                messages[index].text = ViewPacketRenderer.visibleTextSequence(for: patched)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            return true
        }
        return false
    }
}

struct ChatDeltaFlushPlanner: Equatable {
    static let defaultInterval: TimeInterval = 0.1

    var interval: TimeInterval = Self.defaultInterval
    private(set) var lastFlushAt: Date?

    mutating func shouldFlush(after delta: String, at now: Date) -> Bool {
        guard let lastFlushAt else {
            self.lastFlushAt = now
            return true
        }
        if delta.contains("\n") || now.timeIntervalSince(lastFlushAt) >= interval {
            self.lastFlushAt = now
            return true
        }
        return false
    }

    mutating func markFlushed(at now: Date) {
        lastFlushAt = now
    }

    static func maximumFlushes(forDuration duration: TimeInterval, interval: TimeInterval = defaultInterval) -> Int {
        max(1, Int(ceil(max(0, duration) / interval)))
    }
}

@MainActor
final class ChatStreamingTextCoalescer {
    private var planner = ChatDeltaFlushPlanner()
    private var rendered = ""
    private var pending = ""
    private var flushTask: Task<Void, Never>?

    func reset(initialText: String = "") {
        flushTask?.cancel()
        flushTask = nil
        planner = ChatDeltaFlushPlanner()
        rendered = initialText
        pending = ""
    }

    func append(
        _ delta: String,
        at now: Date = Date(),
        apply: @escaping @MainActor (String) -> Void
    ) {
        guard !delta.isEmpty else { return }
        pending += delta
        if planner.shouldFlush(after: delta, at: now) {
            flush(at: now, apply: apply)
        } else {
            scheduleFlush(apply: apply)
        }
    }

    func finish(apply: @escaping @MainActor (String) -> Void) {
        flush(at: Date(), apply: apply)
        reset(initialText: rendered)
    }

    private func scheduleFlush(apply: @escaping @MainActor (String) -> Void) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            self?.flush(at: Date(), apply: apply)
        }
    }

    private func flush(
        at now: Date,
        apply: @escaping @MainActor (String) -> Void
    ) {
        guard !pending.isEmpty else { return }
        flushTask?.cancel()
        flushTask = nil
        rendered += pending
        pending = ""
        planner.markFlushed(at: now)
        apply(ChatThoughtScrubber.scrubbedText(rendered))
    }
}

typealias ChatLegacySender = (
    _ baseURL: String,
    _ text: String,
    _ history: [[String: String]],
    _ onToken: @escaping @MainActor (String) -> Void
) async throws -> CSKChatOutcome

/// Local-only sibling states for the W11 audit. Empty and unreachable stay
/// deterministic and never open the daemon path.
enum ChatSiblingDemo {
    enum State: String, Equatable {
        case empty
        case error
    }

    static var state: State? {
#if DEBUG
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-w11-chat-state"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1)
        else { return nil }
        return State(rawValue: ProcessInfo.processInfo.arguments[index + 1].lowercased())
#else
        return nil
#endif
    }

    static var isEnabled: Bool { state != nil }
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published private(set) var threads: [ChatThread] = []
    @Published var draft: String = ""
    @Published var sending = false
    @Published var footer: String = ""
    @Published private(set) var inputQueue: ChatInputQueueState
    @Published private(set) var attachment: ChatAttachmentMetadata?
    @Published private(set) var trunkThreadID: String
    @Published private(set) var pendingForkMessageIDs: Set<UUID> = []
    @Published private(set) var pendingHandoffAnchorIDs: Set<String> = []
    @Published private(set) var pendingCloseThreadIDs: Set<String> = []
    @Published var pendingActionPacketIDs: Set<String> = []
    @Published var actionErrorTexts: [String: String] = [:]
    @Published var connectionState = KConnectionStateModel()
    @Published var baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
        ?? "http://127.0.0.1:3003"

    private let threadStore: ChatThreadStore
    private let unreadStore: ChatUnreadStore
    private let inputQueueStore: ChatInputQueueStore
    private let branchThreadStore: ChatBranchThreadStore
    private let trunkIdentityStore: ChatTrunkIdentityStore
    private let attachmentStore: ChatAttachmentStore
    private let clientFactory: (String) -> AGUIClient
    private let chatClientFactory: (String) -> CSKChat
    private let legacySender: ChatLegacySender
    private let siblingAuditState: ChatSiblingDemo.State?
    private let censusFixtureEnabled: Bool
    private var actionReplyMessageIDs: [String: UUID] = [:]
    private var sendTask: Task<Void, Never>?
    private let legacyTextCoalescer = ChatStreamingTextCoalescer()
    private let branchTextCoalescer = ChatStreamingTextCoalescer()
    @Published private(set) var lastSeenMessageTimestamp: Date?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var isBranchesLoading = KLoadingPreview.isEnabled
    @Published private(set) var branchesErrorText: String?

    init(
        threadStore: ChatThreadStore = ChatThreadStore(),
        unreadStore: ChatUnreadStore = ChatUnreadStore(),
        inputQueueStore: ChatInputQueueStore = ChatInputQueueStore(),
        branchThreadStore: ChatBranchThreadStore = ChatBranchThreadStore(),
        trunkIdentityStore: ChatTrunkIdentityStore = ChatTrunkIdentityStore(),
        attachmentStore: ChatAttachmentStore = ChatAttachmentStore(),
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        chatClientFactory: @escaping (String) -> CSKChat = { CSKChat(baseURL: $0) },
        legacySender: @escaping ChatLegacySender = { baseURL, text, history, onToken in
            try await CSKChat(baseURL: baseURL).send(message: text, history: history, onToken: onToken)
        }
    ) {
        self.threadStore = threadStore
        self.unreadStore = unreadStore
        self.inputQueueStore = inputQueueStore
        self.branchThreadStore = branchThreadStore
        self.trunkIdentityStore = trunkIdentityStore
        self.attachmentStore = attachmentStore
        self.clientFactory = clientFactory
        self.chatClientFactory = chatClientFactory
        self.legacySender = legacySender
        siblingAuditState = ChatSiblingDemo.state
        censusFixtureEnabled = CensusRemainderFixture.isEnabled()
        inputQueue = inputQueueStore.load()
        attachment = attachmentStore.load()
        trunkThreadID = trunkIdentityStore.loadOrCreate()
        threads = branchThreadStore.load()
        lastSeenMessageTimestamp = unreadStore.load()
        if let cached = threadStore.loadEntry() {
            messages = cached.messages.map(Self.rehydrated)
            lastSyncedAt = cached.lastSyncedAt
            isStale = !messages.isEmpty
        }
        if let w31State = W31ChatThreadFixture.state {
            let fixture = W31ChatThreadFixture.snapshot(state: w31State)
            messages = fixture.messages
            threads = fixture.threads
            inputQueue = ChatInputQueueState()
            attachment = nil
            lastSeenMessageTimestamp = nil
            lastSyncedAt = W31ChatThreadFixture.referenceNow
            isStale = false
        } else if let w30State = W30ChatRailFixture.state {
            let fixture = W30ChatRailFixture.snapshot(state: w30State)
            messages = fixture.messages
            threads = fixture.threads
            inputQueue = ChatInputQueueState()
            attachment = nil
            lastSeenMessageTimestamp = nil
            lastSyncedAt = W30ChatRailFixture.referenceNow
            isStale = false
        } else if ChatDemoFixture.isEnabled() {
            let fixture = ChatDemoFixture.snapshot()
            messages = fixture.messages
            threads = fixture.threads
            inputQueue = ChatInputQueueState()
            attachment = nil
            lastSeenMessageTimestamp = nil
            lastSyncedAt = nil
            isStale = false
            if KLoadingPreview.isEnabled {
                // The reply-pending story is part of the seed: "I asked while
                // K was still loading" is a STATE, not a keyboard interaction,
                // and XCUI typing is the flakiest thing the rig does. Fixed
                // ids + fixture clock keep the walk deterministic.
                let fixtureNow = ChatBranchMotionFixture.fixtureNow
                messages.append(Message(
                    id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                    role: .you,
                    text: "hold while k loads",
                    createdAt: fixtureNow.addingTimeInterval(60)
                ))
                messages.append(Message(
                    id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                    role: .k,
                    text: "",
                    createdAt: fixtureNow.addingTimeInterval(61)
                ))
                sending = true
            }
        } else if ChatBranchMotionFixture.isEnabled() {
            let fixture = ChatBranchMotionFixture.snapshot()
            messages = fixture.messages
            threads = fixture.threads
            inputQueue = ChatInputQueueState()
            attachment = nil
            lastSeenMessageTimestamp = nil
            lastSyncedAt = nil
            isStale = false
        } else if let siblingState = siblingAuditState {
            messages = []
            threads = []
            draft = ""
            inputQueue = ChatInputQueueState()
            attachment = nil
            inputQueueStore.clear()
            attachmentStore.clear()
            lastSyncedAt = nil
            isStale = false
            if siblingState == .error {
                footer = KCopy.offlineRetrying
                branchesErrorText = KCopy.offlineRetrying
            }
        } else if censusFixtureEnabled {
            messages = CensusRemainderFixture.chatMessages
            threads = []
            draft = ""
            inputQueue = ChatInputQueueState()
            attachment = nil
            inputQueueStore.clear()
            attachmentStore.clear()
            lastSyncedAt = CensusRemainderFixture.referenceNow
            isStale = false
        }
    }

    var canStartNewChat: Bool {
        !messages.isEmpty && !sending && inputQueue.items.isEmpty && pendingActionPacketIDs.isEmpty
    }

    var isAuditFixtureEnabled: Bool {
        siblingAuditState != nil
            || censusFixtureEnabled
            || W30ChatRailFixture.isEnabled()
            || W31ChatThreadFixture.isEnabled()
    }

    var queuedMessages: [QueuedChatMessage] {
        inputQueue.items
    }

    var trunkMessages: [Message] {
        messages.filter { message in
            guard let packet = message.packet,
                  let worker = ChatWorkerPacket(packet)
            else { return true }
            return worker.branchID == nil
        }
    }

    var latestKMessageTimestamp: Date? {
        ChatUnreadLogic.latestKMessageTimestamp(in: messages)
    }

    var hasUnread: Bool {
        ChatUnreadLogic.hasUnread(messages: messages, lastSeen: lastSeenMessageTimestamp)
    }

    var stalenessText: String? {
        guard isStale, let lastSyncedAt else { return nil }
        return KTimestampFormatter.asOf(lastSyncedAt)
    }

    func persistBaseURL() {
        UserDefaults.standard.set(baseURL, forKey: "cskBaseURL")
    }

    func markVisibleInForeground() {
        guard let latestKMessageTimestamp else { return }
        if let lastSeenMessageTimestamp, lastSeenMessageTimestamp >= latestKMessageTimestamp {
            return
        }
        self.lastSeenMessageTimestamp = latestKMessageTimestamp
        unreadStore.save(latestKMessageTimestamp)
    }

    func saveThreadNow() {
        guard !ChatDemoFixture.isEnabled(), !ChatBranchMotionFixture.isEnabled(),
              !W31ChatThreadFixture.isEnabled(),
              !isAuditFixtureEnabled
        else { return }
        threadStore.save(messages, syncedAt: lastSyncedAt)
        inputQueueStore.save(inputQueue)
        branchThreadStore.save(threads)
        attachmentStore.save(attachment)
    }

    func startNewChat() {
        guard canStartNewChat else { return }
        messages = []
        draft = ""
        footer = ""
        pendingActionPacketIDs = []
        actionErrorTexts = [:]
        inputQueue = ChatInputQueueState()
        threads = []
        attachment = nil
        trunkThreadID = trunkIdentityStore.rotate()
        pendingForkMessageIDs = []
        pendingHandoffAnchorIDs = []
        pendingCloseThreadIDs = []
        actionReplyMessageIDs = [:]
        lastSyncedAt = nil
        isStale = false
        threadStore.clear()
        inputQueueStore.clear()
        branchThreadStore.clear()
        attachmentStore.clear()
    }

    func send() {
        send(targetBranchID: nil)
    }

    func send(targetBranchID: String?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Audit fixtures are local stories. Loading preview still exercises the
        // founder send/reply anatomy below; a non-loading fixture never opens a
        // daemon path. (Doctrine: staleness-honesty, silence-default.)
        if !KLoadingPreview.isEnabled,
           ChatDemoFixture.isEnabled()
            || ChatBranchMotionFixture.isEnabled()
            || W31ChatThreadFixture.isEnabled() {
            return
        }
        if let targetBranchID,
           !threads.contains(where: { $0.id == targetBranchID && $0.isOpen }) {
            footer = KCopy.chatClosedChooseTrunk
            return
        }
        draft = ""
        if sending {
            enqueue(text, branchID: targetBranchID)
            return
        }
        if let targetBranchID {
            startBranchSend(text, branchID: targetBranchID)
        } else {
            startSend(text)
        }
    }

    func drainInputQueueIfIdle() {
        dispatchNextQueuedMessageIfIdle()
    }

    func editQueuedMessage(id: UUID) {
        guard let text = inputQueue.takeForEdit(id: id) else { return }
        draft = text
        persistInputQueue()
    }

    func dropQueuedMessage(id: UUID) {
        inputQueue.drop(id: id)
        persistInputQueue()
    }

    private func enqueue(
        _ text: String,
        branchID: String? = nil,
        now: Date = Date(),
        markOffline: Bool = false
    ) {
        guard inputQueue.enqueue(text, branchID: branchID, now: now) != nil else { return }
        footer = KCopy.queuedWillSync
        if markOffline, let branchID {
            updateThread(branchID) { thread in
                thread.phase = .queuedOffline
                thread.statusText = KCopy.queuedWillSync
                thread.errorText = nil
                thread.updatedAt = now
            }
        }
        persistInputQueue()
    }

    private func startSend(_ text: String, createdAt: Date = Date()) {
        guard !sending else {
            enqueue(text)
            return
        }
        sending = true
        footer = ""
        connectionState.transition(to: .connecting)
        let founderMessage = Message(role: .you, text: text, createdAt: createdAt)
        let replyMessage = Message(role: .k, text: "", createdAt: createdAt)
        messages.append(founderMessage)
        messages.append(replyMessage)

        if KLoadingPreview.isEnabled { return }

        // Prior turns (excluding the just-appended pair) travel as bounded history.
        let history = messages.dropLast(2).suffix(20).map { message in
            ["role": message.role == .you ? "user" : "assistant", "content": message.text]
        }

        legacyTextCoalescer.reset()
        let agui = clientFactory(baseURL)
        sendTask = Task { [weak self] in
            guard let self else { return }
            var dispatchQueuedAfterFinish = true
            do {
                let outcome = try await agui.send(message: text, history: Array(history), onEvent: { [weak self] event in
                    guard let self else { return }
                    switch event {
                    case .snapshot:
                        break
                    case .packet(let packet):
                        self.connectionState.transition(to: .live)
                        self.markThreadLive()
                        self.upsertStreamPacket(packet, replyMessageID: replyMessage.id)
                    case .patch(let patch):
                        guard self.applyStreamPatch(patch, replyMessageID: replyMessage.id) else { return }
                        self.connectionState.transition(to: .live)
                        self.markThreadLive()
                    }
                })
                guard let packet = outcome.packet else {
                    throw AGUIClientError.stream("missing packet")
                }
                if let replyIndex = self.messageIndex(for: replyMessage.id),
                   self.messages[replyIndex].packet == nil {
                    self.upsertStreamPacket(packet, replyMessageID: replyMessage.id)
                }
                self.connectionState.transition(to: .live)
                self.markThreadLive()
                self.footer = statusLine(outcome)
            } catch is CancellationError {
                if let replyIndex = messageIndex(for: replyMessage.id),
                   messages[replyIndex].text.isEmpty {
                    messages.remove(at: replyIndex)
                }
                footer = KCopy.stopped
                connectionState.transition(to: .live)
                dispatchQueuedAfterFinish = false
            } catch {
                do {
                    let outcome = try await sendLegacy(
                        text: text,
                        history: Array(history),
                        replyMessageID: replyMessage.id
                    )
                    if let replyIndex = messageIndex(for: replyMessage.id),
                       messages[replyIndex].text.isEmpty {
                        messages[replyIndex].text = outcome.content
                    }
                    connectionState.transition(to: .live)
                    markThreadLive()
                    footer = statusLine(outcome)
                } catch is CancellationError {
                    if let replyIndex = messageIndex(for: replyMessage.id),
                       messages[replyIndex].text.isEmpty {
                        messages.remove(at: replyIndex)
                    }
                    footer = KCopy.stopped
                    connectionState.transition(to: .live)
                    dispatchQueuedAfterFinish = false
                } catch {
                    if moveTerminalFailureToInputQueue(
                        text: text,
                        founderMessageID: founderMessage.id,
                        replyMessageID: replyMessage.id,
                        createdAt: createdAt
                    ) {
                        dispatchQueuedAfterFinish = false
                    } else {
                        if let replyIndex = messageIndex(for: replyMessage.id),
                           messages[replyIndex].text.isEmpty {
                            messages.remove(at: replyIndex)
                        }
                        footer = KCopy.answerFailed(reason: error.localizedDescription)
                    }
                    connectionState.transition(to: .offlineRetrying)
                    isStale = !messages.isEmpty
                }
            }
            finishSend(dispatchQueued: dispatchQueuedAfterFinish)
        }
    }

    private func startBranchSend(
        _ text: String,
        branchID: String,
        createdAt: Date = Date(),
        isRetry: Bool = false
    ) {
        guard !sending,
              let thread = threads.first(where: { $0.id == branchID }),
              thread.isOpen
        else {
            enqueue(text, branchID: branchID, now: createdAt)
            return
        }

        sending = true
        footer = ""
        connectionState.transition(to: .connecting)
        let history = thread.history.suffix(20).map { message in
            ["role": message.role == .you ? "user" : "assistant", "content": message.text]
        }
        let founderMessage = Message(role: .you, text: text, createdAt: createdAt)
        let reply = Message(role: .k, text: "", createdAt: createdAt)
        updateThread(branchID) { thread in
            thread.history.append(founderMessage)
            thread.history.append(reply)
            thread.phase = .processing
            thread.statusText = KCopy.chatThinking
            thread.errorText = nil
            thread.stepEvents = []
            thread.retryText = text
            if !isRetry { thread.retryCount = nil }
            thread.updatedAt = createdAt
        }

        if KLoadingPreview.isEnabled { return }

        branchTextCoalescer.reset()
        let client = chatClientFactory(baseURL)
        sendTask = Task { [weak self] in
            guard let self else { return }
            var dispatchQueuedAfterFinish = true
            do {
                let outcome = try await client.send(
                    message: text,
                    history: Array(history),
                    branchId: branchID,
                    onToken: { [weak self] token in
                        guard let self else { return }
                        self.connectionState.transition(to: .live)
                        self.markThreadLive()
                        self.branchTextCoalescer.append(token) { [weak self] rendered in
                            self?.updateThreadReply(branchID: branchID, replyID: reply.id, text: rendered)
                        }
                    }
                )
                branchTextCoalescer.finish { [weak self] rendered in
                    self?.updateThreadReply(branchID: branchID, replyID: reply.id, text: rendered)
                }
                let currentText = threadMessage(branchID: branchID, messageID: reply.id)?.text ?? ""
                if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updateThreadReply(branchID: branchID, replyID: reply.id, text: outcome.content)
                }
                var completedNewResult = false
                let landedAt = Date()
                updateThread(branchID) { thread in
                    thread.phase = .finished
                    thread.statusText = ""
                    thread.actionPacket = outcome.packet
                    thread.errorText = thread.noteText
                    thread.retryText = nil
                    thread.retryCount = nil
                    thread.landedAt = landedAt
                    thread.updatedAt = landedAt
                    completedNewResult = true
                }
                if completedNewResult {
                    ChatThreadLifecycle.archiveSuperseded(&threads, newerID: branchID)
                }
                connectionState.transition(to: .live)
                markThreadLive()
                footer = statusLine(outcome)
            } catch is CancellationError {
                let landedAt = Date()
                updateThread(branchID) { thread in
                    if let index = thread.history.firstIndex(where: { $0.id == reply.id }),
                       thread.history[index].text.isEmpty {
                        thread.history.remove(at: index)
                    }
                    thread.phase = .finished
                    thread.statusText = KCopy.stopped
                    thread.landedAt = landedAt
                    thread.updatedAt = landedAt
                }
                footer = KCopy.stopped
                connectionState.transition(to: .live)
                dispatchQueuedAfterFinish = false
            } catch {
                let isOffline = Self.isOfflineError(error)
                updateThread(branchID) { thread in
                    thread.history.removeAll { $0.id == reply.id }
                    thread.retryText = text
                    if isOffline {
                        thread.phase = .queuedOffline
                        thread.statusText = KCopy.queuedWillSync
                        thread.errorText = nil
                    } else {
                        thread.phase = .failed
                        thread.statusText = ""
                        thread.errorText = KCopy.chatThreadFailed(reason: error.localizedDescription)
                    }
                    thread.updatedAt = Date()
                }
                if isOffline {
                    enqueue(text, branchID: branchID, now: createdAt, markOffline: true)
                    footer = KCopy.queuedWillSync
                } else {
                    footer = KCopy.chatThreadFailed(reason: error.localizedDescription)
                }
                connectionState.transition(to: .offlineRetrying)
                dispatchQueuedAfterFinish = false
            }
            finishSend(dispatchQueued: dispatchQueuedAfterFinish)
        }
    }

    func refreshBranches() {
        guard !ChatDemoFixture.isEnabled(),
              !ChatBranchMotionFixture.isEnabled(),
              !W31ChatThreadFixture.isEnabled()
        else {
            isBranchesLoading = false
            return
        }
        let trunkID = trunkThreadID
        isBranchesLoading = true
        branchesErrorText = nil
        if KLoadingPreview.isEnabled { return }
        Task { [weak self] in
            guard let self else { return }
            defer { isBranchesLoading = false }
            do {
                let branches = try await chatClientFactory(baseURL).listBranches(trunkThreadId: trunkID)
                for branch in branches {
                    if let index = threads.firstIndex(where: { $0.id == branch.id }) {
                        threads[index].reconcile(branch: branch)
                    } else {
                        threads.append(ChatThread(branch: branch))
                    }
                }
                branchThreadStore.save(threads)
            } catch {
                // Local branch history remains usable. A failed refresh must not
                // replace it with an empty or synthetic server state.
                if threads.isEmpty {
                    branchesErrorText = KCopy.offlineRetrying
                }
            }
        }
    }

    func branchID(forkedFrom messageID: UUID) -> String? {
        threads.first(where: { $0.forkMessageID == messageID.uuidString })?.id
    }

    func receive(_ handoff: ChatThreadHandoff) async -> String? {
        let anchorID = handoff.anchorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchorText = handoff.anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anchorID.isEmpty, !anchorText.isEmpty else { return nil }

        if let existing = threads.first(where: { $0.forkMessageID == anchorID && $0.isOpen }) {
            sendHandoffComment(handoff.initialComment, to: existing.id)
            return existing.id
        }
        guard !pendingHandoffAnchorIDs.contains(anchorID) else { return nil }

        pendingHandoffAnchorIDs.insert(anchorID)
        defer { pendingHandoffAnchorIDs.remove(anchorID) }
        do {
            let branch = try await chatClientFactory(baseURL).fork(
                trunkThreadId: trunkThreadID,
                forkMessageId: anchorID,
                forkMessage: anchorText,
                entities: handoff.entities
            )
            let anchor = Message(role: .k, text: anchorText)
            let thread = ChatThread(branch: branch, anchor: anchor)
            threads.removeAll { $0.id == branch.id }
            threads.append(thread)
            branchThreadStore.save(threads)
            footer = KCopy.chatBranched
            sendHandoffComment(handoff.initialComment, to: branch.id)
            return branch.id
        } catch {
            if let comment = handoff.initialComment {
                draft = comment
            }
            footer = KCopy.chatThreadFailed(reason: error.localizedDescription)
            return nil
        }
    }

    func fork(_ message: Message) async -> String? {
        if let existing = branchID(forkedFrom: message.id) { return existing }
        let forkText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .k, !forkText.isEmpty,
              !pendingForkMessageIDs.contains(message.id)
        else { return nil }

        pendingForkMessageIDs.insert(message.id)
        defer { pendingForkMessageIDs.remove(message.id) }
        let entities = message.packet.map { packet in
            EntityRef.unique(
                EntityRef.inObject(packet.fields ?? [:]) + EntityRef.inObject(packet.provenance)
            ).map(\.jsonValue)
        } ?? []

        do {
            let branch = try await chatClientFactory(baseURL).fork(
                trunkThreadId: trunkThreadID,
                forkMessageId: message.id.uuidString,
                forkMessage: forkText,
                entities: entities
            )
            let thread = ChatThread(branch: branch, anchor: message)
            threads.removeAll { $0.id == branch.id }
            threads.append(thread)
            branchThreadStore.save(threads)
            footer = KCopy.chatBranched
            return branch.id
        } catch {
            footer = KCopy.chatThreadFailed(reason: error.localizedDescription)
            return nil
        }
    }

    func createThread(from turnID: UUID) async -> String? {
        guard let message = messages.first(where: { $0.id == turnID }) else { return nil }
        return await fork(message)
    }

    private func sendHandoffComment(_ comment: String?, to branchID: String) {
        guard let normalized = comment?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty
        else { return }
        draft = normalized
        send(targetBranchID: branchID)
    }

    func retainAttachment(_ url: URL) {
        do {
            let retained = try ChatAttachmentMetadata.retaining(url)
            attachment = retained
            attachmentStore.save(retained)
            footer = KCopy.chatAttachmentSelected(retained.filename)
        } catch {
            footer = KCopy.chatAttachmentFailed(reason: error.localizedDescription)
        }
    }

    func markThreadLater(_ threadID: String) {
        updateThread(threadID) { thread in
            thread.statusText = KCopy.chatLater
            thread.updatedAt = Date()
        }
    }

    func retryThread(_ threadID: String) {
        guard !sending,
              let thread = threads.first(where: { $0.id == threadID }),
              thread.phase == .failed,
              ChatThreadLifecycle.canRetry(thread),
              let text = thread.retryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }

        inputQueue.items
            .filter { $0.branchID == threadID && $0.text == text }
            .forEach { inputQueue.drop(id: $0.id) }
        persistInputQueue()

        updateThread(threadID) { thread in
            thread.history.removeAll { message in
                message.role == .you && message.text == text
            }
            thread.phase = .processing
            thread.statusText = KCopy.chatThinking
            thread.errorText = nil
            thread.retryCount = 1
            thread.updatedAt = Date()
        }
        startBranchSend(text, branchID: threadID, createdAt: Date(), isRetry: true)
    }

    func closeThread(_ threadID: String, verdict: CSKChatBranchVerdict) async -> Bool {
        guard let thread = threads.first(where: { $0.id == threadID }),
              thread.isOpen,
              !thread.phase.isProcessing,
              !pendingCloseThreadIDs.contains(threadID)
        else { return false }
        pendingCloseThreadIDs.insert(threadID)
        defer { pendingCloseThreadIDs.remove(threadID) }
        updateThread(threadID) { thread in
            thread.statusText = verdict == .keep ? KCopy.chatResolving : KCopy.chatArchiving
            thread.errorText = nil
        }

        do {
            let branch = try await chatClientFactory(baseURL).closeBranch(
                branchId: threadID,
                verdict: verdict,
                why: ChatThreadCloseComposer.why(for: verdict, thread: thread),
                transcript: ChatThreadCloseComposer.transcript(for: thread)
            )
            updateThread(threadID) { thread in
                thread.reconcile(branch: branch)
                thread.phase = verdict == .keep ? .resolved : .archived
                thread.statusText = verdict == .keep ? KCopy.chatResolved : KCopy.chatArchived
                thread.errorText = nil
            }
            return true
        } catch {
            updateThread(threadID) { thread in
                thread.errorText = KCopy.chatThreadFailed(reason: error.localizedDescription)
                thread.statusText = thread.errorText ?? thread.statusText
            }
            return false
        }
    }

    func invokeBuildAction(threadID: String, packet: ViewPacket) {
        guard let thread = threads.first(where: { $0.id == threadID }),
              ChatThreadActionGate.governedBuildPacket(for: thread)?.id == packet.id,
              thread.buildState != .staging
        else { return }
        updateThread(threadID) { thread in
            thread.buildState = .staging
            thread.statusText = KCopy.chatBuildStaging
            thread.errorText = nil
        }

        // W31's local walk proves the governed intent and handoff without
        // opening a daemon path. Live builds retain the existing held-action
        // contract below; the fixture only short-circuits the transport.
        if W31ChatThreadFixture.isEnabled() {
            updateThread(threadID) { thread in
                thread.buildState = .staged
                thread.statusText = KCopy.chatBuildStaged
                thread.updatedAt = W31ChatThreadFixture.referenceNow
            }
            return
        }

        Task {
            do {
                let outcome = try await clientFactory(baseURL).invokeAction(packet: packet, onEvent: { _ in })
                guard outcome.held else { throw ChatThreadActionError.missingHumanGate }
                updateThread(threadID) { thread in
                    thread.buildState = .staged
                    thread.statusText = KCopy.chatBuildStaged
                    thread.updatedAt = Date()
                }
            } catch {
                updateThread(threadID) { thread in
                    thread.buildState = .failed
                    thread.errorText = KCopy.chatThreadFailed(reason: error.localizedDescription)
                    thread.statusText = thread.errorText ?? thread.statusText
                    thread.updatedAt = Date()
                }
            }
        }
    }

    private func updateThread(
        _ threadID: String,
        persist: Bool = true,
        mutation: (inout ChatThread) -> Void
    ) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        mutation(&threads[index])
        if persist { branchThreadStore.save(threads) }
    }

    private func updateThreadReply(branchID: String, replyID: UUID, text: String) {
        updateThread(branchID, persist: false) { thread in
            guard let index = thread.history.firstIndex(where: { $0.id == replyID }) else { return }
            thread.history[index].text = ChatThoughtScrubber.scrubbedText(text)
            thread.updatedAt = Date()
        }
    }

    private func threadMessage(branchID: String, messageID: UUID) -> Message? {
        threads.first(where: { $0.id == branchID })?.history.first(where: { $0.id == messageID })
    }

    func stopStreaming() {
        guard sending else { return }
        sendTask?.cancel()
        footer = KCopy.stopped
        connectionState.transition(to: .live)
    }

    func invokeAction(from packet: ViewPacket) {
        guard packet.action != nil, !pendingActionPacketIDs.contains(packet.id) else { return }
        pendingActionPacketIDs.insert(packet.id)
        actionErrorTexts[packet.id] = nil
        footer = KCopy.answerPending

        let agui = clientFactory(baseURL)
        Task {
            do {
                let outcome = try await agui.invokeAction(packet: packet, onEvent: { [weak self] event in
                    guard let self else { return }
                    switch event {
                    case .snapshot:
                        break
                    case .packet(let result):
                        self.markThreadLive()
                        self.upsertActionResult(result, for: packet.id)
                    case .patch(let patch):
                        self.markThreadLive()
                        self.applyActionResultPatch(patch, for: packet.id)
                    }
                })
                if let result = outcome.packet {
                    markThreadLive()
                    upsertActionResult(result, for: packet.id)
                }
                actionErrorTexts[packet.id] = nil
                footer = statusLine(outcome)
            } catch {
                let text = KCopy.answerFailed(reason: error.localizedDescription)
                actionErrorTexts[packet.id] = text
                footer = text
            }

            pendingActionPacketIDs.remove(packet.id)
            actionReplyMessageIDs[packet.id] = nil
            saveThreadNow()
        }
    }

    func invokeChosenAction(_ command: ChatActionCommand, from message: Message) {
        guard !command.chosenActionID.isEmpty, var packet = message.packet else { return }
        packet.action = ViewPacketAction(
            kind: "chat.next-action",
            target: command.chosenActionID,
            id: command.chosenActionID,
            args: command.wirePayload
        )
        invokeAction(from: packet)
    }

    private func messageIndex(for id: UUID) -> Int? {
        messages.firstIndex(where: { $0.id == id })
    }

    private func sendLegacy(
        text: String,
        history: [[String: String]],
        replyMessageID: UUID
    ) async throws -> CSKChatOutcome {
        legacyTextCoalescer.reset()
        let outcome = try await legacySender(baseURL, text, history) { [weak self] token in
            guard let self, self.messageIndex(for: replyMessageID) != nil else { return }
            self.connectionState.transition(to: .live)
            self.legacyTextCoalescer.append(token) { [weak self] text in
                guard let self, let replyIndex = self.messageIndex(for: replyMessageID) else { return }
                self.messages[replyIndex].text = text
            }
        }
        legacyTextCoalescer.finish { [weak self] text in
            guard let self, let replyIndex = self.messageIndex(for: replyMessageID) else { return }
            self.messages[replyIndex].text = text
        }
        return outcome
    }

    private func finishSend(dispatchQueued: Bool = true) {
        legacyTextCoalescer.reset()
        branchTextCoalescer.reset()
        sending = false
        sendTask = nil
        saveThreadNow()
        if dispatchQueued {
            dispatchNextQueuedMessageIfIdle()
        }
    }

    private func moveTerminalFailureToInputQueue(
        text: String,
        founderMessageID: UUID,
        replyMessageID: UUID,
        createdAt: Date
    ) -> Bool {
        guard let replyIndex = messageIndex(for: replyMessageID),
              messages[replyIndex].role == .k,
              messages[replyIndex].packet == nil,
              messages[replyIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        messages.remove(at: replyIndex)
        if let founderIndex = messageIndex(for: founderMessageID),
           messages[founderIndex].role == .you,
           messages[founderIndex].text == text {
            messages.remove(at: founderIndex)
        }
        enqueue(text, now: createdAt)
        return true
    }

    private func dispatchNextQueuedMessageIfIdle() {
        guard !sending, let next = inputQueue.nextForDispatch() else { return }
        persistInputQueue()
        if let branchID = next.branchID {
            startBranchSend(next.text, branchID: branchID, createdAt: next.createdAt)
        } else {
            startSend(next.text, createdAt: next.createdAt)
        }
    }

    private func persistInputQueue() {
        inputQueueStore.save(inputQueue)
    }

    private static func isOfflineError(_ error: Error) -> Bool {
        if error is URLError { return true }
        let description = error.localizedDescription.lowercased()
        return ["offline", "network", "not connected", "unreachable", "timed out", "timeout"]
            .contains { description.contains($0) }
    }

    private func upsertStreamPacket(_ packet: ViewPacket, replyMessageID: UUID) {
        KStyle.withMotion {
            let replyIndex = messageIndex(for: replyMessageID)
            if let worker = ChatWorkerPacket(packet), worker.branchID != nil {
                _ = ChatWorkerThreadReducer.upsert(packet, in: &messages, preferredIndex: replyIndex)
                upsertWorkerThread(packet, worker: worker)
            } else if ChatWorkerPacket(packet) != nil {
                let index = ChatWorkerThreadReducer.upsert(packet, in: &messages, preferredIndex: replyIndex)
                if let index, let worker = ChatWorkerPacket(packet), worker.isTerminal {
                    upsertWorkerResultIfPresent(worker, packet: packet, after: index)
                }
            } else if let replyIndex,
                      ChatWorkerPacket(messages[replyIndex].packet ?? packet) == nil {
                messages[replyIndex].packet = packet
                messages[replyIndex].text = Self.historyText(for: packet)
                if let annotations = TermAnnotationsWireDecoder.annotations(from: packet.fields) {
                    messages[replyIndex].termAnnotations = annotations
                }
            } else {
                messages.append(Message(
                    role: .k,
                    text: Self.historyText(for: packet),
                    packet: packet,
                    termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields)
                ))
            }
        }
    }

    private func applyStreamPatch(_ patch: ViewPacketPatch, replyMessageID: UUID) -> Bool {
        if ChatWorkerThreadReducer.applyPatch(patch, in: &messages) {
            for message in messages {
                if let packet = message.packet,
                   let worker = ChatWorkerPacket(packet),
                   worker.branchID != nil {
                    upsertWorkerThread(packet, worker: worker)
                }
            }
            return true
        }
        guard
            let replyIndex = messageIndex(for: replyMessageID),
            let packet = messages[replyIndex].packet
        else { return false }

        let patched = applyPacketPatch(patch, to: packet)
        guard patched != packet else { return false }
        KStyle.withMotion {
            messages[replyIndex].packet = patched
            messages[replyIndex].text = Self.historyText(for: patched)
            if let annotations = TermAnnotationsWireDecoder.annotations(from: patched.fields) {
                messages[replyIndex].termAnnotations = annotations
            }
        }
        return true
    }

    private func upsertWorkerThread(_ packet: ViewPacket, worker: ChatWorkerPacket) {
        guard let branchID = worker.branchID else { return }
        let now = Date()
        if let index = threads.firstIndex(where: { $0.id == branchID }) {
            var thread = threads[index]
            let wasCompleted = thread.isConcluded
            let previousConclusion = thread.history.last(where: { $0.role == .k && !$0.text.isEmpty })?.text
            let isNewPacket = thread.actionPacket?.id != packet.id
            thread.title = worker.label
            thread.statusText = worker.isTerminal
                ? ""
                : (worker.stepEvents.isEmpty ? (worker.stepText ?? worker.stateLine()) : "")
            thread.phase = worker.isFailed
                ? .failed
                : (worker.isTerminal ? .finished : .processing)
            thread.actionPacket = packet
            thread.stepEvents = worker.stepEvents
            thread.errorText = worker.isFailed ? worker.errorText : worker.noteText
            thread.retryText = thread.retryText ?? thread.history.last(where: { $0.role == .you })?.text
            thread.updatedAt = now
            if worker.isTerminal,
               !worker.isFailed,
               let result = worker.resultText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !result.isEmpty,
               thread.history.last?.text != result {
                thread.history.append(Message(
                    role: .k,
                    text: result,
                    termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields),
                    createdAt: now
                ))
            }
            if worker.isTerminal, !worker.isFailed {
                thread.retryText = nil
                thread.retryCount = nil
            }
            threads[index] = thread
            if worker.isTerminal,
               !worker.isFailed,
               (!wasCompleted || isNewPacket || previousConclusion != worker.resultText) {
                ChatThreadLifecycle.archiveSuperseded(&threads, newerID: branchID)
            }
        } else {
            let history = worker.resultText.map {
                [Message(
                    role: .k,
                    text: $0,
                    termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields),
                    createdAt: now
                )]
            } ?? []
            threads.append(ChatThread(
                id: branchID,
                forkMessageID: worker.taskId,
                title: worker.label,
                statusText: worker.isTerminal
                    ? ""
                    : (worker.stepEvents.isEmpty ? (worker.stepText ?? worker.stateLine()) : ""),
                phase: worker.isFailed
                    ? .failed
                    : (worker.isTerminal ? .finished : .processing),
                history: history,
                actionPacket: packet,
                errorText: worker.isFailed ? worker.errorText : worker.noteText,
                stepEvents: worker.stepEvents,
                retryCount: worker.isFailed ? 0 : nil,
                retryText: worker.isFailed ? history.last(where: { $0.role == .you })?.text : nil,
                createdAt: now,
                updatedAt: now
            ))
            if worker.isTerminal, !worker.isFailed {
                ChatThreadLifecycle.archiveSuperseded(&threads, newerID: branchID)
            }
        }
        branchThreadStore.save(threads)
    }

    private func upsertWorkerResultIfPresent(
        _ worker: ChatWorkerPacket,
        packet: ViewPacket,
        after index: Int
    ) {
        guard let result = worker.resultText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty
        else { return }
        let resultIndex = messages.index(after: index)
        if messages.indices.contains(resultIndex),
           messages[resultIndex].role == .k,
           messages[resultIndex].packet == nil,
           messages[resultIndex].text == result {
            return
        }
        messages.insert(
            Message(
                role: .k,
                text: result,
                termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields)
            ),
            at: resultIndex
        )
    }

    private static func rehydrated(_ message: Message) -> Message {
        guard let packet = message.packet else { return message }
        let text = historyText(for: packet)
        guard !text.isEmpty else { return message }

        var rehydrated = message
        rehydrated.text = text
        return rehydrated
    }

    private static func historyText(for packet: ViewPacket) -> String {
        let values = ViewPacketRenderer.visibleTextSequence(for: packet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.joined(separator: "\n")
    }

    private func upsertActionResult(_ packet: ViewPacket, for sourcePacketId: String) {
        let text = Self.historyText(for: packet)
        KStyle.withMotion {
            if let replyMessageID = actionReplyMessageIDs[sourcePacketId],
               let index = messageIndex(for: replyMessageID) {
                messages[index].packet = packet
                messages[index].text = text
                if let annotations = TermAnnotationsWireDecoder.annotations(from: packet.fields) {
                    messages[index].termAnnotations = annotations
                }
            } else {
                let replyMessage = Message(
                    role: .k,
                    text: text,
                    packet: packet,
                    termAnnotations: TermAnnotationsWireDecoder.annotations(from: packet.fields)
                )
                actionReplyMessageIDs[sourcePacketId] = replyMessage.id
                messages.append(replyMessage)
            }
        }
    }

    private func applyActionResultPatch(_ patch: ViewPacketPatch, for sourcePacketId: String) {
        guard
            let replyMessageID = actionReplyMessageIDs[sourcePacketId],
            let index = messageIndex(for: replyMessageID),
            let packet = messages[index].packet
        else { return }

        let patched = applyPacketPatch(patch, to: packet)
        guard patched != packet else { return }
        KStyle.withMotion {
            messages[index].packet = patched
            messages[index].text = Self.historyText(for: patched)
            if let annotations = TermAnnotationsWireDecoder.annotations(from: patched.fields) {
                messages[index].termAnnotations = annotations
            }
        }
    }

    private func statusLine(_ o: AGUIOutcome) -> String {
        var parts: [String] = []
        if let lane = o.lane { parts.append(lane) }
        if let s = o.sensitivity { parts.append(s) }
        if o.held { parts.append("tools held") }
        if o.packet != nil { parts.append("view packet") }
        return parts.joined(separator: " · ").lowercased()
    }

    private func statusLine(_ o: CSKChatOutcome) -> String {
        var parts: [String] = []
        if let lane = o.lane { parts.append(lane) }
        if let s = o.sensitivity { parts.append(s) }
        if o.held { parts.append("tools held") }
        return parts.joined(separator: " · ").lowercased()
    }

    private func markThreadLive(now: Date = Date()) {
        lastSyncedAt = now
        isStale = false
    }
}

enum ChatLineAlignment: Equatable {
    case leading
    case trailing
}

struct ChatEmptyStatePresentation: Equatable {
    static let lines = [
        "k knows you.",
        "ask what is open, what matters, what to attend to.",
    ]
    static let text = lines.joined(separator: "\n")
}

struct ChatMessagePresentation: Equatable {
    let role: Message.Role
    let createdAt: Date

    init(message: Message) {
        role = message.role
        createdAt = message.createdAt
    }

    var speaker: String {
        role == .you ? "founder" : "k"
    }

    var alignment: ChatLineAlignment {
        role == .you ? .trailing : .leading
    }

    var textOpacity: Double {
        role == .you ? KStyle.chatLeadOpacity : KStyle.primaryTextOpacity
    }

    func timestampText(timeZone: TimeZone = .current) -> String {
        ChatTimestampFormatter.text(for: createdAt, timeZone: timeZone)
    }
}

enum ChatMessageAccessibility {
    static func label(for message: Message) -> String {
        let presentation = ChatMessagePresentation(message: message)
        return label(speaker: presentation.speaker, text: message.text)
    }

    static func label(speaker: String, text: String) -> String {
        "\(speaker), \(spokenBody(from: text))"
    }

    private static func spokenBody(from text: String) -> String {
        let parts = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? KCopy.answerPending : parts.joined(separator: ". ")
    }
}

enum ChatTimestampFormatter {
    static func text(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date).lowercased()
    }
}

struct ChatNextActionItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChatReceipt: Equatable, Sendable {
    let soulVersion: String?
    let refCount: Int?

    var text: String? {
        let refs = refCount.map { "\($0) refs" }
        let values = [soulVersion, refs].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

struct ChatNextActionPacket: Equatable, Sendable {
    let actions: [ChatNextActionItem]
    let followUps: [ChatNextActionItem]
    let chosenActionID: String?
    let receipt: ChatReceipt
    let sources: [String]

    init(packet: ViewPacket) {
        let fields = packet.fields ?? [:]
        let dictionaries = [fields, packet.provenance]
        actions = Self.items(
            in: Self.firstValue(in: dictionaries, keys: [
                "nextActions", "next_actions", "suggestedActions", "suggested_actions", "actions"
            ]),
            allowLabelIDFallback: false
        )
        followUps = Self.items(
            in: Self.firstValue(in: dictionaries, keys: [
                "followUps", "follow_ups", "followUpQuestions", "followupQuestions", "follow_up_questions"
            ]),
            allowLabelIDFallback: true
        )

        chosenActionID = Self.chosenActionID(in: dictionaries)

        let receiptObject = dictionaries
            .compactMap { dictionary in
                Self.firstValue(in: [dictionary], keys: ["receipt", "receiptLine"])?.objectValue
            }
            .first
        let soulVersion = Self.scalar(
            in: receiptObject ?? [:],
            keys: ["soulVersion", "soul_version", "valuesVersion", "values_version"]
        ) ?? Self.scalar(
            in: fields,
            keys: ["soulVersion", "soul_version", "valuesVersion", "values_version"]
        )
        let explicitRefCount = Self.integer(
            in: receiptObject ?? [:],
            keys: ["refCount", "ref_count", "referenceCount", "reference_count"]
        ) ?? Self.integer(
            in: fields,
            keys: ["refCount", "ref_count", "referenceCount", "reference_count"]
        )
        let evidenceRefCount = packet.evidence.flatMap { $0.isEmpty ? nil : $0.count }
            ?? (packet.evidencePreviews.isEmpty ? nil : packet.evidencePreviews.count)
        let refCount = explicitRefCount ?? evidenceRefCount
        receipt = ChatReceipt(soulVersion: soulVersion, refCount: refCount)

        let sourceValue = Self.firstValue(
            in: dictionaries,
            keys: ["sources", "references", "refs"]
        )
        let fieldSources = Self.sourceLabels(from: sourceValue)
        sources = Self.unique(fieldSources.isEmpty ? packet.evidencePreviews.map(\.label) : fieldSources)
    }

    var hasActions: Bool { !actions.isEmpty }

    private static func firstValue(
        in dictionaries: [[String: ViewPacketJSONValue]],
        keys: [String]
    ) -> ViewPacketJSONValue? {
        for dictionary in dictionaries {
            for key in keys {
                if let value = dictionary[key] {
                    return value
                }
            }
        }
        return nil
    }

    private static func items(
        in value: ViewPacketJSONValue?,
        allowLabelIDFallback: Bool
    ) -> [ChatNextActionItem] {
        guard let value else { return [] }
        let values: [ViewPacketJSONValue]
        if let array = value.arrayValue {
            values = array
        } else if let object = value.objectValue,
                  let nested = object["items"]?.arrayValue
                    ?? object["actions"]?.arrayValue
                    ?? object["questions"]?.arrayValue {
            values = nested
        } else {
            values = []
        }

        var seen: Set<String> = []
        return values.compactMap { value in
            let object = value.objectValue ?? [:]
            let label = scalar(in: object, keys: ["label", "title", "text", "question"])
                ?? (allowLabelIDFallback ? scalar(value) : nil)
            let fallbackID = allowLabelIDFallback ? label : nil
            guard let label, let id = scalar(in: object, keys: ["id", "actionId", "action_id"]) ?? fallbackID,
                  !label.isEmpty, !id.isEmpty,
                  seen.insert(id).inserted
            else { return nil }
            return ChatNextActionItem(id: id, label: label)
        }
        .prefix(3)
        .map { $0 }
    }

    private static func chosenActionID(in dictionaries: [[String: ViewPacketJSONValue]]) -> String? {
        for dictionary in dictionaries {
            if let value = scalar(in: dictionary, keys: [
                "chosenActionId"
            ]) {
                return value
            }
            for key in ["origin", "actionOrigin", "action_origin"] {
                if let origin = dictionary[key]?.objectValue,
                   let value = scalar(in: origin, keys: ["actionId", "action_id", "id"]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func sourceLabels(from value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }
        let values: [ViewPacketJSONValue]
        if let array = value.arrayValue {
            values = array
        } else if let object = value.objectValue,
                  let nested = object["items"]?.arrayValue ?? object["sources"]?.arrayValue {
            values = nested
        } else {
            values = [value]
        }
        return unique(values.compactMap { value in
            if let object = value.objectValue {
                return scalar(in: object, keys: ["name", "label", "title", "statement", "text"])
            }
            return scalar(value)
        })
    }

    private static func scalar(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = scalar(object[key]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func scalar(_ value: ViewPacketJSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let value):
            return normalized(value)
        case .number, .bool:
            return normalized(value.description)
        case .object, .array, .null:
            return nil
        }
    }

    private static func integer(in object: [String: ViewPacketJSONValue], keys: [String]) -> Int? {
        guard let value = scalar(in: object, keys: keys) else { return nil }
        return Int(value)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized.lowercased()).inserted else { return nil }
            return normalized
        }
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ChatNextActionRowState: Equatable {
    case absent
    case latestActive
    case previousCollapsed
    case previousRestored

    static func resolve(
        actions: [ChatNextActionItem],
        selectedActionID: String?,
        isLatest: Bool,
        isRestored: Bool = false
    ) -> Self {
        guard !actions.isEmpty else { return .absent }
        if isLatest { return .latestActive }
        guard let selectedActionID,
              actions.contains(where: { $0.id == selectedActionID })
        else { return .absent }
        return isRestored ? .previousRestored : .previousCollapsed
    }

    var showsOnlyChosenChip: Bool {
        self == .previousCollapsed
    }
}

enum ChatActionRowPage: Equatable {
    case actions
    case followUps

    var toggled: Self {
        self == .actions ? .followUps : .actions
    }
}

struct ChatActionCommand: Equatable, Sendable {
    let chosenActionID: String

    init(chosenActionID: String) {
        self.chosenActionID = chosenActionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var payload: [String: String] {
        ["chosenActionId": chosenActionID]
    }

    var wirePayload: [String: ViewPacketJSONValue] {
        ["chosenActionId": .string(chosenActionID)]
    }
}

enum ChatNextActionPolicy {
    static func latestKReplyID(in messages: [Message]) -> UUID? {
        messages.last { message in
            guard message.role == .k else { return false }
            if let packet = message.packet,
               packet.viewType == "chat.worker" || ChatWorkerPacket(packet) != nil {
                return false
            }
            return message.packet != nil || !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id
    }
}

enum ChatThreadWorthiness {
    private static let booleanKeys = [
        "threadWorthy", "thread_worthy", "thread-worthy", "shouldThread", "should_thread"
    ]
    private static let scoreKeys = [
        "threadScore", "thread_score", "threadWorthyScore", "thread_worthy_score", "threadWorthiness"
    ]

    static func isWorthy(_ message: Message) -> Bool {
        guard message.role == .k,
              let packet = message.packet,
              !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !packet.displayText.isEmpty,
              packet.viewType != "chat.worker",
              ChatWorkerPacket(packet) == nil
        else { return false }

        let dictionaries = [packet.fields ?? [:], packet.provenance, packet.surfaceDecision ?? [:]]
        if let explicit = boolean(in: dictionaries, keys: booleanKeys) {
            return explicit
        }
        guard let score = number(in: dictionaries, keys: scoreKeys) ?? packet.score else { return false }
        return score >= 0.7
    }

    private static func boolean(
        in dictionaries: [[String: ViewPacketJSONValue]],
        keys: [String]
    ) -> Bool? {
        for dictionary in dictionaries {
            for key in keys {
                guard let value = dictionary[key] else { continue }
                if let bool = value.boolValue { return bool }
                if let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    if ["true", "yes", "worthy"].contains(text) { return true }
                    if ["false", "no", "not_worthy", "not-worthy"].contains(text) { return false }
                }
            }
        }
        return nil
    }

    private static func number(
        in dictionaries: [[String: ViewPacketJSONValue]],
        keys: [String]
    ) -> Double? {
        for dictionary in dictionaries {
            for key in keys {
                guard let value = dictionary[key] else { continue }
                if let number = value.doubleValue { return number }
                if let text = value.stringValue,
                   let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return number
                }
            }
        }
        return nil
    }
}

enum ChatThreadSwapPhase: Equatable {
    case trunkExit
    case threadEnter
    case messageFirst
    case messageSecond
    case composerEnter
    case trunkReturn
}

struct ChatView: View {
    @StateObject private var model = ChatModel()
    @State private var showFileImporter = false
    @State private var selectedThreadID: String?
    @State private var archiveConfirmation = KSecondTapConfirmationModel<String>()
    @State private var archiveConfirmationExpiryTask: Task<Void, Never>?
    @State private var scrollPinning = KScrollPinningModel()
    @State private var selectedQueuedMessageID: UUID?
    @State private var chosenActionIDs: [UUID: String] = [:]
    @State private var composerFocusRequested = false
    @State private var composerFocusTask: Task<Void, Never>?
    @State private var composerStageVisible = true
    @State private var lastFollowScrollAt = Date(timeIntervalSince1970: 0)
    @State private var pendingFollowScrollTask: Task<Void, Never>?
    @State private var pendingFollowScrollTarget: ChatScrollTarget?
    @State private var programmaticScrollResetTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }
    let handoff: ChatThreadHandoff?
    let onUnreadChange: (Bool) -> Void
    let onStalenessChange: (Bool) -> Void
    let onHandoffConsumed: () -> Void
    let onBuildHandoff: () -> Void
    let contextStatsSource: any ContextStatsSource

    init(
        handoff: ChatThreadHandoff? = nil,
        onUnreadChange: @escaping (Bool) -> Void = { _ in },
        onStalenessChange: @escaping (Bool) -> Void = { _ in },
        onHandoffConsumed: @escaping () -> Void = {},
        onBuildHandoff: @escaping () -> Void = {},
        contextStatsSource: any ContextStatsSource = ContextStatsSourceFactory.source()
    ) {
        self.handoff = handoff
        self.onUnreadChange = onUnreadChange
        self.onStalenessChange = onStalenessChange
        self.onHandoffConsumed = onHandoffConsumed
        self.onBuildHandoff = onBuildHandoff
        self.contextStatsSource = contextStatsSource
    }

    var body: some View {
        let trunkMessages = model.trunkMessages
        let trunkQueuedMessages = model.queuedMessages.filter { $0.branchID == nil }
        GeometryReader { proxy in
            if ThreadStackLayoutPolicy.isCompact(availableWidth: proxy.size.width) {
                compactShell(
                    trunkMessages: trunkMessages,
                    trunkQueuedMessages: trunkQueuedMessages
                )
            } else {
                regularShell(
                    metrics: ChatShellLayoutMetrics.resolve(availableWidth: proxy.size.width),
                    trunkMessages: trunkMessages,
                    trunkQueuedMessages: trunkQueuedMessages
                )
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-view")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.retainAttachment(url) }
            case .failure(let error):
                model.footer = KCopy.chatAttachmentFailed(reason: error.localizedDescription)
            }
        }
        .onAppear {
            markSeenIfVisible()
            onUnreadChange(model.hasUnread)
            onStalenessChange(model.isStale)
            if !ChatDemoFixture.isEnabled(),
               !ChatBranchMotionFixture.isEnabled(),
               !W31ChatThreadFixture.isEnabled(),
               !model.isAuditFixtureEnabled {
                model.drainInputQueueIfIdle()
                model.refreshBranches()
            }
        }
        .onDisappear {
            archiveConfirmationExpiryTask?.cancel()
            composerFocusTask?.cancel()
            pendingFollowScrollTask?.cancel()
            programmaticScrollResetTask?.cancel()
            model.saveThreadNow()
            onUnreadChange(model.hasUnread)
            onStalenessChange(model.isStale)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.saveThreadNow()
            } else if phase == .active {
                markSeenIfVisible()
                if !ChatDemoFixture.isEnabled(),
                   !ChatBranchMotionFixture.isEnabled(),
                   !W31ChatThreadFixture.isEnabled(),
                   !model.isAuditFixtureEnabled {
                    model.drainInputQueueIfIdle()
                    model.refreshBranches()
                }
            }
        }
        .onChange(of: model.messages) { _, _ in markSeenIfVisible() }
        .onChange(of: model.isStale) { _, isStale in onStalenessChange(isStale) }
        .task(id: handoff?.anchorID) {
            guard let handoff else { return }
            let threadID = await model.receive(handoff)
            if let threadID {
                selectedThreadID = threadID
            }
            onHandoffConsumed()
        }
        .onChange(of: model.threads) { _, threads in
            guard let selectedThreadID else { return }
            if threads.first(where: { $0.id == selectedThreadID })?.phase.isArchived == true {
                self.selectedThreadID = nil
            }
        }
        .onChange(of: selectedThreadID) { _, selectedThreadID in
            scheduleComposerFocus(for: selectedThreadID)
        }
    }

    private func regularShell(
        metrics: ChatShellLayoutMetrics,
        trunkMessages: [Message],
        trunkQueuedMessages: [QueuedChatMessage]
    ) -> some View {
        let groupWidth = KStyle.chatReservedLeadingWidth
            + KStyle.chatShellColumnGap * 2
            + metrics.trunkWidth
            + KStyle.chatThreadStackWidth
        return VStack(spacing: .zero) {
            HStack(alignment: .top, spacing: KStyle.chatShellColumnGap) {
                Color.clear
                    .frame(width: KStyle.chatReservedLeadingWidth)
                    .accessibilityHidden(true)
                    .overlay { collapseCatcher }
                messageStream(
                    trunkMessages: trunkMessages,
                    trunkQueuedMessages: trunkQueuedMessages
                )
                    .frame(width: metrics.trunkWidth)
                    .overlay { collapseCatcher }
                    .opacity(selectedThreadID == nil ? KStyle.fullOpacity : .zero)
                    .animation(
                        KStyle.chatThreadSwapMotion(
                            reduceMotion,
                            phase: selectedThreadID == nil ? .trunkReturn : .trunkExit
                        ),
                        value: selectedThreadID
                    )
                ZStack(alignment: .topLeading) {
                    threadStack(compact: false)
                    branchLoadingCue
                }
                .accessibilityElement(children: .contain)
            }
            .frame(width: groupWidth)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: .zero) {
            HStack(alignment: .bottom, spacing: KStyle.chatShellColumnGap) {
                // Width-only spacers: an unbounded height here makes this row
                // vertically greedy and steals half the screen from the stream.
                Color.clear.frame(width: KStyle.chatReservedLeadingWidth, height: KStyle.hairlineWidth)
                // Trunk and regular-width branch presentations share the same
                // bottom safe-area slot. Software keyboards lift it; hardware
                // keyboards leave it pinned to the bottom edge.
                if selectedThreadID == nil {
                    composerArea(
                        trunkMessages: trunkMessages,
                        surface: .regularWidth
                    )
                        .frame(width: metrics.trunkWidth)
                } else {
                    Color.clear
                        .frame(width: metrics.trunkWidth, height: KStyle.hairlineWidth)
                }
                Color.clear.frame(width: KStyle.chatThreadStackWidth, height: KStyle.hairlineWidth)
            }
            .frame(width: groupWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func compactShell(
        trunkMessages: [Message],
        trunkQueuedMessages: [QueuedChatMessage]
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            messageStream(
                trunkMessages: trunkMessages,
                trunkQueuedMessages: trunkQueuedMessages
            )
            // A compact branch replaces the visible context. Recreating the
            // trunk stream on that boundary gives the trunk the same newest
            // anchor when the branch is opened or dismissed.
            .id(ChatScrollAnchorLogic.context(for: selectedThreadID))
            .opacity(selectedThreadID == nil ? KStyle.fullOpacity : .zero)
            .animation(
                KStyle.chatThreadSwapMotion(
                    reduceMotion,
                    phase: selectedThreadID == nil ? .trunkReturn : .trunkExit
                ),
                value: selectedThreadID
            )

            if !model.threads.isEmpty
                || W30ChatRailFixture.isEnabled()
                || W31ChatThreadFixture.isEnabled() {
                ZStack(alignment: .topLeading) {
                    threadStack(compact: true)
                    branchLoadingCue
                }
                .accessibilityElement(children: .contain)
                    .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
            } else if model.isBranchesLoading {
                branchLoadingCue
                    .padding(KStyle.smallSpacing)
            } else if let branchesErrorText = model.branchesErrorText {
                KMonoCaption(branchesErrorText, variant: .inlineError, state: .offline)
                    .padding(KStyle.smallSpacing)
                    .accessibilityIdentifier("chat-branches-unreachable")
            }
        }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: .zero) {
            // The compact branch overlay uses the same bottom safe-area slot
            // as trunk chat, including the hardware-keyboard bottom anchor.
            if selectedThreadID == nil {
                composerArea(
                    trunkMessages: trunkMessages,
                    surface: .compactOverlay
                )
            } else {
                Color.clear
                    .frame(height: KStyle.hairlineWidth)
            }
        }
        .animation(KStyle.chatStructureMotion(reduceMotion), value: model.threads.isEmpty)
    }

    @ViewBuilder
    private var branchLoadingCue: some View {
        if model.isBranchesLoading {
            KLoadingPrimitive(
                variant: .dot,
                label: "loading threads",
                accessibilityIdentifier: "chat-branches-loading"
            )
            .padding(.top, KStyle.smallSpacing)
        } else if let branchesErrorText = model.branchesErrorText {
            KMonoCaption(branchesErrorText, variant: .inlineError, state: .offline)
                .accessibilityIdentifier("chat-branches-unreachable")
        }
    }

    // Founder 2026-08-04: with a branch selected, a tap outside the card
    // collapses it. The composer is not "outside" — it targets the branch.
    @ViewBuilder
    private var collapseCatcher: some View {
        if selectedThreadID != nil {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedThreadID = nil
                }
        }
    }

    private func threadStack(compact: Bool) -> some View {
        ThreadStack(
            threads: model.threads,
            queuedMessages: model.queuedMessages,
            pendingCloseThreadIDs: model.pendingCloseThreadIDs,
            expandedThreadID: $selectedThreadID,
            isCompact: compact,
            archiveConfirmationID: archiveConfirmation.pendingKey,
            onResolve: { thread in
                Task {
                    if await model.closeThread(thread.id, verdict: .keep) {
                        selectedThreadID = nil
                    }
                }
            },
            onLater: { thread in
                model.markThreadLater(thread.id)
                selectedThreadID = nil
            },
            onArchive: handleArchive,
            onBuild: { thread, packet in model.invokeBuildAction(threadID: thread.id, packet: packet) },
            onBuildHandoff: onBuildHandoff,
            onDropQueued: model.dropQueuedMessage(id:),
            onRetry: { thread in model.retryThread(thread.id) },
            branchComposer: selectedThreadID.map { _ in
                AnyView(
                    composerArea(
                        trunkMessages: model.messages,
                        surface: compact ? .compactOverlay : .regularWidth
                    )
                )
            }
        )
        .animation(
            KStyle.chatThreadSwapMotion(
                reduceMotion,
                phase: selectedThreadID == nil ? .trunkExit : .threadEnter
            ),
            value: selectedThreadID
        )
    }

    private var composerTarget: ChatComposerTarget {
        guard let selectedThreadID,
              let thread = model.threads.first(where: { $0.id == selectedThreadID })
        else { return .trunk }
        return .thread(id: thread.id, title: thread.title)
    }

    private func contextSnapshot(trunkMessages: [Message]) -> ChatContextSnapshot {
        let messages: [Message]
        if let branchID = composerTarget.branchID,
           let thread = model.threads.first(where: { $0.id == branchID }) {
            messages = thread.history
        } else {
            messages = trunkMessages
        }
        return ChatContextComposer.snapshot(
            target: composerTarget,
            messages: messages,
            attachment: model.attachment
        )
    }

    private func composerArea(
        trunkMessages: [Message],
        surface: ChatComposerSurface
    ) -> some View {
        let slot = ChatComposerSlotPolicy.resolve(
            expandedThreadID: selectedThreadID,
            surface: surface
        )
        let target = composerTarget(for: slot)

        return VStack(alignment: .leading, spacing: KStyle.inputStatusSpacing) {
            if !model.footer.isEmpty {
                footerLine
                    .transition(.opacity)
            }

            ChatComposerBar(
                text: $model.draft,
                focusRequest: $composerFocusRequested,
                state: model.sending ? .loading : .resting,
                placeholder: target.branchID == nil
                    ? KCopy.chatTrunkPlaceholder
                    : KCopy.chatThreadPlaceholder,
                contextTarget: target,
                contextStats: contextStatsSource.contextStats(for: target),
                onAttach: { showFileImporter = true },
                onSubmit: { model.send(targetBranchID: target.branchID) },
                onStop: model.stopStreaming
            )
        }
        .opacity(composerStageVisible ? KStyle.fullOpacity : .zero)
        .animation(KStyle.chatContentSwapMotion(reduceMotion), value: !model.footer.isEmpty)
        .frame(maxWidth: .infinity)
    }

    private func composerTarget(for slot: ChatComposerSlot) -> ChatComposerTarget {
        switch slot {
        case .trunk:
            return .trunk
        case .branch(let branchID):
            guard let thread = model.threads.first(where: { $0.id == branchID }) else {
                return .trunk
            }
            return .thread(id: thread.id, title: thread.title)
        }
    }

    private func handleArchive(_ thread: ChatThread) {
        let now = Date()
        if archiveConfirmation.tap(thread.id, now: now) {
            archiveConfirmationExpiryTask?.cancel()
            Task {
                if await model.closeThread(thread.id, verdict: .discard) {
                    selectedThreadID = nil
                }
            }
            return
        }

        archiveConfirmationExpiryTask?.cancel()
        archiveConfirmationExpiryTask = Task { @MainActor in
            let nanoseconds = UInt64(archiveConfirmation.window * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            archiveConfirmation.clearExpired()
        }
    }

    private func scheduleComposerFocus(for selectedThreadID: String?) {
        composerFocusTask?.cancel()
        composerFocusRequested = false
        composerStageVisible = false

        let delay = selectedThreadID == nil
            ? KStyle.chatThreadTrunkReturnDelay
            : KStyle.chatThreadComposerDelay
        let phase: ChatThreadSwapPhase = selectedThreadID == nil ? .trunkReturn : .composerEnter
        let expectedID = selectedThreadID
        composerFocusTask = Task { @MainActor in
            if reduceMotion {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, self.selectedThreadID == expectedID else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: phase)) {
                composerStageVisible = true
            }
            if expectedID != nil {
                composerFocusRequested = true
            }
        }
    }

    private func markSeenIfVisible() {
        guard scenePhase == .active else {
            onUnreadChange(model.hasUnread)
            return
        }
        model.markVisibleInForeground()
        onUnreadChange(model.hasUnread)
    }

    private func messageStream(
        trunkMessages: [Message],
        trunkQueuedMessages: [QueuedChatMessage]
    ) -> some View {
        let latestScrollTarget = latestScrollTarget(
            trunkMessages: trunkMessages,
            trunkQueuedMessages: trunkQueuedMessages
        )
        let latestKReplyID = ChatNextActionPolicy.latestKReplyID(in: trunkMessages)

        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                            streamHeader.id(ChatScrollTarget.top)

                            if trunkMessages.isEmpty && trunkQueuedMessages.isEmpty {
                                emptyState
                            }

                            ForEach(trunkMessages) { message in
                                streamLine(message, latestKReplyID: latestKReplyID)
                                    .id(ChatScrollTarget.message(message.id))
                            }

                            ForEach(trunkQueuedMessages) { item in
                                queuedStreamLine(item).id(ChatScrollTarget.queued(item.id))
                            }

                            Color.clear
                                .frame(height: KStyle.hairlineWidth)
                                .id(ChatScrollTarget.bottom)
                                .background {
                                    GeometryReader { bottomProxy in
                                        Color.clear.preference(
                                            key: ChatBottomYPreferenceKey.self,
                                            value: bottomProxy.frame(in: .named(ChatScrollID.coordinateSpace)).maxY
                                        )
                                    }
                                }
                        }
                        .padding(.horizontal, KStyle.columnMargin)
                        .padding(.top, KStyle.columnMargin)
                        .padding(.bottom, KStyle.cardPadding)
                    }
                    .coordinateSpace(name: ChatScrollID.coordinateSpace)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .chatDefaultScrollAnchor()
                    .chatScrollGeometryTracking { distance in
                        let scrollPositionViewID = scrollPinning.geometryScrollPositionViewID
                        scrollPinning.updateDistanceFromBottom(
                            distance,
                            scrollPositionViewID: scrollPositionViewID
                        )
                    }
                    .onPreferenceChange(ChatBottomYPreferenceKey.self) { bottomY in
                        let scrollPositionViewID = scrollPinning.geometryScrollPositionViewID
                        scrollPinning.updateDistanceFromBottom(
                            max(.zero, bottomY - geometry.size.height),
                            scrollPositionViewID: scrollPositionViewID
                        )
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in founderDragDidBegin() }
                    )
                    .onAppear {
                        scrollPinning.resumeFollowing()
                        performFollowScroll(
                            proxy: proxy,
                            target: latestScrollTarget,
                            animated: false
                        )
                    }
                    .onChange(of: trunkMessages) { _, _ in
                        requestFollowScroll(proxy: proxy, target: latestScrollTarget)
                    }
                    .onChange(of: trunkQueuedMessages) { _, _ in
                        requestFollowScroll(proxy: proxy, target: latestScrollTarget)
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active, scrollPinning.isFollowing {
                            performFollowScroll(proxy: proxy, target: latestScrollTarget)
                        }
                    }

                    if scrollPinning.showsLatestPill {
                        KActRow(
                            actions: [
                                KActItem(
                                    id: "latest",
                                    label: "latest",
                                    accessibilityIdentifier: "chat-latest"
                                ),
                            ],
                            variant: .admin,
                            onSelect: { _ in
                                scrollPinning.resumeFollowing()
                                performFollowScroll(proxy: proxy, target: latestScrollTarget)
                            }
                        )
                        .kGlassCardTone()
                        .accessibilityLabel("latest")
                        .accessibilityHint("return to the latest reply")
                        .padding(.trailing, KStyle.columnMargin)
                        .padding(.bottom, KStyle.smallSpacing)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func latestScrollTarget(
        trunkMessages: [Message],
        trunkQueuedMessages: [QueuedChatMessage]
    ) -> ChatScrollTarget {
        ChatScrollAnchorLogic.latestTarget(
            messages: trunkMessages,
            queuedMessages: trunkQueuedMessages
        )
    }

    private func requestFollowScroll(proxy: ScrollViewProxy, target: ChatScrollTarget) {
        guard scrollPinning.contentDidAppend() else { return }
        pendingFollowScrollTarget = target
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFollowScrollAt)
        if elapsed >= ChatDeltaFlushPlanner.defaultInterval {
            performFollowScroll(proxy: proxy, target: target, now: now)
            return
        }
        guard pendingFollowScrollTask == nil else { return }
        let delay = UInt64(max(.zero, ChatDeltaFlushPlanner.defaultInterval - elapsed) * 1_000_000_000)
        pendingFollowScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            pendingFollowScrollTask = nil
            performFollowScroll(
                proxy: proxy,
                target: pendingFollowScrollTarget ?? target
            )
        }
    }

    private func performFollowScroll(
        proxy: ScrollViewProxy,
        target: ChatScrollTarget,
        animated: Bool = true,
        now: Date = Date()
    ) {
        pendingFollowScrollTask?.cancel()
        pendingFollowScrollTask = nil
        pendingFollowScrollTarget = nil
        lastFollowScrollAt = now
        programmaticScrollResetTask?.cancel()
        scrollPinning.beginProgrammaticScroll()
        if animated {
            KStyle.withMotion(reduceMotion: reduceMotion) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
        resetProgrammaticScrollTrackingAfterScroll(animated: animated)
    }

    private func founderDragDidBegin() {
        pendingFollowScrollTask?.cancel()
        pendingFollowScrollTask = nil
        pendingFollowScrollTarget = nil
        programmaticScrollResetTask?.cancel()
        programmaticScrollResetTask = nil
        scrollPinning.founderDragDidBegin()
    }

    private func resetProgrammaticScrollTrackingAfterScroll(animated: Bool) {
        let interval = animated && !reduceMotion
            ? KStyle.zenDuration + ChatDeltaFlushPlanner.defaultInterval
            : ChatDeltaFlushPlanner.defaultInterval
        let delay = UInt64(interval * 1_000_000_000)
        programmaticScrollResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            scrollPinning.endProgrammaticScroll()
            programmaticScrollResetTask = nil
        }
    }

    private var streamHeader: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if let stalenessText = model.stalenessText {
                KMonoCaption(stalenessText, variant: .staleness)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-stream-header")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(ChatEmptyStatePresentation.lines, id: \.self) { line in
                Text(line)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, KStyle.chatShellColumnGap)
        .accessibilityIdentifier("chat-empty-state")
    }

    private func streamLine(_ message: Message, latestKReplyID: UUID?) -> some View {
        let presentation = ChatMessagePresentation(message: message)
        // Founder ruling: no per-message clocks or date rows; provenance lives
        // in receipts, not stream chrome.
        let row = KStreamRow(
            role: presentation.streamRole,
            accessibilityText: ChatMessageAccessibility.label(for: message)
        ) {
            messageContent(
                message,
                presentation: presentation,
                latestKReplyID: latestKReplyID
            )
        }
        if message.role == .k, message.packet == nil, message.text.isEmpty {
            return AnyView(row.accessibilityIdentifier("chat-loading"))
        }
        return AnyView(row)
    }

    private func queuedStreamLine(_ item: QueuedChatMessage) -> some View {
        let isSelected = selectedQueuedMessageID == item.id
        return KStreamRow(
            role: .founder,
            meta: "queued",
            state: .loading,
            accessibilityText: "founder, queued, \(item.text)"
        ) {
            VStack(alignment: .trailing, spacing: KStyle.microSpacing) {
                Button {
                    selectedQueuedMessageID = isSelected ? nil : item.id
                } label: {
                    Text(item.text)
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat-queued-\(item.id.uuidString)")

                if isSelected {
                    KActRow(
                        actions: [KActItem(id: "edit"), KActItem(id: "drop")],
                        variant: .admin,
                        onSelect: { action in
                            if action.id == "edit" {
                                model.editQueuedMessage(id: item.id)
                            } else {
                                model.dropQueuedMessage(id: item.id)
                            }
                            selectedQueuedMessageID = nil
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func messageContent(
        _ message: Message,
        presentation: ChatMessagePresentation,
        latestKReplyID: UUID?
    ) -> some View {
        VStack(alignment: presentation.horizontalAlignment, spacing: KStyle.smallSpacing) {
            if message.role == .k, let packet = message.packet {
                let nextActions = ChatNextActionPacket(packet: packet)
                let replyText = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? packet.displayText
                    : message.text
                ChatReplySurface(
                    message: message,
                    packet: nextActions,
                    isLatestKReply: latestKReplyID == message.id,
                    isWorker: packet.viewType == "chat.worker" || ChatWorkerPacket(packet) != nil,
                    selectedActionID: chosenActionIDs[message.id] ?? nextActions.chosenActionID,
                    onSelectAction: { item in
                        let command = ChatActionCommand(chosenActionID: item.id)
                        chosenActionIDs[message.id] = command.chosenActionID
                        model.invokeChosenAction(command, from: message)
                    },
                    onFollowUp: { item in
                        model.draft = item.label
                        composerFocusRequested = true
                    },
                    onVerb: { verb in
                        switch verb {
                        case .branch:
                            let branchID = model.branchID(forkedFrom: message.id)
                            if let branchID {
                                selectedThreadID = branchID
                            } else {
                                Task { _ = await model.fork(message) }
                            }
                        case .actOn:
                            model.invokeAction(from: packet)
                        case .replyTo:
                            model.draft = replyText
                            composerFocusRequested = true
                        case .copy:
                            UIPasteboard.general.string = replyText
                        case .toMind, .refs:
                            break
                        }
                    }
                ) {
                    threadProposalSurface(for: message) {
                        RenderViewPacket(
                            packet: packet,
                            pendingActionPacketIDs: model.pendingActionPacketIDs,
                            actionErrorTexts: model.actionErrorTexts,
                            context: .chatStream,
                            onAction: model.invokeAction(from:)
                        )
                        .environment(\.termAnnotations, message.termAnnotations)
                        .foregroundStyle(.white.opacity(presentation.textOpacity))
                    }
                }
            } else if message.role == .k, message.text.isEmpty {
                KLoadingPrimitive(
                    variant: .dot,
                    label: KCopy.answerPending,
                    accessibilityIdentifier: "chat-loading"
                )
            } else if message.role == .k {
                ChatReplySurface(
                    message: message,
                    packet: nil,
                    isLatestKReply: latestKReplyID == message.id,
                    isWorker: false,
                    selectedActionID: chosenActionIDs[message.id],
                    onSelectAction: { _ in },
                    onFollowUp: { item in
                        model.draft = item.label
                        composerFocusRequested = true
                    },
                    onVerb: { verb in
                        switch verb {
                        case .replyTo:
                            model.draft = message.text
                            composerFocusRequested = true
                        case .copy:
                            UIPasteboard.general.string = message.text
                        case .branch:
                            Task { _ = await model.fork(message) }
                        case .toMind, .actOn, .refs:
                            break
                        }
                    }
                ) {
                    threadProposalSurface(for: message) {
                        ChatReplyProse(text: message.text, annotations: message.termAnnotations)
                    }
                }
            } else if message.role == .you {
                // Mock v21: founder turns are plain right-aligned ink. The stream
                // row owns the alignment; no bubble or secondary material layer.
                Text(message.text)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(presentation.textOpacity))
                    .multilineTextAlignment(presentation.textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text(message.text)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(presentation.textOpacity))
                    .multilineTextAlignment(presentation.textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func threadProposalSurface<Content: View>(
        for message: Message,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if ChatThreadWorthiness.isWorthy(message) {
            ChatThreadProposalCard(
                messageID: message.id,
                onCreate: { createThread(from: message.id) },
                content: content
            )
        } else {
            content()
        }
    }

    private func createThread(from turnID: UUID) {
        Task {
            guard let branchID = await model.createThread(from: turnID) else { return }
            selectedThreadID = branchID
        }
    }

    private func branchControl(for message: Message) -> some View {
        let branchID = model.branchID(forkedFrom: message.id)
        let pending = model.pendingForkMessageIDs.contains(message.id)
        return KActRow(
            actions: [
                KActItem(
                    id: "branch",
                    label: branchID == nil
                        ? (pending ? KCopy.chatBranching : KCopy.chatBranchThis)
                        : KCopy.chatBranched,
                    isEnabled: !pending,
                    accessibilityIdentifier: "chat-branch-\(message.id.uuidString)"
                ),
            ],
            variant: .admin,
            state: pending ? .loading : .resting,
            onSelect: { _ in
                if let branchID {
                    selectedThreadID = branchID
                } else {
                    Task { _ = await model.fork(message) }
                }
            }
        )
    }

    private var footerLine: some View {
        let isError = model.footer.contains("failed") || model.footer.contains("offline")
        return KMonoCaption(
            model.footer,
            variant: isError ? .inlineError : .footer,
            state: isError ? .error : .resting
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KStyle.inputSidePadding)
        .padding(.trailing, KStyle.inputTrailingPadding)
        .textSelection(.enabled)
    }

}

private struct ChatThreadProposalCard<Content: View>: View {
    let messageID: UUID
    let onCreate: () -> Void
    let content: Content

    init(
        messageID: UUID,
        onCreate: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.messageID = messageID
        self.onCreate = onCreate
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            content

            HStack {
                Spacer(minLength: KStyle.smallSpacing)
                Button(action: onCreate) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: KStyle.navRegularIconSize, weight: .regular))
                        .foregroundStyle(Color.white.opacity(KStyle.primaryControlTextOpacity))
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("open thread")
                .accessibilityHint("create a thread from this reply")
                .accessibilityIdentifier("chat-thread-proposal-arrow-\(messageID.uuidString)")
            }
        }
        .padding(.horizontal, KStyle.cardPadding)
        .padding(.top, KStyle.cardPadding)
        .padding(.bottom, KStyle.smallSpacing)
        .kGlassCardTone()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-thread-proposal-\(messageID.uuidString)")
    }
}

private struct ChatReplySurface<Content: View>: View {
    let message: Message
    let packet: ChatNextActionPacket?
    let isLatestKReply: Bool
    let isWorker: Bool
    let selectedActionID: String?
    let onSelectAction: (ChatNextActionItem) -> Void
    let onFollowUp: (ChatNextActionItem) -> Void
    let onVerb: (KChatVerb) -> Void
    let content: Content

    @State private var isDrawerOpen = false
    @State private var isInlineSourcesOpen = false
    @State private var isSourcesSheetOpen = false
    @State private var isFollowUpPage = false
    @State private var showFullActionRow = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }

    init(
        message: Message,
        packet: ChatNextActionPacket?,
        isLatestKReply: Bool,
        isWorker: Bool,
        selectedActionID: String?,
        onSelectAction: @escaping (ChatNextActionItem) -> Void,
        onFollowUp: @escaping (ChatNextActionItem) -> Void,
        onVerb: @escaping (KChatVerb) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.message = message
        self.packet = packet
        self.isLatestKReply = isLatestKReply
        self.isWorker = isWorker
        self.selectedActionID = selectedActionID
        self.onSelectAction = onSelectAction
        self.onFollowUp = onFollowUp
        self.onVerb = onVerb
        self.content = content()
    }

    private var sources: [String] { packet?.sources ?? [] }
    private var reasoningTrace: ChatReasoningTrace? {
        guard let packet = message.packet else { return nil }
        return ChatReasoningTrace.from(packet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            content
                .frame(maxWidth: KStyle.readingMeasureMaxWidth, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: KStyle.smallSpacing)
                        .onEnded { value in
                            guard value.translation.width > KStyle.minimumTapTarget,
                                  abs(value.translation.width) > abs(value.translation.height)
                            else { return }
                            withAnimation(KStyle.chatExpansionMotion(reduceMotion)) {
                                isDrawerOpen = true
                            }
                            onVerb(.replyTo)
                        }
                )

            if let reasoningTrace {
                ChatReasoningTraceView(trace: reasoningTrace, messageID: message.id.uuidString)
            }

            if !isWorker {
                KChatVerbDrawer(
                    isOpen: isDrawerOpen,
                    receipt: packet?.receipt,
                    messageID: message.id.uuidString,
                    onSelect: handleVerb
                )

                if isInlineSourcesOpen {
                    ChatSourcesView(sources: sources)
                        .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
                }

                if let packet, packet.hasActions {
                    KChatActionRow(
                        actions: packet.actions,
                        followUps: packet.followUps,
                        selectedActionID: selectedActionID,
                        isActive: isLatestKReply,
                        showFullRow: showFullActionRow,
                        isFollowUpPage: isFollowUpPage,
                        accessibilityPrefix: "chat-next-actions-\(message.id.uuidString)",
                        onSelect: { item in
                            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                                showFullActionRow = false
                            }
                            onSelectAction(item)
                        },
                        onFollowUp: { item in
                            onFollowUp(item)
                        },
                        onPageChange: { showFollowUps in
                            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                                isFollowUpPage = showFollowUps
                            }
                        },
                        onRestoreFullRow: {
                            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                                showFullActionRow = true
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: KStyle.buildThreadLongPressDuration)
                .onEnded { _ in
                    withAnimation(KStyle.chatExpansionMotion(reduceMotion)) {
                        isDrawerOpen = true
                    }
                }
        )
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isDrawerOpen)
        .animation(KStyle.chatStructureMotion(reduceMotion), value: isInlineSourcesOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-reply-\(message.id.uuidString)")
        .onChange(of: isLatestKReply) { _, isLatest in
            guard !isLatest else { return }
            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                showFullActionRow = false
                isFollowUpPage = false
            }
        }
        .sheet(isPresented: $isSourcesSheetOpen) {
            ChatSourcesView(sources: sources)
                .padding(KStyle.cardPadding)
                .preferredColorScheme(.dark)
        }
    }

    private func handleVerb(_ verb: KChatVerb) {
        if verb == .refs, !sources.isEmpty {
            if horizontalSizeClass == .compact {
                isSourcesSheetOpen = true
            } else {
                withAnimation(KStyle.chatExpansionMotion(reduceMotion)) {
                    isInlineSourcesOpen.toggle()
                }
            }
        }
        onVerb(verb)
    }
}

private struct ChatReasoningTraceView: View {
    let trace: ChatReasoningTrace
    let messageID: String

    @State private var expansion = ChatReasoningTraceExpansionState()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            Button {
                withAnimation(KStyle.chatExpansionMotion(reduceMotion)) {
                    expansion.toggleTrace()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption(trace.summaryLine, variant: .metadata)
                    Spacer(minLength: KStyle.smallSpacing)
                    Image(systemName: expansion.isTraceExpanded ? "chevron.up" : "chevron.down")
                        .font(KStyle.monoCaptionFont)
                        .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expansion.isTraceExpanded ? "collapse reasoning trace" : "expand reasoning trace")
            .accessibilityIdentifier("chat-reasoning-trace-\(messageID)")

            if expansion.isTraceExpanded {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    ForEach(trace.steps) { step in
                        ChatReasoningStepRow(
                            step: step,
                            isExpanded: expansion.expandedStepID == step.id,
                            onToggle: {
                                withAnimation(KStyle.chatExpansionMotion(reduceMotion)) {
                                    expansion.toggleStep(step.id)
                                }
                            }
                        )
                    }
                }
                .padding(.leading, KStyle.smallSpacing)
                .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
            }
        }
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: expansion)
    }
}

private struct ChatReasoningStepRow: View {
    let step: ChatThreadStep
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        if let detail = step.detail {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        Text(step.text.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: KStyle.smallSpacing)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(KStyle.monoCaptionFont)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                    }
                    if isExpanded {
                        Text(detail.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "collapse step \(step.text)" : "expand step \(step.text)")
            .accessibilityIdentifier("chat-reasoning-step-\(step.id)")
        } else {
            Text(step.text.lowercased())
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chat-reasoning-step-\(step.id)")
        }
    }
}

// Mock v35 contrast law: lead sentence bright (chatLeadOpacity), support dim
// (chatSupportOpacity). Shared by the no-packet reply path and the chat-stream
// generic-text packet path so both render the reply grammar identically.
struct ChatReplyProse: View {
    let text: String
    let annotations: [TermAnnotation]?

    @Environment(\.termAnnotations) private var environmentAnnotations

    init(text: String, annotations: [TermAnnotation]? = nil) {
        self.text = text
        self.annotations = annotations
    }

    var body: some View {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAnnotations = TermAnnotationText.resolvedAnnotations(
            in: normalized,
            explicit: annotations ?? environmentAnnotations,
            source: FixtureTermAnnotationsSource.default
        )
        let parts = ChatReplyTextPresentation.split(normalized)
        let leadAnnotations = TermAnnotationText.rebased(
            resolvedAnnotations,
            to: .zero..<parts.lead.utf16.count
        )
        let supportStart = normalized.utf16.count - (parts.support?.utf16.count ?? .zero)
        let supportAnnotations = parts.support.map { support in
            TermAnnotationText.rebased(
                resolvedAnnotations,
                to: supportStart..<normalized.utf16.count
            )
        } ?? []

        return VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if leadAnnotations.isEmpty {
                Text(parts.lead)
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.chatLeadOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                TermAnnotatedText(
                    text: parts.lead,
                    annotations: leadAnnotations,
                    source: FixtureTermAnnotationsSource.empty,
                    font: KStyle.contentFont,
                    foregroundColor: Color.white.opacity(KStyle.chatLeadOpacity),
                    accessibilityIdentifier: "chat-term-lead"
                )
            }

            if let support = parts.support {
                if supportAnnotations.isEmpty {
                    Text(support)
                        .font(KStyle.contentFont)
                        .foregroundStyle(Color.white.opacity(KStyle.chatSupportOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    TermAnnotatedText(
                        text: support,
                        annotations: supportAnnotations,
                        source: FixtureTermAnnotationsSource.empty,
                        font: KStyle.contentFont,
                        foregroundColor: Color.white.opacity(KStyle.chatSupportOpacity),
                        accessibilityIdentifier: "chat-term-support"
                    )
                }
            }
        }
    }
}

enum ChatReplyTextPresentation {
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

private struct ChatSourcesView: View {
    let sources: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                Text(source)
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, KStyle.cardPadding)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineStrongOpacity))
                .frame(width: KStyle.hairlineWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-sources")
    }
}

struct ChatComposerBar: View {
    @Binding var text: String
    @Binding var focusRequest: Bool
    let state: KPrimitiveInteractionState
    let placeholder: String
    let contextTarget: ChatComposerTarget?
    let contextStats: ContextStats?
    let onAttach: () -> Void
    let onSubmit: () -> Void
    let onStop: () -> Void
    // Build reuses the chat composer grammar but owns its focus and context
    // seams. Optional values keep the chat call site byte-equivalent.
    let contextRingExpanded: Binding<Bool>?
    let contextPanelTarget: String?
    let inputAccessibilityIdentifier: String
    let sendAccessibilityIdentifier: String

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }
    @FocusState private var composerFocused: Bool
    @State private var contextRingExpandedState = false

    init(
        text: Binding<String>,
        focusRequest: Binding<Bool>,
        state: KPrimitiveInteractionState,
        placeholder: String,
        contextTarget: ChatComposerTarget? = nil,
        contextStats: ContextStats?,
        onAttach: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        onStop: @escaping () -> Void,
        contextRingExpanded: Binding<Bool>? = nil,
        contextPanelTarget: String? = nil,
        inputAccessibilityIdentifier: String = "chat-composer",
        sendAccessibilityIdentifier: String = "chat-send"
    ) {
        _text = text
        _focusRequest = focusRequest
        self.state = state
        self.placeholder = placeholder
        self.contextTarget = contextTarget
        self.contextStats = contextStats
        self.onAttach = onAttach
        self.onSubmit = onSubmit
        self.onStop = onStop
        self.contextRingExpanded = contextRingExpanded
        self.contextPanelTarget = contextPanelTarget
        self.inputAccessibilityIdentifier = inputAccessibilityIdentifier
        self.sendAccessibilityIdentifier = sendAccessibilityIdentifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.inputStatusSpacing) {
            KScrollEdgeFade()

            if let contextTarget {
                Button(action: { contextRingBinding.wrappedValue.toggle() }) {
                    contextTargetLine(for: contextTarget)
                }
                .buttonStyle(.plain)
                .disabled(contextStats == nil)
                .accessibilityIdentifier("chat-composer-target")
            }

            HStack(alignment: .bottom, spacing: KStyle.inputBarSpacing) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(KStyle.inputControlFont)
                        .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                        .frame(width: KStyle.inputControlSize, height: KStyle.inputControlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KCopy.chatAttach)
                .accessibilityIdentifier("chat-attach")

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        composerPrompt
                            .id(placeholder)
                            .padding(.horizontal, KStyle.inputHorizontalPadding)
                            .padding(.vertical, KStyle.inputVerticalPadding)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($composerFocused)
                        .font(KStyle.inputFont)
                        .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                        .lineLimit(KStyle.inputMinLineCount...KStyle.inputDefaultMaxLineCount)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .keyboardType(.default)
                        .submitLabel(.send)
                        .padding(.horizontal, KStyle.inputHorizontalPadding)
                        .padding(.vertical, KStyle.inputVerticalPadding)
                        .onSubmit {
                            if canSubmit {
                                onSubmit()
                            }
                        }
                        .accessibilityLabel(KCopy.chatMessageK)
                        .accessibilityHint(KCopy.chatDictationHint)
                        .accessibilityIdentifier(inputAccessibilityIdentifier)
                }
                .frame(minHeight: KStyle.minimumTapTarget)
                .kInputFieldTone()
                .animation(KStyle.chatContentSwapMotion(reduceMotion), value: placeholder)

                if let contextStats {
                    ContextRing(
                        stats: contextStats,
                        isExpanded: contextRingBinding,
                        target: contextTarget,
                        panelTarget: contextPanelTarget
                    )
                }

                Button(action: primaryControlTapped) {
                    Image(systemName: controlSymbol)
                        .font(KStyle.inputControlFont)
                        .frame(width: KStyle.inputControlSize, height: KStyle.inputControlSize)
                        .foregroundStyle(controlForeground)
                        .background {
                            Circle().fill(controlFill)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!primaryControlEnabled)
                .accessibilityLabel(controlAccessibilityLabel)
                .accessibilityIdentifier(sendAccessibilityIdentifier)
            }
            .padding(.horizontal, KStyle.inputSidePadding)
            .padding(.trailing, KStyle.inputTrailingPadding)
        }
        .padding(.bottom, KStyle.inputBottomPadding)
        .kAnimated(value: state)
        .onAppear {
            if KLoadingPreview.isEnabled, ChatDemoFixture.isEnabled() {
                // The loading capture is an intentional first-fetch story. Keep
                // the seeded composer in the focus path so XCUI can type into
                // the same 44pt input the founder would use.
                composerFocused = true
            }
            applyFocusRequest()
        }
        .onChange(of: focusRequest) { _, _ in
            applyFocusRequest()
        }
    }

    private func contextTargetLine(for target: ChatComposerTarget) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.microSpacing) {
            switch target {
            case .trunk:
                Text(KCopy.chatTrunkTarget)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
            case .thread(_, let title):
                Text(composerTargetTitle(title))
                    .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    .lineLimit(KStyle.singleLineLimit)
            }
        }
        .kFont(.monoCaption)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, KStyle.inputSidePadding)
        .padding(.trailing, KStyle.inputTrailingPadding + KStyle.inputControlSize + KStyle.inputBarSpacing)
        .contentShape(Rectangle())
    }

    private func composerTargetTitle(_ title: String) -> String {
        let line = title
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (line?.isEmpty == false ? line! : KCopy.chatReadyToExplore).lowercased()
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !normalizedText.isEmpty
    }

    private var canStop: Bool {
        state == .loading && normalizedText.isEmpty
    }

    private var primaryControlEnabled: Bool {
        canSubmit || canStop
    }

    private var controlSymbol: String {
        canStop ? "stop" : "arrow.up"
    }

    private var controlAccessibilityLabel: String {
        canStop ? KCopy.chatStop : KCopy.chatSend
    }

    private var controlForeground: Color {
        primaryControlEnabled
            ? Color.black.opacity(KStyle.primaryControlTextOpacity)
            : Color.white.opacity(KStyle.tertiaryTextOpacity)
    }

    private var controlFill: Color {
        if state == .loading {
            return Color.white.opacity(KStyle.controlPendingFillOpacity)
        }
        return primaryControlEnabled
            ? Color.white.opacity(KStyle.controlEnabledFillOpacity)
            : Color.white.opacity(KStyle.controlDisabledFillOpacity)
    }

    private var composerPrompt: Text {
        Text(placeholder)
            .foregroundColor(Color.white.opacity(KStyle.quaternaryTextOpacity))
    }

    private func primaryControlTapped() {
        if canSubmit {
            onSubmit()
        } else if canStop {
            onStop()
        }
    }

    private func applyFocusRequest() {
        guard focusRequest else { return }
        composerFocused = true
        focusRequest = false
    }

    private var contextRingBinding: Binding<Bool> {
        contextRingExpanded ?? $contextRingExpandedState
    }
}

private enum ChatScrollID {
    static let coordinateSpace = "chat-scroll"
}

enum ChatScrollTarget: Hashable {
    case top
    case message(UUID)
    case queued(UUID)
    case bottom
}

enum ChatScrollContext: Hashable {
    case trunk
    case branch(String)
}

enum ChatScrollAnchorLogic {
    static func latestTarget(
        messages: [Message],
        queuedMessages: [QueuedChatMessage]
    ) -> ChatScrollTarget {
        if let queued = queuedMessages.last { return .queued(queued.id) }
        if let message = messages.last { return .message(message.id) }
        return .bottom
    }

    static func context(for branchID: String?) -> ChatScrollContext {
        guard let branchID, !branchID.isEmpty else { return .trunk }
        return .branch(branchID)
    }
}

private struct ChatBottomYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension ChatMessagePresentation {
    var streamRole: KStreamRowRole {
        alignment == .trailing ? .founder : .k
    }

    var horizontalAlignment: HorizontalAlignment {
        alignment == .trailing ? .trailing : .leading
    }

    var textAlignment: TextAlignment {
        alignment == .trailing ? .trailing : .leading
    }

}

private extension View {
    @ViewBuilder
    func chatDefaultScrollAnchor() -> some View {
        if #available(iOS 18.0, *) {
            self.defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            self.defaultScrollAnchor(.bottom)
        }
    }

    @ViewBuilder
    func chatScrollGeometryTracking(onDistance: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height)
            } action: { _, distance in
                onDistance(distance)
            }
        } else {
            self
        }
    }
}

// Chain-of-thought never reaches the founder's screen. The server scrubs at the
// model seam; this is the view-side guarantee — it also heals messages persisted
// before the server scrubber shipped (founder report 2026-07-10).
enum ChatThoughtScrubber {
    static func scrubbed(_ message: Message) -> Message {
        guard message.role != .you else { return message }
        var clean = message
        clean.text = scrubbedText(message.text)
        return clean
    }

    static func scrubbedText(_ text: String) -> String {
        var result = text
        // Closed think blocks (any casing, multiline) drop entirely.
        while let open = result.range(of: "<think>", options: .caseInsensitive),
              let close = result.range(of: "</think>", options: .caseInsensitive),
              open.lowerBound < close.upperBound {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        // An unclosed think block (mid-stream) hides everything from the tag on;
        // the closing tag arrives with a later token and the block drops above.
        if let open = result.range(of: "<think>", options: .caseInsensitive) {
            result.removeSubrange(open.lowerBound..<result.endIndex)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
