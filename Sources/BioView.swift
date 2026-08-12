import Foundation
import PhotosUI
import SwiftUI
import UIKit

enum BioAccessibility {
    static let view = "bio-view"
    static let stateSelector = "bio-state-selector"
    static let logSubmit = "bio-log-submit"
    static let mealPhoto = "bio-meal-photo"
    static let mealCapture = "bio-meal-capture"
    static let mealMicronutrients = "bio-meal-micronutrients"
    static let nutritionQuickActs = "bio-nutrition-quick-acts"

    static func nutritionCalendarDay(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "bio-calendar-day-\(formatter.string(from: day))"
    }

    static func nutritionMeal(_ id: String) -> String {
        "bio-nutrition-meal-\(id)"
    }

    static func nutritionMealPhotoSlot(_ id: String) -> String {
        "bio-nutrition-meal-photo-\(id)"
    }

    static func nutritionMealMacros(_ id: String) -> String {
        "bio-nutrition-meal-macros-\(id)"
    }

    static func nutritionMealMicroRow(_ id: String) -> String {
        "bio-nutrition-meal-micros-\(id)"
    }

    static func stateSelectorItem(_ state: BioState) -> String {
        "bio-state-\(state.rawValue)"
    }

    static func stateContent(_ state: BioState) -> String {
        "bio-state-content-\(state.rawValue)"
    }

    static func intervention(_ id: String) -> String {
        "bio-intervention-\(id)"
    }

    static func protocolRow(_ id: String) -> String {
        "bio-protocol-\(id)"
    }

    static func biomarker(_ id: String) -> String {
        "bio-biomarker-\(id)"
    }

    static let biomarkerDetail = "bio-biomarker-detail"
    static let biomarkerRangeBand = "bio-biomarker-range-band"
    static let biomarkerHistory = "bio-biomarker-history"
    static let protocolDomainSelector = "bio-protocol-domain-selector"
    static let protocolDetail = "bio-protocol-detail"
    static let protocolCoverageRing = "bio-protocol-coverage-ring"
    static let meditationDetail = "bio-meditation-detail"
    static let biomarkerSources = "bio-biomarker-sources"
    static let interventionStopError = "bio-intervention-stop-error"
    static let interventionStopRetry = "bio-intervention-stop-retry"

    static func testingProtocol(_ id: String) -> String {
        "bio-testing-protocol-\(id)"
    }

    static func meditationProtocol(_ id: String) -> String {
        "bio-meditation-protocol-\(id)"
    }
}

enum BioState: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case overview
    case biomarkers
    case protocols
    case interventions
    case nutrition

    var id: String { rawValue }
}

enum BioStateAvailability {
    // Founder ruling 2026-08-04: the availability gating and the protocols hard-off
    // are retired. All five tabs always render; an empty tab shows its honest empty
    // state rather than being hidden. The register is fixed, not data-derived.
    static var allStates: [BioState] { BioState.allCases }

    // Founder ruling 2026-08-04: bio always opens on nutrition.
    static let defaultState: BioState = .nutrition
}

enum BioInitialState {
    // The opening sub-tab. Defaults to nutrition; a `-biotab <state>` launch argument
    // overrides it (used by the audit/screenshot harness to land on any tab directly).
    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> BioState {
        guard let index = arguments.firstIndex(of: "-biotab"),
              arguments.indices.contains(index + 1),
              let state = BioState(rawValue: arguments[index + 1].trimmingCharacters(in: .whitespaces).lowercased())
        else { return BioStateAvailability.defaultState }
        return state
    }
}

enum BioCameraStageRequest {
    static func isRequested(for state: BioState) -> Bool {
        state == .nutrition
    }
}

enum BioMarker: String, CaseIterable, Identifiable, Equatable, Sendable {
    case recovery
    case sleep
    case hrv

    var id: String { rawValue }
}

// The six body systems the overview grid renders (cursafe v11 · 3×2). The register is
// fixed; each card is populated only when the model genuinely holds a backing metric,
// otherwise it shows the honest "baseline pending" state — silence over fabrication.
enum BioSystem: String, CaseIterable, Identifiable, Equatable, Sendable {
    case heart
    case sleep
    case blood
    case gut
    case muscles
    case brain

    var id: String { rawValue }

    // The metric that drives the headline number, named for the provenance drill.
    var metricLabel: String {
        switch self {
        case .heart:
            return "recovery"
        case .sleep:
            return "sleep"
        case .blood:
            return "blood panel"
        case .gut:
            return "gut"
        case .muscles:
            return "training load"
        case .brain:
            return "focus"
        }
    }
}

enum BioSystemTone: Equatable, Sendable {
    case steady   // at or near your baseline
    case watch    // materially off your baseline — worth a glance
    case pending  // no baseline exists yet

    var word: String {
        switch self {
        case .steady:
            return "steady"
        case .watch:
            return "watch"
        case .pending:
            return "baseline pending"
        }
    }

    var signal: KSignal {
        switch self {
        case .steady:
            return .live
        case .watch:
            return .attention
        case .pending:
            return .idle
        }
    }

    static func derive(deltaPct: Double?) -> BioSystemTone {
        guard let deltaPct, abs(deltaPct) >= BioSystemCard.watchDeltaThreshold else { return .steady }
        return .watch
    }
}

struct BioSystemCard: Identifiable, Equatable, Sendable {
    var system: BioSystem
    var scoreText: String
    var tone: BioSystemTone
    var freshnessText: String
    var provenanceText: String
    var isStale: Bool
    var hasData: Bool

    var id: String { system.rawValue }

    static let watchDeltaThreshold = 12.0
    static let noScore = "—"
    static let pendingProvenance = "no score until a baseline exists — silence beats a fabricated number"

    static func pending(_ system: BioSystem) -> BioSystemCard {
        BioSystemCard(
            system: system,
            scoreText: noScore,
            tone: .pending,
            freshnessText: "no data yet",
            provenanceText: pendingProvenance,
            isStale: false,
            hasData: false
        )
    }

    static func make(
        _ system: BioSystem,
        metric: BioTodayMetric?,
        secondary: (label: String, metric: BioTodayMetric?)? = nil
    ) -> BioSystemCard {
        guard let metric, let value = metric.primaryValue, value.isFinite else {
            return .pending(system)
        }
        let scoreText = BioNumberText.significant(value)
        let source = BioMetricSource(wireValue: metric.source)?.chipText
        let recency = normalizedNonEmpty(metric.label)
        let freshness = [source, recency].compactMap { $0 }.joined(separator: " · ")
        var inputs = ["\(system.metricLabel) \(scoreText)"]
        if let secondary, let value = secondary.metric?.primaryValue, value.isFinite {
            inputs.append("\(secondary.label) \(BioNumberText.significant(value))")
        }
        let provenance = "in: " + inputs.joined(separator: " · ") + (source.map { " (\($0))" } ?? "")
        return BioSystemCard(
            system: system,
            scoreText: scoreText,
            tone: BioSystemTone.derive(deltaPct: metric.deltaPct),
            freshnessText: freshness.isEmpty ? "no data yet" : freshness,
            provenanceText: provenance,
            isStale: BioRecency.isStale(label: metric.label),
            hasData: true
        )
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

// Parses a daemon recency label ("9d ago", "3h ago", "today") into an age in days so a
// stale metric can age-fade. Unparseable → nil → treated as fresh (fail safe, never a
// false staleness claim).
enum BioRecency {
    static let staleThresholdDays = 2.0

    static func isStale(label: String?) -> Bool {
        guard let ageDays = ageDays(from: label) else { return false }
        return ageDays >= staleThresholdDays
    }

    static func ageDays(from label: String?) -> Double? {
        guard let raw = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else { return nil }
        if raw.contains("now") || raw.contains("today") || raw.contains("realtime") { return 0 }
        if raw.contains("yesterday") { return 1 }

        let firstDigitDrop = raw.drop { !$0.isNumber }
        let numberPart = firstDigitDrop.prefix { $0.isNumber || $0 == "." }
        guard let magnitude = Double(numberPart), magnitude.isFinite else { return nil }
        let unit = firstDigitDrop.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces)

        if unit.hasPrefix("mo") || unit.contains("month") { return magnitude * 30 }
        if unit.hasPrefix("y") || unit.contains("year") { return magnitude * 365 }
        if unit.hasPrefix("w") || unit.contains("week") { return magnitude * 7 }
        if unit.hasPrefix("d") || unit.contains("day") { return magnitude }
        if unit.hasPrefix("h") || unit.contains("hour") { return magnitude / 24 }
        if unit.hasPrefix("min") || unit.hasPrefix("m") { return magnitude / 1_440 }
        return nil
    }
}

enum BioMetricSource: Equatable, Sendable {
    case whoopAPI
    case whoopBLE
    case healthKit

    init?(wireValue: String?) {
        guard let value = wireValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !value.isEmpty
        else {
            return nil
        }

        switch value {
        case "whoop-api":
            self = .whoopAPI
        case "whoop-ble":
            self = .whoopBLE
        case "healthkit":
            self = .healthKit
        default:
            return nil
        }
    }

    var chipText: String {
        switch self {
        case .whoopAPI:
            return "whoop api"
        case .whoopBLE:
            return "whoop ble"
        case .healthKit:
            return "healthkit"
        }
    }
}

enum BioLogKind: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case meal
    case note

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = Self(rawValue: value ?? "") ?? .note
    }
}

struct MealMicronutrient: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let amount: Double
    let unit: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case label
        case name
        case nutrient
        case amount
        case value
        case quantity
        case unit
        case units
        case confidence
        case confidenceScore
    }

    init(
        id: String,
        label: String,
        amount: Double,
        unit: String,
        confidence: Double
    ) {
        self.id = Self.normalized(id)
        self.label = Self.normalized(label)
        self.amount = amount
        self.unit = Self.normalized(unit)
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = Self.firstString(in: container, keys: [.id, .key, .name, .label, .nutrient])
        let label = Self.firstString(in: container, keys: [.label, .name, .nutrient, .id, .key])
        let amount = Self.firstDouble(in: container, keys: [.amount, .value, .quantity])
        let unit = Self.firstString(in: container, keys: [.unit, .units])
        let confidence = Self.firstDouble(in: container, keys: [.confidence, .confidenceScore])
        guard let id,
              let label,
              let amount,
              amount.isFinite,
              amount >= 0,
              let unit,
              let confidence,
              confidence.isFinite,
              (0...1).contains(confidence)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "invalid meal micronutrient"
            )
        }

        self.init(
            id: id,
            label: label,
            amount: amount,
            unit: unit,
            confidence: confidence
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(amount, forKey: .amount)
        try container.encode(unit, forKey: .unit)
        try container.encode(confidence, forKey: .confidence)
    }

    /// Numeric text is always resolved through the shared bio formatter. Units stay
    /// attached to the payload value; no conversion or %DV inference happens here.
    var valueText: String {
        "\(BioNumberText.significant(amount)) \(unit)"
    }

    var isRenderable: Bool {
        !id.isEmpty
            && !label.isEmpty
            && !unit.isEmpty
            && amount.isFinite
            && amount >= 0
            && confidence.isFinite
            && (0...1).contains(confidence)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func firstString<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeTrimmedString(for: key) {
                return value
            }
        }
        return nil
    }

    private static func firstDouble<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decodeFlexibleDouble(for: key) {
                return value
            }
        }
        return nil
    }
}

/// The daemon's canonical projection is an array. `micros` is accepted only when
/// each map value still carries the closed quantity/unit/confidence shape, so a bare
/// percentage dictionary cannot silently become a meal fact.
private enum MealMicronutrientPayload {
    static func hasNonNullValue<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Bool {
        keys.contains { key in
            container.contains(key) && (try? container.decodeNil(forKey: key)) != true
        }
    }

    static func decode<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> [MealMicronutrient]? {
        for key in keys where container.contains(key) {
            if (try? container.decodeNil(forKey: key)) == true {
                continue
            }
            do {
                let values = try container.decodeIfPresent(
                    BioLossyArray<MealMicronutrient>.self,
                    forKey: key
                )
                return values?.elements
            } catch {
                // A legacy `micros` object is handled below. Invalid values remain
                // silent rather than becoming guessed nutrients.
            }

            do {
                let values = try container.decodeIfPresent(
                    [String: MealMicronutrientMapValue].self,
                    forKey: key
                )
                return values?.keys.sorted().compactMap { id in
                    values?[id]?.nutrient(id: id)
                }
            } catch {
                return []
            }
        }
        return nil
    }
}

private struct MealMicronutrientMapValue: Decodable {
    private let amount: Double?
    private let unit: String?
    private let confidence: Double?
    private let label: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case name
        case amount
        case value
        case quantity
        case unit
        case units
        case confidence
        case confidenceScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = Self.firstDouble(in: container, keys: [.amount, .value, .quantity])
        unit = Self.firstString(in: container, keys: [.unit, .units])
        confidence = Self.firstDouble(in: container, keys: [.confidence, .confidenceScore])
        label = Self.firstString(in: container, keys: [.label, .name, .id])
    }

    func nutrient(id: String) -> MealMicronutrient? {
        guard let amount, let unit, let confidence else { return nil }
        let nutrient = MealMicronutrient(
            id: id,
            label: label ?? id,
            amount: amount,
            unit: unit,
            confidence: confidence
        )
        return nutrient.isRenderable ? nutrient : nil
    }

    private static func firstString<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeTrimmedString(for: key) {
                return value
            }
        }
        return nil
    }

    private static func firstDouble<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Double? {
        for key in keys {
            if let value = try? container.decodeFlexibleDouble(for: key) {
                return value
            }
        }
        return nil
    }
}

enum MealMicronutrientText {
    static func compactLine(for nutrients: [MealMicronutrient]) -> String? {
        var seenIDs: Set<String> = []
        let values = nutrients.filter { nutrient in
            nutrient.isRenderable && seenIDs.insert(nutrient.id).inserted
        }
        guard !values.isEmpty else { return nil }
        return values.map { "\($0.label) \($0.valueText)" }.joined(separator: " · ")
    }
}

protocol MealMicronutrientsSource: Sendable {
    func micronutrients(for mealID: String) -> [MealMicronutrient]
    func micronutrients(for meal: BioLogEntry) -> [MealMicronutrient]
}

extension MealMicronutrientsSource {
    func micronutrients(for mealID: String) -> [MealMicronutrient] {
        []
    }

    func micronutrients(for meal: BioLogEntry) -> [MealMicronutrient] {
        meal.micronutrients ?? micronutrients(for: meal.id)
    }
}

struct FixtureMealMicronutrientsSource: MealMicronutrientsSource, Sendable {
    enum Fixture: String, CaseIterable, Sendable {
        case typical
        case sparse
        case empty
    }

    let values: [MealMicronutrient]

    init(fixture: Fixture = .typical) {
        let payload: Data
        switch fixture {
        case .typical:
            payload = Self.typicalPayload
        case .sparse:
            payload = Self.sparsePayload
        case .empty:
            payload = Self.emptyPayload
        }
        values = (try? JSONDecoder().decode([MealMicronutrient].self, from: payload)) ?? []
    }

    init(values: [MealMicronutrient]) {
        self.values = values
    }

    static let typical = FixtureMealMicronutrientsSource(fixture: .typical)
    static let sparse = FixtureMealMicronutrientsSource(fixture: .sparse)
    static let empty = FixtureMealMicronutrientsSource(fixture: .empty)

    func micronutrients(for mealID: String) -> [MealMicronutrient] {
        values
    }

    private static let typicalPayload = Data(#"""
    [
      {"id":"iron","label":"iron","amount":4.2,"unit":"mg","confidence":0.7},
      {"id":"potassium","label":"potassium","amount":320,"unit":"mg","confidence":0.9},
      {"id":"vitamin c","label":"vitamin c","amount":32,"unit":"mg","confidence":0.8},
      {"id":"zinc","label":"zinc","amount":3.1,"unit":"mg","confidence":0.6},
      {"id":"b12","label":"b12","amount":2.4,"unit":"mcg","confidence":0.5}
    ]
    """#.utf8)

    private static let sparsePayload = Data(#"""
    [
      {"id":"iron","label":"iron","amount":4.2,"unit":"mg","confidence":0.7}
    ]
    """#.utf8)

    private static let emptyPayload = Data("[]".utf8)
}

struct MealMicronutrientsPresentation: Equatable, Sendable {
    let ordered: [MealMicronutrient]
    let collapsed: [MealMicronutrient]

    init(
        nutrients: [MealMicronutrient],
        collapsedCount: Int = KStyle.microCollapsedCount
    ) {
        ordered = Self.sortedByAmount(nutrients)
        collapsed = Array(ordered.prefix(max(0, collapsedCount)))
    }

    var isVisible: Bool {
        !ordered.isEmpty
    }

    func visibleNutrients(isExpanded: Bool) -> [MealMicronutrient] {
        isExpanded ? ordered : collapsed
    }

    static func sortedByAmount(_ nutrients: [MealMicronutrient]) -> [MealMicronutrient] {
        var seenIDs: Set<String> = []
        return nutrients
            .filter { $0.isRenderable && seenIDs.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                if lhs.id != rhs.id { return lhs.id < rhs.id }
                return lhs.label < rhs.label
            }
    }
}

enum MealMicronutrientsRevealGesture {
    static func nextState(isExpanded: Bool, magnification: CGFloat) -> Bool? {
        if magnification > KStyle.microPinchExpandThreshold, !isExpanded {
            return true
        }
        if magnification < KStyle.microPinchCollapseThreshold, isExpanded {
            return false
        }
        return nil
    }
}

enum BioLogEntryStatus: Equatable, Sendable {
    case saved
    case pending
    case queued
    case failed(String)

    var readLine: String? {
        switch self {
        case .saved:
            return nil
        case .pending:
            return "saving"
        case .queued:
            return KCopy.queuedWillSync
        case .failed(let text):
            return text
        }
    }

    var isLocal: Bool {
        switch self {
        case .saved:
            return false
        case .pending, .queued, .failed:
            return true
        }
    }
}

struct BioMetricSample: Decodable, Equatable, Sendable {
    var date: String
    var value: Double?
    var baseline: Double?
    var deltaPct: Double?
    var driftDirection: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case date
        case value
        case baseline
        case deltaPct
        case driftDirection
        case source
    }

    init(
        date: String,
        value: Double? = nil,
        baseline: Double? = nil,
        deltaPct: Double? = nil,
        driftDirection: String? = nil,
        source: String? = nil
    ) {
        self.date = date.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value
        self.baseline = baseline
        self.deltaPct = deltaPct
        self.driftDirection = Self.normalized(driftDirection)
        self.source = Self.normalized(source)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeTrimmedString(for: .date) ?? ""
        value = try container.decodeFlexibleDouble(for: .value)
        baseline = try container.decodeFlexibleDouble(for: .baseline)
        deltaPct = try container.decodeFlexibleDouble(for: .deltaPct)
        driftDirection = Self.normalized(try container.decodeTrimmedString(for: .driftDirection))
        source = Self.normalized(try container.decodeTrimmedString(for: .source))
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioTodayMetric: Decodable, Equatable, Sendable {
    var value: Double?
    var score: Double?
    var calories: Double?
    var baseline: Double?
    var deltaPct: Double?
    var driftDirection: String?
    var label: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case value
        case score
        case calories
        case kcal
        case baseline
        case deltaPct
        case driftDirection
        case label
        case source
    }

    init(
        value: Double? = nil,
        score: Double? = nil,
        calories: Double? = nil,
        baseline: Double? = nil,
        deltaPct: Double? = nil,
        driftDirection: String? = nil,
        label: String? = nil,
        source: String? = nil
    ) {
        self.value = value
        self.score = score
        self.calories = calories
        self.baseline = baseline
        self.deltaPct = deltaPct
        self.driftDirection = Self.normalized(driftDirection)
        self.label = Self.normalized(label)
        self.source = Self.normalized(source)
    }

    init(from decoder: Decoder) throws {
        if let value = Self.singleValue(from: decoder) {
            self.init(value: value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedValue = try container.decodeFlexibleDouble(for: .value)
        let decodedScore = try container.decodeFlexibleDouble(for: .score)
        let decodedCalories = try container.decodeFlexibleDouble(for: .calories)
            ?? container.decodeFlexibleDouble(for: .kcal)
        let decodedBaseline = try container.decodeFlexibleDouble(for: .baseline)
        let decodedDeltaPct = try container.decodeFlexibleDouble(for: .deltaPct)
        let decodedDriftDirection = Self.normalized(try container.decodeTrimmedString(for: .driftDirection))
        let decodedLabel = Self.normalized(try container.decodeTrimmedString(for: .label))
        let decodedSource = Self.normalized(try container.decodeTrimmedString(for: .source))
        self.init(
            value: decodedValue,
            score: decodedScore,
            calories: decodedCalories,
            baseline: decodedBaseline,
            deltaPct: decodedDeltaPct,
            driftDirection: decodedDriftDirection,
            label: decodedLabel,
            source: decodedSource
        )
    }

    var primaryValue: Double? {
        value ?? score ?? calories
    }

    var calorieValue: Double? {
        calories ?? value ?? score
    }

    private static func singleValue(from decoder: Decoder) -> Double? {
        guard let container = try? decoder.singleValueContainer() else { return nil }
        if let value = try? container.decode(Double.self), value.isFinite {
            return value
        }
        if let value = try? container.decode(Int.self) {
            return Double(value)
        }
        if let string = try? container.decode(String.self),
           let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite {
            return value
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioToday: Decodable, Equatable, Sendable {
    var recovery: BioTodayMetric?
    var sleep: BioTodayMetric?
    var hrv: BioTodayMetric?
    var strain: BioTodayMetric?
    var workout: BioTodayMetric?
    var cycle: BioTodayMetric?
    var calories: BioTodayMetric?

    enum CodingKeys: String, CodingKey {
        case recovery
        case sleep
        case hrv
        case strain
        case workout
        case cycle
        case calories
    }

    init(
        recovery: BioTodayMetric? = nil,
        sleep: BioTodayMetric? = nil,
        hrv: BioTodayMetric? = nil,
        strain: BioTodayMetric? = nil,
        workout: BioTodayMetric? = nil,
        cycle: BioTodayMetric? = nil,
        calories: BioTodayMetric? = nil
    ) {
        self.recovery = recovery
        self.sleep = sleep
        self.hrv = hrv
        self.strain = strain
        self.workout = workout
        self.cycle = cycle
        self.calories = calories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recovery = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .recovery)
        sleep = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .sleep)
        hrv = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .hrv)
        strain = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .strain)
        workout = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .workout)
        cycle = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .cycle)
        calories = try? container.decodeIfPresent(BioTodayMetric.self, forKey: .calories)
    }

    func metric(for marker: BioMarker) -> BioTodayMetric? {
        switch marker {
        case .recovery:
            return recovery
        case .sleep:
            return sleep
        case .hrv:
            return hrv
        }
    }
}

struct BioTrend: Decodable, Equatable, Sendable {
    var recovery: [BioMetricSample]
    var sleep: [BioMetricSample]
    var hrv: [BioMetricSample]

    enum CodingKeys: String, CodingKey {
        case recovery
        case sleep
        case hrv
    }

    init(
        recovery: [BioMetricSample] = [],
        sleep: [BioMetricSample] = [],
        hrv: [BioMetricSample] = []
    ) {
        self.recovery = recovery
        self.sleep = sleep
        self.hrv = hrv
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recovery = (try? container.decode(BioLossyArray<BioMetricSample>.self, forKey: .recovery).elements) ?? []
        sleep = (try? container.decode(BioLossyArray<BioMetricSample>.self, forKey: .sleep).elements) ?? []
        hrv = (try? container.decode(BioLossyArray<BioMetricSample>.self, forKey: .hrv).elements) ?? []
    }

    func entries(for marker: BioMarker) -> [BioMetricSample] {
        switch marker {
        case .recovery:
            return recovery
        case .sleep:
            return sleep
        case .hrv:
            return hrv
        }
    }
}

struct BioLogEntry: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var at: String
    var kind: BioLogKind
    var text: String
    var read: String?
    var imageRef: String?
    var analysisState: String?
    var mealName: String?
    var mealMacros: MealMacroMeasurements?
    var micronutrients: [MealMicronutrient]?
    /// Optional wire addition for future meals. Missing stays false so existing
    /// daemon records keep their saved, logged meaning.
    var isPlanned: Bool
    var status: BioLogEntryStatus

    enum CodingKeys: String, CodingKey {
        case id
        case at
        case timestamp
        case createdAt
        case kind
        case text
        case body
        case note
        case read
        case imageRef
        case image
        case imageURL
        case imageUrl
        case analysis
        case analysisState
        case state
        case name
        case mealName
        case title
        case macros
        case mealInfo
        case calories
        case kcal
        case protein
        case proteinGrams
        case protein_grams
        case carbs
        case carbohydrates
        case carbsGrams
        case carbs_grams
        case fat
        case fatGrams
        case fat_grams
        case fiber
        case fibre
        case fiberGrams
        case fiber_grams
        case sugar
        case sugarGrams
        case sugar_grams
        case micronutrients
        case micros
        case planned
        case isPlanned
    }

    init(
        id: String,
        at: String,
        kind: BioLogKind,
        text: String,
        read: String? = nil,
        imageRef: String? = nil,
        analysisState: String? = nil,
        mealName: String? = nil,
        mealMacros: MealMacroMeasurements? = nil,
        micronutrients: [MealMicronutrient]? = nil,
        isPlanned: Bool = false,
        status: BioLogEntryStatus = .saved
    ) {
        self.id = Self.normalized(id) ?? UUID().uuidString
        self.at = Self.normalized(at) ?? BioDateParser.isoString(Date())
        self.kind = kind
        self.text = Self.normalized(text) ?? ""
        self.read = Self.normalized(read)
        self.imageRef = Self.normalized(imageRef)
        self.analysisState = Self.normalized(analysisState)?.lowercased()
        self.mealName = Self.normalized(mealName)
        self.mealMacros = mealMacros?.hasMeasurement == true ? mealMacros : nil
        self.micronutrients = micronutrients
        self.isPlanned = isPlanned
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let at = try container.decodeTrimmedString(for: .at)
            ?? container.decodeTrimmedString(for: .timestamp)
            ?? container.decodeTrimmedString(for: .createdAt)
        let text = try container.decodeTrimmedString(for: .text)
            ?? container.decodeTrimmedString(for: .body)
            ?? container.decodeTrimmedString(for: .note)
        self.id = try container.decodeTrimmedString(for: .id)
            ?? Self.fallbackID(at: at, text: text)
        self.at = at ?? ""
        self.kind = (try? container.decodeIfPresent(BioLogKind.self, forKey: .kind)) ?? .note
        self.text = text ?? ""
        let analysis: BioMealPhotoAnalysis? = (try? container.decodeIfPresent(
            BioMealPhotoAnalysis.self,
            forKey: .analysis
        )) ?? nil
        let mealInfo: BioMealPhotoAnalysis? = (try? container.decodeIfPresent(
            BioMealPhotoAnalysis.self,
            forKey: .mealInfo
        )) ?? nil
        self.read = Self.normalized(
            try container.decodeTrimmedString(for: .read)
                ?? analysis?.read
                ?? mealInfo?.read
        )
        self.imageRef = Self.normalized(
            try container.decodeTrimmedString(for: .imageRef)
                ?? container.decodeTrimmedString(for: .image)
                ?? container.decodeTrimmedString(for: .imageURL)
                ?? container.decodeTrimmedString(for: .imageUrl)
        )
        self.analysisState = Self.normalized(
            try container.decodeTrimmedString(for: .analysisState)
                ?? container.decodeTrimmedString(for: .state)
                ?? analysis?.state
                ?? mealInfo?.state
        )?.lowercased()
        self.mealName = Self.normalized(
            try container.decodeTrimmedString(for: .mealName)
                ?? container.decodeTrimmedString(for: .name)
                ?? container.decodeTrimmedString(for: .title)
                ?? analysis?.name
                ?? mealInfo?.name
        )
        self.mealMacros = Self.firstMacros(
            BioMealPhotoAnalysis.macros(in: container),
            analysis?.macros,
            mealInfo?.macros
        )
        if container.contains(.micronutrients) || container.contains(.micros) {
            let keys: [CodingKeys] = [.micronutrients, .micros]
            self.micronutrients = MealMicronutrientPayload.hasNonNullValue(
                in: container,
                keys: keys
            )
                ? (MealMicronutrientPayload.decode(in: container, keys: keys) ?? [])
                : nil
        } else {
            self.micronutrients = analysis?.micronutrients ?? mealInfo?.micronutrients
        }
        self.isPlanned = (try? container.decodeIfPresent(Bool.self, forKey: .planned))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .isPlanned))
            ?? false
        self.status = .saved
    }

    var sortDate: Date? {
        BioDateParser.dateTime(from: at)
    }

    var displayTime: String {
        guard let date = sortDate else { return at.lowercased() }
        return KTimestampFormatter.hourMinute(date)
    }

    var readLine: String? {
        switch status {
        case .pending where isMealPhoto:
            return KCopy.mealPhotoReading
        case .saved where isMealPhoto && !analysisDone:
            return KCopy.mealPhotoReading
        default:
            return status.readLine ?? read
        }
    }

    var isMealPhoto: Bool {
        imageRef != nil
    }

    var analysisDone: Bool {
        analysisState?.lowercased() == "done"
    }

    var displayText: String {
        guard isMealPhoto, analysisDone, let mealName else { return text }
        return mealName
    }

    var macroLine: String? {
        guard isMealPhoto, analysisDone else { return nil }
        return mealMacros?.summaryText(prefix: nil).map { "~\($0)" }
    }

    var canRetryMealPhoto: Bool {
        guard isMealPhoto else { return false }
        switch status {
        case .failed, .queued:
            return true
        case .saved, .pending:
            return false
        }
    }

    func replacingStatus(_ status: BioLogEntryStatus) -> BioLogEntry {
        var copy = self
        copy.status = status
        return copy
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func fallbackID(at: String?, text: String?) -> String {
        let seed = [normalized(at), normalized(text)]
            .compactMap { $0 }
            .joined(separator: "-")
        guard !seed.isEmpty else { return UUID().uuidString }
        return "body-log-\(abs(seed.hashValue))"
    }

    private static func firstMacros(_ candidates: MealMacroMeasurements?...) -> MealMacroMeasurements? {
        for candidate in candidates where candidate?.hasMeasurement == true {
            return candidate
        }
        return nil
    }
}

struct BioMealPhotoAnalysis: Decodable, Equatable, Sendable {
    var state: String?
    var name: String?
    var macros: MealMacroMeasurements?
    var micronutrients: [MealMicronutrient]?
    var read: String?

    enum CodingKeys: String, CodingKey {
        case status
        case state
        case analysis
        case name
        case title
        case mealName
        case read
        case kRead
        case summary
        case macros
        case mealInfo
        case calories
        case kcal
        case protein
        case proteinGrams
        case protein_grams
        case carbs
        case carbohydrates
        case carbsGrams
        case carbs_grams
        case fat
        case fatGrams
        case fat_grams
        case fiber
        case fibre
        case fiberGrams
        case fiber_grams
        case sugar
        case sugarGrams
        case sugar_grams
        case micronutrients
        case micros
    }

    init(
        state: String? = nil,
        name: String? = nil,
        macros: MealMacroMeasurements? = nil,
        micronutrients: [MealMicronutrient]? = nil,
        read: String? = nil
    ) {
        self.state = Self.normalized(state)?.lowercased()
        self.name = Self.normalized(name)
        self.macros = macros?.hasMeasurement == true ? macros : nil
        self.micronutrients = micronutrients
        self.read = Self.normalized(read)
    }

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self.init(state: string)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mealInfo: BioMealPhotoAnalysis? = (try? container.decodeIfPresent(
            BioMealPhotoAnalysis.self,
            forKey: .mealInfo
        )) ?? nil
        let nestedMacros: MealMacroMeasurements? = (try? container.decodeIfPresent(
            MealMacroMeasurements.self,
            forKey: .macros
        )) ?? nil
        let nestedMicronutrients = MealMicronutrientPayload.decode(
            in: container,
            keys: [.micronutrients, .micros]
        )

        self.init(
            state: try container.decodeTrimmedString(for: .status)
                ?? container.decodeTrimmedString(for: .state)
                ?? container.decodeTrimmedString(for: .analysis)
                ?? mealInfo?.state,
            name: try container.decodeTrimmedString(for: .mealName)
                ?? container.decodeTrimmedString(for: .name)
                ?? container.decodeTrimmedString(for: .title)
                ?? mealInfo?.name,
            macros: Self.firstMacros(
                nestedMacros,
                Self.macros(in: container),
                mealInfo?.macros
            ),
            micronutrients: nestedMicronutrients ?? mealInfo?.micronutrients,
            read: try container.decodeTrimmedString(for: .read)
                ?? container.decodeTrimmedString(for: .kRead)
                ?? container.decodeTrimmedString(for: .summary)
                ?? mealInfo?.read
        )
    }

    static func macros(in container: KeyedDecodingContainer<BioLogEntry.CodingKeys>) -> MealMacroMeasurements? {
        let nested: MealMacroMeasurements? = (try? container.decodeIfPresent(
            MealMacroMeasurements.self,
            forKey: .macros
        )) ?? nil
        return firstMacros(nested, directMacros(in: container))
    }

    private static func macros(in container: KeyedDecodingContainer<CodingKeys>) -> MealMacroMeasurements? {
        directMacros(in: container)
    }

    private static func directMacros<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>
    ) -> MealMacroMeasurements? {
        let measurements = MealMacroMeasurements(
            calories: flexibleDouble(in: container, keys: ["calories", "kcal"]),
            protein: flexibleDouble(in: container, keys: ["protein", "proteinGrams", "protein_grams"]),
            carbs: flexibleDouble(in: container, keys: ["carbs", "carbohydrates", "carbsGrams", "carbs_grams"]),
            fat: flexibleDouble(in: container, keys: ["fat", "fatGrams", "fat_grams"]),
            fiber: flexibleDouble(in: container, keys: ["fiber", "fibre", "fiberGrams", "fiber_grams"]),
            sugar: flexibleDouble(in: container, keys: ["sugar", "sugarGrams", "sugar_grams"])
        )
        return measurements.hasMeasurement ? measurements : nil
    }

    private static func flexibleDouble<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        keys: [String]
    ) -> Double? {
        for key in keys {
            guard let codingKey = Key(stringValue: key) else { continue }
            if let value = try? container.decodeFlexibleDouble(for: codingKey) {
                return value
            }
        }
        return nil
    }

    private static func firstMacros(_ candidates: MealMacroMeasurements?...) -> MealMacroMeasurements? {
        for candidate in candidates where candidate?.hasMeasurement == true {
            return candidate
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioInterventionTarget: Decodable, Equatable, Sendable {
    var domain: String?
    var id: String?
    var frontierExcluded: Bool?

    init(domain: String? = nil, id: String? = nil, frontierExcluded: Bool? = nil) {
        self.domain = Self.normalized(domain)
        self.id = Self.normalized(id)
        self.frontierExcluded = frontierExcluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            domain: try container.decodeTrimmedString(for: .domain),
            id: try container.decodeTrimmedString(for: .id),
            frontierExcluded: try? container.decodeIfPresent(Bool.self, forKey: .frontierExcluded)
        )
    }

    var displayText: String? {
        let values = [id, domain]
            .compactMap { Self.humanized($0) }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var hasDisplayContent: Bool {
        displayText != nil
    }

    private enum CodingKeys: String, CodingKey {
        case domain
        case id
        case frontierExcluded
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func humanized(_ value: String?) -> String? {
        normalized(value)?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }
}

struct BioInterventionPhase: Decodable, Identifiable, Equatable, Sendable {
    var name: String?
    var order: Int?
    var durationDays: Int?
    var targetBiomarkers: [BioInterventionTarget]

    init(
        name: String? = nil,
        order: Int? = nil,
        durationDays: Int? = nil,
        targetBiomarkers: [BioInterventionTarget] = []
    ) {
        self.name = Self.normalized(name)
        self.order = order
        self.durationDays = durationDays
        self.targetBiomarkers = targetBiomarkers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decodeTrimmedString(for: .name),
            order: try container.decodeFlexibleInt(for: .order),
            durationDays: try container.decodeFlexibleInt(for: .durationDays),
            targetBiomarkers: (try? container.decode(
                BioLossyArray<BioInterventionTarget>.self,
                forKey: .targetBiomarkers
            ).elements) ?? []
        )
    }

    var id: String {
        [order.map(String.init), name, targetsText]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    var hasDisplayContent: Bool {
        summaryText != nil || targetsText != nil
    }

    var summaryText: String? {
        let values = [
            name?.lowercased(),
            durationDays.flatMap { $0 > 0 ? "\($0)d" : nil },
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var targetsText: String? {
        let values = targetBiomarkers.compactMap(\.displayText)
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case order
        case durationDays
        case targetBiomarkers
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioInterventionSupplement: Decodable, Identifiable, Equatable, Sendable {
    var name: String?
    var dose: String?
    var timing: String?
    var withFood: Bool?

    init(name: String? = nil, dose: String? = nil, timing: String? = nil, withFood: Bool? = nil) {
        self.name = Self.normalized(name)
        self.dose = Self.normalized(dose)
        self.timing = Self.normalized(timing)
        self.withFood = withFood
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decodeTrimmedString(for: .name),
            dose: try container.decodeTrimmedString(for: .dose),
            timing: try container.decodeTrimmedString(for: .timing),
            withFood: try? container.decodeIfPresent(Bool.self, forKey: .withFood)
        )
    }

    var id: String {
        [name, dose, timing, summaryText]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    var hasDisplayContent: Bool {
        summaryText != nil
    }

    var summaryText: String? {
        var values = [name, dose, timing]
            .compactMap { $0?.lowercased() }
        if withFood == true {
            values.append("with food")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case dose
        case timing
        case withFood
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum BioInterventionPhaseStatus: String, Equatable, Sendable {
    case planned
    case active
    case washout
    case done

    static func derive(actionState: String?) -> Self {
        switch actionState?.lowercased() {
        case "active":
            return .active
        case "paused":
            return .washout
        case "completed", "done":
            return .done
        default:
            return .planned
        }
    }
}

struct BioHoldToStopStateMachine: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case holding
        case committed
    }

    private(set) var state: State = .idle

    mutating func pressing(_ isPressing: Bool) {
        guard state != .committed else { return }
        state = isPressing ? .holding : .idle
    }

    mutating func complete() -> Bool {
        guard state == .holding else { return false }
        state = .committed
        return true
    }
}

enum MealCaptureIntent: Equatable, Sendable {
    case photo
    case video
}

struct MealCaptureGestureStateMachine: Equatable, Sendable {
    private(set) var isHolding = false

    mutating func pressing(_ pressing: Bool) {
        isHolding = pressing
    }

    mutating func intentAfterRelease() -> MealCaptureIntent {
        defer { isHolding = false }
        return isHolding ? .video : .photo
    }
}

struct BioInterventionProjection: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String?
    var rationale: String?
    var category: String?
    var startPolicy: String?
    var phases: [BioInterventionPhase]
    var supplements: [BioInterventionSupplement]
    var targetBiomarkers: [BioInterventionTarget]
    var eventAt: String?
    var actionState: String?
    var currentPhase: Int?

    init(
        id: String? = nil,
        title: String? = nil,
        rationale: String? = nil,
        category: String? = nil,
        startPolicy: String? = nil,
        phases: [BioInterventionPhase] = [],
        supplements: [BioInterventionSupplement] = [],
        targetBiomarkers: [BioInterventionTarget] = [],
        eventAt: String? = nil,
        actionState: String? = nil,
        currentPhase: Int? = nil
    ) {
        self.title = Self.normalized(title)
        self.rationale = Self.normalized(rationale)
        self.category = Self.normalized(category)
        self.startPolicy = Self.normalized(startPolicy)
        self.phases = phases.filter(\.hasDisplayContent)
        self.supplements = supplements.filter(\.hasDisplayContent)
        self.targetBiomarkers = targetBiomarkers.filter(\.hasDisplayContent)
        self.eventAt = Self.normalized(eventAt)
        self.actionState = Self.normalized(actionState)
        self.currentPhase = currentPhase
        self.id = Self.normalized(id) ?? Self.fallbackID(title: self.title, eventAt: self.eventAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeTrimmedString(for: .id),
            title: try container.decodeTrimmedString(for: .title),
            rationale: try container.decodeTrimmedString(for: .rationale),
            category: try container.decodeTrimmedString(for: .category),
            startPolicy: try container.decodeTrimmedString(for: .startPolicy),
            phases: (try? container.decode(BioLossyArray<BioInterventionPhase>.self, forKey: .phases).elements) ?? [],
            supplements: (try? container.decode(
                BioLossyArray<BioInterventionSupplement>.self,
                forKey: .supplements
            ).elements) ?? [],
            targetBiomarkers: (try? container.decode(
                BioLossyArray<BioInterventionTarget>.self,
                forKey: .targetBiomarkers
            ).elements) ?? [],
            eventAt: try container.decodeTrimmedString(for: .eventAt),
            actionState: try container.decodeTrimmedString(for: .actionState),
            currentPhase: try container.decodeFlexibleInt(for: .currentPhase)
        )
    }

    var hasDisplayContent: Bool {
        title != nil
            || rationale != nil
            || category != nil
            || startPolicy != nil
            || !phases.isEmpty
            || !supplements.isEmpty
            || !targetBiomarkers.isEmpty
    }

    var metadataText: String? {
        let values = [
            Self.humanized(category),
            Self.humanized(startPolicy),
            eventAt.flatMap(Self.eventText),
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var targetsText: String? {
        let values = targetBiomarkers.compactMap(\.displayText)
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var phaseStatus: BioInterventionPhaseStatus {
        BioInterventionPhaseStatus.derive(actionState: actionState)
    }

    var phaseText: String { phaseStatus.rawValue }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case rationale
        case category
        case startPolicy
        case phases
        case supplements
        case targetBiomarkers
        case eventAt
        case actionState
        case currentPhase
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func humanized(_ value: String?) -> String? {
        normalized(value)?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private static func eventText(_ value: String) -> String? {
        guard let date = BioDateParser.dateTime(from: value) else { return nil }
        return "\(BioDateParser.dayText(value)) · \(KTimestampFormatter.hourMinute(date))"
    }

    private static func fallbackID(title: String?, eventAt: String?) -> String {
        let seed = [title, eventAt]
            .compactMap { humanized($0) }
            .joined(separator: "-")
        return seed.isEmpty ? "bio-intervention" : seed
    }
}

struct BioArtifactsResponse: Decodable, Equatable, Sendable {
    var trend: BioTrend?
    var flags: [String]
    var today: BioToday?
    var interventions: [BioInterventionProjection]
    var log: [BioLogEntry]
    // Additive lab and protocol projections. Older daemons omit these keys and
    // therefore continue to render the honest empty state.
    var biomarkers: [BioBiomarkerRecord]
    var nextTests: [BioNextTestRecord]
    var reports: [BioReportRecord]
    var protocols: [BioTestingProtocolProjection]
    var meditationLibrary: [BioMeditationProtocolProjection]
    var generatedAt: String?
    var source: String?
    var ok: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case trend
        case flags
        case today
        case interventions
        case log
        case biomarkers
        case nextTests
        case reports
        case protocols
        case meditationLibrary
        case generatedAt
        case source
        case ok
        case error
    }

    init(
        trend: BioTrend? = nil,
        flags: [String] = [],
        today: BioToday? = nil,
        interventions: [BioInterventionProjection] = [],
        log: [BioLogEntry] = [],
        biomarkers: [BioBiomarkerRecord] = [],
        nextTests: [BioNextTestRecord] = [],
        reports: [BioReportRecord] = [],
        protocols: [BioTestingProtocolProjection] = [],
        meditationLibrary: [BioMeditationProtocolProjection] = [],
        generatedAt: String? = nil,
        source: String? = nil,
        ok: Bool? = nil,
        error: String? = nil
    ) {
        self.trend = trend
        self.flags = flags.map(Self.normalized).compactMap { $0 }
        self.today = today
        self.interventions = interventions
        self.log = log
        self.biomarkers = biomarkers
        self.nextTests = nextTests
        self.reports = reports
        self.protocols = protocols
        self.meditationLibrary = meditationLibrary
        self.generatedAt = Self.normalized(generatedAt)
        self.source = Self.normalized(source)
        self.ok = ok
        self.error = Self.normalized(error)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trend = try? container.decodeIfPresent(BioTrend.self, forKey: .trend)
        flags = (try? container.decodeIfPresent([String].self, forKey: .flags))?
            .map(Self.normalized)
            .compactMap { $0 } ?? []
        today = try? container.decodeIfPresent(BioToday.self, forKey: .today)
        interventions = (try? container.decode(
            BioLossyArray<BioInterventionProjection>.self,
            forKey: .interventions
        ).elements) ?? []
        log = (try? container.decode(BioLossyArray<BioLogEntry>.self, forKey: .log).elements) ?? []
        biomarkers = (try? container.decode(
            BioLossyArray<BioBiomarkerRecord>.self,
            forKey: .biomarkers
        ).elements) ?? []
        nextTests = (try? container.decode(
            BioLossyArray<BioNextTestRecord>.self,
            forKey: .nextTests
        ).elements) ?? []
        reports = (try? container.decode(
            BioLossyArray<BioReportRecord>.self,
            forKey: .reports
        ).elements) ?? []
        protocols = (try? container.decode(
            BioLossyArray<BioTestingProtocolProjection>.self,
            forKey: .protocols
        ).elements) ?? []
        meditationLibrary = (try? container.decode(
            BioLossyArray<BioMeditationProtocolProjection>.self,
            forKey: .meditationLibrary
        ).elements) ?? []
        generatedAt = Self.normalized(try container.decodeTrimmedString(for: .generatedAt))
        source = Self.normalized(try container.decodeTrimmedString(for: .source))
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        error = Self.normalized(try container.decodeTrimmedString(for: .error))
    }

    var isFailure: Bool {
        ok == false || error != nil
    }

    func todayMetric(for marker: BioMarker) -> BioTodayMetric? {
        today?.metric(for: marker)
    }

    func trendEntries(for marker: BioMarker) -> [BioMetricSample] {
        trend?.entries(for: marker) ?? []
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioLogEnvelope: Decodable, Equatable, Sendable {
    var entries: [BioLogEntry]
    var days: Int?
    var generatedAt: String?
    var source: String?
    var ok: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case days
        case generatedAt
        case source
        case ok
        case error
    }

    init(
        entries: [BioLogEntry] = [],
        days: Int? = nil,
        generatedAt: String? = nil,
        source: String? = nil,
        ok: Bool? = nil,
        error: String? = nil
    ) {
        self.entries = entries
        self.days = days
        self.generatedAt = Self.normalized(generatedAt)
        self.source = Self.normalized(source)
        self.ok = ok
        self.error = Self.normalized(error)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? container.decode(BioLossyArray<BioLogEntry>.self, forKey: .entries).elements) ?? []
        days = try container.decodeFlexibleInt(for: .days)
        generatedAt = Self.normalized(try container.decodeTrimmedString(for: .generatedAt))
        source = Self.normalized(try container.decodeTrimmedString(for: .source))
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        error = Self.normalized(try container.decodeTrimmedString(for: .error))
    }

    var isFailure: Bool {
        ok == false || error != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioLogPostResponse: Decodable, Equatable, Sendable {
    var ok: Bool
    var entry: BioLogEntry?
    var error: String?
    var generatedAt: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case entry
        case error
        case generatedAt
        case source
    }

    init(
        ok: Bool,
        entry: BioLogEntry? = nil,
        error: String? = nil,
        generatedAt: String? = nil,
        source: String? = nil
    ) {
        self.ok = ok
        self.entry = entry
        self.error = Self.normalized(error)
        self.generatedAt = Self.normalized(generatedAt)
        self.source = Self.normalized(source)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
        entry = try? container.decodeIfPresent(BioLogEntry.self, forKey: .entry)
        error = Self.normalized(try container.decodeTrimmedString(for: .error))
        generatedAt = Self.normalized(try container.decodeTrimmedString(for: .generatedAt))
        source = Self.normalized(try container.decodeTrimmedString(for: .source))
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BioTodayLine: Equatable, Sendable {
    var marker: BioMarker
    var valueText: String
    var metaText: String
    var source: BioMetricSource?

    var primaryText: String {
        "\(marker.rawValue) \(valueText)"
    }

    var plainText: String {
        [primaryText, metaText, source?.chipText]
            .compactMap { text -> String? in
                guard let text else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }
}

enum BioTodayLineFormatter {
    static func line(marker: BioMarker, metric: BioTodayMetric) -> BioTodayLine? {
        guard let value = metric.value else { return nil }
        let valueText = BioNumberText.significant(value)
        let baselineText = metric.label ?? deltaText(metric.deltaPct)
        let source = BioMetricSource(wireValue: metric.source)
        let metaParts = [baselineText, driftText(metric.driftDirection)]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
        guard !metaParts.isEmpty || source != nil else { return nil }
        return BioTodayLine(
            marker: marker,
            valueText: valueText,
            metaText: metaParts.joined(separator: " · "),
            source: source
        )
    }

    private static func deltaText(_ value: Double?) -> String? {
        guard let value else { return nil }
        if abs(value) < 0.5 {
            return "at your baseline"
        }
        let magnitude = BioNumberText.significant(abs(value))
        return value > 0
            ? "\(magnitude)% over your baseline"
            : "\(magnitude)% under your baseline"
    }

    private static func driftText(_ value: String?) -> String? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up", "rising", "rise":
            return "drifting up"
        case "down", "falling", "drop":
            return "drifting down"
        case "flat", "stable", "steady", "same":
            return "holding steady"
        case let value? where !value.isEmpty:
            return value.replacingOccurrences(of: "_", with: " ")
        default:
            return nil
        }
    }
}

enum BioNumberText {
    static func significant(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

enum BioCopy {
    static let emptyLog = "nothing logged yet · the body rail is listening"
    static let interventionStopFailed = "stop didn't reach k · still active"

    static func logFailed(reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return "log failed · \(trimmed.isEmpty ? "unknown" : trimmed.lowercased())"
    }

    static func mealPhotoFailed(reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed ?? "unknown" : "unknown"
        return "photo failed · \(value.lowercased()) — tap to retry"
    }
}

struct MealPhotoEncodedImage: Equatable, Sendable {
    var imageBase64: String
    var jpegData: Data
    var pixelWidth: Int
    var pixelHeight: Int

    var longestSide: Int {
        max(pixelWidth, pixelHeight)
    }
}

enum MealPhotoEncoder {
    static let maxLongestSide: CGFloat = 1_600
    static let jpegQuality: CGFloat = 0.7

    enum EncodingError: LocalizedError, Equatable {
        case invalidImage

        var errorDescription: String? {
            "photo could not be read"
        }
    }

    static func encode(_ image: UIImage) throws -> MealPhotoEncodedImage {
        let normalized = normalizedImage(image)
        guard normalized.size.width > 0, normalized.size.height > 0 else {
            throw EncodingError.invalidImage
        }

        let targetSize = targetPixelSize(for: normalized.size)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let downscaled = renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = downscaled.jpegData(compressionQuality: jpegQuality) else {
            throw EncodingError.invalidImage
        }

        return MealPhotoEncodedImage(
            imageBase64: jpeg.base64EncodedString(),
            jpegData: jpeg,
            pixelWidth: Int(targetSize.width.rounded()),
            pixelHeight: Int(targetSize.height.rounded())
        )
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = image.scale
        rendererFormat.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: rendererFormat).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func targetPixelSize(for sourceSize: CGSize) -> CGSize {
        let width = max(1, sourceSize.width)
        let height = max(1, sourceSize.height)
        let longest = max(width, height)
        let scale = min(1, maxLongestSide / longest)
        return CGSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )
    }
}

struct QueuedMealPhoto: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var imageBase64: String
    var caption: String?
    var enqueuedAt: Date
    var blockId: String?
    var lastError: String?

    init(
        id: String = "meal-photo-\(UUID().uuidString)",
        imageBase64: String,
        caption: String? = nil,
        enqueuedAt: Date = Date(),
        blockId: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.imageBase64 = imageBase64
        self.caption = Self.normalized(caption)
        self.enqueuedAt = enqueuedAt
        self.blockId = Self.normalized(blockId)
        self.lastError = Self.normalized(lastError)
    }

    var optimisticEntry: BioLogEntry {
        BioLogEntry(
            id: id,
            at: BioDateParser.isoString(enqueuedAt),
            kind: .meal,
            text: caption ?? "meal photo",
            imageRef: id,
            status: lastError == nil ? .queued : .failed(BioCopy.mealPhotoFailed(reason: lastError))
        )
    }

    func withLastError(_ reason: String?) -> QueuedMealPhoto {
        var copy = self
        copy.lastError = Self.normalized(reason)
        return copy
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct MealPhotoQueueStore {
    static let capacity = 3
    static let didChangeNotification = Notification.Name("KMealPhotoQueueStoreDidChange")

    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "body.mealPhotos.queue",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> [QueuedMealPhoto] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let items = (try? JSONDecoder().decode([QueuedMealPhoto].self, from: data)) ?? []
        return Self.bounded(items)
    }

    func save(_ items: [QueuedMealPhoto]) {
        let bounded = Self.bounded(items)
        if bounded.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(bounded) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func append(_ item: QueuedMealPhoto) {
        let remaining = load().filter { $0.id != item.id }
        save(remaining + [item])
    }

    func update(_ item: QueuedMealPhoto) {
        append(item)
    }

    func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    func item(id: String) -> QueuedMealPhoto? {
        load().first { $0.id == id }
    }

    private static func bounded(_ items: [QueuedMealPhoto]) -> [QueuedMealPhoto] {
        Array(items.sorted { lhs, rhs in
            if lhs.enqueuedAt == rhs.enqueuedAt { return lhs.id < rhs.id }
            return lhs.enqueuedAt > rhs.enqueuedAt
        }
        .prefix(capacity))
        .sorted { lhs, rhs in
            if lhs.enqueuedAt == rhs.enqueuedAt { return lhs.id < rhs.id }
            return lhs.enqueuedAt < rhs.enqueuedAt
        }
    }
}

@MainActor
final class BioModel: ObservableObject {
    @Published private(set) var artifact = BioArtifactsResponse()
    @Published private(set) var logEntries: [BioLogEntry] = []
    @Published private(set) var connectionState = KConnectionStateModel()
    @Published private(set) var logErrorText: String?
    @Published private(set) var stopErrorText: String?
    @Published private(set) var stoppingInterventionIDs: Set<String> = []
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var isLoading = false
    @Published private(set) var feedbackTriggers = KFeedbackTriggers()
    @Published var baseURL: String

    private let clientFactory: (String) -> AGUIClient
    private let mealPhotoQueueStore: MealPhotoQueueStore
    private let nowProvider: () -> Date
    private let auditState: BioDemo.AuditState?
    private var hasLoaded = false

    init(
        baseURL: String = UserDefaults.standard.string(forKey: "cskBaseURL")
            ?? "http://127.0.0.1:3003",
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        mealPhotoQueueStore: MealPhotoQueueStore = MealPhotoQueueStore(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.mealPhotoQueueStore = mealPhotoQueueStore
        self.nowProvider = nowProvider
        auditState = BioDemo.auditState
        if auditState == nil {
            restoreQueuedMealPhotos()
        } else {
            mealPhotoQueueStore.save([])
        }
    }

    var flagLines: [String] {
        artifact.flags
    }

    var interventions: [BioInterventionProjection] {
        artifact.interventions.filter(\.hasDisplayContent)
    }

    var biomarkerRecords: [BioBiomarkerRecord] {
        if !artifact.biomarkers.isEmpty { return artifact.biomarkers }
        return BioDemo.enabled && auditState != .empty ? BioDemo.biomarkers : []
    }

    var nextTestRecords: [BioNextTestRecord] {
        if !artifact.nextTests.isEmpty { return artifact.nextTests }
        return BioDemo.enabled && auditState != .empty ? BioDemo.nextTests : []
    }

    var reportRecords: [BioReportRecord] {
        if !artifact.reports.isEmpty { return artifact.reports }
        return BioDemo.enabled && auditState != .empty ? BioDemo.reports : []
    }

    var testingProtocols: [BioTestingProtocolProjection] {
        if !artifact.protocols.isEmpty { return artifact.protocols }
        return BioDemo.enabled && auditState != .empty ? BioDemo.testingProtocols : []
    }

    var meditationProtocols: [BioMeditationProtocolProjection] {
        if !artifact.meditationLibrary.isEmpty { return artifact.meditationLibrary }
        return BioDemo.enabled && auditState != .empty ? BioDemo.meditationLibrary : []
    }

    var hasProtocolSurfaceData: Bool {
        !testingProtocols.isEmpty || !meditationProtocols.isEmpty
    }

    // Every meal, including optimistic pending/queued/failed entries — a just-captured
    // photo appears immediately on the nutrition timeline, then reconciles to saved.
    var nutritionEntries: [BioLogEntry] {
        logEntries.filter { $0.kind == .meal }
    }

    // The 3×2 overview grid. Systems with a genuine backing metric are populated;
    // the rest show the honest "baseline pending" state. No metric is fabricated.
    var systemCards: [BioSystemCard] {
        BioSystem.allCases.map { system in
            switch system {
            case .heart:
                return BioSystemCard.make(
                    .heart,
                    metric: artifact.today?.recovery,
                    secondary: ("hrv", artifact.today?.hrv)
                )
            case .sleep:
                return BioSystemCard.make(.sleep, metric: artifact.today?.sleep)
            case .blood, .gut, .muscles, .brain:
                return .pending(system)
            }
        }
    }

    // The overview alert row surfaces the first real flag, if any — never fabricated.
    var overviewAlert: String? {
        flagLines.first
    }

    // Founder ruling 2026-08-04: the register is fixed at all five tabs.
    var availableStates: [BioState] {
        BioStateAvailability.allStates
    }

    var generatedAtText: String? {
        let raw = artifact.generatedAt
            ?? logEntries.compactMap(\.sortDate).max().map(BioDateParser.isoString)
        guard let raw, let date = BioDateParser.dateTime(from: raw) else { return nil }
        return KTimestampFormatter.asOf(date)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await load() }
    }

    func load() async {
        baseURL = UserDefaults.standard.string(forKey: "cskBaseURL") ?? baseURL
        isStale = lastSyncAt != nil
        isLoading = true
        connectionState.transition(to: .connecting)

#if DEBUG
        if let auditState {
            switch auditState {
            case .empty:
                artifact = BioArtifactsResponse()
                logEntries = []
                lastSyncAt = BioDemo.referenceNow
                isStale = false
                connectionState.transition(to: .live)
            case .error:
                artifact = BioArtifactsResponse()
                logEntries = []
                lastSyncAt = nil
                isStale = false
                connectionState.transition(to: .offlineRetrying)
            case .stopFailure:
                artifact = BioDemo.overlay(onto: BioArtifactsResponse())
                logEntries = []
                lastSyncAt = BioDemo.referenceNow
                isStale = false
                connectionState.transition(to: .live)
            }
            isLoading = false
            return
        }
#endif

        if KLoadingPreview.isEnabled { return }

        let client = clientFactory(baseURL)
        async let artifactResult = fetchBioArtifacts(client: client)
        async let logResult = fetchBodyLog(client: client)

        let loadedArtifact = await artifactResult
        let loadedLog = await logResult

        var didLoad = false
        switch loadedArtifact {
        case .success(let response) where !response.isFailure:
            artifact = await enrichInterventionStates(response, client: client)
            didLoad = true
        case .success, .failure:
            break
        }

        // Founder 2026-08-05: a demo seed (off by default; `-biodemo` arg or the
        // `cskBioDemo` toggle) fills ONLY empty slots with clearly-sample data so the
        // bio UI can be seen and iterated before the real data pipeline lands. Real
        // records always win — demo never overrides them, never persists.
        if BioDemo.enabled {
            artifact = BioDemo.overlay(onto: artifact)
            didLoad = true
        }

        switch loadedLog {
        case .success(let response) where !response.isFailure:
            logEntries = Self.sorted(Self.merge(
                primary: response.entries,
                secondary: artifact.log + localLogEntries()
            ))
            didLoad = true
        case .success, .failure:
            logEntries = Self.sorted(Self.merge(primary: artifact.log, secondary: localLogEntries()))
        }

        if didLoad {
            lastSyncAt = nowProvider()
            isStale = false
            connectionState.transition(to: .live)
        } else {
            isStale = lastSyncAt != nil
            connectionState.transition(to: .offlineRetrying)
        }
        if didLoad {
            await drainMealPhotoQueue()
        }
        isLoading = false
    }

    func stopIntervention(_ intervention: BioInterventionProjection) async {
        guard intervention.phaseStatus == .active else { return }
        guard stoppingInterventionIDs.insert(intervention.id).inserted else { return }
        setStopErrorText(nil)
        defer { stoppingInterventionIDs.remove(intervention.id) }

        do {
            let response = try await clientFactory(baseURL).recordInterventionAct(
                interventionId: intervention.id,
                action: "stop",
                timestamp: nowProvider()
            )
            guard response.ok != false else {
                setStopErrorText(BioCopy.interventionStopFailed)
                return
            }
            artifact = await enrichInterventionStates(artifact, client: clientFactory(baseURL))
            setStopErrorText(nil)
        } catch {
            setStopErrorText(BioCopy.interventionStopFailed)
        }
    }

    @discardableResult
    func submitLog(kind: BioLogKind, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let timestamp = nowProvider()
        let localID = "local-\(UUID().uuidString)"
        let optimistic = BioLogEntry(
            id: localID,
            at: BioDateParser.isoString(timestamp),
            kind: kind,
            text: trimmed,
            status: .pending
        )
        logEntries = Self.sorted([optimistic] + logEntries)
        setLogErrorText(nil)

        do {
            let response = try await clientFactory(baseURL).recordBodyLog(
                kind: kind,
                text: trimmed,
                at: timestamp
            )
            guard response.ok else {
                failOptimisticLog(id: localID, reason: response.error ?? "unknown")
                return false
            }

            let saved = response.entry ?? optimistic.replacingStatus(.saved)
            replaceOptimisticLog(id: localID, with: saved.replacingStatus(.saved))
            return true
        } catch {
            failOptimisticLog(id: localID, reason: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func submitMealPhoto(image: UIImage, caption: String? = nil) async -> Bool {
        do {
            return try await submitMealPhotoPayload(MealPhotoEncoder.encode(image), caption: caption)
        } catch {
            let text = BioCopy.mealPhotoFailed(reason: error.localizedDescription)
            setLogErrorText(text)
            return false
        }
    }

    @discardableResult
    func submitMealPhotoPayload(_ payload: MealPhotoEncodedImage, caption: String? = nil) async throws -> Bool {
        let timestamp = nowProvider()
        let item = QueuedMealPhoto(
            imageBase64: payload.imageBase64,
            caption: caption,
            enqueuedAt: timestamp
        )
        mealPhotoQueueStore.append(item)
        upsertMealPhotoEntry(item.optimisticEntry.replacingStatus(.pending))
        setLogErrorText(nil)
        return await submitQueuedMealPhoto(item)
    }

    func retryMealPhoto(entryID: String) {
        Task { await retryQueuedMealPhoto(entryID: entryID) }
    }

    private func fetchBioArtifacts(client: AGUIClient) async -> Result<BioArtifactsResponse, Error> {
        do {
            return .success(try await client.bioArtifacts())
        } catch {
            return .failure(error)
        }
    }

    private func fetchBodyLog(client: AGUIClient) async -> Result<BioLogEnvelope, Error> {
        do {
            return .success(try await client.bodyLog(days: 7))
        } catch {
            return .failure(error)
        }
    }

    private func enrichInterventionStates(
        _ response: BioArtifactsResponse,
        client: AGUIClient
    ) async -> BioArtifactsResponse {
        guard !response.interventions.isEmpty else { return response }
        var enriched = response
        enriched.interventions = await withTaskGroup(of: BioInterventionProjection.self) { group in
            for intervention in response.interventions {
                group.addTask {
                    guard let state = try? await client.interventionState(id: intervention.id) else {
                        return intervention
                    }
                    var copy = intervention
                    copy.actionState = state.actionState
                    copy.currentPhase = state.currentPhase
                    return copy
                }
            }
            var values: [BioInterventionProjection] = []
            for await value in group { values.append(value) }
            let order = Dictionary(uniqueKeysWithValues: response.interventions.enumerated().map { ($0.element.id, $0.offset) })
            return values.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        }
        return enriched
    }

    private func replaceOptimisticLog(id: String, with entry: BioLogEntry) {
        logEntries = Self.sorted(logEntries.map { $0.id == id ? entry : $0 })
    }

    private func retryQueuedMealPhoto(entryID: String) async {
        guard let item = mealPhotoQueueStore.item(id: entryID) else { return }
        let retrying = item.withLastError(nil)
        mealPhotoQueueStore.update(retrying)
        upsertMealPhotoEntry(retrying.optimisticEntry.replacingStatus(.pending))
        _ = await submitQueuedMealPhoto(retrying)
    }

    private func drainMealPhotoQueue() async {
        let queued = mealPhotoQueueStore.load()
        guard !queued.isEmpty else { return }
        for item in queued {
            upsertMealPhotoEntry(item.optimisticEntry.replacingStatus(.pending))
            _ = await submitQueuedMealPhoto(item.withLastError(nil))
        }
    }

    private func submitQueuedMealPhoto(_ item: QueuedMealPhoto) async -> Bool {
        do {
            let response = try await clientFactory(baseURL).recordBodyMealPhoto(
                imageBase64: item.imageBase64,
                caption: item.caption
            )
            guard response.ok else {
                markQueuedMealPhotoFailed(item, reason: response.error ?? "unknown")
                return false
            }

            mealPhotoQueueStore.remove(id: item.id)
            let saved = response.entry ?? item.optimisticEntry.replacingStatus(.saved)
            replaceOptimisticLog(id: item.id, with: saved.replacingStatus(.saved))
            setLogErrorText(nil)
            return true
        } catch {
            mealPhotoQueueStore.update(item.withLastError(nil))
            upsertMealPhotoEntry(item.optimisticEntry.replacingStatus(.queued))
            connectionState.transition(to: .offlineRetrying)
            return false
        }
    }

    private func markQueuedMealPhotoFailed(_ item: QueuedMealPhoto, reason: String) {
        let text = BioCopy.mealPhotoFailed(reason: reason)
        mealPhotoQueueStore.update(item.withLastError(reason))
        upsertMealPhotoEntry(item.optimisticEntry.replacingStatus(.failed(text)))
        setLogErrorText(text)
    }

    private func upsertMealPhotoEntry(_ entry: BioLogEntry) {
        if logEntries.contains(where: { $0.id == entry.id }) {
            replaceOptimisticLog(id: entry.id, with: entry)
        } else {
            logEntries = Self.sorted([entry] + logEntries)
        }
    }

    private func restoreQueuedMealPhotos() {
        let entries = mealPhotoQueueStore.load().map(\.optimisticEntry)
        guard !entries.isEmpty else { return }
        logEntries = Self.sorted(Self.merge(primary: logEntries, secondary: entries))
    }

    private func localLogEntries() -> [BioLogEntry] {
        let queuedEntries = mealPhotoQueueStore.load().map(\.optimisticEntry)
        return Self.merge(
            primary: logEntries.filter { $0.status.isLocal },
            secondary: queuedEntries
        )
    }

    private func failOptimisticLog(id: String, reason: String) {
        let text = BioCopy.logFailed(reason: reason)
        logEntries = Self.sorted(logEntries.map { entry in
            entry.id == id ? entry.replacingStatus(.failed(text)) : entry
        })
        setLogErrorText(text)
    }

    private func setLogErrorText(_ text: String?) {
        let previous = logErrorText
        logErrorText = text
        var triggers = feedbackTriggers
        triggers.record(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
        feedbackTriggers = triggers
    }

    private func setStopErrorText(_ text: String?) {
        let previous = stopErrorText
        stopErrorText = text
        var triggers = feedbackTriggers
        triggers.record(KFeedbackPolicy.errorSurfaced(previous: previous, current: text))
        feedbackTriggers = triggers
    }

    private static func merge(primary: [BioLogEntry], secondary: [BioLogEntry]) -> [BioLogEntry] {
        var seen: Set<String> = []
        var merged: [BioLogEntry] = []
        for entry in primary + secondary where seen.insert(entry.id).inserted {
            merged.append(entry)
        }
        return merged
    }

    private static func sorted(_ entries: [BioLogEntry]) -> [BioLogEntry] {
        entries.sorted { lhs, rhs in
            switch (lhs.sortDate, rhs.sortDate) {
            case let (left?, right?):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.at > rhs.at
            }
        }
    }
}

struct BioView: View {
    @StateObject private var model = BioModel()
    // Founder ruling 2026-08-04: bio always opens on nutrition (overridable via -biotab).
    @State private var selectedState: BioState = BioInitialState.resolve()
    private let pagerSelection: Binding<BioState>?
    @Binding private var stageRevealRequested: Bool
    // Founder 2026-08-05: the master/detail (rail-and-jut) sub-pages track their selection.
    @State private var selectedInterventionID: String?
    @State private var selectedNutritionDay: Date?
    @State private var selectedProtocolID: String?
    @State private var selectedBiomarkerID: String?
    @State private var selectedWorkoutID: String?
    @State private var isWorkoutArchivePresented = false

    init(
        pagerSelection: Binding<BioState>? = nil,
        stageRevealRequested: Binding<Bool> = .constant(false)
    ) {
        self.pagerSelection = pagerSelection
        _stageRevealRequested = stageRevealRequested
    }

    private var mealMicronutrientsSource: MealMicronutrientsSource {
        FixtureMealMicronutrientsSource.empty
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                // Founder centering law: content is centered, never edge-pinned. Founder
                // 2026-08-06: the top selector keeps a STABLE reading width so it does not
                // shift when a tab widens for the rail-and-jut — only the content breaks
                // out. The menu no longer moves between tabs.
                bioColumn(available: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(BioAccessibility.view)
        .onAppear {
            model.loadIfNeeded()
            syncPagerSelection()
            syncStageReveal()
        }
        .onChange(of: selectedState) { _, newState in
            syncStageReveal()
            guard pagerSelection?.wrappedValue != newState else { return }
            pagerSelection?.wrappedValue = newState
        }
        .onChange(of: pagerSelection?.wrappedValue) { _, newState in
            guard let newState, newState != selectedState else { return }
            selectedState = newState
            syncStageReveal()
        }
        .onDisappear { stageRevealRequested = false }
        .kSensoryFeedback(model.feedbackTriggers)
    }

    private func syncPagerSelection() {
        guard let pagerState = pagerSelection?.wrappedValue,
              pagerState != selectedState
        else { return }
        selectedState = pagerState
    }

    private func syncStageReveal() {
        stageRevealRequested = BioCameraStageRequest.isRequested(for: selectedState)
    }

    // Which tabs render as the rail-and-jut master/detail (BioRailDetail) rather than
    // a single scrolling column. Grows as each tab is ported; interventions is first
    // (it has real read-only data — phases, supplements, targets).
    private func usesRailDetail(_ state: BioState) -> Bool {
        switch state {
        case .biomarkers:
            return !model.biomarkerRecords.isEmpty
        case .protocols:
            return model.hasProtocolSurfaceData
        case .interventions:
            return !model.interventions.isEmpty
        case .nutrition:
            return !model.nutritionEntries.isEmpty
        case .overview:
            return isWorkoutArchivePresented && !model.workoutSessions.isEmpty
        }
    }

    // The top selector renders at a stable reading width (consistent with the other
    // surfaces); only the content area widens for the rail-and-jut, so switching tabs
    // never shifts the menu.
    private func bioColumn(available: CGFloat) -> some View {
        let headerWidth = KStyle.columnWidth(in: available)
        let railDetail = usesRailDetail(selectedState) || isWorkoutArchivePresented
        let contentWidth = railDetail
            ? max(headerWidth, min(available - KStyle.columnMargin * 2, KStyle.bioRailWidth + KStyle.columnMaxWidth))
            : headerWidth

        return VStack(spacing: 0) {
            // Bio's top chrome is the state selector only. Recency remains available
            // to content that needs it, but the founder-facing tab chrome stays quiet.
            BioTabStrip(selection: $selectedState, states: model.availableStates)
                .padding(.horizontal, KStyle.columnMargin)
                .padding(.bottom, KStyle.tightRowSpacing)
                .frame(width: headerWidth)

            ZStack {
                if railDetail {
                    // Rail-and-jut tabs manage their own scrolling and fill the frame;
                    // an outer vertical ScrollView would collapse the GeometryReader.
                    selectedContent
                        .padding(.horizontal, KStyle.columnMargin)
                        .padding(.bottom, KStyle.blockCardVerticalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(BioAccessibility.stateContent(selectedState))
                        .kAnimated(value: model.interventions)
                        .kAnimated(value: model.logEntries)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: KStyle.blockCardVerticalPadding) {
                            selectedContent
                        }
                        .padding(.horizontal, KStyle.columnMargin)
                        .padding(.bottom, KStyle.blockCardVerticalPadding * 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(BioAccessibility.stateContent(selectedState))
                        .kAnimated(value: model.systemCards)
                        .kAnimated(value: model.flagLines)
                        .kAnimated(value: model.logEntries)
                    }
                }
            }
            .frame(width: contentWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var selectedContent: some View {
        if isWorkoutArchivePresented {
            BioWorkoutArchive(
                sessions: model.workoutSessions,
                isLoading: model.isLoading && model.lastSyncAt == nil,
                selectedID: $selectedWorkoutID,
                onBack: {
                    KStyle.withGesturePageMotion { isWorkoutArchivePresented = false }
                }
            )
        } else if model.isLoading && model.lastSyncAt == nil {
            KLoadingPrimitive(
                variant: .skeleton,
                lineCount: 4,
                label: "loading \(selectedState.rawValue)",
                accessibilityIdentifier: "bio-loading-\(selectedState.rawValue)"
            )
        } else if model.connectionState.status == .offlineRetrying && model.lastSyncAt == nil {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                KMonoCaption(KCopy.offlineRetrying, variant: .inlineError, state: .offline)
                Spacer(minLength: KStyle.smallSpacing)
                KActRow(
                    actions: [KActItem(id: "retry")],
                    variant: .admin,
                    onSelect: { _ in Task { await model.load() } }
                )
            }
            .accessibilityIdentifier("bio-unreachable-\(selectedState.rawValue)")
        } else {
            switch selectedState {
            case .overview:
                BioOverviewSection(
                    cards: model.systemCards,
                    alert: model.overviewAlert,
                    onAddress: { selectedState = .biomarkers },
                    onMuscles: {
                        KStyle.withGesturePageMotion { isWorkoutArchivePresented = true }
                    },
                    onFeeling: { rating in
                        Task { await model.submitLog(kind: .note, text: "feeling \(rating)/9") }
                    }
                )
            case .biomarkers:
                if model.biomarkerRecords.isEmpty {
                    BioEmptyState(text: "no biomarker trend yet · panels and wearable history land here")
                } else {
                    BioBiomarkerRailDetail(
                        records: model.biomarkerRecords,
                        nextTests: model.nextTestRecords,
                        reports: model.reportRecords,
                        selectedID: $selectedBiomarkerID
                    )
                }
            case .protocols:
                if !model.hasProtocolSurfaceData {
                    BioEmptyState(text: "no protocols running · testing panels and their coverage land here")
                } else {
                    BioProtocolsSection(
                        testing: model.testingProtocols,
                        meditation: model.meditationProtocols,
                        selectedTestingID: $selectedProtocolID
                    )
                }
            case .interventions:
                if model.interventions.isEmpty {
                    BioEmptyState(text: "no interventions active · the levers k is tracking land here")
                } else {
                    BioInterventionRailDetail(
                        interventions: model.interventions,
                        selectedID: $selectedInterventionID,
                        stoppingInterventionIDs: model.stoppingInterventionIDs,
                        stopErrorText: model.stopErrorText,
                        onStop: { intervention in
                            await model.stopIntervention(intervention)
                        }
                    )
                }
            case .nutrition:
                if model.nutritionEntries.isEmpty {
                    BioNutritionSection(
                        asOfText: model.generatedAtText,
                        errorText: model.logErrorText,
                        onMealPhoto: { image, caption in
                            await model.submitMealPhoto(image: image, caption: caption)
                        }
                    )
                } else {
                    BioNutritionRailDetail(
                        entries: model.nutritionEntries,
                        errorText: model.logErrorText,
                        selectedDay: $selectedNutritionDay,
                        micronutrientsSource: mealMicronutrientsSource,
                        onMealPhoto: { image, caption in
                            await model.submitMealPhoto(image: image, caption: caption)
                        },
                        onRetryMealPhoto: { entry in
                            model.retryMealPhoto(entryID: entry.id)
                        }
                    )
                }
            }
        }
    }

}

// Bio's sub-pages use the shared KSelectorStrip grammar. The domain is different,
// but the material, type, spacing, target width, height, and active treatment stay
// shared so the founder never learns a second tab language.
private struct BioTabStrip: View {
    @Binding var selection: BioState
    let states: [BioState]

    var body: some View {
        KSelectorStrip(
            selection: $selection,
            items: states.map { state in
                KSelectorItem(
                    id: state,
                    title: state.rawValue,
                    accessibilityLabel: "\(state.rawValue) tab",
                    accessibilityIdentifier: BioAccessibility.stateSelectorItem(state)
                )
            },
            accessibilityIdentifier: BioAccessibility.stateSelector
        )
    }
}

// MARK: - Overview (cursafe v11 · 3×2 system grid)

private struct BioOverviewSection: View {
    let cards: [BioSystemCard]
    let alert: String?
    let onAddress: () -> Void
    let onMuscles: () -> Void
    let onFeeling: (Int) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: KStyle.bioSystemGridSpacing, alignment: .top),
            count: KStyle.bioSystemGridColumns
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioSystemGridSpacing) {
            LazyVGrid(columns: columns, spacing: KStyle.bioSystemGridSpacing) {
                ForEach(cards) { card in
                    BioSystemCardView(card: card, onMuscles: card.system == .muscles ? onMuscles : nil)
                }
            }

            if let alert {
                BioAlertRow(text: alert, onAddress: onAddress)
            }

            BioFeelingAsk(onSubmit: onFeeling)
        }
    }
}

private struct BioSystemCardView: View {
    let card: BioSystemCard
    let onMuscles: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioSystemRowSpacing) {
            Text(card.system.rawValue)
                .kFont(.content)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))

            Text(card.scoreText)
                .font(.system(size: KStyle.bioSystemScoreSize, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(card.hasData ? KStyle.primaryTextOpacity : KStyle.tertiaryTextOpacity))

            HStack(spacing: KStyle.smallSpacing) {
                KStatusDot(signal: card.tone.signal, state: card.isStale ? .stale : .resting, size: .small)
                Text(card.tone.word)
                    .kFont(.monoCaption)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            }

            Text(card.freshnessText)
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.quaternaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)

            if isOpen {
                Text(card.provenanceText)
                    .kFont(.monoCaption)
                    .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, KStyle.microSpacing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        .padding(KStyle.bioSystemCardPadding)
        // Stale metric age-fades; a fresh one reads at full strength.
        .opacity(card.isStale ? KStyle.bioStaleFadeOpacity : KStyle.fullOpacity)
        .kGlassCardTone()
        .contentShape(Rectangle())
        .onTapGesture {
            if let onMuscles {
                KStyle.withGesturePageMotion(reduceMotion: reduceMotion) { onMuscles() }
            } else {
                withAnimation(KStyle.motion(reduceMotion)) { isOpen.toggle() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bio-system-\(card.system.rawValue)")
    }
}

private struct BioAlertRow: View {
    let text: String
    let onAddress: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.cardPadding) {
            Text(text)
                .kFont(.content)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: KStyle.smallSpacing)
            KActRow(
                actions: [
                    KActItem(
                        id: "address",
                        label: "address",
                        accessibilityIdentifier: "bio-overview-address"
                    ),
                ],
                variant: .cadence,
                onSelect: { _ in onAddress() }
            )
            .environment(\.kInkOnPaper, true)
        }
        .padding(KStyle.bioSystemCardPadding)
        .kPaperCardTone()
    }
}

// An honest feeling check-in — a real input the founder answers, never a fabricated
// prediction. The scale selection logs a note through the same body-log write path.
private struct BioFeelingAsk: View {
    let onSubmit: (Int) -> Void

    @State private var submitted: Int?
    @State private var draftValue: Int?
    @State private var isDragging = false

    private let scale = Array(1...9)

    init(onSubmit: @escaping (Int) -> Void) {
        self.onSubmit = onSubmit
        _draftValue = State(initialValue: BioDemo.feelingMidDragCaptureEnabled ? 5 : nil)
        _isDragging = State(initialValue: BioDemo.feelingMidDragCaptureEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text(questionText)
                .kFont(.content)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))

            if submitted == nil {
                GeometryReader { proxy in
                    HStack(spacing: KStyle.smallSpacing) {
                        ForEach(scale, id: \.self) { value in
                            Button {
                                submit(value)
                            } label: {
                                ZStack {
                                    if value == draftValue {
                                        Circle()
                                            .fill(Color.white.opacity(KStyle.controlEnabledFillOpacity))
                                    }
                                    Text("\(value)")
                                        .kFont(.monoCaption)
                                        .foregroundStyle(value == draftValue
                                            ? KStyle.nearBlack
                                            : Color.white.opacity(KStyle.secondaryTextOpacity))
                                }
                                .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bio-feeling-\(value)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(scaleDrag(width: proxy.size.width))
                }
                .frame(minHeight: KStyle.minimumTapTarget)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bio-feeling-scale")
                .accessibilityValue(scaleAccessibilityValue)
                .accessibilityHint("drag to choose, or tap a number")
            } else {
                KActRow(
                    actions: [
                        KActItem(
                            id: "adjust",
                            label: "adjust",
                            accessibilityIdentifier: "bio-feeling-adjust"
                        ),
                    ],
                    variant: .cadence,
                    onSelect: { _ in
                        KStyle.withMotion {
                            submitted = nil
                            draftValue = nil
                            isDragging = false
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KStyle.bioSystemCardPadding)
        .kGlassCardTone()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bio-feeling-ask")
    }

    private var questionText: String {
        if let submitted {
            return "logged · feeling \(submitted)/9"
        }
        if isDragging, let draftValue {
            return "feeling \(draftValue)/9"
        }
        return "how are you feeling today?"
    }

    private var scaleAccessibilityValue: String {
        if isDragging, let draftValue {
            return "feeling \(draftValue) of 9, adjusting"
        }
        return "unanswered"
    }

    private func scaleDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: KStyle.bioFeelingScaleDragMinimumDistance)
            .onChanged { value in
                guard submitted == nil else { return }
                isDragging = true
                draftValue = BioFeelingScaleMath.value(
                    atX: value.location.x,
                    width: width,
                    count: scale.count
                )
            }
            .onEnded { value in
                guard submitted == nil else { return }
                let selected = BioFeelingScaleMath.value(
                    atX: value.location.x,
                    width: width,
                    count: scale.count
                )
                submit(selected)
            }
    }

    private func submit(_ value: Int) {
        guard submitted == nil else { return }
        KStyle.withMotion {
            submitted = value
            draftValue = nil
            isDragging = false
        }
        onSubmit(value)
    }
}

enum BioFeelingScaleMath {
    static func value(atX x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 1 else { return 1 }
        let ratio = min(max(x / width, 0), 1)
        let index = Int((ratio * CGFloat(count - 1)).rounded())
        return min(max(index + 1, 1), count)
    }
}

private struct BioEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .kFont(.content)
            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("bio-empty-state")
    }
}

// The capture glyph: a rounded-rect outline with four horizontal lines, stroked in the
// KStyle register (founder ruling 2026-08-04).
struct BioCaptureGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = min(rect.width, rect.height) * 0.22
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
        let inset = rect.width * 0.26
        let lines = 4
        for index in 1...lines {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(lines + 1)
            path.move(to: CGPoint(x: rect.minX + inset, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: y))
        }
        return path
    }
}

// Founder 2026-08-05: the bio demo seed. Off by default; enabled by the `-biodemo`
// launch arg or the `cskBioDemo` UserDefault. Fills ONLY empty slots with clearly
// sample data so the bio UI is visible before the real data pipeline lands. Never
// persisted; real records always win. The planned-row copy is pinned to the mock;
// copy follows k-copy (no hyphen, no em dash).
enum BioDemo {
    enum AuditState: String, Equatable {
        case empty
        case error
        case stopFailure = "stop-failure"
    }

#if DEBUG
    static var auditState: AuditState? {
        if ProcessInfo.processInfo.arguments.contains("-w19-bio-stop-failure") {
            return .stopFailure
        }
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-w11-bio-state"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1)
        else { return nil }
        return AuditState(rawValue: ProcessInfo.processInfo.arguments[index + 1].lowercased())
    }
#else
    static var auditState: AuditState? { nil }
#endif

    static let referenceNow = Date(timeIntervalSince1970: 1_786_353_600)

    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-biodemo")
            || UserDefaults.standard.bool(forKey: "cskBioDemo")
    }

    // Capture-only launch seams keep the interaction states deterministic in the
    // audit walk. They are inert unless the named DEBUG argument is supplied.
    static var holdProgressCaptureEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-bio-hold-progress")
#else
        false
#endif
    }

    static var feelingMidDragCaptureEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-bio-feeling-mid-drag")
#else
        false
#endif
    }

    static func overlay(onto base: BioArtifactsResponse) -> BioArtifactsResponse {
        BioArtifactsResponse(
            trend: base.trend,
            flags: base.flags.isEmpty ? flags : base.flags,
            today: overlayToday(base.today),
            interventions: base.interventions.isEmpty ? interventions : base.interventions,
            log: base.log.contains(where: { $0.kind == .meal }) ? base.log : base.log + meals,
            biomarkers: fillMissing(base.biomarkers, with: biomarkers),
            nextTests: fillMissing(base.nextTests, with: nextTests),
            reports: fillMissing(base.reports, with: reports),
            protocols: fillMissing(base.protocols, with: testingProtocols),
            meditationLibrary: fillMissing(base.meditationLibrary, with: meditationLibrary),
            generatedAt: base.generatedAt,
            source: base.source ?? "demo",
            ok: base.ok,
            error: base.error
        )
    }

    private static func overlayToday(_ real: BioToday?) -> BioToday {
        guard let real else { return today }
        return BioToday(
            recovery: real.recovery ?? today.recovery,
            sleep: real.sleep ?? today.sleep,
            hrv: real.hrv ?? today.hrv,
            strain: real.strain ?? today.strain,
            workout: real.workout ?? today.workout,
            cycle: real.cycle ?? today.cycle,
            calories: real.calories ?? today.calories
        )
    }

    private static func fillMissing<T: Identifiable>(
        _ real: [T],
        with demo: [T]
    ) -> [T] where T.ID == String {
        let realIDs = Set(real.map(\.id))
        return real + demo.filter { !realIDs.contains($0.id) }
    }

    // Spread across early august (midday UTC → same local day) so the calendar shows
    // on-target green days and a streak, plus the selected day from the mock: two
    // logged meals and one future meal waiting for its photo.
    static let meals: [BioLogEntry] = [
        // aug 3 · ~1950 kcal (on target → green)
        meal("d0301", "2026-08-03T02:00:00Z", "greek yogurt, granola, honey", "breakfast", 450, 30, 58, 12, 6, 22),
        meal("d0302", "2026-08-03T06:30:00Z", "turkey wrap, side salad", "lunch", 700, 48, 60, 24, 9, 8),
        meal("d0303", "2026-08-03T11:30:00Z", "steak, potatoes, broccoli", "dinner", 800, 52, 55, 34, 10, 6),
        // aug 4 · ~2050 kcal (on target → green; streak with aug 3)
        meal("d0401", "2026-08-04T02:00:00Z", "eggs, avocado toast", "breakfast", 520, 26, 40, 30, 9, 4),
        meal("d0402", "2026-08-04T06:30:00Z", "poke bowl", "lunch", 730, 42, 68, 22, 9, 11),
        meal("d0403", "2026-08-04T11:30:00Z", "pasta, chicken, salad", "dinner", 800, 46, 82, 24, 8, 9),
        // aug 5 · two logged meals, one planned meal
        meal("d0501", "2026-08-05T06:10:00Z", "poke bowl", "lunch", 640, 42, 68, 21, 9, 12, micronutrients: pokeMicronutrients),
        meal("d0502", "2026-08-05T09:40:00Z", "greek yogurt + berries", "snack", 210, 18, 22, 6, 4, 14, micronutrients: yogurtMicronutrients),
        plannedMeal("d0503", "2026-08-05T12:30:00Z", "dinner — photo when it happens", "dinner"),
    ]

    // W20 archive seed. Dates are offsets from referenceNow so the walk never
    // depends on the device clock. The projection is additive and demo-only.
    static let workouts: [BioWorkoutSession] = {
        let pullExercises = [
            BandishWorkoutExercise(id: "pull-down", name: "pull down", setsRepsWeight: "4 × 8 · 60 kg", completed: true),
            BandishWorkoutExercise(id: "single-row", name: "single arm row", setsRepsWeight: "4 × 10 · 32 kg", completed: true),
            BandishWorkoutExercise(id: "farmer-carry", name: "farmer carry", setsRepsWeight: "3 × 40 m", completed: false),
        ]
        let pullZones = [
            BandishWorkoutZone(zone: 1, minutes: 4),
            BandishWorkoutZone(zone: 2, minutes: 12),
            BandishWorkoutZone(zone: 3, minutes: 18),
            BandishWorkoutZone(zone: 4, minutes: 10),
            BandishWorkoutZone(zone: 5, minutes: 1),
        ]
        func day(_ daysAgo: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
            return calendar.date(byAdding: .day, value: -daysAgo, to: referenceNow) ?? referenceNow
        }
        return [
            BioWorkoutSession(
                id: "pull-day-aug-10",
                name: "pull day",
                date: day(0),
                durationMinutes: 45,
                info: BandishWorkoutInfo(
                    exercises: pullExercises,
                    strain: BandishWorkoutStrain(actual: 14.2, target: 16),
                    tonnage: BandishWorkoutTonnage(current: 4_820, previous: 4_520, change: 6.6),
                    heartRateZones: pullZones,
                    realTime: BandishWorkoutRealtime(heartRate: 142),
                    calories: 412,
                    recoveryHint: "leave tomorrow's work room",
                    source: "whoop"
                ),
                muscleGroups: ["back", "grip", "biceps"],
                trendNote: "tonnage climbing across three sessions · 4,180 to 4,820 kg · grip still the limiter, farmer carry skipped twice"
            ),
            BioWorkoutSession(
                id: "push-day-aug-7",
                name: "push day",
                date: day(3),
                durationMinutes: 38,
                info: BandishWorkoutInfo(source: "whoop"),
                muscleGroups: ["chest", "shoulders", "triceps"],
                trendNote: nil
            ),
            BioWorkoutSession(
                id: "pull-day-aug-6",
                name: "pull day",
                date: day(4),
                durationMinutes: 44,
                info: BandishWorkoutInfo(
                    tonnage: BandishWorkoutTonnage(current: 4_520),
                    source: "whoop"
                ),
                muscleGroups: ["back", "grip", "biceps"],
                trendNote: nil
            ),
            BioWorkoutSession(
                id: "pull-day-aug-3",
                name: "pull day",
                date: day(7),
                durationMinutes: 41,
                info: BandishWorkoutInfo(
                    tonnage: BandishWorkoutTonnage(current: 4_180),
                    source: "whoop"
                ),
                muscleGroups: ["back", "grip", "biceps"],
                trendNote: nil
            ),
        ]
    }()

    // These are deliberately sample readings, never a claim about the founder. The
    // real artifact wins field by field in overlayToday, while the empty demo path
    // has enough signal to exercise the populated overview and its alert row.
    static let today = BioToday(
        recovery: BioTodayMetric(
            value: 39,
            baseline: 68.3,
            deltaPct: -42.9,
            driftDirection: "down",
            label: "today",
            source: "whoop-api"
        ),
        sleep: BioTodayMetric(
            value: 7.4,
            baseline: 8.0,
            deltaPct: -7.5,
            driftDirection: "down",
            label: "today",
            source: "whoop-ble"
        ),
        hrv: BioTodayMetric(
            value: 51,
            baseline: 66.3,
            deltaPct: -23.1,
            driftDirection: "down",
            label: "today",
            source: "healthkit"
        )
    )

    static let flags = ["recovery 43% under your baseline · 6/30 samples"]

    private static func meal(
        _ id: String, _ at: String, _ text: String, _ name: String,
        _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, _ fiber: Double, _ sugar: Double,
        micronutrients: [MealMicronutrient]? = nil
    ) -> BioLogEntry {
        BioLogEntry(
            id: "demo-meal-\(id)", at: at, kind: .meal, text: text, mealName: name,
            mealMacros: MealMacroMeasurements(
                calories: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber, sugar: sugar
            ),
            micronutrients: micronutrients ?? FixtureMealMicronutrientsSource.typical.values
        )
    }

    private static let pokeMicronutrients: [MealMicronutrient] = [
        MealMicronutrient(id: "iron", label: "iron", amount: 4.1, unit: "mg", confidence: 0.7),
        MealMicronutrient(id: "b12", label: "b12", amount: 2.8, unit: "µg", confidence: 0.8),
        MealMicronutrient(id: "omega-3", label: "omega-3", amount: 1.9, unit: "g", confidence: 0.8),
        MealMicronutrient(id: "sodium", label: "sodium", amount: 890, unit: "mg", confidence: 0.9),
        MealMicronutrient(id: "potassium", label: "potassium", amount: 1.1, unit: "g", confidence: 0.8),
    ]

    private static let yogurtMicronutrients: [MealMicronutrient] = [
        MealMicronutrient(id: "calcium", label: "calcium", amount: 190, unit: "mg", confidence: 0.8),
        MealMicronutrient(id: "b12", label: "b12", amount: 1.1, unit: "µg", confidence: 0.8),
        MealMicronutrient(id: "probiotics", label: "probiotics", amount: 1, unit: "serving", confidence: 0.7),
        MealMicronutrient(id: "sugar", label: "sugar", amount: 14, unit: "g", confidence: 0.9),
    ]

    private static func plannedMeal(
        _ id: String,
        _ at: String,
        _ text: String,
        _ name: String
    ) -> BioLogEntry {
        BioLogEntry(
            id: "demo-meal-\(id)",
            at: at,
            kind: .meal,
            text: text,
            mealName: name,
            isPlanned: true
        )
    }

    static let interventions: [BioInterventionProjection] = [
        BioInterventionProjection(
            id: "demo-sleep-latency",
            title: "shorten sleep latency",
            rationale: "you fall asleep in about 25 minutes. magnesium and a wind down window aim to halve that.",
            category: "recovery",
            phases: [
                BioInterventionPhase(
                    name: "load", order: 1, durationDays: 14,
                    targetBiomarkers: [BioInterventionTarget(domain: "sleep", id: "onset latency")]
                ),
                BioInterventionPhase(
                    name: "maintain", order: 2, durationDays: 30,
                    targetBiomarkers: [BioInterventionTarget(domain: "sleep", id: "deep sleep")]
                ),
            ],
            supplements: [
                BioInterventionSupplement(name: "magnesium glycinate", dose: "300mg", timing: "dinner", withFood: true),
            ],
            targetBiomarkers: [BioInterventionTarget(domain: "sleep", id: "onset latency")],
            actionState: "active",
            currentPhase: 1
        ),
        BioInterventionProjection(
            id: "demo-zone2",
            title: "build an aerobic base",
            rationale: "three zone two sessions a week to lift hrv and lower resting heart rate.",
            category: "movement",
            phases: [
                BioInterventionPhase(
                    name: "ramp", order: 1, durationDays: 21,
                    targetBiomarkers: [BioInterventionTarget(domain: "heart", id: "resting hr")]
                ),
            ],
            supplements: [],
            targetBiomarkers: [BioInterventionTarget(domain: "heart", id: "hrv")]
        ),
        BioInterventionProjection(
            id: "demo-focus",
            title: "protect deep work mornings",
            rationale: "no meetings before noon. track focus blocks against afternoon energy.",
            category: "attention",
            phases: [],
            supplements: [
                BioInterventionSupplement(name: "l theanine", dose: "200mg", timing: "morning", withFood: false),
            ],
            targetBiomarkers: []
        ),
    ]

}

// Founder 2026-08-05: interventions ported onto the rail-and-jut master/detail.
// The rail is the levers k tracks (real read-only data); selecting one juts its
// white detail card with phases / supplements / targets and the daemon-backed
// lifecycle state. Stopping is deliberately a hold so the irreversible act is clear.
private struct BioInterventionRailDetail: View {
    let interventions: [BioInterventionProjection]
    @Binding var selectedID: String?
    let stoppingInterventionIDs: Set<String>
    let stopErrorText: String?
    let onStop: (BioInterventionProjection) async -> Void

    private var selected: BioInterventionProjection? {
        interventions.first { $0.id == selectedID } ?? interventions.first
    }

    var body: some View {
        BioRailDetail(hasDetail: selected != nil) {
            VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                ForEach(interventions) { item in
                    BioInterventionRailRow(
                        intervention: item,
                        isSelected: selected?.id == item.id,
                        onTap: { KStyle.withMotion { selectedID = item.id } }
                    )
                }
            }
            .padding(.trailing, KStyle.bioDetailOverlap)
            .padding(.bottom, KStyle.bioSystemGridSpacing)
        } detail: {
            if let selected {
                BioInterventionDetailContent(
                    intervention: selected,
                    isStopping: stoppingInterventionIDs.contains(selected.id),
                    stopErrorText: stopErrorText,
                    onStop: onStop
                )
            }
        }
    }
}

private struct BioInterventionRailRow: View {
    let intervention: BioInterventionProjection
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { isSelected ? .black : .white }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                if let title = intervention.title {
                    Text(title)
                        .kFont(.content)
                        .foregroundStyle(ink.opacity(KStyle.primaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
                BioInterventionPhasePill(intervention: intervention, foreground: ink)
                if let category = intervention.category {
                    Text(category)
                        .kFont(.monoCaption)
                        .foregroundStyle(ink.opacity(KStyle.tertiaryTextOpacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KStyle.bioSystemCardPadding)
            .background {
                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isSelected
                        ? KStyle.chatThreadFinishedFillOpacity
                        : KStyle.chatThreadCollapsedFillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(KStyle.hairlineOpacity), lineWidth: KStyle.hairlineWidth)
            }
            .shadow(
                color: Color.black.opacity(isSelected ? KStyle.bioDetailShadowOpacity : 0),
                radius: isSelected ? KStyle.bioDetailShadowRadius : 0,
                y: isSelected ? KStyle.bioDetailShadowY : 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isSelected)
        .zIndex(isSelected ? KStyle.bioRailSelectedItemZIndex : KStyle.bioRailUnselectedItemZIndex)
        .accessibilityIdentifier(BioAccessibility.intervention(intervention.id))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// The intervention detail — dark ink on the white forward card.
private struct BioInterventionDetailContent: View {
    let intervention: BioInterventionProjection
    let isStopping: Bool
    let stopErrorText: String?
    let onStop: (BioInterventionProjection) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            if let title = intervention.title {
                Text(title)
                    .kFont(.content)
                    .foregroundStyle(.black.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                BioInterventionPhasePill(intervention: intervention, foreground: .black)
                if intervention.phaseStatus == .active {
                    BioHoldToStop(interventionID: intervention.id, isPending: isStopping) {
                        await onStop(intervention)
                    }
                }
            }
            if let stopErrorText {
                VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                    KMonoCaption(stopErrorText, variant: .inlineError, state: .offline)
                        .fixedSize(horizontal: false, vertical: true)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "retry",
                                label: "retry",
                                accessibilityIdentifier: BioAccessibility.interventionStopRetry
                            ),
                        ],
                        variant: .admin,
                        onSelect: { _ in
                            Task { await onStop(intervention) }
                        }
                    )
                    .environment(\.kInkOnPaper, true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(BioAccessibility.interventionStopError)
                .accessibilityLabel(stopErrorText)
            }
            if let rationale = intervention.rationale {
                Text(rationale)
                    .kFont(.content)
                    .foregroundStyle(.black.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let metadataText = intervention.metadataText {
                Text(metadataText)
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(intervention.phases) { phase in
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    if let summaryText = phase.summaryText {
                        Text(summaryText)
                            .kFont(.content)
                            .foregroundStyle(.black.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let targetsText = phase.targetsText {
                        Text("targets · \(targetsText)")
                            .kFont(.monoCaption)
                            .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !intervention.supplements.isEmpty {
                Text("supplements")
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(KStyle.quaternaryTextOpacity))
                ForEach(intervention.supplements) { supplement in
                    if let summaryText = supplement.summaryText {
                        Text(summaryText)
                            .kFont(.content)
                            .foregroundStyle(.black.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let targetsText = intervention.targetsText {
                Text("targets · \(targetsText)")
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BioInterventionPhasePill: View {
    let intervention: BioInterventionProjection
    let foreground: Color

    var body: some View {
        KMonoCaption(intervention.phaseText, variant: .metadata)
            .foregroundStyle(foreground.opacity(KStyle.tertiaryTextOpacity))
            .padding(.horizontal, KStyle.microSpacing)
            .padding(.vertical, KStyle.microSpacing / 2)
            .background {
                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                    .fill(foreground.opacity(KStyle.quaternaryTextOpacity))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("phase \(intervention.phaseText)")
            .accessibilityIdentifier("bio-intervention-phase-\(intervention.id)")
    }
}

private struct BioHoldToStop: View {
    let interventionID: String
    let isPending: Bool
    let onStop: () async -> Void
    @State private var fillProgress: Double
    @State private var stateMachine = BioHoldToStopStateMachine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(interventionID: String, isPending: Bool, onStop: @escaping () async -> Void) {
        self.interventionID = interventionID
        self.isPending = isPending
        self.onStop = onStop
        _fillProgress = State(initialValue: BioDemo.holdProgressCaptureEnabled ? KStyle.sampleProgressRatio : 0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.black.opacity(KStyle.holdToCompleteTrackOpacity),
                    lineWidth: KStyle.holdToCompleteRingWidth
                )
            Circle()
                .trim(from: 0, to: fillProgress)
                .stroke(
                    Color.black,
                    style: StrokeStyle(lineWidth: KStyle.holdToCompleteRingWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "stop.fill")
                .font(KStyle.cadenceCompleteCheckIconFont)
                .foregroundStyle(.black.opacity(KStyle.primaryTextOpacity))
        }
        .frame(width: KStyle.holdToCompleteDiameter, height: KStyle.holdToCompleteDiameter)
        .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
        .opacity(isPending ? KStyle.quaternaryTextOpacity : KStyle.fullOpacity)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: KStyle.holdToCompleteDuration,
            maximumDistance: KStyle.holdToCompleteMaxDistance,
            pressing: { pressing in
                stateMachine.pressing(pressing)
                withAnimation(KStyle.holdToCompleteMotion(pressing: pressing, reduceMotion: reduceMotion)) {
                    fillProgress = pressing ? 1 : 0
                }
            },
            perform: {
                guard !isPending else { return }
                guard stateMachine.complete() else { return }
                Task { await onStop() }
            }
        )
        .disabled(isPending)
        .accessibilityElement()
        .accessibilityLabel("hold to stop")
        .accessibilityIdentifier("bio-intervention-stop-\(interventionID)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !isPending else { return }
            Task { await onStop() }
        }
    }
}

private struct BioNutritionSection: View {
    let asOfText: String?
    let errorText: String?
    let onMealPhoto: (UIImage, String?) async -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.cardPadding) {
            HStack(alignment: .center, spacing: KStyle.smallSpacing) {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    Text("nutrition")
                        .kFont(.content)
                        .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    if let asOfText {
                        KMonoCaption(asOfText.lowercased(), variant: .metadata)
                    }
                }
                Spacer(minLength: 0)
                MealPhotoButton(
                    caption: nil,
                    style: .captureGlyph,
                    accessibilityIdentifier: BioAccessibility.mealCapture,
                    onImage: onMealPhoto
                )
            }

            if let errorText {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("no meals logged yet · tap capture to photo the first")
                .kFont(.content)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Founder 2026-08-05 (cd conformance, build order #1): nutrition ported to the
// rail-and-jut mock (§430–480). Rail = a month calendar (green = on-target day, tap to
// select); detail = the selected day's header + meal timeline, each meal expanding to its
// macro grid, with the real photo capture as the quiet act. Meal micronutrients remain
// silent until the projection or the fixture source provides them.
struct BioCalendarWeekSlice {
    static func monthWeeks(
        for monthAnchor: Date,
        calendar: Calendar = .current
    ) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor),
              let range = calendar.range(of: .day, in: .month, for: monthAnchor)
        else { return [] }

        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in range {
            if let day = calendar.date(byAdding: .day, value: offset - 1, to: first) {
                cells.append(calendar.startOfDay(for: day))
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<$0 + 7])
        }
    }

    static func currentWeekIndex(
        in weeks: [[Date?]],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        let target = calendar.startOfDay(for: referenceDate)
        return weeks.firstIndex { week in
            week.contains { day in
                day.map { calendar.isDate($0, inSameDayAs: target) } ?? false
            }
        } ?? max(0, weeks.count - 1)
    }

    static func visibleWeekIndices(
        in weeks: [[Date?]],
        isExpanded: Bool,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        guard !weeks.isEmpty else { return [] }
        return isExpanded
            ? Array(weeks.indices)
            : [currentWeekIndex(in: weeks, referenceDate: referenceDate, calendar: calendar)]
    }
}

enum BioCalendarRevealGesture {
    static func nextState(isExpanded: Bool, magnification: CGFloat) -> Bool? {
        if magnification > KStyle.bioCalendarPinchExpandThreshold, !isExpanded {
            return true
        }
        if magnification < KStyle.bioCalendarPinchCollapseThreshold, isExpanded {
            return false
        }
        return nil
    }
}

private struct BioNutritionRailDetail: View {
    let entries: [BioLogEntry]
    let errorText: String?
    @Binding var selectedDay: Date?
    let micronutrientsSource: MealMicronutrientsSource
    let onMealPhoto: (UIImage, String?) async -> Bool
    let onRetryMealPhoto: (BioLogEntry) -> Void

    // Founder 2026-08-06: the calendar loads showing only the current week; the full
    // month reveals on expansion through the pinch-depth gesture.
    @State private var calendarExpanded = false

    private var calendar: Calendar { Calendar.current }

    private var mealsByDay: [Date: [BioLogEntry]] {
        var out: [Date: [BioLogEntry]] = [:]
        for entry in entries {
            guard let date = BioDateParser.dateTime(from: entry.at) else { continue }
            out[calendar.startOfDay(for: date), default: []].append(entry)
        }
        return out
    }

    private var kcalByDay: [Date: Double] {
        mealsByDay.mapValues { meals in meals.reduce(0) { $0 + ($1.mealMacros?.calories ?? 0) } }
    }

    private var daysWithMeals: [Date] { mealsByDay.keys.sorted() }

    // Doctrine: spatial-continuity. The calendar cell is the only selection state;
    // the detail reads that same day, including a legitimate empty day, instead of
    // silently falling back to the last meal.
    private var selectedOrigin: Date? {
        if let selectedDay {
            return calendar.startOfDay(for: selectedDay)
        }
        return daysWithMeals.last
    }

    private var monthAnchor: Date { selectedOrigin ?? Date() }

    var body: some View {
        BioRailDetail(hasDetail: selectedOrigin != nil) {
            BioNutritionCalendarRail(
                monthAnchor: monthAnchor,
                selectedDay: selectedOrigin,
                kcalByDay: kcalByDay,
                isExpanded: calendarExpanded,
                onSetExpanded: { expanded in
                    calendarExpanded = expanded
                },
                onSelectDay: { day in KStyle.withMotion { selectedDay = day } }
            )
        } detail: {
            if let day = selectedOrigin {
                BioNutritionDayDetail(
                    day: day,
                    meals: (mealsByDay[day] ?? []).sorted { $0.at < $1.at },
                    errorText: errorText,
                    micronutrientsSource: micronutrientsSource,
                    onMealPhoto: onMealPhoto,
                    onRetryMealPhoto: onRetryMealPhoto
                )
            }
        }
        .onAppear {
            if selectedDay == nil, let firstSelection = daysWithMeals.last {
                selectedDay = firstSelection
            }
        }
    }
}

private struct BioNutritionCalendarRail: View {
    let monthAnchor: Date
    let selectedDay: Date?
    let kcalByDay: [Date: Double]
    let isExpanded: Bool
    let onSetExpanded: (Bool) -> Void
    let onSelectDay: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var calendar: Calendar { Calendar.current }
    private let weekdayHeaders = ["m", "t", "w", "t", "f", "s", "s"]

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM"
        return f.string(from: monthAnchor).uppercased()
    }

    private var weeks: [[Date?]] { BioCalendarWeekSlice.monthWeeks(for: monthAnchor, calendar: calendar) }

    private var visibleWeeks: [Int] {
        BioCalendarWeekSlice.visibleWeekIndices(
            in: weeks,
            isExpanded: isExpanded,
            // Keep the selected origin in the visible week. Using the wall clock
            // here made the detail jut to one day while the rail showed another.
            referenceDate: selectedDay ?? monthAnchor,
            calendar: calendar
        )
    }

    private func isOnTarget(_ day: Date) -> Bool {
        guard let kcal = kcalByDay[day], kcal > 0 else { return false }
        let t = KStyle.bioNutritionDailyTargetKcal
        return abs(kcal - t) <= t * KStyle.bioNutritionTargetTolerance
    }

    private func isSelected(_ day: Date) -> Bool {
        selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
    }

    private func hasGreen(week: Int, col: Int) -> Bool {
        guard weeks.indices.contains(week), weeks[week].indices.contains(col),
              let day = weeks[week][col] else { return false }
        return isOnTarget(day)
    }

    // Corner-merge so a streak of good days reads as one pill. Vertical merge only when the
    // full month is shown; in the week view neighbours above/below are hidden.
    private func corners(week: Int, col: Int) -> RectangleCornerRadii {
        let r = KStyle.bioChipCornerRadius
        let left = col != 0 && hasGreen(week: week, col: col - 1)
        let right = col != 6 && hasGreen(week: week, col: col + 1)
        let top = isExpanded && hasGreen(week: week - 1, col: col)
        let bottom = isExpanded && hasGreen(week: week + 1, col: col)
        return RectangleCornerRadii(
            topLeading: (!left && !top) ? r : 0,
            bottomLeading: (!left && !bottom) ? r : 0,
            bottomTrailing: (!right && !bottom) ? r : 0,
            topTrailing: (!right && !top) ? r : 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text(monthTitle)
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))

            HStack(spacing: KStyle.bioCalendarCellSpacing) {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .kFont(.monoCaption)
                        .foregroundStyle(.white.opacity(KStyle.quaternaryTextOpacity))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(visibleWeeks, id: \.self) { week in
                HStack(spacing: KStyle.bioCalendarCellSpacing) {
                    ForEach(Array(weeks[week].enumerated()), id: \.offset) { col, cell in
                        if let day = cell {
                            BioCalendarDayCell(
                                day: day,
                                kcal: kcalByDay[day],
                                isSelected: isSelected(day),
                                isOnTarget: isOnTarget(day),
                                cornerRadii: corners(week: week, col: col),
                                onTap: { onSelectDay(day) }
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: KStyle.bioCalendarCellHeight)
                        }
                    }
                }
            }

            Text("green = kcal within ±10% of 2000 · merged runs are streaks")
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.quaternaryTextOpacity))
        }
        .padding(.trailing, KStyle.bioDetailOverlap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .gesture(
            MagnificationGesture()
                .onEnded { value in
                    guard let nextState = BioCalendarRevealGesture.nextState(
                        isExpanded: isExpanded,
                        magnification: value
                    ) else { return }
                    onSetExpanded(nextState)
                }
        )
        .accessibilityLabel(isExpanded ? "calendar month" : "calendar current week")
        .animation(KStyle.nativeMotion(.zen, reduceMotion: reduceMotion), value: isExpanded)
    }

}

private struct BioCalendarDayCell: View {
    let day: Date
    let kcal: Double?
    let isSelected: Bool
    let isOnTarget: Bool
    let cornerRadii: RectangleCornerRadii
    let onTap: () -> Void

    private var dayNumber: String { "\(Calendar.current.component(.day, from: day))" }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isOnTarget {
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(KStyle.resultClean.opacity(KStyle.bioCalendarOnTargetFillOpacity))
                }
                if isSelected {
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(Color.white.opacity(KStyle.chatThreadCollapsedFillOpacity))
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Text(dayNumber)
                            .kFont(.monoCaptionDigit)
                            .foregroundStyle(.white.opacity(isSelected ? KStyle.primaryTextOpacity : KStyle.secondaryTextOpacity))
                        Spacer(minLength: 0)
                        if isToday {
                            Circle()
                                .fill(.white.opacity(KStyle.tertiaryTextOpacity))
                                .frame(width: KStyle.bioCalendarDotSize, height: KStyle.bioCalendarDotSize)
                        }
                    }
                    Spacer(minLength: 0)
                    if let kcal, kcal > 0 {
                        Text("\(Int(kcal.rounded()))")
                            .kFont(.monoCaption)
                            .foregroundStyle(.white.opacity(KStyle.quaternaryTextOpacity))
                    }
                }
                .padding(KStyle.smallSpacing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: KStyle.bioCalendarCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? KStyle.bioRailSelectedItemZIndex : KStyle.bioRailUnselectedItemZIndex)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(BioAccessibility.nutritionCalendarDay(day))
    }
}

private struct BioNutritionDayDetail: View {
    let day: Date
    let meals: [BioLogEntry]
    let errorText: String?
    let micronutrientsSource: MealMicronutrientsSource
    let onMealPhoto: (UIImage, String?) async -> Bool
    let onRetryMealPhoto: (BioLogEntry) -> Void

    private var loggedMeals: [BioLogEntry] {
        meals.filter { !$0.isPlanned }
    }

    private var plannedMeals: [BioLogEntry] {
        meals.filter(\.isPlanned)
    }

    private var kcalSoFar: Int {
        Int(loggedMeals.reduce(0) { $0 + ($1.mealMacros?.calories ?? 0) }.rounded())
    }

    private var daySubline: String {
        let target = KStyle.bioNutritionDailyTargetKcal
        let onTrack = plannedMeals.isEmpty
            ? Double(kcalSoFar) >= target * (1 - KStyle.bioNutritionTargetTolerance)
            : Double(kcalSoFar) <= target
        return "\(loggedMeals.count) logged · \(plannedMeals.count) planned · \(kcalSoFar) kcal so far · \(onTrack ? "on track" : "over target")"
    }

    private var header: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.cardPadding) {
            Text(header)
                .kFont(.content)
                .foregroundStyle(.black.opacity(KStyle.primaryTextOpacity))
                .accessibilityIdentifier("bio-nutrition-day")
            Text(daySubline)
                .kFont(.monoCaption)
                .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bio-nutrition-day-subline")
            if let errorText {
                Text(errorText)
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }

            BioNutritionMealTimeline(
                meals: meals,
                micronutrientsSource: micronutrientsSource,
                onMealPhoto: onMealPhoto,
                onRetry: onRetryMealPhoto
            )

            // Quiet acts per bio-v11 §nutrition: dim until relevant — the
            // meal-write backend is not wired yet, so the acts render
            // disabled rather than swallowing taps.
            KActRow(
                actions: [
                    KActItem(
                        id: "add-meal",
                        label: "add meal",
                        isEnabled: false,
                        accessibilityIdentifier: "bio-nutrition-add-meal"
                    ),
                    KActItem(
                        id: "photo",
                        label: "photo",
                        isEnabled: false,
                        accessibilityIdentifier: "bio-nutrition-photo"
                    ),
                    KActItem(
                        id: "supplement",
                        label: "supplement",
                        isEnabled: false,
                        accessibilityIdentifier: "bio-nutrition-supplement"
                    ),
                ],
                variant: .cadence,
                onSelect: { _ in }
            )
            .environment(\.kInkOnPaper, true)
            .accessibilityIdentifier(BioAccessibility.nutritionQuickActs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.kInkOnPaper, true)
    }
}

// Daily summary (web app: big calories + target-relative macro bars). Grayscale bars,
// not the web's blue — K doctrine reserves hue for real status only.
// Founder 2026-08-06: nutrients carry a reference RANGE. A value out of the optimal band
// reads yellow (near an edge) or red (past an edge) with a minimal dot by its name; in-band
// nutrients grey out. Every nutrient shows a value + a range bar. 3 columns.
private struct BioNutrient: Identifiable {
    let name: String
    let value: Double
    let unit: String
    let low: Double
    let optimalLow: Double
    let optimalHigh: Double
    let high: Double

    var id: String { name }

    enum Status { case red, yellow, green }
    var status: Status {
        if value < low || value > high { return .red }
        if value < optimalLow || value > optimalHigh { return .yellow }
        return .green
    }

    // A macro band derived from its daily target: optimal ±20%, edges ±40%.
    static func macro(_ name: String, _ value: Double, target: Double) -> BioNutrient {
        BioNutrient(name: name, value: value, unit: "g",
                    low: target * 0.6, optimalLow: target * 0.8,
                    optimalHigh: target * 1.2, high: target * 1.4)
    }

}

private struct BioNutrientRangeBar: View {
    let nutrient: BioNutrient

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(1, nutrient.high - nutrient.low)
            let clamped = min(max(nutrient.value, nutrient.low), nutrient.high)
            ZStack(alignment: .leading) {
                Capsule().fill(KStyle.nearBlack.opacity(KStyle.bioRangeTrackInkOpacity))
                Capsule()
                    .fill(KStyle.nearBlack.opacity(KStyle.bioRangeBandInkOpacity))
                    .frame(width: w * (nutrient.optimalHigh - nutrient.optimalLow) / span)
                    .offset(x: w * (nutrient.optimalLow - nutrient.low) / span)
                Circle()
                    .fill(KStyle.nearBlack.opacity(KStyle.bioRangeDotInkOpacity))
                    .frame(width: KStyle.bioNutritionRangeDotSize, height: KStyle.bioNutritionRangeDotSize)
                    .offset(x: min(
                        w - KStyle.bioNutritionRangeDotSize,
                        max(
                            0,
                            w * (clamped - nutrient.low) / span
                                - KStyle.bioNutritionRangeDotSize / 2
                        )
                    ))
            }
        }
        .frame(height: KStyle.bioNutritionRangeBarHeight)
    }
}

private struct BioNutrientRow: View {
    let nutrient: BioNutrient

    private var tint: Color {
        switch nutrient.status {
        case .red: return KStyle.inlineError
        case .yellow: return KStyle.resultNotes
        case .green: return KStyle.nearBlack.opacity(KStyle.bioRangeDotInkOpacity)
        }
    }
    private var concern: Bool { nutrient.status != .green }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            HStack(spacing: KStyle.microSpacing) {
                if concern {
                    Circle()
                        .fill(tint)
                        .frame(width: KStyle.bioNutrientStatusDotSize, height: KStyle.bioNutrientStatusDotSize)
                }
                Text(nutrient.name)
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(concern ? KStyle.tertiaryTextOpacity : KStyle.quaternaryTextOpacity))
                Spacer(minLength: 0)
                Text("\(Int(nutrient.value.rounded()))\(nutrient.unit)")
                    .kFont(.monoCaptionDigit)
                    .foregroundStyle(.black.opacity(concern ? KStyle.secondaryTextOpacity : KStyle.quaternaryTextOpacity))
            }
            BioNutrientRangeBar(nutrient: nutrient)
        }
        .opacity(concern ? KStyle.fullOpacity : KStyle.bioNeutralNutrientOpacity)
    }
}

private struct BioNutritionDaySummary: View {
    let meals: [BioLogEntry]

    private func total(_ key: (MealMacroMeasurements) -> Double?) -> Double {
        meals.reduce(0) { $0 + ($1.mealMacros.flatMap(key) ?? 0) }
    }

    private var nutrients: [BioNutrient] {
        var out: [BioNutrient] = [
            .macro("protein", total { $0.protein }, target: KStyle.bioNutritionProteinTarget),
            .macro("carbs", total { $0.carbs }, target: KStyle.bioNutritionCarbsTarget),
            .macro("fat", total { $0.fat }, target: KStyle.bioNutritionFatTarget),
            .macro("fiber", total { $0.fiber }, target: KStyle.bioNutritionFiberTarget),
        ]
        let sugar = total { $0.sugar }
        if sugar > 0 {
            out.append(BioNutrient(name: "sugar", value: sugar, unit: "g",
                                   low: 0, optimalLow: 0, optimalHigh: 40, high: 70))
        }
        return out
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: KStyle.cardPadding, alignment: .top), count: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                let kcal = Int(total { $0.calories }.rounded())
                Text(kcal > 0 ? "\(kcal)" : "—")
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.black.opacity(KStyle.primaryTextOpacity))
                Text("calories")
                    .kFont(.monoCaption)
                    .foregroundStyle(.black.opacity(KStyle.quaternaryTextOpacity))
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: KStyle.smallSpacing) {
                ForEach(nutrients) { BioNutrientRow(nutrient: $0) }
            }
        }
    }
}

// The meal timeline follows the mock's three-column grammar: gutter time, axis, then
// the meal body. A logged row is quiet by default; its deep reveal grows from that row
// and displaces the rows below it (doctrine: spatial-continuity).
private struct BioNutritionMealTimeline: View {
    let meals: [BioLogEntry]
    let micronutrientsSource: MealMicronutrientsSource
    let onMealPhoto: (UIImage, String?) async -> Bool
    let onRetry: (BioLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text("meals")
                .kFont(.monoCaption)
                .foregroundStyle(.black.opacity(KStyle.quaternaryTextOpacity))
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(KStyle.nearBlack.opacity(KStyle.bioMealTimelineSpineOpacity))
                    .frame(width: KStyle.hairlineWidth)
                    .padding(.leading, KStyle.bioMealTimelineGutterWidth + KStyle.bioMealTimelineSpineLeading)
                    .padding(.vertical, KStyle.bioMealTimelineSpineVerticalPadding)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(meals.enumerated()), id: \.element.id) { _, meal in
                        BioMealTimelineRow(
                            meal: meal,
                            micronutrientsSource: micronutrientsSource,
                            onMealPhoto: onMealPhoto,
                            onRetry: { onRetry(meal) }
                        )
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bio-nutrition-meals")
        }
    }
}

private struct BioMealMicronutrientsSection: View {
    let nutrients: [MealMicronutrient]

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: MealMicronutrientsPresentation {
        MealMicronutrientsPresentation(nutrients: nutrients)
    }

    var body: some View {
        if presentation.isVisible {
            VStack(alignment: .leading, spacing: KStyle.microSectionSpacing) {
                Text("micronutrients")
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.tertiaryTextOpacity))

                VStack(alignment: .leading, spacing: KStyle.microRowSpacing) {
                    ForEach(presentation.visibleNutrients(isExpanded: isExpanded)) { nutrient in
                        BioMealMicronutrientRow(nutrient: nutrient)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onEnded { magnification in
                        guard let nextState = MealMicronutrientsRevealGesture.nextState(
                            isExpanded: isExpanded,
                            magnification: magnification
                        ) else { return }
                        KStyle.withMotion(reduceMotion: reduceMotion) {
                            isExpanded = nextState
                        }
                    }
            )
            .animation(KStyle.microRevealMotion(reduceMotion), value: isExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(BioAccessibility.mealMicronutrients)
            .accessibilityLabel("micronutrients")
            .accessibilityHint("pinch out to show all micronutrients")
        }
    }
}

private struct BioMealMicronutrientRow: View {
    let nutrient: MealMicronutrient

    private var confidence: Double {
        min(max(nutrient.confidence, 0), 1)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(nutrient.label)
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.secondaryTextOpacity))
            Spacer(minLength: 0)
            Text(nutrient.valueText)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.primaryTextOpacity))
        }
        .padding(.vertical, KStyle.microRowVerticalPadding)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(KStyle.nearBlack.opacity(KStyle.microConfidenceTrackOpacity))
                    Rectangle()
                        .fill(KStyle.nearBlack.opacity(KStyle.microConfidenceFillOpacity))
                        .frame(width: proxy.size.width * CGFloat(confidence))
                }
            }
        }
        .opacity(KStyle.microConfidenceOpacity(confidence))
    }
}

private struct BioMealTimelineRow: View {
    let meal: BioLogEntry
    let micronutrientsSource: MealMicronutrientsSource
    let onMealPhoto: (UIImage, String?) async -> Bool
    let onRetry: () -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var macros: MealMacroMeasurements? {
        guard let m = meal.mealMacros, m.hasMeasurement else { return nil }
        return m
    }

    private var micronutrients: [MealMicronutrient] {
        micronutrientsSource.micronutrients(for: meal)
    }

    private var microText: String? {
        MealMicronutrientText.compactLine(for: micronutrients)
    }

    private func activate() {
        if meal.canRetryMealPhoto {
            onRetry()
        } else if !meal.isPlanned {
            KStyle.withMotion(reduceMotion: reduceMotion) {
                isExpanded.toggle()
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if meal.isPlanned {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(BioAccessibility.nutritionMeal(meal.id))
                    .accessibilityValue("planned")
            }

            Text(meal.displayTime)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                .frame(width: KStyle.bioMealTimelineGutterWidth, alignment: .trailing)
                .padding(.trailing, KStyle.bioMealTimelineGutterTrailing)

            ZStack(alignment: .top) {
                Circle()
                    .fill(meal.isPlanned ? Color.clear : KStyle.emphasisInk)
                    .overlay {
                        Circle().stroke(
                            KStyle.nearBlack.opacity(KStyle.bioMealTimelineDotBorderOpacity),
                            lineWidth: KStyle.bioMealTimelineDotBorderWidth
                        )
                    }
                    .frame(width: KStyle.bioMealTimelineDotSize, height: KStyle.bioMealTimelineDotSize)
                    .padding(.top, KStyle.microSpacing - KStyle.hairlineWidth)
            }
            .frame(width: KStyle.bioMealTimelineAxisWidth, alignment: .top)

            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text(meal.displayText)
                        .kFont(.content)
                        .foregroundStyle(.black.opacity(meal.isPlanned
                            ? KStyle.bioPaperTertiaryOpacity
                            : KStyle.primaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let kcal = macros?.calories {
                        Text("\(Int(kcal.rounded())) kcal")
                            .kFont(.monoCaptionDigit)
                            .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                    }
                }

                if isExpanded, !meal.isPlanned {
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        BioMealPhotoSlot(mealID: meal.id, onImage: onMealPhoto)

                        if let macros {
                            BioMacroGrid(
                                macros: macros,
                                onLight: true
                            )
                            .accessibilityIdentifier(BioAccessibility.nutritionMealMacros(meal.id))
                        }

                        if let microText {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(microText)
                                    .kFont(.monoCaption)
                                    .foregroundStyle(.black.opacity(KStyle.tertiaryTextOpacity))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(BioAccessibility.nutritionMealMicroRow(meal.id))
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(BioAccessibility.mealMicronutrients)
                        }
                    }
                    .padding(.top, KStyle.hairlineWidth)
                    .transition(.opacity)
                }
            }
            .padding(.leading, KStyle.bioMealTimelineBodyLeading)
        }
        .padding(.bottom, KStyle.bioMealTimelineRowBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .kAnimated(value: isExpanded)
        // A planned row has no expandable child content. Make the row itself
        // the accessibility element so SwiftUI does not flatten its quiet
        // labels into the timeline container (the logged branch keeps its
        // contained children for the macro/photo drill-in).
        .accessibilityElement(children: meal.isPlanned ? .combine : .contain)
        .accessibilityIdentifier(BioAccessibility.nutritionMeal(meal.id))
        .accessibilityLabel(meal.isPlanned ? "planned \(meal.displayText)" : meal.displayText)
        .accessibilityValue(meal.isPlanned ? "planned" : (isExpanded ? "expanded" : "collapsed"))
        .accessibilityHint(meal.canRetryMealPhoto ? "tap to retry" : (meal.isPlanned ? "future meal" : "tap to expand"))
        // Planned rows are still a founder-visible timeline item. Keep the row
        // in the XCUI tree so the audit can recognize the seeded future meal;
        // activation remains a no-op for planned entries. (Doctrine:
        // recognition-over-recall, affordance-honesty, silence-default.)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
    }
}

private struct BioMealPhotoSlot: View {
    let mealID: String
    let onImage: (UIImage, String?) async -> Bool

    var body: some View {
        RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
            .fill(KStyle.nearBlack.opacity(KStyle.microConfidenceTrackOpacity))
            .frame(width: KStyle.bioMealPhotoSlotWidth, height: KStyle.bioMealPhotoSlotHeight)
            .overlay {
                MealPhotoButton(
                    caption: nil,
                    foregroundColor: .black,
                    style: .captureGlyph,
                    accessibilityIdentifier: BioAccessibility.nutritionMealPhotoSlot(mealID),
                    onImage: onImage
                )
            }
    }
}

private struct BioMacroGrid: View {
    let macros: MealMacroMeasurements
    var onLight: Bool = false

    private var ink: Color { onLight ? .black : .white }

    var body: some View {
        let cells: [(String, Double?)] = [
            ("protein", macros.protein),
            ("carbs", macros.carbs),
            ("fat", macros.fat),
            ("fiber", macros.fiber),
        ].filter { $0.1 != nil }
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: KStyle.smallSpacing, alignment: .leading),
                count: 4
            ),
            alignment: .leading,
            spacing: KStyle.smallSpacing
        ) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: KStyle.hairlineWidth) {
                    Text(cell.0.uppercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(ink.opacity(KStyle.quaternaryTextOpacity))
                    Text("\(Int((cell.1 ?? 0).rounded()))g")
                        .kFont(.monoCaptionDigit)
                        .foregroundStyle(ink.opacity(KStyle.secondaryTextOpacity))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

enum MealPhotoButtonStyle: Equatable {
    case text
    case captureGlyph
}

struct MealPhotoButton: View {
    let caption: String?
    var isEnabled = true
    var foregroundColor: Color = .white
    var state: KPrimitiveInteractionState = .resting
    var style: MealPhotoButtonStyle = .text
    var accessibilityIdentifier = "meal-photo"
    let onImage: (UIImage, String?) async -> Bool
    var onVideo: (URL) -> Void = { _ in }

    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
    @State private var captureIntent: MealCaptureIntent = .photo
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPending = false
    @State private var localErrorText: String?
    @State private var gestureStateMachine = MealCaptureGestureStateMachine()
    @State private var didCommitHold = false

    var body: some View {
        VStack(alignment: .trailing, spacing: KStyle.microSpacing) {
            Button {
                guard !didCommitHold else {
                    didCommitHold = false
                    return
                }
                localErrorText = nil
                captureIntent = .photo
                showsCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                if !showsCamera { localErrorText = "camera unavailable" }
            } label: {
                buttonLabel
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)
            .accessibilityLabel(style == .captureGlyph ? "capture meal photo" : "photo")
            .accessibilityIdentifier(accessibilityIdentifier)
            .onLongPressGesture(
                minimumDuration: KStyle.bioCameraHoldDuration,
                maximumDistance: KStyle.holdToCompleteMaxDistance,
                pressing: { pressing in
                    gestureStateMachine.pressing(pressing)
                    NotificationCenter.default.post(
                        name: .bioCameraCaptureHolding,
                        object: pressing
                    )
                },
                perform: {
                    didCommitHold = true
                    _ = gestureStateMachine.intentAfterRelease()
                    captureIntent = .video
                    showsCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                    if !showsCamera { localErrorText = "camera unavailable" }
                }
            )
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .sheet(isPresented: $showsCamera) {
                MealCameraPicker(captureIntent: captureIntent) { image in
                    showsCamera = false
                    submit(image)
                } onVideo: { url in
                    showsCamera = false
                    onVideo(url)
                } onCancel: {
                    showsCamera = false
                }
                .ignoresSafeArea()
            }

            if let localErrorText {
                KMonoCaption(localErrorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            selectedPhotoItem = nil
            Task { await loadLibraryImage(item) }
        }
        .kAnimated(value: isPending)
        .kAnimated(value: localErrorText)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        switch style {
        case .text:
            Text("photo")
                .kFont(.monoCaption)
                .foregroundStyle(buttonColor)
                .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
        case .captureGlyph:
            BioCaptureGlyphShape()
                .stroke(
                    buttonColor,
                    style: StrokeStyle(
                        lineWidth: KStyle.bioCaptureGlyphLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: KStyle.bioCaptureIconSize, height: KStyle.bioCaptureIconSize)
                .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
        }
    }

    private var canSelect: Bool {
        isEnabled && !isPending && !state.disablesAction
    }

    private var buttonColor: Color {
        foregroundColor.opacity(canSelect ? KStyle.secondaryTextOpacity : KStyle.quaternaryTextOpacity)
    }

    private var normalizedCaption: String? {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    @MainActor
    private func loadLibraryImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                localErrorText = MealPhotoEncoder.EncodingError.invalidImage.localizedDescription
                return
            }
            submit(image)
        } catch {
            localErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func submit(_ image: UIImage) {
        guard canSelect else { return }
        isPending = true
        localErrorText = nil
        let caption = normalizedCaption
        Task {
            _ = await onImage(image, caption)
            await MainActor.run {
                isPending = false
            }
        }
    }
}

struct MealCameraPicker: UIViewControllerRepresentable {
    let captureIntent: MealCaptureIntent
    let onImage: (UIImage) -> Void
    let onVideo: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = captureIntent == .video ? .video : .photo
        picker.videoMaximumDuration = KStyle.bioCameraVideoMaximumDuration
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onVideo: onVideo, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onVideo: (URL) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onVideo: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onVideo = onVideo
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else if let url = info[.mediaURL] as? URL {
                onVideo(url)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct BioLossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                elements.append(value)
            } else {
                _ = try? container.decode(BioSkipValue.self)
            }
        }
        self.elements = elements
    }
}

private struct BioSkipValue: Decodable {}

enum BioDateParser {
    static func dateTime(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: trimmed) {
            return date
        }

        return dateOnly(from: trimmed)
    }

    static func dayText(_ value: String) -> String {
        guard let date = dateOnly(from: value) ?? dateTime(from: value) else {
            return value.lowercased()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func dateOnly(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
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

    func decodeFlexibleInt(for key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value.rounded(.down))
        }
        guard let string = try decodeTrimmedString(for: key),
              let value = Double(string),
              value.isFinite
        else {
            return nil
        }
        return Int(value.rounded(.down))
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

// Founder 2026-08-05 ("the sub pages of body are not as per design; do the cd
// process on them"): the bio sub-pages (biomarkers, protocols, interventions,
// nutrition) all share ONE layout grammar the current single-column build is
// missing — the rail-and-jut master/detail (bio-neuro-nutrition-port-spec §1).
//
// Geometry (regular width):
//   · a fixed glass RAIL, width `bioRailWidth` (capped to a fraction of the
//     surface so it never crowds the detail on an 11" landscape); only its
//     selected origin row crosses the seam
//   · a white DETAIL card that owns the seam, tucked UNDER the rail's right edge by `bioDetailOverlap`
//     (24pt), its content kept clear of the rail by a `bioDetailContentLeading`
//     (64pt) left inset, dropped `bioDetailTopInset` (48pt) below the rail top
//   · the detail slides in from `bioDetailSlideInX` (−40) + opacity, zen easing;
//     rail selection is the only detail transition in this grammar
// Compact size class stacks the rail and detail so the pattern survives phone
// width without horizontal crowding. Both iPad orientations keep the regular
// rail-and-jut composition.
//
// The detail card is the shared WHITE forward card (dark ink on white) — the same
// primitive as chat's expanded thread card and the build report inline card. Each
// tab owns its rail rows and its detail content; this view owns only the geometry,
// the slide-in, and the white-card chrome. The rail is the only detail transition;
// there is no dead close act competing with that marked origin.
struct BioRailDetail<Rail: View, Detail: View>: View {
    let hasDetail: Bool
    let railWidthToken: CGFloat
    let railMaxFraction: CGFloat
    let detailOverlap: CGFloat
    let detailTopInset: CGFloat
    let detailPadding: CGFloat
    let detailContentLeading: CGFloat
    @ViewBuilder var rail: () -> Rail
    @ViewBuilder var detail: () -> Detail

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Audit-only capture hook. It reconstructs the pre-UI31 stacking so the
    // named before capture records the actual defect; release builds cannot
    // enter this branch.
    private var ui31LegacyZOrderCapture: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui31-zorder-before")
#else
        false
#endif
    }

    init(
        hasDetail: Bool,
        railWidth: CGFloat = KStyle.bioRailWidth,
        railMaxFraction: CGFloat = KStyle.bioRailMaxFraction,
        detailOverlap: CGFloat = KStyle.bioDetailOverlap,
        detailTopInset: CGFloat = KStyle.bioDetailTopInset,
        detailPadding: CGFloat = KStyle.bioDetailPadding,
        detailContentLeading: CGFloat = KStyle.bioDetailContentLeading,
        @ViewBuilder rail: @escaping () -> Rail,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.hasDetail = hasDetail
        self.railWidthToken = railWidth
        self.railMaxFraction = railMaxFraction
        self.detailOverlap = detailOverlap
        self.detailTopInset = detailTopInset
        self.detailPadding = detailPadding
        self.detailContentLeading = detailContentLeading
        self.rail = rail
        self.detail = detail
    }

    var body: some View {
        GeometryReader { proxy in
            let isRegular = horizontalSizeClass == .regular
            Group {
                if isRegular {
                    regularLayout(width: proxy.size.width)
                } else {
                    compactLayout
                }
            }
            .frame(width: proxy.size.width, alignment: .topLeading)
            .animation(KStyle.nativeMotion(.zen, reduceMotion: reduceMotion), value: hasDetail)
        }
    }

    private func regularLayout(width: CGFloat) -> some View {
        let railWidth = min(railWidthToken, width * railMaxFraction)
        let detailWidth = max(0, width - railWidth + detailOverlap)
        let detailZIndex = ui31LegacyZOrderCapture
            ? KStyle.bioRailUnselectedItemZIndex
            : KStyle.bioRailDetailZIndex
        let railZIndex = ui31LegacyZOrderCapture
            ? KStyle.bioRailDetailZIndex
            : KStyle.bioRailUnselectedItemZIndex
        // Rail and detail each own a scroll and fill the height; the detail tucks
        // under the rail's right edge (overlap) and drops below its top (inset).
        return ZStack(alignment: .topLeading) {
            if hasDetail {
                ScrollView {
                    detailCard.padding(.top, detailTopInset)
                }
                .scrollIndicators(.hidden)
                .frame(width: detailWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity)
                .offset(x: railWidth - detailOverlap)
                .transition(detailTransition)
                .zIndex(detailZIndex)
            }
            ScrollView {
                rail()
            }
            .scrollIndicators(.hidden)
            // The selected origin row is allowed to overhang the rail edge; its
            // own z-index is the only layer that may rise above the detail seam.
            .scrollClipDisabled()
            .frame(width: railWidth, alignment: .top)
            .frame(maxHeight: .infinity)
            .zIndex(railZIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Compact: one scroll, rail rows then the detail card below — no greedy inner
    // scroll to shove the detail off-screen.
    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KStyle.bioSystemGridSpacing) {
                rail()
                if hasDetail {
                    detailCard
                        .transition(detailTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var detailCard: some View {
        detail()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(detailPadding)
            .padding(.leading, detailContentLeading - detailPadding)
            .background {
                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(KStyle.chatThreadFinishedFillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(KStyle.hairlineOpacity), lineWidth: KStyle.hairlineWidth)
            }
            .shadow(
                color: Color.black.opacity(KStyle.bioDetailShadowOpacity),
                radius: KStyle.bioDetailShadowRadius,
                y: KStyle.bioDetailShadowY
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("bio-rail-detail")
    }

    private var detailTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: KStyle.bioDetailSlideInX).combined(with: .opacity),
            removal: .opacity
        )
    }
}
