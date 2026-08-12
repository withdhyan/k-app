import Foundation
import SwiftUI

struct BuildReportDatum: Decodable, Equatable, Sendable {
    let rawValue: ViewPacketJSONValue

    init(from decoder: Decoder) throws {
        rawValue = try ViewPacketJSONValue(from: decoder)
    }

    init(_ rawValue: ViewPacketJSONValue) {
        self.rawValue = rawValue
    }

    var text: String? {
        switch rawValue {
        case .string(let value):
            return Self.normalized(value)
        case .number, .bool:
            return Self.normalized(rawValue.description)
        case .object(let object):
            for key in ["text", "displayText", "display_text", "summary"] {
                guard let value = object[key] else { continue }
                switch value {
                case .string, .number, .bool:
                    if let text = Self.normalized(value.description) {
                        return text
                    }
                case .object, .array, .null:
                    continue
                }
            }
            return nil
        case .array, .null:
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BuildReportLanded: Decodable, Equatable, Sendable {
    let value: BuildReportDatum
    let firstPass: BuildReportDatum?

    private enum CodingKeys: String, CodingKey {
        case firstPass
        case first_pass
    }

    init(from decoder: Decoder) throws {
        value = try BuildReportDatum(from: decoder)
        let object = value.rawValue.objectValue
        firstPass = (object?[CodingKeys.firstPass.rawValue] ?? object?[CodingKeys.first_pass.rawValue])
            .map(BuildReportDatum.init)
    }
}

struct BuildReportNeedsYou: Decodable, Equatable, Sendable {
    let value: BuildReportDatum
    let oldestAge: BuildReportDatum?

    private enum CodingKeys: String, CodingKey {
        case oldestAge
        case oldest_age
    }

    init(from decoder: Decoder) throws {
        value = try BuildReportDatum(from: decoder)
        let object = value.rawValue.objectValue
        oldestAge = (object?[CodingKeys.oldestAge.rawValue] ?? object?[CodingKeys.oldest_age.rawValue])
            .map(BuildReportDatum.init)
    }
}

struct BuildReport: Decodable, Equatable, Sendable {
    let schemaVersion: Int?
    let generatedAt: String?
    let stateSentence: String?
    let landed: BuildReportLanded?
    let needsYou: BuildReportNeedsYou?
    let constraint: BuildReportDatum?
    let rate: BuildReportDatum?
    let eta: BuildReportDatum?
    let repeats: BuildReportDatum?
    let unproven: BuildReportDatum?
    let actedOn: BuildReportDatum?
    let lanes: BuildReportDatum?
    let machine: BuildReportDatum?
    let tokens: BuildReportDatum?
    let spend: BuildReportDatum?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schema_version
        case generatedAt
        case generated_at
        case stateSentence
        case state_sentence
        case landed
        case needsYou
        case needs_you
        case constraint
        case rate
        case eta
        case repeats
        case unproven
        case actedOn
        case acted_on
        case lanes
        case machine
        case tokens
        case spend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? container.decodeIfPresent(Int.self, forKey: .schema_version)
        generatedAt = Self.normalized(
            try container.decodeIfPresent(String.self, forKey: .generatedAt)
                ?? container.decodeIfPresent(String.self, forKey: .generated_at)
        )
        stateSentence = Self.normalized(
            try container.decodeIfPresent(String.self, forKey: .stateSentence)
                ?? container.decodeIfPresent(String.self, forKey: .state_sentence)
        )
        landed = try container.decodeIfPresent(BuildReportLanded.self, forKey: .landed)
        needsYou = try container.decodeIfPresent(BuildReportNeedsYou.self, forKey: .needsYou)
            ?? container.decodeIfPresent(BuildReportNeedsYou.self, forKey: .needs_you)
        constraint = try container.decodeIfPresent(BuildReportDatum.self, forKey: .constraint)
        rate = try container.decodeIfPresent(BuildReportDatum.self, forKey: .rate)
        eta = try container.decodeIfPresent(BuildReportDatum.self, forKey: .eta)
        repeats = try container.decodeIfPresent(BuildReportDatum.self, forKey: .repeats)
        unproven = try container.decodeIfPresent(BuildReportDatum.self, forKey: .unproven)
        actedOn = try container.decodeIfPresent(BuildReportDatum.self, forKey: .actedOn)
            ?? container.decodeIfPresent(BuildReportDatum.self, forKey: .acted_on)
        lanes = try container.decodeIfPresent(BuildReportDatum.self, forKey: .lanes)
        machine = try container.decodeIfPresent(BuildReportDatum.self, forKey: .machine)
        tokens = try container.decodeIfPresent(BuildReportDatum.self, forKey: .tokens)
        spend = try container.decodeIfPresent(BuildReportDatum.self, forKey: .spend)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct BuildReportRow: Identifiable, Equatable, Sendable {
    enum ID: String, Equatable, Sendable {
        case landed
        case needsYou = "needs-you"
        case constraint
        case rate
        case eta
        case firstPass = "first-pass"
        case oldestStuck = "oldest-stuck"
        case repeats
        case unproven
        case actedOn = "acted-on"
        case lanes
        case machine
        case tokens
        case spend
    }

    let id: ID
    let label: String
    let value: String

    var accessibilityIdentifier: String {
        "build-report-\(id.rawValue)"
    }
}

struct BuildReportPresentation: Equatable, Sendable {
    let stateSentence: String?
    let ambientRows: [BuildReportRow]
    let detailRows: [BuildReportRow]

    init(report: BuildReport) {
        stateSentence = report.stateSentence
        ambientRows = [
            Self.row(.landed, label: "landed", value: report.landed?.value.text),
            Self.row(.needsYou, label: "needs you", value: report.needsYou?.value.text),
            Self.row(.constraint, label: "constraint", value: report.constraint?.text),
            Self.row(.rate, label: "rate", value: report.rate?.text),
            Self.row(.eta, label: "eta", value: report.eta?.text),
        ].compactMap { $0 }
        detailRows = [
            Self.row(.firstPass, label: "first-pass", value: report.landed?.firstPass?.text),
            Self.row(.oldestStuck, label: "oldest stuck", value: report.needsYou?.oldestAge?.text),
            Self.row(.repeats, label: "repeats", value: report.repeats?.text),
            Self.row(.unproven, label: "unproven", value: report.unproven?.text),
            Self.row(.actedOn, label: "acted-on", value: report.actedOn?.text),
            Self.row(.lanes, label: "lanes", value: report.lanes?.text),
            Self.row(.machine, label: "machine", value: report.machine?.text),
            Self.row(.tokens, label: "tokens", value: report.tokens?.text),
            Self.row(.spend, label: "spend", value: report.spend?.text),
        ].compactMap { $0 }
    }

    var isEmpty: Bool {
        stateSentence == nil && ambientRows.isEmpty && detailRows.isEmpty
    }

    private static func row(_ id: BuildReportRow.ID, label: String, value: String?) -> BuildReportRow? {
        guard let value = normalized(value) else { return nil }
        return BuildReportRow(id: id, label: label, value: value)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum BuildReportRailPlacement: Equatable {
    case regularRail
    case compactSentence
    case absent
}

enum BuildReportRailLayout {
    static func placement(
        horizontalSizeClass: UserInterfaceSizeClass?,
        availableWidth: CGFloat,
        report: BuildReport?
    ) -> BuildReportRailPlacement {
        guard let report else { return .absent }
        let presentation = BuildReportPresentation(report: report)
        guard !presentation.isEmpty else { return .absent }
        if horizontalSizeClass == .regular,
           availableWidth > KStyle.buildReportCompactMaxWidth {
            return .regularRail
        }
        return presentation.stateSentence == nil ? .absent : .compactSentence
    }

    static func workerPlacement(items: [BuildWorkerRailItem]) -> BuildWorkerRailPlacement {
        items.isEmpty ? .absent : .compactSection
    }
}

struct BuildReportMotionToken: Equatable, Sendable {
    let name: KNativeMotionName
    let duration: Double
}

enum BuildReportMotionSpec {
    static let tokens = [
        BuildReportMotionToken(name: .zen, duration: KStyle.nativeZenDuration),
        BuildReportMotionToken(name: .quick, duration: KStyle.nativeQuickDuration),
    ]
    static let transitionNames = ["opacity-fade", "transform-translate"]
}

extension AGUIClient {
    static let buildReportPath = "/build/report"

    func buildReport() async throws -> BuildReport {
        let request = try buildReportRequest()
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else {
            throw AGUIClientError.invalidResponse
        }

        var lines: [String] = []
        for try await line in lineResponse.lines {
            lines.append(line)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AGUIClientError.httpStatus(http.statusCode)
        }

        let data = Data(lines.joined(separator: "\n").utf8)
        guard !data.isEmpty else { throw AGUIClientError.invalidResponse }
        return try JSONDecoder().decode(BuildReport.self, from: data)
    }

    private func buildReportRequest() throws -> URLRequest {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base), components.scheme != nil else {
            throw AGUIClientError.invalidURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let reportPath = Self.buildReportPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, reportPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else { throw AGUIClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

struct BuildReportCompactSentence: View {
    let report: BuildReport

    var body: some View {
        if let sentence = BuildReportPresentation(report: report).stateSentence {
            Text(sentence)
                .font(KStyle.contentFont)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, KStyle.buildReportCompactTopPadding)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(KStyle.hairlineOpacity))
                        .frame(height: KStyle.dividerHeight)
                }
                .accessibilityLabel(sentence)
                .accessibilityIdentifier("build-report-sentence")
                .modifier(BuildReportArrivalModifier())
        }
    }
}

// The factory's only expanded face lives in the iPad rail. It uses the same
// expand-right paper surface as plan detail; the main factory remains one glass card.
struct BuildFactoryDetailPanel: View {
    let report: BuildReport
    let onClose: () -> Void

    var body: some View {
        BuildGrammarCardSurface(isExpanded: true) {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KMonoCaption("factory", variant: .metadata, state: .active)
                    Spacer(minLength: KStyle.smallSpacing)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "close",
                                label: "close",
                                accessibilityIdentifier: "build-factory-close"
                            ),
                        ],
                        variant: .build,
                        onSelect: { _ in onClose() }
                    )
                    .environment(\.kInkOnPaper, true)
                }
                .accessibilityHint("close factory detail")

                BuildFactoryReportContent(report: report)
            }
            .environment(\.kInkOnPaper, true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("factory detail")
        .accessibilityIdentifier("build-factory-detail")
    }
}

// Founder B10.1 (2026-08-05): the report metrics use a two-column grid so the
// detail reads as a composed card, not a blob of engineering text. The current
// BUILD report face keeps the shared presentation logic in one place.
private struct BuildFactoryReportContent: View {
    let report: BuildReport

    private var presentation: BuildReportPresentation {
        BuildReportPresentation(report: report)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: KStyle.buildReportSectionSpacing, alignment: .leading),
            GridItem(.flexible(), spacing: KStyle.buildReportSectionSpacing, alignment: .leading),
        ]
    }

    var body: some View {
        let p = presentation
        VStack(alignment: .leading, spacing: KStyle.buildReportSectionSpacing) {
            if let sentence = p.stateSentence {
                Text(sentence)
                    .font(KStyle.contentFont)
                    .foregroundStyle(KStyle.nearBlack.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !p.ambientRows.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: KStyle.buildReportSectionSpacing) {
                    ForEach(p.ambientRows) { BuildReportMetricRow(row: $0, onLight: true) }
                }
            }

            if !p.detailRows.isEmpty {
                Rectangle()
                    .fill(KStyle.nearBlack.opacity(KStyle.hairlineOpacity))
                    .frame(height: KStyle.dividerHeight)
                LazyVGrid(columns: columns, alignment: .leading, spacing: KStyle.buildReportSectionSpacing) {
                    ForEach(p.detailRows) { BuildReportMetricRow(row: $0, onLight: true) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BuildReportMetricRow: View {
    let row: BuildReportRow
    // On the white forward card the ink is dark; on dark rail content it stays light.
    var onLight: Bool = false

    private var ink: Color { onLight ? KStyle.nearBlack : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.buildReportMetricSpacing) {
            Text(row.label)
                .kFont(.monoCaption)
                .foregroundStyle(ink.opacity(KStyle.quaternaryTextOpacity))
            Text(row.value)
                .kFont(.monoCaptionDigit)
                .foregroundStyle(ink.opacity(KStyle.tertiaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label), \(row.value)")
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }
}

private struct BuildReportArrivalModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    func body(content: Content) -> some View {
        content
            .opacity(hasArrived ? KStyle.fullOpacity : .zero)
            .offset(
                y: reduceMotion || hasArrived
                    ? .zero
                    : KStyle.buildReportArrivalOffset
            )
            .animation(
                KStyle.nativeMotion(.zen, reduceMotion: reduceMotion),
                value: hasArrived
            )
            .onAppear {
                hasArrived = true
            }
    }
}
