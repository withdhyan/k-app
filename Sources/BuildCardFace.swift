import SwiftUI
struct CardFaceAnchor: Codable, Equatable, Sendable {
    var style: String
    var text: String
    var date: String?

    init(style: String, text: String, date: String? = nil) {
        self.style = style
        self.text = text
        self.date = Self.normalized(date)
    }

    var displayText: String {
        guard let dateLabel else { return text }
        return "from \(dateLabel) · \(text)"
    }

    private var dateLabel: String? {
        guard let date else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.calendar = Calendar(identifier: .gregorian)
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.dateFormat = "yyyy-MM-dd"
        guard let parsed = input.date(from: date) else { return nil }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.calendar = input.calendar
        output.timeZone = input.timeZone
        output.dateFormat = "MMM d"
        return output.string(from: parsed).lowercased()
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CardFace: Codable, Equatable, Sendable {
    var anchor: CardFaceAnchor
    var ask: String

    enum CodingKeys: String, CodingKey {
        case anchor
        case ask
    }

    init(anchor: CardFaceAnchor, ask: String) {
        self.anchor = anchor
        self.ask = ask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAnchor = try container.decode(CardFaceAnchor.self, forKey: .anchor)
        guard let style = Self.normalized(decodedAnchor.style),
              let text = Self.normalized(decodedAnchor.text),
              let ask = Self.normalized(try container.decode(String.self, forKey: .ask))
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .ask,
                in: container,
                debugDescription: "card face requires a non-empty anchor and ask"
            )
        }
        anchor = CardFaceAnchor(style: style, text: text, date: decodedAnchor.date)
        self.ask = ask
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(ask, forKey: .ask)
    }

    static func from(_ value: ViewPacketJSONValue?) -> CardFace? {
        guard let object = value?.objectValue,
              let anchorObject = object["anchor"]?.objectValue,
              let style = normalized(anchorObject["style"]?.stringValue),
              let text = normalized(anchorObject["text"]?.stringValue),
              let ask = normalized(object["ask"]?.stringValue)
        else { return nil }

        return CardFace(
            anchor: CardFaceAnchor(
                style: style,
                text: text,
                date: normalized(anchorObject["date"]?.stringValue)
            ),
            ask: ask
        )
    }

    var jsonValue: ViewPacketJSONValue {
        var anchorObject: [String: ViewPacketJSONValue] = [
            "style": .string(anchor.style),
            "text": .string(anchor.text),
        ]
        if let date = anchor.date {
            anchorObject["date"] = .string(date)
        }
        return .object([
            "anchor": .object(anchorObject),
            "ask": .string(ask),
        ])
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CardFaceRenderState: Equatable {
    var face: CardFace?
    var isExpanded: Bool

    var showsFace: Bool {
        face != nil && !isExpanded
    }

    var showsDisclosure: Bool {
        face == nil || isExpanded
    }

    var showsConsequences: Bool {
        showsDisclosure
    }

    var linksDisclosureEntities: Bool {
        face != nil && isExpanded
    }

    var detailsText: String? {
        guard face != nil else { return nil }
        return isExpanded ? "details ‹" : "details ›"
    }
}

struct DecisionEvidenceSummary: Codable, Equatable, Sendable {
    var conversationCount: Int?
    var atomCount: Int?
    var latestAt: String?
    var topicHints: [String]

    enum CodingKeys: String, CodingKey {
        case conversationCount
        case conversation_count
        case conversations
        case atomCount
        case atom_count
        case atoms
        case latestAt
        case latest_at
        case latest
        case topicHints
        case topic_hints
        case topics
    }

    init(
        conversationCount: Int? = nil,
        atomCount: Int? = nil,
        latestAt: String? = nil,
        topicHints: [String] = []
    ) {
        self.conversationCount = conversationCount
        self.atomCount = atomCount
        self.latestAt = Self.normalized(latestAt)
        self.topicHints = Self.unique(topicHints)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            conversationCount: Self.decodeInt(from: container, keys: [.conversationCount, .conversation_count, .conversations]),
            atomCount: Self.decodeInt(from: container, keys: [.atomCount, .atom_count, .atoms]),
            latestAt: Self.decodeString(from: container, keys: [.latestAt, .latest_at, .latest]),
            topicHints: Self.decodeStrings(from: container, keys: [.topicHints, .topic_hints, .topics])
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(conversationCount, forKey: .conversationCount)
        try container.encodeIfPresent(atomCount, forKey: .atomCount)
        try container.encodeIfPresent(latestAt, forKey: .latestAt)
        if !topicHints.isEmpty {
            try container.encode(topicHints, forKey: .topicHints)
        }
    }

    var isEmpty: Bool {
        conversationCount == nil && atomCount == nil && latestAt == nil && topicHints.isEmpty
    }

    static func from(_ value: ViewPacketJSONValue?) -> DecisionEvidenceSummary? {
        guard let object = value?.objectValue else { return nil }
        let summary = DecisionEvidenceSummary(
            conversationCount: int(in: object, keys: ["conversationCount", "conversation_count", "conversations"]),
            atomCount: int(in: object, keys: ["atomCount", "atom_count", "atoms"]),
            latestAt: string(in: object, keys: ["latestAt", "latest_at", "latest"]),
            topicHints: strings(in: object, keys: ["topicHints", "topic_hints", "topics"])
        )
        return summary.isEmpty ? nil : summary
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite {
                return Int(value.rounded(.down))
            }
            if let value = decodeString(from: container, keys: [key]), let int = Int(value) {
                return int
            }
        }
        return nil
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let normalized = normalized(value) {
                return normalized
            }
        }
        return nil
    }

    private static func decodeStrings(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [String] {
        for key in keys {
            if let values = try? container.decodeIfPresent([String].self, forKey: key) {
                return unique(values)
            }
            if let value = decodeString(from: container, keys: [key]) {
                return [value]
            }
        }
        return []
    }

    private static func int(in object: [String: ViewPacketJSONValue], keys: [String]) -> Int? {
        for key in keys {
            guard let value = object[key] else { continue }
            if case .number(let number) = value, number.isFinite {
                return Int(number.rounded(.down))
            }
            if let string = scalarString(value), let int = Int(string) {
                return int
            }
        }
        return nil
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key], let string = scalarString(value) else { continue }
            return string
        }
        return nil
    }

    private static func strings(in object: [String: ViewPacketJSONValue], keys: [String]) -> [String] {
        for key in keys {
            guard let value = object[key] else { continue }
            if let array = value.arrayValue {
                return unique(array.compactMap(scalarString))
            }
            if let string = scalarString(value) {
                return [string]
            }
        }
        return []
    }

    private static func scalarString(_ value: ViewPacketJSONValue) -> String? {
        switch value {
        case .string(let string):
            return normalized(string)
        case .number, .bool:
            return normalized(value.description)
        case .object, .array, .null:
            return nil
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard let normalized = normalized(value), seen.insert(normalized.lowercased()).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct DecisionEvidencePreview: Codable, Equatable, Identifiable, Sendable {
    var label: String
    var at: String?

    var id: String {
        "\(label)|\(at ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case name
        case label
        case title
        case text
        case statement
        case at
        case createdAt
        case created_at
        case timestamp
        case latestAt
        case latest_at
        case date
    }

    init(label: String, at: String? = nil) {
        self.label = Self.normalized(label) ?? label
        self.at = Self.normalized(at)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let label = Self.decodeString(
            from: container,
            keys: [.name, .label, .title, .statement, .text]
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .label,
                in: container,
                debugDescription: "evidence preview requires a label"
            )
        }
        self.init(
            label: label,
            at: Self.decodeString(
                from: container,
                keys: [.at, .createdAt, .created_at, .timestamp, .latestAt, .latest_at, .date]
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(at, forKey: .at)
    }

    static func from(_ value: ViewPacketJSONValue?) -> [DecisionEvidencePreview] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return unique(array.compactMap(preview))
        }
        return preview(from: value).map { [$0] } ?? []
    }

    var jsonValue: ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = ["label": .string(label)]
        if let at { object["at"] = .string(at) }
        return .object(object)
    }

    private static func preview(from value: ViewPacketJSONValue) -> DecisionEvidencePreview? {
        if let object = value.objectValue {
            let label = string(in: object, keys: ["name", "label", "title", "statement", "text"])
            let at = string(in: object, keys: ["at", "createdAt", "created_at", "timestamp", "latestAt", "latest_at", "date"])
            guard let label else { return nil }
            return DecisionEvidencePreview(label: label, at: at)
        }
        guard let label = scalarString(value) else { return nil }
        return DecisionEvidencePreview(label: label)
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let normalized = normalized(value) {
                return normalized
            }
        }
        return nil
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key], let string = scalarString(value) else { continue }
            return string
        }
        return nil
    }

    private static func scalarString(_ value: ViewPacketJSONValue) -> String? {
        switch value {
        case .string(let string):
            return normalized(string)
        case .number, .bool:
            return normalized(value.description)
        case .object, .array, .null:
            return nil
        }
    }

    private static func unique(_ values: [DecisionEvidencePreview]) -> [DecisionEvidencePreview] {
        var seen: Set<String> = []
        var result: [DecisionEvidencePreview] = []
        for value in values {
            let key = value.id.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum DecisionEvidenceLineFormatter {
    static func line(
        for summary: DecisionEvidenceSummary?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let summary, !summary.isEmpty else { return nil }
        var parts: [String] = []
        if let countText = countText(for: summary) {
            parts.append(countText)
        }
        if let latestAt = summary.latestAt, let latestDate = date(from: latestAt, calendar: calendar) {
            parts.append("latest \(relativeDay(for: latestDate, now: now, calendar: calendar))")
        }
        if !summary.topicHints.isEmpty {
            parts.append(summary.topicHints.joined(separator: ", "))
        }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? nil : text.lowercased()
    }

    private static func countText(for summary: DecisionEvidenceSummary) -> String? {
        if let count = summary.conversationCount {
            return count == 1 ? "1 conversation" : "\(count) conversations"
        }
        if let count = summary.atomCount {
            return count == 1 ? "1 atom" : "\(count) atoms"
        }
        return nil
    }

    static func relativeDay(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).lowercased()
    }

    static func relativeDateText(from text: String?, now: Date, calendar: Calendar) -> String? {
        guard let text, let date = date(from: text, calendar: calendar) else { return nil }
        return relativeDay(for: date, now: now, calendar: calendar)
    }

    static func date(from text: String, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        isoFormatter.formatOptions = [.withFullDate]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }
}

enum DecisionEvidencePreviewFormatter {
    static func lines(
        for previews: [DecisionEvidencePreview],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        previews.compactMap { preview in
            line(for: preview, now: now, calendar: calendar)
        }
    }

    static func summaryLine(
        for previews: [DecisionEvidencePreview],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard !previews.isEmpty else { return nil }
        var parts = [countText(for: previews.count)]
        let latestDate = previews
            .compactMap { preview -> Date? in
                guard let at = preview.at else { return nil }
                return DecisionEvidenceLineFormatter.date(from: at, calendar: calendar)
            }
            .max()
        if let latestDate {
            parts.append("latest \(DecisionEvidenceLineFormatter.relativeDay(for: latestDate, now: now, calendar: calendar))")
        }
        return parts.joined(separator: " · ").lowercased()
    }

    private static func countText(for count: Int) -> String {
        count == 1 ? "1 piece of evidence" : "\(count) pieces of evidence"
    }

    private static func line(
        for preview: DecisionEvidencePreview,
        now: Date,
        calendar: Calendar
    ) -> String? {
        let label = preview.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        if let relative = DecisionEvidenceLineFormatter.relativeDateText(from: preview.at, now: now, calendar: calendar) {
            return "\(label) · \(relative)".lowercased()
        }
        return label.lowercased()
    }
}

enum MindEvidenceDetailFormatter {
    static func lines(
        previews: [DecisionEvidencePreview],
        evidence: [String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let previewLines = DecisionEvidencePreviewFormatter.lines(for: previews, now: now, calendar: calendar)
        if !previewLines.isEmpty {
            return previewLines
        }

        let humanEvidence = evidence.compactMap(humanEvidenceLine)
        if !humanEvidence.isEmpty {
            return humanEvidence
        }

        guard !evidence.isEmpty else { return [] }
        return [countLine(for: evidence.count)]
    }

    static func countLine(for count: Int) -> String {
        count == 1
            ? "1 piece of evidence · details on the desk"
            : "\(count) pieces of evidence · details on the desk"
    }

    static func isEvidenceFieldKey(_ key: String) -> Bool {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        return ["evidence", "evidenceids", "evidencepreviews"].contains(normalized)
    }

    static func isRawEvidenceReference(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        if text.hasPrefix("exp_") { return true }
        if text.range(of: #"^(exp|atom|tool)[_-][a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"^[a-f0-9]{16,}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func humanEvidenceLine(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRawEvidenceReference(trimmed) else { return nil }
        return trimmed.lowercased()
    }
}

struct DecisionEvidenceLineButton: View {
    let line: String
    let isExpanded: Bool
    let onToggle: () -> Void
    let accessibilityIdentifier: String?

    init(
        line: String,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        accessibilityIdentifier: String? = nil
    ) {
        self.line = line
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Button {
            KStyle.withMotion {
                onToggle()
            }
        } label: {
            KMonoCaption(line, variant: .metadata, state: .active)
                .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.lowercased())
        .accessibilityHint(isExpanded ? "hide evidence" : "show evidence")
        .accessibilityIdentifier(accessibilityIdentifier ?? "decision-evidence-line")
    }
}


