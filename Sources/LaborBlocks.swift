import SwiftUI

struct GenMaterializePlan: Equatable, Sendable {
    let identity: String
    let index: Int
    let isFirstAppearance: Bool
    let delay: TimeInterval
}

struct GenMaterializeIdentityState: Equatable, Sendable {
    private(set) var seenIdentities: Set<String> = []

    mutating func appearance(for identity: String, at index: Int) -> GenMaterializePlan {
        let normalizedIndex = max(0, index)
        let isFirstAppearance = !identity.isEmpty && seenIdentities.insert(identity).inserted
        return GenMaterializePlan(
            identity: identity,
            index: normalizedIndex,
            isFirstAppearance: isFirstAppearance,
            delay: KStyle.genMaterializeStaggerDelay(for: normalizedIndex)
        )
    }
}

struct MaterializeModifier: ViewModifier {
    let identity: String
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var identityState = GenMaterializeIdentityState()

    func body(content: Content) -> some View {
        let isSettled = reduceMotion || hasAppeared

        return content
            .opacity(hasAppeared ? KStyle.genMaterializeVisibleOpacity : KStyle.genMaterializeHiddenOpacity)
            .offset(
                y: isSettled
                    ? KStyle.genMaterializeFinalOffset
                    : KStyle.genMaterializeInitialOffset
            )
            .scaleEffect(
                isSettled
                    ? KStyle.genMaterializeFinalScale
                    : KStyle.genMaterializeInitialScale
            )
            .onAppear {
                materializeIfNeeded()
            }
    }

    private func materializeIfNeeded() {
        let plan = identityState.appearance(for: identity, at: index)
        guard plan.isFirstAppearance else { return }

        guard !identity.isEmpty else {
            hasAppeared = true
            return
        }

        withAnimation(KStyle.genMaterializeAnimation(index: plan.index, reduceMotion: reduceMotion)) {
            hasAppeared = true
        }
    }
}

extension View {
    func genMaterialize(identity: String, index: Int = 0) -> some View {
        modifier(MaterializeModifier(identity: identity, index: index))
            .id(identity)
    }

    func materialize(identity: String, index: Int = 0) -> some View {
        genMaterialize(identity: identity, index: index)
    }
}
