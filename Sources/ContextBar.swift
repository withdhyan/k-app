import Foundation

struct ChatAttachmentMetadata: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var bookmarkData: Data
    var selectedAt: Date
    var securityScopedAccessGranted: Bool

    init(
        id: UUID = UUID(),
        filename: String,
        bookmarkData: Data,
        selectedAt: Date = Date(),
        securityScopedAccessGranted: Bool
    ) {
        self.id = id
        self.filename = filename
        self.bookmarkData = bookmarkData
        self.selectedAt = selectedAt
        self.securityScopedAccessGranted = securityScopedAccessGranted
    }

    static func retaining(_ url: URL, now: Date = Date()) throws -> ChatAttachmentMetadata {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: [.nameKey],
            relativeTo: nil
        )
        return ChatAttachmentMetadata(
            filename: url.lastPathComponent,
            bookmarkData: bookmark,
            selectedAt: now,
            securityScopedAccessGranted: accessed
        )
    }
}

struct ChatAttachmentStore {
    private let key: String
    private let defaults: UserDefaults

    init(
        key: String = "chat.attachmentSelection.v1",
        defaults: UserDefaults = .standard
    ) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> ChatAttachmentMetadata? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ChatAttachmentMetadata.self, from: data)
    }

    func save(_ attachment: ChatAttachmentMetadata?) {
        guard let attachment,
              let data = try? JSONEncoder().encode(attachment)
        else {
            clear()
            return
        }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

enum ChatComposerTarget: Equatable, Sendable {
    case trunk
    case thread(id: String, title: String)

    var branchID: String? {
        if case .thread(let id, _) = self { return id }
        return nil
    }

    var shortText: String {
        switch self {
        case .trunk:
            return KCopy.chatTrunkTarget
        case .thread(_, let title):
            let line = title
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "thread · \((line?.isEmpty == false ? line! : KCopy.chatReadyToExplore).lowercased())"
        }
    }
}

struct ChatContextSnapshot: Equatable, Sendable {
    var targetText: String
    var refsText: String?
    var sensesText: String?
    var selfText: String?
    var attachmentText: String?

    var contentID: String {
        [targetText, refsText, sensesText, selfText, attachmentText]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var summaryItems: [String] {
        [targetText, refsText, sensesText, selfText, attachmentText].compactMap { $0 }
    }

    var panelRows: [(label: String, value: String)] {
        [
            ("target", targetText),
            ("refs", refsText ?? KCopy.chatNoRefs),
            ("senses", sensesText ?? KCopy.chatNoSenses),
            ("self", selfText ?? KCopy.chatNoSelfReceipt),
        ]
    }
}

enum ChatContextComposer {
    static func snapshot(
        target: ChatComposerTarget,
        messages: [Message],
        attachment: ChatAttachmentMetadata?
    ) -> ChatContextSnapshot {
        let packet = messages.reversed().compactMap(\.packet).first
        let refsText = refs(in: packet)
        let sensesText = firstValue(
            in: packet,
            fieldKeys: ["senses", "senseContext", "sense_context"],
            provenanceKeys: ["senses"]
        )
        let selfText = firstValue(
            in: packet,
            fieldKeys: ["self", "selfModel", "self_model", "valuesVersion", "values_version"],
            provenanceKeys: ["self", "selfModel", "valuesVersion"]
        )
        return ChatContextSnapshot(
            targetText: target.shortText,
            refsText: refsText,
            sensesText: sensesText?.lowercased(),
            selfText: selfText?.lowercased(),
            attachmentText: attachment.map { KCopy.chatAttachmentSelected($0.filename) }
        )
    }

    private static func refs(in packet: ViewPacket?) -> String? {
        guard let packet else { return nil }
        let evidenceCount = max(packet.evidence?.count ?? 0, packet.evidencePreviews.count)
        if evidenceCount > 0 { return "\(evidenceCount) refs" }
        return firstValue(
            in: packet,
            fieldKeys: ["refs", "references"],
            provenanceKeys: ["refs", "references"]
        )?.lowercased()
    }

    private static func firstValue(
        in packet: ViewPacket?,
        fieldKeys: [String],
        provenanceKeys: [String]
    ) -> String? {
        guard let packet else { return nil }
        for key in fieldKeys {
            if let value = normalized(packet.fields?[key]?.description) { return value }
        }
        for key in provenanceKeys {
            if let value = normalized(packet.provenance[key]?.description) { return value }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}
