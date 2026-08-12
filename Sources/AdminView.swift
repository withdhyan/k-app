import Foundation
import SwiftUI

enum AdminItemType: Codable, Equatable, Hashable, Identifiable, Sendable {
    case timeSensitive
    case regularQueue
    case recurring
    case unknown(String)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .timeSensitive:
            return "TimeSensitive"
        case .regularQueue:
            return "RegularQueue"
        case .recurring:
            return "Recurring"
        case .unknown(let value):
            return value
        }
    }

    var title: String {
        switch self {
        case .timeSensitive:
            return "time sensitive"
        case .regularQueue:
            return "regular queue"
        case .recurring:
            return "recurring"
        case .unknown(let value):
            return value.replacingOccurrences(of: "_", with: " ").lowercased()
        }
    }

    var sortRank: Int {
        switch self {
        case .timeSensitive:
            return 0
        case .regularQueue:
            return 1
        case .recurring:
            return 2
        case .unknown:
            return 3
        }
    }

    init(rawValue: String) {
        switch AdminTextNormalizer.key(rawValue) {
        case "timesensitive":
            self = .timeSensitive
        case "regularqueue":
            self = .regularQueue
        case "recurring":
            self = .recurring
        default:
            self = .unknown(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AdminEffort: Codable, Equatable, Sendable {
    case quick
    case hour
    case hours
    case unknown(String)

    var rawValue: String {
        switch self {
        case .quick:
            return "Quick"
        case .hour:
            return "Hour"
        case .hours:
            return "Hours"
        case .unknown(let value):
            return value
        }
    }

    var title: String {
        rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    var sortRank: Int {
        switch self {
        case .quick:
            return 0
        case .hour:
            return 1
        case .hours:
            return 2
        case .unknown:
            return 3
        }
    }

    init(rawValue: String) {
        switch AdminTextNormalizer.key(rawValue) {
        case "quick":
            self = .quick
        case "hour":
            self = .hour
        case "hours":
            self = .hours
        default:
            self = .unknown(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AdminItemAction: String, Equatable, Sendable {
    case complete
    case reschedule
}

struct AdminItem: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var type: AdminItemType
    var effort: AdminEffort
    var remindAt: String?
    var dueAt: String?
    var status: String
    var verbs: [String]
    var actionPaths: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case effort
        case remindAt
        case dueAt
        case status
        case state
        case verbs
        case actions
        case completePath
        case reschedulePath
    }

    init(
        id: String,
        title: String,
        type: AdminItemType,
        effort: AdminEffort,
        remindAt: String? = nil,
        dueAt: String? = nil,
        status: String = "open",
        verbs: [String] = [],
        actionPaths: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.effort = effort
        self.remindAt = remindAt
        self.dueAt = dueAt
        self.status = status
        self.verbs = verbs.map(AdminTextNormalizer.key)
        self.actionPaths = Dictionary(
            uniqueKeysWithValues: actionPaths.map { (AdminTextNormalizer.key($0.key), $0.value) }
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? container.decode(String.self, forKey: .title)) ?? "untitled op"
        type = AdminItemType(rawValue: (try? container.decode(String.self, forKey: .type)) ?? "RegularQueue")
        effort = AdminEffort(rawValue: (try? container.decode(String.self, forKey: .effort)) ?? "Hour")
        remindAt = try? container.decodeIfPresent(String.self, forKey: .remindAt)
        dueAt = try? container.decodeIfPresent(String.self, forKey: .dueAt)
        status = (try? container.decodeIfPresent(String.self, forKey: .status))
            ?? (try? container.decodeIfPresent(String.self, forKey: .state))
            ?? "open"
        let decodedVerbs = (try? container.decodeIfPresent([String].self, forKey: .verbs)) ?? []
        let actions = (try? container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .actions)) ?? [:]
        var decodedPaths = Self.actionPaths(from: actions)
        if let completePath = try? container.decodeIfPresent(String.self, forKey: .completePath) {
            decodedPaths["complete"] = completePath
        }
        if let reschedulePath = try? container.decodeIfPresent(String.self, forKey: .reschedulePath) {
            decodedPaths["reschedule"] = reschedulePath
        }
        verbs = Self.normalizedVerbs(decodedVerbs, actions: actions)
        actionPaths = decodedPaths
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(effort, forKey: .effort)
        try container.encodeIfPresent(remindAt, forKey: .remindAt)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encode(status, forKey: .status)
        if !verbs.isEmpty { try container.encode(verbs, forKey: .verbs) }
        if !actionPaths.isEmpty {
            try container.encode(
                Dictionary(uniqueKeysWithValues: actionPaths.map { ($0.key, ViewPacketJSONValue.string($0.value)) }),
                forKey: .actions
            )
        }
    }

    var isCompleted: Bool {
        let value = AdminTextNormalizer.key(status)
        return ["complete", "completed", "done", "closed"].contains(value)
    }

    func supports(_ action: AdminItemAction) -> Bool {
        let key = action.rawValue
        return verbs.contains(key) || actionPaths[key] != nil
    }

    func actionPath(for action: AdminItemAction) -> String? {
        actionPaths[action.rawValue]
    }

    func completedCopy() -> AdminItem {
        var copy = self
        copy.status = "completed"
        return copy
    }

    func rescheduledCopy(days: Int = 1, now: Date = Date(), calendar: Calendar = CadenceDateParser.pinnedCalendar) -> AdminItem {
        var copy = self
        copy.dueAt = AdminDateSupport.shiftedDateString(dueAt, days: days, now: now, calendar: calendar)
        if remindAt != nil {
            copy.remindAt = AdminDateSupport.shiftedDateString(remindAt, days: days, now: now, calendar: calendar)
        }
        copy.status = status.isEmpty ? "open" : status
        return copy
    }

    private static func normalizedVerbs(
        _ verbs: [String],
        actions: [String: ViewPacketJSONValue]
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in verbs + actions.keys {
            let key = AdminTextNormalizer.key(value)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(key)
        }
        return result
    }

    private static func actionPaths(from actions: [String: ViewPacketJSONValue]) -> [String: String] {
        var paths: [String: String] = [:]
        for (key, value) in actions {
            let normalizedKey = AdminTextNormalizer.key(key)
            if let path = value.stringValue, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                paths[normalizedKey] = path
                continue
            }
            guard let object = value.objectValue else { continue }
            for pathKey in ["path", "url", "href"] {
                if let path = object[pathKey]?.stringValue,
                   !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    paths[normalizedKey] = path
                    break
                }
            }
        }
        return paths
    }
}

struct AdminBandishResponse: Codable, Equatable, Sendable {
    var records: [AdminItem]
    var sort: [String]

    enum CodingKeys: String, CodingKey {
        case records
        case items
        case sort
    }

    init(records: [AdminItem], sort: [String] = []) {
        self.records = records
        self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let records = try? single.decode([AdminItem].self) {
            self.records = records
            sort = []
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = (try? container.decode(AdminLossyDecodableArray<AdminItem>.self, forKey: .records).elements)
            ?? (try? container.decode(AdminLossyDecodableArray<AdminItem>.self, forKey: .items).elements)
            ?? []
        sort = (try? container.decodeIfPresent([String].self, forKey: .sort)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
        try container.encode(sort, forKey: .sort)
    }
}

struct AdminParseResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var error: String?
    var parsed: [String: ViewPacketJSONValue]
    var confirmToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: ViewPacketJSONValue].self)
        ok = object["ok"]?.boolValue
        error = object["error"]?.stringValue
        confirmToken = object["confirmToken"]?.stringValue ?? object["token"]?.stringValue

        if let parsedValue = object["parsed"] {
            parsed = parsedValue.objectValue ?? ["parsed": parsedValue]
        } else {
            let reservedKeys = Set(["ok", "error", "confirmToken", "token"])
            parsed = object.filter { !reservedKeys.contains($0.key) }
        }
    }
}

struct AdminMutationResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var error: String?
    var item: AdminItem?
    var records: [AdminItem]?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case item
        case record
        case records
        case items
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let object = try? single.decode([String: ViewPacketJSONValue].self),
           object["ok"] == nil,
           object["error"] == nil,
           object["id"] != nil || object["title"] != nil {
            let data = try JSONEncoder().encode(object)
            if let item = try? JSONDecoder().decode(AdminItem.self, from: data) {
                ok = true
                error = nil
                self.item = item
                records = nil
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        item = (try? container.decodeIfPresent(AdminItem.self, forKey: .item))
            ?? (try? container.decodeIfPresent(AdminItem.self, forKey: .record))
        records = (try? container.decodeIfPresent(AdminLossyDecodableArray<AdminItem>.self, forKey: .records)?.elements)
            ?? (try? container.decodeIfPresent(AdminLossyDecodableArray<AdminItem>.self, forKey: .items)?.elements)
    }
}

private struct AdminLossyDecodableArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []

        while !container.isAtEnd {
            do {
                values.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(ViewPacketJSONValue.self)
            }
        }

        elements = values
    }
}

struct AdminParsedField: Identifiable, Equatable, Sendable {
    var key: String
    var value: String

    var id: String { key }
}

struct AdminParseDraft: Equatable, Sendable {
    var fields: [AdminParsedField]
    var confirmToken: String?

    init(parsed: [String: ViewPacketJSONValue], confirmToken: String? = nil) {
        fields = Self.orderedFields(from: parsed)
        self.confirmToken = confirmToken
    }

    var fieldValues: [String: ViewPacketJSONValue] {
        Dictionary(uniqueKeysWithValues: fields.map { field in
            (field.key, ViewPacketJSONValue.string(field.value))
        })
    }

    mutating func update(key: String, value: String) {
        guard let index = fields.firstIndex(where: { $0.key == key }) else { return }
        fields[index].value = value
    }

    func value(for key: String) -> String {
        fields.first(where: { $0.key == key })?.value ?? ""
    }

    private static func orderedFields(from parsed: [String: ViewPacketJSONValue]) -> [AdminParsedField] {
        let priority = ["title", "type", "effort", "remindAt", "dueAt"]
        let normalizedPriority = Dictionary(uniqueKeysWithValues: priority.enumerated().map { offset, key in
            (AdminTextNormalizer.key(key), offset)
        })

        return parsed
            .map { key, value in
                AdminParsedField(key: key, value: value.description)
            }
            .sorted { left, right in
                let leftRank = normalizedPriority[AdminTextNormalizer.key(left.key)] ?? Int.max
                let rightRank = normalizedPriority[AdminTextNormalizer.key(right.key)] ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return left.key < right.key
            }
    }
}

enum AdminIntakeState: Equatable {
    case idle
    case submitting
    case confirming(AdminParseDraft)
    case committing(AdminParseDraft)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .submitting, .committing:
            return true
        case .idle, .confirming, .failed:
            return false
        }
    }

    var parseDraft: AdminParseDraft? {
        switch self {
        case .confirming(let draft), .committing(let draft):
            return draft
        case .idle, .submitting, .failed:
            return nil
        }
    }

    var isCommitting: Bool {
        if case .committing = self { return true }
        return false
    }

    var statusText: String? {
        switch self {
        case .idle:
            return nil
        case .submitting:
            return "parsing"
        case .confirming:
            return "confirm parse"
        case .committing:
            return "committing"
        case .failed(let text):
            return text
        }
    }
}

enum AdminLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct AdminItemSection: Identifiable, Equatable {
    var type: AdminItemType
    var records: [AdminItem]

    var id: String { type.id }

    static func build(records: [AdminItem]) -> [AdminItemSection] {
        var seen: Set<AdminItemType> = []
        let types = records
            .map(\.type)
            .filter { seen.insert($0).inserted }
            .sorted { left, right in
                if left.sortRank != right.sortRank { return left.sortRank < right.sortRank }
                return left.title < right.title
            }

        return types.map { type in
            AdminItemSection(type: type, records: records.filter { $0.type == type })
        }
    }
}

enum AdminBandishSorter {
    static func sorted(
        records: [AdminItem],
        sort: [String],
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> [AdminItem] {
        let keys = sort.map(AdminTextNormalizer.key).filter { !$0.isEmpty }
        guard !keys.isEmpty else { return records }

        return records.enumerated()
            .sorted { left, right in
                for key in keys {
                    let comparison = compare(left.element, right.element, key: key, calendar: calendar)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private static func compare(
        _ left: AdminItem,
        _ right: AdminItem,
        key: String,
        calendar: Calendar
    ) -> ComparisonResult {
        switch key {
        case "remindat", "remind":
            return AdminDateSupport.compare(left.remindAt, right.remindAt, calendar: calendar)
        case "dueat", "due":
            return AdminDateSupport.compare(left.dueAt, right.dueAt, calendar: calendar)
        case "effort":
            if left.effort.sortRank != right.effort.sortRank {
                return left.effort.sortRank < right.effort.sortRank ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        default:
            return .orderedSame
        }
    }
}

enum AdminTabDotLogic {
    static func dueTodayCount(
        records: [AdminItem],
        now: Date = Date(),
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> Int {
        records.filter { item in
            item.type == .timeSensitive
                && !item.isCompleted
                && AdminDateSupport.isToday(item.dueAt, now: now, calendar: calendar)
        }.count
    }
}

struct AdminBandishStore {
    private struct StoredBandish: Codable {
        var version: Int
        var response: AdminBandishResponse
        var savedAt: Date?
    }

    struct CachedBandish: Equatable {
        var response: AdminBandishResponse
        var savedAt: Date
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = AdminBandishStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("admin-bandish.json", isDirectory: false)
    }

    func load() -> AdminBandishResponse? {
        loadEntry()?.response
    }

    func loadEntry() -> CachedBandish? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try JSONDecoder().decode(StoredBandish.self, from: data)
            guard stored.version == 1 || stored.version == 2 else { return nil }
            return CachedBandish(response: stored.response, savedAt: stored.savedAt ?? fileModifiedAt())
        } catch {
            NSLog("[K] admin cache load failed at %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    func save(_ response: AdminBandishResponse, syncedAt: Date = Date()) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(StoredBandish(version: 2, response: response, savedAt: syncedAt))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] admin cache save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func fileModifiedAt() -> Date {
        ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date) ?? Date(timeIntervalSince1970: 0)
    }
}

@MainActor
final class AdminModel: ObservableObject {
    @Published private(set) var records: [AdminItem] = []
    @Published private(set) var sort: [String] = []
    @Published private(set) var loadState: AdminLoadState = .idle
    @Published private(set) var connectionState = KConnectionStateModel()
    @Published private(set) var offlineCaption: String?
    @Published private(set) var loadErrorText: String?
    @Published private(set) var intakeState: AdminIntakeState = .idle
    @Published private(set) var intakeErrorText: String?
    @Published private(set) var pendingItemActionIDs: Set<String> = []
    @Published private(set) var itemActionErrorTexts: [String: String] = [:]
    @Published private(set) var queuedActionTexts: [String: String] = [:]
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var isLoading = false
    @Published var draft: String = ""
    @Published var baseURL: String

    private let clientFactory: (String) -> AGUIClient
    private let cacheStore: AdminBandishStore
    private let now: () -> Date
    private let censusFixtureEnabled: Bool
    private var calendar: Calendar
    private var hasLoaded = false

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        cacheStore: AdminBandishStore = AdminBandishStore(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.cacheStore = cacheStore
        self.now = now
        censusFixtureEnabled = CensusRemainderFixture.isEnabled()
        self.calendar = calendar
        if KLoadingPreview.isEnabled {
            loadState = .loading
            isLoading = true
            connectionState.transition(to: .connecting)
        }
    }

    var sortedRecords: [AdminItem] {
        AdminBandishSorter.sorted(records: records, sort: sort, calendar: calendar)
    }

    var sections: [AdminItemSection] {
        AdminItemSection.build(records: sortedRecords)
    }

    var dueTodayCount: Int {
        AdminTabDotLogic.dueTodayCount(records: records, now: now(), calendar: calendar)
    }

    var canSubmitIntake: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !intakeState.isBusy
    }

    var emptyText: String {
        "no quarantined ops"
    }

    var stalenessText: String? {
        guard isStale, let lastSyncAt else { return nil }
        return KTimestampFormatter.asOf(lastSyncAt, timeZone: calendar.timeZone)
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadState != .loading else { return }
        if censusFixtureEnabled {
            loadCensusFixture()
            return
        }
        if KLoadingPreview.isEnabled {
            loadState = .loading
            isLoading = true
            connectionState.transition(to: .connecting)
            return
        }
        Task { await load() }
    }

    func load() async {
        if censusFixtureEnabled {
            loadCensusFixture()
            return
        }
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        isLoading = true
        if records.isEmpty {
            loadState = .loading
            connectionState.transition(to: .connecting)
        } else {
            connectionState.transition(to: .reconnecting)
        }
        loadErrorText = nil
        offlineCaption = nil

        if KLoadingPreview.isEnabled { return }

        let client = clientFactory(baseURL)
        do {
            let response = try await client.adminBandish()
            apply(response, saveCache: true)
            connectionState.transition(to: .live)
            loadState = .loaded
            isLoading = false
            hasLoaded = true
        } catch {
            do {
                let response = try await client.adminItems()
                apply(response, saveCache: true)
                connectionState.transition(to: .live)
                loadState = .loaded
                isLoading = false
                hasLoaded = true
            } catch {
                loadFromCacheOrFail(error: error)
            }
        }
    }

    func apply(_ response: AdminBandishResponse, saveCache: Bool = false) {
        records = response.records
        sort = response.sort
        queuedActionTexts = queuedActionTexts.filter { queued in
            records.contains { $0.id == queued.key }
        }
        if saveCache {
            let syncedAt = now()
            lastSyncAt = syncedAt
            isStale = false
            cacheStore.save(response, syncedAt: syncedAt)
        }
    }

    func submitIntake() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !intakeState.isBusy else { return }

        intakeState = .submitting
        intakeErrorText = nil
        do {
            let response = try await clientFactory(baseURL).parseAdminIntake(text: text)
            guard response.ok != false else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                intakeState = .failed(Self.failureText(reason: reason?.isEmpty == false ? reason! : "unknown"))
                return
            }

            let parseDraft = AdminParseDraft(parsed: response.parsed, confirmToken: response.confirmToken)
            guard !parseDraft.fields.isEmpty else {
                intakeState = .failed(Self.failureText(reason: "empty parse"))
                return
            }

            draft = ""
            intakeState = .confirming(parseDraft)
        } catch {
            intakeState = .failed(Self.failureText(reason: error.localizedDescription))
        }
    }

    func updateParsedField(key: String, value: String) {
        guard case .confirming(var parseDraft) = intakeState else { return }
        parseDraft.update(key: key, value: value)
        intakeState = .confirming(parseDraft)
    }

    func parsedFieldValue(for key: String) -> String {
        intakeState.parseDraft?.value(for: key) ?? ""
    }

    func cancelIntake() {
        intakeState = .idle
        intakeErrorText = nil
    }

    func confirmParsedIntake() async {
        guard case .confirming(let parseDraft) = intakeState else { return }
        intakeState = .committing(parseDraft)
        intakeErrorText = nil

        do {
            let response = try await clientFactory(baseURL).confirmAdminIntake(
                fields: parseDraft.fieldValues,
                confirmToken: parseDraft.confirmToken
            )
            guard response.ok != false else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                intakeState = .confirming(parseDraft)
                intakeErrorText = Self.failureText(reason: reason?.isEmpty == false ? reason! : "unknown")
                return
            }

            if !applyMutationResponse(response) {
                await load()
            }
            intakeState = .idle
        } catch {
            intakeState = .confirming(parseDraft)
            intakeErrorText = Self.failureText(reason: error.localizedDescription)
        }
    }

    func complete(_ item: AdminItem) async {
        await perform(.complete, on: item)
    }

    func reschedule(_ item: AdminItem) async {
        await perform(.reschedule, on: item)
    }

    func itemActionErrorText(for item: AdminItem) -> String? {
        itemActionErrorTexts[item.id]
    }

    func queuedActionText(for item: AdminItem) -> String? {
        queuedActionTexts[item.id]
    }

    private func perform(_ action: AdminItemAction, on item: AdminItem) async {
        guard !pendingItemActionIDs.contains(item.id) else { return }
        let original = item
        let optimistic = optimisticCopy(for: action, item: item)
        upsert(optimistic, saveCache: false)
        itemActionErrorTexts[item.id] = nil

        if censusFixtureEnabled {
            queuedActionTexts[item.id] = nil
            pendingItemActionIDs.remove(item.id)
            lastSyncAt = CensusRemainderFixture.referenceNow
            isStale = false
            return
        }

        guard item.supports(action) else {
            queuedActionTexts[item.id] = "\(action.rawValue) queued"
            cacheStore.save(AdminBandishResponse(records: records, sort: sort), syncedAt: now())
            return
        }

        pendingItemActionIDs.insert(item.id)
        queuedActionTexts[item.id] = nil
        do {
            let response: AdminMutationResponse
            switch action {
            case .complete:
                response = try await clientFactory(baseURL).completeAdminItem(
                    id: item.id,
                    actionPath: item.actionPath(for: .complete)
                )
            case .reschedule:
                response = try await clientFactory(baseURL).rescheduleAdminItem(
                    id: item.id,
                    remindAt: optimistic.remindAt,
                    dueAt: optimistic.dueAt,
                    actionPath: item.actionPath(for: .reschedule)
                )
            }

            guard response.ok != false else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                revert(original, reason: reason?.isEmpty == false ? reason! : "unknown")
                pendingItemActionIDs.remove(item.id)
                return
            }

            applyMutationResponse(response)
            cacheStore.save(AdminBandishResponse(records: records, sort: sort), syncedAt: now())
        } catch {
            revert(original, reason: error.localizedDescription)
        }

        pendingItemActionIDs.remove(item.id)
    }

    private func optimisticCopy(for action: AdminItemAction, item: AdminItem) -> AdminItem {
        switch action {
        case .complete:
            return item.completedCopy()
        case .reschedule:
            return item.rescheduledCopy(now: now(), calendar: calendar)
        }
    }

    private func revert(_ item: AdminItem, reason: String) {
        upsert(item, saveCache: false)
        itemActionErrorTexts[item.id] = Self.failureText(reason: reason)
    }

    @discardableResult
    private func applyMutationResponse(_ response: AdminMutationResponse) -> Bool {
        if let records = response.records {
            apply(AdminBandishResponse(records: records, sort: sort), saveCache: true)
            return true
        } else if let item = response.item {
            upsert(item, saveCache: true)
            return true
        }
        return false
    }

    private func upsert(_ item: AdminItem, saveCache: Bool) {
        if let index = records.firstIndex(where: { $0.id == item.id }) {
            records[index] = item
        } else {
            records.append(item)
        }

        if saveCache {
            let syncedAt = now()
            lastSyncAt = syncedAt
            isStale = false
            cacheStore.save(AdminBandishResponse(records: records, sort: sort), syncedAt: syncedAt)
        }
    }

    private func loadFromCacheOrFail(error: Error) {
        if let cached = cacheStore.loadEntry() {
            apply(cached.response)
            lastSyncAt = cached.savedAt
            isStale = true
            offlineCaption = "backend unavailable; showing saved view"
            connectionState.transition(to: .offlineRetrying)
            loadState = .loaded
            isLoading = false
            hasLoaded = true
            return
        }

        let text = Self.failureText(reason: error.localizedDescription)
        loadErrorText = text
        loadState = .failed(text)
        connectionState.transition(to: .offlineRetrying)
        isLoading = false
        hasLoaded = true
    }

    private func loadCensusFixture() {
        apply(CensusRemainderFixture.adminResponse)
        lastSyncAt = CensusRemainderFixture.referenceNow
        isStale = false
        offlineCaption = nil
        loadErrorText = nil
        loadState = .loaded
        isLoading = false
        hasLoaded = true
        connectionState.transition(to: .live)
    }

    private static func failureText(reason: String) -> String {
        KCopy.answerFailed(reason: reason)
    }
}

struct AdminView: View {
    @StateObject private var model = AdminModel()
    let onDueTodayCountChange: (Int) -> Void
    let onStalenessChange: (Bool) -> Void

    init(
        onDueTodayCountChange: @escaping (Int) -> Void = { _ in },
        onStalenessChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onDueTodayCountChange = onDueTodayCountChange
        self.onStalenessChange = onStalenessChange
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                adminColumn(width: columnWidth(in: proxy.size.width))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, KStyle.columnMargin)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("admin-view")
        .onAppear {
            model.loadIfNeeded()
            onDueTodayCountChange(model.dueTodayCount)
            onStalenessChange(model.isStale)
        }
        .onChange(of: model.dueTodayCount) { _, count in
            onDueTodayCountChange(count)
        }
        .onChange(of: model.isStale) { _, isStale in
            onStalenessChange(isStale)
        }
    }

    private func columnWidth(in availableWidth: CGFloat) -> CGFloat {
        min(KStyle.readingMeasureMaxWidth, max(0, availableWidth - KStyle.columnMargin * 2))
    }

    private func adminColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)

            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AdminIntakePanel(
                text: $model.draft,
                state: model.intakeState,
                errorText: model.intakeErrorText,
                canSubmit: model.canSubmitIntake,
                fieldValue: { model.parsedFieldValue(for: $0) },
                onFieldChange: model.updateParsedField(key:value:),
                onSubmit: {
                    Task { await model.submitIntake() }
                },
                onConfirm: {
                    Task { await model.confirmParsedIntake() }
                },
                onCancel: model.cancelIntake
            )
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .kAnimated(value: model.sections)
        .kAnimated(value: model.intakeState)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let stalenessText = model.stalenessText {
                Text(stalenessText.lowercased())
                    .kFont(.monoCaptionDigit)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            }
            if model.isLoading, !model.records.isEmpty {
                KLoadingPrimitive(
                    variant: .dot,
                    label: "loading admin",
                    accessibilityIdentifier: "admin-loading"
                )
            }
            Spacer(minLength: 12)
            Text("\(model.records.count) ops")
                .kFont(.monoCaptionDigit)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.loadState == .loading && model.records.isEmpty {
            KLoadingPrimitive(
                variant: .skeleton,
                lineCount: 3,
                label: "loading admin",
                accessibilityIdentifier: "admin-loading"
            )
            .padding(18)
        } else if let loadErrorText = model.loadErrorText, model.records.isEmpty {
            AdminErrorView(text: loadErrorText) {
                Task { await model.load() }
            }
        } else if model.records.isEmpty {
            ScrollView {
                Text(model.emptyText)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .refreshable {
                await model.load()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let offlineCaption = model.offlineCaption {
                        Text(offlineCaption)
                            .kFont(.monoCaption)
                            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                            .textSelection(.enabled)
                    }

                    ForEach(model.sections) { section in
                        AdminSectionView(
                            section: section,
                            isPending: { model.pendingItemActionIDs.contains($0.id) },
                            errorText: { model.itemActionErrorText(for: $0) },
                            queuedText: { model.queuedActionText(for: $0) },
                            onComplete: { item in
                                Task { await model.complete(item) }
                            },
                            onReschedule: { item in
                                Task { await model.reschedule(item) }
                            }
                        )
                    }
                }
                .padding(18)
                .padding(.trailing, 16)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await model.load()
            }
        }
    }
}

private struct AdminErrorView: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            KMonoCaption(text, variant: .inlineError, state: .error)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            KActRow(
                actions: [KActItem(id: "retry")],
                variant: .admin,
                onSelect: { _ in onRetry() }
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AdminSectionView: View {
    let section: AdminItemSection
    let isPending: (AdminItem) -> Bool
    let errorText: (AdminItem) -> String?
    let queuedText: (AdminItem) -> String?
    let onComplete: (AdminItem) -> Void
    let onReschedule: (AdminItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KMonoCaption(section.type.title, variant: .metadata)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(section.records) { item in
                    AdminItemRow(
                        item: item,
                        isPending: isPending(item),
                        errorText: errorText(item),
                        queuedText: queuedText(item),
                        onComplete: { onComplete(item) },
                        onReschedule: { onReschedule(item) }
                    )
                }
            }
        }
    }
}

private struct AdminItemRow: View {
    let item: AdminItem
    let isPending: Bool
    let errorText: String?
    let queuedText: String?
    let onComplete: () -> Void
    let onReschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.title.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(item.isCompleted ? KStyle.tertiaryTextOpacity : KStyle.primaryTextOpacity))
                    .strikethrough(item.isCompleted, color: .white.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                AdminDateEffortMeta(lines: dateMetaLines, effort: item.effort)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 7) {
                    actionButtons
                }
            }

            if let queuedText {
                KMonoCaption(queuedText, variant: .status)
            }

            if let errorText {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .textSelection(.enabled)
            }
        }
        .opacity(isPending ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
        .kAnimated(value: isPending)
        .kAnimated(value: errorText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("admin-item-\(item.id)")
    }

    private var actionButtons: some View {
        KActRow(
            actions: [
                KActItem(
                    id: "complete",
                    isEnabled: !item.isCompleted && !isPending,
                    accessibilityIdentifier: "admin-item-\(item.id)-complete"
                ),
                KActItem(
                    id: "reschedule",
                    isEnabled: !item.isCompleted && !isPending,
                    accessibilityIdentifier: "admin-item-\(item.id)-reschedule"
                ),
            ],
            variant: .admin,
            state: isPending ? .loading : .resting,
            onSelect: { item in
                if item.id == "complete" {
                    onComplete()
                } else {
                    onReschedule()
                }
            }
        )
    }

    private var dateMetaLines: [String] {
        var parts: [String] = []
        let normalizedRemind = item.remindAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDue = item.dueAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remindAt = normalizedRemind, !remindAt.isEmpty {
            parts.append("remind \(AdminDateSupport.display(remindAt))")
        }
        if let dueAt = normalizedDue, !dueAt.isEmpty, normalizedRemind != normalizedDue {
            parts.append("due \(AdminDateSupport.display(dueAt))")
        } else if normalizedRemind == nil, let dueAt = normalizedDue, !dueAt.isEmpty {
            parts.append("due \(AdminDateSupport.display(dueAt))")
        }
        return parts.isEmpty ? ["no dates"] : parts
    }
}

private struct AdminDateEffortMeta: View {
    let lines: [String]
    let effort: AdminEffort

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(lines.indices, id: \.self) { index in
                KMonoCaption(lines[index] + (index == lines.count - 1 ? " · \(effort.title)" : ""), variant: .staleness, state: .disabled)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: 190, alignment: .trailing)
    }
}

private struct AdminIntakePanel: View {
    @Binding var text: String
    let state: AdminIntakeState
    let errorText: String?
    let canSubmit: Bool
    let fieldValue: (String) -> String
    let onFieldChange: (String, String) -> Void
    let onSubmit: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.inputStatusSpacing) {
            if let parseDraft = state.parseDraft {
                AdminParseConfirmCard(
                    draft: parseDraft,
                    isCommitting: state.isCommitting,
                    errorText: errorText,
                    fieldValue: fieldValue,
                    onFieldChange: onFieldChange,
                    onConfirm: onConfirm,
                    onCancel: onCancel
                )
                .padding(.horizontal, 18)
                .padding(.trailing, 16)
                .transition(.opacity)
            }

            KInputBar(
                text: $text,
                mode: .admin,
                state: inputState,
                statusText: statusText,
                disabledReason: disabledReason,
                onSubmit: {
                    if canSubmit {
                        onSubmit()
                    }
                }
            )
        }
        .kAnimated(value: state)
    }

    private var inputState: KPrimitiveInteractionState {
        switch state {
        case .failed:
            return .error
        case .idle, .confirming, .submitting, .committing:
            return .resting
        }
    }

    private var disabledReason: String? {
        state.isBusy ? state.statusText : nil
    }

    private var statusText: String? {
        state.isBusy ? nil : state.statusText
    }
}

private struct AdminParseConfirmCard: View {
    let draft: AdminParseDraft
    let isCommitting: Bool
    let errorText: String?
    let fieldValue: (String) -> String
    let onFieldChange: (String, String) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        KPaperCard(state: isCommitting ? .loading : .resting) {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                KMonoCaption("parsed", variant: .metadata)

                ForEach(draft.fields) { field in
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        KMonoCaption(field.key.replacingOccurrences(of: "_", with: " "), variant: .metadata, state: .disabled)

                        TextField(field.key.lowercased(), text: Binding(
                            get: { fieldValue(field.key) },
                            set: { onFieldChange(field.key, $0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                        .padding(.horizontal, KStyle.inputHorizontalPadding)
                        .padding(.vertical, KStyle.inputVerticalPadding)
                        .frame(minHeight: KStyle.minimumTapTarget)
                        .kInputFieldTone()
                        .disabled(isCommitting)
                    }
                }

                KActRow(
                    actions: [
                        KActItem(id: "confirm", isEnabled: !isCommitting),
                        KActItem(id: "cancel", isEnabled: !isCommitting),
                    ],
                    variant: .admin,
                    state: isCommitting ? .loading : .resting,
                    onSelect: { item in
                        if item.id == "confirm" {
                            onConfirm()
                        } else {
                            onCancel()
                        }
                    }
                )

                if let errorText {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

enum AdminDateSupport {
    static func date(from value: String?, calendar: Calendar = CadenceDateParser.pinnedCalendar) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) {
            return date
        }

        return nil
    }

    static func compare(_ left: String?, _ right: String?, calendar: Calendar = CadenceDateParser.pinnedCalendar) -> ComparisonResult {
        let leftDate = date(from: left, calendar: calendar)
        let rightDate = date(from: right, calendar: calendar)

        switch (leftDate, rightDate) {
        case (.some(let leftDate), .some(let rightDate)):
            return leftDate.compare(rightDate)
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            let leftText = left?.lowercased() ?? ""
            let rightText = right?.lowercased() ?? ""
            return leftText.compare(rightText)
        }
    }

    static func isToday(_ value: String?, now: Date = Date(), calendar: Calendar = CadenceDateParser.pinnedCalendar) -> Bool {
        guard let date = date(from: value, calendar: calendar) else { return false }
        return calendar.isDate(date, inSameDayAs: now)
    }

    static func display(_ value: String, calendar: Calendar = CadenceDateParser.pinnedCalendar) -> String {
        guard let date = date(from: value, calendar: calendar) else {
            return value.lowercased()
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }

    static func shiftedDateString(
        _ value: String?,
        days: Int,
        now: Date,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String {
        let base = date(from: value, calendar: calendar) ?? now
        let shifted = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return dateOnlyString(for: shifted, calendar: calendar)
    }

    private static func dateOnlyString(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum AdminTextNormalizer {
    static func key(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
