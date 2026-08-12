import Foundation
import SwiftUI
import UIKit
enum CadenceTimelineOrdering {
    static func streamBlocks(
        for presentation: CadenceDayPresentation,
        showsEarlier: Bool
    ) -> [CadenceBlockPresentation] {
        let base = showsEarlier
            ? presentation.previousTimelineBlocks + presentation.visibleTimelineBlocks
            : presentation.visibleTimelineBlocks
        // The now-block is lifted to its own card above the list (mock cadence-v7).
        return base.filter { !$0.isNow }
    }
}

extension KBlockActionState {
    var cadenceLifecycleState: CadenceBlockLifecycleState {
        switch self {
        case .available:
            return .available
        case .started:
            return .started
        case .completed:
            return .completed
        }
    }
}

enum CadenceCopy {
    static let defaultDayCaption = "your usual rhythm · k hasn't drafted today"
    static let offlineSavedPlan = "showing saved plan"
}

enum CadenceDateParser {
    // Server dates are Gregorian ISO (yyyy-MM-dd). A device set to a Buddhist or
    // Japanese calendar must not re-interpret them (observed live: header year 2569),
    // so every formatter pins Gregorian and keeps only the device timezone.
    static var pinnedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }

    static func dayString(for date: Date, calendar: Calendar? = nil) -> String {
        let calendar = calendar ?? pinnedCalendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func interval(
        for block: CadenceBlock,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> (start: Date, end: Date)? {
        guard let start = date(from: block.startAt, dayDate: dayDate, calendar: calendar) else { return nil }
        let parsedEnd = date(from: block.endAt, dayDate: dayDate, calendar: calendar) ?? start
        let end = parsedEnd < start ? calendar.date(byAdding: .day, value: 1, to: parsedEnd) ?? parsedEnd : parsedEnd
        return (start, end)
    }

    static func timeRangeText(
        for block: CadenceBlock,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String {
        guard let interval = interval(for: block, dayDate: dayDate, calendar: calendar) else {
            return [block.startAt, block.endAt]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
        return "\(timeText(for: interval.start, calendar: calendar))-\(timeText(for: interval.end, calendar: calendar))"
    }

    static func timelineGutterText(
        for block: CadenceBlock,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String {
        guard let interval = interval(for: block, dayDate: dayDate, calendar: calendar) else {
            return block.startAt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let durationMinutes = max(0, Int(ceil(interval.end.timeIntervalSince(interval.start) / 60)))
        return "\(timeText(for: interval.start, calendar: calendar))\n\(durationClockText(durationMinutes))"
    }

    static func startTimeText(
        for block: CadenceBlock,
        dayDate: String?,
        calendar: Calendar = CadenceDateParser.pinnedCalendar
    ) -> String {
        guard let interval = interval(for: block, dayDate: dayDate, calendar: calendar) else {
            return block.startAt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return timeText(for: interval.start, calendar: calendar)
    }

    static func date(from text: String, dayDate: String?, calendar: Calendar = CadenceDateParser.pinnedCalendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            if let date = dateFormatter(format: format, calendar: calendar).date(from: trimmed) {
                return date
            }
        }

        guard let dayDate else { return nil }
        let timeFormats = trimmed.count <= 5 ? ["HH:mm", "H:mm"] : ["HH:mm:ss", "H:mm:ss", "HH:mm", "H:mm"]
        for format in timeFormats {
            if let time = dateFormatter(format: format, calendar: calendar).date(from: trimmed),
               let day = dateFormatter(format: "yyyy-MM-dd", calendar: calendar).date(from: dayDate) {
                let timeParts = calendar.dateComponents([.hour, .minute, .second], from: time)
                var dayParts = calendar.dateComponents([.year, .month, .day], from: day)
                dayParts.hour = timeParts.hour
                dayParts.minute = timeParts.minute
                dayParts.second = timeParts.second
                return calendar.date(from: dayParts)
            }
        }
        return nil
    }

    private static func timeText(for date: Date, calendar: Calendar) -> String {
        let formatter = dateFormatter(format: "HH:mm", calendar: calendar)
        return formatter.string(from: date).lowercased()
    }

    static func durationClockText(_ minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let remainder = clamped % 60
        return "\(hours):\(String(format: "%02d", remainder))"
    }

    private static func dateFormatter(format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

struct CadenceDayCacheStore {
    private struct StoredDay: Codable {
        var version: Int
        var date: String?
        var day: CadenceDayEnvelope
        var savedAt: Date?
    }

    struct CachedDay: Equatable {
        var day: CadenceDayEnvelope
        var savedAt: Date
        var date: String?
    }

    let fileURL: URL
    let fileManager: FileManager

    init(
        fileURL: URL = CadenceDayCacheStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("cadence-day.json", isDirectory: false)
    }

    func load() -> CadenceDayEnvelope? {
        loadEntry()?.day
    }

    func loadEntry() -> CachedDay? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            if let stored = try? JSONDecoder().decode(StoredDay.self, from: data),
               (1...3).contains(stored.version) {
                return CachedDay(
                    day: stored.day,
                    savedAt: stored.savedAt ?? fileModifiedAt(),
                    date: stored.date ?? stored.day.date
                )
            }
            let day = try JSONDecoder().decode(CadenceDayEnvelope.self, from: data)
            return CachedDay(day: day, savedAt: fileModifiedAt(), date: day.date)
        } catch {
            NSLog("[K] cadence day cache load failed at %@: %@", fileURL.path, String(describing: error))
            return nil
        }
    }

    func save(_ day: CadenceDayEnvelope, syncedAt: Date = Date()) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(StoredDay(version: 3, date: day.date, day: day, savedAt: syncedAt))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] cadence day cache save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    private func fileModifiedAt() -> Date {
        ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date) ?? Date(timeIntervalSince1970: 0)
    }
}

struct CadenceQueuedAct: Codable, Equatable, Identifiable, Sendable {
    static let wakeInitBlockId = "__wake_init__"

    var blockId: String
    var action: CadenceBlockAction
    var enqueuedAt: Date

    var id: String {
        "\(blockId)::\(action.rawValue)::\(enqueuedAt.timeIntervalSinceReferenceDate)"
    }

    var isWakeInit: Bool {
        action == .wakeInit || blockId == Self.wakeInitBlockId
    }
}

enum CadenceMealLogSubmitResult: Equatable {
    case success(String)
    case failure(String)
}

enum CadenceValueProbeSubmitResult: Equatable {
    case success
    case failure(String)
}

struct CadenceActQueueStore {
    private struct StoredQueue: Codable {
        var version: Int
        var actions: [CadenceQueuedAct]
    }

    let fileURL: URL
    let fileManager: FileManager

    init(
        fileURL: URL = CadenceActQueueStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("cadence-act-queue.json", isDirectory: false)
    }

    func load() -> [CadenceQueuedAct] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            if let stored = try? JSONDecoder().decode(StoredQueue.self, from: data), stored.version == 1 {
                return stored.actions
            }
            return try JSONDecoder().decode([CadenceQueuedAct].self, from: data)
        } catch {
            NSLog("[K] cadence act queue load failed at %@: %@", fileURL.path, String(describing: error))
            return []
        }
    }

    func save(_ actions: [CadenceQueuedAct]) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if actions.isEmpty {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
                return
            }
            let data = try JSONEncoder().encode(StoredQueue(version: 1, actions: actions))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[K] cadence act queue save failed at %@: %@", fileURL.path, String(describing: error))
        }
    }

    func append(_ action: CadenceQueuedAct) {
        var actions = load()
        actions.append(action)
        save(actions)
    }

    func upsert(_ action: CadenceQueuedAct) {
        append(action)
    }

    func remove(_ action: CadenceQueuedAct) {
        save(load().filter { $0 != action })
    }

}
