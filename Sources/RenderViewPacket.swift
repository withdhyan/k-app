import Accessibility
import SwiftUI

enum ViewPacketRenderBranch: Equatable {
    case held
    case chatWorker
    case buildStatus
    case buildCard
    case genericText
    case genericTable
    case genericCard
    case genericChart
    case cardCue
    case cardBody
    case cardTranslation
    case k0Decision
    case k0Provenance
    case k0Claim
    case k0Change
    case k0EvalScore
    case k0EvolveReport
    case loopEvidence
    case preview

    /// All 6 k0.* branches, for call sites that previously checked the bare `.k0` prefix.
    static let allK0: [ViewPacketRenderBranch] = [.k0Decision, .k0Provenance, .k0Claim, .k0Change, .k0EvalScore, .k0EvolveReport]

    static let allCards: [ViewPacketRenderBranch] = [.cardCue, .cardBody, .cardTranslation]
}

enum RenderViewPacketContext: Equatable {
    case cardSurface
    case chatStream
}

struct ViewPacketRenderPolicy: Equatable {
    let interruptionClass: KPrimitiveInterruptionClass
    let usesFadeTransition: Bool
    let animatesChanges: Bool
    let dimsSiblings: Bool
}

enum ViewPacketRenderer {
    static func branch(for packet: ViewPacket) -> ViewPacketRenderBranch {
        if packet.shouldRenderHeldState { return .held }

        switch packet.viewType {
        case "chat.worker":
            return .chatWorker
        case "build.status":
            return .buildStatus
        case "build.card":
            return .buildCard
        case "generic.text":
            return .genericText
        case "generic.table":
            return .genericTable
        case "generic.card":
            return .genericCard
        case "generic.chart":
            return .genericChart
        case "card.cue":
            return .cardCue
        case "card.body":
            return .cardBody
        case "card.translation":
            return .cardTranslation
        case "loop.evidence":
            return .loopEvidence
        case "k0.decision":
            return .k0Decision
        case "k0.provenance":
            return .k0Provenance
        case "k0.claim":
            return .k0Claim
        case "k0.change":
            return .k0Change
        case "k0.eval_score":
            return .k0EvalScore
        case "k0.evolve_report":
            return .k0EvolveReport
        default:
            if packet.viewType.hasPrefix("preview.") { return .preview }
            return .genericText
        }
    }

    /// In the chat stream, a `k0.claim` packet renders as the native
    /// `JarvisClaimStreamBlock` only when it carries a warrant; unwarranted claims
    /// fall back to `packetInlineView`. The single source of truth for that gate,
    /// shared by `streamContent` and its tests.
    static func rendersNativeClaimBlock(for packet: ViewPacket) -> Bool {
        branch(for: packet) == .k0Claim && JarvisClaimBlock(packet: packet).isWarrantTagged
    }

    static func exposesActionAffordance(for packet: ViewPacket) -> Bool {
        actionAffordance(for: packet) == .enabled
    }

    static func actionAffordance(for packet: ViewPacket) -> ViewPacketActionAffordance {
        guard packet.action != nil, !packet.shouldRenderHeldState else { return .hidden }
        if packet.isLoopbackOnlyBuildCard { return .disabled(reason: "answer from the mac") }
        return .enabled
    }

    static func visibleTextSequence(for packet: ViewPacket) -> [String] {
        if packet.shouldRenderHeldState {
            return ["surface held", packet.heldStateReason ?? "held by surface decision"]
        }
        if !shouldRender(packet) {
            return []
        }

        var values: [String] = []
        if branch(for: packet) == .chatWorker, let worker = ChatWorkerPacket(packet) {
            values.append(worker.stateLine())
            if let stepText = worker.stepText { values.append(stepText) }
        } else if ViewPacketRenderBranch.allCards.contains(branch(for: packet)),
                  let card = ViewPacketCardPresentation(packet: packet),
                  !card.isSuppressed {
            values.append(contentsOf: card.collapsedVisibleText)
        } else if branch(for: packet) == .buildCard,
           let card = BuildCard(packet: packet),
           let brief = card.brief {
            values.append(contentsOf: briefVisibleText(brief, options: card.options))
        } else if let brief = DecisionBrief.first(in: packet.fields),
                  (ViewPacketRenderBranch.allK0 + [.loopEvidence]).contains(branch(for: packet)) {
            values.append(contentsOf: briefVisibleText(brief, options: []))
        } else if !packet.displayText.isEmpty {
            values.append(packet.displayText)
        }

        if branch(for: packet) == .genericTable {
            let table = ViewPacketTable(packet: packet)
            values.append(contentsOf: table.columns)
            values.append(contentsOf: table.rows.flatMap { $0 })
        }

        if branch(for: packet) == .buildCard, let card = BuildCard(packet: packet), card.brief == nil {
            if let what = card.what { values.append(what) }
            values.append(card.voiceTitle)
            if let body = card.body { values.append(body) }
            if let contrast = card.contrast { values.append(contrast) }
            if let evidenceLine = DecisionEvidenceLineFormatter.line(for: card.evidenceSummary) {
                values.append(evidenceLine)
            }
            values.append(contentsOf: DecisionEvidencePreviewFormatter.lines(for: card.evidencePreviews))
            if let signalExplained = card.signalExplained { values.append(signalExplained) }
            values.append(contentsOf: card.options.flatMap { [$0.label, $0.consequence] })
            if let stakes = card.stakes { values.append(stakes) }
        }

        if !ViewPacketRenderBranch.allCards.contains(branch(for: packet)) {
            values.append(contentsOf: evidenceVisibleLines(for: packet))
        }

        values.append(contentsOf: packet.children.flatMap { visibleTextSequence(for: $0) })
        return values
    }

    private static func briefVisibleText(_ brief: DecisionBrief, options: [BuildCardOption]) -> [String] {
        var values: [String] = []
        if let whyNow = brief.whyNow { values.append(whyNow) }
        if let openQuestion = brief.openQuestion { values.append(openQuestion) }
        values.append(brief.blockerLine)
        values.append(contentsOf: options.flatMap { option -> [String] in
            [option.label, brief.whatHappens(for: option.id) ?? option.consequence]
                .filter { !$0.isEmpty }
        })
        if options.isEmpty {
            values.append(contentsOf: brief.options.compactMap(\.whatHappens))
        }
        if let stakes = brief.stakes { values.append(stakes) }
        return values
    }

    static func evidenceVisibleLines(for packet: ViewPacket) -> [String] {
        MindEvidenceDetailFormatter.lines(
            previews: packet.evidencePreviews,
            evidence: packet.evidence ?? []
        )
    }

    static func shouldRender(_ packet: ViewPacket) -> Bool {
        guard ViewPacketRenderBranch.allCards.contains(branch(for: packet)),
              let card = ViewPacketCardPresentation(packet: packet)
        else { return true }
        return !card.isSuppressed
    }

    static func renderedInterruptionClass(for packet: ViewPacket) -> KPrimitiveInterruptionClass {
        let ceiling = minInterruptionClass(catalogCeiling(for: branch(for: packet)), .peripheral)
        guard let requested = requestedInterruptionClass(for: packet) else { return ceiling }
        let nonFocalRequest = requested == .focal ? KPrimitiveInterruptionClass.peripheral : requested
        return minInterruptionClass(nonFocalRequest, ceiling)
    }

    static func renderPolicy(for packet: ViewPacket) -> ViewPacketRenderPolicy {
        switch renderedInterruptionClass(for: packet) {
        case .ambient:
            return ViewPacketRenderPolicy(
                interruptionClass: .ambient,
                usesFadeTransition: false,
                animatesChanges: false,
                dimsSiblings: false
            )
        case .peripheral:
            return ViewPacketRenderPolicy(
                interruptionClass: .peripheral,
                usesFadeTransition: true,
                animatesChanges: true,
                dimsSiblings: true
            )
        case .focal:
            return ViewPacketRenderPolicy(
                interruptionClass: .peripheral,
                usesFadeTransition: true,
                animatesChanges: true,
                dimsSiblings: true
            )
        }
    }

    private static func catalogCeiling(for branch: ViewPacketRenderBranch) -> KPrimitiveInterruptionClass {
        switch branch {
        case .genericText:
            return .ambient
        case .held, .chatWorker, .buildStatus, .buildCard, .genericTable, .genericCard, .genericChart,
             .cardCue, .cardBody, .cardTranslation,
             .k0Decision, .k0Provenance, .k0Claim, .k0Change, .k0EvalScore, .k0EvolveReport, .loopEvidence, .preview:
            return .peripheral
        }
    }

    private static func requestedInterruptionClass(for packet: ViewPacket) -> KPrimitiveInterruptionClass? {
        for source in [packet.surfaceDecision, packet.fields, packet.provenance] {
            guard let source else { continue }
            for key in ["interruptionClass", "interruption", "interruption_class"] {
                if let value = source[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                   let interruptionClass = KPrimitiveInterruptionClass(rawValue: value) {
                    return interruptionClass
                }
            }
        }
        return nil
    }

    private static func minInterruptionClass(
        _ left: KPrimitiveInterruptionClass,
        _ right: KPrimitiveInterruptionClass
    ) -> KPrimitiveInterruptionClass {
        rank(left) <= rank(right) ? left : right
    }

    private static func rank(_ value: KPrimitiveInterruptionClass) -> Int {
        switch value {
        case .ambient:
            return 0
        case .peripheral:
            return 1
        case .focal:
            return 2
        }
    }
}

enum ViewPacketActionAffordance: Equatable {
    case hidden
    case enabled
    case disabled(reason: String)
}

enum ViewPacketCardKind: String, CaseIterable, Equatable {
    case cue = "card.cue"
    case body = "card.body"
    case translation = "card.translation"

    var fallbackAnchor: String {
        switch self {
        case .cue:
            return "a cue from k"
        case .body:
            return "a body signal"
        case .translation:
            return "a translation update"
        }
    }
}

enum ViewPacketCardActionRole: String, Equatable {
    case accept
    case dismiss

    var visibleLabel: String {
        switch self {
        case .accept:
            return "keep"
        case .dismiss:
            return "dismiss"
        }
    }

    var fallbackConsequence: String {
        switch self {
        case .accept:
            return "records this card as useful and closes it"
        case .dismiss:
            return "records this card as not useful and closes it"
        }
    }

    var unavailableConsequence: String {
        "unavailable until this card refreshes"
    }

    fileprivate var objectKeys: [String] {
        switch self {
        case .accept:
            return ["accept", "keep"]
        case .dismiss:
            return ["dismiss"]
        }
    }

    fileprivate var directKeys: [String] {
        switch self {
        case .accept:
            return ["acceptAction", "accept_action", "accept", "keepAction", "keep_action"]
        case .dismiss:
            return ["dismissAction", "dismiss_action", "dismiss"]
        }
    }
}

struct ViewPacketCardAction: Equatable {
    let role: ViewPacketCardActionRole
    let action: ViewPacketAction?
    let consequence: String
}

struct ViewPacketCardDisclosure: Equatable {
    let brief: DecisionBrief?
    let evidenceLines: [String]
    let supplementalLines: [String]

    init(packet: ViewPacket, fields: [String: ViewPacketJSONValue], disclosure: [String: ViewPacketJSONValue]) {
        brief = DecisionBrief.first(in: disclosure)
            ?? DecisionBrief.from(.object(disclosure))
            ?? DecisionBrief.first(in: fields)

        let previewValue = disclosure["evidencePreviews"]
            ?? disclosure["evidence_previews"]
            ?? disclosure["evidence"]
            ?? fields["evidencePreviews"]
            ?? fields["evidence_previews"]
        let previews = DecisionEvidencePreview.from(previewValue) + packet.evidencePreviews
        let evidence = Self.stringValues(disclosure["evidence"])
            + Self.stringValues(fields["evidence"])
            + (packet.evidence ?? [])
        evidenceLines = Self.unique(
            MindEvidenceDetailFormatter.lines(previews: previews, evidence: evidence)
        )

        var lines: [String] = []
        if let displayText = Self.normalized(packet.displayText) {
            lines.append(displayText)
        }
        for key in ["summary", "body", "contrast", "why"] {
            if let line = Self.normalized(disclosure[key]?.stringValue) {
                lines.append(line)
            }
        }
        for key in ["grounding", "contributors", "confounders", "lockedEntities", "locked_entities"] {
            let value = disclosure[key] ?? fields[key]
            lines.append(contentsOf: Self.namedLines(value))
        }
        supplementalLines = Self.unique(lines)
    }

    var visibleLines: [String] {
        var lines: [String] = []
        if let brief {
            if let whyNow = brief.whyNow { lines.append(whyNow) }
            if let openQuestion = brief.openQuestion { lines.append(openQuestion) }
            lines.append(brief.blockerLine)
            lines.append(contentsOf: brief.options.compactMap(\.whatHappens))
            if let stakes = brief.stakes { lines.append(stakes) }
        }
        lines.append(contentsOf: supplementalLines)
        lines.append(contentsOf: evidenceLines)
        return Self.unique(lines)
    }

    private static func namedLines(_ value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }
        let values = value.arrayValue ?? [value]
        return values.compactMap { item in
            if let string = normalized(item.stringValue), !MindEvidenceDetailFormatter.isRawEvidenceReference(string) {
                return string
            }
            guard let object = item.objectValue else { return nil }
            let name = string(in: object, keys: ["name", "label", "title"])
            let detail = string(
                in: object,
                keys: ["paraphrase", "value", "state", "text", "summary", "type"]
            )
            let parts = [name, detail].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private static func stringValues(_ value: ViewPacketJSONValue?) -> [String] {
        guard let value else { return [] }
        let values = value.arrayValue ?? [value]
        return values.compactMap { item in
            guard let string = normalized(item.stringValue),
                  !MindEvidenceDetailFormatter.isRawEvidenceReference(string)
            else { return nil }
            return string
        }
    }

    private static func string(
        in object: [String: ViewPacketJSONValue],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = normalized(object[key]?.stringValue) { return value }
        }
        return nil
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let normalized = normalized(value) else { return nil }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct ViewPacketCardPresentation: Equatable {
    static let glanceableCharacterLimit = 120

    let kind: ViewPacketCardKind
    let face: CardFace
    let usesFallbackFace: Bool
    let disclosure: ViewPacketCardDisclosure
    let accept: ViewPacketCardAction
    let dismiss: ViewPacketCardAction
    let queuedCueCount: Int?
    let isSuppressed: Bool
    let announcesArrival: Bool

    init?(packet: ViewPacket) {
        guard let kind = ViewPacketCardKind(rawValue: packet.viewType) else { return nil }
        let fields = packet.fields ?? [:]
        let disclosureObject = fields["disclosure"]?.objectValue ?? [:]
        let suppliedFace = CardFace.from(fields["face"])
            ?? CardFace.from(fields["card"]?.objectValue?["face"])

        self.kind = kind
        if let suppliedFace, Self.isWithinGlanceableBudget(suppliedFace) {
            face = suppliedFace
            usesFallbackFace = false
        } else {
            face = Self.fallbackFace(kind: kind, packetText: packet.displayText)
            usesFallbackFace = true
        }
        disclosure = ViewPacketCardDisclosure(
            packet: packet,
            fields: fields,
            disclosure: disclosureObject
        )
        accept = Self.cardAction(
            role: .accept,
            fields: fields,
            disclosure: disclosureObject
        )
        dismiss = Self.cardAction(
            role: .dismiss,
            fields: fields,
            disclosure: disclosureObject
        )
        queuedCueCount = Self.positiveInt(
            fields["queuedCueCount"]
                ?? fields["queued_cue_count"]
                ?? packet.surfaceDecision?["queuedCueCount"]
                ?? packet.surfaceDecision?["queued_cue_count"]
        )
        let status = Self.normalized(fields["status"]?.stringValue ?? fields["state"]?.stringValue)?.lowercased()
        isSuppressed = status?.contains("suppressed") == true
        announcesArrival = kind == .cue && status == "fired"
    }

    var collapsedVisibleText: [String] {
        var lines = [face.anchor.displayText, face.ask, "keep", "dismiss", "details ›"]
        if let queuedCueCount {
            lines.append("+\(queuedCueCount) more")
        }
        return lines
    }

    func selectedPacket(_ role: ViewPacketCardActionRole, from packet: ViewPacket) -> ViewPacket? {
        let selected = role == .accept ? accept : dismiss
        guard let action = selected.action else { return nil }
        var packet = packet
        packet.action = action
        return packet
    }

    static func isWithinGlanceableBudget(_ face: CardFace) -> Bool {
        face.anchor.displayText.count + face.ask.count < glanceableCharacterLimit
    }

    private static func fallbackFace(kind: ViewPacketCardKind, packetText: String) -> CardFace {
        let ask = "details available"
        let packetText = normalized(packetText)
        let anchor = packetText.flatMap { text in
            text.count + ask.count < glanceableCharacterLimit ? text : nil
        } ?? kind.fallbackAnchor
        return CardFace(
            anchor: CardFaceAnchor(style: "restatement", text: anchor),
            ask: ask
        )
    }

    private static func cardAction(
        role: ViewPacketCardActionRole,
        fields: [String: ViewPacketJSONValue],
        disclosure: [String: ViewPacketJSONValue]
    ) -> ViewPacketCardAction {
        let containers = [fields, disclosure]
        for container in containers {
            if let actions = container["actions"]?.objectValue {
                for key in role.objectKeys {
                    if let value = actions[key] {
                        return parsedAction(role: role, value: value)
                    }
                }
            }
            for key in role.directKeys {
                if let value = container[key] {
                    return parsedAction(role: role, value: value)
                }
            }
        }
        return ViewPacketCardAction(
            role: role,
            action: nil,
            consequence: role.unavailableConsequence
        )
    }

    private static func parsedAction(
        role: ViewPacketCardActionRole,
        value: ViewPacketJSONValue
    ) -> ViewPacketCardAction {
        let wrapper = value.objectValue ?? [:]
        let actionValue = wrapper["action"] ?? value
        let object = actionValue.objectValue ?? [:]
        let id = string(in: object, keys: ["id", "actionId"])
        let intent = string(in: object, keys: ["intent", "intentName", "name", "toolId"])
        let kind = string(in: object, keys: ["kind"]) ?? intent
        let target = string(in: object, keys: ["target"]) ?? id ?? intent
        let action: ViewPacketAction?
        if let kind, let target {
            action = ViewPacketAction(
                kind: kind,
                target: target,
                tag: string(in: object, keys: ["tag"]),
                id: id,
                intent: intent,
                args: object["args"]?.objectValue ?? object["arguments"]?.objectValue
            )
        } else {
            action = nil
        }
        let consequence = string(in: wrapper, keys: ["consequence", "accessibilityConsequence"])
            ?? string(in: object, keys: ["consequence", "accessibilityConsequence"])
            ?? role.fallbackConsequence
        return ViewPacketCardAction(role: role, action: action, consequence: consequence)
    }

    private static func string(
        in object: [String: ViewPacketJSONValue],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = normalized(object[key]?.stringValue) { return value }
        }
        return nil
    }

    private static func positiveInt(_ value: ViewPacketJSONValue?) -> Int? {
        guard let value else { return nil }
        let number = value.doubleValue ?? value.stringValue.flatMap(Double.init)
        guard let number, number.isFinite, let count = Int(exactly: number), count > 0 else { return nil }
        return count
    }

    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct ViewPacketCardView: View {
    let packet: ViewPacket
    let pendingActionPacketIDs: Set<String>
    let actionErrorTexts: [String: String]
    let context: RenderViewPacketContext
    let onAction: (ViewPacket) -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var detailsExpanded = false
    @State private var announcedArrival = false

    var body: some View {
        Group {
            if let card = ViewPacketCardPresentation(packet: packet) {
                Group {
                    if context == .chatStream {
                        cardContent(card)
                    } else {
                        KGlassCard {
                            cardContent(card)
                        }
                    }
                }
                .onAppear {
                    announceArrivalIfNeeded(card)
                }
                .onChange(of: card.announcesArrival) { _, _ in
                    announceArrivalIfNeeded(card)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("view-packet-card-\(packet.id)")
    }

    private func cardContent(_ card: ViewPacketCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            if detailsExpanded {
                disclosureBody(card)
            } else {
                faceBody(card.face)
            }

            actionRow(card)

            if let queuedCueCount = card.queuedCueCount {
                KMonoCaption("+\(queuedCueCount) more", variant: .metadata)
                    .accessibilityLabel("\(queuedCueCount) more cues queued")
                    .accessibilityIdentifier("view-packet-queued-cues-\(packet.id)")
            }

            if pendingActionPacketIDs.contains(packet.id) {
                KMonoCaption(KCopy.answerPending, variant: .status, state: .active)
            }
            if let errorText = actionErrorTexts[packet.id] {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func faceBody(_ face: CardFace) -> some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            Text(face.anchor.displayText)
                .kFont(.content)
                .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(face.ask)
                .kFont(.blockActiveTitle)
                .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func disclosureBody(_ card: ViewPacketCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let brief = card.disclosure.brief {
                if let whyNow = brief.whyNow {
                    disclosureText(whyNow, opacity: KStyle.secondaryTextOpacity)
                }
                if let openQuestion = brief.openQuestion {
                    disclosureText(openQuestion, token: .blockActiveTitle, opacity: KStyle.primaryTextOpacity)
                }
                KMonoCaption(brief.blockerLine, variant: .metadata)
                ForEach(Array(brief.options.enumerated()), id: \.offset) { _, option in
                    if let whatHappens = option.whatHappens {
                        disclosureText(whatHappens, opacity: KStyle.secondaryTextOpacity)
                    }
                }
            }

            ForEach(Array(card.disclosure.supplementalLines.enumerated()), id: \.offset) { _, line in
                disclosureText(line, opacity: KStyle.secondaryTextOpacity)
            }

            if !card.disclosure.evidenceLines.isEmpty {
                KEvidenceBlock(text: card.disclosure.evidenceLines.joined(separator: "\n"), variant: .mono)
            }

            KMonoCaption("keep · \(card.accept.consequence)", variant: .metadata)
            KMonoCaption("dismiss · \(card.dismiss.consequence)", variant: .metadata)

            if let stakes = card.disclosure.brief?.stakes {
                KMonoCaption(stakes, variant: .metadata)
            }
        }
    }

    private func disclosureText(
        _ text: String,
        token: KFontToken = .content,
        opacity: Double
    ) -> some View {
        Text(text)
            .kFont(token)
            .foregroundStyle(.white.opacity(opacity))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func actionRow(_ card: ViewPacketCardPresentation) -> some View {
        let isPending = pendingActionPacketIDs.contains(packet.id)
        let detailsLabel = detailsExpanded ? "details ‹" : "details ›"
        return KActRow(
            actions: [
                KActItem(
                    id: ViewPacketCardActionRole.accept.rawValue,
                    label: ViewPacketCardActionRole.accept.visibleLabel,
                    isEnabled: card.accept.action != nil && !isPending,
                    accessibilityIdentifier: "view-packet-keep-\(packet.id)"
                ),
                KActItem(
                    id: ViewPacketCardActionRole.dismiss.rawValue,
                    label: ViewPacketCardActionRole.dismiss.visibleLabel,
                    isEnabled: card.dismiss.action != nil && !isPending,
                    accessibilityIdentifier: "view-packet-dismiss-\(packet.id)"
                ),
                KActItem(
                    id: "details",
                    label: detailsLabel,
                    isEnabled: !isPending,
                    accessibilityIdentifier: "view-packet-details-\(packet.id)"
                ),
            ],
            variant: .build,
            onSelect: { item in
                switch item.id {
                case ViewPacketCardActionRole.accept.rawValue:
                    perform(.accept, card: card)
                case ViewPacketCardActionRole.dismiss.rawValue:
                    perform(.dismiss, card: card)
                case "details":
                    detailsExpanded.toggle()
                default:
                    break
                }
            }
        )
        .accessibilityRepresentation {
            HStack {
                Button("keep") { perform(.accept, card: card) }
                    .disabled(card.accept.action == nil || isPending)
                    .accessibilityHint(card.accept.consequence)
                    .accessibilityIdentifier("view-packet-keep-\(packet.id)")
                Button("dismiss") { perform(.dismiss, card: card) }
                    .disabled(card.dismiss.action == nil || isPending)
                    .accessibilityHint(card.dismiss.consequence)
                    .accessibilityIdentifier("view-packet-dismiss-\(packet.id)")
                Button(detailsLabel) { detailsExpanded.toggle() }
                    .disabled(isPending)
                    .accessibilityHint(detailsExpanded ? "collapses the card detail" : "expands the card detail")
                    .accessibilityIdentifier("view-packet-details-\(packet.id)")
            }
        }
    }

    private func perform(
        _ role: ViewPacketCardActionRole,
        card: ViewPacketCardPresentation
    ) {
        guard let selectedPacket = card.selectedPacket(role, from: packet) else { return }
        onAction(selectedPacket)
    }

    private func announceArrivalIfNeeded(_ card: ViewPacketCardPresentation) {
        guard voiceOverEnabled, card.announcesArrival, !announcedArrival else { return }
        announcedArrival = true
        AccessibilityNotification.Announcement(
            "\(card.face.anchor.displayText). \(card.face.ask)"
        ).post()
    }
}

struct RenderViewPacket: View {
    let packet: ViewPacket
    let pendingActionPacketIDs: Set<String>
    let actionErrorTexts: [String: String]
    let context: RenderViewPacketContext
    let isNested: Bool
    let materializeIndex: Int
    let onAction: (ViewPacket) -> Void

    init(
        packet: ViewPacket,
        pendingActionPacketIDs: Set<String> = [],
        actionErrorTexts: [String: String] = [:],
        context: RenderViewPacketContext = .cardSurface,
        isNested: Bool = false,
        materializeIndex: Int = 0,
        onAction: @escaping (ViewPacket) -> Void = { _ in }
    ) {
        self.packet = packet
        self.pendingActionPacketIDs = pendingActionPacketIDs
        self.actionErrorTexts = actionErrorTexts
        self.context = context
        self.isNested = isNested
        self.materializeIndex = materializeIndex
        self.onAction = onAction
    }

    @ViewBuilder
    var body: some View {
        if ViewPacketRenderer.shouldRender(packet) {
            let policy = ViewPacketRenderer.renderPolicy(for: packet)
            switch policy.interruptionClass {
            case .ambient:
                materializedPacketBody
            case .peripheral:
                if ViewPacketRenderBranch.allCards.contains(ViewPacketRenderer.branch(for: packet)) {
                    materializedPacketBody
                        .transition(policy.usesFadeTransition ? .opacity : .identity)
                        .kOpacityAnimated(value: packet, isEnabled: policy.animatesChanges)
                } else {
                    materializedPacketBody
                        .transition(policy.usesFadeTransition ? .opacity : .identity)
                        .kAnimated(value: packet, isEnabled: policy.animatesChanges)
                }
            case .focal:
                materializedPacketBody
            }
        }
    }

    private var materializedPacketBody: some View {
        packetBody
            .genMaterialize(identity: packet.id, index: materializeIndex)
    }

    private var packetBody: some View {
        VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
            content

            if !ViewPacketRenderBranch.allCards.contains(ViewPacketRenderer.branch(for: packet)),
               ViewPacketRenderer.actionAffordance(for: packet) != .hidden {
                actionButton(ViewPacketRenderer.actionAffordance(for: packet))
            }

            if !packet.shouldRenderHeldState, !packet.children.isEmpty {
                VStack(alignment: .leading, spacing: KStyle.rowSpacing) {
                    ForEach(Array(packet.children.enumerated()), id: \.element.id) { index, child in
                        RenderViewPacket(
                            packet: child,
                            pendingActionPacketIDs: pendingActionPacketIDs,
                            actionErrorTexts: actionErrorTexts,
                            context: context,
                            isNested: true,
                            materializeIndex: index,
                            onAction: onAction
                        )
                    }
                }
                .padding(.leading, KStyle.cardPadding)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(KStyle.hairlineStrongOpacity))
                        .frame(width: KStyle.dividerHeight)
                }
                .kAnimated(
                    value: packet.children.map(\.id),
                    isEnabled: ViewPacketRenderer.renderPolicy(for: packet).animatesChanges
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if context == .chatStream {
            streamContent
        } else {
            cardSurfaceContent
        }
    }

    @ViewBuilder
    private var cardSurfaceContent: some View {
        switch ViewPacketRenderer.branch(for: packet) {
        case .held:
            heldView
        case .chatWorker:
            workerView
        case .buildStatus:
            BuildStatusPacketView(packet: packet)
        case .buildCard:
            BuildCardPacketView(packet: packet)
        case .genericText:
            textView
        case .genericTable:
            tableView
        case .genericCard:
            cardView
        case .genericChart:
            chartPlaceholderView
        case .cardCue, .cardBody, .cardTranslation:
            cardPacketView
        case .k0Decision:
            k0View
        case .k0Provenance, .k0Claim, .k0Change, .k0EvalScore, .k0EvolveReport:
            provenancePanelView
        case .loopEvidence:
            // A2UIPanel takes over plain evidence bundles (packet-emit.mjs's
            // memorySearchPacketInput — exposures/citations); mind/think
            // output group[1] carries a DecisionBrief on this same viewType,
            // and that existing, tested preview keeps precedence so nothing
            // regresses.
            if DecisionBrief.first(in: packet.fields) != nil {
                evidenceView
            } else {
                provenancePanelView
            }
        case .preview:
            previewView
        }
    }

    private var provenancePanelView: some View {
        A2UIPanel(packet: packet)
    }

    private var cardPacketView: some View {
        ViewPacketCardView(
            packet: packet,
            pendingActionPacketIDs: pendingActionPacketIDs,
            actionErrorTexts: actionErrorTexts,
            context: context,
            onAction: onAction
        )
    }

    @ViewBuilder
    private var streamContent: some View {
        switch ViewPacketRenderer.branch(for: packet) {
        case .held:
            heldInlineView
        case .chatWorker:
            workerInlineView
        case .buildStatus:
            buildStatusInlineView
        case .buildCard:
            buildCardInlineView
        case .genericText:
            chatStreamTextView
        case .genericTable:
            tableInlineView
        case .cardCue, .cardBody, .cardTranslation:
            cardPacketView
        case .genericCard, .k0Decision, .k0Provenance, .k0Change, .k0EvalScore, .k0EvolveReport,
             .loopEvidence, .preview:
            packetInlineView
        case .genericChart:
            JarvisChartStreamBlock(packet: packet)
        case .k0Claim:
            if ViewPacketRenderer.rendersNativeClaimBlock(for: packet) {
                JarvisClaimStreamBlock(packet: packet)
            } else {
                packetInlineView
            }
        }
    }

    private func actionButton(_ affordance: ViewPacketActionAffordance) -> some View {
        let isPending = pendingActionPacketIDs.contains(packet.id)
        let errorText = actionErrorTexts[packet.id]
        let isDisabled: Bool = {
            if isPending { return true }
            if case .disabled = affordance { return true }
            return false
        }()
        return VStack(alignment: .leading, spacing: KStyle.microSpacing) {
            KActRow(
                actions: [
                    KActItem(
                        id: packet.id,
                        label: isPending ? KCopy.answerPending : (packet.action?.displayLabel ?? "run"),
                        isEnabled: !isDisabled,
                        accessibilityIdentifier: "view-packet-action-\(packet.id)"
                    ),
                ],
                variant: .build,
                state: isPending ? .loading : .resting,
                onSelect: { _ in
                    guard !isDisabled else { return }
                    onAction(packet)
                }
            )

            if case .disabled(let reason) = affordance {
                KMonoCaption(reason, variant: .metadata)
            }
            if let errorText {
                KMonoCaption(errorText, variant: .inlineError, state: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var textView: some View {
        Text(packet.displayText.isEmpty ? "no content" : packet.displayText)
            .font(KStyle.contentFont)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Chat-stream reply prose carries the mock v35 contrast law (lead bright,
    // support dim); an empty packet keeps the plain debug fallback.
    @ViewBuilder
    private var chatStreamTextView: some View {
        if packet.displayText.isEmpty {
            textView
        } else {
            ChatReplyProse(text: packet.displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packetInlineView: some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let brief = DecisionBrief.first(in: packet.fields),
               (ViewPacketRenderBranch.allK0 + [.loopEvidence]).contains(ViewPacketRenderer.branch(for: packet)) {
                decisionBriefPreview(brief)
            } else {
                if !packet.displayText.isEmpty {
                    Text(packet.displayText)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                } else {
                    KMonoCaption(packet.viewType, variant: .metadata)
                }

                let evidenceLines = ViewPacketRenderer.evidenceVisibleLines(for: packet)
                if !evidenceLines.isEmpty {
                    KEvidenceBlock(text: evidenceLines.joined(separator: "\n"), variant: .mono)
                }

                FieldList(fields: packet.fields)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tableInlineView: some View {
        let table = ViewPacketTable(packet: packet)
        return VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let title = packet.text, !title.isEmpty {
                Text(title)
                    .font(KStyle.blockDefaultTitleFont)
                    .textSelection(.enabled)
            }
            if table.rows.isEmpty {
                KMonoCaption("no rows", variant: .metadata)
            } else {
                Grid(alignment: .leading, horizontalSpacing: KStyle.cardPadding, verticalSpacing: KStyle.tightRowSpacing) {
                    if !table.columns.isEmpty {
                        GridRow {
                            ForEach(table.columns.indices, id: \.self) { index in
                                KMonoCaption(table.columns[index], variant: .metadata, state: .active)
                            }
                        }
                        Divider()
                    }
                    ForEach(table.rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                                Text(table.value(row: rowIndex, column: columnIndex))
                                    .font(KStyle.contentFont)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buildStatusInlineView: some View {
        let summary = BuildStatusSummary(packet: packet)
        return VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                KStatusDot(signal: BuildSignal.from(state: summary.state).kSignal, size: .small)
                Text(summary.title)
                    .font(KStyle.blockDefaultTitleFont)
                    .textSelection(.enabled)
                Spacer(minLength: KStyle.tightRowSpacing)
                if let state = summary.state {
                    KMonoCaption(state, variant: .metadata)
                }
            }
            if let detail = summary.detail {
                Text(detail)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .textSelection(.enabled)
            }
            BuildRecordSection(title: "units", records: summary.units, kind: .unit, emptyText: nil)
                .environment(\.buildRecordFlatOnGlass, true)
            BuildRecordSection(title: "lanes", records: summary.lanes, kind: .lane, emptyText: nil)
                .environment(\.buildRecordFlatOnGlass, true)
            BuildRecordSection(title: "history", records: summary.history, kind: .history, emptyText: nil)
                .environment(\.buildRecordFlatOnGlass, true)
            if !summary.extraFields.isEmpty {
                FieldList(fields: summary.extraFields)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buildCardInlineView: some View {
        let summary = BuildCardSummary(packet: packet)
        return VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let brief = summary.brief {
                decisionBriefPreview(brief)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                    Text(summary.voiceTitle)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                    Spacer(minLength: KStyle.tightRowSpacing)
                    if packet.isLoopbackOnlyBuildCard {
                        KMonoCaption("mac only", variant: .metadata)
                    } else if let state = summary.state {
                        KMonoCaption(state, variant: .metadata)
                    }
                }

                if let body = summary.body {
                    Text(body)
                        .font(KStyle.contentFont)
                        .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                        .textSelection(.enabled)
                }

                if !summary.extraFields.isEmpty {
                    FieldList(fields: summary.extraFields)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decisionBriefPreview(_ brief: DecisionBrief) -> some View {
        VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            if let whyNow = brief.whyNow {
                Text(whyNow)
                    .font(KStyle.contentFont)
                    .foregroundStyle(.white.opacity(KStyle.secondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let openQuestion = brief.openQuestion {
                Text(openQuestion)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            KMonoCaption(brief.blockerLine, variant: .metadata)
                .textSelection(.enabled)
            if let stakes = brief.stakes {
                KMonoCaption(stakes, variant: .metadata)
                    .textSelection(.enabled)
            }
        }
    }

    private var workerInlineView: some View {
        let worker = ChatWorkerPacket(packet)
        return VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.tightRowSpacing) {
                KStatusDot(signal: worker?.isTerminal == true ? .idle : .live, size: .small)
                Text(worker?.stateLine() ?? packet.displayText)
                    .font(KStyle.blockDefaultTitleFont)
                    .foregroundStyle(.white.opacity(KStyle.primaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: KStyle.tightRowSpacing)
                if let state = worker?.state {
                    KMonoCaption(state, variant: .metadata, state: worker?.isTerminal == true ? .disabled : .active)
                }
            }

            if let stepText = worker?.stepText {
                KMonoCaption(stepText, variant: .status, state: worker?.isTerminal == true ? .disabled : .active)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workerView: some View {
        KGlassCard(state: ChatWorkerPacket(packet)?.isTerminal == true ? .disabled : .resting) {
            workerInlineView
        }
    }

    private var heldInlineView: some View {
        VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                KStatusDot(signal: .idle, state: .disabled, size: .small)
                KMonoCaption("surface held", variant: .status, state: .disabled)
            }
            KMonoCaption(packet.heldStateReason ?? "held by surface decision", variant: .metadata, state: .disabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var cardView: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if !packet.displayText.isEmpty {
                    Text(packet.displayText)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                }
                FieldList(fields: packet.fields)
            }
        }
    }

    private var tableView: some View {
        let table = ViewPacketTable(packet: packet)
        return KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if let title = packet.text, !title.isEmpty {
                    Text(title)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                }
                if table.rows.isEmpty {
                    KMonoCaption("no rows", variant: .metadata)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: KStyle.cardPadding, verticalSpacing: KStyle.tightRowSpacing) {
                        if !table.columns.isEmpty {
                            GridRow {
                                ForEach(table.columns.indices, id: \.self) { index in
                                    KMonoCaption(table.columns[index], variant: .metadata, state: .active)
                                }
                            }
                            Divider()
                        }
                        ForEach(table.rows.indices, id: \.self) { rowIndex in
                            GridRow {
                                ForEach(0..<table.columnCount, id: \.self) { columnIndex in
                                    Text(table.value(row: rowIndex, column: columnIndex))
                                        .font(KStyle.contentFont)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var chartPlaceholderView: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                Text(packet.displayText.isEmpty ? "chart" : packet.displayText)
                    .font(KStyle.blockDefaultTitleFont)
                FieldList(fields: packet.fields)
            }
        }
    }

    private var k0View: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if let brief = DecisionBrief.first(in: packet.fields) {
                    decisionBriefPreview(brief)
                } else {
                    Text(packet.displayText.isEmpty ? packet.viewType : packet.displayText)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                    FieldList(fields: packet.fields)
                }
            }
        }
    }

    private var evidenceView: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                if let brief = DecisionBrief.first(in: packet.fields) {
                    decisionBriefPreview(brief)
                } else {
                    Text(packet.displayText.isEmpty ? "evidence" : packet.displayText)
                        .font(KStyle.blockDefaultTitleFont)
                        .textSelection(.enabled)
                    let evidenceLines = ViewPacketRenderer.evidenceVisibleLines(for: packet)
                    if !evidenceLines.isEmpty {
                        KEvidenceBlock(text: evidenceLines.joined(separator: "\n"), variant: .mono)
                    }
                }
            }
        }
    }

    private var previewView: some View {
        KGlassCard {
            VStack(alignment: .leading, spacing: KStyle.tightRowSpacing) {
                Text(packet.displayText.isEmpty ? packet.viewType : packet.displayText)
                    .font(KStyle.blockDefaultTitleFont)
                    .textSelection(.enabled)
                FieldList(fields: packet.fields)
            }
        }
    }

    private var heldView: some View {
        KGlassCard(state: .disabled) {
            VStack(alignment: .leading, spacing: KStyle.smallSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                    KStatusDot(signal: .idle, state: .disabled, size: .small)
                    KMonoCaption("surface held", variant: .status, state: .disabled)
                }
                KMonoCaption(packet.heldStateReason ?? "held by surface decision", variant: .metadata, state: .disabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ViewPacketTable: Equatable {
    let columns: [String]
    let rows: [[String]]

    init(packet: ViewPacket) {
        let fields = packet.fields ?? [:]
        let rowValues = fields["rows"]?.arrayValue ?? []
        var parsedColumns = fields["columns"]?.arrayValue?.map(\.description).filter { !$0.isEmpty } ?? []
        if parsedColumns.isEmpty {
            parsedColumns = Self.objectKeys(from: rowValues)
        }

        let parsedRows = rowValues.map { Self.row(from: $0, columns: parsedColumns) }
        if parsedColumns.isEmpty {
            let width = parsedRows.map(\.count).max() ?? 0
            parsedColumns = width == 0 ? [] : (1...width).map { "column \($0)" }
        }

        columns = parsedColumns
        rows = parsedRows
    }

    var columnCount: Int {
        max(columns.count, rows.map(\.count).max() ?? 0)
    }

    func value(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    private static func row(from value: ViewPacketJSONValue, columns: [String]) -> [String] {
        if let values = value.arrayValue {
            return values.map(\.description)
        }
        if let object = value.objectValue {
            if columns.isEmpty {
                return object
                    .sorted { $0.key < $1.key }
                    .map { $0.value.description }
            }
            return columns.map { object[$0]?.description ?? "" }
        }
        return [value.description]
    }

    private static func objectKeys(from values: [ViewPacketJSONValue]) -> [String] {
        let keys = values.flatMap { value -> [String] in
            guard let object = value.objectValue else { return [] }
            return Array(object.keys)
        }
        return Array(Set(keys)).sorted()
    }
}

struct FieldList: View {
    let fields: [String: ViewPacketJSONValue]?

    var body: some View {
        if !displayFields.isEmpty {
            VStack(alignment: .leading, spacing: KStyle.microSpacing) {
                ForEach(displayFields, id: \.key) { key, value in
                    HStack(alignment: .firstTextBaseline, spacing: KStyle.smallSpacing) {
                        KMonoCaption(key, variant: .metadata, state: .disabled)
                        Text(value.description)
                            .kFont(.monoCaption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var displayFields: [(key: String, value: ViewPacketJSONValue)] {
        (fields ?? [:])
            .filter { !MindEvidenceDetailFormatter.isEvidenceFieldKey($0.key) }
            .sorted { $0.key < $1.key }
    }
}

extension ViewPacket {
    var isBuildStatusPacket: Bool {
        viewType == "build.status"
    }

    var isBuildCardPacket: Bool {
        viewType == "build.card"
    }

    var isLoopbackOnlyBuildCard: Bool {
        guard isBuildCardPacket else { return false }
        return buildStringValue(for: ["tier", "channelTier", "channel", "answerTier", "answerChannel"]) == "loopback"
    }

    var isOpenBuildCard: Bool {
        guard isBuildCardPacket else { return false }
        let status = buildStringValue(for: ["status", "state"]) ?? "raised"
        return !["answered", "applied", "apply-failed", "obsoleted", "superseded", "closed", "dismissed"].contains(status)
    }

    private func buildStringValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = fields?["card"]?.objectValue?[key]?.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !value.isEmpty {
                return value
            }
            if let value = fields?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !value.isEmpty {
                return value
            }
            if let value = provenance[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
