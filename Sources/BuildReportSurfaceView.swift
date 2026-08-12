import SwiftUI

enum BuildSurfaceCopy {
    static func humanTitle(_ raw: String?, fallback: String, identifiers: [String?] = []) -> String {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        let normalized = value.lowercased()
        let knownIdentifiers = identifiers.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if knownIdentifiers.contains(normalized)
            || ["plan-", "plan/", "plan ", "unit-", "lane-", "card-", "build-card-"].contains(where: { normalized.hasPrefix($0) })
            || normalized.range(of: #"^(u|unit|lane|plan)[0-9]+$"#, options: .regularExpression) != nil {
            return fallback
        }
        return value
    }
}

struct BuildStatusSummary: Equatable {
    var planId: String?
    var title: String
    var state: String?
    var detail: String?
    var units: [BuildRecord]
    var lanes: [BuildRecord]
    var history: [BuildRecord]
    var extraFields: [String: ViewPacketJSONValue]

    init(packet: ViewPacket) {
        let fields = packet.fields ?? [:]
        let plan = fields["plan"]?.objectValue

        planId = Self.string(in: plan, keys: ["id", "planId"])
            ?? Self.string(in: fields, keys: ["planId"])
        let humanTitle = Self.string(in: plan, keys: ["title", "name"])
            ?? Self.string(in: fields, keys: ["title", "name"])
            ?? (packet.displayText.isEmpty ? nil : packet.displayText)
        title = BuildSurfaceCopy.humanTitle(
            humanTitle,
            fallback: BuildPlanRow.nickname(planId: planId, title: nil),
            identifiers: [planId]
        )
        state = Self.string(in: plan, keys: ["state", "status"])
            ?? Self.string(in: fields, keys: ["state", "status"])
        detail = Self.string(in: plan, keys: ["summary", "detail", "description"])
            ?? Self.string(in: fields, keys: ["summary", "detail", "description"])
        units = Self.records(from: fields["units"])
        lanes = Self.records(from: fields["lanes"])
        history = Self.records(from: fields["history"] ?? fields["recentHistory"])

        let known: Set<String> = [
            "plan", "planId", "title", "name", "state", "status", "summary", "detail", "description",
            "units", "lanes", "history", "recentHistory",
        ]
        extraFields = fields.filter { !known.contains($0.key) }
    }

    private static func records(from value: ViewPacketJSONValue?) -> [BuildRecord] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.enumerated().compactMap { index, item in
                BuildRecord(value: item, index: index)
            }
        }
        return BuildRecord(value: value, index: 0).map { [$0] } ?? []
    }

    private static func string(in object: [String: ViewPacketJSONValue]?, keys: [String]) -> String? {
        guard let object else { return nil }
        return string(in: object, keys: keys)
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

struct BuildCardSummary: Equatable {
    var title: String
    var voiceTitle: String
    var body: String?
    var state: String?
    var brief: DecisionBrief?
    var options: [BuildCardOption]
    var extraFields: [String: ViewPacketJSONValue]

    init(packet: ViewPacket) {
        let fields = packet.fields ?? [:]
        let cardObject = fields["card"]?.objectValue
        let source = cardObject ?? fields
        let card = BuildCard(packet: packet)
        let resolvedTitle = Self.string(in: source, keys: ["title", "name", "label"])
            ?? (packet.displayText.isEmpty ? nil : packet.displayText)
        let safeTitle = BuildSurfaceCopy.humanTitle(resolvedTitle, fallback: "build card")
        title = safeTitle
        voiceTitle = card?.voiceTitle
            ?? KCopy.buildCardTitle(kind: Self.string(in: source, keys: ["kind", "cardKind"]), rawTitle: safeTitle)
        body = Self.string(in: source, keys: ["body", "text", "message", "detail"])
            ?? (packet.text == title ? nil : packet.text)
        state = Self.string(in: source, keys: ["status", "state"])
        brief = card?.brief
        options = card?.options ?? []

        let known: Set<String> = [
            "title", "name", "label", "body", "text", "message", "detail",
            "what", "contrast", "stakes", "evidenceSummary", "signalExplained", "payload", "brief", "decisionBrief",
            "status", "state", "tier", "channelTier", "channel", "answerTier", "answerChannel",
            "card", "cardId", "kind", "cardKind", "planId", "unitId", "laneId", "options",
            "recommendation", "severity", "answeredBy", "answeredAt", "answerOption", "answerSurface",
            "raisedAt", "updatedAt",
        ]
        extraFields = fields.filter { !known.contains($0.key) }
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

struct BuildRecord: Identifiable, Equatable {
    var id: String
    var planId: String?
    var unitId: String?
    var laneId: String?
    var title: String
    var state: String?
    var age: String?
    var detail: String?
    var goal: String?
    var scope: String?
    var startedAt: String?
    var updatedAt: String?
    var holdReason: String?
    var currentStep: String?
    var resultNote: String?
    var failureReason: String?
    var gateEvidence: String?
    var stateHistory: [String] = []
    var logTail: String?
    var diff: String?
    var diffId: String?
    var docPaths: [String] = []
    var legalActions: [String] = []

    var logTailLaneId: String? {
        if let laneId, !laneId.isEmpty { return laneId }
        if id.lowercased().contains("lane") { return id }
        if isActiveBuildState { return id }
        return nil
    }

    private var isActiveBuildState: Bool {
        let normalized = state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["building", "verifying", "integrating", "running", "processing", "deploying"].contains(normalized)
    }

    init?(value: ViewPacketJSONValue, index: Int) {
        if let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            id = "record-\(index)-\(text)"
            title = Self.humanRecordTitle(text, id: text, unitId: nil, laneId: nil)
            return
        }

        guard let object = value.objectValue else { return nil }
        id = Self.string(in: object, keys: ["id", "unitId", "laneId", "key"]) ?? "record-\(index)"
        planId = Self.string(in: object, keys: ["planId"])
        unitId = Self.string(in: object, keys: ["unitId", "unit"])
        laneId = Self.string(in: object, keys: ["laneId", "lane", "activeLaneId"])
        let humanTitle = Self.string(in: object, keys: ["title", "name", "label", "summary"])
        title = Self.humanRecordTitle(humanTitle, id: id, unitId: unitId, laneId: laneId)
        state = Self.string(in: object, keys: ["state", "status"])
        age = Self.string(in: object, keys: ["age", "ageText", "lastSeenAge", "heartbeatAge", "startedAgo"])
        detail = Self.string(in: object, keys: ["detail", "message", "description", "owner"])
        goal = Self.string(in: object, keys: ["goal"])
        scope = Self.string(in: object, keys: ["scope"])
        startedAt = Self.string(in: object, keys: ["startedAt", "started_at", "started"])
        updatedAt = Self.string(in: object, keys: ["updatedAt", "updated", "at"])
        holdReason = Self.string(in: object, keys: ["holdReason", "hold_reason", "reason", "blocker"])
        currentStep = Self.string(in: object, keys: ["currentStep", "current_step", "step", "stepText", "progress"])
        resultNote = Self.string(in: object, keys: ["resultNote", "result_note", "note", "notes", "warning", "warnings", "retryReason", "environmentalRetry"])
        failureReason = Self.string(in: object, keys: ["failureReason", "failure_reason", "error", "errorText", "failure", "stopReason", "stop_reason"])
        gateEvidence = Self.string(in: object, keys: ["gateEvidence", "gate_evidence", "gateEvidenceLine", "evidence", "verification", "proof"])
        stateHistory = Self.strings(from: object["stateHistory"] ?? object["state_history"] ?? object["history"])
        logTail = Self.string(in: object, keys: ["logTail", "tail", "logs", "log"])
        diff = Self.string(in: object, keys: ["diffStat", "diff", "diffSummary"])
        diffId = Self.string(in: object, keys: ["diffId", "diff_id", "diffArtifactId"])
            ?? Self.diffId(from: diff)
        docPaths = BuildPayload.unique([
            object["docPath"],
            object["docPaths"],
            object["documentPath"],
            object["documents"],
            object["artifactPath"],
            object["artifactPaths"],
            object["referencedArtifacts"],
            object["references"],
        ].flatMap(BuildPayload.strings))
        .compactMap(BuildPayload.documentPath)
        legalActions = Self.strings(from: object["legalActions"] ?? object["actions"])
    }

    private static func string(in object: [String: ViewPacketJSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func humanRecordTitle(
        _ value: String?,
        id: String,
        unitId: String?,
        laneId: String?
    ) -> String {
        if let value,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isPayloadIdentifier(value, matching: [id, unitId, laneId]) {
            return value
        }
        if unitId != nil { return "unit" }
        if laneId != nil { return "lane" }
        return "build item"
    }

    private static func isPayloadIdentifier(_ value: String, matching identifiers: [String?]) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if identifiers.compactMap({ $0?.lowercased() }).contains(normalized) {
            return true
        }
        if ["plan-", "plan/", "plan ", "unit-", "lane-", "card-", "build-card-"].contains(where: { normalized.hasPrefix($0) }) {
            return true
        }
        return normalized.range(of: #"^(u|unit|lane|plan)[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func strings(from value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.compactMap { item in
                let text = item.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return text.isEmpty ? nil : text
            }
        }
        let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty ? [] : [text]
    }

    private static func diffId(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("diff_") else { return nil }
        return trimmed
    }
}

// MARK: - Report-first surface (v4 mock)

/// Where a selected plan's unit detail juts to (#26 slice B). iPad (regular width, wide
/// enough for the existing side rail) is the only finalized target for this jut — selecting
/// a plan there elevates its detail into that rail instead of growing the row in place.
/// iPhone (compact width) has no rail and no finalized design for one yet: it stays a
/// plain, safe fallback — the row still shows a selected state, but nothing juts anywhere.
enum BuildPlanDetailPlacement: Equatable {
    case rail
    case absent
}

enum BuildPlanDetailLayout {
    /// `showsSideRail` is the same regular-width-and-wide-enough decision the report
    /// already makes for its branch rail (`BuildView.body`'s `showsBranchRail`) — the plan
    /// detail jut reuses that exact size-class + width call rather than a second one.
    static func placement(showsSideRail: Bool, selectedPlanID: String?) -> BuildPlanDetailPlacement {
        guard showsSideRail, selectedPlanID != nil else { return .absent }
        return .rail
    }
}

/// The BUILD tab's resting surface. It leads with the factory REPORT (a segmented row per
/// plan) and an always-visible composer at the foot; touching the composer grows the
/// trunk-and-branch chat in below the report, and the needs-you cards stay reachable in a
/// collapsed section. The report never leaves — cards are additive, not the entry point.
struct BuildReportSurfaceView: View {
    @ObservedObject var model: BuildModel
    @Binding var intentText: String
    var showsSideRail: Bool = false
    let onSubmitIntent: () -> Void
    let onOpenReview: (BuildCard) -> Void
    let onOpenEntity: (EntityRef) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var composerFocusRequest = false
    @State private var composerFocusTask: Task<Void, Never>?
    @State private var isSteering = false
    // #28: the needs-you card IS the attention list — it opens showing its rows
    // (founder frame: list items in one large card, not a bare header to tap).
    @State private var needsYouExpanded = true
    @State private var selectedNeedsYouCardID: String?
    @State private var contextLead = "trunk"
    // A branch tap keeps its origin selected while the branch owns the main
    // surface; only the explicit report-row route mounts plan detail in the rail.
    @State private var selectedBranchID: String?
    @State private var branchComposerFocusRequest = false
    @State private var composerStageVisible = true
    /// Keeps the branch card mounted while its exit opacity runs. The selected
    /// id is the source of truth; this rendered id is only the travel shell.
    @State private var renderedBranchID: String?
    @State private var branchTravelTask: Task<Void, Never>?
    // Selecting a plan (#26 slice B) elevates its detail to the rail/panel jut — it no
    // longer grows the row in place, so this drives placement, not an in-place morph.
    @State private var selectedPlanID: String?
    @State private var reportExpanded = false

    private var surface: BuildReportSurface {
        BuildReportSurface.make(packets: model.packets, openCardCount: model.openCards.count)
    }

    private var statusSummaries: [BuildStatusSummary] {
        var order: [String] = []
        var latest: [String: BuildStatusSummary] = [:]
        for packet in model.packets where packet.isBuildStatusPacket {
            let summary = BuildStatusSummary(packet: packet)
            let key = summary.planId ?? summary.title
            if latest[key] == nil { order.append(key) }
            latest[key] = summary
        }
        return order.compactMap { latest[$0] }
    }

    private var planDetailPlacement: BuildPlanDetailPlacement {
        BuildPlanDetailLayout.placement(showsSideRail: showsSideRail, selectedPlanID: selectedPlanID)
    }

    private var selectedPlanDetail: (row: BuildPlanRow, summary: BuildStatusSummary?)? {
        guard let selectedPlanID,
              let row = surface.rows.first(where: { $0.id == selectedPlanID })
        else { return nil }
        let summary = statusSummaries.first { ($0.planId ?? $0.title) == row.id }
        return (row, summary)
    }

    private var buildContextStats: ContextStats? {
        ContextStatsSourceFactory.source().contextStats(for: .trunk)
    }

    private var selectedThreadID: String? {
        if contextLead == KCopy.chatTrunkTarget { return "trunk" }
        let normalizedLead = contextLead.lowercased().replacingOccurrences(of: "-", with: " ")
        return surface.branches.first(where: {
            $0.composedTitle == normalizedLead || $0.title.lowercased() == contextLead.lowercased()
        })?.id
    }

    private var selectedSidebarThreadID: String? {
        selectedBranchID ?? selectedThreadID
    }

    private var selectedBranchDetail: (branch: BuildBranchItem, summary: BuildStatusSummary?)? {
        guard let renderedBranchID,
              renderedBranchID != "trunk",
              let branch = surface.branches.first(where: { $0.id == renderedBranchID })
        else { return nil }
        return (branch, statusSummaries.first {
            ($0.planId ?? $0.title) == renderedBranchID
                || $0.title.caseInsensitiveCompare(branch.title) == .orderedSame
        })
    }

    private var needsYouRows: [BuildNeedsYouRow] {
        model.workingCards.map { card in
            BuildNeedsYouList.row(
                id: card.id,
                planID: card.planId,
                planTitle: card.what,
                title: card.title,
                raisedAt: card.raisedAt ?? card.updatedAt,
                status: card.status,
                kind: card.kind,
                receipt: card.isAnswered ? card.historyLine : nil,
                now: model.fixtureReferenceNow ?? Date()
            )
        }
    }

    private var selectedNeedsYouCard: BuildCard? {
        guard let selectedNeedsYouCardID else { return nil }
        return model.workingCards.first { $0.id == selectedNeedsYouCardID }
    }

    private var railSelectionID: String {
        if reportExpanded { return "factory" }
        if let selectedNeedsYouCardID { return "needs-you-\(selectedNeedsYouCardID)" }
        if let selectedPlanID { return "plan-\(selectedPlanID)" }
        if let selectedBranchID { return "branch-\(selectedBranchID)" }
        return "branch-rail"
    }

    private var depthSelectedActionIDs: Set<String> {
        var ids = Set<String>()
        if model.isDepthOrigin(branchID: "learned") { ids.insert("learned") }
        if model.isDepthOrigin(branchID: "trust") { ids.insert("trust") }
        return ids
    }

    /// Bio's rail-and-jut precedent (`BioRailDetail.detailTransition`): the jut fades in
    /// with a small lateral offset — position follows opacity — and fades out in place, a
    /// crossfade rather than a cut. Reduce-motion drops straight to plain opacity.
    private var jutTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: KStyle.buildPlanDetailRevealOffsetX).combined(with: .opacity),
            removal: .opacity
        )
    }

    var body: some View {
        // Mock build-k-v3: on wide surfaces the changelog + branch stack live in
        // a rail to the RIGHT of the report; on compact they stack inline below it.
        // iPad (regular + wide enough) is the only finalized target for the plan-detail
        // jut — compact has no rail and no finalized design for one yet, so a selected
        // plan there is a plain, safe fallback (the row still shows selected; nothing
        // juts, and nothing clips or crashes for it).
        HStack(alignment: .top, spacing: showsSideRail ? KStyle.buildReportRailGap : 0) {
            mainColumn
            if showsSideRail {
                branchRail
                    .frame(width: KStyle.buildReportRailWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: composerFocused) { _, focused in
            withAnimation(KStyle.chatStructureMotion(reduceMotion)) {
                isSteering = focused
            }
        }
        .onChange(of: selectedBranchID) { _, selectedBranchID in
            scheduleBranchTravel(for: selectedBranchID)
        }
        .onDisappear {
            composerFocusTask?.cancel()
            branchTravelTask?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-report-surface")
    }

    private func planDetailPanel(
        _ detail: (row: BuildPlanRow, summary: BuildStatusSummary?)
    ) -> some View {
        BuildPlanDetailPanel(
            row: detail.row,
            units: detail.summary?.units ?? [],
            planDetail: detail.summary?.detail,
            cards: model.cardRows,
            isPending: { model.isAnswerPending(for: $0) },
            isConfirming: { card, option in model.isConfirming(card: card, option: option) },
            onChoose: { card, option in _ = model.choose(option: option, for: card) },
            onClose: { KStyle.withMotion { selectedPlanID = nil } },
            onOpenEntity: onOpenEntity,
            isDepthOrigin: model.isDepthOrigin(record:)
        )
    }

    private func needsYouDetailPanel(_ card: BuildCard) -> some View {
        BuildNeedsYouDetailPanel(
            card: card,
            isPending: model.isAnswerPending(for: card),
            errorText: model.cardErrorText(for: card),
            captionText: model.cardCaptionText(for: card),
            disabledReason: model.inputDisabledReason,
            isConfirming: { option in model.isConfirming(card: card, option: option) },
            onChoose: { option in _ = model.choose(option: option, for: card) },
            onClose: { KStyle.withMotion { selectedNeedsYouCardID = nil } },
            onOpenReview: { onOpenReview(card) },
            onOpenEntity: onOpenEntity
        )
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    trunkSurface
                        .opacity(selectedBranchID == nil && renderedBranchID == nil ? KStyle.fullOpacity : .zero)
                        .animation(
                            KStyle.chatThreadSwapMotion(
                                reduceMotion,
                                phase: selectedBranchID == nil ? .trunkReturn : .trunkExit
                            ),
                            value: selectedBranchID
                        )
                        .animation(
                            KStyle.chatThreadSwapMotion(
                                reduceMotion,
                                phase: selectedBranchID == nil ? .trunkReturn : .trunkExit
                            ),
                            value: renderedBranchID
                        )
                        .accessibilityHidden(selectedBranchID != nil || renderedBranchID != nil)

                    if let detail = selectedBranchDetail {
                        BuildBranchSurface(
                            branch: detail.branch,
                            summary: detail.summary,
                            now: model.fixtureReferenceNow ?? Date(),
                            isActive: selectedBranchID == detail.branch.id,
                            intentText: $intentText,
                            composerState: model.intentState,
                            composerDisabledReason: model.composerStatusText,
                            composerFocus: $branchComposerFocusRequest,
                            composerStageVisible: composerStageVisible,
                            onSubmitIntent: onSubmitIntent,
                            contextStats: buildContextStats,
                            onClose: { selectBranch(id: "trunk", title: KCopy.chatTrunkTarget) },
                            onOpenReview: { record, kind in
                                KStyle.withGesturePageMotion { model.openReview(for: record, kind: kind) }
                            },
                            onPeekLogTail: { record in
                                KStyle.withGesturePageMotion { model.openLogTail(for: record) }
                            },
                            isDepthOrigin: model.isDepthOrigin(record:)
                        )
                        .opacity(selectedBranchID == detail.branch.id ? KStyle.fullOpacity : .zero)
                        .animation(
                            KStyle.chatThreadSwapMotion(
                                reduceMotion,
                                phase: selectedBranchID == nil ? .trunkExit : .threadEnter
                            ),
                            value: selectedBranchID
                        )
                        .animation(
                            KStyle.chatThreadSwapMotion(
                                reduceMotion,
                                phase: selectedBranchID == nil ? .trunkExit : .threadEnter
                            ),
                            value: renderedBranchID
                        )
                        .accessibilityHidden(selectedBranchID != detail.branch.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, KStyle.inputSidePadding)
                .padding(.top, KStyle.inputSidePadding)
                .padding(.trailing, KStyle.inputTrailingPadding)
                .padding(.bottom, KStyle.buildComposerContentClearance)

                if !showsSideRail {
                    threadsSidebar
                        .padding(.horizontal, KStyle.inputSidePadding)
                        .padding(.top, KStyle.buildReportRailTopPadding)
                        .padding(.bottom, KStyle.inputBottomPadding)
                        .accessibilityHidden(false)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            ZStack(alignment: .bottom) {
                BuildReportComposer(
                    text: $intentText,
                    // The composer stays mounted while the swap stages its
                    // visuals. Its target must follow the selection seam at
                    // phase start, otherwise the still-mounted target line
                    // can report trunk after a branch tap.
                    contextLead: contextLead,
                    state: model.intentState,
                    disabledReason: model.composerStatusText,
                    focus: $composerFocusRequest,
                    onSubmit: onSubmitIntent,
                    contextStats: buildContextStats
                )
                .opacity(
                    selectedBranchID == nil && renderedBranchID == nil && composerStageVisible
                        ? KStyle.fullOpacity
                        : .zero
                )
                .allowsHitTesting(selectedBranchID == nil && renderedBranchID == nil && composerStageVisible)
                .accessibilityHidden(selectedBranchID != nil || renderedBranchID != nil)
                .animation(
                    KStyle.chatThreadSwapMotion(
                        reduceMotion,
                        phase: selectedBranchID == nil ? .trunkReturn : .trunkExit
                    ),
                    value: selectedBranchID
                )

            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var trunkSurface: some View {
        VStack(alignment: .leading, spacing: KStyle.buildReportSurfaceSpacing) {
            BuildTrunkStream(
                lines: model.streamLines,
                proposals: model.openCards,
                now: model.fixtureReferenceNow ?? Date(),
                onSelectBranch: { title in selectBranch(title) },
                onOpenReview: { record, kind in
                    KStyle.withGesturePageMotion { model.openReview(for: record, kind: kind) }
                },
                onPeekLogTail: { record in
                    KStyle.withGesturePageMotion { model.openLogTail(for: record) }
                },
                isDepthOrigin: model.isDepthOrigin(record:)
            )
            .frame(minHeight: KStyle.buildThreadStreamMinHeight, alignment: .topLeading)

            // The frozen BUILD trunk owns one conversation slot. Needs-you is
            // routed to its explicit working-set fixture instead of becoming a
            // second dashboard below the resting stream.
            if !BuildAuditFixture.isEnabled() {
                needsYouSection
            }
        }
    }

    private var threadsSidebar: some View {
        BuildThreadsSidebar(
            model: model,
            selectedBranchID: selectedSidebarThreadID,
            onSelectBranch: { id, title in selectBranch(id: id, title: title) }
        )
    }

    private var branchRail: some View {
        ScrollView {
            railContent
                .padding(.top, KStyle.buildReportRailTopPadding)
                .padding(.leading, KStyle.buildReportRailLeadingPadding)
                .padding(.trailing, KStyle.inputTrailingPadding)
                .padding(.bottom, KStyle.inputBottomPadding)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(KStyle.hairlineOpacity))
                .frame(width: KStyle.hairlineWidth)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: railSelectionID)
    }

    /// Regular width: a selected plan's detail replaces the rail's default
    /// changelog/branches with the jut (#26 slice B) instead of growing the row.
    @ViewBuilder
    private var railContent: some View {
        if reportExpanded, let report = model.report {
            BuildFactoryDetailPanel(
                report: report,
                onClose: { KStyle.withMotion { reportExpanded = false } }
            )
            .transition(jutTransition)
        } else if showsSideRail, let selectedNeedsYouCard {
            needsYouDetailPanel(selectedNeedsYouCard)
                .id(selectedNeedsYouCard.id)
                .transition(jutTransition)
        } else if planDetailPlacement == .rail, let detail = selectedPlanDetail {
            // BuildPlanDetailPanel already carries its own per-row accessibility
            // identifier — no wrapper identifier needed on top of it here.
            planDetailPanel(detail)
                .id(detail.row.id)
                .transition(jutTransition)
        } else {
            threadsSidebar
            .transition(jutTransition)
        }
    }

    private var reportSection: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    selectFactory()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        KMonoCaption("factory", variant: .metadata, state: .active)
                        if model.report != nil {
                            Image(systemName: reportExpanded ? "chevron.up" : "chevron.down")
                                .font(KStyle.monoCaptionFont)
                                .foregroundStyle(.white.opacity(KStyle.buildDimmerOpacity))
                        }
                        Spacer(minLength: KStyle.smallSpacing)
                        KConnectionStateView(state: model.connectionState)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                .accessibilityIdentifier("build-report-header")
                .accessibilityHint(
                    showsSideRail
                        ? (reportExpanded ? "hide the factory detail" : "open the factory detail")
                        : "factory detail opens on iPad"
                )

                if let stalenessText = model.stalenessText {
                    KMonoCaption(stalenessText, variant: .staleness)
                        .padding(.bottom, KStyle.smallSpacing)
                }

                if model.isLoading && model.packets.isEmpty && model.report == nil {
                    KLoadingPrimitive(
                        variant: .skeleton,
                        lineCount: 3,
                        label: "loading build report",
                        accessibilityIdentifier: "build-loading"
                    )
                    .padding(.vertical, KStyle.buildReportPlanRowVerticalPadding)
                } else if model.connectionState.status == .offlineRetrying
                    && model.packets.isEmpty
                    && model.report == nil {
                    KMonoCaption(KCopy.offlineRetrying, variant: .inlineError, state: .offline)
                        .padding(.vertical, KStyle.buildReportPlanRowVerticalPadding)
                        .accessibilityIdentifier("build-unreachable")
                } else if surface.rows.isEmpty {
                    Text("no plans building")
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                        .padding(.vertical, KStyle.buildReportPlanRowVerticalPadding)
                } else {
                    ForEach(surface.rows) { row in
                        let summary = statusSummaries.first { ($0.planId ?? $0.title) == row.id }
                        BuildPlanReportRowView(
                            row: row,
                            units: summary?.units ?? [],
                            isSelected: selectedPlanID == row.id,
                            onSelect: { focusComposer(title: row.nickname) },
                            onToggle: { selectPlan(row.id) }
                        )
                    }
                }

                if let parked = surface.parkedLine {
                    Text(parked)
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.buildDimmerOpacity))
                        .padding(.vertical, KStyle.buildReportParkedVerticalPadding)
                        .accessibilityIdentifier("build-report-parked")
                }
            }
        }
    }

    @ViewBuilder
    private var needsYouSection: some View {
        if !model.workingCards.isEmpty || needsYouExpanded {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                HStack(spacing: KStyle.smallSpacing) {
                    Button {
                        KStyle.withMotion {
                            needsYouExpanded.toggle()
                            if !needsYouExpanded {
                                selectedNeedsYouCardID = nil
                                model.cancelApproveAll()
                            }
                        }
                    } label: {
                        HStack(spacing: KStyle.smallSpacing) {
                            KMonoCaption("needs you (\(model.openCards.count))", variant: .metadata, state: .active)
                            Image(systemName: needsYouExpanded ? "chevron.up" : "chevron.down")
                                .font(KStyle.monoCaptionFont)
                                .foregroundStyle(.white.opacity(KStyle.buildDimmerOpacity))
                        }
                        .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("build-needs-you-toggle")

                    Spacer(minLength: 0)
                    if model.openCards.count > 0 {
                        KActRow(
                            actions: [
                                KActItem(
                                    id: "approve-all",
                                    label: KCopy.buildApproveAllAct,
                                    accessibilityIdentifier: "build-needs-you-approve-all"
                                )
                            ],
                            variant: .build,
                            state: model.approveAllState.isRunning ? .loading : .resting,
                            onSelect: { _ in beginApproveAll() }
                        )
                        .accessibilityElement(children: .contain)
                    }
                }

                if needsYouExpanded {
                    BuildNeedsYouCard(
                        rows: needsYouRows,
                        oldestStuck: model.report?.needsYou?.oldestAge?.text,
                        selectedRowID: selectedNeedsYouCardID,
                        approveAllState: model.approveAllState,
                        errorText: { model.cardErrors[$0] },
                        isDepthOrigin: { row in
                            guard let card = model.workingCards.first(where: { $0.id == row.id }) else {
                                return false
                            }
                            return model.isDepthOrigin(needsYouCard: card)
                        },
                        onSelect: selectNeedsYou,
                        onApproveAllConfirm: {
                            Task { await model.confirmApproveAll() }
                        },
                        onApproveAllCancel: model.cancelApproveAll
                    )
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(KStyle.hairlineOpacity))
                    .frame(height: KStyle.dividerHeight)
                    .padding(.top, -KStyle.rowSpacing)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("build-needs-you-section")
        }
    }

    private func selectBranch(id: String, title: String) {
        // Context is semantic state, not part of the staged visual travel.
        // Commit it before the animated selection transaction so every
        // mounted composer target names the branch immediately.
        contextLead = title
        KStyle.withMotion {
            selectedBranchID = id == "trunk" ? nil : id
            // In v43 a sidebar tap owns the branch card. The THREADS rail stays
            // mounted as the marked origin; the plan-detail jut is reserved for
            // the explicit report-row route (`selectPlan`).
            selectedPlanID = nil
            selectedNeedsYouCardID = nil
            reportExpanded = false
        }
    }

    private func selectBranch(_ title: String) {
        let normalizedTitle = title.lowercased()
        let matchedBranch = surface.branches.first {
            $0.composedTitle == normalizedTitle || $0.title.lowercased() == normalizedTitle
        }
        let streamBranch = model.streamLines
            .compactMap { $0.record?.planId }
            .compactMap { planID in surface.branches.first { $0.id == planID } }
            .first
        // A proposal can arrive before its status packet has acquired the
        // human-readable branch title. Prefer the current K line's existing
        // plan identity, then the first existing plan; never invent a branch.
        let branchID = matchedBranch?.id
            ?? streamBranch?.id
            ?? surface.branches.first(where: { !$0.isTrunk })?.id
        let resolvedTitle = matchedBranch?.composedTitle
            ?? streamBranch?.composedTitle
            ?? surface.branches.first(where: { !$0.isTrunk })?.composedTitle
            ?? title
        // Keep the branch target synchronous with swap start. The staged
        // travel below only controls presentation and focus timing.
        contextLead = resolvedTitle
        KStyle.withMotion {
            selectedBranchID = branchID
            // Proposal travel follows the same branch-owned route as a sidebar
            // tap. Do not mount a second plan-detail surface for the same act.
            selectedPlanID = nil
            selectedNeedsYouCardID = nil
            reportExpanded = false
        }
    }

    private func scheduleBranchTravel(for branchID: String?) {
        branchTravelTask?.cancel()
        composerFocusTask?.cancel()
        composerFocusRequest = false
        branchComposerFocusRequest = false
        composerStageVisible = false

        if let branchID {
            // Mount before the staged opacity animation so the branch ground can
            // run instead of cutting in after the trunk has disappeared.
            renderedBranchID = branchID
        }

        let expectedID = branchID
        let delay = branchID == nil
            ? KStyle.chatThreadTrunkReturnDelay
            : KStyle.chatThreadComposerDelay
        let phase: ChatThreadSwapPhase = branchID == nil ? .trunkReturn : .composerEnter

        if branchID == nil {
            branchTravelTask = Task { @MainActor in
                if reduceMotion {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(KStyle.chatThreadTrunkReturnDelay * 1_000_000_000))
                }
                guard !Task.isCancelled, self.selectedBranchID == nil else { return }
                withAnimation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .trunkReturn)) {
                    renderedBranchID = nil
                }
            }
        }

        composerFocusTask = Task { @MainActor in
            if reduceMotion {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, self.selectedBranchID == expectedID else { return }
            withAnimation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: phase)) {
                composerStageVisible = true
            }
            if expectedID != nil {
                branchComposerFocusRequest = true
            }
        }
    }

    private func focusComposer(title: String) {
        contextLead = title
        KStyle.withMotion {
            composerFocused = true
        }
    }

    private func selectPlan(_ id: String) {
        KStyle.withMotion {
            selectedBranchID = nil
            selectedPlanID = selectedPlanID == id ? nil : id
            selectedNeedsYouCardID = nil
            reportExpanded = false
        }
    }

    private func selectNeedsYou(_ row: BuildNeedsYouRow) {
        KStyle.withMotion {
            selectedBranchID = nil
            selectedNeedsYouCardID = selectedNeedsYouCardID == row.id ? nil : row.id
            selectedPlanID = nil
            reportExpanded = false
        }
    }

    private func beginApproveAll() {
        KStyle.withMotion {
            needsYouExpanded = true
            selectedNeedsYouCardID = nil
            model.beginApproveAll()
        }
    }

    private func selectFactory() {
        guard model.report != nil, showsSideRail else { return }
        KStyle.withMotion {
            reportExpanded.toggle()
            selectedBranchID = nil
            selectedPlanID = nil
            selectedNeedsYouCardID = nil
        }
    }
}
