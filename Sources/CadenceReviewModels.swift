import Foundation
import SwiftUI
import UIKit
struct CadenceReviewSection: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String?
    var body: String?
    var items: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case title
        case label
        case body
        case text
        case prompt
        case value
        case items
        case lines
    }

    init(id: String, title: String? = nil, body: String? = nil, items: [String] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .key)
            ?? "section-\(UUID().uuidString)"
        title = try container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .label)
        body = try container.decodeTrimmedString(for: .body)
            ?? container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .prompt)
            ?? container.decodeTrimmedString(for: .value)
        items = try container.decodeStringArray(for: .items)
            ?? container.decodeStringArray(for: .lines)
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(items, forKey: .items)
    }
}

/// The value trail is an additive projection. Older daemons only send the
/// value-probe shape below; absent trails stay absent and the probe still uses
/// the same answer endpoint. (doctrine: silence-default, staleness-honesty)
enum CadenceValueActImpact: String, Codable, Equatable, Sendable {
    case fed
    case cost

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cost", "costed", "negative", "slip", "slipped", "attention":
            self = .cost
        default:
            self = .fed
        }
    }
}

struct CadenceValueAct: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var dateText: String
    var text: String
    var impact: CadenceValueActImpact

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case dateText
        case when
        case occurredAt
        case eventAt
        case timestamp
        case text
        case what
        case act
        case label
        case impact
        case relation
        case effect
        case fed
        case cost
    }

    init(
        id: String,
        dateText: String,
        text: String,
        impact: CadenceValueActImpact = .fed
    ) {
        self.id = id
        self.dateText = dateText
        self.text = text
        self.impact = impact
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id) ?? "value-act-\(UUID().uuidString)"
        dateText = try container.decodeTrimmedString(for: .dateText)
            ?? container.decodeTrimmedString(for: .date)
            ?? container.decodeTrimmedString(for: .when)
            ?? container.decodeTrimmedString(for: .occurredAt)
            ?? container.decodeTrimmedString(for: .eventAt)
            ?? container.decodeTrimmedString(for: .timestamp)
            ?? ""
        text = try container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .what)
            ?? container.decodeTrimmedString(for: .act)
            ?? container.decodeTrimmedString(for: .label)
            ?? ""

        if let impactText = try container.decodeTrimmedString(for: .impact)
            ?? container.decodeTrimmedString(for: .relation)
            ?? container.decodeTrimmedString(for: .effect) {
            impact = CadenceValueActImpact(rawValue: impactText)
        } else if (try? container.decodeFlexibleBool(for: .cost)) == true {
            impact = .cost
        } else if (try? container.decodeFlexibleBool(for: .fed)) == false {
            impact = .cost
        } else {
            impact = .fed
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dateText, forKey: .dateText)
        try container.encode(text, forKey: .text)
        try container.encode(impact, forKey: .impact)
    }
}

struct CadenceValue: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var signal: CadenceValueSignal
    var streakDays: Int?
    var attentionCount: Int?
    var attentionText: String?
    var lastActText: String?
    var lastActDateText: String?
    var acts: [CadenceValueAct]
    var moreCount: Int
    var moreLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case valueId
        case valueID
        case name
        case label
        case title
        case signal
        case state
        case status
        case streakDays
        case streak
        case heldDays
        case attentionCount
        case attention
        case skippedCount
        case attentionText
        case attentionReason
        case reason
        case last
        case lastAct
        case lastActText
        case lastActDateText
        case lastAt
        case acts
        case trail
        case entries
        case moreCount
        case remainingCount
        case moreLabel
    }

    init(
        id: String,
        name: String,
        signal: CadenceValueSignal = .none,
        streakDays: Int? = nil,
        attentionCount: Int? = nil,
        attentionText: String? = nil,
        lastActText: String? = nil,
        lastActDateText: String? = nil,
        acts: [CadenceValueAct] = [],
        moreCount: Int = 0,
        moreLabel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.signal = signal
        self.streakDays = streakDays
        self.attentionCount = attentionCount
        self.attentionText = attentionText
        self.lastActText = lastActText
        self.lastActDateText = lastActDateText
        self.acts = acts
        self.moreCount = max(0, moreCount)
        self.moreLabel = moreLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .valueId)
            ?? container.decodeTrimmedString(for: .valueID)
            ?? "value-\(UUID().uuidString)"
        name = try container.decodeTrimmedString(for: .name)
            ?? container.decodeTrimmedString(for: .label)
            ?? container.decodeTrimmedString(for: .title)
            ?? id

        let rawSignal = try container.decodeTrimmedString(for: .signal)
            ?? container.decodeTrimmedString(for: .state)
            ?? container.decodeTrimmedString(for: .status)
        let decodedActs = Self.decodeActs(from: container)
        let decodedAttentionCount = try container.decodeFlexibleInt(for: .attentionCount)
            ?? container.decodeFlexibleInt(for: .attention)
            ?? container.decodeFlexibleInt(for: .skippedCount)
        signal = CadenceValueSignal(rawValue: rawSignal ?? "")
            ?? (decodedAttentionCount.map { $0 > 0 } == true ? .attention : (decodedActs.isEmpty ? .none : .held))
        streakDays = try container.decodeFlexibleInt(for: .streakDays)
            ?? container.decodeFlexibleInt(for: .streak)
            ?? container.decodeFlexibleInt(for: .heldDays)
        attentionCount = decodedAttentionCount
        attentionText = try container.decodeTrimmedString(for: .attentionText)
            ?? container.decodeTrimmedString(for: .attentionReason)
            ?? container.decodeTrimmedString(for: .reason)
        lastActText = try container.decodeTrimmedString(for: .lastActText)
            ?? container.decodeTrimmedString(for: .last)
            ?? container.decodeTrimmedString(for: .lastAct)
            ?? decodedActs.first?.text
        lastActDateText = try container.decodeTrimmedString(for: .lastActDateText)
            ?? container.decodeTrimmedString(for: .lastAt)
            ?? decodedActs.first?.dateText
        acts = decodedActs
        moreCount = max(0, (try container.decodeFlexibleInt(for: .moreCount)
            ?? container.decodeFlexibleInt(for: .remainingCount)
            ?? 0))
        moreLabel = try container.decodeTrimmedString(for: .moreLabel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(signal, forKey: .signal)
        try container.encodeIfPresent(streakDays, forKey: .streakDays)
        try container.encodeIfPresent(attentionCount, forKey: .attentionCount)
        try container.encodeIfPresent(attentionText, forKey: .attentionText)
        try container.encodeIfPresent(lastActText, forKey: .lastActText)
        try container.encodeIfPresent(lastActDateText, forKey: .lastActDateText)
        try container.encode(acts, forKey: .acts)
        try container.encode(moreCount, forKey: .moreCount)
        try container.encodeIfPresent(moreLabel, forKey: .moreLabel)
    }

    var hasActs: Bool {
        !acts.isEmpty || lastActText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var effectiveSignal: CadenceValueSignal {
        if signal != .none { return signal }
        return hasActs ? .held : .none
    }

    var lastLine: String? {
        let text = (lastActText?.isEmpty == false ? lastActText : acts.first?.text)
        guard let text, !text.isEmpty else { return nil }
        let date = (lastActDateText ?? acts.first?.dateText)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date, !date.isEmpty {
            return "last: \(text) · \(date)"
        }
        return "last: \(text)"
    }

    private static func decodeActs(from container: KeyedDecodingContainer<CodingKeys>) -> [CadenceValueAct] {
        for key in [CodingKeys.acts, .trail, .entries] {
            if let values = try? container.decode(LossyCadenceArray<CadenceValueAct>.self, forKey: key).elements {
                return values
            }
        }
        return []
    }
}

enum CadenceValueSignal: String, Codable, Equatable, Sendable {
    case held
    case attention
    case none

    init?(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "held", "hold", "on-target", "on_target", "ontarget", "green", "live":
            self = .held
        case "attention", "attn", "slipping", "slip", "warn", "amber":
            self = .attention
        case "none", "empty", "no-acts", "no_acts", "silent", "dim", "idle":
            self = .none
        default:
            return nil
        }
    }
}

struct CadenceValuesCard: Codable, Equatable, Sendable {
    var summary: String?
    var attentionValueID: String?
    var initialExpandedValueID: String?
    var values: [CadenceValue]

    enum CodingKeys: String, CodingKey {
        case summary
        case header
        case subline
        case attentionValueID
        case attentionValueId
        case attentionValue
        case initialExpandedValueID
        case initialExpandedValueId
        case expandedValueID
        case expandedValueId
        case values
        case items
        case rows
        case signals
    }

    init(
        summary: String? = nil,
        attentionValueID: String? = nil,
        initialExpandedValueID: String? = nil,
        values: [CadenceValue] = []
    ) {
        self.summary = summary
        self.attentionValueID = attentionValueID
        self.initialExpandedValueID = initialExpandedValueID
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeTrimmedString(for: .summary)
            ?? container.decodeTrimmedString(for: .header)
            ?? container.decodeTrimmedString(for: .subline)
        attentionValueID = try container.decodeTrimmedString(for: .attentionValueID)
            ?? container.decodeTrimmedString(for: .attentionValueId)
            ?? container.decodeTrimmedString(for: .attentionValue)
        initialExpandedValueID = try container.decodeTrimmedString(for: .initialExpandedValueID)
            ?? container.decodeTrimmedString(for: .initialExpandedValueId)
            ?? container.decodeTrimmedString(for: .expandedValueID)
            ?? container.decodeTrimmedString(for: .expandedValueId)
        values = Self.decodeValues(from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(attentionValueID, forKey: .attentionValueID)
        try container.encodeIfPresent(initialExpandedValueID, forKey: .initialExpandedValueID)
        try container.encode(values, forKey: .values)
    }

    private static func decodeValues(from container: KeyedDecodingContainer<CodingKeys>) -> [CadenceValue] {
        for key in [CodingKeys.values, .items, .rows, .signals] {
            if let values = try? container.decode(LossyCadenceArray<CadenceValue>.self, forKey: key).elements {
                return values
            }
        }
        return []
    }
}

struct CadenceValueProbeReview: Codable, Equatable, Sendable {
    var weekStart: String?
    var weekEnd: String?
    var maxProbes: Int?
    var count: Int
    var answeredCount: Int
    var probes: [CadenceValueProbe]
    var answerAction: CadenceValueProbeAnswerAction?
    var values: CadenceValuesCard?

    enum CodingKeys: String, CodingKey {
        case weekStart
        case weekEnd
        case maxProbes
        case count
        case answeredCount
        case probes
        case answerAction
        case values
        case valueCard
        case valueSignals
    }

    init(
        weekStart: String? = nil,
        weekEnd: String? = nil,
        maxProbes: Int? = nil,
        count: Int? = nil,
        answeredCount: Int = 0,
        probes: [CadenceValueProbe] = [],
        answerAction: CadenceValueProbeAnswerAction? = nil,
        values: CadenceValuesCard? = nil
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.maxProbes = maxProbes
        self.count = count ?? probes.count
        self.answeredCount = answeredCount
        self.probes = probes
        self.answerAction = answerAction
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decodeTrimmedString(for: .weekStart)
        weekEnd = try container.decodeTrimmedString(for: .weekEnd)
        maxProbes = try container.decodeFlexibleInt(for: .maxProbes)
        probes = (try? container.decode(LossyCadenceArray<CadenceValueProbe>.self, forKey: .probes).elements) ?? []
        count = try container.decodeFlexibleInt(for: .count) ?? probes.count
        answeredCount = try container.decodeFlexibleInt(for: .answeredCount) ?? 0
        answerAction = try? container.decodeIfPresent(CadenceValueProbeAnswerAction.self, forKey: .answerAction)
        values = (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .values))
            ?? (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .valueCard))
            ?? (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .valueSignals))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(weekStart, forKey: .weekStart)
        try container.encodeIfPresent(weekEnd, forKey: .weekEnd)
        try container.encodeIfPresent(maxProbes, forKey: .maxProbes)
        try container.encode(count, forKey: .count)
        try container.encode(answeredCount, forKey: .answeredCount)
        try container.encode(probes, forKey: .probes)
        try container.encodeIfPresent(answerAction, forKey: .answerAction)
        try container.encodeIfPresent(values, forKey: .values)
    }
}

struct CadenceValueProbe: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var ordinal: Int
    var axis: String?
    var prompt: String?
    var question: String
    var shape: String?
    var forcedChoice: Bool
    var options: [CadenceValueProbeOption]
    var sourceEvidence: [ViewPacketJSONValue]
    var answer: CadenceValueProbeAnswerAnchor?
    var valueID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ordinal
        case axis
        case prompt
        case question
        case shape
        case forcedChoice
        case options
        case sourceEvidence
        case answer
        case valueID
        case valueId
        case value
    }

    init(
        id: String,
        ordinal: Int,
        axis: String? = nil,
        prompt: String? = nil,
        question: String,
        shape: String? = nil,
        forcedChoice: Bool = true,
        options: [CadenceValueProbeOption] = [],
        sourceEvidence: [ViewPacketJSONValue] = [],
        answer: CadenceValueProbeAnswerAnchor? = nil,
        valueID: String? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.axis = axis
        self.prompt = prompt
        self.question = question
        self.shape = shape
        self.forcedChoice = forcedChoice
        self.options = options
        self.sourceEvidence = sourceEvidence
        self.answer = answer
        self.valueID = valueID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id) ?? "value-probe-\(UUID().uuidString)"
        ordinal = try container.decodeFlexibleInt(for: .ordinal) ?? 0
        axis = try container.decodeTrimmedString(for: .axis)
        prompt = try container.decodeTrimmedString(for: .prompt)
        question = try container.decodeTrimmedString(for: .question)
            ?? prompt
            ?? ""
        shape = try container.decodeTrimmedString(for: .shape)
        forcedChoice = try container.decodeFlexibleBool(for: .forcedChoice) ?? false
        options = (try? container.decode(LossyCadenceArray<CadenceValueProbeOption>.self, forKey: .options).elements) ?? []
        sourceEvidence = (try? container.decode([ViewPacketJSONValue].self, forKey: .sourceEvidence)) ?? []
        answer = try? container.decodeIfPresent(CadenceValueProbeAnswerAnchor.self, forKey: .answer)
        valueID = try container.decodeTrimmedString(for: .valueID)
            ?? container.decodeTrimmedString(for: .valueId)
            ?? container.decodeTrimmedString(for: .value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encodeIfPresent(axis, forKey: .axis)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encode(question, forKey: .question)
        try container.encodeIfPresent(shape, forKey: .shape)
        try container.encode(forcedChoice, forKey: .forcedChoice)
        try container.encode(options, forKey: .options)
        try container.encode(sourceEvidence, forKey: .sourceEvidence)
        try container.encodeIfPresent(answer, forKey: .answer)
        try container.encodeIfPresent(valueID, forKey: .valueID)
    }
}

struct CadenceValueProbeOption: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var value: String?
    var position: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case value
        case position
    }

    init(id: String, label: String? = nil, value: String? = nil, position: String? = nil) {
        self.id = id
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = normalizedLabel?.isEmpty == false ? normalizedLabel! : id
        self.value = value
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id) ?? "option-\(UUID().uuidString)"
        label = try container.decodeTrimmedString(for: .label)
            ?? container.decodeTrimmedString(for: .value)
            ?? id
        value = try container.decodeTrimmedString(for: .value)
        position = try container.decodeTrimmedString(for: .position)
    }
}

struct CadenceValueProbeAnswerAnchor: Codable, Equatable, Sendable {
    var anchorId: String?
    var selectedOptionId: String?
    var selectedLabel: String?
    var selectedValue: String?
    var recordedAt: String?

    enum CodingKeys: String, CodingKey {
        case anchorId
        case selectedOptionId
        case selectedLabel
        case selectedValue
        case recordedAt
    }

    init(
        anchorId: String? = nil,
        selectedOptionId: String? = nil,
        selectedLabel: String? = nil,
        selectedValue: String? = nil,
        recordedAt: String? = nil
    ) {
        self.anchorId = anchorId
        self.selectedOptionId = selectedOptionId
        self.selectedLabel = selectedLabel
        self.selectedValue = selectedValue
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchorId = try container.decodeTrimmedString(for: .anchorId)
        selectedOptionId = try container.decodeTrimmedString(for: .selectedOptionId)
        selectedLabel = try container.decodeTrimmedString(for: .selectedLabel)
        selectedValue = try container.decodeTrimmedString(for: .selectedValue)
        recordedAt = try container.decodeTrimmedString(for: .recordedAt)
    }
}

struct CadenceValueProbeAnswerAction: Codable, Equatable, Sendable {
    var type: String?
    var method: String
    var path: String
    var body: [String: ViewPacketJSONValue]

    enum CodingKeys: String, CodingKey {
        case type
        case method
        case path
        case body
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeTrimmedString(for: .type)
        method = try container.decodeTrimmedString(for: .method) ?? "POST"
        path = try container.decodeTrimmedString(for: .path) ?? ""
        body = (try? container.decode([String: ViewPacketJSONValue].self, forKey: .body)) ?? [:]
    }
}

enum CadenceValueProbeProgression {
    static func nextUnansweredOrdinal(
        in probes: [CadenceValueProbe],
        answeredProbeIDs: Set<String>
    ) -> Int? {
        probes
            .sorted { left, right in
                if left.ordinal == right.ordinal { return left.id < right.id }
                return left.ordinal < right.ordinal
            }
            .first { !answeredProbeIDs.contains($0.id) }?
            .ordinal
    }

    static func headerCountString(answeredProbeIDs: Set<String>, totalCount: Int) -> String {
        headerCountString(answeredCount: answeredProbeIDs.count, totalCount: totalCount)
    }

    static func headerCountString(answeredCount: Int, totalCount: Int) -> String {
        let safeTotal = max(0, totalCount)
        let safeAnswered = min(max(0, answeredCount), safeTotal)
        return "\(safeAnswered)/\(safeTotal) answered"
    }
}

/// Local-only cadence seed for the blessed values-card walk. It is opt-in so
/// sovereign data always wins in normal launches; every displayed date and
/// signal is fixed, so captures do not drift with the wall clock.
enum CadenceValuesDemo {
    enum State: String, CaseIterable, Equatable, Sendable {
        case ask
        case resting
        case trail
        case attention
        case empty
    }

    static let launchArgument = "-valuesdemo"
    static let stateArgument = "-valuesdemo-state"
    static let date = "2026-08-10"
    static let referenceNow: Date =
        ISO8601DateFormatter().date(from: "2026-08-10T10:00:00Z")!

    enum AuditAnswerState: String, Equatable {
        case pending
        case error
    }

    static func auditAnswerState(arguments: [String]) -> AuditAnswerState? {
#if DEBUG
        guard let index = arguments.firstIndex(of: "-w11-values-answer-state"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return AuditAnswerState(rawValue: arguments[index + 1].lowercased())
#else
        return nil
#endif
    }

    static var enabled: Bool {
        enabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static func enabled(arguments: [String]) -> Bool {
        return arguments.contains(launchArgument)
            || arguments.contains("-values-demo")
            || arguments.contains("-values-v2-demo")
            || arguments.contains("-cadence-values-demo")
            || auditAnswerState(arguments: arguments) != nil
    }

    static var state: State {
        state(arguments: ProcessInfo.processInfo.arguments)
    }

    static func state(arguments: [String]) -> State {
        for argument in [stateArgument, "-values-demo-state", "-values-state", "-cadence-values-state", "-w11-values-state"] {
            guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
                continue
            }
            if let state = State(rawValue: arguments[index + 1].lowercased()) {
                return state
            }
        }
        return .ask
    }

    static func card(state: State? = nil) -> CadenceReviewCard {
        switch state ?? self.state {
        case .ask:
            let probe = CadenceValueProbe(
                id: "vp-demo-deep-work",
                ordinal: 1,
                axis: "deep-work",
                prompt: "did the afternoon hold deep work?",
                question: "did the afternoon hold deep work?",
                shape: "which-is-more-you",
                forcedChoice: true,
                options: [
                    CadenceValueProbeOption(id: "held", label: "held it", value: "fed", position: "left"),
                    CadenceValueProbeOption(id: "slipped", label: "it slipped", value: "cost", position: "right"),
                ],
                valueID: "deep-work"
            )
            return CadenceReviewCard(
                id: "review-\(date)-value-probe-demo",
                type: "value-probe",
                date: date,
                title: "values",
                valueProbes: CadenceValueProbeReview(
                    weekStart: "2026-08-10",
                    weekEnd: "2026-08-16",
                    maxProbes: 1,
                    count: 1,
                    probes: [probe],
                    answerAction: CadenceValueProbeAnswerAction(
                        type: "elicitation.value-probe.answer",
                        method: "POST",
                        path: AGUIClient.cadenceValueProbeAnswersPath,
                        body: ["cardId": .string("review-\(date)-value-probe-demo"), "answers": .array([])]
                    ),
                    values: CadenceValuesCard(
                        summary: "1 probe · then quiet",
                        values: [deepWorkValue()]
                    )
                )
            )
        case .resting:
            return valuesCard(
                id: "values-demo-resting",
                summary: "3 held · 1 needs attention",
                values: restingValues()
            )
        case .trail:
            return valuesCard(
                id: "values-demo-trail",
                summary: "3 held · 1 needs attention",
                initialExpandedValueID: "deep-work",
                values: trailValues()
            )
        case .attention:
            return valuesCard(
                id: "values-demo-attention",
                summary: "embodiment slipping · 2 skips this week",
                attentionValueID: "embodiment",
                initialExpandedValueID: "embodiment",
                values: attentionValues()
            )
        case .empty:
            return valuesCard(
                id: "values-demo-empty",
                values: [CadenceValue(id: "presence", name: "presence")]
            )
        }
    }

    private static func valuesCard(
        id: String,
        summary: String? = nil,
        attentionValueID: String? = nil,
        initialExpandedValueID: String? = nil,
        values: [CadenceValue]
    ) -> CadenceReviewCard {
        CadenceReviewCard(
            id: id,
            type: "values",
            date: date,
            title: "values",
            values: CadenceValuesCard(
                summary: summary,
                attentionValueID: attentionValueID,
                initialExpandedValueID: initialExpandedValueID,
                values: values
            )
        )
    }

    private static func deepWorkValue() -> CadenceValue {
        CadenceValue(
            id: "deep-work",
            name: "deep work",
            signal: .held,
            streakDays: 12,
            lastActText: "declined the 09:00 standup",
            lastActDateText: "yesterday",
            acts: [
                CadenceValueAct(id: "deep-work-1", dateText: "yday", text: "declined the 09:00 standup"),
                CadenceValueAct(id: "deep-work-2", dateText: "aug 8", text: "4h uninterrupted on the factory plan"),
                CadenceValueAct(id: "deep-work-3", dateText: "aug 7", text: "context-switched 9× before noon", impact: .cost),
                CadenceValueAct(id: "deep-work-4", dateText: "aug 5", text: "phone in the drawer till 14:00"),
            ],
            moreCount: 12,
            moreLabel: "this month"
        )
    }

    private static func sovereigntyValue() -> CadenceValue {
        CadenceValue(
            id: "sovereignty",
            name: "sovereignty",
            signal: .held,
            streakDays: 34,
            lastActText: "moved chat off the rented model",
            lastActDateText: "aug 4",
            acts: [
                CadenceValueAct(id: "sovereignty-1", dateText: "aug 4", text: "moved chat off the rented model"),
            ]
        )
    }

    private static func embodimentValue() -> CadenceValue {
        CadenceValue(
            id: "embodiment",
            name: "embodiment",
            signal: .attention,
            attentionCount: 2,
            attentionText: "2 skipped sessions",
            lastActText: "skipped the mobility block",
            lastActDateText: "this morning",
            acts: [
                CadenceValueAct(id: "embodiment-1", dateText: "today", text: "skipped the mobility block", impact: .cost),
                CadenceValueAct(id: "embodiment-2", dateText: "aug 8", text: "sat through the strain ceiling", impact: .cost),
                CadenceValueAct(id: "embodiment-3", dateText: "aug 6", text: "full bandish run, hold complete"),
            ]
        )
    }

    private static func restingValues() -> [CadenceValue] {
        [deepWorkValue(), sovereigntyValue(), embodimentValue(), CadenceValue(id: "presence", name: "presence")]
    }

    private static func trailValues() -> [CadenceValue] {
        [deepWorkValue(), sovereigntyValue(), embodimentValue()]
    }

    private static func attentionValues() -> [CadenceValue] {
        var embodiment = embodimentValue()
        embodiment.attentionText = "2 skipped"
        return [embodiment, deepWorkValue(), sovereigntyValue()]
    }
}

struct CadenceReviewCard: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var type: String
    var date: String?
    var title: String?
    var sections: [CadenceReviewSection]
    var valueProbes: CadenceValueProbeReview?
    var values: CadenceValuesCard?

    enum CodingKeys: String, CodingKey {
        case id
        case cardId
        case type
        case kind
        case date
        case title
        case label
        case sections
        case valueProbes
        case values
        case valueCard
        case valueSignals
    }

    init(
        id: String,
        type: String,
        date: String? = nil,
        title: String? = nil,
        sections: [CadenceReviewSection] = [],
        valueProbes: CadenceValueProbeReview? = nil,
        values: CadenceValuesCard? = nil
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.title = title
        self.sections = sections
        self.valueProbes = valueProbes
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .cardId)
            ?? "review-\(UUID().uuidString)"
        type = try container.decodeTrimmedString(for: .type)
            ?? container.decodeTrimmedString(for: .kind)
            ?? "review"
        date = try container.decodeTrimmedString(for: .date)
        title = try container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .label)
        sections = (try? container.decode(LossyCadenceArray<CadenceReviewSection>.self, forKey: .sections).elements) ?? []
        valueProbes = try? container.decodeIfPresent(CadenceValueProbeReview.self, forKey: .valueProbes)
        values = (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .values))
            ?? (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .valueCard))
            ?? (try? container.decodeIfPresent(CadenceValuesCard.self, forKey: .valueSignals))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(sections, forKey: .sections)
        try container.encodeIfPresent(valueProbes, forKey: .valueProbes)
        try container.encodeIfPresent(values, forKey: .values)
    }

    var slot: CadenceReviewSlot? {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "morning-orientation", "morning_orientation", "morning":
            return .morning
        case "evening-reflection", "evening_reflection", "evening":
            return .evening
        default:
            return nil
        }
    }

    var isValueProbeCard: Bool {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "value-probe", "values", "value-card", "value-card-v2":
            return true
        default:
            return false
        }
    }

    var isValuesCard: Bool {
        isValueProbeCard || values != nil || valueProbes?.values != nil
    }

    var valuesCard: CadenceValuesCard? {
        values ?? valueProbes?.values
    }
}

struct CadenceReviewCardsResponse: Decodable, Equatable, Sendable {
    var cards: [CadenceReviewCard]

    enum CodingKeys: String, CodingKey {
        case cards
        case reviewCards
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cards = (try? container.decode(LossyCadenceArray<CadenceReviewCard>.self, forKey: .cards).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceReviewCard>.self, forKey: .reviewCards).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceReviewCard>.self, forKey: .items).elements)
            ?? []
    }
}

struct CadenceSuppressedNudgesResponse: Decodable, Equatable, Sendable {
    var nudges: [CadenceNudge]

    enum CodingKeys: String, CodingKey {
        case nudges
        case suppressed
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nudges = (try? container.decode(LossyCadenceArray<CadenceNudge>.self, forKey: .nudges).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceNudge>.self, forKey: .suppressed).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceNudge>.self, forKey: .items).elements)
            ?? []
    }
}

struct CadenceRetroResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var retro: CadenceRetro?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case retro
        case error
        case weekStart
        case tws
        case dreaming
        case decisionSignal
        case motionProgress
        case goals
        case lists
        case weeks
        case week
        case evalHealth
        case summary
        case metrics
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        error = try container.decodeTrimmedString(for: .error)
        if let envelopeRetro = try? container.decodeIfPresent(CadenceRetro.self, forKey: .retro) {
            retro = envelopeRetro
        } else if container.contains(.weekStart)
                    || container.contains(.tws)
                    || container.contains(.dreaming)
                    || container.contains(.decisionSignal)
                    || container.contains(.motionProgress)
                    || container.contains(.goals)
                    || container.contains(.lists)
                    || container.contains(.weeks)
                    || container.contains(.week)
                    || container.contains(.evalHealth)
                    || container.contains(.summary)
                    || container.contains(.metrics)
                    || container.contains(.kind) {
            retro = try CadenceRetro(from: decoder)
        } else {
            retro = nil
        }
    }
}

struct CadenceRetro: Decodable, Equatable, Sendable {
    var weekStart: String?
    var tws: CadenceRetroTWS?
    var dreaming: CadenceRetroDreaming?
    var decisionSignal: String?
    var motionProgress: CadenceRetroMotionProgress?
    var goals: [String]
    var lists: [String]
    /// Rich week projections are additive to the existing `/api/cadence/retro`
    /// contract. Legacy eval-health fields remain decoded above for older daemons.
    var weeks: [CadenceRetroWeek]
    var week: CadenceRetroWeekRange?
    var evalHealth: CadenceRetroEvalHealth?

    enum CodingKeys: String, CodingKey {
        case weekStart
        case week_start
        case tws
        case dreaming
        case decisionSignal
        case decision_signal
        case motionProgress
        case motion_progress
        case goals
        case lists
        case weeks
        case items
        case week
        case evalHealth
        case summary
        case metrics
    }

    init(
        weekStart: String? = nil,
        tws: CadenceRetroTWS? = nil,
        dreaming: CadenceRetroDreaming? = nil,
        decisionSignal: String? = nil,
        motionProgress: CadenceRetroMotionProgress? = nil,
        goals: [String] = [],
        lists: [String] = [],
        weeks: [CadenceRetroWeek] = [],
        week: CadenceRetroWeekRange? = nil,
        evalHealth: CadenceRetroEvalHealth? = nil
    ) {
        self.weekStart = weekStart
        self.tws = tws
        self.dreaming = dreaming
        self.decisionSignal = decisionSignal
        self.motionProgress = motionProgress
        self.goals = goals
        self.lists = lists
        self.weeks = weeks
        self.week = week
        self.evalHealth = evalHealth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decodeFlexibleText(for: .weekStart)
            ?? container.decodeFlexibleText(for: .week_start)
        tws = try? container.decodeIfPresent(CadenceRetroTWS.self, forKey: .tws)
        dreaming = try? container.decodeIfPresent(CadenceRetroDreaming.self, forKey: .dreaming)
        decisionSignal = try container.decodeFlexibleText(for: .decisionSignal)
            ?? container.decodeFlexibleText(for: .decision_signal)
        motionProgress = (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motionProgress))
            ?? (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motion_progress))
        goals = try container.decodeFlexibleStringArray(for: .goals) ?? []
        lists = try container.decodeFlexibleStringArray(for: .lists) ?? []
        weeks = (try? container.decode(LossyCadenceArray<CadenceRetroWeek>.self, forKey: .weeks).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceRetroWeek>.self, forKey: .items).elements)
            ?? []
        week = try? container.decodeIfPresent(CadenceRetroWeekRange.self, forKey: .week)
        evalHealth = try? container.decodeIfPresent(CadenceRetroEvalHealth.self, forKey: .evalHealth)
            ?? (try? container.decodeIfPresent(CadenceRetroEvalHealth.self, forKey: .summary))
            ?? (try? container.decodeIfPresent(CadenceRetroEvalHealth.self, forKey: .metrics))
    }

    /// The UI consumes a stable week list. A legacy daemon has no week story
    /// fields, so it deliberately returns no surface weeks rather than deriving
    /// held/slipped claims from unrelated eval-health counters.
    var surfaceWeeks: [CadenceRetroWeek] {
        weeks.filter(\.hasSurfaceSummary)
    }

    var rows: [CadenceRetroRow] {
        var values: [CadenceRetroRow] = []
        if let weekStart { values.append(CadenceRetroRow(label: "week start", value: weekStart)) }
        if let trend = tws?.trend { values.append(CadenceRetroRow(label: "tws trend", value: trend)) }
        if let responseRate = tws?.responseRate { values.append(CadenceRetroRow(label: "response rate", value: responseRate)) }
        if let hitRate = dreaming?.hitRate { values.append(CadenceRetroRow(label: "dream hit rate", value: hitRate)) }
        if let junkRate = dreaming?.junkRate { values.append(CadenceRetroRow(label: "dream junk rate", value: junkRate)) }
        if let decisionSignal { values.append(CadenceRetroRow(label: "decision signal", value: decisionSignal)) }
        if let motion = motionProgress?.motion { values.append(CadenceRetroRow(label: "motion", value: motion)) }
        if let progress = motionProgress?.progress { values.append(CadenceRetroRow(label: "progress", value: progress)) }
        return values
    }
}

/// A week range from the daemon's legacy `week` object. It is intentionally
/// separate from `CadenceRetroWeek`: old payloads carry only the window, not the
/// founder-facing held/slipped story.
struct CadenceRetroWeekRange: Decodable, Equatable, Sendable {
    var start: String?
    var end: String?
    var days: Int?

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case days
        case weekStart
        case weekEnd
        case week_start
        case week_end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeTrimmedString(for: .start)
            ?? container.decodeTrimmedString(for: .weekStart)
            ?? container.decodeTrimmedString(for: .week_start)
        end = try container.decodeTrimmedString(for: .end)
            ?? container.decodeTrimmedString(for: .weekEnd)
            ?? container.decodeTrimmedString(for: .week_end)
        days = try container.decodeFlexibleInt(for: .days)
    }
}

/// A rich week projection for the blessed retro paper. Every field is optional
/// so additive server rollout and sparse real records remain silence-default.
struct CadenceRetroWeek: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var start: String?
    var end: String?
    var verdict: String?
    var subline: String?
    var onTargetDays: Int?
    var totalDays: Int?
    var acts: Int?
    var skips: Int?
    var rcaReadyCount: Int?
    var score: CadenceRetroScore?
    var vsLastWeek: Int?
    var held: [CadenceRetroLineItem]
    var slipped: [CadenceRetroLineItem]
    var rca: CadenceRetroRCA?
    var nextWeek: CadenceRetroBet?

    var identity: String {
        id.isEmpty ? [start, end].compactMap { $0 }.joined(separator: "-") : id
    }

    var hasSurfaceSummary: Bool {
        verdict != nil
            || onTargetDays != nil
            || acts != nil
            || skips != nil
            || rcaReadyCount != nil
            || score != nil
            || !held.isEmpty
            || !slipped.isEmpty
            || rca != nil
            || nextWeek != nil
    }

    var normalizedScore: CadenceRetroScore? {
        if let score {
            if score.denominator == nil, let totalDays {
                return CadenceRetroScore(numerator: score.numerator, denominator: totalDays)
            }
            return score
        }
        guard let onTargetDays else { return nil }
        return CadenceRetroScore(numerator: onTargetDays, denominator: totalDays ?? 7)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case weekStart
        case weekEnd
        case week_start
        case week_end
        case dateRange
        case date_range
        case verdict
        case sentence
        case summary
        case subline
        case subtitle
        case onTargetDays
        case on_target_days
        case onTarget
        case totalDays
        case total_days
        case days
        case acts
        case actCount
        case act_count
        case skips
        case skipCount
        case skip_count
        case rcaReadyCount
        case rca_ready_count
        case rcaReady
        case score
        case vsLastWeek
        case vs_last_week
        case held
        case heldItems
        case held_items
        case slipped
        case slippedItems
        case slipped_items
        case rca
        case rcas
        case nextWeek
        case next_week
        case bet
        case check
    }

    init(
        id: String,
        start: String?,
        end: String?,
        verdict: String?,
        subline: String?,
        onTargetDays: Int?,
        totalDays: Int?,
        acts: Int?,
        skips: Int?,
        rcaReadyCount: Int?,
        score: CadenceRetroScore?,
        vsLastWeek: Int?,
        held: [CadenceRetroLineItem],
        slipped: [CadenceRetroLineItem],
        rca: CadenceRetroRCA?,
        nextWeek: CadenceRetroBet?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.verdict = verdict
        self.subline = subline
        self.onTargetDays = onTargetDays
        self.totalDays = totalDays
        self.acts = acts
        self.skips = skips
        self.rcaReadyCount = rcaReadyCount
        self.score = score
        self.vsLastWeek = vsLastWeek
        self.held = held
        self.slipped = slipped
        self.rca = rca
        self.nextWeek = nextWeek
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = (try? container.decodeIfPresent(CadenceRetroWeekSummary.self, forKey: .summary))
        let range = (try? container.decodeIfPresent(CadenceRetroWeekRange.self, forKey: .dateRange))
            ?? (try? container.decodeIfPresent(CadenceRetroWeekRange.self, forKey: .date_range))
        let decodedStart = try container.decodeTrimmedString(for: .start)
            ?? container.decodeTrimmedString(for: .weekStart)
            ?? container.decodeTrimmedString(for: .week_start)
            ?? range?.start
        let decodedEnd = try container.decodeTrimmedString(for: .end)
            ?? container.decodeTrimmedString(for: .weekEnd)
            ?? container.decodeTrimmedString(for: .week_end)
            ?? range?.end
        start = decodedStart
        end = decodedEnd
        verdict = try container.decodeTrimmedString(for: .verdict)
            ?? container.decodeTrimmedString(for: .sentence)
            ?? summary?.verdict
        subline = try container.decodeTrimmedString(for: .subline)
            ?? container.decodeTrimmedString(for: .subtitle)
            ?? summary?.subline
        onTargetDays = try container.decodeFlexibleInt(for: .onTargetDays)
            ?? container.decodeFlexibleInt(for: .on_target_days)
            ?? container.decodeFlexibleInt(for: .onTarget)
            ?? summary?.onTargetDays
        totalDays = try container.decodeFlexibleInt(for: .totalDays)
            ?? container.decodeFlexibleInt(for: .total_days)
            ?? container.decodeFlexibleInt(for: .days)
            ?? summary?.totalDays
        acts = try container.decodeFlexibleInt(for: .acts)
            ?? container.decodeFlexibleInt(for: .actCount)
            ?? container.decodeFlexibleInt(for: .act_count)
            ?? summary?.acts
        skips = try container.decodeFlexibleInt(for: .skips)
            ?? container.decodeFlexibleInt(for: .skipCount)
            ?? container.decodeFlexibleInt(for: .skip_count)
            ?? summary?.skips
        rcaReadyCount = try container.decodeFlexibleInt(for: .rcaReadyCount)
            ?? container.decodeFlexibleInt(for: .rca_ready_count)
            ?? container.decodeFlexibleInt(for: .rcaReady)
            ?? summary?.rcaReadyCount
        score = (try? container.decodeIfPresent(CadenceRetroScore.self, forKey: .score))
            ?? summary?.score
        vsLastWeek = try container.decodeFlexibleInt(for: .vsLastWeek)
            ?? container.decodeFlexibleInt(for: .vs_last_week)
            ?? summary?.vsLastWeek
        held = (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .held).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .heldItems).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .held_items).elements)
            ?? []
        slipped = (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .slipped).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .slippedItems).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceRetroLineItem>.self, forKey: .slipped_items).elements)
            ?? []
        rca = (try? container.decodeIfPresent(CadenceRetroRCA.self, forKey: .rca))
            ?? ((try? container.decode(LossyCadenceArray<CadenceRetroRCA>.self, forKey: .rcas).elements)?.first)
        nextWeek = (try? container.decodeIfPresent(CadenceRetroBet.self, forKey: .nextWeek))
            ?? (try? container.decodeIfPresent(CadenceRetroBet.self, forKey: .next_week))
            ?? Self.bet(from: container)
        id = try container.decodeTrimmedString(for: .id)
            ?? "\(decodedStart ?? "week")-\(decodedEnd ?? "")"
    }

    private static func bet(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> CadenceRetroBet? {
        guard let bet = try? container.decodeTrimmedString(for: .bet) else { return nil }
        return CadenceRetroBet(bet: bet, check: try? container.decodeTrimmedString(for: .check))
    }

    var idValue: String { identity }

    // Identifiable's `id` is the wire value, which is already stable.
}

struct CadenceRetroWeekSummary: Decodable, Equatable, Sendable {
    var verdict: String?
    var subline: String?
    var onTargetDays: Int?
    var totalDays: Int?
    var acts: Int?
    var skips: Int?
    var rcaReadyCount: Int?
    var score: CadenceRetroScore?
    var vsLastWeek: Int?

    enum CodingKeys: String, CodingKey {
        case verdict
        case sentence
        case subline
        case subtitle
        case onTargetDays
        case on_target_days
        case onTarget
        case totalDays
        case total_days
        case days
        case acts
        case actCount
        case act_count
        case skips
        case skipCount
        case skip_count
        case rcaReadyCount
        case rca_ready_count
        case rcaReady
        case score
        case vsLastWeek
        case vs_last_week
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try container.decodeTrimmedString(for: .verdict)
            ?? container.decodeTrimmedString(for: .sentence)
        subline = try container.decodeTrimmedString(for: .subline)
            ?? container.decodeTrimmedString(for: .subtitle)
        onTargetDays = try container.decodeFlexibleInt(for: .onTargetDays)
            ?? container.decodeFlexibleInt(for: .on_target_days)
            ?? container.decodeFlexibleInt(for: .onTarget)
        totalDays = try container.decodeFlexibleInt(for: .totalDays)
            ?? container.decodeFlexibleInt(for: .total_days)
            ?? container.decodeFlexibleInt(for: .days)
        acts = try container.decodeFlexibleInt(for: .acts)
            ?? container.decodeFlexibleInt(for: .actCount)
            ?? container.decodeFlexibleInt(for: .act_count)
        skips = try container.decodeFlexibleInt(for: .skips)
            ?? container.decodeFlexibleInt(for: .skipCount)
            ?? container.decodeFlexibleInt(for: .skip_count)
        rcaReadyCount = try container.decodeFlexibleInt(for: .rcaReadyCount)
            ?? container.decodeFlexibleInt(for: .rca_ready_count)
            ?? container.decodeFlexibleInt(for: .rcaReady)
        score = try? container.decodeIfPresent(CadenceRetroScore.self, forKey: .score)
        vsLastWeek = try container.decodeFlexibleInt(for: .vsLastWeek)
            ?? container.decodeFlexibleInt(for: .vs_last_week)
    }
}

struct CadenceRetroEvalHealth: Decodable, Equatable, Sendable {
    var tws: CadenceRetroTWS?
    var dreaming: CadenceRetroDreaming?
    var decisionSignal: String?
    var motionProgress: CadenceRetroMotionProgress?

    enum CodingKeys: String, CodingKey {
        case tws
        case dreaming
        case decisionSignal
        case decision_signal
        case motionVsProgress
        case motion_vs_progress
        case motionProgress
        case motion_progress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tws = try? container.decodeIfPresent(CadenceRetroTWS.self, forKey: .tws)
        dreaming = try? container.decodeIfPresent(CadenceRetroDreaming.self, forKey: .dreaming)
        decisionSignal = try container.decodeFlexibleText(for: .decisionSignal)
            ?? container.decodeFlexibleText(for: .decision_signal)
        motionProgress = (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motionProgress))
            ?? (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motion_progress))
            ?? (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motionVsProgress))
            ?? (try? container.decodeIfPresent(CadenceRetroMotionProgress.self, forKey: .motion_vs_progress))
    }
}

struct CadenceRetroScore: Decodable, Equatable, Sendable {
    var numerator: Int?
    var denominator: Int?

    init(numerator: Int?, denominator: Int?) {
        self.numerator = numerator
        self.denominator = denominator
    }

    enum CodingKeys: String, CodingKey {
        case numerator
        case denominator
        case onTargetDays
        case on_target_days
        case totalDays
        case total_days
        case days
        case value
        case score
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let text = try? single.decode(String.self) {
                let parts = text.split(separator: "/", maxSplits: 1).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 2 {
                    numerator = parts[0]
                    denominator = parts[1]
                    return
                }
                if let value = Int(text.trimmingCharacters(in: .whitespaces)) {
                    numerator = value
                    denominator = nil
                    return
                }
            }
            if let value = try? single.decode(Int.self) {
                numerator = value
                denominator = nil
                return
            }
            if let value = try? single.decode(Double.self), value.isFinite {
                numerator = Int(value.rounded(.down))
                denominator = nil
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        numerator = try container.decodeFlexibleInt(for: .numerator)
            ?? container.decodeFlexibleInt(for: .onTargetDays)
            ?? container.decodeFlexibleInt(for: .on_target_days)
        denominator = try container.decodeFlexibleInt(for: .denominator)
            ?? container.decodeFlexibleInt(for: .totalDays)
            ?? container.decodeFlexibleInt(for: .total_days)
            ?? container.decodeFlexibleInt(for: .days)
        if numerator == nil, let value = try container.decodeFlexibleDouble(for: .value) {
            numerator = Int(value.rounded(.down))
        }
        if numerator == nil, let value = try container.decodeFlexibleDouble(for: .score) {
            numerator = Int(value.rounded(.down))
        }
    }
}

struct CadenceRetroLineItem: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
    var acts: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case what
        case text
        case title
        case label
        case description
        case acts
        case actCount
        case act_count
        case count
    }

    init(text: String, acts: Int? = nil, id: String? = nil) {
        self.text = text
        self.acts = acts
        self.id = id ?? text
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let text = try? single.decode(String.self) {
            self.init(text: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decodeTrimmedString(for: .what)
            ?? container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .label)
            ?? container.decodeTrimmedString(for: .description)
            ?? ""
        let acts = try container.decodeFlexibleInt(for: .acts)
            ?? container.decodeFlexibleInt(for: .actCount)
            ?? container.decodeFlexibleInt(for: .act_count)
            ?? container.decodeFlexibleInt(for: .count)
        self.init(
            text: value,
            acts: acts,
            id: try container.decodeTrimmedString(for: .id) ?? value
        )
    }
}

struct CadenceRetroRCA: Decodable, Equatable, Sendable {
    var why: [String]
    var fixableCause: String?

    enum CodingKeys: String, CodingKey {
        case why
        case levels
        case causes
        case fixableCause
        case fixable_cause
        case fix
        case cause
    }

    init(why: [String], fixableCause: String?) {
        self.why = why
        self.fixableCause = fixableCause
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        why = (try? container.decodeFlexibleStringArray(for: .why))
            ?? (try? container.decodeFlexibleStringArray(for: .levels))
            ?? (try? container.decodeFlexibleStringArray(for: .causes))
            ?? []
        fixableCause = try container.decodeTrimmedString(for: .fixableCause)
            ?? container.decodeTrimmedString(for: .fixable_cause)
            ?? container.decodeTrimmedString(for: .fix)
            ?? container.decodeTrimmedString(for: .cause)
    }
}

struct CadenceRetroBet: Decodable, Equatable, Sendable {
    var bet: String?
    var check: String?

    enum CodingKeys: String, CodingKey {
        case bet
        case text
        case title
        case check
    }

    init(bet: String?, check: String?) {
        self.bet = bet
        self.check = check
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let text = try? single.decode(String.self) {
            self.init(bet: text, check: nil)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bet = try container.decodeTrimmedString(for: .bet)
            ?? container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .title)
        let check = try container.decodeTrimmedString(for: .check)
        self.init(bet: bet, check: check)
    }
}

enum CadenceRetroDateFormatter {
    static func rangeText(
        start: String?,
        end: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String? {
        guard let startDate = date(start, calendar: calendar) else { return nil }
        let endDate = date(end, calendar: calendar)
        let startMonth = month(startDate, calendar: calendar)
        let startDay = day(startDate, calendar: calendar)
        guard let endDate else { return "\(startMonth) \(startDay)".uppercased() }
        let endMonth = month(endDate, calendar: calendar)
        let endDay = day(endDate, calendar: calendar)
        if startMonth == endMonth {
            return "\(startMonth) \(startDay)–\(endDay)".uppercased()
        }
        // The blessed tab grammar carries one month label and the ending day,
        // including the July-to-August boundary (`JUL 28–3`).
        return "\(startMonth) \(startDay)–\(endDay)".uppercased()
    }

    static func heading(
        start: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String? {
        guard let startDate = date(start, calendar: calendar) else { return nil }
        return "week of \(month(startDate, calendar: calendar)) \(day(startDate, calendar: calendar))"
    }

    static func date(_ value: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        let text = String(value.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private static func month(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).lowercased()
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        String(calendar.component(.day, from: date))
    }
}

enum CadenceWeeklyRetroDemo {
    static let launchArguments = ["-w3retro", "-w3-retro", "-retro-demo"]

    enum AuditState: String, Equatable {
        case empty
        case error
    }

    static func auditState(arguments: [String] = ProcessInfo.processInfo.arguments) -> AuditState? {
#if DEBUG
        guard let index = arguments.firstIndex(of: "-w11-retro-state"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return AuditState(rawValue: arguments[index + 1].lowercased())
#else
        return nil
#endif
    }

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(where: launchArguments.contains) || auditState(arguments: arguments) != nil
    }

    /// Four fixed weeks keep audit captures independent of the wall clock and
    /// never post or persist synthetic founder activity.
    static let retro = CadenceRetro(
        weekStart: "2026-08-04",
        tws: nil,
        dreaming: nil,
        decisionSignal: nil,
        motionProgress: nil,
        goals: [],
        lists: [],
        weeks: [
            week(
                id: "2026-08-04",
                start: "2026-08-04",
                end: "2026-08-10",
                verdict: "held the line on deep work; embodiment slipped twice.",
                score: 5,
                acts: 23,
                skips: 2,
                rcaReadyCount: 1,
                vsLastWeek: -1,
                held: [
                    CadenceRetroLineItem(text: "deep work · 4h blocks landed every workday", acts: 5, id: "deep-work"),
                    CadenceRetroLineItem(text: "sovereignty · chat moved off the rented model", acts: 2, id: "sovereignty"),
                ],
                slipped: [CadenceRetroLineItem(text: "embodiment · 2 sessions skipped, both mornings", id: "embodiment")],
                rca: CadenceRetroRCA(
                    why: [
                        "both skips followed sub 6h sleep nights",
                        "both short nights followed late factory sessions",
                        "the factory session ran late because reviews were serialized after 22:00",
                    ],
                    fixableCause: "reviews after 22:00, not the mornings."
                ),
                nextWeek: CadenceRetroBet(
                    bet: "reviews close by 21:30; mobility block moves to 07:30 fixed.",
                    check: "next retro scores this bet · kept or not, with the trail."
                )
            ),
            week(
                id: "2026-07-28",
                start: "2026-07-28",
                end: "2026-08-03",
                verdict: "six days held; the late review loop cost one morning.",
                score: 6,
                acts: 25,
                skips: 1,
                rcaReadyCount: 1,
                vsLastWeek: 2,
                held: [CadenceRetroLineItem(text: "deep work · the protected block stayed first", acts: 6, id: "deep-work"), CadenceRetroLineItem(text: "review loop · decisions closed before dinner", acts: 3, id: "review-loop")],
                slipped: [CadenceRetroLineItem(text: "mobility · one morning block slipped", id: "mobility")],
                rca: CadenceRetroRCA(why: ["the block followed a late review", "the review waited on a handoff", "the handoff had no owner"], fixableCause: "name the handoff owner before review."),
                nextWeek: CadenceRetroBet(bet: "name the handoff owner before the review starts.", check: "next retro scores this bet · kept or not, with the trail.")
            ),
            week(
                id: "2026-07-21",
                start: "2026-07-21",
                end: "2026-07-27",
                verdict: "the core block held; sleep narrowed the recovery margin.",
                score: 4,
                acts: 19,
                skips: 3,
                rcaReadyCount: 1,
                vsLastWeek: -2,
                held: [CadenceRetroLineItem(text: "core work · four blocks landed", acts: 4, id: "core-work"), CadenceRetroLineItem(text: "sovereignty · local tools stayed local", acts: 2, id: "sovereignty")],
                slipped: [CadenceRetroLineItem(text: "recovery · three short nights cut the margin", id: "recovery")],
                rca: CadenceRetroRCA(why: ["short nights followed long tails", "long tails followed unresolved review queues", "the queue stayed open without a closing pass"], fixableCause: "close the review queue before the tail.") ,
                nextWeek: CadenceRetroBet(bet: "close the review queue before the tail begins.", check: "next retro scores this bet · kept or not, with the trail.")
            ),
            week(
                id: "2026-07-14",
                start: "2026-07-14",
                end: "2026-07-20",
                verdict: "the week steadied once the first block stayed protected.",
                score: 6,
                acts: 21,
                skips: 1,
                rcaReadyCount: 1,
                vsLastWeek: 1,
                held: [CadenceRetroLineItem(text: "first block · the day started with the work", acts: 6, id: "first-block"), CadenceRetroLineItem(text: "embodiment · evening sessions stayed available", acts: 3, id: "embodiment")],
                slipped: [CadenceRetroLineItem(text: "admin · one closeout moved to monday", id: "admin")],
                rca: CadenceRetroRCA(why: ["closeout moved after the last block", "the last block ran long", "it ran long because the end cue was missing"], fixableCause: "add the end cue to the last block."),
                nextWeek: CadenceRetroBet(bet: "add the end cue to the last block.", check: "next retro scores this bet · kept or not, with the trail.")
            ),
        ]
    )

    private static func week(
        id: String,
        start: String,
        end: String,
        verdict: String,
        score: Int,
        acts: Int,
        skips: Int,
        rcaReadyCount: Int,
        vsLastWeek: Int,
        held: [CadenceRetroLineItem],
        slipped: [CadenceRetroLineItem],
        rca: CadenceRetroRCA,
        nextWeek: CadenceRetroBet
    ) -> CadenceRetroWeek {
        CadenceRetroWeek(
            id: id,
            start: start,
            end: end,
            verdict: verdict,
            subline: nil,
            onTargetDays: score,
            totalDays: 7,
            acts: acts,
            skips: skips,
            rcaReadyCount: rcaReadyCount,
            score: CadenceRetroScore(numerator: score, denominator: 7),
            vsLastWeek: vsLastWeek,
            held: held,
            slipped: slipped,
            rca: rca,
            nextWeek: nextWeek
        )
    }
}

struct CadenceRetroTWS: Decodable, Equatable, Sendable {
    var trend: String?
    var responseRate: String?

    enum CodingKeys: String, CodingKey {
        case trend
        case responseRate
        case response_rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trend = try container.decodeFlexibleText(for: .trend)
        responseRate = try container.decodeFlexibleText(for: .responseRate)
            ?? container.decodeFlexibleText(for: .response_rate)
    }
}

struct CadenceRetroDreaming: Decodable, Equatable, Sendable {
    var hitRate: String?
    var junkRate: String?

    enum CodingKeys: String, CodingKey {
        case hitRate
        case hit_rate
        case junkRate
        case junk_rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hitRate = try container.decodeFlexibleText(for: .hitRate)
            ?? container.decodeFlexibleText(for: .hit_rate)
        junkRate = try container.decodeFlexibleText(for: .junkRate)
            ?? container.decodeFlexibleText(for: .junk_rate)
    }
}

struct CadenceRetroMotionProgress: Decodable, Equatable, Sendable {
    var motion: String?
    var progress: String?

    enum CodingKeys: String, CodingKey {
        case motion
        case progress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        motion = try container.decodeFlexibleText(for: .motion)
        progress = try container.decodeFlexibleText(for: .progress)
    }
}

struct CadenceRetroRow: Identifiable, Equatable, Sendable {
    var label: String
    var value: String

    var id: String { label }
}
