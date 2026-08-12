import Foundation

/// Seed-anchored rail stories for the W30 audit. The seam is opt-in and is
/// resolved before ChatModel starts any network work.
enum W30ChatRailFixture {
    enum State: String, Equatable, Sendable {
        case populated
        case aging
        case paging
        case empty
    }

    static let launchArgument = "-w30-chat-rail-fixture"
    static let stateArgument = "-w30-chat-rail-state"
    // 2026-08-12T00:00:00Z. Keep this near the audit date without reading the
    // wall clock, so the rows and aging boundary remain reproducible.
    static let referenceNow = Date(timeIntervalSince1970: 1_786_492_800)

    static var state: State? {
        state(arguments: ProcessInfo.processInfo.arguments)
    }

    static func state(arguments: [String]) -> State? {
        guard arguments.contains(launchArgument),
              let index = arguments.firstIndex(of: stateArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return State(rawValue: arguments[index + 1].lowercased())
    }

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        state(arguments: arguments) != nil
    }

    static func snapshot(state: State, now: Date = referenceNow) -> (messages: [Message], threads: [ChatThread]) {
        switch state {
        case .empty:
            return ([], [])
        case .populated:
            return ([], [
                thread(id: "completed", title: "completed thread", phase: .finished, at: now.addingTimeInterval(-100)),
                thread(id: "processing", title: "processing thread", phase: .processing, at: now.addingTimeInterval(-200)),
                needsYouThread(id: "needs-you", title: "needs you thread", at: now.addingTimeInterval(-300)),
                thread(id: "failed", title: "failed thread", phase: .failed, at: now.addingTimeInterval(-400)),
            ])
        case .aging:
            return ([], [
                thread(
                    id: "aging",
                    title: "aging completed thread",
                    phase: .finished,
                    at: now.addingTimeInterval(-100),
                    landedAt: now.addingTimeInterval(-2 * 24 * 60 * 60)
                ),
                thread(
                    id: "expired",
                    title: "expired completed thread",
                    phase: .finished,
                    at: now.addingTimeInterval(-200),
                    landedAt: now.addingTimeInterval(-4 * 24 * 60 * 60)
                ),
            ])
        case .paging:
            let threads = (1...14).map { index in
                thread(
                    id: "page0-" + String(index),
                    title: "paging thread " + String(index),
                    phase: .finished,
                    at: now.addingTimeInterval(-Double(index))
                )
            }
            return ([], threads)
        }
    }

    private static func thread(
        id: String,
        title: String,
        phase: ChatThreadPhase,
        at: Date,
        landedAt: Date? = nil
    ) -> ChatThread {
        ChatThread(
            id: id,
            forkMessageID: "w30-" + id + "-anchor",
            title: title,
            phase: phase,
            createdAt: at,
            landedAt: landedAt ?? (phase == .finished ? at : nil),
            updatedAt: at
        )
    }

    private static func needsYouThread(id: String, title: String, at: Date) -> ChatThread {
        var thread = thread(id: id, title: title, phase: .finished, at: at)
        thread.actionPacket = ViewPacket(
            id: "w30-" + id + "-packet",
            viewType: "chat.reply",
            text: "a decision is waiting",
            fields: ["threadWorthy": .bool(false)]
        )
        return thread
    }
}
