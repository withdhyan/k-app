import SwiftUI

struct JarvisClaimStreamBlock: View {
    let packet: ViewPacket
    private let claim: JarvisClaimBlock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    init(packet: ViewPacket) {
        self.packet = packet
        self.claim = JarvisClaimBlock(packet: packet)
    }

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                    Text(claim.title)
                        .kFont(.blockDefaultTitle)
                        .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        ClaimStatus(status: claim.status, state: .resting)
                        ConfidenceBadge(level: claim.confidenceLevel, state: .resting)
                    }
                }

                if isExpanded {
                    if let body = claim.bodyText {
                        Text(body)
                            .kFont(.content)
                            .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    if let warrantText = claim.warrantText {
                        KMonoCaption("because \(warrantText)", variant: .metadata, state: .active)
                    }

                    ForEach(claim.supplementalLines, id: \.self) { line in
                        KMonoCaption(line, variant: .metadata)
                    }

                    if !claim.evidenceLines.isEmpty {
                        KEvidenceBlock(text: claim.evidenceLines.joined(separator: "\n"), variant: .mono)
                    }
                } else if !claim.collapsedLines.isEmpty {
                    KMonoCaption(claim.collapsedLines.joined(separator: " · "), variant: .metadata)
                }

                if claim.hasExpandableContent {
                    KMonoCaption(isExpanded ? "hide" : "show", variant: .metadata)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("jarvis-claim-\(packet.id)")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "collapses this claim" : "expands this claim")
        .onTapGesture {
            withAnimation(KStyle.chatContentSwapMotion(reduceMotion)) {
                isExpanded.toggle()
            }
        }
    }
}

struct JarvisChartStreamBlock: View {
    let packet: ViewPacket
    private let chart: JarvisChartBlock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    init(packet: ViewPacket) {
        self.packet = packet
        self.chart = JarvisChartBlock(packet: packet)
    }

    var body: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                Text(chart.title)
                    .kFont(.blockDefaultTitle)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if chart.points.isEmpty {
                    Text(chart.fallbackText)
                        .kFont(.content)
                        .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                        ForEach(displayPoints) { point in
                            chartPointRow(point)
                        }

                        if !isExpanded && chart.hasMorePoints {
                            KMonoCaption("+\(chart.morePointCount) more", variant: .metadata)
                        }
                    }
                }

                if isExpanded {
                    ForEach(chart.metadataLines, id: \.self) { line in
                        KMonoCaption(line, variant: .metadata)
                    }
                }

                if chart.hasToggleControl {
                    KMonoCaption(isExpanded ? "hide" : "show", variant: .metadata)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("jarvis-chart-\(packet.id)")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "collapses this chart" : "expands this chart")
        .onTapGesture {
            withAnimation(KStyle.chatContentSwapMotion(reduceMotion)) {
                isExpanded.toggle()
            }
        }
    }

    private var displayPoints: ArraySlice<JarvisChartPoint> {
        let visibleCount = isExpanded ? chart.points.count : min(chart.points.count, chart.maxCollapsedPoints)
        let endIndex = min(visibleCount, chart.points.count)
        return chart.points[..<endIndex]
    }

    private func chartPointRow(_ point: JarvisChartPoint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(point.label)
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

            if point.value != nil {
                let normalized = point.normalizedValue(max: chart.maxValue)
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: KStyle.smallSpacing)
                        .fill(point.valueColor)
                        .frame(
                            width: max(geometry.size.width * 0.06, geometry.size.width * normalized),
                            height: KStyle.blockDotRegularSize
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: KStyle.blockDotRegularSize)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 80, height: KStyle.blockDotRegularSize)
            }

            Text(point.valueText)
                .kFont(.monoCaption)
                .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                .lineLimit(1)
        }
    }
}

struct JarvisChartBlock: Equatable {
    let title: String
    let fallbackText: String
    let points: [JarvisChartPoint]
    let metadataLines: [String]
    let maxCollapsedPoints: Int
    let maxValue: Double

    init(
        packet: ViewPacket,
        maxCollapsedPoints: Int = 4
    ) {
        let fields = packet.fields ?? [:]

        let resolvedTitle = JarvisBlocks.string(for: fields["title"])
            ?? JarvisBlocks.string(for: fields["name"])
            ?? packet.displayText
        title = resolvedTitle.isEmpty ? "chart" : resolvedTitle

        let trimmedDisplayText = JarvisBlocks.normalize(packet.displayText)
        fallbackText = trimmedDisplayText.isEmpty ? "chart" : trimmedDisplayText

        self.maxCollapsedPoints = max(2, maxCollapsedPoints)

        let chartValue = fields["chart"]
        let seriesValue: ViewPacketJSONValue?
        if let value = fields["series"] {
            seriesValue = value
        } else if let value = fields["points"] {
            seriesValue = value
        } else if let value = fields["rows"] {
            seriesValue = value
        } else if let value = chartValue?.objectValue?["series"] {
            seriesValue = value
        } else if let value = chartValue?.objectValue?["points"] {
            seriesValue = value
        } else {
            seriesValue = chartValue
        }

        let parsedPoints = Self.parsePoints(from: seriesValue)
        points = parsedPoints
        maxValue = parsedPoints.compactMap(\.value).map { abs($0) }.max() ?? 1

        var metadata: [String] = []
        metadata.append(contentsOf: JarvisBlocks.lines(for: ["subtitle", "caption", "xLabel", "yLabel"], in: fields))
        if let chartValue {
            metadata.append(contentsOf: JarvisBlocks.lines(for: ["subtitle", "caption", "xLabel", "yLabel"], in: chartValue.objectValue ?? [:]))
        }

        metadataLines = JarvisBlocks.uniqueLines(metadata)
    }

    var hasMorePoints: Bool {
        points.count > maxCollapsedPoints
    }

    var morePointCount: Int {
        max(0, points.count - maxCollapsedPoints)
    }

    var hasToggleControl: Bool {
        points.count > maxCollapsedPoints
    }

    /// A parsed point before it is given a display identity. Points are assembled
    /// into their final order first, then numbered, so each `JarvisChartPoint.id`
    /// is stable across re-parses and `ForEach` diffs rows instead of rebuilding them.
    private struct RawPoint {
        let label: String
        let value: Double?
        let valueText: String?
    }

    private static func parsePoints(from value: ViewPacketJSONValue?) -> [JarvisChartPoint] {
        parseRawPoints(from: value).enumerated().map { index, raw in
            JarvisChartPoint(index: index, label: raw.label, value: raw.value, valueText: raw.valueText)
        }
    }

    private static func parseRawPoints(from value: ViewPacketJSONValue?) -> [RawPoint] {
        guard let value else { return [] }

        if let array = value.arrayValue {
            return array.enumerated().compactMap { index, item in
                parseRawPoint(item, defaultLabel: "point \(index + 1)")
            }
        }

        if let object = value.objectValue {
            if let labels = object["labels"]?.arrayValue,
               let values = object["values"]?.arrayValue {
                let minCount = min(labels.count, values.count)
                guard minCount > 0 else { return [] }
                return (0..<minCount).compactMap { index in
                    parseRawPoint(
                        values[index],
                        defaultLabel: JarvisBlocks.string(for: labels[index]) ?? "point \(index + 1)"
                    )
                }
            }

            return object.compactMap { key, item in
                parseRawPoint(item, defaultLabel: key)
            }
        }

        return []
    }

    private static func parseRawPoint(_ value: ViewPacketJSONValue?, defaultLabel: String) -> RawPoint? {
        guard let value else { return nil }

        if let object = value.objectValue {
            let parsedValue =
                object["value"]?.doubleValue
                ?? object["y"]?.doubleValue
                ?? object["count"]?.doubleValue
                ?? object["score"]?.doubleValue

            let valueText =
                JarvisBlocks.string(for: object["value"])
                ?? JarvisBlocks.string(for: object["y"])
                ?? JarvisBlocks.string(for: object["count"])
                ?? JarvisBlocks.string(for: object["score"])

            let label =
                JarvisBlocks.string(for: object["label"])
                ?? JarvisBlocks.string(for: object["name"])
                ?? JarvisBlocks.string(for: object["x"])
                ?? JarvisBlocks.string(for: object["key"])
                ?? defaultLabel

            return RawPoint(label: label, value: parsedValue, valueText: valueText)
        }

        return RawPoint(label: defaultLabel, value: value.doubleValue, valueText: JarvisBlocks.string(for: value))
    }
}

struct JarvisChartPoint: Equatable, Identifiable {
    let id: String
    let label: String
    let value: Double?
    let valueText: String

    init(index: Int, label: String, value: Double?, valueText: String?) {
        let normalizedLabel = JarvisBlocks.normalize(label)
        self.id = "\(index)-\(normalizedLabel)"
        self.label = normalizedLabel
        self.value = value
        let normalizedValueText = valueText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedValueText, !normalizedValueText.isEmpty {
            self.valueText = normalizedValueText
        } else if let value {
            self.valueText = String(format: "%.2f", value)
        } else {
            self.valueText = label
        }
    }

    var valueColor: Color {
        guard let value else {
            return KSignal.idle.color
        }
        if value > 0 { return KStyle.liveSignal }
        if value < 0 { return KStyle.errorSignal }
        return KStyle.attentionSignal
    }

    func normalizedValue(max maxValue: Double) -> Double {
        guard let value, maxValue > 0 else { return 0.05 }
        return max(0.05, min(1, abs(value) / maxValue))
    }
}

struct JarvisClaimBlock: Equatable {
    let title: String
    let bodyText: String?
    let warrantText: String?
    let status: KClaimLifecycleStatus
    let confidenceLevel: KConfidenceLevel
    let evidenceLines: [String]
    let supplementalLines: [String]
    let isWarrantTagged: Bool

    init(packet: ViewPacket) {
        let fields = packet.fields ?? [:]

        title = JarvisBlocks.string(for: fields["claimText"])
            ?? JarvisBlocks.string(for: fields["claim"])
            ?? JarvisBlocks.string(for: fields["statement"])
            ?? packet.displayText

        bodyText = JarvisBlocks.string(for: fields["body"])

        warrantText =
            JarvisBlocks.warrantString(for: fields["warrant"])
            ?? JarvisBlocks.warrantString(for: fields["support"])
            ?? JarvisBlocks.warrantString(for: fields["warranty"])

        status = KClaimLifecycleStatus(rawValue: JarvisBlocks.normalized(fields["status"])) ?? .proposed

        confidenceLevel = KConfidenceLevel.forConfidence(fields["confidence"]?.doubleValue ?? packet.confidence)
        isWarrantTagged = JarvisBlocks.hasWarrantTag(fields: fields)

        var supplemental: [String] = []
        supplemental.append(contentsOf: JarvisBlocks.lines(for: ["openQuestion", "stakes", "why", "summary", "contrast"], in: fields))
        supplemental.append(contentsOf: JarvisBlocks.lines(for: ["note", "notes"], in: fields))
        if isWarrantTagged {
            supplemental.append("warrant tagged")
        }
        supplementalLines = JarvisBlocks.uniqueLines(supplemental)

        evidenceLines = JarvisBlocks.uniqueLines([
            ViewPacketRenderer.evidenceVisibleLines(for: packet),
            JarvisBlocks.lines(for: ["evidence", "evidenceSummary", "grounding", "contributors", "confounders"], in: fields),
        ].flatMap { $0 })
    }

    var collapsedLines: [String] {
        supplementalLines
    }

    var hasExpandableContent: Bool {
        bodyText != nil || !supplementalLines.isEmpty || !evidenceLines.isEmpty
    }
}

private enum JarvisBlocks {
    static func string(for value: ViewPacketJSONValue?) -> String? {
        let text = value?.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    static func normalized(_ value: ViewPacketJSONValue?) -> String {
        JarvisBlocks.string(for: value)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    static func strings(for value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }

        if let array = value.arrayValue {
            return array.compactMap { item in
                if let object = item.objectValue {
                    return string(for: object["label"])
                        ?? string(for: object["text"])
                        ?? string(for: object["name"])
                        ?? string(for: object["value"])
                }
                return string(for: item)
            }
        }

        if let object = value.objectValue {
            return object.values.compactMap(string)
        }

        return string(for: value).flatMap { [$0] } ?? []
    }

    static func lines(for keys: [String], in fields: [String: ViewPacketJSONValue]) -> [String] {
        var values: [String] = []
        for key in keys {
            guard let value = fields[key] else { continue }
            values.append(contentsOf: strings(for: value))
        }
        return values
    }

    static func uniqueLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    /// A warrant citation must be a genuine non-empty string. Fail closed:
    /// bool/number/object payloads are not warrants and never tag the claim, so
    /// a malformed warrant renders as the inline fallback, not the native block.
    static func warrantString(for value: ViewPacketJSONValue?) -> String? {
        guard case .string(let raw)? = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hasWarrantTag(fields: [String: ViewPacketJSONValue]) -> Bool {
        if warrantString(for: fields["warrant"]) != nil { return true }
        if warrantString(for: fields["warranty"]) != nil { return true }
        if warrantString(for: fields["support"]) != nil { return true }
        let tags = normalizedTags(fields["tags"])
        return tags.contains("warrant") || tags.contains("warrant-tagged")
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTags(_ value: ViewPacketJSONValue?) -> Set<String> {
        Set(strings(for: value).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }
}
