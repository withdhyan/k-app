import Foundation
import SwiftUI
import UIKit
struct BodyCueContext: Decodable, Equatable, Sendable {
    var baselines: BodyCueBaselines?
    var zScores: BodyCueZScores?
    var protocols: [BodyCueProtocol]
    var generatedAt: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case baselines
        case zScores
        case protocols
        case generatedAt
        case source
    }

    init(
        baselines: BodyCueBaselines? = nil,
        zScores: BodyCueZScores? = nil,
        protocols: [BodyCueProtocol] = [],
        generatedAt: String? = nil,
        source: String? = nil
    ) {
        self.baselines = baselines
        self.zScores = zScores
        self.protocols = protocols
        self.generatedAt = generatedAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = Self.normalizedSource(source)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baselines = try? container.decodeIfPresent(BodyCueBaselines.self, forKey: .baselines)
        zScores = try? container.decodeIfPresent(BodyCueZScores.self, forKey: .zScores)
        protocols = (try? container.decode(LossyCadenceArray<BodyCueProtocol>.self, forKey: .protocols).elements) ?? []
        generatedAt = try container.decodeTrimmedString(for: .generatedAt)
        source = Self.normalizedSource(try container.decodeTrimmedString(for: .source))
    }

    private static func normalizedSource(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BodyCueBaselines: Decodable, Equatable, Sendable {
    var hrv: Double?
    var hrvDrift: BodyCueDrift?
    var samples: Int?

    enum CodingKeys: String, CodingKey {
        case hrv
        case hrvDrift
        case samples
    }

    init(hrv: Double? = nil, hrvDrift: BodyCueDrift? = nil, samples: Int? = nil) {
        self.hrv = hrv
        self.hrvDrift = hrvDrift
        self.samples = samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hrv = try container.decodeFlexibleDouble(for: .hrv)
        hrvDrift = try? container.decodeIfPresent(BodyCueDrift.self, forKey: .hrvDrift)
        samples = try container.decodeFlexibleInt(for: .samples)
    }
}

struct BodyCueDrift: Decodable, Equatable, Sendable {
    var latest: Double?
    var baseline: Double?
    var delta: Double?
    var direction: String?
    var samples: Int?

    enum CodingKeys: String, CodingKey {
        case latest
        case baseline
        case delta
        case direction
        case samples
    }

    init(
        latest: Double? = nil,
        baseline: Double? = nil,
        delta: Double? = nil,
        direction: String? = nil,
        samples: Int? = nil
    ) {
        self.latest = latest
        self.baseline = baseline
        self.delta = delta
        self.direction = direction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.samples = samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeFlexibleDouble(for: .latest)
        baseline = try container.decodeFlexibleDouble(for: .baseline)
        delta = try container.decodeFlexibleDouble(for: .delta)
        direction = try container.decodeTrimmedString(for: .direction)?.lowercased()
        samples = try container.decodeFlexibleInt(for: .samples)
    }
}

struct BodyCueZScores: Decodable, Equatable, Sendable {
    var hrv: BodyCueZScore?

    enum CodingKeys: String, CodingKey {
        case hrv
    }

    init(hrv: BodyCueZScore? = nil) {
        self.hrv = hrv
    }
}

struct BodyCueZScore: Decodable, Equatable, Sendable {
    var latest: Double?
    var baselineMean: Double?
    var standardDeviation: Double?
    var zScore: Double?
    var direction: String?
    var samples: Int?
    var windowDays: Int?

    enum CodingKeys: String, CodingKey {
        case latest
        case baselineMean
        case baseline_mean
        case standardDeviation
        case standard_deviation
        case zScore
        case z_score
        case direction
        case samples
        case windowDays
        case window_days
    }

    init(
        latest: Double? = nil,
        baselineMean: Double? = nil,
        standardDeviation: Double? = nil,
        zScore: Double? = nil,
        direction: String? = nil,
        samples: Int? = nil,
        windowDays: Int? = nil
    ) {
        self.latest = latest
        self.baselineMean = baselineMean
        self.standardDeviation = standardDeviation
        self.zScore = zScore
        self.direction = direction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.samples = samples
        self.windowDays = windowDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeFlexibleDouble(for: .latest)
        baselineMean = try container.decodeFlexibleDouble(for: .baselineMean)
            ?? container.decodeFlexibleDouble(for: .baseline_mean)
        standardDeviation = try container.decodeFlexibleDouble(for: .standardDeviation)
            ?? container.decodeFlexibleDouble(for: .standard_deviation)
        zScore = try container.decodeFlexibleDouble(for: .zScore)
            ?? container.decodeFlexibleDouble(for: .z_score)
        direction = try container.decodeTrimmedString(for: .direction)?.lowercased()
        samples = try container.decodeFlexibleInt(for: .samples)
        windowDays = try container.decodeFlexibleInt(for: .windowDays)
            ?? container.decodeFlexibleInt(for: .window_days)
    }
}

struct BodyCueProtocol: Identifiable, Decodable, Equatable, Sendable {
    var id: String
    var packetId: String?
    var target: String?
    var action: String?
    var object: String?
    var basis: String?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case interventionId
        case intervention_id
        case packetId
        case packet_id
        case target
        case action
        case object
        case basis
        case confidence
    }

    init(
        id: String? = nil,
        packetId: String? = nil,
        target: String? = nil,
        action: String? = nil,
        object: String? = nil,
        basis: String? = nil,
        confidence: Double? = nil
    ) {
        self.target = Self.normalizedText(target)
        self.action = Self.normalizedText(action)
        self.object = Self.normalizedText(object)
        self.basis = Self.normalizedText(basis)
        self.confidence = confidence
        self.packetId = Self.normalizedText(packetId)
        self.id = Self.normalizedID(id) ?? Self.fallbackID(target: self.target, action: self.action, object: self.object)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let target = Self.normalizedText(try container.decodeFlexibleText(for: .target))
        let action = Self.normalizedText(try container.decodeFlexibleText(for: .action))
        let object = Self.normalizedText(try container.decodeFlexibleText(for: .object))
        self.target = target
        self.action = action
        self.object = object
        basis = Self.normalizedText(try container.decodeFlexibleText(for: .basis))
        confidence = try container.decodeFlexibleDouble(for: .confidence)
        packetId = Self.normalizedText(
            try container.decodeFlexibleText(for: .packetId)
                ?? container.decodeFlexibleText(for: .packet_id)
        )
        id = Self.normalizedID(
            try container.decodeFlexibleText(for: .id)
                ?? container.decodeFlexibleText(for: .interventionId)
                ?? container.decodeFlexibleText(for: .intervention_id)
        ) ?? Self.fallbackID(target: target, action: action, object: object)
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func fallbackID(target: String?, action: String?, object: String?) -> String {
        let parts = [target, action, object]
            .compactMap(normalizedIDPart)
        return parts.isEmpty ? "body.intervention" : parts.joined(separator: ".")
    }

    private static func normalizedIDPart(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: " ", with: "_")
    }
}

enum BodyInterventionFeedbackAction: String, Equatable, Sendable {
    case accept
    case dismiss
}

extension BodyInterventionFeedbackAction: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "accept", "accepted":
            self = .accept
        case "dismiss", "dismissed":
            self = .dismiss
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported body intervention feedback action"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct BodyInterventionFeedbackResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var record: Record?
    var error: String?

    struct Record: Decodable, Equatable, Sendable {
        var action: BodyInterventionFeedbackAction?
    }
}

enum BodyCueContextRailFormatter {
    static func lines(from context: BodyCueContext?) -> [String] {
        [
            hrvLine(from: context?.baselines),
            zLine(from: context?.zScores?.hrv),
        ].compactMap { $0 }
    }

    static func hrvLine(from baselines: BodyCueBaselines?) -> String? {
        guard let baselines else { return nil }
        let drift = baselines.hrvDrift
        let latest = drift?.latest ?? baselines.hrv
        guard let latest else { return nil }

        var line = "hrv \(numberText(latest))"
        if let baseline = drift?.baseline ?? (drift?.latest == nil ? nil : baselines.hrv) {
            line += " · baseline \(numberText(baseline))"
        }
        if let arrow = directionArrow(drift?.direction) {
            line += " \(arrow)"
        }
        return line
    }

    static func zLine(from zScore: BodyCueZScore?) -> String? {
        guard let score = zScore?.zScore else { return nil }
        var parts = ["z \(signedFixedOneDecimal(score))"]
        if let windowDays = zScore?.windowDays, windowDays > 0 {
            parts.append("\(windowDays)d")
        }
        return parts.joined(separator: " · ")
    }

    private static func directionArrow(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else { return nil }

        if ["↑", "up", "higher", "positive", "rising", "rise", "increase", "increasing"].contains(value) {
            return "↑"
        }
        if ["↓", "down", "lower", "negative", "falling", "fall", "decrease", "decreasing"].contains(value) {
            return "↓"
        }
        if ["→", "steady", "stable", "flat", "same", "neutral"].contains(value) {
            return "→"
        }
        return nil
    }

    private static func signedFixedOneDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value < 0 {
            return "−\(fixedOneDecimal(abs(value)))"
        }
        if value > 0 {
            return "+\(fixedOneDecimal(value))"
        }
        return fixedOneDecimal(.zero)
    }

    private static func fixedOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return fixedOneDecimal(value)
    }
}

enum BodyCueProtocolFormatter {
    static func line(for item: BodyCueProtocol) -> String {
        let actionObject = [humanText(item.action), humanText(item.object)]
            .compactMap { $0 }
            .joined(separator: " ")
        let focus = actionObject.isEmpty ? humanText(item.target) : actionObject
        let parts = [
            focus?.isEmpty == false ? focus : nil,
            humanText(item.basis),
            item.confidence.flatMap(confidenceText),
        ].compactMap { $0 }
        return parts.isEmpty ? "body intervention" : parts.joined(separator: " · ")
    }

    private static func humanText(_ value: String?) -> String? {
        let text = value?
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return text?.isEmpty == false ? text : nil
    }

    private static func confidenceText(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct CadenceBodyInterventionsChecklistModel: Equatable {
    var protocols: [BodyCueProtocol]
    var pendingIDs: Set<String>
    var errorText: String?

    init?(
        context: BodyCueContext?,
        dismissedIDs: Set<String>,
        pendingIDs: Set<String>,
        errorText: String?
    ) {
        let items = (context?.protocols ?? []).filter { !dismissedIDs.contains($0.id) }
        let normalizedError = Self.normalized(errorText)
        guard !items.isEmpty else { return nil }
        protocols = items
        self.pendingIDs = pendingIDs
        self.errorText = normalizedError
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}


