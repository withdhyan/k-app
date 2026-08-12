import Foundation

/// Build reuses the chat context grammar. Live context is optional on the build
/// wire, so the ring stays absent when no measurement exists rather than inventing
/// a number. Fixture values keep the panel shape testable when a walk opts in.
enum BuildComposerContextStats {
    static func forBuild(_ stats: ContextStats) -> ContextStats {
        let labels = [KCopy.buildContextSpec, KCopy.buildContextDiffs, KCopy.buildContextLaw]
        let breakup = stats.breakup.enumerated().map { index, row in
            ContextBreakup(
                id: labels.indices.contains(index) ? labels[index] : row.id,
                label: labels.indices.contains(index) ? labels[index] : row.label,
                fraction: row.fraction
            )
        }
        return ContextStats(fullness: stats.fullness, breakup: breakup)
    }
}

extension KCopy {
    static let buildContextSpec = "spec"
    static let buildContextDiffs = "diffs"
    static let buildContextLaw = "law"
    static let buildContextTarget = "target"
    static let buildContextTokenBar = "context token bar"
    static let buildThreadsEmpty = "no threads yet"
    static let buildThreadsHeading = "threads"
    static let buildThreadsEtaLabel = "eta"
    static let buildThreadsRateLabel = "rate"
    // The metric label already names the measure. Keep the absence value
    // label-free so the row reads "eta · not available", never "eta eta ...".
    static let buildThreadsEta = "not available"
    static let buildThreadsRate = "not available"
    static let buildThreadsEarlier = "earlier"
    static let buildThreadsLater = "later"
    static let buildThreadsDoneAging = "done · aging out"
    static let buildThreadsQueued = "queued"
    static let buildThreadsHeldExternal = "held external"
    static let buildThreadsNeedsYou = "needs you"
    static let buildThreadsBuilding = "building"
    static let buildThreadsFailed = "failed"
    static let buildThreadsLanded = "landed"
    static let buildThreadsUnknown = "unknown"
    static let buildTrunkNoStream = "no factory turns yet"
    static let buildTrunkToday = "today"
    static let buildTrunkYesterday = "yesterday"
    static let buildTrunkQuietActsVisible = "quiet acts visible"
    static let buildTrunkHoldForQuietActs = "hold for quiet acts"
    static let buildTrunkCollapseReceipt = "collapse receipt"
    static let buildTrunkExpandReceipt = "expand receipt"
    static let buildTrunkBranchProposal = "branch this proposal"
    static let buildTrunkQuietBranch = "branch"
    static let buildTrunkQuietKeep = "keep in trunk"
    static let buildTrunkQuietJunk = "junk"

    static func buildTrunkDaysAgo(_ count: Int) -> String {
        "\(count) days ago"
    }

    static func buildThreadsPageAccessibility(count: Int, label: String) -> String {
        "+\(count) \(label) threads"
    }
}
