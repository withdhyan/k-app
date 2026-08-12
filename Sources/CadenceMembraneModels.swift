import Foundation
import SwiftUI
import UIKit
struct CadenceActResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var day: CadenceDayEnvelope?
    var recalibration: CadenceRecalibrationSummary?
    var alreadyActed: CadenceAlreadyActed?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case day
        case plan
        case recalibration
        case alreadyActed
        case alreadyAnswered
        case firstWrite
        case kept
        case winner
        case existing
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try? container.decodeIfPresent(Bool.self, forKey: .ok)
        day = (try? container.decodeIfPresent(CadenceDayEnvelope.self, forKey: .day))
            ?? (try? container.decodeIfPresent(CadenceDayEnvelope.self, forKey: .plan))
        recalibration = try? container.decodeIfPresent(CadenceRecalibrationSummary.self, forKey: .recalibration)
        alreadyActed = nil
        for key in [CodingKeys.alreadyActed, .alreadyAnswered, .firstWrite, .kept, .winner, .existing] {
            if let decoded = try? container.decodeIfPresent(CadenceAlreadyActed.self, forKey: key) {
                alreadyActed = decoded
                break
            }
        }
        error = try container.decodeTrimmedString(for: .error)
    }

    var firstWriteSurface: String? {
        alreadyActed?.surfaceText
    }

    var isFirstWriteConflict: Bool {
        if alreadyActed != nil { return true }
        let value = error?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.contains("already") || value.contains("conflict") || value.contains("first-write") || value.contains("first write")
    }
}

struct CadenceAlreadyActed: Decodable, Equatable, Sendable {
    var surface: String?
    var by: String?
    var action: CadenceBlockAction?

    enum CodingKeys: String, CodingKey {
        case surface
        case source
        case answerSurface
        case by
        case actor
        case answeredBy
        case action
        case keptAction
        case existingAction
        case answer
    }

    init(surface: String? = nil, by: String? = nil, action: CadenceBlockAction? = nil) {
        self.surface = surface
        self.by = by
        self.action = action
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            surface = value
            by = nil
            action = CadenceBlockAction.serverValue(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        surface = try container.decodeTrimmedString(for: .surface)
            ?? container.decodeTrimmedString(for: .source)
            ?? container.decodeTrimmedString(for: .answerSurface)
        by = try container.decodeTrimmedString(for: .by)
            ?? container.decodeTrimmedString(for: .actor)
            ?? container.decodeTrimmedString(for: .answeredBy)
        let actionText = try container.decodeTrimmedString(for: .action)
            ?? container.decodeTrimmedString(for: .keptAction)
            ?? container.decodeTrimmedString(for: .existingAction)
            ?? container.decodeTrimmedString(for: .answer)
        action = CadenceBlockAction.serverValue(actionText)
    }

    var surfaceText: String? {
        let value = surface ?? by
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct CadenceReviewAnswerResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var card: CadenceReviewCard?
    var error: String?
}

struct CadenceNudgeDispositionResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var nudge: CadenceNudge?
    var error: String?
}

// ---- membrane compare (cadence rescore, advisory rung) ----
// The membrane re-scores the live day and offers one higher-scoring next block
// (the challenger) against the block the founder is about to live (the
// incumbent). The founder's take/keep answer is a comparison verdict — the
// membrane never moves the day; it only learns (v1 filter/advisory rung).

struct CadenceRescoreHeadline: Decodable, Equatable, Sendable {
    var candidateBlockId: String? = nil
    var incumbentBlockId: String? = nil
    var evalDelta: Double? = nil
}

struct CadenceRescoreResponse: Decodable, Equatable, Sendable {
    var ok: Bool? = nil
    var date: String? = nil
    var surface: Bool? = nil
    var reason: String? = nil
    var headline: CadenceRescoreHeadline? = nil
    var alternativeDay: CadenceDayEnvelope? = nil
    var error: String? = nil
}

struct CadenceRescoreCompareResponse: Decodable, Equatable, Sendable {
    var ok: Bool?
    var changed: Bool?
    var error: String?
}

/// The one challenger the compare surface presents at a seam. Derived per tick
/// by `CadenceMembraneCompareLogic`; nil is earned silence.
struct CadenceMembraneCompareModel: Equatable {
    var date: String
    var candidateBlockId: String
    var incumbentBlockId: String
    var incumbentTitle: String
    var challengerTitle: String
    var challengerTimeText: String
    var challengerRing: CadenceRing
    var deltaText: String
}

enum CadenceMembraneCopy {
    // Staleness honesty (doctrine): the v1 signal is a per-day recovery-adjacent
    // proxy from nightly hrv — never presented as live per-moment stress.
    static let basisLine = "basis · today's hrv vs your 14 day baseline · daily, not this moment"
    // The tap's whole mechanical truth: it trains the membrane's verdict corpus;
    // the day template moves only through the founder's own acts.
    static let trainsLine = "trains k · the day moves only when you do"
    static let takeAct = "take"
    static let keepAct = "keep"
    static let saveFailed = "verdict didn't save · tap take or keep again"

    static func tookEcho(_ title: String) -> String {
        "took · \(title.lowercased())"
    }

    static func keptEcho(_ title: String) -> String {
        "kept · \(title.lowercased())"
    }

    static func deltaText(_ evalDelta: Double) -> String {
        let percent = Int((evalDelta * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "\(percent)%"
    }
}

/// Founder-answered comparison verdicts, persisted so an already-judged seam
/// never re-presents after relaunch (the rescore GET recomputes fresh and
/// carries no verdict state). Local echo only — the daemon owns the record.
struct CadenceMembraneVerdictStore {
    static let defaultsKey = "cskMembraneVerdicts"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(date: String, candidateBlockId: String) -> String {
        "\(date)|\(candidateBlockId)"
    }

    func load() -> [String: Bool] {
        (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Bool]) ?? [:]
    }

    func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    func save(_ verdicts: [String: Bool], date: String) {
        // Keep only the live day — stale seams never re-present, so old keys
        // are dead weight.
        let pruned = verdicts.filter { $0.key.hasPrefix("\(date)|") }
        defaults.set(pruned, forKey: Self.defaultsKey)
    }
}

enum CadenceMembraneCompareLogic {
    /// Seam + congruence gate. The challenger presents only when every clause
    /// holds; any doubt is silence (invariant 7), never a stale or mid-flow cue.
    static func compareModel(
        rescore: CadenceRescoreResponse?,
        presentation: CadenceDayPresentation,
        localVerdicts: [String: Bool],
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> CadenceMembraneCompareModel? {
        guard let rescore,
              rescore.ok != false,
              rescore.surface == true,
              let headline = rescore.headline,
              let candidateBlockId = headline.candidateBlockId,
              let incumbentBlockId = headline.incumbentBlockId,
              let evalDelta = headline.evalDelta,
              evalDelta > 0
        else { return nil }

        // The rescore must describe the day on screen, not a cached other day.
        let date = rescore.date ?? presentation.dateText
        guard date == presentation.dateText else { return nil }

        // Seam only: the incumbent renders as the unstarted current card. A
        // started block anywhere means mid-flow; a passed window is a stale
        // seam; the wake gate and a resident nudge each already own the card.
        guard let incumbent = presentation.nowBlock,
              incumbent.block.id == incumbentBlockId,
              incumbent.actionState == .available,
              !incumbent.hasEnded,
              !incumbent.startsDay,
              !incumbent.isPending,
              incumbent.nudge == nil
        else { return nil }
        guard !presentation.blocks.contains(where: { $0.actionState == .started }) else { return nil }

        // One verdict per seam per day — an answered compare stays collapsed.
        guard localVerdicts[CadenceMembraneVerdictStore.key(
            date: date,
            candidateBlockId: candidateBlockId
        )] == nil else { return nil }

        // The challenger's projected block carries the incumbent's slot (the
        // membrane proposes it for this seam, not its original time).
        guard let challenger = rescore.alternativeDay?.resolvedBandish
            .first(where: { $0.id == candidateBlockId })
        else { return nil }
        let challengerTitle = (challenger.title
            ?? challenger.description?.components(separatedBy: CharacterSet.newlines).first
            ?? challenger.mode).lowercased()
        guard !challengerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return CadenceMembraneCompareModel(
            date: date,
            candidateBlockId: candidateBlockId,
            incumbentBlockId: incumbentBlockId,
            incumbentTitle: incumbent.titleText,
            challengerTitle: challengerTitle,
            challengerTimeText: CadenceDateParser.startTimeText(
                for: challenger,
                dayDate: date,
                calendar: calendar
            ),
            challengerRing: challenger.ring,
            deltaText: CadenceMembraneCopy.deltaText(evalDelta)
        )
    }
}

// Demo seed for the membrane compare, mirroring BioDemo: off by default, enabled
// by the `-membranedemo` launch arg or the `cskMembraneDemo` UserDefault. Used
// only when no real rescore loaded; fabricated entirely from the rendered day.
// A demo verdict NEVER posts — five better:true writes would graduate the real
// membrane on synthetic data (GRADUATION_N=5), poisoning the shadow-gate corpus.
enum CadenceMembraneDemo {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-membranedemo")
            || UserDefaults.standard.bool(forKey: "cskMembraneDemo")
    }

    /// Day seed only, no challenger — the compare surface's resting state.
    static var showsDemoDay: Bool {
        enabled || ProcessInfo.processInfo.arguments.contains("-membranedemoday")
    }

    /// Capture fixtures own a stable local-noon clock. The opened day may
    /// follow the device day, but temporal state never follows wall-clock
    /// drift while the evidence walk is running.
    static let fixtureNow: Date = CadenceWorkoutDemo.openingInstant()

    static let demoEvalDelta = 0.18

    /// A clearly-synthetic day anchored to the clock so a seam exists whenever
    /// the demo runs (the fixed default template has between-block gaps most
    /// hours). Keep the offsets as real dates so the seam remains valid across
    /// midnight instead of being collapsed by a clock-only clamp.
    static func demoDay(
        now: Date,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> CadenceDayEnvelope {
        let dateText = CadenceDateParser.dayString(for: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        func clock(_ offsetMinutes: Int) -> String {
            let shifted = calendar.date(byAdding: .minute, value: offsetMinutes, to: now) ?? now
            return formatter.string(from: shifted)
        }
        return CadenceDayEnvelope(
            date: dateText,
            bandish: [
                CadenceBlock(
                    id: "demo-orient",
                    title: "orient",
                    mode: "restore",
                    type: "routine",
                    why: "set the day's shape",
                    ring: .outer,
                    startAt: clock(-120),
                    endAt: clock(-90)
                ),
                CadenceBlock(
                    id: "demo-core-work",
                    title: "core work",
                    mode: "converge",
                    type: "work",
                    why: "the one thing that compounds",
                    ring: .core,
                    startAt: clock(-45),
                    endAt: clock(75)
                ),
                CadenceBlock(
                    id: "demo-deep-work",
                    title: "deep work",
                    mode: "converge",
                    type: "work",
                    why: "protect the focus window",
                    ring: .core,
                    startAt: clock(90),
                    endAt: clock(180)
                ),
                CadenceBlock(
                    id: "demo-reflect",
                    title: "reflect",
                    mode: "restore",
                    type: "meditation",
                    why: "close the day with a settled mind",
                    ring: .outer,
                    startAt: clock(195),
                    endAt: clock(225)
                ),
            ],
            caption: CadenceCopy.defaultDayCaption
        )
    }

    static func rescore(for presentation: CadenceDayPresentation) -> CadenceRescoreResponse? {
        guard let incumbent = presentation.nowBlock else { return nil }
        let challengerSource = presentation.blocks.first { block in
            block.id != incumbent.id
                && !block.isNow
                && !block.hasEnded
                && block.actionState == .available
                && block.block.normalizedTypeText == "work"
        } ?? presentation.blocks.first { block in
            block.id != incumbent.id
                && !block.isNow
                && !block.hasEnded
                && block.actionState == .available
        }
        guard let challengerSource else { return nil }
        // Project the challenger into the incumbent's slot, as the daemon does.
        var challenger = challengerSource.block
        challenger.startAt = incumbent.block.startAt
        challenger.endAt = incumbent.block.endAt
        return CadenceRescoreResponse(
            ok: true,
            date: presentation.dateText,
            surface: true,
            reason: "higher_eval",
            headline: CadenceRescoreHeadline(
                candidateBlockId: challenger.id,
                incumbentBlockId: incumbent.id,
                evalDelta: demoEvalDelta
            ),
            alternativeDay: CadenceDayEnvelope(
                date: presentation.dateText,
                bandish: [challenger]
            )
        )
    }
}

// doctrine: silence-default + optimism-with-proof. The workout fixture is
// capture-only, deterministic, and never reaches the daemon or the live body
// stream. Factory WHOOP wiring can populate the same optional `workoutInfo` later.
enum CadenceWorkoutDemo {
    enum State: String, CaseIterable, Equatable, Sendable {
        case pre
        case mid
        case post
    }

    /// The fixture owns a seed-anchor clock while it is enabled. Keeping the
    /// day and time fixed makes every capture independent of the device clock.
    static let fixtureNow = Date(timeIntervalSince1970: 1_786_363_200) // 2026-08-10 12:00 UTC

    static func openingInstant(
        openedAt: Date = Date(),
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: openedAt)
        components.hour = 12
        components.minute = .zero
        components.second = .zero
        components.nanosecond = .zero
        return calendar.date(from: components) ?? openedAt
    }

    static var state: State? { state(arguments: ProcessInfo.processInfo.arguments) }

    static var enabled: Bool { state != nil }

    static func state(arguments: [String]) -> State? {
        if arguments.contains("-workoutdemo-pre") { return .pre }
        if arguments.contains("-workoutdemo-mid") { return .mid }
        if arguments.contains("-workoutdemo-post") { return .post }
        guard let index = arguments.firstIndex(of: "-workoutdemo") else { return nil }
        if let stateIndex = arguments.firstIndex(of: "-workoutdemo-state"),
           arguments.indices.contains(stateIndex + 1),
           let value = State(rawValue: arguments[stateIndex + 1].lowercased()) {
            return value
        }
        if arguments.indices.contains(index + 1),
           let value = State(rawValue: arguments[index + 1].lowercased()) {
            return value
        }
        return .mid
    }

    static func day(
        state: State = CadenceWorkoutDemo.state ?? .mid,
        now: Date = fixtureNow,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> CadenceDayEnvelope {
        let dateText = CadenceDateParser.dayString(for: now, calendar: calendar)
        func clock(_ offsetMinutes: Int) -> String {
            let date = calendar.date(byAdding: .minute, value: offsetMinutes, to: now) ?? now
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        func isoClock(_ offsetMinutes: Int) -> String {
            "\(dateText)T\(clock(offsetMinutes)):00"
        }

        let workoutInfo: BandishWorkoutInfo
        let actionState: CadenceBlockLifecycleState
        let status: String?
        let startOffset: Int
        let endOffset: Int
        let startedAt: String?
        let completedAt: String?
        switch state {
        case .pre:
            workoutInfo = preWorkoutInfo
            actionState = .available
            status = nil
            startOffset = -10
            endOffset = 50
            startedAt = nil
            completedAt = nil
        case .mid:
            workoutInfo = midWorkoutInfo
            actionState = .started
            status = "started"
            startOffset = -10
            endOffset = 50
            startedAt = isoClock(-10)
            completedAt = nil
        case .post:
            workoutInfo = completedWorkoutInfo
            actionState = .completed
            status = "complete"
            startOffset = -90
            endOffset = -30
            startedAt = isoClock(-90)
            completedAt = isoClock(-30)
        }

        let workout = CadenceBlock(
            id: "demo-workout",
            title: "strength · pull day",
            mode: "physical",
            type: "workout",
            why: "keep the body budget honest",
            ring: .core,
            startAt: clock(startOffset),
            endAt: clock(endOffset),
            description: "strength · pull day",
            status: status,
            actionState: actionState,
            startedAt: startedAt,
            completedAt: completedAt,
            elapsedMinutes: state == .post ? 60 : (state == .mid ? 10 : nil),
            workoutInfo: workoutInfo
        )

        let before = CadenceBlock(
            id: "demo-workout-before",
            title: "walk",
            mode: "restore",
            type: "routine",
            why: "arrive in the body",
            ring: .outer,
            startAt: clock(-130),
            endAt: clock(-100),
            status: "complete",
            actionState: .completed,
            completedAt: isoClock(-100)
        )
        let after = CadenceBlock(
            id: "demo-workout-after",
            title: "refuel",
            mode: "restore",
            type: "meal",
            why: "replace what the session used",
            ring: .outer,
            startAt: clock(70),
            endAt: clock(100)
        )

        return CadenceDayEnvelope(
            date: dateText,
            bandish: [before, workout, after],
            caption: "workout depth · seeded whoop read"
        )
    }

    private static let preWorkoutInfo = BandishWorkoutInfo(
        exercises: exercises,
        strain: BandishWorkoutStrain(actual: nil, target: 16),
        tonnage: BandishWorkoutTonnage(current: nil, previous: 4_520, change: nil),
        heartRateZones: zeroZones,
        realTime: BandishWorkoutRealtime(currentZone: nil, isActive: false, heartRate: nil),
        calories: nil,
        effortCurve: [0.08, 0.08, 0.10, 0.09, 0.10],
        recoveryHint: nil,
        source: "whoop"
    )

    private static let midWorkoutInfo = BandishWorkoutInfo(
        exercises: exercises,
        strain: BandishWorkoutStrain(actual: 7.8, target: 16),
        tonnage: BandishWorkoutTonnage(current: 2_180, previous: 4_520, change: nil),
        heartRateZones: [
            BandishWorkoutZone(zone: 1, minutes: 3),
            BandishWorkoutZone(zone: 2, minutes: 8),
            BandishWorkoutZone(zone: 3, minutes: 10),
            BandishWorkoutZone(zone: 4, minutes: 2),
            BandishWorkoutZone(zone: 5, minutes: 0),
        ],
        realTime: BandishWorkoutRealtime(currentZone: 3, isActive: true, heartRate: 148),
        calories: 214,
        effortCurve: [0.12, 0.20, 0.36, 0.49, 0.58, 0.64, 0.70],
        recoveryHint: nil,
        source: "whoop"
    )

    private static let completedWorkoutInfo = BandishWorkoutInfo(
        exercises: exercises,
        strain: BandishWorkoutStrain(actual: 14.2, target: 16),
        tonnage: BandishWorkoutTonnage(current: 4_820, previous: 4_520, change: 6.6),
        heartRateZones: [
            BandishWorkoutZone(zone: 1, minutes: 4),
            BandishWorkoutZone(zone: 2, minutes: 12),
            BandishWorkoutZone(zone: 3, minutes: 18),
            BandishWorkoutZone(zone: 4, minutes: 10),
            BandishWorkoutZone(zone: 5, minutes: 1),
        ],
        realTime: BandishWorkoutRealtime(currentZone: nil, isActive: false, heartRate: 142),
        calories: 412,
        effortCurve: [0.10, 0.22, 0.42, 0.60, 0.78, 0.68, 0.88, 0.46],
        recoveryHint: "leave tomorrow's work room",
        source: "whoop"
    )

    private static let exercises = [
        BandishWorkoutExercise(id: "pull-down", name: "pull down", setsRepsWeight: "4 × 8 · 60 kg", completed: true),
        BandishWorkoutExercise(id: "single-row", name: "single arm row", setsRepsWeight: "4 × 10 · 32 kg", completed: true),
        BandishWorkoutExercise(id: "farmer-carry", name: "farmer carry", setsRepsWeight: "3 × 40 m", completed: false),
    ]

    private static let zeroZones = (1...5).map { BandishWorkoutZone(zone: $0) }
}

enum CadenceDemoClock {
    static func now() -> Date {
        if CadenceWorkoutDemo.enabled { return CadenceWorkoutDemo.fixtureNow }
        if CadenceMembraneDemo.showsDemoDay { return CadenceMembraneDemo.fixtureNow }
        return Date()
    }
}
