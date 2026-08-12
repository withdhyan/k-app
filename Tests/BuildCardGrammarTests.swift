import XCTest
import SwiftUI
@testable import K

final class BuildCardGrammarTests: XCTestCase {
    func testSelectingARecordExpandsOnlyThatRecordAndCollapseClearsIt() {
        var selection = BuildCardSelectionState()

        selection.select("u4")
        XCTAssertEqual(selection.expandedID, "u4")

        selection.select("u5")
        XCTAssertEqual(selection.expandedID, "u5")

        selection.collapse()
        XCTAssertNil(selection.expandedID)
    }

    func testResultToneCarriesEachTerminalState() {
        XCTAssertEqual(BuildCardGrammar.tone(for: "building"), .running)
        XCTAssertEqual(BuildCardGrammar.tone(for: "verifying"), .running)
        XCTAssertEqual(BuildCardGrammar.tone(for: "completed"), .clean)
        XCTAssertEqual(BuildCardGrammar.tone(for: "completed", note: "retried once"), .notes)
        XCTAssertEqual(BuildCardGrammar.tone(for: "failed"), .failed)
        XCTAssertEqual(BuildCardGrammar.tone(for: "line-stopped"), .failed)
        XCTAssertEqual(BuildCardGrammar.tone(for: "line stop"), .failed)
    }

    // Build #26 slice A, fix 1: the running/clean dot was hardwired to white ink, so
    // it went invisible on the near-white expanded plan card. `inkOnPaper` gives it a
    // dark variant; notes/failed already carry a distinct hue and stay untouched.
    func testResultDotInksDarkOnPaperForRunningAndCleanOnly() {
        for tone in [BuildResultTone.running, .clean] {
            let onPaper = BuildCardResultDot.resolveColor(tone: tone, inkOnPaper: true)
            XCTAssertEqual(onPaper, KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity), "\(tone)")

            let onGlass = BuildCardResultDot.resolveColor(tone: tone, inkOnPaper: false)
            XCTAssertEqual(onGlass, Color.white.opacity(KStyle.primaryTextOpacity), "\(tone)")
            XCTAssertNotEqual(onPaper, onGlass, "\(tone)")
        }

        for tone in [BuildResultTone.notes, .failed] {
            let expected = tone == .notes ? KStyle.resultNotes : KStyle.inlineError
            XCTAssertEqual(BuildCardResultDot.resolveColor(tone: tone, inkOnPaper: true), expected, "\(tone)")
            XCTAssertEqual(BuildCardResultDot.resolveColor(tone: tone, inkOnPaper: false), expected, "\(tone)")
        }
    }

    // Build #26 slice B: the plan row can now sit on paper too (selected state), and its
    // segment bar reused the same near-white "building" fill + dim-white "pending" fill
    // that went invisible on paper for the result dot. Same fix, same shape: dark ink on
    // paper for those two only; done/needsYou/failed already carry a hue and stay put.
    func testSegmentBarInksDarkOnPaperForBuildingAndPendingOnly() {
        for segment in [BuildSegmentState.building, .pending] {
            let onPaper = BuildSegmentBar.resolveColor(segment: segment, inkOnPaper: true)
            let onGlass = BuildSegmentBar.resolveColor(segment: segment, inkOnPaper: false)
            XCTAssertNotEqual(onPaper, onGlass, "\(segment)")
            XCTAssertEqual(
                onPaper,
                segment == .building
                    ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
                    : KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity),
                "\(segment)"
            )
        }

        for segment in [BuildSegmentState.done, .needsYou, .failed] {
            let onPaper = BuildSegmentBar.resolveColor(segment: segment, inkOnPaper: true)
            let onGlass = BuildSegmentBar.resolveColor(segment: segment, inkOnPaper: false)
            XCTAssertEqual(onPaper, onGlass, "\(segment)")
        }
    }

    func testFailureReasonIsVisibleOnTheResultLine() throws {
        let record = try XCTUnwrap(BuildRecord(value: .object([
            "id": .string("u4"),
            "title": .string("ios build"),
            "state": .string("failed"),
            "failureReason": .string("tests stopped the lane"),
        ]), index: 0))

        let presentation = BuildCardGrammar.presentation(for: record)

        XCTAssertEqual(presentation.tone, .failed)
        XCTAssertEqual(presentation.errorLine, "tests stopped the lane")
        XCTAssertNil(presentation.noteLine)
    }

    func testNotesKeepTheirReasonLineDimAndPresent() throws {
        let record = try XCTUnwrap(BuildRecord(value: .object([
            "id": .string("u2"),
            "title": .string("retry"),
            "state": .string("completed"),
            "resultNote": .string("environmental retry"),
        ]), index: 0))

        let presentation = BuildCardGrammar.presentation(for: record)

        XCTAssertEqual(presentation.tone, .notes)
        XCTAssertEqual(presentation.noteLine, "environmental retry")
        XCTAssertNil(presentation.errorLine)
    }

    func testCleanCompletionHasNoStatusLine() throws {
        let record = try XCTUnwrap(BuildRecord(value: .object([
            "id": .string("u1"),
            "title": .string("contract"),
            "state": .string("integrated"),
            "detail": .string("green"),
        ]), index: 0))

        let presentation = BuildCardGrammar.presentation(for: record)

        XCTAssertEqual(presentation.tone, .clean)
        XCTAssertNil(presentation.stepLine)
        XCTAssertNil(presentation.noteLine)
        XCTAssertNil(presentation.errorLine)
    }
}
