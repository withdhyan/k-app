import SwiftUI
enum BuildPayload {
    static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key], let text = scalarString(value) else { continue }
            return text
        }
        return nil
    }

    static func int(in object: [String: ViewPacketJSONValue], keys: [String]) -> Int? {
        for key in keys {
            guard let value = object[key] else { continue }
            if case .number(let number) = value { return Int(number) }
            if let text = scalarString(value), let int = Int(text) { return int }
        }
        return nil
    }

    static func bool(in object: [String: ViewPacketJSONValue], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = object[key] else { continue }
            if case .bool(let bool) = value { return bool }
            if let text = scalarString(value)?.lowercased() {
                if ["true", "yes", "1"].contains(text) { return true }
                if ["false", "no", "0"].contains(text) { return false }
            }
        }
        return nil
    }

    static func values(in object: [String: ViewPacketJSONValue], keys: [String]) -> [ViewPacketJSONValue] {
        for key in keys {
            guard let value = object[key] else { continue }
            if let array = value.arrayValue { return array }
            if value != .null { return [value] }
        }
        return []
    }

    static func strings(from value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.flatMap { item -> [String] in
                if let object = item.objectValue {
                    return string(in: object, keys: ["path", "docPath", "artifactPath", "id", "title", "name", "label"]).map { [$0] } ?? []
                }
                return scalarString(item).map { [$0] } ?? []
            }
        }
        if let object = value.objectValue {
            return string(in: object, keys: ["path", "docPath", "artifactPath", "id", "title", "name", "label"]).map { [$0] } ?? []
        }
        return scalarString(value).map { [$0] } ?? []
    }

    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    static func documentPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.hasSuffix(".json") else { return nil }
        return trimmed
    }

    static func scalarString(_ value: ViewPacketJSONValue) -> String? {
        switch value {
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number, .bool:
            let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        case .object, .array, .null:
            return nil
        }
    }
}

struct BuildDocumentResponse: Decodable, Equatable, Sendable, Identifiable {
    var path: String?
    var title: String?
    var content: String
    var language: String?
    var truncated: Bool

    var id: String {
        path ?? title ?? String(content.prefix(24))
    }

    init(
        path: String? = nil,
        title: String? = nil,
        content: String,
        language: String? = nil,
        truncated: Bool = false
    ) {
        self.path = path
        self.title = title
        self.content = content
        self.language = language
        self.truncated = truncated
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let text = BuildPayload.scalarString(value) {
            self.init(content: text)
            return
        }

        guard let object = value.objectValue else {
            self.init(content: value.description)
            return
        }

        self.init(
            path: BuildPayload.string(in: object, keys: ["path", "repoPath", "artifactPath", "file"]),
            title: BuildPayload.string(in: object, keys: ["title", "name", "label"]),
            content: BuildPayload.string(in: object, keys: ["content", "text", "body", "markdown", "json"]) ?? "",
            language: BuildPayload.string(in: object, keys: ["language", "lang", "type"]),
            truncated: BuildPayload.bool(in: object, keys: ["truncated", "capped"]) ?? false
        )
    }

    static func decode(data: Data, fallbackPath: String) -> BuildDocumentResponse {
        if var decoded = try? JSONDecoder().decode(BuildDocumentResponse.self, from: data) {
            if decoded.path == nil {
                decoded.path = fallbackPath
            }
            if decoded.title == nil {
                decoded.title = fallbackPath
            }
            return decoded
        }
        return BuildDocumentResponse(
            path: fallbackPath,
            title: fallbackPath,
            content: String(data: data, encoding: .utf8) ?? "",
            language: nil,
            truncated: false
        )
    }
}

enum BuildEvidenceRenderKind: String, Equatable, Sendable {
    case text
    case transcript
    case image
    case gateOutput = "gate-output"

    var usesMonospacedBody: Bool {
        switch self {
        case .gateOutput:
            return true
        case .text, .transcript, .image:
            return false
        }
    }

    var founderTitle: String {
        switch self {
        case .gateOutput: return "gate output"
        case .transcript: return "transcript"
        case .image: return "image"
        case .text: return "evidence"
        }
    }
}

struct BuildEvidenceEntry: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: String
    var title: String?
    var text: String?
    var path: String?
    var imageReference: String?
    var diffId: String?
    var docPath: String?
    var createdAt: String?

    var renderKind: BuildEvidenceRenderKind {
        let normalized = kind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "gate-output", "gate", "gateoutput", "gate-output-log":
            return .gateOutput
        case "transcript", "conversation", "log-transcript":
            return .transcript
        case "image", "screenshot", "png", "jpg", "jpeg":
            return .image
        default:
            return .text
        }
    }

    init(
        id: String,
        kind: String,
        title: String? = nil,
        text: String? = nil,
        path: String? = nil,
        imageReference: String? = nil,
        diffId: String? = nil,
        docPath: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.path = path
        self.imageReference = imageReference
        self.diffId = diffId
        self.docPath = docPath
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        self.init(value: try ViewPacketJSONValue(from: decoder), index: 0)
    }

    init(value: ViewPacketJSONValue, index: Int) {
        if let text = BuildPayload.scalarString(value) {
            self.init(id: "evidence-\(index)", kind: "text", text: text)
            return
        }

        let object = value.objectValue ?? [:]
        let id = BuildPayload.string(in: object, keys: ["id", "evidenceId", "artifactId", "key"]) ?? "evidence-\(index)"
        let kind = BuildPayload.string(in: object, keys: ["kind", "type", "evidenceKind"]) ?? "text"
        let path = BuildPayload.string(in: object, keys: ["path", "artifactPath", "repoPath", "file"])
        let imageReference = BuildPayload.string(in: object, keys: ["imageUrl", "imageURL", "url", "uri", "src", "href"])
            ?? (kind.lowercased().contains("image") ? path : nil)
        let docPath = BuildPayload.documentPath(BuildPayload.string(in: object, keys: ["docPath", "documentPath", "sourcePath", "artifactPath", "path"]))

        self.init(
            id: id,
            kind: kind,
            title: BuildPayload.string(in: object, keys: ["title", "name", "label", "gate", "command"]),
            text: BuildPayload.string(in: object, keys: ["text", "content", "body", "output", "transcript", "summary"]),
            path: path,
            imageReference: imageReference,
            diffId: BuildPayload.string(in: object, keys: ["diffId", "diff_id", "diffArtifactId"]),
            docPath: docPath,
            createdAt: BuildPayload.string(in: object, keys: ["createdAt", "updatedAt", "at", "timestamp"])
        )
    }
}

struct BuildEvidenceEntryPresentation: Equatable, Sendable {
    var id: String
    var renderKind: BuildEvidenceRenderKind
    var title: String
    var body: String
    var metadata: String?
    var imageReference: String?
    var usesMonospacedBody: Bool

    init(entry: BuildEvidenceEntry) {
        id = entry.id
        renderKind = entry.renderKind
        title = BuildSurfaceCopy.humanTitle(
            entry.title,
            fallback: entry.renderKind.founderTitle,
            identifiers: [entry.id, entry.path]
        ).lowercased()
        body = entry.text ?? ""
        imageReference = entry.imageReference
        usesMonospacedBody = entry.renderKind.usesMonospacedBody
        metadata = BuildPayload.unique([entry.createdAt].compactMap { $0 })
            .joined(separator: " · ")
            .lowercased()
        if metadata?.isEmpty == true {
            metadata = nil
        }
    }
}

struct BuildEvidenceResponse: Decodable, Equatable, Sendable {
    var entries: [BuildEvidenceEntry]
    var generatedAt: String?

    init(entries: [BuildEvidenceEntry] = [], generatedAt: String? = nil) {
        self.entries = entries
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let array = value.arrayValue {
            self.init(entries: array.enumerated().map { BuildEvidenceEntry(value: $0.element, index: $0.offset) })
            return
        }

        guard let object = value.objectValue else {
            self.init(entries: [BuildEvidenceEntry(value: value, index: 0)])
            return
        }

        let values = BuildPayload.values(in: object, keys: ["entries", "evidence", "items", "records", "rows"])
        if values.isEmpty {
            self.init(
                entries: [BuildEvidenceEntry(value: value, index: 0)],
                generatedAt: BuildPayload.string(in: object, keys: ["generatedAt", "updatedAt"])
            )
        } else {
            self.init(
                entries: values.enumerated().map { BuildEvidenceEntry(value: $0.element, index: $0.offset) },
                generatedAt: BuildPayload.string(in: object, keys: ["generatedAt", "updatedAt"])
            )
        }
    }
}

struct BuildDiffFile: Decodable, Equatable, Sendable, Identifiable {
    var path: String
    var status: String?
    var additions: Int?
    var deletions: Int?
    var patch: String

    var id: String { path }

    init(
        path: String,
        status: String? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        patch: String = ""
    ) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }

    init(from decoder: Decoder) throws {
        self.init(value: try ViewPacketJSONValue(from: decoder), index: 0)
    }

    init(value: ViewPacketJSONValue, index: Int) {
        if let text = BuildPayload.scalarString(value) {
            self.init(path: "diff-\(index)", patch: text)
            return
        }
        let object = value.objectValue ?? [:]
        self.init(
            path: BuildPayload.string(in: object, keys: ["path", "file", "newPath", "oldPath", "name"]) ?? "diff-\(index)",
            status: BuildPayload.string(in: object, keys: ["status", "state", "changeType"]),
            additions: BuildPayload.int(in: object, keys: ["additions", "added"]),
            deletions: BuildPayload.int(in: object, keys: ["deletions", "deleted", "removals"]),
            patch: BuildPayload.string(in: object, keys: ["patch", "diff", "content", "hunks", "text"]) ?? ""
        )
    }
}

struct BuildDiffResponse: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var summary: String?
    var files: [BuildDiffFile]
    var docPaths: [String]

    init(
        id: String,
        summary: String? = nil,
        files: [BuildDiffFile] = [],
        docPaths: [String] = []
    ) {
        self.id = id
        self.summary = summary
        self.files = files
        self.docPaths = docPaths
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let text = BuildPayload.scalarString(value) {
            self.init(id: "diff", files: [BuildDiffFile(path: "diff", patch: text)])
            return
        }
        if let array = value.arrayValue {
            self.init(id: "diff", files: array.enumerated().map { BuildDiffFile(value: $0.element, index: $0.offset) })
            return
        }

        let object = value.objectValue ?? [:]
        var files = BuildPayload.values(in: object, keys: ["files", "fileDiffs", "diffFiles", "artifacts"])
            .enumerated()
            .map { BuildDiffFile(value: $0.element, index: $0.offset) }
        let patch = BuildPayload.string(in: object, keys: ["patch", "diff", "content", "text"])
        if files.isEmpty, let patch {
            files = [BuildDiffFile(path: BuildPayload.string(in: object, keys: ["path", "file"]) ?? "diff", patch: patch)]
        }

        let docPaths = BuildPayload.unique(
            ["docPath", "documentPath", "artifactPath", "path"].compactMap { object[$0] }.flatMap(BuildPayload.strings)
        ).compactMap(BuildPayload.documentPath)

        self.init(
            id: BuildPayload.string(in: object, keys: ["id", "diffId", "artifactId"]) ?? "diff",
            summary: BuildPayload.string(in: object, keys: ["summary", "title", "message"]),
            files: files,
            docPaths: docPaths
        )
    }
}

enum BuildLearnedDecision: String, Codable, CaseIterable, Sendable {
    case approve
    case edit
    case discard
}

struct BuildLearnedEntry: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String?
    var text: String
    var status: String?
    var decision: BuildLearnedDecision?
    var source: String?
    var updatedAt: String?

    var isPending: Bool {
        guard decision == nil else { return false }
        let normalized = status?.lowercased() ?? "pending"
        return ["pending", "proposed", "new", "awaiting-consent"].contains(normalized)
    }

    var isApproved: Bool {
        decision == .approve || status?.lowercased() == "approved"
    }

    init(
        id: String,
        title: String? = nil,
        text: String,
        status: String? = nil,
        decision: BuildLearnedDecision? = nil,
        source: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.status = status
        self.decision = decision
        self.source = source
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        self.init(value: try ViewPacketJSONValue(from: decoder), index: 0)
    }

    init(value: ViewPacketJSONValue, index: Int) {
        if let text = BuildPayload.scalarString(value) {
            self.init(id: "learned-\(index)", text: text)
            return
        }
        let object = value.objectValue ?? [:]
        let decisionText = BuildPayload.string(in: object, keys: ["decision", "consentDecision"])
        self.init(
            id: BuildPayload.string(in: object, keys: ["id", "learnedId", "key"]) ?? "learned-\(index)",
            title: BuildPayload.string(in: object, keys: ["title", "name", "label"]),
            text: BuildPayload.string(in: object, keys: ["text", "body", "content", "summary", "lesson"]) ?? "",
            status: BuildPayload.string(in: object, keys: ["status", "state"]),
            decision: decisionText.flatMap(BuildLearnedDecision.init(rawValue:)),
            source: BuildPayload.string(in: object, keys: ["source", "path", "unitId", "laneId"]),
            updatedAt: BuildPayload.string(in: object, keys: ["updatedAt", "createdAt", "at"])
        )
    }

    func applying(_ decision: BuildLearnedDecision) -> BuildLearnedEntry {
        var copy = self
        copy.decision = decision
        copy.status = decision == .approve ? "approved" : decision.rawValue
        return copy
    }
}

struct BuildLearnedFeed: Equatable, Sendable {
    var pending: [BuildLearnedEntry]
    var approved: [BuildLearnedEntry]

    init(pending: [BuildLearnedEntry] = [], approved: [BuildLearnedEntry] = []) {
        self.pending = Self.unique(pending)
        self.approved = Self.unique(approved)
    }

    var nextPending: BuildLearnedEntry? {
        pending.first
    }

    func applying(entry: BuildLearnedEntry, decision: BuildLearnedDecision) -> BuildLearnedFeed {
        let decided = entry.applying(decision)
        var pending = self.pending.filter { $0.id != entry.id }
        var approved = self.approved.filter { $0.id != entry.id }
        if decision == .approve {
            approved.insert(decided, at: 0)
        }
        pending = Self.unique(pending)
        approved = Self.unique(approved)
        return BuildLearnedFeed(pending: pending, approved: approved)
    }

    private static func unique(_ entries: [BuildLearnedEntry]) -> [BuildLearnedEntry] {
        var seen: Set<String> = []
        return entries.filter { seen.insert($0.id).inserted }
    }
}

struct BuildLearnedResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var feed: BuildLearnedFeed
    var error: String?

    init(ok: Bool = true, feed: BuildLearnedFeed = BuildLearnedFeed(), error: String? = nil) {
        self.ok = ok
        self.feed = feed
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let array = value.arrayValue {
            self.init(feed: Self.split(array.enumerated().map { BuildLearnedEntry(value: $0.element, index: $0.offset) }))
            return
        }
        guard let object = value.objectValue else {
            self.init(feed: BuildLearnedFeed(pending: [BuildLearnedEntry(value: value, index: 0)]))
            return
        }

        let pending = BuildPayload.values(in: object, keys: ["pending", "pendingEntries", "proposed"])
            .enumerated()
            .map { BuildLearnedEntry(value: $0.element, index: $0.offset) }
        let approved = BuildPayload.values(in: object, keys: ["approved", "approvedEntries", "accepted"])
            .enumerated()
            .map { BuildLearnedEntry(value: $0.element, index: $0.offset) }
        let entries = BuildPayload.values(in: object, keys: ["entries", "items", "learned"])
            .enumerated()
            .map { BuildLearnedEntry(value: $0.element, index: $0.offset) }

        let feed = pending.isEmpty && approved.isEmpty ? Self.split(entries) : BuildLearnedFeed(pending: pending, approved: approved)
        self.init(
            ok: BuildPayload.bool(in: object, keys: ["ok", "success"]) ?? true,
            feed: feed,
            error: BuildPayload.string(in: object, keys: ["error", "message"])
        )
    }

    private static func split(_ entries: [BuildLearnedEntry]) -> BuildLearnedFeed {
        BuildLearnedFeed(
            pending: entries.filter(\.isPending),
            approved: entries.filter(\.isApproved)
        )
    }
}

struct BuildLearnedDecisionResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var entry: BuildLearnedEntry?
    var feed: BuildLearnedFeed?
    var error: String?

    init(ok: Bool = true, entry: BuildLearnedEntry? = nil, feed: BuildLearnedFeed? = nil, error: String? = nil) {
        self.ok = ok
        self.entry = entry
        self.feed = feed
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        guard let object = value.objectValue else {
            self.init(entry: BuildLearnedEntry(value: value, index: 0))
            return
        }

        let response = try? JSONDecoder().decode(BuildLearnedResponse.self, from: JSONEncoder().encode(value))
        let hasFeed = ["pending", "pendingEntries", "proposed", "approved", "approvedEntries", "accepted", "entries", "items", "learned"]
            .contains { object[$0] != nil }
        let entryValue = object["entry"] ?? object["learned"] ?? object["item"]
        self.init(
            ok: BuildPayload.bool(in: object, keys: ["ok", "success"]) ?? true,
            entry: entryValue.map { BuildLearnedEntry(value: $0, index: 0) },
            feed: hasFeed ? response?.feed : nil,
            error: BuildPayload.string(in: object, keys: ["error", "message"])
        )
    }
}

struct BuildTrustPair: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var verdict: String
    var decision: String
    var signal: String?
    var source: String?
    var createdAt: String?

    init(
        id: String,
        verdict: String,
        decision: String,
        signal: String? = nil,
        source: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.verdict = verdict
        self.decision = decision
        self.signal = signal
        self.source = source
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        self.init(value: try ViewPacketJSONValue(from: decoder), index: 0)
    }

    init(value: ViewPacketJSONValue, index: Int) {
        if let text = BuildPayload.scalarString(value) {
            self.init(id: "trust-\(index)", verdict: text, decision: "")
            return
        }
        let object = value.objectValue ?? [:]
        self.init(
            id: BuildPayload.string(in: object, keys: ["id", "pairId", "key"]) ?? "trust-\(index)",
            verdict: BuildPayload.string(in: object, keys: ["verdict", "runnerVerdict", "predicted", "claim"]) ?? "",
            decision: BuildPayload.string(in: object, keys: ["decision", "founderDecision", "actual", "outcome"]) ?? "",
            signal: BuildPayload.string(in: object, keys: ["signal", "decisionSignal", "decisionSignalId", "kind"]),
            source: BuildPayload.string(in: object, keys: ["source", "unitId", "laneId", "path"]),
            createdAt: BuildPayload.string(in: object, keys: ["createdAt", "updatedAt", "at"])
        )
    }
}

struct BuildTrustPairPresentation: Equatable, Sendable, Identifiable {
    var id: String
    var verdictText: String
    var decisionText: String
    var metaText: String?

    init(pair: BuildTrustPair) {
        id = pair.id
        verdictText = BuildSurfaceCopy.humanTitle(
            pair.verdict,
            fallback: "verification",
            identifiers: [pair.id, pair.source]
        ).lowercased()
        decisionText = BuildSurfaceCopy.humanTitle(
            pair.decision,
            fallback: "no decision",
            identifiers: [pair.id, pair.source]
        ).lowercased()
        let meta = BuildPayload.unique([pair.createdAt].compactMap { $0 })
            .joined(separator: " · ")
            .lowercased()
        metaText = meta.isEmpty ? nil : meta
    }
}

struct BuildTrustResponse: Decodable, Equatable, Sendable {
    var pairs: [BuildTrustPair]
    var decisionSignalCount: Int
    var generatedAt: String?

    var presentations: [BuildTrustPairPresentation] {
        pairs.map(BuildTrustPairPresentation.init)
    }

    init(pairs: [BuildTrustPair] = [], decisionSignalCount: Int? = nil, generatedAt: String? = nil) {
        self.pairs = pairs
        self.decisionSignalCount = decisionSignalCount ?? pairs.count
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let array = value.arrayValue {
            let pairs = array.enumerated().map { BuildTrustPair(value: $0.element, index: $0.offset) }
            self.init(pairs: pairs)
            return
        }
        guard let object = value.objectValue else {
            self.init(pairs: [BuildTrustPair(value: value, index: 0)])
            return
        }

        let pairs = BuildPayload.values(in: object, keys: ["pairs", "verdictDecisionPairs", "items", "entries", "rows"])
            .enumerated()
            .map { BuildTrustPair(value: $0.element, index: $0.offset) }
        self.init(
            pairs: pairs,
            decisionSignalCount: BuildPayload.int(in: object, keys: ["decisionSignalCount", "signalCount", "count", "total"]),
            generatedAt: BuildPayload.string(in: object, keys: ["generatedAt", "updatedAt"])
        )
    }
}

struct BuildLaneLogTailResponse: Decodable, Equatable, Sendable {
    var laneId: String?
    var text: String
    var truncated: Bool
    var updatedAt: String?

    init(laneId: String? = nil, text: String, truncated: Bool = false, updatedAt: String? = nil) {
        self.laneId = laneId
        self.text = text
        self.truncated = truncated
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let value = try ViewPacketJSONValue(from: decoder)
        if let text = BuildPayload.scalarString(value) {
            self.init(text: text)
            return
        }
        let object = value.objectValue ?? [:]
        let lines = BuildPayload.values(in: object, keys: ["lines", "entries"])
            .compactMap(BuildPayload.scalarString)
        self.init(
            laneId: BuildPayload.string(in: object, keys: ["laneId", "id"]),
            text: BuildPayload.string(in: object, keys: ["text", "tail", "logTail", "content", "body"]) ?? lines.joined(separator: "\n"),
            truncated: BuildPayload.bool(in: object, keys: ["truncated", "capped"]) ?? false,
            updatedAt: BuildPayload.string(in: object, keys: ["updatedAt", "at", "generatedAt"])
        )
    }

    static func decode(data: Data, fallbackLaneId: String) -> BuildLaneLogTailResponse {
        if var decoded = try? JSONDecoder().decode(BuildLaneLogTailResponse.self, from: data) {
            if decoded.laneId == nil {
                decoded.laneId = fallbackLaneId
            }
            return decoded
        }
        return BuildLaneLogTailResponse(
            laneId: fallbackLaneId,
            text: String(data: data, encoding: .utf8) ?? "",
            truncated: false
        )
    }
}
