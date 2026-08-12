import Foundation

enum MealMacroKind: CaseIterable, Sendable {
    case calories
    case protein
    case carbs
    case fat
    case fiber
    case sugar
}

struct MealMacroMeasurements: Codable, Equatable, Sendable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?

    init(
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil
    ) {
        self.calories = Self.positive(calories)
        self.protein = Self.positive(protein)
        self.carbs = Self.positive(carbs)
        self.fat = Self.positive(fat)
        self.fiber = Self.positive(fiber)
        self.sugar = Self.positive(sugar)
    }

    var hasMeasurement: Bool {
        values.contains { $0 != nil }
    }

    var values: [Double?] {
        [calories, protein, carbs, fat, fiber, sugar]
    }

    func value(for kind: MealMacroKind) -> Double? {
        switch kind {
        case .calories:
            return calories
        case .protein:
            return protein
        case .carbs:
            return carbs
        case .fat:
            return fat
        case .fiber:
            return fiber
        case .sugar:
            return sugar
        }
    }

    mutating func set(_ value: Double, for kind: MealMacroKind) {
        guard let value = Self.positive(value) else { return }
        switch kind {
        case .calories:
            calories = value
        case .protein:
            protein = value
        case .carbs:
            carbs = value
        case .fat:
            fat = value
        case .fiber:
            fiber = value
        case .sugar:
            sugar = value
        }
    }

    func adding(_ other: MealMacroMeasurements) -> MealMacroMeasurements {
        MealMacroMeasurements(
            calories: Self.sum(calories, other.calories),
            protein: Self.sum(protein, other.protein),
            carbs: Self.sum(carbs, other.carbs),
            fat: Self.sum(fat, other.fat),
            fiber: Self.sum(fiber, other.fiber),
            sugar: Self.sum(sugar, other.sugar)
        )
    }

    func summaryText(prefix: String? = nil) -> String? {
        let parts = [
            calories.map { "\(Self.formatted($0)) kcal" },
            protein.map { "\(Self.formatted($0))g protein" },
            carbs.map { "\(Self.formatted($0))g carbs" },
            fat.map { "\(Self.formatted($0))g fat" },
            fiber.map { "\(Self.formatted($0))g fiber" },
            sugar.map { "\(Self.formatted($0))g sugar" },
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let values = [prefix].compactMap { $0 } + parts
        return values.joined(separator: " · ")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(carbs, forKey: .carbs)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(fiber, forKey: .fiber)
        try container.encodeIfPresent(sugar, forKey: .sugar)
    }

    private enum CodingKeys: String, CodingKey {
        case calories
        case protein
        case carbs
        case fat
        case fiber
        case sugar
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func sum(_ left: Double?, _ right: Double?) -> Double? {
        let value = (left ?? 0) + (right ?? 0)
        return value > 0 ? value : nil
    }

    private static func formatted(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

enum MealTextParser {
    static func parse(_ text: String) -> MealMacroMeasurements? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        var measurements = MealMacroMeasurements()
        let candidates = pairCandidates(in: normalized)
        for candidate in selectedCandidates(from: candidates) {
            measurements.set(candidate.value, for: candidate.kind)
        }

        return measurements.hasMeasurement ? measurements : nil
    }

    private static func pairCandidates(in text: String) -> [Candidate] {
        numberBeforeWordCandidates(in: text) + wordBeforeNumberCandidates(in: text)
    }

    private static func numberBeforeWordCandidates(in text: String) -> [Candidate] {
        candidates(
            pattern: "(^|[^a-z0-9.])([0-9]+(?:\\.[0-9]+)?)\\s*(?:g|grams?)?\\s*(kcal|calories|cal|protein|carbs|carb|fat|fiber|fibre|sugar|p|c|f)(?=$|[^a-z0-9])",
            in: text,
            numberGroup: 2,
            unitGroup: 3
        )
    }

    private static func wordBeforeNumberCandidates(in text: String) -> [Candidate] {
        candidates(
            pattern: "(^|[^a-z0-9])(kcal|calories|cal|protein|carbs|carb|fat|fiber|fibre|sugar|p|c|f)\\s*[:=]?\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:g|grams?)?(?=$|[^a-z0-9])",
            in: text,
            numberGroup: 3,
            unitGroup: 2
        )
    }

    private static func candidates(
        pattern: String,
        in text: String,
        numberGroup: Int,
        unitGroup: Int
    ) -> [Candidate] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard
                let numberRange = Range(match.range(at: numberGroup), in: text),
                let unitRange = Range(match.range(at: unitGroup), in: text),
                let value = Double(text[numberRange]),
                let kind = kind(for: String(text[unitRange]))
            else { return nil }
            let candidateRange = NSUnionRange(match.range(at: numberGroup), match.range(at: unitGroup))
            return Candidate(kind: kind, value: value, range: candidateRange)
        }
    }

    private static func selectedCandidates(from candidates: [Candidate]) -> [Candidate] {
        let sorted = candidates.sorted { lhs, rhs in
            if NSMaxRange(lhs.range) == NSMaxRange(rhs.range) {
                if lhs.range.location == rhs.range.location {
                    return lhs.range.length < rhs.range.length
                }
                return lhs.range.location < rhs.range.location
            }
            return NSMaxRange(lhs.range) < NSMaxRange(rhs.range)
        }
        guard !sorted.isEmpty else { return [] }

        var bestSelections = Array(repeating: [Candidate](), count: sorted.count + 1)
        for index in sorted.indices {
            let candidate = sorted[index]
            var previousIndex = index - 1
            while previousIndex >= 0, NSMaxRange(sorted[previousIndex].range) > candidate.range.location {
                previousIndex -= 1
            }
            let include = bestSelections[previousIndex + 1] + [candidate]
            let exclude = bestSelections[index]
            bestSelections[index + 1] = include.count > exclude.count ? include : exclude
        }

        return bestSelections[sorted.count].sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private static func kind(for unit: String) -> MealMacroKind? {
        switch unit {
        case "kcal", "cal", "calories":
            return .calories
        case "protein", "p":
            return .protein
        case "carbs", "carb", "c":
            return .carbs
        case "fat", "f":
            return .fat
        case "fiber", "fibre":
            return .fiber
        case "sugar":
            return .sugar
        default:
            return nil
        }
    }

    private struct Candidate {
        var kind: MealMacroKind
        var value: Double
        var range: NSRange
    }
}

struct MealLogRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var meal: MealMacroMeasurements
    var blockId: String?

    init(id: UUID = UUID(), timestamp: Date, meal: MealMacroMeasurements, blockId: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.meal = meal
        self.blockId = blockId
    }
}

enum MealLogAccumulator {
    static func total(
        in records: [MealLogRecord],
        now: Date,
        calendar: Calendar = Calendar.current
    ) -> MealMacroMeasurements? {
        let total = records
            .filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
            .reduce(MealMacroMeasurements()) { partial, record in
                partial.adding(record.meal)
            }
        return total.hasMeasurement ? total : nil
    }
}

struct MealLogLocalStore {
    static let didChangeNotification = Notification.Name("KMealLogLocalStoreDidChange")

    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "body.mealLogs.local",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> [MealLogRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MealLogRecord].self, from: data)) ?? []
    }

    func save(_ records: [MealLogRecord], now: Date = Date(), calendar: Calendar = Calendar.current) {
        let pruned = records.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        if pruned.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(pruned) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func append(_ record: MealLogRecord, now: Date = Date(), calendar: Calendar = Calendar.current) {
        save(load() + [record], now: now, calendar: calendar)
    }
}

struct BodyMealLogResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var error: String?
}

struct AGUIOutcome: Equatable, Sendable {
    let packet: ViewPacket?
    let packetId: String?
    let lane: String?
    let sensitivity: String?
    let sovereign: Bool
    let steps: Int?
    let held: Bool
}

enum AGUIStreamEvent: Equatable, Sendable {
    case snapshot([ViewPacket])
    case packet(ViewPacket)
    case patch(ViewPacketPatch)
}

enum AGUIClientError: LocalizedError, Equatable {
    case invalidURL
    case httpStatus(Int)
    case apiError(status: Int, message: String)
    case invalidResponse
    case missingAction
    case sovereignUnavailable(silenced: Bool)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The daemon URL is invalid."
        case .httpStatus(let code):
            return "Daemon returned HTTP \(code)."
        case .apiError(_, let message):
            return message
        case .invalidResponse:
            return "Daemon returned an unreadable response."
        case .missingAction:
            return "This packet does not expose an action."
        case .sovereignUnavailable(let silenced):
            return silenced
                ? "Sovereign lane unavailable — held rather than answered from a frontier."
                : "Sovereign lane unavailable."
        case .stream(let message):
            return "AG-UI stream error: \(message)"
        }
    }
}

extension AGUIClientError {
    var isHTTP404: Bool {
        switch self {
        case .httpStatus(404), .apiError(status: 404, message: _):
            return true
        default:
            return false
        }
    }
}

struct AGUILineResponse {
    let response: URLResponse
    let lines: AsyncThrowingStream<String, Error>
}

struct AGUIHTTPTransport {
    private let handler: (URLRequest) async throws -> AGUILineResponse

    init(handler: @escaping (URLRequest) async throws -> AGUILineResponse) {
        self.handler = handler
    }

    func lines(for request: URLRequest) async throws -> AGUILineResponse {
        try await handler(request)
    }

    static let live = AGUIHTTPTransport { request in
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return AGUILineResponse(response: response, lines: stream)
    }
}

/// Minimal SSE client for the cs-k AG-UI `POST /api/agui/message` endpoint.
///
/// This mirrors `CSKChat`: plain HTTP only to the sovereign daemon over
/// loopback/Tailscale, no bearer token, no third-party transport.
struct AGUIClient {
    static let actionInvokeType = "action-invoke"
    static let buildEventsPath = "/api/build/events"
    static let buildCardAnswerPath = "/api/build/cards/answer"
    static let buildRequestPath = "/api/build/request"
    static let buildDocPath = "/api/build/doc"
    static let buildDiffPath = "/api/build/diff"
    static let buildEvidencePath = "/api/build/evidence"
    static let buildLearnedPath = "/api/build/learned"
    static let buildLearnedDecisionPath = "/api/build/learned/decision"
    static let buildTrustPath = "/api/build/trust"
    static let buildTrustPairsPath = "/api/build/trust/pair"
    static let buildLaneLogTailPath = "/api/build/lane/log-tail"
    static let buildSignalsPath = "/api/build/signals"
    static let mindArtifactsPath = "/api/artifacts/mind"
    static let mindEntityPath = "/api/mind/entity"
    static let mindVerdictPath = "/api/artifacts/mind/verdict"
    static let bioArtifactsPath = "/api/artifacts/bio"
    static let interventionsPath = "/api/interventions"
    static let cadenceDayPath = "/api/cadence/day"
    static let cadenceActsPath = "/api/cadence/acts"
    static let cadenceRetroPath = "/api/cadence/retro"
    static let cadenceReviewCardsPath = "/api/cadence/review-cards"
    static let cadenceValueProbeAnswersPath = "/api/cadence/value-probes/answers"
    static let cadenceSuppressedNudgesPath = "/api/cadence/nudges/suppressed-today"
    static let cadenceNudgeDispositionPath = "/api/cadence/nudges/disposition"
    static let cadenceRescorePath = "/api/cadence/rescore"
    static let cadenceRescoreComparePath = "/api/cadence/rescore/compare"
    static let bodySummaryPath = "/api/body/summary"
    static let bodyCueContextPath = "/api/body/cue-context"
    static let bodyInterventionsFeedbackPath = "/api/body/interventions/feedback"
    static let bodyMealPath = "/api/body/meal"
    static let bodyMealPhotoPath = "/api/body/meal-photo"
    static let bodyLogPath = "/api/body/log"
    static let aguiEventsPath = "/api/agui/events"
    static let adminBandishPath = "/api/admin/bandish"
    static let adminItemsPath = "/api/admin/items"
    static let adminIntakePath = "/api/admin/intake"
    static let adminConfirmPath = "/api/admin/confirm"

    let baseURL: String
    let transport: AGUIHTTPTransport

    init(baseURL: String, transport: AGUIHTTPTransport = .live) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func send(
        message: String,
        history: [[String: String]] = [],
        onPacket: @escaping @MainActor (ViewPacket) -> Void
    ) async throws -> AGUIOutcome {
        try await send(message: message, history: history, onEvent: { event in
            if case .packet(let packet) = event {
                onPacket(packet)
            }
        })
    }

    func send(
        message: String,
        history: [[String: String]] = [],
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void
    ) async throws -> AGUIOutcome {
        var body: [String: Any] = ["message": message]
        if !history.isEmpty { body["history"] = history }
        let request = try makeAGUIRequest(body: JSONSerialization.data(withJSONObject: body))
        return try await stream(request: request, onEvent: onEvent)
    }

    func invokeAction(
        packet: ViewPacket,
        onPacket: @escaping @MainActor (ViewPacket) -> Void
    ) async throws -> AGUIOutcome {
        try await invokeAction(packet: packet, onEvent: { event in
            if case .packet(let packet) = event {
                onPacket(packet)
            }
        })
    }

    func invokeAction(
        packet: ViewPacket,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void
    ) async throws -> AGUIOutcome {
        guard let action = packet.action else { throw AGUIClientError.missingAction }
        let request = try makeAGUIRequest(body: Self.actionInvokeBody(packet: packet, action: action))
        return try await stream(request: request, onEvent: onEvent)
    }

    func subscribeBuildEvents(
        lastEventID: String?,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void,
        onEventID: (@MainActor (String) -> Void)? = nil
    ) async throws {
        let request = try makeBuildEventsRequest(lastEventID: lastEventID)
        try await subscribeEvents(request: request, onEvent: onEvent, onEventID: onEventID)
    }

    func subscribeBuildEvents(
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void
    ) async throws {
        try await subscribeBuildEvents(lastEventID: nil, onEvent: onEvent, onEventID: nil)
    }

    func subscribeAGUIEvents(
        recentPacketLimit: Int = 10,
        lastEventID: String?,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void,
        onEventID: (@MainActor (String) -> Void)? = nil
    ) async throws {
        let request = try makeAGUIEventsRequest(recentPacketLimit: recentPacketLimit, lastEventID: lastEventID)
        try await subscribeEvents(request: request, onEvent: onEvent, onEventID: onEventID)
    }

    func subscribeAGUIEvents(
        recentPacketLimit: Int = 10,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void
    ) async throws {
        try await subscribeAGUIEvents(
            recentPacketLimit: recentPacketLimit,
            lastEventID: nil,
            onEvent: onEvent,
            onEventID: nil
        )
    }

    private func subscribeEvents(
        request: URLRequest,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void,
        onEventID: (@MainActor (String) -> Void)? = nil
    ) async throws {
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else { throw AGUIClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AGUIClientError.httpStatus(http.statusCode) }

        let decoder = JSONDecoder()
        var event = ""

        for try await line in lineResponse.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("id:") {
                let eventID = line.dropFirst("id:".count).trimmingCharacters(in: .whitespaces)
                if !eventID.isEmpty {
                    await onEventID?(eventID)
                }
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8) else { continue }

            switch event {
            case "snapshot", "build.snapshot", "build_snapshot", "packet", "packet_patch",
                 "chat.worker", "worker", "task", "task_packet":
                if let decoded = try Self.decodeStreamEvent(named: event, data: data, decoder: decoder) {
                    await onEvent(decoded)
                }
            case "error":
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AGUIClientError.stream("unknown")
                }
                throw AGUIClientError.stream((obj["error"] as? String) ?? "unknown")
            default:
                continue
            }
        }
    }

    func buildSnapshotOnce() async throws -> [ViewPacket] {
        let request = try makeBuildEventsRequest()
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else { throw AGUIClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AGUIClientError.httpStatus(http.statusCode) }

        let decoder = JSONDecoder()
        var event = ""

        for try await line in lineResponse.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8) else { continue }

            switch event {
            case "snapshot", "build.snapshot", "build_snapshot":
                if case .snapshot(let packets) = try Self.decodeStreamEvent(named: event, data: data, decoder: decoder) {
                    return packets
                }
            case "packet":
                if case .packet(let packet) = try Self.decodeStreamEvent(named: event, data: data, decoder: decoder) {
                    return [packet]
                }
            case "error":
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AGUIClientError.stream("unknown")
                }
                throw AGUIClientError.stream((obj["error"] as? String) ?? "unknown")
            default:
                continue
            }
        }

        throw AGUIClientError.stream("build snapshot unavailable")
    }

    func answerBuildCard(
        cardId: String,
        optionId: String,
        answerText: String? = nil,
        surface: String = "tailnet",
        actor: String = "founder"
    ) async throws -> BuildCardAnswerResponse {
        let body = BuildCardAnswerBody(
            cardId: cardId,
            optionId: optionId,
            answerText: answerText,
            surface: surface,
            actor: actor
        )
        let request = try makeJSONRequest(path: Self.buildCardAnswerPath, body: body)
        return try await sendJSON(request)
    }

    func requestBuild(
        input: String,
        actor: String = "founder"
    ) async throws -> BuildIntentResponse {
        let body = BuildIntentBody(input: input, actor: actor)
        let request = try makeJSONRequest(path: Self.buildRequestPath, body: body)
        return try await sendJSON(request)
    }

    func buildDocument(path: String) async throws -> BuildDocumentResponse {
        let request = try makeGETJSONRequest(
            path: Self.buildDocPath,
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
        let data = try await sendData(request)
        return BuildDocumentResponse.decode(data: data, fallbackPath: path)
    }

    func buildDiff(id: String) async throws -> BuildDiffResponse {
        let request = try makeGETJSONRequest(
            path: Self.buildDiffPath,
            queryItems: [URLQueryItem(name: "id", value: id)]
        )
        return try await sendJSON(request)
    }

    func buildEvidence(
        unitId: String? = nil,
        cardId: String? = nil,
        laneId: String? = nil
    ) async throws -> BuildEvidenceResponse {
        let request = try makeGETJSONRequest(
            path: Self.buildEvidencePath,
            queryItems: [
                URLQueryItem(name: "unitId", value: unitId),
                URLQueryItem(name: "cardId", value: cardId),
                URLQueryItem(name: "laneId", value: laneId),
            ].filter { $0.value?.isEmpty == false }
        )
        return try await sendJSON(request)
    }

    func buildLearned() async throws -> BuildLearnedResponse {
        let request = try makeGETJSONRequest(path: Self.buildLearnedPath)
        return try await sendJSON(request)
    }

    func decideBuildLearned(id: String, decision: BuildLearnedDecision) async throws -> BuildLearnedDecisionResponse {
        let body = BuildLearnedDecisionBody(id: id, decision: decision)
        let request = try makeJSONRequest(path: Self.buildLearnedDecisionPath, body: body)
        return try await sendJSON(request)
    }

    func buildTrust() async throws -> BuildTrustResponse {
        let request = try makeGETJSONRequest(path: Self.buildTrustPath)
        return try await sendJSON(request)
    }

    func buildTrustPairs() async throws -> BuildTrustResponse {
        let request = try makeGETJSONRequest(path: Self.buildTrustPairsPath)
        return try await sendJSON(request)
    }

    func buildLaneLogTail(laneId: String) async throws -> BuildLaneLogTailResponse {
        let request = try makeGETJSONRequest(
            path: Self.buildLaneLogTailPath,
            queryItems: [URLQueryItem(name: "laneId", value: laneId)]
        )
        let data = try await sendData(request)
        return BuildLaneLogTailResponse.decode(data: data, fallbackLaneId: laneId)
    }

    func postBuildSignals(_ batch: CrashSignalBatch) async throws {
        let request = try makeJSONRequest(path: Self.buildSignalsPath, body: batch)
        _ = try await sendData(request)
    }

    func mindArtifacts() async throws -> MindArtifactsResponse {
        let request = try makeGETJSONRequest(path: Self.mindArtifactsPath)
        return try await sendJSON(request)
    }

    func mindEntityDossier(selection: EntityDossierSelection) async throws -> EntityDossierEnvelope {
        let key = selection.key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = selection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryItem = key?.isEmpty == false
            ? URLQueryItem(name: "id", value: key)
            : URLQueryItem(name: "name", value: name)
        let request = try makeGETJSONRequest(path: Self.mindEntityPath, queryItems: [queryItem])
        do {
            return try await sendJSON(request)
        } catch let error as AGUIClientError {
            if error.isHTTP404 {
                return EntityDossierEnvelope(ok: false, error: error.localizedDescription)
            }
            throw error
        }
    }

    func bioArtifacts() async throws -> BioArtifactsResponse {
        let request = try makeGETJSONRequest(path: Self.bioArtifactsPath)
        return try await sendJSON(request)
    }

    func interventionState(id: String) async throws -> BioInterventionStateResponse {
        let request = try makeGETJSONRequest(path: "\(Self.interventionsPath)/\(id)/state")
        return try await sendJSON(request)
    }

    func recordInterventionAct(
        interventionId: String,
        action: String,
        timestamp: Date = Date()
    ) async throws -> BioInterventionActResponse {
        let body = BioInterventionActBody(
            action: action,
            eventAt: Self.isoTimestamp(timestamp),
            source: "ios"
        )
        let request = try makeJSONRequest(
            path: "\(Self.interventionsPath)/\(interventionId)/acts",
            body: body
        )
        return try await sendJSON(request)
    }

    func recordMindVerdict(
        passId: String? = nil,
        date: String? = nil,
        outputType: String,
        outputId: String,
        verdict: MindVerdict
    ) async throws -> MindVerdictResponse {
        let body = MindVerdictBody(
            passId: passId,
            date: date,
            outputType: outputType,
            outputId: outputId,
            verdict: verdict,
            feedback: nil
        )
        let request = try makeJSONRequest(path: Self.mindVerdictPath, body: body)
        return try await sendJSON(request)
    }

    func recordMindFeedback(
        passId: String? = nil,
        date: String? = nil,
        outputType: String,
        outputId: String,
        feedback: MindNudgeFeedback
    ) async throws -> MindVerdictResponse {
        let body = MindVerdictBody(
            passId: passId,
            date: date,
            outputType: outputType,
            outputId: outputId,
            verdict: nil,
            feedback: feedback
        )
        let request = try makeJSONRequest(path: Self.mindVerdictPath, body: body)
        return try await sendJSON(request)
    }

    func cadenceDay() async throws -> CadenceDayEnvelope {
        let request = try makeGETJSONRequest(path: Self.cadenceDayPath)
        return try await sendJSON(request)
    }

    func bodySummary() async throws -> BodySummary {
        let request = try makeGETJSONRequest(path: Self.bodySummaryPath)
        return try await sendJSON(request)
    }

    func bodyCueContext() async throws -> BodyCueContext {
        let request = try makeGETJSONRequest(path: Self.bodyCueContextPath)
        return try await sendJSON(request)
    }

    func bodyLog(days: Int = 7) async throws -> BioLogEnvelope {
        let clampedDays = max(1, min(days, 30))
        let request = try makeGETJSONRequest(
            path: Self.bodyLogPath,
            queryItems: [URLQueryItem(name: "days", value: String(clampedDays))]
        )
        return try await sendJSON(request)
    }

    func recordCadenceAct(
        blockId: String,
        action: CadenceBlockAction,
        eventAt: Date? = nil,
        date: String? = nil
    ) async throws -> CadenceActResponse {
        let body = CadenceActBody(
            blockId: blockId,
            action: action,
            eventAt: eventAt.map(Self.isoTimestamp),
            date: date
        )
        let request = try makeJSONRequest(path: Self.cadenceActsPath, body: body)
        return try await sendJSON(request)
    }

    func recordCadenceWakeInit(eventAt: Date? = nil, date: String? = nil) async throws -> CadenceActResponse {
        let body = CadenceWakeInitActBody(
            action: .wakeInit,
            eventAt: eventAt.map(Self.isoTimestamp),
            date: date
        )
        let request = try makeJSONRequest(path: Self.cadenceActsPath, body: body)
        return try await sendJSON(request)
    }

    func recordCadenceChecklistAct(blockId: String, itemId: String, done: Bool) async throws -> CadenceActResponse {
        let body = CadenceChecklistActBody(blockId: blockId, action: "checklist", itemId: itemId, done: done)
        let request = try makeJSONRequest(path: Self.cadenceActsPath, body: body)
        return try await sendJSON(request)
    }

    func cadenceRetro() async throws -> CadenceRetroResponse {
        let request = try makeGETJSONRequest(path: Self.cadenceRetroPath)
        return try await sendJSON(request)
    }

    func cadenceReviewCards(status: String = "open") async throws -> CadenceReviewCardsResponse {
        let request = try makeGETJSONRequest(
            path: Self.cadenceReviewCardsPath,
            queryItems: [URLQueryItem(name: "status", value: status)]
        )
        return try await sendJSON(request)
    }

    func adminBandish() async throws -> AdminBandishResponse {
        let request = try makeGETJSONRequest(path: Self.adminBandishPath)
        return try await sendJSON(request)
    }

    func adminItems() async throws -> AdminBandishResponse {
        let request = try makeGETJSONRequest(path: Self.adminItemsPath)
        return try await sendJSON(request)
    }

    func parseAdminIntake(text: String) async throws -> AdminParseResponse {
        let request = try makeJSONRequest(path: Self.adminIntakePath, body: AdminIntakeBody(text: text))
        return try await sendJSON(request)
    }

    func confirmAdminIntake(
        fields: [String: ViewPacketJSONValue],
        confirmToken: String? = nil
    ) async throws -> AdminMutationResponse {
        let request = try makeJSONRequest(
            path: Self.adminConfirmPath,
            body: AdminConfirmBody(fields: fields, confirmToken: confirmToken)
        )
        return try await sendJSON(request)
    }

    func answerCadenceReviewCard(
        cardId: String,
        answers: [String: String] = [:],
        surface: String = "tailnet",
        actor: String = "founder"
    ) async throws -> CadenceReviewAnswerResponse {
        let body = CadenceReviewAnswerBody(
            cardId: cardId,
            answers: answers,
            surface: surface,
            actor: actor
        )
        let request = try makeJSONRequest(path: Self.cadenceReviewCardsPath, body: body)
        return try await sendJSON(request)
    }

    func answerCadenceValueProbe(
        cardId: String,
        probeId: String,
        selectedOptionId: String
    ) async throws -> CadenceReviewAnswerResponse {
        let body = CadenceValueProbeAnswerBody(
            cardId: cardId,
            answers: [
                CadenceValueProbeSubmittedAnswer(
                    probeId: probeId,
                    selectedOptionId: selectedOptionId
                ),
            ]
        )
        let request = try makeJSONRequest(path: Self.cadenceValueProbeAnswersPath, body: body)
        return try await sendJSON(request)
    }

    func suppressedCadenceNudgesToday() async throws -> CadenceSuppressedNudgesResponse {
        let request = try makeGETJSONRequest(path: Self.cadenceSuppressedNudgesPath)
        return try await sendJSON(request)
    }

    func recordCadenceNudgeDisposition(
        id: String,
        disposition: CadenceNudgeDisposition
    ) async throws -> CadenceNudgeDispositionResponse {
        let body = CadenceNudgeDispositionBody(id: id, disposition: disposition)
        let request = try makeJSONRequest(path: Self.cadenceNudgeDispositionPath, body: body)
        return try await sendJSON(request)
    }

    func cadenceRescore() async throws -> CadenceRescoreResponse {
        let request = try makeGETJSONRequest(path: Self.cadenceRescorePath)
        return try await sendJSON(request)
    }

    func recordCadenceRescoreCompare(
        date: String,
        blockId: String,
        better: Bool
    ) async throws -> CadenceRescoreCompareResponse {
        let body = CadenceRescoreCompareBody(date: date, blockId: blockId, better: better)
        let request = try makeJSONRequest(path: Self.cadenceRescoreComparePath, body: body)
        return try await sendJSON(request)
    }

    func recordCadenceNudgeAct(_ act: CadenceNudgeActDescriptor) async throws -> CadenceNudgeDispositionResponse {
        guard act.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "POST",
              !act.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AGUIClientError.invalidResponse
        }
        let request = try makeJSONRequest(path: act.path, body: act.body)
        return try await sendJSON(request)
    }

    func recordBodyInterventionFeedback(
        interventionId: String,
        action: BodyInterventionFeedbackAction,
        packetId: String? = nil,
        timestamp: Date = Date()
    ) async throws -> BodyInterventionFeedbackResponse {
        let body = BodyInterventionFeedbackBody(
            interventionId: interventionId,
            action: action,
            packetId: packetId,
            timestamp: Self.isoTimestamp(timestamp)
        )
        let request = try makeJSONRequest(path: Self.bodyInterventionsFeedbackPath, body: body)
        return try await sendJSON(request)
    }

    func recordBodyMeal(
        meal: MealMacroMeasurements,
        timestamp: Date = Date()
    ) async throws -> BodyMealLogResponse {
        guard meal.hasMeasurement else { throw AGUIClientError.invalidResponse }
        let body = BodyMealLogBody(
            timestamp: Self.isoTimestamp(timestamp),
            meal: meal
        )
        let request = try makeJSONRequest(path: Self.bodyMealPath, body: body)
        return try await sendJSON(request)
    }

    func recordBodyMealPhoto(
        imageBase64: String,
        caption: String? = nil
    ) async throws -> BioLogPostResponse {
        let trimmedImage = imageBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else { throw AGUIClientError.invalidResponse }
        let body = BodyMealPhotoPostBody(
            imageBase64: trimmedImage,
            caption: Self.normalized(caption)
        )
        let request = try makeJSONRequest(path: Self.bodyMealPhotoPath, body: body)
        return try await sendJSON(request)
    }

    func recordBodyLog(
        kind: BioLogKind,
        text: String,
        at: Date? = nil
    ) async throws -> BioLogPostResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AGUIClientError.invalidResponse }
        let body = BodyLogPostBody(
            kind: kind.rawValue,
            text: trimmed,
            at: at.map(Self.isoTimestamp)
        )
        let request = try makeJSONRequest(path: Self.bodyLogPath, body: body)
        return try await sendJSON(request)
    }

    func completeAdminItem(
        id: String,
        actionPath: String? = nil
    ) async throws -> AdminMutationResponse {
        let request = try makeJSONRequest(
            path: actionPath ?? "\(Self.adminItemsPath)/\(id)/complete",
            body: AdminItemActionBody(id: id, action: "complete", remindAt: nil, dueAt: nil)
        )
        return try await sendJSON(request)
    }

    func rescheduleAdminItem(
        id: String,
        remindAt: String?,
        dueAt: String?,
        actionPath: String? = nil
    ) async throws -> AdminMutationResponse {
        let request = try makeJSONRequest(
            path: actionPath ?? "\(Self.adminItemsPath)/\(id)/reschedule",
            body: AdminItemActionBody(id: id, action: "reschedule", remindAt: remindAt, dueAt: dueAt)
        )
        return try await sendJSON(request)
    }

    private func makeAGUIRequest(body: Data) throws -> URLRequest {
        let url = try endpointURL(path: "/api/agui/message")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = body
        return request
    }

    private func makeBuildEventsRequest(lastEventID: String? = nil) throws -> URLRequest {
        let url = try endpointURL(path: Self.buildEventsPath)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventID, !lastEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }
        request.timeoutInterval = 120
        return request
    }

    private func makeAGUIEventsRequest(recentPacketLimit: Int, lastEventID: String? = nil) throws -> URLRequest {
        let url = try endpointURL(
            path: Self.aguiEventsPath,
            queryItems: [URLQueryItem(name: "packets", value: String(max(0, recentPacketLimit)))]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventID, !lastEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }
        request.timeoutInterval = 120
        return request
    }

    private func makeJSONRequest<T: Encodable>(path: String, body: T) throws -> URLRequest {
        let url = try endpointURL(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func makeGETJSONRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let url = try endpointURL(path: path, queryItems: queryItems)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return request
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base), components.scheme != nil else {
            throw AGUIClientError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { throw AGUIClientError.invalidURL }
        return url
    }

    private func stream(
        request: URLRequest,
        onEvent: @escaping @MainActor (AGUIStreamEvent) -> Void
    ) async throws -> AGUIOutcome {
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else { throw AGUIClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AGUIClientError.httpStatus(http.statusCode) }

        let decoder = JSONDecoder()
        var event = ""
        var latestPacket: ViewPacket?

        for try await line in lineResponse.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8) else { continue }

            switch event {
            case "packet", "chat.worker", "worker", "task", "task_packet":
                if case .packet(let packet) = try Self.decodeStreamEvent(named: event, data: data, decoder: decoder) {
                    latestPacket = packet
                    await onEvent(.packet(packet))
                }
            case "packet_patch":
                if case .patch(let patch) = try Self.decodeStreamEvent(named: event, data: data, decoder: decoder) {
                    if let packet = latestPacket {
                        latestPacket = applyPacketPatch(patch, to: packet)
                    }
                    await onEvent(.patch(patch))
                }
            case "done":
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AGUIClientError.stream("invalid done event")
                }
                return AGUIOutcome(
                    packet: latestPacket,
                    packetId: obj["packetId"] as? String,
                    lane: obj["lane"] as? String,
                    sensitivity: obj["sensitivity"] as? String,
                    sovereign: (obj["sovereign"] as? Bool) ?? false,
                    steps: obj["steps"] as? Int,
                    held: Self.heldValue(from: obj["held"])
                )
            case "error":
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AGUIClientError.stream("unknown")
                }
                if (obj["error"] as? String) == "sovereign_lane_unavailable" {
                    throw AGUIClientError.sovereignUnavailable(silenced: (obj["silenced"] as? Bool) ?? true)
                }
                throw AGUIClientError.stream((obj["error"] as? String) ?? "unknown")
            default:
                continue
            }
        }

        if let latestPacket {
            return AGUIOutcome(
                packet: latestPacket,
                packetId: latestPacket.id,
                lane: nil,
                sensitivity: nil,
                sovereign: false,
                steps: nil,
                held: false
            )
        }
        throw AGUIClientError.stream("stream ended before completion")
    }

    private func sendJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await sendData(request)
        guard !data.isEmpty else { throw AGUIClientError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else {
            throw AGUIClientError.invalidResponse
        }

        var lines: [String] = []
        for try await line in lineResponse.lines {
            lines.append(line)
        }

        let body = lines.joined(separator: "\n")
        let data = Data(body.utf8)
        guard (200...299).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
               !envelope.error.isEmpty {
                throw AGUIClientError.apiError(status: http.statusCode, message: envelope.error)
            }
            throw AGUIClientError.httpStatus(http.statusCode)
        }

        return data
    }

    static func actionInvokeBody(packet: ViewPacket, action: ViewPacketAction) throws -> Data {
        let body = ActionInvokeBody(
            packetId: packet.id,
            action: ActionInvokeBody.Action(
                id: action.invokeActionId,
                intent: action.invokeIntent,
                args: action.invokeArgs
            )
        )
        return try JSONEncoder().encode(body)
    }

    private static func heldValue(from value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let array = value as? [Any] { return !array.isEmpty }
        return false
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func decodeSSEFrame(
        _ frame: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AGUIStreamEvent? {
        var event = "message"
        var dataLines: [String] = []

        for rawLine in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
            }
        }

        guard !dataLines.isEmpty else { return nil }
        guard let data = dataLines.joined(separator: "\n").data(using: .utf8) else { return nil }
        return try decodeStreamEvent(named: event, data: data, decoder: decoder)
    }

    static func decodeStreamEvent(
        named event: String,
        data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AGUIStreamEvent? {
        switch event {
        case "snapshot", "build.snapshot", "build_snapshot":
            return .snapshot(try decodeBuildSnapshot(data, decoder: decoder))
        case "packet":
            return .packet(try decoder.decode(ViewPacket.self, from: data))
        case "chat.worker", "worker", "task", "task_packet":
            return .packet(try decodeChatWorkerPacket(data, decoder: decoder))
        case "packet_patch":
            return .patch(try decoder.decode(ViewPacketPatch.self, from: data))
        default:
            return nil
        }
    }

    private static func decodeChatWorkerPacket(
        _ data: Data,
        decoder: JSONDecoder
    ) throws -> ViewPacket {
        if let packet = try? decoder.decode(ViewPacket.self, from: data) {
            if packet.viewType == "chat.worker" { return packet }
            return ViewPacket(
                id: packet.id,
                viewType: "chat.worker",
                text: packet.text,
                fields: packet.fields,
                children: packet.children,
                action: packet.action,
                score: packet.score,
                evidence: packet.evidence,
                evidencePreviews: packet.evidencePreviews,
                siblings: packet.siblings,
                confidence: packet.confidence,
                provenance: packet.provenance,
                surfaceDecision: packet.surfaceDecision,
                frontierExcluded: packet.frontierExcluded
            )
        }

        let fields = try decoder.decode([String: ViewPacketJSONValue].self, from: data)
        let taskId = fields["taskId"]?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fields["task_id"]?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fields["id"]?.description.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? UUID().uuidString
        return ViewPacket(
            id: "chat-worker-\(taskId)",
            viewType: "chat.worker",
            fields: fields,
            provenance: ["surface": .string("chat")],
            frontierExcluded: false
        )
    }

    private static func decodeBuildSnapshot(
        _ data: Data,
        decoder: JSONDecoder
    ) throws -> [ViewPacket] {
        if let packets = try? decoder.decode([ViewPacket].self, from: data) {
            return packets
        }
        if let packet = try? decoder.decode(ViewPacket.self, from: data) {
            return [packet]
        }
        return try decoder.decode(BuildSnapshotEnvelope.self, from: data).packets
    }
}

private struct ActionInvokeBody: Encodable {
    let type = AGUIClient.actionInvokeType
    let packetId: String
    let action: Action

    struct Action: Encodable {
        let id: String?
        let intent: String
        let args: [String: ViewPacketJSONValue]
    }
}

private struct BuildCardAnswerBody: Encodable {
    let cardId: String
    let optionId: String
    let answerText: String?
    let surface: String
    let actor: String

    enum CodingKeys: String, CodingKey {
        case cardId
        case optionId
        case answerText
        case surface
        case actor
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cardId, forKey: .cardId)
        try container.encode(optionId, forKey: .optionId)
        try container.encodeIfPresent(answerText, forKey: .answerText)
        try container.encode(surface, forKey: .surface)
        try container.encode(actor, forKey: .actor)
    }
}

private struct BuildIntentBody: Encodable {
    let input: String
    let actor: String
}

private struct BuildLearnedDecisionBody: Encodable {
    let id: String
    let decision: BuildLearnedDecision
}

private struct MindVerdictBody: Encodable {
    let passId: String?
    let date: String?
    let outputType: String
    let outputId: String
    let verdict: MindVerdict?
    let feedback: MindNudgeFeedback?
}

private struct CadenceActBody: Encodable {
    let blockId: String
    let action: CadenceBlockAction
    let eventAt: String?
    let date: String?
}

private struct CadenceWakeInitActBody: Encodable {
    let action: CadenceBlockAction
    let eventAt: String?
    let date: String?
}

private struct CadenceChecklistActBody: Encodable {
    let blockId: String
    let action: String
    let itemId: String
    let done: Bool
}

private struct CadenceReviewAnswerBody: Encodable {
    let cardId: String
    let answers: [String: String]
    let surface: String
    let actor: String
}

private struct CadenceValueProbeAnswerBody: Encodable {
    let cardId: String
    let answers: [CadenceValueProbeSubmittedAnswer]
}

private struct CadenceValueProbeSubmittedAnswer: Encodable {
    let probeId: String
    let selectedOptionId: String
}

private struct CadenceNudgeDispositionBody: Encodable {
    let id: String
    let disposition: CadenceNudgeDisposition
}

private struct CadenceRescoreCompareBody: Encodable {
    let date: String
    let blockId: String
    let better: Bool
}

private struct BodyInterventionFeedbackBody: Encodable {
    let interventionId: String
    let action: BodyInterventionFeedbackAction
    let packetId: String?
    let timestamp: String
}

private struct BioInterventionActBody: Encodable {
    let action: String
    let eventAt: String
    let source: String
}

struct BioInterventionStateResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var id: String?
    var actionState: String?
    var currentPhase: Int?
    var error: String?
}

struct BioInterventionActResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var created: Bool?
    var record: Record?
    var error: String?

    struct Record: Decodable, Equatable, Sendable {
        var action: String?
        var actionState: String?
    }
}

private struct BodyMealLogBody: Encodable {
    let eventType = "nutrition_log"
    let source = "ios"
    let timestamp: String
    let meal: MealMacroMeasurements

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case source
        case timestamp
        case meal
    }
}

private struct BodyMealPhotoPostBody: Encodable {
    let imageBase64: String
    let caption: String?
}

private struct BodyLogPostBody: Encodable {
    let kind: String
    let text: String
    let at: String?
}

private struct AdminIntakeBody: Encodable {
    let text: String
}

private struct AdminConfirmBody: Encodable {
    let fields: [String: ViewPacketJSONValue]
    let confirmToken: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AdminDynamicCodingKey.self)
        for (key, value) in fields {
            try container.encode(value, forKey: AdminDynamicCodingKey(key))
        }
        if let confirmToken {
            try container.encode(confirmToken, forKey: AdminDynamicCodingKey("confirmToken"))
        }
    }
}

private struct AdminItemActionBody: Encodable {
    let id: String
    let action: String
    let remindAt: String?
    let dueAt: String?
}

private struct AdminDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: String
}

private struct BuildSnapshotEnvelope: Decodable {
    var packets: [ViewPacket]

    enum CodingKeys: String, CodingKey {
        case packet
        case packets
        case status
        case cards
        case openCards
        case history
        case plans
        case units
        case lanes
        case generatedAt
        case counts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded: [ViewPacket] = []

        if let packet = try? container.decode(ViewPacket.self, forKey: .packet) {
            decoded.append(packet)
        }
        if let packets = try? container.decode([ViewPacket].self, forKey: .packets) {
            decoded.append(contentsOf: packets)
        }
        if let status = try? container.decode(ViewPacket.self, forKey: .status) {
            decoded.append(status)
        }
        if let cards = try? container.decode([ViewPacket].self, forKey: .cards) {
            decoded.append(contentsOf: cards)
        }
        if let openCards = try? container.decode([ViewPacket].self, forKey: .openCards) {
            decoded.append(contentsOf: openCards)
        }
        if let history = try? container.decode([ViewPacket].self, forKey: .history) {
            decoded.append(contentsOf: history)
        }

        let units = (try? container.decode([ViewPacketJSONValue].self, forKey: .units)) ?? []
        let lanes = (try? container.decode([ViewPacketJSONValue].self, forKey: .lanes)) ?? []
        if let plans = try? container.decode([ViewPacketJSONValue].self, forKey: .plans) {
            decoded.append(contentsOf: Self.statusPackets(from: plans, units: units, lanes: lanes, container: container))
        } else if !units.isEmpty || !lanes.isEmpty {
            decoded.append(Self.statusPacket(plan: nil, units: units, lanes: lanes, index: 0, container: container))
        }

        if let cards = try? container.decode([BuildCard].self, forKey: .cards) {
            decoded.append(contentsOf: cards.map(\.packet))
        }
        if let openCards = try? container.decode([BuildCard].self, forKey: .openCards) {
            decoded.append(contentsOf: openCards.map(\.packet))
        }

        packets = decoded
    }

    private static func statusPackets(
        from plans: [ViewPacketJSONValue],
        units allUnits: [ViewPacketJSONValue],
        lanes allLanes: [ViewPacketJSONValue],
        container: KeyedDecodingContainer<CodingKeys>
    ) -> [ViewPacket] {
        plans.enumerated().map { index, plan in
            let planId = plan.objectValue?["id"]?.description
            let planUnits = units(for: plan, planId: planId, fallback: allUnits)
            let unitIDs = Set(planUnits.compactMap { unit in
                unit.objectValue?["id"]?.description
                    ?? unit.objectValue?["unitId"]?.description
            })
            let lanes = allLanes.filter { lane in
                let lanePlanId = lane.objectValue?["planId"]?.description
                let laneUnitId = lane.objectValue?["unitId"]?.description
                if let planId, lanePlanId == planId { return true }
                guard let laneUnitId else { return false }
                return unitIDs.contains(laneUnitId)
            }
            return statusPacket(plan: plan, units: planUnits, lanes: lanes, index: index, container: container)
        }
    }

    private static func units(
        for plan: ViewPacketJSONValue,
        planId: String?,
        fallback: [ViewPacketJSONValue]
    ) -> [ViewPacketJSONValue] {
        if let planUnits = plan.objectValue?["units"]?.arrayValue {
            return planUnits
        }
        guard let planId else { return fallback }
        return fallback.filter { $0.objectValue?["planId"]?.description == planId }
    }

    private static func statusPacket(
        plan: ViewPacketJSONValue?,
        units: [ViewPacketJSONValue],
        lanes: [ViewPacketJSONValue],
        index: Int,
        container: KeyedDecodingContainer<CodingKeys>
    ) -> ViewPacket {
        let planObject = plan?.objectValue
        let planId = planObject?["id"]?.description
        let title = planObject?["title"]?.description
            ?? planObject?["name"]?.description
            ?? planId
            ?? "build status"
        let state = planObject?["status"] ?? planObject?["state"]
        var fields: [String: ViewPacketJSONValue] = [
            "title": .string(title),
            "units": .array(units),
            "lanes": .array(lanes),
        ]
        if let plan {
            fields["plan"] = plan
        }
        if let state {
            fields["status"] = state
        }
        if let generatedAt = try? container.decode(String.self, forKey: .generatedAt) {
            fields["updatedAt"] = .string(generatedAt)
        }
        if let counts = try? container.decode(ViewPacketJSONValue.self, forKey: .counts) {
            fields["counts"] = counts
        }

        return ViewPacket(
            id: "build-status-\(planId ?? "snapshot-\(index)")",
            viewType: "build.status",
            text: title,
            fields: fields,
            provenance: [
                "surface": .string("build"),
                "lane": .string("daemon"),
                "plane": .string("agent"),
                "module": .string("build-snapshot"),
            ],
            frontierExcluded: true
        )
    }
}
