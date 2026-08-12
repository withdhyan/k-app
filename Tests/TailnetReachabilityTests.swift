import XCTest
@testable import K

final class TailnetReachabilityTests: XCTestCase {
    func testHealthURLAppendsAPIHealthToDaemonBaseURL() {
        XCTAssertEqual(
            TailnetReachabilityProbe.healthURL(baseURL: "http://127.0.0.1:3003")?.absoluteString,
            "http://127.0.0.1:3003/api/health"
        )
        XCTAssertEqual(
            TailnetReachabilityProbe.healthURL(baseURL: " http://daemon.test/root?old=1#frag ")?.absoluteString,
            "http://daemon.test/root/api/health"
        )
        XCTAssertNil(TailnetReachabilityProbe.healthURL(baseURL: "daemon.test"))
    }

    func testProbeTreatsAnyHTTPResponseAsDirectReachable() async throws {
        var capturedRequest: URLRequest?
        let probe = TailnetReachabilityProbe { request in
            capturedRequest = request
            return HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
        }

        let decision = await probe.probe(baseURL: "http://daemon.test")

        XCTAssertEqual(decision, .directReachable)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://daemon.test/api/health")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 3)
    }

    func testProbeTreatsTransportFailureAsTailnetNeeded() async {
        let probe = TailnetReachabilityProbe { _ in
            throw URLError(.timedOut)
        }

        let decision = await probe.probe(baseURL: "http://daemon.test")

        XCTAssertEqual(decision, .tailnetNeeded)
    }

    func testTailnetStatusLineOnlyAppearsWhenNeeded() {
        XCTAssertNil(TailnetReachabilityStatusLine.text(for: .notChecked))
        XCTAssertNil(TailnetReachabilityStatusLine.text(for: .directReachable))
        XCTAssertEqual(
            TailnetReachabilityStatusLine.text(for: .tailnetNeeded),
            "daemon unreachable · tailnet needed"
        )
    }

    func testConnectionStateCanRepresentTailnetNeeded() {
        let start = Date(timeIntervalSince1970: 3_000)
        let state = KConnectionStateModel(status: .tailnetNeeded, changedAt: start)
        let presentation = state.presentation(now: start)

        XCTAssertEqual(state.status.text, "daemon unreachable · tailnet needed")
        XCTAssertEqual(presentation.word, "daemon unreachable · tailnet needed")
        XCTAssertEqual(presentation.signal, .offline)
        XCTAssertEqual(presentation.inputsDisabledReason, "tailnet needed")
    }
}
