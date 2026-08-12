import SwiftUI

enum KConnectionStatus: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case offlineRetrying
    case tailnetNeeded

    var text: String {
        switch self {
        case .idle:
            return "idle"
        case .connecting:
            return KCopy.connecting
        case .live:
            return KCopy.live
        case .reconnecting:
            return KCopy.reconnecting
        case .offlineRetrying:
            return KCopy.offlineRetrying
        case .tailnetNeeded:
            return KCopy.tailnetNeeded
        }
    }
}

enum KConnectionSignal: Equatable {
    case idle
    case live
    case reconnecting
    case offline

    enum Condition: String, Equatable {
        case idle
        case live
        case degraded
        case down
    }

    var kSignal: KSignal {
        switch self {
        case .idle:
            return .idle
        case .live:
            return .live
        case .reconnecting:
            return .attention
        case .offline:
            return .offline
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .white.opacity(KStyle.quaternaryTextOpacity)
        case .live:
            return KStyle.liveSignal
        case .reconnecting:
            return KStyle.signalWarning
        case .offline:
            return KStyle.signalFailure
        }
    }

    var condition: Condition {
        switch self {
        case .idle:
            return .idle
        case .live:
            return .live
        case .reconnecting:
            return .degraded
        case .offline:
            return .down
        }
    }

    var breathes: Bool {
        condition == .degraded || condition == .down
    }

    var colorHex: String? {
        switch self {
        case .idle:
            return nil
        case .live:
            return nil
        case .reconnecting:
            return KStyle.signalWarningToken.hex
        case .offline:
            return KStyle.signalFailureToken.hex
        }
    }

    var accessibilityLabel: String {
        switch condition {
        case .idle:
            return "connection idle, tap to retry"
        case .live:
            return "connection live, tap to retry"
        case .degraded:
            return "connection degraded, tap to retry"
        case .down:
            return "connection down, tap to retry"
        }
    }
}

struct KConnectionPresentation: Equatable {
    var word: String?
    var signal: KConnectionSignal
    var inputsDisabledReason: String?

    var inputsEnabled: Bool {
        inputsDisabledReason == nil
    }
}

struct KConnectionStateModel: Equatable {
    static let connectingWordDuration: TimeInterval = 2
    static let liveWordDuration: TimeInterval = 3

    private(set) var status: KConnectionStatus
    private(set) var changedAt: Date

    init(status: KConnectionStatus = .idle, changedAt: Date = Date()) {
        self.status = status
        self.changedAt = changedAt
    }

    mutating func transition(to status: KConnectionStatus, now: Date = Date()) {
        guard self.status != status else { return }
        self.status = status
        changedAt = now
    }

    func presentation(now: Date = Date()) -> KConnectionPresentation {
        let age = now.timeIntervalSince(changedAt)
        switch status {
        case .idle:
            return KConnectionPresentation(word: nil, signal: .idle, inputsDisabledReason: nil)
        case .connecting:
            return KConnectionPresentation(
                word: age <= Self.connectingWordDuration ? KCopy.connecting : nil,
                signal: .reconnecting,
                inputsDisabledReason: nil
            )
        case .live:
            return KConnectionPresentation(
                word: age <= Self.liveWordDuration ? KCopy.live : nil,
                signal: .live,
                inputsDisabledReason: nil
            )
        case .reconnecting:
            return KConnectionPresentation(word: KCopy.reconnecting, signal: .reconnecting, inputsDisabledReason: nil)
        case .offlineRetrying:
            return KConnectionPresentation(word: KCopy.offlineRetrying, signal: .offline, inputsDisabledReason: "offline")
        case .tailnetNeeded:
            return KConnectionPresentation(word: KCopy.tailnetNeeded, signal: .offline, inputsDisabledReason: "tailnet needed")
        }
    }
}

struct KConnectionStateView: View {
    let state: KConnectionStateModel

    var body: some View {
        TimelineView(.periodic(from: state.changedAt, by: 0.5)) { context in
            let presentation = state.presentation(now: context.date)
            // Founder 2026-08-05: connection status is JUST the dot — no
            // "connecting"/"live" word. The word survives only as the a11y label.
            KStatusDot(signal: presentation.signal.kSignal, size: .small)
                .accessibilityLabel(presentation.word ?? state.status.text)
        }
    }
}

struct KScrollPinningModel: Equatable {
    static let bottomTolerance: CGFloat = 28
    static let followBreakDistance: CGFloat = 180

    private(set) var isFollowing = true
    private(set) var distanceFromBottom: CGFloat = 0
    private(set) var showsLatestPill = false
    private(set) var isProgrammaticallyScrolling = false

    var isAtBottom: Bool {
        distanceFromBottom <= Self.bottomTolerance
    }

    var showsNewBelow: Bool {
        showsLatestPill
    }

    var geometryScrollPositionViewID: AnyHashable? {
        isProgrammaticallyScrolling ? nil : "scroll"
    }

    mutating func beginProgrammaticScroll() {
        isProgrammaticallyScrolling = true
    }

    mutating func endProgrammaticScroll() {
        isProgrammaticallyScrolling = false
    }

    mutating func founderDragDidBegin() {
        endProgrammaticScroll()
    }

    mutating func updateAtBottom(_ atBottom: Bool) {
        updateDistanceFromBottom(atBottom ? 0 : Self.followBreakDistance + 1)
    }

    mutating func updateDistanceFromBottom(
        _ distance: CGFloat,
        scrollPositionViewID: AnyHashable? = "scroll"
    ) {
        distanceFromBottom = max(0, distance)

        if isAtBottom {
            resumeFollowing()
            return
        }

        // SwiftUI can report a nil positioned view after a programmatic scroll.
        // That is not a founder scroll gesture, so it must not break follow mode.
        guard scrollPositionViewID != nil else { return }

        if distanceFromBottom > Self.followBreakDistance {
            isFollowing = false
            showsLatestPill = true
        }
    }

    @discardableResult
    mutating func contentDidAppend() -> Bool {
        if isFollowing {
            showsLatestPill = false
            return true
        }
        showsLatestPill = true
        return false
    }

    mutating func jumpToBottom() {
        resumeFollowing()
    }

    mutating func resumeFollowing() {
        isFollowing = true
        distanceFromBottom = 0
        showsLatestPill = false
    }
}

enum KOptimisticPostState: Equatable {
    case idle
    case pending
    case confirmed
    case failed(String)

    var isOptimistic: Bool {
        if case .pending = self { return true }
        return false
    }

    var inlineErrorText: String? {
        if case .failed(let reason) = self {
            return KCopy.answerFailed(reason: reason)
        }
        return nil
    }
}

struct KOptimisticPostModel: Equatable {
    private(set) var state: KOptimisticPostState = .idle

    mutating func begin() {
        state = .pending
    }

    mutating func confirm() {
        state = .confirmed
    }

    mutating func fail(reason: String) {
        state = .failed(reason)
    }
}

struct KSecondTapConfirmationModel<Key: Equatable>: Equatable {
    private(set) var pendingKey: Key?
    private(set) var expiresAt: Date?
    var window: TimeInterval = 3

    mutating func tap(_ key: Key, now: Date = Date()) -> Bool {
        if isPending(key, now: now) {
            pendingKey = nil
            expiresAt = nil
            return true
        }
        pendingKey = key
        expiresAt = now.addingTimeInterval(window)
        return false
    }

    mutating func clearExpired(now: Date = Date()) {
        guard let expiresAt, now > expiresAt else { return }
        pendingKey = nil
        self.expiresAt = nil
    }

    mutating func cancel() {
        pendingKey = nil
        expiresAt = nil
    }

    func isPending(_ key: Key, now: Date = Date()) -> Bool {
        pendingKey == key && expiresAt.map { now <= $0 } == true
    }
}
