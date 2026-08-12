import Foundation

struct BuildNeedsYouRow: Identifiable, Equatable, Sendable {
    let id: String
    let planID: String?
    let planTitle: String?
    let kind: String?
    let title: String
    let timeAgo: String
    let classWord: String
    let receipt: String?
    let stuckAt: Date?

    var severityRank: Int {
        KCopy.buildCardSeverityRank(for: kind)
    }

    var line: String {
        [timeAgo, title, classWord]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " · ")
    }

    /// A plan name is useful context; its payload slug is not. When the wire does
    /// not carry a human title, the existing plan nickname distills the slug without
    /// exposing the date/sequence prefix.
    var planDisplayTitle: String? {
        guard planID != nil || planTitle != nil else { return nil }
        return BuildPlanRow.nickname(planId: planID, title: planTitle).lowercased()
    }
}

/// The one bulk act on the needs-you queue is intentionally modelled as data. The
/// view only renders this state through the existing glass, mono-caption, and
/// KActRow primitives; it never re-composes the decision rules.
struct BuildApproveAllKindSummary: Identifiable, Equatable, Sendable {
    let id: String
    let kind: String
    let label: String
    let count: Int
    let lean: String

    var countLine: String {
        KCopy.buildApproveAllKindLine(count: count, kind: kind)
    }
}

struct BuildApproveAllSummary: Equatable, Sendable {
    let kinds: [BuildApproveAllKindSummary]
    let hardestStakes: String?
    let answerableCount: Int
    let skippedCount: Int

    init(cards: [BuildCard]) {
        let answerable = cards.filter(\.isBulkAnswerable)
        answerableCount = answerable.count
        skippedCount = max(0, cards.count - answerable.count)

        var grouped: [String: (count: Int, labels: [String])] = [:]
        for card in answerable {
            let kind = card.kindLabel
            let option = card.bulkRecommendationOption
            let label = option?.label.lowercased() ?? card.recommendation?.lowercased() ?? ""
            if var existing = grouped[kind] {
                existing.count += 1
                if !label.isEmpty, !existing.labels.contains(label) {
                    existing.labels.append(label)
                }
                grouped[kind] = existing
            } else {
                grouped[kind] = (
                    count: 1,
                    labels: label.isEmpty ? [] : [label]
                )
            }
        }

        kinds = grouped
            .map { kind, value in
                BuildApproveAllKindSummary(
                    id: kind,
                    kind: kind,
                    label: KCopy.buildCardVoice(kind: kind),
                    count: value.count,
                    lean: value.labels.isEmpty
                        ? "k's lean"
                        : "k leans \(value.labels.joined(separator: " · "))"
                )
            }
            .sorted { lhs, rhs in
                let leftRank = KCopy.buildCardSeverityRank(for: lhs.kind)
                let rightRank = KCopy.buildCardSeverityRank(for: rhs.kind)
                return leftRank == rightRank ? lhs.kind < rhs.kind : leftRank < rightRank
            }

        hardestStakes = cards
            .sorted { lhs, rhs in
                let leftRank = KCopy.buildCardSeverityRank(for: lhs.kind)
                let rightRank = KCopy.buildCardSeverityRank(for: rhs.kind)
                return leftRank == rightRank ? lhs.id < rhs.id : leftRank < rightRank
            }
            .compactMap { card in
                let stakes = card.stakes ?? card.brief?.stakes
                let trimmed = stakes?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .first
    }

    var countLine: String {
        kinds.map(\.countLine).joined(separator: " · ")
    }
}

struct BuildApproveAllDisclosure: Equatable, Sendable {
    let cards: [BuildCard]
    let summary: BuildApproveAllSummary

    init(cards: [BuildCard]) {
        self.cards = cards
        summary = BuildApproveAllSummary(cards: cards)
    }
}

struct BuildApproveAllProgress: Equatable, Sendable {
    let answered: Int
    let total: Int
    let skipped: Int
    let failed: Int
    let currentCardID: String?

    var line: String {
        KCopy.buildApproveAllProgress(
            answered: answered,
            total: total,
            skipped: skipped,
            failed: failed
        )
    }
}

struct BuildApproveAllResult: Equatable, Sendable {
    let answered: Int
    let skipped: Int
    let failed: Int

    var line: String {
        KCopy.buildApproveAllResult(answered: answered, skipped: skipped, failed: failed)
    }
}

enum BuildApproveAllState: Equatable, Sendable {
    case idle
    case disclosure(BuildApproveAllDisclosure)
    case running(BuildApproveAllProgress)
    case finished(BuildApproveAllResult)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

enum BuildNeedsYouFixtureMode: String, Equatable, Sendable {
    case mixed
    case allClear = "all-clear"
    case failure
}

/// Audit-only needs-you data. It is deliberately local and deterministic: the
/// production path still uses the daemon snapshot and the existing answer route.
enum BuildNeedsYouFixture {
    static let launchArgument = "-ui36-needsyou-fixture"
    static let referenceNow = Date(timeIntervalSince1970: 1_786_353_600) // 2026-08-10 09:20 UTC
    static let answerText = "founder: approve-all (k's lean) from device"
    static let failureCardID = "ui36-failure-card"
    static let answerDelayNanoseconds: UInt64 = 300_000_000

    static func mode(from arguments: [String] = ProcessInfo.processInfo.arguments) -> BuildNeedsYouFixtureMode? {
        for (index, argument) in arguments.enumerated() {
            if argument == launchArgument {
                if arguments.indices.contains(index + 1),
                   let mode = BuildNeedsYouFixtureMode(rawValue: arguments[index + 1]) {
                    return mode
                }
                return .mixed
            }
            if argument.hasPrefix(launchArgument + "=") {
                return BuildNeedsYouFixtureMode(
                    rawValue: String(argument.dropFirst((launchArgument + "=").count))
                ) ?? .mixed
            }
        }
        return nil
    }

    static func packets(for mode: BuildNeedsYouFixtureMode) -> [ViewPacket] {
        switch mode {
        case .mixed:
            return mixedCards.map(\.packet)
        case .allClear:
            return []
        case .failure:
            return [failureCard.packet]
        }
    }

    private static let mixedCards: [BuildCard] = [
        card(
            id: "ui36-protected-1",
            kind: "safety-floor",
            title: "safety floor hold",
            optionID: "keep-floor",
            optionLabel: "keep the floor",
            status: "raised",
            stakes: "hard to undo after integration"
        ),
        card(
            id: "ui36-protected-2",
            kind: "safety-floor",
            title: "safety floor review",
            optionID: "keep-floor",
            optionLabel: "keep the floor",
            status: "notified",
            stakes: "hard to undo after integration"
        ),
        card(
            id: "ui36-protected-3",
            kind: "safety-floor",
            title: "safety floor boundary",
            optionID: "keep-floor",
            optionLabel: "keep the floor",
            status: "re-raised",
            stakes: "hard to undo after integration"
        ),
        card(
            id: "ui36-plan-start",
            kind: "plan-approval",
            title: "plan approval",
            optionID: "start-plan",
            optionLabel: "start the plan",
            status: "raised",
            stakes: "reversible · silence keeps the lane staged"
        ),
        card(
            id: "ui36-setup-1",
            kind: "infra",
            title: "setup hold",
            optionID: "continue-setup",
            optionLabel: "continue setup",
            status: "raised",
            stakes: "reversible · silence keeps the lane waiting"
        ),
        card(
            id: "ui36-setup-2",
            kind: "infra",
            title: "environment choice",
            optionID: "continue-setup",
            optionLabel: "continue setup",
            status: "notified",
            stakes: "reversible · silence keeps the lane waiting"
        ),
        card(
            id: "ui36-checks",
            kind: "line-stop",
            title: "verification gate failed",
            optionID: "inspect-checks",
            optionLabel: "inspect the checks",
            status: "raised",
            stakes: "reversible · silence keeps the lane stopped"
        ),
        card(
            id: "ui36-queued",
            kind: "infra",
            title: "queued setup",
            optionID: "continue-setup",
            optionLabel: "continue setup",
            status: "queued",
            stakes: "reversible · waiting for its turn"
        ),
        card(
            id: "ui36-no-recommendation",
            kind: "shaping",
            title: "shaping question",
            optionID: nil,
            optionLabel: nil,
            status: "raised",
            stakes: "reversible · silence keeps the question open"
        ),
    ]

    private static let failureCard = card(
        id: failureCardID,
        kind: "infra",
        title: "setup answer failed",
        optionID: "continue-setup",
        optionLabel: "continue setup",
        status: "raised",
        stakes: "reversible · silence keeps the lane waiting"
    )

    private static func card(
        id: String,
        kind: String,
        title: String,
        optionID: String?,
        optionLabel: String?,
        status: String,
        stakes: String
    ) -> BuildCard {
        let options = optionID.map {
            [BuildCardOption(
                id: $0,
                label: optionLabel ?? $0,
                consequence: "the lane follows k's lean."
            )]
        } ?? []
        return BuildCard(
            id: id,
            kind: kind,
            planId: "ui36-needs-you",
            title: title,
            body: "fixture decision",
            what: "needs you decisions",
            stakes: stakes,
            options: options,
            recommendation: optionID,
            status: status,
            raisedAt: "2026-08-10T00:00:00Z"
        )
    }
}

/// Deterministic, local-only BUILD walk data. The audit surface needs the same
/// plans, branch groups, and unit biography on every run; selecting this seed
/// bypasses both the cached factory snapshot and the daemon stream. The cards
/// deliberately reuse the ui36 needs-you fixture so the walk has a real primary
/// proposal. The needs-you working set belongs to its named fixture route.
/// Doctrine: staleness-honesty, recognition-over-recall, silence-default.
enum BuildAuditFixture {
    static let launchArgument = "-builddemo"
    static let alternateLaunchArgument = "-ui67-build-fixture"

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument) || arguments.contains(alternateLaunchArgument)
    }

    // The sidebar is a seven-row replacement window, so the audit seed must
    // contain a real parked/archive tail rather than only the five active plans.
    // The first two archive packets are the held-external and failed active rows;
    // the remaining fourteen are the stale parked tail. Keep the newest "stage
    // the next pass" packet last because BuildModel's mission summary reads the
    // final status packet.
    static let packets: [ViewPacket] = [kRecordPacket, kLinePacket]
        + BuildNeedsYouFixture.packets(for: .mixed)
        + statusPackets.dropLast()
        + archivePackets
        + [statusPackets[statusPackets.count - 1]]

    /// A record-backed K line keeps the walk on the shared BuildStreamLineView
    /// path while still carrying a real plan identity for the branch seam.
    private static let kRecordPacket = statusPacket(
        id: "plan-bio-workout-archive",
        title: "bio workout archive",
        state: "building",
        detail: "the K reply carries the same receipt grammar as chat.",
        units: [
            unit(
                id: "build-demo-k-unit",
                title: "carry the receipt",
                state: "building",
                updatedAt: "2026-08-12T07:00:00Z",
                planId: "plan-bio-workout-archive"
            ),
        ],
        history: [],
        receiptFields: [
            "soulVersion": .string("factory report"),
            "refCount": .number(3),
        ]
    )

    /// The build walk's K turn mirrors the v44 mock: a real build packet with
    /// the shared receipt fields, so the verb drawer is exercised end to end.
    private static let kLinePacket = ViewPacket(
        id: "build-demo-k-line",
        viewType: "build.reply",
        text: "nowhere · an ownership gap. this deserves a branch.",
        fields: [
            "soulVersion": .string("factory report"),
            "refCount": .number(3),
        ],
        provenance: ["surface": .string("build")],
        frontierExcluded: true
    )

    private static let statusPackets: [ViewPacket] = [
        statusPacket(
            id: "build-demo-plan-rig",
            title: "build the walk rig",
            state: "building",
            detail: "the selected plan stays visible while its units move through the factory.",
            units: [
                unit(id: "build-demo-unit-seed", title: "seed the walk", state: "integrated", updatedAt: "2026-08-10T07:00:00Z"),
                unit(id: "build-demo-unit-rail", title: "hold the rail", state: "building", currentStep: "assembling the right rail", updatedAt: "2026-08-10T07:04:00Z"),
                unit(id: "build-demo-unit-capture", title: "name the captures", state: "queued", updatedAt: "2026-08-10T07:05:00Z"),
            ],
            history: [
                record(id: "build-demo-history-rig", title: "fixture seeded", state: "integrated", age: "4m ago"),
                record(id: "build-demo-history-rail", title: "rail is assembling", state: "building", age: "now"),
            ]
        ),
        statusPacket(
            id: "build-demo-plan-attention",
            title: "keep the attention lane",
            state: "held",
            detail: "one human gate keeps this lane from moving on its own.",
            units: [
                unit(id: "build-demo-unit-gate", title: "answer the gate", state: "held", holdReason: "waiting for your call", updatedAt: "2026-08-10T06:58:00Z"),
                unit(id: "build-demo-unit-proof", title: "carry the proof", state: "integrated", updatedAt: "2026-08-10T06:40:00Z"),
            ],
            history: [
                record(id: "build-demo-history-gate", title: "human gate raised", state: "held", age: "8m ago"),
            ]
        ),
        statusPacket(
            id: "build-demo-plan-landed",
            title: "land the quiet slice",
            state: "integrated",
            detail: "the small slice landed with its verification record attached.",
            units: [
                unit(id: "build-demo-unit-landed-a", title: "make the slice", state: "integrated", updatedAt: "2026-08-10T06:20:00Z"),
                unit(id: "build-demo-unit-landed-b", title: "verify the slice", state: "integrated", updatedAt: "2026-08-10T06:30:00Z"),
            ],
            history: [
                record(id: "build-demo-history-landed", title: "slice landed", state: "integrated", age: "34m ago"),
            ]
        ),
        statusPacket(
            id: "build-demo-plan-next",
            title: "stage the next pass",
            state: "planned",
            detail: "the next pass is named but has not started.",
            units: [
                unit(id: "build-demo-unit-next", title: "start the next pass", state: "planned", updatedAt: "2026-08-10T06:00:00Z"),
            ],
            history: []
        ),
    ]

    private static let archivePackets: [ViewPacket] = {
        let titles = [
            "lab ingest apply", "answer the proof gate", "holon landing",
            "retro capture matrix", "iphone compact pass", "meal photo backfill",
            "values card sweep", "dossier polish", "nav dot audit", "mind depth pass",
            "chat archive header", "capacity drawer", "suppressed nudges",
            "entity dossier v2", "cadence rest strip", "holon film scrub",
        ]
        return titles.enumerated().map { index, title in
            let state = index == 0 ? "held-external" : (index == 1 ? "failed" : "stale")
            let unitStates: [String]
            switch index {
            case 0: unitStates = ["integrated", "held-external"]
            case 1: unitStates = ["integrated", "failed"]
            case 2: unitStates = ["integrated", "queued", "queued"]
            case 3, 6, 10, 13: unitStates = ["integrated", "queued"]
            case 8: unitStates = ["integrated", "integrated"]
            default: unitStates = ["queued", "queued"]
            }
            return statusPacket(
                id: "build-demo-archive-\(index)",
                title: title,
                state: state,
                detail: "parked archive fixture",
                units: unitStates.enumerated().map { unitIndex, unitState in
                    unit(
                        id: "build-demo-archive-unit-\(index)-\(unitIndex)",
                        title: title,
                        state: unitState,
                        updatedAt: "2026-08-09T07:00:00Z"
                    )
                },
                history: [],
                receiptFields: ["sidebarOnly": .bool(true)]
            )
        }
    }()

    private static func statusPacket(
        id: String,
        title: String,
        state: String,
        detail: String,
        units: [ViewPacketJSONValue],
        history: [ViewPacketJSONValue],
        receiptFields: [String: ViewPacketJSONValue] = [:]
    ) -> ViewPacket {
        let planID = id
        return ViewPacket(
            id: "build-status-\(id)",
            viewType: "build.status",
            text: title,
            fields: [
                "plan": .object([
                    "id": .string(planID),
                    "title": .string(title),
                    "state": .string(state),
                    "detail": .string(detail),
                ]),
                "title": .string(title),
                "units": .array(units),
                "history": .array(history),
                "updatedAt": .string("2026-08-10T07:05:00Z"),
            ].merging(receiptFields) { current, _ in current },
            provenance: [
                "surface": .string("build"),
                "lane": .string("audit-fixture"),
            ],
            frontierExcluded: true
        )
    }

    private static func unit(
        id: String,
        title: String,
        state: String,
        currentStep: String? = nil,
        holdReason: String? = nil,
        updatedAt: String,
        planId: String? = nil
    ) -> ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [
            "id": .string(id),
            "unitId": .string(id),
            "title": .string(title),
            "state": .string(state),
            "updatedAt": .string(updatedAt),
            "stateHistory": .array([.string(state)]),
        ]
        if let planId { object["planId"] = .string(planId) }
        if let currentStep { object["currentStep"] = .string(currentStep) }
        if let holdReason { object["holdReason"] = .string(holdReason) }
        return .object(object)
    }

    private static func record(
        id: String,
        title: String,
        state: String,
        age: String
    ) -> ViewPacketJSONValue {
        .object([
            "id": .string(id),
            "title": .string(title),
            "state": .string(state),
            "age": .string(age),
        ])
    }
}

struct BuildNeedsYouGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let rows: [BuildNeedsYouRow]
}

struct BuildNeedsYouFold: Equatable, Sendable {
    let visibleRows: [BuildNeedsYouRow]
    let quieterRows: [BuildNeedsYouRow]

    var quieterCount: Int { quieterRows.count }
}

enum BuildNeedsYouList {
    // Critical severity owns the first read; age breaks ties inside each severity.
    // This keeps a safety floor or line stop from being buried by an older quiet hold.
    static func ordered(_ rows: [BuildNeedsYouRow]) -> [BuildNeedsYouRow] {
        rows.sorted { lhs, rhs in
            if lhs.severityRank != rhs.severityRank {
                return lhs.severityRank < rhs.severityRank
            }
            switch (lhs.stuckAt, rhs.stuckAt) {
            case let (left?, right?):
                if left != right { return left < right }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.id < rhs.id
        }
    }

    static func fold(
        _ rows: [BuildNeedsYouRow],
        visibleLimit: Int = KStyle.buildNeedsYouVisibleRowLimit
    ) -> BuildNeedsYouFold {
        let orderedRows = ordered(rows)
        let limit = max(0, visibleLimit)
        return BuildNeedsYouFold(
            visibleRows: Array(orderedRows.prefix(limit)),
            quieterRows: Array(orderedRows.dropFirst(limit))
        )
    }

    static func groups(_ rows: [BuildNeedsYouRow]) -> [BuildNeedsYouGroup] {
        let orderedRows = ordered(rows)
        guard orderedRows.count > 10 else {
            return orderedRows.isEmpty
                ? []
                : [BuildNeedsYouGroup(id: "all", title: nil, rows: orderedRows)]
        }

        var order: [String] = []
        var grouped: [String: [BuildNeedsYouRow]] = [:]
        for row in orderedRows {
            let key = row.planID ?? "unassigned"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.map { key in
            let rows = grouped[key] ?? []
            return BuildNeedsYouGroup(
                id: key,
                title: rows.first?.planDisplayTitle ?? (key == "unassigned" ? "unassigned" : BuildPlanRow.nickname(planId: key, title: nil)),
                rows: rows
            )
        }
    }

    static func row(
        id: String,
        planID: String? = nil,
        planTitle: String? = nil,
        title: String? = nil,
        raisedAt: String?,
        status: String,
        kind: String? = nil,
        receipt: String? = nil,
        now: Date = Date()
    ) -> BuildNeedsYouRow {
        let parsed = parseDate(raisedAt)
        let displayTitle = normalized(title)
            ?? normalized(planTitle)
            ?? shortSlug(planID)
            ?? "plan"
        return BuildNeedsYouRow(
            id: id,
            planID: normalized(planID),
            planTitle: normalized(planTitle),
            kind: normalized(kind),
            title: KCopy.buildCardTitle(kind: kind, rawTitle: displayTitle),
            timeAgo: timeAgo(raisedAt, date: parsed, now: now),
            classWord: classWord(for: status),
            receipt: receipt,
            stuckAt: parsed
        )
    }

    private static func classWord(for status: String) -> String {
        let normalized = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if normalized.contains("block") { return "blocked" }
        if normalized.contains("wait") || normalized.contains("decision") || normalized.contains("review") {
            return "awaiting"
        }
        if normalized.contains("hold") || normalized.contains("pause") { return "held" }
        if normalized == "answered" || normalized == "completed" || normalized == "complete" {
            return "answered"
        }
        return "awaiting"
    }

    private static func timeAgo(_ raw: String?, date: Date?, now: Date) -> String {
        if let date {
            let seconds = max(0, now.timeIntervalSince(date))
            if seconds < 60 { return "now" }
            if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
            if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
            return "\(Int(seconds / 86_400))d ago"
        }
        return "now"
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = normalized(raw) else { return nil }
        if let value = Double(raw) { return Date(timeIntervalSince1970: value) }
        let formatter = ISO8601DateFormatter()
        for candidate in [raw, raw.uppercased()] {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: candidate) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: candidate) { return date }
        }
        return nil
    }

    private static func shortSlug(_ value: String?) -> String? {
        guard let value = normalized(value) else { return nil }
        return BuildPlanRow.nickname(planId: value, title: nil)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

// The report-first BUILD surface (v4 mock: "build-k — v4 base, trunk-and-branch chat
// added on"). The tab leads with the factory REPORT — a row per plan, each carrying a
// segment bar mapped from its units' states — never with raw decision-card faces.
//
// This file is the pure, testable model behind that surface: unit-state → segment
// classification, plan-row assembly, report-first ordering, the parked summary line, and
// the branch/changelog rail. The SwiftUI layer lives in BuildView.swift and renders these.

/// One unit's contribution to a plan's segment bar. The four classes map to the mock's
/// pill colors: done → sage, building → white (breathing), needsYou → amber (breathing),
/// pending → dim.
enum BuildSegmentState: String, Equatable, CaseIterable, Sendable {
    case done
    case building
    case needsYou
    case failed
    case pending

    /// Maps a raw unit/lane state string to a segment class. Attention wins over motion
    /// wins over completion: a held unit reads as needs-you even if it also looks active.
    static func from(unitState: String?) -> BuildSegmentState {
        let normalized = (unitState ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        guard !normalized.isEmpty else { return .pending }
        if failedStates.contains(normalized) { return .failed }
        if needsYouStates.contains(normalized) { return .needsYou }
        if doneStates.contains(normalized) { return .done }
        if buildingStates.contains(normalized) { return .building }
        return .pending
    }

    private static let failedStates: Set<String> = [
        "failed", "failed-closed", "red", "error", "errored", "quarantined",
        "cancelled", "abandoned", "rejected",
    ]
    private static let needsYouStates: Set<String> = [
        "held", "blocked", "needs-decision", "needs-you", "needs-founder",
        "waiting", "awaiting", "paused", "review-pending", "gate-human",
    ]
    private static let doneStates: Set<String> = [
        "integrated", "complete", "completed", "done", "green", "verified",
        "deployed", "delivered", "landed", "passed", "merged", "shipped",
    ]
    private static let buildingStates: Set<String> = [
        "building", "verifying", "integrating", "running", "processing",
        "deploying", "recovering", "reviewing", "planning",
    ]
}

/// A single plan's report row: a nickname, its per-unit segment bar, and a done/total
/// fraction. Ordering priority puts plans that need the founder first.
struct BuildPlanRow: Identifiable, Equatable, Sendable {
    var id: String
    var nickname: String
    var segments: [BuildSegmentState]
    var doneCount: Int
    var totalCount: Int
    var buildingUnitLabel: String?

    var fraction: String { "\(doneCount)/\(totalCount)" }
    var hasNeedsYou: Bool { needsYouCount > 0 }
    var hasBuilding: Bool { segments.contains(.building) }
    var needsYouCount: Int { segments.filter { $0 == .needsYou }.count }

    /// 0 = needs the founder, 1 = building, 2 = quiet. Lower sorts first (report-first).
    var priorityRank: Int {
        if hasNeedsYou { return 0 }
        if hasBuilding { return 1 }
        return 2
    }

    init(
        id: String,
        nickname: String,
        segments: [BuildSegmentState],
        buildingUnitLabel: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.segments = segments
        doneCount = segments.filter { $0 == .done }.count
        totalCount = segments.count
        self.buildingUnitLabel = buildingUnitLabel
    }

    init(summary: BuildStatusSummary) {
        let segments = summary.units.map { BuildSegmentState.from(unitState: $0.state) }
        let firstBuilding = zip(summary.units, segments).first { $0.1 == .building }?.0
        self.init(
            id: summary.planId ?? summary.title,
            nickname: BuildPlanRow.nickname(planId: summary.planId, title: summary.title),
            segments: segments,
            buildingUnitLabel: firstBuilding?.title.lowercased()
        )
    }

    /// A short, human nickname for a plan — the mock leads each row with a slug, not a
    /// path or a machine id. Prefers a slug distilled from the title, then the plan id.
    static func nickname(planId: String?, title: String?) -> String {
        if let tail = slugTail(title) { return tail }
        if let tail = slugTail(planId) { return tail }
        let fallback = (title ?? planId ?? "plan")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return fallback.isEmpty ? "plan" : fallback
    }

    private static let typeWords: Set<String> = [
        "feat", "fix", "chore", "docs", "refactor", "test", "perf",
        "build", "ci", "style", "revert",
    ]

    /// Strips a leading `plan-` marker, date/sequence numerics, and one conventional
    /// commit-type word from a hyphenated slug, leaving the descriptive tail. A spaced
    /// human title is lowercased and keeps its words, minus a leading "feat:/fix:"-style
    /// commit prefix (see spacedTail).
    private static func slugTail(_ raw: String?) -> String? {
        guard var slug = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !slug.isEmpty else { return nil }
        for prefix in ["plan-", "plan/", "plan "] where slug.hasPrefix(prefix) {
            slug = String(slug.dropFirst(prefix.count))
        }
        guard !slug.contains(" ") else { return spacedTail(slug) }

        var tokens = slug.split(separator: "-").map(String.init)
        while let first = tokens.first, first.allSatisfy(\.isNumber), tokens.count > 1 {
            tokens.removeFirst()
        }
        if let first = tokens.first, typeWords.contains(first), tokens.count > 1 {
            tokens.removeFirst()
        }
        let tail = tokens.joined(separator: "-")
        return tail.isEmpty ? nil : tail
    }

    /// A spaced human title keeps its words, but a leading conventional-commit type
    /// prefix ("feat:", "fix:", …) is pipeline vocabulary — stripped so the founder
    /// surface reads "generative blocks labor-0", never "feat: generative blocks labor-0".
    /// The trailing colon is required: it is the unambiguous commit marker, so a prose
    /// title that merely opens with a type word ("build the membrane") is left whole.
    private static func spacedTail(_ slug: String) -> String? {
        var words = slug.split(separator: " ").map(String.init)
        if let first = words.first,
           first.hasSuffix(":"),
           typeWords.contains(String(first.dropLast())),
           words.count > 1 {
            words.removeFirst()
        }
        let tail = words.joined(separator: " ")
        return tail.isEmpty ? nil : tail
    }
}

/// A branch card in the rail: the parent trunk first, then one per plan (parent-trunk
/// doctrine). Building branches carry a breathing status dot.
struct BuildBranchItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var status: String
    var isTrunk: Bool
    var isBuilding: Bool

    /// Composed once at construction — genuinely stored on the item, no shared static cache
    /// (no data race, no unbounded growth). Terse, lowercase, hyphens become spaces, capped to five.
    let composedTitle: String

    /// Structured signals from the plan row so `group` never re-parses the display string.
    let hasNeedsYou: Bool
    let hasFailed: Bool
    let isComplete: Bool

    static func composeTitle(_ nickname: String) -> String {
        var words = nickname
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        if words.count > 5 { words = Array(words.prefix(5)) }
        return words.joined(separator: " ").lowercased()
    }

    /// Attention group for this branch — nil for the trunk (pinned top, ungrouped).
    var group: BuildBranchGroup? {
        if isTrunk { return nil }
        // failed folds into needsYou so a red plan is never buried under queued.
        if hasNeedsYou || hasFailed { return .needsYou }
        if isBuilding { return .building }
        if isComplete { return .done }
        return .queued
    }

    static let trunk = BuildBranchItem(
        id: "trunk",
        title: "parent trunk",
        status: "doctrine · values · ledger",
        isTrunk: true,
        isBuilding: false
    )

    init(id: String, title: String, status: String, isTrunk: Bool, isBuilding: Bool) {
        self.id = id
        self.title = title
        self.status = status
        self.isTrunk = isTrunk
        self.isBuilding = isBuilding
        self.composedTitle = isTrunk ? title : Self.composeTitle(title)
        self.hasNeedsYou = false
        self.hasFailed = false
        self.isComplete = false
    }

    init(row: BuildPlanRow) {
        id = row.id
        title = row.nickname
        isTrunk = false
        isBuilding = row.hasBuilding
        if row.needsYouCount > 0 {
            status = "held · needs your \(row.needsYouCount)"
        } else if let label = row.buildingUnitLabel {
            status = "\(label) building · \(row.fraction)"
        } else {
            status = row.fraction
        }
        composedTitle = Self.composeTitle(row.nickname)
        hasNeedsYou = row.hasNeedsYou
        hasFailed = row.segments.contains(.failed)
        isComplete = !row.segments.isEmpty && row.segments.allSatisfy { $0 == .done }
    }
}

/// A changelog row in the rail: a time gutter, a line, and whether it reads as a clean
/// landing (sage time) versus a neutral note.
struct BuildChangelogEntry: Identifiable, Equatable, Sendable {
    var id: String
    var time: String
    var text: String
    var isOk: Bool

    private static let okMarkers = [
        "deployed", "live", "landed", "0-fail", "0 fail", "green", "passed",
        "merged", "shipped", "spared", "crash gone", "clean", "resolved",
    ]

    static func isOkText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return okMarkers.contains { lower.contains($0) }
    }
}

/// The assembled report-first surface: the visible plan rows, the parked summary, and the
/// branch/changelog rail. Built purely from the packets and open-card count the tab
/// already consumes.
/// Status groups for the branch rail — collapses a flat list into
/// fewer than 5 attention-based groups. Trunk is ungrouped (nil).
enum BuildBranchGroup: String, CaseIterable, Equatable, Hashable, Sendable {
    case needsYou
    case building
    case queued
    case done

    var label: String {
        switch self {
        case .needsYou: return "needs you"
        case .building: return "building"
        case .queued: return "queued"
        case .done: return "done"
        }
    }
}


struct BuildReportSurface: Equatable, Sendable {
    var rows: [BuildPlanRow]
    var parkedBuilding: Int
    var waiting: Int
    var parkedLine: String?
    var branches: [BuildBranchItem]
    var changelog: [BuildChangelogEntry]

    /// The mock shows four plan rows and rolls the rest into the parked line.
    static let maxVisiblePlanRows = 4
    static let maxChangelogRows = 4

    var isEmpty: Bool {
        rows.isEmpty && parkedLine == nil && branches.count <= 1 && changelog.isEmpty
    }

    static func make(packets: [ViewPacket], openCardCount: Int) -> BuildReportSurface {
        let summaries = statusSummaries(from: packets)
        let allRows = summaries
            .map(BuildPlanRow.init(summary:))
            .filter { $0.totalCount > 0 }

        let ranked = allRows.enumerated()
            .sorted { lhs, rhs in
                lhs.element.priorityRank != rhs.element.priorityRank
                    ? lhs.element.priorityRank < rhs.element.priorityRank
                    : lhs.offset < rhs.offset
            }
            .map(\.element)

        let visible = Array(ranked.prefix(maxVisiblePlanRows))
        let hidden = ranked.dropFirst(maxVisiblePlanRows)
        let parkedBuilding = hidden.reduce(0) { partial, row in
            partial + row.segments.filter { $0 == .building }.count
        }

        // Report rows are ranked by founder attention; THREADS is a separate
        // source-order projection and applies the frozen state order immediately
        // before its seven-row replacement window.
        let branches = [BuildBranchItem.trunk] + allRows.map(BuildBranchItem.init(row:))
        let changelog = changelogEntries(from: summaries)

        return BuildReportSurface(
            rows: visible,
            parkedBuilding: parkedBuilding,
            waiting: openCardCount,
            parkedLine: parkedLine(building: parkedBuilding, waiting: openCardCount),
            branches: branches,
            changelog: changelog
        )
    }

    static func parkedLine(building: Int, waiting: Int) -> String? {
        var parts: [String] = []
        if building > 0 { parts.append("+\(building) building") }
        if waiting > 0 { parts.append("\(waiting) waiting on decisions") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Dedupes status packets by plan, keeping the freshest packet for each plan while
    /// preserving first-seen order — mirrors the worker rail's per-unit dedupe.
    private static func statusSummaries(from packets: [ViewPacket]) -> [BuildStatusSummary] {
        var order: [String] = []
        var byKey: [String: BuildStatusSummary] = [:]
        for packet in packets where packet.isBuildStatusPacket {
            let summary = BuildStatusSummary(packet: packet)
            let key = summary.planId ?? summary.title
            if byKey[key] == nil { order.append(key) }
            byKey[key] = summary
        }
        return order.compactMap { byKey[$0] }
    }

    private static func changelogEntries(from summaries: [BuildStatusSummary]) -> [BuildChangelogEntry] {
        var seen: Set<String> = []
        var entries: [BuildChangelogEntry] = []
        for summary in summaries {
            for record in summary.history {
                let text = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, seen.insert(record.id).inserted else { continue }
                entries.append(
                    BuildChangelogEntry(
                        id: record.id,
                        time: (record.age ?? "").lowercased(),
                        text: text.lowercased(),
                        isOk: BuildChangelogEntry.isOkText([text, record.state ?? ""].joined(separator: " "))
                    )
                )
            }
        }
        return Array(entries.prefix(maxChangelogRows))
    }
}
