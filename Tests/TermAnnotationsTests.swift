import Foundation
import XCTest
@testable import K

final class TermAnnotationsTests: XCTestCase {
    func testAnnotationRangeApplicationKeepsPlainGapsAndMarksOnlyTheRange() {
        let text = "k uses ontology here"
        let annotation = TermAnnotation(
            term: "ontology",
            range: TermAnnotationRange(start: 7, length: 8),
            definition: "the kinds of things a system can know and act on.",
            firstSeenRef: "chat"
        )

        let segments = TermAnnotationText.segments(in: text, annotations: [annotation])

        XCTAssertEqual(segments.map(\.text), ["k uses ", "ontology", " here"])
        XCTAssertNil(segments[0].annotation)
        XCTAssertEqual(segments[1].annotation, annotation)
        XCTAssertNil(segments[2].annotation)
    }

    func testFixtureSourceDecodesPayloadAndRebasesItsDeterministicMatch() throws {
        let data = Data(#"""
        {
          "termAnnotations": [
            {
              "term": "ontology",
              "range": {"start": 0, "length": 8},
              "definition": "the kinds of things a system can know and act on.",
              "firstSeenRef": "chat"
            }
          ]
        }
        """#.utf8)

        let source = try FixtureTermAnnotationsSource(data: data)
        let annotations = source.annotations(for: "k uses ontology")

        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].term, "ontology")
        XCTAssertEqual(annotations[0].range, TermAnnotationRange(start: 7, length: 8))
        XCTAssertEqual(annotations[0].firstSeenRef, "chat")
    }

    func testMissingAnnotationFieldDecodesAsOptionalEmptyPayload() throws {
        let payload = try JSONDecoder().decode(
            TermAnnotationsPayload.self,
            from: Data(#"{}"#.utf8)
        )

        XCTAssertTrue(payload.termAnnotations.isEmpty)
    }

    func testEmptyFixtureLeavesTextPlainAndAddsNoAnnotationChrome() {
        let text = "nothing new here"

        XCTAssertTrue(FixtureTermAnnotationsSource.empty.annotations(for: text).isEmpty)
        XCTAssertEqual(
            TermAnnotationText.segments(in: text, annotations: []),
            [TermAnnotationSegment(text: text, annotation: nil)]
        )
    }

    func testInvalidRangeFailsSoftToPlainText() {
        let text = "plain text"
        let annotation = TermAnnotation(
            term: "missing",
            range: TermAnnotationRange(start: 100, length: 7),
            definition: "not shown"
        )

        XCTAssertEqual(
            TermAnnotationText.segments(in: text, annotations: [annotation]),
            [TermAnnotationSegment(text: text, annotation: nil)]
        )
    }
}
