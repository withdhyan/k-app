import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════════════
// KNavBar — the floating root nav (blessed 2026-08-03 mock).
//
//   compact width  ->  a capsule of icons floating at the bottom-centre,
//                      24pt above the safe-area bottom (bottom bar).
//   regular width  ->  a vertical capsule pinned to the right edge, centred
//                      (side rail).
//
// Selection is quiet: the active tab is an ink-bright glyph inside a hairline
// ring — never a filled circle, never an accent hue. Unread state is a small
// dot beside the glyph, carrying the same waiting semantics as the old text
// strip (KTabStripModel owns that logic, shared here). KNavBar is additive to
// the catalog: KTabStrip stays the inset-track text selector; this is the
// icon nav the mock rules. Every value below reads a KStyle token.
// ════════════════════════════════════════════════════════════════════════

/// The circle-family glyph for each tab, drawn as a single composite stroke in
/// the mock's 24-unit viewBox and scaled into the icon frame. One shape, one
/// stroke — so weight and round joins stay uniform across every glyph.
struct KNavIconShape: Shape {
    let tab: KAppTab

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = rect.width / KStyle.navIconViewBox

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
            path.move(to: point(x0, y0))
            path.addLine(to: point(x1, y1))
        }
        func polyline(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: point(first.0, first.1))
            for next in points.dropFirst() {
                path.addLine(to: point(next.0, next.1))
            }
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            path.addEllipse(in: CGRect(
                x: rect.minX + (cx - r) * scale,
                y: rect.minY + (cy - r) * scale,
                width: 2 * r * scale,
                height: 2 * r * scale
            ))
        }

        // The founder-locked set (2026-08-03): pulse · continuous bubble ·
        // node-branch · spiral-dot mind · lung arcs bio · cut-terminal admin.
        switch tab {
        case .cadence: // pulse
            polyline([(2.5, 12), (6, 12), (9, 4.5), (14, 19), (16.5, 12), (21.5, 12)])
        case .chat: // continuous-line bubble, tail folds inward
            path.move(to: point(19.5, 15))
            path.addArc(
                center: point(12, 12),
                radius: 8 * scale,
                startAngle: .degrees(22),
                endAngle: .degrees(338),
                clockwise: false
            )
            path.addQuadCurve(to: point(20.5, 19.5), control: point(19, 18.5))
        case .build: // branch: two nodes, stem, quarter arc
            line(7, 21, 7, 7)
            circle(7, 4.5, 2)
            circle(17, 7.5, 2)
            path.move(to: point(17, 10.5))
            path.addQuadCurve(to: point(7, 15), control: point(15, 15))
        case .mind: // spiral into the dot
            path.move(to: point(12, 21))
            path.addArc(
                center: point(12, 12),
                radius: 9 * scale,
                startAngle: .degrees(90),
                endAngle: .degrees(40),
                clockwise: false
            )
            path.addQuadCurve(to: point(14.4, 14.6), control: point(19.5, 16.5))
            path.addArc(
                center: point(12.8, 13.2),
                radius: 2.1 * scale,
                startAngle: .degrees(40),
                endAngle: .degrees(320),
                clockwise: false
            )
        case .bio: // lung arcs
            path.move(to: point(10, 5))
            path.addLine(to: point(10, 11))
            path.addQuadCurve(to: point(4, 18), control: point(10, 17))
            path.move(to: point(14, 5))
            path.addLine(to: point(14, 11))
            path.addQuadCurve(to: point(20, 18), control: point(14, 17))
        case .admin: // two cut lines, offset
            line(5, 9, 15, 9)
            line(9, 15, 19, 15)
        }

        return path
    }
}

/// A single nav glyph at the requested size, stroked in the current foreground
/// colour with round joins and mock-faithful weight.
struct KNavIcon: View {
    let tab: KAppTab
    let size: CGFloat

    var body: some View {
        KNavIconShape(tab: tab)
            .stroke(
                style: StrokeStyle(
                    lineWidth: KStyle.navIconStrokeWidth(iconSize: size),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
    }
}

struct KNavBar: View, KPrimitiveComponent {
    static let primitiveDescriptor = KPrimitiveComponentDescriptor(
        name: "KNavBar",
        semanticRole: "floating root nav — circle-family icon capsule, bottom bar on compact width and right side rail on regular width, with quiet ink-bright ring selection",
        props: [
            KPrimitivePropDescriptor(name: "selection", type: "Binding<KAppTab>", required: true),
            KPrimitivePropDescriptor(name: "axis", type: "Axis", required: false),
            KPrimitivePropDescriptor(name: "cadenceNeedsAttention", type: "Bool", required: false),
            KPrimitivePropDescriptor(name: "chatHasUnread", type: "Bool", required: false),
            KPrimitivePropDescriptor(name: "openBuildCards", type: "Int", required: false),
            KPrimitivePropDescriptor(name: "unjudgedMindOutputs", type: "Int", required: false),
            KPrimitivePropDescriptor(name: "adminDueTodayItems", type: "Int", required: false),
            KPrimitivePropDescriptor(name: "staleTabs", type: "Set<KAppTab>", required: false),
            KPrimitivePropDescriptor(name: "notificationItems", type: "[KNotification]", required: false),
        ],
        variants: ["bottom-bar", "side-rail"],
        interactionStates: [
            KPrimitiveInteractionState.resting.rawValue,
            KPrimitiveInteractionState.active.rawValue,
            KPrimitiveInteractionState.disabled.rawValue,
            KPrimitiveInteractionState.loading.rawValue,
            KPrimitiveInteractionState.error.rawValue,
            KPrimitiveInteractionState.offline.rawValue,
        ],
        usageWhen: [
            "use as the app's floating root nav",
            "bottom bar on compact width, right side rail on regular width",
        ],
        usageNever: [
            "never fill the selected item — selection is an ink-bright glyph plus a hairline ring",
            "never add accent tint or numbered badges",
            "never use for in-panel navigation",
        ],
        calmTech: KPrimitiveCalmTech(interruptionClass: .ambient, maxSimultaneousCues: 5),
        usesTokenOnlyStyling: true
    )

    @Binding var selection: KAppTab
    let axis: Axis
    let cadenceNeedsAttention: Bool
    let chatHasUnread: Bool
    let openBuildCards: Int
    let unjudgedMindOutputs: Int
    let adminDueTodayItems: Int
    let staleTabs: Set<KAppTab>
    let notificationItems: [KNotification]
    let state: KPrimitiveInteractionState

    init(
        selection: Binding<KAppTab>,
        axis: Axis = .horizontal,
        cadenceNeedsAttention: Bool = false,
        chatHasUnread: Bool = false,
        openBuildCards: Int = .zero,
        unjudgedMindOutputs: Int = .zero,
        adminDueTodayItems: Int = .zero,
        staleTabs: Set<KAppTab> = [],
        notificationItems: [KNotification] = [],
        state: KPrimitiveInteractionState = .resting
    ) {
        _selection = selection
        self.axis = axis
        self.cadenceNeedsAttention = cadenceNeedsAttention
        self.chatHasUnread = chatHasUnread
        self.openBuildCards = openBuildCards
        self.unjudgedMindOutputs = unjudgedMindOutputs
        self.adminDueTodayItems = adminDueTodayItems
        self.staleTabs = staleTabs
        self.notificationItems = notificationItems
        self.state = state
    }

    private var isRegular: Bool { axis == .vertical }
    private var itemSize: CGFloat { isRegular ? KStyle.navRegularItemSize : KStyle.navCompactItemSize }
    private var iconSize: CGFloat { isRegular ? KStyle.navRegularIconSize : KStyle.navCompactIconSize }
    private var itemSpacing: CGFloat { isRegular ? KStyle.navRegularItemSpacing : KStyle.navCompactItemSpacing }
    private var verticalPadding: CGFloat { isRegular ? KStyle.navRegularVerticalPadding : KStyle.navCompactVerticalPadding }
    private var horizontalPadding: CGFloat { isRegular ? KStyle.navRegularHorizontalPadding : KStyle.navCompactHorizontalPadding }

    private var items: [KTabStripItem] {
        KTabStripModel.items(
            active: selection,
            cadenceNeedsAttention: cadenceNeedsAttention,
            chatHasUnread: chatHasUnread,
            openBuildCards: openBuildCards,
            unjudgedMindOutputs: unjudgedMindOutputs,
            adminDueTodayItems: adminDueTodayItems,
            staleTabs: staleTabs,
            notificationItems: notificationItems
        )
    }

    var body: some View {
        capsule
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background {
                Capsule(style: .continuous)
                    .fill(KStyle.navBarGround.opacity(KStyle.navBarGroundOpacity))
                    .background(KStyle.hazeMaterial.material, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(KStyle.hairlineOpacity),
                                lineWidth: KStyle.hairlineWidth
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(KStyle.navBarShadowOpacity),
                radius: KStyle.navBarShadowRadius,
                y: KStyle.navBarShadowY
            )
            .tint(.white)
            .opacity(state.contentOpacity)
            .kAnimated(value: selection)
            .kAnimated(value: state)
    }

    @ViewBuilder
    private var capsule: some View {
        if isRegular {
            VStack(spacing: itemSpacing) { itemButtons }
        } else {
            HStack(spacing: itemSpacing) { itemButtons }
        }
    }

    private var itemButtons: some View {
        ForEach(items) { item in
            Button {
                selection = item.tab
            } label: {
                itemLabel(item)
            }
            .buttonStyle(.plain)
            .disabled(state == .disabled)
            .accessibilityLabel("\(item.title) tab")
            .accessibilityValue(hasStatusDot(for: item) ? "status" : "quiet")
            .accessibilityAddTraits(item.isActive ? .isSelected : AccessibilityTraits())
            .accessibilityHint(hasStatusDot(for: item) ? "has updates" : "")
            .accessibilityIdentifier("k-nav-\(item.tab.rawValue)")
        }
    }

    private func itemLabel(_ item: KTabStripItem) -> some View {
        KNavIcon(tab: item.tab, size: iconSize)
            .foregroundStyle(iconColor(for: item))
            .frame(width: itemSize, height: itemSize)
            .background {
                if item.isActive {
                    Circle().strokeBorder(
                        Color.white.opacity(KStyle.navSelectedRingOpacity),
                        lineWidth: KStyle.hairlineWidth
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if hasStatusDot(for: item) {
                    KNavStatusDot(opacityScale: opacityScale(for: item))
                }
            }
            .contentShape(Circle())
    }

    private func hasStatusDot(for item: KTabStripItem) -> Bool {
        KNavStatusDotLogic.isShown(
            for: item,
            staleTabs: staleTabs,
            notificationItems: notificationItems
        )
    }

    private func opacityScale(for item: KTabStripItem) -> Double {
        KNavStatusDotLogic.opacityScale(
            for: item,
            staleTabs: staleTabs,
            notificationItems: notificationItems
        )
    }

    private func iconColor(for item: KTabStripItem) -> Color {
        Color.white.opacity(item.isActive ? KStyle.navSelectedIconOpacity : KStyle.navIdleIconOpacity)
    }
}

/// The one root-nav dot grammar: token-sized, white ink, and one quiet breath.
enum KNavStatusDotLogic {
    /// The cadence tab's indicator is the root-nav standard. Notifications
    /// use this exact renderer too, so a dot never acquires a tab-specific
    /// size, offset, or breath.
    static var size: CGFloat { KStyle.navStatusDotSize }

    static func isShown(for item: KTabStripItem, staleTabs: Set<KAppTab>) -> Bool {
        item.showsDot || staleTabs.contains(item.tab)
    }

    static func isShown(
        for item: KTabStripItem,
        staleTabs: Set<KAppTab>,
        notificationItems: [KNotification]
    ) -> Bool {
        guard !notificationItems.isEmpty else {
            return isShown(for: item, staleTabs: staleTabs)
        }
        return KNotificationViewLogic.status(for: item.tab, in: notificationItems).showsDot
    }

    static func opacityScale(for item: KTabStripItem, staleTabs: Set<KAppTab>) -> Double {
        guard item.showsDot else {
            return staleTabs.contains(item.tab) ? KStyle.staleDotFactor : .zero
        }
        return item.dotOpacity / KStyle.notifStatusDotOpacity
    }

    static func opacityScale(
        for item: KTabStripItem,
        staleTabs: Set<KAppTab>,
        notificationItems: [KNotification]
    ) -> Double {
        guard !notificationItems.isEmpty else {
            return opacityScale(for: item, staleTabs: staleTabs)
        }
        return KNotificationViewLogic.status(for: item.tab, in: notificationItems).opacityScale
    }

    static func opacity(
        at date: Date,
        reduceMotion: Bool,
        scale: Double = KStyle.fullOpacity
    ) -> Double {
        KStyle.navStatusDotPulseOpacity(at: date, reduceMotion: reduceMotion) * scale
    }
}

private struct KNavStatusDot: View {
    let opacityScale: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            dot(opacity: KNavStatusDotLogic.opacity(
                at: Date(),
                reduceMotion: true,
                scale: opacityScale
            ))
        } else {
            TimelineView(.periodic(from: Date(), by: KStyle.navStatusDotTickInterval)) { context in
                dot(opacity: KNavStatusDotLogic.opacity(
                    at: context.date,
                    reduceMotion: false,
                    scale: opacityScale
                ))
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
    }

    private func dot(opacity: Double) -> some View {
        Circle()
            .fill(KStyle.navStatusDotColor)
            .frame(width: KNavStatusDotLogic.size, height: KNavStatusDotLogic.size)
            .opacity(opacity)
            .offset(x: KStyle.navStatusDotOffsetX, y: KStyle.navStatusDotOffsetY)
            .accessibilityHidden(true)
    }
}

enum KNotificationKind: Equatable, Codable, Sendable {
    case cardRaised
    case cardAnswered
    case planCompleted
    case andon
    case buildCards
    case mindUnjudged
    case adminDue
    case cadenceAttention
    case chatUnread
    case staleness(KAppTab)
    case unknown(String)

    init(rawValue: String) {
        let normalized = rawValue.lowercased()
        switch normalized {
        case "card-raised": self = .cardRaised
        case "card-answered": self = .cardAnswered
        case "plan-completed": self = .planCompleted
        case "andon": self = .andon
        case "build-cards": self = .buildCards
        case "mind-unjudged": self = .mindUnjudged
        case "admin-due": self = .adminDue
        case "cadence-attention": self = .cadenceAttention
        case "chat-unread": self = .chatUnread
        default: self = .unknown(rawValue)
        }
        if normalized.hasPrefix("staleness-"),
           let tab = KAppTab(rawValue: String(normalized.dropFirst("staleness-".count))) {
            self = .staleness(tab)
        } else if normalized.hasPrefix("stale-"),
                  let tab = KAppTab(rawValue: String(normalized.dropFirst("stale-".count))) {
            // Additive wire tolerance for the shorter fixture spelling.
            self = .staleness(tab)
        }
    }

    var rawValue: String {
        switch self {
        case .cardRaised: return "card-raised"
        case .cardAnswered: return "card-answered"
        case .planCompleted: return "plan-completed"
        case .andon: return "andon"
        case .buildCards: return "build-cards"
        case .mindUnjudged: return "mind-unjudged"
        case .adminDue: return "admin-due"
        case .cadenceAttention: return "cadence-attention"
        case .chatUnread: return "chat-unread"
        case .staleness(let tab): return "staleness-\(tab.rawValue)"
        case .unknown(let value): return value
        }
    }

    var glyphName: String {
        switch self {
        case .cardRaised: return "rectangle.badge.plus"
        case .cardAnswered: return "rectangle.badge.checkmark"
        case .planCompleted: return "checkmark.circle"
        case .andon: return "exclamationmark.triangle"
        case .buildCards: return "rectangle.stack"
        case .mindUnjudged: return "circle.dotted"
        case .adminDue: return "calendar"
        case .cadenceAttention: return "waveform.path.ecg"
        case .chatUnread: return "bubble"
        case .staleness: return "clock"
        case .unknown: return "bell"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cardRaised: return "build card"
        case .cardAnswered: return "answered card"
        case .planCompleted: return "completed plan"
        case .andon: return "factory alert"
        case .buildCards: return "build cards"
        case .mindUnjudged: return "unjudged mind output"
        case .adminDue: return "admin item due"
        case .cadenceAttention: return "cadence attention"
        case .chatUnread: return "unread chat"
        case .staleness(let tab): return "stale \(tab.title)"
        case .unknown: return "notification"
        }
    }

    var homeTab: KAppTab? {
        switch self {
        case .cardRaised, .cardAnswered, .planCompleted, .buildCards:
            return .build
        case .andon: return nil
        case .mindUnjudged: return .mind
        case .adminDue: return .admin
        case .cadenceAttention: return .cadence
        case .chatUnread: return .chat
        case .staleness(let tab): return tab
        case .unknown: return nil
        }
    }

    var isStaleness: Bool {
        if case .staleness = self { return true }
        return false
    }

    /// Source kinds are local status projections. Server-origin rows such as
    /// `card-raised` remain ordinary notification events, but resolve to the
    /// same home tab and dot grammar.
    var isStatusSource: Bool {
        switch self {
        case .buildCards, .mindUnjudged, .adminDue, .cadenceAttention, .chatUnread:
            return true
        case .cardRaised, .cardAnswered, .planCompleted, .andon, .staleness, .unknown:
            return false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct KNotification: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let kind: KNotificationKind
    let title: String
    let detail: String
    let at: Date
    var seen: Bool

    init(
        id: String,
        kind: KNotificationKind,
        title: String,
        detail: String = "",
        at: Date,
        seen: Bool = false
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.at = at
        self.seen = seen
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case detail
        case at
        case seen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
            kind: try container.decodeIfPresent(KNotificationKind.self, forKey: .kind) ?? .unknown("unknown"),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            detail: try container.decodeIfPresent(String.self, forKey: .detail) ?? "",
            at: KNotificationDateCodec.date(
                from: try container.decodeIfPresent(String.self, forKey: .at)
            ) ?? .distantPast,
            seen: try container.decodeIfPresent(Bool.self, forKey: .seen) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(KNotificationDateCodec.string(from: at), forKey: .at)
        try container.encode(seen, forKey: .seen)
    }

    func markedSeen() -> KNotification {
        var copy = self
        copy.seen = true
        return copy
    }
}

struct KNotificationsEnvelope: Equatable, Codable, Sendable {
    let items: [KNotification]

    init(items: [KNotification] = []) {
        self.items = Self.validItems(items)
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try container.decodeIfPresent([KNotification].self, forKey: .items) ?? [])
    }

    private static func validItems(_ items: [KNotification]) -> [KNotification] {
        items.filter { !$0.id.isEmpty && !$0.title.isEmpty }
    }
}

enum NotificationsWireDecoder {
    static func decode(_ data: Data) throws -> KNotificationsEnvelope {
        try JSONDecoder().decode(KNotificationsEnvelope.self, from: data)
    }
}

protocol NotificationsDataSource: Sendable {
    /// Read-only by design. The future acknowledgement path will be a separate conformance.
    func fetchNotifications() async throws -> [KNotification]
}

struct FixtureNotificationsDataSource: NotificationsDataSource, Sendable {
    enum Fixture: Sendable {
        case attention
        case navDot
        case empty
    }

    let items: [KNotification]

    init(fixture: Fixture = .attention) {
        let payload: Data
        switch fixture {
        case .attention:
            payload = Self.attentionPayload
        case .navDot:
            payload = Self.navDotPayload
        case .empty:
            payload = Self.emptyPayload
        }
        items = (try? NotificationsWireDecoder.decode(payload).items) ?? []
    }

    init(items: [KNotification]) {
        self.items = items
    }

    static let attention = FixtureNotificationsDataSource(fixture: .attention)
    static let navDot = FixtureNotificationsDataSource(fixture: .navDot)
    static let empty = FixtureNotificationsDataSource(fixture: .empty)

    static var launchDefault: FixtureNotificationsDataSource {
        KNavDotDemo.isEnabled ? .navDot : .empty
    }

    func fetchNotifications() async throws -> [KNotification] {
        items
    }

    private static let attentionPayload = Data(#"""
    {
      "items": [
        {
          "id": "fixture-card-raised",
          "kind": "card-raised",
          "title": "choose the next build slice",
          "detail": "a build card is waiting",
          "at": "2026-08-09T02:00:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-plan-completed",
          "kind": "plan-completed",
          "title": "the evening plan finished",
          "detail": "the factory closed the plan",
          "at": "2026-08-09T01:00:00.000Z",
          "seen": true
        },
        {
          "id": "fixture-andon",
          "kind": "andon",
          "title": "the build lane needs a look",
          "detail": "the factory raised an alert",
          "at": "2026-08-08T23:00:00.000Z",
          "seen": false
        }
      ]
    }
    """#.utf8)

    /// Capture-only mixed state: every tab has one explicit source row, while
    /// bio's stale row stays seen so its dot demonstrates the dimmer rather
    /// than pretending stale data is new work.
    private static let navDotPayload = Data(#"""
    {
      "items": [
        {
          "id": "fixture-cadence-attention",
          "kind": "cadence-attention",
          "title": "cadence needs attention",
          "detail": "a cadence value slipped",
          "at": "2026-08-10T07:05:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-chat-unread",
          "kind": "chat-unread",
          "title": "chat has unread messages",
          "detail": "k left a reply",
          "at": "2026-08-10T07:04:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-build-card",
          "kind": "build-cards",
          "title": "choose the next build slice",
          "detail": "a build card is waiting",
          "at": "2026-08-10T07:03:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-mind-unjudged",
          "kind": "mind-unjudged",
          "title": "1 mind output to judge",
          "detail": "a verdict is waiting",
          "at": "2026-08-10T07:02:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-admin-due",
          "kind": "admin-due",
          "title": "1 admin item due",
          "detail": "today's intake is waiting",
          "at": "2026-08-10T07:01:00.000Z",
          "seen": false
        },
        {
          "id": "fixture-staleness-bio",
          "kind": "staleness-bio",
          "title": "bio is stale",
          "detail": "last glance is cached",
          "at": "2026-08-10T07:00:00.000Z",
          "seen": true
        }
      ]
    }
    """#.utf8)

    private static let emptyPayload = Data(#"{"items":[]}"#.utf8)
}

enum KNavDotDemo {
    static let launchArgument = "-navdotdemo"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum KNotificationRelativeTime {
    static func text(from date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= .zero else { return "soon" }

        let minute: TimeInterval = 60
        let hour = minute * 60
        let day = hour * 24
        let week = day * 7

        if elapsed < minute { return "now" }
        if elapsed < hour { return "\(Int(elapsed / minute))m" }
        if elapsed < day { return "\(Int(elapsed / hour))h" }
        if elapsed < day * 2 { return "yesterday" }
        if elapsed < week { return "\(Int(elapsed / day))d" }
        return "\(Int(elapsed / week))w"
    }
}

struct KTabNotificationStatus: Equatable, Sendable {
    let hasUnseen: Bool
    let isStale: Bool

    var showsDot: Bool { hasUnseen || isStale }

    var opacityScale: Double {
        isStale ? KStyle.staleDotFactor : KStyle.fullOpacity
    }
}

enum KNotificationViewLogic {
    static func unseen(_ items: [KNotification]) -> [KNotification] {
        items.filter { !$0.seen && !$0.kind.isStaleness }
    }

    static func hasUnseen(_ items: [KNotification]) -> Bool {
        !unseen(items).isEmpty
    }

    static func items(for tab: KAppTab, in items: [KNotification]) -> [KNotification] {
        items.filter { $0.kind.homeTab == tab }
    }

    static func unseen(for tab: KAppTab, in items: [KNotification]) -> [KNotification] {
        KNotificationViewLogic.items(for: tab, in: items).filter { !$0.seen && !$0.kind.isStaleness }
    }

    static func status(for tab: KAppTab, in items: [KNotification]) -> KTabNotificationStatus {
        KTabNotificationStatus(
            hasUnseen: !unseen(for: tab, in: items).isEmpty,
            isStale: KNotificationViewLogic.items(for: tab, in: items).contains { $0.kind.isStaleness }
        )
    }

    static func statusSources(
        cadenceNeedsAttention: Bool = false,
        chatHasUnread: Bool = false,
        openBuildCards: Int = .zero,
        unjudgedMindOutputs: Int = .zero,
        adminDueTodayItems: Int = .zero,
        staleTabs: Set<KAppTab> = [],
        now: Date = Date()
    ) -> [KNotification] {
        var rows: [KNotification] = []
        if cadenceNeedsAttention {
            rows.append(statusSource(.cadenceAttention, title: "cadence needs attention", at: now))
        }
        if chatHasUnread {
            rows.append(statusSource(.chatUnread, title: "chat has unread messages", at: now))
        }
        if openBuildCards > 0 {
            rows.append(statusSource(
                .buildCards,
                title: "\(openBuildCards) \(openBuildCards == 1 ? "build card" : "build cards") waiting",
                at: now
            ))
        }
        if unjudgedMindOutputs > 0 {
            rows.append(statusSource(
                .mindUnjudged,
                title: "\(unjudgedMindOutputs) mind \(unjudgedMindOutputs == 1 ? "output" : "outputs") to judge",
                at: now
            ))
        }
        if adminDueTodayItems > 0 {
            rows.append(statusSource(
                .adminDue,
                title: "\(adminDueTodayItems) admin \(adminDueTodayItems == 1 ? "item" : "items") due",
                at: now
            ))
        }
        for tab in KAppTab.allCases where staleTabs.contains(tab) {
            rows.append(KNotification(
                id: statusID(for: .staleness(tab)),
                kind: .staleness(tab),
                title: "\(tab.title) is stale",
                at: now,
                seen: true
            ))
        }
        return rows
    }

    static func statusSource(
        _ kind: KNotificationKind,
        title: String,
        at: Date,
        seen: Bool = false
    ) -> KNotification {
        KNotification(
            id: statusID(for: kind),
            kind: kind,
            title: title,
            at: at,
            seen: seen
        )
    }

    static func statusID(for kind: KNotificationKind) -> String {
        "status-\(kind.rawValue)"
    }

    static func markSeen(id: String, in items: [KNotification]) -> [KNotification] {
        items.map { $0.id == id ? $0.markedSeen() : $0 }
    }

    static func showsEmptyState(isExpanded: Bool, items: [KNotification]) -> Bool {
        isExpanded && items.isEmpty
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var items: [KNotification] = []
    @Published private(set) var isExpanded = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorText: String?

    private let dataSource: NotificationsDataSource
    private var remoteItems: [KNotification] = []
    private var statusItems: [KNotification] = []
    private var localSeenIDs: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    init(dataSource: NotificationsDataSource, initiallyExpanded: Bool = false) {
        self.dataSource = dataSource
        isExpanded = initiallyExpanded
    }

    var unseenItems: [KNotification] {
        KNotificationViewLogic.unseen(items)
    }

    var hasUnseen: Bool {
        !unseenItems.isEmpty
    }

    /// A stale tab is still a useful peripheral cue even when every event has
    /// been seen. The nav status control and the unfurl use this same answer.
    var hasStatus: Bool {
        hasUnseen || KAppTab.allCases.contains {
            KNotificationViewLogic.status(for: $0, in: items).isStale
        }
    }

    func status(for tab: KAppTab) -> KTabNotificationStatus {
        KNotificationViewLogic.status(for: tab, in: items)
    }

    func unseenItems(for tab: KAppTab) -> [KNotification] {
        KNotificationViewLogic.unseen(for: tab, in: items)
    }

    func setStatus(
        _ kind: KNotificationKind,
        active: Bool,
        count: Int = 1,
        at: Date = Date()
    ) {
        guard kind.isStatusSource, !KNavDotDemo.isEnabled else { return }
        let id = KNotificationViewLogic.statusID(for: kind)
        if !active || count <= 0 {
            statusItems.removeAll { $0.id == id }
            localSeenIDs.remove(id)
            rebuildItems()
            return
        }

        let title: String
        switch kind {
        case .cadenceAttention:
            title = "cadence needs attention"
        case .chatUnread:
            title = "chat has unread messages"
        case .buildCards:
            title = "\(count) \(count == 1 ? "build card" : "build cards") waiting"
        case .mindUnjudged:
            title = "\(count) mind \(count == 1 ? "output" : "outputs") to judge"
        case .adminDue:
            title = "\(count) admin \(count == 1 ? "item" : "items") due"
        case .cardRaised, .cardAnswered, .planCompleted, .andon, .staleness, .unknown:
            return
        }

        let seen = localSeenIDs.contains(id)
        let row = KNotificationViewLogic.statusSource(kind, title: title, at: at, seen: seen)
        if let index = statusItems.firstIndex(where: { $0.id == id }) {
            statusItems[index] = row
        } else {
            statusItems.append(row)
        }
        rebuildItems()
    }

    func setStale(_ tab: KAppTab, isStale: Bool, at: Date = Date()) {
        let kind = KNotificationKind.staleness(tab)
        let id = KNotificationViewLogic.statusID(for: kind)
        if isStale {
            let row = KNotification(
                id: id,
                kind: kind,
                title: "\(tab.title) is stale",
                at: at,
                seen: true
            )
            if let index = statusItems.firstIndex(where: { $0.id == id }) {
                statusItems[index] = row
            } else {
                statusItems.append(row)
            }
        } else {
            statusItems.removeAll { $0.id == id }
            localSeenIDs.remove(id)
        }
        rebuildItems()
    }

    var showsEmptyState: Bool {
        KNotificationViewLogic.showsEmptyState(isExpanded: isExpanded, items: items)
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        loadErrorText = nil
        if KLoadingPreview.isEnabled { return }
        let source = dataSource
        refreshTask = Task { [weak self] in
            do {
                let fetched = try await source.fetchNotifications()
                guard !Task.isCancelled else { return }
                self?.applyRemote(fetched)
                self?.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.isLoading = false
                if self?.items.isEmpty == true {
                    self?.loadErrorText = KCopy.notificationsUnavailable
                }
            }
        }
    }

    func refreshNow() async {
        refreshTask?.cancel()
        isLoading = true
        loadErrorText = nil
        if KLoadingPreview.isEnabled { return }
        do {
            let fetched = try await dataSource.fetchNotifications()
            guard !Task.isCancelled else { return }
            applyRemote(fetched)
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            if items.isEmpty {
                loadErrorText = KCopy.notificationsUnavailable
            }
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func collapse() {
        isExpanded = false
    }

    func markSeen(id: String) {
        guard let item = items.first(where: { $0.id == id }), !item.seen else { return }
        localSeenIDs.insert(id)
        remoteItems = KNotificationViewLogic.markSeen(id: id, in: remoteItems)
        statusItems = KNotificationViewLogic.markSeen(id: id, in: statusItems)
        rebuildItems()
    }

    @discardableResult
    func select(id: String) -> KAppTab? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        markSeen(id: id)
        collapse()
        return item.kind.homeTab
    }

    private func applyRemote(_ fetched: [KNotification]) {
        let remote = fetched.filter { !$0.id.isEmpty && !$0.title.isEmpty }
        let remoteIDs = Set(remote.map(\.id))
        localSeenIDs.formIntersection(remoteIDs.union(statusItems.map(\.id)))

        // A future ack path can make `seen` durable. Once the read projection
        // confirms that, the local overlay no longer needs to carry the id.
        for item in remote where item.seen {
            localSeenIDs.remove(item.id)
        }

        remoteItems = remote.map { item in
            localSeenIDs.contains(item.id) ? item.markedSeen() : item
        }
        rebuildItems()
    }

    private func rebuildItems() {
        let remoteIDs = Set(remoteItems.map(\.id))
        let statusOnly = statusItems.filter { !remoteIDs.contains($0.id) }
        items = (remoteItems + statusOnly).sorted { left, right in
            if left.at == right.at { return left.id < right.id }
            return left.at > right.at
        }
    }
}

struct NotificationsNavControl: View {
    @ObservedObject var model: NotificationsViewModel
    let axis: Axis
    let onNavigate: (KAppTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.isExpanded {
            expandedContent
                .transition(expandedTransition)
                .animation(KStyle.notifUnfurlMotion(reduceMotion), value: model.isExpanded)
        } else if model.hasStatus || model.isLoading {
            statusButton
                .transition(.opacity)
                .animation(KStyle.notifUnfurlMotion(reduceMotion), value: model.hasStatus)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if axis == .horizontal {
            VStack(alignment: .trailing, spacing: KStyle.notifNavGap) {
                panel
                if model.hasStatus {
                    statusButton
                }
            }
        } else {
            HStack(alignment: .center, spacing: KStyle.notifNavGap) {
                panel
                if model.hasStatus {
                    statusButton
                }
            }
        }
    }

    private var panel: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.notifRowSpacing) {
                if model.isLoading {
                    KLoadingPrimitive(
                        variant: .skeleton,
                        lineCount: 3,
                        label: "loading notifications",
                        accessibilityIdentifier: "notifications-loading"
                    )
                } else if let loadErrorText = model.loadErrorText {
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        KMonoCaption(loadErrorText, variant: .inlineError, state: .offline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: KStyle.smallSpacing)
                        KActRow(
                            actions: [KActItem(id: "retry")],
                            variant: .admin,
                            onSelect: { _ in model.refresh() }
                        )
                    }
                } else if model.items.isEmpty {
                    KMonoCaption(KCopy.notificationsEmpty, variant: .metadata, state: .empty)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notifications-empty")
                } else {
                    ForEach(model.items) { item in
                        NotificationRow(
                            item: item,
                            now: Date(),
                            onSelect: select(item:)
                        )
                    }
                }
            }
            .padding(.trailing, KStyle.minimumTapTarget)
        }
        .frame(width: KStyle.notifPanelWidth)
        .overlay(alignment: .topTrailing) {
            Button {
                model.collapse()
            } label: {
                Image(systemName: "chevron.down")
                    .font(KStyle.monoCaptionFont)
                    .foregroundStyle(KStyle.notifStatusDotColor.opacity(KStyle.notifGlyphOpacity))
                    .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("collapse notifications")
            .accessibilityIdentifier("notifications-collapse")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notifications-unfurl")
    }

    private var statusButton: some View {
        Button {
            model.toggleExpanded()
        } label: {
            KNavStatusDot(opacityScale: KStyle.fullOpacity)
                .frame(width: KStyle.minimumTapTarget, height: KStyle.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("notifications")
        .accessibilityValue(
            model.hasUnseen
                ? "\(model.unseenItems.count) unseen"
                : "stale glance"
        )
        .accessibilityHint("show notifications")
        .accessibilityIdentifier("k-nav-notifications")
    }

    private var expandedTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        if axis == .horizontal {
            return .opacity.combined(with: .offset(y: KStyle.notifUnfurlOffset))
        }
        return .opacity.combined(with: .offset(x: KStyle.notifUnfurlOffset))
    }

    private func select(item: KNotification) {
        if let tab = model.select(id: item.id) {
            onNavigate(tab)
        }
    }
}

private struct NotificationRow: View {
    let item: KNotification
    let now: Date
    let onSelect: (KNotification) -> Void

    private var titleOpacity: Double {
        item.seen ? KStyle.notifSeenOpacity : KStyle.notifTitleOpacity
    }

    var body: some View {
        Button {
            onSelect(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.notifRowSpacing) {
                Image(systemName: item.kind.glyphName)
                    .font(KStyle.notifGlyphFont)
                    .foregroundStyle(KStyle.notifStatusDotColor.opacity(KStyle.notifGlyphOpacity))
                    .frame(width: KStyle.notifGlyphColumnWidth, alignment: .leading)
                    .accessibilityHidden(true)

                Text(item.title)
                    .font(KStyle.contentFont)
                    .foregroundStyle(KStyle.notifStatusDotColor.opacity(titleOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                KMonoCaption(
                    KNotificationRelativeTime.text(from: item.at, now: now),
                    variant: .staleness,
                    state: item.seen ? .disabled : .active
                )
            }
            .padding(.vertical, KStyle.notifRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.kind.accessibilityLabel), \(item.title), \(KNotificationRelativeTime.text(from: item.at, now: now))"
        )
        .accessibilityHint(item.kind.homeTab == .build ? "marks seen and opens build" : "marks seen")
        .accessibilityIdentifier("notification-\(item.id)")
    }
}

private enum KNotificationDateCodec {
    static func date(from value: String?) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: .zero)
        return formatter.string(from: date)
    }
}
