import Foundation
import SwiftUI

struct ContextBreakup: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    let fraction: Double

    init(id: String, label: String, fraction: Double) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = normalizedID
        self.label = normalizedLabel.isEmpty ? normalizedID : normalizedLabel
        self.fraction = min(max(fraction, .zero), 1)
    }

    var percentText: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    func barFraction(in fullness: Double) -> CGFloat {
        guard fullness > .zero else { return .zero }
        return CGFloat(min(max(fraction / fullness, .zero), 1))
    }
}

struct ContextStats: Codable, Equatable, Sendable {
    let fullness: Double
    let breakup: [ContextBreakup]

    init(fullness: Double, breakup: [ContextBreakup]) {
        self.fullness = min(max(fullness, .zero), 1)
        self.breakup = breakup
    }

    var percentText: String {
        "\(Int((fullness * 100).rounded()))%"
    }

    var ringPercentText: String {
        "\(Int((fullness * 100).rounded()))"
    }

    var isNearFull: Bool {
        fullness >= KStyle.contextRingNearFullThreshold
    }
}

protocol ContextStatsSource {
    func contextStats(for target: ChatComposerTarget) -> ContextStats?
}

extension ContextStatsSource {
    func stats(for target: ChatComposerTarget) -> ContextStats? {
        contextStats(for: target)
    }
}

enum ContextStatsFixture: String, CaseIterable, Sendable {
    case typical
    case nearFull = "near-full"
    case absent

    init?(argument: String) {
        let normalized = argument
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        self.init(rawValue: normalized)
    }
}

enum ContextStatsFixtures {
    static let typical = ContextStats(
        fullness: 0.34,
        breakup: [
            ContextBreakup(id: "self-model", label: "self-model", fraction: 0.12),
            ContextBreakup(id: "history", label: "history", fraction: 0.15),
            ContextBreakup(id: "senses", label: "senses", fraction: 0.07),
        ]
    )

    static let nearFull = ContextStats(
        fullness: 0.91,
        breakup: [
            ContextBreakup(id: "self-model", label: "self-model", fraction: 0.32),
            ContextBreakup(id: "refs", label: "refs", fraction: 0.15),
            ContextBreakup(id: "history", label: "history", fraction: 0.25),
            ContextBreakup(id: "senses", label: "senses", fraction: 0.19),
        ]
    )

    static func stats(for fixture: ContextStatsFixture) -> ContextStats? {
        switch fixture {
        case .typical:
            return typical
        case .nearFull:
            return nearFull
        case .absent:
            return nil
        }
    }
}

struct FixtureContextStatsSource: ContextStatsSource, Sendable {
    let fixture: ContextStatsFixture

    func contextStats(for target: ChatComposerTarget) -> ContextStats? {
        ContextStatsFixtures.stats(for: fixture)
    }
}

struct EmptyContextStatsSource: ContextStatsSource, Sendable {
    func contextStats(for target: ChatComposerTarget) -> ContextStats? {
        nil
    }
}

enum ContextStatsSourceFactory {
    private static let fixtureArguments = [
        "-chat-context-stats-fixture",
        "-chat-context-stats",
        "-ui57-context-ring",
    ]

    static func source(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> any ContextStatsSource {
        guard let fixture = fixture(from: arguments) else {
            // The chat look fixtures exercise the full composer grammar without
            // each caller having to repeat the context seam. An explicit
            // `absent` fixture still wins above and keeps the ring silent.
            if chatFixtureIsEnabled(arguments: arguments) {
                return FixtureContextStatsSource(fixture: .typical)
            }
            return EmptyContextStatsSource()
        }
        return FixtureContextStatsSource(fixture: fixture)
    }

    private static func chatFixtureIsEnabled(arguments: [String]) -> Bool {
        arguments.contains(ChatDemoFixture.launchArgument)
            || arguments.contains(ChatBranchMotionFixture.launchArgument)
            || arguments.contains(W30ChatRailFixture.launchArgument)
            || arguments.contains(W31ChatThreadFixture.launchArgument)
            || arguments.contains(BuildAuditFixture.launchArgument)
            || arguments.contains(BuildAuditFixture.alternateLaunchArgument)
    }

    static func fixture(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ContextStatsFixture? {
        for (index, argument) in arguments.enumerated() {
            for key in fixtureArguments {
                if argument == key {
                    if key == "-ui57-context-ring" && !arguments.indices.contains(index + 1) {
                        return .typical
                    }
                    guard arguments.indices.contains(index + 1),
                          let fixture = ContextStatsFixture(argument: arguments[index + 1])
                    else { continue }
                    return fixture
                }

                let prefix = "\(key)="
                if argument.hasPrefix(prefix) {
                    return ContextStatsFixture(argument: String(argument.dropFirst(prefix.count)))
                }
            }
        }
        return nil
    }
}

struct ContextRing: View {
    let stats: ContextStats
    let target: ChatComposerTarget?
    // Build's target is a plain context line rather than a chat thread enum.
    // Keep this seam optional so chat U1/U2 remains unchanged.
    let panelTarget: String?
    @Binding private var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || KStyle.auditReduceMotionOverride }

    init(
        stats: ContextStats,
        isExpanded: Binding<Bool>,
        target: ChatComposerTarget? = nil,
        panelTarget: String? = nil
    ) {
        self.stats = stats
        self.target = target
        self.panelTarget = panelTarget
        self._isExpanded = isExpanded
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ringButton

            if isExpanded {
                ContextRingBreakup(stats: stats, target: target, panelTarget: panelTarget)
                    .offset(y: -(KStyle.contextRingButtonSize + KStyle.contextRingPanelSpacing))
                    .transition(breakupTransition)
                    .zIndex(1)
            }
        }
        .frame(width: KStyle.contextRingButtonSize, height: KStyle.contextRingButtonSize)
        .animation(KStyle.contextRingExpansionMotion(reduceMotion), value: isExpanded)
        .animation(KStyle.contextRingFillMotion(reduceMotion), value: stats.fullness)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-context-ring-container")
    }

    private var ringButton: some View {
        Button(action: toggleExpansion) {
            ZStack {
                Circle()
                    .stroke(
                        Color.white.opacity(KStyle.contextRingTrackOpacity),
                        lineWidth: KStyle.contextRingStrokeWidth
                    )

                Circle()
                    .trim(from: .zero, to: CGFloat(stats.fullness))
                    .stroke(
                        KStyle.emphasisInk.opacity(fillOpacity),
                        style: StrokeStyle(
                            lineWidth: KStyle.contextRingStrokeWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(KStyle.contextRingRotationDegrees))

                Text(stats.ringPercentText)
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.contextRingPercentOpacity))
                    .contentTransition(.opacity)
            }
            .frame(width: KStyle.contextRingGlyphSize, height: KStyle.contextRingGlyphSize)
            .frame(width: KStyle.contextRingButtonSize, height: KStyle.contextRingButtonSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KCopy.chatContextRingLabel)
        .accessibilityValue(stats.accessibilityValue)
        .accessibilityHint(isExpanded ? KCopy.chatContextRingCollapseHint : KCopy.chatContextRingShowHint)
        .accessibilityIdentifier("chat-context-ring")
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { scale in
                    if scale >= KStyle.contextRingPinchExpandThreshold {
                        setExpanded(true)
                    } else if scale <= KStyle.contextRingPinchCollapseThreshold {
                        setExpanded(false)
                    }
                }
        )
    }

    private var fillOpacity: Double {
        stats.isNearFull
            ? KStyle.contextRingNearFullFillOpacity
            : KStyle.contextRingFillOpacity
    }

    private var breakupTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: KStyle.contextRingRevealOffset))
    }

    private func toggleExpansion() {
        isExpanded.toggle()
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }
}

private struct ContextRingBreakup: View {
    let stats: ContextStats
    let target: ChatComposerTarget?
    let panelTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.contextRingPanelSpacing) {
            if let panelTarget {
                buildContextTarget(panelTarget)
                buildTokenBar
                buildTokenLegend
            } else {
                if let target {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.microSpacing) {
                        Text("target")
                            .foregroundStyle(Color.white.opacity(KStyle.contextRingRowLabelOpacity))
                        Text(target.shortText)
                            .foregroundStyle(Color.white.opacity(KStyle.contextRingFractionOpacity))
                            .lineLimit(KStyle.singleLineLimit)
                    }
                    .kFont(.monoCaption)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("chat-context-target")
                }

                Text(KCopy.chatContextRingBreakupTitle(stats.percentText))
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.contextRingHeaderOpacity))
                    .fixedSize(horizontal: false, vertical: true)

                tokenBar
                tokenLegend

                // Chat v21 keeps the context explanation to one sentence, one
                // bar, and one legend. Detailed rows belong to an intentional
                // diagnostic surface, not the resting chat panel.
            }

            if panelTarget != nil {
                ForEach(stats.breakup) { row in
                    ContextRingBreakupRow(row: row, fullness: stats.fullness)
                }
            }
        }
        .padding(KStyle.contextRingPanelPadding)
        .frame(width: KStyle.contextRingPanelWidth, alignment: .leading)
        .kGlassCardTone()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-context-breakup")
    }

    private func buildContextTarget(_ target: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            Text(KCopy.buildContextTarget)
                .foregroundStyle(Color.white.opacity(KStyle.contextRingHeaderOpacity))
            Text(target.lowercased())
                .foregroundStyle(Color.white.opacity(KStyle.contextRingRowLabelOpacity))
        }
        .kFont(.monoCaption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("build-context-target")
    }

    private var buildTokenBar: some View {
        GeometryReader { proxy in
            HStack(spacing: .zero) {
                ForEach(Array(stats.breakup.enumerated()), id: \.element.id) { index, row in
                    Rectangle()
                        .fill(buildTokenColor(index: index))
                        .frame(width: proxy.size.width * CGFloat(row.fraction / totalTokenFraction))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KStyle.contextRingBarHeight / 2, style: .continuous))
        }
        .frame(height: KStyle.contextRingBarHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KCopy.buildContextTokenBar)
        .accessibilityIdentifier("build-context-token-bar")
    }

    private var buildTokenLegend: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(Array(stats.breakup.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: KStyle.microSpacing) {
                    RoundedRectangle(cornerRadius: KStyle.hairlineWidth, style: .continuous)
                        .fill(buildTokenColor(index: index))
                        .frame(width: KStyle.contextRingBarHeight, height: KStyle.contextRingBarHeight)
                    Text(row.label.lowercased())
                    Spacer(minLength: KStyle.smallSpacing)
                    Text(row.percentText)
                        .kFont(.monoCaptionDigit)
                }
                .kFont(.monoCaption)
            }
        }
        .foregroundStyle(Color.white.opacity(KStyle.contextRingRowLabelOpacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-context-token-legend")
    }

    private var totalTokenFraction: Double {
        max(stats.breakup.reduce(0) { $0 + $1.fraction }, .leastNonzeroMagnitude)
    }

    private func buildTokenColor(index: Int) -> Color {
        switch index {
        case 0: return KStyle.emphasisInk
        case 1: return KStyle.liveSignal
        case 2: return KStyle.signalWarning
        default: return Color.white.opacity(KStyle.secondaryTextOpacity)
        }
    }

    private var tokenBar: some View {
        GeometryReader { proxy in
            HStack(spacing: .zero) {
                ForEach(stats.breakup) { row in
                    Rectangle()
                        .fill(Color.white.opacity(KStyle.contextRingBarFillOpacity))
                        .frame(width: proxy.size.width * row.barFraction(in: stats.fullness))
                }
            }
        }
        .frame(height: KStyle.contextRingBarHeight)
        .clipShape(Capsule())
        .accessibilityIdentifier("chat-context-token-bar")
    }

    private var tokenLegend: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.contextRingRowSpacing) {
            ForEach(stats.breakup) { row in
                Text("· \(row.label.lowercased()) \(row.percentText)")
                    .kFont(.monoCaptionDigit)
                    .foregroundStyle(Color.white.opacity(KStyle.contextRingFractionOpacity))
                    .lineLimit(KStyle.singleLineLimit)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat-context-token-legend")
    }
}

private struct ContextRingBreakupRow: View {
    let row: ContextBreakup
    let fullness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.contextRingRowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.rowSpacing) {
                Text(row.label.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(Color.white.opacity(KStyle.contextRingRowLabelOpacity))
                    .lineLimit(KStyle.singleLineLimit)

                Spacer(minLength: KStyle.smallSpacing)

                Text(row.percentText)
                    .kFont(.monoCaptionDigit)
                    .foregroundStyle(Color.white.opacity(KStyle.contextRingFractionOpacity))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(KStyle.contextRingBarTrackOpacity))
                    Capsule()
                        .fill(Color.white.opacity(KStyle.contextRingBarFillOpacity))
                        .frame(width: proxy.size.width * row.barFraction(in: fullness))
                }
            }
            .frame(height: KStyle.contextRingBarHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label.lowercased()), \(row.percentText)")
        .accessibilityIdentifier("chat-context-breakup-row-\(row.id)")
    }
}

private extension ContextStats {
    var accessibilityValue: String {
        isNearFull
            ? "\(percentText), \(KCopy.chatContextRingNearFull)"
            : percentText
    }
}
