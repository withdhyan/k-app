import XCTest
import UIKit
@testable import K

final class KStyleMotionTests: XCTestCase {
    func testMotionResolutionUsesZenTimingCurveUnlessReducedMotionIsEnabled() {
        XCTAssertEqual(
            KStyle.motionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.zenDuration
            )
        )
        XCTAssertNotNil(KStyle.motion(false))

        XCTAssertEqual(KStyle.motionResolution(true), .none)
        XCTAssertNil(KStyle.motion(true))
    }

    func testCadenceSelectorMotionIsNamedOrderedAndReduceMotionSafe() {
        XCTAssertEqual(KStyle.selectorTextDuration, 0.22)
        XCTAssertEqual(KStyle.selectorBackgroundDuration, 0.45)
        XCTAssertEqual(KStyle.selectorBackgroundDelay, 0.13)
        XCTAssertEqual(
            KStyle.selectorTextMotionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.selectorTextDuration
            )
        )
        XCTAssertEqual(
            KStyle.selectorBackgroundMotionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.selectorBackgroundDuration
            )
        )
        XCTAssertEqual(
            KStyle.selectorTextMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
        XCTAssertEqual(
            KStyle.selectorBackgroundMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testOpacityMotionResolutionStaysFastEaseOutForReducedMotionFeedback() {
        XCTAssertEqual(KStyle.easeFastDuration, 0.15)
        XCTAssertEqual(
            KStyle.opacityMotionResolution(false),
            .easeOut(duration: KStyle.easeFastDuration)
        )
        XCTAssertEqual(
            KStyle.opacityMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testChatV16MotionUsesNamedZenCurvesAndNoSprings() {
        let expected: [(Double, KMotionResolution)] = [
            (KStyle.chatExpansionDuration, KStyle.chatExpansionMotionResolution(false)),
            (KStyle.chatStructureDuration, KStyle.chatStructureMotionResolution(false)),
            (KStyle.chatHistoryAppendDuration, KStyle.chatHistoryAppendMotionResolution(false)),
            (KStyle.chatContentSwapDuration, KStyle.chatContentSwapMotionResolution(false)),
            (KStyle.chatChromeDuration, KStyle.chatChromeMotionResolution(false)),
        ]

        XCTAssertEqual(KStyle.chatExpansionDuration, 0.4)
        XCTAssertEqual(KStyle.chatStructureDuration, 0.7)
        XCTAssertEqual(KStyle.chatHistoryAppendDuration, 0.5)
        XCTAssertEqual(KStyle.chatContentSwapDuration, 0.3)
        XCTAssertEqual(KStyle.chatChromeDuration, 0.4)
        for (duration, resolution) in expected {
            XCTAssertEqual(
                resolution,
                .timingCurve(
                    KStyle.zenCurveX1,
                    KStyle.zenCurveY1,
                    KStyle.zenCurveX2,
                    KStyle.zenCurveY2,
                    duration: duration
                )
            )
        }
        XCTAssertEqual(KStyle.chatExpansionMotionResolution(true), .none)
        XCTAssertEqual(KStyle.chatStructureMotionResolution(true), .none)
        XCTAssertEqual(KStyle.chatHistoryAppendMotionResolution(true), .none)
        XCTAssertEqual(
            KStyle.chatContentSwapMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
        XCTAssertEqual(
            KStyle.chatChromeMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testCameraFadeKeepsLaunchFadeButShortensForReducedMotion() {
        XCTAssertEqual(KStyle.cameraFadeDuration, 0.8)
        XCTAssertEqual(
            KStyle.cameraFadeMotionResolution(false),
            .easeOut(duration: KStyle.cameraFadeDuration)
        )
        XCTAssertEqual(
            KStyle.cameraFadeMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testStateFloodMotionIsNamedSlowExceptionAndReducesToOpacityFeedback() {
        XCTAssertEqual(KStyle.stateFloodDuration, 0.9)
        XCTAssertEqual(
            KStyle.stateFloodMotionResolution(false),
            .easeOut(duration: KStyle.stateFloodDuration)
        )
        XCTAssertEqual(
            KStyle.stateFloodMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testGenMaterializeStaggerUsesBoundedNonNegativeIndexes() {
        XCTAssertEqual(KStyle.genMaterializeStaggerDelay(for: -1), 0, accuracy: 0.000_1)
        XCTAssertEqual(
            KStyle.genMaterializeStaggerDelay(for: 2),
            Double(2) * KStyle.genMaterializeStaggerInterval,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            KStyle.genMaterializeStaggerDelay(for: KStyle.genMaterializeMaxStaggerSteps + 4),
            Double(KStyle.genMaterializeMaxStaggerSteps) * KStyle.genMaterializeStaggerInterval,
            accuracy: 0.000_1
        )
    }

    func testGenMaterializeIdentityStateOnlyMaterializesEachIdentityOnce() {
        var state = GenMaterializeIdentityState()

        let first = state.appearance(for: "labor-a", at: 2)
        XCTAssertTrue(first.isFirstAppearance)
        XCTAssertEqual(first.index, 2)
        XCTAssertEqual(first.delay, KStyle.genMaterializeStaggerDelay(for: 2), accuracy: 0.000_1)

        let rerender = state.appearance(for: "labor-a", at: 0)
        XCTAssertFalse(rerender.isFirstAppearance)
        XCTAssertEqual(rerender.identity, first.identity)

        let next = state.appearance(for: "labor-b", at: -1)
        XCTAssertTrue(next.isFirstAppearance)
        XCTAssertEqual(next.index, 0)
        XCTAssertEqual(next.delay, 0, accuracy: 0.000_1)
    }

    func testGenMaterializeIdentityStateFailsQuietlyWithoutAnIdentity() {
        var state = GenMaterializeIdentityState()

        let first = state.appearance(for: "", at: 0)
        let second = state.appearance(for: "", at: 0)

        XCTAssertFalse(first.isFirstAppearance)
        XCTAssertFalse(second.isFirstAppearance)
        XCTAssertTrue(state.seenIdentities.isEmpty)
    }

    func testRingAndSignalColorTokensMatchFounderHexes() {
        XCTAssertEqual(KStyle.ringCoreToken.hex, "#212936")
        XCTAssertEqual(KStyle.ringMiddleToken.hex, "#2d4867")
        XCTAssertEqual(KStyle.ringOuterToken.hex, "#889a9f")
        XCTAssertEqual(KStyle.signalWarningToken.hex, "#fabb00")
        XCTAssertEqual(KStyle.signalFailureToken.hex, "#e15554")

        XCTAssertEqual(CadenceRing.core.colorHex, "#212936")
        XCTAssertEqual(CadenceRing.middle.colorHex, "#2d4867")
        XCTAssertEqual(CadenceRing.outer.colorHex, "#889a9f")
    }

    func testOptionButtonPressFeedbackTokenValues() {
        XCTAssertEqual(KStyle.optionButtonPressedScale, 0.97)
        XCTAssertEqual(KStyle.optionButtonPressInDuration, 0.10)
    }

    func testEnvironmentHazeTokensAndReduceTransparencyFallback() {
        XCTAssertEqual(KStyle.hazeMaterial, .ultraThin)
        XCTAssertEqual(KStyle.hazeTintOpacity, 0.47)
        XCTAssertGreaterThanOrEqual(KStyle.hazeEffectiveDarkness, 0.75)
        XCTAssertLessThanOrEqual(KStyle.hazeEffectiveDarkness, 0.82)

        XCTAssertEqual(
            KStyle.hazeResolution(reduceTransparency: false),
            .haze(material: .ultraThin, tintOpacity: KStyle.hazeTintOpacity)
        )
        XCTAssertEqual(KStyle.hazeResolution(reduceTransparency: true), .nearBlack)
    }

    func testScaledFontTokensGrowWithContentSizeCategory() {
        let regular = UITraitCollection(preferredContentSizeCategory: .large)
        let extraLarge = UITraitCollection(preferredContentSizeCategory: .extraLarge)

        XCTAssertGreaterThan(
            KStyle.scaledPointSize(for: .content, compatibleWith: extraLarge),
            KStyle.scaledPointSize(for: .content, compatibleWith: regular)
        )
        XCTAssertGreaterThan(
            KStyle.scaledPointSize(for: .monoCaption, compatibleWith: extraLarge),
            KStyle.scaledPointSize(for: .monoCaption, compatibleWith: regular)
        )
        XCTAssertEqual(KFontToken.monoCaption.textStyle, .caption1)
        XCTAssertEqual(KFontToken.mindStatement.textStyle, .title1)
    }

    func testTrackingTokensAreSizeSpecific() {
        XCTAssertEqual(KStyle.nowTitleTracking, -0.5)
        XCTAssertEqual(KStyle.mindStatementTracking, -0.5)
        XCTAssertEqual(KStyle.monoCaptionTracking, 0.2)

        XCTAssertEqual(KStyle.tracking(for: .nowTitle), KStyle.nowTitleTracking)
        XCTAssertEqual(KStyle.tracking(for: .mindStatement), KStyle.mindStatementTracking)
        XCTAssertEqual(KStyle.tracking(for: .monoCaption), KStyle.monoCaptionTracking)
        XCTAssertEqual(KStyle.tracking(for: .monoCaptionDigit), KStyle.monoCaptionTracking)
        XCTAssertEqual(KStyle.tracking(for: .content), KStyle.neutralTracking)
    }

    func testFeedbackPoliciesDeriveOnlyMeaningfulHapticEvents() {
        XCTAssertEqual(KFeedbackPolicy.cadenceBlockEvent(for: .start), .blockStarted)
        XCTAssertEqual(KFeedbackPolicy.cadenceBlockEvent(for: .complete), .blockCompleted)
        XCTAssertNil(KFeedbackPolicy.cadenceBlockEvent(for: .pause))
        XCTAssertNil(KFeedbackPolicy.cadenceBlockEvent(for: .skip))

        XCTAssertEqual(KFeedbackPolicy.mindVerdictEvent(didSubmit: true), .mindVerdictSubmitted)
        XCTAssertNil(KFeedbackPolicy.mindVerdictEvent(didSubmit: false))

        XCTAssertEqual(KFeedbackPolicy.errorSurfaced(previous: nil, current: "answer failed"), .errorSurfaced)
        XCTAssertNil(KFeedbackPolicy.errorSurfaced(previous: "old error", current: "new error"))
        XCTAssertNil(KFeedbackPolicy.errorSurfaced(previous: nil, current: " "))
    }

    func testBuildAnswerFeedbackRequiresOpenToAnsweredTransition() throws {
        let card = BuildCard(
            id: "card-1",
            title: "choose scope",
            options: [
                BuildCardOption(id: "approve", label: "Approve"),
            ]
        )
        let option = try XCTUnwrap(card.options.first)
        let answered = card.answeredCopy(option: option)

        XCTAssertEqual(KFeedbackPolicy.buildAnswerEvent(before: card, after: answered), .buildCardAnswered)
        XCTAssertNil(KFeedbackPolicy.buildAnswerEvent(before: answered, after: answered))
    }

    func testFeedbackTriggersRouteToSensoryBuckets() {
        var triggers = KFeedbackTriggers()

        triggers.record(.blockStarted)
        triggers.record(.buildCardAnswered)
        triggers.record(.mindVerdictSubmitted)
        triggers.record(.errorSurfaced)

        XCTAssertEqual(triggers.impactLightCount, 2)
        XCTAssertEqual(triggers.selectionCount, 1)
        XCTAssertEqual(triggers.errorCount, 1)
    }
}

final class GestureRouterTests: XCTestCase {
    private let router = GestureRouter(
        pageCount: 4,
        subPageCounts: [1, 1, 5, 1]
    )

    func testHorizontalDirectionMovesPagesAndResetsSubPage() throws {
        let next = try XCTUnwrap(
            router.target(
                axis: .horizontal,
                direction: .forward,
                currentPosition: .init(page: 1, subPage: 3)
            )
        )
        XCTAssertEqual(next, .init(page: 2, subPage: .zero))

        let previous = try XCTUnwrap(
            router.target(
                axis: .horizontal,
                direction: .backward,
                currentPosition: .init(page: 2, subPage: 4)
            )
        )
        XCTAssertEqual(previous, .init(page: 1, subPage: .zero))
    }

    func testVerticalDirectionMovesOnlyTheCurrentPageSubPage() throws {
        let next = try XCTUnwrap(
            router.target(
                axis: .vertical,
                direction: .forward,
                currentPosition: .init(page: 2, subPage: 1)
            )
        )
        XCTAssertEqual(next, .init(page: 2, subPage: 2))

        let previous = try XCTUnwrap(
            router.target(
                axis: .vertical,
                direction: .backward,
                current: .init(page: 2, subPage: 2)
            )
        )
        XCTAssertEqual(previous, .init(page: 2, subPage: 1))
    }

    func testBoundedRouterStopsAtPageAndSubPageEdges() {
        XCTAssertNil(
            router.target(
                axis: .horizontal,
                direction: .backward,
                currentPosition: .init(page: .zero)
            )
        )
        XCTAssertNil(
            router.target(
                axis: .horizontal,
                direction: .forward,
                currentPosition: .init(page: 3)
            )
        )
        XCTAssertNil(
            router.target(
                axis: .vertical,
                direction: .backward,
                currentPosition: .init(page: 2, subPage: .zero)
            )
        )
        XCTAssertNil(
            router.target(
                axis: .vertical,
                direction: .forward,
                currentPosition: .init(page: 1)
            )
        )
    }

    func testWrappingRouterWrapsBothAxes() throws {
        let wrapping = GestureRouter(
            pageCount: 4,
            subPageCounts: [1, 1, 2, 1],
            wraps: true
        )

        let page = try XCTUnwrap(
            wrapping.target(
                axis: .horizontal,
                direction: .backward,
                currentPosition: .init(page: .zero)
            )
        )
        XCTAssertEqual(page, .init(page: 3))

        let subPage = try XCTUnwrap(
            wrapping.target(
                axis: .vertical,
                direction: .backward,
                currentPosition: .init(page: 2, subPage: .zero)
            )
        )
        XCTAssertEqual(subPage, .init(page: 2, subPage: 1))
    }

    func testGesturePageMotionUsesZenAndReducedOpacityFeedback() {
        XCTAssertEqual(KStyle.gesturePageTouchCount, 3)
        XCTAssertEqual(KStyle.gesturePageSwipeMinimumDistance, 48)
        XCTAssertEqual(KStyle.gesturePageAxisDominanceRatio, 1.25)
        XCTAssertEqual(KStyle.gesturePageTransitionDuration, 0.25)
        XCTAssertEqual(
            KStyle.gesturePageTransitionMotionResolution(false),
            .timingCurve(
                KStyle.zenCurveX1,
                KStyle.zenCurveY1,
                KStyle.zenCurveX2,
                KStyle.zenCurveY2,
                duration: KStyle.gesturePageTransitionDuration
            )
        )
        XCTAssertEqual(
            KStyle.gesturePageTransitionMotionResolution(true),
            .easeOut(duration: KStyle.easeFastDuration)
        )
    }

    func testThreeFingerPagerIsSuppressedForTextInputContexts() {
        XCTAssertTrue(
            KPagerGestureSuppression.isSuppressed(textInputIsFirstResponder: true)
        )
        XCTAssertFalse(
            KPagerGestureSuppression.isSuppressed(textInputIsFirstResponder: false)
        )
    }
}
