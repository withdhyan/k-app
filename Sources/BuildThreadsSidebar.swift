import Foundation
import SwiftUI

/// A display projection of the existing branch and plan objects. It is not a
/// second wire model: the branch identity remains `BuildBranchItem`, while the
/// dash language is derived from the current `BuildStatusSummary` records.
struct BuildThreadProjection: Identifiable, Equatable, Sendable {
    let branch: BuildBranchItem
    let dashes: [BuildThreadDashState]
    let isStale: Bool

    var id: String { branch.id }
    var title: String { branch.isTrunk ? KCopy.chatTrunkTarget : branch.composedTitle }
    var isDone: Bool {
        !branch.isTrunk && !dashes.isEmpty && dashes.allSatisfy { $0 == .landed || $0 == .done }
    }
    var stateLabel: String {
        if isStale { return KCopy.buildThreadsStale }
        if branch.isTrunk { return KCopy.buildThreadsLanded }
        if dashes.contains(.failed) { return KCopy.buildThreadsFailed }
        if dashes.contains(.needsYou) { return KCopy.buildThreadsNeedsYou }
        if dashes.contains(.heldExternal) { return KCopy.buildThreadsHeldExternal }
        if dashes.contains(.building) { return KCopy.buildThreadsBuilding }
        if dashes.contains(.stale) { return KCopy.buildThreadsStale }
        if isDone { return KCopy.buildThreadsDone }
        if dashes.contains(.unknown) { return KCopy.buildThreadsUnknown }
        return KCopy.buildThreadsQueued
    }

    var doneAgingLabel: String? {
        isDone && !isStale ? KCopy.buildThreadsDoneAging : nil
    }

    static func make(
        branches: [BuildBranchItem],
        summaries: [BuildStatusSummary],
        isStale: Bool
    ) -> [BuildThreadProjection] {
        // The trunk is the main surface, not a plan thread. Keeping it out of
        // this projection also means the resting rail has no selected row.
        let candidates = branches.filter { !$0.isTrunk }.enumerated().map { sourceIndex, branch in
            let summary = summaries.first { summary in
                summary.planId == branch.id
                    || summary.title.caseInsensitiveCompare(branch.title) == .orderedSame
            }
            let dashes = (summary?.units ?? []).map { BuildThreadDashState.from(rawState: $0.state) }
            let summaryIsStale = summary?.state?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "stale"
            return (
                sourceIndex,
                BuildThreadProjection(
                    branch: branch,
                    dashes: dashes.isEmpty ? [.queued] : dashes,
                    isStale: isStale || summaryIsStale || dashes.contains(.stale)
                )
            )
        }

        return candidates
            .sorted { lhs, rhs in
                let leftKey = orderKey(for: lhs.1, sourceIndex: lhs.0)
                let rightKey = orderKey(for: rhs.1, sourceIndex: rhs.0)
                return leftKey.0 == rightKey.0
                    ? leftKey.1 < rightKey.1
                    : leftKey.0 < rightKey.0
            }
            .map(\.1)
    }

    /// The frozen audit seed leads with the K proposal's branch, then walks the
    /// live state grammar before the parked/stale tail. Source order breaks ties
    /// so live snapshots remain deterministic without a second wire model.
    private static func orderKey(
        for thread: BuildThreadProjection,
        sourceIndex: Int
    ) -> (Int, Int) {
        if sourceIndex == 0 { return (-1, sourceIndex) }
        if thread.isStale { return (6, sourceIndex) }
        if thread.dashes.contains(.needsYou) { return (0, sourceIndex) }
        if thread.dashes.contains(.building) { return (1, sourceIndex) }
        if thread.dashes.contains(.queued) || thread.dashes.contains(.unknown) { return (2, sourceIndex) }
        if thread.dashes.contains(.heldExternal) { return (3, sourceIndex) }
        if thread.dashes.contains(.failed) { return (4, sourceIndex) }
        if thread.dashes.contains(.landed) || thread.dashes.contains(.done) { return (5, sourceIndex) }
        return (2, sourceIndex)
    }
}

/// Nine display states used by the frozen dash language. `stale` and `unknown`
/// are retained as explicit fallbacks so a new wire value never silently reads
/// as live. `stale` is row-level in the renderer; the remaining states are dashes.
enum BuildThreadDashState: String, CaseIterable, Equatable, Sendable {
    case landed
    case building
    case needsYou
    case queued
    case heldExternal
    case failed
    case done
    case stale
    case unknown

    static func from(rawState: String?) -> BuildThreadDashState {
        let value = rawState?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            ?? ""
        if ["held-external", "external", "waiting-external", "blocked-external"].contains(value) {
            return .heldExternal
        }
        if value == "stale" { return .stale }
        if value == "done" { return .done }
        if ["queued", "pending", "planned", "not-started", "not-yet"].contains(value) {
            return .queued
        }
        switch BuildSegmentState.from(unitState: value) {
        case .done: return .landed
        case .building: return .building
        case .needsYou: return value == "held-external" ? .heldExternal : .needsYou
        case .failed: return .failed
        case .pending: return .unknown
        }
    }
}

enum BuildThreadPaging {
    static func start(itemCount: Int, proposed: Int, pageSize: Int = KStyle.buildThreadPageSize) -> Int {
        let safePageSize = max(pageSize, 1)
        return min(max(proposed, 0), max(itemCount - safePageSize, 0))
    }

    static func window<T>(items: [T], start: Int, pageSize: Int = KStyle.buildThreadPageSize) -> ArraySlice<T> {
        let resolved = self.start(itemCount: items.count, proposed: start, pageSize: pageSize)
        return items.dropFirst(resolved).prefix(max(pageSize, 1))
    }

    static func earlierCount(itemCount: Int, start: Int, pageSize: Int = KStyle.buildThreadPageSize) -> Int {
        // The counter names every parked row before the replacement window.
        // It is intentionally larger than one page on the last window (+14 in
        // the frozen mock), while the tap still moves one page at a time.
        max(start, 0)
    }

    static func laterCount(itemCount: Int, start: Int, pageSize: Int = KStyle.buildThreadPageSize) -> Int {
        max(0, itemCount - start - max(pageSize, 1))
    }
}

/// The seven-row, bidirectional replacement window from v43.
struct BuildThreadsSidebar: View {
    @ObservedObject var model: BuildModel
    let selectedBranchID: String?
    let etaText: String?
    let rateText: String?
    let onSelectBranch: (String, String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageStart = 0
    @State private var pageDirection: PageDirection = .down

    init(
        model: BuildModel,
        selectedBranchID: String? = nil,
        etaText: String? = nil,
        rateText: String? = nil,
        onSelectBranch: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.model = model
        self.selectedBranchID = selectedBranchID
        self.etaText = etaText
        self.rateText = rateText
        self.onSelectBranch = onSelectBranch
    }

    private var surface: BuildReportSurface {
        BuildReportSurface.make(packets: model.packets, openCardCount: model.openCards.count)
    }

    private var summaries: [BuildStatusSummary] {
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

    private var threads: [BuildThreadProjection] {
        guard surface.branches.count > 1 else { return [] }
        return BuildThreadProjection.make(
            branches: surface.branches,
            summaries: summaries,
            isStale: model.isStale
        )
    }

    private var page: ArraySlice<BuildThreadProjection> {
        BuildThreadPaging.window(items: threads, start: pageStart)
    }

    private var canPageEarlier: Bool { pageStart > 0 }
    private var canPageLater: Bool { pageStart + KStyle.buildThreadPageSize < threads.count }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            metrics
            KMonoCaption(KCopy.buildThreadsHeading, variant: .metadata, state: .disabled)

            if threads.isEmpty {
                KMonoCaption(KCopy.buildThreadsEmpty, variant: .metadata)
                    .accessibilityIdentifier("build-threads-empty")
            } else {
                if canPageEarlier {
                    pageControl(
                        label: KCopy.buildThreadsEarlier,
                        count: BuildThreadPaging.earlierCount(itemCount: threads.count, start: pageStart),
                        direction: .up,
                        target: max(0, pageStart - KStyle.buildThreadPageSize)
                    )
                }

                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    ForEach(Array(page.enumerated()), id: \.element.id) { index, thread in
                        BuildThreadRow(
                            thread: thread,
                            isSelected: selectedBranchID == thread.id,
                            onSelect: {
                                onSelectBranch(
                                    thread.id,
                                    thread.branch.isTrunk ? KCopy.chatTrunkTarget : thread.title
                                )
                            }
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: pageDirection == .down
                                    ? KStyle.buildThreadPageOffset
                                    : -KStyle.buildThreadPageOffset))
                        )
                        .animation(
                            KStyle.gesturePageTransitionMotion(reduceMotion)?
                                .delay(reduceMotion ? 0 : Double(index) * KStyle.buildThreadPageStagger),
                            value: pageStart
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("build-threads-window")

                if canPageLater {
                    pageControl(
                        label: KCopy.buildThreadsLater,
                        count: BuildThreadPaging.laterCount(itemCount: threads.count, start: pageStart),
                        direction: .down,
                        target: min(pageStart + KStyle.buildThreadPageSize, max(threads.count - KStyle.buildThreadPageSize, 0))
                    )
                }
            }
        }
        .onChange(of: threads.map(\.id)) { _, ids in
            let maxStart = max(ids.count - KStyle.buildThreadPageSize, 0)
            if pageStart > maxStart { pageStart = maxStart }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-threads-sidebar")
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            metric(label: KCopy.buildThreadsEtaLabel, value: etaText ?? KCopy.buildThreadsEta)
            metric(label: KCopy.buildThreadsRateLabel, value: rateText ?? KCopy.buildThreadsRate)
            if model.isStale, let asOf = model.stalenessText {
                Text(asOf.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                    .accessibilityIdentifier("build-threads-as-of")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-threads-metrics")
    }

    private func metric(label: String, value: String) -> some View {
        HStack(spacing: KStyle.smallSpacing) {
            Text(label)
            Text(value.lowercased())
                .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
        }
        .kFont(.monoCaption)
        .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
    }

    private enum PageDirection { case up, down }

    private func pageControl(label: String, count: Int, direction: PageDirection, target: Int) -> some View {
        Button {
            KStyle.withMotion {
                pageDirection = direction
                pageStart = target
            }
        } label: {
            HStack(spacing: KStyle.smallSpacing) {
                Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                    .font(KStyle.monoCaptionFont)
                Text("+\(count) \(label)")
                    .kFont(.monoCaption)
            }
            .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
            .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(KCopy.buildThreadsPageAccessibility(count: count, label: label))
        .accessibilityIdentifier("build-threads-page-\(label)")
    }
}

private struct BuildThreadRow: View {
    let thread: BuildThreadProjection
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paperPulse = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("build-thread-marker-\(thread.id)")

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    Text(thread.title)
                        .font(KStyle.blockDefaultTitleFont)
                        .foregroundStyle(isSelected
                            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperPrimaryOpacity)
                            : Color.white.opacity(KStyle.secondaryTextOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                        .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)

                    HStack(spacing: KStyle.buildSegmentPillGap) {
                        ForEach(Array(thread.dashes.enumerated()), id: \.offset) { _, dash in
                            BuildThreadDashView(
                                state: dash,
                                reduceMotion: reduceMotion,
                                isOnPaper: isSelected
                            )
                        }
                    }

                    if let doneAgingLabel = thread.doneAgingLabel {
                        Text(doneAgingLabel)
                            .kFont(.monoCaption)
                            .foregroundStyle(isSelected
                                ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
                                : Color.white.opacity(KStyle.quaternaryTextOpacity))
                    }
                }
                .padding(.vertical, KStyle.smallSpacing)
                .padding(.horizontal, KStyle.smallSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? KStyle.emphasisInk : .clear,
                    in: RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(thread.isStale ? KStyle.staleDotFactor : KStyle.fullOpacity)
            // This is a real Button row. Combine its label and dash children so
            // XCUI keeps the row in the buttons query while the marker remains
            // an independent in-tree sibling for existence checks.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(thread.title), \(thread.stateLabel)")
            .accessibilityValue(thread.stateLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("build-thread-\(thread.id)")
        }
        .padding(.leading, isSelected ? -KStyle.buildThreadSelectedOverhang : 0)
        .shadow(
            color: KStyle.nearBlack.opacity(isSelected ? KStyle.chatThreadCardShadowOpacity : 0),
            radius: isSelected ? KStyle.chatThreadCardShadowRadius : 0,
            y: isSelected ? KStyle.chatThreadCardShadowY : 0
        )
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isSelected)
        .scaleEffect(paperPulse ? KStyle.buildThreadSelectedPulseScale : KStyle.identityScale, anchor: .leading)
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: paperPulse)
        .onChange(of: isSelected) { _, selected in
            guard selected else { return }
            paperPulse = true
            guard !reduceMotion else {
                paperPulse = false
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                paperPulse = false
            }
        }
    }
}

private struct BuildThreadDashView: View {
    let state: BuildThreadDashState
    let reduceMotion: Bool
    let isOnPaper: Bool

    var body: some View {
        if (state == .building || state == .needsYou) && !reduceMotion {
            TimelineView(.animation(minimumInterval: KStyle.buildThreadBreathFrameInterval, paused: false)) { context in
                dash(opacity: KStyle.breathOpacity(
                    at: context.date,
                    period: KStyle.buildSegmentBreathPeriod,
                    minimumOpacity: KStyle.buildSegmentBreathMinOpacity
                ))
            }
        } else {
            dash(opacity: KStyle.fullOpacity)
        }
    }

    private func dash(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: KStyle.buildSegmentPillRadius, style: .continuous)
            .fill(fill)
            .frame(width: KStyle.buildSegmentPillWidth, height: height)
            .opacity(opacity)
            .overlay {
                if state == .heldExternal || state == .unknown || state == .stale {
                    RoundedRectangle(cornerRadius: KStyle.buildSegmentPillRadius, style: .continuous)
                        .stroke(isOnPaper
                            ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
                            : Color.white.opacity(KStyle.quaternaryTextOpacity), lineWidth: KStyle.hairlineWidth)
                }
            }
            .accessibilityHidden(true)
    }

    private var height: CGFloat {
        state == .heldExternal || state == .unknown || state == .stale
            ? KStyle.hairlineWidth
            : KStyle.buildSegmentPillHeight
    }

    private var fill: Color {
        switch state {
        case .landed, .done: return KStyle.liveSignal
        case .building: return isOnPaper ? KStyle.nearBlack : KStyle.emphasisInk
        case .needsYou: return KStyle.signalWarning
        case .failed: return KStyle.errorSignal
        case .queued:
            return isOnPaper
                ? KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
                : Color.white.opacity(KStyle.buildDimmerOpacity)
        case .heldExternal, .stale, .unknown: return .clear
        }
    }
}

extension KCopy {
    static let buildThreadsStale = "stale"
    static let buildThreadsDone = "done"
}
