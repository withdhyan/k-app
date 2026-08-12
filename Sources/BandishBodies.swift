import Foundation
import SwiftUI

// MARK: - Additive wire models

struct BandishMealInfo: Codable, Equatable, Sendable {
    var name: String?
    var calories: Double?
    var portionSize: String?
    var macros: BandishMealMacros?
    var micros: [String: Double]
    var images: [BandishMealImage]

    enum CodingKeys: String, CodingKey {
        case name
        case calories
        case portionSize
        case macros
        case micros
        case images
        case protein
        case carbs
        case fat
        case fiber
        case fibre
    }

    init(
        name: String? = nil,
        calories: Double? = nil,
        portionSize: String? = nil,
        macros: BandishMealMacros? = nil,
        micros: [String: Double] = [:],
        images: [BandishMealImage] = []
    ) {
        self.name = Self.normalized(name)
        self.calories = calories
        self.portionSize = Self.normalized(portionSize)
        self.macros = macros
        self.micros = micros
        self.images = images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = Self.normalized(try container.decodeIfPresent(String.self, forKey: .name))
        calories = try container.bandishFlexibleDouble(forKey: .calories)
        portionSize = Self.normalized(try container.decodeIfPresent(String.self, forKey: .portionSize))
        macros = try? container.decodeIfPresent(BandishMealMacros.self, forKey: .macros)
        if macros?.hasValues != true {
            let topLevel = BandishMealMacros(
                protein: try container.bandishFlexibleDouble(forKey: .protein),
                carbs: try container.bandishFlexibleDouble(forKey: .carbs),
                fat: try container.bandishFlexibleDouble(forKey: .fat),
                fiber: try container.bandishFlexibleDouble(forKey: .fiber)
                    ?? container.bandishFlexibleDouble(forKey: .fibre)
            )
            macros = topLevel.hasValues ? topLevel : nil
        }
        micros = (try? container.decodeIfPresent([String: Double].self, forKey: .micros)) ?? [:]
        if micros.isEmpty,
           let stringMicros = try? container.decodeIfPresent([String: String].self, forKey: .micros) {
            micros = stringMicros.reduce(into: [:]) { values, entry in
                if let value = Double(entry.value) { values[entry.key] = value }
            }
        }
        images = (try? container.decodeIfPresent([BandishMealImage].self, forKey: .images)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(portionSize, forKey: .portionSize)
        try container.encodeIfPresent(macros, forKey: .macros)
        try container.encode(micros, forKey: .micros)
        try container.encode(images, forKey: .images)
    }

    var hasAnalysis: Bool {
        !images.isEmpty && (macros?.hasValues == true || !micros.isEmpty || calories != nil || name != nil)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BandishMealMacros: Codable, Equatable, Sendable {
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?

    enum CodingKeys: String, CodingKey {
        case protein
        case carbs
        case fat
        case fiber
        case fibre
    }

    init(protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, fiber: Double? = nil) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protein = try container.bandishFlexibleDouble(forKey: .protein)
        carbs = try container.bandishFlexibleDouble(forKey: .carbs)
        fat = try container.bandishFlexibleDouble(forKey: .fat)
        fiber = try container.bandishFlexibleDouble(forKey: .fiber)
            ?? container.bandishFlexibleDouble(forKey: .fibre)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(carbs, forKey: .carbs)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(fiber, forKey: .fiber)
    }

    var hasValues: Bool {
        protein != nil || carbs != nil || fat != nil || fiber != nil
    }
}

struct BandishMealImage: Codable, Equatable, Sendable {
    var id: String?
    var url: String?
    var isAnalyzed: Bool?
}

struct BandishSleepInfo: Codable, Equatable, Sendable {
    var deepSleep: Double?
    var remSleep: Double?
    var lightSleep: Double?
    var awakeTime: Double?
    var duration: Double?
    var efficiency: Double?
    var performancePercentage: Double?
    var sleepNeededMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case deepSleep
        case deep
        case remSleep
        case rem
        case lightSleep
        case light
        case awakeTime
        case awake
        case duration
        case efficiency
        case performancePercentage
        case performancePercentageSnake = "performance_percentage"
        case sleepNeeded
    }

    enum SleepNeededKeys: String, CodingKey {
        case total
    }

    init(
        deepSleep: Double? = nil,
        remSleep: Double? = nil,
        lightSleep: Double? = nil,
        awakeTime: Double? = nil,
        duration: Double? = nil,
        efficiency: Double? = nil,
        performancePercentage: Double? = nil,
        sleepNeededMinutes: Double? = nil
    ) {
        self.deepSleep = deepSleep
        self.remSleep = remSleep
        self.lightSleep = lightSleep
        self.awakeTime = awakeTime
        self.duration = duration
        self.efficiency = efficiency
        self.performancePercentage = performancePercentage
        self.sleepNeededMinutes = sleepNeededMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deepSleep = try container.bandishFlexibleDouble(forKey: .deepSleep)
            ?? container.bandishFlexibleDouble(forKey: .deep)
        remSleep = try container.bandishFlexibleDouble(forKey: .remSleep)
            ?? container.bandishFlexibleDouble(forKey: .rem)
        lightSleep = try container.bandishFlexibleDouble(forKey: .lightSleep)
            ?? container.bandishFlexibleDouble(forKey: .light)
        awakeTime = try container.bandishFlexibleDouble(forKey: .awakeTime)
            ?? container.bandishFlexibleDouble(forKey: .awake)
        duration = try container.bandishFlexibleDouble(forKey: .duration)
        efficiency = try container.bandishFlexibleDouble(forKey: .efficiency)
        performancePercentage = try container.bandishFlexibleDouble(forKey: .performancePercentage)
            ?? container.bandishFlexibleDouble(forKey: .performancePercentageSnake)
        if let needed = try? container.nestedContainer(keyedBy: SleepNeededKeys.self, forKey: .sleepNeeded) {
            sleepNeededMinutes = try needed.bandishFlexibleDouble(forKey: .total)
        } else {
            sleepNeededMinutes = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(deepSleep, forKey: .deepSleep)
        try container.encodeIfPresent(remSleep, forKey: .remSleep)
        try container.encodeIfPresent(lightSleep, forKey: .lightSleep)
        try container.encodeIfPresent(awakeTime, forKey: .awakeTime)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(efficiency, forKey: .efficiency)
        try container.encodeIfPresent(performancePercentage, forKey: .performancePercentageSnake)
        if let sleepNeededMinutes {
            var needed = container.nestedContainer(keyedBy: SleepNeededKeys.self, forKey: .sleepNeeded)
            try needed.encode(sleepNeededMinutes, forKey: .total)
        }
    }

    var hasData: Bool {
        phaseMinutes.reduce(0, +) > 0 || efficiency != nil || performancePercentage != nil
    }

    var phaseMinutes: [Int] {
        [deepSleep, remSleep, lightSleep, awakeTime].map(Self.minutes)
    }

    private static func minutes(_ value: Double?) -> Int {
        // Sleep-stage fields are minutes (the canonical block unit). No magnitude
        // heuristic: a raw 24 is 24 min awake, not 24 h — any hours→minutes guess
        // collides with legitimate minute values. Hour-sourced data normalizes at
        // ingest, never here.
        guard let value, value.isFinite, value > 0 else { return 0 }
        return Int(value.rounded())
    }
}

struct BandishMeditationInfo: Codable, Equatable, Sendable {
    var sessionType: String?
    var technique: String?
    var protocolId: String?

    enum CodingKeys: String, CodingKey {
        case sessionType
        case sessionTypeSnake = "session_type"
        case technique
        case protocolId
        case methodId
    }

    init(sessionType: String? = nil, technique: String? = nil, protocolId: String? = nil) {
        self.sessionType = Self.normalized(sessionType)
        self.technique = Self.normalized(technique)
        self.protocolId = Self.normalized(protocolId)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionType = Self.normalized(try container.decodeIfPresent(String.self, forKey: .sessionType)
            ?? container.decodeIfPresent(String.self, forKey: .sessionTypeSnake))
        technique = Self.normalized(try container.decodeIfPresent(String.self, forKey: .technique))
        protocolId = Self.normalized(try container.decodeIfPresent(String.self, forKey: .protocolId)
            ?? container.decodeIfPresent(String.self, forKey: .methodId))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sessionType, forKey: .sessionType)
        try container.encodeIfPresent(technique, forKey: .technique)
        try container.encodeIfPresent(protocolId, forKey: .protocolId)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

// doctrine: additive-only decode (wire fields stay optional) + staleness-honesty.
// WHOOP-shaped workout data is a local seam for now; the factory can add the same
// optional object later without changing the cadence row contract.
struct BandishWorkoutExercise: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var setsRepsWeight: String?
    var completed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case setsRepsWeight
        case setsRepsWeightSnake = "sets_reps_weight"
        case sets
        case completed
        case done
    }

    init(
        id: String,
        name: String,
        setsRepsWeight: String? = nil,
        completed: Bool = false
    ) {
        self.id = id
        self.name = Self.normalized(name) ?? "exercise"
        self.setsRepsWeight = Self.normalized(setsRepsWeight)
        self.completed = completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = (try? container.decodeFlexibleText(for: .name))
            ?? (try? container.decodeFlexibleText(for: .title))
            ?? "exercise"
        name = Self.normalized(decodedName) ?? "exercise"
        id = (try? container.decodeTrimmedString(for: .id)) ?? name
        setsRepsWeight = Self.normalized(
            (try? container.decodeFlexibleText(for: .setsRepsWeight))
                ?? (try? container.decodeFlexibleText(for: .setsRepsWeightSnake))
                ?? (try? container.decodeFlexibleText(for: .sets))
        )
        completed = (try? container.decodeFlexibleBool(for: .completed))
            ?? (try? container.decodeFlexibleBool(for: .done))
            ?? false
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(setsRepsWeight, forKey: .setsRepsWeight)
        try container.encode(completed, forKey: .completed)
    }
}

struct BandishWorkoutStrain: Codable, Equatable, Sendable {
    var actual: Double?
    var target: Double?

    enum CodingKeys: String, CodingKey {
        case actual
        case score
        case target
        case goal
    }

    init(actual: Double? = nil, target: Double? = nil) {
        self.actual = actual
        self.target = target
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actual = (try? container.decodeFlexibleDouble(for: .actual))
            ?? (try? container.decodeFlexibleDouble(for: .score))
        target = (try? container.decodeFlexibleDouble(for: .target))
            ?? (try? container.decodeFlexibleDouble(for: .goal))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(actual, forKey: .actual)
        try container.encodeIfPresent(target, forKey: .target)
    }
}

struct BandishWorkoutTonnage: Codable, Equatable, Sendable {
    var current: Double?
    var previous: Double?
    var change: Double?

    enum CodingKeys: String, CodingKey {
        case current
        case previous
        case change
    }

    init(current: Double? = nil, previous: Double? = nil, change: Double? = nil) {
        self.current = current
        self.previous = previous
        self.change = change
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try? container.decodeFlexibleDouble(for: .current)
        previous = try? container.decodeFlexibleDouble(for: .previous)
        change = try? container.decodeFlexibleDouble(for: .change)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(current, forKey: .current)
        try container.encodeIfPresent(previous, forKey: .previous)
        try container.encodeIfPresent(change, forKey: .change)
    }
}

struct BandishWorkoutZone: Codable, Equatable, Sendable {
    var zone: Int
    var name: String?
    var minutes: Double
    var percentage: Double?

    enum CodingKeys: String, CodingKey {
        case zone
        case number
        case name
        case label
        case minutes
        case duration
        case percentage
        case percent
    }

    init(
        zone: Int,
        name: String? = nil,
        minutes: Double = 0,
        percentage: Double? = nil
    ) {
        self.zone = max(1, zone)
        self.name = Self.normalized(name)
        self.minutes = max(0, minutes)
        self.percentage = percentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zone = max(
            1,
            (try? container.decodeFlexibleInt(for: .zone))
                ?? (try? container.decodeFlexibleInt(for: .number))
                ?? 1
        )
        name = Self.normalized(
            (try? container.decodeFlexibleText(for: .name))
                ?? (try? container.decodeFlexibleText(for: .label))
        )
        minutes = max(
            0,
            (try? container.decodeFlexibleDouble(for: .minutes))
                ?? (try? container.decodeFlexibleDouble(for: .duration))
                ?? 0
        )
        percentage = (try? container.decodeFlexibleDouble(for: .percentage))
            ?? (try? container.decodeFlexibleDouble(for: .percent))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zone, forKey: .zone)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(minutes, forKey: .minutes)
        try container.encodeIfPresent(percentage, forKey: .percentage)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BandishWorkoutRealtime: Codable, Equatable, Sendable {
    var currentZone: Int?
    var isActive: Bool
    var heartRate: Int?

    enum CodingKeys: String, CodingKey {
        case currentZone
        case currentZoneSnake = "current_zone"
        case zone
        case isActive
        case active
        case heartRate
        case heartRateSnake = "heart_rate"
    }

    init(currentZone: Int? = nil, isActive: Bool = false, heartRate: Int? = nil) {
        self.currentZone = currentZone
        self.isActive = isActive
        self.heartRate = heartRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentZone = (try? container.decodeFlexibleInt(for: .currentZone))
            ?? (try? container.decodeFlexibleInt(for: .currentZoneSnake))
            ?? (try? container.decodeFlexibleInt(for: .zone))
        isActive = (try? container.decodeFlexibleBool(for: .isActive))
            ?? (try? container.decodeFlexibleBool(for: .active))
            ?? false
        heartRate = (try? container.decodeFlexibleInt(for: .heartRate))
            ?? (try? container.decodeFlexibleInt(for: .heartRateSnake))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(currentZone, forKey: .currentZone)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(heartRate, forKey: .heartRate)
    }
}

struct BandishWorkoutInfo: Codable, Equatable, Sendable {
    var exercises: [BandishWorkoutExercise]
    var strain: BandishWorkoutStrain?
    var tonnage: BandishWorkoutTonnage?
    var heartRateZones: [BandishWorkoutZone]
    var realTime: BandishWorkoutRealtime?
    var calories: Double?
    var effortCurve: [Double]
    var recoveryHint: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case exercises
        case strain
        case tonnage
        case heartRateZones
        case zones
        case realTime
        case realtime
        case calories
        case kcal
        case effortCurve
        case effort
        case recoveryHint
        case recovery
        case source
    }

    init(
        exercises: [BandishWorkoutExercise] = [],
        strain: BandishWorkoutStrain? = nil,
        tonnage: BandishWorkoutTonnage? = nil,
        heartRateZones: [BandishWorkoutZone] = [],
        realTime: BandishWorkoutRealtime? = nil,
        calories: Double? = nil,
        effortCurve: [Double] = [],
        recoveryHint: String? = nil,
        source: String? = nil
    ) {
        self.exercises = exercises
        self.strain = strain
        self.tonnage = tonnage
        self.heartRateZones = heartRateZones
        self.realTime = realTime
        self.calories = calories
        self.effortCurve = effortCurve.filter { $0.isFinite }.map { min(1, max(0, $0)) }
        self.recoveryHint = Self.normalized(recoveryHint)
        self.source = Self.normalized(source)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exercises = (try? container.decode([BandishWorkoutExercise].self, forKey: .exercises)) ?? []
        strain = try? container.decodeIfPresent(BandishWorkoutStrain.self, forKey: .strain)
        tonnage = try? container.decodeIfPresent(BandishWorkoutTonnage.self, forKey: .tonnage)
        heartRateZones = (try? container.decode([BandishWorkoutZone].self, forKey: .heartRateZones))
            ?? (try? container.decode([BandishWorkoutZone].self, forKey: .zones))
            ?? []
        realTime = (try? container.decodeIfPresent(BandishWorkoutRealtime.self, forKey: .realTime))
            ?? (try? container.decodeIfPresent(BandishWorkoutRealtime.self, forKey: .realtime))
        calories = (try? container.decodeFlexibleDouble(for: .calories))
            ?? (try? container.decodeFlexibleDouble(for: .kcal))
        effortCurve = Self.normalizedCurve(
            (try? container.decode([Double].self, forKey: .effortCurve))
                ?? (try? container.decode([Double].self, forKey: .effort))
                ?? []
        )
        recoveryHint = Self.normalized(
            (try? container.decodeFlexibleText(for: .recoveryHint))
                ?? (try? container.decodeFlexibleText(for: .recovery))
        )
        source = Self.normalized(try? container.decodeFlexibleText(for: .source))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(strain, forKey: .strain)
        try container.encodeIfPresent(tonnage, forKey: .tonnage)
        try container.encode(heartRateZones, forKey: .heartRateZones)
        try container.encodeIfPresent(realTime, forKey: .realTime)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encode(effortCurve, forKey: .effortCurve)
        try container.encodeIfPresent(recoveryHint, forKey: .recoveryHint)
        try container.encodeIfPresent(source, forKey: .source)
    }

    var hasData: Bool {
        strain != nil || tonnage != nil || !heartRateZones.isEmpty || realTime != nil
            || calories != nil || !effortCurve.isEmpty || !exercises.isEmpty || recoveryHint != nil
    }

    private static func normalizedCurve(_ values: [Double]) -> [Double] {
        values.filter { $0.isFinite }.map { min(1, max(0, $0)) }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BandishMorningOrientation: Codable, Equatable, Sendable {
    var summary: String?
    var decisions: [BandishMorningDecision]
    var priorities: [BandishMorningPriority]
    var complete: Bool

    enum CodingKeys: String, CodingKey {
        case summary
        case overnightSummary
        case decisions
        case decisionsNeeded
        case priorities
        case todayPriorities
        case complete
        case orientationComplete
    }

    init(
        summary: String? = nil,
        decisions: [BandishMorningDecision] = [],
        priorities: [BandishMorningPriority] = [],
        complete: Bool = false
    ) {
        self.summary = Self.normalized(summary)
        self.decisions = decisions
        self.priorities = priorities
        self.complete = complete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = Self.normalized(try container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .overnightSummary))
        decisions = Self.decodeDecisions(container, key: .decisions)
        if decisions.isEmpty { decisions = Self.decodeDecisions(container, key: .decisionsNeeded) }
        priorities = Self.decodePriorities(container, key: .priorities)
        if priorities.isEmpty { priorities = Self.decodePriorities(container, key: .todayPriorities) }
        complete = (try? container.decodeIfPresent(Bool.self, forKey: .complete)) ?? false
        if !complete {
            complete = (try? container.decodeIfPresent(Bool.self, forKey: .orientationComplete)) ?? false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summary, forKey: .overnightSummary)
        try container.encode(decisions, forKey: .decisionsNeeded)
        try container.encode(priorities, forKey: .todayPriorities)
        try container.encode(complete, forKey: .complete)
    }

    private static func decodeDecisions(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [BandishMorningDecision] {
        if let values = try? container.decodeIfPresent([BandishMorningDecision].self, forKey: key) {
            return values
        }
        let values = (try? container.decodeIfPresent([String].self, forKey: key)) ?? []
        return values.enumerated().map { BandishMorningDecision(id: "decision-\($0.offset)", observation: $0.element) }
    }

    private static func decodePriorities(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [BandishMorningPriority] {
        if let values = try? container.decodeIfPresent([BandishMorningPriority].self, forKey: key) {
            return values
        }
        let values = (try? container.decodeIfPresent([String].self, forKey: key)) ?? []
        return values.enumerated().map { BandishMorningPriority(id: "priority-\($0.offset)", title: $0.element) }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BandishMorningDecision: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var observation: String
    var urgency: String?

    init(id: String, observation: String, urgency: String? = nil) {
        self.id = id
        self.observation = observation.lowercased()
        self.urgency = urgency?.lowercased()
    }
}

struct BandishMorningPriority: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var time: String?
    var title: String

    init(id: String, time: String? = nil, title: String) {
        self.id = id
        self.time = time
        self.title = title.lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case time
        case title
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? "priority"
        let decodedTime = try container.decodeIfPresent(String.self, forKey: .time)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "priority-\(decodedTime ?? "time")-\(decodedTitle)"
        time = decodedTime
        title = decodedTitle.lowercased()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(title, forKey: .title)
    }
}

// MARK: - Pure variant matrix

enum BandishBodyTemporalVariant: Equatable, Sendable {
    case past
    case current
    case future
    case pastDetail

    var rendersCurrentBody: Bool {
        self == .current || self == .pastDetail
    }
}

enum BandishBodyKind: String, Equatable, Sendable {
    case none
    case mealAnalysis = "meal-analysis"
    case sleepOverview = "sleep-overview"
    case meditationProtocol = "meditation-protocol"
    case meditationSession = "meditation-session"
    case workPreparation = "work-preparation"
    case workSession = "work-session"
    case workoutLive = "workout-live"
    case workoutDetail = "workout-detail"
}

struct BandishBodyMetric: Equatable, Identifiable, Sendable {
    var label: String
    var value: String
    var id: String { label }
}

struct BandishMealAnalysisPresentation: Equatable, Sendable {
    var macroColumn: [BandishBodyMetric]
    var micronutrientColumns: [[BandishBodyMetric]]
}

struct BandishSleepStagePresentation: Equatable, Identifiable, Sendable {
    var label: String
    var minutes: Int
    var ratio: Double
    var id: String { label }
}

struct BandishOrientationPresentation: Equatable, Sendable {
    var summary: String?
    var decisions: [BandishMorningDecision]
    var priorities: [BandishMorningPriority]
    var completionText: String?
}

struct BandishSleepPresentation: Equatable, Sendable {
    var stages: [BandishSleepStagePresentation]
    var efficiencyText: String?
    var needText: String?
    var orientation: BandishOrientationPresentation?
}

struct BandishBodyPhasePresentation: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        case pending
        case active
        case completed
    }

    var id: String
    var label: String
    var progress: Double
    var state: State
}

struct BandishMeditationPresentation: Equatable, Sendable {
    var protocolName: String
    var technique: String
    var elapsedText: String?
    var phaseName: String?
    var instruction: String?
    var phases: [BandishBodyPhasePresentation]
}

struct BandishWorkTaskLine: Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var isDone: Bool
    var isTimeSensitive: Bool
}

struct BandishWorkPresentation: Equatable, Sendable {
    var mode: String
    var protocolName: String?
    var remainingText: String?
    var phaseName: String?
    var instruction: String?
    var phases: [BandishBodyPhasePresentation]
    var taskLines: [BandishWorkTaskLine]
    var inProgressText: String?
}

enum BandishWorkoutBodyState: String, Equatable, Sendable {
    case preWorkout = "pre-workout"
    case midWorkout = "mid-workout"
    case completed = "completed"
}

struct BandishWorkoutZonePresentation: Equatable, Identifiable, Sendable {
    var label: String
    var minutes: Int
    var ratio: Double
    var isCurrent: Bool
    var id: String { label }
}

struct BandishWorkoutExercisePresentation: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var detail: String?
    var completed: Bool
}

struct BandishWorkoutPresentation: Equatable, Sendable {
    var state: BandishWorkoutBodyState
    var strainText: String?
    var targetStrainText: String?
    var currentZoneText: String?
    var heartRateText: String?
    var caloriesText: String?
    var sourceText: String?
    var recordingText: String?
    var zones: [BandishWorkoutZonePresentation]
    var effortCurve: [Double]
    var exercises: [BandishWorkoutExercisePresentation]
    var tonnageText: String?
    var recoveryHint: String?
}

struct BandishBodyPresentation: Equatable, Sendable {
    var kind: BandishBodyKind
    var title: String
    var secondaryInfo: String?
    var meal: BandishMealAnalysisPresentation?
    var sleep: BandishSleepPresentation?
    var meditation: BandishMeditationPresentation?
    var work: BandishWorkPresentation?
    var workout: BandishWorkoutPresentation?

    static func empty(title: String, secondaryInfo: String? = nil) -> BandishBodyPresentation {
        BandishBodyPresentation(
            kind: .none,
            title: title,
            secondaryInfo: secondaryInfo,
            meal: nil,
            sleep: nil,
            meditation: nil,
            work: nil,
            workout: nil
        )
    }
}

enum BandishBodyVariantResolver {
    static func presentation(
        for block: CadenceBlock,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState,
        elapsedSeconds: Int
    ) -> BandishBodyPresentation {
        let baseTitle = normalized(block.title) ?? normalized(block.description) ?? normalized(block.mode) ?? "cadence"

        switch block.normalizedTypeText {
        case "meal":
            return mealPresentation(block: block, baseTitle: baseTitle, temporal: temporal)
        case "sleep":
            return sleepPresentation(
                block: block,
                baseTitle: baseTitle,
                temporal: temporal,
                actionState: actionState
            )
        case "meditation":
            return meditationPresentation(
                block: block,
                baseTitle: baseTitle,
                temporal: temporal,
                actionState: actionState,
                elapsedSeconds: elapsedSeconds
            )
        case "work":
            return workPresentation(
                block: block,
                baseTitle: baseTitle,
                temporal: temporal,
                actionState: actionState,
                elapsedSeconds: elapsedSeconds
            )
        case "workout":
            return workoutPresentation(
                block: block,
                baseTitle: baseTitle,
                temporal: temporal,
                actionState: actionState
            )
        default:
            return .empty(title: baseTitle)
        }
    }

    static func presentation(
        for block: CadenceBlock,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState,
        elapsedSeconds: Int? = nil
    ) -> BandishBodyPresentation {
        presentation(
            for: block,
            temporal: temporal,
            actionState: actionState,
            elapsedSeconds: max(0, elapsedSeconds ?? 0)
        )
    }

    private static func mealPresentation(
        block: CadenceBlock,
        baseTitle: String,
        temporal: BandishBodyTemporalVariant
    ) -> BandishBodyPresentation {
        guard let info = block.mealInfo else { return .empty(title: baseTitle) }
        let title = info.name.map { "\(baseTitle) | \($0)" } ?? baseTitle
        let secondaryInfo = mealSecondaryInfo(info)
        guard temporal.rendersCurrentBody, info.hasAnalysis else {
            return .empty(title: title, secondaryInfo: secondaryInfo)
        }

        let macroValues: [(String, Double?)] = [
            ("protein", info.macros?.protein),
            ("carbs", info.macros?.carbs),
            ("fat", info.macros?.fat),
            ("fiber", info.macros?.fiber),
        ]
        let macros = macroValues.compactMap { label, value -> BandishBodyMetric? in
            guard let value else { return nil }
            return BandishBodyMetric(label: label, value: "\(number(value))g")
        }
        let micros = info.micros
            .sorted { left, right in
                left.value == right.value ? left.key < right.key : left.value > right.value
            }
            .prefix(8)
            .map { BandishBodyMetric(label: $0.key.lowercased(), value: "\(number($0.value))%") }
        let split = min(4, micros.count)

        return BandishBodyPresentation(
            kind: .mealAnalysis,
            title: title,
            secondaryInfo: secondaryInfo,
            meal: BandishMealAnalysisPresentation(
                macroColumn: macros,
                micronutrientColumns: [Array(micros[..<split]), Array(micros[split...])]
            ),
            sleep: nil,
            meditation: nil,
            work: nil,
            workout: nil
        )
    }

    private static func sleepPresentation(
        block: CadenceBlock,
        baseTitle: String,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState
    ) -> BandishBodyPresentation {
        let isInit = baseTitle == "init"
        let performance = block.sleepInfo?.performancePercentage
        let title = performance.map { "\(baseTitle) | \(Int($0.rounded()))%" } ?? baseTitle
        guard temporal.rendersCurrentBody else { return .empty(title: title) }

        let canShowSleep = isInit
            ? actionState == .started || actionState == .completed
            : actionState == .completed
        let stages: [BandishSleepStagePresentation]
        if canShowSleep, let info = block.sleepInfo, info.hasData {
            let minutes = info.phaseMinutes
            let total = minutes.reduce(0, +)
            let labels = ["deep", "rem", "light", "awake"]
            stages = zip(labels, minutes).map { label, value in
                BandishSleepStagePresentation(
                    label: label,
                    minutes: value,
                    ratio: total > 0 ? Double(value) / Double(total) : 0
                )
            }
        } else {
            stages = []
        }

        let orientation: BandishOrientationPresentation?
        if isInit, actionState == .started, let value = block.morningOrientation {
            orientation = BandishOrientationPresentation(
                summary: value.summary,
                decisions: value.decisions,
                priorities: Array(value.priorities.prefix(3)),
                completionText: value.complete || value.decisions.isEmpty ? "orientation complete" : nil
            )
        } else {
            orientation = nil
        }

        let efficiency = block.sleepInfo?.efficiency.flatMap(percentValue).map { "\($0)%" }
        let need = block.sleepInfo?.sleepNeededMinutes.flatMap(sleepNeedText)
        return BandishBodyPresentation(
            kind: .sleepOverview,
            title: title,
            secondaryInfo: nil,
            meal: nil,
            sleep: BandishSleepPresentation(
                stages: stages,
                efficiencyText: efficiency,
                needText: need,
                orientation: orientation
            ),
            meditation: nil,
            work: nil,
            workout: nil
        )
    }

    private static func meditationPresentation(
        block: CadenceBlock,
        baseTitle: String,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState,
        elapsedSeconds: Int
    ) -> BandishBodyPresentation {
        guard temporal.rendersCurrentBody else { return .empty(title: baseTitle) }
        let protocolID = MeditationCatalog.identifier(
            block.meditationInfo?.protocolId
                ?? block.brainState
                ?? block.meditationInfo?.sessionType
        )
        let method = MeditationCatalog.method(id: protocolID)
        if actionState != .started {
            return BandishBodyPresentation(
                kind: .meditationProtocol,
                title: baseTitle,
                secondaryInfo: nil,
                meal: nil,
                sleep: nil,
                meditation: BandishMeditationPresentation(
                    protocolName: method.name,
                    technique: MeditationCatalog.technique(
                        block.meditationInfo?.technique,
                        fallback: method.technique
                    ),
                    elapsedText: nil,
                    phaseName: nil,
                    instruction: nil,
                    phases: []
                ),
                work: nil,
                workout: nil
            )
        }

        let guided = MeditationCatalog.guidedPresentation(method: method, elapsedSeconds: elapsedSeconds)
        return BandishBodyPresentation(
            kind: .meditationSession,
            title: baseTitle,
            secondaryInfo: nil,
            meal: nil,
            sleep: nil,
            meditation: guided,
            work: nil,
            workout: nil
        )
    }

    private static func workPresentation(
        block: CadenceBlock,
        baseTitle: String,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState,
        elapsedSeconds: Int
    ) -> BandishBodyPresentation {
        let mode = BandishWorkModeResolver.mode(block.brainState)
            ?? BandishWorkModeResolver.mode(block.mode)
        let title = mode.map { "\(baseTitle) | \($0)" } ?? baseTitle
        guard let mode else { return .empty(title: title) }

        if temporal.rendersCurrentBody,
           actionState == .started,
           elapsedSeconds < WorkPrepCatalog.duration(for: mode) {
            let prep = WorkPrepCatalog.presentation(mode: mode, elapsedSeconds: elapsedSeconds)
            return BandishBodyPresentation(
                kind: .workPreparation,
                title: title,
                secondaryInfo: nil,
                meal: nil,
                sleep: nil,
                meditation: nil,
                work: prep,
                workout: nil
            )
        }

        let isConvergent = mode == "convergent"
        let visibleSubtasks: ArraySlice<Subtask>
        if temporal.rendersCurrentBody {
            visibleSubtasks = block.subtasks.prefix(3)
        } else {
            visibleSubtasks = block.subtasks[...]
        }
        let taskLines = isConvergent ? visibleSubtasks.map {
            BandishWorkTaskLine(id: $0.id, text: $0.text, isDone: $0.done, isTimeSensitive: $0.timeSensitive)
        } : []
        let inProgressText = temporal.rendersCurrentBody && actionState == .started && !isConvergent
            ? "\(mode) in progress"
            : nil
        guard !taskLines.isEmpty || inProgressText != nil else { return .empty(title: title) }

        return BandishBodyPresentation(
            kind: .workSession,
            title: title,
            secondaryInfo: nil,
            meal: nil,
            sleep: nil,
            meditation: nil,
            work: BandishWorkPresentation(
                mode: mode,
                protocolName: nil,
                remainingText: nil,
                phaseName: nil,
                instruction: nil,
                phases: [],
                taskLines: taskLines,
                inProgressText: inProgressText
            ),
            workout: nil
        )
    }

    private static func workoutPresentation(
        block: CadenceBlock,
        baseTitle: String,
        temporal: BandishBodyTemporalVariant,
        actionState: KBlockActionState
    ) -> BandishBodyPresentation {
        guard let info = block.workoutInfo, info.hasData else {
            return .empty(title: baseTitle)
        }

        let summary = workoutSummary(info)
        let completedTitle = [baseTitle, summary]
            .compactMap { $0 }
            .joined(separator: " | ")
        let state: BandishWorkoutBodyState
        if temporal == .past || temporal == .pastDetail || actionState == .completed {
            state = .completed
        } else if actionState == .started {
            state = .midWorkout
        } else {
            state = .preWorkout
        }

        let zones = workoutZones(info: info, currentZone: state == .midWorkout ? info.realTime?.currentZone : nil)
        let workout = BandishWorkoutPresentation(
            state: state,
            strainText: state == .preWorkout ? "not started" : info.strain?.actual.flatMap(workoutNumber),
            targetStrainText: info.strain?.target.flatMap { "target \(workoutNumber($0))" },
            currentZoneText: info.realTime?.currentZone.map { "zone \($0)" },
            heartRateText: info.realTime?.heartRate.map { "\($0) bpm" },
            caloriesText: info.calories.flatMap { "\(workoutNumber($0)) kcal" },
            sourceText: info.source,
            recordingText: state == .preWorkout
                ? "ready"
                : (state == .midWorkout ? "recording" : nil),
            zones: zones,
            effortCurve: info.effortCurve,
            exercises: info.exercises.map {
                BandishWorkoutExercisePresentation(
                    id: $0.id,
                    name: $0.name,
                    detail: $0.setsRepsWeight,
                    completed: $0.completed
                )
            },
            tonnageText: workoutTonnageText(info.tonnage),
            recoveryHint: info.recoveryHint
        )

        switch state {
        case .preWorkout, .midWorkout:
            return BandishBodyPresentation(
                kind: .workoutLive,
                title: baseTitle,
                secondaryInfo: nil,
                meal: nil,
                sleep: nil,
                meditation: nil,
                work: nil,
                workout: workout
            )
        case .completed:
            if temporal == .pastDetail {
                return BandishBodyPresentation(
                    kind: .workoutDetail,
                    title: completedTitle,
                    secondaryInfo: summary,
                    meal: nil,
                    sleep: nil,
                    meditation: nil,
                    work: nil,
                    workout: workout
                )
            }
            return .empty(title: completedTitle, secondaryInfo: summary)
        }
    }

    private static func workoutZones(
        info: BandishWorkoutInfo,
        currentZone: Int?
    ) -> [BandishWorkoutZonePresentation] {
        // Preserve the last wire value when a provider repeats a zone. The
        // body remains additive and quiet instead of trapping on malformed
        // telemetry.
        let supplied = info.heartRateZones.reduce(into: [Int: BandishWorkoutZone]()) { result, zone in
            result[zone.zone] = zone
        }
        let totalMinutes = info.heartRateZones.map(\.minutes).reduce(0, +)
        return (1...5).map { number in
            let zone = supplied[number]
            let minutes = Int((zone?.minutes ?? 0).rounded())
            let ratio: Double
            if let percentage = zone?.percentage, percentage.isFinite {
                ratio = min(1, max(0, percentage > 1.5 ? percentage / 100 : percentage))
            } else {
                ratio = totalMinutes > 0 ? min(1, max(0, (zone?.minutes ?? 0) / totalMinutes)) : 0
            }
            return BandishWorkoutZonePresentation(
                label: zone?.name ?? "z\(number)",
                minutes: minutes,
                ratio: ratio,
                isCurrent: currentZone == number
            )
        }
    }

    private static func workoutSummary(_ info: BandishWorkoutInfo) -> String? {
        [
            info.calories.flatMap { "\(workoutNumber($0)) kcal" },
            info.strain?.actual.flatMap { "\(workoutNumber($0)) strain" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private static func workoutTonnageText(_ tonnage: BandishWorkoutTonnage?) -> String? {
        guard let tonnage else { return nil }
        let current = tonnage.current.map { "tonnage \(workoutNumber($0)) kg" }
        let change = tonnage.change.map { "\(workoutSignedNumber($0))%" }
        return [current, change].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    private static func workoutNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value { return "\(Int(value.rounded()))" }
        return String(format: "%.1f", value)
    }

    private static func workoutSignedNumber(_ value: Double) -> String {
        let text = workoutNumber(abs(value))
        return value < 0 ? "-\(text)" : "+\(text)"
    }

    private static func mealSecondaryInfo(_ info: BandishMealInfo) -> String? {
        var parts: [String] = []
        // calories are exact, not significant-figure rounded — 612 kcal must not read 610.
        if let calories = info.calories { parts.append("\(Int(calories.rounded())) kcal") }
        if let portion = cleanedPortion(info.portionSize) { parts.append(portion) }
        let macros = [info.macros?.protein, info.macros?.carbs, info.macros?.fat, info.macros?.fiber]
            .compactMap { $0.map { "\(number($0))g" } }
        if !macros.isEmpty { parts.append(macros.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private static func cleanedPortion(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean.isEmpty ? nil : clean
    }

    private static func number(_ value: Double) -> String {
        BioNumberText.significant(value)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func percentValue(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(max(0, min(100, value > 1.5 ? value : value * 100)).rounded())
    }

    private static func sleepNeedText(_ minutes: Double) -> String? {
        guard minutes.isFinite, minutes > 0 else { return nil }
        let total = Int(minutes.rounded())
        return "need \(total / 60)h \(total % 60)m"
    }
}

private struct MeditationMethod {
    var id: String
    var name: String
    var technique: String
    var phases: [MeditationPhase]
}

private struct MeditationPhase {
    var id: String
    var duration: Int
    var instructions: [String]
}

private enum MeditationCatalog {
    static func identifier(_ rawValue: String?) -> String {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "open-monitoring", "vipassana", "vipassanā", "om-v1": return "open-monitoring"
        case "body-scan", "body-scan-v1": return "body-scan"
        case "loving-kindness", "metta", "mettā", "metta-v1": return "loving-kindness"
        case "fa-v1": return "focused-attention"
        default: return "focused-attention"
        }
    }

    static func method(id: String) -> MeditationMethod {
        methods[id] ?? methods["focused-attention"]!
    }

    static func technique(_ rawValue: String?, fallback: String) -> String {
        switch rawValue?.lowercased() {
        case "vipassana": return "vipassanā"
        case "metta": return "mettā cultivation"
        default: return rawValue?.lowercased() ?? fallback
        }
    }

    static func guidedPresentation(method: MeditationMethod, elapsedSeconds: Int) -> BandishMeditationPresentation {
        let elapsed = max(0, elapsedSeconds)
        var phaseIndex = 0
        var phaseStart = 0
        for index in method.phases.indices {
            let next = phaseStart + method.phases[index].duration
            if elapsed < next || index == method.phases.index(before: method.phases.endIndex) {
                phaseIndex = index
                break
            }
            phaseStart = next
        }
        let phase = method.phases[phaseIndex]
        let elapsedInPhase = max(0, elapsed - phaseStart)
        let progress = phase.duration > 0 ? min(1, Double(elapsedInPhase) / Double(phase.duration)) : 0
        let instructionIndex = min(
            phase.instructions.count - 1,
            max(0, Int(floor(progress * Double(phase.instructions.count))))
        )
        return BandishMeditationPresentation(
            protocolName: method.name,
            technique: method.technique,
            elapsedText: BandishCardElapsedClock.format(elapsed),
            phaseName: phase.id,
            instruction: phase.instructions[instructionIndex],
            phases: phasePresentations(method.phases, activeIndex: phaseIndex, activeProgress: progress)
        )
    }

    private static func phasePresentations(
        _ phases: [MeditationPhase],
        activeIndex: Int,
        activeProgress: Double
    ) -> [BandishBodyPhasePresentation] {
        phases.enumerated().map { index, phase in
            let state: BandishBodyPhasePresentation.State = index < activeIndex
                ? .completed
                : (index == activeIndex ? .active : .pending)
            return BandishBodyPhasePresentation(
                id: phase.id,
                label: phase.id,
                progress: index < activeIndex ? 1 : (index == activeIndex ? activeProgress : 0),
                state: state
            )
        }
    }

    private static let methods: [String: MeditationMethod] = [
        "focused-attention": MeditationMethod(
            id: "focused-attention",
            name: "focused attention",
            technique: "ānāpānasati",
            phases: phases(
                prime: ["sit upright with spine naturally erect", "close your eyes gently", "take three deep breaths to settle", "find your natural breathing rhythm", "anchor attention on breath sensations"],
                practice: ["maintain continuous attention on breath", "when mind wanders, gently return to breath", "label distractions once, then release", "every 10 minutes, widen peripheral awareness", "correct dullness with gentle alertness"],
                close: ["expand awareness to whole body breathing", "reflect on the quality of attention", "set intention for daily mindfulness", "take three slow, conscious breaths", "gently open eyes when ready"]
            )
        ),
        "open-monitoring": MeditationMethod(
            id: "open-monitoring",
            name: "open monitoring",
            technique: "vipassanā",
            phases: phases(
                prime: ["establish brief breath anchor", "set intention: \"allow all experiences\"", "open awareness like sky", "release need to control", "rest in spacious presence"],
                practice: ["observe all phenomena without preference", "notice thoughts, sensations, emotions", "minimal noting: \"thinking\", \"feeling\", \"hearing\"", "return to open awareness when lost", "rest as the witness of experience"],
                close: ["reflect on the impermanent nature of all phenomena", "appreciate the spaciousness of awareness", "dedicate merit to all beings", "slowly return to ordinary consciousness", "carry this openness into daily life"]
            )
        ),
        "body-scan": MeditationMethod(
            id: "body-scan",
            name: "body scan",
            technique: "vipassanā",
            phases: phases(
                prime: ["lie down or sit comfortably", "feel contact points with surface", "take one deep grounding breath", "set intention for body awareness", "begin with feet"],
                practice: ["systematically scan from feet to head", "spend 30-60 seconds per body region", "notice sensations without judgment", "include areas of no sensation", "maintain equanimity with all experiences"],
                close: ["sense the body as a unified whole", "take six slow, conscious breaths", "appreciate the body's wisdom", "gently wiggle fingers and toes", "slowly return to sitting"]
            )
        ),
        "loving-kindness": MeditationMethod(
            id: "loving-kindness",
            name: "loving-kindness",
            technique: "mettā cultivation",
            phases: phases(
                prime: ["recall a moment of genuine warmth", "allow a gentle smile", "place hand on heart if helpful", "connect with natural kindness", "set intention for all beings"],
                practice: ["begin with loving-kindness for yourself", "extend to a beloved benefactor", "include a neutral person", "embrace a difficult person", "radiate to all beings everywhere"],
                close: ["rest in the warmth you've cultivated", "dedicate merit to all beings", "carry this kindness into daily interactions", "seal practice with gratitude", "gently open eyes with soft gaze"]
            )
        ),
    ]

    private static func phases(prime: [String], practice: [String], close: [String]) -> [MeditationPhase] {
        [
            MeditationPhase(id: "prime", duration: 300, instructions: prime),
            MeditationPhase(id: "practice", duration: 2_700, instructions: practice),
            MeditationPhase(id: "close", duration: 600, instructions: close),
        ]
    }
}

enum BandishWorkModeResolver {
    static func mode(_ rawValue: String?) -> String? {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value?.contains("divergent") == true || value?.contains("diverge") == true { return "divergent" }
        if value?.contains("convergent") == true || value?.contains("converge") == true || value?.contains("dhyān 1") == true || value?.contains("dhyan 1") == true {
            return "convergent"
        }
        if value?.contains("breakthrough") == true { return "breakthrough" }
        return nil
    }
}

private enum WorkPrepCatalog {

    static func duration(for mode: String) -> Int {
        switch mode {
        case "divergent": return 180
        case "breakthrough": return 300
        default: return 120
        }
    }

    static func presentation(mode: String, elapsedSeconds: Int) -> BandishWorkPresentation {
        let duration = duration(for: mode)
        let elapsed = max(0, min(duration, elapsedSeconds))
        let remaining = max(0, duration - elapsed)
        let boundaries = [Int((Double(duration) * 0.2).rounded()), Int((Double(duration) * 0.8).rounded()), duration]
        let index = elapsed < boundaries[0] ? 0 : (elapsed < boundaries[1] ? 1 : 2)
        let starts = [0, boundaries[0], boundaries[1]]
        let lengths = [boundaries[0], boundaries[1] - boundaries[0], boundaries[2] - boundaries[1]]
        let elapsedInPhase = max(0, elapsed - starts[index])
        let progress = lengths[index] > 0 ? min(1, Double(elapsedInPhase) / Double(lengths[index])) : 0
        let labels = ["settle", "focus", "ready"]
        let phaseIDs = ["prime", "practice", "close"]
        let protocolName = protocolName(for: mode)
        // Founder 2026-08-06: one lead cue per phase, not a sub-rotation through the
        // phase's three cues. The prep phase shows its opener the whole time.
        let instructions = instructionCatalog[protocolName]![index]
        let phases = labels.enumerated().map { phaseIndex, label in
            BandishBodyPhasePresentation(
                id: phaseIDs[phaseIndex],
                label: label,
                progress: phaseIndex < index ? 1 : (phaseIndex == index ? progress : 0),
                state: phaseIndex < index ? .completed : (phaseIndex == index ? .active : .pending)
            )
        }
        return BandishWorkPresentation(
            mode: mode,
            protocolName: protocolName,
            remainingText: BandishCardElapsedClock.format(remaining),
            phaseName: labels[index],
            instruction: instructions.first ?? "",
            phases: phases,
            taskLines: [],
            inProgressText: nil
        )
    }

    private static func protocolName(for mode: String) -> String {
        switch mode {
        case "divergent": return "open monitoring"
        case "breakthrough": return "deep jhana"
        default: return "focused attention"
        }
    }

    private static let instructionCatalog: [String: [[String]]] = [
        "open monitoring": [
            ["close your eyes", "open awareness like sky", "release need to control"],
            ["observe all phenomena", "notice without preference", "rest as witness"],
            ["appreciate spaciousness", "slowly return", "carry openness forward"],
        ],
        "focused attention": [
            ["close your eyes", "find breath sensations", "anchor attention"],
            ["maintain focus on breath", "when mind wanders, return", "stay with each breath"],
            ["widen awareness gently", "prepare for focused work", "open eyes slowly"],
        ],
        "deep jhana": [
            ["close your eyes", "release all tension", "settle deeply"],
            ["rest in stillness", "let mind become quiet", "allow absorption"],
            ["emerge gently", "maintain calm clarity", "begin with presence"],
        ],
    ]
}

enum CadencePreviousToggleLabel {
    static func text(isExpanded: Bool, count: Int) -> String? {
        guard count > 0 else { return nil }
        return isExpanded ? "HIDE PREVIOUS" : "SHOW PREVIOUS (\(count))"
    }
}

// MARK: - Native bodies

struct BandishBodiesView: View {
    let block: CadenceBlock
    let temporal: BandishBodyTemporalVariant
    let actionState: KBlockActionState
    let baselineElapsedSeconds: Int
    let clockReferenceDate: Date
    let isRunning: Bool
    let foregroundColor: Color
    let usesPaperTone: Bool
    let onSubtaskToggle: (Subtask) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var skipsWorkPreparation = false

    var body: some View {
        Group {
            if isRunning && tickedKind {
                TimelineView(.periodic(from: clockReferenceDate, by: BandishBodyMotionSpec.timerTickInterval)) { context in
                    content(elapsedSeconds: clock.elapsedSeconds(at: context.date) ?? baselineElapsedSeconds)
                }
            } else {
                content(elapsedSeconds: baselineElapsedSeconds)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var clock: BandishCardElapsedClock {
        BandishCardElapsedClock(
            baselineElapsedSeconds: baselineElapsedSeconds,
            referenceDate: clockReferenceDate,
            isRunning: isRunning
        )
    }

    private var tickedKind: Bool {
        block.normalizedTypeText == "meditation" || block.normalizedTypeText == "work"
    }

    @ViewBuilder
    private func content(elapsedSeconds: Int) -> some View {
        let presentation = BandishBodyVariantResolver.presentation(
            for: block,
            temporal: temporal,
            actionState: actionState,
            elapsedSeconds: effectiveElapsedSeconds(elapsedSeconds)
        )
        switch presentation.kind {
        case .mealAnalysis:
            if let meal = presentation.meal {
                BandishMealAnalysisView(presentation: meal, foregroundColor: foregroundColor)
            }
        case .sleepOverview:
            if let sleep = presentation.sleep {
                BandishSleepOverviewView(presentation: sleep, foregroundColor: foregroundColor)
            }
        case .meditationProtocol, .meditationSession:
            if let meditation = presentation.meditation {
                BandishMeditationBodyView(
                    presentation: meditation,
                    foregroundColor: foregroundColor,
                    phaseFillColor: block.ring.color
                )
            }
        case .workPreparation, .workSession:
            if let work = presentation.work {
                BandishWorkBodyView(
                    presentation: work,
                    subtasks: block.subtasks,
                    foregroundColor: foregroundColor,
                    phaseFillColor: block.ring.color,
                    actionState: actionState,
                    usesCurrentTaskRows: temporal.rendersCurrentBody,
                    usesPaperTone: usesPaperTone,
                    reduceMotion: reduceMotion,
                    onSkipPreparation: { skipsWorkPreparation = true },
                    onSubtaskToggle: onSubtaskToggle
                )
            }
        case .workoutLive, .workoutDetail:
            if let workout = presentation.workout {
                BandishWorkoutBodyView(
                    presentation: workout,
                    foregroundColor: foregroundColor
                )
            }
        case .none:
            EmptyView()
        }
    }

    private func effectiveElapsedSeconds(_ elapsedSeconds: Int) -> Int {
        guard skipsWorkPreparation,
              let mode = BandishWorkModeResolver.mode(block.brainState)
                ?? BandishWorkModeResolver.mode(block.mode)
        else { return elapsedSeconds }
        return max(elapsedSeconds, WorkPrepCatalog.duration(for: mode))
    }
}

private struct BandishMealAnalysisView: View {
    let presentation: BandishMealAnalysisPresentation
    let foregroundColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: KStyle.bandishMealColumnSpacing) {
            metricColumn(presentation.macroColumn)
            ForEach(Array(presentation.micronutrientColumns.enumerated()), id: \.offset) { column in
                metricColumn(column.element)
            }
        }
        .padding(.top, KStyle.bandishBodyTopSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-meal-analysis-grid")
    }

    private func metricColumn(_ values: [BandishBodyMetric]) -> some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            ForEach(values) { metric in
                VStack(alignment: .leading, spacing: .zero) {
                    Text(metric.label)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                    Text(metric.value)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BandishWorkoutBodyView: View {
    let presentation: BandishWorkoutPresentation
    let foregroundColor: Color

    private var isDetail: Bool { presentation.state == .completed }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bandishWorkoutSectionSpacing) {
            if !isDetail {
                BandishDeviceStatusRow(
                    devices: [
                        BandishDeviceStatus(name: presentation.sourceText ?? "whoop", hasData: true),
                        BandishDeviceStatus(name: "apple watch", hasData: false),
                    ],
                    foregroundColor: foregroundColor
                )
            }

            strainSummary

            if let recordingText = presentation.recordingText {
                HStack(spacing: KStyle.tightRowSpacing) {
                    Circle()
                        .fill(presentation.state == .midWorkout ? KStyle.bandishSuccessColor : foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                        .frame(width: KStyle.bandishDeviceDotSize, height: KStyle.bandishDeviceDotSize)
                    Text(recordingText)
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                    if let sourceText = presentation.sourceText {
                        Text(sourceText)
                            .font(KStyle.bandishFont(.secondaryInfo))
                            .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                    }
                }
                .accessibilityIdentifier("bandish-workout-recording")
            }

            zoneLadder
            effortCurve

            if let tonnageText = presentation.tonnageText {
                Text(tonnageText)
                    .font(KStyle.bandishFont(.secondaryInfo))
                    .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                    .accessibilityIdentifier("bandish-workout-tonnage")
            }

            if isDetail, !presentation.exercises.isEmpty {
                exerciseSummary
            }

            if isDetail, let recoveryHint = presentation.recoveryHint {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    Text("recovery")
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .tracking(KStyle.bandishWorkoutHeaderTracking)
                        .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                    Text(recoveryHint)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bandish-workout-recovery")
            }
        }
        .padding(.top, KStyle.bandishBodyTopSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isDetail ? "bandish-workout-detail" : "bandish-workout-body")
    }

    private var strainSummary: some View {
        HStack(alignment: .top, spacing: KStyle.bandishWorkoutMetricSpacing) {
            metric(label: "strain", value: presentation.strainText)
            metric(label: "target", value: presentation.targetStrainText)
            if let caloriesText = presentation.caloriesText {
                metric(label: "kcal", value: caloriesText.replacingOccurrences(of: " kcal", with: ""))
            }
            if let currentZoneText = presentation.currentZoneText {
                metric(label: "now", value: currentZoneText)
            }
            if let heartRateText = presentation.heartRateText {
                metric(label: "hr", value: heartRateText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-workout-strain")
    }

    @ViewBuilder
    private func metric(label: String, value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: .zero) {
                Text(label)
                    .font(KStyle.bandishFont(.secondaryInfo))
                    .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                Text(value)
                    .font(KStyle.bandishFont(.title))
                    .monospacedDigit()
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
            }
            .frame(minWidth: KStyle.bandishWorkoutMetricMinimumWidth, alignment: .leading)
        }
    }

    private var zoneLadder: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            Text("zones")
                .font(KStyle.bandishFont(.secondaryInfo))
                .tracking(KStyle.bandishWorkoutHeaderTracking)
                .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))

            ForEach(presentation.zones) { zone in
                HStack(spacing: KStyle.bandishWorkoutZoneSpacing) {
                    Text(zone.label)
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .foregroundStyle(foregroundColor.opacity(zone.isCurrent ? KStyle.fullOpacity : KStyle.tertiaryTextOpacity))
                        .frame(width: KStyle.bandishWorkoutZoneLabelWidth, alignment: .leading)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(foregroundColor.opacity(KStyle.bandishWorkoutTrackOpacity))
                            Rectangle()
                                .fill(foregroundColor.opacity(zone.isCurrent ? KStyle.fullOpacity : KStyle.secondaryTextOpacity))
                                .frame(width: proxy.size.width * zone.ratio)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
                    }
                    .frame(height: KStyle.bandishWorkoutZoneBarHeight)

                    Text("\(zone.minutes)m")
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                        .frame(width: KStyle.bandishWorkoutMinutesWidth, alignment: .trailing)
                }
                .frame(minHeight: KStyle.bandishWorkoutZoneRowHeight)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-workout-zone-ladder")
    }

    private var effortCurve: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            Text("effort")
                .font(KStyle.bandishFont(.secondaryInfo))
                .tracking(KStyle.bandishWorkoutHeaderTracking)
                .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
            BandishWorkoutEffortCurve(points: presentation.effortCurve, foregroundColor: foregroundColor)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-workout-effort-curve")
    }

    private var exerciseSummary: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            Text("exercises")
                .font(KStyle.bandishFont(.secondaryInfo))
                .tracking(KStyle.bandishWorkoutHeaderTracking)
                .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
            ForEach(presentation.exercises) { exercise in
                HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                    Text(exercise.completed ? "done" : "open")
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .foregroundStyle(foregroundColor.opacity(exercise.completed ? KStyle.tertiaryTextOpacity : KStyle.secondaryTextOpacity))
                        .frame(width: KStyle.bandishWorkoutExerciseStateWidth, alignment: .leading)
                    Text(exercise.name)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor.opacity(exercise.completed ? KStyle.tertiaryTextOpacity : KStyle.secondaryTextOpacity))
                    if let detail = exercise.detail {
                        Text(detail)
                            .font(KStyle.bandishFont(.secondaryInfo))
                            .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-workout-exercises")
    }
}

private struct BandishWorkoutEffortCurve: View {
    let points: [Double]
    let foregroundColor: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(foregroundColor.opacity(KStyle.bandishWorkoutTrackOpacity))
                    .frame(height: KStyle.hairlineWidth)
                Path { path in
                    let values = points.isEmpty ? [0.0, 0.0] : points
                    let width = max(.zero, proxy.size.width)
                    let height = KStyle.bandishWorkoutCurveHeight
                    let step = values.count > 1 ? width / CGFloat(values.count - 1) : width
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * step
                        let y = height * (1 - CGFloat(min(1, max(0, value))))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(foregroundColor.opacity(KStyle.secondaryTextOpacity), lineWidth: KStyle.bandishWorkoutCurveLineWidth)
            }
        }
        .frame(height: KStyle.bandishWorkoutCurveHeight)
        .accessibilityIdentifier("bandish-workout-effort-curve-plot")
    }
}

private struct BandishSleepOverviewView: View {
    let presentation: BandishSleepPresentation
    let foregroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bandishSleepSectionSpacing) {
            if !presentation.stages.isEmpty {
                stagePanel
            }

            BandishDeviceStatusRow(
                devices: [
                    BandishDeviceStatus(name: "whoop", hasData: !presentation.stages.isEmpty),
                    BandishDeviceStatus(name: "apple watch", hasData: false),
                ],
                foregroundColor: foregroundColor
            )

            if let orientation = presentation.orientation {
                BandishMorningOrientationView(presentation: orientation, foregroundColor: foregroundColor)
            }
        }
        .padding(.top, KStyle.bandishSleepTopSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-sleep-overview")
    }

    private var stagePanel: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            HStack(spacing: KStyle.bandishSleepMetricSpacing) {
                Color.clear
                    .frame(width: KStyle.bandishSleepEfficiencyWidth)
                    .accessibilityHidden(true)
                GeometryReader { proxy in
                    HStack(spacing: .zero) {
                        ForEach(presentation.stages) { stage in
                            Text(stage.label)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                                .lineLimit(1)
                                .minimumScaleFactor(KStyle.bandishStageMinimumScale)
                                .frame(width: proxy.size.width * stage.ratio)
                        }
                    }
                }
            }
            .frame(height: KStyle.bandishStageLabelHeight)

            HStack(alignment: .center, spacing: KStyle.bandishSleepMetricSpacing) {
                Group {
                    if let efficiencyText = presentation.efficiencyText {
                        Text(efficiencyText)
                            .font(KStyle.bandishSleepEfficiencyFont)
                            .monospacedDigit()
                            .foregroundStyle(foregroundColor)
                    }
                }
                .frame(width: KStyle.bandishSleepEfficiencyWidth, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(foregroundColor.opacity(KStyle.bandishSleepStageTrackOpacity))
                        HStack(spacing: .zero) {
                            ForEach(Array(presentation.stages.enumerated()), id: \.element.id) { stage in
                                Rectangle()
                                    .fill(KStyle.bandishSleepStageColor(at: stage.offset))
                                    .frame(width: proxy.size.width * stage.element.ratio)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
                }
                .frame(height: KStyle.bandishSleepStageBarHeight)
            }

            if let needText = presentation.needText {
                let value = needText.hasPrefix("need ") ? String(needText.dropFirst(5)) : needText
                (Text("need ")
                    .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                    + Text(value)
                    .foregroundStyle(foregroundColor))
                    .font(KStyle.bandishFont(.title))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-sleep-stage-bar")
    }
}

private struct BandishMorningOrientationView: View {
    let presentation: BandishOrientationPresentation
    let foregroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let completionText = presentation.completionText {
                Text(completionText)
                    .font(KStyle.bandishFont(.secondaryInfo))
                    .foregroundStyle(KStyle.bandishSuccessColor)
            } else {
                if let summary = presentation.summary {
                    Text(summary)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor)
                }

                if !presentation.decisions.isEmpty {
                    sectionHeader("decisions")
                    ForEach(presentation.decisions) { decision in
                        VStack(alignment: .leading, spacing: .zero) {
                            Text(decision.observation)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                                .lineLimit(1)
                            if let urgency = decision.urgency {
                                Text(urgency)
                                    .font(KStyle.bandishFont(.secondaryInfo))
                                    .foregroundStyle(foregroundColor.opacity(KStyle.quaternaryTextOpacity))
                            }
                        }
                    }
                }

                if !presentation.priorities.isEmpty {
                    sectionHeader("today")
                    ForEach(presentation.priorities) { priority in
                        HStack(spacing: KStyle.tightRowSpacing) {
                            Text(priority.time ?? "")
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .monospacedDigit()
                                .foregroundStyle(foregroundColor.opacity(KStyle.quaternaryTextOpacity))
                                .frame(width: KStyle.bandishOrientationTimeWidth, alignment: .trailing)
                            Text(priority.title)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-morning-orientation")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(KStyle.bandishFont(.secondaryInfo))
            .tracking(KStyle.bandishOrientationTracking)
            .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
    }
}

private struct BandishMeditationBodyView: View {
    let presentation: BandishMeditationPresentation
    let foregroundColor: Color
    let phaseFillColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bandishMeditationSectionSpacing) {
            if let elapsedText = presentation.elapsedText {
                HStack(alignment: .center, spacing: KStyle.bandishMeditationTimerSpacing) {
                    Text(elapsedText)
                        .font(KStyle.bandishBodyTimerFont)
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor)
                    BandishPhaseTabs(
                        phases: presentation.phases,
                        foregroundColor: foregroundColor,
                        fillColor: phaseFillColor
                    )
                }

                if let instruction = presentation.instruction {
                    (Text("\(presentation.protocolName): ")
                        .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                     + Text(instruction).foregroundStyle(foregroundColor))
                        .font(KStyle.bandishFont(.title))
                        .id(instruction)
                        .transition(.opacity)
                        .animation(
                            KStyle.bandishMeditationInstructionAnimation(reduceMotion: reduceMotion),
                            value: instruction
                        )
                }
            } else {
                BandishDeviceStatusRow(
                    devices: [
                        BandishDeviceStatus(name: "neurosity", hasData: false),
                        BandishDeviceStatus(name: "whoop", hasData: false),
                    ],
                    foregroundColor: foregroundColor
                )
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    Text(presentation.protocolName)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor)
                    Text(presentation.technique)
                        .font(KStyle.bandishFont(.secondaryInfo))
                        .foregroundStyle(foregroundColor.opacity(KStyle.tertiaryTextOpacity))
                }
            }
        }
        .padding(.top, KStyle.bandishBodyTopSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-meditation-body")
    }
}

private struct BandishWorkBodyView: View {
    let presentation: BandishWorkPresentation
    let subtasks: [Subtask]
    let foregroundColor: Color
    let phaseFillColor: Color
    let actionState: KBlockActionState
    let usesCurrentTaskRows: Bool
    let usesPaperTone: Bool
    let reduceMotion: Bool
    let onSkipPreparation: () -> Void
    let onSubtaskToggle: (Subtask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bandishWorkSectionSpacing) {
            if let remainingText = presentation.remainingText {
                HStack(alignment: .center, spacing: KStyle.bandishMeditationTimerSpacing) {
                    Text(remainingText)
                        .font(KStyle.bandishBodyTimerFont)
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor)
                    BandishPhaseTabs(
                        phases: presentation.phases,
                        foregroundColor: foregroundColor,
                        fillColor: phaseFillColor
                    )
                }

                HStack(alignment: .bottom, spacing: KStyle.tightRowSpacing) {
                    if let protocolName = presentation.protocolName,
                       let instruction = presentation.instruction {
                        (Text("\(protocolName): ")
                            .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                         + Text(instruction).foregroundStyle(foregroundColor))
                            .font(KStyle.bandishFont(.title))
                            .id(instruction)
                            .transition(.opacity.combined(with: .offset(y: KStyle.bandishWorkInstructionOffset)))
                            .animation(
                                KStyle.bandishWorkInstructionAnimation(reduceMotion: reduceMotion),
                                value: instruction
                            )
                    }
                    Spacer(minLength: KStyle.tightRowSpacing)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "skip",
                                label: "skip",
                                accessibilityIdentifier: "bandish-work-prep-skip"
                            ),
                        ],
                        variant: .cadence,
                        onSelect: { _ in onSkipPreparation() }
                    )
                    .environment(\.kInkOnPaper, usesPaperTone)
                }
            } else if let inProgressText = presentation.inProgressText {
                Text(inProgressText)
                    .font(KStyle.bandishFont(.title))
                    .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
            } else {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    ForEach(Array(presentation.taskLines.enumerated()), id: \.element.id) { task in
                        if usesCurrentTaskRows {
                            Button {
                                guard actionState == .started,
                                      let subtask = subtasks.first(where: { $0.id == task.element.id })
                                else { return }
                                onSubtaskToggle(subtask)
                            } label: {
                                taskText(task.element, fontRole: .title)
                                    .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(actionState != .started)
                            .bandishWorkReveal(index: task.offset, reduceMotion: reduceMotion)
                            .accessibilityIdentifier("bandish-work-task-\(task.element.id)")
                        } else {
                            taskText(task.element, fontRole: .secondaryInfo)
                                .bandishWorkReveal(index: task.offset, reduceMotion: reduceMotion)
                        }
                    }
                }
            }
        }
        .padding(.top, KStyle.bandishBodyTopSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-work-body")
    }

    private func taskText(
        _ task: BandishWorkTaskLine,
        fontRole: BandishCardTextRole
    ) -> some View {
        Text(task.text)
            .font(KStyle.bandishFont(fontRole))
            .foregroundStyle(
                foregroundColor.opacity(task.isDone ? KStyle.quaternaryTextOpacity : KStyle.tertiaryTextOpacity)
            )
            .strikethrough(task.isDone)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BandishPhaseTabs: View {
    let phases: [BandishBodyPhasePresentation]
    let foregroundColor: Color
    let fillColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: .zero) {
            ForEach(phases) { phase in
                ZStack {
                    Rectangle()
                        .fill(fillColor)
                        .scaleEffect(x: phase.progress, y: KStyle.identityScale, anchor: .leading)
                        .animation(
                            KStyle.bandishPhaseProgressAnimation(reduceMotion: reduceMotion),
                            value: phase.progress
                        )
                    Text(phase.label)
                        .font(KStyle.bandishPhaseFont)
                        .tracking(KStyle.bandishPhaseTracking)
                        .foregroundStyle(
                            phase.progress > KStyle.bandishPhaseFilledLabelThreshold
                                ? Color.white
                                : foregroundColor.opacity(KStyle.tertiaryTextOpacity)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: KStyle.bandishPhaseSegmentHeight)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .background(foregroundColor.opacity(KStyle.bandishPhaseTrackOpacity))
        .clipShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-guided-phase-tabs")
    }
}

private struct BandishDeviceStatus: Identifiable {
    var name: String
    var hasData: Bool
    var id: String { name }
}

private struct BandishDeviceStatusRow: View {
    let devices: [BandishDeviceStatus]
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: KStyle.bandishDeviceSpacing) {
            Spacer(minLength: .zero)
            ForEach(devices) { device in
                HStack(spacing: KStyle.bandishDeviceNameSpacing) {
                    Text(device.name)
                        .font(KStyle.bandishFont(.title))
                        .foregroundStyle(foregroundColor.opacity(KStyle.secondaryTextOpacity))
                    Circle()
                        .fill(device.hasData ? KStyle.bandishSuccessColor : KStyle.bandishDeviceDisabledColor)
                        .frame(width: KStyle.bandishDeviceDotSize, height: KStyle.bandishDeviceDotSize)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.trailing, KStyle.bandishDeviceTrailingPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-device-status")
    }
}

enum BandishBodyMotionSpec {
    static let timerTickInterval: TimeInterval = 1
    static let meditationInstructionDuration: TimeInterval = 0.3
    static let instructionDuration: TimeInterval = 1
    static let workRevealDuration: TimeInterval = 2
    static let workRevealStagger: TimeInterval = 0.2
}

private struct BandishWorkRevealModifier: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var isRevealed = false

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed || reduceMotion ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? .zero : KStyle.bandishWorkRowEntranceOffset)
            .onAppear {
                withAnimation(KStyle.bandishWorkRevealAnimation(index: index, reduceMotion: reduceMotion)) {
                    isRevealed = true
                }
            }
    }
}

private extension View {
    func bandishWorkReveal(index: Int, reduceMotion: Bool) -> some View {
        modifier(BandishWorkRevealModifier(index: index, reduceMotion: reduceMotion))
    }
}

extension KStyle {
    static let bandishBodyTopSpacing = tightRowSpacing
    static let bandishMealColumnSpacing: CGFloat = 16
    static let bandishSleepTopSpacing: CGFloat = 16
    static let bandishSleepSectionSpacing: CGFloat = 12
    static let bandishSleepMetricSpacing: CGFloat = 12
    static let bandishSleepEfficiencyWidth: CGFloat = 48
    static let bandishSleepStageBarHeight: CGFloat = 12
    static let bandishSleepStageTrackOpacity = 0.10
    static let bandishStageLabelHeight: CGFloat = 14
    static let bandishStageMinimumScale: CGFloat = 0.6
    static let bandishMeditationSectionSpacing: CGFloat = 12
    static let bandishMeditationTimerSpacing: CGFloat = 12
    static let bandishWorkSectionSpacing: CGFloat = 12
    static let bandishWorkInstructionOffset: CGFloat = 4
    static let bandishWorkRowEntranceOffset: CGFloat = 8
    static let bandishPhaseSegmentHeight: CGFloat = 24
    static let bandishPhaseTrackOpacity = 0.15
    static let bandishPhaseFilledLabelThreshold = 0.5
    static let bandishPhaseTracking: CGFloat = 0.5
    static let bandishPhaseFont = Font.system(size: 10, weight: .medium, design: .default)
    static let bandishDeviceSpacing: CGFloat = 16
    static let bandishDeviceNameSpacing: CGFloat = 8
    static let bandishDeviceDotSize: CGFloat = 8
    static let bandishDeviceTrailingPadding: CGFloat = 16
    static let bandishOrientationTracking: CGFloat = 0.6
    static let bandishOrientationTimeWidth: CGFloat = 48
    // doctrine: recognition-over-recall + honest-motion. Workout depth composes
    // from the existing bandish body grammar;
    // these geometry values stay in KStyle so the zone ladder and effort plot do
    // not create a second styling vocabulary.
    static let bandishWorkoutSectionSpacing: CGFloat = 12
    static let bandishWorkoutMetricSpacing: CGFloat = 12
    static let bandishWorkoutMetricMinimumWidth: CGFloat = 52
    static let bandishWorkoutHeaderTracking: CGFloat = 0.5
    static let bandishWorkoutZoneSpacing: CGFloat = 8
    static let bandishWorkoutZoneLabelWidth: CGFloat = 26
    static let bandishWorkoutMinutesWidth: CGFloat = 32
    static let bandishWorkoutZoneBarHeight: CGFloat = 8
    static let bandishWorkoutZoneRowHeight: CGFloat = 16
    static let bandishWorkoutTrackOpacity = 0.12
    static let bandishWorkoutCurveHeight: CGFloat = 48
    static let bandishWorkoutCurveLineWidth: CGFloat = 1.5
    static let bandishWorkoutExerciseStateWidth: CGFloat = 34
    static let bandishBodyTimerFont = Font.system(size: 24, weight: .regular, design: .default)
    static let bandishSleepEfficiencyFont = Font.system(size: 20, weight: .regular, design: .default)
    static let bandishDeviceDisabledColor = Color(red: 0.63, green: 0.63, blue: 0.67)
    static let bandishSuccessColor = Color(red: 107 / 255, green: 157 / 255, blue: 124 / 255)

    static func bandishSleepStageColor(at index: Int) -> Color {
        let colors = [
            Color(red: 33 / 255, green: 41 / 255, blue: 54 / 255),
            Color(red: 45 / 255, green: 72 / 255, blue: 103 / 255),
            Color(red: 136 / 255, green: 154 / 255, blue: 159 / 255),
            Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255),
        ]
        return colors[max(0, min(colors.count - 1, index))]
    }

    static func bandishMeditationInstructionAnimation(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .easeOut(duration: BandishBodyMotionSpec.meditationInstructionDuration)
    }

    static func bandishWorkInstructionAnimation(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .timingCurve(0.15, 0, 0.15, 1, duration: BandishBodyMotionSpec.instructionDuration)
    }

    static func bandishPhaseProgressAnimation(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .easeOut(duration: 0.3)
    }

    static func bandishWorkRevealAnimation(index: Int, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .timingCurve(0.15, 0, 0.15, 1, duration: BandishBodyMotionSpec.workRevealDuration)
            .delay(Double(index) * BandishBodyMotionSpec.workRevealStagger)
    }
}

private extension KeyedDecodingContainer {
    func bandishFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
