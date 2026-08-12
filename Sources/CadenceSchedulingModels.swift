import Foundation
import SwiftUI
import UIKit
enum CadenceRing: String, Codable, CaseIterable, Sendable {
    case core
    case middle
    case outer
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = CadenceRing(rawValue: raw ?? "") ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var signalColor: Color {
        color
    }

    var color: Color {
        colorToken.color
    }

    var colorHex: String {
        colorToken.hex
    }

    var colorToken: KRGBToken {
        switch self {
        case .core:
            return KStyle.ringCoreToken
        case .middle:
            return KStyle.ringMiddleToken
        case .outer:
            return KStyle.ringOuterToken
        case .unknown:
            return KStyle.ringUnknownToken
        }
    }

    var kSignal: KSignal {
        switch self {
        case .core:
            return .live
        case .middle:
            return .attention
        case .outer, .unknown:
            return .idle
        }
    }
}

enum CadenceBlockAction: String, Codable, Equatable, Sendable {
    case start
    case pause
    case complete
    case skip
    case extend15 = "extend_15"
    case twsYes = "tws_yes"
    case twsNo = "tws_no"
    case wakeInit = "wake_init"

    var label: String {
        switch self {
        case .start:
            return "start"
        case .pause:
            return "pause"
        case .complete:
            return "complete"
        case .skip:
            return "skip"
        case .extend15:
            return "+15"
        case .twsYes:
            return "y"
        case .twsNo:
            return "n"
        case .wakeInit:
            return "start"
        }
    }
}

extension CadenceBlockAction {
    static func serverValue(_ text: String?) -> CadenceBlockAction? {
        let value = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch value {
        case "start", "started", "begin", "resume", "resumed":
            return .start
        case "pause", "paused":
            return .pause
        case "complete", "completed", "done":
            return .complete
        case "skip", "skipped":
            return .skip
        case "extend_15", "+15", "extend15", "extended":
            return .extend15
        case "tws_yes", "yes", "y", "well_spent":
            return .twsYes
        case "tws_no", "no", "n", "not_well_spent":
            return .twsNo
        case "wake_init", "wake", "day_start", "day_starts_now", "day_start_now":
            return .wakeInit
        default:
            return nil
        }
    }
}

enum CadenceBlockLifecycleState: String, Codable, Equatable, Sendable {
    case available
    case started
    case completed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch raw {
        case "available":
            self = .available
        case "started", "active", "running":
            self = .started
        case "completed", "complete", "done":
            self = .completed
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid cadence lifecycle state"
            )
        }
    }
}

enum CadenceRecalibrationChangeType: String, Codable, Equatable, Sendable {
    case shift
    case compress
    case merge
    case skip
    case protect
}

struct CadenceRecalibrationChange: Codable, Equatable, Sendable {
    var type: CadenceRecalibrationChangeType?
    var blockId: String?
    var deltaMinutes: Int?
    var originalStart: String?
    var newStart: String?
    var originalEnd: String?
    var newEnd: String?
    var fromStartAt: String?
    var toStartAt: String?
    var fromEndAt: String?
    var toEndAt: String?
    var mergedIntoBlockId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case blockId
        case blockID
        case deltaMinutes
        case originalStart
        case newStart
        case originalEnd
        case newEnd
        case fromStartAt
        case toStartAt
        case fromEndAt
        case toEndAt
        case mergedIntoBlockId
    }

    init(
        type: CadenceRecalibrationChangeType? = nil,
        blockId: String? = nil,
        deltaMinutes: Int? = nil,
        originalStart: String? = nil,
        newStart: String? = nil,
        originalEnd: String? = nil,
        newEnd: String? = nil,
        fromStartAt: String? = nil,
        toStartAt: String? = nil,
        fromEndAt: String? = nil,
        toEndAt: String? = nil,
        mergedIntoBlockId: String? = nil
    ) {
        self.type = type
        self.blockId = blockId
        self.deltaMinutes = deltaMinutes
        self.originalStart = originalStart
        self.newStart = newStart
        self.originalEnd = originalEnd
        self.newEnd = newEnd
        self.fromStartAt = fromStartAt
        self.toStartAt = toStartAt
        self.fromEndAt = fromEndAt
        self.toEndAt = toEndAt
        self.mergedIntoBlockId = mergedIntoBlockId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(CadenceRecalibrationChangeType.self, forKey: .type)
        blockId = try container.decodeTrimmedString(for: .blockId)
            ?? container.decodeTrimmedString(for: .blockID)
        deltaMinutes = try container.decodeFlexibleInt(for: .deltaMinutes)
        originalStart = try container.decodeTrimmedString(for: .originalStart)
        newStart = try container.decodeTrimmedString(for: .newStart)
        originalEnd = try container.decodeTrimmedString(for: .originalEnd)
        newEnd = try container.decodeTrimmedString(for: .newEnd)
        fromStartAt = try container.decodeTrimmedString(for: .fromStartAt)
        toStartAt = try container.decodeTrimmedString(for: .toStartAt)
        fromEndAt = try container.decodeTrimmedString(for: .fromEndAt)
        toEndAt = try container.decodeTrimmedString(for: .toEndAt)
        mergedIntoBlockId = try container.decodeTrimmedString(for: .mergedIntoBlockId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(blockId, forKey: .blockId)
        try container.encodeIfPresent(deltaMinutes, forKey: .deltaMinutes)
        try container.encodeIfPresent(originalStart, forKey: .originalStart)
        try container.encodeIfPresent(newStart, forKey: .newStart)
        try container.encodeIfPresent(originalEnd, forKey: .originalEnd)
        try container.encodeIfPresent(newEnd, forKey: .newEnd)
        try container.encodeIfPresent(fromStartAt, forKey: .fromStartAt)
        try container.encodeIfPresent(toStartAt, forKey: .toStartAt)
        try container.encodeIfPresent(fromEndAt, forKey: .fromEndAt)
        try container.encodeIfPresent(toEndAt, forKey: .toEndAt)
        try container.encodeIfPresent(mergedIntoBlockId, forKey: .mergedIntoBlockId)
    }

    var displayFromStart: String? {
        fromStartAt ?? originalStart
    }

    var displayToStart: String? {
        toStartAt ?? newStart
    }
}

struct CadenceRecalibrationSummary: Codable, Equatable, Sendable {
    var reason: String?
    var anchorAt: String?
    var changes: [CadenceRecalibrationChange]

    enum CodingKeys: String, CodingKey {
        case reason
        case anchorAt
        case changes
    }

    init(reason: String? = nil, anchorAt: String? = nil, changes: [CadenceRecalibrationChange] = []) {
        self.reason = reason
        self.anchorAt = anchorAt
        self.changes = changes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try container.decodeTrimmedString(for: .reason)?.lowercased()
        anchorAt = try container.decodeTrimmedString(for: .anchorAt)
        changes = (try? container.decode(LossyCadenceArray<CadenceRecalibrationChange>.self, forKey: .changes).elements) ?? []
    }
}

enum CadenceNudgeDisposition: String, Codable, Equatable, Sendable {
    case act
    case watch
    case suppress
}

struct CadenceNudge: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String?
    var body: String?
    var mode: String?
    var blockId: String?
    var rank: Int?
    var status: String?
    var source: String?
    var category: String?
    var cardId: String?
    var optionId: String?
    var what: String?
    var contrast: String?
    var stakes: String?
    var evidenceSummary: DecisionEvidenceSummary?
    var signalExplained: String?
    var brief: DecisionBrief?
    var buildCard: CadenceNudgeBuildCard?
    var act: CadenceNudgeActDescriptor?

    enum CodingKeys: String, CodingKey {
        case id
        case nudgeId
        case kind
        case title
        case text
        case body
        case description
        case caption
        case mode
        case blockId
        case blockID
        case rank
        case priority
        case status
        case state
        case source
        case category
        case cardId
        case optionId
        case what
        case contrast
        case stakes
        case evidenceSummary
        case signalExplained
        case brief
        case decisionBrief
        case payload
        case buildCard
        case act
    }

    init(
        id: String,
        title: String? = nil,
        body: String? = nil,
        mode: String? = nil,
        blockId: String? = nil,
        rank: Int? = nil,
        status: String? = nil,
        source: String? = nil,
        category: String? = nil,
        cardId: String? = nil,
        optionId: String? = nil,
        what: String? = nil,
        contrast: String? = nil,
        stakes: String? = nil,
        evidenceSummary: DecisionEvidenceSummary? = nil,
        signalExplained: String? = nil,
        brief: DecisionBrief? = nil,
        buildCard: CadenceNudgeBuildCard? = nil,
        act: CadenceNudgeActDescriptor? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.mode = mode
        self.blockId = blockId
        self.rank = rank
        self.status = status
        self.source = source
        self.category = category
        self.cardId = cardId
        self.optionId = optionId
        self.what = Self.normalized(what)
        self.contrast = Self.normalized(contrast)
        self.stakes = Self.normalized(stakes)
        self.evidenceSummary = evidenceSummary?.isEmpty == false ? evidenceSummary : nil
        self.signalExplained = Self.normalized(signalExplained)
        self.brief = brief?.isEmpty == false ? brief : nil
        self.buildCard = buildCard
        self.act = act
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .nudgeId)
            ?? "nudge-\(UUID().uuidString)"
        title = try container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .text)
        body = try container.decodeTrimmedString(for: .body)
            ?? container.decodeTrimmedString(for: .description)
            ?? container.decodeTrimmedString(for: .caption)
        mode = try container.decodeTrimmedString(for: .mode)
        blockId = try container.decodeTrimmedString(for: .blockId)
            ?? container.decodeTrimmedString(for: .blockID)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
            ?? container.decodeIfPresent(Int.self, forKey: .priority)
        status = try container.decodeTrimmedString(for: .status)
            ?? container.decodeTrimmedString(for: .state)
        source = try container.decodeTrimmedString(for: .source)
        category = try container.decodeTrimmedString(for: .category)
            ?? container.decodeTrimmedString(for: .kind)
        cardId = try container.decodeTrimmedString(for: .cardId)
        optionId = try container.decodeTrimmedString(for: .optionId)
        what = Self.decodeString(from: container, for: .what)
        contrast = Self.decodeString(from: container, for: .contrast)
        stakes = Self.decodeString(from: container, for: .stakes)
        let decodedEvidenceSummary = try? container.decode(DecisionEvidenceSummary.self, forKey: .evidenceSummary)
        evidenceSummary = decodedEvidenceSummary?.isEmpty == false ? decodedEvidenceSummary : nil
        let payload = try? container.decode([String: ViewPacketJSONValue].self, forKey: .payload)
        signalExplained = Self.decodeString(from: container, for: .signalExplained)
            ?? Self.string(in: payload, keys: ["signalExplained", "signal_explained"])
        let decodedBrief = (try? container.decodeIfPresent(DecisionBrief.self, forKey: .brief))
            ?? (try? container.decodeIfPresent(DecisionBrief.self, forKey: .decisionBrief))
            ?? DecisionBrief.first(in: payload)
        brief = decodedBrief?.isEmpty == false ? decodedBrief : nil
        buildCard = try? container.decodeIfPresent(CadenceNudgeBuildCard.self, forKey: .buildCard)
        act = try? container.decodeIfPresent(CadenceNudgeActDescriptor.self, forKey: .act)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(blockId, forKey: .blockId)
        try container.encodeIfPresent(rank, forKey: .rank)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(cardId, forKey: .cardId)
        try container.encodeIfPresent(optionId, forKey: .optionId)
        try container.encodeIfPresent(what, forKey: .what)
        try container.encodeIfPresent(contrast, forKey: .contrast)
        try container.encodeIfPresent(stakes, forKey: .stakes)
        try container.encodeIfPresent(evidenceSummary, forKey: .evidenceSummary)
        try container.encodeIfPresent(signalExplained, forKey: .signalExplained)
        try container.encodeIfPresent(brief, forKey: .brief)
        try container.encodeIfPresent(buildCard, forKey: .buildCard)
        try container.encodeIfPresent(act, forKey: .act)
    }

    var isResolved: Bool {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["acted", "act", "watched", "watch", "suppressed", "dismissed", "closed"].contains(value)
    }

    var buildCardIdFromNudge: String? {
        Self.normalized(cardId) ?? Self.normalized(act?.body["cardId"]?.stringValue)
    }

    var recommendedOptionIdFromNudge: String? {
        Self.normalized(optionId) ?? Self.normalized(act?.body["optionId"]?.stringValue)
    }

    var recommendedOptionLabel: String? {
        guard let optionID = recommendedOptionIdFromNudge else { return nil }
        return buildCard?.options.first { $0.id == optionID }?.label ?? optionID
    }

    var recommendedBuildOption: BuildCardOption? {
        guard let optionID = recommendedOptionIdFromNudge else { return nil }
        return buildCard?.options.first { $0.id == optionID } ?? BuildCardOption(id: optionID, label: optionID)
    }

    var decisionBrief: DecisionBrief? {
        brief ?? buildCard?.brief
    }

    var decisionWhat: String? {
        Self.normalized(what) ?? buildCard?.what
    }

    var decisionContrast: String? {
        Self.normalized(contrast) ?? buildCard?.contrast
    }

    var decisionStakes: String? {
        decisionBrief?.stakes ?? Self.normalized(stakes) ?? buildCard?.stakes
    }

    var decisionEvidenceSummary: DecisionEvidenceSummary? {
        evidenceSummary ?? buildCard?.evidenceSummary
    }

    var decisionSignalExplained: String? {
        Self.normalized(signalExplained) ?? buildCard?.signalExplained
    }

    var isBuildCardNudge: Bool {
        [source, category].contains { Self.normalized($0) == "build-card" } || buildCardIdFromNudge != nil
    }

    var isBuildCardActable: Bool {
        isBuildCardNudge && act != nil && buildCardIdFromNudge != nil && recommendedOptionIdFromNudge != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        for key: CodingKeys
    ) -> String? {
        normalized(try? container.decode(String.self, forKey: key))
    }

    private static func string(in object: [String: ViewPacketJSONValue]?, keys: [String]) -> String? {
        guard let object else { return nil }
        for key in keys {
            guard let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }
}

struct CadenceNudgeBuildCard: Codable, Equatable, Sendable {
    var id: String?
    var optionId: String?
    var what: String?
    var contrast: String?
    var stakes: String?
    var evidenceSummary: DecisionEvidenceSummary?
    var signalExplained: String?
    var brief: DecisionBrief?
    var options: [BuildCardOption]

    init(
        id: String? = nil,
        optionId: String? = nil,
        what: String? = nil,
        contrast: String? = nil,
        stakes: String? = nil,
        evidenceSummary: DecisionEvidenceSummary? = nil,
        signalExplained: String? = nil,
        brief: DecisionBrief? = nil,
        options: [BuildCardOption] = []
    ) {
        self.id = id
        self.optionId = optionId
        self.what = Self.normalized(what)
        self.contrast = Self.normalized(contrast)
        self.stakes = Self.normalized(stakes)
        self.evidenceSummary = evidenceSummary?.isEmpty == false ? evidenceSummary : nil
        self.signalExplained = Self.normalized(signalExplained)
        self.brief = brief?.isEmpty == false ? brief : nil
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case id
        case optionId
        case what
        case contrast
        case stakes
        case evidenceSummary
        case signalExplained
        case brief
        case decisionBrief
        case payload
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id)
        optionId = try container.decodeTrimmedString(for: .optionId)
        what = Self.decodeString(from: container, for: .what)
        contrast = Self.decodeString(from: container, for: .contrast)
        stakes = Self.decodeString(from: container, for: .stakes)
        let decodedEvidenceSummary = try? container.decode(DecisionEvidenceSummary.self, forKey: .evidenceSummary)
        evidenceSummary = decodedEvidenceSummary?.isEmpty == false ? decodedEvidenceSummary : nil
        let payload = try? container.decode([String: ViewPacketJSONValue].self, forKey: .payload)
        signalExplained = Self.decodeString(from: container, for: .signalExplained)
            ?? Self.string(in: payload, keys: ["signalExplained", "signal_explained"])
        let decodedBrief = (try? container.decodeIfPresent(DecisionBrief.self, forKey: .brief))
            ?? (try? container.decodeIfPresent(DecisionBrief.self, forKey: .decisionBrief))
            ?? DecisionBrief.first(in: payload)
        brief = decodedBrief?.isEmpty == false ? decodedBrief : nil
        options = (try? container.decode(LossyCadenceArray<BuildCardOption>.self, forKey: .options).elements) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(optionId, forKey: .optionId)
        try container.encodeIfPresent(what, forKey: .what)
        try container.encodeIfPresent(contrast, forKey: .contrast)
        try container.encodeIfPresent(stakes, forKey: .stakes)
        try container.encodeIfPresent(evidenceSummary, forKey: .evidenceSummary)
        try container.encodeIfPresent(signalExplained, forKey: .signalExplained)
        try container.encodeIfPresent(brief, forKey: .brief)
        try container.encode(options, forKey: .options)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        for key: CodingKeys
    ) -> String? {
        normalized(try? container.decode(String.self, forKey: key))
    }

    private static func string(in object: [String: ViewPacketJSONValue]?, keys: [String]) -> String? {
        guard let object else { return nil }
        for key in keys {
            guard let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }
}

struct CadenceNudgeActDescriptor: Codable, Equatable, Sendable {
    var type: String?
    var method: String
    var path: String
    var body: [String: ViewPacketJSONValue]

    init(
        type: String? = nil,
        method: String = "POST",
        path: String,
        body: [String: ViewPacketJSONValue] = [:]
    ) {
        self.type = type
        self.method = method
        self.path = path
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case type
        case method
        case path
        case body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeTrimmedString(for: .type)
        method = try container.decodeTrimmedString(for: .method) ?? "POST"
        path = try container.decodeTrimmedString(for: .path) ?? ""
        body = (try? container.decode([String: ViewPacketJSONValue].self, forKey: .body)) ?? [:]
    }
}

struct CadenceChecklistItem: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var done: Bool
    var timeSensitive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case itemId
        case title
        case text
        case label
        case done
        case completed
        case checked
        case timeSensitive
        case dueToday
    }

    init(id: String, title: String, done: Bool = false, timeSensitive: Bool = false) {
        self.id = id
        self.title = title.lowercased()
        self.done = done
        self.timeSensitive = timeSensitive
    }

    init(_ item: ChecklistItem) {
        self.init(id: item.id, title: item.text, done: item.isDone)
    }

    init(_ subtask: Subtask) {
        self.init(
            id: subtask.id,
            title: subtask.text,
            done: subtask.done,
            timeSensitive: subtask.timeSensitive
        )
    }

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            let decodedTitle = string.trimmingCharacters(in: .whitespacesAndNewlines)
            title = decodedTitle.isEmpty ? "check" : decodedTitle.lowercased()
            id = CadenceChecklistItem.generatedID(title: title)
            done = false
            timeSensitive = false
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .label)
            ?? "check"
        id = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .itemId)
            ?? CadenceChecklistItem.generatedID(title: decodedTitle)
        title = decodedTitle.lowercased()
        done = try container.decodeFlexibleBool(for: .done)
            ?? container.decodeFlexibleBool(for: .completed)
            ?? container.decodeFlexibleBool(for: .checked)
            ?? false
        timeSensitive = try container.decodeFlexibleBool(for: .timeSensitive)
            ?? container.decodeFlexibleBool(for: .dueToday)
            ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(done, forKey: .done)
        try container.encode(timeSensitive, forKey: .timeSensitive)
    }

    var subtask: Subtask {
        Subtask(id: id, text: title, timeSensitive: timeSensitive, done: done)
    }

    var rowTitle: String {
        timeSensitive ? "\(title) · due today" : title
    }

    private static func generatedID(title: String) -> String {
        let sanitized = title
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let value = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "check-\(UUID().uuidString)" : value
    }
}


