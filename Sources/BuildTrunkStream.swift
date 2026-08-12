import Foundation
import SwiftUI

/// The resting factory conversation. It consumes BuildModel's existing stream
/// lines and cards, then sends the one proposal act back through the caller's
/// `selectBranch` seam. No branch/thread store is introduced here.
struct BuildTrunkStream: View {
    let lines: [BuildStreamLine]
    let proposals: [BuildCard]
    let onSelectBranch: (String) -> Void
    let onOpenReview: (BuildRecord, BuildRecordSection.Kind) -> Void
    let onPeekLogTail: (BuildRecord) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool
    let now: Date

    init(
        lines: [BuildStreamLine],
        proposals: [BuildCard] = [],
        now: Date = Date(),
        onSelectBranch: @escaping (String) -> Void = { _ in },
        onOpenReview: @escaping (BuildRecord, BuildRecordSection.Kind) -> Void = { _, _ in },
        onPeekLogTail: @escaping (BuildRecord) -> Void = { _ in },
        isDepthOrigin: @escaping (BuildRecord) -> Bool = { _ in false }
    ) {
        self.lines = lines
        self.proposals = proposals
        self.now = now
        self.onSelectBranch = onSelectBranch
        self.onOpenReview = onOpenReview
        self.onPeekLogTail = onPeekLogTail
        self.isDepthOrigin = isDepthOrigin
    }

    var body: some View {
        let restingLines = lines.count == 1 && lines[0].id.hasPrefix("connection-") ? [] : lines

        // The mock keeps mono stream and receipt rows on the same tight beat;
        // the 44pt row target supplies touch clearance without stretching the
        // visual gaps between milestones.
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if restingLines.isEmpty, proposals.isEmpty {
                Text(KCopy.buildTrunkNoStream)
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.buildDimOpacity))
                    .accessibilityIdentifier("build-trunk-empty")
            } else {
                if !restingLines.isEmpty {
                    if let separator = BuildTrunkDateSeparator.text(for: restingLines[0].meta, now: now) {
                        Text(separator)
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                            .accessibilityIdentifier("build-trunk-date-0")
                    }
                }
                // One-slot rule: only K's first open proposal is resting-primary.
                // It precedes receipt history so the ranked cue is encountered
                // before the stream recedes into its archive.
                if let proposal = proposals.first {
                    BuildTrunkProposalCard(proposal) {
                        onSelectBranch(BuildTrunkBranchName.from(card: proposal))
                    }
                }

                ForEach(Array(restingLines.enumerated()), id: \.element.id) { index, line in
                    if let separator = BuildTrunkDateSeparator.text(for: line.meta, now: now),
                       index > 0 && BuildTrunkDateSeparator.text(for: restingLines[index - 1].meta, now: now) != separator {
                        Text(separator)
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.quaternaryTextOpacity))
                            .accessibilityIdentifier("build-trunk-date-\(index)")
                    }

                    if let record = line.record, line.recordKind == .history {
                        BuildMilestoneReceipt(
                            word: BuildTrunkDateSeparator.receiptWord(from: line.text),
                            branchName: BuildTrunkBranchName.from(record: record),
                            detail: record.detail ?? record.resultNote ?? record.state,
                            accessibilityID: "build-trunk-receipt-\(line.id)"
                        )
                    } else if line.role == .runner, line.record == nil,
                              !line.id.hasPrefix("intent-queued-"), !line.id.hasPrefix("intent-ack-") {
                        // Intent receipts ("queued · will sync", acks) are state
                        // lines, not tappable runner turns — they render as plain
                        // stream rows so the receipt stays a StaticText.
                        BuildTrunkRunnerLine(
                            line: line,
                            onSelectBranch: onSelectBranch
                        )
                    } else {
                        BuildStreamLineView(
                            line: line.withoutPerMessageMeta,
                            onOpenReview: onOpenReview,
                            onPeekLogTail: onPeekLogTail,
                            isDepthOrigin: isDepthOrigin,
                            onSelectBranch: onSelectBranch,
                            branchName: line.recordKind == .history
                                ? nil
                                : line.record.map(BuildTrunkBranchName.from(record:))
                        )
                    }
                }
            }
        }
        // Keep the empty stream's identified accessibility element honest about
        // the space reserved for the trunk above the composer. The parent
        // ScrollView also carries this minimum, but a frame applied outside the
        // identified group is invisible to XCUI layout assertions.
        .frame(
            maxWidth: .infinity,
            minHeight: KStyle.buildThreadStreamMinHeight,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-trunk-stream")
    }
}

private extension BuildStreamLine {
    /// The resting trunk uses date separators for temporal orientation. The
    /// stream row still owns its metadata for other surfaces, but this page
    /// must not reintroduce per-message timestamps. A queued intent receipt is
    /// state, not chrome, so its exact copy and metadata stay attached.
    var withoutPerMessageMeta: BuildStreamLine {
        guard !isQueuedIntent else { return self }
        var copy = self
        copy.meta = nil
        return copy
    }

    private var isQueuedIntent: Bool {
        id.hasPrefix("intent-queued-")
            || text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == KCopy.queuedWillSync
            || meta?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == KCopy.queuedWillSync
    }
}

private struct BuildTrunkRunnerLine: View {
    let line: BuildStreamLine
    let onSelectBranch: (String) -> Void
    @State private var isDrawerOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            Button {
                // A regular tap keeps the existing branch/context seam useful;
                // the quiet row itself remains a long-press reveal.
                onSelectBranch(BuildTrunkBranchName.from(line: line))
            } label: {
                Text(line.text.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.text.lowercased())
            .accessibilityHint(isDrawerOpen ? KCopy.buildTrunkQuietActsVisible : KCopy.buildTrunkHoldForQuietActs)
            .accessibilityIdentifier("build-trunk-line-\(line.id)")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: KStyle.buildThreadLongPressDuration)
                    .onEnded { _ in
                        KStyle.withMotion(reduceMotion: reduceMotion) { isDrawerOpen = true }
                    }
            )

            KChatVerbDrawer(
                isOpen: isDrawerOpen,
                receipt: line.receipt,
                messageID: "build-\(line.id)",
                onSelect: handleVerb
            )
        }
    }

    private func handleVerb(_ verb: KChatVerb) {
        guard verb == .branch else { return }
        onSelectBranch(BuildTrunkBranchName.from(line: line))
    }
}

private struct BuildMilestoneReceipt: View {
    let word: String
    let branchName: String
    let detail: String?
    let accessibilityID: String
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            receiptCap

            Button {
                KStyle.withMotion { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    Text(word.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    Text(branchName.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.buildThreadReceiptBranchOpacity))
                }
                .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(word.lowercased()), \(branchName.lowercased())")
            .accessibilityHint(isExpanded ? KCopy.buildTrunkCollapseReceipt : KCopy.buildTrunkExpandReceipt)
            .accessibilityIdentifier(accessibilityID)

            if isExpanded, let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, KStyle.buildThreadReceiptBodyIndent)
                    .padding(.bottom, KStyle.smallSpacing)
                    .transition(.opacity.combined(with: .offset(y: -KStyle.microSpacing)))
            }

            receiptCap
        }
        .animation(KStyle.microRevealMotion(reduceMotion), value: isExpanded)
        .padding(.leading, KStyle.buildThreadReceiptLeadingInset)
    }

    private var receiptCap: some View {
        Rectangle()
            .fill(Color.white.opacity(KStyle.buildThreadReceiptCapOpacity))
            .frame(width: KStyle.hairlineWidth, height: KStyle.buildThreadReceiptCapHeight)
            .padding(.leading, KStyle.smallSpacing)
            .accessibilityHidden(true)
    }
}

private struct BuildTrunkProposalCard: View {
    let card: BuildCard
    let onBranch: () -> Void
    @State private var isDrawerOpen = false
    @State private var isAccepting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ card: BuildCard, onBranch: @escaping () -> Void) {
        self.card = card
        self.onBranch = onBranch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text(card.voiceTitle.lowercased())
                .font(KStyle.contentFont)
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)

            if let briefText = card.brief?.openQuestion ?? card.body ?? card.what,
               !briefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(briefText.lowercased())
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer(minLength: KStyle.smallSpacing)
                Button {
                    KStyle.withMotion { isAccepting = true }
                    onBranch()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(KStyle.inputControlFont)
                        .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                        .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: KStyle.buildThreadProposalArrowInset)
                .accessibilityLabel(KCopy.buildTrunkBranchProposal)
                .accessibilityIdentifier("build-trunk-proposal-branch-\(card.id)")
            }

            KChatVerbDrawer(
                isOpen: isDrawerOpen,
                messageID: "build-proposal-\(card.id)",
                onSelect: handleVerb
            )
        }
        .padding(KStyle.buildThreadProposalPadding)
        .background(
            Color.white.opacity(KStyle.buildChatBubbleFillOpacity),
            in: RoundedRectangle(cornerRadius: KStyle.buildThreadProposalRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: KStyle.buildThreadProposalRadius, style: .continuous))
        .opacity(isAccepting ? KStyle.buildDimmerOpacity : KStyle.fullOpacity)
        .scaleEffect(
            isAccepting ? KStyle.buildThreadProposalCondenseScale : KStyle.identityScale,
            anchor: .leading
        )
        .animation(KStyle.chatThreadSwapSettledMotion(reduceMotion, phase: .trunkExit), value: isAccepting)
        .accessibilityValue(isAccepting ? "accepting branch" : "proposal")
        .onLongPressGesture(minimumDuration: KStyle.buildThreadLongPressDuration) {
            KStyle.withMotion(reduceMotion: reduceMotion) { isDrawerOpen = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-trunk-proposal-\(card.id)")
    }

    private func handleVerb(_ verb: KChatVerb) {
        guard verb == .branch else { return }
        onBranch()
    }
}

enum BuildTrunkBranchName {
    static func from(card: BuildCard) -> String {
        let title = card.planId == nil ? (card.what ?? card.title) : nil
        return BuildPlanRow.nickname(planId: card.planId, title: title).lowercased()
    }

    static func from(record: BuildRecord) -> String {
        BuildPlanRow.nickname(planId: record.planId, title: nil).lowercased()
    }

    static func from(line: BuildStreamLine) -> String {
        if let record = line.record { return from(record: record) }
        return KCopy.chatTrunkTarget
    }
}

enum BuildTrunkDateSeparator {
    static func text(for raw: String?, now: Date, calendar: Calendar = .current) -> String? {
        guard let raw, let date = date(from: raw, now: now, calendar: calendar) else { return nil }
        let startDate = calendar.startOfDay(for: date)
        let startNow = calendar.startOfDay(for: now)
        let day = calendar.dateComponents([.day], from: startDate, to: startNow).day ?? 0
        if day == 0 { return KCopy.buildTrunkToday }
        if day == 1 { return KCopy.buildTrunkYesterday }
        if day > 1 { return KCopy.buildTrunkDaysAgo(day) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }

    static func receiptWord(from text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "·" }).first.map(String.init) ?? text
    }

    private static func date(from raw: String, now: Date, calendar: Calendar) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let value = iso.date(from: trimmed) { return value }

        let relative = trimmed.lowercased()
        if relative == KCopy.buildTrunkToday { return now }
        if relative == KCopy.buildTrunkYesterday {
            return calendar.date(byAdding: .day, value: -1, to: now)
        }
        if let match = relative.range(of: #"^(\d+)\s*(?:days?|d)\s*ago$"#, options: .regularExpression) {
            let digits = relative[match].prefix(while: { $0.isNumber })
            if let count = Int(digits) {
                return calendar.date(byAdding: .day, value: -count, to: now)
            }
        }
        if relative.range(of: #"^\d+\s*(?:minutes?|m|hours?|h)\s*ago$"#, options: .regularExpression) != nil {
            return now
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }
}
