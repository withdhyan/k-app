import Foundation
import SwiftUI
import UIKit
enum CadenceReviewSlot: Equatable {
    case morning
    case evening

    func isDue(now: Date, calendar: Calendar = CadenceDateParser.pinnedCalendar) -> Bool {
        let hour = calendar.component(.hour, from: now)
        switch self {
        case .morning:
            return (4..<12).contains(hour)
        case .evening:
            return (17..<24).contains(hour)
        }
    }
}

enum CadenceReviewSlotModel {
    static func dueCard(
        from cards: [CadenceReviewCard],
        dismissedIDs: Set<String>,
        now: Date,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> CadenceReviewCard? {
        cards.first { card in
            guard !dismissedIDs.contains(card.id) else {
                return false
            }
            if card.isValuesCard {
                // The probe remains the focused ask until answered; its additive
                // values projection then stays in the same one slot for signals
                // and trail evidence. (doctrine: one-slot, silence-default)
                if let review = card.valueProbes, !review.probes.isEmpty {
                    return review.probes.contains { $0.answer == nil } || card.valuesCard != nil
                }
                // A resting values projection has no probe to answer, but it is
                // still the one cadence card in the top slot. (doctrine: one-slot)
                return card.valuesCard != nil
            }
            guard let slot = card.slot, slot.isDue(now: now, calendar: calendar) else { return false }
            guard let dayDate, let cardDate = card.date, !cardDate.isEmpty else {
                return true
            }
            return cardDate == dayDate
        }
    }
}

enum CadenceTopSlotCue: Equatable {
    case review(CadenceReviewCard)
    case nudge(CadenceNudge)
    case bodyLive(ViewPacket)
}

struct CadenceTopSlotModel: Equatable {
    var active: CadenceTopSlotCue?
    var queued: CadenceTopSlotCue?

    static func resolve(
        reviewCard: CadenceReviewCard?,
        nudge: CadenceNudge?,
        bodyLivePacket: ViewPacket? = nil
    ) -> CadenceTopSlotModel {
        let lowerPriorityCues = [
            nudge.map(CadenceTopSlotCue.nudge),
            bodyLivePacket.map(CadenceTopSlotCue.bodyLive),
        ].compactMap { $0 }

        if let reviewCard {
            return CadenceTopSlotModel(
                active: .review(reviewCard),
                queued: lowerPriorityCues.first
            )
        }
        return CadenceTopSlotModel(
            active: lowerPriorityCues.first,
            queued: lowerPriorityCues.dropFirst().first
        )
    }
}

enum CadenceBodyLivePacketRouter {
    static let module = "body-live"

    static func slotCandidate(from packet: ViewPacket?, dismissedIDs: Set<String> = []) -> ViewPacket? {
        guard let packet,
              !dismissedIDs.contains(packet.id),
              packet.provenance["module"]?.stringValue == module,
              ViewPacketRenderer.renderedInterruptionClass(for: packet) == .ambient
        else { return nil }
        return packet
    }
}

struct CadenceLocalActState: Equatable {
    var completedBlockIDs: Set<String> = []
    var skippedBlockIDs: Set<String> = []
    var extendedBlockIDs: Set<String> = []
    var twsAnswers: [String: Bool] = [:]
    var checklistDoneByItem: [String: Bool] = [:]
    var queuedChecklistActs: [CadenceQueuedChecklistAct] = []
    var pendingActions: [String: CadenceBlockAction] = [:]
    var queuedActions: [String: CadenceBlockAction] = [:]
    var startReferenceDates: [String: Date] = [:]
    var actionErrors: [String: String] = [:]
    var disposedNudgeIDs: Set<String> = []

    mutating func apply(blockId: String, action: CadenceBlockAction, at eventDate: Date? = nil) {
        pendingActions[blockId] = action
        actionErrors[blockId] = nil
        switch action {
        case .start:
            completedBlockIDs.remove(blockId)
            skippedBlockIDs.remove(blockId)
            if let eventDate {
                startReferenceDates[blockId] = eventDate
            }
        case .pause:
            startReferenceDates.removeValue(forKey: blockId)
        case .complete:
            completedBlockIDs.insert(blockId)
            skippedBlockIDs.remove(blockId)
            startReferenceDates.removeValue(forKey: blockId)
        case .skip:
            skippedBlockIDs.insert(blockId)
            completedBlockIDs.remove(blockId)
            startReferenceDates.removeValue(forKey: blockId)
        case .extend15:
            extendedBlockIDs.insert(blockId)
        case .twsYes:
            twsAnswers[blockId] = true
        case .twsNo:
            twsAnswers[blockId] = false
        case .wakeInit:
            break
        }
    }

    mutating func markQueued(blockId: String, action: CadenceBlockAction, at eventDate: Date? = nil) {
        pendingActions[blockId] = action
        queuedActions[blockId] = action
        actionErrors[blockId] = nil
        if action == .start, startReferenceDates[blockId] == nil, let eventDate {
            startReferenceDates[blockId] = eventDate
        }
    }

    mutating func applyChecklist(blockId: String, itemId: String, done: Bool) {
        checklistDoneByItem[Self.checklistKey(blockId: blockId, itemId: itemId)] = done
    }

    mutating func queueChecklistAct(_ act: CadenceQueuedChecklistAct) {
        queuedChecklistActs.removeAll { $0.blockId == act.blockId && $0.itemId == act.itemId }
        queuedChecklistActs.append(act)
    }

    mutating func removeQueuedChecklistAct(_ act: CadenceQueuedChecklistAct) {
        queuedChecklistActs.removeAll { $0.blockId == act.blockId && $0.itemId == act.itemId && $0.done == act.done }
    }

    func checklistDone(blockId: String, item: CadenceChecklistItem) -> Bool {
        checklistDone(blockId: blockId, itemId: item.id, fallback: item.done)
    }

    func checklistDone(blockId: String, itemId: String, fallback: Bool) -> Bool {
        checklistDoneByItem[Self.checklistKey(blockId: blockId, itemId: itemId)] ?? fallback
    }

    static func checklistKey(blockId: String, itemId: String) -> String {
        "\(blockId)::\(itemId)"
    }

    mutating func confirm(blockId: String) {
        pendingActions.removeValue(forKey: blockId)
        queuedActions.removeValue(forKey: blockId)
        startReferenceDates.removeValue(forKey: blockId)
    }

    mutating func fail(blockId: String, previous: CadenceLocalActState, reason: String) {
        self = previous
        actionErrors[blockId] = KCopy.answerFailed(reason: reason)
    }

    mutating func failQueued(blockId: String, reason: String) {
        pendingActions.removeValue(forKey: blockId)
        queuedActions.removeValue(forKey: blockId)
        startReferenceDates.removeValue(forKey: blockId)
        actionErrors[blockId] = KCopy.answerFailed(reason: reason)
    }

    mutating func removeLocalAct(blockId: String) {
        completedBlockIDs.remove(blockId)
        skippedBlockIDs.remove(blockId)
        extendedBlockIDs.remove(blockId)
        twsAnswers.removeValue(forKey: blockId)
        pendingActions.removeValue(forKey: blockId)
        queuedActions.removeValue(forKey: blockId)
        startReferenceDates.removeValue(forKey: blockId)
        actionErrors.removeValue(forKey: blockId)
    }
}

struct CadenceQueuedChecklistAct: Equatable, Sendable {
    var blockId: String
    var itemId: String
    var done: Bool
}

struct CadenceNowPanelModel: Equatable {
    var title: String
    var whyText: String?
    var metaText: String?
    var detailText: String?
    var content: BlockContent?
    var isEmpty: Bool

    static let empty = CadenceNowPanelModel(
        title: "no active block",
        whyText: "the day is between blocks.",
        metaText: nil,
        detailText: nil,
        content: nil,
        isEmpty: true
    )

    init(block: CadenceBlockPresentation?) {
        guard let block else {
            self = Self.empty
            return
        }

        title = block.titleText
        whyText = block.whyText
        content = block.content.isEmpty ? nil : block.content
        detailText = block.block.hasTypedContentContract ? nil : block.typeDetailText
        isEmpty = false

        let remainingText = block.remainingMinutes.map { "\($0)m left" }
        let progressText = block.lifecycleControl.isStarted
            ? block.lifecycleControl.progressRatio.map { "\(Int(($0 * 100).rounded()))%" }
            : nil
        let ringText = block.block.ring == .unknown ? nil : block.block.ring.rawValue
        let metaParts = [remainingText, progressText, block.block.mode, ringText, block.typeLabel]
            .compactMap(Self.normalized)
        metaText = metaParts.isEmpty ? nil : metaParts.joined(separator: " · ")
    }

    private init(
        title: String,
        whyText: String?,
        metaText: String?,
        detailText: String?,
        content: BlockContent?,
        isEmpty: Bool
    ) {
        self.title = title
        self.whyText = whyText
        self.metaText = metaText
        self.detailText = detailText
        self.content = content
        self.isEmpty = isEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CadenceNextRowModel: Equatable {
    var timeText: String
    var titleText: String

    init?(block: CadenceBlockPresentation?) {
        guard let block else { return nil }
        timeText = block.startTimeText
        titleText = block.titleText
    }
}

struct CadenceCapacityLineModel: Equatable {
    var text: String

    init?(entries: [CadenceCapacityEntry]) {
        let segments = entries.compactMap(\.remainingSegment)
        guard !segments.isEmpty else { return nil }
        text = "left: \(segments.joined(separator: " · "))"
    }
}

struct CadenceCapacityEntry: Identifiable, Equatable {
    var mode: String
    var budgetMinutes: Int?
    var remainingMinutes: Int?

    var id: String { mode }

    var budgetText: String? {
        CadenceDurationFormatter.minutesText(budgetMinutes)
    }

    var remainingText: String? {
        CadenceDurationFormatter.minutesText(remainingMinutes)
    }

    var remainingSegment: String? {
        remainingText.map { "\(mode) \($0)" }
    }

    static func entries(
        budgetHoursByMode: [String: Double],
        remainingMinutesByMode: [String: Double]
    ) -> [CadenceCapacityEntry] {
        let budgets = normalizedValues(budgetHoursByMode)
        let remaining = normalizedValues(remainingMinutesByMode)
        let modes = Set(budgets.keys).union(remaining.keys)
        return modes
            .compactMap { mode -> CadenceCapacityEntry? in
                guard !mode.isEmpty else { return nil }
                return CadenceCapacityEntry(
                    mode: mode,
                    budgetMinutes: budgets[mode].flatMap(CadenceDurationFormatter.budgetMinutes),
                    remainingMinutes: remaining[mode].flatMap(CadenceDurationFormatter.remainingMinutes)
                )
            }
            .sorted { left, right in
                let leftRank = modeRank(left.mode)
                let rightRank = modeRank(right.mode)
                if leftRank == rightRank { return left.mode < right.mode }
                return leftRank < rightRank
            }
    }

    private static func normalizedValues(_ values: [String: Double]) -> [String: Double] {
        values.reduce(into: [:]) { result, pair in
            let mode = pair.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !mode.isEmpty else { return }
            result[mode] = pair.value
        }
    }

    private static func modeRank(_ mode: String) -> Int {
        let order = ["converge", "core", "middle", "physical", "restore", "review", "outer"]
        return order.firstIndex(of: mode) ?? order.count
    }
}

enum CadenceDurationFormatter {
    static func budgetMinutes(from hours: Double) -> Int? {
        guard hours > 0 else { return nil }
        return Int((hours * 60).rounded())
    }

    static func remainingMinutes(from minutes: Double) -> Int? {
        guard minutes > 0 else { return nil }
        return Int(minutes.rounded())
    }

    static func minutesText(_ value: Int?) -> String? {
        guard let value, value > 0 else { return nil }
        let hours = value / 60
        let minutes = value % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct CadenceLifecycleControlModel: Equatable {
    var optionLabel: String?
    var optionAction: CadenceBlockAction?
    var rowActions: [CadenceBlockAction]
    var elapsedLineText: String?
    var elapsedTimerText: String?
    var elapsedSeconds: Int?
    var progressRatio: Double?
    var isStarted: Bool

    static let empty = CadenceLifecycleControlModel(
        optionLabel: nil,
        optionAction: nil,
        rowActions: [],
        elapsedLineText: nil,
        elapsedTimerText: nil,
        elapsedSeconds: nil,
        progressRatio: nil,
        isStarted: false
    )
}

enum CadenceLifecyclePresentationLogic {
    static func controlModel(
        actionState: CadenceBlockLifecycleState?,
        startedAt: String?,
        completedAt: String? = nil,
        elapsedMinutes: Int?,
        progress: Double?,
        durationMinutes: Int?,
        now: Date,
        syncedAt: Date?,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar,
        liveTicks: Bool = true,
        freezeAt: Date? = nil
    ) -> CadenceLifecycleControlModel {
        let state = actionState ?? .available
        switch state {
        case .completed:
            let elapsedSeconds = completedElapsedSeconds(
                startedAt: startedAt,
                completedAt: completedAt,
                dayDate: dayDate,
                calendar: calendar
            ) ?? elapsedMinutes.map { max(0, $0 * 60) }
            return CadenceLifecycleControlModel(
                optionLabel: "resume",
                optionAction: .start,
                rowActions: [],
                elapsedLineText: nil,
                elapsedTimerText: nil,
                elapsedSeconds: elapsedSeconds,
                progressRatio: progressRatio(
                    serverProgress: progress,
                    durationMinutes: durationMinutes,
                    elapsedSeconds: elapsedSeconds
                ),
                isStarted: false
            )
        case .started:
            let elapsedSeconds = liveElapsedSeconds(
                actionState: state,
                startedAt: startedAt,
                elapsedMinutes: elapsedMinutes,
                durationMinutes: durationMinutes,
                now: now,
                syncedAt: syncedAt,
                dayDate: dayDate,
                calendar: calendar,
                liveTicks: liveTicks,
                freezeAt: freezeAt
            )
            let elapsedWholeMinutes = elapsedSeconds.map { max(0, $0 / 60) }
            let ratio = progressRatio(
                serverProgress: progress,
                durationMinutes: durationMinutes,
                elapsedSeconds: elapsedSeconds
            )
            return CadenceLifecycleControlModel(
                optionLabel: nil,
                optionAction: nil,
                rowActions: [.complete],
                elapsedLineText: elapsedWholeMinutes.map { "\($0)m · elapsed" },
                elapsedTimerText: elapsedSeconds.map(formatElapsedTime),
                elapsedSeconds: elapsedSeconds,
                progressRatio: ratio,
                isStarted: true
            )
        case .available:
            let paused = startedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || (elapsedMinutes ?? 0) > 0
            return CadenceLifecycleControlModel(
                optionLabel: paused ? "resume" : "start",
                optionAction: .start,
                rowActions: [],
                elapsedLineText: nil,
                elapsedTimerText: elapsedMinutes.map { formatElapsedTime(max(0, $0 * 60)) },
                elapsedSeconds: elapsedMinutes.map { max(0, $0 * 60) },
                progressRatio: nil,
                isStarted: false
            )
        }
    }

    static func liveElapsedMinutes(
        actionState: CadenceBlockLifecycleState?,
        startedAt: String?,
        completedAt: String? = nil,
        elapsedMinutes: Int?,
        durationMinutes: Int? = nil,
        now: Date,
        syncedAt: Date?,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar,
        liveTicks: Bool = true,
        freezeAt: Date? = nil
    ) -> Int? {
        liveElapsedSeconds(
            actionState: actionState,
            startedAt: startedAt,
            completedAt: completedAt,
            elapsedMinutes: elapsedMinutes,
            durationMinutes: durationMinutes,
            now: now,
            syncedAt: syncedAt,
            dayDate: dayDate,
            calendar: calendar,
            liveTicks: liveTicks,
            freezeAt: freezeAt
        ).map { max(0, $0 / 60) }
    }

    static func liveElapsedSeconds(
        actionState: CadenceBlockLifecycleState?,
        startedAt: String?,
        completedAt: String? = nil,
        elapsedMinutes: Int?,
        durationMinutes: Int? = nil,
        now: Date,
        syncedAt: Date?,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar,
        liveTicks: Bool = true,
        freezeAt: Date? = nil
    ) -> Int? {
        if actionState == .completed {
            return completedElapsedSeconds(
                startedAt: startedAt,
                completedAt: completedAt,
                dayDate: dayDate,
                calendar: calendar
            ) ?? elapsedMinutes.map { max(0, $0 * 60) }
        }

        let base = max(0, (elapsedMinutes ?? 0) * 60)
        guard actionState == .started else {
            return elapsedMinutes.map { max(0, $0 * 60) }
        }

        if !liveTicks {
            let frozenSeconds = frozenElapsedSeconds(
                startedAt: startedAt,
                freezeAt: freezeAt,
                dayDate: dayDate,
                calendar: calendar
            )
            let scheduledSeconds = durationMinutes.map { max(0, $0 * 60) }
            if let frozenSeconds, let scheduledSeconds {
                return min(frozenSeconds, scheduledSeconds)
            }
            return frozenSeconds ?? scheduledSeconds ?? base
        }

        if let syncedAt {
            return base + max(0, Int(floor(now.timeIntervalSince(syncedAt))))
        }

        guard let startedAt,
              let startedDate = CadenceDateParser.date(from: startedAt, dayDate: dayDate, calendar: calendar)
        else {
            return base
        }

        let running = max(0, Int(floor(now.timeIntervalSince(startedDate))))
        return max(base, running)
    }

    private static func completedElapsedSeconds(
        startedAt: String?,
        completedAt: String?,
        dayDate: String?,
        calendar: Calendar
    ) -> Int? {
        guard let completedAt,
              let completedDate = CadenceDateParser.date(from: completedAt, dayDate: dayDate, calendar: calendar)
        else {
            return nil
        }
        return frozenElapsedSeconds(
            startedAt: startedAt,
            freezeAt: completedDate,
            dayDate: dayDate,
            calendar: calendar
        )
    }

    private static func frozenElapsedSeconds(
        startedAt: String?,
        freezeAt: Date?,
        dayDate: String?,
        calendar: Calendar
    ) -> Int? {
        guard let startedAt,
              let freezeAt,
              let startedDate = CadenceDateParser.date(from: startedAt, dayDate: dayDate, calendar: calendar)
        else {
            return nil
        }
        return max(0, Int(floor(freezeAt.timeIntervalSince(startedDate))))
    }

    static func progressRatio(serverProgress: Double?, durationMinutes: Int?, elapsedSeconds: Int?) -> Double? {
        if let durationMinutes, durationMinutes > 0, let elapsedSeconds {
            return min(
                KStyle.fullProgressRatio,
                max(KStyle.zeroProgressRatio, Double(elapsedSeconds) / Double(durationMinutes * 60))
            )
        }
        guard let serverProgress else { return nil }
        return min(KStyle.fullProgressRatio, max(KStyle.zeroProgressRatio, serverProgress))
    }

    static func formatElapsedTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remainingSeconds = clamped % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }
}
