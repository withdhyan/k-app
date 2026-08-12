import SwiftUI

enum MindVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case junk
    case nod
    case actOn = "act-on"

    var id: String { rawValue }

    static let buttonOrder: [MindVerdict] = [.junk, .nod, .actOn]

    var iconName: String {
        switch self {
        case .actOn:
            return "arrow.up.right.circle"
        case .nod:
            return "checkmark.circle"
        case .junk:
            return "trash"
        }
    }
}

enum MindNudgeFeedback: String, Codable, CaseIterable, Identifiable, Sendable {
    case up
    case down
    case tooLate = "too_late"
    case tooNoisy = "too_noisy"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .tooLate:
            return "clock"
        case .tooNoisy:
            return "speaker.slash"
        }
    }

    var label: String {
        switch self {
        case .up:
            return "up"
        case .down:
            return "down"
        case .tooLate:
            return "too late"
        case .tooNoisy:
            return "too noisy"
        }
    }
}

enum MindVerdictAccessibility {
    static func controlLabel(for verdict: MindVerdict) -> String {
        switch verdict {
        case .actOn:
            return "act on"
        case .nod:
            return "nod"
        case .junk:
            return "junk"
        }
    }

    static func controlHint(for verdict: MindVerdict, output: MindOutput) -> String {
        "record \(controlLabel(for: verdict)) for \(title(for: output))"
    }

    static func cardLabel(for output: MindOutput) -> String {
        let face = output.face
        return [
            "title: \(face?.anchor.displayText ?? title(for: output))",
            "body: \(spoken(face?.ask ?? output.statement) ?? "no statement")",
            "source: \(source(for: output))",
        ].joined(separator: ". ")
    }

    static func detailsLabel(for output: MindOutput, isExpanded: Bool) -> String {
        let state = isExpanded ? "hide" : "show"
        return "\(state) details, \(source(for: output))"
    }

    static func detailsHint(isExpanded: Bool) -> String {
        isExpanded ? "collapses evidence and context" : "expands evidence and context"
    }

    private static func title(for output: MindOutput) -> String {
        spoken(output.label) ?? spoken(output.displayType) ?? "mind output"
    }

    private static func source(for output: MindOutput) -> String {
        var parts = [spoken(output.displayType)]
        parts.append(evidenceSummary(output.evidence.count))
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private static func evidenceSummary(_ count: Int) -> String {
        count == 1 ? "1 evidence item" : "\(count) evidence items"
    }

    private static func spoken(_ value: String?) -> String? {
        let parts = (value ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ")
    }
}

struct MindOutputKey: Hashable, Sendable {
    var outputType: String
    var outputId: String
}

struct MindEvalVerdict: Codable, Equatable, Sendable {
    var passId: String?
    var date: String?
    var outputType: String
    var outputId: String
    var label: String?
    var verdict: MindVerdict

    var key: MindOutputKey {
        MindOutputKey(outputType: outputType, outputId: outputId)
    }
}

struct MindOutput: Identifiable, Equatable, Sendable {
    var packet: ViewPacket
    var outputType: String
    var outputId: String
    var statement: String
    var label: String?
    var kind: String?
    var type: String?
    var what: String?
    var contrast: String?
    var stakes: String?
    var evidenceSummary: DecisionEvidenceSummary?
    var evidencePreviews: [DecisionEvidencePreview]
    var signalExplained: String?
    var face: CardFace?
    var brief: DecisionBrief?
    var options: [BuildCardOption]
    var evidence: [String]
    var siblings: [String]
    var considerations: [String]
    var observation: String?
    var nextAction: String?
    var verdict: MindVerdict?
    var entityRefs: [EntityRef]
    var artifactSignal: MindArtifactSignal
    var useTrail: [MindUseTrailEntry]
    var commentThread: MindCommentThread?
    var verdictConsequences: [MindVerdict: String]

    var id: String { "\(outputType):\(outputId)" }

    var key: MindOutputKey {
        MindOutputKey(outputType: outputType, outputId: outputId)
    }

    var displayType: String {
        outputType.replacingOccurrences(of: "_", with: " ")
    }

    var supportsNudgeFeedback: Bool {
        let fields = packet.fields ?? [:]
        if Self.hasCue(in: fields) {
            return true
        }

        let candidates = [
            outputType,
            kind,
            type,
            Self.string(in: fields, keys: ["outputGroup", "group", "outputKind", "kind", "type"]),
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0.contains("nudge") }
    }

    init?(packet: ViewPacket, verdict: MindVerdict? = nil) {
        let fields = packet.fields ?? [:]
        let payloadFields = fields["payload"]?.objectValue ?? [:]
        let outputId = Self.string(in: fields, keys: ["outputId", "id"])
            ?? packet.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputType = Self.string(in: fields, keys: ["outputType", "outputGroup", "group"])
            ?? Self.outputType(from: packet.viewType)
            ?? packet.viewType.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = packet.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let statement = Self.string(in: fields, keys: ["statement", "text", "body"])
            ?? (displayText.isEmpty ? nil : displayText)
            ?? Self.string(in: fields, keys: ["decision", "label", "summary"])

        guard !outputId.isEmpty, !outputType.isEmpty, let statement, !statement.isEmpty else {
            return nil
        }

        self.packet = packet
        self.outputType = outputType
        self.outputId = outputId
        self.statement = statement
        label = Self.string(in: fields, keys: ["label", "decision", "title", "name"])
        kind = Self.string(in: fields, keys: ["kind"])
        type = Self.string(in: fields, keys: ["type"])
        what = Self.string(in: fields, keys: ["what"])
        contrast = Self.string(in: fields, keys: ["contrast"])
        stakes = Self.string(in: fields, keys: ["stakes"])
        evidenceSummary = DecisionEvidenceSummary.from(fields["evidenceSummary"])
        evidencePreviews = Self.evidencePreviews(packet: packet, fields: fields)
        signalExplained = Self.signalExplained(in: fields)
        face = CardFace.from(fields["face"])
            ?? CardFace.from(payloadFields["face"])
        brief = Self.decisionBrief(in: fields)
        options = Self.options(in: fields, brief: brief)
        evidence = Self.unique((packet.evidence ?? []) + Self.strings(from: fields["evidenceIds"]) + Self.strings(from: fields["evidence"]))
        siblings = Self.unique((packet.siblings ?? []) + Self.strings(from: fields["siblings"]))
        considerations = Self.unique(Self.insightStrings(from: fields["considerations"])
            + Self.insightStrings(from: payloadFields["considerations"]))
        observation = Self.string(in: fields, keys: ["observation"])
            ?? Self.string(in: payloadFields, keys: ["observation"])
        nextAction = Self.string(in: fields, keys: ["nextAction"])
            ?? packet.action?.target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.verdict = verdict
        artifactSignal = Self.artifactSignal(in: fields, payload: payloadFields)
        useTrail = Self.useTrail(in: fields, payload: payloadFields)
        commentThread = Self.commentThread(in: fields, payload: payloadFields)
        verdictConsequences = Self.verdictConsequences(
            in: fields,
            payload: payloadFields,
            brief: brief
        )
        entityRefs = EntityRef.unique(
            EntityRef.inObject(fields)
                + EntityRef.inObject(payloadFields)
        )
    }

    private static func outputType(from viewType: String) -> String? {
        switch viewType {
        case "k0.decision":
            return "build_decide"
        case "loop.evidence":
            return "themes_open_loops"
        case "k0.claim":
            return "resurfaced"
        case "k0.change":
            return "new_ideas"
        default:
            return nil
        }
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] else { continue }
            let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func strings(from value: ViewPacketJSONValue?) -> [String] {
        strings(from: value, objectKeys: ["statement", "label", "title", "id", "atomId"])
    }

    private static func insightStrings(from value: ViewPacketJSONValue?) -> [String] {
        strings(from: value, objectKeys: ["statement", "label", "title", "text", "body", "observation"])
            .filter { !MindEvidenceDetailFormatter.isRawEvidenceReference($0) }
    }

    private static func strings(from value: ViewPacketJSONValue?, objectKeys: [String]) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.compactMap { item in
                if let object = item.objectValue {
                    return string(in: object, keys: objectKeys)
                }
                let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }
        let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? [] : [text]
    }

    private static func options(
        in fields: [String: ViewPacketJSONValue],
        brief: DecisionBrief?
    ) -> [BuildCardOption] {
        let direct = buildOptions(from: fields["options"])
        if !direct.isEmpty {
            return applyBrief(brief, to: direct)
        }
        if let decisionCard = fields["decisionCard"]?.objectValue {
            return applyBrief(brief, to: buildOptions(from: decisionCard["options"]))
        }
        if let payload = fields["payload"]?.objectValue {
            return applyBrief(brief, to: buildOptions(from: payload["options"]))
        }
        return []
    }

    private static func applyBrief(_ brief: DecisionBrief?, to options: [BuildCardOption]) -> [BuildCardOption] {
        guard let brief else { return options }
        return options.map { option in
            BuildCardOption(
                id: option.id,
                label: option.label,
                consequence: brief.whatHappens(for: option.id) ?? option.consequence
            )
        }
    }

    private static func buildOptions(from value: ViewPacketJSONValue?) -> [BuildCardOption] {
        value?.arrayValue?.enumerated().compactMap { index, item in
            if let object = item.objectValue {
                guard let id = string(in: object, keys: ["id", "optionId"]) else { return nil }
                return BuildCardOption(
                    id: id,
                    label: string(in: object, keys: ["label", "title", "name"]) ?? id,
                    consequence: string(in: object, keys: ["consequence", "effect", "result"]) ?? ""
                )
            }
            let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : BuildCardOption(id: "option-\(index)", label: text)
        } ?? []
    }

    private static func signalExplained(in fields: [String: ViewPacketJSONValue]) -> String? {
        string(in: fields, keys: ["signalExplained", "signal_explained"])
            ?? string(in: fields["payload"]?.objectValue ?? [:], keys: ["signalExplained", "signal_explained"])
    }

    private static func artifactSignal(
        in fields: [String: ViewPacketJSONValue],
        payload: [String: ViewPacketJSONValue]
    ) -> MindArtifactSignal {
        let objects = [fields, payload]
        for object in objects {
            for key in ["artifactSignal", "artifact_signal", "mindState", "mind_state", "status", "state"] {
                guard let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { continue }
                let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
                if normalized.contains("fresh") || normalized.contains("new") {
                    return .fresh
                }
                if normalized.contains("acted") || normalized.contains("used") {
                    return .acted
                }
            }

            for key in ["fresh", "isFresh", "is_fresh"] where object[key]?.boolValue == true {
                return .fresh
            }
            for key in ["acted", "isActed", "is_acted"] where object[key]?.boolValue == true {
                return .acted
            }
        }
        return .none
    }

    private static func useTrail(
        in fields: [String: ViewPacketJSONValue],
        payload: [String: ViewPacketJSONValue]
    ) -> [MindUseTrailEntry] {
        let values = [
            fields["useTrail"], fields["use_trail"], fields["trail"],
            payload["useTrail"], payload["use_trail"], payload["trail"],
        ]
        for value in values {
            let entries = parseTrail(value)
            if !entries.isEmpty { return entries }
        }
        return []
    }

    private static func parseTrail(_ value: ViewPacketJSONValue?) -> [MindUseTrailEntry] {
        guard let value else { return [] }
        let values = value.arrayValue ?? [value]
        return values.enumerated().compactMap { index, item in
            if let object = item.objectValue {
                let id = string(in: object, keys: ["id", "key", "trailId", "trail_id"]) ?? "trail-\(index)"
                let text = string(in: object, keys: [
                    "text", "summary", "detail", "description", "used", "usage",
                    "whatChanged", "what_changed", "location",
                ]) ?? composedTrailText(in: object)
                guard let text else { return nil }
                return MindUseTrailEntry(
                    id: id,
                    text: text,
                    at: string(in: object, keys: ["at", "usedAt", "used_at", "timestamp", "date"])
                )
            }
            let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MindUseTrailEntry(id: "trail-\(index)", text: text)
        }
    }

    private static func composedTrailText(in object: [String: ViewPacketJSONValue]) -> String? {
        let parts = [
            string(in: object, keys: ["where", "destination", "surface"]),
            string(in: object, keys: ["change", "consequence", "result"]),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func commentThread(
        in fields: [String: ViewPacketJSONValue],
        payload: [String: ViewPacketJSONValue]
    ) -> MindCommentThread? {
        let values = [
            fields["commentThread"], fields["comment_thread"], fields["thread"],
            payload["commentThread"], payload["comment_thread"], payload["thread"],
        ]
        for value in values {
            if let thread = parseCommentThread(value), thread.hasContent {
                return thread
            }
        }
        return nil
    }

    private static func parseCommentThread(_ value: ViewPacketJSONValue?) -> MindCommentThread? {
        guard let object = value?.objectValue else { return nil }
        let commentsValue = object["comments"] ?? object["messages"] ?? object["turns"]
        let comments = parseComments(commentsValue)
        let receipt = parseReceipt(object["receipt"] ?? object["resolution"] ?? object["resolvedReceipt"])
        return MindCommentThread(comments: comments, receipt: receipt)
    }

    private static func parseComments(_ value: ViewPacketJSONValue?) -> [MindCommentTurn] {
        guard let value else { return [] }
        let values = value.arrayValue ?? [value]
        return values.enumerated().compactMap { index, item in
            if let object = item.objectValue {
                guard let text = string(in: object, keys: ["text", "content", "body", "message"]) else {
                    return nil
                }
                return MindCommentTurn(
                    id: string(in: object, keys: ["id", "key"]) ?? "comment-\(index)",
                    role: string(in: object, keys: ["role", "author", "who", "from"]) ?? "k",
                    text: text,
                    at: string(in: object, keys: ["at", "timestamp", "date"])
                )
            }
            let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MindCommentTurn(id: "comment-\(index)", role: "k", text: text)
        }
    }

    private static func parseReceipt(_ value: ViewPacketJSONValue?) -> MindCommentReceipt? {
        guard let object = value?.objectValue else { return nil }
        let change = string(in: object, keys: ["change", "whatChanged", "what_changed", "text", "summary"])
        guard let change else { return nil }
        return MindCommentReceipt(
            who: string(in: object, keys: ["who", "by", "resolvedBy", "resolved_by"]) ?? "you",
            at: string(in: object, keys: ["at", "when", "resolvedAt", "resolved_at", "timestamp", "date"]) ?? "today",
            change: change
        )
    }

    private static func verdictConsequences(
        in fields: [String: ViewPacketJSONValue],
        payload: [String: ViewPacketJSONValue],
        brief: DecisionBrief?
    ) -> [MindVerdict: String] {
        var result: [MindVerdict: String] = [:]
        for object in [fields, payload] {
            for key in ["verdictConsequences", "verdict_consequences", "consequences"] {
                guard let values = object[key]?.objectValue else { continue }
                for verdict in MindVerdict.allCases {
                    if let text = string(in: values, keys: [verdict.rawValue, verdict.rawValue.replacingOccurrences(of: "-", with: "_")]) {
                        result[verdict] = text
                    }
                }
            }
        }
        for verdict in MindVerdict.allCases {
            if result[verdict] == nil, let text = brief?.whatHappens(for: verdict.rawValue) {
                result[verdict] = text
            }
        }
        return result
    }

    private static func decisionBrief(in fields: [String: ViewPacketJSONValue]) -> DecisionBrief? {
        DecisionBrief.first(in: fields)
            ?? DecisionBrief.first(in: fields["decisionCard"]?.objectValue)
    }

    private static func evidencePreviews(
        packet: ViewPacket,
        fields: [String: ViewPacketJSONValue]
    ) -> [DecisionEvidencePreview] {
        uniquePreviews(
            packet.evidencePreviews
                + DecisionEvidencePreview.from(fields["evidencePreviews"])
                + DecisionEvidencePreview.from(fields["evidence_previews"])
                + DecisionEvidencePreview.from(fields["payload"]?.objectValue?["evidencePreviews"])
                + DecisionEvidencePreview.from(fields["payload"]?.objectValue?["evidence_previews"])
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private static func uniquePreviews(_ values: [DecisionEvidencePreview]) -> [DecisionEvidencePreview] {
        var seen: Set<String> = []
        var result: [DecisionEvidencePreview] = []
        for value in values {
            let key = value.id.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func hasCue(in fields: [String: ViewPacketJSONValue]) -> Bool {
        guard let cue = fields["cue"] else { return false }
        if case .null = cue { return false }
        return true
    }
}

struct MindCardContextRow: Equatable, Sendable {
    var primary: String
    var secondary: String?
}

struct MindCardContextSection: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case record
        case extracted
    }

    var kind: Kind
    var title: String
    var rows: [MindCardContextRow]
}

enum MindCardContextPresenter {
    static func sections(for output: MindOutput) -> [MindCardContextSection] {
        [
            recordSection(for: output),
            extractedSection(for: output),
        ].compactMap { $0 }
    }

    static func recordSection(for output: MindOutput) -> MindCardContextSection? {
        let rows = output.evidencePreviews.compactMap { preview -> MindCardContextRow? in
            guard let label = oneLine(preview.label) else { return nil }
            return MindCardContextRow(primary: label, secondary: oneLine(preview.at))
        }
        guard !rows.isEmpty else { return nil }
        return MindCardContextSection(kind: .record, title: "from your record", rows: rows)
    }

    static func extractedSection(for output: MindOutput) -> MindCardContextSection? {
        let rows = ([output.observation].compactMap { oneLine($0) } + output.considerations.compactMap(oneLine))
            .map { MindCardContextRow(primary: $0, secondary: nil) }
        guard !rows.isEmpty else { return nil }
        return MindCardContextSection(kind: .extracted, title: "what k extracted", rows: rows)
    }

    private static func oneLine(_ value: String?) -> String? {
        let text = (value ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}

struct MindCardPinnedLayoutPlan: Equatable {
    var viewportHeight: CGFloat
    var bodyContentHeight: CGFloat
    var pinnedControlsHeight: CGFloat
    var scrollViewportHeight: CGFloat
    var pinnedControlsMinY: CGFloat

    var bodyOverflows: Bool {
        bodyContentHeight > scrollViewportHeight
    }

    var optionsVisible: Bool {
        pinnedControlsHeight > 0 && pinnedControlsMinY >= 0
    }
}

enum MindCardPinnedLayoutPolicy {
    static let scrollBodyLayoutPriority = 0.0
    static let pinnedControlsLayoutPriority = 1.0
    static let minimumScrollableBodyHeight: CGFloat = KStyle.minimumTapTarget

    static func plan(
        viewportHeight: CGFloat,
        bodyContentHeight: CGFloat,
        pinnedControlsHeight: CGFloat
    ) -> MindCardPinnedLayoutPlan {
        let viewportHeight = max(0, viewportHeight)
        let pinnedControlsHeight = max(0, pinnedControlsHeight)
        let availableForBody = max(minimumScrollableBodyHeight, viewportHeight - pinnedControlsHeight)
        return MindCardPinnedLayoutPlan(
            viewportHeight: viewportHeight,
            bodyContentHeight: max(0, bodyContentHeight),
            pinnedControlsHeight: pinnedControlsHeight,
            scrollViewportHeight: availableForBody,
            pinnedControlsMinY: max(0, viewportHeight - pinnedControlsHeight)
        )
    }
}

struct MindArtifactsResponse: Decodable, Equatable, Sendable {
    var outputs: [MindOutput]
    var priorVerdicts: [MindEvalVerdict]
    var evalDate: String?
    var generatedAt: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case outputSections
        case buildDecide = "build_decide"
        case candidates
        case themesOpenLoops = "themes_open_loops"
        case resurfaced
        case newIdeas = "new_ideas"
        case priorVerdicts
        case evalDate
        case generatedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let verdicts = (try? container.decode(LossyDecodableArray<MindEvalVerdict>.self, forKey: .priorVerdicts).elements) ?? []
        var verdictsByKey: [MindOutputKey: MindVerdict] = [:]
        for verdict in verdicts {
            verdictsByKey[verdict.key] = verdict.verdict
        }
        var packets: [ViewPacket] = []

        if let sections = try? container.decode(LossyDecodableArray<MindOutputSection>.self, forKey: .outputSections).elements {
            packets.append(contentsOf: sections.flatMap(\.items))
        }

        for key in [CodingKeys.buildDecide, .candidates, .themesOpenLoops, .resurfaced, .newIdeas] {
            if let group = try? container.decode(LossyDecodableArray<ViewPacket>.self, forKey: key).elements {
                packets.append(contentsOf: group)
            }
        }

        outputs = Self.assembleOutputs(packets: packets, verdictsByKey: verdictsByKey)
        priorVerdicts = verdicts
        evalDate = try? container.decodeIfPresent(String.self, forKey: .evalDate)
        generatedAt = try? container.decodeIfPresent(String.self, forKey: .generatedAt)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
    }

    // Shared packet → output pipeline. Reused by the disk cache so a cached
    // pass rebuilds byte-identically to a freshly fetched one.
    static func assembleOutputs(
        packets: [ViewPacket],
        verdictsByKey: [MindOutputKey: MindVerdict]
    ) -> [MindOutput] {
        var seen: Set<String> = []
        return packets.compactMap { packet in
            guard var output = MindOutput(packet: packet) else { return nil }
            guard seen.insert(output.id).inserted else { return nil }
            output.verdict = verdictsByKey[output.key]
            return output
        }
    }
}

/// A previously fetched mind pass, persisted so a cold launch renders the last
/// known cards immediately instead of a bare loading state. Only the display
/// packets and prior verdicts are stored; outputs are rebuilt via the same
/// `assembleOutputs` pipeline the live decoder uses.
struct CachedMindPass: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var packets: [ViewPacket]
    var priorVerdicts: [MindEvalVerdict]
    var evalDate: String?
    var generatedAt: String?
    var source: String?

    init(response: MindArtifactsResponse) {
        version = Self.currentVersion
        packets = response.outputs.map(\.packet)
        priorVerdicts = response.priorVerdicts
        evalDate = response.evalDate
        generatedAt = response.generatedAt
        source = response.source
    }

    func rebuiltOutputs() -> [MindOutput] {
        var verdictsByKey: [MindOutputKey: MindVerdict] = [:]
        for verdict in priorVerdicts {
            verdictsByKey[verdict.key] = verdict.verdict
        }
        return MindArtifactsResponse.assembleOutputs(packets: packets, verdictsByKey: verdictsByKey)
    }
}

protocol MindPassCaching: Sendable {
    func load() -> CachedMindPass?
    func save(_ pass: CachedMindPass)
    func clear()
}

/// Test/default seam: the model is constructed with this so unit tests never
/// touch the shared Application Support file. Production wires the disk cache
/// at the view layer.
struct DisabledMindPassCache: MindPassCaching {
    func load() -> CachedMindPass? { nil }
    func save(_ pass: CachedMindPass) {}
    func clear() {}
}

/// Disk-backed cache modeled on `ChatBranchThreadStore`: atomic write to
/// Application Support, silent empty read on any failure, injectable file URL
/// for hermetic tests.
struct MindPassDiskCache: MindPassCaching {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = MindPassDiskCache.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("mind-pass-cache.json", isDirectory: false)
    }

    func load() -> CachedMindPass? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(CachedMindPass.self, from: data),
              stored.version == CachedMindPass.currentVersion
        else { return nil }
        return stored
    }

    func save(_ pass: CachedMindPass) {
        guard !pass.packets.isEmpty else {
            clear()
            return
        }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(pass).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] mind pass cache save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }
}

private struct MindOutputSection: Decodable, Equatable, Sendable {
    var key: String
    var label: String?
    var items: [ViewPacket]

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        items = (try? container.decode(LossyDecodableArray<ViewPacket>.self, forKey: .items).elements) ?? []
    }
}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
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

struct MindVerdictResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var verdict: MindEvalVerdict?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case verdict
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        verdict = try? container.decodeIfPresent(MindEvalVerdict.self, forKey: .verdict)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
    }
}

enum MindLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct MindSubmittedVerdict: Equatable, Sendable {
    var output: MindOutput
    var index: Int
    var verdict: MindVerdict
}

struct MindInlineVerdictError: Equatable, Sendable {
    var outputKey: MindOutputKey
    var verdict: MindVerdict
    var text: String
}

@MainActor
final class MindVerdictsModel: ObservableObject {
    @Published private(set) var outputs: [MindOutput] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var loadState: MindLoadState = .idle
    @Published private(set) var loadErrorText: String?
    @Published private(set) var submissionError: MindInlineVerdictError?
    @Published private(set) var pendingVerdict: MindVerdict?
    @Published private(set) var pendingOutputKey: MindOutputKey?
    @Published private(set) var lastSubmitted: MindSubmittedVerdict?
    @Published private(set) var undoExpiresAt: Date?
    @Published private(set) var nudgeFeedback: [MindOutputKey: MindNudgeFeedback] = [:]
    @Published private(set) var connectionState = KConnectionStateModel()
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isStale = false
    // A fetch is in flight over cards already on screen (from memory or disk
    // cache). Drives the quiet "refreshing" affordance instead of the skeleton.
    @Published private(set) var isRefreshing = false
    // The cards on screen came from the disk cache and have not yet been
    // confirmed against a live fetch.
    @Published private(set) var isShowingCachedPass = false
    @Published private(set) var feedbackTriggers = KFeedbackTriggers()
    @Published var baseURL: String

    private let clientFactory: (String) -> AGUIClient
    private let cache: MindPassCaching
    private let auditState: MindDemo.AuditState?
    private let demoResponse: MindArtifactsResponse?
    private var evalDate: String?
    private var sessionVerdicts: [MindOutputKey: MindVerdict] = [:]
    private var hasLoaded = false
    private var undoExpiryTask: Task<Void, Never>?
    private let undoWindow: TimeInterval = 5

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        cache: MindPassCaching = DisabledMindPassCache(),
        demoResponse: MindArtifactsResponse? = nil
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.cache = cache
        let resolvedAuditState = MindDemo.auditState
        self.auditState = resolvedAuditState
        self.demoResponse = demoResponse ?? (MindDemo.enabled && resolvedAuditState != .error ? MindDemo.response : nil)
    }

    var currentOutput: MindOutput? {
        guard outputs.indices.contains(currentIndex) else { return nil }
        return outputs[currentIndex]
    }

    var isLoading: Bool {
        loadState == .loading
    }

    // Skeleton state: no cards yet, and the first fetch has neither landed nor
    // failed. Kept distinct from earned-silence (loaded + empty) and from
    // unreachable (failed + empty) so the three read differently — invariant 7.
    var isInitialLoad: Bool {
        outputs.isEmpty && loadState != .loaded && loadErrorText == nil
    }

    var isComplete: Bool {
        !outputs.isEmpty && currentIndex >= outputs.count
    }

    var progressText: String {
        guard !outputs.isEmpty else { return "0 of 0" }
        return "\(min(currentIndex + 1, outputs.count)) of \(outputs.count)"
    }

    var emptyText: String {
        "no outputs to judge — the mind pass is running"
    }

    var canUndo: Bool {
        canUndo(now: Date())
    }

    var canBrowsePrevious: Bool {
        !outputs.isEmpty && currentIndex > 0
    }

    var canBrowseNext: Bool {
        !outputs.isEmpty && currentIndex < outputs.count - 1
    }

    var unjudgedCount: Int {
        outputs.filter { !Self.isDone($0, sessionVerdicts: sessionVerdicts) }.count
    }

    var thoughtList: MindThoughtListState {
        MindThoughtListState(outputs: outputs)
    }

    var isDemoPass: Bool { demoResponse != nil }

    func canUndo(now: Date) -> Bool {
        guard lastSubmitted != nil, pendingVerdict == nil, let undoExpiresAt else { return false }
        return now <= undoExpiresAt
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadState != .loading else { return }
        Task { await load() }
    }

    /// Render the last persisted pass immediately on a cold launch so the first
    /// paint is real cards, not a skeleton. A live `load()` still follows and
    /// supersedes this; until it lands, the pass reads as stale + refreshing.
    func primeFromCacheIfNeeded() {
        if KLoadingPreview.isEnabled { return }
        guard demoResponse == nil, auditState != .error else { return }
        guard outputs.isEmpty, !hasLoaded, loadState == .idle else { return }
        guard let cached = cache.load() else { return }
        let rebuilt = cached.rebuiltOutputs()
        guard !rebuilt.isEmpty else { return }
        evalDate = cached.evalDate
        outputs = Self.sortedForJudgment(outputs: rebuilt, sessionVerdicts: sessionVerdicts)
        currentIndex = outputs.firstIndex(where: { !Self.isDone($0, sessionVerdicts: sessionVerdicts) }) ?? 0
        isShowingCachedPass = true
        isStale = true
    }

    func browsePrevious() {
        browse(by: -1)
    }

    func browseNext() {
        browse(by: 1)
    }

    private func browse(by delta: Int) {
        guard pendingVerdict == nil, !outputs.isEmpty else { return }
        let baseIndex = min(currentIndex, outputs.count - 1)
        let nextIndex = min(max(baseIndex + delta, 0), outputs.count - 1)
        guard nextIndex != currentIndex else { return }
        currentIndex = nextIndex
    }

    func load() async {
#if DEBUG
        if auditState == .error {
            outputs = []
            currentIndex = 0
            evalDate = nil
            isShowingCachedPass = false
            let text = KCopy.mindUnreachable
            setLoadErrorText(text)
            loadState = .failed(text)
            connectionState.transition(to: .offlineRetrying)
            isStale = false
            isRefreshing = false
            hasLoaded = true
            return
        }
#endif
        if let demoResponse {
            loadDemo(response: demoResponse)
            return
        }

        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        // Cards already on screen (memory or primed cache) refresh in place;
        // only a truly empty surface shows the skeleton loading state.
        isRefreshing = !outputs.isEmpty
        if outputs.isEmpty {
            loadState = .loading
            connectionState.transition(to: .connecting)
        }
        setLoadErrorText(nil)

        if KLoadingPreview.isEnabled {
            return
        }

        do {
            let response = try await clientFactory(baseURL).mindArtifacts()
            evalDate = response.evalDate
            outputs = Self.sortedForJudgment(
                outputs: response.outputs.map { output in
                    var hydrated = output
                    if let verdict = sessionVerdicts[output.key] {
                        hydrated.verdict = verdict
                    }
                    return hydrated
                },
                sessionVerdicts: sessionVerdicts
            )
            currentIndex = outputs.isEmpty ? 0 : min(currentIndex, outputs.count - 1)
            if let firstUnjudged = outputs.firstIndex(where: { !Self.isDone($0, sessionVerdicts: sessionVerdicts) }) {
                currentIndex = firstUnjudged
            }
            loadState = .loaded
            connectionState.transition(to: .live)
            lastSyncedAt = Date()
            isStale = false
            isShowingCachedPass = false
            isRefreshing = false
            hasLoaded = true
            cache.save(CachedMindPass(response: response))
        } catch {
            let text = Self.loadFailureText(reason: error.localizedDescription)
            setLoadErrorText(text)
            loadState = .failed(text)
            connectionState.transition(to: .offlineRetrying)
            isStale = !outputs.isEmpty
            isRefreshing = false
        }
    }

    @discardableResult
    func submitVerdict(_ verdict: MindVerdict) async -> Bool {
        guard let output = currentOutput else { return false }
        return await submitVerdict(verdict, for: output.key)
    }

    @discardableResult
    func submitVerdict(_ verdict: MindVerdict, for outputKey: MindOutputKey) async -> Bool {
        guard pendingVerdict == nil,
              let outputIndex = outputs.firstIndex(where: { $0.key == outputKey })
        else { return false }
        let output = outputs[outputIndex]
        pendingVerdict = verdict
        pendingOutputKey = outputKey
        setSubmissionError(nil)

        if demoResponse != nil {
            sessionVerdicts[output.key] = verdict
            outputs[outputIndex].verdict = verdict
            lastSubmitted = MindSubmittedVerdict(output: output, index: outputIndex, verdict: verdict)
            undoExpiresAt = Date().addingTimeInterval(undoWindow)
            scheduleUndoExpiry()
            currentIndex = min(outputIndex + 1, outputs.count)
            pendingVerdict = nil
            pendingOutputKey = nil
            recordFeedback(KFeedbackPolicy.mindVerdictEvent(didSubmit: true))
            return true
        }

        do {
            let response = try await clientFactory(baseURL).recordMindVerdict(
                date: evalDate,
                outputType: output.outputType,
                outputId: output.outputId,
                verdict: verdict
            )
            guard response.ok else {
                let reason = response.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                failSubmission(output: output, verdict: verdict, reason: reason?.isEmpty == false ? reason! : "unknown")
                pendingVerdict = nil
                pendingOutputKey = nil
                return false
            }

            let appliedVerdict = response.verdict?.verdict ?? verdict
            sessionVerdicts[output.key] = appliedVerdict
            if outputs.indices.contains(outputIndex) {
                outputs[outputIndex].verdict = appliedVerdict
            }
            lastSubmitted = MindSubmittedVerdict(output: output, index: outputIndex, verdict: appliedVerdict)
            undoExpiresAt = Date().addingTimeInterval(undoWindow)
            scheduleUndoExpiry()
            currentIndex = min(outputIndex + 1, outputs.count)
            pendingVerdict = nil
            pendingOutputKey = nil
            recordFeedback(KFeedbackPolicy.mindVerdictEvent(didSubmit: true))
            return true
        } catch {
            failSubmission(output: output, verdict: verdict, reason: error.localizedDescription)
            pendingVerdict = nil
            pendingOutputKey = nil
            return false
        }
    }

    @discardableResult
    func retryVerdict() async -> Bool {
        guard let submissionError else { return false }
        return await submitVerdict(submissionError.verdict, for: submissionError.outputKey)
    }

    @discardableResult
    func submitNudgeFeedback(_ feedback: MindNudgeFeedback) async -> Bool {
        guard let output = currentOutput, output.supportsNudgeFeedback else { return false }
        nudgeFeedback[output.key] = feedback

        if demoResponse != nil {
            return true
        }

        do {
            let response = try await clientFactory(baseURL).recordMindFeedback(
                date: evalDate,
                outputType: output.outputType,
                outputId: output.outputId,
                feedback: feedback
            )
            return response.ok
        } catch {
            return false
        }
    }

    func undoLastVerdict() {
        guard let lastSubmitted, outputs.indices.contains(lastSubmitted.index), pendingVerdict == nil else { return }
        currentIndex = lastSubmitted.index
        setSubmissionError(nil)
        self.lastSubmitted = nil
        undoExpiresAt = nil
        undoExpiryTask?.cancel()
    }

    private func scheduleUndoExpiry() {
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.lastSubmitted = nil
            self.undoExpiresAt = nil
        }
    }

    private func failSubmission(output: MindOutput, verdict: MindVerdict, reason: String) {
        setSubmissionError(MindInlineVerdictError(
            outputKey: output.key,
            verdict: verdict,
            text: Self.verdictFailureText(reason: reason)
        ))
    }

    private static func sortedForJudgment(
        outputs: [MindOutput],
        sessionVerdicts: [MindOutputKey: MindVerdict]
    ) -> [MindOutput] {
        outputs.enumerated()
            .sorted { left, right in
                let leftDone = isDone(left.element, sessionVerdicts: sessionVerdicts)
                let rightDone = isDone(right.element, sessionVerdicts: sessionVerdicts)
                if leftDone != rightDone { return !leftDone }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private func loadDemo(response: MindArtifactsResponse) {
        evalDate = response.evalDate
        outputs = Self.sortedForJudgment(outputs: response.outputs, sessionVerdicts: sessionVerdicts)
        currentIndex = outputs.firstIndex(where: { !Self.isDone($0, sessionVerdicts: sessionVerdicts) }) ?? 0
        loadState = .loaded
        loadErrorText = nil
        connectionState.transition(to: .live)
        isStale = false
        isShowingCachedPass = false
        isRefreshing = false
        hasLoaded = true
    }

    private static func isDone(_ output: MindOutput, sessionVerdicts: [MindOutputKey: MindVerdict]) -> Bool {
        output.verdict != nil || sessionVerdicts[output.key] != nil
    }

    private static func verdictFailureText(reason: String) -> String {
        KCopy.answerFailed(reason: reason)
    }

    private static func loadFailureText(reason: String) -> String {
        KCopy.answerFailed(reason: reason)
    }

    private func setLoadErrorText(_ text: String?) {
        let previous = loadErrorText
        loadErrorText = text
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
    }

    private func setSubmissionError(_ error: MindInlineVerdictError?) {
        let previous = submissionError?.text
        submissionError = error
        recordFeedback(KFeedbackPolicy.errorSurfaced(previous: previous, current: error?.text))
    }

    private func recordFeedback(_ event: KFeedbackEvent?) {
        var triggers = feedbackTriggers
        triggers.record(event)
        feedbackTriggers = triggers
    }
}

struct MindVerdictsView: View {
    @StateObject private var model = MindVerdictsModel(cache: MindPassDiskCache())
    @State private var entityDossierSelection: EntityDossierSelection?
    @State private var selectedOutputID: String?
    @State private var showsArchived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onUnjudgedCountChange: (Int) -> Void
    let onStalenessChange: (Bool) -> Void
    let onHandoffToChat: (ChatThreadHandoff) -> Void

    init(
        onUnjudgedCountChange: @escaping (Int) -> Void = { _ in },
        onStalenessChange: @escaping (Bool) -> Void = { _ in },
        onHandoffToChat: @escaping (ChatThreadHandoff) -> Void = { _ in }
    ) {
        self.onUnjudgedCountChange = onUnjudgedCountChange
        self.onStalenessChange = onStalenessChange
        self.onHandoffToChat = onHandoffToChat
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = KStyle.columnWidth(in: proxy.size.width)
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                mindColumn(width: columnWidth)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, KStyle.columnMargin)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mind-view")
        .onAppear {
            model.primeFromCacheIfNeeded()
            model.loadIfNeeded()
            if KLoadingPreview.hasFlag("-ui34-loading-dossier") {
                entityDossierSelection = EntityDossierSelection(name: "ui34 entity")
            }
            onUnjudgedCountChange(model.unjudgedCount)
            onStalenessChange(model.isStale)
        }
        .onChange(of: model.unjudgedCount) { _, count in
            onUnjudgedCountChange(count)
        }
        .onChange(of: model.isStale) { _, isStale in
            onStalenessChange(isStale)
        }
        .onChange(of: model.thoughtList.active.map(\.id)) { _, activeIDs in
            if let selectedOutputID, !activeIDs.contains(selectedOutputID) {
                self.selectedOutputID = nil
            }
        }
        .kSensoryFeedback(model.feedbackTriggers)
    }

    private func mindColumn(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            content
                .environment(\.kSelectedEntityID, entityDossierSelection?.id)

            if let entityDossierSelection {
                EntityDossierPanel(
                    baseURL: model.baseURL,
                    selection: entityDossierSelection,
                    onDismiss: dismissEntityDossier
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(x: KStyle.gesturePageTransitionOffset))
                )
                .zIndex(KStyle.bioRailDetailZIndex)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        // Three distinct empty surfaces — never collapsed into one. Invariant 7:
        // unreachable is not the same as ran-and-surfaced-nothing.
        if model.isInitialLoad {
            KLoadingPrimitive(
                variant: .skeleton,
                lineCount: 3,
                label: KCopy.mindLoading,
                accessibilityIdentifier: "mind-loading-skeleton"
            )
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.top, KStyle.mindThoughtRowVerticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.loadErrorText != nil, model.outputs.isEmpty {
            MindUnreachableView {
                Task { await model.load() }
            }
            .padding(KStyle.inputSidePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.outputs.isEmpty {
            ScrollView {
                Text(KCopy.mindSilentDay)
                    .font(KStyle.mindThoughtFont(.claim))
                    .foregroundStyle(
                        KStyle.mindThoughtUnselectedInk.opacity(KStyle.quaternaryTextOpacity)
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, KStyle.mindThoughtSilentDayTopPadding)
                    .padding(.horizontal, KStyle.inputSidePadding)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await model.load()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mind-card-scroll")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.isRefreshing {
                        MindRefreshingRow()
                            .padding(.bottom, KStyle.mindThoughtRowVerticalPadding)
                    }

                    if let loadErrorText = model.loadErrorText {
                        MindErrorRow(text: loadErrorText) {
                            Task { await model.load() }
                        }
                        .padding(.bottom, KStyle.mindThoughtRowVerticalPadding)
                    }

                    if let weekLine = KCopy.mindWeekLine(
                        active: model.thoughtList.active.count,
                        unjudged: model.unjudgedCount,
                        archived: model.thoughtList.archived.count
                    ) {
                        Text(weekLine)
                            .font(KStyle.mindThoughtFont(.reference))
                            .foregroundStyle(
                                KStyle.mindThoughtUnselectedInk.opacity(KStyle.tertiaryTextOpacity)
                            )
                            .padding(.bottom, KStyle.mindThoughtClaimTopPadding)
                            .accessibilityIdentifier("mind-week-line")
                    }

                    ForEach(model.thoughtList.active) { output in
                        thoughtCard(output)
                    }

                    if !model.thoughtList.archived.isEmpty {
                        archivedToggle
                            .padding(.top, KStyle.mindThoughtArchivedTopPadding)

                        if showsArchived {
                            ForEach(model.thoughtList.archived) { output in
                                MindThoughtCard(
                                    output: output,
                                    isSelected: false,
                                    actionsDisabled: true,
                                    onSelect: {},
                                    onOpenEntity: openEntityDossier(_:),
                                    onVerdict: { _ in },
                                    onRetry: {}
                                )
                                .transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.bottom, KStyle.inputBottomPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("mind-stack-index")
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await model.load()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mind-card-scroll")
        }
    }

    private func thoughtCard(_ output: MindOutput) -> some View {
        let isSelected = selectedOutputID == output.id
        let isPending = model.pendingOutputKey == output.key
        return MindThoughtCard(
            output: output,
            isSelected: isSelected,
            pendingVerdict: isPending ? model.pendingVerdict : nil,
            actionsDisabled: model.pendingVerdict != nil,
            submissionErrorText: model.submissionError?.outputKey == output.key
                ? model.submissionError?.text
                : nil,
            preservesLegacyCardIdentifier: model.thoughtList.active.first?.id == output.id,
            onSelect: {
                withAnimation(KStyle.mindThoughtAnimation(.selectionFlood, reduceMotion: reduceMotion)) {
                    selectedOutputID = isSelected ? nil : output.id
                }
            },
            onOpenEntity: openEntityDossier(_:),
            onVerdict: { verdict in
                Task {
                    let didSubmit = await model.submitVerdict(verdict, for: output.key)
                    if didSubmit, verdict == .junk {
                        selectedOutputID = nil
                    }
                }
            },
            onRetry: {
                Task { await model.retryVerdict() }
            },
            onComment: { comment in
                guard !model.isDemoPass else { return }
                onHandoffToChat(
                    MindChatThreadHandoffComposer.handoff(for: output, comment: comment)
                )
            },
            onContinueInChat: {
                guard !model.isDemoPass else { return }
                onHandoffToChat(
                    MindChatThreadHandoffComposer.handoff(for: output)
                )
            }
        )
    }

    private var archivedToggle: some View {
        KActRow(
            actions: [
                KActItem(
                    id: "archived",
                    label: KCopy.mindArchivedCount(
                        model.thoughtList.archived.count,
                        isExpanded: showsArchived
                    ),
                    accessibilityIdentifier: "mind-archived-toggle"
                ),
            ],
            variant: .mindFeedback,
            selectedActionIDs: showsArchived ? ["archived"] : [],
            onSelect: { _ in
                withAnimation(KStyle.mindThoughtAnimation(.evidenceReveal, reduceMotion: reduceMotion)) {
                    showsArchived.toggle()
                }
            }
        )
    }

    private func openEntityDossier(_ ref: EntityRef) {
        KStyle.withGesturePageMotion(reduceMotion: reduceMotion) {
            entityDossierSelection = EntityDossierSelection(ref: ref)
        }
    }

    private func dismissEntityDossier() {
        KStyle.withGesturePageMotion(reduceMotion: reduceMotion) {
            entityDossierSelection = nil
        }
    }
}

/// Quiet "k is unreachable" line with a retry — the failed-fetch surface, kept
/// visually apart from earned silence so the two never read the same.
private struct MindUnreachableView: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            KMonoCaption(KCopy.mindUnreachable, variant: .metadata, state: .offline)
            Spacer(minLength: 8)
            KActRow(
                actions: [KActItem(id: "retry")],
                variant: .admin,
                onSelect: { _ in onRetry() }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mind-unreachable")
    }
}

/// Subtle marker shown above cached/in-memory cards while a fresh pass loads.
private struct MindRefreshingRow: View {
    var body: some View {
        KLoadingPrimitive(
            variant: .dot,
            label: KCopy.mindRefreshing,
            accessibilityIdentifier: "mind-refreshing"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MindOutputCardView: View {
    let output: MindOutput
    let pendingVerdict: MindVerdict?
    let selectedNudgeFeedback: MindNudgeFeedback?
    let submissionErrorText: String?
    let onRetry: () -> Void
    let onNudgeFeedback: (MindNudgeFeedback) -> Void
    let onBrowsePrevious: () -> Void
    let onBrowseNext: () -> Void
    let onOpenEntity: (EntityRef) -> Void
    let onVerdict: (MindVerdict) -> Void

    @State private var detailsExpanded = false

    private var isSubmitting: Bool {
        pendingVerdict != nil
    }

    private var faceRenderState: CardFaceRenderState {
        CardFaceRenderState(face: output.face, isExpanded: detailsExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                cardBodyContent
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(MindCardPinnedLayoutPolicy.scrollBodyLayoutPriority)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mind-card-scroll")

            MindVerdictControlsView(
                output: output,
                pendingVerdict: pendingVerdict,
                state: isSubmitting ? .loading : .resting,
                errorText: submissionErrorText,
                showsConsequences: faceRenderState.showsConsequences,
                linksDisclosureEntities: faceRenderState.linksDisclosureEntities,
                onOpenEntity: onOpenEntity,
                onVerdict: onVerdict,
                onRetry: onRetry
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(MindCardPinnedLayoutPolicy.pinnedControlsLayoutPriority)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(browseGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .junk))) {
            submitAccessibilityVerdict(.junk)
        }
        .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .nod))) {
            submitAccessibilityVerdict(.nod)
        }
        .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .actOn))) {
            submitAccessibilityVerdict(.actOn)
        }
        .accessibilityIdentifier("mind-output-card")
    }

    private var browseGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) >= 48, abs(horizontal) > abs(vertical) * 1.4 else { return }
                if horizontal < 0 {
                    onBrowseNext()
                } else {
                    onBrowsePrevious()
                }
            }
    }

    @ViewBuilder
    private var cardBodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if faceRenderState.showsFace, let face = output.face {
                faceBody(face)
                    .transition(.opacity)
            } else if output.face != nil {
                disclosedBody
                    .transition(.opacity)
            } else {
                legacyBody
            }

            if let detailsText = faceRenderState.detailsText {
                detailsToggle(text: detailsText)
            }
        }
    }

    private func faceBody(_ face: CardFace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EntityLinkedText(
                face.anchor.displayText,
                refs: output.entityRefs,
                fontToken: .content,
                opacity: KStyle.primaryTextOpacity,
                onOpen: onOpenEntity
            )

            EntityLinkedText(
                face.ask,
                refs: output.entityRefs,
                fontToken: .mindStatement,
                opacity: KStyle.secondaryTextOpacity,
                lineSpacing: 4,
                onOpen: onOpenEntity
            )
                .accessibilityLabel(MindVerdictAccessibility.cardLabel(for: output))
        }
    }

    private var disclosedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            primaryBody(linksDisclosureEntities: true)
            cardContext(linksDisclosureEntities: true)
            stakesBody(linksDisclosureEntities: true)
            nudgeFeedbackBody
            MindDetailsView(
                output: output,
                showsOptions: output.brief == nil,
                linksDisclosureEntities: true,
                onOpenEntity: onOpenEntity
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            primaryBody(linksDisclosureEntities: false)
            cardContext(linksDisclosureEntities: false)
            stakesBody(linksDisclosureEntities: false)
            nudgeFeedbackBody

            if output.brief == nil {
                detailsToggle(text: evidenceLineText)
            }

            if detailsExpanded {
                MindDetailsView(
                    output: output,
                    showsOptions: true,
                    linksDisclosureEntities: false,
                    onOpenEntity: onOpenEntity
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func primaryBody(linksDisclosureEntities: Bool) -> some View {
        if let brief = output.brief {
            decisionBriefBody(brief, linksDisclosureEntities: linksDisclosureEntities)
        } else {
            statementBody(linksDisclosureEntities: linksDisclosureEntities)
        }
    }

    private func cardContext(linksDisclosureEntities: Bool) -> some View {
        MindCardContextView(
            sections: MindCardContextPresenter.sections(for: output),
            refs: output.entityRefs,
            linksDisclosureEntities: linksDisclosureEntities,
            onOpenEntity: onOpenEntity
        )
    }

    @ViewBuilder
    private func stakesBody(linksDisclosureEntities: Bool) -> some View {
        if let stakesText {
            if linksDisclosureEntities {
                EntityLinkedText(
                    stakesText,
                    refs: output.entityRefs,
                    fontToken: .monoCaption,
                    opacity: KStyle.tertiaryTextOpacity,
                    onOpen: onOpenEntity
                )
            } else {
                KMonoCaption(stakesText, variant: .metadata)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var nudgeFeedbackBody: some View {
        if output.supportsNudgeFeedback {
            MindNudgeFeedbackRow(
                selection: selectedNudgeFeedback,
                onSelect: onNudgeFeedback
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func statementBody(linksDisclosureEntities: Bool) -> some View {
        if let what = output.what {
            if linksDisclosureEntities {
                EntityLinkedText(
                    what,
                    refs: output.entityRefs,
                    fontToken: .monoCaption,
                    opacity: KStyle.tertiaryTextOpacity,
                    onOpen: onOpenEntity
                )
            } else {
                KMonoCaption(what, variant: .metadata)
            }
        }

        EntityLinkedText(
            output.statement,
            refs: output.entityRefs,
            fontToken: .mindStatement,
            opacity: KStyle.primaryTextOpacity,
            minimumScaleFactor: KStyle.mindStatementMinimumScaleFactor,
            lineSpacing: 4,
            onOpen: onOpenEntity
        )
            .accessibilityLabel(MindVerdictAccessibility.cardLabel(for: output))
            .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .junk))) {
                submitAccessibilityVerdict(.junk)
            }
            .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .nod))) {
                submitAccessibilityVerdict(.nod)
            }
            .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .actOn))) {
                submitAccessibilityVerdict(.actOn)
            }
    }

    private func detailsToggle(text: String) -> some View {
        KActRow(
            actions: [
                KActItem(
                    id: "details",
                    label: text,
                    accessibilityIdentifier: "mind-details-toggle"
                ),
            ],
            variant: .mindFeedback,
            selectedActionIDs: detailsExpanded ? ["details"] : [],
            onSelect: { _ in
                KStyle.withMotion {
                    detailsExpanded.toggle()
                }
            }
        )
        .accessibilityLabel(MindVerdictAccessibility.detailsLabel(
            for: output,
            isExpanded: detailsExpanded
        ))
        .accessibilityHint(MindVerdictAccessibility.detailsHint(isExpanded: detailsExpanded))
        .accessibilityIdentifier("mind-details-toggle")
    }

    private var stakesText: String? {
        output.brief?.stakes ?? output.stakes
    }

    private var metaText: String {
        let evidenceCount = output.evidence.count
        let evidenceWord = evidenceCount == 1 ? "evidence" : "evidence"
        return "\(output.displayType) · \(evidenceCount) \(evidenceWord)"
    }

    private var evidenceLineText: String {
        DecisionEvidenceLineFormatter.line(for: output.evidenceSummary)
            ?? DecisionEvidencePreviewFormatter.summaryLine(for: output.evidencePreviews)
            ?? metaText
    }

    private func decisionBriefBody(
        _ brief: DecisionBrief,
        linksDisclosureEntities: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let whyNow = brief.whyNow {
                EntityLinkedText(
                    whyNow,
                    refs: output.entityRefs,
                    fontToken: .content,
                    opacity: KStyle.secondaryTextOpacity,
                    onOpen: onOpenEntity
                )
            }

            if let openQuestion = brief.openQuestion {
                EntityLinkedText(
                    openQuestion,
                    refs: output.entityRefs,
                    fontToken: .mindStatement,
                    opacity: KStyle.primaryTextOpacity,
                    minimumScaleFactor: KStyle.mindStatementMinimumScaleFactor,
                    lineSpacing: 4,
                    onOpen: onOpenEntity
                )
                    .accessibilityLabel(MindVerdictAccessibility.cardLabel(for: output))
                    .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .junk))) {
                        submitAccessibilityVerdict(.junk)
                    }
                    .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .nod))) {
                        submitAccessibilityVerdict(.nod)
                    }
                    .accessibilityAction(named: Text(MindVerdictAccessibility.controlLabel(for: .actOn))) {
                        submitAccessibilityVerdict(.actOn)
                    }
            }

            if linksDisclosureEntities {
                EntityLinkedText(
                    brief.blockerLine,
                    refs: output.entityRefs,
                    fontToken: .monoCaption,
                    opacity: KStyle.tertiaryTextOpacity,
                    onOpen: onOpenEntity
                )
            } else {
                KMonoCaption(brief.blockerLine, variant: .metadata)
                    .textSelection(.enabled)
            }
        }
    }

    private func submitAccessibilityVerdict(_ verdict: MindVerdict) {
        guard !isSubmitting else { return }
        onVerdict(verdict)
    }
}

private struct MindCardContextView: View {
    let sections: [MindCardContextSection]
    let refs: [EntityRef]
    let linksDisclosureEntities: Bool
    let onOpenEntity: (EntityRef) -> Void

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
            }
        }
    }

    private func sectionView(_ section: MindCardContextSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KMonoCaption(section.title, variant: .metadata, state: .disabled)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, kind: section.kind)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: MindCardContextRow, kind: MindCardContextSection.Kind) -> some View {
        switch kind {
        case .record:
            if linksDisclosureEntities {
                linkedRecordRow(row)
            } else {
                recordRow(row)
                    .kFont(.monoCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        case .extracted:
            if linksDisclosureEntities {
                EntityLinkedText(
                    row.primary,
                    refs: refs,
                    fontToken: .content,
                    opacity: KStyle.secondaryTextOpacity,
                    onOpen: onOpenEntity
                )
            } else {
                Text(row.primary)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func linkedRecordRow(_ row: MindCardContextRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.microSpacing) {
            EntityLinkedText(
                row.primary,
                refs: refs,
                fontToken: .monoCaption,
                opacity: KStyle.secondaryTextOpacity,
                onOpen: onOpenEntity
            )
            if let secondary = row.secondary {
                KMonoCaption("· \(secondary)", variant: .metadata)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordRow(_ row: MindCardContextRow) -> Text {
        var text = Text(row.primary)
            .foregroundColor(.white.opacity(KStyle.secondaryTextOpacity))
        if let secondary = row.secondary {
            text = text
                + Text(" · ").foregroundColor(.white.opacity(KStyle.tertiaryTextOpacity))
                + Text(secondary).foregroundColor(.white.opacity(KStyle.tertiaryTextOpacity))
        }
        return text
    }
}

private struct MindVerdictControlsView: View {
    let output: MindOutput
    let pendingVerdict: MindVerdict?
    let state: KPrimitiveInteractionState
    let errorText: String?
    let showsConsequences: Bool
    let linksDisclosureEntities: Bool
    let onOpenEntity: (EntityRef) -> Void
    let onVerdict: (MindVerdict) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.verdictButtonSpacing) {
            HStack(alignment: .top, spacing: KStyle.verdictButtonSpacing) {
                ForEach(MindVerdict.buttonOrder) { verdict in
                    VStack(alignment: .center, spacing: KStyle.microSpacing) {
                        MindVerdictControlButton(
                            output: output,
                            verdict: verdict,
                            isPending: pendingVerdict == verdict,
                            isDisabled: buttonsDisabled,
                            state: state,
                            action: { onVerdict(verdict) }
                        )
                        if showsConsequences,
                           let whatHappens = output.brief?.whatHappens(for: verdict.rawValue) {
                            // The consequence IS the decision — never clip it
                            // (k-copy: a visible truncated fragment fails review).
                            if linksDisclosureEntities {
                                EntityLinkedText(
                                    whatHappens.lowercased(),
                                    refs: output.entityRefs,
                                    fontToken: .monoCaption,
                                    opacity: KStyle.tertiaryTextOpacity,
                                    onOpen: onOpenEntity
                                )
                                .multilineTextAlignment(.center)
                            } else {
                                Text(whatHappens.lowercased())
                                    .kFont(.monoCaption)
                                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let errorText {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "retry",
                                label: "retry",
                                accessibilityIdentifier: "mind-verdict-retry"
                            ),
                        ],
                        variant: .mindFeedback,
                        onSelect: { _ in onRetry() }
                    )
                    .accessibilityLabel("retry verdict")
                    .accessibilityHint(errorText)
                }
            }

        }
    }

    private var buttonsDisabled: Bool {
        pendingVerdict != nil || state.disablesAction
    }
}

private struct MindVerdictControlButton: View {
    let output: MindOutput
    let verdict: MindVerdict
    let isPending: Bool
    let isDisabled: Bool
    let state: KPrimitiveInteractionState
    let action: () -> Void

    private var variant: KOptionButtonVariant {
        switch verdict {
        case .actOn: return .primaryFilled
        case .nod: return .secondaryHairline
        case .junk: return .archiveNaked
        }
    }

    var body: some View {
        KOptionButton(
            label: verdict.rawValue,
            variant: variant,
            isEnabled: !isDisabled || isPending,
            isPending: isPending,
            state: isPending ? .loading : state,
            accessibilityIdentifier: "mind-verdict-\(verdict.rawValue)",
            onSelect: action
        )
        .frame(maxWidth: .infinity, minHeight: KStyle.verdictButtonHeight)
        .accessibilityLabel(MindVerdictAccessibility.controlLabel(for: verdict))
        .accessibilityHint(MindVerdictAccessibility.controlHint(for: verdict, output: output))
        .accessibilityAddTraits(isPending ? .isSelected : AccessibilityTraits())
    }
}

private struct MindDetailsView: View {
    let output: MindOutput
    let showsOptions: Bool
    let linksDisclosureEntities: Bool
    let onOpenEntity: (EntityRef) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let signalExplained = output.signalExplained {
                detailText("signal", signalExplained)
            }
            if let contrast = output.contrast {
                detailText("contrast", contrast)
            }
            if let observation = output.observation {
                detailText("observation", observation)
            }
            if let nextAction = output.nextAction {
                detailText("consider", nextAction)
            }
            if showsOptions, !output.options.isEmpty {
                detailOptions(output.options)
            }
            evidenceDetailList
            detailList("siblings", values: output.siblings, emptyText: "no sibling refs")
            if !output.considerations.isEmpty {
                detailList("considerations", values: output.considerations, emptyText: "")
            }
            if let stakes = output.stakes {
                detailText("stakes", stakes)
            }
        }
    }

    private func detailText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            KMonoCaption(label, variant: .metadata, state: .disabled)
            if linksDisclosureEntities {
                EntityLinkedText(
                    value,
                    refs: output.entityRefs,
                    fontToken: .content,
                    opacity: KStyle.secondaryTextOpacity,
                    onOpen: onOpenEntity
                )
            } else {
                Text(value)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .textSelection(.enabled)
            }
        }
    }

    private func detailList(_ label: String, values: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KMonoCaption(label, variant: .metadata, state: .disabled)
            if values.isEmpty {
                if !emptyText.isEmpty {
                    KMonoCaption(emptyText, variant: .metadata)
                }
            } else {
                if linksDisclosureEntities {
                    ForEach(values, id: \.self) { value in
                        EntityLinkedText(
                            value,
                            refs: output.entityRefs,
                            fontToken: .monoCaption,
                            opacity: KStyle.secondaryTextOpacity,
                            onOpen: onOpenEntity
                        )
                    }
                } else {
                    KEvidenceBlock(text: values.joined(separator: "\n"), variant: .mono)
                }
            }
        }
    }

    private var evidenceDetailList: some View {
        let lines = MindEvidenceDetailFormatter.lines(
            previews: output.evidencePreviews,
            evidence: output.evidence
        )
        return VStack(alignment: .leading, spacing: 4) {
            KMonoCaption("evidence", variant: .metadata, state: .disabled)
            if lines.isEmpty {
                KMonoCaption("no evidence", variant: .metadata)
            } else {
                if linksDisclosureEntities {
                    ForEach(lines, id: \.self) { line in
                        EntityLinkedText(
                            line,
                            refs: output.entityRefs,
                            fontToken: .monoCaption,
                            opacity: KStyle.tertiaryTextOpacity,
                            onOpen: onOpenEntity
                        )
                    }
                } else {
                    ForEach(lines, id: \.self) { line in
                        KMonoCaption(line, variant: .metadata)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func detailOptions(_ options: [BuildCardOption]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            KMonoCaption("options", variant: .metadata, state: .disabled)
            ForEach(options, id: \.id) { option in
                VStack(alignment: .leading, spacing: 2) {
                    if linksDisclosureEntities {
                        EntityLinkedText(
                            option.label.lowercased(),
                            refs: output.entityRefs,
                            fontToken: .content,
                            opacity: KStyle.secondaryTextOpacity,
                            onOpen: onOpenEntity
                        )
                    } else {
                        Text(option.label.lowercased())
                            .font(KStyle.contentFont)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if !option.consequence.isEmpty {
                        if linksDisclosureEntities {
                            EntityLinkedText(
                                option.consequence,
                                refs: output.entityRefs,
                                fontToken: .monoCaption,
                                opacity: KStyle.tertiaryTextOpacity,
                                onOpen: onOpenEntity
                            )
                        } else {
                            KMonoCaption(option.consequence, variant: .metadata)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

private struct MindNudgeFeedbackRow: View {
    let selection: MindNudgeFeedback?
    let onSelect: (MindNudgeFeedback) -> Void

    var body: some View {
        KActRow(
            actions: MindNudgeFeedback.allCases.map { feedback in
                KActItem(
                    id: feedback.rawValue,
                    label: feedback.label,
                    accessibilityIdentifier: "mind-nudge-feedback-\(feedback.rawValue)"
                )
            },
            variant: .mindFeedback,
            selectedActionIDs: selection.map { Set([$0.rawValue]) } ?? [],
            onSelect: { item in
                if let feedback = MindNudgeFeedback(rawValue: item.id) {
                    onSelect(feedback)
                }
            }
        )
    }
}

private struct MindErrorRow: View {
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
    }
}

private struct MindCompleteView: View {
    let canUndo: Bool
    let loadErrorText: String?
    let onUndo: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("all visible mind outputs judged")
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                Spacer(minLength: 8)
                if canUndo {
                    KActRow(
                        actions: [KActItem(id: "undo")],
                        variant: .admin,
                        onSelect: { _ in onUndo() }
                    )
                }
            }
            if let loadErrorText {
                MindErrorRow(text: loadErrorText, onRetry: onRetry)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
