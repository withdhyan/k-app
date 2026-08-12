import Foundation

enum ViewPacketJSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ViewPacketJSONValue])
    case array([ViewPacketJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ViewPacketJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ViewPacketJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var description: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded(.towardZero) == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let value):
            return value
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.description)" }
                .joined(separator: ", ")
        case .array(let value):
            return value.map(\.description).joined(separator: ", ")
        case .null:
            return ""
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var arrayValue: [ViewPacketJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: ViewPacketJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

struct EntityRef: Identifiable, Codable, Equatable, Hashable, Sendable {
    var name: String
    var key: String?

    enum CodingKeys: String, CodingKey {
        case name
        case label
        case key
        case id
    }

    init(name: String, key: String? = nil) {
        self.name = Self.normalized(name) ?? name
        self.key = Self.normalized(key)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .label)
        let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        name = Self.normalized(decodedName) ?? Self.normalized(decodedKey) ?? ""
        key = Self.normalized(decodedKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(key, forKey: .key)
    }

    var id: String {
        (key ?? name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var jsonValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = ["name": .string(name)]
        if let key {
            object["key"] = .string(key)
        }
        return .object(object)
    }

    static func from(_ value: ViewPacketJSONValue?) -> [EntityRef] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return unique(array.compactMap(ref(from:)))
        }
        if let ref = ref(from: value) {
            return [ref]
        }
        return []
    }

    static func inObject(
        _ object: [String: ViewPacketJSONValue],
        keys: [String] = ["entityRefs", "entity_refs"]
    ) -> [EntityRef] {
        for key in keys {
            let refs = from(object[key])
            if !refs.isEmpty { return refs }
        }
        return []
    }

    static func unique(_ refs: [EntityRef]) -> [EntityRef] {
        var seen: Set<String> = []
        var result: [EntityRef] = []
        for ref in refs {
            let name = ref.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = (ref.key ?? name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(EntityRef(name: name, key: ref.key))
        }
        return result
    }

    private static func ref(from value: ViewPacketJSONValue) -> EntityRef? {
        if let object = value.objectValue {
            let name = normalized(object["name"]?.description)
                ?? normalized(object["label"]?.description)
                ?? normalized(object["title"]?.description)
                ?? normalized(object["id"]?.description)
                ?? normalized(object["key"]?.description)
            guard let name else { return nil }
            let key = normalized(object["key"]?.description)
                ?? normalized(object["id"]?.description)
            return EntityRef(name: name, key: key)
        }
        if let name = normalized(value.description) {
            return EntityRef(name: name)
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityTextMatch: Equatable, Sendable {
    var ref: EntityRef
    var range: Range<String.Index>
}

enum EntitySpanMatcher {
    static func matches(in text: String, refs: [EntityRef]) -> [EntityTextMatch] {
        let normalizedRefs = EntityRef.unique(refs)
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { left, right in
                if left.name.count == right.name.count {
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
                return left.name.count > right.name.count
            }
        guard !text.isEmpty, !normalizedRefs.isEmpty else { return [] }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var occupied: [NSRange] = []
        var matches: [EntityTextMatch] = []

        for ref in normalizedRefs {
            let escaped = NSRegularExpression.escapedPattern(for: ref.name)
            let pattern = #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            for match in regex.matches(in: text, range: fullRange) {
                let nsRange = match.range
                guard nsRange.location != NSNotFound, nsRange.length > 0 else { continue }
                let overlaps = occupied.contains { NSIntersectionRange($0, nsRange).length > 0 }
                guard !overlaps, let range = Range(nsRange, in: text) else { continue }
                occupied.append(nsRange)
                matches.append(EntityTextMatch(ref: ref, range: range))
            }
        }

        return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

struct EntityDossierTimelineRow: Decodable, Equatable, Sendable {
    var date: String
    var sourceName: String
    var gist: String

    init(date: String = "", sourceName: String = "", gist: String = "") {
        self.date = Self.normalized(date) ?? ""
        self.sourceName = Self.normalized(sourceName) ?? ""
        self.gist = Self.normalized(gist) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case date
        case sourceName
        case source_name
        case gist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = Self.normalized(try? container.decode(String.self, forKey: .date)) ?? ""
        sourceName = Self.normalized(try? container.decode(String.self, forKey: .sourceName))
            ?? Self.normalized(try? container.decode(String.self, forKey: .source_name))
            ?? ""
        gist = Self.normalized(try? container.decode(String.self, forKey: .gist)) ?? ""
    }

    var isEmpty: Bool {
        date.isEmpty && sourceName.isEmpty && gist.isEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityDossier: Decodable, Equatable, Sendable {
    var definition: String?
    var timeline: [EntityDossierTimelineRow]
    var related: [String]
    var openQuestion: String?

    init(
        definition: String? = nil,
        timeline: [EntityDossierTimelineRow] = [],
        related: [String] = [],
        openQuestion: String? = nil
    ) {
        self.definition = Self.normalized(definition)
        self.timeline = timeline.filter { !$0.isEmpty }
        self.related = related.compactMap(Self.normalized)
        self.openQuestion = Self.normalized(openQuestion)
    }

    enum CodingKeys: String, CodingKey {
        case definition
        case timeline
        case related
        case openQuestion
        case open_question
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definition = Self.normalized(try? container.decode(String.self, forKey: .definition))
        timeline = ((try? container.decode([EntityDossierTimelineRow].self, forKey: .timeline)) ?? [])
            .filter { !$0.isEmpty }
        related = ((try? container.decode([String].self, forKey: .related)) ?? [])
            .compactMap(Self.normalized)
        openQuestion = Self.normalized(try? container.decode(String.self, forKey: .openQuestion))
            ?? Self.normalized(try? container.decode(String.self, forKey: .open_question))
    }

    var isEmpty: Bool {
        definition == nil && timeline.isEmpty && related.isEmpty && openQuestion == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityDossierMetadata: Decodable, Equatable, Sendable {
    var key: String?
    var name: String?
    var evidenceIds: [String]

    enum CodingKeys: String, CodingKey {
        case key
        case id
        case name
        case evidenceIds
        case evidence_ids
    }

    init(key: String? = nil, name: String? = nil, evidenceIds: [String] = []) {
        self.key = Self.normalized(key)
        self.name = Self.normalized(name)
        self.evidenceIds = evidenceIds.compactMap(Self.normalized)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = Self.normalized(try? container.decode(String.self, forKey: .key))
            ?? Self.normalized(try? container.decode(String.self, forKey: .id))
        name = Self.normalized(try? container.decode(String.self, forKey: .name))
        evidenceIds = ((try? container.decode([String].self, forKey: .evidenceIds))
            ?? (try? container.decode([String].self, forKey: .evidence_ids))
            ?? [])
            .compactMap(Self.normalized)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityDossierEnvelope: Decodable, Equatable, Sendable {
    var ok: Bool?
    var entity: EntityDossierMetadata?
    var dossier: EntityDossier?
    var generatedAt: String?
    var source: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case entity
        case dossier
        case definition
        case timeline
        case related
        case openQuestion
        case open_question
        case generatedAt
        case source
        case error
    }

    init(
        ok: Bool? = nil,
        entity: EntityDossierMetadata? = nil,
        dossier: EntityDossier? = nil,
        generatedAt: String? = nil,
        source: String? = nil,
        error: String? = nil
    ) {
        self.ok = ok
        self.entity = entity
        self.dossier = dossier?.isEmpty == false ? dossier : nil
        self.generatedAt = Self.normalized(generatedAt)
        self.source = Self.normalized(source)
        self.error = Self.normalized(error)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        entity = try? container.decodeIfPresent(EntityDossierMetadata.self, forKey: .entity)
        let nestedDossier = try? container.decodeIfPresent(EntityDossier.self, forKey: .dossier)
        let directDossier = EntityDossier(
            definition: Self.normalized(try? container.decode(String.self, forKey: .definition)),
            timeline: (try? container.decode([EntityDossierTimelineRow].self, forKey: .timeline)) ?? [],
            related: (try? container.decode([String].self, forKey: .related)) ?? [],
            openQuestion: Self.normalized(try? container.decode(String.self, forKey: .openQuestion))
                ?? Self.normalized(try? container.decode(String.self, forKey: .open_question))
        )
        if let nestedDossier, !nestedDossier.isEmpty {
            dossier = nestedDossier
        } else {
            dossier = directDossier.isEmpty ? nil : directDossier
        }
        generatedAt = Self.normalized(try? container.decode(String.self, forKey: .generatedAt))
        source = Self.normalized(try? container.decode(String.self, forKey: .source))
        error = Self.normalized(try? container.decode(String.self, forKey: .error))
    }

    var isMissing: Bool {
        dossier == nil || dossier?.isEmpty == true || ok == false
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityDossierSelection: Equatable, Identifiable, Sendable {
    var name: String
    var key: String?

    init(name: String, key: String? = nil) {
        self.name = Self.normalized(name) ?? name
        self.key = Self.normalized(key)
    }

    init(ref: EntityRef) {
        self.init(name: ref.name, key: ref.key)
    }

    var id: String {
        let value = key ?? name
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct EntityDossierPanelNavigation: Equatable, Sendable {
    private(set) var current: EntityDossierSelection

    init(selection: EntityDossierSelection) {
        current = selection
    }

    mutating func replace(with selection: EntityDossierSelection) {
        current = selection
    }

    mutating func openRelated(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        current = EntityDossierSelection(name: trimmed)
    }
}

struct ViewPacketAction: Codable, Equatable, Sendable {
    var kind: String
    var target: String
    var tag: String?
    var id: String?
    var intent: String?
    var args: [String: ViewPacketJSONValue]?

    enum CodingKeys: String, CodingKey {
        case kind
        case target
        case tag
        case id
        case actionId
        case intent
        case intentName
        case name
        case toolId
        case args
        case arguments
    }

    init(
        kind: String,
        target: String,
        tag: String? = nil,
        id: String? = nil,
        intent: String? = nil,
        args: [String: ViewPacketJSONValue]? = nil
    ) {
        self.kind = kind
        self.target = target
        self.tag = tag
        self.id = id
        self.intent = intent
        self.args = args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .actionId)
        let intent = try container.decodeIfPresent(String.self, forKey: .intent)
            ?? container.decodeIfPresent(String.self, forKey: .intentName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .toolId)
        guard let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? intent else {
            throw DecodingError.keyNotFound(
                CodingKeys.kind,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "action.kind or action.intent is required")
            )
        }
        guard let target = try container.decodeIfPresent(String.self, forKey: .target) ?? id ?? intent else {
            throw DecodingError.keyNotFound(
                CodingKeys.target,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "action.target, action.id, or action.intent is required")
            )
        }

        self.kind = kind
        self.target = target
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag)
        self.id = id
        self.intent = intent
        self.args = try container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .args)
            ?? container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .arguments)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(tag, forKey: .tag)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(args, forKey: .args)
    }

    var invokeActionId: String? {
        normalizedActionValue(id ?? target)
    }

    var invokeIntent: String {
        normalizedActionValue(intent ?? kind) ?? kind
    }

    var invokeArgs: [String: ViewPacketJSONValue] {
        args ?? [:]
    }

    var displayLabel: String {
        normalizedActionValue(tag)
            ?? normalizedActionValue(intent)
            ?? normalizedActionValue(kind)
            ?? "run"
    }

    private func normalizedActionValue(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}

struct ViewPacket: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var viewType: String
    var text: String?
    var fields: [String: ViewPacketJSONValue]?
    var children: [ViewPacket]
    var action: ViewPacketAction?
    var score: Double?
    var evidence: [String]?
    var evidencePreviews: [DecisionEvidencePreview]
    var siblings: [String]?
    var confidence: Double?
    var provenance: [String: ViewPacketJSONValue]
    var surfaceDecision: [String: ViewPacketJSONValue]?
    var frontierExcluded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case viewType
        case text
        case fields
        case children
        case action
        case score
        case evidence
        case evidencePreviews
        case evidence_previews
        case siblings
        case confidence
        case provenance
        case surfaceDecision
        case frontierExcluded
    }

    init(
        id: String,
        viewType: String,
        text: String? = nil,
        fields: [String: ViewPacketJSONValue]? = nil,
        children: [ViewPacket] = [],
        action: ViewPacketAction? = nil,
        score: Double? = nil,
        evidence: [String]? = nil,
        evidencePreviews: [DecisionEvidencePreview] = [],
        siblings: [String]? = nil,
        confidence: Double? = nil,
        provenance: [String: ViewPacketJSONValue] = [:],
        surfaceDecision: [String: ViewPacketJSONValue]? = nil,
        frontierExcluded: Bool = true
    ) {
        self.id = id
        self.viewType = viewType
        self.text = text
        self.fields = fields
        self.children = children
        self.action = action
        self.score = score
        self.evidence = evidence
        self.evidencePreviews = evidencePreviews
        self.siblings = siblings
        self.confidence = confidence
        self.provenance = provenance
        self.surfaceDecision = surfaceDecision
        self.frontierExcluded = frontierExcluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        viewType = try container.decode(String.self, forKey: .viewType)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        fields = try container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .fields)
        children = try container.decodeIfPresent([ViewPacket].self, forKey: .children) ?? []
        action = try container.decodeIfPresent(ViewPacketAction.self, forKey: .action)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence)
        evidencePreviews = (try? container.decodeIfPresent([DecisionEvidencePreview].self, forKey: .evidencePreviews))
            ?? (try? container.decodeIfPresent([DecisionEvidencePreview].self, forKey: .evidence_previews))
            ?? []
        siblings = try container.decodeIfPresent([String].self, forKey: .siblings)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        provenance = try container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .provenance) ?? [:]
        surfaceDecision = try container.decodeIfPresent([String: ViewPacketJSONValue].self, forKey: .surfaceDecision)
        frontierExcluded = try container.decodeIfPresent(Bool.self, forKey: .frontierExcluded) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(viewType, forKey: .viewType)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(fields, forKey: .fields)
        if !children.isEmpty { try container.encode(children, forKey: .children) }
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(evidence, forKey: .evidence)
        if !evidencePreviews.isEmpty {
            try container.encode(evidencePreviews, forKey: .evidencePreviews)
        }
        try container.encodeIfPresent(siblings, forKey: .siblings)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        if !provenance.isEmpty { try container.encode(provenance, forKey: .provenance) }
        try container.encodeIfPresent(surfaceDecision, forKey: .surfaceDecision)
        try container.encode(frontierExcluded, forKey: .frontierExcluded)
    }
}

extension ViewPacket {
    var displayText: String {
        if let text, !text.isEmpty { return text }
        if let value = fields?["text"]?.stringValue, !value.isEmpty { return value }
        if let value = fields?["body"]?.stringValue, !value.isEmpty { return value }
        if let value = fields?["title"]?.stringValue, !value.isEmpty { return value }
        return ""
    }

    var shouldRenderHeldState: Bool {
        if let decision = surfaceDecision {
            if decision["surface"]?.boolValue == false { return true }
            if decision["allowed"]?.boolValue == false { return true }
            if decision["render"]?.boolValue == false { return true }
            if decision["held"]?.boolValue == true { return true }
            if ["status", "reason", "state"].contains(where: { key in
                guard let value = decision[key]?.stringValue?.lowercased() else { return false }
                return value.contains("held")
                    || value.contains("hold")
                    || value.contains("unreachable")
                    || value.contains("denied")
                    || value.contains("excluded")
            }) {
                return true
            }
        }

        guard let fields else { return false }
        if fields["held"]?.boolValue == true { return true }
        if fields["held"]?.arrayValue?.isEmpty == false { return true }
        return ["status", "state"].contains { key in
            guard let value = fields[key]?.stringValue?.lowercased() else { return false }
            return value.contains("held") || value.contains("hold")
        }
    }

    var surfaceDecisionReason: String? {
        guard let decision = surfaceDecision else { return nil }
        for key in ["reason", "status", "state"] {
            if let value = decision[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }

    var heldStateReason: String? {
        if let reason = surfaceDecisionReason { return reason }
        if let text, !text.isEmpty { return text }
        guard let fields else { return nil }
        for key in ["reason", "status", "state"] {
            if let value = fields[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }
}

enum ViewPacketPatchOp: Equatable, Sendable {
    case set(field: String, value: ViewPacketJSONValue)
    case appendChild(ViewPacket)
    case flip(field: String, from: ViewPacketJSONValue?, value: ViewPacketJSONValue)
}

struct ViewPacketPatch: Codable, Equatable, Sendable {
    var targetId: String
    var resultId: String?
    var ops: [ViewPacketPatchOp]
    var ignoresAllOps: Bool

    enum CodingKeys: String, CodingKey {
        case targetId
        case packetId
        case resultId
        case ops
        case op
    }

    init(
        targetId: String,
        resultId: String? = nil,
        ops: [ViewPacketPatchOp],
        ignoresAllOps: Bool = false
    ) {
        self.targetId = targetId
        self.resultId = resultId
        self.ops = ops
        self.ignoresAllOps = ignoresAllOps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetId = try container.decodeIfPresent(String.self, forKey: .targetId)
            ?? container.decode(String.self, forKey: .packetId)
        resultId = try container.decodeIfPresent(String.self, forKey: .resultId)

        let rawOps: [ViewPacketPatchOpPayload]
        if let decodedOps = try container.decodeIfPresent([ViewPacketPatchOpPayload].self, forKey: .ops) {
            rawOps = decodedOps
        } else if container.contains(.op) {
            rawOps = [try ViewPacketPatchOpPayload(from: decoder)]
        } else {
            rawOps = []
        }

        var normalizedOps: [ViewPacketPatchOp] = []
        for rawOp in rawOps {
            guard let opName = rawOp.opName else { continue }
            guard let normalizedName = Self.normalizedPatchOpName(opName) else {
                ops = []
                ignoresAllOps = true
                return
            }

            switch normalizedName {
            case "set":
                guard
                    let field = Self.normalizedSetField(rawOp.field),
                    let value = rawOp.value
                else { continue }
                normalizedOps.append(.set(field: field, value: value))
            case "append_child":
                guard let child = rawOp.child ?? rawOp.valueChild else { continue }
                normalizedOps.append(.appendChild(child))
            case "flip":
                guard
                    let field = Self.normalizedFlipField(rawOp.field),
                    let value = rawOp.value
                else { continue }
                normalizedOps.append(.flip(field: field, from: rawOp.from, value: value))
            default:
                ops = []
                ignoresAllOps = true
                return
            }
        }

        ops = normalizedOps
        ignoresAllOps = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetId, forKey: .targetId)
        try container.encodeIfPresent(resultId, forKey: .resultId)
        var opsContainer = container.nestedUnkeyedContainer(forKey: .ops)
        for op in ops {
            var opContainer = opsContainer.nestedContainer(keyedBy: ViewPacketPatchOpCodingKeys.self)
            switch op {
            case .set(let field, let value):
                try opContainer.encode("set", forKey: .op)
                try opContainer.encode(field, forKey: .field)
                try opContainer.encode(value, forKey: .value)
            case .appendChild(let child):
                try opContainer.encode("append_child", forKey: .op)
                try opContainer.encode(child, forKey: .child)
            case .flip(let field, let from, let value):
                try opContainer.encode("flip", forKey: .op)
                try opContainer.encode(field, forKey: .field)
                try opContainer.encodeIfPresent(from, forKey: .from)
                try opContainer.encode(value, forKey: .value)
            }
        }
    }

    private static func normalizedPatchOpName(_ value: String) -> String? {
        let op = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if op == "append-child" || op == "appendChild" { return "append_child" }
        if ["set", "append_child", "flip"].contains(op) { return op }
        return nil
    }

    private static func normalizedSetField(_ value: String?) -> String? {
        guard let field = normalizedPatchField(value) else { return nil }
        let setFields: Set<String> = [
            "text",
            "fields",
            "action",
            "score",
            "evidence",
            "siblings",
            "confidence",
            "surfaceDecision",
        ]
        if setFields.contains(field) || field.hasPrefix("fields.") { return field }
        return nil
    }

    private static func normalizedFlipField(_ value: String?) -> String? {
        guard let field = normalizedPatchField(value) else { return nil }
        if field == "viewType" || field == "fields.status" { return field }
        return nil
    }

    private static func normalizedPatchField(_ value: String?) -> String? {
        guard let value else { return nil }
        let field = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !field.isEmpty else { return nil }
        return field == "status" ? "fields.status" : field
    }
}

@discardableResult
func applyPacketPatch(
    _ patch: ViewPacketPatch,
    to packet: ViewPacket,
    logger: ((String) -> Void)? = nil
) -> ViewPacket {
    guard !patch.ignoresAllOps, !patch.ops.isEmpty else { return packet }

    let result = applyPatchToNode(packet, patch: patch)
    if result.found { return result.packet }
    if patchAlreadyApplied(packet, patch: patch) { return packet }

    let message = "[cs-k] view-packet patch ignored: unknown packet id \(patch.targetId)"
    if let logger {
        logger(message)
    } else {
        NSLog("%@", message)
    }
    return packet
}

private struct ViewPacketPatchOpPayload: Decodable {
    var opName: String?
    var field: String?
    var value: ViewPacketJSONValue?
    var from: ViewPacketJSONValue?
    var child: ViewPacket?
    var valueChild: ViewPacket?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ViewPacketPatchOpCodingKeys.self)
        opName = try container.decodeIfPresent(String.self, forKey: .op)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        field = try container.decodeIfPresent(String.self, forKey: .field)
            ?? container.decodeIfPresent(String.self, forKey: .path)
            ?? container.decodeIfPresent(String.self, forKey: .key)
        value = Self.decodeJSONValue(in: container, forKey: .value)
        from = Self.decodeJSONValue(in: container, forKey: .from)
        child = try? container.decode(ViewPacket.self, forKey: .child)
        valueChild = try? container.decode(ViewPacket.self, forKey: .value)
    }

    private static func decodeJSONValue(
        in container: KeyedDecodingContainer<ViewPacketPatchOpCodingKeys>,
        forKey key: ViewPacketPatchOpCodingKeys
    ) -> ViewPacketJSONValue? {
        guard container.contains(key) else { return nil }
        return try? container.decode(ViewPacketJSONValue.self, forKey: key)
    }
}

private enum ViewPacketPatchOpCodingKeys: String, CodingKey {
    case op
    case type
    case field
    case path
    case key
    case value
    case from
    case child
}

private func applyPatchToNode(_ packet: ViewPacket, patch: ViewPacketPatch) -> (found: Bool, packet: ViewPacket) {
    if packet.id == patch.targetId {
        return (true, applyPatchOpsToTarget(packet, patch: patch))
    }

    guard !packet.children.isEmpty else { return (false, packet) }

    var found = false
    var changed = false
    var children = packet.children
    for index in children.indices {
        let result = applyPatchToNode(children[index], patch: patch)
        guard result.found else { continue }
        found = true
        if result.packet != children[index] {
            children[index] = result.packet
            changed = true
        }
    }

    guard found else { return (false, packet) }
    guard changed else { return (true, packet) }

    var updated = packet
    updated.children = children
    return (true, updated == packet ? packet : updated)
}

private func applyPatchOpsToTarget(_ packet: ViewPacket, patch: ViewPacketPatch) -> ViewPacket {
    var updated = packet
    var touched = false

    for op in patch.ops {
        switch op {
        case .set(let field, let value):
            touched = setPatchField(field, value: value, on: &updated) || touched
        case .appendChild(let child):
            if !updated.children.contains(where: { $0.id == child.id }) {
                updated.children.append(child)
            }
            touched = true
        case .flip(let field, let from, let value):
            let current = readPatchField(field, from: updated)
            if from == nil || current == from || current == value {
                touched = setPatchField(field, value: value, on: &updated) || touched
            }
        }
    }

    if touched, let resultId = patch.resultId {
        updated.id = resultId
    }
    return updated == packet ? packet : updated
}

@discardableResult
private func setPatchField(
    _ field: String,
    value: ViewPacketJSONValue,
    on packet: inout ViewPacket
) -> Bool {
    if field.hasPrefix("fields.") {
        let key = String(field.dropFirst("fields.".count))
        var fields = packet.fields ?? [:]
        fields[key] = value
        packet.fields = fields
        return true
    }

    switch field {
    case "text":
        packet.text = value.packetStringValue
        return true
    case "fields":
        guard let object = value.objectValue else { return false }
        packet.fields = object
        return true
    case "action":
        guard let action = ViewPacketAction(jsonValue: value) else { return false }
        packet.action = action
        return true
    case "score":
        packet.score = value.finiteDoubleValue
        return true
    case "evidence":
        guard let values = value.stringArrayValue else { return false }
        packet.evidence = values
        return true
    case "evidencePreviews", "evidence_previews":
        packet.evidencePreviews = DecisionEvidencePreview.from(value)
        return true
    case "siblings":
        guard let values = value.stringArrayValue else { return false }
        packet.siblings = values
        return true
    case "confidence":
        guard let number = value.finiteDoubleValue, (0...1).contains(number) else { return false }
        packet.confidence = number
        return true
    case "surfaceDecision":
        guard let object = value.objectValue else { return false }
        packet.surfaceDecision = object
        return true
    case "viewType":
        guard let viewType = value.packetStringValue else { return false }
        packet.viewType = viewType
        return true
    default:
        return false
    }
}

private func readPatchField(_ field: String, from packet: ViewPacket) -> ViewPacketJSONValue {
    if field.hasPrefix("fields.") {
        let key = String(field.dropFirst("fields.".count))
        return packet.fields?[key] ?? .null
    }

    switch field {
    case "text":
        return packet.text.map(ViewPacketJSONValue.string) ?? .null
    case "fields":
        return packet.fields.map(ViewPacketJSONValue.object) ?? .null
    case "action":
        return packet.action.map(ViewPacketJSONValue.actionObject) ?? .null
    case "score":
        return packet.score.map(ViewPacketJSONValue.number) ?? .null
    case "evidence":
        return packet.evidence.map { .array($0.map(ViewPacketJSONValue.string)) } ?? .null
    case "evidencePreviews", "evidence_previews":
        return packet.evidencePreviews.isEmpty
            ? .null
            : .array(packet.evidencePreviews.map(\.jsonValue))
    case "siblings":
        return packet.siblings.map { .array($0.map(ViewPacketJSONValue.string)) } ?? .null
    case "confidence":
        return packet.confidence.map(ViewPacketJSONValue.number) ?? .null
    case "surfaceDecision":
        return packet.surfaceDecision.map(ViewPacketJSONValue.object) ?? .null
    case "viewType":
        return .string(packet.viewType)
    default:
        return .null
    }
}

private func patchAlreadyApplied(_ packet: ViewPacket, patch: ViewPacketPatch) -> Bool {
    if let resultId = patch.resultId, packetContainsId(resultId, in: packet) { return true }
    if patchOpsAlreadyApplied(patch.ops, to: packet) { return true }
    return packet.children.contains { patchAlreadyApplied($0, patch: patch) }
}

private func patchOpsAlreadyApplied(_ ops: [ViewPacketPatchOp], to packet: ViewPacket) -> Bool {
    ops.allSatisfy { op in
        switch op {
        case .set(let field, let value), .flip(let field, _, let value):
            return readPatchField(field, from: packet) == value
        case .appendChild(let child):
            return packet.children.contains { $0.id == child.id }
        }
    }
}

private func packetContainsId(_ id: String, in packet: ViewPacket) -> Bool {
    packet.id == id || packet.children.contains { packetContainsId(id, in: $0) }
}

private extension ViewPacketJSONValue {
    var packetStringValue: String? {
        let text: String?
        switch self {
        case .string(let value):
            text = value
        case .number, .bool, .object, .array:
            text = description
        case .null:
            text = nil
        }
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    var finiteDoubleValue: Double? {
        let number: Double?
        switch self {
        case .number(let value):
            number = value
        case .string(let value):
            number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            number = value ? 1 : 0
        case .null, .object, .array:
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    var stringArrayValue: [String]? {
        guard let array = arrayValue else { return nil }
        var values: [String] = []
        for value in array {
            guard let string = value.packetStringValue else { return nil }
            values.append(string)
        }
        return values
    }

    static func actionObject(_ action: ViewPacketAction) -> ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [
            "kind": .string(action.kind),
            "target": .string(action.target),
        ]
        if let tag = action.tag { object["tag"] = .string(tag) }
        if let id = action.id { object["id"] = .string(id) }
        if let intent = action.intent { object["intent"] = .string(intent) }
        if let args = action.args { object["args"] = .object(args) }
        return .object(object)
    }
}

private extension ViewPacketAction {
    init?(jsonValue: ViewPacketJSONValue) {
        guard let object = jsonValue.objectValue else { return nil }

        let id = object["id"]?.packetStringValue ?? object["actionId"]?.packetStringValue
        let intent = object["intent"]?.packetStringValue
            ?? object["intentName"]?.packetStringValue
            ?? object["name"]?.packetStringValue
            ?? object["toolId"]?.packetStringValue
        guard let kind = object["kind"]?.packetStringValue ?? intent else { return nil }
        guard let target = object["target"]?.packetStringValue ?? id ?? intent else { return nil }

        self.init(
            kind: kind,
            target: target,
            tag: object["tag"]?.packetStringValue,
            id: id,
            intent: intent,
            args: object["args"]?.objectValue ?? object["arguments"]?.objectValue
        )
    }
}
