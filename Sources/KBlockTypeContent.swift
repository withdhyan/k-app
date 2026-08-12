import Foundation

enum BlockTemporal: Equatable, Sendable {
    case elapsed
    case now
    case upcoming
}

struct HealthSummary: Equatable, Sendable {
    var strain: String?
    var avgHeartRate: String?

    init(strain: String? = nil, avgHeartRate: String? = nil) {
        self.strain = Self.normalized(strain)
        self.avgHeartRate = Self.normalized(avgHeartRate)
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

struct BodySummary: Decodable, Equatable, Sendable {
    var globalBodyState: String?
    var generatedAt: String?
    var source: String?
    var hrv: BodySummaryMetric?
    var sleep: BodySummaryMetric?

    enum CodingKeys: String, CodingKey {
        case globalBodyState
        case generatedAt
        case source
        case hrv
        case sleep
    }

    init(
        globalBodyState: String? = nil,
        generatedAt: String? = nil,
        source: String? = nil,
        hrv: BodySummaryMetric? = nil,
        sleep: BodySummaryMetric? = nil
    ) {
        self.globalBodyState = Self.normalized(globalBodyState)
        self.generatedAt = generatedAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = Self.normalized(source)
        self.hrv = hrv
        self.sleep = sleep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalBodyState = Self.normalized(try container.decodeTrimmedString(for: .globalBodyState))
        generatedAt = try container.decodeTrimmedString(for: .generatedAt)
        source = Self.normalized(try container.decodeTrimmedString(for: .source))
        hrv = try? container.decodeIfPresent(BodySummaryMetric.self, forKey: .hrv)
        sleep = try? container.decodeIfPresent(BodySummaryMetric.self, forKey: .sleep)
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

struct BodySummaryMetric: Decodable, Equatable, Sendable {
    var latest: Double?
    var latestHours: Double?
    var recentMean: Double?
    var recentMeanHours: Double?
    var drift: Double?
    var driftDirection: String?
    var trendDeltaHours: Double?
    var trendDirection: String?
    var count: Int?
    var zScore: Double?
    var zScoreDirection: String?
    var zScoreSamples: Int?
    var zScoreUnavailableReason: String?
    var low: Bool?

    enum CodingKeys: String, CodingKey {
        case latest
        case latestHours
        case recentMean
        case recentMeanHours
        case drift
        case driftDirection
        case trendDeltaHours
        case trendDirection
        case count
        case zScore
        case zScoreDirection
        case zScoreSamples
        case zScoreUnavailableReason
        case low
    }

    init(
        latest: Double? = nil,
        latestHours: Double? = nil,
        recentMean: Double? = nil,
        recentMeanHours: Double? = nil,
        drift: Double? = nil,
        driftDirection: String? = nil,
        trendDeltaHours: Double? = nil,
        trendDirection: String? = nil,
        count: Int? = nil,
        zScore: Double? = nil,
        zScoreDirection: String? = nil,
        zScoreSamples: Int? = nil,
        zScoreUnavailableReason: String? = nil,
        low: Bool? = nil
    ) {
        self.latest = latest
        self.latestHours = latestHours
        self.recentMean = recentMean
        self.recentMeanHours = recentMeanHours
        self.drift = drift
        self.driftDirection = Self.normalized(driftDirection)
        self.trendDeltaHours = trendDeltaHours
        self.trendDirection = Self.normalized(trendDirection)
        self.count = count
        self.zScore = zScore
        self.zScoreDirection = Self.normalized(zScoreDirection)
        self.zScoreSamples = zScoreSamples
        self.zScoreUnavailableReason = Self.normalized(zScoreUnavailableReason)
        self.low = low
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeFlexibleDouble(for: .latest)
        latestHours = try container.decodeFlexibleDouble(for: .latestHours)
        recentMean = try container.decodeFlexibleDouble(for: .recentMean)
        recentMeanHours = try container.decodeFlexibleDouble(for: .recentMeanHours)
        drift = try container.decodeFlexibleDouble(for: .drift)
        driftDirection = Self.normalized(try container.decodeTrimmedString(for: .driftDirection))
        trendDeltaHours = try container.decodeFlexibleDouble(for: .trendDeltaHours)
        trendDirection = Self.normalized(try container.decodeTrimmedString(for: .trendDirection))
        count = try container.decodeFlexibleInt(for: .count)
        zScore = try container.decodeFlexibleDouble(for: .zScore)
        zScoreDirection = Self.normalized(try container.decodeTrimmedString(for: .zScoreDirection))
        zScoreSamples = try container.decodeFlexibleInt(for: .zScoreSamples)
        zScoreUnavailableReason = Self.normalized(try container.decodeTrimmedString(for: .zScoreUnavailableReason))
        low = try container.decodeFlexibleBool(for: .low)
    }

    var hasAnyData: Bool {
        latest != nil
            || latestHours != nil
            || recentMean != nil
            || recentMeanHours != nil
            || drift != nil
            || driftDirection != nil
            || trendDeltaHours != nil
            || trendDirection != nil
            || count != nil
            || zScore != nil
            || zScoreDirection != nil
            || zScoreSamples != nil
            || zScoreUnavailableReason != nil
            || low != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

struct Subtask: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var text: String
    var timeSensitive: Bool
    var done: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case itemId
        case text
        case title
        case label
        case timeSensitive
        case dueToday
        case done
        case completed
        case checked
    }

    init(id: String, text: String, timeSensitive: Bool = false, done: Bool = false) {
        let normalizedText = Self.normalized(text) ?? "check"
        self.id = Self.normalized(id) ?? Self.generatedID(text: normalizedText)
        self.text = normalizedText
        self.timeSensitive = timeSensitive
        self.done = done
    }

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            let normalizedText = Self.normalized(string) ?? "check"
            id = Self.generatedID(text: normalizedText)
            text = normalizedText
            timeSensitive = false
            done = false
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .label)
            ?? "check"
        id = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .itemId)
            ?? Self.generatedID(text: decodedText)
        text = decodedText.lowercased()
        timeSensitive = try container.decodeFlexibleBool(for: .timeSensitive)
            ?? container.decodeFlexibleBool(for: .dueToday)
            ?? false
        done = try container.decodeFlexibleBool(for: .done)
            ?? container.decodeFlexibleBool(for: .completed)
            ?? container.decodeFlexibleBool(for: .checked)
            ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(timeSensitive, forKey: .timeSensitive)
        try container.encode(done, forKey: .done)
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }

    private static func generatedID(text: String) -> String {
        let sanitized = text
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let value = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "check-\(UUID().uuidString)" : value
    }
}

struct ChecklistItem: Identifiable, Equatable, Sendable {
    var id: String
    var text: String
    var isDone: Bool

    init(id: String, text: String, isDone: Bool = false) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.isDone = isDone
    }
}

struct BlockContent: Equatable, Sendable {
    var metaSuffix: String?
    var detailLines: [String]
    var checklist: [ChecklistItem]?
    var liveLine: String?

    static let empty = BlockContent(metaSuffix: nil, detailLines: [], checklist: nil, liveLine: nil)

    init(
        metaSuffix: String? = nil,
        detailLines: [String] = [],
        checklist: [ChecklistItem]? = nil,
        liveLine: String? = nil
    ) {
        self.metaSuffix = Self.normalized(metaSuffix)
        self.detailLines = detailLines.compactMap(Self.normalized)
        self.checklist = checklist.flatMap { items in
            let normalized = items.filter { !$0.text.isEmpty }
            return normalized.isEmpty ? nil : normalized
        }
        self.liveLine = Self.normalized(liveLine)
    }

    var isEmpty: Bool {
        metaSuffix == nil && detailLines.isEmpty && checklist == nil && liveLine == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

struct DetailSection: Identifiable, Equatable, Sendable {
    var header: String?
    var lines: [String]
    var checklist: [ChecklistItem]?

    var id: String {
        let checklistIDs = checklist?.map(\.id).joined(separator: "|") ?? ""
        return ([header ?? "detail"] + lines + [checklistIDs]).joined(separator: "|")
    }

    init(
        header: String? = nil,
        lines: [String] = [],
        checklist: [ChecklistItem]? = nil
    ) {
        self.header = Self.normalized(header)
        self.lines = lines.compactMap(Self.normalized)
        self.checklist = checklist.flatMap { items in
            let normalized = items.filter { !$0.text.isEmpty }
            return normalized.isEmpty ? nil : normalized
        }
    }

    var isEmpty: Bool {
        lines.isEmpty && checklist == nil
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

enum KBlockTypeContent {
    static func content(
        type: String?,
        detail: ViewPacketJSONValue?,
        subtasks: [Subtask]?,
        temporal: BlockTemporal,
        health: HealthSummary?,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?,
        bodySummary: BodySummary? = nil,
        isStarted: Bool = false
    ) -> BlockContent {
        switch normalized(type) {
        case "work":
            return workContent(
                detail: detail,
                subtasks: subtasks,
                temporal: temporal,
                blockDurationMinutes: blockDurationMinutes,
                elapsedMinutes: elapsedMinutes,
                isStarted: isStarted
            )
        case "meal":
            return mealContent(detail: detail)
        case "meditation":
            return meditationContent(
                detail: detail,
                temporal: temporal,
                blockDurationMinutes: blockDurationMinutes,
                elapsedMinutes: elapsedMinutes
            )
        case "workout":
            return workoutContent(
                detail: detail,
                temporal: temporal,
                health: health,
                blockDurationMinutes: blockDurationMinutes
            )
        case "sleep":
            return sleepContent(
                detail: detail,
                temporal: temporal,
                blockDurationMinutes: blockDurationMinutes,
                bodySummary: bodySummary
            )
        case "routine":
            return routineContent(subtasks: subtasks)
        case "ops":
            return opsContent(subtasks: subtasks)
        default:
            return .empty
        }
    }

    static func detail(
        type: String?,
        detail: ViewPacketJSONValue?,
        subtasks: [Subtask]?,
        temporal: BlockTemporal,
        health: HealthSummary?,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?,
        bodySummary: BodySummary? = nil
    ) -> [DetailSection] {
        let sections: [DetailSection]
        switch normalized(type) {
        case "work":
            sections = workDetail(
                detail: detail,
                subtasks: subtasks,
                temporal: temporal,
                blockDurationMinutes: blockDurationMinutes,
                elapsedMinutes: elapsedMinutes
            )
        case "meal":
            sections = mealDetail(detail: detail)
        case "meditation":
            sections = meditationDetail(
                detail: detail,
                temporal: temporal,
                blockDurationMinutes: blockDurationMinutes,
                elapsedMinutes: elapsedMinutes
            )
        case "workout":
            sections = workoutDetail(
                detail: detail,
                temporal: temporal,
                health: health,
                blockDurationMinutes: blockDurationMinutes
            )
        case "sleep":
            sections = sleepDetail(detail: detail, bodySummary: bodySummary)
        case "routine":
            sections = checklistDetail(subtasks: subtasks, marksDueToday: true)
        case "ops":
            sections = checklistDetail(subtasks: subtasks, marksDueToday: true)
        default:
            sections = []
        }
        return sections.filter { !$0.isEmpty }
    }

    private static func workContent(
        detail: ViewPacketJSONValue?,
        subtasks: [Subtask]?,
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?,
        isStarted: Bool = false
    ) -> BlockContent {
        BlockContent(
            metaSuffix: DetailReader(detail).text(keys: ["brainState", "brain_state"]),
            checklist: temporal == .now ? checklistItems(from: subtasks) : nil,
            // Mock cadence-v7: the work phase line ('prime · set the single aim')
            // is a STARTED-state affordance. Available now-blocks show the mode
            // pills only (founder 2026-08-05: 'some more text at the bottom').
            // Founder 2026-08-05: work is the 3 mode tabs, no instruction line.
            liveLine: nil
        )
    }

    private static func workDetail(
        detail: ViewPacketJSONValue?,
        subtasks: [Subtask]?,
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?
    ) -> [DetailSection] {
        let reader = DetailReader(detail)
        var sections: [DetailSection] = []

        sections.append(DetailSection(header: "subtasks", checklist: checklistItems(from: subtasks)))

        let currentPhase = workPhase(
            temporal: temporal,
            blockDurationMinutes: blockDurationMinutes,
            elapsedMinutes: elapsedMinutes
        )
        sections.append(DetailSection(
            header: "prep arc",
            lines: ["prime", "practice", "close"].map { phase in
                phase == currentPhase ? "\(phase) · current" : phase
            }
        ))

        if let brainState = reader.text(keys: ["brainState", "brain_state"]) {
            sections.append(DetailSection(header: "brain state", lines: [brainState]))
        }

        return sections
    }

    private static func mealContent(detail: ViewPacketJSONValue?) -> BlockContent {
        let reader = DetailReader(detail)
        var lines: [String] = []
        let composition = reader.stringArray(keys: ["composition"])
        if !composition.isEmpty {
            lines.append(composition.joined(separator: " · "))
        }

        let protein = reader.text(keys: ["protein"]).map(proteinText)
        let calories = reader.text(keys: ["calories", "kcal"]).map(calorieText)
        let nutrition = [protein, calories].compactMap { $0 }
        if !nutrition.isEmpty {
            lines.append(nutrition.joined(separator: " · "))
        }

        return BlockContent(detailLines: lines)
    }

    private static func mealDetail(detail: ViewPacketJSONValue?) -> [DetailSection] {
        let reader = DetailReader(detail)
        return [
            DetailSection(
                header: "composition",
                lines: reader.stringArray(keys: ["composition", "items", "ingredients"])
            ),
            DetailSection(
                header: "macros",
                lines: mealMacroLine(reader: reader).map { [$0] } ?? []
            ),
        ]
    }

    private static func meditationContent(
        detail: ViewPacketJSONValue?,
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?
    ) -> BlockContent {
        let reader = DetailReader(detail)
        var lines: [String] = []

        if let practice = reader.text(keys: ["practice"]),
           let duration = positiveMinutes(blockDurationMinutes) {
            lines.append("\(practice) · \(duration)m")
        }

        let phase = reader.text(keys: ["phase"]).map(phaseText)
        let method = reader.text(keys: ["method"])
        let phaseMethod = [phase, method].compactMap { $0 }
        if !phaseMethod.isEmpty {
            lines.append(phaseMethod.joined(separator: " · "))
        }

        // Founder 2026-08-05: started meditation shows the mock's method
        // instruction (cadence-v7: "breath: follow the exhale to its end"),
        // not a raw "Xm in" timer. Spec-to-mock: only 'breath' is provided.
        let practiceKind = reader.text(keys: ["practice"])
        let liveLine: String?
        if temporal == .now,
           ((normalized(practiceKind) ?? "").contains("breath") || (normalized(method) ?? "").contains("breath")) {
            liveLine = "breath: follow the exhale to its end"
        } else {
            liveLine = nil
        }

        return BlockContent(detailLines: lines, liveLine: liveLine)
    }

    private static func meditationDetail(
        detail: ViewPacketJSONValue?,
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?
    ) -> [DetailSection] {
        let reader = DetailReader(detail)
        var sections: [DetailSection] = []

        if let practice = reader.text(keys: ["practice"]) {
            let line = positiveMinutes(blockDurationMinutes).map { "\(practice) · \($0)m" } ?? practice
            sections.append(DetailSection(header: "practice", lines: [line]))
        }

        let phase = reader.text(keys: ["phase"]).map(phaseText)
        let method = reader.text(keys: ["method"])
        let protocolLine = [phase, method].compactMap { $0 }.joined(separator: " · ")
        if !protocolLine.isEmpty {
            sections.append(DetailSection(header: "protocol", lines: [protocolLine]))
        }

        if temporal == .now, let elapsedMinutes {
            sections.append(DetailSection(header: "elapsed", lines: ["\(max(0, elapsedMinutes))m in"]))
        }

        sections.append(DetailSection(header: "session notes", lines: ["notes land here after the session"]))
        return sections
    }

    private static func workoutContent(
        detail: ViewPacketJSONValue?,
        temporal: BlockTemporal,
        health: HealthSummary?,
        blockDurationMinutes: Int?
    ) -> BlockContent {
        let reader = DetailReader(detail)
        var lines: [String] = []

        if let plan = reader.planText(keys: ["plan"]),
           let duration = positiveMinutes(blockDurationMinutes) {
            lines.append("\(plan) · \(duration)m")
        }

        if temporal == .elapsed {
            let healthParts = [
                health?.strain.map { "strain \($0)" },
                health?.avgHeartRate.map { "avg hr \($0)" },
            ].compactMap { $0 }
            if !healthParts.isEmpty {
                lines.append(healthParts.joined(separator: " · "))
            }
        }

        return BlockContent(detailLines: lines)
    }

    private static func workoutDetail(
        detail: ViewPacketJSONValue?,
        temporal: BlockTemporal,
        health: HealthSummary?,
        blockDurationMinutes: Int?
    ) -> [DetailSection] {
        let reader = DetailReader(detail)
        var sections: [DetailSection] = []

        let planLines = reader.stringArray(keys: ["plan"])
        if !planLines.isEmpty {
            sections.append(DetailSection(header: "plan", lines: planLines))
        } else if let plan = reader.planText(keys: ["plan"]) {
            sections.append(DetailSection(header: "plan", lines: [plan]))
        }

        sections.append(DetailSection(
            header: "exercises",
            lines: reader.stringArray(keys: ["exercises"])
        ))

        let resolvedHealth = health ?? healthSummary(detail: detail)
        if temporal == .elapsed, let line = healthLine(resolvedHealth) {
            let duration = positiveMinutes(blockDurationMinutes).map { "elapsed \($0)m" }
            sections.append(DetailSection(header: "body", lines: [[duration, line].compactMap { $0 }.joined(separator: " · ")]))
        }

        return sections
    }

    private static func sleepContent(
        detail: ViewPacketJSONValue?,
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        bodySummary: BodySummary?
    ) -> BlockContent {
        switch temporal {
        case .now, .upcoming:
            let duration = positiveMinutes(blockDurationMinutes).map(durationSentenceText)
            return BlockContent(detailLines: duration.map { ["sleep · \($0)"] } ?? [])
        case .elapsed:
            let values = sleepPhaseValues(reader: DetailReader(detail))
            let total = values.map(\.minutes).reduce(0, +)
            var lines: [String] = []

            if total > 0 {
                var parts = [durationText(total)]
                if let deep = values.first(where: { $0.name == "deep" })?.minutes {
                    parts.append("deep \(durationText(deep))")
                }
                if let rem = values.first(where: { $0.name == "rem" })?.minutes {
                    parts.append("rem \(durationText(rem))")
                }
                lines.append(parts.joined(separator: " · "))
            }

            if let attentionLine = sleepNeedsAttentionLine(bodySummary: bodySummary) {
                lines.append(attentionLine)
            }
            if let readinessLine = sleepReadinessLine(
                totalSleepMinutes: total > 0 ? total : nil,
                bodySummary: bodySummary
            ) {
                lines.append(readinessLine)
            }
            return BlockContent(detailLines: lines)
        }
    }

    private static func sleepDetail(detail: ViewPacketJSONValue?, bodySummary: BodySummary?) -> [DetailSection] {
        let reader = DetailReader(detail)
        var vitals = vitalsLines(reader: reader)
        if let hrvLine = bodySummaryHRVLine(bodySummary?.hrv) {
            vitals.append(hrvLine)
        }
        return [
            DetailSection(header: "phases", lines: sleepPhaseLines(reader: reader)),
            DetailSection(header: "vitals", lines: vitals),
        ]
    }

    static func sleepNeedsAttentionLine(bodySummary: BodySummary?) -> String? {
        let reasons = sleepNeedsAttentionReasons(bodySummary: bodySummary)
        guard !reasons.isEmpty else { return nil }
        return (["needs attention"] + reasons).joined(separator: " · ")
    }

    static func sleepReadinessLine(totalSleepMinutes: Int?, bodySummary: BodySummary?) -> String? {
        let sleepMinutes = positiveMinutes(totalSleepMinutes)
            ?? bodySummary?.sleep?.latestHours.flatMap(minutesFromHours)
        let sleptSegment = sleepMinutes.map { "slept \(durationSentenceText($0))" }
        let hrvSegment = sleepReadinessHRVSegment(bodySummary?.hrv)
        let sleepSignalSegment = sleepReadinessSleepSegment(
            bodySummary?.sleep,
            alreadyShowsSleepDuration: sleptSegment != nil
        )
        let segments = [sleptSegment, hrvSegment, sleepSignalSegment].compactMap { $0 }
        guard !segments.isEmpty else { return nil }
        let hasLowFlag = bodySummary?.hrv?.low == true || bodySummary?.sleep?.low == true
        return (segments + [hasLowFlag ? "gentle day" : "ready"]).joined(separator: " · ")
    }

    static func sleepPhaseTypographyLines(detail: ViewPacketJSONValue?) -> [String] {
        sleepPhaseLines(reader: DetailReader(detail))
    }

    private static func routineContent(subtasks: [Subtask]?) -> BlockContent {
        let items = checklistItems(from: subtasks)
        return BlockContent(
            metaSuffix: countText(for: items),
            checklist: items
        )
    }

    private static func opsContent(subtasks: [Subtask]?) -> BlockContent {
        let items = subtasks?.map { subtask in
            ChecklistItem(
                id: subtask.id,
                text: subtask.timeSensitive ? "\(subtask.text) · due today" : subtask.text,
                isDone: subtask.done
            )
        }
        let normalized = items?.isEmpty == false ? items : nil
        return BlockContent(
            metaSuffix: countText(for: normalized),
            checklist: normalized
        )
    }

    private static func checklistDetail(subtasks: [Subtask]?, marksDueToday: Bool) -> [DetailSection] {
        let items = subtasks?.map { subtask in
            ChecklistItem(
                id: subtask.id,
                text: marksDueToday && subtask.timeSensitive ? "\(subtask.text) · due today" : subtask.text,
                isDone: subtask.done
            )
        }
        return [DetailSection(header: "checklist", checklist: items)]
    }

    // Founder 2026-08-05: align to the cadence-v7 mock — the started-work line
    // is a MODE instruction, not a phase line. "convergent: ..." is the mock's
    // exact copy; divergent/breakthrough are drafts to refine.
    private static func workLiveLine(temporal: BlockTemporal, mode: String?) -> String? {
        guard temporal == .now else { return nil }
        let m = normalized(mode) ?? ""
        // Spec-to-mock: cadence-v7 only provides the convergent line. Other
        // modes show no invented instruction until the founder specs them.
        if m.contains("converge") || m.contains("convergent") {
            return "convergent: one thing, until it yields"
        }
        return nil
    }

    private static func workPhase(
        temporal: BlockTemporal,
        blockDurationMinutes: Int?,
        elapsedMinutes: Int?
    ) -> String? {
        guard temporal == .now,
              let duration = blockDurationMinutes,
              duration > 0,
              let elapsedMinutes
        else { return nil }

        let fraction = Double(max(0, elapsedMinutes)) / Double(duration)
        if fraction <= 0.1 { return "prime" }
        if fraction >= 0.9 { return "close" }
        return "practice"
    }

    private static func checklistItems(from subtasks: [Subtask]?) -> [ChecklistItem]? {
        let items = subtasks?.map { subtask in
            ChecklistItem(id: subtask.id, text: subtask.text, isDone: subtask.done)
        }
        return items?.isEmpty == false ? items : nil
    }

    private static func countText(for items: [ChecklistItem]?) -> String? {
        guard let items, !items.isEmpty else { return nil }
        return "\(items.filter(\.isDone).count)/\(items.count)"
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }

    private static func proteinText(_ value: String) -> String {
        if value.contains("protein") { return value }
        if value.contains("g") { return "\(value) protein" }
        return "\(value)g protein"
    }

    private static func calorieText(_ value: String) -> String {
        if value.contains("kcal") { return value }
        return "\(value) kcal"
    }

    private static func gramText(_ value: String, label: String) -> String {
        if value.contains(label) { return value }
        if value.contains("g") { return "\(value) \(label)" }
        return "\(value)g \(label)"
    }

    private static func mealMacroLine(reader: DetailReader) -> String? {
        let protein = reader.text(keys: ["protein", "proteinGrams", "protein_g"]).map(proteinText)
        let calories = reader.text(keys: ["calories", "kcal"]).map(calorieText)
        let carbs = reader.text(keys: ["carbs", "carbohydrates", "carbsGrams", "carbs_g"]).map { gramText($0, label: "carbs") }
        let fat = reader.text(keys: ["fat", "fatGrams", "fat_g"]).map { gramText($0, label: "fat") }
        let fibre = reader.text(keys: ["fibre", "fiber", "fibreGrams", "fiberGrams", "fibre_g", "fiber_g"]).map { gramText($0, label: "fibre") }
        let parts = [protein, calories, carbs, fat, fibre].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func phaseText(_ value: String) -> String {
        value.hasPrefix("phase ") ? value : "phase \(value)"
    }

    private static func positiveMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", remainder))"
        }
        return "\(minutes)m"
    }

    private static func durationSentenceText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0, remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private static func healthSummary(detail: ViewPacketJSONValue?) -> HealthSummary? {
        let reader = DetailReader(detail)
        let nested = reader.object(keys: ["health", "body"])
        let healthReader = nested.map { DetailReader(.object($0)) } ?? reader
        let summary = HealthSummary(
            strain: healthReader.text(keys: ["strain"]),
            avgHeartRate: healthReader.text(keys: ["avgHeartRate", "avg_hr", "averageHeartRate"])
        )
        return summary.strain == nil && summary.avgHeartRate == nil ? nil : summary
    }

    private static func healthLine(_ health: HealthSummary?) -> String? {
        let parts = [
            health?.strain.map { "strain \($0)" },
            health?.avgHeartRate.map { "avg hr \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func sleepPhaseValues(reader: DetailReader) -> [(name: String, minutes: Int)] {
        let phaseReader = reader.object(keys: ["phases", "phaseBreakdown"])
            .map { DetailReader(.object($0)) } ?? reader
        return ["deep", "rem", "light", "awake"].compactMap { key in
            guard let minutes = phaseReader.int(keys: [key]), minutes > 0 else { return nil }
            return (name: key, minutes: minutes)
        }
    }

    private static func sleepPhaseLines(reader: DetailReader) -> [String] {
        let values = sleepPhaseValues(reader: reader)
        let total = values.map(\.minutes).reduce(0, +)
        guard total > 0 else { return [] }
        return values.map { value in
            let duration = leftPadded(durationText(value.minutes), toLength: 5)
            let percentage = leftPadded("\(Int((Double(value.minutes) / Double(total) * 100).rounded()))%", toLength: 4)
            return "\(value.name.padding(toLength: 5, withPad: " ", startingAt: 0)) \(duration) \(percentage)"
        }
    }

    private static func bodySummaryHRVLine(_ hrv: BodySummaryMetric?) -> String? {
        guard let hrv else { return nil }
        let parts = [
            hrv.latest.map { "hrv \(numberText($0))" },
            hrv.recentMean.map { "baseline \(numberText($0))" },
            hrv.zScore.map { "z \(signedNumberText($0))" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func sleepNeedsAttentionReasons(bodySummary: BodySummary?) -> [String] {
        [
            bodySummary?.hrv?.low == true ? "hrv low" : nil,
            bodySummary?.sleep?.low == true ? "sleep low" : nil,
        ].compactMap { $0 }
    }

    private static func sleepReadinessHRVSegment(_ hrv: BodySummaryMetric?) -> String? {
        guard let hrv, hrv.hasAnyData else { return nil }
        if hrv.low == true {
            return "hrv low"
        }
        if let direction = hrv.driftDirection ?? hrv.zScoreDirection {
            return "hrv \(direction)"
        }
        if hrv.low == false {
            return "hrv steady"
        }
        return nil
    }

    private static func sleepReadinessSleepSegment(
        _ sleep: BodySummaryMetric?,
        alreadyShowsSleepDuration: Bool
    ) -> String? {
        guard let sleep, sleep.hasAnyData else { return nil }
        if sleep.low == true {
            return "sleep low"
        }
        if alreadyShowsSleepDuration {
            return nil
        }
        if let direction = sleep.trendDirection ?? sleep.zScoreDirection {
            return "sleep \(direction)"
        }
        if sleep.low == false {
            return "sleep steady"
        }
        return nil
    }

    private static func minutesFromHours(_ hours: Double) -> Int? {
        guard hours.isFinite, hours > 0 else { return nil }
        return Int((hours * 60).rounded())
    }

    private static func leftPadded(_ value: String, toLength length: Int) -> String {
        let deficit = max(0, length - value.count)
        return String(repeating: " ", count: deficit) + value
    }

    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded(.towardZero) == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    private static func signedNumberText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value < 0 {
            return "−\(numberText(abs(value)))"
        }
        if value > 0 {
            return "+\(numberText(value))"
        }
        return "0"
    }

    private static func vitalsLines(reader: DetailReader) -> [String] {
        guard let vitals = reader.object(keys: ["vitals"]) else { return [] }
        let vitalReader = DetailReader(.object(vitals))
        let orderedKeys = [
            ("hrv", ["hrv"]),
            ("rhr", ["rhr", "restingHeartRate", "resting_hr"]),
            ("avg hr", ["avgHeartRate", "avg_hr", "averageHeartRate"]),
            ("resp", ["respiratoryRate", "respiratory_rate", "resp"]),
            ("spo2", ["spo2", "oxygen"]),
            ("skin temp", ["skinTemp", "skin_temp"]),
        ]
        var used = Set<String>()
        var lines = orderedKeys.compactMap { label, keys -> String? in
            guard let value = vitalReader.text(keys: keys) else { return nil }
            used.formUnion(keys)
            return "\(label) \(value)"
        }
        let fallback = vitals.keys
            .filter { !used.contains($0) }
            .sorted()
            .compactMap { key -> String? in
                guard let value = DetailReader(.object(vitals)).text(keys: [key]) else { return nil }
                return "\(key) \(value)"
            }
        lines.append(contentsOf: fallback)
        return lines
    }
}

private struct DetailReader {
    private let fields: [String: ViewPacketJSONValue]

    init(_ value: ViewPacketJSONValue?) {
        fields = value?.objectValue ?? [:]
    }

    func text(keys: [String]) -> String? {
        for key in keys {
            guard let value = fields[key] else { continue }
            if let text = Self.scalarText(value) {
                return text
            }
        }
        return nil
    }

    func int(keys: [String]) -> Int? {
        for key in keys {
            guard let value = fields[key] else { continue }
            switch value {
            case .number(let number):
                return Int(number.rounded())
            case .string(let string):
                let digits = string.filter { $0.isNumber }
                if let value = Int(digits) {
                    return value
                }
            default:
                continue
            }
        }
        return nil
    }

    func object(keys: [String]) -> [String: ViewPacketJSONValue]? {
        for key in keys {
            if let object = fields[key]?.objectValue {
                return object
            }
        }
        return nil
    }

    func stringArray(keys: [String]) -> [String] {
        for key in keys {
            guard let value = fields[key] else { continue }
            let strings: [String]
            if let array = value.arrayValue {
                strings = array.compactMap(Self.textFromListItem)
            } else if let text = Self.scalarText(value) {
                strings = [text]
            } else {
                strings = []
            }
            if !strings.isEmpty {
                return strings
            }
        }
        return []
    }

    func planText(keys: [String]) -> String? {
        let values = stringArray(keys: keys)
        if !values.isEmpty {
            return values.joined(separator: " · ")
        }
        return text(keys: keys)
    }

    private static func textFromListItem(_ value: ViewPacketJSONValue) -> String? {
        if let object = value.objectValue {
            for key in ["text", "title", "label", "name"] {
                if let text = scalarText(object[key]) {
                    return text
                }
            }
            return nil
        }
        return scalarText(value)
    }

    private static func scalarText(_ value: ViewPacketJSONValue?) -> String? {
        guard let value else { return nil }
        let text: String
        switch value {
        case .string(let string):
            text = string
        case .number(let number):
            text = number.rounded(.towardZero) == number ? String(Int(number)) : String(number)
        case .bool(let bool):
            text = bool ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

private extension KeyedDecodingContainer {
    func decodeTrimmedString(for key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    func decodeFlexibleBool(for key: Key) throws -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        guard let string = try decodeTrimmedString(for: key)?.lowercased() else {
            return nil
        }
        if ["yes", "y", "true", "1", "well-spent", "well spent"].contains(string) {
            return true
        }
        if ["no", "n", "false", "0", "not-well-spent", "not well spent"].contains(string) {
            return false
        }
        return nil
    }

    func decodeFlexibleInt(for key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded())
        }
        guard let string = try decodeTrimmedString(for: key),
              let value = Double(string),
              value.isFinite
        else {
            return nil
        }
        return Int(value.rounded())
    }

    func decodeFlexibleDouble(for key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        guard let string = try decodeTrimmedString(for: key),
              let value = Double(string),
              value.isFinite
        else {
            return nil
        }
        return value
    }
}
