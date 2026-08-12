import SwiftUI
import XCTest
@testable import K

final class BuildReportRailTests: XCTestCase {
    func testTodayResponseDecodesAdditivelyAndKeepsServerText() throws {
        let report = try decodeReport(todayResponse)

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.generatedAt, "2026-07-19T12:00:00.000Z")
        XCTAssertEqual(report.stateSentence, "1 decision has blocked the chain for 30h — everything else is flowing.")
        XCTAssertEqual(report.landed?.value.text, "2/24h")
        XCTAssertEqual(report.landed?.firstPass?.text, "1/2")
        XCTAssertEqual(report.needsYou?.value.text, "1 · 30h")
        XCTAssertEqual(report.needsYou?.oldestAge?.text, "30h")
        XCTAssertEqual(report.constraint?.text, "your decisions · 30h")
        XCTAssertEqual(report.rate?.text, "0.71/day · best 2")
        XCTAssertEqual(report.eta?.text, "4–5d")
        XCTAssertEqual(report.tokens?.text, "not measured")
        XCTAssertEqual(report.spend?.text, "Not Measured By Server")
    }

    func testPresentationHasFiveAmbientRowsAndOnlyTodayDetailRows() throws {
        let presentation = BuildReportPresentation(report: try decodeReport(todayResponse))

        XCTAssertEqual(presentation.ambientRows.map(\.label), [
            "landed", "needs you", "constraint", "rate", "eta",
        ])
        XCTAssertEqual(presentation.ambientRows.map(\.value), [
            "2/24h", "1 · 30h", "your decisions · 30h", "0.71/day · best 2", "4–5d",
        ])
        XCTAssertEqual(presentation.detailRows.map(\.label), [
            "first-pass", "oldest stuck", "tokens", "spend",
        ])
        XCTAssertEqual(presentation.detailRows.map(\.value), [
            "1/2", "30h", "not measured", "Not Measured By Server",
        ])
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("repeats"))
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("unproven"))
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("acted-on"))
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("lanes"))
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("machine"))
    }

    func testFutureDetailFieldsDecodeWithoutChangingTodayContract() throws {
        let report = try decodeReport(
            #"""
            {
              "state_sentence":"nothing needs you; verified work is landing",
              "landed":{"text":"3/24h","first_pass":{"text":"2/3"}},
              "needs_you":{"text":"0"},
              "constraint":{"text":"verification · 4h"},
              "rate":{"text":"0.43/day · best 2"},
              "repeats":{"count":2,"total":7,"text":"2/7"},
              "unproven":{"text":"1/4"},
              "acted_on":{"text":"3/5"},
              "lanes":{"text":"2/4 · verification jammed"},
              "machine":{"text":"3/8"},
              "tokens":"not measured",
              "spend":"not measured",
              "future_server_field":{"nested":true}
            }
            """#
        )
        let presentation = BuildReportPresentation(report: report)

        XCTAssertEqual(presentation.detailRows.map(\.label), [
            "first-pass", "repeats", "unproven", "acted-on", "lanes", "machine", "tokens", "spend",
        ])
        XCTAssertEqual(presentation.detailRows.map(\.value), [
            "2/3", "2/7", "1/4", "3/5", "2/4 · verification jammed", "3/8", "not measured", "not measured",
        ])
    }

    func testAbsentEtaAndCostsStaySilent() throws {
        let report = try decodeReport(
            #"""
            {
              "stateSentence":"nothing needs you; verified work is landing",
              "landed":{"text":"0/24h","firstPass":{"text":"0/0"}},
              "needsYou":{"text":"0"},
              "constraint":{"text":"building · 0h"},
              "rate":{"text":"0/day · best 0"}
            }
            """#
        )
        let presentation = BuildReportPresentation(report: report)

        XCTAssertEqual(presentation.ambientRows.map(\.label), ["landed", "needs you", "constraint", "rate"])
        XCTAssertEqual(presentation.detailRows.map(\.label), ["first-pass"])
    }

    func testObjectWithoutHumanTextNeverLeaksTemplateKeys() throws {
        let report = try decodeReport(
            #"""
            {
              "stateSentence":"nothing needs you; verified work is landing",
              "landed":{"text":"0/24h"},
              "needsYou":{"text":"0"},
              "repeats":{"count":2,"total":7},
              "machine":["busy","idle"]
            }
            """#
        )
        let presentation = BuildReportPresentation(report: report)

        XCTAssertFalse(presentation.detailRows.map(\.label).contains("repeats"))
        XCTAssertFalse(presentation.detailRows.map(\.label).contains("machine"))
        XCTAssertFalse(presentation.detailRows.map(\.value).contains { $0.contains("count:") })
    }

    func testLayoutUsesReportRailOnlyAtRegularWidthAndKeepsWorkersInline() throws {
        let report = try decodeReport(todayResponse)
        let worker = BuildWorkerRailItem(planId: "plan-a", unitId: "u1", state: "building")

        XCTAssertEqual(
            BuildReportRailLayout.placement(
                horizontalSizeClass: .regular,
                availableWidth: 1024,
                report: report
            ),
            .regularRail
        )
        XCTAssertEqual(
            BuildReportRailLayout.placement(
                horizontalSizeClass: .compact,
                availableWidth: 1024,
                report: report
            ),
            .compactSentence
        )
        XCTAssertEqual(
            BuildReportRailLayout.placement(
                horizontalSizeClass: .regular,
                availableWidth: KStyle.buildReportCompactMaxWidth,
                report: report
            ),
            .compactSentence
        )
        XCTAssertEqual(BuildReportRailLayout.workerPlacement(items: [worker]), .compactSection)
        XCTAssertEqual(BuildReportRailLayout.workerPlacement(items: []), .absent)
    }

    func testRailGeometryAndMotionMatchTheBindingMock() {
        // Founder 2026-08-05: wider sidebar (264, was 200).
        XCTAssertEqual(KStyle.buildReportRailWidth, 320)
        XCTAssertEqual(KStyle.buildReportRailGap, 48)
        XCTAssertEqual(KStyle.buildReportRailLeadingPadding, 32)
        XCTAssertEqual(KStyle.buildReportRailTopPadding, 48)
        XCTAssertEqual(KStyle.buildReportSectionSpacing, 16)
        XCTAssertEqual(KStyle.buildReportMetricSpacing, 2)
        XCTAssertEqual(KStyle.buildReportStateBottomPadding, 8)
        XCTAssertEqual(KStyle.buildReportArrivalOffset, 3)

        XCTAssertEqual(BuildReportMotionSpec.tokens.map(\.name), [.zen, .quick])
        XCTAssertEqual(BuildReportMotionSpec.tokens.map(\.duration), [1.0, 0.5])
        XCTAssertEqual(BuildReportMotionSpec.transitionNames, ["opacity-fade", "transform-translate"])
        XCTAssertEqual(
            KStyle.nativeMotionResolution(.zen, reduceMotion: false),
            .timingCurve(0.25, 0.1, 0.25, 1, duration: 1.0)
        )
        XCTAssertEqual(
            KStyle.nativeMotionResolution(.quick, reduceMotion: false),
            .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.5)
        )
        XCTAssertEqual(KStyle.nativeMotionResolution(.zen, reduceMotion: true), .none)
        XCTAssertEqual(Set(KNativeMotionName.allCases), [.quick, .zen])
    }

    func testBuildReportClientUsesTheUnprefixedServerPath() async throws {
        let recorder = BuildReportRequestRecorder(body: todayResponse)

        let report = try await AGUIClient(
            baseURL: "http://daemon.test",
            transport: recorder.transport
        ).buildReport()

        XCTAssertEqual(report.landed?.value.text, "2/24h")
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, [AGUIClient.buildReportPath])
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET"])
    }

    @MainActor
    func testBuildModelKeepsLastReportStaleOnFailedRefresh() async throws {
        let recorder = BuildReportRequestRecorder(
            responses: [
                (200, todayResponse),
                (503, #"{"ok":false,"error":"unavailable"}"#),
            ]
        )
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        await model.loadReport()
        XCTAssertEqual(model.report?.stateSentence, "1 decision has blocked the chain for 30h — everything else is flowing.")

        await model.loadReport()
        // #22 contract: a failed refresh keeps the last good report and declares it
        // stale (staleness-honesty) — it never blanks the surface.
        XCTAssertNotNil(model.report)
        XCTAssertEqual(model.report?.stateSentence, "1 decision has blocked the chain for 30h — everything else is flowing.")
        XCTAssertTrue(model.isStale)
    }

    @MainActor
    func testLiveStreamMutationRefreshesTheReport() async throws {
        let updatedResponse = todayResponse.replacingOccurrences(
            of: "1 decision has blocked the chain for 30h — everything else is flowing.",
            with: "nothing needs you; verified work is landing"
        )
        let recorder = BuildReportLiveRefreshRecorder(reportBodies: [todayResponse, updatedResponse])
        let model = BuildModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) }
        )

        model.start()
        defer {
            recorder.finishStream()
            model.stop()
        }

        try await waitUntil {
            model.report?.stateSentence == "1 decision has blocked the chain for 30h — everything else is flowing."
        }
        model.apply(.snapshot([]))
        try await waitUntil {
            model.report?.stateSentence == "nothing needs you; verified work is landing"
        }

        XCTAssertEqual(recorder.reportRequestCount, 2)
    }

    private func decodeReport(_ json: String) throws -> BuildReport {
        try JSONDecoder().decode(BuildReport.self, from: Data(json.utf8))
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition did not become true")
    }

    private var todayResponse: String {
        #"""
        {
          "ok":true,
          "schemaVersion":1,
          "generatedAt":"2026-07-19T12:00:00.000Z",
          "stateSentence":"1 decision has blocked the chain for 30h — everything else is flowing.",
          "landed":{
            "count":2,
            "windowHours":24,
            "text":"2/24h",
            "firstPass":{"count":1,"total":2,"share":0.5,"text":"1/2"}
          },
          "needsYou":{
            "count":1,
            "oldestAgeHours":30,
            "oldestAge":"30h",
            "text":"1 · 30h"
          },
          "constraint":{"station":"founder-decisions","blockedHours":30,"text":"your decisions · 30h"},
          "rate":{"windowDays":7,"landed":5,"unitsPerDay":0.71,"bestDay":2,"text":"0.71/day · best 2"},
          "eta":{"queueDepth":3,"minDays":4,"maxDays":5,"text":"4–5d"},
          "tokens":"not measured",
          "spend":"Not Measured By Server"
        }
        """#
    }
}

private final class BuildReportLiveRefreshRecorder {
    private var reportBodies: [String]
    private var streamContinuation: AsyncThrowingStream<String, Error>.Continuation?
    private(set) var reportRequestCount = 0

    init(reportBodies: [String]) {
        self.reportBodies = reportBodies
    }

    func finishStream() {
        streamContinuation?.finish()
        streamContinuation = nil
    }

    lazy var transport = AGUIHTTPTransport { request in
        let path = request.url?.path
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        if path == AGUIClient.buildReportPath {
            self.reportRequestCount += 1
            let body = self.reportBodies.isEmpty ? "" : self.reportBodies.removeFirst()
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(body)
                continuation.finish()
            }
            return AGUILineResponse(response: response, lines: stream)
        }

        let stream = AsyncThrowingStream<String, Error> { continuation in
            self.streamContinuation = continuation
        }
        return AGUILineResponse(response: response, lines: stream)
    }
}

private final class BuildReportRequestRecorder {
    private(set) var requests: [URLRequest] = []
    private var responses: [(Int, String)]

    init(body: String) {
        responses = [(200, body)]
    }

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    lazy var transport = AGUIHTTPTransport { request in
        self.requests.append(request)
        let next = self.responses.isEmpty
            ? (200, "")
            : self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.0,
            httpVersion: nil,
            headerFields: nil
        )!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            if !next.1.isEmpty {
                for line in next.1.split(separator: "\n", omittingEmptySubsequences: false) {
                    continuation.yield(String(line))
                }
            }
            continuation.finish()
        }
        return AGUILineResponse(response: response, lines: stream)
    }
}
