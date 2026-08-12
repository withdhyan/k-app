import Combine
import Foundation

enum TailnetReachabilityDecision: Equatable {
    case notChecked
    case directReachable
    case tailnetNeeded
}

struct TailnetReachabilityProbe {
    static let healthPath = "/api/health"
    static let timeout: TimeInterval = 3

    private let fetch: (URLRequest) async throws -> URLResponse

    init(fetch: @escaping (URLRequest) async throws -> URLResponse = Self.liveFetch) {
        self.fetch = fetch
    }

    func probe(baseURL: String) async -> TailnetReachabilityDecision {
        guard let url = Self.healthURL(baseURL: baseURL) else {
            return .notChecked
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeout

        do {
            _ = try await fetch(request)
            return .directReachable
        } catch is CancellationError {
            return .notChecked
        } catch {
            return .tailnetNeeded
        }
    }

    static func healthURL(baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base), components.scheme != nil else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = healthPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func liveFetch(_ request: URLRequest) async throws -> URLResponse {
        let (_, response) = try await URLSession.shared.data(for: request)
        return response
    }
}

enum TailnetReachabilityStatusLine {
    static func text(for decision: TailnetReachabilityDecision) -> String? {
        switch decision {
        case .tailnetNeeded:
            return KCopy.tailnetNeeded
        case .notChecked, .directReachable:
            return nil
        }
    }
}

@MainActor
final class TailnetReachabilityModel: ObservableObject {
    @Published private(set) var decision: TailnetReachabilityDecision = .notChecked

    private let baseURL: () -> String
    private let probe: TailnetReachabilityProbe
    private var task: Task<Void, Never>?

    init(
        baseURL: @escaping () -> String = {
            UserDefaults.standard.string(forKey: "cskBaseURL") ?? "http://127.0.0.1:3003"
        },
        probe: TailnetReachabilityProbe = TailnetReachabilityProbe()
    ) {
        self.baseURL = baseURL
        self.probe = probe
    }

    var statusLine: String? {
        TailnetReachabilityStatusLine.text(for: decision)
    }

    func refresh() {
        task?.cancel()
        if KLoadingPreview.isEnabled { return }
        task = Task { [baseURL, probe] in
            let decision = await probe.probe(baseURL: baseURL())
            guard !Task.isCancelled else { return }
            self.decision = decision
        }
    }
}
