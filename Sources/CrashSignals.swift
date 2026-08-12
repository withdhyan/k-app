import Foundation

#if canImport(MetricKit)
import MetricKit
#endif

struct CrashSignalBatch: Codable, Equatable, Sendable {
    var kind: String
    var payloads: [CrashSignalPayload]
    var appVersion: String
    var osVersion: String

    init(
        kind: String = "ios-crash",
        payloads: [CrashSignalPayload],
        appVersion: String,
        osVersion: String
    ) {
        self.kind = kind
        self.payloads = payloads
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

struct CrashSignalPayload: Codable, Equatable, Sendable {
    var exceptionType: String?
    var signal: String?
    var terminationReason: String?
    var callStackTree: ViewPacketJSONValue?

    init(
        exceptionType: String? = nil,
        signal: String? = nil,
        terminationReason: String? = nil,
        callStackTree: ViewPacketJSONValue? = nil
    ) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.terminationReason = terminationReason
        self.callStackTree = callStackTree
    }
}

enum CrashSignalSanitizer {
    private static let diagnosticKeys = ["crashDiagnostics", "hangDiagnostics"]
    private static let rootStringKeys = Set(["exceptionType", "signal", "terminationReason"])
    private static let stackStringKeys = Set(["binaryName", "address", "offset"])
    private static let stackNumberKeys = Set(["address", "offset"])
    private static let stackRootKeys = ["callStackTree"]
    private static let stackContainerKeys = Set([
        "callStackRootFrames",
        "callStacks",
        "callStackTree",
        "frames",
        "stackFrames",
        "subFrames",
    ])

    static func sanitizedBatch(
        fromDiagnosticPayloadData payloadData: [Data],
        appVersion: String,
        osVersion: String
    ) -> CrashSignalBatch {
        let dictionaries = payloadData.compactMap { data -> [String: Any]? in
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return object as? [String: Any]
        }
        return sanitizedBatch(from: dictionaries, appVersion: appVersion, osVersion: osVersion)
    }

    static func sanitizedBatch(
        from diagnosticPayloads: [[String: Any]],
        appVersion: String,
        osVersion: String
    ) -> CrashSignalBatch {
        let payloads = diagnosticPayloads.flatMap { sanitizedPayloads(from: $0) }
        return CrashSignalBatch(payloads: payloads, appVersion: appVersion, osVersion: osVersion)
    }

    static func sanitizedPayloads(from diagnosticPayload: [String: Any]) -> [CrashSignalPayload] {
        diagnosticKeys.flatMap { key in
            diagnosticDictionaries(in: diagnosticPayload[key]).compactMap { diagnostic in
                sanitizedDiagnostic(diagnostic)
            }
        }
    }

    private static func diagnosticDictionaries(in value: Any?) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary]
        }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func sanitizedDiagnostic(_ diagnostic: [String: Any]) -> CrashSignalPayload? {
        let callStackTree = sanitizedCallStackTree(in: diagnostic)
        let payload = CrashSignalPayload(
            exceptionType: rootString(in: diagnostic, key: "exceptionType"),
            signal: rootString(in: diagnostic, key: "signal"),
            terminationReason: rootString(in: diagnostic, key: "terminationReason"),
            callStackTree: callStackTree
        )

        guard payload.exceptionType != nil ||
            payload.signal != nil ||
            payload.terminationReason != nil ||
            payload.callStackTree != nil
        else {
            return nil
        }
        return payload
    }

    private static func rootString(in dictionary: [String: Any], key: String) -> String? {
        guard rootStringKeys.contains(key),
              let value = dictionary[key] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedCallStackTree(in diagnostic: [String: Any]) -> ViewPacketJSONValue? {
        for key in stackRootKeys where diagnostic[key] != nil {
            if let value = sanitizedStackValue(diagnostic[key]) {
                return value
            }
        }
        return nil
    }

    private static func sanitizedStackValue(_ value: Any?) -> ViewPacketJSONValue? {
        if let dictionary = value as? [String: Any] {
            var result: [String: ViewPacketJSONValue] = [:]
            for (key, rawValue) in dictionary {
                if let scalar = sanitizedStackScalar(rawValue, key: key) {
                    result[key] = scalar
                } else if stackContainerKeys.contains(key),
                          let nested = sanitizedStackValue(rawValue) {
                    result[key] = nested
                }
            }
            return result.isEmpty ? nil : .object(result)
        }

        if let array = value as? [Any] {
            let values = array.compactMap { sanitizedStackValue($0) }
            return values.isEmpty ? nil : .array(values)
        }

        return nil
    }

    private static func sanitizedStackScalar(_ value: Any, key: String) -> ViewPacketJSONValue? {
        if let string = value as? String, stackStringKeys.contains(key) {
            return .string(string)
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           stackNumberKeys.contains(key) {
            return .number(number.doubleValue)
        }
        return nil
    }
}

struct CrashSignalBufferEntry: Codable, Equatable, Sendable {
    var payload: CrashSignalPayload
    var appVersion: String
    var osVersion: String
}

struct CrashSignalBufferStore {
    let fileURL: URL
    let cap: Int

    init(fileURL: URL = CrashSignalBufferStore.defaultFileURL(), cap: Int = 50) {
        self.fileURL = fileURL
        self.cap = max(0, cap)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("CrashSignals", isDirectory: true)
            .appendingPathComponent("buffer.json")
    }

    func loadEntries() -> [CrashSignalBufferEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([CrashSignalBufferEntry].self, from: data)) ?? []
    }

    func append(batch: CrashSignalBatch) {
        guard !batch.payloads.isEmpty else { return }
        let newEntries = batch.payloads.map {
            CrashSignalBufferEntry(payload: $0, appVersion: batch.appVersion, osVersion: batch.osVersion)
        }
        replaceEntries(loadEntries() + newEntries)
    }

    func removeFirst(_ count: Int) {
        guard count > 0 else { return }
        replaceEntries(Array(loadEntries().dropFirst(count)))
    }

    func replaceEntries(_ entries: [CrashSignalBufferEntry]) {
        let capped = cap == 0 ? [] : Array(entries.suffix(cap))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(capped)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }

    static func batches(from entries: [CrashSignalBufferEntry]) -> [CrashSignalBatch] {
        var batches: [CrashSignalBatch] = []
        var pendingPayloads: [CrashSignalPayload] = []
        var pendingAppVersion: String?
        var pendingOSVersion: String?

        func flushPending() {
            guard let appVersion = pendingAppVersion,
                  let osVersion = pendingOSVersion,
                  !pendingPayloads.isEmpty
            else {
                return
            }
            batches.append(CrashSignalBatch(
                payloads: pendingPayloads,
                appVersion: appVersion,
                osVersion: osVersion
            ))
            pendingPayloads.removeAll()
        }

        for entry in entries {
            if pendingAppVersion != entry.appVersion || pendingOSVersion != entry.osVersion {
                flushPending()
                pendingAppVersion = entry.appVersion
                pendingOSVersion = entry.osVersion
            }
            pendingPayloads.append(entry.payload)
        }
        flushPending()

        return batches
    }
}

struct CrashSignalAppContext: Equatable, Sendable {
    var appVersion: String
    var osVersion: String

    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> CrashSignalAppContext {
        let info = bundle.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String
        let buildVersion = info[kCFBundleVersionKey as String] as? String
        let appVersion = [
            shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            buildVersion.map { "(\($0.trimmingCharacters(in: .whitespacesAndNewlines)))" },
        ]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty, value != "()" else { return nil }
                return value
            }
            .joined(separator: " ")

        return CrashSignalAppContext(
            appVersion: appVersion.isEmpty ? "unknown" : appVersion,
            osVersion: processInfo.operatingSystemVersionString
        )
    }
}

actor CrashSignalReporter {
    private let bufferStore: CrashSignalBufferStore
    private let baseURL: () -> String
    private let clientFactory: (String) -> AGUIClient
    private let appContext: () -> CrashSignalAppContext

    init(
        bufferStore: CrashSignalBufferStore = CrashSignalBufferStore(),
        baseURL: @escaping () -> String = {
            UserDefaults.standard.string(forKey: "cskBaseURL") ?? "http://127.0.0.1:3003"
        },
        clientFactory: @escaping (String) -> AGUIClient = { AGUIClient(baseURL: $0) },
        appContext: @escaping () -> CrashSignalAppContext = { CrashSignalAppContext.live() }
    ) {
        self.bufferStore = bufferStore
        self.baseURL = baseURL
        self.clientFactory = clientFactory
        self.appContext = appContext
    }

    func receiveDiagnosticPayloadData(_ payloadData: [Data]) async {
        let context = appContext()
        let batch = CrashSignalSanitizer.sanitizedBatch(
            fromDiagnosticPayloadData: payloadData,
            appVersion: context.appVersion,
            osVersion: context.osVersion
        )
        if !batch.payloads.isEmpty {
            bufferStore.append(batch: batch)
        }
        await flush()
    }

    func flush() async {
        let entries = bufferStore.loadEntries()
        guard !entries.isEmpty else { return }

        let client = clientFactory(baseURL())
        var sentPayloadCount = 0
        for batch in CrashSignalBufferStore.batches(from: entries) {
            do {
                try await client.postBuildSignals(batch)
                sentPayloadCount += batch.payloads.count
            } catch {
                // TODO(R8.5-daemon): Keep buffering until cs-k implements POST /api/build/signals.
                break
            }
        }

        if sentPayloadCount > 0 {
            bufferStore.removeFirst(sentPayloadCount)
        }
    }
}

final class CrashSignals: NSObject {
    static let shared = CrashSignals()

    private let reporter: CrashSignalReporter
    private var isRegistered = false

    init(reporter: CrashSignalReporter = CrashSignalReporter()) {
        self.reporter = reporter
        super.init()
    }

    func register() {
#if targetEnvironment(simulator)
        return
#else
        guard !isRegistered else { return }
        isRegistered = true
#if canImport(MetricKit)
        MXMetricManager.shared.add(self)
        Task { await reporter.flush() }
#endif
#endif
    }
}

#if canImport(MetricKit)
extension CrashSignals: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let data = payloads.map { $0.jsonRepresentation() }
        Task { await reporter.receiveDiagnosticPayloadData(data) }
    }
}
#endif
