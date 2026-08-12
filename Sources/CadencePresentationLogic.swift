import Foundation
import SwiftUI
import UIKit
enum CadenceWakeInitLogic {
    static func isAvailable(
        blocks: [CadenceBlock],
        now: Date,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> Bool {
        initBlockID(blocks: blocks, now: now, dayDate: dayDate, calendar: calendar) != nil
    }

    static func initBlockID(
        blocks: [CadenceBlock],
        now: Date,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String? {
        guard !blocks.contains(where: hasActed) else { return nil }
        let sorted = blocks.sorted { left, right in
            let leftInterval = CadenceDateParser.interval(for: left, dayDate: dayDate, calendar: calendar)
            let rightInterval = CadenceDateParser.interval(for: right, dayDate: dayDate, calendar: calendar)
            switch (leftInterval?.start, rightInterval?.start) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.id < right.id
            }
        }
        guard let first = sorted.first,
              isInitSleep(first),
              first.actionState != .completed,
              normalizedStatus(first.status) != "completed",
              normalizedStatus(first.status) != "complete",
              normalizedStatus(first.status) != "skipped"
        else {
            return nil
        }
        return first.id
    }

    private static func hasActed(_ block: CadenceBlock) -> Bool {
        if block.actionState != nil { return true }
        if block.startedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if (block.elapsedMinutes ?? 0) > 0 { return true }
        switch normalizedStatus(block.status) {
        case "completed", "complete", "done", "skipped", "skip":
            return true
        default:
            return false
        }
    }

    private static func isInitSleep(_ block: CadenceBlock) -> Bool {
        normalizedStatus(block.title) == "init" && block.normalizedTypeText == "sleep"
    }

    private static func normalizedStatus(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

enum CadenceRecalibrationDiffFormatter {
    static func line(
        for change: CadenceRecalibrationChange?,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String? {
        guard let change, let type = change.type else { return nil }
        switch type {
        case .shift:
            if let shifted = shiftedLine(prefix: "shifted", change: change, dayDate: dayDate, calendar: calendar) {
                return shifted
            }
            return signedMinutes(change.deltaMinutes).map { "shifted \($0)" }
        case .compress:
            if let delta = change.deltaMinutes {
                let minutes = signedMinutes(-abs(delta)) ?? "0m"
                return "compressed \(minutes)"
            }
            return "compressed"
        case .merge:
            return "merged"
        case .skip:
            return "skipped"
        case .protect:
            return "protected"
        }
    }

    private static func shiftedLine(
        prefix: String,
        change: CadenceRecalibrationChange,
        dayDate: String?,
        calendar: Calendar
    ) -> String? {
        guard let from = timeText(change.displayFromStart, dayDate: dayDate, calendar: calendar),
              let to = timeText(change.displayToStart, dayDate: dayDate, calendar: calendar)
        else {
            return nil
        }
        return "\(prefix) \(from) → \(to)"
    }

    private static func timeText(_ value: String?, dayDate: String?, calendar: Calendar) -> String? {
        guard let value,
              let date = CadenceDateParser.date(from: value, dayDate: dayDate, calendar: calendar)
        else {
            return nil
        }
        return KTimestampFormatter.hourMinute(date, timeZone: calendar.timeZone)
    }

    private static func signedMinutes(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value < 0 {
            return "−\(abs(value))m"
        }
        if value > 0 {
            return "+\(value)m"
        }
        return "0m"
    }
}

enum CadenceRecalibrationSummaryFormatter {
    static func line(
        for summary: CadenceRecalibrationSummary?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String? {
        guard let summary,
              let reason = summary.reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !reason.isEmpty,
              let anchorAt = summary.anchorAt,
              let anchorDate = CadenceDateParser.date(from: anchorAt, dayDate: nil, calendar: calendar)
        else {
            return nil
        }
        return "recalibrated · \(reason) \(KTimestampFormatter.hourMinute(anchorDate, timeZone: calendar.timeZone))"
    }
}

enum CadenceRecalibrationGutterFormatter {
    static func gutter(
        for block: CadenceBlock,
        startText: String,
        durationText: String?,
        durationMinutes: Int?,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> KBlockTimeGutter {
        var gutter = KBlockTimeGutter(startText: startText, durationText: durationText)
        guard let change = block.recalibrationChange, let type = change.type else { return gutter }

        switch type {
        case .shift:
            gutter.struckStartText = timeText(change.displayFromStart, dayDate: dayDate, calendar: calendar)
            if let to = timeText(change.displayToStart, dayDate: dayDate, calendar: calendar) {
                gutter.startText = to
            }
        case .compress:
            gutter.struckDurationText = originalDurationText(
                change: change,
                fallbackDurationMinutes: durationMinutes,
                dayDate: dayDate,
                calendar: calendar
            )
        case .merge, .skip, .protect:
            break
        }
        return gutter
    }

    private static func originalDurationText(
        change: CadenceRecalibrationChange,
        fallbackDurationMinutes: Int?,
        dayDate: String?,
        calendar: Calendar
    ) -> String? {
        if let start = date(change.displayFromStart, dayDate: dayDate, calendar: calendar),
           let end = date(change.originalEnd ?? change.fromEndAt, dayDate: dayDate, calendar: calendar) {
            return durationText(start: start, end: end, calendar: calendar)
        }
        guard let fallbackDurationMinutes, let delta = change.deltaMinutes else { return nil }
        return CadenceDateParser.durationClockText(fallbackDurationMinutes + abs(delta))
    }

    private static func durationText(start: Date, end: Date, calendar: Calendar) -> String {
        let resolvedEnd = end < start ? calendar.date(byAdding: .day, value: 1, to: end) ?? end : end
        let minutes = max(0, Int(ceil(resolvedEnd.timeIntervalSince(start) / 60)))
        return CadenceDateParser.durationClockText(minutes)
    }

    private static func timeText(_ value: String?, dayDate: String?, calendar: Calendar) -> String? {
        guard let date = date(value, dayDate: dayDate, calendar: calendar) else { return nil }
        return KTimestampFormatter.hourMinute(date, timeZone: calendar.timeZone)
    }

    private static func date(_ value: String?, dayDate: String?, calendar: Calendar) -> Date? {
        guard let value else { return nil }
        return CadenceDateParser.date(from: value, dayDate: dayDate, calendar: calendar)
    }
}

struct CadenceBlockPresentation: Identifiable, Equatable {
    var block: CadenceBlock
    var timeText: String
    var startTimeText: String
    var durationText: String?
    var timeGutter: KBlockTimeGutter
    var titleText: String
    var titleSuffixText: String?
    var detailText: String?
    var whyText: String?
    var typeLabel: String?
    var typeDetailText: String?
    var secondaryInfoText: String?
    var content: BlockContent
    var detailSections: [DetailSection]
    var statusText: String?
    var actionState: KBlockActionState
    var isNow: Bool
    var isNext: Bool
    var startsDay: Bool
    var hasEnded: Bool
    var remainingMinutes: Int?
    var durationSeconds: Int?
    var clockReferenceDate: Date
    var lifecycleControl: CadenceLifecycleControlModel
    var recalibrationDiffText: String?
    var isPending: Bool
    var actionErrorText: String?
    var actionCaptionText: String?
    var twsAnswerText: String?
    var showsTWSPrompt: Bool
    var nudge: CadenceNudge?
    var showsMealLogAffordance: Bool
    var mealLogEchoText: String?

    var id: String { block.id }

    var isStartedOverrun: Bool {
        actionState == .started && hasEnded
    }

    var hasDrillInDetail: Bool {
        let textValues = [
            detailText,
            whyText,
            typeDetailText,
            content.liveLine,
            recalibrationDiffText,
        ] + content.detailLines

        return textValues.contains { Self.normalized($0) != nil }
            || content.checklist?.isEmpty == false
            || detailSections.contains { !$0.isEmpty }
            || secondaryInfoText != nil
            || BandishBodyVariantResolver.presentation(
                for: block,
                temporal: .pastDetail,
                actionState: actionState
            ).kind != .none
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CadenceSensesRailModel: Equatable {
    var groups: [KSensesRailGroup]

    init?(
        bodyCueContext: BodyCueContext?,
        capacityEntries: [CadenceCapacityEntry],
        loggedMealTotals: MealMacroMeasurements?
    ) {
        var values: [KSensesRailGroup] = []

        let bodyLines = BodyCueContextRailFormatter.lines(from: bodyCueContext)
        if !bodyLines.isEmpty {
            values.append(KSensesRailGroup(id: "body", title: "body", source: "body", lines: bodyLines))
        }

        let capacityLines = capacityEntries.compactMap(\.remainingSegment)
        if !capacityLines.isEmpty {
            values.append(KSensesRailGroup(id: "capacity", title: "capacity", source: "cadence", lines: capacityLines))
        }

        let nutritionLines = Self.nutritionLines(from: loggedMealTotals)
        if !nutritionLines.isEmpty {
            values.append(KSensesRailGroup(id: "nutrition", title: "nutrition", source: "ios", lines: nutritionLines))
        }

        guard !values.isEmpty else { return nil }
        groups = values
    }

    private static func nutritionLines(from totals: MealMacroMeasurements?) -> [String] {
        totals?.summaryText(prefix: "logged today").map { [$0] } ?? []
    }
}

struct CadenceDayPresentation: Equatable {
    var dateText: String
    var caption: String
    var blocks: [CadenceBlockPresentation]
    var bodyCueContext: BodyCueContext?
    var bodyInterventions: CadenceBodyInterventionsChecklistModel?
    var topReviewCard: CadenceReviewCard?
    var topNudge: CadenceNudge?
    var topSlot: CadenceTopSlotModel
    var isViewingToday: Bool
    var capacityEntries: [CadenceCapacityEntry]
    var loggedMealTotals: MealMacroMeasurements?
    var hasUnresolvedNudge: Bool
    var isDefaultDay: Bool
    var recalibrationText: String?
    var showsWakeInit: Bool

    var nowBlock: CadenceBlockPresentation? {
        blocks.first { $0.isNow }
    }

    var nextBlock: CadenceBlockPresentation? {
        blocks.first { $0.isNext }
    }

    var nowPanel: CadenceNowPanelModel {
        CadenceNowPanelModel(block: nowBlock)
    }

    var nextRow: CadenceNextRowModel? {
        CadenceNextRowModel(block: nextBlock)
    }

    var capacityLine: CadenceCapacityLineModel? {
        CadenceCapacityLineModel(entries: capacityEntries)
    }

    var sensesRail: CadenceSensesRailModel? {
        CadenceSensesRailModel(
            bodyCueContext: bodyCueContext,
            capacityEntries: capacityEntries,
            loggedMealTotals: loggedMealTotals
        )
    }

    var elapsedTimelineBlocks: [CadenceBlockPresentation] {
        previousTimelineBlocks
    }

    var remainingTimelineBlocks: [CadenceBlockPresentation] {
        visibleTimelineBlocks
    }

    var earlierToggleText: String? {
        previousToggleText
    }

    var visibleTimelineBlocks: [CadenceBlockPresentation] {
        if !isViewingToday {
            return blocks
        }

        if showsWakeInit {
            return blocks.filter(\.startsDay)
        }

        let immediatePastID = immediatePastBlock?.id
        // Founder 2026-07-11: exactly ONE past-looking row in the stream. The
        // freshest started-overrun outranks the immediate past (it still needs
        // its ✓); everything older lives behind "show previous".
        let freshestOverrunID = blocks.last(where: { $0.isStartedOverrun })?.id
        let keptPastID = freshestOverrunID ?? immediatePastID
        return blocks.filter { block in
            block.isNow || !block.hasEnded || block.id == keptPastID
        }
    }

    var previousTimelineBlocks: [CadenceBlockPresentation] {
        if !isViewingToday || showsWakeInit { return [] }
        let visibleIDs = Set(visibleTimelineBlocks.map(\.id))
        let past = pastTimelineBlocks.filter { !visibleIDs.contains($0.id) }
        guard !past.isEmpty else { return [] }
        return past
    }

    var previousToggleText: String? {
        CadencePreviousToggleLabel.text(isExpanded: false, count: previousTimelineBlocks.count)
    }

    init(
        day: CadenceDayEnvelope,
        bodySummary: BodySummary? = nil,
        bodyCueContext: BodyCueContext? = nil,
        dismissedBodyProtocolIDs: Set<String> = [],
        bodyInterventionPendingIDs: Set<String> = [],
        bodyInterventionErrorText: String? = nil,
        localState: CadenceLocalActState = CadenceLocalActState(),
        reviewCards: [CadenceReviewCard] = [],
        dismissedReviewCardIDs: Set<String> = [],
        bodyLivePacket: ViewPacket? = nil,
        dismissedBodyLivePacketIDs: Set<String> = [],
        mealLogs: [MealLogRecord] = [],
        actionCaptionTexts: [String: String] = [:],
        captionOverride: String? = nil,
        now: Date = Date(),
        snapshotSyncedAt: Date? = nil,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) {
        let hasServerBlocks = !day.bandish.isEmpty
        let renderedDay = hasServerBlocks ? day : CadenceDayEnvelope.defaultTemplate(date: now, calendar: calendar)
        dateText = renderedDay.date ?? CadenceDateParser.dayString(for: now, calendar: calendar)
        isViewingToday = dateText == CadenceDateParser.dayString(for: now, calendar: calendar)
        caption = captionOverride
            ?? (hasServerBlocks ? (renderedDay.caption ?? "") : CadenceCopy.defaultDayCaption)
        isDefaultDay = !hasServerBlocks

        let activeNudge = Self.activeNudge(in: renderedDay.resolvedBandish, disposedIDs: localState.disposedNudgeIDs)
        let activeBodyLivePacket = CadenceBodyLivePacketRouter.slotCandidate(
            from: bodyLivePacket,
            dismissedIDs: dismissedBodyLivePacketIDs
        )
        let dueReviewCard = CadenceReviewSlotModel.dueCard(
            from: reviewCards,
            dismissedIDs: dismissedReviewCardIDs,
            now: now,
            dayDate: renderedDay.date,
            calendar: calendar
        )
        topNudge = activeNudge
        topReviewCard = dueReviewCard
        topSlot = CadenceTopSlotModel.resolve(
            reviewCard: dueReviewCard,
            nudge: activeNudge,
            bodyLivePacket: activeBodyLivePacket
        )
        hasUnresolvedNudge = activeNudge != nil
        capacityEntries = CadenceCapacityEntry.entries(
            budgetHoursByMode: renderedDay.capacityByMode,
            remainingMinutesByMode: renderedDay.remainingCapacityByMode
        )
        loggedMealTotals = MealLogAccumulator.total(in: mealLogs, now: now, calendar: calendar)
        self.bodyCueContext = bodyCueContext
        bodyInterventions = CadenceBodyInterventionsChecklistModel(
            context: bodyCueContext,
            dismissedIDs: dismissedBodyProtocolIDs,
            pendingIDs: bodyInterventionPendingIDs,
            errorText: bodyInterventionErrorText
        )
        recalibrationText = CadenceRecalibrationSummaryFormatter.line(for: renderedDay.recalibration, calendar: calendar)
        let intervals = renderedDay.resolvedBandish.map { block in
            (block: block, interval: CadenceDateParser.interval(for: block, dayDate: renderedDay.date, calendar: calendar))
        }
        let mealLogEchoes = Self.mealLogEchoesByBlock(in: mealLogs, now: now, calendar: calendar)
        let dayStartInitBlockID = CadenceWakeInitLogic.initBlockID(
            blocks: intervals.map(\.block),
            now: now,
            dayDate: renderedDay.date,
            calendar: calendar
        )
        showsWakeInit = dayStartInitBlockID != nil
        let clockCurrentBlockID = intervals
            .filter { item in
                guard let interval = item.interval else { return false }
                return now >= interval.start && now < interval.end
            }
            .sorted { left, right in
                guard let leftStart = left.interval?.start, let rightStart = right.interval?.start else { return false }
                if leftStart == rightStart { return left.block.id < right.block.id }
                return leftStart < rightStart
            }
            .first?.block.id
        let nowBlockID = dayStartInitBlockID ?? clockCurrentBlockID
        let nextBlockID = intervals
            .filter { item in
                guard let start = item.interval?.start else { return false }
                return start > now
            }
            .sorted { left, right in
                guard let leftStart = left.interval?.start, let rightStart = right.interval?.start else { return false }
                return leftStart < rightStart
            }
            .first?.block.id

        blocks = intervals.map { item in
            var block = item.block
            if !block.checklist.isEmpty {
                block.checklist = block.checklist.map { item in
                    var copy = item
                    copy.done = localState.checklistDone(blockId: block.id, item: item)
                    return copy
                }
            }
            if !block.subtasks.isEmpty {
                block.subtasks = block.subtasks.map { item in
                    var copy = item
                    copy.done = localState.checklistDone(blockId: block.id, itemId: item.id, fallback: item.done)
                    return copy
                }
            }
            let statusText = Self.statusText(for: block, localState: localState)
            let actionState = Self.actionState(for: block, statusText: statusText, localState: localState)
            let serverTWS = block.twsAnswer
            let localTWS = localState.twsAnswers[block.id]
            let twsAnswer = localTWS ?? serverTWS
            let hasEnded = item.interval.map { now >= $0.end } ?? false
            let remainingMinutes = item.interval.flatMap { Self.remainingMinutes(until: $0.end, now: now) }
            let durationMinutes = item.interval.map { Self.durationMinutes(for: $0) }
            let isNow = block.id == nowBlockID
            let localStartReferenceDate = localState.startReferenceDates[block.id]
            let lifecycleControl = CadenceLifecyclePresentationLogic.controlModel(
                actionState: actionState.cadenceLifecycleState,
                startedAt: block.startedAt,
                completedAt: block.completedAt,
                elapsedMinutes: block.elapsedMinutes,
                progress: block.progress,
                durationMinutes: durationMinutes,
                now: now,
                syncedAt: localStartReferenceDate ?? snapshotSyncedAt,
                dayDate: renderedDay.date,
                calendar: calendar,
                liveTicks: isNow && !hasEnded,
                freezeAt: hasEnded ? item.interval?.end : nil
            )
            let elapsedMinutes = lifecycleControl.elapsedSeconds.map { max(0, $0 / 60) }
                ?? Self.workPhaseElapsedMinutes(for: block, interval: item.interval, isNow: isNow, now: now)
            let temporal = Self.temporal(isNow: isNow, hasEnded: hasEnded)
            let bodyTemporal: BandishBodyTemporalVariant = isNow ? .current : (hasEnded ? .past : .future)
            let assignedNudge = activeNudge?.blockId == block.id ? activeNudge : nil
            let content = KBlockTypeContent.content(
                type: block.type,
                detail: block.detail,
                subtasks: block.contentSubtasks,
                temporal: temporal,
                health: nil,
                blockDurationMinutes: durationMinutes,
                elapsedMinutes: elapsedMinutes,
                bodySummary: bodySummary,
                isStarted: actionState.cadenceLifecycleState == .started
            )
            let detailSections = KBlockTypeContent.detail(
                type: block.type,
                detail: block.detail,
                subtasks: block.contentSubtasks,
                temporal: temporal,
                health: nil,
                blockDurationMinutes: durationMinutes,
                elapsedMinutes: elapsedMinutes,
                bodySummary: bodySummary
            )
            let isPending = localState.pendingActions[block.id] != nil
            let bodyPresentation = BandishBodyVariantResolver.presentation(
                for: block,
                temporal: bodyTemporal,
                actionState: actionState,
                elapsedSeconds: lifecycleControl.elapsedSeconds
            )
            let baseTitle = (block.title ?? block.description?.components(separatedBy: CharacterSet.newlines).first ?? block.mode).lowercased()
            return CadenceBlockPresentation(
                block: block,
                timeText: CadenceDateParser.timelineGutterText(for: block, dayDate: renderedDay.date, calendar: calendar),
                startTimeText: CadenceDateParser.startTimeText(for: block, dayDate: renderedDay.date, calendar: calendar),
                durationText: durationMinutes.map(CadenceDateParser.durationClockText),
                timeGutter: CadenceRecalibrationGutterFormatter.gutter(
                    for: block,
                    startText: CadenceDateParser.startTimeText(for: block, dayDate: renderedDay.date, calendar: calendar),
                    durationText: durationMinutes.map(CadenceDateParser.durationClockText),
                    durationMinutes: durationMinutes,
                    dayDate: renderedDay.date,
                    calendar: calendar
                ),
                titleText: block.normalizedTypeText == "work" ? baseTitle : bodyPresentation.title,
                titleSuffixText: Self.titleSuffixText(for: block, content: content),
                detailText: block.description?.lowercased(),
                whyText: block.whyText,
                typeLabel: block.normalizedTypeText,
                typeDetailText: block.typeDetailText,
                secondaryInfoText: bodyPresentation.secondaryInfo,
                content: content,
                detailSections: detailSections,
                statusText: statusText,
                actionState: actionState,
                isNow: isNow,
                isNext: block.id == nextBlockID,
                startsDay: block.id == dayStartInitBlockID,
                hasEnded: hasEnded,
                remainingMinutes: remainingMinutes,
                durationSeconds: durationMinutes.map { max(0, $0 * 60) },
                clockReferenceDate: localStartReferenceDate.map { max(now, $0) } ?? now,
                lifecycleControl: lifecycleControl,
                recalibrationDiffText: CadenceRecalibrationDiffFormatter.line(
                    for: block.recalibrationChange,
                    dayDate: renderedDay.date,
                    calendar: calendar
                ),
                isPending: isPending,
                actionErrorText: localState.actionErrors[block.id],
                actionCaptionText: actionCaptionTexts[block.id]
                    ?? (localState.queuedActions[block.id] == nil ? nil : KCopy.queuedWillSync),
                twsAnswerText: twsAnswer.map { $0 ? "well spent" : "not well spent" },
                showsTWSPrompt: hasEnded && actionState != .started && twsAnswer == nil,
                nudge: assignedNudge,
                showsMealLogAffordance: block.normalizedTypeText == "meal" && isNow,
                mealLogEchoText: mealLogEchoes[block.id]
            )
        }
    }

    private static func activeNudge(in blocks: [CadenceBlock], disposedIDs: Set<String>) -> CadenceNudge? {
        blocks
            .flatMap(\.nudges)
            .filter { !disposedIDs.contains($0.id) && !$0.isResolved }
            .sorted { left, right in
                (left.rank ?? Int.max, left.id) < (right.rank ?? Int.max, right.id)
            }
            .first
    }

    private static func mealLogEchoesByBlock(
        in records: [MealLogRecord],
        now: Date,
        calendar: Calendar
    ) -> [String: String] {
        var echoes: [String: String] = [:]
        for record in records where calendar.isDate(record.timestamp, inSameDayAs: now) {
            guard let blockId = record.blockId,
                  let text = record.meal.summaryText(prefix: "logged")
            else { continue }
            echoes[blockId] = text
        }
        return echoes
    }

    private var pastTimelineBlocks: [CadenceBlockPresentation] {
        blocks.filter { $0.hasEnded && !$0.isNow }
    }

    private var immediatePastBlock: CadenceBlockPresentation? {
        pastTimelineBlocks.last
    }

    private static func remainingMinutes(until end: Date, now: Date) -> Int? {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return Int(ceil(seconds / 60))
    }

    private static func durationMinutes(for interval: (start: Date, end: Date)) -> Int {
        max(0, Int(ceil(interval.end.timeIntervalSince(interval.start) / 60)))
    }

    private static func elapsedMinutes(since start: Date, now: Date) -> Int {
        max(0, Int(floor(now.timeIntervalSince(start) / 60)))
    }

    private static func workPhaseElapsedMinutes(
        for block: CadenceBlock,
        interval: (start: Date, end: Date)?,
        isNow: Bool,
        now: Date
    ) -> Int? {
        guard isNow, block.normalizedTypeText == "work", let interval else { return nil }
        return elapsedMinutes(since: interval.start, now: now)
    }

    private static func temporal(isNow: Bool, hasEnded: Bool) -> BlockTemporal {
        if isNow { return .now }
        return hasEnded ? .elapsed : .upcoming
    }

    private static func statusText(for block: CadenceBlock, localState: CadenceLocalActState) -> String? {
        if localState.completedBlockIDs.contains(block.id) { return "complete" }
        if localState.skippedBlockIDs.contains(block.id) { return "skipped" }
        if localState.extendedBlockIDs.contains(block.id) { return "+15" }
        let value = block.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.isEmpty == false ? value : nil
    }

    private static func actionState(
        for block: CadenceBlock,
        statusText: String?,
        localState: CadenceLocalActState
    ) -> KBlockActionState {
        if localState.completedBlockIDs.contains(block.id) {
            return .completed
        }
        switch localState.pendingActions[block.id] {
        case .start:
            return .started
        case .pause:
            return .available
        default:
            break
        }
        let normalizedStatus = statusText?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedStatus {
        case "complete", "completed", "done", "skipped", "skip":
            return .completed
        default:
            break
        }
        if block.completedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return .completed
        }
        switch block.actionState {
        case .started:
            return .started
        case .completed:
            return .completed
        case .available, nil:
            break
        }
        switch normalizedStatus {
        case "active", "in-progress", "in_progress", "running", "started":
            return .started
        default:
            break
        }
        return .available
    }

    private static func titleSuffixText(for block: CadenceBlock, content: BlockContent) -> String? {
        guard block.normalizedTypeText == "work" else { return nil }
        for candidate in [block.brainState, content.metaSuffix, block.mode] {
            if let mode = BandishWorkModeResolver.mode(candidate) {
                return "| \(mode)"
            }
        }
        return nil
    }
}

