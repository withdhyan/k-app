import SwiftUI
import UIKit

enum KFontToken: String, CaseIterable, Equatable {
    case content
    case nowTitle
    case blockActiveTitle
    case blockDefaultTitle
    case monoCaption
    case monoCaptionDigit
    case tab
    case input
    case inputControl
    case optionButton
    case verdict
    case evidence
    case mindStatement

    var basePointSize: CGFloat {
        switch self {
        case .content, .verdict:
            return 16
        case .blockDefaultTitle:
            return 15
        case .nowTitle:
            return 24
        case .blockActiveTitle:
            return 18
        case .monoCaption, .monoCaptionDigit:
            return 11
        case .tab, .optionButton, .evidence:
            return 12
        case .input, .inputControl:
            return 17
        case .mindStatement:
            return 28
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .content, .blockDefaultTitle, .verdict:
            return .callout
        case .nowTitle:
            return .title2
        case .blockActiveTitle:
            return .title3
        case .monoCaption, .monoCaptionDigit, .tab, .optionButton, .evidence:
            return .caption1
        case .input, .inputControl:
            return .body
        case .mindStatement:
            return .title1
        }
    }

    var weight: UIFont.Weight {
        switch self {
        case .nowTitle, .blockActiveTitle, .blockDefaultTitle, .inputControl, .optionButton, .verdict:
            return .regular
        case .mindStatement:
            return .light
        case .content, .monoCaption, .monoCaptionDigit, .tab, .input, .evidence:
            return .regular
        }
    }

    var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .monoCaption, .monoCaptionDigit, .tab, .evidence:
            return .monospaced
        case .content, .nowTitle, .blockActiveTitle, .blockDefaultTitle, .input, .inputControl, .optionButton, .verdict, .mindStatement:
            return .default
        }
    }

    var usesMonospacedDigits: Bool {
        self == .monoCaptionDigit
    }
}

enum KMotionResolution: Equatable {
    case timingCurve(Double, Double, Double, Double, duration: Double)
    case easeOut(duration: Double)
    case none
}

enum KNativeMotionName: String, CaseIterable, Equatable, Hashable, Sendable {
    case quick
    case zen
}

enum KFeedbackEvent: Equatable {
    case blockStarted
    case blockCompleted
    case buildCardAnswered
    case mindVerdictSubmitted
    case errorSurfaced
}

struct KRGBToken: Equatable, Sendable {
    let hex: String
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String, red255: Double, green255: Double, blue255: Double) {
        self.hex = hex
        red = red255 / 255
        green = green255 / 255
        blue = blue255 / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum KMaterialToken: String, Equatable {
    case ultraThin = "ultra-thin"
    case thin

    var material: Material {
        switch self {
        case .ultraThin:
            return .ultraThinMaterial
        case .thin:
            return .thinMaterial
        }
    }
}

enum KEnvironmentHazeResolution: Equatable {
    case haze(material: KMaterialToken, tintOpacity: Double)
    case nearBlack
}

struct KTabStripMetrics: Equatable {
    let itemSpacing: CGFloat
    let horizontalPadding: CGFloat
    let labelTracking: CGFloat
    let labelMinimumScaleFactor: CGFloat
}

struct KFeedbackTriggers: Equatable {
    private(set) var impactLightCount = 0
    private(set) var selectionCount = 0
    private(set) var errorCount = 0

    mutating func record(_ event: KFeedbackEvent?) {
        guard let event else { return }
        switch event {
        case .blockStarted, .blockCompleted, .buildCardAnswered:
            impactLightCount += 1
        case .mindVerdictSubmitted:
            selectionCount += 1
        case .errorSurfaced:
            errorCount += 1
        }
    }
}

enum KFeedbackPolicy {
    static func cadenceBlockEvent(for action: CadenceBlockAction) -> KFeedbackEvent? {
        switch action {
        case .start:
            return .blockStarted
        case .complete:
            return .blockCompleted
        case .pause, .skip, .extend15, .twsYes, .twsNo, .wakeInit:
            return nil
        }
    }

    static func buildAnswerEvent(before: BuildCard, after: BuildCard) -> KFeedbackEvent? {
        before.isOpen && after.isAnswered ? .buildCardAnswered : nil
    }

    static func mindVerdictEvent(didSubmit: Bool) -> KFeedbackEvent? {
        didSubmit ? .mindVerdictSubmitted : nil
    }

    static func errorSurfaced(previous: String?, current: String?) -> KFeedbackEvent? {
        normalized(previous).isEmpty && !normalized(current).isEmpty ? .errorSurfaced : nil
    }

    private static func normalized(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum KStyle {
    /// XCTest can exercise the reduced-motion branch without mutating the
    /// simulator-wide accessibility preference. Production still reads the
    /// system environment; the override is a sealed launch-only audit seam.
    static var auditReduceMotionOverride: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-test-reduce-motion")
#else
        false
#endif
    }

    static let fullOpacity = 1.0
    // Founder 2026-07-10: "much darker and translucent" → superseded.
    // Founder 2026-07-20: "bg needs to be much darker and more opaque." → superseded.
    // Founder 2026-08-06: "dial back" — the 0.94 near-solid made the haze read as an
    // opaque slab (0.97 effective), not glass. Back to glass: 0.65 lands the haze at
    // ~0.81 effective, inside the [0.75, 0.82] still-glass band.
    static let backgroundOpacity = 0.65
    static let primaryTextOpacity = 0.87
    static let secondaryTextOpacity = 0.64
    static let tertiaryTextOpacity = 0.48
    static let quaternaryTextOpacity = 0.30
    static let hairlineOpacity = 0.08
    static let hairlineStrongOpacity = 0.16
    static let controlHairlineOpacity = 0.22
    static let dividerOpacity = 0.12
    static let panelScrimOpacity = 0.24
    static let hazeTintOpacity = 0.47
    static let glassOpacity = 0.35
    static let glassStrongOpacity = 0.52
    static let paperOpacity = 0.10
    static let progressTrackOpacity = 0.13
    static let progressFillOpacity = 0.56
    static let inputFillOpacity = 0.06
    static let controlEnabledFillOpacity = 0.90
    static let controlPendingFillOpacity = 0.62
    static let controlDisabledFillOpacity = 0.10
    static let controlPressedFillOpacity = 0.72
    static let controlPendingDotOpacity = 0.42
    static let primaryControlTextOpacity = 0.86
    static let errorTextOpacity = 0.92
    static let activeDotOpacity = 0.96
    static let idleDotOpacity = 0.72
    static let staleDotFactor = 0.5
    static let idleSignalOpacity = 0.52
    static let mindDividerOpacity = 0.10
    static let scrollEdgeFadeOpacity = 0.045

    // Fidelity pass 2026-07-20: mocks card 12-14 / controls 8-10; 3 read near-square.
    static let cornerRadius: CGFloat = 12
    static let hairlineWidth: CGFloat = 1
    static let dividerHeight: CGFloat = 1
    static let columnMinWidth: CGFloat = 360
    static let columnMaxWidth: CGFloat = 720
    static let readingMeasureMaxWidth: CGFloat = 565
    static let columnMargin: CGFloat = 18
    static let minimumTapTarget: CGFloat = 44
    static let cardPadding: CGFloat = 12
    static let cardLargePadding: CGFloat = 14
    static let blockTimeGutterWidth: CGFloat = 72
    static let blockDotSmallSize: CGFloat = 7
    static let blockDotRegularSize: CGFloat = 10
    static let blockDotTopPadding: CGFloat = 7
    static let blockCardVerticalPadding: CGFloat = 16
    static let blockRowVerticalPadding: CGFloat = 8
    static let blockCardHorizontalPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 10
    static let tightRowSpacing: CGFloat = 8
    static let smallSpacing: CGFloat = 6
    static let microSpacing: CGFloat = 3
    static let summarySpacing: CGFloat = 6
    // Shared fetch grammar: static, dim, no-shimmer lines and an inline loading dot.
    static let loadingSkeletonRowSpacing: CGFloat = 8
    static let loadingSkeletonLineHeight: CGFloat = 12
    static let loadingSkeletonMetaHeight: CGFloat = 9
    static let loadingSkeletonCornerRadius: CGFloat = 3
    static let loadingSkeletonMinHeight: CGFloat = 70
    static let loadingSkeletonFillOpacity = paperOpacity
    static let loadingSkeletonMetaOpacity = hairlineStrongOpacity
    static let loadingSkeletonWidths: [CGFloat] = [0.92, 0.66, 0.30]

    static func loadingSkeletonWidth(for index: Int) -> CGFloat {
        loadingSkeletonWidths[min(max(index, 0), loadingSkeletonWidths.count - 1)]
    }
    static let streamRowGutterWidth: CGFloat = 58
    static let bandishTimeGutterWidth: CGFloat = 80
    static let bandishDotColumnWidth: CGFloat = 48
    static let bandishStatusDotSize: CGFloat = 8
    static let activeBandishCornerRadius: CGFloat = 8
    static let activeBandishTrailingOverhang: CGFloat = 54
    static let activeBandishLeadingOffset: CGFloat = -16
    static let activeBandishShadowRadius: CGFloat = 12
    static let activeBandishShadowY: CGFloat = 8
    static let activeBandishShadowOpacity = 0.12
    static let activeBandishProgressOverlayOpacity = 0.15
    static let activeBandishStartedDotMinimumOpacity = 0.28
    static let activeBandishStartedDotPeriod: TimeInterval = 4
    static let cadenceCompleteCheckIconSize: CGFloat = 13
    static let cadenceStreamPanelHorizontalPadding: CGFloat = 8
    static let cadenceStreamPanelTopPadding: CGFloat = 6
    static let cadenceStreamPanelBottomPadding: CGFloat = 10
    static let cadenceStreamPanelRowSpacing: CGFloat = 0
    static let cadenceStreamPreviousTopPadding: CGFloat = 20
    static let cadenceArcTopSpace: CGFloat = 16
    static let cadenceArcBottomSpace: CGFloat = 36
    static let cadenceStreamPreviousBottomPadding: CGFloat = 2
    static let cadenceDayRowTimeWidth: CGFloat = 56
    static let cadenceDayRowVerticalPadding: CGFloat = 10
    static let cadenceWorkChipHorizontalPadding: CGFloat = 7
    static let cadenceWorkChipVerticalPadding: CGFloat = 2
    static let cadenceWorkChipGroupPadding: CGFloat = 3
    static let cadenceWorkChipHeight: CGFloat = 30
    static let cadenceWorkChipGroupFillOpacity = 0.10
    static let cadenceWorkChipLockSize: CGFloat = 9
    // Weekly retro v3 geometry. The surface composes KSelectorStrip, KPaperCard,
    // and the existing paper-card family; these tokens only own route spacing and
    // the iPad-to-compact handoff.
    static let retroFlowBottomSpacing: CGFloat = 8
    static let retroCardHorizontalPadding: CGFloat = 20
    static let retroCardVerticalPadding: CGFloat = 16
    static let retroCardHeaderSpacing: CGFloat = 10
    static let retroCardMetricSpacing: CGFloat = 18
    static let retroCardMetricVerticalPadding: CGFloat = 8
    static let retroCardActTopSpacing: CGFloat = 8
    static let retroSurfaceMaxWidth: CGFloat = 980
    static let retroDetailPadding: CGFloat = 30
    static let retroDetailCompactPadding: CGFloat = 18
    static let retroDetailTitleSpacing: CGFloat = 2
    static let retroDetailSubtitleBottomSpacing: CGFloat = 18
    static let retroDetailSectionSpacing: CGFloat = 18
    static let retroDetailSectionTitleSpacing: CGFloat = 8
    static let retroDetailRowVerticalPadding: CGFloat = 6
    static let retroDetailRowColumnSpacing: CGFloat = 10
    static let retroDetailDotSize: CGFloat = 6
    static let retroDetailRCAIndent: CGFloat = 24
    static let retroDetailRCAContentPadding: CGFloat = 14
    static let retroDetailRCASpacing: CGFloat = 6
    static let retroDetailDividerOpacity: Double = 0.12
    static let retroCompactWidthThreshold: CGFloat = 760
    static let retroTabBottomSpacing: CGFloat = 10
    static let selectorTrackPadding: CGFloat = 4
    static let selectorTrackFillOpacity = 0.10
    static let selectorActiveFillOpacity = 0.90
    static let selectorActiveTextOpacity = 0.86
    static let selectorInactiveTextOpacity = 0.48
    // Shared in-panel selector grammar, ported from the bandish mode-pill
    // treatment. The 3pt group inset leaves a visible margin around the one
    // active fill; the 2pt sibling seam and 7pt side padding keep the strip
    // quiet. Visual pills are 30pt high while their transparent button label
    // retains the doctrine's 44pt tap target.
    static let selectorStripItemSpacing: CGFloat = tabLabelSpacing
    static let selectorStripItemMinimumWidth: CGFloat = minimumTapTarget
    static let selectorStripItemHorizontalPadding: CGFloat = cadenceWorkChipHorizontalPadding
    static let selectorStripItemVisualHeight: CGFloat = cadenceWorkChipHeight
    static let selectorStripTrackInset: CGFloat = cadenceWorkChipGroupPadding
    static let selectorStripTrackVisualHeight: CGFloat = cadenceWorkChipHeight + selectorStripTrackInset * 2
    static let selectorStripTrackCornerRadius: CGFloat = activeBandishCornerRadius
    static let selectorStripActiveCornerRadius: CGFloat = 6
    static let selectorStripTrackVerticalPadding: CGFloat = 0
    static let selectorStripTrackHorizontalPadding: CGFloat = selectorStripTrackInset
    // Bio surface — cursafe v11 conformance (founder ruling 2026-08-04). The
    // overview is a 3×2 system grid; nutrition carries the capture control over
    // a faint live-camera stage. Bio's rendered sub-tab strip uses the shared
    // tabStripMetrics/inset-track grammar below, not a second chip grammar.
    static let bioChipCornerRadius: CGFloat = 8
    // Retained for the legacy selector source; rendered bio chrome uses the
    // app-wide tab-strip tokens above and below.
    static let bioChipHorizontalPadding: CGFloat = 14
    static let bioChipSpacing: CGFloat = 8
    static let bioSystemGridColumns = 3
    static let bioSystemGridSpacing: CGFloat = 12
    static let bioSystemCardPadding: CGFloat = 16
    static let bioSystemRowSpacing: CGFloat = 6
    static let bioSystemScoreSize: CGFloat = 30
    static let bioFeelingScaleDragMinimumDistance: CGFloat = 8
    static let bioCameraStageOpacity = 0.10
    static let bioCameraStageRevealOpacity = 0.72
    static let bioCameraHoldDuration: TimeInterval = 0.45
    static let bioCameraVideoMaximumDuration: TimeInterval = 8
    static let bioCaptureIconSize: CGFloat = 24
    static let bioCaptureGlyphLineWidth: CGFloat = 1.6
    static let bioStaleFadeOpacity = 0.72
    // Rail-and-jut master/detail (bio-neuro-nutrition-port-spec §1): a fixed glass
    // rail under the detail seam, with only the selected origin row rising above
    // the white card by its 24pt overlap; content stays clear by a 64pt left inset.
    // The detail slides in from x−40.
    // Compact size class stacks the rail and detail; regular iPad width keeps the
    // rail-and-jut composition in both orientations.
    static let bioRailWidth: CGFloat = 420
    static let bioRailMaxFraction: CGFloat = 0.42
    static let bioDetailOverlap: CGFloat = 24
    static let bioDetailTopInset: CGFloat = 48
    static let bioDetailPadding: CGFloat = 40
    static let bioDetailContentLeading: CGFloat = 64
    static let bioDetailSlideInX: CGFloat = -40
    static let bioDetailShadowOpacity = 0.12
    static let bioDetailShadowRadius: CGFloat = 4
    static let bioDetailShadowY: CGFloat = 2
    // UI17 bio research tabs. These tokens mirror the v11 mock's rail, paper
    // detail, range, chart, and coverage geometry without leaking literals into
    // surface code.
    static let bioResearchRailSurfaceOpacity = 0.03
    static let bioResearchRailWidth: CGFloat = 340
    static let bioResearchRailMaxFraction: CGFloat = 0.50
    static let bioResearchDetailOverlap: CGFloat = 12
    static let bioResearchDetailTopInset: CGFloat = 0
    static let bioResearchDetailPadding: CGFloat = 32
    static let bioResearchDetailContentLeading: CGFloat = 44
    static let bioResearchRailCornerRadius: CGFloat = 14
    static let bioResearchRailVerticalPadding: CGFloat = 16
    static let bioResearchRailHorizontalPadding: CGFloat = 20
    static let bioResearchRailRowVerticalPadding: CGFloat = 14
    static let bioResearchRailSelectionOverhang: CGFloat = 24
    static let bioResearchInactiveSelectionOverhang: CGFloat = 0
    static let bioResearchActiveShadowOpacity = 0.35
    static let bioResearchInactiveShadowOpacity = 0.0
    static let bioResearchActiveShadowRadius: CGFloat = 24
    static let bioResearchActiveShadowY: CGFloat = 8
    // Rail-and-jut ordering: the detail card owns the seam, then only the
    // selected origin row rises back above it. Unselected rows stay underneath.
    static let bioRailUnselectedItemZIndex: Double = 0
    static let bioRailDetailZIndex: Double = 1
    static let bioRailSelectedItemZIndex: Double = 2
    static let bioResearchRailRowSpacing: CGFloat = 8
    static let bioResearchSectionSpacing: CGFloat = 12
    static let bioProtocolDomainBottomSpacing: CGFloat = 24
    static let bioResearchDetailMinimumHeight: CGFloat = 280
    static let bioResearchDetailTitleSpacing: CGFloat = 4
    static let bioResearchDetailSubtitleBottomSpacing: CGFloat = 24
    static let bioResearchDetailNoteTopSpacing: CGFloat = 16
    static let bioResearchDetailHistoryTopSpacing: CGFloat = 24
    static let bioResearchDetailSourcesTopSpacing: CGFloat = 20
    static let bioResearchProtocolCategoriesTopSpacing: CGFloat = 22
    static let bioResearchProtocolBookingTopSpacing: CGFloat = 24
    static let bioResearchMeditationPhasesTopSpacing: CGFloat = 20
    static let bioResearchMeditationFocusTopSpacing: CGFloat = 12
    static let bioResearchMeditationSectionTopSpacing: CGFloat = 20
    static let bioResearchMeditationIndicationsTopSpacing: CGFloat = 22
    static let bioResearchMeditationSafetyTopSpacing: CGFloat = 22
    static let bioRangeBandHeight: CGFloat = 6
    static let bioRangeBandCornerRadius: CGFloat = 3
    static let bioRangeBandVerticalSpacing: CGFloat = 8
    static let bioRangeTickWidth: CGFloat = 2
    static let bioRangeTickExtension: CGFloat = 5
    static let bioRangeValueOffset: CGFloat = 22
    static let bioHistoryHeight: CGFloat = 72
    static let bioHistoryMaximumWidth: CGFloat = 380
    static let bioHistoryLineWidth: CGFloat = 1.5
    static let bioHistoryEndDotSize: CGFloat = 6
    static let bioHistoryBottomLabelOffset: CGFloat = 12
    static let bioSparklineWidth: CGFloat = 40
    static let bioSparklineHeight: CGFloat = 12
    static let bioSparklineLineWidth: CGFloat = 1
    static let bioSourceDocumentGlyphSize: CGFloat = 12
    static let bioProtocolCoverageRingSize: CGFloat = 44
    static let bioProtocolCoverageRingRadius: CGFloat = 18
    static let bioProtocolCoverageRingLineWidth: CGFloat = 3
    static let bioProtocolCategoryDotSize: CGFloat = 6
    static let bioProtocolCategoryColumnSpacing: CGFloat = 24
    static let bioProtocolCategoryRowSpacing: CGFloat = 10
    static let bioProtocolEvidenceCornerRadius: CGFloat = 6
    static let bioProtocolEvidenceHorizontalPadding: CGFloat = 9
    static let bioProtocolEvidenceVerticalPadding: CGFloat = 5
    static let bioProtocolPhaseCornerRadius: CGFloat = 6
    static let bioProtocolPhaseHorizontalPadding: CGFloat = 12
    static let bioProtocolPhaseVerticalPadding: CGFloat = 7
    static let bioProtocolPhaseSpacing: CGFloat = 2
    static let bioProtocolPhaseTrackPadding: CGFloat = 4
    static let bioProtocolPhaseMinimumHeight: CGFloat = 34
    static let bioProtocolSafetyDotSize: CGFloat = 5
    static let bioProtocolSafetyLeadingPadding: CGFloat = 14
    static let bioProtocolSafetyVerticalPadding: CGFloat = 5
    static let bioProtocolIndicatorRowVerticalPadding: CGFloat = 6
    static let bioProtocolIndicatorSpacing: CGFloat = 10
    static let bioProtocolIndicatorPillCornerRadius: CGFloat = 5
    static let bioProtocolIndicatorPillHorizontalPadding: CGFloat = 8
    static let bioProtocolIndicatorPillVerticalPadding: CGFloat = 3
    static let bioProtocolDetailMaxTextWidth: CGFloat = 460
    static let bioProtocolNoteMaximumCharacters = 280
    static let bioPaperPrimaryOpacity = 0.90
    static let bioPaperSecondaryOpacity = 0.72
    static let bioPaperTertiaryOpacity = 0.55
    static let bioPaperQuaternaryOpacity = 0.30
    static let bioRailPrimaryOpacity = 0.87
    static let bioRailSecondaryOpacity = 0.45
    static let bioRailTertiaryOpacity = 0.22
    static let bioRangeTrackOpacity = 0.08
    static let bioRangeRedOpacity = 0.85
    static let bioRangeGreenOpacity = 0.85
    static let bioHistoryAreaTopOpacity = 0.10
    static let bioHistoryAreaBottomOpacity = 0.0
    static let bioHistoryLineOpacity = 0.75
    static let bioHistoryLabelOpacity = 0.28
    // W20 bio workout archive. These route-scoped measurements keep the
    // rail/detail composition on the shared token seam.
    static let bioWorkoutRailRowVerticalPadding: CGFloat = 12
    static let bioWorkoutRailHorizontalPadding: CGFloat = 20
    static let bioWorkoutRailFooterTopSpacing: CGFloat = 14
    static let bioWorkoutDetailColumnSpacing: CGFloat = 48
    static let bioWorkoutDetailMetaBottomSpacing: CGFloat = 28
    static let bioWorkoutDetailSectionLaterSpacing: CGFloat = 26
    static let bioWorkoutExerciseRowVerticalPadding: CGFloat = 7.5
    static let bioWorkoutZoneBarHeight: CGFloat = 7
    static let bioWorkoutZoneBarCornerRadius: CGFloat = 3.5
    static let bioWorkoutZoneLabelWidth: CGFloat = 20
    static let bioWorkoutZoneMinutesWidth: CGFloat = 22
    static let bioWorkoutZoneSpacing: CGFloat = 12
    static let bioWorkoutTrendHeight: CGFloat = 150
    static let bioWorkoutTrendPointDotSize: CGFloat = 6
    static let bioWorkoutTrendBottomLabelOffset: CGFloat = 18
    static let bioWorkoutTrendValueOffset: CGFloat = 12
    static let bioWorkoutHintTopSpacing: CGFloat = 20
    static let bioWorkoutHintLabelSpacing: CGFloat = 10
    static let bioWorkoutBackGestureThreshold: CGFloat = 64
    static let bioCoverageTrackOpacity = 0.08
    static let bioCoverageFillOpacity = 0.90
    static let bioProtocolEvidenceStrongOpacity = 0.16
    static let bioProtocolEvidenceModerateOpacity = 0.14
    static let bioProtocolEvidenceTradOpacity = 0.06
    static let bioProtocolSafetyOpacity = 0.60
    static let bioProtocolAbsoluteSafetyOpacity = 0.80
    static let bioCoverageRingRotation: Angle = .degrees(-90)
    static let bioProtocolSafetySignal = Color(red: 0.64, green: 0.34, blue: 0.23)
    static let bioProtocolAbsoluteSafetySignal = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let bioProtocolRangeGradient: [Color] = [
        signalFailure.opacity(bioRangeRedOpacity),
        signalWarning.opacity(bioRangeRedOpacity),
        liveSignal.opacity(bioRangeGreenOpacity),
        liveSignal.opacity(bioRangeGreenOpacity),
        signalWarning.opacity(bioRangeRedOpacity),
        signalFailure.opacity(bioRangeRedOpacity),
    ]
    // Nutrition calendar (bio mock §430): a month grid where a day reads green when its
    // logged kcal lands within tolerance of the daily target. Target is a default until a
    // real founder target lands (real data before machinery — the sums are real, the
    // target is a placeholder constant).
    static let bioNutritionDailyTargetKcal: Double = 2000
    static let bioNutritionTargetTolerance: Double = 0.10
    static let bioCalendarColumns = 7
    static let bioCalendarCellSpacing: CGFloat = 2
    static let bioCalendarCellHeight: CGFloat = 46
    static let bioCalendarDotSize: CGFloat = 4
    // On-target day = a green CELL background (web: rgba(107,157,124,0.30)); consecutive
    // on-target cells corner-merge into a streak. Detail macro bars use web targets.
    static let bioCalendarOnTargetFillOpacity: Double = 0.30
    // Nutrition range bar (bio detail): the optimal band is a faint ink wash; the
    // position dot is quiet ink — status color lives in the row dot, never the slider
    // (founder 2026-08-06; #24 neutral-slider ruling).
    static let bioRangeTrackInkOpacity: Double = 0.08
    static let bioRangeBandInkOpacity: Double = 0.14
    static let bioRangeDotInkOpacity: Double = 0.30
    static let bioNutritionProteinTarget: Double = 150
    static let bioNutritionCarbsTarget: Double = 250
    static let bioNutritionFatTarget: Double = 80
    static let bioNutritionFiberTarget: Double = 30
    static let bioNutritionRangeBarHeight: CGFloat = 6
    static let bioNutritionRangeDotSize: CGFloat = 6
    static let bioNeutralNutrientOpacity: Double = 0.60
    static let bioNutrientStatusDotSize: CGFloat = 4
    static let bioMealTimelineSpineOpacity: Double = 0.12
    static let bioMealTimelineSpineLeading: CGFloat = 6.5
    static let bioMealTimelineSpineVerticalPadding: CGFloat = 8
    static let bioMealTimelineDotSize: CGFloat = 14
    static let bioMealTimelineDotBorderWidth: CGFloat = 2
    static let bioMealTimelineDotBorderOpacity: Double = 0.35
    static let bioMealTimelineGutterWidth: CGFloat = 52
    static let bioMealTimelineGutterTrailing: CGFloat = 12
    static let bioMealTimelineAxisWidth: CGFloat = 16
    static let bioMealTimelineBodyLeading: CGFloat = 12
    static let bioMealTimelineRowBottomPadding: CGFloat = 24
    static let bioMealPhotoSlotWidth: CGFloat = 120
    static let bioMealPhotoSlotHeight: CGFloat = 80
    // UI16 meal micronutrients. The section is quiet by default: confidence is
    // carried by row fill and text opacity, never by a percentage badge.
    static let microCollapsedCount = 3
    static let microSectionSpacing: CGFloat = 8
    static let microRowSpacing: CGFloat = 4
    static let microRowVerticalPadding: CGFloat = 6
    static let microConfidenceTrackOpacity: Double = 0.06
    static let microConfidenceFillOpacity: Double = 0.14
    static let microConfidenceMinimumOpacity: Double = 0.30
    static let microConfidenceMaximumOpacity: Double = 0.87
    static let microPinchExpandThreshold: CGFloat = 1.25
    static let microPinchCollapseThreshold: CGFloat = 0.8
    static let microRevealDuration: TimeInterval = 0.25

    static func microConfidenceOpacity(_ confidence: Double) -> Double {
        let bounded = min(max(confidence, 0), 1)
        return microConfidenceMinimumOpacity
            + (microConfidenceMaximumOpacity - microConfidenceMinimumOpacity) * bounded
    }

    static let connectionSignalMinimumOpacity = 0.28
    static let connectionSignalPeriod: TimeInterval = 4
    static let progressStripHeight: CGFloat = 1
    static let actButtonMinWidth: CGFloat = 30
    static let tabItemSpacing: CGFloat = 22
    static let tabCompactWidthThreshold: CGFloat = 430
    static let tabCompactItemSpacing: CGFloat = 8
    static let tabLabelSpacing: CGFloat = 2
    static let tabHorizontalPadding: CGFloat = 14
    static let tabCompactHorizontalPadding: CGFloat = 6
    static let tabCompactTracking: CGFloat = 0
    static let tabLabelMinimumScaleFactor: CGFloat = 0.86
    // Floating icon nav (blessed 2026-08-03 mock): bottom bar on compact width,
    // right side rail on regular width. Bottom-bar item 32 / icon 14; rail item 40 / icon 17.
    static let navCompactItemSize: CGFloat = 32
    static let navRegularItemSize: CGFloat = 40
    static let navCompactIconSize: CGFloat = 14
    static let navRegularIconSize: CGFloat = 17
    static let navCompactItemSpacing: CGFloat = 10
    static let navRegularItemSpacing: CGFloat = 14
    static let navCompactVerticalPadding: CGFloat = 7
    static let navCompactHorizontalPadding: CGFloat = 12
    static let navRegularVerticalPadding: CGFloat = 16
    static let navRegularHorizontalPadding: CGFloat = 10
    static let navBottomInset: CGFloat = 24
    static let navTrailingInset: CGFloat = 32
    static let navCompactContentClearance: CGFloat = 88
    static let navRegularContentClearance: CGFloat = 120
    static let navIconViewBox: CGFloat = 24
    static let navIconStrokeRatio: CGFloat = 1.4
    // Root-nav and notification dots share the cadence tab's one indicator
    // grammar. Keep the legacy name as an alias so older primitive call sites
    // cannot drift into a second size.
    static let navStatusDotSize: CGFloat = 6
    static let navUnreadDotSize: CGFloat = navStatusDotSize
    static let navStatusDotColor = Color.white
    static let navStatusDotOffsetX: CGFloat = 0
    static let navStatusDotOffsetY: CGFloat = 0
    static let navStatusDotOpacity = primaryTextOpacity
    static let navStatusDotMinimumOpacity = secondaryTextOpacity
    static let navStatusDotPeriod: TimeInterval = 4
    static let navStatusDotTickInterval: TimeInterval = 0.15
    static let navBarShadowRadius: CGFloat = 12
    static let navBarShadowY: CGFloat = 8
    static let navBarGroundOpacity = 0.92
    static let navSelectedIconOpacity = 0.96
    static let navIdleIconOpacity = 0.45
    static let navSelectedRingOpacity = 0.18
    static let navBarShadowOpacity = 0.5

    // Notifications stay peripheral until the founder opens them. The status dot
    // breathes opacity only, matching the doctrine's quiet status-dot rule.
    static let notifStatusDotSize: CGFloat = navStatusDotSize
    static let notifStatusDotColor = navStatusDotColor
    static let notifStatusDotOpacity = navStatusDotOpacity
    static let notifStatusDotMinimumOpacity = navStatusDotMinimumOpacity
    static let notifStatusDotPeriod: TimeInterval = navStatusDotPeriod
    static let notifStatusDotTickInterval: TimeInterval = navStatusDotTickInterval
    static let notifPanelWidth: CGFloat = 300
    static let notifRowSpacing: CGFloat = 8
    static let notifRowVerticalPadding: CGFloat = 4
    static let notifGlyphSize: CGFloat = 14
    static let notifGlyphColumnWidth: CGFloat = 20
    static let notifGlyphOpacity = 0.64
    static let notifTitleOpacity = 0.87
    static let notifSeenOpacity = 0.48
    static let notifNavGap: CGFloat = 10
    static let notifUnfurlOffset: CGFloat = 6
    static let notifUnfurlDuration: TimeInterval = 0.22
    static let notifReducedMotionDuration: TimeInterval = 0.15

    static var notifGlyphFont: Font {
        .system(size: notifGlyphSize, weight: .regular)
    }

    /// Stroke width for a nav glyph rendered at `iconSize`, holding the founder-locked
    /// 1.4 weight in the 24-unit viewBox proportional as the icon scales.
    static func navIconStrokeWidth(iconSize: CGFloat) -> CGFloat {
        iconSize / navIconViewBox * navIconStrokeRatio
    }
    static let optionButtonSpacing: CGFloat = 6
    static let optionButtonHorizontalPadding: CGFloat = 10
    static let optionButtonVerticalPadding: CGFloat = 7
    static let optionButtonPendingDotSize: CGFloat = 5
    static let inputSidePadding: CGFloat = 18
    static let inputTrailingPadding: CGFloat = 16
    static let inputBottomPadding: CGFloat = 14
    static let inputBarSpacing: CGFloat = 10
    static let inputStatusSpacing: CGFloat = 7
    static let inputHorizontalPadding: CGFloat = 11
    static let inputVerticalPadding: CGFloat = 9
    static let inputMinLineCount = 1
    static let inputDefaultMaxLineCount = 5
    static let inputBuildMaxLineCount = 3
    static let inputControlSize: CGFloat = 44
    static let chatReservedLeadingWidth: CGFloat = 80
    static let chatThreadStackWidth: CGFloat = 260
    static let chatThreadExpandedWidth: CGFloat = 620
    static let chatCompactThreadWidth: CGFloat = 248
    static let chatShellColumnGap: CGFloat = 32
    static let chatRegularLayoutMinimumWidth: CGFloat = 900
    static let chatThreadCornerControlSize: CGFloat = 32
    static let chatThreadStatusDotSize: CGFloat = 6
    static let chatThreadLiftScale: CGFloat = 1.02
    static let chatThreadPressedScale: CGFloat = 0.97
    static let chatThreadHistoryMaxFraction: CGFloat = 0.7
    static let chatThreadCardShadowRadius: CGFloat = 24
    static let chatThreadCardShadowY: CGFloat = 6
    static let chatThreadCardShadowOpacity = 0.40
    static let chatThreadFinishedFillOpacity = 0.98
    static let chatThreadCollapsedFillOpacity = 0.08
    static let chatThreadPaperPrimaryOpacity = 0.90
    static let chatThreadPaperSecondaryOpacity = 0.50
    static let chatThreadDotMinimumOpacity = 0.45
    static let chatThreadPageStaggerInterval: TimeInterval = 0.06
    static let chatThreadHistoryFocusOpacity = 0.95
    static let chatThreadHistoryDimOpacity = 0.58
    // Context ring grammar (chat mock v16): the ring stays ink-only; the panel grows
    // from the ring and the fill sweep is reserved for a changed context measurement.
    static let contextRingButtonSize: CGFloat = Self.inputControlSize
    static let contextRingGlyphSize: CGFloat = 26
    static let contextRingStrokeWidth: CGFloat = 2.5
    static let contextRingRotationDegrees: Double = -90
    static let contextRingTrackOpacity = 0.12
    static let contextRingFillOpacity = Self.primaryTextOpacity
    static let contextRingNearFullFillOpacity = Self.primaryTextOpacity
    static let contextRingNearFullThreshold = 0.85
    static let contextRingPercentOpacity = Self.quaternaryTextOpacity
    static let contextRingHeaderOpacity = Self.tertiaryTextOpacity
    static let contextRingRowLabelOpacity = Self.tertiaryTextOpacity
    static let contextRingFractionOpacity = Self.secondaryTextOpacity
    static let contextRingBarTrackOpacity = Self.progressTrackOpacity
    static let contextRingBarFillOpacity = Self.secondaryTextOpacity
    static let contextRingBarHeight: CGFloat = 8
    static let contextRingPanelWidth: CGFloat = 280
    static let contextRingPanelPadding: CGFloat = Self.cardLargePadding
    static let contextRingPanelSpacing: CGFloat = Self.smallSpacing
    static let contextRingRowSpacing: CGFloat = Self.microSpacing
    static let contextRingRevealOffset: CGFloat = Self.smallSpacing
    static let contextRingPinchExpandThreshold: CGFloat = 1.25
    static let contextRingPinchCollapseThreshold: CGFloat = 0.8
    // The panel follows chat-v16's zen structure timing. The one-second ring sweep
    // is a rare measurement change and mirrors the mock's stroke-dashoffset timing.
    static let contextRingExpansionDuration: TimeInterval = 0.7
    static let contextRingFillDuration: TimeInterval = 1.0
    // Ontological term depth stays quiet: the range is marked by an underline
    // whisper, and the definition reuses the existing in-place expansion grammar.
    static let termHighlightColor = Color.white
    static let termHighlightUnderlineOpacity = 0.64
    static let termPinchExpandThreshold: CGFloat = 1.25
    static let termPinchCollapseThreshold: CGFloat = 0.8
    static let termDefinitionSpacing: CGFloat = 6
    static let termDefinitionRevealOffset: CGFloat = 6
    static let termFlowLineSpacing: CGFloat = 3
    static let termFlowMinimumWidth: CGFloat = 44
    static let evidencePadding: CGFloat = 10
    static let verdictButtonHeight: CGFloat = 56
    static let verdictButtonSpacing: CGFloat = 8
    static let decisionConsequenceMaxWidth: CGFloat = 420
    static let sensesRailWidth: CGFloat = 190
    static let sensesRailGap: CGFloat = 28
    static let buildWorkerRailWidth: CGFloat = 220
    static let buildWorkerRegularRailMinimumWidth: CGFloat = 700
    // v43 mock: the thread window is a narrow 200pt side column beside the trunk.
    static let buildReportRailWidth: CGFloat = 200
    static let buildReportRailGap: CGFloat = 48
    static let buildReportRailLeadingPadding: CGFloat = 32
    static let buildReportRailTopPadding: CGFloat = 48
    static let buildReportCompactMaxWidth: CGFloat = 720
    static let buildReportSectionSpacing: CGFloat = 16
    static let buildReportMetricSpacing: CGFloat = 2
    static let buildReportStateBottomPadding: CGFloat = 8
    static let buildReportDividerVerticalPadding: CGFloat = 8
    static let buildReportCompactTopPadding: CGFloat = 16
    static let buildReportArrivalOffset: CGFloat = 3
    // #26 slice B: selecting a plan on iPad juts its detail into the side rail instead
    // of growing the row in place. Small lateral offset only — position follows
    // opacity, it does not lead it.
    static let buildPlanDetailRevealOffsetX: CGFloat = 16
    // v4 report-first surface (build-k mock). Segment pills: 8×3 rounded, 3pt gap; the
    // building/needs-you pills breathe on a 4s zen cycle between .72 and full opacity.
    static let buildSegmentPillWidth: CGFloat = 8
    static let buildSegmentPillHeight: CGFloat = 3
    static let buildSegmentPillRadius: CGFloat = 2
    static let buildSegmentPillGap: CGFloat = 3
    static let buildSegmentBreathPeriod: TimeInterval = 4
    static let buildSegmentBreathMinOpacity = 0.72
    // Mock ink scale: --dim .45, --dimmer .22 (distinct from the app's .48/.30 desk scale;
    // these two are the report surface's own, matched to the blessed mock).
    static let buildDimOpacity = 0.45
    static let buildDimmerOpacity = 0.22
    // #28: the needs-you queue is quiet rows in ONE glass card. A fixed age gutter
    // keeps every title on the same left edge (list continuity) whatever the age text.
    static let buildNeedsYouGutterWidth: CGFloat = 40
    // #44: keep the first fold small enough to preserve the critical-first read. The
    // rows after it remain reachable in the same glass card, never behind a sheet.
    static let buildNeedsYouVisibleRowLimit = 5
    static let buildReportPlanRowVerticalPadding: CGFloat = 14
    static let buildReportPlanColumnGap: CGFloat = 32
    static let buildReportSegmentMetaGap: CGFloat = 16
    static let buildReportParkedVerticalPadding: CGFloat = 12
    static let buildReportSurfaceSpacing: CGFloat = 16
    static let buildComposerChipGap: CGFloat = 8
    static let buildComposerChipHorizontalPadding: CGFloat = 10
    static let buildComposerChipVerticalPadding: CGFloat = 4
    static let buildComposerChipRadius: CGFloat = 6
    static let buildComposerControlRadius: CGFloat = 10
    static let buildComposerRowSpacing: CGFloat = 8
    // The build composer is mounted below, rather than as a ScrollView safe-area
    // inset. Reserve its resting footprint so the needs-you card's last row can
    // scroll clear of the pinned input controls.
    static let buildComposerContentClearance: CGFloat = 88
    static let buildBranchCardSpacing: CGFloat = 10
    static let buildBranchCardVerticalPadding: CGFloat = 12
    static let buildBranchCardHorizontalPadding: CGFloat = 14
    static let buildBranchTrunkTintOpacity = 0.20
    static let buildBranchCardFillOpacity = 0.02
    static let buildChangelogRowSpacing: CGFloat = 9
    static let buildChatBubbleFillOpacity = 0.06
    static let buildChatYouMaxWidthFactor = 0.75
    static let buildGrowInTranslation: CGFloat = 8
    // W28 thread window and trunk receipt geometry. The surface owns no ad hoc
    // spacing or motion values; these stay in the KStyle token seam.
    static let buildThreadPageSize = 7
    static let buildThreadPageStagger: TimeInterval = 0.04
    static let buildThreadPageOffset: CGFloat = 8
    static let buildThreadReceiptCapHeight: CGFloat = 5
    static let buildThreadReceiptCapOpacity = 0.08
    static let buildThreadReceiptBranchOpacity = 0.16
    static let buildThreadReceiptBodyIndent: CGFloat = 14
    static let buildThreadReceiptLeadingInset: CGFloat = 44
    static let buildThreadQuietActSpacing: CGFloat = 6
    static let buildThreadQuietActRadius: CGFloat = 12
    static let buildThreadProposalRadius: CGFloat = 14
    static let buildThreadProposalPadding: CGFloat = 16
    static let buildThreadProposalArrowInset: CGFloat = -14
    static let buildThreadLongPressDuration: TimeInterval = 0.5
    static let buildThreadSelectedOverhang: CGFloat = 18
    static let buildThreadSelectedPulseScale: CGFloat = 1.02
    static let buildThreadProposalCondenseScale: CGFloat = 0.98
    static let buildThreadStreamMinHeight: CGFloat = 600
    static let buildThreadBreathFrameInterval: TimeInterval = 1.0 / 30.0
    static let compactTextMinimumScaleFactor = 0.78
    static let titleMinimumScaleFactor = 0.70
    static let mindStatementMinimumScaleFactor = 0.70
    static let singleLineLimit = 1
    static let cadenceNowTickInterval: TimeInterval = 60
    static let bandishDetailLongPressDuration: TimeInterval = 0.5
    // Hold-to-complete: a deliberate 2s press fills a ring around the check, so a
    // bandish is never marked done by an accidental tap.
    static let holdToCompleteDuration: TimeInterval = 2.0
    static let holdToCompleteResetDuration: TimeInterval = 0.25
    static let holdToCompleteMaxDistance: CGFloat = 50
    static let holdToCompleteDiameter: CGFloat = 28
    static let holdToCompleteRingWidth: CGFloat = 2
    static let holdToCompleteTrackOpacity: Double = 0.25
    // UI40 gen-UI materialization. Generated blocks enter with a small physical
    // settle; the short cap keeps a long packet list from feeling held hostage by
    // its entrance. Reduce Motion keeps the opacity cue and removes geometry.
    static let genMaterializeHiddenOpacity: Double = 0
    static let genMaterializeVisibleOpacity: Double = 1
    static let genMaterializeInitialOffset: CGFloat = 6
    static let genMaterializeFinalOffset: CGFloat = 0
    static let genMaterializeInitialScale: CGFloat = 0.97
    static let genMaterializeFinalScale: CGFloat = 1
    static let genMaterializeStaggerInterval: TimeInterval = 0.05
    static let genMaterializeMaxStaggerSteps = 6
    static let genMaterializeDuration: TimeInterval = 0.22
    static let genMaterializeReducedMotionDuration: TimeInterval = 0.15
    // A running bandish advances its visible steps without a tap. A missing
    // duration uses the quiet default; a supplied block duration divides evenly
    // across the steps. The minimum keeps malformed or very short fixtures safe.
    static let bandishAutoRunDefaultStepDuration: TimeInterval = 60
    static let bandishAutoRunMinimumStepDuration: TimeInterval = 1
    static let bandishAutoRunStepTransitionDuration: TimeInterval = 0.25
    // Pinch to open a bandish detail: a marked pinch-out expands, pinch-in collapses.
    static let bandishPinchExpandThreshold: CGFloat = 1.25
    static let bandishPinchCollapseThreshold: CGFloat = 0.8
    // Nutrition calendar reveal-depth gesture: pinch-out opens the month, pinch-in
    // returns to the current week.
    static let bioCalendarPinchExpandThreshold: CGFloat = 1.25
    static let bioCalendarPinchCollapseThreshold: CGFloat = 0.8
    // UI15 gesture grammar: the four-touch pager is deliberately more demanding
    // than a content drag, and its page arrival stays small and interruptible.
    static let gesturePageMinimumTouchCount = 4
    static let gesturePageMaximumTouchCount = 4
    static let gesturePageSwipeMinimumDistance: CGFloat = 48
    static let gesturePageAxisDominanceRatio: CGFloat = 1.25
    static let gesturePageTransitionOffset: CGFloat = 24
    static let gesturePageTransitionDuration: TimeInterval = 0.25
    static let cadenceRefreshNanoseconds: UInt64 = 60_000_000_000
    static let zeroProgressRatio = 0.0
    static let sampleProgressRatio = 0.4
    static let fullProgressRatio = 1.0
    static let identityScale: CGFloat = 1
    static let optionButtonPressedScale: CGFloat = 0.97
    static let scrollEdgeFadeHeight: CGFloat = 10
    static let nowTitleTracking: CGFloat = -0.5
    static let mindStatementTracking: CGFloat = -0.5
    static let monoCaptionTracking: CGFloat = 0.2
    static let neutralTracking: CGFloat = 0

    static var contentFont: Font { font(.content) }
    static var nowTitleFont: Font { font(.nowTitle) }
    static var blockActiveTitleFont: Font { font(.blockActiveTitle) }
    static var blockDefaultTitleFont: Font { font(.blockDefaultTitle) }
    static var monoCaptionFont: Font { font(.monoCaption) }
    static var monoCaptionDigitFont: Font { font(.monoCaptionDigit) }
    static var tabFont: Font { font(.tab) }
    static var inputFont: Font { font(.input) }
    static var inputControlFont: Font { font(.inputControl) }
    static var cadenceCompleteCheckIconFont: Font {
        .system(size: cadenceCompleteCheckIconSize, weight: .regular)
    }
    static var optionButtonFont: Font { font(.optionButton) }
    static var verdictFont: Font { font(.verdict) }
    static var evidenceFont: Font { font(.evidence) }
    static var mindStatementFont: Font { font(.mindStatement) }

    static let zenCurveX1 = 0.65
    static let zenCurveY1 = 0.0
    static let zenCurveX2 = 0.35
    static let zenCurveY2 = 1.0
    static let zenDuration = 0.5
    static let easeFastDuration = 0.15
    // Founder-approved chat-v16 motion exceptions. These are deliberate spatial
    // explanations: the same right-stack card grows leftward in place, its
    // history opens its own space, and reordered neighbors retain continuity.
    static let chatExpansionDuration = 0.4
    static let chatStructureDuration = 0.7
    // Thread heads use the mock's 0fr to 1fr detail unfold. Keep its zen timing
    // in the shared motion seam so Reduce Motion resolves centrally.
    static let chatThreadDetailDuration = 0.6
    static let chatHistoryAppendDuration = 0.5
    static let chatContentSwapDuration = 0.3
    static let chatChromeDuration = 0.4
    // chat-v21: selected-thread travel is staged so the founder can keep the
    // trunk origin in mind while the thread takes its place.
    static let chatThreadTrunkFadeDuration: TimeInterval = 0.5
    static let chatThreadGroundDuration: TimeInterval = 0.6
    static let chatThreadMessageDuration: TimeInterval = 0.3
    static let chatThreadComposerDuration: TimeInterval = 0.5
    static let chatThreadTrunkReturnDelay: TimeInterval = 0.55
    static let chatThreadGroundDelay: TimeInterval = 0.5
    static let chatThreadMessageFirstDelay: TimeInterval = 1.05
    static let chatThreadMessageSecondDelay: TimeInterval = 1.2
    static let chatThreadComposerDelay: TimeInterval = 1.3
    // Founder-approved cadence-v7 selector exception: text resolves first, then
    // the active background arrives deliberately. Color-only; no geometry moves.
    static let selectorTextDuration = 0.22
    static let selectorBackgroundDuration = 0.45
    static let selectorBackgroundDelay = 0.13
    // Founder exception: rare active-bandish state flood is a deliberate 0.9s color ramp.
    static let stateFloodDuration = 0.9
    static let optionButtonPressInDuration = 0.10
    // Founder-set Build report motion. These are the binding native `quick`
    // and `zen` names from the app-overhaul mapping, not general UI timings.
    static let nativeQuickDuration = 0.5
    static let nativeZenDuration = 1.0
    static let nativeMotionCurveX1 = 0.25
    static let nativeMotionCurveY1 = 0.1
    static let nativeMotionCurveX2 = 0.25
    static let nativeMotionCurveY2 = 1.0
    // Founder exception: camera reveal is ambience, not state — slow fade avoids a
    // hard flash on launch/permission grant.
    static let cameraFadeDuration = 0.8

    // Doctrine (kedar calm-start): springs forbidden; zen tween cubic-bezier(0.65,0,0.35,1).
    // Founder 2026-07-20 fidelity pass — 82 call sites inherit this token.
    static let ease = Animation.timingCurve(
        zenCurveX1,
        zenCurveY1,
        zenCurveX2,
        zenCurveY2,
        duration: zenDuration
    )
    static let easeFast = Animation.easeOut(duration: easeFastDuration)
    static let stateFlood = Animation.easeOut(duration: stateFloodDuration)
    static let optionButtonPressIn = Animation.easeOut(duration: optionButtonPressInDuration)
    static let cameraFade = Animation.easeOut(duration: cameraFadeDuration)
    static let nearBlack = Color(red: 0.015, green: 0.015, blue: 0.017)
    // Mock --ink #f7f7f5: the near-white emphasis ink. The build segment bar's
    // "building" pill and any pure-emphasis mark ride this, distinct from full white.
    static let emphasisInk = Color(red: 0.969, green: 0.969, blue: 0.961)
    // Floating nav capsule ground: rgba(20,20,20) tinted at navBarGroundOpacity over a blur.
    static let navBarGround = Color(red: 0.078, green: 0.078, blue: 0.078)
    // ultraThin: "glass hazy translucent" — thin frosted the camera to invisibility
    // under the tint (founder validation 2026-07-11).
    static let hazeMaterial = KMaterialToken.ultraThin
    static let inlineError = Color(red: 1.0, green: 0.58, blue: 0.54)
    // Thread result tones — hue lives in the non-text check mark only (KTD-A).
    static let resultClean = Color(red: 0.55, green: 0.78, blue: 0.58)
    // Chat trunk contrast law (mock v35): lead near-full ink, support dim.
    static let chatLeadOpacity: Double = 0.95
    static let chatSupportOpacity: Double = 0.45
    static let resultNotes = Color(red: 0.85, green: 0.74, blue: 0.45)
    static let chatThreadCheckSize: CGFloat = 11
    static let ringCoreToken = KRGBToken(hex: "#212936", red255: 33, green255: 41, blue255: 54)
    static let ringMiddleToken = KRGBToken(hex: "#2d4867", red255: 45, green255: 72, blue255: 103)
    static let ringOuterToken = KRGBToken(hex: "#889a9f", red255: 136, green255: 154, blue255: 159)
    static let ringUnknownToken = KRGBToken(hex: "#ffffff", red255: 255, green255: 255, blue255: 255)
    static let signalWarningToken = KRGBToken(hex: "#fabb00", red255: 250, green255: 187, blue255: 0)
    static let signalFailureToken = KRGBToken(hex: "#e15554", red255: 225, green255: 85, blue255: 84)
    static let ringCore = ringCoreToken.color
    static let ringMiddle = ringMiddleToken.color
    static let ringOuter = ringOuterToken.color
    static let signalWarning = signalWarningToken.color
    static let signalFailure = signalFailureToken.color
    // Fidelity 2026-07-20: sage #6b9d7c per mock, not saturated green (chromatic-accent law)
    static let liveSignal = Color(red: 0.42, green: 0.616, blue: 0.486)
    static let attentionSignal = signalWarning
    static let errorSignal = signalFailure

    static func font(_ token: KFontToken) -> Font {
        var font = Font(scaledUIFont(for: token))
        if token.usesMonospacedDigits {
            font = font.monospacedDigit()
        }
        return font
    }

    static func scaledPointSize(
        for token: KFontToken,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> CGFloat {
        scaledUIFont(for: token, compatibleWith: traitCollection).pointSize
    }

    static func scaledUIFont(
        for token: KFontToken,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: token.basePointSize, weight: token.weight)
        let descriptor = baseFont.fontDescriptor.withDesign(token.design) ?? baseFont.fontDescriptor
        let designedFont = UIFont(descriptor: descriptor, size: token.basePointSize)
        return UIFontMetrics(forTextStyle: token.textStyle).scaledFont(
            for: designedFont,
            compatibleWith: traitCollection
        )
    }

    static func tracking(for token: KFontToken) -> CGFloat {
        switch token {
        case .nowTitle:
            return nowTitleTracking
        case .mindStatement:
            return mindStatementTracking
        case .monoCaption, .monoCaptionDigit, .tab, .evidence:
            return monoCaptionTracking
        case .content, .blockActiveTitle, .blockDefaultTitle, .input, .inputControl, .optionButton, .verdict:
            return neutralTracking
        }
    }

    static func columnWidth(in availableWidth: CGFloat) -> CGFloat {
        min(columnMaxWidth, max(columnMinWidth, availableWidth - columnMargin * 2))
    }

    static var hazeEffectiveDarkness: Double {
        fullOpacity - (fullOpacity - backgroundOpacity) * (fullOpacity - hazeTintOpacity)
    }

    static func hazeResolution(reduceTransparency: Bool) -> KEnvironmentHazeResolution {
        reduceTransparency ? .nearBlack : .haze(material: hazeMaterial, tintOpacity: hazeTintOpacity)
    }

    static func tabStripMetrics(availableWidth: CGFloat) -> KTabStripMetrics {
        if availableWidth <= tabCompactWidthThreshold {
            return KTabStripMetrics(
                itemSpacing: tabCompactItemSpacing,
                horizontalPadding: tabCompactHorizontalPadding,
                labelTracking: tabCompactTracking,
                labelMinimumScaleFactor: tabLabelMinimumScaleFactor
            )
        }
        return KTabStripMetrics(
            itemSpacing: tabItemSpacing,
            horizontalPadding: tabHorizontalPadding,
            labelTracking: tracking(for: .tab),
            labelMinimumScaleFactor: fullOpacity
        )
    }

    static func motionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        // Doctrine: springs forbidden — every kAnimated/withMotion call routes HERE,
        // so the 2026-07-20 de-spring must land here, not only on .ease (census regression).
        reduceMotion ? .none : .timingCurve(
            zenCurveX1,
            zenCurveY1,
            zenCurveX2,
            zenCurveY2,
            duration: zenDuration
        )
    }

    static func opacityMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        .easeOut(duration: easeFastDuration)
    }

    static func cameraFadeMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? opacityMotionResolution(reduceMotion) : .easeOut(duration: cameraFadeDuration)
    }

    static func stateFloodMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? opacityMotionResolution(reduceMotion) : .easeOut(duration: stateFloodDuration)
    }

    static func genMaterializeStaggerDelay(for index: Int) -> TimeInterval {
        Double(min(max(0, index), genMaterializeMaxStaggerSteps)) * genMaterializeStaggerInterval
    }

    static func genMaterializeAnimation(index: Int, reduceMotion: Bool) -> Animation {
        let base = reduceMotion
            ? Animation.easeOut(duration: genMaterializeReducedMotionDuration)
            : Animation.timingCurve(
                zenCurveX1,
                zenCurveY1,
                zenCurveX2,
                zenCurveY2,
                duration: genMaterializeDuration
            )
        return reduceMotion ? base : base.delay(genMaterializeStaggerDelay(for: index))
    }

    static func bandishAutoRunStepMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? .easeOut(duration: easeFastDuration)
            : .timingCurve(
                zenCurveX1,
                zenCurveY1,
                zenCurveX2,
                zenCurveY2,
                duration: bandishAutoRunStepTransitionDuration
            )
    }

    static func bandishAutoRunStepMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: bandishAutoRunStepMotionResolution(reduceMotion)) ?? easeFast
    }

    static func holdToCompleteMotion(
        pressing: Bool,
        reduceMotion: Bool
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return pressing
            ? .linear(duration: holdToCompleteDuration)
            : .easeOut(duration: holdToCompleteResetDuration)
    }

    static func nativeMotionResolution(
        _ name: KNativeMotionName,
        reduceMotion: Bool
    ) -> KMotionResolution {
        guard !reduceMotion else { return .none }
        let duration = name == .quick ? nativeQuickDuration : nativeZenDuration
        return .timingCurve(
            nativeMotionCurveX1,
            nativeMotionCurveY1,
            nativeMotionCurveX2,
            nativeMotionCurveY2,
            duration: duration
        )
    }

    static func selectorTextMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? opacityMotionResolution(reduceMotion)
            : .timingCurve(
                zenCurveX1,
                zenCurveY1,
                zenCurveX2,
                zenCurveY2,
                duration: selectorTextDuration
            )
    }

    static func selectorBackgroundMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? opacityMotionResolution(reduceMotion)
            : .timingCurve(
                zenCurveX1,
                zenCurveY1,
                zenCurveX2,
                zenCurveY2,
                duration: selectorBackgroundDuration
            )
    }

    static func chatExpansionMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? .none : zenTimingCurve(duration: chatExpansionDuration)
    }

    static func chatStructureMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? .none : zenTimingCurve(duration: chatStructureDuration)
    }

    static func chatThreadDetailMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? .none : zenTimingCurve(duration: chatThreadDetailDuration)
    }

    static func chatHistoryAppendMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? .none : zenTimingCurve(duration: chatHistoryAppendDuration)
    }

    static func chatContentSwapMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? opacityMotionResolution(reduceMotion) : zenTimingCurve(duration: chatContentSwapDuration)
    }

    static func chatChromeMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? opacityMotionResolution(reduceMotion) : zenTimingCurve(duration: chatChromeDuration)
    }

    static func chatThreadSwapMotion(
        _ reduceMotion: Bool,
        phase: ChatThreadSwapPhase
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let duration = chatThreadSwapDuration(for: phase)
        let delay = chatThreadSwapDelay(for: phase)
        return animation(for: zenTimingCurve(duration: duration))?.delay(delay)
    }

    static func chatThreadSwapSettledMotion(
        _ reduceMotion: Bool,
        phase: ChatThreadSwapPhase
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        return animation(for: zenTimingCurve(duration: chatThreadSwapDuration(for: phase)))
    }

    private static func chatThreadSwapDuration(for phase: ChatThreadSwapPhase) -> TimeInterval {
        switch phase {
        case .trunkExit:
            return chatThreadTrunkFadeDuration
        case .threadEnter:
            return chatThreadGroundDuration
        case .messageFirst:
            return chatThreadMessageDuration
        case .messageSecond:
            return chatThreadMessageDuration
        case .composerEnter:
            return chatThreadComposerDuration
        case .trunkReturn:
            return chatThreadTrunkFadeDuration
        }
    }

    private static func chatThreadSwapDelay(for phase: ChatThreadSwapPhase) -> TimeInterval {
        switch phase {
        case .trunkExit:
            return .zero
        case .threadEnter:
            return chatThreadGroundDelay
        case .messageFirst:
            return chatThreadMessageFirstDelay
        case .messageSecond:
            return chatThreadMessageSecondDelay
        case .composerEnter:
            return chatThreadComposerDelay
        case .trunkReturn:
            return chatThreadTrunkReturnDelay
        }
    }

    static func contextRingExpansionMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? opacityMotionResolution(reduceMotion)
            : zenTimingCurve(duration: contextRingExpansionDuration)
    }

    static func contextRingFillMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? opacityMotionResolution(reduceMotion)
            : zenTimingCurve(duration: contextRingFillDuration)
    }

    static func notifUnfurlMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? .easeOut(duration: notifReducedMotionDuration)
            : zenTimingCurve(duration: notifUnfurlDuration)
    }

    static func notifUnfurlMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: notifUnfurlMotionResolution(reduceMotion)) ?? easeFast
    }

    static func navStatusDotPulseOpacity(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return navStatusDotOpacity }
        return breathOpacity(
            at: date,
            period: navStatusDotPeriod,
            minimumOpacity: navStatusDotMinimumOpacity,
            maximumOpacity: navStatusDotOpacity
        )
    }

    /// Compatibility name for the notifications primitive. Both paths resolve
    /// through the same root-nav cadence-dot token set.
    static func notifPulseOpacity(at date: Date, reduceMotion: Bool) -> Double {
        navStatusDotPulseOpacity(at: date, reduceMotion: reduceMotion)
    }

    static func gesturePageTransitionMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion
            ? opacityMotionResolution(reduceMotion)
            : zenTimingCurve(duration: gesturePageTransitionDuration)
    }

    static func microRevealMotionResolution(_ reduceMotion: Bool) -> KMotionResolution {
        reduceMotion ? .none : zenTimingCurve(duration: microRevealDuration)
    }

    static func motion(_ reduceMotion: Bool) -> Animation? {
        animation(for: motionResolution(reduceMotion))
    }

    static func opacityMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: opacityMotionResolution(reduceMotion)) ?? easeFast
    }

    static func cameraFadeMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: cameraFadeMotionResolution(reduceMotion)) ?? easeFast
    }

    static func stateFloodMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: stateFloodMotionResolution(reduceMotion)) ?? easeFast
    }

    static func nativeMotion(_ name: KNativeMotionName, reduceMotion: Bool) -> Animation? {
        animation(for: nativeMotionResolution(name, reduceMotion: reduceMotion))
    }

    static func selectorTextMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: selectorTextMotionResolution(reduceMotion)) ?? easeFast
    }

    static func selectorBackgroundMotion(_ reduceMotion: Bool) -> Animation {
        let base = animation(for: selectorBackgroundMotionResolution(reduceMotion)) ?? easeFast
        return reduceMotion ? base : base.delay(selectorBackgroundDelay)
    }

    static func chatExpansionMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: chatExpansionMotionResolution(reduceMotion))
    }

    static func chatStructureMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: chatStructureMotionResolution(reduceMotion))
    }

    static func chatThreadDetailMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: chatThreadDetailMotionResolution(reduceMotion))
    }

    static func chatHistoryAppendMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: chatHistoryAppendMotionResolution(reduceMotion))
    }

    static func chatContentSwapMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: chatContentSwapMotionResolution(reduceMotion)) ?? easeFast
    }

    static func chatChromeMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: chatChromeMotionResolution(reduceMotion)) ?? easeFast
    }

    static func contextRingExpansionMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: contextRingExpansionMotionResolution(reduceMotion)) ?? easeFast
    }

    static func contextRingFillMotion(_ reduceMotion: Bool) -> Animation {
        animation(for: contextRingFillMotionResolution(reduceMotion)) ?? easeFast
    }

    static func termDefinitionMotion(_ reduceMotion: Bool) -> Animation? {
        chatExpansionMotion(reduceMotion)
    }

    static func gesturePageTransitionMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: gesturePageTransitionMotionResolution(reduceMotion))
    }

    static func microRevealMotion(_ reduceMotion: Bool) -> Animation? {
        animation(for: microRevealMotionResolution(reduceMotion))
    }

    static func breathOpacity(
        at date: Date,
        period: TimeInterval,
        minimumOpacity: Double,
        maximumOpacity: Double = fullOpacity
    ) -> Double {
        guard period > .zero else { return maximumOpacity }
        let unit = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        let wave = (sin(unit * 2 * .pi - .pi / 2) + 1) / 2
        return minimumOpacity + (maximumOpacity - minimumOpacity) * wave
    }

    static func withMotion<Result>(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        _ updates: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(motion(reduceMotion), updates)
    }

    /// State changes that travel between a resting origin and an elevated detail
    /// use the gesture-page family so the spatial continuity motion is consistent
    /// across cadence, build, and dossier elevations.
    static func withGesturePageMotion<Result>(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        _ updates: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(gesturePageTransitionMotion(reduceMotion), updates)
    }

    private static func animation(for resolution: KMotionResolution) -> Animation? {
        switch resolution {
        case .timingCurve(let x1, let y1, let x2, let y2, let duration):
            return .timingCurve(x1, y1, x2, y2, duration: duration)
        case .easeOut(let duration):
            return .easeOut(duration: duration)
        case .none:
            return nil
        }
    }

    private static func zenTimingCurve(duration: Double) -> KMotionResolution {
        .timingCurve(
            zenCurveX1,
            zenCurveY1,
            zenCurveX2,
            zenCurveY2,
            duration: duration
        )
    }
}

enum KCopy {
    // Build card voice is deliberately centralized. The daemon keeps its machine kinds
    // and titles; the founder sees one short, lower-case line. Keep this table exhaustive
    // against the known build-card kinds so a new runner kind cannot leak raw copy.
    // Founder register 2026-08-09: name the DECISION in plain words — no repo
    // nouns (diff, gate, scope), no state labels. Matches the blessed
    // decision-row voice ("choose review depth · awaiting").
    static let buildCardVoiceByKind: [String: String] = [
        "plan-approval": "start this plan?",
        "safety-floor": "a protected rule changes — your call",
        "drift": "built more than planned — allow?",
        "line-stop": "checks failed — what now?",
        "bound": "out of retries — what now?",
        "infra": "stuck on setup — what now?",
        "fork": "two ways forward — pick one",
        "shaping": "a question before building",
        "review-finding": "review found something — apply?",
    ]

    static var buildCardKinds: [String] {
        buildCardVoiceByKind.keys.sorted()
    }

    /// The only founder-facing voice for a build decision kind. Kind tokens stay in
    /// the payload and are used only to select this blessed line.
    static func buildCardVoice(kind: String?) -> String {
        guard let normalizedKind = normalizedBuildKind(kind),
              let voice = buildCardVoiceByKind[normalizedKind]
        else {
            return "a build decision"
        }
        return voice
    }

    static func buildApproveAllKindLine(count: Int, kind: String?) -> String {
        "\(count) × \(buildCardVoice(kind: kind))"
    }

    static func buildCardTitle(kind: String?, rawTitle: String) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let normalizedKind = kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        // Specific runner phrases win over the broader kind fallback. These are the
        // phrases that used to make the card feel like an internal status console.
        if normalizedTitle.contains("runner core") && normalizedTitle.contains("hand harvest") {
            return "needs a hand finish — yours or mine"
        }
        if normalizedTitle.contains("retry limit reached") {
            return buildCardVoice(kind: "bound")
        }
        if normalizedTitle.contains("verification gate failed") {
            return buildCardVoice(kind: "line-stop")
        }
        if normalizedTitle.contains("safety floor") {
            return buildCardVoice(kind: "safety-floor")
        }
        if normalizedTitle.contains("held unit needs a decision") {
            return buildCardVoice(kind: "infra")
        }
        if normalizedTitle.contains("plan approval") {
            return buildCardVoice(kind: "plan-approval")
        }

        if let normalizedKind, let mapped = buildCardVoiceByKind[normalizedKind] {
            return mapped
        }
        if Self.looksLikePayloadIdentifier(title) {
            return "a build decision"
        }
        return title.isEmpty ? "build decision" : title.lowercased()
    }

    static func buildCardSeverityRank(for kind: String?) -> Int {
        switch kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-") {
        case "safety-floor": return 0
        case "line-stop": return 1
        case "plan-approval": return 2
        case "review-finding": return 3
        case "infra": return 4
        case "bound": return 5
        case "drift": return 6
        case "fork": return 7
        case "shaping": return 8
        default: return Int.max
        }
    }

    static func buildNeedsYouQuieter(_ count: Int) -> String {
        "+\(count) quieter"
    }

    static let buildApproveAllAct = "accept all · k's lean"
    static let buildApproveAllConfirm = "accept all"
    static let buildApproveAllCancel = "cancel"
    static let buildApproveAllAnswerText = "founder: approve-all (k's lean) from device"

    static func buildCardKindLabel(kind: String?) -> String {
        buildCardVoice(kind: kind)
    }

    private static func normalizedBuildKind(_ kind: String?) -> String? {
        let value = kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return value?.isEmpty == false ? value : nil
    }

    private static func looksLikePayloadIdentifier(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if ["plan-", "plan/", "plan ", "unit-", "lane-", "card-", "build-card-"].contains(where: { normalized.hasPrefix($0) }) {
            return true
        }
        return normalized.range(of: #"^(u|unit|lane|plan)[0-9]+$"#, options: .regularExpression) != nil
    }

    static func buildApproveAllProgress(
        answered: Int,
        total: Int,
        skipped: Int,
        failed: Int
    ) -> String {
        var parts = ["\(answered)/\(total) accepted", "applying k's lean"]
        if skipped > 0 { parts.append("\(skipped) waiting their turn") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    static func buildApproveAllResult(answered: Int, skipped: Int, failed: Int) -> String {
        var parts = ["\(answered) accepted"]
        if skipped > 0 { parts.append("\(skipped) waiting their turn") }
        if failed > 0 { parts.append("\(failed) failed · retry") }
        return parts.joined(separator: " · ")
    }

    static let notificationsEmpty = "nothing needs you"
    static let notificationsUnavailable = "notifications unavailable · retry"
    static let connecting = "connecting…"
    static let live = "live"
    static let reconnecting = "reconnecting…"
    static let offlineRetrying = "offline · retrying"
    static let tailnetNeeded = "daemon unreachable · tailnet needed"
    static let cameraPrePermission = "k renders over your camera. the feed never leaves this device."
    static let cameraDenied = "camera denied · enable it in settings"
    static let drafting = "drafting…"
    static let answerPending = "answer pending"
    static let snapshotSynced = "snapshot synced"
    static let liveBuildUpdate = "live build update"
    static let buildUpdatePatched = "build update patched"
    static let stopped = "stopped"
    static let queuedWillSync = "queued · will sync"
    static let mealPhotoReading = "reading the plate…"
    static let buildIntentPlaceholder = "describe what k should build…"
    static let buildIntentAcknowledgment = "staged for shaping — a card follows"
    static let chatThinking = "thinking…"
    static let chatReadyToExplore = "ready to explore"
    static let chatBranchThis = "branch this"
    static let chatBranched = "branched · open on the right"
    static let chatThreadsHeading = "threads"
    static let chatArchiveHeading = "archive"
    static let chatBuildIt = "build it"
    static let chatBuildStaging = "staging behind your gate…"
    static let chatBuildStaged = "staged to build · waiting on your yes"
    static let chatBuildGateExplanation = "stages a build card · nothing runs until you approve it"
    static let chatLater = "later · thread stays open"
    static let chatResolved = "resolved"
    static let chatArchived = "archived"
    static let chatArchiveConfirm = "sure?"
    static let chatTrunkTarget = "trunk"
    static let chatNoRefs = "no refs for the next turn"
    static let chatNoSenses = "no live senses for the next turn"
    static let chatNoSelfReceipt = "no self receipt for the next turn"
    static let chatAttachmentLocalOnly = "selected locally · not sent to k"
    static let chatAttach = "attach"
    static let chatTrunkPlaceholder = "ask k · feeds the trunk"
    static let chatThreadPlaceholder = "reply in this thread"
    static let chatBranching = "branching…"
    static let chatClosedChooseTrunk = "thread closed · choose the trunk"
    static let chatContextNextTurn = "context for the next turn"
    static let chatContextCollapseHint = "collapse context"
    static let chatContextShowHint = "show target, refs, senses, and self"
    static let chatContextRingLabel = "context fill"
    static let chatContextRingShowHint = "tap for the breakup, or pinch out to reveal it"
    static let chatContextRingCollapseHint = "collapse the context breakup"
    static let chatContextRingNearFull = "near full"
    static let chatDropQueuedReply = "drop queued reply"
    static let chatResolve = "resolve"
    static let chatCollapse = "collapse thread"
    static let chatMessageK = "message k"
    static let termFirstSeen = "first seen"
    static let termShowDefinition = "show definition"
    static let termCollapseDefinition = "collapse definition"
    static let termPinchHint = "pinch out to reveal definition"
    static let chatDictationHint = "type or use the keyboard microphone to dictate"
    static let chatSend = "send"
    static let chatStop = "stop"
    static let chatExpandThreadHint = "expand thread in place"
    static let chatExpandedThreadHint = "use collapse to close this thread"
    static let chatResolving = "resolving…"
    static let chatArchiving = "archiving…"

    static func chatContextRingBreakupTitle(_ percent: String) -> String {
        "context ring \(percent) full · the breakup:"
    }

    static func chatAttachmentSelected(_ filename: String) -> String {
        "selected · \(filename.lowercased())"
    }

    static func chatAttachmentFailed(reason: String) -> String {
        "file selection failed · \(reason.lowercased())"
    }

    static func chatThreadFailed(reason: String) -> String {
        "thread failed · \(reason.lowercased())"
    }

    static func answerFailed(reason: String) -> String {
        "answer failed · retry"
    }

    static func answeredEarlier(surface: String) -> String {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "another surface" : trimmed.lowercased()
        return "answered earlier from \(value) · kept that answer"
    }
}

enum KTimestampFormatter {
    static func hourMinute(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date).lowercased()
    }

    static func asOf(_ date: Date, timeZone: TimeZone = .current) -> String {
        "as of \(hourMinute(date, timeZone: timeZone))"
    }
}

extension View {
    func kAnimated<Value: Equatable>(value: Value, isEnabled: Bool = true) -> some View {
        modifier(KMotionAnimationModifier(value: value, isEnabled: isEnabled))
    }

    func kOpacityAnimated<Value: Equatable>(value: Value, isEnabled: Bool = true) -> some View {
        modifier(KOpacityAnimationModifier(value: value, isEnabled: isEnabled))
    }

    func kContentText(_ opacity: Double = KStyle.primaryTextOpacity) -> some View {
        foregroundStyle(.white.opacity(opacity))
    }

    func kMetaText(_ opacity: Double = KStyle.tertiaryTextOpacity) -> some View {
        kFont(.monoCaption)
            .foregroundStyle(.white.opacity(opacity))
    }

    func kFont(_ token: KFontToken) -> some View {
        font(KStyle.font(token))
            .tracking(KStyle.tracking(for: token))
    }

    func kNowTitleText() -> some View {
        kFont(.nowTitle)
    }

    func kMindStatementText() -> some View {
        kFont(.mindStatement)
    }

    func kTapTarget() -> some View {
        frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
            .contentShape(Rectangle())
    }

    func kGlassFill(opacity: Double = KStyle.glassOpacity) -> some View {
        background(
            Color.black.opacity(opacity),
            in: RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
        )
    }

    func kHairline(_ opacity: Double = KStyle.hairlineOpacity) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                .stroke(.white.opacity(opacity), lineWidth: KStyle.hairlineWidth)
        }
    }

    func kSensoryFeedback(_ triggers: KFeedbackTriggers) -> some View {
        self
            .sensoryFeedback(.impact(weight: .light), trigger: triggers.impactLightCount)
            .sensoryFeedback(.selection, trigger: triggers.selectionCount)
            .sensoryFeedback(.error, trigger: triggers.errorCount)
    }

    func kNavigationTone() -> some View {
        modifier(KNavigationToneModifier())
    }

    // NavigationStack's UIKit host paints opaque systemBackground; on the
    // one-haze-layer rule the environment must show through instead.
    // iOS 18 API; earlier systems keep the host background (devices run 26).
    @ViewBuilder
    func kClearNavigationContainer() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(Color.clear, for: .navigation)
        } else {
            self
        }
    }

    func kEnvironmentHazeBackdrop(ignoresSafeAreaEdges: Edge.Set? = nil) -> some View {
        modifier(KEnvironmentHazeBackdropModifier(ignoresSafeAreaEdges: ignoresSafeAreaEdges))
    }

}

struct KScrollEdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(.zero), location: .zero),
                .init(color: Color.white.opacity(KStyle.scrollEdgeFadeOpacity), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: KStyle.scrollEdgeFadeHeight)
        .accessibilityHidden(true)
    }
}

private struct KNavigationToneModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .toolbarBackground(KStyle.nearBlack, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}

private struct KEnvironmentHazeBackdropModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let ignoresSafeAreaEdges: Edge.Set?

    func body(content: Content) -> some View {
        content
            .background {
                if let ignoresSafeAreaEdges {
                    backdrop
                        .ignoresSafeArea(edges: ignoresSafeAreaEdges)
                } else {
                    backdrop
                }
            }
    }

    @ViewBuilder
    private var backdrop: some View {
        switch KStyle.hazeResolution(reduceTransparency: reduceTransparency) {
        case .nearBlack:
            Rectangle()
                .fill(KStyle.nearBlack)
        case .haze(let material, let tintOpacity):
            Rectangle()
                .fill(Color.black.opacity(tintOpacity))
                .background(material.material)
        }
    }
}

private struct KMotionAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.animation(isEnabled ? KStyle.motion(reduceMotion) : nil, value: value)
    }
}

private struct KOpacityAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.animation(isEnabled ? KStyle.opacityMotion(reduceMotion) : nil, value: value)
    }
}
