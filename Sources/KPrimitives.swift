import SwiftUI
import UIKit

enum KPrimitiveInteractionState: String, CaseIterable, Equatable {
    case resting = "default"
    case active
    case disabled
    case loading
    case error
    case offline
    case empty
    case stale

    var disablesInput: Bool {
        self == .disabled || self == .offline
    }

    var disablesAction: Bool {
        self == .disabled || self == .loading || self == .offline
    }

    var contentOpacity: Double {
        switch self {
        case .resting, .active, .error:
            return KStyle.fullOpacity
        case .loading, .offline:
            return KStyle.secondaryTextOpacity
        case .disabled:
            return KStyle.quaternaryTextOpacity
        case .empty, .stale:
            return KStyle.secondaryTextOpacity
        }
    }

    var quietTextOpacity: Double {
        switch self {
        case .active:
            return KStyle.secondaryTextOpacity
        case .disabled:
            return KStyle.quaternaryTextOpacity
        case .loading, .offline:
            return KStyle.tertiaryTextOpacity
        case .resting, .error:
            return KStyle.tertiaryTextOpacity
        case .empty, .stale:
            return KStyle.tertiaryTextOpacity
        }
    }
}

/// Audit-only fetch seam. The walk rig asks every surface to hold its first-fetch
/// state without contacting a daemon, so loading captures are deterministic.
enum KLoadingPreview {
    static let launchArgument = "-ui34-loading"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func hasFlag(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func value(for argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum KSignal: String, CaseIterable, Equatable {
    case idle
    case live
    case attention
    case error
    case offline

    var color: Color {
        switch self {
        case .idle:
            return Color.white.opacity(KStyle.tertiaryTextOpacity)
        case .live:
            return KStyle.liveSignal
        case .attention:
            return KStyle.attentionSignal
        case .error, .offline:
            return KStyle.errorSignal
        }
    }
}

enum KStatusDotSize: Equatable {
    case small
    case regular
    case large

    var dimension: CGFloat {
        switch self {
        case .small:
            return KStyle.blockDotSmallSize
        case .regular:
            return KStyle.blockDotRegularSize
        case .large:
            return KStyle.blockDotRegularSize
        }
    }
}

enum KBlockRowVariant: String, CaseIterable, Equatable {
    case current
    case upcoming
    case elapsed
}

enum KBlockRowSurfaceTone: String, CaseIterable, Equatable {
    case darkGlass = "dark-glass"
    case lightGlass = "light-glass"
}

enum KBlockActionState: String, CaseIterable, Equatable {
    case available
    case started
    case completed
}

enum KBlockRowFillBase: Equatable {
    case light
    case active
}

struct KBlockRowStyleResolution: Equatable {
    var cardFillBase: KBlockRowFillBase
    var textBase: KOptionButtonStyleColorBase

    static func resolve(
        surfaceTone: KBlockRowSurfaceTone,
        variant: KBlockRowVariant,
        actionState: KBlockActionState
    ) -> KBlockRowStyleResolution {
        let isCurrentCard = variant == .current
        let isStartedCurrentCard = isCurrentCard && actionState == .started
        let usesDarkText = !isStartedCurrentCard && (isCurrentCard || surfaceTone == .lightGlass)

        return KBlockRowStyleResolution(
            cardFillBase: isStartedCurrentCard ? .active : .light,
            textBase: usesDarkText ? .nearBlack : .light
        )
    }

    func cardFillColor(activeFillColor: Color?, resolvedDotColor: Color) -> Color {
        switch cardFillBase {
        case .active:
            return activeFillColor ?? resolvedDotColor
        case .light:
            return .white
        }
    }

    var textBaseColor: Color {
        textBase.color
    }
}

struct KBlockTimeGutter: Equatable, Sendable {
    var startText: String
    var durationText: String?
    var struckStartText: String?
    var struckDurationText: String?

    init(
        startText: String,
        durationText: String? = nil,
        struckStartText: String? = nil,
        struckDurationText: String? = nil
    ) {
        self.startText = startText
        self.durationText = Self.normalized(durationText)
        self.struckStartText = Self.normalized(struckStartText)
        self.struckDurationText = Self.normalized(struckDurationText)
    }

    init(timeText: String) {
        let lines = timeText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        startText = lines.first ?? timeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        durationText = lines.dropFirst().first
        struckStartText = nil
        struckDurationText = nil
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

enum KCardTone: String, CaseIterable, Equatable {
    case paper
    case glass
}

enum KActRowVariant: String, CaseIterable, Equatable {
    case cadence
    case admin
    case build
    case mindFeedback = "mind-feedback"
}

enum KOptionButtonVariant: String, CaseIterable, Equatable {
    case primaryFilled = "primary-filled"
    case quietHairline = "quiet-hairline"
    case secondaryHairline = "secondary-hairline"
    case archiveNaked = "archive-naked"
}

enum KMonoCaptionVariant: String, CaseIterable, Equatable {
    case status
    case staleness
    case footer
    case metadata
    case inlineError = "inline-error"
}

enum KLoadingVariant: String, CaseIterable, Equatable {
    case skeleton
    case dot
}

enum KInputBarMode: String, CaseIterable, Equatable {
    case chat
    case admin
    case build

    var maxLineCount: Int {
        switch self {
        case .chat, .admin:
            return KStyle.inputDefaultMaxLineCount
        case .build:
            return KStyle.inputBuildMaxLineCount
        }
    }

    var inputAccessibilityLabel: String {
        switch self {
        case .chat:
            return "ask k"
        case .admin:
            return "admin intake"
        case .build:
            return "what should k build?"
        }
    }

    var submitAccessibilityLabel: String {
        switch self {
        case .chat:
            return "send"
        case .admin:
            return "parse admin intake"
        case .build:
            return "submit build intent"
        }
    }
}

enum KStreamRowRole: String, CaseIterable, Equatable {
    case founder
    case k
    case runner
    case system

    var horizontalAlignment: HorizontalAlignment {
        self == .founder ? .trailing : .leading
    }

    var textAlignment: TextAlignment {
        self == .founder ? .trailing : .leading
    }

    var frameAlignment: Alignment {
        self == .founder ? .trailing : .leading
    }

    var keepsLeadingGutter: Bool {
        self == .founder
    }
}

enum KProgressStripVariant: String, CaseIterable, Equatable {
    case buildMission = "build-mission"
}

enum KEvidenceBlockVariant: String, CaseIterable, Equatable {
    case mono
    case gateOutput = "gate-output"
    case diff
    case logTail = "log-tail"
}

struct KActItem: Identifiable, Equatable {
    let id: String
    let label: String
    let isEnabled: Bool
    let accessibilityIdentifier: String?

    init(
        id: String,
        label: String? = nil,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil
    ) {
        self.id = id
        self.label = label ?? id
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

struct KSensesRailGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let lines: [String]

    init(id: String, title: String, source: String, lines: [String]) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.lines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

struct KPrimitivePropDescriptor: Equatable {
    let name: String
    let type: String
    let required: Bool
}

enum KPrimitiveInterruptionClass: String, Equatable {
    case ambient
    case peripheral
    case focal
}

struct KPrimitiveCalmTech: Equatable {
    let interruptionClass: KPrimitiveInterruptionClass
    let maxSimultaneousCues: Int?
}

struct KPrimitiveComponentDescriptor: Equatable {
    let name: String
    let semanticRole: String
    let props: [KPrimitivePropDescriptor]
    let variants: [String]
    let interactionStates: [String]
    let usageWhen: [String]
    let usageNever: [String]
    let calmTech: KPrimitiveCalmTech
    let usesTokenOnlyStyling: Bool
    let isDeprecated: Bool

    init(
        name: String,
        semanticRole: String,
        props: [KPrimitivePropDescriptor],
        variants: [String],
        interactionStates: [String],
        usageWhen: [String],
        usageNever: [String],
        calmTech: KPrimitiveCalmTech,
        usesTokenOnlyStyling: Bool,
        isDeprecated: Bool = false
    ) {
        self.name = name
        self.semanticRole = semanticRole
        self.props = props
        self.variants = variants
        self.interactionStates = interactionStates
        self.usageWhen = usageWhen
        self.usageNever = usageNever
        self.calmTech = calmTech
        self.usesTokenOnlyStyling = usesTokenOnlyStyling
        self.isDeprecated = isDeprecated
    }
}

protocol KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor { get }
}

private enum KDeprecatedPrimitiveDescriptors {
    static let blockRow = KPrimitiveDescriptors.component(
        name: "KBlockRow",
        semanticRole: "deprecated BandishCard re-copy retained as catalog history only",
        props: [
            KPrimitiveDescriptors.prop("timeText", "String"),
            KPrimitiveDescriptors.prop("signal", "KSignal"),
            KPrimitiveDescriptors.prop("title", "String"),
            KPrimitiveDescriptors.prop("detail", "String?", required: false),
            KPrimitiveDescriptors.prop("why", "String?", required: false),
            KPrimitiveDescriptors.prop("typeLabel", "String?", required: false),
            KPrimitiveDescriptors.prop("titleSuffix", "String?", required: false),
            KPrimitiveDescriptors.prop("badge", "String?", required: false),
            KPrimitiveDescriptors.prop("content", "BlockContent?", required: false),
            KPrimitiveDescriptors.prop("timeGutter", "KBlockTimeGutter?", required: false),
            KPrimitiveDescriptors.prop("dotColor", "Color?", required: false),
            KPrimitiveDescriptors.prop("activeFillColor", "Color?", required: false),
            KPrimitiveDescriptors.prop("surfaceTone", "KBlockRowSurfaceTone", required: false),
            KPrimitiveDescriptors.prop("variant", "KBlockRowVariant", required: false),
            KPrimitiveDescriptors.prop("actionState", "KBlockActionState", required: false),
            KPrimitiveDescriptors.prop("elapsedText", "String?", required: false),
            KPrimitiveDescriptors.prop("progressRatio", "Double?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onStart", "(() -> Void)?", required: false),
            KPrimitiveDescriptors.prop("onComplete", "(() -> Void)?", required: false),
            KPrimitiveDescriptors.prop("onResume", "(() -> Void)?", required: false),
            KPrimitiveDescriptors.prop("onTap", "(() -> Void)?", required: false),
            KPrimitiveDescriptors.prop("accessibilityIdentifier", "String?", required: false),
            KPrimitiveDescriptors.prop("accessory", "View", required: false),
            KPrimitiveDescriptors.prop("footer", "View", required: false),
        ],
        variants: KBlockRowVariant.allCases.map(\.rawValue),
        usageWhen: [
            "deprecated: use BandishCard for cadence and build timeline rows",
        ],
        usageNever: [
            "never instantiate in product or showcase code",
            "never extend this descriptor with new behavior",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 2,
        isDeprecated: true
    )

    static let nowPanel = KPrimitiveDescriptors.component(
        name: "KNowPanel",
        semanticRole: "deprecated duplicate of the current BandishCard state retained as catalog history only",
        props: [
            KPrimitiveDescriptors.prop("eyebrow", "String", required: false),
            KPrimitiveDescriptors.prop("title", "String"),
            KPrimitiveDescriptors.prop("why", "String?", required: false),
            KPrimitiveDescriptors.prop("meta", "String?", required: false),
            KPrimitiveDescriptors.prop("detail", "String?", required: false),
            KPrimitiveDescriptors.prop("content", "BlockContent?", required: false),
            KPrimitiveDescriptors.prop("nextTimeText", "String?", required: false),
            KPrimitiveDescriptors.prop("nextTitleText", "String?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onTap", "(() -> Void)?", required: false),
            KPrimitiveDescriptors.prop("actions", "View"),
        ],
        variants: ["instrument"],
        interactionStates: KPrimitiveDescriptors.cadenceInstrumentStates,
        usageWhen: [
            "deprecated: use the current BandishCard lifecycle state",
        ],
        usageNever: [
            "never instantiate in product or showcase code",
            "never extend this descriptor with new behavior",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1,
        isDeprecated: true
    )
}

enum KPrimitiveRegistry {
    static let id = "k-catalog"
    static let version = "1.15.3"
    static let comment = "Evolution is additive-only: never delete or repurpose components, props, variants, interaction states, or calm-tech fields; add new names and deprecate old names with replacement notes. Motion note 1.7.0: KStyle.ease is the founder-blessed zen timing curve; springs are forbidden; reduced motion removes movement animations while retaining opacity feedback through easeFast. Typography and haptics note 1.8.0: KStyle font tokens scale through UIFontMetrics with size-specific tracking, and semantic commit events route to sensory feedback triggers. Cadence note 1.9.2: KBlockRow owns the active-bandish lifecycle stream, KNowPanel is deprecated for cadence, signal/ring colors resolve through KStyle tokens, and non-current cadence rows plus sidebar stats sit directly on the environment haze. Provenance catalog note 1.10.0: A2UIPanel/ProvenanceCard/EvidenceRow/ConfidenceBadge/ClaimStatus/ChangeActionBar are the shared k0.provenance/claim/change/eval_score/evolve_report + loop.evidence composition (design-system plan 003 U5); confidence/status resolve through KSignal only, never a new hue. Control-taxonomy note 1.11.0: founder-blessed mind-v18, bio-v11, cadence-v7, and chat-v16 establish uppercase inset-track selectors, a circular 44pt input control, the filled-primary/hairline-secondary/naked-archive verdict register, quiet borderless acts, and the named cadence selector color sequence; KBlockRow and KNowPanel are descriptor-only deprecations replaced by BandishCard. Chat-v16 motion note 1.11.1: named zen-curve tokens own in-place expansion, stack continuity, append-only history, thinking-to-answer crossfade, and chrome reveal; status dots breathe opacity only. Nav note 1.12.0: KNavBar is the additive floating root nav — circle-family icon capsule, bottom bar on compact width and right side rail on regular width, selection is an ink-bright glyph plus a hairline ring and never a fill; KTabStrip remains the inset-track text selector. Chat grammar note 1.13.0: KChatVerbDrawer and KChatActionRow are the chat-v33 grammar surface — the verb drawer keeps its receipt inside and the three-tier action row is latest-only with ✓-chip demarcation; a chosen action is a command, never an utterance. Selector grammar note 1.14.0: KSelectorStrip is the shared in-panel uppercase inset-track selector for Bio's state and biology/meditation domain bars; wider 44pt targets, a quieter 48pt track, and token-owned motion keep the language singular. Loading grammar note 1.15.0: KLoadingPrimitive is the shared no-shimmer skeleton or quiet loading-dot treatment for every fetch-bound surface; loading never reads as empty or unreachable. Dead-code sweep note 1.15.1: BuildWorkingArea, BuildIntentInput, BuildStreamColumn, BuildReportRail, BuildReportInlineCard, ChatMealQuickEntryRow, ContextBar's view, BioLogEntryRow, and CadenceRestStripModel are deprecated retired names; their coverage entries are removed, while live model/catalog history remains additive. Selector refinement note 1.15.2: KSelectorStrip inherits the bandish mode-pill inset, sibling seam, compact visual height, tighter side padding, and separate 44pt hit floor across Bio and retro consumers. Loading audit-hook note 1.15.3: KLoadingPrimitive additionally exposes its accessibility identifier through an in-tree 1×1 clear marker sibling because grouped-element exposure is context-flaky under XCUI; visual treatment is unchanged."

    static let components: [KPrimitiveComponentDescriptor] = [
        KDeprecatedPrimitiveDescriptors.blockRow,
        KBlockDetail<EmptyView>.primitiveDescriptor,
        KSensesRail.primitiveDescriptor,
        KDeprecatedPrimitiveDescriptors.nowPanel,
        KNextRow.primitiveDescriptor,
        KRestStrip.primitiveDescriptor,
        KCapacityLine.primitiveDescriptor,
        KPaperCard<EmptyView>.primitiveDescriptor,
        KGlassCard<EmptyView>.primitiveDescriptor,
        KColumnPanel<EmptyView>.primitiveDescriptor,
        KActRow.primitiveDescriptor,
        KOptionButton.primitiveDescriptor,
        KMonoCaption.primitiveDescriptor,
        KStatusDot.primitiveDescriptor,
        KLoadingPrimitive.primitiveDescriptor,
        KTabStrip.primitiveDescriptor,
        KSelectorStrip<String>.primitiveDescriptor,
        KNavBar.primitiveDescriptor,
        KStreamRow<EmptyView>.primitiveDescriptor,
        KProgressStrip.primitiveDescriptor,
        KInputBar.primitiveDescriptor,
        KChecklistRow.primitiveDescriptor,
        KVerdictBar.primitiveDescriptor,
        KEvidenceBlock.primitiveDescriptor,
        KSummaryStrip.primitiveDescriptor,
        KChatVerbDrawer.primitiveDescriptor,
        KChatActionRow.primitiveDescriptor,
        A2UIPanel.primitiveDescriptor,
        ProvenanceCard.primitiveDescriptor,
        EvidenceRow.primitiveDescriptor,
        ConfidenceBadge.primitiveDescriptor,
        ClaimStatus.primitiveDescriptor,
        ChangeActionBar.primitiveDescriptor,
    ]
}

private enum KPrimitiveCopy {
    static let middleDot = "·"
    static let inputPlaceholder = "…"
    static let loading = "loading"
    static let empty = "empty"
    static let errorRetry = "error · retry"
}

private enum KPrimitiveDescriptors {
    static let fullStates = [
        KPrimitiveInteractionState.resting.rawValue,
        KPrimitiveInteractionState.active.rawValue,
        KPrimitiveInteractionState.disabled.rawValue,
        KPrimitiveInteractionState.loading.rawValue,
        KPrimitiveInteractionState.error.rawValue,
        KPrimitiveInteractionState.offline.rawValue,
    ]
    static let cadenceInstrumentStates = [
        KPrimitiveInteractionState.resting.rawValue,
        KPrimitiveInteractionState.empty.rawValue,
        KPrimitiveInteractionState.stale.rawValue,
        KPrimitiveInteractionState.offline.rawValue,
    ]
    static let evidenceStates = [
        KPrimitiveInteractionState.resting.rawValue,
        KPrimitiveInteractionState.loading.rawValue,
        KPrimitiveInteractionState.error.rawValue,
        KPrimitiveInteractionState.offline.rawValue,
    ]

    static func prop(_ name: String, _ type: String, required: Bool = true) -> KPrimitivePropDescriptor {
        KPrimitivePropDescriptor(name: name, type: type, required: required)
    }

    static func component(
        name: String,
        semanticRole: String,
        props: [KPrimitivePropDescriptor],
        variants: [String],
        interactionStates: [String] = fullStates,
        usageWhen: [String],
        usageNever: [String],
        interruptionClass: KPrimitiveInterruptionClass,
        maxSimultaneousCues: Int,
        usesTokenOnlyStyling: Bool = true,
        isDeprecated: Bool = false
    ) -> KPrimitiveComponentDescriptor {
        KPrimitiveComponentDescriptor(
            name: name,
            semanticRole: semanticRole,
            props: props,
            variants: variants,
            interactionStates: interactionStates,
            usageWhen: usageWhen,
            usageNever: usageNever,
            calmTech: KPrimitiveCalmTech(
                interruptionClass: interruptionClass,
                maxSimultaneousCues: maxSimultaneousCues
            ),
            usesTokenOnlyStyling: usesTokenOnlyStyling,
            isDeprecated: isDeprecated
        )
    }
}

private struct KCardToneModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tone: KCardTone

    func body(content: Content) -> some View {
        content
            .background {
                backgroundShape
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: KStyle.hairlineWidth)
            }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        let shape = RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(KStyle.nearBlack)
        } else {
            switch tone {
            case .paper:
                shape.fill(Color.white.opacity(KStyle.paperOpacity))
            case .glass:
                shape
                    .fill(Color.black.opacity(KStyle.glassStrongOpacity))
                    .background(.ultraThinMaterial, in: shape)
            }
        }
    }

    private var borderOpacity: Double {
        if reduceTransparency {
            return KStyle.hairlineStrongOpacity
        }
        switch tone {
        case .paper:
            return KStyle.hairlineOpacity
        case .glass:
            return KStyle.hairlineStrongOpacity
        }
    }
}

private struct KInputFieldToneModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? KStyle.nearBlack : Color.white.opacity(KStyle.inputFillOpacity),
                in: RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(KStyle.dividerOpacity), lineWidth: KStyle.hairlineWidth)
            }
    }
}

private struct KColumnPanelToneModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    Rectangle()
                        .fill(KStyle.nearBlack)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(KStyle.panelScrimOpacity))
                        .background(.ultraThinMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(KStyle.hairlineOpacity), lineWidth: KStyle.hairlineWidth)
            }
    }
}

extension View {
    func kPaperCardTone() -> some View {
        modifier(KCardToneModifier(tone: .paper))
    }

    func kGlassCardTone() -> some View {
        modifier(KCardToneModifier(tone: .glass))
    }

    func kInputFieldTone() -> some View {
        modifier(KInputFieldToneModifier())
    }

    func kColumnPanelTone() -> some View {
        modifier(KColumnPanelToneModifier())
    }
}

struct KColumnPanel<Content: View>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KColumnPanel",
            semanticRole: "sanctioned floating column panel tone over the camera layer",
            props: [
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("content", "View"),
            ],
            variants: ["column-panel"],
            usageWhen: [
                "use for genuine floating panels, detail routes, drawers, and sheets",
                "use through kColumnPanelTone only when content needs a separate material layer",
            ],
            usageNever: [
                "never use as the default five-tab root shell",
                "never use inside cards, rows, or packet content",
                "never expose platform material directly at call sites",
            ],
            interruptionClass: .ambient,
            maxSimultaneousCues: 1
        )
    }

    let state: KPrimitiveInteractionState
    let content: Content

    init(
        state: KPrimitiveInteractionState = .resting,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .kColumnPanelTone()
            .opacity(state.contentOpacity)
            .kAnimated(value: state)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("k-column-panel")
    }
}

struct EntityLinkedText: View {
    let text: String
    let refs: [EntityRef]
    let fontToken: KFontToken
    let opacity: Double
    let lineLimit: Int?
    let minimumScaleFactor: CGFloat?
    let lineSpacing: CGFloat?
    let onOpen: (EntityRef) -> Void

    @Environment(\.kInkOnPaper) private var inkOnPaper
    @Environment(\.kSelectedEntityID) private var selectedEntityID

    private var ink: Color { inkOnPaper ? KStyle.nearBlack : .white }
    private var isOriginMarked: Bool {
        guard let selectedEntityID else { return false }
        return refs.contains { $0.id == selectedEntityID }
    }

    init(
        _ text: String,
        refs: [EntityRef],
        fontToken: KFontToken = .content,
        opacity: Double = KStyle.secondaryTextOpacity,
        lineLimit: Int? = nil,
        minimumScaleFactor: CGFloat? = nil,
        lineSpacing: CGFloat? = nil,
        onOpen: @escaping (EntityRef) -> Void
    ) {
        self.text = text
        self.refs = refs
        self.fontToken = fontToken
        self.opacity = opacity
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
        self.lineSpacing = lineSpacing
        self.onOpen = onOpen
    }

    var body: some View {
        Text(attributedText)
            .kFont(fontToken)
            .foregroundStyle(ink.opacity(opacity))
            .tint(ink.opacity(opacity))
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor ?? CGFloat(KStyle.fullOpacity))
            .lineSpacing(lineSpacing ?? .zero)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .opacity(isOriginMarked ? KStyle.secondaryTextOpacity : KStyle.fullOpacity)
            .accessibilityAddTraits(isOriginMarked ? .isSelected : [])
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "kentity",
                      let indexText = url.pathComponents.last,
                      let index = Int(indexText),
                      matches.indices.contains(index)
                else { return .discarded }
                onOpen(matches[index].ref)
                return .handled
            })
            .accessibilityLabel(text)
    }

    private var matches: [EntityTextMatch] {
        EntitySpanMatcher.matches(in: text, refs: refs)
    }

    private var attributedText: AttributedString {
        let matches = matches
        guard !matches.isEmpty else { return AttributedString(text) }

        var result = AttributedString()
        var cursor = text.startIndex
        for (index, match) in matches.enumerated() {
            if cursor < match.range.lowerBound {
                result += AttributedString(String(text[cursor..<match.range.lowerBound]))
            }
            var linked = AttributedString(String(text[match.range]))
            linked.link = URL(string: "kentity://open/\(index)")
            result += linked
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            result += AttributedString(String(text[cursor..<text.endIndex]))
        }
        return result
    }
}

private enum EntityDossierLoadState: Equatable {
    case idle
    case loading
    case loaded(EntityDossierEnvelope)
    case missing
    case failed(String)
}

struct EntityDossierPanel: View {
    let baseURL: String
    let selection: EntityDossierSelection
    let onDismiss: () -> Void
    @State private var navigation: EntityDossierPanelNavigation
    @State private var loadState: EntityDossierLoadState = .idle

    init(
        baseURL: String,
        selection: EntityDossierSelection,
        onDismiss: @escaping () -> Void
    ) {
        self.baseURL = baseURL
        self.selection = selection
        self.onDismiss = onDismiss
        _navigation = State(initialValue: EntityDossierPanelNavigation(selection: selection))
    }

    var body: some View {
        KColumnPanel {
            VStack(alignment: .leading, spacing: 0) {
                header

                Rectangle()
                    .fill(.white.opacity(KStyle.dividerOpacity))
                    .frame(height: KStyle.dividerHeight)

                ScrollView {
                    content
                        .padding(KStyle.columnMargin)
                        .padding(.trailing, KStyle.inputTrailingPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entity-dossier-panel")
        .gesture(
            DragGesture(minimumDistance: KStyle.minimumTapTarget / 2)
                .onEnded { value in
                    let verticalTolerance = KStyle.minimumTapTarget + KStyle.rowSpacing * 2
                    if value.translation.width > KStyle.minimumTapTarget,
                       abs(value.translation.height) < verticalTolerance {
                        onDismiss()
                    }
                }
        )
        .task(id: navigation.current.id) {
            await load(selection: navigation.current)
        }
        .onChange(of: selection) { _, newSelection in
            navigation.replace(with: newSelection)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: KStyle.rowSpacing) {
            KActRow(
                actions: [
                    KActItem(id: "back", accessibilityIdentifier: "entity-dossier-back"),
                ],
                variant: .admin,
                onSelect: { _ in onDismiss() }
            )

            Text(navigation.current.name)
                .font(KStyle.blockActiveTitleFont)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .lineLimit(2)
                .minimumScaleFactor(KStyle.titleMinimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("entity-dossier-title")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, KStyle.columnMargin)
        .padding(.trailing, KStyle.inputTrailingPadding)
        .padding(.vertical, KStyle.cardPadding)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            KLoadingPrimitive(
                variant: .skeleton,
                lineCount: 3,
                label: "loading entity",
                accessibilityIdentifier: "entity-dossier-loading"
            )
        case .missing:
            missingLine
        case .failed(let message):
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                KMonoCaption(message, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                KActRow(
                    actions: [
                        KActItem(id: "retry", accessibilityIdentifier: "entity-dossier-retry"),
                    ],
                    variant: .admin,
                    onSelect: { _ in
                        Task { await load(selection: navigation.current) }
                    }
                )
            }
        case .loaded(let envelope):
            if let dossier = envelope.dossier, !dossier.isEmpty {
                dossierContent(dossier)
            } else {
                missingLine
            }
        }
    }

    private var missingLine: some View {
        Text("k hasn't distilled this yet")
            .font(KStyle.contentFont)
            .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier("entity-dossier-missing")
    }

    private func dossierContent(_ dossier: EntityDossier) -> some View {
        VStack(alignment: .leading, spacing: KStyle.cardLargePadding) {
            if let definition = dossier.definition {
                Text(definition)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("entity-dossier-definition")
            }

            if !dossier.timeline.isEmpty {
                VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                    ForEach(Array(dossier.timeline.enumerated()), id: \.offset) { index, row in
                        timelineRow(row)
                            .accessibilityIdentifier("entity-dossier-timeline-\(index)")
                    }
                }
            }

            if !dossier.related.isEmpty {
                relatedChips(dossier.related)
            }

            if let openQuestion = dossier.openQuestion {
                Text(openQuestion)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("entity-dossier-open-question")
            }
        }
    }

    private func timelineRow(_ row: EntityDossierTimelineRow) -> some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                if !row.date.isEmpty {
                    KMonoCaption(row.date, variant: .metadata)
                }
                if !row.sourceName.isEmpty {
                    Text(row.sourceName)
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if !row.gist.isEmpty {
                Text(row.gist)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func relatedChips(_ related: [String]) -> some View {
        let columns = [GridItem(.adaptive(minimum: KStyle.minimumTapTarget * 2), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: KStyle.smallSpacing) {
            ForEach(related, id: \.self) { name in
                Button {
                    KStyle.withMotion {
                        navigation.openRelated(name)
                    }
                } label: {
                    Text(name.lowercased())
                        .kFont(.monoCaption)
                        .foregroundStyle(.white.opacity(KStyle.tertiaryTextOpacity))
                        .lineLimit(2)
                        .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                        .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("entity-dossier-related-\(name)")
            }
        }
    }

    @MainActor
    private func load(selection: EntityDossierSelection) async {
        loadState = .loading
        if KLoadingPreview.isEnabled { return }
        do {
            let envelope = try await AGUIClient(baseURL: baseURL).mindEntityDossier(selection: selection)
            guard !Task.isCancelled else { return }
            loadState = envelope.isMissing ? .missing : .loaded(envelope)
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed("entity unavailable · retry")
        }
    }
}

struct KStatusDot: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KStatusDot",
        semanticRole: "semantic signal dot for live, attention, error, offline, or idle state",
        props: [
            KPrimitiveDescriptors.prop("signal", "KSignal"),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("size", "KStatusDotSize", required: false),
        ],
        variants: KSignal.allCases.map(\.rawValue),
        usageWhen: [
            "use when color is reserved for semantic connection, block, or unit signals",
            "use alongside copy when the state needs initial recognition",
        ],
        usageNever: [
            "never use as decoration",
            "never encode arbitrary categories with color",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let signal: KSignal
    let state: KPrimitiveInteractionState
    let size: KStatusDotSize

    @Environment(\.kInkOnPaper) private var inkOnPaper

    init(
        signal: KSignal,
        state: KPrimitiveInteractionState = .resting,
        size: KStatusDotSize = .regular
    ) {
        self.signal = signal
        self.state = state
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: size.dimension, height: size.dimension)
            .opacity(dotOpacity)
            .accessibilityHidden(true)
    }

    private var dotOpacity: Double {
        if state == .disabled {
            return KStyle.quaternaryTextOpacity
        }
        if state == .stale {
            return (signal == .idle ? KStyle.idleDotOpacity : KStyle.activeDotOpacity) * KStyle.secondaryTextOpacity
        }
        return signal == .idle ? KStyle.idleDotOpacity : KStyle.activeDotOpacity
    }

    private var dotColor: Color {
        // Idle is the one signal used for the mind-v18 fresh marker. On the
        // selected paper card it must remain visible without inventing a new
        // hue, so the semantic idle ink flips with the primitive surface.
        if inkOnPaper, signal == .idle {
            return KStyle.nearBlack
        }
        return signal.color
    }
}

private struct KInkOnPaperKey: EnvironmentKey {
    static let defaultValue = false
}

private struct KSelectedEntityIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    /// True when a primitive's ink renders on a near-white paper surface instead of
    /// glass/dark chrome. Founder law: text is never colored — this flips ink
    /// lightness (dark-on-paper vs light-on-glass) only, never a hue.
    var kInkOnPaper: Bool {
        get { self[KInkOnPaperKey.self] }
        set { self[KInkOnPaperKey.self] = newValue }
    }

    /// The currently elevated entity dossier origin. Link-bearing copy uses this
    /// identity to keep the tapped entity visibly marked while its dossier floats
    /// above the resting surface.
    var kSelectedEntityID: String? {
        get { self[KSelectedEntityIDKey.self] }
        set { self[KSelectedEntityIDKey.self] = newValue }
    }
}

struct KLoadingPrimitive: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KLoadingPrimitive",
        semanticRole: "shared no-shimmer fetch loading treatment with dim skeleton lines or a quiet loading dot",
        props: [
            KPrimitiveDescriptors.prop("variant", "KLoadingVariant", required: false),
            KPrimitiveDescriptors.prop("lineCount", "Int", required: false),
            KPrimitiveDescriptors.prop("label", "String", required: false),
            KPrimitiveDescriptors.prop("accessibilityIdentifier", "String?", required: false),
        ],
        variants: KLoadingVariant.allCases.map(\.rawValue),
        interactionStates: [KPrimitiveInteractionState.loading.rawValue],
        usageWhen: [
            "use for every fetch that has not resolved to loaded, empty, or unreachable",
            "use skeleton for content-shaped waits and dot for an inline stream wait",
        ],
        usageNever: [
            "never shimmer, pulse, or spin",
            "never use as the empty or unreachable state",
            "never create a private loading skeleton or loading dot in a surface",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let variant: KLoadingVariant
    let lineCount: Int
    let label: String
    let accessibilityIdentifier: String?

    init(
        variant: KLoadingVariant = .skeleton,
        lineCount: Int = 3,
        label: String = KPrimitiveCopy.loading,
        accessibilityIdentifier: String? = nil
    ) {
        self.variant = variant
        self.lineCount = max(1, lineCount)
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label.lowercased())
                .accessibilityIdentifier(accessibilityIdentifier ?? "k-loading-\(variant.rawValue)")

            Group {
                switch variant {
                case .skeleton:
                    skeleton
                case .dot:
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        KStatusDot(signal: .idle, state: .loading, size: .small)
                        KMonoCaption(label, variant: .status, state: .loading)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label.lowercased())
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier(accessibilityIdentifier ?? "k-loading-\(variant.rawValue)")
        }
    }

    private var skeleton: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: KStyle.loadingSkeletonRowSpacing) {
                ForEach(0..<lineCount, id: \.self) { index in
                    RoundedRectangle(
                        cornerRadius: KStyle.loadingSkeletonCornerRadius,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(index == lineCount - 1
                        ? KStyle.loadingSkeletonMetaOpacity
                        : KStyle.loadingSkeletonFillOpacity))
                    .frame(
                        width: proxy.size.width * KStyle.loadingSkeletonWidth(for: index),
                        height: index == lineCount - 1
                            ? KStyle.loadingSkeletonMetaHeight
                            : KStyle.loadingSkeletonLineHeight
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: KStyle.loadingSkeletonMinHeight)
    }
}

struct KMonoCaption: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KMonoCaption",
        semanticRole: "monospaced lowercase status, staleness, metadata, or footer caption",
        props: [
            KPrimitiveDescriptors.prop("text", "String"),
            KPrimitiveDescriptors.prop("variant", "KMonoCaptionVariant", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
        ],
        variants: KMonoCaptionVariant.allCases.map(\.rawValue),
        usageWhen: [
            "use for written status visibility and inline recovery messages",
            "use for stale snapshot, footer, and metadata lines",
        ],
        usageNever: [
            "never use for primary content paragraphs",
            "never hide errors in alerts or icon-only controls",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let text: String
    let variant: KMonoCaptionVariant
    let state: KPrimitiveInteractionState

    @Environment(\.kInkOnPaper) private var inkOnPaper

    init(
        _ text: String,
        variant: KMonoCaptionVariant = .status,
        state: KPrimitiveInteractionState = .resting
    ) {
        self.text = text
        self.variant = variant
        self.state = state
    }

    var body: some View {
        // Founder law: text is never colored — failure hue lives on the dot.
        HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
            if isErrorRegister {
                Circle()
                    .fill(KStyle.inlineError)
                    .frame(width: KStyle.chatThreadStatusDotSize, height: KStyle.chatThreadStatusDotSize)
                    .accessibilityHidden(true)
            }
            Text(text.lowercased())
                .kFont(fontToken)
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel(text.lowercased())
        }
    }

    private var isErrorRegister: Bool {
        variant == .inlineError || state == .error
    }

    private var fontToken: KFontToken {
        variant == .staleness ? .monoCaptionDigit : .monoCaption
    }

    private var foregroundColor: Color {
        Self.resolveForegroundColor(isErrorRegister: isErrorRegister, state: state, inkOnPaper: inkOnPaper)
    }

    /// Pure ink resolution, split out for unit testing without a view host.
    /// Founder law: text is never colored — this only ever flips lightness
    /// (dark-on-paper vs light-on-glass), never a hue.
    static func resolveForegroundColor(
        isErrorRegister: Bool,
        state: KPrimitiveInteractionState,
        inkOnPaper: Bool
    ) -> Color {
        if inkOnPaper {
            // Same caption ink already used for on-paper captions elsewhere in
            // this card grammar (history/detail lines) — dark, not white.
            return KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity)
        }
        if isErrorRegister {
            return Color.white.opacity(KStyle.tertiaryTextOpacity)
        }
        return Color.white.opacity(state.quietTextOpacity)
    }
}

struct KPaperCard<Content: View>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KPaperCard",
            semanticRole: "quiet paper-tone card for nudge, review, and decision content",
            props: [
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("content", "View"),
            ],
            variants: ["nudge", "review", "decision"],
            usageWhen: [
                "use for the lighter card tone extracted from cadence nudges and review cards",
                "use when a surface needs slight grouping without platform glass",
            ],
            usageNever: [
                "never nest inside another card",
                "never use for chrome, decoration, or marketing-style panels",
            ],
            interruptionClass: .peripheral,
            maxSimultaneousCues: 1
        )
    }

    let state: KPrimitiveInteractionState
    let content: Content

    init(
        state: KPrimitiveInteractionState = .resting,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.content = content()
    }

    var body: some View {
        content
            .padding(KStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kPaperCardTone()
            .opacity(state.contentOpacity)
            .kAnimated(value: state)
    }
}

struct KGlassCard<Content: View>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KGlassCard",
            semanticRole: "semantic glass-tone card for depth panels and scrollable utility surfaces",
            props: [
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("content", "View"),
            ],
            variants: ["panel", "depth", "inline"],
            usageWhen: [
                "use for the stronger glass tone extracted from build depth panels and evidence blocks",
                "use when the card needs to survive future platform material changes",
            ],
            usageNever: [
                "never introduce a third card tone",
                "never expose platform material directly at call sites",
            ],
            interruptionClass: .peripheral,
            maxSimultaneousCues: 1
        )
    }

    let state: KPrimitiveInteractionState
    let content: Content

    init(
        state: KPrimitiveInteractionState = .resting,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.content = content()
    }

    var body: some View {
        content
            .padding(KStyle.cardLargePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kGlassCardTone()
            .opacity(state.contentOpacity)
            .kAnimated(value: state)
    }
}

struct KNextRow: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KNextRow",
        semanticRole: "quiet mono next line with label, start time, and title",
        props: [
            KPrimitiveDescriptors.prop("timeText", "String?", required: false),
            KPrimitiveDescriptors.prop("title", "String?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
        ],
        variants: ["next"],
        interactionStates: KPrimitiveDescriptors.cadenceInstrumentStates,
        usageWhen: [
            "use directly under cadence now to name the next block without promoting it",
            "use when start time and title should scan as metadata",
        ],
        usageNever: [
            "never use for full timeline rows",
            "never decorate the next item with a card or badge",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let timeText: String?
    let title: String?
    let state: KPrimitiveInteractionState

    init(
        timeText: String? = nil,
        title: String? = nil,
        state: KPrimitiveInteractionState = .resting
    ) {
        self.timeText = timeText
        self.title = title
        self.state = state
    }

    var body: some View {
        if let detailText {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                KMonoCaption("next", variant: .metadata, state: state)
                KMonoCaption(detailText, variant: .metadata, state: state)
                Spacer(minLength: .zero)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("k-next-row")
        } else if state == .empty {
            KMonoCaption("next · none", variant: .metadata, state: state)
                .accessibilityIdentifier("k-next-row")
        }
    }

    private var detailText: String? {
        let values = [timeText, title]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " \(KPrimitiveCopy.middleDot) ").lowercased()
    }
}

struct KRestStrip: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KRestStrip",
        semanticRole: "single quiet mono line for the remaining day shape after next",
        props: [
            KPrimitiveDescriptors.prop("text", "String?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
        ],
        variants: ["remaining"],
        interactionStates: KPrimitiveDescriptors.cadenceInstrumentStates,
        usageWhen: [
            "use below KNextRow to keep the day's remaining shape peripheral",
            "use for up to four compact start-time and title pairs",
        ],
        usageNever: [
            "never show elapsed blocks here",
            "never use as a scrollable or tappable timeline",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let text: String?
    let state: KPrimitiveInteractionState

    init(
        text: String? = nil,
        state: KPrimitiveInteractionState = .resting
    ) {
        self.text = text
        self.state = state
    }

    var body: some View {
        if let displayText {
            KMonoCaption(displayText, variant: .metadata, state: state)
                .accessibilityIdentifier("k-rest-strip")
        } else if state == .empty {
            KMonoCaption("rest clear", variant: .metadata, state: state)
                .accessibilityIdentifier("k-rest-strip")
        }
    }

    private var displayText: String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed?.lowercased() : nil
    }
}

struct KCapacityLine: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KCapacityLine",
        semanticRole: "quiet mono remaining capacity line with optional in-flow detail tap",
        props: [
            KPrimitiveDescriptors.prop("text", "String?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelect", "(() -> Void)?", required: false),
        ],
        variants: ["remaining-capacity"],
        interactionStates: KPrimitiveDescriptors.cadenceInstrumentStates,
        usageWhen: [
            "use for cadence's peripheral per-mode attention budget summary",
            "use when tapping expands the capacity detail under its origin line",
        ],
        usageNever: [
            "never show zero or missing modes",
            "never promote capacity above the now instrument",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 1
    )

    let text: String?
    let state: KPrimitiveInteractionState
    let onSelect: (() -> Void)?

    init(
        text: String? = nil,
        state: KPrimitiveInteractionState = .resting,
        onSelect: (() -> Void)? = nil
    ) {
        self.text = text
        self.state = state
        self.onSelect = onSelect
    }

    var body: some View {
        if let displayText {
            Button {
                onSelect?()
            } label: {
                KMonoCaption(displayText, variant: .metadata, state: state)
                    .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onSelect == nil || state.disablesAction)
            .accessibilityIdentifier("k-capacity-line")
        } else if state == .empty {
            KMonoCaption("left clear", variant: .metadata, state: state)
                .accessibilityIdentifier("k-capacity-line")
        }
    }

    private var displayText: String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed?.lowercased() : nil
    }
}

struct KBlockDetail<Actions: View>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KBlockDetail",
            semanticRole: "single-column block detail route with title, time, why, metadata, detail sections, and optional quiet actions",
            props: [
                KPrimitiveDescriptors.prop("title", "String"),
                KPrimitiveDescriptors.prop("timeText", "String?", required: false),
                KPrimitiveDescriptors.prop("why", "String?", required: false),
                KPrimitiveDescriptors.prop("meta", "String?", required: false),
                KPrimitiveDescriptors.prop("sections", "[DetailSection]"),
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("onChecklistToggle", "((ChecklistItem) -> Void)?", required: false),
                KPrimitiveDescriptors.prop("actions", "View"),
            ],
            variants: ["block-detail"],
            usageWhen: [
                "use for cadence block drill-ins that preserve type-specific richness after founder intent",
                "use when DetailSection lines and checklist rows need one quiet reading column",
            ],
            usageNever: [
                "never use as an inline timeline expansion",
                "never place inside a card or secondary sheet",
            ],
            interruptionClass: .focal,
            maxSimultaneousCues: 1
        )
    }

    let title: String
    let timeText: String?
    let why: String?
    let meta: String?
    let sections: [DetailSection]
    let state: KPrimitiveInteractionState
    let onChecklistToggle: ((ChecklistItem) -> Void)?
    let actions: Actions

    init(
        title: String,
        timeText: String? = nil,
        why: String? = nil,
        meta: String? = nil,
        sections: [DetailSection],
        state: KPrimitiveInteractionState = .resting,
        onChecklistToggle: ((ChecklistItem) -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.timeText = Self.normalized(timeText)
        self.why = Self.normalized(why)
        self.meta = Self.normalized(meta)
        self.sections = sections.filter { !$0.isEmpty }
        self.state = state
        self.onChecklistToggle = onChecklistToggle
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            Text(title.lowercased())
                .kNowTitleText()
                .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                .minimumScaleFactor(KStyle.titleMinimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let timeText {
                KMonoCaption(timeText, variant: .staleness, state: state)
            }

            if let why {
                Text(why)
                    .font(KStyle.contentFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let meta {
                KMonoCaption(meta, variant: .metadata, state: state)
            }

            ForEach(sections) { section in
                KDetailSectionView(
                    section: section,
                    state: state,
                    onChecklistToggle: onChecklistToggle
                )
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(state.contentOpacity)
        .kAnimated(value: state)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("k-block-detail")
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

extension KBlockDetail where Actions == EmptyView {
    init(
        title: String,
        timeText: String? = nil,
        why: String? = nil,
        meta: String? = nil,
        sections: [DetailSection],
        state: KPrimitiveInteractionState = .resting,
        onChecklistToggle: ((ChecklistItem) -> Void)? = nil
    ) {
        self.init(
            title: title,
            timeText: timeText,
            why: why,
            meta: meta,
            sections: sections,
            state: state,
            onChecklistToggle: onChecklistToggle
        ) {
            EmptyView()
        }
    }
}

private struct KDetailSectionView: View {
    let section: DetailSection
    let state: KPrimitiveInteractionState
    let onChecklistToggle: ((ChecklistItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            if let header = section.header {
                KMonoCaption(header, variant: .metadata, state: state)
            }

            ForEach(section.lines, id: \.self) { line in
                KMonoCaption(line, variant: .metadata, state: state)
            }

            if let checklist = section.checklist {
                KBlockContentChecklistRows(
                    items: checklist,
                    state: state,
                    onToggle: onChecklistToggle
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KSensesRail: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KSensesRail",
        semanticRole: "ambient regular-width rail of source-labeled body, capacity, and nutrition sense groups",
        props: [
            KPrimitiveDescriptors.prop("groups", "[KSensesRailGroup]"),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelectGroup", "((KSensesRailGroup) -> Void)?", required: false),
        ],
        variants: ["rail"],
        interactionStates: KPrimitiveDescriptors.cadenceInstrumentStates,
        usageWhen: [
            "use on regular-width cadence for peripheral body, capacity, and nutrition readings",
            "use only when existing fetched data has at least one line to render",
        ],
        usageNever: [
            "never use card material, borders, or fills for the rail groups",
            "never render placeholder dashes for absent sources",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 3
    )

    let groups: [KSensesRailGroup]
    let state: KPrimitiveInteractionState
    let onSelectGroup: ((KSensesRailGroup) -> Void)?

    init(
        groups: [KSensesRailGroup],
        state: KPrimitiveInteractionState = .resting,
        onSelectGroup: ((KSensesRailGroup) -> Void)? = nil
    ) {
        self.groups = groups.filter { !$0.title.isEmpty && !$0.source.isEmpty && !$0.lines.isEmpty }
        self.state = state
        self.onSelectGroup = onSelectGroup
    }

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                ForEach(groups) { group in
                    if let onSelectGroup {
                        Button {
                            onSelectGroup(group)
                        } label: {
                            groupView(group)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.disablesAction)
                    } else {
                        groupView(group)
                    }
                }
            }
            .frame(width: KStyle.sensesRailWidth, alignment: .topLeading)
            .opacity(state.contentOpacity)
            .kAnimated(value: state)
            .accessibilityIdentifier("k-senses-rail")
        }
    }

    private func groupView(_ group: KSensesRailGroup) -> some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(group.title)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .lineLimit(KStyle.singleLineLimit)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)

                Spacer(minLength: KStyle.smallSpacing)

                HStack(alignment: .center, spacing: KStyle.microSpacing) {
                    KStatusDot(signal: .live, state: state, size: .small)
                    KMonoCaption(group.source, variant: .metadata, state: state)
                }
            }

            ForEach(group.lines, id: \.self) { line in
                KMonoCaption(line, variant: .metadata, state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct KBlockContentChecklistRows: View {
    let items: [ChecklistItem]
    let state: KPrimitiveInteractionState
    let onToggle: ((ChecklistItem) -> Void)?
    let foregroundColor: Color
    @State private var localDoneByID: [String: Bool] = [:]

    init(
        items: [ChecklistItem],
        state: KPrimitiveInteractionState,
        onToggle: ((ChecklistItem) -> Void)?,
        foregroundColor: Color = .white
    ) {
        self.items = items
        self.state = state
        self.onToggle = onToggle
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            ForEach(items) { item in
                KChecklistRow(
                    title: item.text,
                    isDone: doneState(for: item),
                    state: state,
                    foregroundColor: foregroundColor,
                    onToggle: {
                        toggle(item)
                    }
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
            return
        }
        localDoneByID[item.id] = !doneState(for: item)
    }
}

enum KChatVerb: String, CaseIterable, Identifiable {
    case branch
    case toMind
    case actOn
    case refs
    case replyTo
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .branch: return "branch"
        case .toMind: return "to mind"
        case .actOn: return "act on"
        case .refs: return "refs"
        case .replyTo: return "reply to"
        case .copy: return "copy"
        }
    }
}

struct KChatVerbDrawer: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KChatVerbDrawer",
        semanticRole: "quiet verb drawer for a k reply with receipt and source access",
        props: [
            KPrimitiveDescriptors.prop("isOpen", "Bool", required: false),
            KPrimitiveDescriptors.prop("receipt", "ChatReceipt", required: false),
            KPrimitiveDescriptors.prop("onSelect", "(KChatVerb) -> Void"),
        ],
        variants: ["message"],
        usageWhen: [
            "use on a k reply after long press or reply swipe",
            "keep receipt inside the drawer and keep source access inline on regular width",
        ],
        usageNever: [
            "never add a second backdrop or corner action cluster",
            "never invent receipt values when the packet is silent",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let isOpen: Bool
    let receipt: ChatReceipt?
    let messageID: String?
    let onSelect: (KChatVerb) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isOpen: Bool,
        receipt: ChatReceipt? = nil,
        messageID: String? = nil,
        onSelect: @escaping (KChatVerb) -> Void
    ) {
        self.isOpen = isOpen
        self.receipt = receipt
        self.messageID = messageID
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            if isOpen {
                HStack(spacing: KStyle.smallSpacing) {
                    ForEach(KChatVerb.allCases) { verb in
                        Button {
                            onSelect(verb)
                        } label: {
                            verbIcon(verb)
                                .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(KStyle.chatSupportOpacity))
                        .accessibilityLabel(verb.title)
                        .accessibilityIdentifier(identifier(for: verb))
                    }

                    if let receiptText = receipt?.text {
                        KMonoCaption(receiptText, variant: .metadata)
                            .padding(.leading, KStyle.microSpacing)
                            .accessibilityIdentifier("chat-verb-receipt")
                    }
                }
                .padding(.horizontal, KStyle.microSpacing)
                .overlay {
                    Capsule()
                        .stroke(
                            Color.white.opacity(KStyle.hairlineOpacity),
                            lineWidth: KStyle.hairlineWidth
                        )
                }
                .transition(.opacity.combined(with: .offset(y: KStyle.smallSpacing)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(KStyle.chatStructureMotion(reduceMotion), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(messageID.map { "chat-verb-drawer-\($0)" } ?? "chat-verb-drawer")
    }

    private func identifier(for verb: KChatVerb) -> String {
        if verb == .branch, let messageID {
            return "chat-branch-\(messageID)"
        }
        if let messageID {
            return "chat-verb-\(verb.id)-\(messageID)"
        }
        return "chat-verb-\(verb.id)"
    }

    @ViewBuilder
    private func verbIcon(_ verb: KChatVerb) -> some View {
        switch verb {
        case .branch:
            Image(systemName: "arrow.right")
        case .toMind:
            KNavIcon(tab: .mind, size: KStyle.navCompactIconSize)
        case .actOn:
            Image(systemName: "arrow.up")
        case .refs:
            Image(systemName: "line.3.horizontal.decrease")
        case .replyTo:
            Image(systemName: "arrowshape.turn.up.left.fill")
        case .copy:
            Image(systemName: "square.on.square")
        }
    }
}

enum KChatActionTier: Equatable {
    case bare
    case hairline
    case filled

    var foreground: Color {
        switch self {
        case .bare:
            return Color.white.opacity(KStyle.tertiaryTextOpacity)
        case .hairline:
            return Color.white.opacity(KStyle.chatSupportOpacity)
        case .filled:
            return KStyle.nearBlack.opacity(KStyle.primaryControlTextOpacity)
        }
    }
}

struct KChatActionRow: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KChatActionRow",
        semanticRole: "latest-only three-tier next-action row with follow-up slider and chosen receipt chip",
        props: [
            KPrimitiveDescriptors.prop("actions", "[ChatNextActionItem]"),
            KPrimitiveDescriptors.prop("followUps", "[ChatNextActionItem]", required: false),
            KPrimitiveDescriptors.prop("selectedActionID", "String?", required: false),
            KPrimitiveDescriptors.prop("isActive", "Bool", required: false),
            KPrimitiveDescriptors.prop("showFullRow", "Bool", required: false),
            KPrimitiveDescriptors.prop("isFollowUpPage", "Bool", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelect", "(ChatNextActionItem) -> Void"),
            KPrimitiveDescriptors.prop("onFollowUp", "(ChatNextActionItem) -> Void", required: false),
            KPrimitiveDescriptors.prop("onPageChange", "(Bool) -> Void", required: false),
            KPrimitiveDescriptors.prop("onRestoreFullRow", "() -> Void", required: false),
        ],
        variants: ["latest", "previous"],
        interactionStates: KPrimitiveDescriptors.fullStates,
        usageWhen: [
            "use only when the reply packet emits next-action fields",
            "right-align the three tiers with the primary action at the right edge",
            "collapse previous action turns to the chosen checkmark chip",
        ],
        usageNever: [
            "never fabricate an action, placeholder, or user bubble",
            "never send action text from this row",
            "never use a spring or a per-message clock",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let actions: [ChatNextActionItem]
    let followUps: [ChatNextActionItem]
    let selectedActionID: String?
    let isActive: Bool
    let showFullRow: Bool
    let isFollowUpPage: Bool
    let state: KPrimitiveInteractionState
    let accessibilityPrefix: String
    let onSelect: (ChatNextActionItem) -> Void
    let onFollowUp: (ChatNextActionItem) -> Void
    let onPageChange: (Bool) -> Void
    let onRestoreFullRow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        actions: [ChatNextActionItem],
        followUps: [ChatNextActionItem] = [],
        selectedActionID: String? = nil,
        isActive: Bool = true,
        showFullRow: Bool = false,
        isFollowUpPage: Bool = false,
        state: KPrimitiveInteractionState = .resting,
        accessibilityPrefix: String = "chat-next-actions",
        onSelect: @escaping (ChatNextActionItem) -> Void,
        onFollowUp: @escaping (ChatNextActionItem) -> Void = { _ in },
        onPageChange: @escaping (Bool) -> Void = { _ in },
        onRestoreFullRow: @escaping () -> Void = {}
    ) {
        self.actions = actions
        self.followUps = followUps
        self.selectedActionID = selectedActionID
        self.isActive = isActive
        self.showFullRow = showFullRow
        self.isFollowUpPage = isFollowUpPage
        self.state = state
        self.accessibilityPrefix = accessibilityPrefix
        self.onSelect = onSelect
        self.onFollowUp = onFollowUp
        self.onPageChange = onPageChange
        self.onRestoreFullRow = onRestoreFullRow
    }

    var body: some View {
        Group {
            switch rowState {
            case .absent:
                EmptyView()
            case .previousCollapsed:
                chosenChip
            case .latestActive, .previousRestored:
                fullRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(KStyle.chatStructureMotion(reduceMotion), value: rowState)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix)
    }

    private var rowState: ChatNextActionRowState {
        ChatNextActionRowState.resolve(
            actions: actions,
            selectedActionID: selectedActionID,
            isLatest: isActive,
            isRestored: showFullRow
        )
    }

    private var chosenItem: ChatNextActionItem? {
        guard let selectedActionID else { return nil }
        return actions.first { $0.id == selectedActionID }
    }

    private var chosenChip: some View {
        Text("✓ \(chosenItem?.label.lowercased() ?? "")")
            .kFont(.monoCaption)
            .foregroundStyle(Color.white.opacity(KStyle.chatSupportOpacity))
            .padding(.horizontal, KStyle.optionButtonHorizontalPadding)
            .frame(minHeight: KStyle.minimumTapTarget)
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(KStyle.hairlineOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
            }
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: KStyle.bandishDetailLongPressDuration) {
                onRestoreFullRow()
            }
            .accessibilityLabel("chosen \(chosenItem?.label.lowercased() ?? "action")")
            .accessibilityHint("long-press to restore actions")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("\(accessibilityPrefix)-chosen")
    }

    @ViewBuilder
    private var fullRow: some View {
        HStack(alignment: .center, spacing: KStyle.smallSpacing) {
            if isFollowUpPage {
                followUpItems
                if !actions.isEmpty {
                    chevron(direction: .right)
                }
            } else {
                if !followUps.isEmpty {
                    chevron(direction: .left)
                }
                actionItems
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .id(isFollowUpPage)
        .transition(.opacity.combined(with: .offset(x: KStyle.chatShellColumnGap)))
    }

    @ViewBuilder
    private var actionItems: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
            actionButton(item, tier: tier(for: index, count: actions.count), action: onSelect)
        }
    }

    @ViewBuilder
    private var followUpItems: some View {
        ForEach(Array(followUps.enumerated()), id: \.element.id) { index, item in
            actionButton(item, tier: tier(for: index, count: followUps.count), action: onFollowUp)
        }
    }

    private func tier(for index: Int, count: Int) -> KChatActionTier {
        switch max(0, count - index) {
        case 1:
            return .filled
        case 2:
            return .hairline
        default:
            return .bare
        }
    }

    @ViewBuilder
    private func actionButton(
        _ item: ChatNextActionItem,
        tier: KChatActionTier,
        action: @escaping (ChatNextActionItem) -> Void
    ) -> some View {
        Button {
            guard !state.disablesAction else { return }
            action(item)
        } label: {
            Text(item.label.lowercased())
                .kFont(.optionButton)
                .lineLimit(KStyle.singleLineLimit)
                .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                .foregroundStyle(tier.foreground)
                .padding(.horizontal, KStyle.optionButtonHorizontalPadding)
                .frame(minHeight: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.disablesAction)
        .background {
            switch tier {
            case .bare:
                Color.clear
            case .hairline:
                Capsule()
                    .stroke(
                        Color.white.opacity(KStyle.controlHairlineOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
            case .filled:
                Capsule()
                    .fill(Color.white.opacity(KStyle.controlEnabledFillOpacity))
            }
        }
        .accessibilityIdentifier("\(accessibilityPrefix)-\(item.id)")
    }

    private enum ChevronDirection {
        case left
        case right

        var systemName: String {
            switch self {
            case .left: return "chevron.left"
            case .right: return "chevron.right"
            }
        }
    }

    private func chevron(direction: ChevronDirection) -> some View {
        Button {
            onPageChange(direction == .right)
        } label: {
            Image(systemName: direction.systemName)
                .kFont(.monoCaption)
                .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .left ? "follow-up questions" : "next actions")
        .accessibilityIdentifier("\(accessibilityPrefix)-\(direction == .left ? "previous" : "next")")
    }
}

struct KActRow: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KActRow",
        semanticRole: "quiet lowercase text actions separated by middle dots",
        props: [
            KPrimitiveDescriptors.prop("actions", "[KActItem]"),
            KPrimitiveDescriptors.prop("selectedActionIDs", "Set<String>", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelect", "(KActItem) -> Void"),
        ],
        variants: KActRowVariant.allCases.map(\.rawValue),
        usageWhen: [
            "use for quiet answerable text acts such as complete, skip, reschedule, approve, or retry",
            "use when recognition of available actions matters more than visual priority",
        ],
        usageNever: [
            "never use for the fixed mind verdict bar",
            "never add icons, filled pills, or badges",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let actions: [KActItem]
    let variant: KActRowVariant
    let selectedActionIDs: Set<String>
    let state: KPrimitiveInteractionState
    let onSelect: (KActItem) -> Void

    @Environment(\.kInkOnPaper) private var inkOnPaper

    init(
        actions: [KActItem],
        variant: KActRowVariant = .cadence,
        selectedActionIDs: Set<String> = [],
        state: KPrimitiveInteractionState = .resting,
        onSelect: @escaping (KActItem) -> Void
    ) {
        self.actions = actions
        self.variant = variant
        self.selectedActionIDs = selectedActionIDs
        self.state = state
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: KStyle.smallSpacing) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    onSelect(action)
                } label: {
                    Text(action.label.lowercased())
                        .kFont(.monoCaption)
                        .lineLimit(KStyle.singleLineLimit)
                        .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
                        .foregroundStyle(inkColor.opacity(opacity(for: action)))
                        .frame(minWidth: KStyle.actButtonMinWidth, minHeight: KStyle.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.disablesAction || !action.isEnabled)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "k-act-\(action.id)")

                if index < actions.count - 1 {
                        Text(KPrimitiveCopy.middleDot)
                            .kFont(.monoCaption)
                        .foregroundStyle(inkColor.opacity(KStyle.quaternaryTextOpacity))
                        .accessibilityHidden(true)
                }
            }
        }
        .kAnimated(value: state)
        .accessibilityElement(children: .contain)
    }

    private func opacity(for action: KActItem) -> Double {
        guard action.isEnabled else { return KStyle.quaternaryTextOpacity }
        if state.disablesAction { return KStyle.quaternaryTextOpacity }
        if selectedActionIDs.contains(action.id) { return KStyle.secondaryTextOpacity }
        return state.quietTextOpacity
    }

    private var inkColor: Color {
        inkOnPaper ? KStyle.nearBlack : Color.white
    }
}

struct KOptionButton: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KOptionButton",
        semanticRole: "build decision option button with primary fill or quiet hairline treatment",
        props: [
            KPrimitiveDescriptors.prop("label", "String"),
            KPrimitiveDescriptors.prop("variant", "KOptionButtonVariant", required: false),
            KPrimitiveDescriptors.prop("isEnabled", "Bool", required: false),
            KPrimitiveDescriptors.prop("isPending", "Bool", required: false),
            KPrimitiveDescriptors.prop("isConfirming", "Bool", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelect", "() -> Void"),
        ],
        variants: KOptionButtonVariant.allCases.map(\.rawValue),
        usageWhen: [
            "use for build card options that need a primary-filled or quiet-hairline treatment",
            "use when kill-class options replace their label with sure? on the second-tap confirmation window",
        ],
        usageNever: [
            "never use for quiet text acts that belong in KActRow",
            "never introduce local button styles for build card options",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let label: String
    let variant: KOptionButtonVariant
    let isEnabled: Bool
    let isPending: Bool
    let isConfirming: Bool
    let state: KPrimitiveInteractionState
    let accessibilityIdentifier: String?
    let onSelect: () -> Void

    @Environment(\.kInkOnPaper) private var inkOnPaper

    init(
        label: String,
        variant: KOptionButtonVariant = .quietHairline,
        isEnabled: Bool = true,
        isPending: Bool = false,
        isConfirming: Bool = false,
        state: KPrimitiveInteractionState = .resting,
        accessibilityIdentifier: String? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.label = label
        self.variant = variant
        self.isEnabled = isEnabled
        self.isPending = isPending
        self.isConfirming = isConfirming
        self.state = state
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: KStyle.optionButtonSpacing) {
                if isPending {
                    Circle()
                        .fill(pendingDotColor)
                        .frame(
                            width: KStyle.optionButtonPendingDotSize,
                            height: KStyle.optionButtonPendingDotSize
                        )
                }
                Text(displayLabel)
                    .lineLimit(KStyle.singleLineLimit)
                    .minimumScaleFactor(KStyle.compactTextMinimumScaleFactor)
            }
        }
        .buttonStyle(KOptionButtonStyle(
            variant: variant,
            isPending: isPending,
            isEnabled: isEnabled && !state.disablesAction,
            inkOnPaper: inkOnPaper
        ))
        .disabled(state.disablesAction || !isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier ?? "k-option-\(normalizedLabel)")
        .kAnimated(value: state)
        .kAnimated(value: isPending)
        .kAnimated(value: isConfirming)
    }

    private var displayLabel: String {
        isConfirming ? "sure?" : label.lowercased()
    }

    private var normalizedLabel: String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private var pendingDotColor: Color {
        KOptionButtonStyleResolution.resolve(
            variant: variant,
            isPending: isPending,
            isEnabled: isEnabled && !state.disablesAction,
            isPressed: false,
            inkOnPaper: inkOnPaper
        )
        .foregroundColor
        .opacity(KStyle.controlPendingDotOpacity)
    }
}

enum KOptionButtonStyleColorBase: Equatable {
    case clear
    case light
    case nearBlack

    var color: Color {
        switch self {
        case .clear:
            return .clear
        case .light:
            return .white
        case .nearBlack:
            return KStyle.nearBlack
        }
    }
}

struct KOptionButtonStyleResolution: Equatable {
    var foregroundBase: KOptionButtonStyleColorBase
    var foregroundOpacity: Double
    var fillBase: KOptionButtonStyleColorBase
    var fillOpacity: Double
    var strokeBase: KOptionButtonStyleColorBase
    var strokeOpacity: Double

    static func resolve(
        variant: KOptionButtonVariant,
        isPending: Bool,
        isEnabled: Bool,
        isPressed: Bool,
        inkOnPaper: Bool = false
    ) -> KOptionButtonStyleResolution {
        let usesFill = variant == .primaryFilled || isPending
        let foregroundBase: KOptionButtonStyleColorBase = usesFill || inkOnPaper ? .nearBlack : .light
        let foregroundOpacity: Double
        if !isEnabled {
            foregroundOpacity = KStyle.quaternaryTextOpacity
        } else if usesFill {
            foregroundOpacity = KStyle.primaryControlTextOpacity
        } else if variant == .archiveNaked {
            foregroundOpacity = KStyle.tertiaryTextOpacity
        } else {
            foregroundOpacity = KStyle.secondaryTextOpacity
        }

        let fillOpacity: Double
        if !usesFill {
            fillOpacity = .zero
        } else if isPending {
            fillOpacity = KStyle.controlPendingFillOpacity
        } else if isPressed {
            fillOpacity = KStyle.controlPressedFillOpacity
        } else {
            fillOpacity = KStyle.controlEnabledFillOpacity
        }

        return KOptionButtonStyleResolution(
            foregroundBase: foregroundBase,
            foregroundOpacity: foregroundOpacity,
            fillBase: usesFill ? .light : .clear,
            fillOpacity: fillOpacity,
            strokeBase: strokeBase(for: variant, usesFill: usesFill, inkOnPaper: inkOnPaper),
            strokeOpacity: strokeOpacity(for: variant, usesFill: usesFill)
        )
    }

    private static func strokeBase(
        for variant: KOptionButtonVariant,
        usesFill: Bool,
        inkOnPaper: Bool
    ) -> KOptionButtonStyleColorBase {
        if inkOnPaper, !usesFill { return .nearBlack }
        switch variant {
        case .secondaryHairline, .archiveNaked: return .light
        default: return usesFill ? .nearBlack : .light
        }
    }

    private static func strokeOpacity(for variant: KOptionButtonVariant, usesFill: Bool) -> Double {
        switch variant {
        case .secondaryHairline: return KStyle.hairlineStrongOpacity
        case .archiveNaked: return .zero
        default: return usesFill ? KStyle.hairlineStrongOpacity : KStyle.controlHairlineOpacity
        }
    }

    var foregroundColor: Color {
        foregroundBase.color.opacity(foregroundOpacity)
    }

    var fillColor: Color {
        fillBase.color.opacity(fillOpacity)
    }

    var strokeColor: Color {
        strokeBase.color.opacity(strokeOpacity)
    }
}

private struct KOptionButtonStyle: ButtonStyle {
    let variant: KOptionButtonVariant
    let isPending: Bool
    let isEnabled: Bool
    let inkOnPaper: Bool

    func makeBody(configuration: Configuration) -> some View {
        let resolution = KOptionButtonStyleResolution.resolve(
            variant: variant,
            isPending: isPending,
            isEnabled: isEnabled,
            isPressed: configuration.isPressed,
            inkOnPaper: inkOnPaper
        )

        configuration.label
            .font(KStyle.optionButtonFont)
            .padding(.horizontal, KStyle.optionButtonHorizontalPadding)
            .padding(.vertical, KStyle.optionButtonVerticalPadding)
            .frame(minHeight: KStyle.minimumTapTarget)
            .foregroundStyle(resolution.foregroundColor)
            .background {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(resolution.fillColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .stroke(resolution.strokeColor, lineWidth: KStyle.hairlineWidth)
            }
            .modifier(KOptionButtonPressFeedbackModifier(isPressed: configuration.isPressed))
    }
}

private struct KOptionButtonPressFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressedScale)
            .animation(pressAnimation, value: isPressed)
    }

    private var pressedScale: CGFloat {
        isPressed ? KStyle.optionButtonPressedScale : KStyle.identityScale
    }

    private var pressAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return isPressed ? KStyle.optionButtonPressIn : KStyle.ease
    }
}

struct KStreamRow<Content: View>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KStreamRow",
            semanticRole: "quiet aligned stream row with content and optional mono metadata",
            props: [
                KPrimitiveDescriptors.prop("role", "KStreamRowRole"),
                KPrimitiveDescriptors.prop("meta", "String?", required: false),
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("content", "View"),
            ],
            variants: KStreamRowRole.allCases.map(\.rawValue),
            usageWhen: [
                "use for chat and build stream rows that need founder/right and k-or-runner/left alignment",
                "use when stream metadata belongs under the line instead of in a badge",
            ],
            usageNever: [
                "never use for timeline rows with semantic dots",
                "never use for cards, summaries, or action clusters",
            ],
            interruptionClass: .ambient,
            maxSimultaneousCues: 1
        )
    }

    let role: KStreamRowRole
    let meta: String?
    let state: KPrimitiveInteractionState
    let accessibilityText: String?
    let content: Content

    init(
        role: KStreamRowRole,
        meta: String? = nil,
        state: KPrimitiveInteractionState = .resting,
        accessibilityText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.meta = meta
        self.state = state
        self.accessibilityText = accessibilityText
        self.content = content()
    }

    var body: some View {
        if let accessibilityText {
            row
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText)
        } else {
            row
                .accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        HStack(alignment: .bottom, spacing: KStyle.tightRowSpacing) {
            if role.keepsLeadingGutter {
                Spacer(minLength: KStyle.streamRowGutterWidth)
            }

            VStack(alignment: role.horizontalAlignment, spacing: KStyle.microSpacing) {
                content
                    .multilineTextAlignment(role.textAlignment)

                if let meta, !meta.isEmpty {
                    KMonoCaption(meta, variant: .metadata, state: state)
                        .multilineTextAlignment(role.textAlignment)
                }
            }

            if !role.keepsLeadingGutter {
                Spacer(minLength: KStyle.streamRowGutterWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: role.frameAlignment)
        .opacity(state.contentOpacity)
        .kAnimated(value: state)
    }
}

struct KProgressStrip: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KProgressStrip",
        semanticRole: "quiet progress strip with title, progress copy, and hairline fill",
        props: [
            KPrimitiveDescriptors.prop("title", "String"),
            KPrimitiveDescriptors.prop("progressText", "String"),
            KPrimitiveDescriptors.prop("progressRatio", "Double"),
            KPrimitiveDescriptors.prop("variant", "KProgressStripVariant", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
        ],
        variants: KProgressStripVariant.allCases.map(\.rawValue),
        usageWhen: [
            "use for a compact mission or unit-progress line inside a route surface",
            "use when written progress and a single hairline fill need to travel together",
        ],
        usageNever: [
            "never use as a spinner or ambient animation",
            "never stack more than one progress strip in the same slot",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let title: String
    let progressText: String
    let progressRatio: Double
    let variant: KProgressStripVariant
    let state: KPrimitiveInteractionState

    init(
        title: String,
        progressText: String,
        progressRatio: Double,
        variant: KProgressStripVariant = .buildMission,
        state: KPrimitiveInteractionState = .resting
    ) {
        self.title = title
        self.progressText = progressText
        self.progressRatio = progressRatio
        self.variant = variant
        self.state = state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.rowSpacing) {
                Text(title.lowercased())
                    .kFont(.tab)
                    .foregroundStyle(Color.white.opacity(KStyle.secondaryTextOpacity))
                    .lineLimit(KStyle.singleLineLimit)
                    .truncationMode(.middle)

                Spacer(minLength: KStyle.tightRowSpacing)

                KMonoCaption(progressText, variant: .metadata, state: state)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(KStyle.progressTrackOpacity))
                    Rectangle()
                        .fill(Color.white.opacity(KStyle.progressFillOpacity))
                        .frame(width: geometry.size.width * clampedProgressRatio)
                }
            }
            .frame(height: KStyle.progressStripHeight)
        }
        .opacity(state.contentOpacity)
        .kAnimated(value: state)
        .accessibilityElement(children: .combine)
    }

    private var clampedProgressRatio: Double {
        min(KStyle.fullProgressRatio, max(KStyle.zeroProgressRatio, progressRatio))
    }
}

enum KTabStripLayout {
    static func requiredWidth(
        for items: [KTabStripItem],
        availableWidth: CGFloat,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> CGFloat {
        guard !items.isEmpty else { return .zero }
        let metrics = KStyle.tabStripMetrics(availableWidth: availableWidth)
        let itemWidths = items.map { item in
            max(
                KStyle.minimumTapTarget,
                labelWidth(for: item, metrics: metrics, compatibleWith: traitCollection)
            )
        }
        let spacingCount = max(items.count - 1, Int.zero)
        return itemWidths.reduce(.zero, +)
            + CGFloat(spacingCount) * metrics.itemSpacing
            + metrics.horizontalPadding * 2
            + KStyle.selectorTrackPadding * 2
    }

    private static func labelWidth(
        for item: KTabStripItem,
        metrics: KTabStripMetrics,
        compatibleWith traitCollection: UITraitCollection?
    ) -> CGFloat {
        let font = KStyle.scaledUIFont(for: .tab, compatibleWith: traitCollection)
        let titleWidth = textWidth(item.title.uppercased(), font: font, tracking: metrics.labelTracking)
        guard item.showsDot else { return titleWidth }
        return titleWidth
            + KStyle.tabLabelSpacing
            + textWidth(KPrimitiveCopy.middleDot, font: font, tracking: metrics.labelTracking)
    }

    private static func textWidth(_ text: String, font: UIFont, tracking: CGFloat) -> CGFloat {
        let baseWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return baseWidth + max(.zero, CGFloat(text.count - 1) * tracking)
    }
}

struct KTabStrip: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KTabStrip",
        semanticRole: "root doctrine selector with mono uppercase labels in an inset track and a filled active state",
        props: [
            KPrimitiveDescriptors.prop("selection", "Binding<KAppTab>"),
            KPrimitiveDescriptors.prop("cadenceNeedsAttention", "Bool", required: false),
            KPrimitiveDescriptors.prop("chatHasUnread", "Bool", required: false),
            KPrimitiveDescriptors.prop("openBuildCards", "Int", required: false),
            KPrimitiveDescriptors.prop("unjudgedMindOutputs", "Int", required: false),
            KPrimitiveDescriptors.prop("adminDueTodayItems", "Int", required: false),
            KPrimitiveDescriptors.prop("staleTabs", "Set<KAppTab>", required: false),
        ],
        variants: ["root", "attention-dot", "stale-dot"],
        usageWhen: [
            "use only for the app's top doctrine selector",
            "use dots for waiting state without counts",
        ],
        usageNever: [
            "never add icons, blue tint, or numbered badges",
            "never render the active tab as text-only",
            "never use for in-panel segmented controls",
        ],
        interruptionClass: .ambient,
        maxSimultaneousCues: 5
    )

    @Binding var selection: KAppTab
    let cadenceNeedsAttention: Bool
    let chatHasUnread: Bool
    let openBuildCards: Int
    let unjudgedMindOutputs: Int
    let adminDueTodayItems: Int
    let staleTabs: Set<KAppTab>
    let state: KPrimitiveInteractionState

    init(
        selection: Binding<KAppTab>,
        cadenceNeedsAttention: Bool = false,
        chatHasUnread: Bool = false,
        openBuildCards: Int = .zero,
        unjudgedMindOutputs: Int = .zero,
        adminDueTodayItems: Int = .zero,
        staleTabs: Set<KAppTab> = [],
        state: KPrimitiveInteractionState = .resting
    ) {
        _selection = selection
        self.cadenceNeedsAttention = cadenceNeedsAttention
        self.chatHasUnread = chatHasUnread
        self.openBuildCards = openBuildCards
        self.unjudgedMindOutputs = unjudgedMindOutputs
        self.adminDueTodayItems = adminDueTodayItems
        self.staleTabs = staleTabs
        self.state = state
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = KStyle.tabStripMetrics(availableWidth: proxy.size.width)
            HStack(spacing: metrics.itemSpacing) {
                ForEach(KTabStripModel.items(
                    active: selection,
                    cadenceNeedsAttention: cadenceNeedsAttention,
                    chatHasUnread: chatHasUnread,
                    openBuildCards: openBuildCards,
                    unjudgedMindOutputs: unjudgedMindOutputs,
                    adminDueTodayItems: adminDueTodayItems,
                    staleTabs: staleTabs
                )) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: KStyle.tabLabelSpacing) {
                            Text(item.title.uppercased())
                                .foregroundStyle(tabTextColor(for: item))
                                .lineLimit(KStyle.singleLineLimit)
                                .allowsTightening(true)
                                .minimumScaleFactor(metrics.labelMinimumScaleFactor)
                                .fixedSize(horizontal: true, vertical: false)
                            if item.showsDot {
                                Text(KPrimitiveCopy.middleDot)
                                    .foregroundStyle(tabDotColor(for: item))
                                    .lineLimit(KStyle.singleLineLimit)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(KStyle.tabFont)
                        .tracking(metrics.labelTracking)
                        .frame(minWidth: KStyle.minimumTapTarget, minHeight: KStyle.minimumTapTarget)
                        .background {
                            RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                                .fill(item.isActive
                                    ? Color.white.opacity(KStyle.selectorActiveFillOpacity)
                                    : Color.clear)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(state == .disabled)
                    .accessibilityLabel("\(item.title) tab")
                    .accessibilityAddTraits(item.isActive ? .isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("k-tab-\(item.tab.rawValue)")
                }
            }
            .padding(KStyle.selectorTrackPadding)
            .background {
                RoundedRectangle(cornerRadius: KStyle.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(KStyle.selectorTrackFillOpacity))
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .center)
            .tint(.white)
            .opacity(state.contentOpacity)
            .kAnimated(value: state)
        }
        .frame(height: KStyle.minimumTapTarget + KStyle.selectorTrackPadding * 2)
    }

    private func tabTextColor(for item: KTabStripItem) -> Color {
        item.isActive
            ? KStyle.nearBlack.opacity(KStyle.selectorActiveTextOpacity)
            : Color.white.opacity(item.textOpacity)
    }

    private func tabDotColor(for item: KTabStripItem) -> Color {
        item.isActive
            ? KStyle.nearBlack.opacity(item.dotOpacity)
            : Color.white.opacity(item.dotOpacity)
    }
}

struct KSelectorItem<Selection: Hashable>: Identifiable, Equatable {
    let id: Selection
    let title: String
    let accessibilityLabel: String?
    let accessibilityIdentifier: String?

    init(
        id: Selection,
        title: String,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// Shared uppercase inset-track selector for in-panel tabs and domains. Root
/// navigation remains KTabStrip; every Bio selector composes this grammar so
/// target width, spacing, height, fill, and motion cannot drift by surface.
struct KSelectorStrip<Selection: Hashable>: View, KPrimitiveComponent {
    static var primitiveDescriptor: KPrimitiveComponentDescriptor {
        KPrimitiveDescriptors.component(
            name: "KSelectorStrip",
            semanticRole: "shared in-panel selector with uppercase labels, compact bandish pills, and one filled active state",
            props: [
                KPrimitiveDescriptors.prop("selection", "Binding<Selection>"),
                KPrimitiveDescriptors.prop("items", "[KSelectorItem<Selection>]"),
                KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
                KPrimitiveDescriptors.prop("accessibilityIdentifier", "String?", required: false),
            ],
            variants: ["inset-track"],
            usageWhen: [
                "use for in-panel tabs and domain selectors that share the uppercase inset-track grammar",
                "use when every item has a stable selection value and a 44pt target",
            ],
            usageNever: [
                "never use for root navigation: use KTabStrip or KNavBar",
                "never use for progress/status segments with no selection",
                "never add a second fill, border, icon, or numbered badge",
            ],
            interruptionClass: .ambient,
            maxSimultaneousCues: 1
        )
    }

    @Binding var selection: Selection
    let items: [KSelectorItem<Selection>]
    let state: KPrimitiveInteractionState
    let accessibilityIdentifier: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        selection: Binding<Selection>,
        items: [KSelectorItem<Selection>],
        state: KPrimitiveInteractionState = .resting,
        accessibilityIdentifier: String? = nil
    ) {
        _selection = selection
        self.items = items
        self.state = state
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KStyle.selectorStripTrackCornerRadius, style: .continuous)
                .fill(KStyle.emphasisInk.opacity(KStyle.selectorTrackFillOpacity))
                .frame(maxWidth: .infinity)
                .frame(height: KStyle.selectorStripTrackVisualHeight)
                .accessibilityHidden(true)

            ScrollView(.horizontal) {
                HStack(spacing: KStyle.selectorStripItemSpacing) {
                    ForEach(items) { item in
                        selectorButton(item)
                    }
                }
                .padding(.horizontal, KStyle.selectorStripTrackHorizontalPadding)
                .padding(.vertical, KStyle.selectorStripTrackVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: KStyle.minimumTapTarget, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: KStyle.minimumTapTarget)
        .tint(KStyle.emphasisInk)
        .opacity(state.contentOpacity)
        .kAnimated(value: state)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "k-selector-strip")
    }

    private func selectorButton(_ item: KSelectorItem<Selection>) -> some View {
        let isActive = selection == item.id
        return Button {
            selection = item.id
        } label: {
            Text(item.title.uppercased())
                .foregroundStyle(isActive
                    ? KStyle.nearBlack.opacity(KStyle.selectorActiveTextOpacity)
                    : KStyle.emphasisInk.opacity(KStyle.selectorInactiveTextOpacity))
                .lineLimit(KStyle.singleLineLimit)
                .allowsTightening(true)
                .minimumScaleFactor(KStyle.tabLabelMinimumScaleFactor)
                .fixedSize(horizontal: true, vertical: false)
                .font(KStyle.tabFont)
                .tracking(KStyle.tracking(for: .tab))
                .frame(
                    minWidth: KStyle.selectorStripItemMinimumWidth,
                    minHeight: KStyle.selectorStripItemVisualHeight
                )
                .padding(.horizontal, KStyle.selectorStripItemHorizontalPadding)
                .background {
                    RoundedRectangle(cornerRadius: KStyle.selectorStripActiveCornerRadius, style: .continuous)
                        .fill(isActive ? KStyle.emphasisInk.opacity(KStyle.selectorActiveFillOpacity) : Color.clear)
                        .animation(KStyle.selectorBackgroundMotion(reduceMotion), value: selection)
                }
                // Keep the visible pill compact while the button's transparent
                // label still satisfies the 44pt accessibility target.
                .frame(minHeight: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
                .animation(KStyle.selectorTextMotion(reduceMotion), value: selection)
        }
        .buttonStyle(.plain)
        .disabled(state == .disabled)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityAddTraits(isActive ? .isSelected : AccessibilityTraits())
        .accessibilityIdentifier(item.accessibilityIdentifier ?? "k-selector-\(String(describing: item.id))")
    }
}

struct KInputBar: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KInputBar",
        semanticRole: "bottom intent input for chat, admin, and build with one circular 44pt send-or-stop control",
        props: [
            KPrimitiveDescriptors.prop("text", "Binding<String>"),
            KPrimitiveDescriptors.prop("mode", "KInputBarMode", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("statusText", "String?", required: false),
            KPrimitiveDescriptors.prop("disabledReason", "String?", required: false),
            KPrimitiveDescriptors.prop("onSubmit", "() -> Void"),
            KPrimitiveDescriptors.prop("onStop", "(() -> Void)?", required: false),
        ],
        variants: KInputBarMode.allCases.map(\.rawValue),
        usageWhen: [
            "use for one-sentence intents in chat, admin intake, and build intent",
            "use inline text for loading, offline, and error recovery",
        ],
        usageNever: [
            "never add a second primary control beside send or stop",
            "never replace inline errors with alerts or spinners",
        ],
        interruptionClass: .focal,
        maxSimultaneousCues: 2
    )

    @Binding var text: String
    let mode: KInputBarMode
    let state: KPrimitiveInteractionState
    let placeholder: String
    let statusText: String?
    let disabledReason: String?
    let onSubmit: () -> Void
    let onStop: (() -> Void)?

    init(
        text: Binding<String>,
        mode: KInputBarMode = .chat,
        state: KPrimitiveInteractionState = .resting,
        placeholder: String = KPrimitiveCopy.inputPlaceholder,
        statusText: String? = nil,
        disabledReason: String? = nil,
        onSubmit: @escaping () -> Void,
        onStop: (() -> Void)? = nil
    ) {
        _text = text
        self.mode = mode
        self.state = state
        self.placeholder = placeholder
        self.statusText = statusText
        self.disabledReason = disabledReason
        self.onSubmit = onSubmit
        self.onStop = onStop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.inputStatusSpacing) {
            KScrollEdgeFade()

            HStack(alignment: .bottom, spacing: KStyle.inputBarSpacing) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(KStyle.inputFont)
                    .foregroundStyle(Color.white.opacity(KStyle.primaryTextOpacity))
                    .lineLimit(KStyle.inputMinLineCount...mode.maxLineCount)
                    .padding(.horizontal, KStyle.inputHorizontalPadding)
                    .padding(.vertical, KStyle.inputVerticalPadding)
                    .frame(minHeight: KStyle.minimumTapTarget)
                    .kInputFieldTone()
                    .disabled(isInputDisabled)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSubmit {
                            onSubmit()
                        }
                    }
                    .accessibilityLabel(mode.inputAccessibilityLabel)

                Button(action: primaryControlTapped) {
                    Image(systemName: controlSymbol)
                        .font(KStyle.inputControlFont)
                        .frame(width: KStyle.inputControlSize, height: KStyle.inputControlSize)
                        .foregroundStyle(controlForeground)
                        .background {
                            Circle().fill(controlFill)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!primaryControlEnabled)
                .accessibilityLabel(controlAccessibilityLabel)
            }
            .padding(.horizontal, KStyle.inputSidePadding)
            .padding(.trailing, KStyle.inputTrailingPadding)

            if let captionText {
                KMonoCaption(captionText, variant: captionVariant, state: state)
                    .padding(.horizontal, KStyle.inputSidePadding)
                    .padding(.trailing, KStyle.inputTrailingPadding)
            }
        }
        .padding(.bottom, KStyle.inputBottomPadding)
        .kAnimated(value: state)
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInputDisabled: Bool {
        state.disablesInput || disabledReason != nil
    }

    private var canSubmit: Bool {
        !isInputDisabled && state != .loading && !normalizedText.isEmpty
    }

    private var canStop: Bool {
        state == .loading && onStop != nil
    }

    private var primaryControlEnabled: Bool {
        canSubmit || canStop
    }

    private var controlSymbol: String {
        state == .loading ? "stop.fill" : "arrow.up"
    }

    private var controlAccessibilityLabel: String {
        state == .loading ? "stop" : mode.submitAccessibilityLabel
    }

    private var controlForeground: Color {
        primaryControlEnabled
            ? Color.black.opacity(KStyle.primaryControlTextOpacity)
            : Color.white.opacity(KStyle.tertiaryTextOpacity)
    }

    private var controlFill: Color {
        if state == .loading {
            return Color.white.opacity(KStyle.controlPendingFillOpacity)
        }
        return primaryControlEnabled
            ? Color.white.opacity(KStyle.controlEnabledFillOpacity)
            : Color.white.opacity(KStyle.controlDisabledFillOpacity)
    }

    private var captionText: String? {
        if let disabledReason {
            return disabledReason.lowercased()
        }
        if state == .offline {
            return KCopy.offlineRetrying
        }
        return statusText?.lowercased()
    }

    private var captionVariant: KMonoCaptionVariant {
        state == .error ? .inlineError : .status
    }

    private func primaryControlTapped() {
        if state == .loading {
            onStop?()
        } else {
            onSubmit()
        }
    }
}

struct KChecklistRow: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KChecklistRow",
        semanticRole: "single quiet checklist item with bullet, lowercase title, and done state",
        props: [
            KPrimitiveDescriptors.prop("title", "String"),
            KPrimitiveDescriptors.prop("isDone", "Bool"),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("foregroundColor", "Color", required: false),
            KPrimitiveDescriptors.prop("onToggle", "() -> Void"),
        ],
        variants: ["todo", "done"],
        usageWhen: [
            "use for cadence ops checklist lines",
            "use when the entire row should be a 44pt toggle target",
        ],
        usageNever: [
            "never use a checkbox chrome glyph",
            "never truncate the checklist title",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 1
    )

    let title: String
    let isDone: Bool
    let state: KPrimitiveInteractionState
    let foregroundColor: Color
    let onToggle: () -> Void

    init(
        title: String,
        isDone: Bool,
        state: KPrimitiveInteractionState = .resting,
        foregroundColor: Color = .white,
        onToggle: @escaping () -> Void
    ) {
        self.title = title
        self.isDone = isDone
        self.state = state
        self.foregroundColor = foregroundColor
        self.onToggle = onToggle
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                Text(KPrimitiveCopy.middleDot)
                    .kFont(.monoCaption)
                    .foregroundStyle(foregroundColor.opacity(rowOpacity))
                    .accessibilityHidden(true)
                Text(title.lowercased())
                    .kFont(.monoCaption)
                    .foregroundStyle(foregroundColor.opacity(rowOpacity))
                    .strikethrough(isDone, color: foregroundColor.opacity(KStyle.quaternaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: .zero)
            }
            .frame(minHeight: KStyle.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.disablesAction)
        .kAnimated(value: state)
    }

    private var rowOpacity: Double {
        if isDone { return KStyle.quaternaryTextOpacity }
        return state.disablesAction ? KStyle.quaternaryTextOpacity : KStyle.tertiaryTextOpacity
    }
}

struct KVerdictBar: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KVerdictBar",
        semanticRole: "fixed mind verdict register: filled act-on, hairline nod, naked junk/archive",
        props: [
            KPrimitiveDescriptors.prop("pendingVerdict", "MindVerdict?", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("errorText", "String?", required: false),
            KPrimitiveDescriptors.prop("onVerdict", "(MindVerdict) -> Void"),
            KPrimitiveDescriptors.prop("onRetry", "() -> Void"),
        ],
        variants: ["mind"],
        usageWhen: [
            "use only for mind verdict bursts",
            "use fixed 56pt targets that do not move between outputs",
        ],
        usageNever: [
            "never give the three verdicts equal bordered treatment",
            "never change the left-to-right order",
        ],
        interruptionClass: .focal,
        maxSimultaneousCues: 1
    )

    let pendingVerdict: MindVerdict?
    let state: KPrimitiveInteractionState
    let errorText: String?
    let onVerdict: (MindVerdict) -> Void
    let onRetry: () -> Void

    init(
        pendingVerdict: MindVerdict? = nil,
        state: KPrimitiveInteractionState = .resting,
        errorText: String? = nil,
        onVerdict: @escaping (MindVerdict) -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.pendingVerdict = pendingVerdict
        self.state = state
        self.errorText = errorText
        self.onVerdict = onVerdict
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KStyle.verdictButtonSpacing) {
            HStack(spacing: KStyle.verdictButtonSpacing) {
                ForEach(MindVerdict.buttonOrder) { verdict in
                    KVerdictButton(
                        verdict: verdict,
                        isPending: pendingVerdict == verdict,
                        isDisabled: buttonsDisabled,
                        state: state,
                        action: { onVerdict(verdict) }
                    )
                }
            }

            if let errorText {
                VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                    KMonoCaption(errorText, variant: .inlineError, state: .error)
                    KActRow(
                        actions: [
                            KActItem(
                                id: "retry",
                                label: "retry",
                                accessibilityIdentifier: "mind-verdict-retry"
                            ),
                        ],
                        variant: .mindFeedback,
                        onSelect: { _ in onRetry() }
                    )
                }
            }
        }
    }

    private var buttonsDisabled: Bool {
        pendingVerdict != nil || state.disablesAction
    }
}

private struct KVerdictButton: View {
    let verdict: MindVerdict
    let isPending: Bool
    let isDisabled: Bool
    let state: KPrimitiveInteractionState
    let action: () -> Void

    private var variant: KOptionButtonVariant {
        switch verdict {
        case .actOn: return .primaryFilled
        case .nod:   return .secondaryHairline
        case .junk:  return .archiveNaked
        }
    }

    var body: some View {
        KOptionButton(
            label: verdict.rawValue,
            variant: variant,
            isEnabled: !isDisabled || isPending,
            isPending: isPending,
            state: isPending ? .loading : state,
            accessibilityIdentifier: "mind-verdict-\(verdict.rawValue)",
            onSelect: action
        )
        .frame(maxWidth: .infinity, minHeight: KStyle.verdictButtonHeight)
    }
}

struct KEvidenceBlock: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KEvidenceBlock",
        semanticRole: "monospaced horizontally scrollable evidence, diff, or log block",
        props: [
            KPrimitiveDescriptors.prop("text", "String"),
            KPrimitiveDescriptors.prop("variant", "KEvidenceBlockVariant", required: false),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
        ],
        variants: KEvidenceBlockVariant.allCases.map(\.rawValue),
        interactionStates: KPrimitiveDescriptors.evidenceStates,
        usageWhen: [
            "use for build gate output, diffs, log tails, and evidence ids that need monospaced scanning",
            "use written empty, loading, error, and offline states",
        ],
        usageNever: [
            "never use for prose paragraphs",
            "never shimmer or animate loading text",
        ],
        interruptionClass: .focal,
        maxSimultaneousCues: 1
    )

    let text: String
    let variant: KEvidenceBlockVariant
    let state: KPrimitiveInteractionState

    init(
        text: String,
        variant: KEvidenceBlockVariant = .mono,
        state: KPrimitiveInteractionState = .resting
    ) {
        self.text = text
        self.variant = variant
        self.state = state
    }

    var body: some View {
        ScrollView(.horizontal) {
            Text(displayText)
                .kFont(.evidence)
                .foregroundStyle(foregroundColor)
                .fixedSize(horizontal: true, vertical: false)
                .padding(KStyle.evidencePadding)
                .textSelection(.enabled)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kGlassCardTone()
        .kAnimated(value: state)
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return text
        }
        switch state {
        case .loading:
            return KPrimitiveCopy.loading
        case .error:
            return KPrimitiveCopy.errorRetry
        case .offline:
            return KCopy.offlineRetrying
        case .resting, .active, .disabled, .empty, .stale:
            return KPrimitiveCopy.empty
        }
    }

    private var foregroundColor: Color {
        state == .error
            ? KStyle.inlineError.opacity(KStyle.errorTextOpacity)
            : Color.white.opacity(KStyle.secondaryTextOpacity)
    }
}

struct KSummaryStrip: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveDescriptors.component(
        name: "KSummaryStrip",
        semanticRole: "waiting-line summary of tappable segments separated by middle dots",
        props: [
            KPrimitiveDescriptors.prop("segments", "[KWaitingSummarySegment]"),
            KPrimitiveDescriptors.prop("state", "KPrimitiveInteractionState", required: false),
            KPrimitiveDescriptors.prop("onSelect", "(KAppTab) -> Void"),
        ],
        variants: ["waiting-line"],
        usageWhen: [
            "use for the glance answer to what is waiting on the founder",
            "use when each segment can route directly to the relevant tab",
        ],
        usageNever: [
            "never show counts as badges",
            "never use as a general breadcrumb or nav bar",
        ],
        interruptionClass: .peripheral,
        maxSimultaneousCues: 3
    )

    let segments: [KWaitingSummarySegment]
    let state: KPrimitiveInteractionState
    let onSelect: (KAppTab) -> Void

    init(
        segments: [KWaitingSummarySegment],
        state: KPrimitiveInteractionState = .resting,
        onSelect: @escaping (KAppTab) -> Void
    ) {
        self.segments = segments
        self.state = state
        self.onSelect = onSelect
    }

    var body: some View {
        if !segments.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.summarySpacing) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Button {
                        onSelect(segment.tab)
                    } label: {
                        Text(segment.label.lowercased())
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(state == .active ? KStyle.secondaryTextOpacity : state.quietTextOpacity))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: KStyle.minimumTapTarget)
                    .disabled(state.disablesAction)

                    if index < segments.count - 1 {
                        Text(KPrimitiveCopy.middleDot)
                            .kFont(.monoCaption)
                            .foregroundStyle(Color.white.opacity(KStyle.tertiaryTextOpacity))
                            .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: .zero)
            }
            .transition(.opacity)
            .kAnimated(value: state)
        }
    }
}
