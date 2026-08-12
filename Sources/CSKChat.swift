import Foundation

/// Finalized sovereign turn — mirrors the daemon's `event: done` payload.
struct CSKChatOutcome: Equatable, Sendable {
    let content: String
    let lane: String?
    let sensitivity: String?
    let sovereign: Bool
    let steps: Int?
    let held: Bool
    let packet: ViewPacket?
}

struct CSKChatBranch: Codable, Equatable, Sendable {
    struct ContextCapsule: Codable, Equatable, Sendable {
        var forkMessage: String?
        var entities: [ViewPacketJSONValue]?
    }

    var id: String
    var recordId: String?
    var trunkThreadId: String?
    var forkMessageId: String?
    var contextCapsule: ContextCapsule?
    var state: String?
    var createdAt: String?
    var updatedAt: String?
    var expiresAt: String?
    var readOnly: Bool?
    var verdict: String?
    var why: String?

    var isOpen: Bool {
        state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "open"
    }
}

enum CSKChatBranchVerdict: String, Codable, Sendable {
    case keep
    case discard
}

struct CSKChatBranchTranscriptTurn: Codable, Equatable, Sendable {
    var id: String
    var role: String
    var content: String
    var eventAt: String
}

enum CSKChatError: LocalizedError, Equatable {
    case invalidURL
    case httpStatus(Int)
    case invalidResponse
    case sovereignUnavailable(silenced: Bool)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "can't reach k · tailnet needed"
        case .httpStatus: return "k's brain didn't answer · retry"
        case .invalidResponse: return "k's reply came back garbled · retry"
        case .sovereignUnavailable(let silenced):
            return silenced
                ? "sovereign lane held · answered from your own memory, not a frontier"
                : "sovereign lane unavailable"
        case .stream: return "connection dropped mid-answer · retry"
        }
    }
}

/// SSE + durable branch client for the sovereign chat façade.
///
/// The daemon binds loopback + the Tailscale CGNAT range (100.64/10) only, so
/// Tailscale is the perimeter and there is no bearer token. Branch transcripts
/// remain client-owned; only the bounded fork capsule and lifecycle live on the
/// daemon.
struct CSKChat {
    static let chatPath = "/api/chat"
    static let branchForkPath = "/api/chat/fork"
    static let branchListPath = "/api/chat/branches"
    static let branchClosePath = "/api/chat/close"

    let baseURL: String
    let transport: AGUIHTTPTransport

    init(baseURL: String, transport: AGUIHTTPTransport = .live) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func send(
        message: String,
        history: [[String: String]] = [],
        branchId: String? = nil,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> CSKChatOutcome {
        var body: [String: Any] = ["message": message]
        if !history.isEmpty { body["history"] = history }
        if let branchId = Self.normalized(branchId) { body["branchId"] = branchId }
        let request = try makeRequest(
            path: Self.chatPath,
            method: "POST",
            accept: "text/event-stream",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else {
            throw CSKChatError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw CSKChatError.httpStatus(http.statusCode)
        }

        var event = ""
        var accumulated = ""
        var latestPacket: ViewPacket?
        for try await line in lineResponse.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch event {
            case "token":
                if let text = object["text"] as? String {
                    accumulated += text
                    await onToken(text)
                }
            case "packet", "view.packet", "action.packet":
                latestPacket = Self.packet(in: object) ?? Self.decodePacket(object)
            case "done":
                return CSKChatOutcome(
                    content: (object["content"] as? String) ?? accumulated,
                    lane: object["lane"] as? String,
                    sensitivity: object["sensitivity"] as? String,
                    sovereign: (object["sovereign"] as? Bool) ?? false,
                    steps: object["steps"] as? Int,
                    held: !((object["held"] as? [Any])?.isEmpty ?? true),
                    packet: Self.packet(in: object) ?? latestPacket
                )
            case "error":
                if (object["error"] as? String) == "sovereign_lane_unavailable" {
                    throw CSKChatError.sovereignUnavailable(
                        silenced: (object["silenced"] as? Bool) ?? true
                    )
                }
                throw CSKChatError.stream((object["error"] as? String) ?? "unknown")
            default:
                continue
            }
        }
        if !accumulated.isEmpty {
            return CSKChatOutcome(
                content: accumulated,
                lane: nil,
                sensitivity: nil,
                sovereign: false,
                steps: nil,
                held: false,
                packet: nil
            )
        }
        throw CSKChatError.stream("stream ended before completion")
    }

    func fork(
        trunkThreadId: String,
        forkMessageId: String,
        forkMessage: String,
        entities: [ViewPacketJSONValue] = []
    ) async throws -> CSKChatBranch {
        let body = BranchForkBody(
            trunkThreadId: trunkThreadId,
            forkMessageId: forkMessageId,
            forkMessage: forkMessage,
            entities: entities.isEmpty ? nil : entities
        )
        let request = try makeRequest(
            path: Self.branchForkPath,
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
        return try await decodeJSON(BranchEnvelope.self, from: request).branch
    }

    func listBranches(trunkThreadId: String) async throws -> [CSKChatBranch] {
        let request = try makeRequest(
            path: Self.branchListPath,
            method: "GET",
            queryItems: [URLQueryItem(name: "trunkThreadId", value: trunkThreadId)]
        )
        return try await decodeJSON(BranchListEnvelope.self, from: request).branches
    }

    func closeBranch(
        branchId: String,
        verdict: CSKChatBranchVerdict,
        why: String,
        transcript: [CSKChatBranchTranscriptTurn] = []
    ) async throws -> CSKChatBranch {
        let body = BranchCloseBody(
            branchId: branchId,
            verdict: verdict,
            why: why,
            transcript: transcript.isEmpty ? nil : transcript
        )
        let request = try makeRequest(
            path: Self.branchClosePath,
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
        return try await decodeJSON(BranchEnvelope.self, from: request).branch
    }

    private func makeRequest(
        path: String,
        method: String,
        accept: String = "application/json",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmedBase + path) else {
            throw CSKChatError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw CSKChatError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = body
        return request
    }

    private func decodeJSON<Value: Decodable>(
        _ type: Value.Type,
        from request: URLRequest
    ) async throws -> Value {
        let lineResponse = try await transport.lines(for: request)
        guard let http = lineResponse.response as? HTTPURLResponse else {
            throw CSKChatError.invalidResponse
        }
        var lines: [String] = []
        for try await line in lineResponse.lines { lines.append(line) }
        guard (200...299).contains(http.statusCode) else {
            throw CSKChatError.httpStatus(http.statusCode)
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        guard !data.isEmpty else { throw CSKChatError.invalidResponse }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CSKChatError.invalidResponse
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func packet(in object: [String: Any]) -> ViewPacket? {
        for key in ["packet", "viewPacket", "actionPacket"] {
            guard let value = object[key], let packet = decodePacket(value) else { continue }
            return packet
        }
        return nil
    }

    private static func decodePacket(_ value: Any) -> ViewPacket? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder().decode(ViewPacket.self, from: data)
    }
}

private struct BranchForkBody: Encodable {
    var trunkThreadId: String
    var forkMessageId: String
    var forkMessage: String
    var entities: [ViewPacketJSONValue]?
}

private struct BranchCloseBody: Encodable {
    var branchId: String
    var verdict: CSKChatBranchVerdict
    var why: String
    var transcript: [CSKChatBranchTranscriptTurn]?
}

private struct BranchEnvelope: Decodable {
    var branch: CSKChatBranch
}

private struct BranchListEnvelope: Decodable {
    var branches: [CSKChatBranch]
}
