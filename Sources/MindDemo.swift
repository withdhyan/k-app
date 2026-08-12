import Foundation

/// Deterministic, local-only mind-v18 seed used by the audit walk. It mirrors
/// the other demo families: the launch argument opts in, the seed never writes
/// to the cache, and a real daemon pass remains the default outside the audit.
enum MindDemo {
    static let launchArgument = "-minddemo"
    static let freshOutputID = "efficiency-jhana"
    static let actedOutputID = "morning-light"
    static let threadOutputID = freshOutputID

    enum AuditState: String, Equatable {
        case empty
        case error
    }

#if DEBUG
    static var auditState: AuditState? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-w11-mind-state"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1)
        else { return nil }
        return AuditState(rawValue: ProcessInfo.processInfo.arguments[index + 1].lowercased())
    }
#else
    static var auditState: AuditState? { nil }
#endif

    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || UserDefaults.standard.bool(forKey: "cskMindDemo")
            || auditState != nil
    }

    static var response: MindArtifactsResponse {
        auditState == .empty ? emptyResponse : decodedResponse
    }

    private static let emptyResponse: MindArtifactsResponse = {
        let data = Data(emptyJSON.utf8)
        guard let response = try? JSONDecoder().decode(MindArtifactsResponse.self, from: data) else {
            preconditionFailure("mind empty audit seed must remain valid JSON")
        }
        return response
    }()

    private static let decodedResponse: MindArtifactsResponse = {
        let data = Data(json.utf8)
        guard let response = try? JSONDecoder().decode(MindArtifactsResponse.self, from: data) else {
            preconditionFailure("mind demo seed must remain valid JSON")
        }
        return response
    }()

    private static let json = #"""
    {
      "outputSections": [
        {
          "key": "mind-demo",
          "items": [
            {
              "id": "mind-demo-efficiency-jhana",
              "viewType": "loop.evidence",
              "text": "the measurement question is resolved · one reversible step remains: pick the next sit protocol.",
              "fields": {
                "outputId": "efficiency-jhana",
                "outputType": "mind_demo",
                "label": "efficiency jhana",
                "observation": "the measurement question is resolved · one reversible step remains: pick the next sit protocol.",
                "artifactSignal": "fresh",
                "evidenceCount": {"shown": 83, "total": 83},
                "useTrail": [
                  {"id": "deep-block", "text": "staged for today's deep block", "at": "today"}
                ],
                "brief": {
                  "options": [
                    {"id": "act-on", "whatHappens": "starts the next sit protocol in today's deep block"},
                    {"id": "nod", "whatHappens": "waits for new evidence before it returns"},
                    {"id": "junk", "whatHappens": "removes it from the active mind pass"}
                  ]
                },
                "commentThread": {
                  "comments": [
                    {"id": "why-now", "role": "founder", "text": "why is this ready now?"},
                    {"id": "why-now-answer", "role": "k", "text": "the third conversation settled how depth gets measured · nothing else was blocking."}
                  ]
                }
              },
              "evidence": ["chat-efficiency-1", "chat-efficiency-2", "note-efficiency-1"],
              "evidencePreviews": [
                {"label": "the efficiency question is really a measurement question", "at": "2026-08-09T12:00:00Z"},
                {"label": "jhana depth versus session length · pick one axis", "at": "2026-08-08T12:00:00Z"}
              ],
              "frontierExcluded": true
            },
            {
              "id": "mind-demo-kedars-name",
              "viewType": "loop.evidence",
              "text": "kedar's name keeps meeting product positioning · three conversations, still unresolved.",
              "fields": {
                "outputId": "kedars-name",
                "outputType": "mind_demo",
                "label": "kedar's name",
                "observation": "keeps meeting product positioning · three conversations, still unresolved. worth building on?",
                "artifactSignal": "fresh",
                "evidenceCount": {"shown": 3, "total": 3},
                "useTrail": [
                  {"id": "nowhere", "text": "nowhere yet · it surfaces here first; act on it to let it shape work", "at": "now"}
                ],
                "brief": {
                  "options": [
                    {"id": "act-on", "whatHappens": "lets the naming signal shape the next positioning pass"},
                    {"id": "nod", "whatHappens": "waits for the pattern to recur before it returns"},
                    {"id": "junk", "whatHappens": "keeps the naming signal out of the active pass"}
                  ]
                }
              },
              "evidence": ["conversation-name-1", "conversation-name-2", "conversation-name-3"],
              "frontierExcluded": true
            },
            {
              "id": "mind-demo-morning-light",
              "viewType": "loop.evidence",
              "text": "the 10-minute sunlight block correlates with your two best deep blocks this week.",
              "fields": {
                "outputId": "morning-light",
                "outputType": "mind_demo",
                "label": "morning light",
                "observation": "the 10-minute sunlight block correlates with your two best deep blocks this week.",
                "artifactSignal": "acted",
                "evidenceCount": {"shown": 6, "total": 7},
                "useTrail": [
                  {"id": "cadence-shift", "text": "moved your two deep blocks after sunlight this week · that change came from this insight", "at": "this week"}
                ],
                "brief": {
                  "options": [
                    {"id": "act-on", "whatHappens": "keeps the sunlight shift in your cadence"},
                    {"id": "nod", "whatHappens": "leaves the changed blocks in place and watches"},
                    {"id": "junk", "whatHappens": "removes the sunlight signal from the active pass"}
                  ]
                }
              },
              "evidence": ["whoop-1", "cadence-1", "cadence-2", "cadence-3", "cadence-4", "cadence-5"],
              "frontierExcluded": true
            },
            {
              "id": "mind-demo-standing-desk",
              "viewType": "loop.evidence",
              "text": "within noise.",
              "fields": {
                "outputId": "standing-desk",
                "outputType": "mind_demo",
                "label": "standing desk research",
                "observation": "within noise.",
                "artifactSignal": "none",
                "evidenceCount": {"shown": 2, "total": 2}
              },
              "evidence": ["bookmark-desk-1", "bookmark-desk-2"],
              "frontierExcluded": true
            }
          ]
        }
      ],
      "priorVerdicts": [
        {
          "passId": "mind-demo",
          "date": "2026-08-10",
          "outputType": "mind_demo",
          "outputId": "morning-light",
          "label": "morning light",
          "verdict": "act-on"
        },
        {
          "passId": "mind-demo",
          "date": "2026-08-10",
          "outputType": "mind_demo",
          "outputId": "standing-desk",
          "label": "standing desk research",
          "verdict": "junk"
        }
      ],
      "evalDate": "2026-08-10",
      "generatedAt": "2026-08-10T07:00:00.000Z",
      "source": "mind-demo"
    }
    """#

    private static let emptyJSON = #"""
    {
      "outputSections": [],
      "priorVerdicts": [],
      "evalDate": "2026-08-10",
      "generatedAt": "2026-08-10T07:00:00.000Z",
      "source": "mind-audit-empty"
    }
    """#
}
