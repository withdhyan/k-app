import CryptoKit
import Foundation
import XCTest
@testable import K

final class ContractFixtureTests: XCTestCase {
    private static let expectedFixtureSHA256 = "88ac8f39c981722dacb82561274c4300f96aa17e2e143e242902743cf4390a22"
    private static let resyncInstruction = "cd ~/ai/cs-k && npm run sync-contract-fixture, copy to Tests/Fixtures/"

    func testVendoredContractFixtureHashMatchesCheckedInExpectation() throws {
        let data = try Self.fixtureData()
        let actualHash = Self.sha256Hex(data)

        XCTAssertEqual(
            actualHash,
            Self.expectedFixtureSHA256,
            "Tests/Fixtures/k-contract-fixture.json is stale or was edited by hand. Resync: \(Self.resyncInstruction)"
        )

        let fixture = try Self.decodeFixture(from: data)
        XCTAssertEqual(fixture.kind, "KContractFixture", "kind drifted")
        XCTAssertEqual(fixture.schemaVersion, 1, "schemaVersion drifted")
        try requireNonEmpty(fixture.generatedAt, "generatedAt")
        XCTAssertEqual(fixture.source, "cs-k", "source drifted")
    }

    func testVendoredContractFixtureDecodesThroughRealModels() throws {
        let fixture = try Self.decodeFixture(from: Self.fixtureData())

        try assertCadenceContracts(fixture.contracts.cadence)
        try assertReviewContracts(fixture.contracts.review)
        try assertBuildContracts(fixture.contracts.build)
        try assertBodyContracts(fixture.contracts.body)
        try assertWhoopContracts(fixture.contracts.whoop)
        try assertAGUIContracts(fixture.contracts.agui)
    }

    private func assertCadenceContracts(_ cadence: CadenceContracts) throws {
        let day = cadence.daySnapshot
        XCTAssertTrue(day.ok, "contracts.cadence.daySnapshot.ok drifted")
        try requireNonEmpty(day.generatedAt, "contracts.cadence.daySnapshot.generatedAt")
        XCTAssertEqual(day.source, "cs-k", "contracts.cadence.daySnapshot.source drifted")
        try requireNonEmpty(day.day.date, "contracts.cadence.daySnapshot.date")
        try requireNotEmpty(day.bandish, "contracts.cadence.daySnapshot.bandish")
        try requireNotEmpty(day.blocks, "contracts.cadence.daySnapshot.blocks")
        XCTAssertEqual(
            day.day.bandish.count,
            day.bandish.count,
            "contracts.cadence.daySnapshot.bandish decoded count drifted"
        )

        for (index, block) in day.blocks.enumerated() {
            try assertRequiredCadenceBlock(block, keyPrefix: "contracts.cadence.daySnapshot.blocks[\(index)]")
            XCTAssertNotNil(block.actionState, "contracts.cadence.daySnapshot.blocks[\(index)].actionState decoded nil")
            XCTAssertNotNil(block.elapsedMinutes, "contracts.cadence.daySnapshot.blocks[\(index)].elapsedMinutes decoded nil")
            let change = try require(block.recalibrationChange, "contracts.cadence.daySnapshot.blocks[\(index)].recalibrationChange")
            XCTAssertNotNil(change.type, "contracts.cadence.daySnapshot.blocks[\(index)].recalibrationChange.type decoded nil")
            XCTAssertNotNil(change.deltaMinutes, "contracts.cadence.daySnapshot.blocks[\(index)].recalibrationChange.deltaMinutes decoded nil")
        }

        let started = try require(
            day.blocks.first { $0.actionState == .started },
            "contracts.cadence.daySnapshot.blocks[].actionState"
        )
        try requireNonEmpty(started.startedAt, "contracts.cadence.daySnapshot.blocks[].startedAt")

        let recalibration = try require(day.day.recalibration, "contracts.cadence.daySnapshot.recalibration")
        try requireNonEmpty(recalibration.reason, "contracts.cadence.daySnapshot.recalibration.reason")
        try requireNonEmpty(recalibration.anchorAt, "contracts.cadence.daySnapshot.recalibration.anchorAt")
        try requireNotEmpty(recalibration.changes, "contracts.cadence.daySnapshot.recalibration.changes")
        let recalibrationChanges = try require(
            day.day.recalibrationChanges,
            "contracts.cadence.daySnapshot.recalibrationChanges"
        )
        try requireNotEmpty(recalibrationChanges, "contracts.cadence.daySnapshot.recalibrationChanges")

        let nowNext = cadence.nowNextSnapshot
        XCTAssertTrue(nowNext.ok, "contracts.cadence.nowNextSnapshot.ok drifted")
        XCTAssertEqual(nowNext.kind, "CadenceNowNext", "contracts.cadence.nowNextSnapshot.kind drifted")
        XCTAssertEqual(nowNext.schemaVersion, 1, "contracts.cadence.nowNextSnapshot.schemaVersion drifted")
        try requireNonEmpty(nowNext.generatedAt, "contracts.cadence.nowNextSnapshot.generatedAt")
        try assertRequiredCadenceBlock(nowNext.nowBlock, keyPrefix: "contracts.cadence.nowNextSnapshot.nowBlock")
        XCTAssertEqual(nowNext.nowBlock.actionState, .started, "contracts.cadence.nowNextSnapshot.nowBlock.actionState drifted")
        try requireNonEmpty(nowNext.nowBlock.startedAt, "contracts.cadence.nowNextSnapshot.nowBlock.startedAt")
        XCTAssertNotNil(nowNext.nowBlock.progress, "contracts.cadence.nowNextSnapshot.nowBlock.progress decoded nil")
        try assertRequiredCadenceBlock(nowNext.nextBlock, keyPrefix: "contracts.cadence.nowNextSnapshot.nextBlock")
        try requireNotEmpty(nowNext.stream, "contracts.cadence.nowNextSnapshot.stream")
    }

    private func assertReviewContracts(_ review: ReviewContracts) throws {
        let card = review.valueProbeCard
        try requireNonEmpty(card.id, "contracts.review.valueProbeCard.id")
        XCTAssertEqual(card.type, "value-probe", "contracts.review.valueProbeCard.type drifted")
        try requireNonEmpty(card.date, "contracts.review.valueProbeCard.date")
        try requireNonEmpty(card.title, "contracts.review.valueProbeCard.title")

        let valueProbes = try require(card.valueProbes, "contracts.review.valueProbeCard.valueProbes")
        try requireNonEmpty(valueProbes.weekStart, "contracts.review.valueProbeCard.valueProbes.weekStart")
        try requireNonEmpty(valueProbes.weekEnd, "contracts.review.valueProbeCard.valueProbes.weekEnd")
        XCTAssertNotNil(valueProbes.maxProbes, "contracts.review.valueProbeCard.valueProbes.maxProbes decoded nil")
        XCTAssertEqual(valueProbes.count, valueProbes.probes.count, "contracts.review.valueProbeCard.valueProbes.count drifted")
        try requireNotEmpty(valueProbes.probes, "contracts.review.valueProbeCard.valueProbes.probes")
        let answerAction = try require(
            valueProbes.answerAction,
            "contracts.review.valueProbeCard.valueProbes.answerAction"
        )
        XCTAssertEqual(answerAction.method, "POST", "contracts.review.valueProbeCard.valueProbes.answerAction.method drifted")
        try requireNonEmpty(answerAction.path, "contracts.review.valueProbeCard.valueProbes.answerAction.path")
        XCTAssertEqual(
            answerAction.body["cardId"]?.stringValue,
            card.id,
            "contracts.review.valueProbeCard.valueProbes.answerAction.body.cardId drifted"
        )

        for (index, probe) in valueProbes.probes.enumerated() {
            let prefix = "contracts.review.valueProbeCard.valueProbes.probes[\(index)]"
            try requireNonEmpty(probe.id, "\(prefix).id")
            XCTAssertGreaterThan(probe.ordinal, 0, "\(prefix).ordinal drifted")
            try requireNonEmpty(probe.axis, "\(prefix).axis")
            try requireNonEmpty(probe.prompt, "\(prefix).prompt")
            try requireNonEmpty(probe.question, "\(prefix).question")
            try requireNonEmpty(probe.shape, "\(prefix).shape")
            XCTAssertTrue(probe.forcedChoice, "\(prefix).forcedChoice drifted")
            try requireNotEmpty(probe.options, "\(prefix).options")
            try requireNotEmpty(probe.sourceEvidence, "\(prefix).sourceEvidence")
        }
    }

    private func assertBuildContracts(_ build: BuildContracts) throws {
        let card = build.card
        try requireNonEmpty(card.id, "contracts.build.card.id")
        try requireNonEmpty(card.kind, "contracts.build.card.kind")
        try requireNonEmpty(card.planId, "contracts.build.card.planId")
        try requireNonEmpty(card.unitId, "contracts.build.card.unitId")
        try requireNonEmpty(card.laneId, "contracts.build.card.laneId")
        try requireNonEmpty(card.title, "contracts.build.card.title")
        try requireNonEmpty(card.body, "contracts.build.card.body")
        try requireNonEmpty(card.what, "contracts.build.card.what")
        try requireNonEmpty(card.contrast, "contracts.build.card.contrast")
        try requireNonEmpty(card.stakes, "contracts.build.card.stakes")
        try requireNotEmpty(card.options, "contracts.build.card.options")
        try requireNonEmpty(card.options.first?.consequence, "contracts.build.card.options[0].consequence")
        try requireNonEmpty(card.recommendation, "contracts.build.card.recommendation")
        try requireNonEmpty(card.status, "contracts.build.card.status")

        let nudge = build.cadenceNudge
        try requireNonEmpty(nudge.id, "contracts.build.cadenceNudge.id")
        try requireNonEmpty(nudge.blockId, "contracts.build.cadenceNudge.blockId")
        try requireNonEmpty(nudge.cardId, "contracts.build.cadenceNudge.cardId")
        try requireNonEmpty(nudge.optionId, "contracts.build.cadenceNudge.optionId")
        XCTAssertTrue(nudge.isBuildCardActable, "contracts.build.cadenceNudge.act decoded non-actable")
        let buildCard = try require(nudge.buildCard, "contracts.build.cadenceNudge.buildCard")
        try requireNonEmpty(buildCard.id, "contracts.build.cadenceNudge.buildCard.id")
        try requireNonEmpty(buildCard.optionId, "contracts.build.cadenceNudge.buildCard.optionId")
        try requireNonEmpty(buildCard.what, "contracts.build.cadenceNudge.buildCard.what")
        try requireNonEmpty(buildCard.contrast, "contracts.build.cadenceNudge.buildCard.contrast")
        try requireNonEmpty(buildCard.stakes, "contracts.build.cadenceNudge.buildCard.stakes")
        try requireNotEmpty(buildCard.options, "contracts.build.cadenceNudge.buildCard.options")
        try requireNonEmpty(buildCard.options.first?.consequence, "contracts.build.cadenceNudge.buildCard.options[0].consequence")
        let act = try require(nudge.act, "contracts.build.cadenceNudge.act")
        XCTAssertEqual(act.method, "POST", "contracts.build.cadenceNudge.act.method drifted")
        try requireNonEmpty(act.path, "contracts.build.cadenceNudge.act.path")
        XCTAssertEqual(act.body["nudgeId"]?.stringValue, nudge.id, "contracts.build.cadenceNudge.act.body.nudgeId drifted")
        XCTAssertEqual(act.body["cardId"]?.stringValue, card.id, "contracts.build.cadenceNudge.act.body.cardId drifted")
        XCTAssertEqual(act.body["optionId"]?.stringValue, card.recommendation, "contracts.build.cadenceNudge.act.body.optionId drifted")

        let snapshotEvent = try AGUIClient.decodeSSEFrame(build.buildSnapshotEnvelope.sseFrame())
        guard case .snapshot(let packets) = snapshotEvent else {
            return XCTFail("contracts.build.buildSnapshotEnvelope failed to decode as AGUIStreamEvent.snapshot")
        }
        try requireNotEmpty(packets, "contracts.build.buildSnapshotEnvelope.data")
        XCTAssertTrue(
            packets.contains { $0.viewType == "build.status" },
            "contracts.build.buildSnapshotEnvelope.data.packets build.status decoded missing"
        )
        let cardPacket = try require(
            packets.first { $0.viewType == "build.card" },
            "contracts.build.buildSnapshotEnvelope.data.cards[]"
        )
        let packetCard = try require(
            BuildCard(packet: cardPacket),
            "contracts.build.buildSnapshotEnvelope.data.cards[].BuildCard(packet:)"
        )
        XCTAssertEqual(packetCard.id, card.id, "contracts.build.buildSnapshotEnvelope.data.cards[].id drifted")

        XCTAssertEqual(build.routes.cardAnswer, AGUIClient.buildCardAnswerPath, "contracts.build.routes.cardAnswer drifted")
        XCTAssertEqual(build.events.snapshot, "build_snapshot", "contracts.build.events.snapshot drifted")
    }

    private func assertBodyContracts(_ body: BodyContracts) throws {
        try requireNonEmpty(body.summary.globalBodyState, "contracts.body.summary.globalBodyState")
        try requireNonEmpty(body.summary.generatedAt, "contracts.body.summary.generatedAt")
        XCTAssertEqual(body.summary.source, "cs-k", "contracts.body.summary.source drifted")

        let baselines = try require(body.cueContext.baselines, "contracts.body.cueContext.baselines")
        XCTAssertNotNil(baselines.hrv, "contracts.body.cueContext.baselines.hrv decoded nil")
        let drift = try require(baselines.hrvDrift, "contracts.body.cueContext.baselines.hrvDrift")
        XCTAssertNotNil(drift.latest, "contracts.body.cueContext.baselines.hrvDrift.latest decoded nil")
        XCTAssertNotNil(drift.baseline, "contracts.body.cueContext.baselines.hrvDrift.baseline decoded nil")
        XCTAssertNotNil(drift.delta, "contracts.body.cueContext.baselines.hrvDrift.delta decoded nil")
        try requireNonEmpty(drift.direction, "contracts.body.cueContext.baselines.hrvDrift.direction")

        let zScore = try require(body.cueContext.zScores?.hrv, "contracts.body.cueContext.zScores.hrv")
        XCTAssertNotNil(zScore.latest, "contracts.body.cueContext.zScores.hrv.latest decoded nil")
        XCTAssertNotNil(zScore.baselineMean, "contracts.body.cueContext.zScores.hrv.baselineMean decoded nil")
        XCTAssertNotNil(zScore.standardDeviation, "contracts.body.cueContext.zScores.hrv.standardDeviation decoded nil")
        XCTAssertNotNil(zScore.zScore, "contracts.body.cueContext.zScores.hrv.zScore decoded nil")
        try requireNonEmpty(body.cueContext.generatedAt, "contracts.body.cueContext.generatedAt")
        XCTAssertEqual(body.cueContext.source, "cs-k", "contracts.body.cueContext.source drifted")
    }

    private func assertWhoopContracts(_ whoop: WhoopContracts) throws {
        XCTAssertEqual(whoop.status["configured"]?.boolValue, true, "contracts.whoop.status.configured drifted")
        XCTAssertEqual(whoop.status["connected"]?.boolValue, true, "contracts.whoop.status.connected drifted")
        try requireNonEmpty(whoop.status["lastSyncAt"]?.stringValue, "contracts.whoop.status.lastSyncAt")
        let counts = try require(whoop.status["counts"]?.objectValue, "contracts.whoop.status.counts")
        for key in ["recovery", "sleep", "cycle", "workout"] {
            XCTAssertNotNil(counts[key], "contracts.whoop.status.counts.\(key) decoded nil")
        }
    }

    private func assertAGUIContracts(_ agui: AGUIContracts) throws {
        XCTAssertEqual(agui.actionInvokeType, AGUIClient.actionInvokeType, "contracts.agui.actionInvokeType drifted")
        XCTAssertEqual(agui.packetPatchEvent, "packet_patch", "contracts.agui.packetPatchEvent drifted")
        XCTAssertEqual(agui.paths.message, "/api/agui/message", "contracts.agui.paths.message drifted")
        XCTAssertEqual(agui.paths.events, AGUIClient.aguiEventsPath, "contracts.agui.paths.events drifted")

        for envelope in [agui.packetEnvelope] + agui.packetEnvelopes {
            let event = try AGUIClient.decodeSSEFrame(envelope.sseFrame())
            guard case .packet(let packet) = event else {
                return XCTFail("contracts.agui.packetEnvelope failed to decode as AGUIStreamEvent.packet")
            }
            try requireNonEmpty(packet.id, "contracts.agui.packetEnvelope.data.id")
            try requireNonEmpty(packet.viewType, "contracts.agui.packetEnvelope.data.viewType")
            XCTAssertEqual(packet.provenance["surface"]?.stringValue, "verbatim-chat", "contracts.agui.packetEnvelope.data.provenance.surface drifted")
        }

        for envelope in [agui.patchEnvelope] + agui.patchEnvelopes {
            let event = try AGUIClient.decodeSSEFrame(envelope.sseFrame())
            guard case .patch(let patch) = event else {
                return XCTFail("contracts.agui.patchEnvelope failed to decode as AGUIStreamEvent.patch")
            }
            try requireNonEmpty(patch.targetId, "contracts.agui.patchEnvelope.data.targetId")
            try requireNotEmpty(patch.ops, "contracts.agui.patchEnvelope.data.ops")
        }

        XCTAssertEqual(agui.doneEnvelope.event, "done", "contracts.agui.doneEnvelope.event drifted")
        XCTAssertEqual(agui.doneEnvelope.data["ok"]?.boolValue, true, "contracts.agui.doneEnvelope.data.ok drifted")
        try requireNonEmpty(agui.doneEnvelope.data["packetId"]?.stringValue, "contracts.agui.doneEnvelope.data.packetId")
    }

    private func assertRequiredCadenceBlock(_ block: CadenceBlock, keyPrefix: String) throws {
        try requireNonEmpty(block.id, "\(keyPrefix).id")
        try requireNonEmpty(block.startAt, "\(keyPrefix).startAt")
        try requireNonEmpty(block.endAt, "\(keyPrefix).endAt")
        try requireNonEmpty(block.type, "\(keyPrefix).type")
        // why is genuinely optional on the wire (template blocks omit it);
        // the view renders it only when present.
        XCTAssertNotEqual(block.ring, .unknown, "\(keyPrefix).ring drifted")
    }

    private static func fixtureData() throws -> Data {
        let bundle = Bundle(for: ContractFixtureTests.self)
        let url = [
            bundle.url(forResource: "k-contract-fixture", withExtension: "json"),
            bundle.url(forResource: "k-contract-fixture", withExtension: "json", subdirectory: "Fixtures"),
            bundle.url(forResource: "k-contract-fixture", withExtension: "json", subdirectory: "Tests/Fixtures"),
        ].compactMap { $0 }.first
        guard let url else {
            throw ContractFixtureTestError.missingFixture("Tests/Fixtures/k-contract-fixture.json")
        }
        return try Data(contentsOf: url)
    }

    private static func decodeFixture(from data: Data) throws -> ContractFixture {
        do {
            return try JSONDecoder().decode(ContractFixture.self, from: data)
        } catch {
            XCTFail("k-contract-fixture.json failed to decode through real Swift models: \(error)")
            throw error
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct ContractFixture: Decodable {
    var kind: String
    var schemaVersion: Int
    var generatedAt: String
    var source: String
    var contracts: ContractSections
}

private struct ContractSections: Decodable {
    var cadence: CadenceContracts
    var review: ReviewContracts
    var build: BuildContracts
    var body: BodyContracts
    var whoop: WhoopContracts
    var agui: AGUIContracts
}

private struct CadenceContracts: Decodable {
    var daySnapshot: CadenceDaySnapshotContract
    var nowNextSnapshot: CadenceNowNextSnapshotContract
}

private struct CadenceDaySnapshotContract: Decodable {
    var ok: Bool
    var generatedAt: String
    var source: String
    var day: CadenceDayEnvelope
    var bandish: [CadenceBlock]
    var blocks: [CadenceBlock]

    enum CodingKeys: String, CodingKey {
        case ok
        case generatedAt
        case source
        case bandish
        case blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        source = try container.decode(String.self, forKey: .source)
        bandish = try container.decode([CadenceBlock].self, forKey: .bandish)
        blocks = try container.decode([CadenceBlock].self, forKey: .blocks)
        day = try CadenceDayEnvelope(from: decoder)
    }
}

private struct CadenceNowNextSnapshotContract: Decodable {
    var ok: Bool
    var kind: String
    var schemaVersion: Int
    var generatedAt: String
    var nowBlock: CadenceBlock
    var nextBlock: CadenceBlock
    var stream: [CadenceBlock]
}

private struct ReviewContracts: Decodable {
    var valueProbeCard: CadenceReviewCard
}

private struct BuildContracts: Decodable {
    var card: BuildCard
    var cadenceNudge: CadenceNudge
    var buildSnapshotEnvelope: EventEnvelope<ViewPacketJSONValue>
    var routes: BuildRoutes
    var events: BuildEvents
}

private struct BuildRoutes: Decodable {
    var cardAnswer: String
}

private struct BuildEvents: Decodable {
    var snapshot: String
}

private struct BodyContracts: Decodable {
    var summary: BodySummary
    var cueContext: BodyCueContext
}

private struct WhoopContracts: Decodable {
    var status: [String: ViewPacketJSONValue]
}

private struct AGUIContracts: Decodable {
    var actionInvokeType: String
    var doneEnvelope: DoneEnvelope
    var packetEnvelope: EventEnvelope<ViewPacket>
    var packetEnvelopes: [EventEnvelope<ViewPacket>]
    var packetPatchEvent: String
    var patchEnvelope: EventEnvelope<ViewPacketPatch>
    var patchEnvelopes: [EventEnvelope<ViewPacketPatch>]
    var paths: AGUIPaths
}

private struct AGUIPaths: Decodable {
    var message: String
    var events: String
}

private struct EventEnvelope<Payload: Codable>: Codable {
    var event: String
    var data: Payload

    func sseFrame() throws -> String {
        let payload = try JSONEncoder().encode(data)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw ContractFixtureTestError.invalidUTF8Payload
        }
        return "event: \(event)\ndata: \(json)"
    }
}

private struct DoneEnvelope: Decodable {
    var event: String
    var data: [String: ViewPacketJSONValue]
}

private enum ContractFixtureTestError: Error {
    case missingFixture(String)
    case invalidUTF8Payload
    case requiredKeyNil(String)
    case requiredKeyEmpty(String)
}

@discardableResult
private func require<T>(
    _ value: T?,
    _ key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value else {
        XCTFail("\(key) decoded nil; fixture drifted", file: file, line: line)
        throw ContractFixtureTestError.requiredKeyNil(key)
    }
    return value
}

@discardableResult
private func requireNonEmpty(
    _ value: String?,
    _ key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let value = try require(value, key, file: file, line: line)
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        XCTFail("\(key) decoded empty; fixture drifted", file: file, line: line)
        throw ContractFixtureTestError.requiredKeyEmpty(key)
    }
    return value
}

private func requireNotEmpty<Collection: Swift.Collection>(
    _ value: Collection,
    _ key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard !value.isEmpty else {
        XCTFail("\(key) decoded empty; fixture drifted", file: file, line: line)
        throw ContractFixtureTestError.requiredKeyEmpty(key)
    }
}
