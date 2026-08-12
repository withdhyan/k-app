import Foundation
import SwiftUI

struct TermAnnotationRange: Codable, Equatable, Sendable {
    let start: Int
    let length: Int

    init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    fileprivate func stringRange(in text: String) -> Range<String.Index>? {
        guard start >= 0, length > 0, start <= Int.max - length else { return nil }
        guard let lower = stringIndex(utf16Offset: start, in: text),
              let upper = stringIndex(utf16Offset: start + length, in: text),
              lower < upper
        else { return nil }
        return lower..<upper
    }

    private func stringIndex(utf16Offset: Int, in text: String) -> String.Index? {
        let view = text.utf16
        guard let offsetIndex = view.index(
            view.startIndex,
            offsetBy: utf16Offset,
            limitedBy: view.endIndex
        ) else { return nil }
        return String.Index(offsetIndex, within: text)
    }
}

struct TermAnnotation: Codable, Equatable, Sendable {
    let term: String
    let range: TermAnnotationRange
    let definition: String
    let firstSeenRef: String?

    init(
        term: String,
        range: TermAnnotationRange,
        definition: String,
        firstSeenRef: String? = nil
    ) {
        self.term = term
        self.range = range
        self.definition = definition
        self.firstSeenRef = firstSeenRef
    }

    var stableID: String {
        [term, String(range.start), String(range.length), definition, firstSeenRef ?? ""]
            .joined(separator: "|")
    }

    fileprivate func withRange(_ range: TermAnnotationRange) -> TermAnnotation {
        TermAnnotation(
            term: term,
            range: range,
            definition: definition,
            firstSeenRef: firstSeenRef
        )
    }
}

struct TermAnnotationsPayload: Codable, Equatable, Sendable {
    let termAnnotations: [TermAnnotation]

    init(termAnnotations: [TermAnnotation] = []) {
        self.termAnnotations = termAnnotations
    }

    private enum CodingKeys: String, CodingKey {
        case termAnnotations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termAnnotations = try container.decodeIfPresent([TermAnnotation].self, forKey: .termAnnotations) ?? []
    }
}

protocol TermAnnotationsSource: Sendable {
    func annotations(for text: String) -> [TermAnnotation]
}

private struct TermAnnotationsEnvironmentKey: EnvironmentKey {
    static let defaultValue: [TermAnnotation]? = nil
}

extension EnvironmentValues {
    var termAnnotations: [TermAnnotation]? {
        get { self[TermAnnotationsEnvironmentKey.self] }
        set { self[TermAnnotationsEnvironmentKey.self] = newValue }
    }
}

struct FixtureTermAnnotationsSource: TermAnnotationsSource, Equatable, Sendable {
    enum Fixture: Sendable {
        case annotated
        case empty
    }

    let fixtureAnnotations: [TermAnnotation]

    init(fixture: Fixture = .annotated) {
        let payload: Data
        switch fixture {
        case .annotated:
            payload = Self.annotatedPayload
        case .empty:
            payload = Self.emptyPayload
        }
        fixtureAnnotations = (try? TermAnnotationsWireDecoder.decode(payload).termAnnotations) ?? []
    }

    init(annotations: [TermAnnotation]) {
        fixtureAnnotations = annotations
    }

    init(data: Data) throws {
        fixtureAnnotations = try TermAnnotationsWireDecoder.decode(data).termAnnotations
    }

    static let annotated = FixtureTermAnnotationsSource(fixture: .annotated)
    static let empty = FixtureTermAnnotationsSource(fixture: .empty)
    static let `default` = annotated

    func annotations(for text: String) -> [TermAnnotation] {
        guard !text.isEmpty else { return [] }

        return fixtureAnnotations.compactMap { fixtureAnnotation in
            let term = fixtureAnnotation.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty,
                  let match = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  )
            else { return nil }

            let matchRange = NSRange(match, in: text)
            return fixtureAnnotation.withRange(
                TermAnnotationRange(start: matchRange.location, length: matchRange.length)
            )
        }
    }

    private static let annotatedPayload = Data(#"""
    {
      "termAnnotations": [
        {
          "term": "ontology",
          "range": {"start": 0, "length": 8},
          "definition": "the kinds of things a system can know and act on.",
          "firstSeenRef": "chat"
        },
        {
          "term": "membrane",
          "range": {"start": 0, "length": 8},
          "definition": "the boundary that decides what crosses between systems.",
          "firstSeenRef": "build chat"
        }
      ]
    }
    """#.utf8)

    private static let emptyPayload = Data(#"{"termAnnotations":[]}"#.utf8)
}

enum TermAnnotationsWireDecoder {
    static func decode(_ data: Data) throws -> TermAnnotationsPayload {
        try JSONDecoder().decode(TermAnnotationsPayload.self, from: data)
    }

    static func annotations(from fields: [String: ViewPacketJSONValue]?) -> [TermAnnotation]? {
        guard let value = fields?["termAnnotations"] else { return nil }
        return annotations(from: value)
    }

    static func annotations(from value: ViewPacketJSONValue) -> [TermAnnotation]? {
        if let object = value.objectValue,
           let nested = object["termAnnotations"] {
            return annotations(from: nested)
        }

        guard let values = value.arrayValue else { return [] }
        return values.compactMap(annotation(from:))
    }

    private static func annotation(from value: ViewPacketJSONValue) -> TermAnnotation? {
        guard let object = value.objectValue,
              let term = nonEmptyString(object["term"]),
              let rangeObject = object["range"]?.objectValue,
              let start = integer(rangeObject["start"]),
              let length = integer(rangeObject["length"]),
              let definition = nonEmptyString(object["definition"])
        else { return nil }

        return TermAnnotation(
            term: term,
            range: TermAnnotationRange(start: start, length: length),
            definition: definition,
            firstSeenRef: nonEmptyString(object["firstSeenRef"])
        )
    }

    private static func nonEmptyString(_ value: ViewPacketJSONValue?) -> String? {
        guard let value,
              let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }

    private static func integer(_ value: ViewPacketJSONValue?) -> Int? {
        guard let number = value?.doubleValue,
              number.isFinite,
              number.rounded() == number,
              number >= Double(Int.min),
              number <= Double(Int.max)
        else { return nil }
        return Int(number)
    }
}

struct TermAnnotationSegment: Equatable, Sendable {
    let text: String
    let annotation: TermAnnotation?

    var isAnnotated: Bool { annotation != nil }
}

struct TermAnnotationToken: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let annotation: TermAnnotation?
}

enum TermAnnotationText {
    static func resolvedAnnotations(
        in text: String,
        explicit: [TermAnnotation]?,
        source: any TermAnnotationsSource
    ) -> [TermAnnotation] {
        explicit ?? source.annotations(for: text)
    }

    static func segments(
        in text: String,
        annotations: [TermAnnotation]
    ) -> [TermAnnotationSegment] {
        guard !text.isEmpty else { return [] }

        let candidates = annotations.enumerated().compactMap { index, annotation -> Candidate? in
            guard let range = annotation.range.stringRange(in: text) else { return nil }
            return Candidate(annotation: annotation, range: range, order: index)
        }
        .sorted { left, right in
            if left.range.lowerBound == right.range.lowerBound {
                return left.order < right.order
            }
            return left.range.lowerBound < right.range.lowerBound
        }

        var output: [TermAnnotationSegment] = []
        var cursor = text.startIndex

        for candidate in candidates {
            guard candidate.range.lowerBound >= cursor else { continue }

            if cursor < candidate.range.lowerBound {
                output.append(TermAnnotationSegment(
                    text: String(text[cursor..<candidate.range.lowerBound]),
                    annotation: nil
                ))
            }

            output.append(TermAnnotationSegment(
                text: String(text[candidate.range]),
                annotation: candidate.annotation
            ))
            cursor = candidate.range.upperBound
        }

        if cursor < text.endIndex {
            output.append(TermAnnotationSegment(
                text: String(text[cursor..<text.endIndex]),
                annotation: nil
            ))
        }

        return output.isEmpty
            ? [TermAnnotationSegment(text: text, annotation: nil)]
            : output
    }

    static func applying(
        _ annotations: [TermAnnotation],
        to text: String
    ) -> [TermAnnotationSegment] {
        segments(in: text, annotations: annotations)
    }

    static func rebased(
        _ annotations: [TermAnnotation],
        to utf16Range: Range<Int>
    ) -> [TermAnnotation] {
        annotations.compactMap { annotation in
            let start = annotation.range.start
            guard start >= 0,
                  annotation.range.length > 0,
                  start <= Int.max - annotation.range.length
            else { return nil }
            let end = start + annotation.range.length
            guard start >= utf16Range.lowerBound,
                  end <= utf16Range.upperBound,
                  end > start
            else { return nil }
            return annotation.withRange(
                TermAnnotationRange(
                    start: start - utf16Range.lowerBound,
                    length: annotation.range.length
                )
            )
        }
    }

    static func tokens(from segments: [TermAnnotationSegment]) -> [TermAnnotationToken] {
        var tokens: [TermAnnotationToken] = []
        var index = 0

        for segment in segments {
            var run = ""
            var runIsWhitespace: Bool?

            func appendRun() {
                guard !run.isEmpty else { return }
                tokens.append(TermAnnotationToken(
                    id: "term-token-\(index)",
                    text: run,
                    annotation: segment.annotation
                ))
                index += 1
                run = ""
            }

            for character in segment.text {
                let isWhitespace = character.isWhitespace
                if let runIsWhitespace, runIsWhitespace != isWhitespace {
                    appendRun()
                }
                runIsWhitespace = isWhitespace
                run.append(character)
            }
            appendRun()
        }

        return tokens
    }

    private struct Candidate {
        let annotation: TermAnnotation
        let range: Range<String.Index>
        let order: Int
    }
}

struct TermAnnotatedText: View {
    let text: String
    let annotations: [TermAnnotation]?
    let source: any TermAnnotationsSource
    let font: Font
    let foregroundColor: Color
    let accessibilityIdentifier: String

    @State private var revealedAnnotationID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: String,
        annotations: [TermAnnotation]? = nil,
        source: any TermAnnotationsSource = FixtureTermAnnotationsSource.default,
        font: Font = KStyle.contentFont,
        foregroundColor: Color = KStyle.termHighlightColor.opacity(KStyle.primaryTextOpacity),
        accessibilityIdentifier: String = "term-annotated-text"
    ) {
        self.text = text
        self.annotations = annotations
        self.source = source
        self.font = font
        self.foregroundColor = foregroundColor
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var resolvedAnnotations: [TermAnnotation] {
        TermAnnotationText.resolvedAnnotations(in: text, explicit: annotations, source: source)
    }

    private var appliedSegments: [TermAnnotationSegment] {
        TermAnnotationText.segments(in: text, annotations: resolvedAnnotations)
    }

    private var visibleAnnotations: [TermAnnotation] {
        appliedSegments.compactMap(\.annotation)
    }

    private var revealedAnnotation: TermAnnotation? {
        guard let revealedAnnotationID else { return nil }
        return visibleAnnotations.first { $0.stableID == revealedAnnotationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.termDefinitionSpacing) {
            if visibleAnnotations.isEmpty {
                plainText
            } else {
                TermAnnotationFlowLayout(spacing: KStyle.termFlowLineSpacing) {
                    ForEach(TermAnnotationText.tokens(from: appliedSegments)) { token in
                        tokenView(token)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let revealedAnnotation {
                    definitionCard(revealedAnnotation)
                        .transition(definitionTransition)
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onEnded { value in
                                    if value < KStyle.termPinchCollapseThreshold {
                                        collapseDefinition()
                                    }
                                }
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .animation(KStyle.termDefinitionMotion(reduceMotion), value: revealedAnnotationID)
        .onChange(of: text) { _, _ in
            revealedAnnotationID = nil
        }
    }

    private var plainText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func tokenView(_ token: TermAnnotationToken) -> some View {
        let base = Text(token.text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .fixedSize()

        if let annotation = token.annotation {
            base
                .underline(
                    true,
                    color: KStyle.termHighlightColor.opacity(KStyle.termHighlightUnderlineOpacity)
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    MagnificationGesture()
                        .onEnded { value in
                            if value > KStyle.termPinchExpandThreshold {
                                reveal(annotation)
                            } else if value < KStyle.termPinchCollapseThreshold {
                                collapseDefinition()
                            }
                        }
                )
                .accessibilityLabel(annotation.term.lowercased())
                .accessibilityHint(KCopy.termPinchHint)
                .accessibilityIdentifier("term-highlight-\(annotation.stableID)")
                .accessibilityAction(named: Text(KCopy.termShowDefinition)) {
                    reveal(annotation)
                }
        } else {
            base
        }
    }

    private func definitionCard(_ annotation: TermAnnotation) -> some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.termDefinitionSpacing) {
                KMonoCaption(annotation.term, variant: .metadata)
                Text(annotation.definition)
                    .font(font)
                    .foregroundStyle(foregroundColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let firstSeenRef = annotation.firstSeenRef,
                   !firstSeenRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    KMonoCaption(
                        "\(KCopy.termFirstSeen) · \(firstSeenRef)",
                        variant: .metadata
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("term-definition-\(annotation.stableID)")
        .accessibilityAction(named: Text(KCopy.termCollapseDefinition)) {
            collapseDefinition()
        }
    }

    private var definitionTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(y: KStyle.termDefinitionRevealOffset))
    }

    private func reveal(_ annotation: TermAnnotation) {
        withAnimation(KStyle.termDefinitionMotion(reduceMotion)) {
            revealedAnnotationID = annotation.stableID
        }
    }

    private func collapseDefinition() {
        withAnimation(KStyle.termDefinitionMotion(reduceMotion)) {
            revealedAnnotationID = nil
        }
    }
}

private struct TermAnnotationFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? max(
            sizes.reduce(.zero) { $0 + $1.width },
            KStyle.termFlowMinimumWidth
        )
        return layout(sizes: sizes, width: availableWidth).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? bounds.width
        let placements = layout(sizes: sizes, width: availableWidth).placements

        for (index, placement) in placements.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + placement.origin.x,
                    y: bounds.minY + placement.origin.y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func layout(sizes: [CGSize], width: CGFloat) -> (size: CGSize, placements: [Placement]) {
        guard !sizes.isEmpty else { return (.zero, []) }

        var placements: [Placement] = []
        var x: CGFloat = .zero
        var y: CGFloat = .zero
        var rowHeight: CGFloat = .zero

        for size in sizes {
            if x > .zero, x + size.width > width {
                y += rowHeight + spacing
                x = .zero
                rowHeight = .zero
            }

            placements.append(Placement(
                origin: CGPoint(x: x, y: y),
                size: size
            ))
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        return (
            CGSize(width: width, height: y + rowHeight),
            placements
        )
    }

    private struct Placement {
        let origin: CGPoint
        let size: CGSize
    }
}
