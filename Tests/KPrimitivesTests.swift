import XCTest
import SwiftUI
@testable import K

final class KPrimitivesTests: XCTestCase {
    func testCatalogMetadataMatchesCodeRegistry() throws {
        let catalog = try loadCatalog()

        XCTAssertEqual(catalog.id, KPrimitiveRegistry.id)
        XCTAssertEqual(catalog.version, KPrimitiveRegistry.version)
        XCTAssertEqual(catalog.comment, KPrimitiveRegistry.comment)
        XCTAssertTrue(catalog.comment.lowercased().contains("additive-only"))
    }

    func testCatalogComponentsMatchCompiledPrimitiveRegistry() throws {
        let catalog = try loadCatalog()
        let catalogNames = catalog.components.map(\.name)
        let codeNames = KPrimitiveRegistry.components.map(\.name)

        XCTAssertEqual(catalogNames, codeNames)

        let codeByName = Dictionary(uniqueKeysWithValues: KPrimitiveRegistry.components.map { ($0.name, $0) })
        for component in catalog.components {
            let descriptor = try XCTUnwrap(codeByName[component.name])
            XCTAssertEqual(component.semanticRole, descriptor.semanticRole, component.name)
            XCTAssertEqual(component.variants, descriptor.variants, component.name)
            XCTAssertEqual(component.interactionStates, descriptor.interactionStates, component.name)
            XCTAssertEqual(component.props.map(\.signature), descriptor.props.map(\.signature), component.name)
            XCTAssertEqual(component.usageRules.whenToUse, descriptor.usageWhen, component.name)
            XCTAssertEqual(component.usageRules.neverUse, descriptor.usageNever, component.name)
            XCTAssertEqual(component.calmTech.interruptionClass, descriptor.calmTech.interruptionClass.rawValue, component.name)
            XCTAssertEqual(component.calmTech.maxSimultaneousCues, descriptor.calmTech.maxSimultaneousCues, component.name)
            XCTAssertEqual(component.deprecated ?? false, descriptor.isDeprecated, component.name)
        }
    }

    func testSharedSelectorStripOwnsBioSelectorGeometry() {
        let descriptor = KSelectorStrip<String>.primitiveDescriptor
        XCTAssertEqual(descriptor.name, "KSelectorStrip")
        XCTAssertEqual(descriptor.variants, ["inset-track"])
        XCTAssertEqual(descriptor.calmTech.interruptionClass, .ambient)
        XCTAssertEqual(KStyle.selectorStripTrackInset, KStyle.cadenceWorkChipGroupPadding)
        XCTAssertEqual(KStyle.selectorStripTrackHorizontalPadding, KStyle.selectorStripTrackInset)
        XCTAssertEqual(KStyle.selectorStripItemSpacing, KStyle.tabLabelSpacing)
        XCTAssertEqual(KStyle.selectorStripItemMinimumWidth, KStyle.minimumTapTarget)
        XCTAssertEqual(KStyle.selectorStripItemHorizontalPadding, KStyle.cadenceWorkChipHorizontalPadding)
        XCTAssertEqual(KStyle.selectorStripItemVisualHeight, KStyle.cadenceWorkChipHeight)
        XCTAssertEqual(
            KStyle.selectorStripTrackVisualHeight,
            KStyle.selectorStripItemVisualHeight + KStyle.selectorStripTrackInset * 2
        )
        XCTAssertLessThan(KStyle.selectorStripTrackVisualHeight, KStyle.minimumTapTarget)
        XCTAssertLessThan(KStyle.selectorStripItemVisualHeight, KStyle.minimumTapTarget)
        XCTAssertEqual(KStyle.selectorStripTrackCornerRadius, KStyle.activeBandishCornerRadius)
        XCTAssertLessThan(KStyle.selectorStripActiveCornerRadius, KStyle.selectorStripTrackCornerRadius)
        XCTAssertEqual(KStyle.selectorStripTrackVerticalPadding, .zero)
        XCTAssertLessThan(KStyle.bioRailUnselectedItemZIndex, KStyle.bioRailDetailZIndex)
        XCTAssertLessThan(KStyle.bioRailDetailZIndex, KStyle.bioRailSelectedItemZIndex)

        let item = KSelectorItem(id: "biology", title: "biology", accessibilityIdentifier: "bio-domain-biology")
        XCTAssertEqual(item.id, "biology")
        XCTAssertEqual(item.accessibilityIdentifier, "bio-domain-biology")
    }

    func testEveryCatalogComponentHasCalmTechFields() throws {
        let catalog = try loadCatalog()
        let raw = try loadRawCatalog()
        let rawComponents = try XCTUnwrap(raw["components"] as? [[String: Any]])
        let allowedClasses = Set(["ambient", "peripheral", "focal"])

        XCTAssertEqual(rawComponents.count, catalog.components.count)
        for component in rawComponents {
            let name = try XCTUnwrap(component["name"] as? String)
            let calmTech = try XCTUnwrap(component["calmTech"] as? [String: Any], name)
            XCTAssertTrue(calmTech.keys.contains("interruptionClass"), name)
            XCTAssertTrue(calmTech.keys.contains("maxSimultaneousCues"), name)
            XCTAssertTrue(allowedClasses.contains(try XCTUnwrap(calmTech["interruptionClass"] as? String)), name)
            XCTAssertGreaterThan(try XCTUnwrap(calmTech["maxSimultaneousCues"] as? Int), 0, name)
        }
    }

#if DEBUG
    func testShowcaseModelCoversEveryCatalogComponentAndSpecimen() throws {
        let catalog = try loadCatalog()

        let activeComponents = catalog.components.filter { $0.deprecated != true }
        XCTAssertEqual(ShowcaseCatalogModel.groups.map(\.component.name), activeComponents.map(\.name))
        XCTAssertEqual(ShowcaseCatalogModel.groups.count, activeComponents.count)

        let groupsByName = Dictionary(uniqueKeysWithValues: ShowcaseCatalogModel.groups.map { ($0.component.name, $0) })
        for component in activeComponents {
            let group = try XCTUnwrap(groupsByName[component.name], component.name)
            XCTAssertEqual(group.specimens.count, component.variants.count * component.interactionStates.count, component.name)
            XCTAssertEqual(Set(group.specimens.map(\.variant)), Set(component.variants), component.name)
            XCTAssertEqual(Set(group.specimens.map { $0.state.rawValue }), Set(component.interactionStates), component.name)
            XCTAssertEqual(Set(group.specimens.map(\.label)).count, group.specimens.count, component.name)
        }
    }
#endif

    func testOnlyPaperAndGlassCardTonesExist() {
        XCTAssertEqual(KCardTone.allCases.map(\.rawValue), ["paper", "glass"])
    }

    // Build #26 slice A, fix 1: KMonoCaption was hardwired to white ink, so it went
    // invisible on the near-white expanded plan card. `kInkOnPaper` gives it a dark
    // variant; this pins that it actually flips, and that an error register never
    // recolors the text itself (the hue still lives on the dot — founder law).
    func testKMonoCaptionInksDarkOnPaperAndLightOnGlass() {
        let onPaper = KMonoCaption.resolveForegroundColor(isErrorRegister: false, state: .resting, inkOnPaper: true)
        XCTAssertEqual(onPaper, KStyle.nearBlack.opacity(KStyle.chatThreadPaperSecondaryOpacity))

        let onGlass = KMonoCaption.resolveForegroundColor(isErrorRegister: false, state: .resting, inkOnPaper: false)
        XCTAssertEqual(onGlass, Color.white.opacity(KPrimitiveInteractionState.resting.quietTextOpacity))
        XCTAssertNotEqual(onPaper, onGlass)

        let errorOnPaper = KMonoCaption.resolveForegroundColor(isErrorRegister: true, state: .resting, inkOnPaper: true)
        XCTAssertEqual(errorOnPaper, onPaper, "paper ink wins over the error-register tint — the dot carries the hue, not the text")
    }

    func testPrimaryFilledForegroundUsesNearBlackAcrossPendingAndDisabledStates() {
        for isEnabled in [true, false] {
            for isPending in [true, false] {
                let resolution = KOptionButtonStyleResolution.resolve(
                    variant: .primaryFilled,
                    isPending: isPending,
                    isEnabled: isEnabled,
                    isPressed: false
                )

                XCTAssertEqual(resolution.foregroundBase, .nearBlack)
                XCTAssertNotEqual(resolution.foregroundBase, .light)
                XCTAssertEqual(resolution.fillBase, .light)
                XCTAssertEqual(resolution.strokeBase, .nearBlack)
            }
        }
    }

    func testStartedCurrentBlockUsesActiveFillAndLightText() {
        let started = KBlockRowStyleResolution.resolve(
            surfaceTone: .lightGlass,
            variant: .current,
            actionState: .started
        )
        XCTAssertEqual(started.cardFillBase, .active)
        XCTAssertEqual(started.textBase, .light)

        let available = KBlockRowStyleResolution.resolve(
            surfaceTone: .lightGlass,
            variant: .current,
            actionState: .available
        )
        XCTAssertEqual(available.cardFillBase, .light)
        XCTAssertEqual(available.textBase, .nearBlack)

        let completed = KBlockRowStyleResolution.resolve(
            surfaceTone: .lightGlass,
            variant: .current,
            actionState: .completed
        )
        XCTAssertEqual(completed.cardFillBase, .light)
        XCTAssertEqual(completed.textBase, .nearBlack)
    }

    func testOptionVariantResolutionPreservesThreeLevelTreatment() {
        // Post-consolidation (#23): the verdict register resolves through the shared
        // KOptionButton path (actOn=primaryFilled, nod=secondaryHairline, junk=archiveNaked).
        // Asserts the visual intent per variant, not the old struct's internal fields.
        let archive = KOptionButtonStyleResolution.resolve(
            variant: .archiveNaked, isPending: false, isEnabled: true, isPressed: false
        )
        let secondary = KOptionButtonStyleResolution.resolve(
            variant: .secondaryHairline, isPending: false, isEnabled: true, isPressed: false
        )
        let primary = KOptionButtonStyleResolution.resolve(
            variant: .primaryFilled, isPending: false, isEnabled: true, isPressed: false
        )

        // archive: naked — no fill, no visible stroke, dim ink
        XCTAssertEqual(archive.fillBase, .clear)
        XCTAssertEqual(archive.fillOpacity, .zero)
        XCTAssertEqual(archive.strokeOpacity, .zero)
        XCTAssertEqual(archive.foregroundOpacity, KStyle.tertiaryTextOpacity)

        // secondary: hairline — no fill, a light stroke
        XCTAssertEqual(secondary.fillBase, .clear)
        XCTAssertEqual(secondary.fillOpacity, .zero)
        XCTAssertEqual(secondary.strokeBase, .light)
        XCTAssertEqual(secondary.strokeOpacity, KStyle.hairlineStrongOpacity)

        // primary: filled — light fill, dark ink
        XCTAssertEqual(primary.fillBase, .light)
        XCTAssertGreaterThan(primary.fillOpacity, .zero)
        XCTAssertEqual(primary.foregroundBase, .nearBlack)
    }

    func testKilledComponentsRemainDescriptorOnlyAndHaveNoRuntimeConsumers() throws {
        let deprecatedNames = Set(
            KPrimitiveRegistry.components
                .filter(\.isDeprecated)
                .map(\.name)
        )
        XCTAssertEqual(deprecatedNames, ["KBlockRow", "KNowPanel"])

        let sourceDirectory = repoRoot().appendingPathComponent("Sources")
        let sourceURLs = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL)
            XCTAssertFalse(source.contains("KBlockRow("), sourceURL.lastPathComponent)
            XCTAssertFalse(source.contains("KNowPanel("), sourceURL.lastPathComponent)
        }

        let primitiveSource = try String(contentsOf: sourceDirectory.appendingPathComponent("KPrimitives.swift"))
        XCTAssertFalse(primitiveSource.contains("struct KBlockRow:"))
        XCTAssertFalse(primitiveSource.contains("struct KNowPanel:"))
    }

    func testEntityLinkedTextDoesNotAppendDegreeMarkers() throws {
        let source = try String(contentsOf: repoRoot().appendingPathComponent("Sources/KPrimitives.swift"))
        XCTAssertFalse(source.contains("AttributedString(\"°\")"))
    }

    func testMissingCadenceTimesRenderAsSilenceInsteadOfPlaceholders() {
        let missingTimes = CadenceBlock(
            id: "missing-times",
            title: "quiet",
            startAt: "",
            endAt: ""
        )

        XCTAssertEqual(CadenceDateParser.timeRangeText(for: missingTimes, dayDate: nil), "")
        XCTAssertEqual(CadenceDateParser.timelineGutterText(for: missingTimes, dayDate: nil), "")
        XCTAssertEqual(CadenceDateParser.startTimeText(for: missingTimes, dayDate: nil), "")
    }

    func testPrimitiveSourceStaysTokenOnlyWhereSourceIsAvailable() throws {
        let sourceURL = repoRoot().appendingPathComponent("Sources/KPrimitives.swift")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("primitive source is unavailable in this test context")
        }

        let source = try String(contentsOf: sourceURL)
        XCTAssertTrue(KPrimitiveRegistry.components.allSatisfy(\.usesTokenOnlyStyling))
        XCTAssertFalse(source.contains(".spring("))
        XCTAssertFalse(source.contains("interpolatingSpring"))
        XCTAssertFalse(source.contains("Animation.ease"))

        let forbiddenPatterns = [
            #"\\.opacity\\([0-9]"#,
            #"lineWidth: [0-9]"#,
            #"cornerRadius: [0-9]"#,
            #"frame\\([^\\n]*(width|height|minWidth|minHeight): [0-9]"#,
            #"padding\\([^\\n]*[0-9]"#,
        ]
        for pattern in forbiddenPatterns {
            XCTAssertNil(source.range(of: pattern, options: .regularExpression), pattern)
        }
    }

    private func loadCatalog() throws -> DesignCatalog {
        let data = try Data(contentsOf: catalogURL())
        return try JSONDecoder().decode(DesignCatalog.self, from: data)
    }

    private func loadRawCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func catalogURL() -> URL {
        repoRoot().appendingPathComponent("docs/design/catalog.json")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct DesignCatalog: Decodable {
    let id: String
    let version: String
    let comment: String
    let components: [DesignCatalogComponent]
}

private struct DesignCatalogComponent: Decodable {
    let name: String
    let semanticRole: String
    let deprecated: Bool?
    let props: [DesignCatalogProp]
    let variants: [String]
    let interactionStates: [String]
    let usageRules: DesignCatalogUsageRules
    let calmTech: DesignCatalogCalmTech
}

private struct DesignCatalogProp: Decodable {
    let name: String
    let type: String
    let required: Bool

    var signature: String {
        "\(name):\(type):\(required)"
    }
}

private extension KPrimitivePropDescriptor {
    var signature: String {
        "\(name):\(type):\(required)"
    }
}

private struct DesignCatalogUsageRules: Decodable {
    let whenToUse: [String]
    let neverUse: [String]
}

private struct DesignCatalogCalmTech: Decodable {
    let interruptionClass: String
    let maxSimultaneousCues: Int?
}
