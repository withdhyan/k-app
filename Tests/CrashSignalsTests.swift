import XCTest
@testable import K

final class CrashSignalsTests: XCTestCase {
    func testSanitizerKeepsOnlyAllowlistedCrashAndHangFields() throws {
        let secret = "founder cached life-data secret"
        let fixture: [String: Any] = [
            "crashDiagnostics": [
                [
                    "exceptionType": "EXC_BAD_ACCESS",
                    "signal": "SIGSEGV",
                    "terminationReason": "Namespace SIGNAL, Code 11",
                    "reason": secret,
                    "diagnosticMetaData": [
                        "appVersion": secret,
                        "osVersion": secret,
                    ],
                    "callStackTree": [
                        "callStackRootFrames": [
                            [
                                "binaryName": "K",
                                "address": "0x1000",
                                "offset": 32,
                                "symbol": secret,
                                "sourceLine": secret,
                                "subFrames": [
                                    [
                                        "binaryName": "KCore",
                                        "address": "0x1004",
                                        "offset": "0x4",
                                        "userText": secret,
                                    ],
                                ],
                            ],
                        ],
                        "threadAttributed": true,
                        "diagnosticText": secret,
                    ],
                ],
            ],
            "hangDiagnostics": [
                [
                    "message": secret,
                    "callStackTree": [
                        "callStacks": [
                            [
                                "frames": [
                                    [
                                        "binaryName": "UIKitCore",
                                        "address": "0x2000",
                                        "offset": 7,
                                        "sampleCount": 9,
                                        "note": secret,
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            "cachedText": secret,
        ]

        let batch = CrashSignalSanitizer.sanitizedBatch(
            from: [fixture],
            appVersion: "1.2 (3)",
            osVersion: "iOS 18.1"
        )
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(batch), encoding: .utf8))

        XCTAssertEqual(batch.kind, "ios-crash")
        XCTAssertEqual(batch.appVersion, "1.2 (3)")
        XCTAssertEqual(batch.osVersion, "iOS 18.1")
        XCTAssertEqual(batch.payloads.count, 2)
        XCTAssertEqual(batch.payloads.first?.exceptionType, "EXC_BAD_ACCESS")
        XCTAssertEqual(batch.payloads.first?.signal, "SIGSEGV")
        XCTAssertEqual(batch.payloads.first?.terminationReason, "Namespace SIGNAL, Code 11")
        XCTAssertNotNil(batch.payloads.last?.callStackTree)
        XCTAssertTrue(encoded.contains("KCore"))
        XCTAssertTrue(encoded.contains("UIKitCore"))
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("diagnosticMetaData"))
        XCTAssertFalse(encoded.contains("sampleCount"))
        XCTAssertFalse(encoded.contains("symbol"))
    }

    func testBufferCapsPayloadsFIFO() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("buffer.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CrashSignalBufferStore(fileURL: fileURL, cap: 3)
        store.append(batch: batch(["old-1", "old-2"]))
        store.append(batch: batch(["new-1", "new-2", "new-3"]))

        XCTAssertEqual(store.loadEntries().map { $0.payload.exceptionType }, [
            "new-1",
            "new-2",
            "new-3",
        ])

        store.append(batch: batch(["new-4"]))

        XCTAssertEqual(store.loadEntries().map { $0.payload.exceptionType }, [
            "new-2",
            "new-3",
            "new-4",
        ])
    }

    func testBuildSignalRequestEncoding() async throws {
        var capturedRequest: URLRequest?
        let transport = AGUIHTTPTransport { request in
            capturedRequest = request
            return Self.response(url: try XCTUnwrap(request.url))
        }
        let client = AGUIClient(baseURL: "http://daemon.test/root", transport: transport)
        let payload = CrashSignalPayload(
            exceptionType: "EXC_CRASH",
            signal: "SIGABRT",
            terminationReason: "Namespace SIGNAL",
            callStackTree: .object([
                "callStackRootFrames": .array([
                    .object([
                        "binaryName": .string("K"),
                        "address": .string("0x3000"),
                        "offset": .number(12),
                    ]),
                ]),
            ])
        )
        let batch = CrashSignalBatch(
            payloads: [payload],
            appVersion: "1.2 (3)",
            osVersion: "iOS 18.1"
        )

        try await client.postBuildSignals(batch)

        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let payloads = try XCTUnwrap(json["payloads"] as? [[String: Any]])
        let firstPayload = try XCTUnwrap(payloads.first)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/root/api/build/signals")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(json["kind"] as? String, "ios-crash")
        XCTAssertEqual(json["appVersion"] as? String, "1.2 (3)")
        XCTAssertEqual(json["osVersion"] as? String, "iOS 18.1")
        XCTAssertEqual(firstPayload["exceptionType"] as? String, "EXC_CRASH")
    }

    private func batch(_ exceptionTypes: [String]) -> CrashSignalBatch {
        CrashSignalBatch(
            payloads: exceptionTypes.map {
                CrashSignalPayload(exceptionType: $0)
            },
            appVersion: "1.2 (3)",
            osVersion: "iOS 18.1"
        )
    }

    private static func response(url: URL, status: Int = 200, body: String = #"{"ok":true}"#) -> AGUILineResponse {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        let stream = AsyncThrowingStream<String, Error> { continuation in
            if !body.isEmpty {
                continuation.yield(body)
            }
            continuation.finish()
        }
        return AGUILineResponse(response: response, lines: stream)
    }
}
