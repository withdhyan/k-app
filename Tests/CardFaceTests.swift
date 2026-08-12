import XCTest
@testable import K

final class CardFaceTests: XCTestCase {
    func testFaceDecodesRecognitionAnchorAndAsk() throws {
        let face = try JSONDecoder().decode(CardFace.self, from: Data("""
        {
          "anchor": {
            "style": "words",
            "text": "calling it K",
            "date": "2026-01-03"
          },
          "ask": "ship the naming slice?"
        }
        """.utf8))

        XCTAssertEqual(face.anchor.style, "words")
        XCTAssertEqual(face.anchor.text, "calling it K")
        XCTAssertEqual(face.anchor.date, "2026-01-03")
        XCTAssertEqual(face.anchor.displayText, "from jan 3 · calling it K")
        XCTAssertEqual(face.ask, "ship the naming slice?")
    }

    func testInvalidOrAbsentFaceFallsBackToExistingDisclosure() throws {
        let invalidFace: ViewPacketJSONValue = .object([
            "anchor": .object([
                "style": .string("words"),
                "text": .string("   "),
            ]),
            "ask": .string("ship it?"),
        ])

        XCTAssertNil(CardFace.from(invalidFace))

        let buildPacket = ViewPacket(
            id: "invalid-build-face",
            viewType: "build.card",
            text: "legacy build card",
            fields: ["face": invalidFace]
        )
        XCTAssertNil(try XCTUnwrap(BuildCard(packet: buildPacket)).face)

        let mindPacket = ViewPacket(
            id: "invalid-mind-face",
            viewType: "k0.decision",
            text: "legacy mind card",
            fields: [
                "outputId": .string("invalid-mind-face"),
                "outputType": .string("build_decide"),
                "statement": .string("legacy mind card"),
                "face": invalidFace,
            ]
        )
        XCTAssertNil(try XCTUnwrap(MindOutput(packet: mindPacket)).face)

        let absent = CardFaceRenderState(face: nil, isExpanded: false)
        XCTAssertFalse(absent.showsFace)
        XCTAssertTrue(absent.showsDisclosure)
        XCTAssertTrue(absent.showsConsequences)
        XCTAssertFalse(absent.linksDisclosureEntities)
        XCTAssertNil(absent.detailsText)
    }

    func testFaceRenderStateMovesAllDepthBehindOneTap() {
        let face = makeFace()
        let collapsed = CardFaceRenderState(face: face, isExpanded: false)

        XCTAssertTrue(collapsed.showsFace)
        XCTAssertFalse(collapsed.showsDisclosure)
        XCTAssertFalse(collapsed.showsConsequences)
        XCTAssertFalse(collapsed.linksDisclosureEntities)
        XCTAssertEqual(collapsed.detailsText, "details ›")

        let disclosed = CardFaceRenderState(face: face, isExpanded: true)
        XCTAssertFalse(disclosed.showsFace)
        XCTAssertTrue(disclosed.showsDisclosure)
        XCTAssertTrue(disclosed.showsConsequences)
        XCTAssertTrue(disclosed.linksDisclosureEntities)
        XCTAssertEqual(disclosed.detailsText, "details ‹")
    }

    func testBuildCardDecodesNestedFaceWithoutChangingVerbActions() throws {
        let packet = ViewPacket(
            id: "build-face-packet",
            viewType: "build.card",
            text: "legacy title",
            fields: [
                "card": .object([
                    "id": .string("build-face"),
                    "title": .string("legacy title"),
                    "face": faceValue,
                    "brief": briefValue,
                    "options": .array([
                        .object([
                            "id": .string("approve"),
                            "label": .string("approve"),
                            "consequence": .string("the naming lane runs."),
                        ]),
                        .object([
                            "id": .string("hold"),
                            "label": .string("hold"),
                            "consequence": .string("the naming lane stays staged."),
                        ]),
                    ]),
                ]),
            ]
        )

        let card = try XCTUnwrap(BuildCard(packet: packet))
        let presentation = BuildCardPresentation(card: card)

        XCTAssertEqual(card.face, makeFace())
        XCTAssertEqual(card.brief?.whatHappens(for: "approve"), "the naming lane runs.")
        XCTAssertEqual(presentation.options.map(\.option.label), ["approve", "hold"])
        XCTAssertEqual(presentation.options.map(\.isEnabled), [true, true])
        XCTAssertEqual(presentation.options.map(\.consequence), [
            "the naming lane runs.",
            "the naming lane stays staged.",
        ])
    }

    func testBuildCardPacketRoundTripRetainsFaceAndDisclosureDepth() throws {
        let original = BuildCard(
            id: "round-trip",
            title: "legacy title",
            face: makeFace(),
            brief: DecisionBrief(
                whyNow: "the naming evidence is fresh.",
                openQuestion: "ship the naming slice?",
                blocker: "founder judgment",
                stakes: "reversible",
                options: [
                    DecisionBriefOption(id: "approve", whatHappens: "the naming lane runs."),
                ]
            ),
            options: [
                BuildCardOption(id: "approve", label: "approve", consequence: "the naming lane runs."),
            ]
        )

        let decoded = try XCTUnwrap(BuildCard(packet: original.packet))

        XCTAssertEqual(decoded.face, original.face)
        XCTAssertEqual(decoded.brief, original.brief)
        XCTAssertEqual(decoded.options, original.options)
    }

    func testMindOutputDecodesFaceAndKeepsVerdictVerbsAndEntityRefs() throws {
        let packet = ViewPacket(
            id: "mind-face-packet",
            viewType: "k0.decision",
            text: "legacy statement",
            fields: [
                "outputId": .string("mind-face"),
                "outputType": .string("build_decide"),
                "statement": .string("legacy statement"),
                "face": faceValue,
                "brief": briefValue,
                "entityRefs": .array([
                    .object([
                        "name": .string("naming lane"),
                        "key": .string("naming-lane"),
                    ]),
                ]),
            ]
        )

        let output = try XCTUnwrap(MindOutput(packet: packet))

        XCTAssertEqual(output.face, makeFace())
        XCTAssertEqual(MindVerdict.buttonOrder, [.junk, .nod, .actOn])
        XCTAssertEqual(output.brief?.whatHappens(for: MindVerdict.actOn.rawValue), "the naming lane runs.")
        XCTAssertEqual(output.entityRefs, [EntityRef(name: "naming lane", key: "naming-lane")])
        XCTAssertEqual(
            EntitySpanMatcher.matches(in: output.brief?.whyNow ?? "", refs: output.entityRefs).map(\.ref.key),
            ["naming-lane"]
        )
        XCTAssertTrue(MindVerdictAccessibility.cardLabel(for: output).contains("from jan 3 · calling it K"))
        XCTAssertTrue(MindVerdictAccessibility.cardLabel(for: output).contains("ship the naming slice?"))
    }

    private var faceValue: ViewPacketJSONValue {
        makeFace().jsonValue
    }

    private var briefValue: ViewPacketJSONValue {
        .object([
            "whyNow": .string("the naming lane evidence is fresh."),
            "openQuestion": .string("ship the naming slice?"),
            "blocker": .string("founder judgment"),
            "stakes": .string("reversible"),
            "options": .array([
                .object([
                    "id": .string("approve"),
                    "whatHappens": .string("the naming lane runs."),
                ]),
                .object([
                    "id": .string("hold"),
                    "whatHappens": .string("the naming lane stays staged."),
                ]),
                .object([
                    "id": .string(MindVerdict.actOn.rawValue),
                    "whatHappens": .string("the naming lane runs."),
                ]),
            ]),
        ])
    }

    private func makeFace() -> CardFace {
        CardFace(
            anchor: CardFaceAnchor(style: "words", text: "calling it K", date: "2026-01-03"),
            ask: "ship the naming slice?"
        )
    }
}
