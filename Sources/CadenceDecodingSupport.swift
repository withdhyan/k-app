import Foundation
import SwiftUI
import UIKit
struct LossyCadenceArray<Element: Decodable>: Decodable {
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

struct FlexibleCadenceDouble: Decodable {
    var value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let string = try? container.decode(String.self),
                  let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.value = value
        } else {
            self.value = 0
        }
    }
}

extension KeyedDecodingContainer {
    func decodeTrimmedString(for key: Key, _ cadenceScope: Void = ()) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    func decodeFlexibleBool(for key: Key, _ cadenceScope: Void = ()) throws -> Bool? {
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

    func decodeFlexibleInt(for key: Key, _ cadenceScope: Void = ()) throws -> Int? {
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

    func decodeFlexibleDouble(for key: Key, _ cadenceScope: Void = ()) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return value
        }
        guard let string = try decodeTrimmedString(for: key),
              let value = Double(string),
              value.isFinite
        else {
            return nil
        }
        return value
    }

    func decodeStringArray(for key: Key, _ cadenceScope: Void = ()) throws -> [String]? {
        if let strings = try? decodeIfPresent([String].self, forKey: key) {
            return strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let values = try? decodeIfPresent([ViewPacketJSONValue].self, forKey: key) {
            let strings = values
                .map(\.description)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return strings.isEmpty ? nil : strings
        }
        return nil
    }

    func decodeFlexibleText(for key: Key, _ cadenceScope: Void = ()) throws -> String? {
        if let string = try? decodeTrimmedString(for: key) {
            return string
        }
        guard let value = try? decodeIfPresent(ViewPacketJSONValue.self, forKey: key) else {
            return nil
        }
        let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func decodeFlexibleStringArray(for key: Key, _ cadenceScope: Void = ()) throws -> [String]? {
        if let strings = try? decodeIfPresent([String].self, forKey: key) {
            let trimmed = strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let values = try? decodeIfPresent([ViewPacketJSONValue].self, forKey: key) else {
            return nil
        }
        let strings = values.compactMap { value -> String? in
            if let object = value.objectValue {
                let text = object["title"]?.description
                    ?? object["name"]?.description
                    ?? object["label"]?.description
                    ?? object["id"]?.description
                let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return strings.isEmpty ? nil : strings
    }
}

#if DEBUG
/// Deterministic showcase for the active work row. `CadenceBlockRow` is private
/// to this file, so its showcase entry lives here and is exposed to `ShowcaseView`.
/// The fixture reproduces the exact state `CadenceWorkModeChips` gates on —
/// a current, not-yet-started work block (`normalizedTypeText == "work"`,
/// rowVariant `.current`, `actionState == .available`) — by running a fixed
/// envelope through the real `CadenceDayPresentation` builder, so visual review
/// exercises the same path production does without a live cadence day.
struct CadenceShowcaseActiveWorkRow: View {
    private static let referenceNow: Date =
        ISO8601DateFormatter().date(from: "2026-07-06T09:15:00Z") ?? Date()

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let presentation: CadenceBlockPresentation? = {
        let json = """
        {
          "date": "2026-07-06",
          "bandish": [
            {
              "id": "work-now",
              "title": "Core draft",
              "type": "work",
              "mode": "core",
              "ring": "core",
              "brainState": "convergent",
              "why": "set the edge before calls",
              "startAt": "09:00",
              "endAt": "10:00"
            }
          ]
        }
        """
        guard let day = try? JSONDecoder().decode(CadenceDayEnvelope.self, from: Data(json.utf8)) else {
            return nil
        }
        return CadenceDayPresentation(day: day, now: referenceNow, calendar: utcCalendar)
            .blocks.first { $0.isNow }
    }()

    var body: some View {
        if let presentation = Self.presentation {
            CadenceBlockRow(
                presentation: presentation,
                onStart: {},
                onComplete: {},
                onResume: {},
                onChecklistToggle: { _ in },
                onMealLog: { _ in .success("") },
                onMealPhoto: { _, _ in .success("") },
                isExpanded: false,
                onToggleExpansion: {}
            )
        } else {
            KMonoCaption("showcase fixture failed to build", variant: .inlineError, state: .error)
        }
    }
}
#endif
