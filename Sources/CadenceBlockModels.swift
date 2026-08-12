import Foundation
import SwiftUI
import UIKit
struct CadenceBlock: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String?
    var mode: String
    var type: String?
    var brainState: String?
    var why: String?
    var ring: CadenceRing
    var startAt: String
    var endAt: String
    var description: String?
    var detail: ViewPacketJSONValue?
    var status: String?
    var actionState: CadenceBlockLifecycleState?
    var startedAt: String?
    var completedAt: String?
    var elapsedMinutes: Int?
    var progress: Double?
    var recalibrationChange: CadenceRecalibrationChange?
    var twsAnswer: Bool?
    var nudges: [CadenceNudge]
    var checklist: [CadenceChecklistItem]
    var subtasks: [Subtask]
    var mealInfo: BandishMealInfo?
    var sleepInfo: BandishSleepInfo?
    var meditationInfo: BandishMeditationInfo?
    // doctrine: silence-default + staleness-honesty. Workout data is additive
    // and optional so older daemon packets keep their existing rendering.
    var workoutInfo: BandishWorkoutInfo?
    var morningOrientation: BandishMorningOrientation?

    enum CodingKeys: String, CodingKey {
        case id
        case blockId
        case title
        case name
        case mode
        case attentionMode
        case type
        case kind
        case brainState
        case why
        case reason
        case ring
        case startAt
        case start
        case endAt
        case end
        case description
        case body
        case detail
        case status
        case state
        case actionState
        case startedAt
        case completedAt
        case completedAtSnake = "completed_at"
        case endedAt
        case finishedAt
        case elapsedMinutes
        case progress
        case recalibrationChange
        case twsAnswer
        case tws
        case wellSpent
        case nudge
        case rankedNudge
        case nudges
        case checklist
        case subtasks
        case mealInfo
        case sleepInfo
        case meditationInfo
        case workoutInfo
        case morningOrientation
    }

    init(
        id: String,
        title: String? = nil,
        mode: String = "cadence",
        type: String? = nil,
        brainState: String? = nil,
        why: String? = nil,
        ring: CadenceRing = .outer,
        startAt: String,
        endAt: String,
        description: String? = nil,
        detail: ViewPacketJSONValue? = nil,
        status: String? = nil,
        actionState: CadenceBlockLifecycleState? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
        elapsedMinutes: Int? = nil,
        progress: Double? = nil,
        recalibrationChange: CadenceRecalibrationChange? = nil,
        twsAnswer: Bool? = nil,
        nudges: [CadenceNudge] = [],
        checklist: [CadenceChecklistItem] = [],
        subtasks: [Subtask] = [],
        mealInfo: BandishMealInfo? = nil,
        sleepInfo: BandishSleepInfo? = nil,
        meditationInfo: BandishMeditationInfo? = nil,
        workoutInfo: BandishWorkoutInfo? = nil,
        morningOrientation: BandishMorningOrientation? = nil
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.type = type
        self.brainState = brainState
        self.why = why
        self.ring = ring
        self.startAt = startAt
        self.endAt = endAt
        self.description = description
        self.detail = detail
        self.status = status
        self.actionState = actionState
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.elapsedMinutes = elapsedMinutes
        self.progress = progress
        self.recalibrationChange = recalibrationChange
        self.twsAnswer = twsAnswer
        self.nudges = nudges
        self.checklist = checklist
        self.subtasks = subtasks
        self.mealInfo = mealInfo
        self.sleepInfo = sleepInfo
        self.meditationInfo = meditationInfo
        self.workoutInfo = workoutInfo
        self.morningOrientation = morningOrientation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decodeTrimmedString(for: .title)
            ?? container.decodeTrimmedString(for: .name)
        let decodedMode = try container.decodeTrimmedString(for: .attentionMode)
            ?? container.decodeTrimmedString(for: .mode)
            ?? "cadence"
        let decodedType = try container.decodeTrimmedString(for: .type)
            ?? container.decodeTrimmedString(for: .kind)
        let decodedBrainState = try container.decodeTrimmedString(for: .brainState)
        let decodedWhy = try container.decodeTrimmedString(for: .why)
            ?? container.decodeTrimmedString(for: .reason)
        let decodedStart = try container.decodeTrimmedString(for: .startAt)
            ?? container.decodeTrimmedString(for: .start)
            ?? ""
        let decodedEnd = try container.decodeTrimmedString(for: .endAt)
            ?? container.decodeTrimmedString(for: .end)
            ?? decodedStart

        let resolvedID = try container.decodeTrimmedString(for: .id)
            ?? container.decodeTrimmedString(for: .blockId)
            ?? Self.generatedID(title: decodedTitle, mode: decodedMode, startAt: decodedStart, endAt: decodedEnd)
        let decodedRing = (try? container.decode(CadenceRing.self, forKey: .ring)) ?? .unknown
        let decodedDescription = try container.decodeTrimmedString(for: .description)
            ?? container.decodeTrimmedString(for: .body)
        let decodedDetail = try? container.decodeIfPresent(ViewPacketJSONValue.self, forKey: .detail)
        let decodedStatus = try container.decodeTrimmedString(for: .status)
            ?? container.decodeTrimmedString(for: .state)
        let decodedActionState = try? container.decodeIfPresent(CadenceBlockLifecycleState.self, forKey: .actionState)
        let decodedStartedAt = try container.decodeTrimmedString(for: .startedAt)
        let decodedCompletedAt = try container.decodeTrimmedString(for: .completedAt)
            ?? container.decodeTrimmedString(for: .completedAtSnake)
            ?? container.decodeTrimmedString(for: .endedAt)
            ?? container.decodeTrimmedString(for: .finishedAt)
        let decodedElapsedMinutes = try container.decodeFlexibleInt(for: .elapsedMinutes)
        let decodedProgress = try container.decodeFlexibleDouble(for: .progress)
        let decodedRecalibrationChange = try? container.decodeIfPresent(
            CadenceRecalibrationChange.self,
            forKey: .recalibrationChange
        )
        let decodedTWSAnswer = try container.decodeFlexibleBool(for: .twsAnswer)
            ?? container.decodeFlexibleBool(for: .wellSpent)
            ?? container.decodeFlexibleBool(for: .tws)

        var decodedNudges = (try? container.decode(LossyCadenceArray<CadenceNudge>.self, forKey: .nudges).elements) ?? []
        if let nudge = try? container.decode(CadenceNudge.self, forKey: .nudge) {
            decodedNudges.append(nudge)
        }
        if let nudge = try? container.decode(CadenceNudge.self, forKey: .rankedNudge) {
            decodedNudges.append(nudge)
        }
        let normalizedNudges = decodedNudges.map { nudge in
            guard nudge.blockId == nil else { return nudge }
            var copy = nudge
            copy.blockId = resolvedID
            return copy
        }

        id = resolvedID
        title = decodedTitle
        mode = decodedMode
        type = decodedType
        brainState = decodedBrainState
        why = decodedWhy
        ring = decodedRing
        startAt = decodedStart
        endAt = decodedEnd
        description = decodedDescription
        detail = decodedDetail ?? nil
        status = decodedStatus
        actionState = decodedActionState ?? nil
        startedAt = decodedStartedAt
        completedAt = decodedCompletedAt
        elapsedMinutes = decodedElapsedMinutes
        progress = decodedProgress
        recalibrationChange = decodedRecalibrationChange ?? nil
        twsAnswer = decodedTWSAnswer
        nudges = normalizedNudges
        checklist = (try? container.decode(LossyCadenceArray<CadenceChecklistItem>.self, forKey: .checklist).elements) ?? []
        subtasks = (try? container.decode(LossyCadenceArray<Subtask>.self, forKey: .subtasks).elements) ?? []
        mealInfo = try? container.decodeIfPresent(BandishMealInfo.self, forKey: .mealInfo)
        sleepInfo = try? container.decodeIfPresent(BandishSleepInfo.self, forKey: .sleepInfo)
        meditationInfo = try? container.decodeIfPresent(BandishMeditationInfo.self, forKey: .meditationInfo)
        workoutInfo = try? container.decodeIfPresent(BandishWorkoutInfo.self, forKey: .workoutInfo)
        morningOrientation = try? container.decodeIfPresent(BandishMorningOrientation.self, forKey: .morningOrientation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(brainState, forKey: .brainState)
        try container.encodeIfPresent(why, forKey: .why)
        try container.encode(ring, forKey: .ring)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(endAt, forKey: .endAt)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(actionState, forKey: .actionState)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(elapsedMinutes, forKey: .elapsedMinutes)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(recalibrationChange, forKey: .recalibrationChange)
        try container.encodeIfPresent(twsAnswer, forKey: .twsAnswer)
        try container.encode(nudges, forKey: .nudges)
        try container.encode(checklist, forKey: .checklist)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encodeIfPresent(mealInfo, forKey: .mealInfo)
        try container.encodeIfPresent(sleepInfo, forKey: .sleepInfo)
        try container.encodeIfPresent(meditationInfo, forKey: .meditationInfo)
        try container.encodeIfPresent(workoutInfo, forKey: .workoutInfo)
        try container.encodeIfPresent(morningOrientation, forKey: .morningOrientation)
    }

    var normalizedTypeText: String? {
        let value = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.isEmpty == false ? value : nil
    }

    var whyText: String? {
        let value = why?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.isEmpty == false ? value : nil
    }

    var typeDetailText: String? {
        guard let detail else { return nil }
        let label = Self.detailLabel(for: normalizedTypeText)
        let keyed = label.flatMap { Self.detailText(in: detail, key: $0) }
        let text = keyed ?? Self.detailText(from: detail)
        guard let text else { return nil }
        if let label {
            return "\(label): \(text)".lowercased()
        }
        return text.lowercased()
    }

    var showsOpsChecklist: Bool {
        guard !checklist.isEmpty else { return false }
        let values = [mode, title ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return values.contains { value in
            value == "ops" || value.contains("ops") || value.contains("operation")
        }
    }

    var contentSubtasks: [Subtask]? {
        if !subtasks.isEmpty {
            return subtasks
        }
        let items = checklist.map(\.subtask)
        return items.isEmpty ? nil : items
    }

    var hasTypedContentContract: Bool {
        switch normalizedTypeText {
        case "work", "meal", "meditation", "workout", "sleep", "routine", "ops":
            return true
        default:
            return false
        }
    }

    private static func generatedID(title: String?, mode: String, startAt: String, endAt: String) -> String {
        let seed = [title, mode, startAt, endAt]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let sanitized = seed
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let value = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "cadence-block" : value
    }

    private static func detailLabel(for type: String?) -> String? {
        switch type {
        case "meal":
            return "items"
        case "meditation":
            return "practice"
        case "workout":
            return "plan"
        default:
            return nil
        }
    }

    private static func detailText(in value: ViewPacketJSONValue, key: String) -> String? {
        guard let object = value.objectValue else { return nil }
        return detailText(from: object[key])
    }

    private static func detailText(from value: ViewPacketJSONValue?) -> String? {
        guard let value else { return nil }
        let text: String
        if let array = value.arrayValue {
            text = array
                .map(\.description)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } else {
            text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }
}

struct CadenceDayEnvelope: Codable, Equatable, Sendable {
    var date: String?
    var bandish: [CadenceBlock]
    var capacityByMode: [String: Double]
    var remainingCapacityByMode: [String: Double]
    var nowBlock: CadenceBlock?
    var nowBlockId: String?
    var nextBlock: CadenceBlock?
    var nextBlockId: String?
    var caption: String?
    var recalibration: CadenceRecalibrationSummary?
    var recalibrationChanges: [CadenceRecalibrationChange]?

    enum CodingKeys: String, CodingKey {
        case date
        case bandish
        case blocks
        case capacityByMode
        case remainingCapacity
        case nowBlock
        case nextBlock
        case caption
        case recalibration
        case recalibrationChanges
    }

    init(
        date: String? = nil,
        bandish: [CadenceBlock] = [],
        capacityByMode: [String: Double] = [:],
        remainingCapacityByMode: [String: Double] = [:],
        nowBlock: CadenceBlock? = nil,
        nowBlockId: String? = nil,
        nextBlock: CadenceBlock? = nil,
        nextBlockId: String? = nil,
        caption: String? = nil,
        recalibration: CadenceRecalibrationSummary? = nil,
        recalibrationChanges: [CadenceRecalibrationChange]? = nil
    ) {
        self.date = date
        self.bandish = bandish
        self.capacityByMode = capacityByMode
        self.remainingCapacityByMode = remainingCapacityByMode
        self.nowBlock = nowBlock
        self.nowBlockId = nowBlockId
        self.nextBlock = nextBlock
        self.nextBlockId = nextBlockId
        self.caption = caption
        self.recalibration = recalibration
        self.recalibrationChanges = recalibrationChanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeTrimmedString(for: .date)
        bandish = (try? container.decode(LossyCadenceArray<CadenceBlock>.self, forKey: .bandish).elements)
            ?? (try? container.decode(LossyCadenceArray<CadenceBlock>.self, forKey: .blocks).elements)
            ?? []
        capacityByMode = (try? container.decode([String: FlexibleCadenceDouble].self, forKey: .capacityByMode)
            .mapValues(\.value)) ?? [:]
        remainingCapacityByMode = (try? container.decode([String: FlexibleCadenceDouble].self, forKey: .remainingCapacity)
            .mapValues(\.value)) ?? [:]

        if let block = try? container.decode(CadenceBlock.self, forKey: .nowBlock) {
            nowBlock = block
            nowBlockId = block.id
        } else {
            nowBlock = nil
            nowBlockId = try container.decodeTrimmedString(for: .nowBlock)
        }

        if let block = try? container.decode(CadenceBlock.self, forKey: .nextBlock) {
            nextBlock = block
            nextBlockId = block.id
        } else {
            nextBlock = nil
            nextBlockId = try container.decodeTrimmedString(for: .nextBlock)
        }

        caption = try container.decodeTrimmedString(for: .caption)
        recalibration = try? container.decodeIfPresent(CadenceRecalibrationSummary.self, forKey: .recalibration)
        recalibrationChanges = try? container.decodeIfPresent(
            LossyCadenceArray<CadenceRecalibrationChange>.self,
            forKey: .recalibrationChanges
        )?.elements
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(bandish, forKey: .bandish)
        try container.encode(capacityByMode, forKey: .capacityByMode)
        try container.encode(remainingCapacityByMode, forKey: .remainingCapacity)
        if let nowBlock {
            try container.encode(nowBlock, forKey: .nowBlock)
        } else {
            try container.encodeIfPresent(nowBlockId, forKey: .nowBlock)
        }
        if let nextBlock {
            try container.encode(nextBlock, forKey: .nextBlock)
        } else {
            try container.encodeIfPresent(nextBlockId, forKey: .nextBlock)
        }
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(recalibration, forKey: .recalibration)
        try container.encodeIfPresent(recalibrationChanges, forKey: .recalibrationChanges)
    }

    var resolvedBandish: [CadenceBlock] {
        var blocks = bandish
        if let nowBlock, !blocks.contains(where: { $0.id == nowBlock.id }) {
            blocks.append(nowBlock)
        }
        if let nextBlock, !blocks.contains(where: { $0.id == nextBlock.id }) {
            blocks.append(nextBlock)
        }
        return blocks
    }

    static func defaultTemplate(date: Date = Date(), calendar: Calendar = CadenceDateParser.pinnedCalendar) -> CadenceDayEnvelope {
        let dateText = CadenceDateParser.dayString(for: date, calendar: calendar)
        return CadenceDayEnvelope(
            date: dateText,
            bandish: [
                CadenceBlock(
                    id: "default-orient",
                    title: "orient",
                    mode: "restore",
                    type: "routine",
                    why: "set the day's shape",
                    ring: .outer,
                    startAt: "\(dateText)T08:00:00",
                    endAt: "\(dateText)T08:30:00",
                    description: "morning orientation"
                ),
                CadenceBlock(
                    id: "default-core",
                    title: "core work",
                    mode: "converge",
                    type: "work",
                    why: "the one thing that compounds",
                    ring: .core,
                    startAt: "\(dateText)T09:00:00",
                    endAt: "\(dateText)T12:00:00",
                    description: "deep block"
                ),
                CadenceBlock(
                    id: "default-middle",
                    title: "middle",
                    mode: "operative",
                    type: "ops",
                    why: "clear the operational queue",
                    ring: .middle,
                    startAt: "\(dateText)T13:00:00",
                    endAt: "\(dateText)T16:00:00",
                    description: "operational block"
                ),
                CadenceBlock(
                    id: "default-reflect",
                    title: "reflect",
                    mode: "restore",
                    type: "meditation",
                    why: "close the day with a settled mind",
                    ring: .outer,
                    startAt: "\(dateText)T20:00:00",
                    endAt: "\(dateText)T20:30:00",
                    description: "evening reflection"
                ),
            ],
            caption: CadenceCopy.defaultDayCaption
        )
    }
}

