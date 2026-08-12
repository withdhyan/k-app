import SwiftUI
struct BuildCardOption: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var consequence: String

    init(id: String, label: String? = nil, consequence: String = "") {
        self.id = id
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = normalizedLabel?.isEmpty == false ? normalizedLabel! : id
        self.consequence = consequence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? id
        consequence = try container.decodeIfPresent(String.self, forKey: .consequence) ?? ""
    }

    var requiresConfirmation: Bool {
        let text = "\(id) \(label)".lowercased()
        return ["kill", "quarantine", "reject"].contains { text.contains($0) }
    }
}

struct DecisionBriefOption: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var whatHappens: String?

    init(id: String, whatHappens: String? = nil) {
        self.id = id
        self.whatHappens = Self.normalized(whatHappens)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case optionId
        case whatHappens
        case what_happens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.normalized(try? container.decode(String.self, forKey: .id))
            ?? Self.normalized(try? container.decode(String.self, forKey: .optionId))
            ?? ""
        whatHappens = Self.normalized(try? container.decode(String.self, forKey: .whatHappens))
            ?? Self.normalized(try? container.decode(String.self, forKey: .what_happens))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(whatHappens, forKey: .whatHappens)
    }

    var jsonValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = ["id": .string(id)]
        if let whatHappens { object["whatHappens"] = .string(whatHappens) }
        return .object(object)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct DecisionBrief: Codable, Equatable, Sendable {
    var whyNow: String?
    var openQuestion: String?
    var blocker: String?
    var stakes: String?
    var options: [DecisionBriefOption]

    init(
        whyNow: String? = nil,
        openQuestion: String? = nil,
        blocker: String? = nil,
        stakes: String? = nil,
        options: [DecisionBriefOption] = []
    ) {
        self.whyNow = Self.normalized(whyNow)
        self.openQuestion = Self.normalized(openQuestion)
        self.blocker = Self.normalized(blocker)
        self.stakes = Self.normalized(stakes)
        self.options = options.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case whyNow
        case why_now
        case openQuestion
        case open_question
        case blocker
        case stakes
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whyNow = Self.normalized(try? container.decode(String.self, forKey: .whyNow))
            ?? Self.normalized(try? container.decode(String.self, forKey: .why_now))
        openQuestion = Self.normalized(try? container.decode(String.self, forKey: .openQuestion))
            ?? Self.normalized(try? container.decode(String.self, forKey: .open_question))
        blocker = Self.normalized(try? container.decode(String.self, forKey: .blocker))
        stakes = Self.normalized(try? container.decode(String.self, forKey: .stakes))
        options = ((try? container.decode([DecisionBriefOption].self, forKey: .options)) ?? [])
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(whyNow, forKey: .whyNow)
        try container.encodeIfPresent(openQuestion, forKey: .openQuestion)
        try container.encodeIfPresent(blocker, forKey: .blocker)
        try container.encodeIfPresent(stakes, forKey: .stakes)
        if !options.isEmpty {
            try container.encode(options, forKey: .options)
        }
    }

    var isEmpty: Bool {
        whyNow == nil && openQuestion == nil && blocker == nil && stakes == nil && options.isEmpty
    }

    var blockerLine: String {
        if let blocker {
            return "blocker · \(blocker)"
        }
        return "ready to decide"
    }

    var jsonValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [:]
        if let whyNow { object["whyNow"] = .string(whyNow) }
        if let openQuestion { object["openQuestion"] = .string(openQuestion) }
        if let blocker { object["blocker"] = .string(blocker) }
        if let stakes { object["stakes"] = .string(stakes) }
        if !options.isEmpty {
            object["options"] = .array(options.map(\.jsonValue))
        }
        return .object(object)
    }

    func whatHappens(for optionID: String) -> String? {
        let normalizedID = Self.optionKey(optionID)
        guard !normalizedID.isEmpty else { return nil }
        return options.first { option in
            Self.optionKey(option.id) == normalizedID
        }?.whatHappens
    }

    static func from(_ value: ViewPacketJSONValue?) -> DecisionBrief? {
        guard let object = value?.objectValue else { return nil }
        let brief = DecisionBrief(
            whyNow: string(in: object, keys: ["whyNow", "why_now"]),
            openQuestion: string(in: object, keys: ["openQuestion", "open_question"]),
            blocker: string(in: object, keys: ["blocker"]),
            stakes: string(in: object, keys: ["stakes"]),
            options: options(from: object["options"])
        )
        return brief.isEmpty ? nil : brief
    }

    static func first(in object: [String: ViewPacketJSONValue]?) -> DecisionBrief? {
        guard let object else { return nil }
        return from(object["brief"])
            ?? from(object["decisionBrief"])
            ?? from(object["payload"]?.objectValue?["brief"])
            ?? from(object["payload"]?.objectValue?["decisionBrief"])
    }

    private static func options(from value: ViewPacketJSONValue?) -> [DecisionBriefOption] {
        value?.arrayValue?.compactMap { item in
            guard let object = item.objectValue,
                  let id = string(in: object, keys: ["id", "optionId"])
            else { return nil }
            return DecisionBriefOption(
                id: id,
                whatHappens: string(in: object, keys: ["whatHappens", "what_happens"])
            )
        } ?? []
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func optionKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}

struct BuildAlreadyAnswered: Decodable, Equatable, Sendable {
    var by: String?
    var at: String?
    var optionId: String?
}

struct BuildCard: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var kind: String?
    var planId: String?
    var unitId: String?
    var laneId: String?
    var tier: String
    var title: String
    var body: String?
    var what: String?
    var contrast: String?
    var stakes: String?
    var evidenceSummary: DecisionEvidenceSummary?
    var evidencePreviews: [DecisionEvidencePreview]
    var signalExplained: String?
    var face: CardFace?
    var brief: DecisionBrief?
    var options: [BuildCardOption]
    var recommendation: String?
    var status: String
    var severity: String?
    var raisedAt: String?
    var answeredBy: String?
    var answeredAt: String?
    var answerOption: String?
    var answerSurface: String?
    var updatedAt: String?
    var applyFailureReason: String?
    var entityRefs: [EntityRef]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case planId
        case unitId
        case laneId
        case tier
        case title
        case body
        case text
        case what
        case contrast
        case stakes
        case evidenceSummary
        case evidencePreviews
        case evidence_previews
        case signalExplained
        case face
        case brief
        case decisionBrief
        case payload
        case options
        case recommendation
        case status
        case state
        case severity
        case raisedAt
        case answeredBy
        case answeredAt
        case answerOption
        case answerSurface
        case updatedAt
        case applyFailureReason
        case entityRefs
        case entity_refs
    }

    init(
        id: String,
        kind: String? = nil,
        planId: String? = nil,
        unitId: String? = nil,
        laneId: String? = nil,
        tier: String = "tailnet",
        title: String,
        body: String? = nil,
        what: String? = nil,
        contrast: String? = nil,
        stakes: String? = nil,
        evidenceSummary: DecisionEvidenceSummary? = nil,
        evidencePreviews: [DecisionEvidencePreview] = [],
        signalExplained: String? = nil,
        face: CardFace? = nil,
        brief: DecisionBrief? = nil,
        options: [BuildCardOption] = [],
        recommendation: String? = nil,
        status: String = "raised",
        severity: String? = nil,
        raisedAt: String? = nil,
        answeredBy: String? = nil,
        answeredAt: String? = nil,
        answerOption: String? = nil,
        answerSurface: String? = nil,
        updatedAt: String? = nil,
        applyFailureReason: String? = nil,
        entityRefs: [EntityRef] = []
    ) {
        self.id = id
        self.kind = kind
        self.planId = planId
        self.unitId = unitId
        self.laneId = laneId
        self.tier = tier
        self.title = title
        self.body = body
        self.what = Self.normalized(what)
        self.contrast = Self.normalized(contrast)
        self.stakes = Self.normalized(stakes)
        self.evidenceSummary = evidenceSummary?.isEmpty == false ? evidenceSummary : nil
        self.evidencePreviews = evidencePreviews
        self.signalExplained = Self.normalized(signalExplained)
        self.face = face
        self.brief = brief?.isEmpty == false ? brief : nil
        self.options = options
        self.recommendation = recommendation
        self.status = status
        self.severity = severity
        self.raisedAt = raisedAt
        self.answeredBy = answeredBy
        self.answeredAt = answeredAt
        self.answerOption = answerOption
        self.answerSurface = answerSurface
        self.updatedAt = updatedAt
        self.applyFailureReason = applyFailureReason
        self.entityRefs = EntityRef.unique(entityRefs)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        planId = try container.decodeIfPresent(String.self, forKey: .planId)
        unitId = try container.decodeIfPresent(String.self, forKey: .unitId)
        laneId = try container.decodeIfPresent(String.self, forKey: .laneId)
        tier = try container.decodeIfPresent(String.self, forKey: .tier) ?? "tailnet"
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let decodedText = try container.decodeIfPresent(String.self, forKey: .text)
        title = decodedTitle ?? decodedText ?? "build card"
        let decodedBody = try container.decodeIfPresent(String.self, forKey: .body)
        body = decodedBody ?? decodedText
        what = Self.normalized(try? container.decode(String.self, forKey: .what))
        contrast = Self.normalized(try? container.decode(String.self, forKey: .contrast))
        stakes = Self.normalized(try? container.decode(String.self, forKey: .stakes))
        let decodedEvidenceSummary = try? container.decode(DecisionEvidenceSummary.self, forKey: .evidenceSummary)
        evidenceSummary = decodedEvidenceSummary?.isEmpty == false ? decodedEvidenceSummary : nil
        evidencePreviews = (try? container.decodeIfPresent([DecisionEvidencePreview].self, forKey: .evidencePreviews))
            ?? (try? container.decodeIfPresent([DecisionEvidencePreview].self, forKey: .evidence_previews))
            ?? []
        let payload = try? container.decode([String: ViewPacketJSONValue].self, forKey: .payload)
        signalExplained = Self.normalized(try? container.decode(String.self, forKey: .signalExplained))
            ?? Self.string(in: payload, keys: ["signalExplained", "signal_explained"])
        face = try? container.decodeIfPresent(CardFace.self, forKey: .face)
        let decodedBrief = (try? container.decodeIfPresent(DecisionBrief.self, forKey: .brief))
            ?? (try? container.decodeIfPresent(DecisionBrief.self, forKey: .decisionBrief))
            ?? DecisionBrief.first(in: payload)
        brief = decodedBrief?.isEmpty == false ? decodedBrief : nil
        options = try container.decodeIfPresent([BuildCardOption].self, forKey: .options) ?? []
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        let decodedStatus = try container.decodeIfPresent(String.self, forKey: .status)
        let decodedState = try container.decodeIfPresent(String.self, forKey: .state)
        status = decodedStatus ?? decodedState ?? "raised"
        severity = try container.decodeIfPresent(String.self, forKey: .severity)
        raisedAt = try container.decodeIfPresent(String.self, forKey: .raisedAt)
        answeredBy = try container.decodeIfPresent(String.self, forKey: .answeredBy)
        answeredAt = try container.decodeIfPresent(String.self, forKey: .answeredAt)
        answerOption = try container.decodeIfPresent(String.self, forKey: .answerOption)
        answerSurface = try container.decodeIfPresent(String.self, forKey: .answerSurface)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        applyFailureReason = try container.decodeIfPresent(String.self, forKey: .applyFailureReason)
        entityRefs = EntityRef.unique(
            (try? container.decodeIfPresent([EntityRef].self, forKey: .entityRefs)) ?? []
                + ((try? container.decodeIfPresent([EntityRef].self, forKey: .entity_refs)) ?? [])
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(planId, forKey: .planId)
        try container.encodeIfPresent(unitId, forKey: .unitId)
        try container.encodeIfPresent(laneId, forKey: .laneId)
        try container.encode(tier, forKey: .tier)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(what, forKey: .what)
        try container.encodeIfPresent(contrast, forKey: .contrast)
        try container.encodeIfPresent(stakes, forKey: .stakes)
        try container.encodeIfPresent(evidenceSummary, forKey: .evidenceSummary)
        if !evidencePreviews.isEmpty {
            try container.encode(evidencePreviews, forKey: .evidencePreviews)
        }
        try container.encodeIfPresent(signalExplained, forKey: .signalExplained)
        try container.encodeIfPresent(face, forKey: .face)
        try container.encodeIfPresent(brief, forKey: .brief)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(recommendation, forKey: .recommendation)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(severity, forKey: .severity)
        try container.encodeIfPresent(raisedAt, forKey: .raisedAt)
        try container.encodeIfPresent(answeredBy, forKey: .answeredBy)
        try container.encodeIfPresent(answeredAt, forKey: .answeredAt)
        try container.encodeIfPresent(answerOption, forKey: .answerOption)
        try container.encodeIfPresent(answerSurface, forKey: .answerSurface)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(applyFailureReason, forKey: .applyFailureReason)
        if !entityRefs.isEmpty {
            try container.encode(entityRefs, forKey: .entityRefs)
        }
    }

    init?(packet: ViewPacket) {
        guard packet.isBuildCardPacket else { return nil }
        let fields = packet.fields ?? [:]
        let cardObject = fields["card"]?.objectValue
        let source = cardObject ?? fields
        let id = Self.string(in: source, keys: ["id", "cardId"]) ?? Self.string(in: fields, keys: ["cardId"]) ?? packet.id
        self.id = id
        kind = Self.string(in: source, keys: ["kind", "cardKind"])
        planId = Self.string(in: source, keys: ["planId"])
        unitId = Self.string(in: source, keys: ["unitId"])
        laneId = Self.string(in: source, keys: ["laneId"])
        tier = Self.string(in: source, keys: ["tier", "channelTier", "channel", "answerTier", "answerChannel"]) ?? "tailnet"
        title = Self.string(in: source, keys: ["title", "name", "label"])
            ?? (packet.displayText.isEmpty ? "build card" : packet.displayText)
        body = Self.string(in: source, keys: ["body", "text", "message", "detail"])
            ?? (packet.text == title ? nil : packet.text)
        what = Self.string(in: source, keys: ["what"])
        contrast = Self.string(in: source, keys: ["contrast"])
        stakes = Self.string(in: source, keys: ["stakes"])
        evidenceSummary = Self.evidenceSummary(in: source) ?? Self.evidenceSummary(in: fields)
        evidencePreviews = Self.uniqueEvidencePreviews(
            Self.evidencePreviews(in: source)
                + (cardObject == nil ? [] : Self.evidencePreviews(in: fields))
                + packet.evidencePreviews
        )
        signalExplained = Self.signalExplained(in: source) ?? Self.signalExplained(in: fields)
        face = CardFace.from(source["face"])
            ?? (cardObject == nil ? nil : CardFace.from(fields["face"]))
        brief = DecisionBrief.first(in: source)
            ?? (cardObject == nil ? nil : DecisionBrief.first(in: fields))
        options = Self.options(from: source["options"])
        recommendation = Self.string(in: source, keys: ["recommendation"])
        status = Self.string(in: source, keys: ["status", "state"]) ?? "raised"
        severity = Self.string(in: source, keys: ["severity"])
        raisedAt = Self.string(in: source, keys: ["raisedAt", "queuedAt", "notifiedAt"])
        answeredBy = Self.string(in: source, keys: ["answeredBy"])
        answeredAt = Self.string(in: source, keys: ["answeredAt"])
        answerOption = Self.string(in: source, keys: ["answerOption", "optionId"])
        answerSurface = Self.string(in: source, keys: ["answerSurface"])
        updatedAt = Self.string(in: source, keys: ["updatedAt", "at"])
        applyFailureReason = Self.string(in: source, keys: ["applyFailureReason", "reason"])
        entityRefs = EntityRef.unique(
            EntityRef.inObject(source)
                + (cardObject == nil ? [] : EntityRef.inObject(fields))
        )
    }

    var packet: ViewPacket {
        var fields: [String: ViewPacketJSONValue] = [
            "card": cardValue,
            "cardId": .string(id),
            "title": .string(title),
            "status": .string(status),
            "tier": .string(tier),
            "options": .array(options.map(\.jsonValue)),
        ]
        if let body { fields["body"] = .string(body) }
        if let kind { fields["kind"] = .string(kind) }
        if let planId { fields["planId"] = .string(planId) }
        if let unitId { fields["unitId"] = .string(unitId) }
        if let laneId { fields["laneId"] = .string(laneId) }
        if let what { fields["what"] = .string(what) }
        if let contrast { fields["contrast"] = .string(contrast) }
        if let stakes { fields["stakes"] = .string(stakes) }
        if let evidenceSummary { fields["evidenceSummary"] = evidenceSummary.jsonValue }
        if !evidencePreviews.isEmpty { fields["evidencePreviews"] = .array(evidencePreviews.map(\.jsonValue)) }
        if let signalExplained { fields["payload"] = .object(["signalExplained": .string(signalExplained)]) }
        if let face { fields["face"] = face.jsonValue }
        if let brief { fields["brief"] = brief.jsonValue }
        if let recommendation { fields["recommendation"] = .string(recommendation) }
        if let severity { fields["severity"] = .string(severity) }
        if let answeredBy { fields["answeredBy"] = .string(answeredBy) }
        if let answeredAt { fields["answeredAt"] = .string(answeredAt) }
        if let answerOption { fields["answerOption"] = .string(answerOption) }
        if let answerSurface { fields["answerSurface"] = .string(answerSurface) }
        if let updatedAt { fields["updatedAt"] = .string(updatedAt) }
        if let applyFailureReason { fields["applyFailureReason"] = .string(applyFailureReason) }
        if !entityRefs.isEmpty { fields["entityRefs"] = .array(entityRefs.map(\.jsonValue)) }

        return ViewPacket(
            id: "build-card-\(id)",
            viewType: "build.card",
            text: title,
            fields: fields,
            evidencePreviews: evidencePreviews,
            provenance: [
                "surface": .string("build"),
                "lane": .string("daemon"),
                "plane": .string("agent"),
                "module": .string("build-card"),
            ],
            frontierExcluded: true
        )
    }

    var isLoopbackOnly: Bool {
        tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "loopback"
    }

    var isOpen: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["raised", "notified", "re-raised", "queued"].contains(normalized)
    }

    var isAnswered: Bool {
        !isOpen || answeredBy != nil || answeredAt != nil || answerOption != nil
    }

    var historyLine: String {
        // answeredBy carries the transport surface — machine vocabulary.
        // Founder copy names the place, never the channel.
        switch answeredBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "loopback": return "answered on the mac"
        case "tailnet": return "answered from the app"
        case .some(let by) where !by.isEmpty: return "answered by \(by)"
        default: return "answered"
        }
    }

    func answeredCopy(option: BuildCardOption, alreadyAnswered: BuildAlreadyAnswered? = nil) -> BuildCard {
        var copy = self
        copy.status = "answered"
        copy.answeredBy = alreadyAnswered?.by ?? answeredBy ?? "founder"
        copy.answeredAt = alreadyAnswered?.at ?? answeredAt
        copy.answerOption = alreadyAnswered?.optionId ?? answerOption ?? option.id
        copy.answerSurface = answerSurface ?? "tailnet"
        return copy
    }

    private var cardValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [
            "id": .string(id),
            "tier": .string(tier),
            "title": .string(title),
            "status": .string(status),
            "options": .array(options.map(\.jsonValue)),
        ]
        if let kind { object["kind"] = .string(kind) }
        if let planId { object["planId"] = .string(planId) }
        if let unitId { object["unitId"] = .string(unitId) }
        if let laneId { object["laneId"] = .string(laneId) }
        if let body { object["body"] = .string(body) }
        if let what { object["what"] = .string(what) }
        if let contrast { object["contrast"] = .string(contrast) }
        if let stakes { object["stakes"] = .string(stakes) }
        if let evidenceSummary { object["evidenceSummary"] = evidenceSummary.jsonValue }
        if !evidencePreviews.isEmpty { object["evidencePreviews"] = .array(evidencePreviews.map(\.jsonValue)) }
        if let signalExplained { object["payload"] = .object(["signalExplained": .string(signalExplained)]) }
        if let face { object["face"] = face.jsonValue }
        if let brief { object["brief"] = brief.jsonValue }
        if let recommendation { object["recommendation"] = .string(recommendation) }
        if let severity { object["severity"] = .string(severity) }
        if let raisedAt { object["raisedAt"] = .string(raisedAt) }
        if let answeredBy { object["answeredBy"] = .string(answeredBy) }
        if let answeredAt { object["answeredAt"] = .string(answeredAt) }
        if let answerOption { object["answerOption"] = .string(answerOption) }
        if let answerSurface { object["answerSurface"] = .string(answerSurface) }
        if let updatedAt { object["updatedAt"] = .string(updatedAt) }
        if let applyFailureReason { object["applyFailureReason"] = .string(applyFailureReason) }
        if !entityRefs.isEmpty { object["entityRefs"] = .array(entityRefs.map(\.jsonValue)) }
        return .object(object)
    }

    private static func options(from value: ViewPacketJSONValue?) -> [BuildCardOption] {
        value?.arrayValue?.enumerated().compactMap { index, item in
            if let object = item.objectValue {
                guard let id = string(in: object, keys: ["id", "optionId"]) else { return nil }
                return BuildCardOption(
                    id: id,
                    label: string(in: object, keys: ["label", "title", "name"]) ?? id,
                    consequence: string(in: object, keys: ["consequence", "effect", "result"]) ?? ""
                )
            }
            if let id = item.stringValue {
                return BuildCardOption(id: id, label: id, consequence: "")
            }
            return BuildCardOption(id: "option-\(index)", label: item.description, consequence: "")
        } ?? []
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func string(in object: [String: ViewPacketJSONValue]?, keys: [String]) -> String? {
        guard let object else { return nil }
        return string(in: object, keys: keys)
    }

    private static func evidenceSummary(in object: [String: ViewPacketJSONValue]) -> DecisionEvidenceSummary? {
        DecisionEvidenceSummary.from(object["evidenceSummary"])
    }

    private static func evidencePreviews(in object: [String: ViewPacketJSONValue]) -> [DecisionEvidencePreview] {
        DecisionEvidencePreview.from(object["evidencePreviews"]) + DecisionEvidencePreview.from(object["evidence_previews"])
    }

    private static func uniqueEvidencePreviews(_ values: [DecisionEvidencePreview]) -> [DecisionEvidencePreview] {
        var seen: Set<String> = []
        var result: [DecisionEvidencePreview] = []
        for value in values {
            let key = value.id.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func signalExplained(in object: [String: ViewPacketJSONValue]) -> String? {
        string(in: object, keys: ["signalExplained", "signal_explained"])
            ?? string(in: object["payload"]?.objectValue, keys: ["signalExplained", "signal_explained"])
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

extension BuildCardOption {
    var jsonValue: ViewPacketJSONValue {
        .object([
            "id": .string(id),
            "label": .string(label),
            "consequence": .string(consequence),
        ])
    }
}

extension DecisionEvidenceSummary {
    var jsonValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [:]
        if let conversationCount { object["conversationCount"] = .number(Double(conversationCount)) }
        if let atomCount { object["atomCount"] = .number(Double(atomCount)) }
        if let latestAt { object["latestAt"] = .string(latestAt) }
        if !topicHints.isEmpty {
            object["topicHints"] = .array(topicHints.map(ViewPacketJSONValue.string))
        }
        return .object(object)
    }
}

extension BuildCard {
    var voiceTitle: String {
        KCopy.buildCardTitle(kind: kind, rawTitle: title)
    }

    /// The bulk act is narrower than the individual answer affordance: queued
    /// cards and cards without K's recommendation remain visible, but never get
    /// a guessed answer.
    var isBulkAnswerable: Bool {
        guard isOpen, !isLoopbackOnly else { return false }
        let normalizedStatus = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedStatus != "queued" else { return false }
        return recommendation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var bulkRecommendationOption: BuildCardOption? {
        guard let recommendation = recommendation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !recommendation.isEmpty
        else { return nil }
        return options.first {
            $0.id.caseInsensitiveCompare(recommendation) == .orderedSame
        } ?? BuildCardOption(id: recommendation, label: recommendation)
    }

    /// The plan context is human copy when present. A missing title falls back to the
    /// established nickname distiller; payload ids never cross into founder-facing UI.
    var planDisplayTitle: String? {
        guard what?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || planId != nil else {
            return nil
        }
        return BuildPlanRow.nickname(planId: planId, title: what).lowercased()
    }

    var kindLabel: String {
        let value = kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return value?.isEmpty == false ? value! : "decision"
    }

    var hasReviewDepth: Bool {
        unitId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || laneId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct BuildCardAnswerResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var card: BuildCard?
    var alreadyAnswered: BuildAlreadyAnswered?
    var error: String?
    var packet: ViewPacket?
    var packets: [ViewPacket]?

    enum CodingKeys: String, CodingKey {
        case ok
        case card
        case alreadyAnswered
        case error
        case packet
        case packets
    }

    init(
        ok: Bool,
        card: BuildCard? = nil,
        alreadyAnswered: BuildAlreadyAnswered? = nil,
        error: String? = nil,
        packet: ViewPacket? = nil,
        packets: [ViewPacket]? = nil
    ) {
        self.ok = ok
        self.card = card
        self.alreadyAnswered = alreadyAnswered
        self.error = error
        self.packet = packet
        self.packets = packets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        card = try? container.decodeIfPresent(BuildCard.self, forKey: .card)
        alreadyAnswered = try? container.decodeIfPresent(BuildAlreadyAnswered.self, forKey: .alreadyAnswered)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        packet = try? container.decodeIfPresent(ViewPacket.self, forKey: .packet)
        packets = try? container.decodeIfPresent([ViewPacket].self, forKey: .packets)
    }
}

struct BuildIntentResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var error: String?
    var state: String?
    var status: String?
    var message: String?
    var draft: ViewPacketJSONValue?
    var packet: ViewPacket?
    var packets: [ViewPacket]?

    var progressText: String {
        if let message, !message.isEmpty { return message }
        if let status, !status.isEmpty { return status }
        if let state, !state.isEmpty { return state }
        if let draft {
            let text = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return "draft requested"
    }
}
