import XCTest
@testable import K

final class AdminViewTests: XCTestCase {
    @MainActor
    func testIntakeStaysInParseConfirmUntilFounderConfirms() async throws {
        let recorder = AdminRequestRecorder(responses: [
            "POST /api/admin/intake": [
                """
                {"parsed":{"title":"renew passport","type":"TimeSensitive","effort":"Quick","remindAt":"2026-07-15","dueAt":"2026-08-01"},"confirmToken":"parse-1"}
                """,
            ],
            "POST /api/admin/confirm": [
                """
                {"ok":true,"item":{"id":"admin-1","title":"renew passport and visa","type":"TimeSensitive","effort":"Quick","remindAt":"2026-07-15","dueAt":"2026-08-01","status":"open"}}
                """,
            ],
        ])
        let model = AdminModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: tempStore()
        )

        model.draft = "renew passport by aug, remind mid-july"
        await model.submitIntake()

        guard case .confirming(let parseDraft) = model.intakeState else {
            return XCTFail("expected parse-confirm state, got \(model.intakeState)")
        }
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertEqual(parseDraft.fields.map(\.key), ["title", "type", "effort", "remindAt", "dueAt"])
        XCTAssertEqual(parseDraft.confirmToken, "parse-1")

        model.updateParsedField(key: "title", value: "renew passport and visa")
        await model.confirmParsedIntake()

        XCTAssertEqual(model.records.map(\.title), ["renew passport and visa"])
        XCTAssertEqual(model.intakeState, .idle)

        let intakeRequest = try XCTUnwrap(recorder.requests.first)
        let intakeBody = try bodyObject(from: intakeRequest)
        XCTAssertEqual(intakeRequest.url?.path, "/api/admin/intake")
        XCTAssertEqual(intakeBody["text"] as? String, "renew passport by aug, remind mid-july")

        let confirmRequest = try XCTUnwrap(recorder.requests.last)
        let confirmBody = try bodyObject(from: confirmRequest)
        XCTAssertEqual(confirmRequest.url?.path, "/api/admin/confirm")
        XCTAssertEqual(confirmBody["title"] as? String, "renew passport and visa")
        XCTAssertEqual(confirmBody["type"] as? String, "TimeSensitive")
        XCTAssertEqual(confirmBody["confirmToken"] as? String, "parse-1")
    }

    func testBandishSortUsesServerSortKeys() {
        let calendar = utcCalendar()
        let records = [
            AdminItem(id: "a", title: "later", type: .regularQueue, effort: .quick, dueAt: "2026-07-08"),
            AdminItem(id: "b", title: "same remind slower", type: .regularQueue, effort: .hours, remindAt: "2026-07-01", dueAt: "2026-07-09"),
            AdminItem(id: "c", title: "same remind first due", type: .regularQueue, effort: .quick, remindAt: "2026-07-01", dueAt: "2026-07-08"),
        ]

        let sorted = AdminBandishSorter.sorted(
            records: records,
            sort: ["remindAt", "dueAt", "effort"],
            calendar: calendar
        )

        XCTAssertEqual(sorted.map(\.id), ["c", "b", "a"])
    }

    func testAdminDotCountsOnlyTimeSensitiveItemsDueToday() throws {
        let calendar = utcCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T12:00:00Z"))
        let records = [
            AdminItem(id: "due", title: "renew passport", type: .timeSensitive, effort: .quick, dueAt: "2026-07-06"),
            AdminItem(id: "tomorrow", title: "book visit", type: .timeSensitive, effort: .hour, dueAt: "2026-07-07"),
            AdminItem(id: "regular", title: "sort papers", type: .regularQueue, effort: .quick, dueAt: "2026-07-06"),
            AdminItem(id: "done", title: "closed thing", type: .timeSensitive, effort: .quick, dueAt: "2026-07-06", status: "completed"),
        ]

        XCTAssertEqual(AdminTabDotLogic.dueTodayCount(records: records, now: now, calendar: calendar), 1)
    }

    @MainActor
    func testCacheFallbackShowsSavedViewCaption() async throws {
        let store = tempStore()
        let cachedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T08:45:00Z"))
        store.save(AdminBandishResponse(records: [
            AdminItem(id: "cached", title: "cached op", type: .recurring, effort: .hour, dueAt: "2026-07-09"),
        ], sort: ["dueAt"]), syncedAt: cachedAt)
        let recorder = AdminRequestRecorder(errors: [
            "GET /api/admin/bandish": [AGUIClientError.stream("offline")],
            "GET /api/admin/items": [AGUIClientError.stream("offline")],
        ])
        let model = AdminModel(
            baseURL: "http://daemon.test",
            clientFactory: { AGUIClient(baseURL: $0, transport: recorder.transport) },
            cacheStore: store,
            calendar: utcCalendar()
        )

        await model.load()

        XCTAssertEqual(model.records.map(\.id), ["cached"])
        XCTAssertEqual(model.sort, ["dueAt"])
        XCTAssertEqual(model.offlineCaption, "backend unavailable; showing saved view")
        XCTAssertEqual(model.stalenessText, "as of 08:45")
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.connectionState.status, .offlineRetrying)
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/api/admin/bandish", "/api/admin/items"])
    }

    private func bodyObject(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func tempStore() -> AdminBandishStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("admin-\(UUID().uuidString).json")
        return AdminBandishStore(fileURL: url)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private final class AdminRequestRecorder {
    private var responses: [String: [String]]
    private var errors: [String: [Error]]
    private(set) var requests: [URLRequest] = []

    init(
        responses: [String: [String]] = [:],
        errors: [String: [Error]] = [:]
    ) {
        self.responses = responses
        self.errors = errors
    }

    var transport: AGUIHTTPTransport {
        AGUIHTTPTransport { request in
            self.requests.append(request)
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"

            if var routeErrors = self.errors[key], !routeErrors.isEmpty {
                let error = routeErrors.removeFirst()
                self.errors[key] = routeErrors
                throw error
            }

            let body: String
            if var routeResponses = self.responses[key], !routeResponses.isEmpty {
                body = routeResponses.removeFirst()
                self.responses[key] = routeResponses
            } else if request.httpMethod == "GET" {
                body = #"{"records":[],"sort":[]}"#
            } else {
                body = #"{"ok":true}"#
            }

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return AGUILineResponse(response: response, lines: Self.stream(body))
        }
    }

    private static func stream(_ body: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if !body.isEmpty {
                continuation.yield(body)
            }
            continuation.finish()
        }
    }
}
