import Foundation

/// Seed-anchored stories for the W31 thread-travel walk. The fixture resolves
/// at model init, before any branch fetch or action invocation, so every frame
/// in the walk is local, repeatable, and safe to run without a daemon.
enum W31ChatThreadFixture {
    enum State: String, Equatable, Sendable {
        case populated
        case edge
    }

    static let launchArgument = "-w31-chat-thread-fixture"
    static let stateArgument = "-w31-chat-thread-state"
    static let referenceNow = ISO8601DateFormatter.fixtureDate("2026-08-12T07:00:00Z")
    static let threadID = "w31-build-thread"

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

    static func snapshot(
        state: State,
        now: Date = referenceNow
    ) -> (messages: [Message], threads: [ChatThread]) {
        switch state {
        case .populated:
            let anchor = Message(
                id: UUID(uuidString: "71717171-7171-4171-8171-717171717171")!,
                role: .k,
                text: "trace the solar window across the tariff, roof, and battery.",
                createdAt: now.addingTimeInterval(-900)
            )
            let founderTurn = Message(
                id: UUID(uuidString: "72727272-7272-4272-8272-727272727272")!,
                role: .you,
                text: "keep the source trail attached.",
                createdAt: now.addingTimeInterval(-780)
            )
            let answer = Message(
                id: UUID(uuidString: "73737373-7373-4373-8373-737373737373")!,
                role: .k,
                text: "the trace is complete; the build gate is yours.",
                createdAt: now.addingTimeInterval(-600)
            )
            let packet = ViewPacket(
                id: "w31-build-packet",
                viewType: "chat.reply",
                text: answer.text,
                fields: [
                    "sources": .array([
                        .string("reading tariff filings · third of three"),
                        .string("grid-rates api · pulled"),
                        .string("solar-brief.pdf · read, 4 claims held"),
                    ]),
                    "refCount": .number(3),
                ],
                action: ViewPacketAction(
                    kind: "build",
                    target: "staged-unit",
                    tag: "[gate:human]",
                    id: "w31-stage-build",
                    intent: "stage_to_build",
                    args: ["unit": .string("solar-window")]
                )
            )
            let thread = ChatThread(
                id: threadID,
                forkMessageID: anchor.id.uuidString,
                title: "solar window",
                statusText: KCopy.chatReadyToExplore,
                phase: .finished,
                history: [anchor, founderTurn, answer],
                actionPacket: packet,
                createdAt: now.addingTimeInterval(-1_200),
                landedAt: now.addingTimeInterval(-600),
                updatedAt: now.addingTimeInterval(-600)
            )
            return ([anchor], [thread])

        case .edge:
            return ([], [])
        }
    }
}

private extension ISO8601DateFormatter {
    static func fixtureDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
