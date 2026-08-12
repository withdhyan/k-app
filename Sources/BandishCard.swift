import SwiftUI
import UIKit

private enum BandishCardCopy {
    static let middleDot = "·"
}

enum BandishCardTextRole: String, CaseIterable, Equatable {
    case time
    case title
    case duration
    case elapsed
    case secondaryInfo
    case workSubtype
}

struct BandishCardTypeMetric: Equatable {
    let role: BandishCardTextRole
    let pointSize: CGFloat
    let isRegular: Bool
    let usesTabularDigits: Bool
    let usesMonospace: Bool
    let minimumWidth: CGFloat?

    init(
        role: BandishCardTextRole,
        pointSize: CGFloat,
        isRegular: Bool,
        usesTabularDigits: Bool,
        usesMonospace: Bool = false,
        minimumWidth: CGFloat? = nil
    ) {
        self.role = role
        self.pointSize = pointSize
        self.isRegular = isRegular
        self.usesTabularDigits = usesTabularDigits
        self.usesMonospace = usesMonospace
        self.minimumWidth = minimumWidth
    }
}

enum BandishCardTypography {
    // /ai/k bandish-card.tsx: font-label/font-body are no-ops. The component is
    // deliberately one regular-weight page face, with only a 14/12pt size split.
    static let snapshot: [BandishCardTypeMetric] = [
        BandishCardTypeMetric(role: .time, pointSize: 14, isRegular: true, usesTabularDigits: true, usesMonospace: true),
        BandishCardTypeMetric(role: .title, pointSize: 14, isRegular: true, usesTabularDigits: false),
        BandishCardTypeMetric(role: .duration, pointSize: 12, isRegular: true, usesTabularDigits: false, usesMonospace: true),
        BandishCardTypeMetric(
            role: .elapsed,
            pointSize: 12,
            isRegular: true,
            usesTabularDigits: true,
            usesMonospace: true,
            minimumWidth: 52
        ),
        BandishCardTypeMetric(role: .secondaryInfo, pointSize: 12, isRegular: true, usesTabularDigits: false),
        BandishCardTypeMetric(role: .workSubtype, pointSize: 12, isRegular: true, usesTabularDigits: false),
    ]

    static func metric(for role: BandishCardTextRole) -> BandishCardTypeMetric {
        snapshot.first(where: { $0.role == role }) ?? snapshot[0]
    }
}

enum BandishCardMotionFamily: String, Hashable {
    case timingCurve
}

enum BandishCardCubicCurve: String, Equatable {
    case zen
    case standard
    case entranceOut
    case native

    var controlPoints: (Double, Double, Double, Double) {
        switch self {
        case .zen:
            return (0.15, 0, 0.15, 1)
        case .standard:
            return (0.4, 0, 0.2, 1)
        case .entranceOut:
            return (0.16, 1, 0.3, 1)
        case .native:
            return (0.25, 0.1, 0.25, 1)
        }
    }
}

enum BandishCardMotionName: String, Equatable {
    case colorFlood
    case textColor
    case progress
    case geometry
    case entranceOffset
    case entranceOpacity
}

struct BandishCardMotionToken: Equatable {
    let name: BandishCardMotionName
    let duration: TimeInterval
    let curve: BandishCardCubicCurve
    var family: BandishCardMotionFamily { .timingCurve }
}

enum BandishCardMotionSpec {
    static let timerTickInterval: TimeInterval = 1
    // Doctrine (doctrine.json 1.5.2 motion, founder 2026-08-05): the started-dot
    // keeps a 4s numeric breath. Wired to the canonical KStyle token (was a
    // stray 6s, token dead).
    static let breathingCycleDuration: TimeInterval = KStyle.activeBandishStartedDotPeriod
    static let breathingFrameInterval: TimeInterval = 1 / 60
    static let staggerInterval: TimeInterval = 0.1
    static let maxStaggerSteps = 6

    // Durations above 300ms are named exact-port exceptions. They reproduce
    // /ai/k's state explanation and continuous progress, not generic UI delay.
    static let tokens: [BandishCardMotionToken] = [
        BandishCardMotionToken(name: .colorFlood, duration: 1.0, curve: .zen),
        BandishCardMotionToken(name: .textColor, duration: 0.7, curve: .zen),
        BandishCardMotionToken(name: .progress, duration: 0.5, curve: .standard),
        BandishCardMotionToken(name: .geometry, duration: 0.8, curve: .zen),
        BandishCardMotionToken(name: .entranceOffset, duration: 0.8, curve: .entranceOut),
        BandishCardMotionToken(name: .entranceOpacity, duration: 0.6, curve: .native),
    ]

    static func token(named name: BandishCardMotionName) -> BandishCardMotionToken {
        tokens.first(where: { $0.name == name }) ?? tokens[0]
    }

    static func staggerDelay(for index: Int) -> TimeInterval {
        Double(min(max(0, index), maxStaggerSteps)) * staggerInterval
    }
}

enum BandishCardProgress {
    static let floorRatio = 0.10
    static let remainingRatio = 0.90

    static func visibleRatio(rawRatio: Double) -> Double {
        let clamped = min(1, max(0, rawRatio))
        let percentage = (floorRatio + remainingRatio * clamped) * 100
        return percentage.rounded() / 100
    }
}

struct BandishAutoRunStep: Identifiable, Equatable, Sendable {
    let id: String
    let text: String

    init(id: String, text: String) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func steps(from content: BlockContent?) -> [BandishAutoRunStep] {
        guard let content else { return [] }

        if let checklist = content.checklist, !checklist.isEmpty {
            return checklist.compactMap { item in
                guard !item.text.isEmpty else { return nil }
                return BandishAutoRunStep(id: item.id, text: item.text)
            }
        }

        return (content.detailLines + [content.liveLine].compactMap { $0 })
            .enumerated()
            .map { index, text in
                BandishAutoRunStep(id: "detail-\(index)", text: text)
            }
    }
}

struct BandishAutoRunStateMachine: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case running
        case paused
        case completed
    }

    let steps: [BandishAutoRunStep]
    let stepDuration: TimeInterval
    private(set) var state: State = .idle
    private(set) var currentStepIndex = 0
    private(set) var elapsedSeconds: TimeInterval = .zero
    private var lastDate: Date?

    init(
        steps: [BandishAutoRunStep],
        totalDuration: TimeInterval? = nil,
        stepDuration: TimeInterval = KStyle.bandishAutoRunDefaultStepDuration
    ) {
        self.steps = steps
        let equalStepDuration: TimeInterval? = totalDuration.flatMap { duration -> TimeInterval? in
            guard duration > .zero, !steps.isEmpty else { return nil }
            return duration / Double(steps.count)
        }
        self.stepDuration = max(
            KStyle.bandishAutoRunMinimumStepDuration,
            equalStepDuration ?? stepDuration
        )
    }

    var phase: State { state }

    var currentStep: BandishAutoRunStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }
    var isCompleted: Bool { state == .completed }

    var progressRatio: Double {
        guard !steps.isEmpty else { return .zero }
        let totalDuration = stepDuration * Double(steps.count)
        guard totalDuration > .zero else { return .zero }
        return min(1, max(0, elapsedSeconds / totalDuration))
    }

    mutating func start(at date: Date? = nil) {
        guard !steps.isEmpty else {
            reset()
            return
        }

        if state == .completed {
            reset()
        }
        state = .running
        lastDate = date
    }

    @discardableResult
    mutating func advance(by seconds: TimeInterval) -> Bool {
        guard state == .running, seconds > .zero, !steps.isEmpty else { return false }

        let previousIndex = currentStepIndex
        elapsedSeconds += seconds
        currentStepIndex = min(
            steps.count - 1,
            max(0, Int(floor(elapsedSeconds / stepDuration)))
        )
        return previousIndex != currentStepIndex
    }

    @discardableResult
    mutating func advance(to date: Date) -> Bool {
        guard state == .running else { return false }
        guard let lastDate else {
            self.lastDate = date
            return false
        }

        let delta = date.timeIntervalSince(lastDate)
        guard delta > .zero else { return false }
        self.lastDate = date
        return advance(by: delta)
    }

    @discardableResult
    mutating func tick(at date: Date) -> Bool {
        advance(to: date)
    }

    mutating func pause(at date: Date? = nil) {
        guard state == .running else { return }
        if let date {
            _ = advance(to: date)
        }
        state = .paused
        lastDate = nil
    }

    mutating func resume(at date: Date? = nil) {
        guard state == .paused else { return }
        state = .running
        lastDate = date
    }

    mutating func setExpanded(_ expanded: Bool, at date: Date? = nil) {
        if expanded {
            pause(at: date)
        } else {
            resume(at: date)
        }
    }

    @discardableResult
    mutating func complete(at date: Date? = nil) -> Bool {
        guard state == .running || state == .paused else { return false }
        if state == .running, let date {
            _ = advance(to: date)
        }
        state = .completed
        lastDate = nil
        return true
    }

    mutating func reset() {
        state = .idle
        currentStepIndex = .zero
        elapsedSeconds = .zero
        lastDate = nil
    }
}

struct BandishCardElapsedClock: Equatable {
    let baselineElapsedSeconds: Int?
    let referenceDate: Date
    let isRunning: Bool

    func elapsedSeconds(at date: Date) -> Int? {
        guard let baselineElapsedSeconds else { return nil }
        guard isRunning else { return max(0, baselineElapsedSeconds) }
        let tickedSeconds = max(0, Int(floor(date.timeIntervalSince(referenceDate))))
        return max(0, baselineElapsedSeconds) + tickedSeconds
    }

    func visibleProgressRatio(
        at date: Date,
        durationSeconds: Int?,
        fallbackRawRatio: Double?
    ) -> Double {
        let rawRatio: Double
        if let elapsedSeconds = elapsedSeconds(at: date),
           let durationSeconds,
           durationSeconds > 0 {
            rawRatio = Double(elapsedSeconds) / Double(durationSeconds)
        } else {
            rawRatio = fallbackRawRatio ?? 0
        }
        return BandishCardProgress.visibleRatio(rawRatio: rawRatio)
    }

    static func format(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }
}

enum BandishCardBreathing {
    static let opacity = 0.8
    static let maximumIntensity255 = 255.0
    static let intensityRange255 = 55.0

    static func intensity255(at date: Date, referenceDate: Date) -> Double {
        let cycle = BandishCardMotionSpec.breathingCycleDuration
        var elapsed = date.timeIntervalSince(referenceDate).truncatingRemainder(dividingBy: cycle)
        if elapsed < 0 { elapsed += cycle }
        let progress = elapsed / cycle
        let phase = (sin(progress * 2 * .pi - .pi / 2) + 1) / 2
        return maximumIntensity255 - phase * intensityRange255
    }
}

extension KStyle {
    static let bandishDarkPrimaryOpacity = 0.90
    static let bandishDarkSecondaryOpacity = 0.70
    static let bandishDarkTertiaryOpacity = 0.50
    static let bandishNonCurrentTimeOpacity = 0.70
    static let bandishEntranceOffset: CGFloat = -20

    static func bandishFont(_ role: BandishCardTextRole) -> Font {
        let metric = BandishCardTypography.metric(for: role)
        let textStyle: UIFont.TextStyle = metric.pointSize > 12 ? .callout : .caption1
        let base = metric.usesMonospace
            ? UIFont.monospacedSystemFont(ofSize: metric.pointSize, weight: .regular)
            : UIFont.systemFont(ofSize: metric.pointSize, weight: .regular)
        let scaled = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        var font = Font(scaled)
        if metric.usesTabularDigits {
            font = font.monospacedDigit()
        }
        return font
    }

    static func bandishAnimation(
        _ name: BandishCardMotionName,
        reduceMotion: Bool,
        delay: TimeInterval = 0
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let token = BandishCardMotionSpec.token(named: name)
        let points = token.curve.controlPoints
        return Animation
            .timingCurve(points.0, points.1, points.2, points.3, duration: token.duration)
            .delay(delay)
    }
}

struct BandishCard<Accessory: View, Footer: View>: View {
    let timeText: String
    let signal: KSignal
    let title: String
    let detail: String?
    let why: String?
    let typeLabel: String?
    let titleSuffix: String?
    let badge: String?
    let content: BlockContent?
    let timeGutter: KBlockTimeGutter?
    let dotColor: Color?
    let activeFillColor: Color?
    let variant: KBlockRowVariant
    let isTemporalCurrent: Bool
    let actionState: KBlockActionState
    let baselineElapsedSeconds: Int?
    let clockReferenceDate: Date
    let durationSeconds: Int?
    let fallbackProgressRatio: Double?
    let state: KPrimitiveInteractionState
    let onChecklistToggle: ((ChecklistItem) -> Void)?
    let onStart: (() -> Void)?
    let onComplete: (() -> Void)?
    let onResume: (() -> Void)?
    let onTap: (() -> Void)?
    let accessibilityIdentifier: String?
    let accessory: Accessory
    let footer: Footer

    @State private var autoRunMachine: BandishAutoRunStateMachine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        timeText: String,
        signal: KSignal,
        title: String,
        detail: String? = nil,
        why: String? = nil,
        typeLabel: String? = nil,
        titleSuffix: String? = nil,
        badge: String? = nil,
        content: BlockContent? = nil,
        timeGutter: KBlockTimeGutter? = nil,
        dotColor: Color? = nil,
        activeFillColor: Color? = nil,
        variant: KBlockRowVariant = .upcoming,
        isTemporalCurrent: Bool = false,
        actionState: KBlockActionState = .available,
        baselineElapsedSeconds: Int? = nil,
        clockReferenceDate: Date,
        durationSeconds: Int? = nil,
        fallbackProgressRatio: Double? = nil,
        state: KPrimitiveInteractionState = .resting,
        accessibilityIdentifier: String? = nil,
        onChecklistToggle: ((ChecklistItem) -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        onResume: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder footer: () -> Footer
    ) {
        self.timeText = timeText
        self.signal = signal
        self.title = title
        self.detail = detail
        self.why = why
        self.typeLabel = typeLabel
        self.titleSuffix = titleSuffix
        self.badge = badge
        self.content = content
        self.timeGutter = timeGutter
        self.dotColor = dotColor
        self.activeFillColor = activeFillColor
        self.variant = variant
        self.isTemporalCurrent = isTemporalCurrent
        self.actionState = actionState
        self.baselineElapsedSeconds = baselineElapsedSeconds
        self.clockReferenceDate = clockReferenceDate
        self.durationSeconds = durationSeconds
        self.fallbackProgressRatio = fallbackProgressRatio
        self.state = state
        self.onChecklistToggle = onChecklistToggle
        self.onStart = onStart
        self.onComplete = onComplete
        self.onResume = onResume
        self.onTap = onTap
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessory = accessory()
        self.footer = footer()
        _autoRunMachine = State(
            initialValue: BandishAutoRunStateMachine(
                steps: BandishAutoRunStep.steps(from: content),
                totalDuration: durationSeconds.map { TimeInterval($0) }
            )
        )
    }

    var body: some View {
        Group {
            if liveClock.isRunning {
                TimelineView(.periodic(
                    from: clockReferenceDate,
                    by: BandishCardMotionSpec.timerTickInterval
                )) { context in
                    card(at: context.date)
                }
            } else {
                card(at: clockReferenceDate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(state.contentOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "k-block-row")
        .onAppear {
            synchronizeAutoRun(at: clockReferenceDate)
        }
        .onChange(of: actionState) { _, _ in
            synchronizeAutoRun(at: clockReferenceDate)
        }
        .onChange(of: variant) { _, _ in
            synchronizeAutoRun(at: clockReferenceDate)
        }
        .onChange(of: isTemporalCurrent) { _, _ in
            synchronizeAutoRun(at: clockReferenceDate)
        }
        .onChange(of: autoRunStepIDs) { _, _ in
            resetAutoRun()
            synchronizeAutoRun(at: clockReferenceDate)
        }
        .onChange(of: durationSeconds) { _, _ in
            resetAutoRun()
            synchronizeAutoRun(at: clockReferenceDate)
        }
    }

    @ViewBuilder
    private func card(at date: Date) -> some View {
        if isCurrentCard {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: KStyle.activeBandishCornerRadius, style: .continuous)
                    .fill(cardBackgroundColor)
                    .animation(
                        KStyle.bandishAnimation(.colorFlood, reduceMotion: reduceMotion),
                        value: actionState
                    )

                if showsProgressOverlay {
                    Rectangle()
                        .fill(Color.black.opacity(KStyle.activeBandishProgressOverlayOpacity))
                        .scaleEffect(
                            x: liveClock.visibleProgressRatio(
                                at: date,
                                durationSeconds: durationSeconds,
                                fallbackRawRatio: fallbackProgressRatio
                            ),
                            y: KStyle.identityScale,
                            anchor: .leading
                        )
                        .animation(
                            KStyle.bandishAnimation(.progress, reduceMotion: reduceMotion),
                            value: liveClock.elapsedSeconds(at: date)
                        )
                        .accessibilityHidden(true)
                }

                rowContent(at: date)
                    .padding(.vertical, KStyle.blockCardVerticalPadding)
                    .padding(.horizontal, KStyle.blockCardHorizontalPadding)
                    .animation(
                        KStyle.bandishAnimation(.textColor, reduceMotion: reduceMotion),
                        value: actionState
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: KStyle.activeBandishCornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(KStyle.activeBandishShadowOpacity),
                radius: KStyle.activeBandishShadowRadius,
                y: KStyle.activeBandishShadowY
            )
            .padding(.trailing, -KStyle.activeBandishTrailingOverhang)
            .offset(x: KStyle.activeBandishLeadingOffset)
            .contentShape(Rectangle())
            .onTapGesture(perform: primaryTap)
            .animation(
                KStyle.bandishAnimation(.geometry, reduceMotion: reduceMotion),
                value: variant
            )
            .onAppear {
                synchronizeAutoRun(at: date)
            }
            .onChange(of: date) { _, newDate in
                advanceAutoRun(to: newDate)
            }
        } else {
            rowContent(at: date)
                .padding(.vertical, KStyle.blockRowVerticalPadding)
                .contentShape(Rectangle())
                .onTapGesture(perform: primaryTap)
                .onAppear {
                    synchronizeAutoRun(at: date)
                }
        }
    }

    private func rowContent(at date: Date) -> some View {
        HStack(alignment: .top, spacing: .zero) {
            timeGutterView
                .frame(width: KStyle.bandishTimeGutterWidth, alignment: .leading)
                .padding(.top, KStyle.microSpacing)

            statusDot
                .frame(width: KStyle.bandishDotColumnWidth, alignment: .center)
                .padding(.top, KStyle.blockDotTopPadding)

            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                HStack(alignment: .top, spacing: KStyle.tightRowSpacing) {
                    VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                        titleLine

                        if let elapsedSeconds = liveClock.elapsedSeconds(at: date),
                           actionState == .started,
                           isTemporalCurrent {
                            Text(BandishCardElapsedClock.format(elapsedSeconds))
                                .font(KStyle.bandishFont(.elapsed))
                                .foregroundStyle(secondaryTextColor)
                                .frame(
                                    minWidth: BandishCardTypography.metric(for: .elapsed).minimumWidth,
                                    alignment: .leading
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let why {
                            Text(why.lowercased())
                                .font(KStyle.bandishFont(.title))
                                .foregroundStyle(tertiaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        if let detail {
                            Text(detail.lowercased())
                                .font(KStyle.bandishFont(.title))
                                .foregroundStyle(tertiaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        ForEach(contentLines, id: \.self) { line in
                            Text(line)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer(minLength: KStyle.tightRowSpacing)

                    VStack(alignment: .trailing, spacing: KStyle.microSpacing) {
                        if let badge {
                            Text(badge.lowercased())
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(secondaryTextColor)
                        }
                        if let displayTypeLabel {
                            Text(displayTypeLabel)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(secondaryTextColor)
                        }
                        completedStatusIcon
                        accessory
                        lifecycleActionButton
                    }
                }

                if isCurrentCard, actionState == .started, !autoRunSteps.isEmpty {
                    BandishCardAutoRunSteps(
                        steps: autoRunSteps,
                        currentStepIndex: autoRunMachine.currentStepIndex,
                        isExpanded: isExpanded,
                        foregroundColor: textBaseColor,
                        reduceMotion: reduceMotion
                    )
                } else if let checklist = content?.checklist, isCurrentCard {
                    BandishCardChecklistRows(
                        items: checklist,
                        state: state,
                        onToggle: onChecklistToggle,
                        foregroundColor: textBaseColor
                    )
                }

                if !isCurrentCard {
                    ForEach(compactChecklistLines) { item in
                        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                            Text(BandishCardCopy.middleDot)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(secondaryTextColor)
                                .accessibilityHidden(true)
                            Text(item.text)
                                .font(KStyle.bandishFont(.secondaryInfo))
                                .foregroundStyle(secondaryTextColor)
                                .strikethrough(
                                    item.isDone,
                                    color: textBaseColor.opacity(KStyle.quaternaryTextOpacity)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }

                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeGutterView: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if let struckStartText = gutter.struckStartText {
                Text(struckStartText)
                    .strikethrough(true, color: tertiaryTextColor)
                    .font(KStyle.bandishFont(.time))
                    .foregroundStyle(timeTextColor)
            }

            Text(gutter.startText)
                .font(KStyle.bandishFont(.time))
                .foregroundStyle(timeTextColor)

            if let struckDurationText = gutter.struckDurationText {
                Text(struckDurationText)
                    .strikethrough(true, color: tertiaryTextColor)
                    .font(KStyle.bandishFont(.duration))
                    .foregroundStyle(timeTextColor)
            }

            if let durationText = gutter.durationText {
                Text(durationText)
                    .font(KStyle.bandishFont(.duration))
                    .foregroundStyle(timeTextColor)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if actionState == .started && isTemporalCurrent {
            BandishCardBreathingDot(referenceDate: clockReferenceDate, reduceMotion: reduceMotion)
        } else {
            Circle()
                .fill(resolvedDotColor)
                .frame(width: KStyle.bandishStatusDotSize, height: KStyle.bandishStatusDotSize)
                .accessibilityHidden(true)
        }
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(title.lowercased())
                .font(KStyle.bandishFont(.title))
                .foregroundStyle(primaryTextColor)
                .lineLimit(KStyle.singleLineLimit)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)

            if let titleSuffixText {
                Text(titleSuffixText)
                    .font(KStyle.bandishFont(.workSubtype))
                    .foregroundStyle(tertiaryTextColor)
                    .lineLimit(KStyle.singleLineLimit)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var lifecycleActionButton: some View {
        if isCurrentCard && actionState == .started {
            BandishHoldToComplete(
                iconColor: actionIconColor,
                isEnabled: onComplete != nil && !state.disablesAction,
                accessibilityIdentifier: "\(accessibilityIdentifier ?? "k-block-row")-complete",
                onComplete: { onComplete?() }
            )
        }
    }

    @ViewBuilder
    private var completedStatusIcon: some View {
        if actionState == .completed {
            Image(systemName: "checkmark")
                .font(KStyle.cadenceCompleteCheckIconFont)
                .foregroundStyle(secondaryTextColor)
                .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
                .accessibilityLabel("complete")
        }
    }

    private var autoRunSteps: [BandishAutoRunStep] {
        BandishAutoRunStep.steps(from: content)
    }

    private var autoRunStepIDs: [String] {
        autoRunSteps.map(\.id)
    }

    private var isExpanded: Bool {
        isCurrentCard && !isTemporalCurrent
    }

    private func resetAutoRun() {
        autoRunMachine = BandishAutoRunStateMachine(
            steps: autoRunSteps,
            totalDuration: durationSeconds.map { TimeInterval($0) }
        )
    }

    private func startAutoRun(at date: Date) {
        autoRunMachine.start(at: clockReferenceDate)
        if let baselineElapsedSeconds {
            _ = autoRunMachine.advance(by: TimeInterval(max(0, baselineElapsedSeconds)))
        }
        _ = autoRunMachine.advance(to: date)
    }

    private func synchronizeAutoRun(at date: Date) {
        guard !autoRunSteps.isEmpty else {
            if autoRunMachine.state != .idle { resetAutoRun() }
            return
        }

        switch actionState {
        case .available:
            if autoRunMachine.state != .idle { resetAutoRun() }
        case .completed:
            _ = autoRunMachine.complete(at: date)
        case .started:
            if isTemporalCurrent {
                if autoRunMachine.state == .idle || autoRunMachine.state == .completed {
                    if autoRunMachine.state == .completed { resetAutoRun() }
                    startAutoRun(at: date)
                } else if autoRunMachine.state == .paused {
                    autoRunMachine.resume(at: date)
                } else {
                    _ = autoRunMachine.advance(to: date)
                }
            } else if isCurrentCard {
                if autoRunMachine.state == .idle {
                    startAutoRun(at: date)
                }
                autoRunMachine.pause(at: date)
            } else if autoRunMachine.state != .idle {
                resetAutoRun()
            }
        }
    }

    private func advanceAutoRun(to date: Date) {
        guard actionState == .started, isTemporalCurrent, !isExpanded else { return }
        if autoRunMachine.state == .idle || autoRunMachine.state == .completed {
            if autoRunMachine.state == .completed { resetAutoRun() }
            startAutoRun(at: date)
        } else {
            _ = autoRunMachine.advance(to: date)
        }
    }

    private var liveClock: BandishCardElapsedClock {
        BandishCardElapsedClock(
            baselineElapsedSeconds: baselineElapsedSeconds,
            referenceDate: clockReferenceDate,
            isRunning: actionState == .started && isTemporalCurrent
        )
    }

    private var isCurrentCard: Bool {
        variant == .current
    }

    private func primaryTap() {
        if isCurrentCard {
            switch actionState {
            case .available:
                if !state.disablesAction { onStart?() }
            case .completed:
                if !state.disablesAction { onResume?() }
            case .started:
                break
            }
            return
        }
        onTap?()
    }

    private var cardBackgroundColor: Color {
        actionState == .started ? (activeFillColor ?? resolvedDotColor) : .white
    }

    private var showsProgressOverlay: Bool {
        guard actionState == .started, isTemporalCurrent else { return false }
        return (durationSeconds ?? 0) > 0 || fallbackProgressRatio != nil
    }

    private var gutter: KBlockTimeGutter {
        timeGutter ?? KBlockTimeGutter(timeText: timeText)
    }

    private var resolvedDotColor: Color {
        dotColor ?? signal.color
    }

    private var textBaseColor: Color {
        usesDarkText ? .black : .white
    }

    private var usesDarkText: Bool {
        isCurrentCard && actionState != .started
    }

    private var primaryTextColor: Color {
        textBaseColor.opacity(
            usesDarkText ? KStyle.bandishDarkPrimaryOpacity : KStyle.primaryTextOpacity
        )
    }

    private var secondaryTextColor: Color {
        textBaseColor.opacity(
            usesDarkText ? KStyle.bandishDarkSecondaryOpacity : KStyle.secondaryTextOpacity
        )
    }

    private var tertiaryTextColor: Color {
        textBaseColor.opacity(
            usesDarkText ? KStyle.bandishDarkTertiaryOpacity : KStyle.tertiaryTextOpacity
        )
    }

    private var timeTextColor: Color {
        if isCurrentCard {
            return secondaryTextColor
        }
        return Color.white.opacity(KStyle.bandishNonCurrentTimeOpacity)
    }

    private var actionIconColor: Color {
        primaryTextColor
    }

    private var titleSuffixText: String? {
        Self.normalized(titleSuffix)
            ?? (Self.normalized(typeLabel) == "work" ? Self.normalized(content?.metaSuffix) : nil)
    }

    private var displayTypeLabel: String? {
        if Self.normalized(typeLabel) == "work" { return nil }
        let values = [typeLabel, content?.metaSuffix].compactMap(Self.normalized)
        return values.isEmpty ? nil : values.joined(separator: " \(BandishCardCopy.middleDot) ")
    }

    private var contentLines: [String] {
        let values = (content?.detailLines ?? []) + [content?.liveLine].compactMap { $0 }
        return values.compactMap(Self.normalized)
    }

    private var compactChecklistLines: [ChecklistItem] {
        content?.checklist ?? []
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

private struct BandishCardAutoRunSteps: View {
    let steps: [BandishAutoRunStep]
    let currentStepIndex: Int
    let isExpanded: Bool
    let foregroundColor: Color
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if isExpanded {
                ForEach(Array(steps.enumerated()), id: \.element.id) { step in
                    stepRow(step.element, at: step.offset)
                }
            } else if steps.indices.contains(currentStepIndex) {
                stepRow(steps[currentStepIndex], at: currentStepIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            KStyle.bandishAutoRunStepMotion(reduceMotion),
            value: currentStepIndex
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bandish-auto-run-steps")
    }

    private func stepRow(_ step: BandishAutoRunStep, at index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(BandishCardCopy.middleDot)
                .font(KStyle.bandishFont(.secondaryInfo))
                .foregroundStyle(stepColor(for: index))
                .accessibilityHidden(true)
            Text(step.text)
                .font(KStyle.bandishFont(.secondaryInfo))
                .foregroundStyle(stepColor(for: index))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .id(step.id)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bandish-auto-run-step-\(step.id)")
        .accessibilityAddTraits(index == currentStepIndex ? .isSelected : [])
    }

    private func stepColor(for index: Int) -> Color {
        foregroundColor.opacity(
            index == currentStepIndex
                ? KStyle.primaryTextOpacity
                : KStyle.tertiaryTextOpacity
        )
    }
}

/// Hold-to-complete: a 2-second press fills a ring around the check, then commits.
/// Early release rewinds. Tap-free by construction — the deliberate hold replaces a
/// one-tap complete so a bandish is never marked done by accident. VoiceOver gets a
/// direct "complete" action underneath (the hold is the touch accelerator).
private struct BandishHoldToComplete: View {
    let iconColor: Color
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let onComplete: () -> Void

    @State private var fillProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    iconColor.opacity(KStyle.holdToCompleteTrackOpacity),
                    lineWidth: KStyle.holdToCompleteRingWidth
                )
            Circle()
                .trim(from: 0, to: fillProgress)
                .stroke(
                    iconColor,
                    style: StrokeStyle(lineWidth: KStyle.holdToCompleteRingWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(KStyle.cadenceCompleteCheckIconFont)
                .foregroundStyle(iconColor)
        }
        .frame(width: KStyle.holdToCompleteDiameter, height: KStyle.holdToCompleteDiameter)
        .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: KStyle.holdToCompleteDuration,
            maximumDistance: KStyle.holdToCompleteMaxDistance,
            pressing: { pressing in
                guard isEnabled else { return }
                withAnimation(
                    KStyle.holdToCompleteMotion(
                        pressing: pressing,
                        reduceMotion: reduceMotion
                    )
                ) {
                    fillProgress = pressing ? 1 : 0
                }
            },
            perform: {
                guard isEnabled else { return }
                onComplete()
            }
        )
        .disabled(!isEnabled)
        .accessibilityElement()
        .accessibilityLabel("hold to complete")
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if isEnabled { onComplete() }
        }
    }
}

private struct BandishCardBreathingDot: View {
    let referenceDate: Date
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: BandishCardMotionSpec.breathingFrameInterval,
            paused: reduceMotion
        )) { context in
            let date = reduceMotion ? referenceDate : context.date
            let intensity = BandishCardBreathing.intensity255(
                at: date,
                referenceDate: referenceDate
            ) / BandishCardBreathing.maximumIntensity255
            Circle()
                .fill(Color(.sRGB, white: intensity, opacity: BandishCardBreathing.opacity))
                .frame(width: KStyle.bandishStatusDotSize, height: KStyle.bandishStatusDotSize)
                .accessibilityHidden(true)
        }
    }
}

private struct BandishCardChecklistRows: View {
    let items: [ChecklistItem]
    let state: KPrimitiveInteractionState
    let onToggle: ((ChecklistItem) -> Void)?
    let foregroundColor: Color
    @State private var localDoneByID: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(items) { item in
                KChecklistRow(
                    title: item.text,
                    isDone: doneState(for: item),
                    state: state,
                    foregroundColor: foregroundColor,
                    onToggle: { toggle(item) }
                )
                .accessibilityIdentifier("k-block-content-checklist-\(item.id)")
            }
        }
    }

    private func doneState(for item: ChecklistItem) -> Bool {
        localDoneByID[item.id] ?? item.isDone
    }

    private func toggle(_ item: ChecklistItem) {
        if let onToggle {
            onToggle(item)
        } else {
            localDoneByID[item.id] = !doneState(for: item)
        }
    }
}

private struct BandishCardEntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        let delay = BandishCardMotionSpec.staggerDelay(for: index)
        content
            .offset(y: reduceMotion || hasAppeared ? 0 : KStyle.bandishEntranceOffset)
            .animation(
                KStyle.bandishAnimation(.entranceOffset, reduceMotion: reduceMotion, delay: delay),
                value: hasAppeared
            )
            .opacity(hasAppeared ? KStyle.fullOpacity : .zero)
            .animation(
                KStyle.bandishAnimation(.entranceOpacity, reduceMotion: reduceMotion, delay: delay),
                value: hasAppeared
            )
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
            }
    }
}

extension View {
    func bandishCardEntrance(index: Int) -> some View {
        modifier(BandishCardEntranceModifier(index: index))
    }
}
