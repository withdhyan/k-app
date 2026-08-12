import SwiftUI
struct BuildStreamLineView: View {
    let line: BuildStreamLine
    let onOpenReview: (BuildRecord, BuildRecordSection.Kind) -> Void
    let onPeekLogTail: (BuildRecord) -> Void
    let isDepthOrigin: (BuildRecord) -> Bool
    let onSelectBranch: ((String) -> Void)?
    /// Trunk milestone rows carry their plan identity as a dim mono line.
    /// It is optional so branch/chat consumers keep their existing grammar.
    let branchName: String?
    @State private var isExpanded = false
    @State private var isDrawerOpen = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(
        line: BuildStreamLine,
        onOpenReview: @escaping (BuildRecord, BuildRecordSection.Kind) -> Void,
        onPeekLogTail: @escaping (BuildRecord) -> Void,
        isDepthOrigin: @escaping (BuildRecord) -> Bool,
        onSelectBranch: ((String) -> Void)? = nil,
        branchName: String? = nil
    ) {
        self.line = line
        self.onOpenReview = onOpenReview
        self.onPeekLogTail = onPeekLogTail
        self.isDepthOrigin = isDepthOrigin
        self.onSelectBranch = onSelectBranch
        self.branchName = branchName
    }

    var body: some View {
        VStack(alignment: line.role == .founder ? .trailing : .leading, spacing: 6) {
            if line.record == nil {
                lineContent
            } else {
                Button {
                    KStyle.withMotion {
                        isExpanded.toggle()
                    }
                } label: {
                    streamRow
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }

            if isKLine {
                KChatVerbDrawer(
                    isOpen: isDrawerOpen,
                    receipt: line.receipt,
                    messageID: "build-\(line.id)",
                    onSelect: handleVerb
                )
            }

            if isExpanded, let record = line.record, let kind = line.recordKind {
                BuildRecordExpandedDetails(
                    record: record,
                    kind: kind,
                    onOpenReview: { onOpenReview(record, kind) },
                    onPeekLogTail: { onPeekLogTail(record) }
                )
                    .padding(.leading, 18)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.role == .founder ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .opacity(line.record.map(isDepthOrigin) == true ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
        .accessibilityAddTraits(line.record.map(isDepthOrigin) == true ? .isSelected : [])
        .accessibilityHint(line.record.map(isDepthOrigin) == true ? "depth reader open from this record" : "")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: KStyle.buildThreadLongPressDuration)
                .onEnded { _ in
                    guard isKLine else { return }
                    KStyle.withMotion(reduceMotion: reduceMotion) {
                        isDrawerOpen = true
                    }
                }
        )
    }

    private var isKLine: Bool {
        guard line.role == .runner else { return false }
        // Queued and acknowledgement receipts are state rows. BuildTrunkStream
        // may route them here for their plain rendering, but they never gain a
        // long-press drawer or command targets.
        return !line.id.hasPrefix("intent-queued-")
            && !line.id.hasPrefix("intent-ack-")
    }

    private var reduceMotion: Bool {
        systemReduceMotion || KStyle.auditReduceMotionOverride
    }

    @ViewBuilder
    private var lineContent: some View {
        if let onSelectBranch, isKLine {
            Button {
                onSelectBranch(BuildTrunkBranchName.from(line: line))
            } label: {
                streamRow
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        } else if isKLine {
            streamRow
                .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .leading)
        } else {
            streamRow
        }
    }

    private var streamRow: some View {
        KStreamRow(role: streamRole, meta: line.meta) {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                TermAnnotatedText(
                    text: line.text,
                    annotations: line.termAnnotations,
                    font: KStyle.contentFont,
                    foregroundColor: textColor,
                    accessibilityIdentifier: "build-term-text-\(line.id)"
                )

                if let branchName, !branchName.isEmpty {
                    Text(branchName.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(Color.white.opacity(KStyle.buildThreadReceiptBranchOpacity))
                        .lineLimit(KStyle.singleLineLimit)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func handleVerb(_ verb: KChatVerb) {
        guard verb == .branch else { return }
        onSelectBranch?(BuildTrunkBranchName.from(line: line))
    }

    private var streamRole: KStreamRowRole {
        switch line.role {
        case .founder:
            return .founder
        case .runner:
            return .runner
        case .system:
            return .system
        }
    }

    private var textColor: Color {
        switch line.role {
        case .runner:
            return .white.opacity(KStyle.secondaryTextOpacity)
        case .founder:
            return .white.opacity(KStyle.tertiaryTextOpacity)
        case .system:
            return .white.opacity(KStyle.secondaryTextOpacity)
        }
    }
}
