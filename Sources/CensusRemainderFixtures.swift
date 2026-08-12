import Foundation

/// A sealed, local-only fixture for the W12 census walk. The route is opt-in via
/// `-ui48-census-fixture`; production paths never consult this data.
/// Doctrine: silence-default, one-slot, staleness-honesty, interruption-classes.
enum CensusRemainderFixture {
    static let launchArgument = "-ui48-census-fixture"
    static let onboardingLaunchArgument = "-ui48-onboarding-fixture"
    static let referenceNow = Date(timeIntervalSince1970: 1_786_353_600) // 2026-08-10 09:20 UTC

    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    static func isOnboardingEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(onboardingLaunchArgument)
    }

    static let chatMessages: [Message] = {
        let annotation = TermAnnotation(
            term: "ontology",
            range: TermAnnotationRange(start: 0, length: 8),
            definition: "the kinds of things a system can know and act on.",
            firstSeenRef: "w12 census"
        )
        return [
            Message(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000481")!,
                role: .you,
                text: "what boundary is holding the lane?",
                createdAt: referenceNow.addingTimeInterval(-180)
            ),
            Message(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000482")!,
                role: .k,
                text: "ontology is the boundary.\nit keeps the proof legible.",
                termAnnotations: [annotation],
                createdAt: referenceNow.addingTimeInterval(-120)
            ),
            Message(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000483")!,
                role: .k,
                text: chatCardPacket.displayText,
                packet: chatCardPacket,
                createdAt: referenceNow.addingTimeInterval(-60)
            ),
        ]
    }()

    static let chatCardPacket = ViewPacket(
        id: "w12-chat-card-cue",
        viewType: "card.cue",
        text: "the walk fixture has one quiet decision cue",
        fields: [
            "status": .string("pending"),
            "interruptionClass": .string("peripheral"),
            "maxSimultaneousCues": .number(1),
            "face": CardFace(
                anchor: CardFaceAnchor(style: "restatement", text: "the walk fixture has one quiet decision cue"),
                ask: "keep this cue for the audit?"
            ).jsonValue,
            "disclosure": .object([
                "brief": .object([
                    "whyNow": .string("the fixture keeps the visible card path inspectable."),
                    "openQuestion": .string("keep this cue for the audit?"),
                    "blocker": .string("nothing · ready to decide"),
                    "stakes": .string("reversible · silence leaves the fixture unchanged"),
                ]),
                "evidence": .array([
                    .object([
                        "label": .string("one seeded walk state"),
                        "at": .string("aug 10"),
                    ]),
                ]),
            ]),
            "actions": .object([
                "accept": actionWrapper(id: "w12-chat-card-keep", disposition: "accepted"),
                "dismiss": actionWrapper(id: "w12-chat-card-dismiss", disposition: "dismissed"),
            ]),
        ],
        provenance: [
            "surface": .string("chat"),
            "lane": .string("seeded"),
        ],
        frontierExcluded: true
    )

    static let buildPackets: [ViewPacket] = [
        buildStatusPacket,
        buildNotePacket,
        buildCard.packet,
    ]

    static let buildReport: BuildReport = {
        let json = #"""
        {
          "schemaVersion": 1,
          "generatedAt": "2026-08-10T09:20:00Z",
          "stateSentence": "the lane is moving",
          "landed": {"text": "2 units", "firstPass": {"text": "1 pass"}},
          "needsYou": {"text": "1 card", "oldestAge": {"text": "18m"}},
          "constraint": {"text": "one review"},
          "rate": {"text": "2 units per day"},
          "eta": {"text": "today"},
          "repeats": {"text": "none"},
          "unproven": {"text": "one edge"},
          "actedOn": {"text": "one decision"},
          "lanes": {"text": "one lane"},
          "machine": {"text": "ipad"},
          "tokens": {"text": "quiet"},
          "spend": {"text": "none"}
        }
        """#
        return try! JSONDecoder().decode(BuildReport.self, from: Data(json.utf8))
    }()

    static let adminResponse = AdminBandishResponse(
        records: [
            AdminItem(
                id: "w12-admin-op",
                title: "review the census remainder",
                type: .timeSensitive,
                effort: .hour,
                remindAt: "2026-08-10T09:00:00Z",
                dueAt: "2026-08-10T10:00:00Z",
                verbs: ["complete", "reschedule"]
            ),
            AdminItem(
                id: "w12-admin-quiet",
                title: "keep the seeded fixture local",
                type: .regularQueue,
                effort: .quick,
                dueAt: "2026-08-11T10:00:00Z",
                verbs: ["complete", "reschedule"]
            ),
        ],
        sort: ["dueAt", "effort"]
    )

    static let provenancePackets: [ViewPacket] = [
        ViewPacket(
            id: "w12-provenance",
            viewType: "k0.provenance",
            fields: [
                "subject": .string("census walk coverage"),
                "asOf": .string("09:20"),
                "sourceRefs": .array([
                    .object(["id": .string("seeded fixture"), "statement": .string("56 surfaces mapped"), "surface": .string("design")]),
                    .object(["id": .string("walk rig"), "statement": .string("named captures on ipad"), "surface": .string("tests")]),
                ]),
            ],
            frontierExcluded: true
        ),
        ViewPacket(
            id: "w12-claim",
            viewType: "k0.claim",
            text: "the visible remainder has a walk path",
            fields: [
                "status": .string("promoted"),
                "confidence": .number(0.92),
            ],
            confidence: 0.92,
            frontierExcluded: true
        ),
        ViewPacket(
            id: "w12-change",
            viewType: "k0.change",
            fields: [
                "before": .string("no named capture"),
                "after": .string("named capture"),
                "actor": .string("w12 walk rig"),
            ],
            frontierExcluded: true
        ),
        ViewPacket(
            id: "w12-eval-score",
            viewType: "k0.eval_score",
            fields: [
                "metric": .string("visible states covered"),
                "score": .number(0.86),
                "rationale": .string("founder-facing routes have deterministic proof."),
            ],
            score: 0.86,
            frontierExcluded: true
        ),
        ViewPacket(
            id: "w12-evolve-report",
            viewType: "k0.evolve_report",
            fields: [
                "periodStart": .string("aug 1"),
                "periodEnd": .string("aug 10"),
                "changeCount": .number(4),
            ],
            frontierExcluded: true
        ),
        ViewPacket(
            id: "w12-loop-evidence",
            viewType: "loop.evidence",
            fields: [
                "exposures": .array([
                    .object(["id": .string("capture"), "statement": .string("resting state captured"), "surface": .string("walk rig")]),
                    .object(["id": .string("fixture"), "statement": .string("no network used"), "surface": .string("seed")]),
                ]),
            ],
            frontierExcluded: true
        ),
    ]

    static let reviewEvidence: [BuildEvidenceEntry] = [
        BuildEvidenceEntry(
            id: "w12-evidence-gate",
            kind: "gate-output",
            title: "walk gate",
            text: "fixture loaded\nno network request",
            createdAt: "09:20"
        ),
        BuildEvidenceEntry(
            id: "w12-evidence-transcript",
            kind: "transcript",
            title: "capture transcript",
            text: "named states remain visible",
            createdAt: "09:20"
        ),
    ]

    static let reviewDiffs: [BuildDiffResponse] = [
        BuildDiffResponse(
            id: "w12-diff",
            summary: "walk coverage added",
            files: [BuildDiffFile(path: "KedarAuditUITests/KedarAuditUITests.swift", status: "modified", additions: 42, deletions: 0, patch: "+ named captures")],
            docPaths: ["docs/design/2026-08-10-census-remainder.md"]
        ),
    ]

    static let reviewDocuments: [BuildDocumentResponse] = [
        BuildDocumentResponse(
            path: "docs/design/2026-08-10-census-remainder.md",
            title: "census remainder",
            content: "founder-facing remainder mapped to named captures.",
            language: "markdown"
        ),
    ]

    static let learnedFeed = BuildLearnedFeed(
        pending: [
            BuildLearnedEntry(
                id: "w12-learned",
                text: "seeded captures make review repeatable",
                status: "pending",
                source: "walk rig",
                updatedAt: "09:20"
            ),
        ],
        approved: [
            BuildLearnedEntry(
                id: "w12-learned-approved",
                text: "founder-facing states need named captures",
                status: "approved",
                decision: .approve,
                source: "census",
                updatedAt: "09:10"
            ),
        ]
    )

    static let trustResponse = BuildTrustResponse(
        pairs: [
            BuildTrustPair(id: "w12-trust-1", verdict: "fixture is local", decision: "keep", signal: "seed", source: "walk rig", createdAt: "09:20"),
            BuildTrustPair(id: "w12-trust-2", verdict: "capture is named", decision: "keep", signal: "coverage", source: "audit", createdAt: "09:20"),
        ],
        generatedAt: "09:20"
    )

    static let logTailResponse = BuildLaneLogTailResponse(
        laneId: "w12-lane",
        text: "09:19 fixture opened\n09:20 capture ready",
        updatedAt: "09:20"
    )

    private static let buildCard = BuildCard(
        id: "w12-card-face",
        kind: "plan-approval",
        planId: "w12-census-remainder",
        unitId: "w12-unit-review",
        laneId: "w12-lane",
        title: "review the walk fixture",
        body: "the visible remainder is ready for one quiet pass.",
        what: "a coverage decision",
        contrast: "k leans keep the fixture. dropping it leaves the remainder unproven.",
        stakes: "reversible · silence leaves the lane staged",
        evidenceSummary: DecisionEvidenceSummary(conversationCount: 2, atomCount: 4, latestAt: "aug 10", topicHints: ["walk rig"]),
        evidencePreviews: [DecisionEvidencePreview(label: "named capture set", at: "09:20")],
        signalExplained: "the route is deterministic and local.",
        face: CardFace(
            anchor: CardFaceAnchor(style: "restatement", text: "the visible remainder is ready for one quiet pass"),
            ask: "keep the fixture?"
        ),
        brief: DecisionBrief(
            whyNow: "the census names the remaining founder surfaces.",
            openQuestion: "keep the seeded fixture?",
            blocker: "nothing · ready to decide",
            stakes: "reversible · silence leaves the lane staged",
            options: [
                DecisionBriefOption(id: "keep-fixture", whatHappens: "the walk stays repeatable on this ipad."),
                DecisionBriefOption(id: "drop-fixture", whatHappens: "the remaining states wait for another pass."),
            ]
        ),
        options: [
            BuildCardOption(id: "keep-fixture", label: "keep the fixture", consequence: "the walk stays repeatable on this ipad."),
            BuildCardOption(id: "drop-fixture", label: "drop the fixture", consequence: "the remaining states wait for another pass."),
        ],
        recommendation: "keep-fixture",
        status: "raised",
        severity: "review",
        raisedAt: "2026-08-10T09:02:00Z",
        updatedAt: "2026-08-10T09:20:00Z"
    )

    private static let buildStatusPacket = ViewPacket(
        id: "w12-build-status",
        viewType: "build.status",
        text: "census remainder",
        fields: [
            "plan": .object([
                "id": .string("w12-census-remainder"),
                "title": .string("census remainder"),
                "state": .string("building"),
                "summary": .string("one lane keeps the visible states moving"),
            ]),
            "units": .array([
                recordObject(
                    id: "w12-unit-review",
                    unitId: "w12-unit-review",
                    title: "walk the visible states",
                    state: "building",
                    goal: "capture the founder path",
                    scope: "chat · build · admin",
                    age: "4m",
                    updatedAt: "09:20",
                    gateEvidence: "seeded capture ready",
                    stateHistory: ["queued", "building"],
                    diffId: "w12-diff",
                    docPaths: ["docs/design/2026-08-10-census-remainder.md"],
                    legalActions: ["review"]
                ),
                recordObject(
                    id: "w12-unit-seed",
                    unitId: "w12-unit-seed",
                    title: "seed the fixture",
                    state: "complete",
                    goal: "keep every state local",
                    scope: "fixture",
                    age: "8m",
                    updatedAt: "09:12",
                    gateEvidence: "no network request",
                    stateHistory: ["queued", "complete"]
                ),
            ]),
            "lanes": .array([
                recordObject(
                    id: "w12-lane",
                    laneId: "w12-lane",
                    title: "ipad lane",
                    state: "building",
                    goal: "run the walk rig",
                    scope: "iPad landscape",
                    age: "4m",
                    updatedAt: "09:20",
                    logTail: "09:20 capture ready",
                    diff: "1 file · 42 additions",
                    legalActions: ["peek"]
                ),
            ]),
            "history": .array([
                recordObject(id: "w12-history-1", title: "fixture opened", state: "complete", age: "8m"),
                recordObject(id: "w12-history-2", title: "capture gate ready", state: "building", age: "4m"),
            ]),
        ],
        frontierExcluded: true
    )

    private static let buildNotePacket = ViewPacket(
        id: "w12-build-note",
        viewType: "build.note",
        text: "ontology keeps the proof legible",
        fields: [
            "at": .string("09:20"),
            "termAnnotations": .array([
                .object([
                    "term": .string("ontology"),
                    "range": .object(["start": .number(0), "length": .number(8)]),
                    "definition": .string("the kinds of things a system can know and act on."),
                    "firstSeenRef": .string("w12 census"),
                ]),
            ]),
        ],
        frontierExcluded: true
    )

    private static func recordObject(
        id: String,
        planId: String = "w12-census-remainder",
        unitId: String? = nil,
        laneId: String? = nil,
        title: String,
        state: String,
        goal: String? = nil,
        scope: String? = nil,
        age: String? = nil,
        updatedAt: String? = nil,
        gateEvidence: String? = nil,
        stateHistory: [String] = [],
        logTail: String? = nil,
        diff: String? = nil,
        diffId: String? = nil,
        docPaths: [String] = [],
        legalActions: [String] = []
    ) -> ViewPacketJSONValue {
        var object: [String: ViewPacketJSONValue] = [
            "id": .string(id),
            "planId": .string(planId),
            "title": .string(title),
            "state": .string(state),
        ]
        if let unitId { object["unitId"] = .string(unitId) }
        if let laneId { object["laneId"] = .string(laneId) }
        if let goal { object["goal"] = .string(goal) }
        if let scope { object["scope"] = .string(scope) }
        if let age { object["age"] = .string(age) }
        if let updatedAt { object["updatedAt"] = .string(updatedAt) }
        if let gateEvidence { object["gateEvidence"] = .string(gateEvidence) }
        if !stateHistory.isEmpty { object["stateHistory"] = .array(stateHistory.map(ViewPacketJSONValue.string)) }
        if let logTail { object["logTail"] = .string(logTail) }
        if let diff { object["diff"] = .string(diff) }
        if let diffId { object["diffId"] = .string(diffId) }
        if !docPaths.isEmpty { object["docPaths"] = .array(docPaths.map(ViewPacketJSONValue.string)) }
        if !legalActions.isEmpty { object["legalActions"] = .array(legalActions.map(ViewPacketJSONValue.string)) }
        return .object(object)
    }

    private static func actionWrapper(id: String, disposition: String) -> ViewPacketJSONValue {
        .object([
            "action": .object([
                "kind": .string("decision-card.answer"),
                "target": .string(id),
                "id": .string(id),
                "intent": .string("decision-card.answer"),
                "args": .object(["disposition": .string(disposition)]),
            ]),
            "consequence": .string("records the choice in the local fixture"),
        ])
    }
}

