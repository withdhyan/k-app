import SwiftUI
struct BuildBranchRailView: View {
    let changelog: [BuildChangelogEntry]
    let branches: [BuildBranchItem]
    let selectedBranchID: String?
    let onSelectBranch: (String, String) -> Void
    let onOpenLearned: () -> Void
    let onOpenTrust: () -> Void
    var selectedActionIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.buildReportSectionSpacing) {
            if !changelog.isEmpty {
                VStack(alignment: .leading, spacing: KStyle.buildChangelogRowSpacing) {
                    KMonoCaption("changelog", variant: .metadata, state: .active)
                    ForEach(changelog) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                            Text(entry.time)
                                .kFont(.monoCaptionDigit)
                                .foregroundStyle(.white.opacity(entry.isOk ? KStyle.primaryTextOpacity : KStyle.buildDimmerOpacity))
                            Text(entry.text)
                                .kFont(.monoCaption)
                                .foregroundStyle(.white.opacity(KStyle.buildDimOpacity))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: KStyle.buildBranchCardSpacing) {
                KMonoCaption("branches", variant: .metadata, state: .active)
                GroupedBranchCards(
                    branches: branches,
                    selectedBranchID: selectedBranchID,
                    onSelectBranch: onSelectBranch
                )
            }

            KActRow(
                actions: [KActItem(id: "learned"), KActItem(id: "trust")],
                variant: .build,
                selectedActionIDs: selectedActionIDs,
                onSelect: { item in item.id == "learned" ? onOpenLearned() : onOpenTrust() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, KStyle.buildReportSectionSpacing)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(KStyle.hairlineOpacity))
                .frame(height: KStyle.dividerHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build-branch-rail")
    }
}

private struct BuildBranchCardView: View {
    let branch: BuildBranchItem
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { isSelected ? KStyle.nearBlack : .white }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                HStack(spacing: KStyle.smallSpacing) {
                    dot
                    Text(branch.composedTitle)
                        .font(KStyle.blockDefaultTitleFont)
                        .foregroundStyle(ink.opacity(KStyle.primaryTextOpacity))
                }
                if !branch.status.isEmpty, !branch.isTrunk {
                    Text(branch.status)
                        .kFont(.monoCaption)
                        .foregroundStyle(ink.opacity(KStyle.tertiaryTextOpacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, KStyle.buildBranchCardVerticalPadding)
            .padding(.horizontal, KStyle.buildBranchCardHorizontalPadding)
            .background(
                Color.white.opacity(isSelected
                    ? KStyle.chatThreadFinishedFillOpacity
                    : KStyle.buildBranchCardFillOpacity),
                in: RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(
                        branch.isTrunk
                            ? KStyle.liveSignal.opacity(KStyle.buildBranchTrunkTintOpacity)
                            : .white.opacity(KStyle.hairlineOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(branch.title), \(branch.status)")
        .accessibilityIdentifier("build-branch-\(branch.id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(KStyle.chatExpansionMotion(reduceMotion), value: isSelected)
        .zIndex(isSelected ? KStyle.bioRailSelectedItemZIndex : KStyle.bioRailUnselectedItemZIndex)
        .shadow(
            color: KStyle.nearBlack.opacity(isSelected ? KStyle.bioDetailShadowOpacity : 0),
            radius: isSelected ? KStyle.bioDetailShadowRadius : 0,
            y: isSelected ? KStyle.bioDetailShadowY : 0
        )
    }

    @ViewBuilder
    private var dot: some View {
        if branch.isTrunk {
            Circle()
                .fill(KStyle.liveSignal)
                .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
        } else if branch.isBuilding, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                Circle()
                    .fill(isSelected ? KStyle.nearBlack : Color.white)
                    .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
                    .opacity(
                        KStyle.breathOpacity(
                            at: context.date,
                            period: KStyle.buildSegmentBreathPeriod,
                            minimumOpacity: KStyle.buildSegmentBreathMinOpacity
                        )
                    )
            }
        } else {
            Circle()
                .fill((isSelected ? KStyle.nearBlack : Color.white).opacity(KStyle.buildDimmerOpacity))
                .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
        }
    }
}

/// Renders branches in attention-based groups (< 5), each with a lowercase
/// header. The trunk is pinned top and ungrouped. Empty groups are collapsed.
private struct GroupedBranchCards: View {
    let branches: [BuildBranchItem]
    let selectedBranchID: String?
    let onSelectBranch: (String, String) -> Void

    private typealias BranchGroup = (
        group: BuildBranchGroup,
        items: [BuildBranchItem]
    )

    private var trunk: BuildBranchItem? {
        branches.first(where: \.isTrunk)
    }

    private var nonTrunk: [BuildBranchItem] {
        branches.filter { !$0.isTrunk }
    }

    private var activeGroups: [BranchGroup] {
        let grouped = Dictionary(grouping: nonTrunk, by: \.group)
        return BuildBranchGroup.allCases.compactMap { g in
            if let items = grouped[g], !items.isEmpty {
                return (g, items)
            }
            return nil
        }
    }

    var body: some View {
        // Trunk — pinned top, ungrouped.
        if let trunk {
            BuildBranchCardView(
                branch: trunk,
                isSelected: selectedBranchID == trunk.id,
                onSelect: { onSelectBranch(trunk.id, trunk.title) }
            )
        }

        // Groups — each with a small lowercase header.
        ForEach(activeGroups, id: \.group) { entry in
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                KMonoCaption(entry.group.label, variant: .metadata, state: .disabled)
                ForEach(entry.items) { branch in
                    BuildBranchCardView(
                        branch: branch,
                        isSelected: selectedBranchID == branch.id,
                        onSelect: { onSelectBranch(branch.id, branch.title) }
                    )
                }
            }
        }
    }
}
