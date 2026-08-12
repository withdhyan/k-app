import Foundation
import SwiftUI

// MARK: - Wire projections

private struct BioResearchKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

private enum BioResearchDecodeError: Error {
    case missing(String)
}

private extension KeyedDecodingContainer where Key == BioResearchKey {
    func researchString(_ names: [String]) -> String? {
        for name in names {
            let key = BioResearchKey(name)
            if let value = try? decode(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    func researchDouble(_ names: [String]) -> Double? {
        for name in names {
            let key = BioResearchKey(name)
            if let value = try? decode(Double.self, forKey: key),
               value.isFinite {
                return value
            }
            if let value = try? decode(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = researchString([name]),
               let number = Double(value),
               number.isFinite {
                return number
            }
        }
        return nil
    }

    func researchInt(_ names: [String]) -> Int? {
        guard let value = researchDouble(names) else { return nil }
        return Int(value.rounded(.towardZero))
    }

    func researchArray<Element: Decodable>(_ names: [String], as type: [Element].Type = [Element].self) -> [Element] {
        for name in names {
            let key = BioResearchKey(name)
            if let value = try? decode(type, forKey: key) {
                return value
            }
        }
        return []
    }

    func researchNested<Element: Decodable>(_ names: [String], as type: Element.Type) -> Element? {
        for name in names {
            let key = BioResearchKey(name)
            if let value = try? decode(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}

private enum BioResearchCopy {
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    static func fallbackID(_ value: String?, prefix: String) -> String {
        let source = normalized(value)?.lowercased() ?? prefix
        let pieces = source.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let result = String(pieces)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return result.isEmpty ? prefix : "\(prefix)-\(result)"
    }

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        let formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        return formatted
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

struct BioBiomarkerRange: Decodable, Equatable, Sendable {
    let lower: Double
    let upper: Double
    let optimalLower: Double?
    let optimalUpper: Double?
    let optimalLabel: String

    init(
        lower: Double,
        upper: Double,
        optimalLower: Double? = nil,
        optimalUpper: Double? = nil,
        optimalLabel: String? = nil
    ) {
        self.lower = lower
        self.upper = upper
        self.optimalLower = optimalLower
        self.optimalUpper = optimalUpper
        self.optimalLabel = optimalLabel ?? "optimal \(BioResearchCopy.number(optimalLower ?? lower))–\(BioResearchCopy.number(optimalUpper ?? upper))"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let lower = container.researchDouble(["lower", "low", "min"]),
              let upper = container.researchDouble(["upper", "high", "max"])
        else {
            throw BioResearchDecodeError.missing("biomarker range")
        }
        let optimal = container.researchNested(["optimal", "target"], as: BioBiomarkerOptimalBounds.self)
        self.init(
            lower: lower,
            upper: upper,
            optimalLower: container.researchDouble(["optimalLower", "optimalLow", "targetLower"]) ?? optimal?.lower,
            optimalUpper: container.researchDouble(["optimalUpper", "optimalHigh", "targetUpper"]) ?? optimal?.upper,
            optimalLabel: container.researchString(["optimalLabel", "label"])
        )
    }
}

private struct BioBiomarkerOptimalBounds: Decodable {
    let lower: Double?
    let upper: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        lower = container.researchDouble(["lower", "low", "min"])
        upper = container.researchDouble(["upper", "high", "max"])
    }
}

struct BioBiomarkerHistoryPoint: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let value: Double

    init(id: String? = nil, label: String, value: Double) {
        self.label = label
        self.value = value
        self.id = id ?? BioResearchCopy.fallbackID(label, prefix: "history")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let label = container.researchString(["label", "month", "date", "at"]),
              let value = container.researchDouble(["value", "current"])
        else {
            throw BioResearchDecodeError.missing("biomarker history point")
        }
        self.init(
            id: container.researchString(["id"]),
            label: label,
            value: value
        )
    }
}

enum BioSourceDocumentGlyph: String, Equatable, Sendable {
    case document
    case scan
    case circle

    var systemName: String {
        switch self {
        case .document:
            return "doc.text"
        case .scan:
            return "viewfinder"
        case .circle:
            return "circle"
        }
    }
}

struct BioBiomarkerDocument: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let text: String
    let glyph: BioSourceDocumentGlyph

    init(id: String? = nil, text: String, glyph: BioSourceDocumentGlyph = .document) {
        self.text = text
        self.glyph = glyph
        self.id = id ?? BioResearchCopy.fallbackID(text, prefix: "source")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let text = container.researchString(["text", "title", "source", "label"]) else {
            throw BioResearchDecodeError.missing("source document")
        }
        let glyph = BioSourceDocumentGlyph(rawValue: container.researchString(["glyph", "kind"]) ?? "document") ?? .document
        self.init(id: container.researchString(["id"]), text: text, glyph: glyph)
    }
}

struct BioBiomarkerRecord: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let value: Double
    let unit: String
    let subtitle: String?
    let range: BioBiomarkerRange?
    let history: [BioBiomarkerHistoryPoint]
    let note: String?
    let documents: [BioBiomarkerDocument]
    // The mock supplies the visual tick placement independently of the reference
    // range. Wire records use the mathematically derived placement when absent.
    let bandPositionOverride: Double?

    init(
        id: String,
        name: String,
        value: Double,
        unit: String,
        subtitle: String? = nil,
        range: BioBiomarkerRange? = nil,
        history: [BioBiomarkerHistoryPoint] = [],
        note: String? = nil,
        documents: [BioBiomarkerDocument] = [],
        bandPositionOverride: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.subtitle = subtitle
        self.range = range
        self.history = history
        self.note = note
        self.documents = documents
        self.bandPositionOverride = bandPositionOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title", "marker"]),
              let value = container.researchDouble(["value", "current"]) else {
            throw BioResearchDecodeError.missing("biomarker")
        }
        self.init(
            id: container.researchString(["id"]) ?? BioResearchCopy.fallbackID(name, prefix: "biomarker"),
            name: name,
            value: value,
            unit: container.researchString(["unit", "units"]) ?? "",
            subtitle: container.researchString(["subtitle", "sub"]),
            range: container.researchNested(["range", "referenceRange"], as: BioBiomarkerRange.self),
            history: container.researchArray(["history", "trend"], as: [BioBiomarkerHistoryPoint].self),
            note: container.researchString(["note", "dnote"]),
            documents: container.researchArray(["documents", "docs", "sources"], as: [BioBiomarkerDocument].self),
            bandPositionOverride: container.researchDouble(["bandPosition", "you"])
        )
    }

    var currentText: String { BioResearchCopy.number(value) }

    var currentWithUnitText: String {
        unit.isEmpty ? currentText : "\(currentText) \(unit)"
    }

    var detailSubtitle: String {
        subtitle ?? currentWithUnitText
    }
}

struct BioNextTestRecord: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    let date: String

    init(id: String? = nil, name: String, status: String, date: String) {
        self.name = name
        self.status = status
        self.date = date
        self.id = id ?? BioResearchCopy.fallbackID(name, prefix: "test")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title", "test"]) else {
            throw BioResearchDecodeError.missing("next test")
        }
        self.init(
            id: container.researchString(["id"]),
            name: name,
            status: container.researchString(["status", "state"]) ?? "due",
            date: container.researchString(["date", "dueDate", "when"]) ?? "—"
        )
    }
}

struct BioReportRecord: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let date: String
    let glyph: BioSourceDocumentGlyph

    init(id: String? = nil, name: String, date: String, glyph: BioSourceDocumentGlyph = .document) {
        self.name = name
        self.date = date
        self.glyph = glyph
        self.id = id ?? BioResearchCopy.fallbackID(name, prefix: "report")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title", "report"]) else {
            throw BioResearchDecodeError.missing("report")
        }
        let glyph = BioSourceDocumentGlyph(rawValue: container.researchString(["glyph", "kind"]) ?? "document") ?? .document
        self.init(
            id: container.researchString(["id"]),
            name: name,
            date: container.researchString(["date", "at"]) ?? "—",
            glyph: glyph
        )
    }
}

enum BioProtocolCategorySignal: String, Equatable, Sendable {
    case ok
    case warn
    case dim
    case unknown

    var color: Color {
        switch self {
        case .ok:
            return KStyle.liveSignal
        case .warn:
            return KStyle.signalWarning
        case .dim, .unknown:
            return KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity)
        }
    }
}

struct BioProtocolCategory: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let count: Int
    let signal: BioProtocolCategorySignal

    init(id: String? = nil, name: String, count: Int, signal: BioProtocolCategorySignal = .unknown) {
        self.name = name
        self.count = count
        self.signal = signal
        self.id = id ?? BioResearchCopy.fallbackID(name, prefix: "category")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title"]) else {
            throw BioResearchDecodeError.missing("protocol category")
        }
        self.init(
            id: container.researchString(["id"]),
            name: name,
            count: container.researchInt(["count", "total", "markers"]) ?? 0,
            signal: BioProtocolCategorySignal(rawValue: container.researchString(["signal", "status"]) ?? "unknown") ?? .unknown
        )
    }
}

struct BioTestingProtocolProjection: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let tested: Int?
    let total: Int?
    let coveragePercent: Double
    let coverageLine: String
    let categories: [BioProtocolCategory]
    let dueTests: [String]
    let note: String

    init(
        id: String,
        name: String,
        subtitle: String,
        tested: Int? = nil,
        total: Int? = nil,
        coveragePercent: Double,
        coverageLine: String,
        categories: [BioProtocolCategory],
        dueTests: [String],
        note: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.tested = tested
        self.total = total
        self.coveragePercent = min(max(coveragePercent, 0), 100)
        self.coverageLine = coverageLine
        self.categories = categories
        self.dueTests = dueTests
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title"]) else {
            throw BioResearchDecodeError.missing("testing protocol")
        }
        let rawCoverage = container.researchDouble(["coveragePercent", "coverage", "cov"]) ?? 0
        let coverage = rawCoverage <= 1 ? rawCoverage * 100 : rawCoverage
        self.init(
            id: container.researchString(["id"]) ?? BioResearchCopy.fallbackID(name, prefix: "protocol"),
            name: name,
            subtitle: container.researchString(["subtitle", "sub"]) ?? "",
            tested: container.researchInt(["tested", "testedCount"]),
            total: container.researchInt(["total", "totalCount"]),
            coveragePercent: coverage,
            coverageLine: container.researchString(["coverageLine", "coverageLabel", "covl"]) ?? "",
            categories: container.researchArray(["categories", "cats"], as: [BioProtocolCategory].self),
            dueTests: container.researchArray(["dueTests", "book", "booking"], as: [String].self),
            note: container.researchString(["note", "dnote"]) ?? ""
        )
    }

    var coverageFraction: Double {
        BioCoverageRingMath.fraction(tested: nil, total: nil, coveragePercent: coveragePercent)
    }

    var coverageText: String {
        "\(BioResearchCopy.number(coveragePercent))%"
    }

    var railValue: String {
        if let tested, let total {
            return "\(tested)/\(total)"
        }
        return id == "investigation" ? "gut · tier 2" : coverageText
    }
}

enum BioMeditationGroup: String, CaseIterable, Equatable, Sendable {
    case active
    case foundation
    case depth

    var title: String { rawValue.uppercased() }
}

enum BioMeditationEvidence: String, Equatable, Sendable {
    case strong
    case mod
    case trad
    case unknown

    var color: Color {
        switch self {
        case .strong:
            return KStyle.liveSignal
        case .mod:
            return KStyle.signalWarning
        case .trad, .unknown:
            return KStyle.nearBlack
        }
    }

    var fillOpacity: Double {
        switch self {
        case .strong:
            return KStyle.bioProtocolEvidenceStrongOpacity
        case .mod:
            return KStyle.bioProtocolEvidenceModerateOpacity
        case .trad, .unknown:
            return KStyle.bioProtocolEvidenceTradOpacity
        }
    }
}

struct BioMeditationIndication: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let evidence: BioMeditationEvidence
    let outcome: String

    init(id: String? = nil, name: String, evidence: BioMeditationEvidence, outcome: String) {
        self.name = name
        self.evidence = evidence
        self.outcome = outcome
        self.id = id ?? BioResearchCopy.fallbackID(name, prefix: "indication")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "condition", "indication"]) else {
            throw BioResearchDecodeError.missing("meditation indication")
        }
        self.init(
            id: container.researchString(["id"]),
            name: name,
            evidence: BioMeditationEvidence(rawValue: container.researchString(["evidence", "strength", "grade"]) ?? "unknown") ?? .unknown,
            outcome: container.researchString(["outcome", "result", "expected"]) ?? ""
        )
    }
}

struct BioMeditationSafety: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let text: String
    let absolute: Bool
    let frequency: String?

    init(id: String? = nil, text: String, absolute: Bool = false, frequency: String? = nil) {
        self.text = text
        self.absolute = absolute
        self.frequency = frequency
        self.id = id ?? BioResearchCopy.fallbackID(text, prefix: "safety")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let text = container.researchString(["text", "event", "name"]) else {
            throw BioResearchDecodeError.missing("meditation safety")
        }
        self.init(
            id: container.researchString(["id"]),
            text: text,
            absolute: (try? container.decode(Bool.self, forKey: BioResearchKey("absolute"))) ?? false,
            frequency: container.researchString(["frequency", "rate"])
        )
    }
}

struct BioMeditationProtocolProjection: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let group: BioMeditationGroup
    let railStatus: String
    let subtitle: String
    let evidenceLabel: String
    let phases: [String]
    let currentPhaseIndex: Int
    let focus: String
    let methodNow: [String]
    let indications: [BioMeditationIndication]
    let safety: [BioMeditationSafety]
    let note: String

    init(
        id: String,
        name: String,
        group: BioMeditationGroup,
        railStatus: String,
        subtitle: String,
        evidenceLabel: String,
        phases: [String],
        currentPhaseIndex: Int,
        focus: String,
        methodNow: [String],
        indications: [BioMeditationIndication],
        safety: [BioMeditationSafety],
        note: String
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.railStatus = railStatus
        self.subtitle = subtitle
        self.evidenceLabel = evidenceLabel
        self.phases = phases
        self.currentPhaseIndex = min(max(currentPhaseIndex, 0), max(phases.count - 1, 0))
        self.focus = focus
        self.methodNow = methodNow
        self.indications = indications
        self.safety = safety
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BioResearchKey.self)
        guard let name = container.researchString(["name", "title"]) else {
            throw BioResearchDecodeError.missing("meditation protocol")
        }
        self.init(
            id: container.researchString(["id"]) ?? BioResearchCopy.fallbackID(name, prefix: "meditation"),
            name: name,
            group: BioMeditationGroup(rawValue: container.researchString(["group", "section"]) ?? "foundation") ?? .foundation,
            railStatus: container.researchString(["railStatus", "progress", "status"]) ?? "",
            subtitle: container.researchString(["subtitle", "sub", "lineage"]) ?? "",
            evidenceLabel: container.researchString(["evidenceLabel", "evidence", "badge"]) ?? "",
            phases: container.researchArray(["phases", "phaseNames"], as: [String].self),
            currentPhaseIndex: container.researchInt(["currentPhaseIndex", "phase"]) ?? 0,
            focus: container.researchString(["focus", "now"]) ?? "",
            methodNow: container.researchArray(["methodNow", "method"], as: [String].self),
            indications: container.researchArray(["indications", "helps"], as: [BioMeditationIndication].self),
            safety: container.researchArray(["safety", "contraindications", "adverseEvents"], as: [BioMeditationSafety].self),
            note: container.researchString(["note", "dnote"]) ?? ""
        )
    }
}

// MARK: - Pure presentation math

enum BioRangeBandMath {
    static func position(value: Double, lower: Double, upper: Double) -> Double {
        guard value.isFinite, lower.isFinite, upper.isFinite, upper > lower else { return 0.5 }
        return min(max((value - lower) / (upper - lower), 0), 1)
    }
}

enum BioCoverageRingMath {
    static func fraction(tested: Int?, total: Int?, coveragePercent: Double? = nil) -> Double {
        if let tested, let total, total > 0 {
            return min(max(Double(tested) / Double(total), 0), 1)
        }
        guard let coveragePercent, coveragePercent.isFinite else { return 0 }
        let value = coveragePercent > 1 ? coveragePercent / 100 : coveragePercent
        return min(max(value, 0), 1)
    }
}

enum BioSparklineMath {
    static func reduce(_ values: [Double], maximumPoints: Int) -> [Double] {
        guard maximumPoints > 0, values.count > maximumPoints else { return values }
        guard maximumPoints > 1 else { return [values[0]] }
        let lastIndex = values.count - 1
        return (0..<maximumPoints).map { slot in
            let ratio = Double(slot) / Double(maximumPoints - 1)
            let index = Int((ratio * Double(lastIndex)).rounded())
            return values[min(max(index, 0), lastIndex)]
        }
    }

    static func points(_ values: [Double], width: CGFloat, height: CGFloat, maximumPoints: Int = 8) -> [CGPoint] {
        let values = reduce(values, maximumPoints: maximumPoints)
        guard values.count > 1, width > 0, height > 0 else {
            return values.isEmpty ? [] : [CGPoint(x: 0, y: height / 2)]
        }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? minValue
        let span = max(maxValue - minValue, 0.0001)
        return values.enumerated().map { index, value in
            let x = width * CGFloat(index) / CGFloat(values.count - 1)
            let y = height - CGFloat((value - minValue) / span) * height
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Biomarkers surface

struct BioBiomarkerRailDetail: View {
    let records: [BioBiomarkerRecord]
    let nextTests: [BioNextTestRecord]
    let reports: [BioReportRecord]
    @Binding var selectedID: String?

    var body: some View {
        BioRailDetail(
            hasDetail: selectedRecord != nil,
            railWidth: KStyle.bioResearchRailWidth,
            railMaxFraction: KStyle.bioResearchRailMaxFraction,
            detailOverlap: KStyle.bioResearchDetailOverlap,
            detailTopInset: KStyle.bioResearchDetailTopInset,
            detailPadding: KStyle.bioResearchDetailPadding,
            detailContentLeading: KStyle.bioResearchDetailContentLeading
        ) {
            BioBiomarkerRail(
                records: records,
                nextTests: nextTests,
                reports: reports,
                selectedID: $selectedID
            )
        } detail: {
            if let selectedRecord {
                BioBiomarkerDetail(record: selectedRecord)
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: records) { _, _ in selectFirstIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private var selectedRecord: BioBiomarkerRecord? {
        records.first { $0.id == selectedID } ?? records.first
    }

    private func selectFirstIfNeeded() {
        guard selectedID == nil || !records.contains(where: { $0.id == selectedID }) else { return }
        selectedID = records.first(where: { $0.id == "ferritin" })?.id ?? records.first?.id
    }
}

private struct BioBiomarkerRail: View {
    let records: [BioBiomarkerRecord]
    let nextTests: [BioNextTestRecord]
    let reports: [BioReportRecord]
    @Binding var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioResearchSectionSpacing) {
            BioResearchRailGroup(title: "markers") {
                ForEach(records) { record in
                    Button {
                        withAnimation(KStyle.selectorTextMotion(reduceMotion)) { selectedID = record.id }
                    } label: {
                        HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                                Text(record.name)
                                    .kFont(.content)
                                    .foregroundStyle(railInk(for: record))
                                    .lineLimit(1)
                                HStack(spacing: KStyle.smallSpacing) {
                                    Text(record.currentWithUnitText)
                                        .kFont(.monoCaptionDigit)
                                        .foregroundStyle(railInk(for: record).opacity(KStyle.bioRailSecondaryOpacity))
                                    BioSparkline(values: record.history.map(\.value))
                                }
                            }
                            Spacer(minLength: KStyle.smallSpacing)
                        }
                        .padding(.vertical, KStyle.bioResearchRailRowVerticalPadding)
                        .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if selectedID == record.id {
                                RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                                    .fill(KStyle.emphasisInk)
                            }
                        }
                        .padding(.trailing, selectedID == record.id ? -KStyle.bioResearchRailSelectionOverhang : KStyle.bioResearchInactiveSelectionOverhang)
                        .shadow(
                            color: KStyle.nearBlack.opacity(selectedID == record.id ? KStyle.bioResearchActiveShadowOpacity : KStyle.bioResearchInactiveShadowOpacity),
                            radius: KStyle.bioResearchActiveShadowRadius,
                            y: KStyle.bioResearchActiveShadowY
                        )
                    }
                    .buttonStyle(.plain)
                    // Only the selected origin crosses the detail seam. Keep the
                    // ordering on the tappable row so it survives label composition.
                    .zIndex(selectedID == record.id
                        ? KStyle.bioRailSelectedItemZIndex
                        : KStyle.bioRailUnselectedItemZIndex)
                    .accessibilityIdentifier(BioAccessibility.biomarker(record.id))
                    .accessibilityLabel(record.name)
                    .accessibilityValue(record.currentWithUnitText)
                }
            }

            BioResearchRailGroup(title: "next tests") {
                ForEach(nextTests) { test in
                    HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                        Text(test.name)
                            .kFont(.content)
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity))
                        Spacer(minLength: KStyle.smallSpacing)
                        Text(test.status)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                        Text(test.date)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                    }
                    .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
                    .accessibilityIdentifier("bio-next-test-\(test.id)")
                }
            }

            BioResearchRailGroup(title: "reports & scans") {
                ForEach(reports) { report in
                    HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                        Image(systemName: report.glyph.systemName)
                            .font(KStyle.font(.monoCaption))
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                            .frame(width: KStyle.bioSourceDocumentGlyphSize, height: KStyle.bioSourceDocumentGlyphSize)
                        Text(report.name)
                            .kFont(.content)
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity))
                        Spacer(minLength: KStyle.smallSpacing)
                        Text(report.date)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                    }
                    .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
                    .accessibilityIdentifier("bio-report-\(report.id)")
                }
            }
        }
        .padding(.vertical, KStyle.bioResearchRailVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: KStyle.bioResearchRailCornerRadius, style: .continuous)
                .fill(KStyle.emphasisInk.opacity(KStyle.bioResearchRailSurfaceOpacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bio-biomarker-rail")
    }

    private func railInk(for record: BioBiomarkerRecord) -> Color {
        selectedID == record.id ? KStyle.nearBlack : KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity)
    }
}

private struct BioResearchRailGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioResearchSectionSpacing) {
            Text(title.uppercased())
                .kFont(.monoCaption)
                .tracking(KStyle.tracking(for: .monoCaption))
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
                .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
            content()
        }
    }
}

private struct BioSparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            let points = BioSparklineMath.points(
                values,
                width: size.width,
                height: size.height,
                maximumPoints: 8
            )
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity)),
                lineWidth: KStyle.bioSparklineLineWidth
            )
        }
        .frame(width: KStyle.bioSparklineWidth, height: KStyle.bioSparklineHeight)
        .accessibilityHidden(true)
    }
}

private struct BioBiomarkerDetail: View {
    let record: BioBiomarkerRecord

    var body: some View {
        ZStack(alignment: .topLeading) {
            // SwiftUI drops identifiers stamped on this grouped detail root under XCUI.
            // Keep the audit anchor as a real in-tree element without changing layout.
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("biomarker detail")
                .accessibilityIdentifier(BioAccessibility.biomarkerDetail)

            VStack(alignment: .leading, spacing: 0) {
                Text(record.name)
                    .kFont(.blockActiveTitle)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                Text(record.detailSubtitle)
                    .kFont(.monoCaption)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .padding(.top, KStyle.bioResearchDetailTitleSpacing)
                    .padding(.bottom, KStyle.bioResearchDetailSubtitleBottomSpacing)

                if let range = record.range {
                    BioRangeBand(record: record, range: range)
                }

                if !record.history.isEmpty {
                    BioBiomarkerHistory(record: record)
                        .padding(.top, KStyle.bioResearchDetailHistoryTopSpacing)
                }

                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .kFont(.content)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                        .lineSpacing(KStyle.microSpacing)
                        .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth, alignment: .leading)
                        .padding(.top, KStyle.bioResearchDetailNoteTopSpacing)
                }

                if !record.documents.isEmpty {
                    KActRow(
                        actions: record.documents.map { document in
                            KActItem(
                                id: document.id,
                                label: document.text,
                                isEnabled: false,
                                accessibilityIdentifier: "bio-biomarker-source-\(document.id)"
                            )
                        },
                        variant: .cadence,
                        onSelect: { _ in }
                    )
                    .environment(\.kInkOnPaper, true)
                    .padding(.top, KStyle.bioResearchDetailNoteTopSpacing)
                    .accessibilityIdentifier(BioAccessibility.biomarkerSources)
                }
            }
        }
        .frame(minHeight: KStyle.bioResearchDetailMinimumHeight, alignment: .topLeading)
        .environment(\.kInkOnPaper, true)
        .accessibilityElement(children: .contain)
    }
}

private struct BioRangeBand: View {
    let record: BioBiomarkerRecord
    let range: BioBiomarkerRange

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioRangeBandVerticalSpacing) {
            GeometryReader { proxy in
                let position = record.bandPositionOverride
                    ?? BioRangeBandMath.position(value: record.value, lower: range.lower, upper: range.upper)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: KStyle.bioRangeBandCornerRadius, style: .continuous)
                        .fill(LinearGradient(
                            colors: KStyle.bioProtocolRangeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(height: KStyle.bioRangeBandHeight)
                    Rectangle()
                        .fill(KStyle.nearBlack)
                        .frame(width: KStyle.bioRangeTickWidth, height: KStyle.bioRangeBandHeight + KStyle.bioRangeTickExtension * 2)
                        .offset(x: proxy.size.width * position - KStyle.bioRangeTickWidth / 2, y: -KStyle.bioRangeTickExtension)
                    Text(record.currentText)
                        .kFont(.monoCaptionDigit)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                        .offset(x: min(max(proxy.size.width * position - KStyle.bioRangeValueOffset / 2, 0), max(proxy.size.width - KStyle.bioRangeValueOffset, 0)), y: -KStyle.bioRangeValueOffset)
                }
            }
            .frame(height: KStyle.bioRangeBandHeight + KStyle.bioRangeTickExtension * 2)

            HStack {
                Text(BioResearchCopy.number(range.lower))
                Spacer()
                Text(range.optimalLabel)
                Spacer()
                Text(BioResearchCopy.number(range.upper))
            }
            .kFont(.monoCaption)
            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(BioAccessibility.biomarkerRangeBand)
        .accessibilityLabel("range band")
        .accessibilityValue("\(record.currentWithUnitText), \(range.optimalLabel)")
    }
}

private struct BioBiomarkerHistory: View {
    let record: BioBiomarkerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text("9 MONTHS")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
            GeometryReader { proxy in
                let points = BioSparklineMath.points(
                    record.history.map(\.value),
                    width: proxy.size.width,
                    height: proxy.size.height - KStyle.bioHistoryBottomLabelOffset,
                    maximumPoints: 9
                )
                ZStack(alignment: .topLeading) {
                    if let first = points.first, let last = points.last {
                        Path { path in
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                            path.addLine(to: CGPoint(x: last.x, y: proxy.size.height - KStyle.bioHistoryBottomLabelOffset))
                            path.addLine(to: CGPoint(x: first.x, y: proxy.size.height - KStyle.bioHistoryBottomLabelOffset))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(
                            colors: [
                                KStyle.nearBlack.opacity(KStyle.bioHistoryAreaTopOpacity),
                                KStyle.nearBlack.opacity(KStyle.bioHistoryAreaBottomOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))

                        Path { path in
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                        }
                        .stroke(
                            KStyle.nearBlack.opacity(KStyle.bioHistoryLineOpacity),
                            lineWidth: KStyle.bioHistoryLineWidth
                        )

                        Circle()
                            .fill(KStyle.nearBlack)
                            .frame(width: KStyle.bioHistoryEndDotSize, height: KStyle.bioHistoryEndDotSize)
                            .position(last)
                        Text(record.currentText)
                            .kFont(.monoCaptionDigit)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                            .position(x: min(last.x + KStyle.bioHistoryEndDotSize * 2, proxy.size.width - KStyle.bioHistoryEndDotSize * 2), y: last.y)
                    }

                    if let firstLabel = record.history.first?.label,
                       let lastLabel = record.history.last?.label {
                        Text(firstLabel)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioHistoryLabelOpacity))
                            .position(x: KStyle.bioHistoryEndDotSize, y: proxy.size.height - KStyle.bioHistoryEndDotSize)
                        Text(lastLabel)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioHistoryLabelOpacity))
                            .position(x: proxy.size.width - KStyle.bioHistoryEndDotSize * 2, y: proxy.size.height - KStyle.bioHistoryEndDotSize)
                    }
                }
            }
            .frame(height: KStyle.bioHistoryHeight)
            .frame(maxWidth: KStyle.bioHistoryMaximumWidth)
        }
        .frame(maxWidth: KStyle.bioHistoryMaximumWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(BioAccessibility.biomarkerHistory)
        .accessibilityLabel("9 months history")
        .accessibilityValue(record.history.map { "\($0.label) \(BioResearchCopy.number($0.value))" }.joined(separator: " · "))
    }
}

// MARK: - Protocols surface

private enum BioProtocolDomain: String, CaseIterable, Hashable {
    case biology
    case meditation
}

struct BioProtocolsSection: View {
    let testing: [BioTestingProtocolProjection]
    let meditation: [BioMeditationProtocolProjection]
    @Binding var selectedTestingID: String?
    @State private var domain: BioProtocolDomain = .biology
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: KStyle.bioProtocolDomainBottomSpacing) {
            BioProtocolDomainSelector(domain: $domain)
            if domain == .biology, !testing.isEmpty {
                BioTestingRailDetail(protocols: testing, selectedID: $selectedTestingID)
            } else if domain == .meditation, !meditation.isEmpty {
                BioMeditationRailDetail(protocols: meditation)
            } else {
                Text("no protocol reference loaded")
                    .kFont(.content)
                    .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
            }
        }
        .kAnimated(value: domain)
        .animation(KStyle.selectorTextMotion(reduceMotion), value: domain)
        .accessibilityElement(children: .contain)
    }
}

private struct BioProtocolDomainSelector: View {
    @Binding var domain: BioProtocolDomain

    var body: some View {
        KSelectorStrip(
            selection: $domain,
            items: BioProtocolDomain.allCases.map { value in
                KSelectorItem(
                    id: value,
                    title: value.rawValue,
                    accessibilityLabel: "\(value.rawValue) protocol domain",
                    accessibilityIdentifier: "bio-protocol-domain-\(value.rawValue)"
                )
            },
            accessibilityIdentifier: BioAccessibility.protocolDomainSelector
        )
    }
}

private struct BioTestingRailDetail: View {
    let protocols: [BioTestingProtocolProjection]
    @Binding var selectedID: String?

    var body: some View {
        BioRailDetail(
            hasDetail: selectedProtocol != nil,
            railWidth: KStyle.bioResearchRailWidth,
            railMaxFraction: KStyle.bioResearchRailMaxFraction,
            detailOverlap: KStyle.bioResearchDetailOverlap,
            detailTopInset: KStyle.bioResearchDetailTopInset,
            detailPadding: KStyle.bioResearchDetailPadding,
            detailContentLeading: KStyle.bioResearchDetailContentLeading
        ) {
            BioTestingRail(protocols: protocols, selectedID: $selectedID)
        } detail: {
            if let selectedProtocol {
                BioTestingDetail(protocol: selectedProtocol)
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: protocols) { _, _ in selectFirstIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private var selectedProtocol: BioTestingProtocolProjection? {
        protocols.first { $0.id == selectedID } ?? protocols.first
    }

    private func selectFirstIfNeeded() {
        guard selectedID == nil || !protocols.contains(where: { $0.id == selectedID }) else { return }
        selectedID = protocols.first?.id
    }
}

private struct BioTestingRail: View {
    let protocols: [BioTestingProtocolProjection]
    @Binding var selectedID: String?

    var body: some View {
        BioResearchRailGroup(title: "testing protocols") {
            ForEach(protocols) { protocolProjection in
                Button {
                    selectedID = protocolProjection.id
                } label: {
                    HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                        Text(protocolProjection.name)
                            .kFont(.content)
                            .foregroundStyle(selectedID == protocolProjection.id ? KStyle.nearBlack : KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity))
                            .lineLimit(1)
                        Spacer(minLength: KStyle.smallSpacing)
                        Text(protocolProjection.railValue)
                            .kFont(.monoCaption)
                            .foregroundStyle(selectedID == protocolProjection.id ? KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity) : KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                    }
                    .padding(.vertical, KStyle.bioResearchRailRowVerticalPadding)
                    .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if selectedID == protocolProjection.id {
                            RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                                .fill(KStyle.emphasisInk)
                        }
                    }
                    .padding(.trailing, selectedID == protocolProjection.id ? -KStyle.bioResearchRailSelectionOverhang : KStyle.bioResearchInactiveSelectionOverhang)
                    .shadow(
                        color: KStyle.nearBlack.opacity(selectedID == protocolProjection.id ? KStyle.bioResearchActiveShadowOpacity : KStyle.bioResearchInactiveShadowOpacity),
                        radius: KStyle.bioResearchActiveShadowRadius,
                        y: KStyle.bioResearchActiveShadowY
                    )
                }
                .buttonStyle(.plain)
                .zIndex(selectedID == protocolProjection.id
                    ? KStyle.bioRailSelectedItemZIndex
                    : KStyle.bioRailUnselectedItemZIndex)
                .accessibilityIdentifier(BioAccessibility.testingProtocol(protocolProjection.id))
                .accessibilityLabel(protocolProjection.name)
                .accessibilityValue(protocolProjection.railValue)
            }
        }
        .padding(.vertical, KStyle.bioResearchRailVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: KStyle.bioResearchRailCornerRadius, style: .continuous)
                .fill(KStyle.emphasisInk.opacity(KStyle.bioResearchRailSurfaceOpacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bio-testing-protocol-rail")
    }
}

private struct BioTestingDetail: View {
    let `protocol`: BioTestingProtocolProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: KStyle.bioResearchSectionSpacing) {
                VStack(alignment: .leading, spacing: KStyle.bioResearchDetailTitleSpacing) {
                    Text(`protocol`.name)
                        .kFont(.blockActiveTitle)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    Text(`protocol`.subtitle)
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                }
                Spacer(minLength: KStyle.rowSpacing)
                BioCoverageRing(fraction: `protocol`.coverageFraction, text: `protocol`.coverageText)
            }
            Text(`protocol`.coverageLine)
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: KStyle.bioProtocolCategoryRowSpacing
            ) {
                ForEach(`protocol`.categories) { category in
                    HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                        Circle()
                            .fill(category.signal.color)
                            .frame(width: KStyle.bioProtocolCategoryDotSize, height: KStyle.bioProtocolCategoryDotSize)
                        Text(category.name)
                            .kFont(.content)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                            .lineLimit(1)
                        Spacer(minLength: KStyle.smallSpacing)
                        Text("\(category.count)")
                            .kFont(.monoCaptionDigit)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .gridColumnAlignment(.leading)
            .padding(.top, KStyle.bioResearchProtocolCategoriesTopSpacing)

            Text(`protocol`.note)
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                .lineSpacing(KStyle.microSpacing)
                .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth, alignment: .leading)
                .padding(.top, KStyle.bioResearchDetailNoteTopSpacing)
        }
        .frame(minHeight: KStyle.bioResearchDetailMinimumHeight, alignment: .topLeading)
        .environment(\.kInkOnPaper, true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(BioAccessibility.protocolDetail)
    }
}

private struct BioCoverageRing: View {
    let fraction: Double
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(KStyle.nearBlack.opacity(KStyle.bioCoverageTrackOpacity), lineWidth: KStyle.bioProtocolCoverageRingLineWidth)
                .frame(width: KStyle.bioProtocolCoverageRingRadius * 2, height: KStyle.bioProtocolCoverageRingRadius * 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(KStyle.nearBlack.opacity(KStyle.bioCoverageFillOpacity), style: StrokeStyle(lineWidth: KStyle.bioProtocolCoverageRingLineWidth, lineCap: .round))
                .rotationEffect(KStyle.bioCoverageRingRotation)
                .frame(width: KStyle.bioProtocolCoverageRingRadius * 2, height: KStyle.bioProtocolCoverageRingRadius * 2)
            Text(text)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
        }
        .frame(width: KStyle.bioProtocolCoverageRingSize, height: KStyle.bioProtocolCoverageRingSize)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(BioAccessibility.protocolCoverageRing)
        .accessibilityLabel("coverage")
        .accessibilityValue(text)
    }
}

private struct BioMeditationRailDetail: View {
    let protocols: [BioMeditationProtocolProjection]
    @State private var selectedID: String?

    var body: some View {
        BioRailDetail(
            hasDetail: selectedProtocol != nil,
            railWidth: KStyle.bioResearchRailWidth,
            railMaxFraction: KStyle.bioResearchRailMaxFraction,
            detailOverlap: KStyle.bioResearchDetailOverlap,
            detailTopInset: KStyle.bioResearchDetailTopInset,
            detailPadding: KStyle.bioResearchDetailPadding,
            detailContentLeading: KStyle.bioResearchDetailContentLeading
        ) {
            BioMeditationRail(protocols: protocols, selectedID: $selectedID)
        } detail: {
            if let selectedProtocol {
                BioMeditationDetail(protocol: selectedProtocol)
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: protocols) { _, _ in selectFirstIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private var selectedProtocol: BioMeditationProtocolProjection? {
        protocols.first { $0.id == selectedID } ?? protocols.first
    }

    private func selectFirstIfNeeded() {
        guard selectedID == nil || !protocols.contains(where: { $0.id == selectedID }) else { return }
        selectedID = protocols.first?.id
    }
}

private struct BioMeditationRail: View {
    let protocols: [BioMeditationProtocolProjection]
    @Binding var selectedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioResearchSectionSpacing) {
            ForEach(BioMeditationGroup.allCases, id: \.self) { group in
                let members = protocols.filter { $0.group == group }
                if !members.isEmpty {
                    BioResearchRailGroup(title: group.rawValue) {
                        ForEach(members) { meditation in
                            Button {
                                selectedID = meditation.id
                            } label: {
                                HStack(spacing: KStyle.bioResearchRailRowSpacing) {
                                    HStack(spacing: KStyle.smallSpacing) {
                                        if meditation.group == .active {
                                            Circle()
                                                .fill(KStyle.liveSignal)
                                                .frame(width: KStyle.bioProtocolSafetyDotSize, height: KStyle.bioProtocolSafetyDotSize)
                                        }
                                        Text(meditation.name)
                                            .kFont(.content)
                                            .foregroundStyle(selectedID == meditation.id ? KStyle.nearBlack : KStyle.emphasisInk.opacity(KStyle.bioRailPrimaryOpacity))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: KStyle.smallSpacing)
                                    Text(meditation.railStatus)
                                        .kFont(.monoCaption)
                                        .foregroundStyle(selectedID == meditation.id ? KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity) : KStyle.emphasisInk.opacity(KStyle.bioRailSecondaryOpacity))
                                        .lineLimit(1)
                                }
                                .padding(.vertical, KStyle.bioResearchRailRowVerticalPadding)
                                .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    if selectedID == meditation.id {
                                        RoundedRectangle(cornerRadius: KStyle.bioChipCornerRadius, style: .continuous)
                                            .fill(KStyle.emphasisInk)
                                    }
                                }
                                .padding(.trailing, selectedID == meditation.id ? -KStyle.bioResearchRailSelectionOverhang : KStyle.bioResearchInactiveSelectionOverhang)
                                .shadow(
                                    color: KStyle.nearBlack.opacity(selectedID == meditation.id ? KStyle.bioResearchActiveShadowOpacity : KStyle.bioResearchInactiveShadowOpacity),
                                    radius: KStyle.bioResearchActiveShadowRadius,
                                    y: KStyle.bioResearchActiveShadowY
                                )
                            }
                            .buttonStyle(.plain)
                            .zIndex(selectedID == meditation.id
                                ? KStyle.bioRailSelectedItemZIndex
                                : KStyle.bioRailUnselectedItemZIndex)
                            .accessibilityIdentifier(BioAccessibility.meditationProtocol(meditation.id))
                            .accessibilityLabel(meditation.name)
                            .accessibilityValue(meditation.railStatus)
                        }
                    }
                }
            }
            Text("15 protocols vendored · attention surface owns the live practice")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.emphasisInk.opacity(KStyle.bioRailTertiaryOpacity))
                .padding(.horizontal, KStyle.bioResearchRailHorizontalPadding)
        }
        .padding(.vertical, KStyle.bioResearchRailVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: KStyle.bioResearchRailCornerRadius, style: .continuous)
                .fill(KStyle.emphasisInk.opacity(KStyle.bioResearchRailSurfaceOpacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bio-meditation-rail")
    }
}

private struct BioMeditationDetail: View {
    let `protocol`: BioMeditationProtocolProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: KStyle.bioResearchSectionSpacing) {
                VStack(alignment: .leading, spacing: KStyle.bioResearchDetailTitleSpacing) {
                    Text(`protocol`.name)
                        .kFont(.blockActiveTitle)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    Text(`protocol`.subtitle)
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                }
                Spacer(minLength: KStyle.rowSpacing)
                Text(`protocol`.evidenceLabel)
                    .kFont(.evidence)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperPrimaryOpacity))
                    .padding(.horizontal, KStyle.bioProtocolEvidenceHorizontalPadding)
                    .padding(.vertical, KStyle.bioProtocolEvidenceVerticalPadding)
                    .overlay {
                        RoundedRectangle(cornerRadius: KStyle.bioProtocolEvidenceCornerRadius, style: .continuous)
                            .stroke(KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity), lineWidth: KStyle.hairlineWidth)
                    }
            }

            BioMeditationPhases(protocol: `protocol`)
                .padding(.top, KStyle.bioResearchMeditationPhasesTopSpacing)

            Text(`protocol`.focus)
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                .lineSpacing(KStyle.microSpacing)
                .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth, alignment: .leading)
                .padding(.top, KStyle.bioResearchMeditationFocusTopSpacing)

            BioProtocolTextRows(title: "method now", rows: `protocol`.methodNow)
                .padding(.top, KStyle.bioResearchMeditationSectionTopSpacing)
            BioMeditationIndications(indications: `protocol`.indications)
                .padding(.top, KStyle.bioResearchMeditationIndicationsTopSpacing)
            BioMeditationSafetyList(safety: `protocol`.safety)
                .padding(.top, KStyle.bioResearchMeditationSafetyTopSpacing)

            Text(`protocol`.note)
                .kFont(.content)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                .lineSpacing(KStyle.microSpacing)
                .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth, alignment: .leading)
                .padding(.top, KStyle.bioResearchDetailNoteTopSpacing)
        }
        .frame(minHeight: KStyle.bioResearchDetailMinimumHeight, alignment: .topLeading)
        .environment(\.kInkOnPaper, true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(BioAccessibility.meditationDetail)
    }
}

private struct BioMeditationPhases: View {
    let `protocol`: BioMeditationProtocolProjection

    var body: some View {
        HStack(spacing: KStyle.bioProtocolPhaseSpacing) {
            ForEach(Array(`protocol`.phases.enumerated()), id: \.offset) { index, phase in
                Text(phase)
                    .kFont(.monoCaption)
                    .foregroundStyle(index == `protocol`.currentPhaseIndex ? KStyle.nearBlack : KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    .padding(.horizontal, KStyle.bioProtocolPhaseHorizontalPadding)
                    .padding(.vertical, KStyle.bioProtocolPhaseVerticalPadding)
                    .frame(minHeight: KStyle.bioProtocolPhaseMinimumHeight)
                    .background {
                        RoundedRectangle(cornerRadius: KStyle.bioProtocolPhaseCornerRadius, style: .continuous)
                            .fill(index == `protocol`.currentPhaseIndex ? KStyle.emphasisInk : KStyle.nearBlack.opacity(KStyle.bioPaperQuaternaryOpacity))
                    }
            }
        }
        .padding(KStyle.bioProtocolPhaseTrackPadding)
        .background {
            RoundedRectangle(cornerRadius: KStyle.bioProtocolPhaseCornerRadius, style: .continuous)
                .fill(KStyle.nearBlack.opacity(KStyle.bioRangeTrackOpacity))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BioProtocolTextRows: View {
    let title: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioProtocolIndicatorRowVerticalPadding) {
            Text(title.uppercased())
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .kFont(.content)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                    .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth, alignment: .leading)
            }
        }
    }
}

private struct BioMeditationIndications: View {
    let indications: [BioMeditationIndication]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioProtocolIndicatorRowVerticalPadding) {
            Text("WHAT IT HELPS")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
            ForEach(indications) { indication in
                HStack(alignment: .firstTextBaseline, spacing: KStyle.bioProtocolIndicatorSpacing) {
                    Text(indication.name)
                        .kFont(.content)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                    Spacer(minLength: KStyle.smallSpacing)
                    Text(indication.evidence.rawValue)
                        .kFont(.monoCaption)
                        .foregroundStyle(indication.evidence.color.opacity(KStyle.bioPaperPrimaryOpacity))
                        .padding(.horizontal, KStyle.bioProtocolEvidenceHorizontalPadding)
                        .padding(.vertical, KStyle.bioProtocolEvidenceVerticalPadding)
                        .background {
                            RoundedRectangle(cornerRadius: KStyle.bioProtocolEvidenceCornerRadius, style: .continuous)
                                .fill(indication.evidence.color.opacity(indication.evidence.fillOpacity))
                        }
                    Text(indication.outcome)
                        .kFont(.monoCaption)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                        .frame(maxWidth: KStyle.bioProtocolDetailMaxTextWidth * 0.5, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct BioMeditationSafetyList: View {
    let safety: [BioMeditationSafety]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.bioProtocolSafetyVerticalPadding) {
            Text("CONTRAINDICATIONS · ADVERSE EVENTS")
                .kFont(.monoCaption)
                .foregroundStyle(KStyle.bioProtocolSafetySignal.opacity(KStyle.bioProtocolSafetyOpacity))
            ForEach(safety) { item in
                HStack(alignment: .firstTextBaseline, spacing: KStyle.bioProtocolSafetyLeadingPadding) {
                    Circle()
                        .fill(item.absolute ? KStyle.bioProtocolAbsoluteSafetySignal : KStyle.bioProtocolSafetySignal)
                        .frame(width: KStyle.bioProtocolSafetyDotSize, height: KStyle.bioProtocolSafetyDotSize)
                    Text(item.text)
                        .kFont(.content)
                        .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperTertiaryOpacity))
                    if let frequency = item.frequency, !frequency.isEmpty {
                        Text(frequency)
                            .kFont(.monoCaption)
                            .foregroundStyle(KStyle.nearBlack.opacity(KStyle.bioPaperSecondaryOpacity))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Demo seed extension

extension BioDemo {
    static let biomarkers: [BioBiomarkerRecord] = [
        BioBiomarkerRecord(
            id: "vitamin-d",
            name: "vitamin d",
            value: 54,
            unit: "ng/mL",
            subtitle: "54 ng/mL · panel jul 6 · rising on protocol",
            range: BioBiomarkerRange(lower: 30, upper: 100, optimalLower: 40, optimalUpper: 80, optimalLabel: "optimal 40–80"),
            history: [
                BioBiomarkerHistoryPoint(label: "oct", value: 30),
                BioBiomarkerHistoryPoint(label: "jan", value: 38),
                BioBiomarkerHistoryPoint(label: "apr", value: 47),
                BioBiomarkerHistoryPoint(label: "jul", value: 54),
            ],
            note: "climbing steadily on the d3+k2 protocol — inside the target band since april.",
            documents: [
                BioBiomarkerDocument(text: "source: panel jul 6 · pdf"),
                BioBiomarkerDocument(text: "panel apr 2 · pdf"),
            ],
            bandPositionOverride: 0.46
        ),
        BioBiomarkerRecord(
            id: "ferritin",
            name: "ferritin",
            value: 38,
            unit: "ng/mL",
            subtitle: "38 ng/mL · panel jul 6 · 3rd consecutive decline",
            range: BioBiomarkerRange(lower: 15, upper: 400, optimalLower: 50, optimalUpper: 150, optimalLabel: "optimal 50–150"),
            history: [
                BioBiomarkerHistoryPoint(label: "oct", value: 61),
                BioBiomarkerHistoryPoint(label: "jan", value: 52),
                BioBiomarkerHistoryPoint(label: "apr", value: 44),
                BioBiomarkerHistoryPoint(label: "jul", value: 38),
            ],
            note: "trending toward the low band — the decline is consistent across three panels, not noise. the linked lever is the iron protocol; reasoning ran on the sovereign lane.",
            documents: [
                BioBiomarkerDocument(text: "source: panel jul 6 · pdf"),
                BioBiomarkerDocument(text: "panel apr 2 · pdf"),
            ],
            bandPositionOverride: 0.22
        ),
        BioBiomarkerRecord(
            id: "hba1c",
            name: "hba1c",
            value: 5.2,
            unit: "%",
            subtitle: "5.2% · panel jul 6 · flat, optimal",
            range: BioBiomarkerRange(lower: 4.5, upper: 6.5, optimalLower: 4.8, optimalUpper: 5.6, optimalLabel: "optimal 4.8–5.6"),
            history: [
                BioBiomarkerHistoryPoint(label: "oct", value: 5.3),
                BioBiomarkerHistoryPoint(label: "jan", value: 5.3),
                BioBiomarkerHistoryPoint(label: "apr", value: 5.1),
                BioBiomarkerHistoryPoint(label: "jul", value: 5.2),
            ],
            note: "flat inside the optimal band across four panels — nothing to act on.",
            documents: [BioBiomarkerDocument(text: "source: panel jul 6 · pdf")],
            bandPositionOverride: 0.48
        ),
        BioBiomarkerRecord(
            id: "apo-b",
            name: "apoB",
            value: 72,
            unit: "mg/dL",
            subtitle: "72 mg/dL · panel jul 6 · slow improvement",
            range: BioBiomarkerRange(lower: 40, upper: 130, optimalLower: 40, optimalUpper: 80, optimalLabel: "optimal 40–80"),
            history: [
                BioBiomarkerHistoryPoint(label: "oct", value: 84),
                BioBiomarkerHistoryPoint(label: "jan", value: 80),
                BioBiomarkerHistoryPoint(label: "apr", value: 76),
                BioBiomarkerHistoryPoint(label: "jul", value: 72),
            ],
            note: "drifting down the healthy way — four panels of slow improvement.",
            documents: [
                BioBiomarkerDocument(text: "source: panel jul 6 · pdf"),
                BioBiomarkerDocument(text: "panel apr 2 · pdf"),
            ],
            bandPositionOverride: 0.40
        ),
        BioBiomarkerRecord(
            id: "hs-crp",
            name: "hs-crp",
            value: 0.6,
            unit: "mg/L",
            subtitle: "0.6 mg/L · panel jul 6 · quiet",
            range: BioBiomarkerRange(lower: 0, upper: 3, optimalLower: 0, optimalUpper: 1, optimalLabel: "optimal 0–1"),
            history: [
                BioBiomarkerHistoryPoint(label: "oct", value: 0.8),
                BioBiomarkerHistoryPoint(label: "jan", value: 1.1),
                BioBiomarkerHistoryPoint(label: "apr", value: 0.7),
                BioBiomarkerHistoryPoint(label: "jul", value: 0.6),
            ],
            note: "low and quiet — one winter bump, long gone.",
            documents: [BioBiomarkerDocument(text: "source: panel jul 6 · pdf")],
            bandPositionOverride: 0.30
        ),
    ]

    static let nextTests: [BioNextTestRecord] = [
        BioNextTestRecord(id: "iron-panel", name: "iron panel", status: "booked", date: "aug 2"),
        BioNextTestRecord(id: "full-panel", name: "full panel", status: "due", date: "oct"),
    ]

    static let reports: [BioReportRecord] = [
        BioReportRecord(id: "blood-panel", name: "blood panel", date: "jul 6", glyph: .document),
        BioReportRecord(id: "dexa-scan", name: "dexa scan", date: "apr 12", glyph: .scan),
        BioReportRecord(id: "mri-report", name: "mri report", date: "jan 20", glyph: .circle),
    ]

    static let testingProtocols: [BioTestingProtocolProjection] = [
        BioTestingProtocolProjection(
            id: "baseline",
            name: "baseline",
            subtitle: "the quarterly floor · 24 markers · <₹40k · last run jul 6",
            tested: 22,
            total: 24,
            coveragePercent: 92,
            coverageLine: "22 of 24 markers tested · 2 due",
            categories: [
                BioProtocolCategory(name: "metabolic", count: 5, signal: .ok),
                BioProtocolCategory(name: "lipids", count: 4, signal: .ok),
                BioProtocolCategory(name: "iron panel", count: 3, signal: .warn),
                BioProtocolCategory(name: "inflammation", count: 2, signal: .ok),
                BioProtocolCategory(name: "thyroid", count: 3, signal: .ok),
                BioProtocolCategory(name: "vitamins", count: 2, signal: .warn),
                BioProtocolCategory(name: "cbc", count: 5, signal: .ok),
            ],
            dueTests: ["ferritin + iron studies", "vitamin d 25-OH"],
            note: "the recurring panel behind the overview scores. the two due markers gate the blood system's freshness — booking them refreshes it. testing only; the levers that move these numbers live in interventions."
        ),
        BioTestingProtocolProjection(
            id: "blueprint",
            name: "blueprint",
            subtitle: "the deep annual · 40 markers · ₹3k+ · last run jan",
            tested: 18,
            total: 40,
            coveragePercent: 45,
            coverageLine: "18 of 40 markers tested · 22 due",
            categories: [
                BioProtocolCategory(name: "metabolic", count: 6, signal: .ok),
                BioProtocolCategory(name: "advanced lipids", count: 5, signal: .warn),
                BioProtocolCategory(name: "hormones", count: 8, signal: .dim),
                BioProtocolCategory(name: "micronutrients", count: 7, signal: .warn),
                BioProtocolCategory(name: "organ panels", count: 8, signal: .ok),
                BioProtocolCategory(name: "inflammation", count: 6, signal: .dim),
            ],
            dueTests: ["apoB + Lp(a)", "omega-3 index", "full hormone panel"],
            note: "the once-a-year deep read. most of it is stale — a blueprint draw is due. it doesn't chase a lever; it re-baselines everything the quarterly panel skips."
        ),
        BioTestingProtocolProjection(
            id: "advanced",
            name: "advanced",
            subtitle: "specialist add-ons · 28 markers · ₹5k+ · mostly untested",
            tested: 6,
            total: 28,
            coveragePercent: 21,
            coverageLine: "6 of 28 markers tested · 22 available",
            categories: [
                BioProtocolCategory(name: "cardiac risk", count: 6, signal: .warn),
                BioProtocolCategory(name: "metabolomics", count: 8, signal: .dim),
                BioProtocolCategory(name: "toxins + heavy metals", count: 6, signal: .dim),
                BioProtocolCategory(name: "epigenetic age", count: 4, signal: .dim),
                BioProtocolCategory(name: "autoimmune", count: 4, signal: .dim),
            ],
            dueTests: ["heavy-metals panel", "epigenetic age clock"],
            note: "opt-in depth for a specific question — ordered when a signal warrants it, not on a cadence. contact for the clinician-ordered rows."
        ),
        BioTestingProtocolProjection(
            id: "investigation",
            name: "investigation",
            subtitle: "targeted dig · gut · tier 2 of 3 active",
            coveragePercent: 60,
            coverageLine: "tier 1 core done · tier 2 gut active · tier 3 env available",
            categories: [
                BioProtocolCategory(name: "tier 1 · core", count: 8, signal: .ok),
                BioProtocolCategory(name: "tier 2 · gut", count: 6, signal: .warn),
                BioProtocolCategory(name: "tier 3 · environment", count: 7, signal: .dim),
            ],
            dueTests: ["gut microbiome (tier 2)", "organic acids (tier 2)"],
            note: "a cumulative dig into one system — tiers activate in order. currently on gut; the results decide whether tier 3 (environment) is worth running."
        ),
    ]

    static let meditationLibrary: [BioMeditationProtocolProjection] = [
        meditation(
            id: "jhana",
            group: .active,
            railStatus: "day 34 · ph 2",
            subtitle: "the 8 absorptions · Ayya Khema / Pa Auk / Brasington lineages · day 34 of 90",
            evidenceLabel: "Level IV",
            phases: ["access concentration", "first jhana entry", "second jhana", "higher jhanas + integration"],
            phase: 1,
            focus: "phase 2 — first jhana entry: sustain access concentration until the nimitta stabilizes, then incline toward pīti. don't grasp; let absorption arrive.",
            method: ["samatha on the breath-nimitta", "45 min · eyes closed", "gate: 5 stable sits before phase 3"],
            indications: [
                BioMeditationIndication(name: "advanced concentration / deeper samādhi", evidence: .trad, outcome: "needs 100+ hrs base practice"),
                BioMeditationIndication(name: "hedonic well-being", evidence: .trad, outcome: "reliable pleasant abiding"),
            ],
            safety: [
                BioMeditationSafety(text: "prior psychosis or bipolar — screen before deep concentration work", absolute: true),
                BioMeditationSafety(text: "intense pīti/energy can disrupt sleep — cap session length if so"),
                BioMeditationSafety(text: "informed consent: absorption states are destabilizing for some"),
            ]
        ),
        meditation(
            id: "mbsr",
            group: .foundation,
            railStatus: "Level I",
            subtitle: "mindfulness-based stress reduction · 8-week clinical standard · Kabat-Zinn",
            evidenceLabel: "Level I",
            phases: ["foundation", "develop", "deepen", "integrate"],
            phase: 0,
            focus: "phase 1 — foundation: the body scan, daily. build the habit of attention returning without judgment before adding sitting practice.",
            method: ["body scan 45 min · guided", "6 days/week", "evidence: Cochrane CD004998 (pain), CD011723 (cancer)"],
            indications: [
                BioMeditationIndication(name: "chronic pain", evidence: .strong, outcome: "30–40% ↓ pain interference"),
                BioMeditationIndication(name: "anxiety disorders", evidence: .strong, outcome: "moderate–large effect"),
                BioMeditationIndication(name: "depression relapse", evidence: .strong, outcome: "Cochrane-supported"),
            ],
            safety: [
                BioMeditationSafety(text: "trauma history — body scan can surface material; pair with support", absolute: true),
                BioMeditationSafety(text: "not a substitute for care in acute depression"),
            ]
        ),
        meditation(
            id: "vipassana",
            group: .foundation,
            railStatus: "10-day",
            subtitle: "insight · Goenka (U Ba Khin) / Mahasi / Shinzen lineages · 10-day form",
            evidenceLabel: "Level II",
            phases: ["anapana", "body scanning intro", "deep scanning", "integration"],
            phase: 0,
            focus: "phase 1 — anapana: attention on the breath at the nostrils, narrowing the field for three days before scanning begins.",
            method: ["anapana 60 min", "10-day silent container", "then body sweeping (Goenka form)"],
            indications: [
                BioMeditationIndication(name: "equanimity / insight", evidence: .mod, outcome: "reactivity ↓ over retreat"),
                BioMeditationIndication(name: "stress reactivity", evidence: .mod, outcome: "sustained post-retreat"),
            ],
            safety: [
                BioMeditationSafety(text: "10-day retreats are intense — not for acute mental-health crises", absolute: true),
                BioMeditationSafety(text: "re-entry can be destabilizing; plan a soft landing"),
            ]
        ),
        meditation(
            id: "zen",
            group: .depth,
            railStatus: "Level II",
            subtitle: "shikantaza + koan · Sōtō / Rinzai · sitting-only depth",
            evidenceLabel: "Level II",
            phases: ["posture + breath", "shikantaza", "koan introspection", "just sitting"],
            phase: 1,
            focus: "phase 2 — shikantaza: 'just sitting', objectless awareness. no technique to lean on; the practice is the sitting itself.",
            method: ["zazen 40 min · eyes open, downcast", "posture is the practice", "teacher (roshi) for koan work"],
            indications: [
                BioMeditationIndication(name: "sustained attention", evidence: .mod, outcome: "builds over months"),
                BioMeditationIndication(name: "equanimity in daily life", evidence: .mod, outcome: "gradual"),
            ],
            safety: [
                BioMeditationSafety(text: "knee/hip load from long sitting — use a bench"),
                BioMeditationSafety(text: "koan work needs a teacher; self-directed can loop"),
            ]
        ),
        meditation(
            id: "kasina",
            group: .depth,
            railStatus: "concentration",
            subtitle: "concentration on a visual object · Pa Auk / Theravada · nimitta training",
            evidenceLabel: "Level IV",
            phases: ["object gazing", "after-image", "mental nimitta", "absorption"],
            phase: 0,
            focus: "phase 1 — object gazing: steady the attention on a colored disk (or candle) until the after-image holds when the eyes close.",
            method: ["kasina disk · 30 min", "dim room", "gate: after-image holds 10 breaths"],
            indications: [
                BioMeditationIndication(name: "nimitta / concentration training", evidence: .trad, outcome: "after-image stabilizes"),
                BioMeditationIndication(name: "absorption access", evidence: .trad, outcome: "gateway to jhana"),
            ],
            safety: [
                BioMeditationSafety(text: "visual after-images can persist — stop if they intrude on daily vision"),
                BioMeditationSafety(text: "intense concentration; screen for instability", absolute: true),
            ]
        ),
    ]

    private static func meditation(
        id: String,
        group: BioMeditationGroup,
        railStatus: String,
        subtitle: String,
        evidenceLabel: String,
        phases: [String],
        phase: Int,
        focus: String,
        method: [String],
        indications: [BioMeditationIndication],
        safety: [BioMeditationSafety]
    ) -> BioMeditationProtocolProjection {
        BioMeditationProtocolProjection(
            id: id,
            name: id,
            group: group,
            railStatus: railStatus,
            subtitle: subtitle,
            evidenceLabel: evidenceLabel,
            phases: phases,
            currentPhaseIndex: phase,
            focus: focus,
            methodNow: method,
            indications: indications,
            safety: safety,
            note: "the clinical library — indications with evidence strength, and the contraindications/adverse-event gate. a practice protocol is what you train, not what you measure; the live session, timer and brainwave read live on the attention surface."
        )
    }
}
